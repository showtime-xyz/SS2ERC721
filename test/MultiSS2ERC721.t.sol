// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.0;

import {Test, console2} from "forge-std/Test.sol";

import {SSTORE2} from "solmate/utils/SSTORE2.sol";

import {MultiSS2ERC721} from "src/MultiSS2ERC721.sol";

import "test/ERC721Test.t.sol";

// based on ERC721Test.t.sol's MockERC721
abstract contract MockMultiSS2ERC721 is MultiSS2ERC721 {
    constructor(string memory _name, string memory _symbol) MultiSS2ERC721(_name, _symbol) {}

    /*//////////////////////////////////////////////////////////////
                             MUST OVERRIDE
    //////////////////////////////////////////////////////////////*/

    function safeMint(address to, bytes memory data) public virtual;

    function mint(address to) public virtual;

    /*//////////////////////////////////////////////////////////////
                                HELPERS
    //////////////////////////////////////////////////////////////*/

    function tokenURI(uint256) public pure virtual override returns (string memory) {}

    function safeMintToPointer(address pointer, bytes memory data) public {
        _safeMint(pointer, data);
    }

    function safeMint(address to) public virtual {
        safeMint(to, "");
    }

    // public authenticated wrapper
    function burn(uint256 id) public {
        address from = ownerOf(id);
        require(
            msg.sender == from || isApprovedForAll[from][msg.sender] || msg.sender == getApproved[id], "NOT_AUTHORIZED"
        );
        _burn(id);
    }
}

contract MockMultiSS2ERC721PointerMinter is MockMultiSS2ERC721 {
    constructor(
        string memory _name,
        string memory _symbol
    ) MockMultiSS2ERC721(_name, _symbol) {}

    function safeMint(address to, bytes memory data) public override {
        address pointer = SSTORE2.write(abi.encodePacked(to));
        _safeMint(pointer, data);
    }

    function mint(address to) public override {
        address pointer = SSTORE2.write(abi.encodePacked(to));
        _mint(pointer);
    }
}

contract MockMultiSS2ERC721CalldataMinter is MockMultiSS2ERC721 {
    constructor(
        string memory _name,
        string memory _symbol
    ) MockMultiSS2ERC721(_name, _symbol) {}

    function mint(bytes calldata addresses) public {
        _mint(addresses);
    }

    function safeMint(address to, bytes memory data) public override {
        // note: there is no safeMint calldata version
        address pointer = SSTORE2.write(abi.encodePacked(to));
        _safeMint(pointer, data);
    }

    function mint(address to) public override {
        // create a new call frame
        MockMultiSS2ERC721CalldataMinter(address(this)).mint(abi.encodePacked(to));
    }
}

/// @notice Test suite for ERC721 based on solmate's
/// @dev specifically test MultiSS2ERC721._mint(bytes calldata addresses)
contract MultiSS2ERC721Calldata is ERC721Test {
    function getERC721Impl(string memory name, string memory symbol) public virtual override returns (MockERC721) {
        return MockERC721(address(new MockMultiSS2ERC721CalldataMinter(name, symbol)));
    }
}

/// @notice Test suite for ERC721 based on solmate's
/// @dev specifically test MultiSS2ERC721._mint(address pointer)
contract MultiSS2ERC721Pointer is ERC721Test {
    function getERC721Impl(string memory name, string memory symbol) public virtual override returns (MockERC721) {
        return MockERC721(address(new MockMultiSS2ERC721PointerMinter(name, symbol)));
    }
}
