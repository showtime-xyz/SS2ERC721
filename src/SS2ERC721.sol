// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.0;

import {ERC721, ERC721TokenReceiver} from "solmate/tokens/ERC721.sol";
import {SSTORE2} from "solmate/utils/SSTORE2.sol";

/// @notice SSTORE2-backed version of Solmate's ERC721, optimized for minting in a single batch
abstract contract SS2ERC721 is ERC721 {
    uint256 private constant WORD_SIZE = 32;
    uint256 private constant ADDRESS_SIZE_BYTES = 20;
    uint256 private constant ADDRESS_OFFSET_BITS = 96;
    uint256 private constant FREE_MEM_PTR = 0x40;
    uint256 private constant SSTORE2_DATA_OFFSET = 1;
    uint256 private constant ERROR_STRING_SELECTOR = 0x08c379a0; // Error(string)

    // The `Transfer` event signature is given by:
    // `keccak256(bytes("Transfer(address,address,uint256)"))`.
    bytes32 private constant _TRANSFER_EVENT_SIGNATURE =
        0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef;

    // The mask of the lower 160 bits for addresses.
    uint256 private constant _BITMASK_ADDRESS = (1 << 160) - 1;

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

    /// @dev a flag for _balanceIndicator
    uint256 internal constant SKIP_PRIMARY_BALANCE = 1 << 255;

    /// @dev a flag for _ownerIndicator
    /// @dev use a different value then SKIP_PRIMARY_BALANCE to avoid confusion
    uint256 internal constant BURNED = 1 << 254;

    uint256 internal constant BALANCE_MASK = type(uint256).max >> 1;

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    constructor(string memory _name, string memory _symbol) ERC721(_name, _symbol) {}

    /*//////////////////////////////////////////////////////////////
                         OWNER / BALANCE LOGIC
    //////////////////////////////////////////////////////////////*/

    // borrowed from https://github.com/ensdomains/resolvers/blob/master/contracts/ResolverBase.sol
    function bytesToAddress(bytes memory b) internal pure returns (address payable a) {
        require(b.length == 20);
        assembly {
            a := div(mload(add(b, 32)), exp(256, 12))
        }
    }

    function _ownersPrimaryLength() internal view returns (uint256) {
        if (_ownersPrimaryPointer == address(0)) {
            return 0;
        }

        // checked math will underflow if _ownersPrimaryPointer.code.length == 0
        return (_ownersPrimaryPointer.code.length - 1) / 20;
    }

    function _ownerOfPrimary(uint256 id) internal view returns (address owner) {
        require(id > 0, "ZERO_ID");
        require(id <= _ownersPrimaryLength(), "NOT_MINTED");

        unchecked {
            uint256 start = (id - 1) * 20;
            owner = bytesToAddress(SSTORE2.read(_ownersPrimaryPointer, start, start + 20));
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
        uint256 ownerIndicator = _ownerIndicator[id];
        owner = address(uint160(ownerIndicator));

        if (ownerIndicator & BURNED == BURNED) {
            // normally 0, but return what has been set in the mapping in case inherited contract changes it
            return owner;
        }

        // we use 0 as a sentinel value, meaning that we can't burn by setting the owner to address(0)
        if (owner == address(0)) {
            owner = _ownerOfPrimary(id);
            require(owner != address(0), "NOT_MINTED");
        }
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
        address owner = ownerOf(id);

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
            _balanceIndicator[to]++;
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

    /*//////////////////////////////////////////////////////////////
                        INTERNAL MINT/BURN LOGIC
    //////////////////////////////////////////////////////////////*/

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

    /// @dev specialized version that performs a batch mint with no safeMint checks
    function _mint(address pointer) internal virtual returns (uint256 numMinted) {
        assembly {
            function revert_invalid_addresses() {
                let ptr := mload(FREE_MEM_PTR)
                mstore(ptr, shl(224, ERROR_STRING_SELECTOR))
                mstore(add(ptr, 0x04), WORD_SIZE) // String offset
                mstore(add(ptr, 0x24), 17) // Revert reason length
                mstore(add(ptr, 0x44), "INVALID_ADDRESSES")
                revert(ptr, 0x64) // Revert data length is 4 bytes for selector and 3 slots of 0x20 bytes
            }

            function revert_already_minted() {
                let ptr := mload(FREE_MEM_PTR)
                mstore(ptr, shl(224, ERROR_STRING_SELECTOR))
                mstore(add(ptr, 0x04), WORD_SIZE) // String offset
                mstore(add(ptr, 0x24), 14) // Revert reason length
                mstore(add(ptr, 0x44), "ALREADY_MINTED")
                revert(ptr, 0x64) // Revert data length is 4 bytes for selector and 3 slots of 0x20 bytes
            }

            function revert_not_sorted() {
                let ptr := mload(FREE_MEM_PTR)
                mstore(ptr, shl(224, ERROR_STRING_SELECTOR))
                mstore(add(ptr, 0x04), WORD_SIZE) // String offset
                mstore(add(ptr, 0x24), 20) // Revert reason length
                mstore(add(ptr, 0x44), "ADDRESSES_NOT_SORTED")
                revert(ptr, 0x64) // Revert data length is 4 bytes for selector and 3 slots of 0x20 bytes
            }

            let stored_primary_pointer := sload(_ownersPrimaryPointer.slot)

            // if the primary pointer is already set, we can't mint
            // note: we don't clean the upper bits of the address, we check against the full word
            if gt(stored_primary_pointer, 0) {
                revert_already_minted()
            }

            // zero-out the upper bits of `pointer`
            let clean_pointer := and(pointer, _BITMASK_ADDRESS)

            let pointer_codesize := extcodesize(clean_pointer)

            // if pointer_codesize is 0, then it is not an SSTORE2 pointer
            // if pointer_codesize is 1, then it may be a valid but empty SSTORE2 pointer
            if lt(pointer_codesize, 2) {
                revert_invalid_addresses()
            }

            // subtract 1 because SSTORE2 prepends the data with a `00` byte (a STOP opcode)
            // can not overflow because pointer_codesize is at least 2
            let addresses_length := sub(pointer_codesize, 1)

            // we expect the SSTORE2 pointer to contain a list of packed addresses
            // so the length must be a multiple of 20 bytes
            if gt(mod(addresses_length, ADDRESS_SIZE_BYTES), 0) {
                revert_invalid_addresses()
            }

            // perform the SSTORE2 read, store the data in memory at `addresses_data`
            let addresses_data := mload(FREE_MEM_PTR)
            extcodecopy(
                clean_pointer,          // address
                addresses_data,         // memory offset
                SSTORE2_DATA_OFFSET,    // destination offset
                addresses_length        // size
            )

            numMinted := div(addresses_length, ADDRESS_SIZE_BYTES)
            let prev := 0
            for { let i := 0 } lt(i, numMinted) { } {
                // compute the pointer to the recipient address
                let to_ptr := add(addresses_data, mul(i, ADDRESS_SIZE_BYTES))

                // mload loads a whole 32-byte word, so we get the 20 bytes we want plus 12 bytes we don't:
                //      AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAABBBBBBBBBBBBBBBBBBBBBBBB
                // so we shift right by 12 bytes to get rid of the extra bytes and align the address:
                //      000000000000000000000000AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
                // this guarantees that the high bits of `to` are clean
                let to := shr(ADDRESS_OFFSET_BITS, mload(to_ptr))

                // make sure that the addresses are sorted, the binary search in balanceOf relies on it
                if iszero(gt(to, prev)) {
                    revert_not_sorted()
                }

                prev := to

                // counter increment, can not overflow
                // increment before emitting the event, because the first valid tokenId is 1
                i := add(i, 1)

                // borrowed from ERC721A.sol
                // Emit the `Transfer` event
                log4(
                    0, // Start of data (0, since no data).
                    0, // End of data (0, since no data).
                    _TRANSFER_EVENT_SIGNATURE, // Signature.
                    0, // `from`.
                    to,
                    i // `tokenId`.
                )
            }

            sstore(_ownersPrimaryPointer.slot, clean_pointer)
        }
    }

    function _safeMint(address pointer) internal virtual returns (uint256 numMinted) {
        numMinted = _safeMint(pointer, "");
    }

    /// @dev specialized version that performs a batch mint with a safeMint check at each iteration
    /// @dev in _safeMint, we try to keep assembly usage at a minimum
    function _safeMint(address pointer, bytes memory data) internal virtual returns (uint256 numMinted) {
        require(_ownersPrimaryPointer == address(0), "ALREADY_MINTED");

        bytes memory addresses = SSTORE2.read(pointer);
        uint256 length = addresses.length;
        require(length > 0 && length % 20 == 0, "INVALID_ADDRESSES");

        numMinted = length / 20;
        address prev = address(0);

        for (uint256 i = 0; i < numMinted;) {
            address to;
            assembly {
                to := shr(96, mload(add(addresses, add(32, mul(i, 20)))))
                i := add(i, 1)
            }

            // enforce that the addresses are sorted with no duplicates, and no zero addresses
            require(to > prev, "ADDRESSES_NOT_SORTED");
            prev = to;

            emit Transfer(address(0), to, i);

            require(_checkOnERC721Received(address(0), to, i, data), "UNSAFE_RECIPIENT");
        }

        _ownersPrimaryPointer = pointer;
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
                _balanceIndicator[owner]--;
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
        private
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
