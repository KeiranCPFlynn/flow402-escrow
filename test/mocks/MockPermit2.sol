// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "../../src/interfaces/IPermit2.sol";

interface IERC20Minimal {
    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) external returns (bool);
}

/// @notice Lightweight Permit2 mock used for tests (no signature validation).
contract MockPermit2 is IPermit2 {
    event PermitTransfer(
        address indexed owner,
        address indexed token,
        address indexed to,
        uint256 amount
    );

    function permitTransferFrom(
        PermitTransferFrom calldata permit,
        SignatureTransferDetails calldata transferDetails,
        address owner,
        bytes calldata /*signature*/
    ) external override {
        if (transferDetails.to == address(0)) revert("Permit2: invalid to");
        if (permit.permitted.token == address(0))
            revert("Permit2: invalid token");
        if (transferDetails.requestedAmount == 0)
            revert("Permit2: zero amount");
        if (transferDetails.requestedAmount > permit.permitted.amount)
            revert("Permit2: exceeds permitted");

        IERC20Minimal(permit.permitted.token).transferFrom(
            owner,
            transferDetails.to,
            transferDetails.requestedAmount
        );
        emit PermitTransfer(
            owner,
            permit.permitted.token,
            transferDetails.to,
            transferDetails.requestedAmount
        );
    }

    function transferFrom(
        address from,
        address to,
        uint160 amount,
        address token
    ) external override {
        if (to == address(0)) revert("Permit2: invalid to");
        if (token == address(0)) revert("Permit2: invalid token");
        if (amount == 0) revert("Permit2: zero amount");

        IERC20Minimal(token).transferFrom(from, to, amount);
    }
}
