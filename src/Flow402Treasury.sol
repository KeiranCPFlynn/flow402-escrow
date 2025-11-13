// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20Permit} from "./interfaces/IERC20Permit.sol";
import {IPermit2} from "./interfaces/IPermit2.sol";

/// @notice Minimal ERC-20 interface
interface IERC20 {
    function balanceOf(address account) external view returns (uint256);

    function transfer(address to, uint256 value) external returns (bool);

    function transferFrom(
        address from,
        address to,
        uint256 value
    ) external returns (bool);
}

/// @notice Lightweight SafeERC20
library SafeERC20 {
    error SafeERC20FailedOperation();

    function safeTransfer(IERC20 token, address to, uint256 value) internal {
        _callOptionalReturn(
            token,
            abi.encodeWithSelector(token.transfer.selector, to, value)
        );
    }

    function safeTransferFrom(
        IERC20 token,
        address from,
        address to,
        uint256 value
    ) internal {
        _callOptionalReturn(
            token,
            abi.encodeWithSelector(token.transferFrom.selector, from, to, value)
        );
    }

    function _callOptionalReturn(IERC20 token, bytes memory data) private {
        (bool success, bytes memory returndata) = address(token).call(data);
        if (!success) {
            if (returndata.length == 0) revert SafeERC20FailedOperation();
            assembly {
                revert(add(32, returndata), mload(returndata))
            }
        }
        if (returndata.length > 0 && !abi.decode(returndata, (bool))) {
            revert SafeERC20FailedOperation();
        }
    }
}

/// @notice Simple ownership
abstract contract Ownable {
    error Unauthorized();
    address public owner;
    event OwnershipTransferred(
        address indexed previousOwner,
        address indexed newOwner
    );

    modifier onlyOwner() {
        if (msg.sender != owner) revert Unauthorized();
        _;
    }

    constructor(address initialOwner) {
        owner = initialOwner;
        emit OwnershipTransferred(address(0), initialOwner);
    }

    function transferOwnership(address newOwner) external onlyOwner {
        if (newOwner == address(0)) revert Unauthorized();
        emit OwnershipTransferred(owner, newOwner);
        owner = newOwner;
    }
}

/// @notice Reentrancy guard
abstract contract ReentrancyGuard {
    error Reentrancy();
    uint256 private constant _NOT_ENTERED = 1;
    uint256 private constant _ENTERED = 2;
    uint256 private _status = _NOT_ENTERED;

    modifier nonReentrant() {
        if (_status == _ENTERED) revert Reentrancy();
        _status = _ENTERED;
        _;
        _status = _NOT_ENTERED;
    }
}

