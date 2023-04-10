// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.0;

import {Test, console2} from "forge-std/Test.sol";

import {SSTORE2} from "solmate/utils/SSTORE2.sol";

import {SS2ERC721} from "src/SS2ERC721.sol";

contract NastySS2ERC721 is SS2ERC721 {
    constructor(
        string memory _name,
        string memory _symbol
    ) SS2ERC721(_name, _symbol) {}

    function safeMint(address pointer, bytes memory data) public {
        _safeMint(pointer, data);
    }

    function mint(address pointer) public {
        _mint(pointer);
    }

    function mint(bytes calldata addresses) public {
        _mint(addresses);
    }

    function retrieveOwnerSlot() public view returns (uint256 value) {
        assembly {
            value := sload(_ownersPrimaryPointer.slot)
        }
    }

    function setOwnerSlot(uint256 value) public {
        assembly {
            sstore(_ownersPrimaryPointer.slot, value)
        }
    }

    function tokenURI(
        uint256 id
    ) public view virtual override returns (string memory) {}
}

contract PointerSafetyTest is Test {
    // we're going to pack this in the upper 12 bytes of _ownersPrimaryPointer
    uint256 constant SENTINEL = 0x11223344556677889900AABB << 160;

    NastySS2ERC721 token;

    function setUp() public {
        token = new NastySS2ERC721("name", "symbol");

        token.setOwnerSlot(SENTINEL);
    }

    function test_mintCalldata_preservesUpperBits() public {
        token.mint(abi.encodePacked(address(this)));

        uint256 retrieved = token.retrieveOwnerSlot();
        assertEq(retrieved >> 160, SENTINEL >> 160);
    }

    function test_mintPointer_preservesUpperBits() public {
        token.mint(SSTORE2.write(abi.encodePacked(address(this))));

        uint256 retrieved = token.retrieveOwnerSlot();
        assertEq(retrieved >> 160, SENTINEL >> 160);
    }

    function test_safeMint_preservesUpperBits() public {
        token.safeMint(SSTORE2.write(abi.encodePacked(address(1))), "");

        uint256 retrieved = token.retrieveOwnerSlot();
        assertEq(retrieved >> 160, SENTINEL >> 160);
    }
}
