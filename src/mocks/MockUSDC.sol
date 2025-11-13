// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";

contract MockUSDC is ERC20 {
    constructor() ERC20("Mock USDC", "mUSDC") {}

    // 6 decimals like real USDC
    function decimals() public pure override returns (uint8) {
        return 6;
    }

    // Mint function so we can give ourselves tokens on local testnet
    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}
