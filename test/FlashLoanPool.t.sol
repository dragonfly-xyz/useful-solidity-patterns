// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.23;

import "solmate/tokens/ERC20.sol";
import "../patterns/flash-loans/FlashLoanPool.sol";
import "./TestUtils.sol";

contract TestERC20 is ERC20 {
    constructor(string memory name, string memory symbol) ERC20(name, symbol, 6) {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function asIERC20() external view returns (IERC20) {
        return IERC20(address(this));
    }
}

contract FlashLoanValidator is StdAssertions {
    struct Data {
        address expectedOperator;
        uint256 expectedAmount;
        uint256 expectedFee;
        IERC20 expectedToken;
    }

    function validateFlashLoan(
        address operator,
        IERC20 token,
        uint256 amount,
        uint256 fee,
        bytes calldata rawData
    )
        external
    {
        Data memory data = abi.decode(rawData, (Data));
        assertEq(operator, data.expectedOperator);
        assertEq(address(token), address(data.expectedToken));
        assertEq(amount, data.expectedAmount);
        assertEq(fee, data.expectedFee);
    }
}

contract MintBorrower is IBorrower {
    struct Data {
        uint256 mintAmount;
        FlashLoanValidator validator;
        bytes validatorData;
    }

    function onFlashLoan(
        address operator,
        IERC20 token,
        uint256 amount,
        uint256 fee,
        bytes calldata rawData
    )
        external
    {
        Data memory data = abi.decode(rawData, (Data));
        if (address(data.validator) != address(0)) {
            assert(address(data.validator).code.length != 0);
            data.validator.validateFlashLoan(operator, token, amount, fee, data.validatorData);
        }
        TestERC20(address(token)).mint(msg.sender, data.mintAmount);
    }
}

contract MockDEX {
    mapping (TestERC20 => mapping (TestERC20 => uint32)) private _rates;

    function setRate(TestERC20 sellToken, TestERC20 buyToken, uint32 rate) external {
        _rates[sellToken][buyToken] = rate;
    }

    function swapBalance(TestERC20 sellToken, TestERC20 buyToken) external {
        uint32 rate = _rates[sellToken][buyToken];
        _rates[sellToken][buyToken] = 0;
        uint256 sellAmount = sellToken.balanceOf(msg.sender);
        {
            uint256 sellAllowance = sellToken.allowance(msg.sender, address(this));
            if (sellAllowance < sellAmount) {
                sellAmount = sellAllowance;
            }
        }
        sellToken.transferFrom(msg.sender, address(this), sellAmount);
        uint256 buyAmount = sellAmount * rate * 10**buyToken.decimals()
            / (10**sellToken.decimals() * 1e4);
        buyToken.mint(msg.sender, buyAmount);
    }
}

contract ArbitrageBorrower is IBorrower {
    FlashLoanPool public immutable POOL;
    address public immutable OPERATOR;

    constructor(FlashLoanPool pool, address operator) {
        POOL = pool;
        OPERATOR = operator;
    }

    function onFlashLoan(
        address operator,
        IERC20 token,
        uint256 amount,
        uint256 fee,
        bytes calldata data
    )
        external
    {
        // Only FlashLoanPool can call this function.
        require(msg.sender == address(POOL), 'not pool');
        // Only a designated operator can trigger it.
        require(operator == OPERATOR, 'not operator');
        (
            address[] memory addrs,
            IERC20[] memory dstTokens,
            bytes[] memory swapCalls
        ) = abi.decode(data, (address[], IERC20[], bytes[]));
        assert(addrs.length == swapCalls.length && addrs.length == dstTokens.length);
        for (uint256 i = 0; i < addrs.length; ++i) {
            IERC20 srcToken = i == 0 ? token : dstTokens[i - 1];
            IERC20 dstToken = dstTokens[i];
            // Last token must be the original token.
            assert(i < addrs.length - 1 || dstToken == token);
            // Grant an allowance to the target address.
            srcToken.approve(addrs[i], srcToken.balanceOf(address(this)));
            // Call the target.
            // NOTE: that token quantities will likely need to be baked
            // into the call data. Leaving dynamic quantities for a future exercise.
            // WARNING: This executes ANY target + call data combo, INCLUDING an ERC20
            // transfer() call, so it's important that this contract either never holds
            // assets long-term or is restricted in who can interact with it.
            (bool b, bytes memory r) = addrs[i].call(swapCalls[i]);
            if (!b) {
                // Bubble up revert on failure.
                assembly { revert(add(r, 0x20), mload(r)) }
            }
            // Revoke allowance.
            srcToken.approve(addrs[i], 0);
            // Transfer any remaining tokens to the operator.
            token.transfer(msg.sender, srcToken.balanceOf(address(this)));
        }
        // Transfer borrowed amount + fee back to the lender.
        token.transfer(msg.sender, amount + fee);
        // Transfer anything remaining to the operator.
        token.transfer(operator, token.balanceOf(address(this)));
    }
}

contract FlashLoanPoolTest is TestUtils, FlashLoanValidator {
    FlashLoanPool pool = new FlashLoanPool(address(this));
    TestERC20[] tokens;

    constructor() {
        tokens.push(new TestERC20('TEST1', 'TEST1'));
        tokens.push(new TestERC20('TEST1', 'TEST1'));
        tokens[0].mint(address(pool), 100e6);
        tokens[1].mint(address(pool), 100e6);
    }
    
    function _getFee(uint256 amount) private view returns (uint256) {
        return (pool.FEE_BPS() * amount + 1e4-1) / 1e4;
    }

    function test_canWithdraw() external {
        pool.withdraw(tokens[0].asIERC20(), 1e6);
        assertEq(tokens[0].balanceOf(address(this)), 1e6);
        assertEq(tokens[0].balanceOf(address(pool)), 100e6 - 1e6);
        pool.withdraw(tokens[1].asIERC20(), 1e6);
        assertEq(tokens[1].balanceOf(address(this)), 1e6);
        assertEq(tokens[1].balanceOf(address(pool)), 100e6 - 1e6);
    }

    function test_notOwnerCannotWithdraw() external {
        IERC20 token = tokens[0].asIERC20();
        vm.expectRevert('not owner');
        vm.prank(_randomAddress());
        pool.withdraw(token, 1e6);
    }


    function test_cannotFlashLoanWithoutFee() external {
        IERC20 token = tokens[0].asIERC20();
        address operator = _randomAddress();
        MintBorrower borrower = new MintBorrower();
        uint256 amount = 1e6;
        uint256 fee = _getFee(amount);
        bytes memory data = abi.encode(MintBorrower.Data({
            mintAmount: fee + amount - 1,
            validator: FlashLoanValidator(address(0)),
            validatorData: ""
        }));
        vm.expectRevert('not repaid');
        vm.prank(operator);
        pool.flashLoan(token, amount, borrower, data);
    }

    function test_canFlashLoan() external {
        IERC20 token = tokens[0].asIERC20();
        address operator = _randomAddress();
        MintBorrower borrower = new MintBorrower();
        uint256 amount = 1e6;
        uint256 fee = _getFee(amount);
        bytes memory data = abi.encode(MintBorrower.Data({
            mintAmount: fee + amount,
            validator: this,
            validatorData: abi.encode(FlashLoanValidator.Data({
                expectedOperator: operator,
                expectedAmount: amount,
                expectedFee: fee,
                expectedToken: token
            }))
        }));
        vm.prank(operator);
        pool.flashLoan(token, amount, borrower, data);
        assertEq(token.balanceOf(address(pool)), 100e6 + fee);
    }

    function test_cannotFlashLoanMoreThanBalance() external {
        IERC20 token = tokens[0].asIERC20();
        address operator = _randomAddress();
        MintBorrower borrower = new MintBorrower();
        uint256 amount = token.balanceOf(address(pool)) + 1;
        uint256 fee = _getFee(amount);
        bytes memory data = abi.encode(MintBorrower.Data({
            mintAmount: fee + amount,
            validator: FlashLoanValidator(address(0)),
            validatorData: ""
        }));
        vm.expectRevert('too much');
        vm.prank(operator);
        pool.flashLoan(token, amount, borrower, data);
    }

    function test_canFlashLoanToArbitrageBorrower() external {
        IERC20 token = tokens[0].asIERC20();
        address operator = _randomAddress();
        ArbitrageBorrower borrower = new ArbitrageBorrower(pool, operator);
        uint256 amount = token.balanceOf(address(pool));
        TestERC20[] memory tokenPath = new TestERC20[](4);
        tokenPath[0] = new TestERC20('USDC', 'USDC'); // TEST1 -> USDC
        tokenPath[1] = new TestERC20('MKR', 'MKR'); // USDC -> MKR
        tokenPath[2] = tokenPath[0]; // MKR -> USDC (arb)
        tokenPath[3] = TestERC20(address(token)); // USDC -> TEST1
        // Set up a DEX with a +0.25% MKR/USDC arb.
        MockDEX dex = new MockDEX();
        dex.setRate(tokenPath[3], tokenPath[0], 0.5e4); // TEST1 -> USDC
        dex.setRate(tokenPath[0], tokenPath[1], 0.01e4); // USDC -> MKR
        dex.setRate(tokenPath[1], tokenPath[2], 100.25e4); // MKR -> USDC (+ 0.25%)
        dex.setRate(tokenPath[2], tokenPath[3], 2e4); // USDC -> TEST1
        MockDEX[] memory dexes = new MockDEX[](tokenPath.length);
        bytes[] memory callDatas = new bytes[](tokenPath.length);
        for (uint256 i = 0; i < tokenPath.length; ++i) {
            dexes[i] = dex;
            callDatas[i] = abi.encodeCall(
                MockDEX.swapBalance,
                (
                    tokenPath[(i + tokenPath.length - 1) % tokenPath.length],
                    tokenPath[i]
                )
            );
        }
        assertEq(token.balanceOf(operator), 0);
        vm.prank(operator);
        pool.flashLoan(token, amount, borrower, abi.encode(dexes, tokenPath, callDatas));
        uint256 profit = (1.0025e4 * amount / 1e4) - (amount + _getFee(amount));
        assertGt(profit, 0);
        assertEq(token.balanceOf(operator), profit);
        assertEq(token.balanceOf(address(pool)), 100e6 + _getFee(amount));
    }
}