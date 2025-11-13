// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "../src/Flow402Treasury.sol";

contract DeployFlow402Treasury is Script {
    function run() external returns (Flow402Treasury treasury) {
        address usdc = vm.envAddress("USDC_ADDRESS");
        address gateway = vm.envAddress("GATEWAY_ADDRESS");
        uint96 feeBps = uint96(vm.envUint("FEE_BPS"));
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        string memory commit = vm.envString("GIT_COMMIT");

        vm.startBroadcast(deployerKey);
        treasury = new Flow402Treasury(IERC20(usdc), gateway);
        if (feeBps != treasury.feeBps()) {
            treasury.setFeeBps(feeBps);
        }
        vm.stopBroadcast();

        console.log("Flow402Treasury deployed at", address(treasury));
        console.log("USDC:", usdc);
        console.log("Gateway:", gateway);
        console.log("Fee BPS:", treasury.feeBps());

        string memory json = string(
            abi.encodePacked(
                '{"address":"',
                vm.toString(address(treasury)),
                '","chainId":',
                vm.toString(block.chainid),
                ',"block":',
                vm.toString(block.number),
                ',"commit":"',
                commit,
                '"}'
            )
        );

        vm.createDir("deployments", true);
        vm.writeFile("deployments/base-sepolia.json", json);
    }
}
