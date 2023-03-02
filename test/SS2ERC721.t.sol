// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.0;

import {Test} from "forge-std/Test.sol";

import {SSTORE2} from "solmate/utils/SSTORE2.sol";

import {ERC721TokenReceiver} from "src/ERC721TokenReceiver.sol";
import {SS2ERC721} from "src/SS2ERC721.sol";

contract ERC721Recipient is ERC721TokenReceiver {
    address public operator;
    address public from;
    uint256 public id;
    bytes public data;

    function onERC721Received(
        address _operator,
        address _from,
        uint256 _id,
        bytes calldata _data
    ) public virtual override returns (bytes4) {
        operator = _operator;
        from = _from;
        id = _id;
        data = _data;

        return ERC721TokenReceiver.onERC721Received.selector;
    }
}

contract RevertingERC721Recipient is ERC721TokenReceiver {
    function onERC721Received(
        address,
        address,
        uint256,
        bytes calldata
    ) public virtual override returns (bytes4) {
        revert(
            string(
                abi.encodePacked(ERC721TokenReceiver.onERC721Received.selector)
            )
        );
    }
}

contract WrongReturnDataERC721Recipient is ERC721TokenReceiver {
    function onERC721Received(
        address,
        address,
        uint256,
        bytes calldata
    ) public virtual override returns (bytes4) {
        return 0xCAFEBEEF;
    }
}

