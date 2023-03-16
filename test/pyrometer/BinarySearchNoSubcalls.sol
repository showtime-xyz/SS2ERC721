// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

contract BinarySearchNoSubcalls {
    function balanceOfPrimary(address[] memory owners, address owner) public pure returns (uint256) {
        if (owners.length == 0) return 0;

        uint256 low = 1;
        uint256 high = owners.length;
        uint256 mid = (low + high) / 2;

        while (low <= high) {
            require(mid > 0, "ZERO_ID");
            address midOwner = owners[mid - 1];

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
}


