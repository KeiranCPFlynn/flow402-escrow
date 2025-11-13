// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../src/Flow402Treasury.sol";
import "../src/interfaces/IPermit2.sol";
import "../src/interfaces/IERC20Permit.sol";
import "./mocks/MockPermit2.sol";

contract MockUSDCWithPermit is IERC20Permit {
    string public constant name = "Mock USDC";
    string public constant symbol = "mUSDC";
    uint8 public constant decimals = 6;

    uint256 public totalSupply;
    mapping(address => uint256) private _balances;
    mapping(address => mapping(address => uint256)) public allowance;
    mapping(address => uint256) public override nonces;
    bytes32 public override DOMAIN_SEPARATOR;

    event Transfer(address indexed from, address indexed to, uint256 amount);
    event Approval(address indexed owner, address indexed spender, uint256 amount);

    constructor() {
        uint256 chainId;
        assembly {
            chainId := chainid()
        }
        DOMAIN_SEPARATOR = keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256(bytes(name)),
                keccak256(bytes("1")),
                chainId,
                address(this)
            )
        );
    }

    function mint(address to, uint256 amount) external {
        _balances[to] += amount;
        totalSupply += amount;
        emit Transfer(address(0), to, amount);
    }

    function balanceOf(address account) external view returns (uint256) {
        return _balances[account];
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        _transfer(msg.sender, to, amount);
        return true;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        uint256 currentAllowance = allowance[from][msg.sender];
        if (currentAllowance != type(uint256).max) {
            require(currentAllowance >= amount, "allowance");
            allowance[from][msg.sender] = currentAllowance - amount;
        }
        _transfer(from, to, amount);
        return true;
    }

    function permit(
        address owner,
        address spender,
        uint256 value,
        uint256 deadline,
        uint8, /*v*/
        bytes32, /*r*/
        bytes32 /*s*/
    ) external override {
        if (deadline < block.timestamp) revert("permit expired");
        nonces[owner]++;
        allowance[owner][spender] = value;
        emit Approval(owner, spender, value);
    }

    function _transfer(address from, address to, uint256 amount) internal {
        require(_balances[from] >= amount, "balance");
        _balances[from] -= amount;
        _balances[to] += amount;
        emit Transfer(from, to, amount);
    }
}

