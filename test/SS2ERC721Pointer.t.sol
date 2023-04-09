// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.0;

import {Test, console2} from "forge-std/Test.sol";

import {SSTORE2} from "solmate/utils/SSTORE2.sol";

import {ERC721Test, MockERC721} from "test/ERC721Test.t.sol";

contract MockERC721PointerMinter is MockERC721 {
    constructor(string memory _name, string memory _symbol) MockERC721(_name, _symbol) {}

    function tokenURI(uint256) public pure virtual override returns (string memory) {}

    function safeMint(address addr1, bytes memory data) public override {
        address pointer = SSTORE2.write(abi.encodePacked(addr1));
        _safeMint(pointer, data);
    }

    function safeMintToPointer(address pointer, bytes memory data) public {
        _safeMint(pointer, data);
    }

    function mint(address to) public override {
        address pointer = SSTORE2.write(abi.encodePacked(to));
        _mint(pointer);
    }

    function mint(address addr1, address addr2) public override {
        address pointer = SSTORE2.write(abi.encodePacked(addr1, addr2));
        _mint(pointer);
    }
}

/// @notice Test suite for ERC721 based on solmate's
/// @dev specifically test the pointer version of _mint
contract SS2ERC721Pointer is ERC721Test {
    function getERC721Impl(string memory name, string memory symbol) public virtual override returns (MockERC721) {
        return new MockERC721PointerMinter(name, symbol);
    }

    function testSafeMintToEOA(address to) public override {
        to = bound_min(to, 20);
        vm.assume(to.code.length == 0);

        address ptr = SSTORE2.write(abi.encodePacked(to));
        bool collision = ptr == to;

        // a collision means that `to` is the address of the SSTORE2 ptr
        // clearly at this point, this is not an EOA so we stop the test
        vm.assume(!collision);

        MockERC721PointerMinter(address(token)).safeMintToPointer(ptr, "");

        assertEq(token.ownerOf(1), to);
        assertEq(token.balanceOf(to), 1);
    }
}
