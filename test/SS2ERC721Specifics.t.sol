// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import {Test} from "forge-std/Test.sol";
import {SSTORE2} from "solmate/utils/SSTORE2.sol";

import {SS2ERC721} from "src/SS2ERC721.sol";

contract BasicSS2ERC721 is SS2ERC721 {
    constructor(string memory name_, string memory symbol_)
        SS2ERC721(name_, symbol_)
    {}

    function mint(address ptr) public returns (uint256 numMinted) {
        numMinted = _mint(ptr);
    }

    function tokenURI(uint256) public view virtual override returns (string memory) {
        return "";
    }
}

contract SS2ERC721Specifics is Test {
    // https://docs.soliditylang.org/en/latest/control-structures.html#panic-via-assert-and-error-via-require
    uint256 internal constant ARITHMETIC_UNDERFLOW_OVERFLOW = 0x11;

    BasicSS2ERC721 nftContract;

    function setUp() public {
        nftContract = new BasicSS2ERC721("basic", unicode"✌️");
    }

    function test_getOwnersPrimaryPointer_startsNull() public {
        assertEq(nftContract.getOwnersPrimaryPointer(), address(0));
    }

    function test_getOwnersPrimaryPointer_afterMint() public {
        address ptr = SSTORE2.write(abi.encodePacked(address(this)));
        nftContract.mint(ptr);
        assertEq(nftContract.getOwnersPrimaryPointer(), ptr);
    }

    function test_ownerOf_idZero_reverts() public {
        vm.expectRevert("ZERO_ID");
        nftContract.ownerOf(0);
    }

    function test_mint_nullPointer_reverts() public {
        // there is actually no special treatment for null pointers,
        // it fails with the same error as a bad pointer (i.e. no code at that address)
        test_mint_badPointer_reverts(address(0));
    }

    function test_mint_badPointer_reverts(address ptr) public {
        vm.assume(ptr.code.length == 0);

        vm.expectRevert(abi.encodeWithSignature("Panic(uint256)", ARITHMETIC_UNDERFLOW_OVERFLOW));
        nftContract.mint(address(0));
    }

    function test_mint_emptyPointer_reverts() public {
        address ptr = SSTORE2.write("");

        vm.expectRevert("INVALID_ADDRESSES");
        nftContract.mint(ptr);
    }

    function test_mint_randomData_reverts() public {
        address ptr = SSTORE2.write("beep boop");

        vm.expectRevert("INVALID_ADDRESSES");
        nftContract.mint(ptr);
    }

    function test_mint_invalidData_reverts() public {
        address ptr = SSTORE2.write(abi.encodePacked(address(this), "beep boop"));

        vm.expectRevert("INVALID_ADDRESSES");
        nftContract.mint(ptr);
    }

    function test_mint_unsortedAddresses_reverts() public {
        address ptr = SSTORE2.write(abi.encodePacked(address(2), address(1)));

        vm.expectRevert("ADDRESSES_NOT_SORTED");
        nftContract.mint(ptr);
    }

    function test_mint_twice_reverts() public {
        address ptr = SSTORE2.write(abi.encodePacked(address(this)));
        nftContract.mint(ptr);

        vm.expectRevert("ALREADY_MINTED");
        nftContract.mint(ptr);
    }

    function test_mint_returnsNumMinted() public {
        address ptr = SSTORE2.write(abi.encodePacked(address(1), address(2), address(3)));
        uint256 numMinted = nftContract.mint(ptr);
        assertEq(numMinted, 3);
    }
}