contract Flow402TreasuryTest is Test {
    Flow402Treasury internal treasury;
    MockUSDCWithPermit internal usdc;
    address internal gateway = address(0xA11CE);
    address internal user = address(0xBEEF);
    address internal vendor = address(0xC0FFEE);

    function setUp() external {
        usdc = new MockUSDCWithPermit();
        treasury = new Flow402Treasury(IERC20(address(usdc)), gateway);

        // Deploy mock Permit2 at the canonical address
        MockPermit2 permit2 = new MockPermit2();
        vm.etch(treasury.PERMIT2(), address(permit2).code);
    }

    function testDepositUpdatesState() external {
        uint256 amount = 1_000e6;
        uint256 spendingLimit = amount / 2;
        _mintAndApprove(user, amount, address(treasury));

        uint256 fee = (amount * treasury.feeBps()) / treasury.BPS_DENOMINATOR();
        uint256 net = amount - fee;

        vm.expectEmit(true, false, false, true, address(treasury));
        emit Flow402Treasury.UserDeposit(user, net, fee, spendingLimit);

        vm.prank(user);
        treasury.deposit(amount, spendingLimit);

        assertEq(treasury.userDeposits(user), net);
        assertEq(treasury.protocolFees(), fee);
        assertEq(treasury.userSpendingLimit(user), spendingLimit);
    }

    function testDepositWithPermit() external {
        uint256 amount = 500e6;
        uint256 spendingLimit = amount;
        usdc.mint(user, amount);

        uint256 fee = (amount * treasury.feeBps()) / treasury.BPS_DENOMINATOR();
        uint256 net = amount - fee;

        uint256 deadline = block.timestamp + 1 days;
        vm.expectEmit(true, false, false, true, address(treasury));
        emit Flow402Treasury.UserDeposit(user, net, fee, spendingLimit);

        treasury.depositWithPermit(
            user,
            amount,
            spendingLimit,
            deadline,
            0,
            bytes32(0),
            bytes32(0)
        );

        assertEq(treasury.userDeposits(user), net);
        assertEq(usdc.allowance(user, address(treasury)), 0);
    }

    function testDepositWithPermit2() external {
        uint256 amount = 750e6;
        uint256 spendingLimit = amount;
        _mintAndApprove(user, amount, treasury.PERMIT2());

        IPermit2.PermitTransferFrom memory permit = IPermit2.PermitTransferFrom({
            permitted: IPermit2.TokenPermissions({token: address(usdc), amount: amount}),
            nonce: 0,
            deadline: block.timestamp + 1 days
        });
        IPermit2.SignatureTransferDetails memory details = IPermit2.SignatureTransferDetails({
            to: address(treasury),
            requestedAmount: amount
        });

        uint256 fee = (amount * treasury.feeBps()) / treasury.BPS_DENOMINATOR();
        uint256 net = amount - fee;
        vm.expectEmit(true, false, false, true, address(treasury));
        emit Flow402Treasury.UserDeposit(user, net, fee, spendingLimit);

        treasury.depositWithPermit2(
            user,
            amount,
            spendingLimit,
            permit,
            details,
            hex""
        );

        assertEq(treasury.userDeposits(user), net);
        assertEq(treasury.protocolFees(), fee);
    }

    function testDepositWithPermit2RevertsForBadRecipient() external {
        uint256 amount = 100e6;
        _mintAndApprove(user, amount, treasury.PERMIT2());
        IPermit2.PermitTransferFrom memory permit = IPermit2.PermitTransferFrom({
            permitted: IPermit2.TokenPermissions({token: address(usdc), amount: amount}),
            nonce: 0,
            deadline: block.timestamp + 1 days
        });
        IPermit2.SignatureTransferDetails memory details = IPermit2.SignatureTransferDetails({
            to: address(0),
            requestedAmount: amount
        });

        vm.expectRevert(Flow402Treasury.InvalidAddress.selector);
        treasury.depositWithPermit2(
            user,
            amount,
            amount,
            permit,
            details,
            hex""
        );
    }

    function testDepositWithPermit2RevertsForWrongToken() external {
        uint256 amount = 100e6;
        _mintAndApprove(user, amount, treasury.PERMIT2());
        IPermit2.PermitTransferFrom memory permit = IPermit2.PermitTransferFrom({
            permitted: IPermit2.TokenPermissions({token: address(0x1234), amount: amount}),
            nonce: 0,
            deadline: block.timestamp + 1 days
        });
        IPermit2.SignatureTransferDetails memory details = IPermit2.SignatureTransferDetails({
            to: address(treasury),
            requestedAmount: amount
        });

        vm.expectRevert(Flow402Treasury.InvalidAddress.selector);
        treasury.depositWithPermit2(
            user,
            amount,
            amount,
            permit,
            details,
            hex""
        );
    }

    function testDepositRevertsWhenTokenRevertsNoData() external {
        FaultyERC20 token = new FaultyERC20();
        Flow402Treasury badTreasury = new Flow402Treasury(IERC20(address(token)), gateway);
        token.setFailure(FaultyERC20.Failure.RevertNoData);

        vm.prank(user);
        vm.expectRevert(SafeERC20.SafeERC20FailedOperation.selector);
        badTreasury.deposit(1, 1);
    }

    function testDepositRevertsWhenTokenRevertsWithMessage() external {
        FaultyERC20 token = new FaultyERC20();
        Flow402Treasury badTreasury = new Flow402Treasury(IERC20(address(token)), gateway);
        token.setFailure(FaultyERC20.Failure.RevertWithMessage);

        vm.prank(user);
        vm.expectRevert(bytes("FAIL"));
        badTreasury.deposit(1, 1);
    }

    function testDepositRevertsWhenTokenReturnsFalse() external {
        FaultyERC20 token = new FaultyERC20();
        Flow402Treasury badTreasury = new Flow402Treasury(IERC20(address(token)), gateway);
        token.setFailure(FaultyERC20.Failure.ReturnFalse);

        vm.prank(user);
        vm.expectRevert(SafeERC20.SafeERC20FailedOperation.selector);
        badTreasury.deposit(1, 1);
    }

    function testDepositWithPermit2RevertsForExpiredDeadline() external {
        uint256 amount = 100e6;
        _mintAndApprove(user, amount, treasury.PERMIT2());
        IPermit2.PermitTransferFrom memory permit = IPermit2.PermitTransferFrom({
            permitted: IPermit2.TokenPermissions({token: address(usdc), amount: amount}),
            nonce: 0,
            deadline: block.timestamp - 1
        });
        IPermit2.SignatureTransferDetails memory details = IPermit2.SignatureTransferDetails({
            to: address(treasury),
            requestedAmount: amount
        });

        vm.expectRevert(Flow402Treasury.InvalidAmount.selector);
        treasury.depositWithPermit2(
            user,
            amount,
            amount,
            permit,
            details,
            hex""
        );
    }

    function testDepositRevertsForZeroInputs() external {
        vm.expectRevert(Flow402Treasury.InvalidAmount.selector);
        treasury.deposit(0, 1);

        vm.expectRevert(Flow402Treasury.InvalidAmount.selector);
        treasury.deposit(1, 0);
    }

    function testBatchSettleAndVendorWithdraw() external {
        uint256 amount = 1_000e6;
        uint256 spendingLimit = amount;
        _mintAndApprove(user, amount, address(treasury));
        vm.prank(user);
        treasury.deposit(amount, spendingLimit);

        address[] memory users = new address[](1);
        users[0] = user;
        address[] memory vendors = new address[](1);
        vendors[0] = vendor;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = amount / 2;

        vm.prank(gateway);
        treasury.batchSettle(users, vendors, amounts);

        assertEq(treasury.userDeposits(user), (amount - (amount * treasury.feeBps()) / treasury.BPS_DENOMINATOR()) - amounts[0]);
        assertEq(treasury.vendorPending(vendor), amounts[0]);

        vm.prank(vendor);
        treasury.withdrawVendor(amounts[0]);
        assertEq(usdc.balanceOf(vendor), amounts[0]);
        assertEq(treasury.vendorPending(vendor), 0);
    }

    function testBatchSettleRespectsSpendingLimit() external {
        uint256 amount = 500e6;
        uint256 spendingLimit = amount / 2;
        _mintAndApprove(user, amount, address(treasury));
        vm.prank(user);
        treasury.deposit(amount, spendingLimit);

        address[] memory users = new address[](1);
        users[0] = user;
        address[] memory vendors = new address[](1);
        vendors[0] = vendor;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = spendingLimit + 1;

        vm.prank(gateway);
        vm.expectRevert(Flow402Treasury.ExceedsSpendingLimit.selector);
        treasury.batchSettle(users, vendors, amounts);
    }

    function testBatchSettleRevertsWhenPaused() external {
        treasury.setSettlementsPaused(true);

        address[] memory users = new address[](1);
        users[0] = user;
        address[] memory vendors = new address[](1);
        vendors[0] = vendor;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 1;

        vm.prank(gateway);
        vm.expectRevert(Flow402Treasury.SettlementsPaused.selector);
        treasury.batchSettle(users, vendors, amounts);
    }

    function testBatchSettleLengthMismatchReverts() external {
        address[] memory users = new address[](1);
        address[] memory vendors = new address[](2);
        uint256[] memory amounts = new uint256[](1);

        vm.prank(gateway);
        vm.expectRevert(Flow402Treasury.InvalidAmount.selector);
        treasury.batchSettle(users, vendors, amounts);
    }

    function testOnlyGatewayCanSettle() external {
        address[] memory users = new address[](1);
        users[0] = user;
        address[] memory vendors = new address[](1);
        vendors[0] = vendor;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 1;

        vm.expectRevert(Ownable.Unauthorized.selector);
        treasury.batchSettle(users, vendors, amounts);
    }

    function testTransferOwnershipAndZeroAddressRevert() external {
        address newOwner = address(0x1234);
        treasury.transferOwnership(newOwner);
        assertEq(treasury.owner(), newOwner);

        vm.prank(newOwner);
        vm.expectRevert(Ownable.Unauthorized.selector);
        treasury.transferOwnership(address(0));
    }

    function testWithdrawUser() external {
        uint256 amount = 300e6;
        _mintAndApprove(user, amount, address(treasury));
        vm.prank(user);
        treasury.deposit(amount, amount);

        uint256 withdrawAmount = 100e6;
        vm.prank(user);
        treasury.withdrawUser(withdrawAmount);

        assertEq(usdc.balanceOf(user), withdrawAmount);
    }

    function testWithdrawUserRevertsInsufficientBalance() external {
        vm.prank(user);
        vm.expectRevert(Flow402Treasury.InsufficientBalance.selector);
        treasury.withdrawUser(1);
    }

    function testConstructorRevertsOnZeroAddress() external {
        vm.expectRevert(Flow402Treasury.InvalidAddress.selector);
        new Flow402Treasury(IERC20(address(0)), gateway);

        vm.expectRevert(Flow402Treasury.InvalidAddress.selector);
        new Flow402Treasury(IERC20(address(usdc)), address(0));
    }

    function testSetFeeBpsBounds() external {
        uint96 maxFee = treasury.MAX_FEE_BPS();
        treasury.setFeeBps(maxFee);

        vm.expectRevert(Flow402Treasury.InvalidAmount.selector);
        treasury.setFeeBps(maxFee + 1);
    }

    function testSetGatewayAndPause() external {
        address newGateway = address(0x123);
        treasury.setGateway(newGateway);
        assertEq(treasury.gateway(), newGateway);

        treasury.setSettlementsPaused(true);
        assertTrue(treasury.settlementsPaused());
    }

    function testWithdrawProtocolFees() external {
        uint256 amount = 1_000e6;
        _mintAndApprove(user, amount, address(treasury));
        vm.prank(user);
        treasury.deposit(amount, amount);

        uint256 fee = (amount * treasury.feeBps()) / treasury.BPS_DENOMINATOR();
        uint256 ownerBalanceBefore = usdc.balanceOf(address(this));

        treasury.withdrawProtocolFees(fee);
        assertEq(usdc.balanceOf(address(this)), ownerBalanceBefore + fee);
        assertEq(treasury.protocolFees(), 0);
    }

    function testTotalReservesMatchesBalance() external {
        uint256 amount = 200e6;
        _mintAndApprove(user, amount, address(treasury));
        vm.prank(user);
        treasury.deposit(amount, amount);

        assertEq(treasury.totalReserves(), usdc.balanceOf(address(treasury)));
    }

    function testSetSpendingLimit() external {
        uint256 newLimit = 42;
        vm.prank(user);
        treasury.setSpendingLimit(newLimit);
        assertEq(treasury.userSpendingLimit(user), newLimit);
    }

    function testCanUserSpendView() external {
        uint256 amount = 200e6;
        uint256 spendingLimit = amount;
        _mintAndApprove(user, amount, address(treasury));
        vm.prank(user);
        treasury.deposit(amount, spendingLimit);

        assertTrue(treasury.canUserSpend(user, amount / 2));
        assertFalse(treasury.canUserSpend(user, amount * 2));
    }

    function _mintAndApprove(address account, uint256 amount, address spender) internal {
        usdc.mint(account, amount);
        vm.prank(account);
        usdc.approve(spender, amount);
    }
}

contract FaultyERC20 is IERC20 {
    enum Failure {
        None,
        RevertNoData,
        RevertWithMessage,
        ReturnFalse
    }

    Failure public failure;

    function setFailure(Failure newFailure) external {
        failure = newFailure;
    }

    function balanceOf(address) external pure returns (uint256) {
        return 0;
    }

    function transfer(address, uint256) external returns (bool) {
        return _handle();
    }

    function transferFrom(address, address, uint256) external returns (bool) {
        return _handle();
    }

    function _handle() internal view returns (bool) {
        if (failure == Failure.RevertNoData) {
            assembly {
                revert(0, 0)
            }
        }
        if (failure == Failure.RevertWithMessage) {
            revert("FAIL");
        }
        if (failure == Failure.ReturnFalse) {
            return false;
        }
        return true;
    }
}
