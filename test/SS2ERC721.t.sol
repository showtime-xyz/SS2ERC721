// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.0;

import {Test, console2} from "forge-std/Test.sol";

import {SSTORE2} from "solmate/utils/SSTORE2.sol";

import {SS2ERC721} from "src/SS2ERC721.sol";

import {ERC721Test, MockERC721} from "test/ERC721Test.t.sol";

contract MockERC721CalldataMinter is MockERC721 {
    constructor(
        string memory _name,
        string memory _symbol
    ) MockERC721(_name, _symbol)  {}

    function mint(bytes calldata addresses) public {
        _mint(addresses);
    }

    function safeMint(address addr1, bytes memory data) public override {
        // note: there is no safeMint calldata version
        address pointer = SSTORE2.write(abi.encodePacked(addr1));
        _safeMint(pointer, data);
    }

    function mint(address to) public override {
        // create a new call frame
        MockERC721CalldataMinter(address(this)).mint(abi.encodePacked(to));
    }
}

contract MockERC721PointerMinter is MockERC721 {
    constructor(string memory _name, string memory _symbol) MockERC721(_name, _symbol) {}

    function safeMint(address to, bytes memory data) public override {
        address pointer = SSTORE2.write(abi.encodePacked(to));
        _safeMint(pointer, data);
    }

    function mint(address to) public override {
        address pointer = SSTORE2.write(abi.encodePacked(to));
        _mint(pointer);
    }
}

/// @notice Test suite for ERC721 based on solmate's
/// @dev specifically test SS2ERC721._mint(bytes calldata addresses)
contract SS2ERC721Calldata is ERC721Test {
    function getERC721Impl(string memory name, string memory symbol) public virtual override returns (MockERC721) {
        return new MockERC721CalldataMinter(name, symbol);
    }
}

/// @notice Test suite for ERC721 based on solmate's
/// @dev specifically test SS2ERC721._mint(address pointer)
contract SS2ERC721Pointer is ERC721Test {
    function getERC721Impl(string memory name, string memory symbol) public virtual override returns (MockERC721) {
        return new MockERC721PointerMinter(name, symbol);
    }
}
