// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.0;

import {ERC721, ERC721TokenReceiver} from "solmate/tokens/ERC721.sol";

abstract contract SS2ERC721Base is ERC721 {
    /*//////////////////////////////////////////////////////////////
                               CONSTANTS
    //////////////////////////////////////////////////////////////*/

    /// @dev a flag for _balanceIndicator
    uint256 internal constant SKIP_PRIMARY_BALANCE = 1 << 255;

    /// @dev a flag for _ownerIndicator
    /// @dev use a different value then SKIP_PRIMARY_BALANCE to avoid confusion
    uint256 internal constant BURNED = 1 << 254;

    uint256 internal constant BALANCE_MASK = type(uint256).max >> 1;

    /*//////////////////////////////////////////////////////////////
                            MUTABLE STORAGE
    //////////////////////////////////////////////////////////////*/

    /// @dev mapping from token id to indicator (owner address plus burned flag packed in the higher bits)
    mapping(uint256 => uint256) internal _ownerIndicator;

    /// @dev 255-bit balance + 1-bit not primary owner flag
    ///
    /// - ownerIndicator[id] == 0 == (not_burned, address(0))
    ///     means that there is no secondary owner for id and we should fall back to the primary owner check
    ///
    /// - ownerIndicator[id] == (burned, address(0))
    ///     means that address(0) *is* the secondary owner, no need to fall back on the primary owner check
    ///
    /// - ownerIndicator[id] == (not_burned, owner)
    ///     means that `owner` is the secondary owner, no need to fall back on the primary owner check
    mapping(address => uint256) internal _balanceIndicator;

    /*//////////////////////////////////////////////////////////////
                             VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// implementations must override this function to return the number of tokens minted
    function _ownersPrimaryLength() internal view virtual returns (uint256);

    /// implementations must override this function to return the primary owner of a token
    /// or address(0) if the token does not exist
    function _ownerOfPrimary(uint256 id) internal view virtual returns (address owner);

    /// @dev performs no bounds check, just a raw extcodecopy on the pointer
    /// @return addr the address at the given pointer (may include 0 bytes if reading past the end of the pointer)
    function SSTORE2_readRawAddress(address pointer, uint256 start) internal view returns (address addr) {
        // we're going to read 20 bytes from the pointer in the first scratch space slot
        uint256 dest_offset = 12;

        assembly {
            start := add(start, 1) // add the SSTORE2 DATA_OFFSET

            // clear it the first scratch space slot
            mstore(0, 0)

            extcodecopy(pointer, dest_offset, start, 20)

            addr := mload(0)
        }
    }

    function _getOwnerSecondary(uint256 id) internal view returns (address owner) {
        owner = address(uint160(_ownerIndicator[id]));
    }

    function _setOwnerSecondary(uint256 id, address owner) internal {
        if (owner == address(0)) {
            _setBurned(id);
        } else {
            // we don't expect this to be called after burning, so no need to carry over the BURNED flag
            _ownerIndicator[id] = uint160(owner);
        }
    }

    function _hasBeenBurned(uint256 id) internal view returns (bool) {
        return _ownerIndicator[id] & BURNED != 0;
    }

    /// @dev sets the burned flag *and* sets the owner to address(0)
    function _setBurned(uint256 id) internal {
        _ownerIndicator[id] = BURNED;
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

    /// @dev for internal use -- does not revert on unminted token ids
    function __ownerOf(uint256 id) internal view returns (address owner) {
        uint256 ownerIndicator = _ownerIndicator[id];
        owner = address(uint160(ownerIndicator));

        if (ownerIndicator & BURNED == BURNED) {
            // normally 0, but return what has been set in the mapping in case inherited contract changes it
            return owner;
        }

        // we use 0 as a sentinel value, meaning that we can't burn by setting the owner to address(0)
        if (owner == address(0)) {
            owner = _ownerOfPrimary(id);
        }
    }

    function ownerOf(uint256 id) public view virtual override returns (address owner) {
        owner = __ownerOf(id);
        require(owner != address(0), "NOT_MINTED");
    }

    function balanceOf(address owner) public view virtual override returns (uint256 balance) {
        require(owner != address(0), "ZERO_ADDRESS");

        uint256 balanceIndicator = _balanceIndicator[owner];
        balance = balanceIndicator & BALANCE_MASK;

        if (balanceIndicator & SKIP_PRIMARY_BALANCE == 0) {
            balance += _balanceOfPrimary(owner);
        }
    }

    /*//////////////////////////////////////////////////////////////
                              ERC721 LOGIC
    //////////////////////////////////////////////////////////////*/

    function approve(address spender, uint256 id) public virtual override {
        // need to use the ownerOf getter here instead of directly accessing the storage
        address owner = __ownerOf(id);

        require(msg.sender == owner || isApprovedForAll[owner][msg.sender], "NOT_AUTHORIZED");

        getApproved[id] = spender;

        emit Approval(owner, spender, id);
    }

    function transferFrom(address from, address to, uint256 id) public virtual override {
        require(
            msg.sender == from || isApprovedForAll[from][msg.sender] || msg.sender == getApproved[id], "NOT_AUTHORIZED"
        );
        require(to != address(0), "INVALID_RECIPIENT");

        address owner = _moveTokenTo(id, to);

        require(from == owner, "WRONG_FROM");

        unchecked {
            ++_balanceIndicator[to];
        }
    }

    /// @dev needs to be overridden here to invoke our custom version of transferFrom
    function safeTransferFrom(address from, address to, uint256 id) public virtual override {
        transferFrom(from, to, id);

        require(
            to.code.length == 0
                || ERC721TokenReceiver(to).onERC721Received(msg.sender, from, id, "")
                    == ERC721TokenReceiver.onERC721Received.selector,
            "UNSAFE_RECIPIENT"
        );
    }

    /// @dev needs to be overridden here to invoke our custom version of transferFrom
    function safeTransferFrom(address from, address to, uint256 id, bytes calldata data) public virtual override {
        transferFrom(from, to, id);

        require(
            to.code.length == 0
                || ERC721TokenReceiver(to).onERC721Received(msg.sender, from, id, data)
                    == ERC721TokenReceiver.onERC721Received.selector,
            "UNSAFE_RECIPIENT"
        );
    }

    function _burn(uint256 id) internal virtual override {
        _moveTokenTo(id, address(0));
    }

    function _moveTokenTo(uint256 id, address to) private returns (address owner) {
        owner = _getOwnerSecondary(id);

        if (owner == address(0)) {
            owner = _ownerOfPrimary(id);
            require(owner != address(0), "NOT_MINTED");

            _balanceIndicator[owner] |= SKIP_PRIMARY_BALANCE;
        } else {
            unchecked {
                --_balanceIndicator[owner];
            }
        }

        _setOwnerSecondary(id, to);

        delete getApproved[id];

        emit Transfer(owner, to, id);
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
    function _checkOnERC721Received(address from, address to, uint256 tokenId, bytes memory data)
        internal
        returns (bool)
    {
        if (to.code.length == 0) {
            return true;
        }

        try ERC721TokenReceiver(to).onERC721Received(msg.sender, from, tokenId, data) returns (bytes4 retval) {
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
