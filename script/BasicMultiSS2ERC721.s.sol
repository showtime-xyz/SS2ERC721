// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import "forge-std/Script.sol";
import {StdAssertions} from "forge-std/StdAssertions.sol";

import {Addresses} from "test/helpers/Addresses.sol";
import {BasicMultiSS2ERC721} from "test/helpers/BasicMultiSS2ERC721.sol";

contract BasicERC721Script is Script, StdAssertions {
    string internal constant ANVIL_MNEMONIC = "test test test test test test test test test test test junk";

    function mint(BasicMultiSS2ERC721 token, uint256 count) public returns (uint256 numMinted) {
        uint256 batchNum = 0;
        while (count > 0) {
            batchNum++;

            uint256 batchSize = count / 1228 > 0 ? 1228 : count % 1228;
            count -= batchSize;

            console2.log("sending batch", batchNum, "with size", batchSize);

            numMinted += token.mint(Addresses.make(address(uint160(numMinted) + 1), batchSize));
        }
    }

    // can deploy with
    //   forge script script/BasicSS2ERC721.s.sol --rpc-url anvil --broadcast
    function run() public {
        string memory mnemonic = vm.envOr("MNEMONIC", ANVIL_MNEMONIC);
        uint256 deployerPK = vm.envOr("PRIVATE_KEY", vm.deriveKey(mnemonic, uint32(0)));
        address deployer = vm.addr(deployerPK);
        console2.log("deployer address:", deployer);

        vm.startBroadcast(deployerPK);
        BasicMultiSS2ERC721 token = new BasicMultiSS2ERC721("aaahh I'm batching", unicode"✌️");

        // gas used 6255964
        // assertEq(mint(mint1000, 1000), 1000);

        // 8 full batches of 1228 tokens + 1 batch of 176 tokens
        // gas used 7660933 + 7652066 + 7652066 + 7652066 + 7652078 + 7652066 + 7652066 + 7652066 + 1171038 = 62396445
        // cost per mint = 6240
        assertEq(mint(token, 10000), 10000);

        vm.stopBroadcast();
    }
}
