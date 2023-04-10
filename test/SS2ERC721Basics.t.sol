// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import {Test, console2} from "forge-std/Test.sol";
import {SSTORE2} from "solmate/utils/SSTORE2.sol";

import {SS2ERC721} from "src/SS2ERC721.sol";

import {Addresses} from "test/helpers/Addresses.sol";
import {BasicSS2ERC721} from "test/helpers/BasicSS2ERC721.sol";


contract BasicERC721Test is Test {
    BasicSS2ERC721 nftContract;
    BasicSS2ERC721 nftContract_preminted;
    BasicSS2ERC721 nftContract_pretransferred;

    address ptr1000;

    address private alice = makeAddr("alice");
    address private bob = makeAddr("bob");
    address private carlotta = makeAddr("carlotta");

    function setUp() public {
        nftContract = new BasicSS2ERC721("basic", unicode"✌️");
        nftContract_preminted = new BasicSS2ERC721("preminted", unicode"✌️");
        nftContract_pretransferred = new BasicSS2ERC721("pretransferred", unicode"✌️");

        // alice starts with a token
        nftContract_preminted.mint(SSTORE2.write(abi.encodePacked(alice)));

        // set up the pre-transfer
        nftContract_pretransferred.mint(SSTORE2.write(abi.encodePacked(bob, alice)));

        vm.prank(alice);
        nftContract_pretransferred.transferFrom(alice, bob, 2);

        vm.prank(bob);
        nftContract_pretransferred.transferFrom(bob, carlotta, 1);

        // set up the 1000 token test
        ptr1000 = SSTORE2.write(Addresses.make(1000));
    }

    function mint(uint256 n) private {
        bytes memory addresses = Addresses.make(n);
        nftContract.mint(addresses);
    }

    function test_mint_newcomer_0001() public {
        mint(1);
    }

    function test_mint_newcomer_0010() public {
        mint(10);
    }

    function test_mint_newcomer_0100() public {
        mint(100);
    }

    function test_mint_newcomer_1000() public {
        mint(1000);
    }

    function test_mint_existingPointer_1000() public {
        nftContract.mint(ptr1000);
    }

    function test_transferFrom_initial() public {
        vm.prank(alice);
        nftContract_preminted.transferFrom(alice, bob, 1);
    }

    function test_transferFrom_subsequent() public {
        vm.prank(carlotta);
        nftContract_pretransferred.transferFrom(carlotta, bob, 1);
    }

    function test_balanceOf() public view {
        nftContract_preminted.balanceOf(alice);
    }

    function test_ownerOf() public view {
        nftContract_preminted.ownerOf(1);
    }
}
