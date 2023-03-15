// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import {SSTORE2} from "solmate/utils/SSTORE2.sol";

import {SS2ERC721} from "src/SS2ERC721.sol";

contract BasicSS2ERC721 is SS2ERC721 {
    constructor(string memory name_, string memory symbol_) SS2ERC721(name_, symbol_) {}

    function mint(address ptr) public returns (uint256) {
        return _mint(ptr);
    }

    function mint(bytes calldata recipients) public returns (uint256) {
        return _mint(SSTORE2.write(recipients));
    }

    function burn(uint256 tokenId) public {
        _burn(tokenId);
    }

    function tokenURI(uint256) public view virtual override returns (string memory) {
        return "";
    }
}
