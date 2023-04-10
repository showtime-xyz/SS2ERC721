// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import {MultiSS2ERC721} from "src/MultiSS2ERC721.sol";

contract BasicMultiSS2ERC721 is MultiSS2ERC721 {
    constructor(string memory name_, string memory symbol_) MultiSS2ERC721(name_, symbol_) {}

    function safeMint(address ptr) public returns (uint256) {
        return _safeMint(ptr, "");
    }

    function mint(address ptr) public returns (uint256) {
        return _mint(ptr);
    }

    function mint(bytes calldata recipients) public returns (uint256) {
        return _mint(recipients);
    }

    function burn(uint256 tokenId) public {
        _burn(tokenId);
    }

    function tokenURI(uint256) public view virtual override returns (string memory) {
        return "";
    }
}
