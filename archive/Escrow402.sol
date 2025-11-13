// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @notice Minimal ERC-20 interface (subset used by escrow)
interface IERC20 {
    function totalSupply() external view returns (uint256);

    function balanceOf(address account) external view returns (uint256);

    function allowance(
        address owner,
        address spender
    ) external view returns (uint256);

    function transfer(address to, uint256 value) external returns (bool);

    function approve(address spender, uint256 value) external returns (bool);

    function transferFrom(
        address from,
        address to,
        uint256 value
    ) external returns (bool);

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(
        address indexed owner,
        address indexed spender,
        uint256 value
    );
}

/// @notice Lightweight SafeERC20 clone to avoid pulling full OZ dependency.
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
            _revertWithData(returndata);
        }
        if (returndata.length > 0 && !abi.decode(returndata, (bool))) {
            revert SafeERC20FailedOperation();
        }
    }

    function _revertWithData(bytes memory returndata) private pure {
        if (returndata.length == 0) revert SafeERC20FailedOperation();
        /// @solidity memory-safe-assembly
        assembly {
            revert(add(32, returndata), mload(returndata))
        }
    }
}

/// @notice Simple ownership helper.
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

/// @notice Reentrancy guard modeled after OZ's implementation.
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

/// @title Escrow402
/// @notice Minimal non-custodial USDC escrow for Flow402 vendors.
contract Escrow402 is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    error InvalidAddress();
    error InvalidFee();
    error ZeroAmount();
    error InsufficientBalance();

    uint96 public constant MAX_FEE_BPS = 500;
    uint256 public constant BPS_DENOMINATOR = 10_000;

    IERC20 public immutable usdc;
    address public feeRecipient;
    uint96 public feeBps;

    mapping(address => uint256) public vendorBalances;

    event Deposited(
        address indexed payer,
        address indexed vendor,
        uint256 netAmount,
        uint256 feeAmount
    );
    event Withdrawn(address indexed vendor, uint256 amount);
    event FeeUpdated(uint96 feeBps);
    event FeeRecipientUpdated(address feeRecipient);

    constructor(
        IERC20 _usdc,
        address _feeRecipient,
        uint96 _feeBps
    ) Ownable(msg.sender) {
        if (address(_usdc) == address(0) || _feeRecipient == address(0))
            revert InvalidAddress();
        if (_feeBps > MAX_FEE_BPS) revert InvalidFee();

        usdc = _usdc;
        feeRecipient = _feeRecipient;
        feeBps = _feeBps;
    }

    /// @notice Deposits USDC on behalf of a vendor and routes the fee.
    function depositFor(address vendor, uint256 amount) external {
        if (vendor == address(0)) revert InvalidAddress();
        if (amount == 0) revert ZeroAmount();

        usdc.safeTransferFrom(msg.sender, address(this), amount);

        uint256 fee = (amount * feeBps) / BPS_DENOMINATOR;
        uint256 netAmount = amount - fee;

        vendorBalances[vendor] += netAmount;

        if (fee > 0) {
            usdc.safeTransfer(feeRecipient, fee);
        }

        emit Deposited(msg.sender, vendor, netAmount, fee);
    }

    /// @notice Withdraws previously credited funds for the caller (vendor).
    function withdraw(uint256 amount) external nonReentrant {
        if (amount == 0) revert ZeroAmount();
        uint256 balance = vendorBalances[msg.sender];
        if (balance < amount) revert InsufficientBalance();

        vendorBalances[msg.sender] = balance - amount;
        usdc.safeTransfer(msg.sender, amount);

        emit Withdrawn(msg.sender, amount);
    }

    /// @notice Updates the fee recipient address.
    function setFeeRecipient(address newRecipient) external onlyOwner {
        if (newRecipient == address(0)) revert InvalidAddress();
        feeRecipient = newRecipient;
        emit FeeRecipientUpdated(newRecipient);
    }

    /// @notice Updates the fee (in basis points) capped at MAX_FEE_BPS.
    function setFeeBps(uint96 newFeeBps) external onlyOwner {
        if (newFeeBps > MAX_FEE_BPS) revert InvalidFee();
        feeBps = newFeeBps;
        emit FeeUpdated(newFeeBps);
    }
}
