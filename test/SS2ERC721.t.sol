// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.0;

import {Test, console2} from "forge-std/Test.sol";

import {Owned} from "solmate/auth/Owned.sol";
import {SSTORE2} from "solmate/utils/SSTORE2.sol";

import {SS2ERC721, ERC721TokenReceiver} from "src/SS2ERC721.sol";

contract ERC721Recipient is ERC721TokenReceiver {
    address public operator;
    address public from;
    uint256 public id;
    bytes public data;

    function onERC721Received(address _operator, address _from, uint256 _id, bytes calldata _data)
        public
        virtual
        override
        returns (bytes4)
    {
        operator = _operator;
        from = _from;
        id = _id;
        data = _data;

        return ERC721TokenReceiver.onERC721Received.selector;
    }
}

contract RevertingERC721Recipient is ERC721TokenReceiver {
    function onERC721Received(address, address, uint256, bytes calldata) public virtual override returns (bytes4) {
        revert("NO_THANKS");
    }
}

contract WrongReturnDataERC721Recipient is ERC721TokenReceiver {
    function onERC721Received(address, address, uint256, bytes calldata) public virtual override returns (bytes4) {
        return 0xCAFEBEEF;
    }
}

contract MockERC721 is SS2ERC721, Owned {
    constructor(string memory _name, string memory _symbol) SS2ERC721(_name, _symbol) Owned(msg.sender) {}

    function tokenURI(uint256) public pure virtual override returns (string memory) {}

    function safeMint(address addr) public returns (bool collision) {
        address pointer = SSTORE2.write(abi.encodePacked(addr));
        if (pointer == addr) {
            return true;
        }

        _safeMint(pointer);
    }

    function safeMint(address addr1, bytes memory data) public {
        address pointer = SSTORE2.write(abi.encodePacked(addr1));
        _safeMint(pointer, data);
    }

    function mint(address to) public {
        address pointer = SSTORE2.write(abi.encodePacked(to));
        _mint(pointer);
    }

    function mint(address addr1, address addr2) public {
        address pointer = SSTORE2.write(abi.encodePacked(addr1, addr2));
        _mint(pointer);
    }

    // public authenticated wrapper
    function burn(uint256 id) public {
        address from = ownerOf(id);
        require(
            msg.sender == from || isApprovedForAll[from][msg.sender] || msg.sender == getApproved[id], "NOT_AUTHORIZED"
        );
        _burn(id);
    }

    // no auth! contract owner can burn anything
    function burnByContractOwner(uint256 id) public onlyOwner {
        _burn(id);
    }
}

contract NonERC721Recipient {}

