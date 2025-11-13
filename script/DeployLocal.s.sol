// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/Flow402Treasury.sol";

contract DeployLocal is Script {
    function run() external {
        // Load from .env (your cycle script will set these)
        address usdc = vm.envAddress("USDC_ADDRESS");
        address gateway = vm.envAddress("GATEWAY_ADDRESS");
        uint256 deployerPk = vm.envUint("DEPLOYER_PK");

        console.log("Deploying Flow402Treasury with:");
        console.log("  USDC:    ", usdc);
        console.log("  Gateway: ", gateway);

        vm.startBroadcast(deployerPk);
        Flow402Treasury treasury = new Flow402Treasury(IERC20(usdc), gateway);
        vm.stopBroadcast();

        console.log("Treasury deployed at:", address(treasury));
    }
}