contract MockERC721 is SS2ERC721 {
    constructor(string memory _name, string memory _symbol) SS2ERC721(_name, _symbol) {}

    function tokenURI(uint256)
        public
        pure
        virtual
        override
        returns (string memory)
    {}

    function safeMint(address addr) public {
        address pointer = SSTORE2.write(abi.encodePacked(addr));
        _safeMint(pointer);
    }

    function safeMint(address addr1, address addr2) public {
        address pointer = SSTORE2.write(abi.encodePacked(addr1, addr2));
        _safeMint(pointer);
    }

    function safeMint(
        address addr1,
        address addr2,
        bytes memory data
    ) public {
        address pointer = SSTORE2.write(abi.encodePacked(addr1, addr2));
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

    function burn(uint256 id) public {
        if (msg.sender != ownerOf(id)) {
            revert("WRONG_FROM");
        }
        _burn(id);
    }
}

contract NonERC721Recipient {}

contract ERC721Test is Test {
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

    function incr(address addr) internal pure returns (address) {
        return address(uint160(addr) + 1);
    }

    function invariantMetadata() public {
        assertEq(token.name(), "Token");
        assertEq(token.symbol(), "TKN");
    }

    function testMint() public {
        token.mint(address(0xBEEF), address(0xBFFF));

        assertEq(token.balanceOf(address(0xBEEF)), 1);
        assertEq(token.ownerOf(1), address(0xBEEF));
    }

    function testBalanceOfBeforeMint() public {
        assertEq(token.balanceOf(address(0xBEEF)), 0);
    }

    function testOwnerOfBeforeMint(uint256 n) public {
        vm.assume(n > 0);
        vm.expectRevert("NOT_MINTED");
        token.ownerOf(n);
    }

    function testMint2() public {
        address to1 = 0xaAaAaAaaAaAaAaaAaAAAAAAAAaaaAaAaAaaAaaAa;
        address to2 = 0xbBbBBBBbbBBBbbbBbbBbbbbBBbBbbbbBbBbbBBbB;

        token.mint(to1, to2);
        assertEq(token.balanceOf(to1), 1);
        assertEq(token.balanceOf(to2), 1);
        assertEq(token.ownerOf(1), to1);
        assertEq(token.ownerOf(2), to2);
    }

    function testBurn() public {
        token.mint(address(0xBEEF), address(0xBFFF));

        vm.prank(address(0xBEEF));
        token.burn(1);

        assertEq(token.balanceOf(address(0xBEEF)), 0);
        assertEq(token.ownerOf(1), address(0xdead));
    }

    function testApprove() public {
        token.mint(address(this));

        token.approve(address(0xBEEF), 1);

        assertEq(token.getApproved(1), address(0xBEEF));
    }

    function testApproveBurn() public {
        token.mint(address(this), incr(address(this)));

        token.approve(address(0xBEEF), 1);

        token.burn(1);

        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.getApproved(1), address(0));

        assertEq(token.ownerOf(1), address(0xdead));
    }

    function testApproveAll() public {
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
        token.mint(address(this), incr(address(this)));

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

        token.mint(from, incr(from));

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

        token.mint(from, incr(from));

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

        token.mint(from, incr(from));

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
        token.safeMint(address(0xBEEF), address(0xBFFF));

        assertEq(token.ownerOf(1), address(0xBEEF));
        assertEq(token.balanceOf(address(0xBEEF)), 1);
    }

    function testSafeMintToERC721Recipient() public {
        ERC721Recipient to = ERC721Recipient(happyRecipient);

        token.safeMint(address(to), incr(address(to)));

        assertEq(token.ownerOf(1), address(to));
        assertEq(token.balanceOf(address(to)), 1);

        assertEq(to.operator(), address(this));
        assertEq(to.from(), address(0));
        assertEq(to.id(), 1);
        assertEq(to.data(), "");
    }

    function testSafeMintToERC721RecipientWithData() public {
        ERC721Recipient to = ERC721Recipient(happyRecipient);

        token.safeMint(address(to), incr(address(to)), "testing 123");

        assertEq(token.ownerOf(1), address(to));
        assertEq(token.balanceOf(address(to)), 1);

        assertEq(to.operator(), address(this));
        assertEq(to.from(), address(0));
        assertEq(to.id(), 1);
        assertEq(to.data(), "testing 123");
    }

    function testFailMintToZero() public {
        token.mint(address(0), address(1));
    }

    function testFailDoubleMint() public {
        token.mint(address(0xBEEF), address(0xBEEF));
    }

    function testFailBurnUnMinted() public {
        token.burn(1337);
    }

    function testFailDoubleBurn() public {
        token.mint(address(0xBEEF), address(0xBFFF));

        token.burn(1);
        token.burn(1);
    }

    function testFailApproveUnMinted() public {
        token.approve(address(0xBEEF), 1337);
    }

    function testFailApproveUnAuthorized() public {
        token.mint(address(0xCAFE), address(0xDEAD));

        token.approve(address(0xBEEF), 1337);
    }

    function testFailTransferFromUnOwned() public {
        token.transferFrom(address(0xFEED), address(0xBEEF), 1337);
    }

    function testFailTransferFromWrongFrom() public {
        token.mint(address(0xBEEF), address(0xCAFE));

        token.transferFrom(address(0xFEED), address(0xBEEF), 1);
    }

    function testFailTransferFromToZero() public {
        token.mint(address(this), incr(address(this)));

        token.transferFrom(address(this), address(0), 1);
    }

    function testFailTransferFromNotOwner() public {
        token.mint(address(0xF00D), address(0xFEED));

        token.transferFrom(address(0xF00D), address(0xBEEF), 1);
    }

    function testFailSafeTransferFromToNonERC721Recipient() public {
        token.mint(address(this), incr(address(this)));

        token.safeTransferFrom(
            address(this),
            nonRecipient,
            1
        );
    }

    function testFailSafeTransferFromToNonERC721RecipientWithData() public {
        token.mint(address(this), incr(address(this)));

        token.safeTransferFrom(
            address(this),
            nonRecipient,
            1,
            "testing 123"
        );
    }

    function testFailSafeTransferFromToRevertingERC721Recipient() public {
        token.mint(address(this), incr(address(this)));

        token.safeTransferFrom(
            address(this),
            revertingRecipient,
            1
        );
    }

    function testFailSafeTransferFromToRevertingERC721RecipientWithData()
        public
    {
        token.mint(address(this), incr(address(this)));

        token.safeTransferFrom(
            address(this),
            revertingRecipient,
            1,
            "testing 123"
        );
    }

    function testFailSafeTransferFromToERC721RecipientWithWrongReturnData()
        public
    {
        token.mint(address(this), incr(address(this)));

        token.safeTransferFrom(
            address(this),
            wrongReturnDataRecipient,
            1
        );
    }

    function testFailSafeTransferFromToERC721RecipientWithWrongReturnDataWithData()
        public
    {
        token.mint(address(this), incr(address(this)));

        token.safeTransferFrom(
            address(this),
            wrongReturnDataRecipient,
            1,
            "testing 123"
        );
    }

    function testFailSafeMintToNonERC721Recipient() public {
        address to = nonRecipient;
        token.safeMint(to, incr(to));
    }

    function testFailSafeMintToNonERC721RecipientWithData() public {
        address to = nonRecipient;
        token.safeMint(
            nonRecipient,
            incr(to),
            "testing 123"
        );
    }

    function testFailSafeMintToRevertingERC721Recipient() public {
        address to = revertingRecipient;
        token.safeMint(to, incr(to));
    }

    function testFailSafeMintToRevertingERC721RecipientWithData() public {
        address to = revertingRecipient;
        token.safeMint(to, incr(to), "testing 123");
    }

    function testFailSafeMintToERC721RecipientWithWrongReturnData() public {
        address to = wrongReturnDataRecipient;
        token.safeMint(to, incr(to));
    }

    function testFailSafeMintToERC721RecipientWithWrongReturnDataWithData()
        public
    {
        address to = wrongReturnDataRecipient;
        token.safeMint(to, incr(to), "testing 123");
    }

    function testFailBalanceOfZeroAddress() public view {
        token.balanceOf(address(0));
    }

    function testFailOwnerOfUnminted() public view {
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

        token.mint(to1, to2);
        assertEq(token.ownerOf(1), to1);
        assertEq(token.ownerOf(2), to2);
        assertEq(token.balanceOf(to1), 1);
        assertEq(token.balanceOf(to2), 1);
    }

    function testBurn(address to) public {
        vm.assume(to != address(0));

        token.mint(to);

        vm.prank(to);
        token.burn(1);

        assertEq(token.balanceOf(to), 0);

        assertEq(token.ownerOf(1), address(0xdead));
    }

    function testApprove(address to) public {
        token.mint(address(this));

        token.approve(to, 1);

        assertEq(token.getApproved(1), to);
    }

    function testApproveBurn(address to) public {
        vm.assume(to != address(0));

        token.mint(address(this));
        token.approve(address(to), 1);
        token.burn(1);

        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.getApproved(1), address(0));

        assertEq(token.ownerOf(1), address(0xdead));
    }

    function testApproveAll(address to, bool approved) public {
        token.setApprovalForAll(to, approved);

        assertEq(token.isApprovedForAll(address(this), to), approved);
    }

    function testTransferFrom(address from, address to) public {
        vm.assume(address(0) < from);
        vm.assume(from < address(this));

        if (to == address(0) || to == from || to == address(this)) to = address(0xBEEF);

        token.mint(from, address(this));

        vm.prank(from);
        token.approve(address(this), 1);

        token.transferFrom(from, to, 1);

        assertEq(token.getApproved(1), address(0));
        assertEq(token.ownerOf(1), to);
        assertEq(token.balanceOf(to), 1);
        assertEq(token.balanceOf(from), 0);
    }

    function testTransferFromSelf(address to) public {
        if (to == address(0) || to == address(this)) to = address(0xBEEF);

        token.mint(address(this), incr(address(this)));

        token.transferFrom(address(this), to, 1);

        assertEq(token.getApproved(1), address(0));
        assertEq(token.ownerOf(1), to);
        assertEq(token.balanceOf(to), 1);
        assertEq(token.balanceOf(address(this)), 0);
    }

    function testTransferFromApproveAll(address from, address to) public {
        vm.assume(address(0) < from);
        vm.assume(from < address(this));

        if (to == address(0) || to == from || to == address(this)) to = address(0xBEEF);

        token.mint(from, address(this));

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
        vm.assume(to.code.length == 0);
        vm.assume(to != address(0));
        vm.assume(to != from);

        token.mint(from);

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

    function testSafeTransferFromToERC721RecipientWithData(
        address from,
        bytes calldata data
    ) public {
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

        token.safeMint(to);

        assertEq(token.ownerOf(1), to);
        assertEq(token.balanceOf(to), 1);
    }

    function testSafeMintToERC721RecipientWithData(bytes calldata data) public {
        ERC721Recipient to = ERC721Recipient(happyRecipient);

        token.safeMint(address(to), incr(address(to)), data);

        assertEq(token.ownerOf(1), address(to));
        assertEq(token.balanceOf(address(to)), 1);

        assertEq(to.operator(), address(this));
        assertEq(to.from(), address(0));
        assertEq(to.id(), 1);
        assertEq(to.data(), data);
    }

    function testFailDoubleMint(address to) public {
        vm.assume(to > address(0));

        token.mint(to, to);
    }

    function testFailBurnUnMinted(uint256 id) public {
        token.burn(id);
    }

    function testFailDoubleBurn(address to) public {
        vm.assume(to > address(0));

        token.mint(to, incr(to));

        token.burn(1);
        token.burn(1);
    }

    function testFailApproveUnMinted(uint256 id, address to) public {
        token.approve(to, id);
    }

    function testFailApproveUnAuthorized(address owner, address to) public {
        vm.assume(owner > address(0));
        vm.assume(owner != address(this));

        token.mint(owner, incr(owner));

        token.approve(to, 1);
    }

    function testFailTransferFromUnOwned(
        address from,
        address to,
        uint256 id
    ) public {
        token.transferFrom(from, to, id);
    }

    function testFailTransferFromWrongFrom(
        address owner,
        address from,
        address to
    ) public {
        if (owner == address(0)) to = address(0xBEEF);
        if (from == owner) revert();

        token.mint(owner, incr(owner));

        token.transferFrom(from, to, 1);
    }

    function testFailTransferFromNotOwner(address from, address to) public {
        if (from == address(this)) from = address(0xBEEF);

        token.mint(from, incr(from));

        token.transferFrom(from, to, 1);
    }

    function testFailSafeTransferFromToNonERC721RecipientWithData(
        bytes calldata data
    ) public {
        token.mint(address(this), incr(address(this)));

        token.safeTransferFrom(
            address(this),
            nonRecipient,
            1,
            data
        );
    }

    function testFailSafeTransferFromToRevertingERC721RecipientWithData(
        bytes calldata data
    ) public {
        token.mint(address(this), incr(address(this)));

        token.safeTransferFrom(
            address(this),
            revertingRecipient,
            1,
            data
        );
    }

    function testFailSafeTransferFromToERC721RecipientWithWrongReturnDataWithData(
        bytes calldata data
    ) public {
        token.mint(address(this), incr(address(this)));

        token.safeTransferFrom(
            address(this),
            wrongReturnDataRecipient,
            1,
            data
        );
    }

    function testFailSafeMintToNonERC721RecipientWithData(bytes calldata data)
        public
    {
        address to = nonRecipient;
        token.safeMint(to, incr(to), data);
    }

    function testFailSafeMintToRevertingERC721RecipientWithData(
        bytes calldata data
    ) public {
        address to = revertingRecipient;
        token.safeMint(to, incr(to), data);
    }

    function testFailSafeMintToERC721RecipientWithWrongReturnDataWithData(
        bytes calldata data
    ) public {
        address to = wrongReturnDataRecipient;
        token.safeMint(to, incr(to), data);
    }

    function testFailOwnerOfUnminted(uint256 id) public view {
        token.ownerOf(id);
    }
}