/// @notice Test suite for ERC721 based on solmate's
contract ERC721Test is Test {
    event Transfer(address indexed from, address indexed to, uint256 indexed id);
    event Approval(address indexed owner, address indexed spender, uint256 indexed id);
    event ApprovalForAll(address indexed owner, address indexed operator, bool approved);

    MockERC721 token;

    address happyRecipient;
    address nonRecipient;
    address revertingRecipient;
    address wrongReturnDataRecipient;

    function setUp() public {
        token = new MockERC721("Token", "TKN");
        happyRecipient = address(new ERC721Recipient());
        nonRecipient = address(new NonERC721Recipient());
        revertingRecipient = address(new RevertingERC721Recipient());
        wrongReturnDataRecipient = address(new WrongReturnDataERC721Recipient());
    }

    function bound_min(address a, uint256 min) internal view returns (address) {
        return address(uint160(bound(uint160(a), min, type(uint160).max)));
    }

    /// @dev a value strictly greater than min_addr
    function bound_min(address a, address min_addr) internal view returns (address) {
        uint256 min = uint160(min_addr) + 1;
        return bound_min(a, min);
    }

    function invariantMetadata() public {
        assertEq(token.name(), "Token");
        assertEq(token.symbol(), "TKN");
    }

    function testMint() public {
        vm.expectEmit(true, true, true, true);
        emit Transfer(address(0), address(0xBEEF), 1);

        vm.expectEmit(true, true, true, true);
        emit Transfer(address(0), address(0xBFFF), 2);

        token.mint(address(0xBEEF), address(0xBFFF));

        assertEq(token.balanceOf(address(0xBEEF)), 1);
        assertEq(token.ownerOf(1), address(0xBEEF));
    }

    function testBalanceOfBeforeMint() public {
        assertEq(token.balanceOf(address(0xBEEF)), 0);
    }

    function testBurn() public {
        token.mint(address(0xBEEF), address(0xBFFF));

        vm.expectEmit(true, true, true, true);
        emit Transfer(address(0xBEEF), address(0), 1);

        vm.prank(address(0xBEEF));
        token.burn(1);

        assertEq(token.balanceOf(address(0xBEEF)), 0);
        assertEq(token.ownerOf(1), address(0));
    }

    function testApprove() public {
        token.mint(address(this));

        vm.expectEmit(true, true, true, true);
        emit Approval(address(this), address(0xBEEF), 1);

        token.approve(address(0xBEEF), 1);

        assertEq(token.getApproved(1), address(0xBEEF));
    }

    function testApproveBurn() public {
        token.mint(address(this));

        token.approve(address(0xBEEF), 1);

        token.burn(1);

        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.getApproved(1), address(0));

        assertEq(token.ownerOf(1), address(0));
    }

    function testUnauthorizedBurn() public {
        token.mint(address(0xc0ffee));

        vm.expectRevert("NOT_AUTHORIZED");
        token.burn(1);

        assertEq(token.balanceOf(address(0xc0ffee)), 1);
    }

    function testBurnByAdmin() public {
        token.mint(address(0xc0ffee));

        token.burnByContractOwner(1);

        assertEq(token.balanceOf(address(0xc0ffee)), 0);
        assertEq(token.ownerOf(1), address(0));
    }

    function testApproveAll() public {
        vm.expectEmit(true, true, true, true);
        emit ApprovalForAll(address(this), address(0xBEEF), true);

        token.setApprovalForAll(address(0xBEEF), true);

        assertTrue(token.isApprovedForAll(address(this), address(0xBEEF)));
    }

    function testTransferFrom() public {
        address from = address(0xABCD);

        token.mint(from, address(0xBFFF));

        vm.prank(from);
        token.approve(address(this), 1);

        token.transferFrom(from, address(0xBEEF), 1);

        assertEq(token.getApproved(1), address(0));
        assertEq(token.ownerOf(1), address(0xBEEF));
        assertEq(token.balanceOf(address(0xBEEF)), 1);
        assertEq(token.balanceOf(from), 0);
    }

    function testTransferFromSelf() public {
        token.mint(address(this));

        token.transferFrom(address(this), address(0xBEEF), 1);

        assertEq(token.getApproved(1), address(0));
        assertEq(token.ownerOf(1), address(0xBEEF));
        assertEq(token.balanceOf(address(0xBEEF)), 1);
        assertEq(token.balanceOf(address(this)), 0);
    }

    function testTransferFromApproveAll() public {
        address from = address(0xABCD);

        token.mint(from, address(0xBFFF));

        vm.prank(from);
        token.setApprovalForAll(address(this), true);

        token.transferFrom(from, address(0xBEEF), 1);

        assertEq(token.getApproved(1), address(0));
        assertEq(token.ownerOf(1), address(0xBEEF));
        assertEq(token.balanceOf(address(0xBEEF)), 1);
        assertEq(token.balanceOf(from), 0);
    }

    function testSafeTransferFromToEOA() public {
        address from = address(0xABCD);

        token.mint(from);

        vm.prank(from);
        token.setApprovalForAll(address(this), true);

        token.safeTransferFrom(from, address(0xBEEF), 1);

        assertEq(token.getApproved(1), address(0));
        assertEq(token.ownerOf(1), address(0xBEEF));
        assertEq(token.balanceOf(address(0xBEEF)), 1);
        assertEq(token.balanceOf(from), 0);
    }

    function testSafeTransferFromToERC721Recipient() public {
        address from = address(0xABCD);
        ERC721Recipient recipient = ERC721Recipient(happyRecipient);

        token.mint(from);

        vm.prank(from);
        token.setApprovalForAll(address(this), true);

        token.safeTransferFrom(from, address(recipient), 1);

        assertEq(token.getApproved(1), address(0));
        assertEq(token.ownerOf(1), address(recipient));
        assertEq(token.balanceOf(address(recipient)), 1);
        assertEq(token.balanceOf(from), 0);

        assertEq(recipient.operator(), address(this));
        assertEq(recipient.from(), from);
        assertEq(recipient.id(), 1);
        assertEq(recipient.data(), "");
    }

    function testSafeTransferFromToERC721RecipientWithData() public {
        address from = address(0xABCD);
        ERC721Recipient recipient = ERC721Recipient(happyRecipient);

        token.mint(from);

        vm.prank(from);
        token.setApprovalForAll(address(this), true);

        token.safeTransferFrom(from, address(recipient), 1, "testing 123");

        assertEq(token.getApproved(1), address(0));
        assertEq(token.ownerOf(1), address(recipient));
        assertEq(token.balanceOf(address(recipient)), 1);
        assertEq(token.balanceOf(from), 0);

        assertEq(recipient.operator(), address(this));
        assertEq(recipient.from(), from);
        assertEq(recipient.id(), 1);
        assertEq(recipient.data(), "testing 123");
    }

    function testSafeMintToEOA() public {
        token.safeMint(address(0xBEEF));

        assertEq(token.ownerOf(1), address(0xBEEF));
        assertEq(token.balanceOf(address(0xBEEF)), 1);
    }

    function testSafeMintToERC721Recipient() public {
        ERC721Recipient to = ERC721Recipient(happyRecipient);

        token.safeMint(address(to));

        assertEq(token.ownerOf(1), address(to));
        assertEq(token.balanceOf(address(to)), 1);

        assertEq(to.operator(), address(this));
        assertEq(to.from(), address(0));
        assertEq(to.id(), 1);
        assertEq(to.data(), "");
    }

    function testSafeMintToERC721RecipientWithData() public {
        ERC721Recipient to = ERC721Recipient(happyRecipient);

        token.safeMint(address(to), "testing 123");

        assertEq(token.ownerOf(1), address(to));
        assertEq(token.balanceOf(address(to)), 1);

        assertEq(to.operator(), address(this));
        assertEq(to.from(), address(0));
        assertEq(to.id(), 1);
        assertEq(to.data(), "testing 123");
    }

    function test_mint_toZero_reverts() public {
        vm.expectRevert("ADDRESSES_NOT_SORTED");
        token.mint(address(0));
    }

    function test_burn_unminted_reverts() public {
        vm.expectRevert("NOT_MINTED");
        token.burn(1337);
    }

    function test_burn_double_reverts() public {
        token.mint(address(this));
        token.burn(1);

        vm.expectRevert("NOT_AUTHORIZED");
        token.burn(1);
    }

    function test_approve_unminted_reverts() public {
        vm.expectRevert("NOT_MINTED");
        token.approve(address(0xBEEF), 1337);
    }

    function test_approve_unauthorized_reverts() public {
        token.mint(address(0xCAFE));

        vm.expectRevert("NOT_AUTHORIZED");
        token.approve(address(0xBEEF), 1);
    }

    function test_transferFrom_unowned_reverts() public {
        vm.expectRevert("NOT_MINTED");
        vm.prank(address(0xFEED));
        token.transferFrom(address(0xFEED), address(0xBEEF), 1337);
    }

    function test_transferFrom_wrongFrom_reverts() public {
        token.mint(address(0xBEEF));

        vm.expectRevert("WRONG_FROM");
        vm.prank(address(0xFEED));
        token.transferFrom(address(0xFEED), address(0xBEEF), 1);
    }

    function test_transferFrom_toZero_reverts() public {
        token.mint(address(this));

        vm.expectRevert("INVALID_RECIPIENT");
        token.transferFrom(address(this), address(0), 1);
    }

    function test_transferFrom_notOwner_reverts() public {
        token.mint(address(0xF00D));

        vm.expectRevert("NOT_AUTHORIZED");
        token.transferFrom(address(0xF00D), address(0xBEEF), 1);
    }

    function test_safeTransferFrom_toNonERC721Recipient_reverts() public {
        token.mint(address(this));

        vm.expectRevert();
        token.safeTransferFrom(address(this), nonRecipient, 1);
    }

    function test_safeTransferFrom_toNonERC721RecipientWithData_reverts() public {
        token.mint(address(this));

        vm.expectRevert();
        token.safeTransferFrom(address(this), nonRecipient, 1, "testing 123");
    }

    function test_safeTransferFrom_toRevertingERC721Recipient_reverts() public {
        token.mint(address(this));

        vm.expectRevert("NO_THANKS");
        token.safeTransferFrom(address(this), revertingRecipient, 1);
    }

    function test_safeTransferFrom_toRevertingERC721RecipientWithData_reverts() public {
        token.mint(address(this));

        vm.expectRevert("NO_THANKS");
        token.safeTransferFrom(address(this), revertingRecipient, 1, "testing 123");
    }

    function test_safeTransferFrom_toERC721RecipientWithWrongReturnData_reverts() public {
        token.mint(address(this));

        vm.expectRevert("UNSAFE_RECIPIENT");
        token.safeTransferFrom(address(this), wrongReturnDataRecipient, 1);
    }

    function test_safeTransferFrom_toERC721RecipientWithWrongReturnDataWithData_reverts() public {
        token.mint(address(this));

        vm.expectRevert("UNSAFE_RECIPIENT");
        token.safeTransferFrom(address(this), wrongReturnDataRecipient, 1, "testing 123");
    }

    function test_safeMint_toNonERC721Recipient_reverts() public {
        vm.expectRevert();
        token.safeMint(nonRecipient);
    }

    function test_safeMint_toNonERC721RecipientWithData_reverts() public {
        vm.expectRevert();
        token.safeMint(nonRecipient, "testing 123");
    }

    function test_safeMint_toRevertingERC721Recipient_reverts() public {
        vm.expectRevert("NO_THANKS");
        token.safeMint(revertingRecipient);
    }

    function test_safeMint_toRevertingERC721RecipientWithData_reverts() public {
        vm.expectRevert("NO_THANKS");
        token.safeMint(revertingRecipient, "testing 123");
    }

    function test_safeMint_toERC721RecipientWithWrongReturnData_reverts() public {
        vm.expectRevert("UNSAFE_RECIPIENT");
        token.safeMint(wrongReturnDataRecipient);
    }

    function test_safeMint_toERC721RecipientWithWrongReturnDataWithData_reverts() public {
        vm.expectRevert("UNSAFE_RECIPIENT");
        token.safeMint(wrongReturnDataRecipient, "testing 123");
    }

    function test_balanceOf_zeroAddress_reverts() public {
        vm.expectRevert("ZERO_ADDRESS");
        token.balanceOf(address(0));
    }

    function test_ownerOf_unminted_reverts() public {
        vm.expectRevert("NOT_MINTED");
        token.ownerOf(1337);
    }

    function testMetadata(string memory name, string memory symbol) public {
        MockERC721 tkn = new MockERC721(name, symbol);

        assertEq(tkn.name(), name);
        assertEq(tkn.symbol(), symbol);
    }

    function testMint(address to1, address to2) public {
        vm.assume(to1 != address(0));
        to2 = bound_min(to2, to1);

        vm.expectEmit(true, true, true, true);
        emit Transfer(address(0), to1, 1);

        vm.expectEmit(true, true, true, true);
        emit Transfer(address(0), to2, 2);

        token.mint(to1, to2);
        assertEq(token.ownerOf(1), to1);
        assertEq(token.ownerOf(2), to2);
        assertEq(token.balanceOf(to1), 1);
        assertEq(token.balanceOf(to2), 1);
    }

    function testBurn(address to) public {
        vm.assume(to != address(0));
        token.mint(to);

        vm.expectEmit(true, true, true, true);
        emit Transfer(to, address(0), 1);

        vm.prank(to);
        token.burn(1);

        assertEq(token.balanceOf(to), 0);

        assertEq(token.ownerOf(1), address(0));
    }

    function testApprove(address to) public {
        token.mint(address(this));

        vm.expectEmit(true, true, true, true);
        emit Approval(address(this), to, 1);
        token.approve(to, 1);

        assertEq(token.getApproved(1), to);
    }

    function testApproveBurn(address to) public {
        vm.assume(to != address(0));

        token.mint(address(this));
        token.approve(address(to), 1);

        vm.prank(to);
        token.burn(1);

        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.getApproved(1), address(0));

        assertEq(token.ownerOf(1), address(0));
    }

    function testApproveAll(address to, bool approved) public {
        vm.expectEmit(true, true, true, true);
        emit ApprovalForAll(address(this), to, approved);

        token.setApprovalForAll(to, approved);

        assertEq(token.isApprovedForAll(address(this), to), approved);
    }

    function testTransferFrom(address from, address to) public {
        vm.assume(from != address(0));
        vm.assume(to != address(0));
        vm.assume(to != from);

        token.mint(from);

        vm.prank(from);
        token.approve(address(this), 1);

        token.transferFrom(from, to, 1);

        assertEq(token.getApproved(1), address(0));
        assertEq(token.ownerOf(1), to);
        assertEq(token.balanceOf(to), 1);
        assertEq(token.balanceOf(from), 0);
    }

    function testTransferFromSelf(address to) public {
        vm.assume(to != address(0));
        vm.assume(to != address(this));

        token.mint(address(this));

        token.transferFrom(address(this), to, 1);

        assertEq(token.getApproved(1), address(0));
        assertEq(token.ownerOf(1), to);
        assertEq(token.balanceOf(to), 1);
        assertEq(token.balanceOf(address(this)), 0);
    }

    function testTransferFromApproveAll(address from, address to) public {
        vm.assume(from != address(0));
        vm.assume(to != address(0));
        vm.assume(to != from);

        token.mint(from);

        vm.prank(from);
        token.setApprovalForAll(address(this), true);

        token.transferFrom(from, to, 1);

        assertEq(token.getApproved(1), address(0));
        assertEq(token.ownerOf(1), to);
        assertEq(token.balanceOf(to), 1);
        assertEq(token.balanceOf(from), 0);
    }

    function testSafeTransferFromToEOA(address from, address to) public {
        from = bound_min(from, 20);
        to = bound_min(to, 20);
        vm.assume(to != from);
        vm.assume(to != address(0));

        token.mint(from);

        vm.assume(to.code.length == 0);

        vm.prank(from);
        token.setApprovalForAll(address(this), true);

        token.safeTransferFrom(from, to, 1);

        assertEq(token.getApproved(1), address(0));
        assertEq(token.ownerOf(1), to);
        assertEq(token.balanceOf(to), 1);
        assertEq(token.balanceOf(from), 0);
    }

    function testSafeTransferFromToERC721Recipient(address from) public {
        from = bound_min(from, 20);
        vm.assume(from != happyRecipient);

        ERC721Recipient recipient = ERC721Recipient(happyRecipient);

        token.mint(from);

        vm.prank(from);
        token.setApprovalForAll(address(this), true);

        token.safeTransferFrom(from, address(recipient), 1);

        assertEq(token.getApproved(1), address(0));
        assertEq(token.ownerOf(1), address(recipient));
        assertEq(token.balanceOf(address(recipient)), 1);
        assertEq(token.balanceOf(from), 0);

        assertEq(recipient.operator(), address(this));
        assertEq(recipient.from(), from);
        assertEq(recipient.id(), 1);
        assertEq(recipient.data(), "");
    }

    function testSafeTransferFromToERC721RecipientWithData(address from, bytes calldata data) public {
        from = bound_min(from, 20);

        ERC721Recipient recipient = ERC721Recipient(happyRecipient);

        token.mint(from);

        vm.prank(from);
        token.setApprovalForAll(address(this), true);

        token.safeTransferFrom(from, address(recipient), 1, data);

        assertEq(token.getApproved(1), address(0));
        assertEq(token.ownerOf(1), address(recipient));
        assertEq(token.balanceOf(address(recipient)), 1);
        assertEq(token.balanceOf(from), 0);

        assertEq(recipient.operator(), address(this));
        assertEq(recipient.from(), from);
        assertEq(recipient.id(), 1);
        assertEq(recipient.data(), data);
    }

    function testSafeMintToEOA(address to) public {
        to = bound_min(to, 20);
        vm.assume(to.code.length == 0);

        bool collision = token.safeMint(to);

        // a collision means that `to` is the address of the SSTORE2 ptr
        // clearly at this point, this is not an EOA so we stop the test
        vm.assume(!collision);

        assertEq(token.ownerOf(1), to);
        assertEq(token.balanceOf(to), 1);
    }

    function testSafeMintToERC721RecipientWithData(bytes calldata data) public {
        ERC721Recipient to = ERC721Recipient(happyRecipient);

        token.safeMint(address(to), data);

        assertEq(token.ownerOf(1), address(to));
        assertEq(token.balanceOf(address(to)), 1);

        assertEq(to.operator(), address(this));
        assertEq(to.from(), address(0));
        assertEq(to.id(), 1);
        assertEq(to.data(), data);
    }

    function test_burn_unminted_reverts(uint256 id) public {
        vm.assume(id != 0);
        vm.expectRevert("NOT_MINTED");
        token.burn(id);
    }

    function test_burn_double_reverts(address to) public {
        vm.assume(to != address(0));

        token.mint(to);

        vm.prank(to);
        token.burn(1);

        vm.expectRevert("NOT_AUTHORIZED");
        vm.prank(to);
        token.burn(1);
    }

    function test_approve_unminted_reverts(uint256 id, address to) public {
        vm.assume(id != 0);
        vm.expectRevert("NOT_MINTED");
        token.approve(to, id);
    }

    function test_approve_unauthorized_reverts(address owner, address to) public {
        vm.assume(owner > address(0));
        vm.assume(owner != address(this));

        token.mint(owner);

        vm.expectRevert("NOT_AUTHORIZED");
        token.approve(to, 1);
    }

    function test_transferFrom_unowned_reverts(address from, address to, uint256 id) public {
        vm.assume(id != 0);
        vm.assume(to != address(0));

        vm.expectRevert("NOT_MINTED");
        vm.prank(from);
        token.transferFrom(from, to, id);
    }

    function test_transferFrom_wrongFrom_reverts(address owner, address from, address to) public {
        vm.assume(owner != address(0));
        vm.assume(from != owner);
        vm.assume(to != address(0));

        token.mint(owner);

        vm.expectRevert("WRONG_FROM");
        vm.prank(from);
        token.transferFrom(from, to, 1);
    }

    function test_transferFrom_notOwner_reverts(address from, address to) public {
        vm.assume(from != address(0));
        vm.assume(from != address(this));
        vm.assume(to != address(0));

        token.mint(from);

        vm.expectRevert("NOT_AUTHORIZED");
        token.transferFrom(from, to, 1);
    }

    function test_safeTransferFrom_toNonERC721RecipientWithData_reverts(bytes calldata data) public {
        token.mint(address(this));

        vm.expectRevert();
        token.safeTransferFrom(address(this), nonRecipient, 1, data);
    }

    function test_safeTransferFrom_toRevertingERC721RecipientWithData_reverts(bytes calldata data) public {
        token.mint(address(this));

        vm.expectRevert("NO_THANKS");
        token.safeTransferFrom(address(this), revertingRecipient, 1, data);
    }

    function test_safeTransferFrom_toERC721RecipientWithWrongReturnDataWithData_reverts(bytes calldata data) public {
        token.mint(address(this));

        vm.expectRevert("UNSAFE_RECIPIENT");
        token.safeTransferFrom(address(this), wrongReturnDataRecipient, 1, data);
    }

    function test_safeMint_toNonERC721RecipientWithData_reverts(bytes calldata data) public {
        vm.expectRevert("UNSAFE_RECIPIENT");
        token.safeMint(nonRecipient, data);
    }

    function test_safeMint_toRevertingERC721RecipientWithData(bytes calldata data) public {
        vm.expectRevert("NO_THANKS");
        token.safeMint(revertingRecipient, data);
    }

    function test_safeMint_toERC721RecipientWithWrongReturnDataWithData(bytes calldata data) public {
        vm.expectRevert("UNSAFE_RECIPIENT");
        token.safeMint(wrongReturnDataRecipient, data);
    }

    function test_ownerOf_unminted_reverts(uint256 id) public {
        vm.expectRevert("NOT_MINTED");
        token.ownerOf(id);
    }
}