/// @title Flow402Treasury
/// @notice Non-custodial treasury for Flow402 credit system (MVP)
/// @dev Users deposit with spending limits; gateway settles in batches
contract Flow402Treasury is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    error InvalidAddress();
    error InvalidAmount();
    error InsufficientBalance();
    error ExceedsSpendingLimit();
    error SettlementsPaused();

    IERC20 public immutable usdc;
    address public gateway;
    bool public settlementsPaused;

    address public constant PERMIT2 =
        0x000000000022D473030F116dDEE9F6B43aC78BA3;

    // Fee taken at deposit (1% default)
    uint96 public feeBps = 100; // 1% = 100 basis points
    uint256 public constant BPS_DENOMINATOR = 10_000;
    uint96 public constant MAX_FEE_BPS = 500; // Max 5%

    // User balances (net of deposit fee)
    mapping(address => uint256) public userDeposits;

    // User spending limits (user-controlled safety)
    mapping(address => uint256) public userSpendingLimit;

    // Vendor claimable earnings
    mapping(address => uint256) public vendorPending;

    // Protocol accumulated fees
    uint256 public protocolFees;

    event UserDeposit(
        address indexed user,
        uint256 netAmount,
        uint256 fee,
        uint256 spendingLimit
    );
    event SpendingLimitUpdated(address indexed user, uint256 newLimit);
    event Settlement(
        address indexed user,
        address indexed vendor,
        uint256 amount
    );
    event UserWithdrawal(address indexed user, uint256 amount);
    event VendorWithdrawal(address indexed vendor, uint256 amount);
    event ProtocolFeeWithdrawal(address indexed recipient, uint256 amount);
    event GatewayUpdated(address indexed newGateway);
    event SettlementsPausedUpdated(bool paused);
    event FeeUpdated(uint96 feeBps);

    modifier onlyGateway() {
        if (msg.sender != gateway) revert Unauthorized();
        _;
    }

    modifier whenNotPaused() {
        if (settlementsPaused) revert SettlementsPaused();
        _;
    }

    constructor(IERC20 _usdc, address _gateway) Ownable(msg.sender) {
        if (address(_usdc) == address(0) || _gateway == address(0))
            revert InvalidAddress();
        usdc = _usdc;
        gateway = _gateway;
    }

    /// @notice User deposits USDC and sets spending limit
    /// @param amount Gross USDC amount (before fee)
    /// @param spendingLimit Max amount per settlement batch (safety limit)
    function deposit(uint256 amount, uint256 spendingLimit) external {
        if (amount == 0 || spendingLimit == 0) revert InvalidAmount();

        usdc.safeTransferFrom(msg.sender, address(this), amount);
        _afterFundsArrived(msg.sender, amount, spendingLimit);
    }

    /// @notice Gasless deposit using EIP-2612 permit
    /// @param user User address (from permit signature)
    /// @param amount Gross USDC amount (before fee)
    /// @param spendingLimit Max amount per settlement batch
    /// @param deadline Permit signature deadline
    /// @param v Signature v
    /// @param r Signature r
    /// @param s Signature s
    function depositWithPermit(
        address user,
        uint256 amount,
        uint256 spendingLimit,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external {
        if (amount == 0 || spendingLimit == 0) revert InvalidAmount();

        // Execute permit (user signed approval off-chain)
        IERC20Permit(address(usdc)).permit(
            user,
            address(this),
            amount,
            deadline,
            v,
            r,
            s
        );

        // Now deposit on behalf of user
        usdc.safeTransferFrom(user, address(this), amount);
        _afterFundsArrived(user, amount, spendingLimit);
    }

    /// @notice Gasless deposit path using Permit2 signature transfers
    function depositWithPermit2(
        address user,
        uint256 amount,
        uint256 spendingLimit,
        IPermit2.PermitTransferFrom calldata permit,
        IPermit2.SignatureTransferDetails calldata transferDetails,
        bytes calldata signature
    ) external nonReentrant {
        if (amount == 0 || spendingLimit == 0) revert InvalidAmount();
        if (transferDetails.to != address(this)) revert InvalidAddress();
        if (permit.permitted.token != address(usdc)) revert InvalidAddress();
        if (transferDetails.requestedAmount != amount) revert InvalidAmount();
        if (permit.deadline < block.timestamp) revert InvalidAmount();

        IPermit2(PERMIT2).permitTransferFrom(
            permit,
            transferDetails,
            user,
            signature
        );
        _afterFundsArrived(user, amount, spendingLimit);
    }

    /// @notice Internal accounting for deposit flows once funds are held by treasury
    function _afterFundsArrived(
        address user,
        uint256 amount,
        uint256 spendingLimit
    ) internal {
        // Take fee at deposit (upfront, simple)
        uint256 fee = (amount * feeBps) / BPS_DENOMINATOR;
        uint256 netAmount = amount - fee;

        // Credit user net amount
        userDeposits[user] += netAmount;
        userSpendingLimit[user] = spendingLimit;
        protocolFees += fee;

        emit UserDeposit(user, netAmount, fee, spendingLimit);
    }

    /// @notice User updates their spending limit
    /// @dev Set to 0 for emergency stop, increase to allow more spending
    function setSpendingLimit(uint256 newLimit) external {
        userSpendingLimit[msg.sender] = newLimit;
        emit SpendingLimitUpdated(msg.sender, newLimit);
    }

    /// @notice Gateway settles batch of payments (daily/weekly)
    /// @dev No additional fee - already taken at deposit
    function batchSettle(
        address[] calldata users,
        address[] calldata vendors,
        uint256[] calldata amounts
    ) external onlyGateway whenNotPaused {
        uint256 len = users.length;
        if (len != vendors.length || len != amounts.length)
            revert InvalidAmount();

        for (uint256 i = 0; i < len; i++) {
            _settlePayment(users[i], vendors[i], amounts[i]);
        }
    }

    /// @notice Internal settlement logic
    function _settlePayment(
        address user,
        address vendor,
        uint256 amount
    ) internal {
        if (amount == 0) return;
        if (user == address(0) || vendor == address(0)) revert InvalidAddress();

        // Check user has sufficient balance
        if (userDeposits[user] < amount) revert InsufficientBalance();

        // Check within spending limit (user-controlled safety)
        if (amount > userSpendingLimit[user]) revert ExceedsSpendingLimit();

        // Move funds: user deposit → vendor pending
        // No additional fee (already taken at deposit)
        userDeposits[user] -= amount;
        vendorPending[vendor] += amount;

        emit Settlement(user, vendor, amount);
    }

    /// @notice User withdraws unused balance
    function withdrawUser(uint256 amount) external nonReentrant {
        if (amount == 0) revert InvalidAmount();
        if (userDeposits[msg.sender] < amount) revert InsufficientBalance();

        userDeposits[msg.sender] -= amount;
        usdc.safeTransfer(msg.sender, amount);

        emit UserWithdrawal(msg.sender, amount);
    }

    /// @notice Vendor withdraws earned balance
    function withdrawVendor(uint256 amount) external nonReentrant {
        if (amount == 0) revert InvalidAmount();
        if (vendorPending[msg.sender] < amount) revert InsufficientBalance();

        vendorPending[msg.sender] -= amount;
        usdc.safeTransfer(msg.sender, amount);

        emit VendorWithdrawal(msg.sender, amount);
    }

    /// @notice Owner withdraws protocol fees
    function withdrawProtocolFees(
        uint256 amount
    ) external onlyOwner nonReentrant {
        if (amount == 0) revert InvalidAmount();
        if (protocolFees < amount) revert InsufficientBalance();

        protocolFees -= amount;
        usdc.safeTransfer(owner, amount);

        emit ProtocolFeeWithdrawal(owner, amount);
    }

    /// @notice Update gateway address (emergency only)
    function setGateway(address newGateway) external onlyOwner {
        if (newGateway == address(0)) revert InvalidAddress();
        gateway = newGateway;
        emit GatewayUpdated(newGateway);
    }

    /// @notice Pause/unpause settlements (emergency)
    function setSettlementsPaused(bool paused) external onlyOwner {
        settlementsPaused = paused;
        emit SettlementsPausedUpdated(paused);
    }

    /// @notice Update fee (capped at MAX_FEE_BPS)
    function setFeeBps(uint96 newFeeBps) external onlyOwner {
        if (newFeeBps > MAX_FEE_BPS) revert InvalidAmount();
        feeBps = newFeeBps;
        emit FeeUpdated(newFeeBps);
    }

    /// @notice View total USDC reserves
    function totalReserves() external view returns (uint256) {
        return usdc.balanceOf(address(this));
    }

    /// @notice Check if user can spend amount (within balance and limit)
    function canUserSpend(
        address user,
        uint256 amount
    ) external view returns (bool) {
        return
            userDeposits[user] >= amount && userSpendingLimit[user] >= amount;
    }
}
