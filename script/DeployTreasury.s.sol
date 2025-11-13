// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Script.sol";
import "../src/Flow402Treasury.sol";

contract DeployTreasury is Script {
    function run() external {
        address usdc = 0x5FbDB2315678afecb367f032d93F642f64180aa3; // your USDC address
        address gateway = 0xe7f1725E7734CE288F8367e1Bb143E90bb3F0512; // your gateway address

        vm.startBroadcast(
            0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
        );
        Flow402Treasury treasury = new Flow402Treasury(IERC20(usdc), gateway);
        vm.stopBroadcast();

        console.log("Treasury deployed at:", address(treasury));
    }
}
