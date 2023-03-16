// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Test.sol";

import {BinarySearch} from "./BinarySearch.sol";
import {BinarySearchNoSubcalls} from "./BinarySearchNoSubcalls.sol";

contract BinarySearchTest is Test {
    BinarySearch binarySearch;
    BinarySearchNoSubcalls binarySearchNoSubcalls;
    address[] internal owners;

    function setUp() public {
        owners.push(address(0x1));
        owners.push(address(0x2));
        owners.push(address(0x3));

        binarySearch = new BinarySearch();
        binarySearchNoSubcalls = new BinarySearchNoSubcalls();
    }

    function testBalanceOfPrimary() public {
        assertEq(binarySearch.balanceOfPrimary(owners, address(0x1)), 1);
        assertEq(binarySearch.balanceOfPrimary(owners, address(0x2)), 1);
        assertEq(binarySearch.balanceOfPrimary(owners, address(0x3)), 1);
        assertEq(binarySearch.balanceOfPrimary(owners, address(0x4)), 0);
    }

    function testBalanceOfPrimaryNoSubcalls() public {
        assertEq(binarySearchNoSubcalls.balanceOfPrimary(owners, address(0x1)), 1);
        assertEq(binarySearchNoSubcalls.balanceOfPrimary(owners, address(0x2)), 1);
        assertEq(binarySearchNoSubcalls.balanceOfPrimary(owners, address(0x3)), 1);
        assertEq(binarySearchNoSubcalls.balanceOfPrimary(owners, address(0x4)), 0);
    }
}
