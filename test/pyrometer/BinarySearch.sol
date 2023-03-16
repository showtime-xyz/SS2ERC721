// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

contract BinarySearch {
    function _ownersPrimaryLength(address[] memory owners) internal pure returns (uint256) {
        return owners.length;
    }

    function _ownerOfPrimary(address[] memory owners, uint256 id) internal pure returns (address owner) {
        require(id > 0, "ZERO_ID");
        require(id <= _ownersPrimaryLength(owners), "NOT_MINTED");

        return owners[id - 1];
    }

    // abstract the SSTORE2 pointer with a simple address array
    function balanceOfPrimary(address[] memory owners, address owner) public pure returns (uint256) {
        uint256 low = 1;
        uint256 high = _ownersPrimaryLength(owners);
        uint256 mid = (low + high) / 2;

        while (low <= high) {
            address midOwner = _ownerOfPrimary(owners, mid);
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


