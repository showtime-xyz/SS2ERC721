// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.0;

import {ERC721} from "solmate/tokens/ERC721.sol";
import {SSTORE2} from "solmate/utils/SSTORE2.sol";

import {ERC721TokenReceiver} from "./ERC721TokenReceiver.sol";

/// @notice SSTORE2-backed version of Solmate's ERC721, optimized for minting in a single batch
abstract contract SS2ERC721 is ERC721 {
    /*//////////////////////////////////////////////////////////////
                      ERC721 BALANCE/OWNER STORAGE
    //////////////////////////////////////////////////////////////*/

    /// stored as SSTORE2 pointer (https://github.com/transmissions11/solmate/blob/main/src/utils/SSTORE2.sol)
    ///
    /// array of abi.encodePacked(address1, address2, address3...) where address1 is the owner of token 1,
    /// address2 is the owner of token 2, etc.
    /// This means that:
    /// - addresses are stored contiguously in storage with no gaps (rather than 1 address per slot)
    /// - this is optimized for the mint path and using as few storage slots as possible for the primary owners
    /// - the tradeoff is that it causes extra gas and storage costs in the transfer/burn paths
    /// - this also causes extra costs in the ownerOf/balanceOf/tokenURI functions, but these are view functions
    ///
    /// Assumptions:
    /// - the list of addresses contains no duplicate
    /// - the list of addresses is sorted
    /// - the first valid token id is 1
    address internal _ownersPrimaryPointer;

    mapping(uint256 => address) internal _ownerOfSecondary;

    /// @dev signed integer to allow for negative adjustments relative to _ownersPrimary
    mapping(address => int256) internal _balanceOfAdjustment;

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    constructor(string memory _name, string memory _symbol) ERC721(_name, _symbol) {}

    /*//////////////////////////////////////////////////////////////
                         OWNER / BALANCE LOGIC
    //////////////////////////////////////////////////////////////*/

    // borrowed from https://github.com/ensdomains/resolvers/blob/master/contracts/ResolverBase.sol
    function bytesToAddress(bytes memory b)
        internal
        pure
        returns (address payable a)
    {
        require(b.length == 20);
        assembly {
            a := div(mload(add(b, 32)), exp(256, 12))
        }
    }

    function _ownersPrimaryLength() internal view returns (uint256) {
        if (_ownersPrimaryPointer == address(0)) {
            return 0;
        }

        return (_ownersPrimaryPointer.code.length - 1) / 20;
    }

    function _ownerOfPrimary(uint256 id) internal view returns (address owner) {
        require(id > 0, "ZERO_ID");
        require(id <= _ownersPrimaryLength(), "NOT_MINTED");

        unchecked {
            uint256 start = (id - 1) * 20;
            owner = bytesToAddress(
                SSTORE2.read(_ownersPrimaryPointer, start, start + 20)
            );
        }
    }

    // binary search of the address based on _ownerOfPrimary
    // performs O(log n) sloads
    // relies on the assumption that the list of addresses is sorted and contains no duplicates
    // returns 1 if the address is found in _ownersPrimary, 0 if not
    function _balanceOfPrimary(address owner) internal view returns (uint256) {
        uint256 low = 1;
        uint256 high = _ownersPrimaryLength();
        uint256 mid = (low + high) / 2;

        // TODO: unchecked
        while (low <= high) {
            address midOwner = _ownerOfPrimary(mid);
            if (midOwner == owner) {
                return 1;
            } else if (midOwner < owner) {
                low = mid + 1;
            } else {
                high = mid - 1;
            }
            mid = (low + high) / 2;
        }

        return 0;
    }

    function ownerOf(uint256 id) public view virtual override returns (address owner) {
        owner = _ownerOfSecondary[id];

        // we use 0 as a sentinel value, meaning that we can't burn by setting the owner to address(0)
        if (owner == address(0)) {
            owner = _ownerOfPrimary(id);
        }

        require(owner != address(0), "NOT_MINTED");
    }

    function balanceOf(address owner) public view virtual override returns (uint256) {
        require(owner != address(0), "ZERO_ADDRESS");

        int256 balance = int256(_balanceOfPrimary(owner)) +
            _balanceOfAdjustment[owner];

        require(balance >= 0, "OVERFLOW");

        return uint256(balance);
    }

    /*//////////////////////////////////////////////////////////////
                              ERC721 LOGIC
    //////////////////////////////////////////////////////////////*/

    function approve(address spender, uint256 id) public virtual override {
        // need to use the ownerOf getter here instead of directly accessing the storage
        address owner = ownerOf(id);

        require(
            msg.sender == owner || isApprovedForAll[owner][msg.sender],
            "NOT_AUTHORIZED"
        );

        getApproved[id] = spender;

        emit Approval(owner, spender, id);
    }

    function transferFrom(
        address from,
        address to,
        uint256 id
    ) public virtual override {
        // need to use the ownerOf getter here instead of directly accessing the storage
        require(from == ownerOf(id), "WRONG_FROM");

        require(to != address(0), "INVALID_RECIPIENT");

        require(
            msg.sender == from || isApprovedForAll[from][msg.sender] || msg.sender == getApproved[id],
            "NOT_AUTHORIZED"
        );

        // Underflow of the sender's balance is impossible because we check for
        // ownership above and the recipient's balance can't realistically overflow.
        unchecked {
            _balanceOfAdjustment[from]--;

            _balanceOfAdjustment[to]++;
        }

        _ownerOfSecondary[id] = to;

        delete getApproved[id];

        emit Transfer(from, to, id);
    }

    /// @dev needs to be overridden here to invoke our custom version of transferFrom
    function safeTransferFrom(
        address from,
        address to,
        uint256 id
    ) public virtual override {
        transferFrom(from, to, id);

        require(
            to.code.length == 0 ||
                ERC721TokenReceiver(to).onERC721Received(msg.sender, from, id, "") ==
                ERC721TokenReceiver.onERC721Received.selector,
            "UNSAFE_RECIPIENT"
        );
    }

    /// @dev needs to be overridden here to invoke our custom version of transferFrom
    function safeTransferFrom(
        address from,
        address to,
        uint256 id,
        bytes calldata data
    ) public virtual override {
        transferFrom(from, to, id);

        require(
            to.code.length == 0 ||
                ERC721TokenReceiver(to).onERC721Received(msg.sender, from, id, data) ==
                ERC721TokenReceiver.onERC721Received.selector,
            "UNSAFE_RECIPIENT"
        );
    }

    /*//////////////////////////////////////////////////////////////
                        INTERNAL MINT/BURN LOGIC
    //////////////////////////////////////////////////////////////*/

    function _mint(address pointer)
        internal
        virtual
        returns (uint256 numMinted)
    {
        numMinted = _mint(pointer, false, "");
    }

    function _safeMint(address pointer)
        internal
        virtual
        returns (uint256 numMinted)
    {
        numMinted = _mint(pointer, true, "");
    }

    function _safeMint(address pointer, bytes memory data)
        internal
        virtual
        returns (uint256 numMinted)
    {
        numMinted = _mint(pointer, true, data);
    }

    // can only be called once
    function _mint(
        address pointer,
        bool safeMint,
        bytes memory safeMintData
    ) internal virtual returns (uint256 numMinted) {
        require(_ownersPrimaryPointer == address(0), "ALREADY_MINTED");

        bytes memory addresses = SSTORE2.read(pointer);
        require(addresses.length % 20 == 0, "INVALID_ADDRESSES");

        numMinted = addresses.length / 20;

        address prev = address(0);
        for (uint256 i = 0; i < numMinted; ) {
            address to;

            assembly {
                to := shr(96, mload(add(addresses, add(32, mul(i, 20)))))
            }

            // enforce that the addresses are sorted with no duplicates
            require(to > prev, "ADDRESSES_NOT_SORTED");
            prev = to;

            unchecked {
                ++i;
            }

            // start with token id 1
            emit Transfer(address(0), to, i);

            if (safeMint) {
                require(
                    _checkOnERC721Received(address(0), to, i, safeMintData),
                    "UNSAFE_RECIPIENT"
                );
            }
        }

        // we do not explicitly set balanceOf for the primary owners
        _ownersPrimaryPointer = pointer;
    }

    function _burn(uint256 id) internal virtual override {
        address owner = ownerOf(id);

        require(owner != address(0), "NOT_MINTED");

        // signed math
        unchecked {
            _balanceOfAdjustment[owner]--;
        }

        _ownerOfSecondary[id] = address(0xdead);

        delete getApproved[id];

        emit Transfer(owner, address(0xdead), id);
    }

    /*//////////////////////////////////////////////////////////////
                        INTERNAL SAFE MINT LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Internal function to invoke {IERC721Receiver-onERC721Received} on a target address.
     * The call is not executed if the target address is not a contract.
     *
     * @param from address representing the previous owner of the given token ID
     * @param to target address that will receive the tokens
     * @param tokenId uint256 ID of the token to be transferred
     * @param data bytes optional data to send along with the call
     * @return bool whether the call correctly returned the expected magic value
     */
    function _checkOnERC721Received(
        address from,
        address to,
        uint256 tokenId,
        bytes memory data
    ) private returns (bool) {
        if (to.code.length == 0) {
            return true;
        }

        try
            ERC721TokenReceiver(to).onERC721Received(
                msg.sender,
                from,
                tokenId,
                data
            )
        returns (bytes4 retval) {
            return retval == ERC721TokenReceiver.onERC721Received.selector;
        } catch (bytes memory reason) {
            if (reason.length == 0) {
                revert("UNSAFE_RECIPIENT");
            } else {
                /// @solidity memory-safe-assembly
                assembly {
                    revert(add(32, reason), mload(reason))
                }
            }
        }
    }
}
