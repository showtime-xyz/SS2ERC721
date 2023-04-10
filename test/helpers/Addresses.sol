// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

import "forge-std/Test.sol";

library Addresses {
    // generates sorted addresses
    function make(uint256 n) public pure returns (bytes memory addresses) {
        return make(address(0xaAaAaAaaAaAaAaaAaAAAAAAAAaaaAaAaAaaAaaAa), n);
    }

    // generates sorted addresses
    function make(address startingAddress, uint256 n) public pure returns (bytes memory addresses) {
        assembly {
            addresses := mload(0x40)
            let data := add(addresses, 32)

            let addr := startingAddress
            for {
                let i := n
            } gt(i, 0) {
                i := sub(i, 1)
            } {
                mstore(add(data, sub(mul(i, 20), 32)), add(addr, sub(i, 1)))
            }

            let last := add(data, mul(n, 20))

            // store the length
            mstore(addresses, mul(n, 20))

            // Allocate memory for the length and the bytes,
            // rounded up to a multiple of 32.
            mstore(0x40, and(add(last, 31), not(31)))
        }
    }

    function incr(address addr) internal pure returns (address) {
        return address(uint160(addr) + 1);
    }

    function isEOA(address addr) internal view returns (bool) {
        return addr > address(18) && addr.code.length == 0;
    }
}
