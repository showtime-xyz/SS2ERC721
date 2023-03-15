// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import {Test} from "forge-std/Test.sol";
import {SSTORE2} from "solmate/utils/SSTORE2.sol";
import {stdError} from "forge-std/StdError.sol";

import {SS2ERC721} from "src/SS2ERC721.sol";

contract BasicSS2ERC721 is SS2ERC721 {
    constructor(string memory name_, string memory symbol_) SS2ERC721(name_, symbol_) {}

    function mint(address ptr) public returns (uint256 numMinted) {
        numMinted = _mint(ptr);
    }

    function burn(uint256 tokenId) public {
        _burn(tokenId);
    }

    function tokenURI(uint256) public view virtual override returns (string memory) {
        return "";
    }
}

contract SS2ERC721Specifics is Test {
    address internal constant BURN_ADDRESS = address(0xdEaD);

    BasicSS2ERC721 token;

    function setUp() public {
        token = new BasicSS2ERC721("basic", unicode"✌️");
    }

    function test_ownerOf_idZero_reverts() public {
        vm.expectRevert("ZERO_ID");
        token.ownerOf(0);
    }

    function test_mint_nullPointer_reverts() public {
        // there is actually no special treatment for null pointers,
        // it fails with the same error as a bad pointer (i.e. no code at that address)
        test_mint_badPointer_reverts(address(0));
    }

    function test_mint_badPointer_reverts(address ptr) public {
        vm.assume(ptr.code.length == 0);

        vm.expectRevert(stdError.arithmeticError);
        token.mint(address(0));
    }

    function test_mint_emptyPointer_reverts() public {
        address ptr = SSTORE2.write("");

        vm.expectRevert("INVALID_ADDRESSES");
        token.mint(ptr);
    }

    function test_mint_randomData_reverts() public {
        address ptr = SSTORE2.write("beep boop");

        vm.expectRevert("INVALID_ADDRESSES");
        token.mint(ptr);
    }

    function test_mint_invalidData_reverts() public {
        address ptr = SSTORE2.write(abi.encodePacked(address(this), "beep boop"));

        vm.expectRevert("INVALID_ADDRESSES");
        token.mint(ptr);
    }

    function test_mint_unsortedAddresses_reverts() public {
        address ptr = SSTORE2.write(abi.encodePacked(address(2), address(1)));

        vm.expectRevert("ADDRESSES_NOT_SORTED");
        token.mint(ptr);
    }

    function test_mint_twice_reverts() public {
        address ptr = SSTORE2.write(abi.encodePacked(address(this)));
        token.mint(ptr);

        vm.expectRevert("ALREADY_MINTED");
        token.mint(ptr);
    }

    function test_mint_returnsNumMinted() public {
        address ptr = SSTORE2.write(abi.encodePacked(address(1), address(2), address(3)));
        uint256 numMinted = token.mint(ptr);
        assertEq(numMinted, 3);
    }

    function test_mint_double_reverts() public {
        address ptr = SSTORE2.write(abi.encodePacked(address(0xBEEF), address(0xBEEF)));

        vm.expectRevert("ADDRESSES_NOT_SORTED");
        token.mint(ptr);
    }

    function test_mint_double_reverts(address to) public {
        vm.assume(to > address(0));
        address ptr = SSTORE2.write(abi.encodePacked(to, to));

        vm.expectRevert("ADDRESSES_NOT_SORTED");
        token.mint(ptr);
    }

    function test_transferFrom_toBurnAddressDoesBurn() public {
        address ptr = SSTORE2.write(abi.encodePacked(address(this)));
        token.mint(ptr);

        token.transferFrom(address(this), BURN_ADDRESS, 1);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.ownerOf(1), BURN_ADDRESS);
        assertEq(token.balanceOf(BURN_ADDRESS), 0);
    }

    function test_e2e() public {
        address alice = makeAddr("alice");
        address bob = address(uint160(alice) + 1);
        address carol = address(uint160(alice) + 2);
        address dennis = makeAddr("dennis");

        vm.label(bob, "bob");
        vm.label(carol, "carol");

        // mint to alice, bob, carol

        address ptr = SSTORE2.write(abi.encodePacked(alice, bob, carol));
        token.mint(ptr);

        assertEq(token.balanceOf(alice), 1);
        assertEq(token.balanceOf(bob), 1);
        assertEq(token.balanceOf(carol), 1);
        assertEq(token.balanceOf(dennis), 0);

        assertEq(token.ownerOf(1), alice);
        assertEq(token.ownerOf(2), bob);
        assertEq(token.ownerOf(3), carol);

        // transfers among primary owners

        vm.prank(bob);
        token.transferFrom(bob, alice, 2);

        vm.prank(carol);
        token.transferFrom(carol, alice, 3);

        assertEq(token.balanceOf(alice), 3);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.balanceOf(carol), 0);
        assertEq(token.balanceOf(dennis), 0);

        assertEq(token.ownerOf(1), alice);
        assertEq(token.ownerOf(2), alice);
        assertEq(token.ownerOf(3), alice);

        // transfers to secondary owners

        vm.startPrank(alice);
        token.transferFrom(alice, dennis, 1);
        token.transferFrom(alice, dennis, 2);
        token.transferFrom(alice, dennis, 3);
        vm.stopPrank();

        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.balanceOf(carol), 0);
        assertEq(token.balanceOf(dennis), 3);

        assertEq(token.ownerOf(1), dennis);
        assertEq(token.ownerOf(2), dennis);
        assertEq(token.ownerOf(3), dennis);

        // burns

        vm.startPrank(dennis);
        token.burn(1);
        token.burn(2);
        token.burn(3);
        vm.stopPrank();

        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.balanceOf(carol), 0);
        assertEq(token.balanceOf(dennis), 0);
        assertEq(token.balanceOf(BURN_ADDRESS), 0);

        assertEq(token.ownerOf(1), BURN_ADDRESS);
        assertEq(token.ownerOf(2), BURN_ADDRESS);
        assertEq(token.ownerOf(3), BURN_ADDRESS);
    }
}
