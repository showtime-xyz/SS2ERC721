// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import {Test, console2} from "forge-std/Test.sol";
import {SSTORE2} from "solmate/utils/SSTORE2.sol";
import {stdError} from "forge-std/StdError.sol";

import {BasicMultiSS2ERC721} from "test/helpers/BasicMultiSS2ERC721.sol";
import {Addresses} from "test/helpers/Addresses.sol";

contract MultiSS2ERC721Specifics is Test {
    uint256 BATCH_SIZE = 1228;

    event Transfer(address indexed from, address indexed to, uint256 indexed tokenId);

    BasicMultiSS2ERC721 token;

    function setUp() public {
        token = new BasicMultiSS2ERC721("basic", unicode"✌️");
    }

    function test_mint_nullPointer_reverts() public {
        // there is actually no special treatment for null pointers,
        // it fails with the same error as a bad pointer (i.e. no code at that address)
        test_mint_badPointer_reverts(address(0));
    }

    function test_mint_badPointer_reverts(address ptr) public {
        vm.assume(ptr.code.length == 0);

        vm.expectRevert("INVALID_ADDRESSES");
        token.mint(address(0));
    }

    function test_mint_badRecipients_reverts() public {
        vm.expectRevert("INVALID_ADDRESSES");
        token.mint("beep boop");
    }

    function test_mint_nullRecipient_reverts() public {
        // will be caught by the to > prev check since prev is initialized as 0
        // not the greatest error message for this case, but not worth having a special check
        vm.expectRevert("ADDRESSES_NOT_SORTED");
        token.mint(abi.encodePacked(address(0)));
    }

    function test_mint_emptyPointer_reverts() public {
        address ptr = SSTORE2.write("");

        vm.expectRevert("INVALID_ADDRESSES");
        token.mint(ptr);
    }

    function test_mint_emptyRecipients_reverts() public {
        vm.expectRevert("INVALID_ADDRESSES");
        token.mint("");
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

    function test_transferFrom_toDeadAddr() public {
        address ptr = SSTORE2.write(abi.encodePacked(address(this)));
        token.mint(ptr);

        address burn_address = address(0xdead);

        token.transferFrom(address(this), burn_address, 1);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.ownerOf(1), burn_address);

        // this is a normal transfer, so the balance is incremented
        assertEq(token.balanceOf(burn_address), 1);
    }

    function test_e2e_singleBatch() public {
        address alice = makeAddr("alice");
        address bob = address(uint160(alice) + 1);
        address carol = address(uint160(alice) + 2);
        address dennis = makeAddr("dennis");

        vm.label(bob, "bob");
        vm.label(carol, "carol");

        // mint to alice, bob, carol
        token.mint(abi.encodePacked(alice, bob, carol));

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

        vm.expectRevert("NOT_MINTED");
        token.ownerOf(1);

        vm.expectRevert("NOT_MINTED");
        token.ownerOf(2);

        vm.expectRevert("NOT_MINTED");
        token.ownerOf(3);
    }

    /*//////////////////////////////////////////////////////////////
                        ACTUAL MULTI BATCH TESTS
    //////////////////////////////////////////////////////////////*/

    function test_mint_incomplete_batch() public {
        address ptr = SSTORE2.write(abi.encodePacked(address(this)));
        token.mint(ptr);

        vm.expectRevert("INCOMPLETE_BATCH");
        token.mint(ptr);

        vm.expectRevert("INCOMPLETE_BATCH");
        token.mint(abi.encodePacked(address(this)));

        vm.expectRevert("INCOMPLETE_BATCH");
        token.safeMint(ptr);
    }

    function test_mint_incomplete_batch(uint256 size) public {
        size = bound(size, 1, BATCH_SIZE - 1);

        bytes memory recipients = Addresses.make(size);
        address ptr = SSTORE2.write(recipients);
        token.mint(ptr);

        vm.expectRevert("INCOMPLETE_BATCH");
        token.mint(ptr);

        vm.expectRevert("INCOMPLETE_BATCH");
        token.mint(recipients);

        vm.expectRevert("INCOMPLETE_BATCH");
        token.safeMint(ptr);
    }

    function test_e2e_multiBatch() public {
        // First full batch, with mint(bytes calldata recipients)

        vm.expectEmit(true, true, true, true);
        emit Transfer(address(0), address(1), 1);

        vm.expectEmit(true, true, true, true);
        emit Transfer(address(0), addr(BATCH_SIZE), BATCH_SIZE);

        uint256 numMinted = token.mint(Addresses.make(address(1), BATCH_SIZE));
        assertEq(numMinted, BATCH_SIZE);

        // Second full batch, with mint(address ptr)

        vm.expectEmit(true, true, true, true);
        emit Transfer(address(0), addr(BATCH_SIZE + 1), BATCH_SIZE + 1);

        vm.expectEmit(true, true, true, true);
        emit Transfer(address(0), addr(BATCH_SIZE * 2), BATCH_SIZE * 2);

        bytes memory batch2 = Addresses.make(addr(BATCH_SIZE + 1), BATCH_SIZE);
        numMinted = token.mint(SSTORE2.write(batch2));
        assertEq(numMinted, BATCH_SIZE);

        // Third batch, with safeMint(address ptr)

        vm.expectEmit(true, true, true, true);
        emit Transfer(address(0), addr(BATCH_SIZE * 2 + 1), BATCH_SIZE * 2 + 1);

        vm.expectEmit(true, true, true, true);
        emit Transfer(address(0), addr(BATCH_SIZE * 3), BATCH_SIZE * 3);

        bytes memory batch3 = Addresses.make(addr(BATCH_SIZE * 2 + 1), BATCH_SIZE);
        numMinted = token.safeMint(SSTORE2.write(batch3));
        assertEq(numMinted, BATCH_SIZE);


        // top if off with an incomplete batch

        token.mint(abi.encodePacked(address(this)));

        // balance checks work
        assertEq(token.balanceOf(address(1)), 1);
        assertEq(token.balanceOf(addr(BATCH_SIZE)), 1);
        assertEq(token.balanceOf(addr(BATCH_SIZE + 1)), 1);
        assertEq(token.balanceOf(address(this)), 1);

        // ownerOf checks work
        assertEq(token.ownerOf(1), address(1));
        assertEq(token.ownerOf(BATCH_SIZE), addr(BATCH_SIZE));
        assertEq(token.ownerOf(BATCH_SIZE + 1), addr(BATCH_SIZE + 1));
        assertEq(token.ownerOf(BATCH_SIZE * 3 + 1), address(this));
    }

    function addr(uint256 i) internal pure returns (address) {
        return address(uint160(i));
    }
}
