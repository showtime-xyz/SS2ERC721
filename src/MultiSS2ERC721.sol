// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.0;

import {SSTORE2} from "solmate/utils/SSTORE2.sol";

import {SS2ERC721Base, ERC721, ERC721TokenReceiver} from "./common/SS2ERC721Base.sol";

/// @notice SSTORE2-backed version of Solmate's ERC721, with support for multiple batches
abstract contract MultiSS2ERC721 is SS2ERC721Base {
    uint256 private constant WORD_SIZE = 32;
    uint256 private constant ADDRESS_SIZE_BYTES = 20;
    uint256 private constant ADDRESS_OFFSET_BITS = 96;
    uint256 private constant FREE_MEM_PTR = 0x40;
    uint256 private constant SSTORE2_DATA_OFFSET = 1;
    uint256 private constant ERROR_STRING_SELECTOR = 0x08c379a0; // Error(string)
    uint256 private constant SSTORE2_CREATION_CODE_PREFIX = 0x600B5981380380925939F3; // see SSTORE2.sol
    uint256 private constant SSTORE2_CREATION_CODE_OFFSET = 12; // prefix length + 1 for a 0 byte

    uint256 private constant MAX_ADDRESSES_PER_POINTER = 1228;

    // The `Transfer` event signature is given by:
    // `keccak256(bytes("Transfer(address,address,uint256)"))`.
    bytes32 private constant TRANSFER_EVENT_SIGNATURE =
        0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef;

    // The mask of the lower 160 bits for addresses.
    uint256 private constant BITMASK_ADDRESS = (1 << 160) - 1;

    /*//////////////////////////////////////////////////////////////
                      ERC721 BALANCE/OWNER STORAGE
    //////////////////////////////////////////////////////////////*/

    /// array of SSTORE2 pointers (https://github.com/transmissions11/solmate/blob/main/src/utils/SSTORE2.sol)
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
    address[] internal _ownersPrimaryPointers;

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    constructor(string memory _name, string memory _symbol) ERC721(_name, _symbol) {}

    /*//////////////////////////////////////////////////////////////
                         OWNER / BALANCE LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @return numPointers the length of _ownersPrimaryPointers
    /// @return lastPointer the last pointer in _ownersPrimaryPointers or address(0)
    /// @return lastPointerLength the length of the last pointer (in number of addresses, not bytes)
    function _loadCurrentState() internal view returns (uint256 numPointers, address lastPointer, uint256 lastPointerLength) {
        numPointers = _ownersPrimaryPointers.length;
        if (numPointers == 0) {
            return (0, address(0), 0);
        }

        unchecked {
            // numPointers - 1 can not overflow because numPointers > 0
            // lastPointer.code.length - 1 can not underflow because we don't allow empty pointers
            lastPointer = _ownersPrimaryPointers[numPointers - 1];
            lastPointerLength = (lastPointer.code.length - 1) / 20;
        }
    }


    function _ownersPrimaryLength() internal view override returns (uint256) {
        (uint256 numPointers, /* lastPointer */, uint256 lastPointerLength) = _loadCurrentState();
        if (numPointers == 0) {
            return 0;
        }

        // numPointers - 1 can not overflow because numPointers > 0
        // the multiplication can not realistically overflow
        unchecked {
            // every pointer except the last one must be full
            return (numPointers - 1) * MAX_ADDRESSES_PER_POINTER + lastPointerLength;
        }
    }

    /// @dev this is a little like a bucket search in a hashmap
    /// @return owner returns the owner of the given token id
    function _ownerOfPrimary(uint256 id) internal view override returns (address owner) {
        // this is an internal method, so return address(0) and let the caller decide if they want to revert
        if (id == 0) {
            return address(0);
        }

        unchecked {
            // can not underflow because id > 0
            uint256 zeroBasedId = id - 1;

            // we must first find which bucket the id is in
            uint256 pointerIndex = (id - 1) / MAX_ADDRESSES_PER_POINTER;
            if (pointerIndex >= _ownersPrimaryPointers.length) {
                return address(0);
            }

            address pointer = _ownersPrimaryPointers[pointerIndex];
            if (pointer == address(0)) {
                return address(0);
            }

            // then we can calculate the offset into the bucket
            uint256 offset = (zeroBasedId % MAX_ADDRESSES_PER_POINTER) * ADDRESS_SIZE_BYTES;

            // if we read past the end of the bucket, we will get 0 bytes back
            // which is great, because we're supposed to return address(0) in that case anyway
            owner = SSTORE2_readRawAddress(pointer, offset);
        }
    }


    /*//////////////////////////////////////////////////////////////
                        INTERNAL MINT/BURN LOGIC
    //////////////////////////////////////////////////////////////*/


    // checks that if there is a previous batch, it is full
    // returns the last owner of the previous batch so that we can check cross-batch sortedness
    function _mintChecks() internal view returns (uint256 lastTokenId, address prev) {
        (uint256 numPointers, address lastPointer, uint256 lastPointerLength) = _loadCurrentState();
        if (numPointers == 0 || lastPointer == address(0)) {
            return (0, address(0));
        }

        require(lastPointerLength == MAX_ADDRESSES_PER_POINTER, "INCOMPLETE_BATCH");

        unchecked {
            lastTokenId = numPointers * MAX_ADDRESSES_PER_POINTER;
            prev = SSTORE2_readRawAddress(lastPointer, ADDRESS_SIZE_BYTES * (MAX_ADDRESSES_PER_POINTER - 1));
        }
    }

    /// @dev this function creates a new SSTORE2 pointer, and saves it
    /// @dev reading addresses from calldata means we can assemble the creation code with a single memory copy
    function _mint(bytes calldata addresses) internal virtual returns (uint256 numMinted) {
        (uint256 lastTokenId, address prev) = _mintChecks();
        address clean_pointer;

        assembly {
            function revert_invalid_addresses() {
                let ptr := mload(FREE_MEM_PTR)
                mstore(ptr, shl(224, ERROR_STRING_SELECTOR))
                mstore(add(ptr, 0x04), WORD_SIZE) // String offset
                mstore(add(ptr, 0x24), 17) // Revert reason length
                mstore(add(ptr, 0x44), "INVALID_ADDRESSES")
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

            // we expect addresses.length to be > 0
            if eq(addresses.length, 0) { revert_invalid_addresses() }

            // we expect the SSTORE2 pointer to contain a list of packed addresses
            // so the length must be a multiple of 20 bytes
            if gt(mod(addresses.length, ADDRESS_SIZE_BYTES), 0) { revert_invalid_addresses() }

            // the SSTORE2 creation code is SSTORE2_CREATION_CODE_PREFIX + addresses_data
            let creation_code_len := add(SSTORE2_CREATION_CODE_OFFSET, addresses.length)
            let creation_code_ptr := mload(FREE_MEM_PTR)

            // copy the creation code prefix
            // this sets up the memory at creation_code_ptr with the following word:
            //      600B5981380380925939F3000000000000000000000000000000000000000000
            // this also has the advantage of storing fresh 0 bytes
            mstore(
                creation_code_ptr,
                shl(
                    168, // shift the prefix to the left by 21 bytes
                    SSTORE2_CREATION_CODE_PREFIX
                )
            )

            // copy the address data in memory after the creation code prefix
            // after this call, the memory at creation_code_ptr will look like this:
            //      600B5981380380925939F300AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
            // note that the 00 bytes between the prefix and the first address is guaranteed to be clean
            // because of the shl above
            let addresses_data_ptr := add(creation_code_ptr, SSTORE2_CREATION_CODE_OFFSET)
            calldatacopy(
                addresses_data_ptr, // destOffset in memory
                addresses.offset, // offset in calldata
                addresses.length // length
            )

            numMinted := div(addresses.length, ADDRESS_SIZE_BYTES)
            for { let i := 0 } lt(i, numMinted) {} {
                // compute the pointer to the recipient address
                let to_ptr := add(addresses_data_ptr, mul(i, ADDRESS_SIZE_BYTES))

                // mload loads a whole 32-byte word, so we get the 20 bytes we want plus 12 bytes we don't:
                //      AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAABBBBBBBBBBBBBBBBBBBBBBBB
                // so we shift right by 12 bytes to get rid of the extra bytes and align the address:
                //      000000000000000000000000AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
                // this guarantees that the high bits of `to` are clean
                let to := shr(ADDRESS_OFFSET_BITS, mload(to_ptr))

                // make sure that the addresses are sorted, the binary search in balanceOf relies on it
                if iszero(gt(to, prev)) { revert_not_sorted() }

                prev := to

                // counter increment, can not overflow
                // increment before emitting the event, because the first valid tokenId is 1
                i := add(i, 1)

                let tokenId := add(lastTokenId, i)

                // emit the Transfer event
                log4(
                    0, // dataOffset
                    0, // dataSize
                    TRANSFER_EVENT_SIGNATURE, // topic1 = signature
                    0, // topic2 = from
                    to, // topic3 = to
                    tokenId // topic4 = tokenId
                )
            }

            // perform the SSTORE2 write
            clean_pointer :=
                create(
                    0, // value
                    creation_code_ptr, // offset
                    creation_code_len // length
                )
        }

        _ownersPrimaryPointers.push(clean_pointer);
    }

    /// @dev specialized version that performs a batch mint with no safeMint checks
    /// @dev this function reads from an existing SSTORE2 pointer, and saves it
    function _mint(address pointer) internal virtual returns (uint256 numMinted) {
        (uint256 lastTokenId, address prev) = _mintChecks();
        address clean_pointer;

        assembly {
            function revert_invalid_addresses() {
                let ptr := mload(FREE_MEM_PTR)
                mstore(ptr, shl(224, ERROR_STRING_SELECTOR))
                mstore(add(ptr, 0x04), WORD_SIZE) // String offset
                mstore(add(ptr, 0x24), 17) // Revert reason length
                mstore(add(ptr, 0x44), "INVALID_ADDRESSES")
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

            // zero-out the upper bits of `pointer`
            clean_pointer := and(pointer, BITMASK_ADDRESS)

            let pointer_codesize := extcodesize(clean_pointer)

            // if pointer_codesize is 0, then it is not an SSTORE2 pointer
            // if pointer_codesize is 1, then it may be a valid but empty SSTORE2 pointer
            if lt(pointer_codesize, 2) { revert_invalid_addresses() }

            // subtract 1 because SSTORE2 prepends the data with a `00` byte (a STOP opcode)
            // can not overflow because pointer_codesize is at least 2
            let addresses_length := sub(pointer_codesize, 1)

            // we expect the SSTORE2 pointer to contain a list of packed addresses
            // so the length must be a multiple of 20 bytes
            if gt(mod(addresses_length, ADDRESS_SIZE_BYTES), 0) { revert_invalid_addresses() }

            // perform the SSTORE2 read, store the data in memory at `addresses_data`
            let addresses_data := mload(FREE_MEM_PTR)
            extcodecopy(
                clean_pointer, // address
                addresses_data, // memory offset
                SSTORE2_DATA_OFFSET, // destination offset
                addresses_length // size
            )

            numMinted := div(addresses_length, ADDRESS_SIZE_BYTES)
            for { let i := 0 } lt(i, numMinted) {} {
                // compute the pointer to the recipient address
                let to_ptr := add(addresses_data, mul(i, ADDRESS_SIZE_BYTES))

                // mload loads a whole 32-byte word, so we get the 20 bytes we want plus 12 bytes we don't:
                //      AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAABBBBBBBBBBBBBBBBBBBBBBBB
                // so we shift right by 12 bytes to get rid of the extra bytes and align the address:
                //      000000000000000000000000AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
                // this guarantees that the high bits of `to` are clean
                let to := shr(ADDRESS_OFFSET_BITS, mload(to_ptr))

                // make sure that the addresses are sorted, the binary search in balanceOf relies on it
                if iszero(gt(to, prev)) { revert_not_sorted() }

                prev := to

                // counter increment, can not overflow
                // increment before emitting the event, because the first valid tokenId is 1
                i := add(i, 1)

                let tokenId := add(lastTokenId, i)

                // emit the Transfer event
                log4(
                    0, // dataOffset
                    0, // dataSize
                    TRANSFER_EVENT_SIGNATURE, // topic1 = signature
                    0, // topic2 = from
                    to, // topic3 = to
                    tokenId // topic4 = tokenId
                )
            }
        }

        _ownersPrimaryPointers.push(clean_pointer);
    }

    function _safeMint(address pointer) internal virtual returns (uint256 numMinted) {
        numMinted = _safeMint(pointer, "");
    }

    /// @dev specialized version that performs a batch mint with a safeMint check at each iteration
    /// @dev in _safeMint, we try to keep assembly usage at a minimum
    function _safeMint(address pointer, bytes memory data) internal virtual returns (uint256 numMinted) {
        (uint256 lastTokenId, address prev) = _mintChecks();

        bytes memory addresses = SSTORE2.read(pointer);
        uint256 length = addresses.length;
        require(length > 0 && length % 20 == 0, "INVALID_ADDRESSES");

        numMinted = length / 20;
        for (uint256 i = 0; i < numMinted;) {
            address to;
            uint256 tokenId;
            assembly {
                to := shr(96, mload(add(addresses, add(32, mul(i, 20)))))
                i := add(i, 1)
                tokenId := add(lastTokenId, i)
            }

            // enforce that the addresses are sorted with no duplicates, and no zero addresses
            require(to > prev, "ADDRESSES_NOT_SORTED");
            prev = to;

            emit Transfer(address(0), to, tokenId);

            require(_checkOnERC721Received(address(0), to, i, data), "UNSAFE_RECIPIENT");
        }

        _ownersPrimaryPointers.push(pointer);
    }
}
