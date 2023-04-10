// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import "forge-std/Script.sol";
import {StdAssertions} from "forge-std/StdAssertions.sol";

import {Addresses} from "test/helpers/Addresses.sol";
import {BasicSS2ERC721} from "test/SS2ERC721Basics.t.sol";

contract BasicERC721Script is Script, StdAssertions {
    string internal constant ANVIL_MNEMONIC = "test test test test test test test test test test test junk";

    // can deploy with
    //   forge script script/BasicSS2ERC721.s.sol --rpc-url anvil --broadcast
    function run() public {
        string memory mnemonic = vm.envOr("MNEMONIC", ANVIL_MNEMONIC);
        uint256 deployerPK = vm.deriveKey(mnemonic, uint32(0));
        address deployer = vm.addr(deployerPK);
        console2.log("deployer address:", deployer);

        vm.startBroadcast(deployerPK);
        BasicSS2ERC721 mint1 = new BasicSS2ERC721("mint1", unicode"✌️");
        BasicSS2ERC721 mint10 = new BasicSS2ERC721("mint10", unicode"✌️");
        BasicSS2ERC721 mint100 = new BasicSS2ERC721("mint100", unicode"✌️");
        BasicSS2ERC721 mint1000 = new BasicSS2ERC721("mint1000", unicode"✌️");
        BasicSS2ERC721 mintMAX = new BasicSS2ERC721("mintMAX", unicode"✌️");

        // gas used 84362
        assertEq(mint1.mint(Addresses.make(1)), 1);

        // gas used 142489
        assertEq(mint10.mint(Addresses.make(10)), 10);

        // gas used 722765
        assertEq(mint100.mint(Addresses.make(100)), 100);

        // gas used 6537658
        assertEq(mint1000.mint(Addresses.make(1000)), 1000);

        // gas used 8014192
        // cost per mint 8014192/1228 = 6526
        assertEq(mintMAX.mint(Addresses.make(1228)), 1228);

        vm.stopBroadcast();
    }
}
