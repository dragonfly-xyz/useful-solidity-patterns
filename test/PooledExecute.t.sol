// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "../patterns/error-handling/PooledExecute.sol";
import "./TestUtils.sol";

contract PooledExecuteTest is TestUtils {
    event ExecuteSucceeded(bytes returnData);
    event ExecuteFailed(bytes revertData);
    event TargetCalled(uint256 value);

    ExecuteTarget target = new ExecuteTarget();

    function test_canExecuteAndSucceed() external {
        PooledExecute pool = new PooledExecute(
            address(target),
            abi.encodeCall(target.noop, ()),
            1,
            100e3
        );
        vm.expectEmit(false, false, false, true);
        emit TargetCalled(1);
        vm.expectEmit(false, false, false, true);
        emit ExecuteSucceeded('');
        pool.join{value: 1}();
        assertEq(address(target).balance, 1);
    }

    function test_canExecuteAndFail() external {
        PooledExecute pool = new PooledExecute(
            address(target),
            abi.encodeCall(target.fail, ()),
            1,
            100e3
        );
        vm.expectEmit(false, false, false, true);
        emit ExecuteFailed(abi.encodeWithSignature('Error(string)', 'fail'));
        pool.join{value: 1}();
        assertEq(address(target).balance, 0);
        assertEq(address(pool).balance, 1);
    }

    function test_refundsExcessEth() external {
        PooledExecute pool = new PooledExecute(
            address(target),
            abi.encodeCall(target.noop, ()),
            2,
            100e3
        );
        vm.deal(address(pool), 1);
        address contributor = _randomAddress();
        vm.deal(contributor, 2);
        vm.prank(contributor);
        pool.join{value: 2}();
        assertEq(contributor.balance, 1);
    }

    function test_doesNotExecuteIfNotEnoughEth() external {
        PooledExecute pool = new PooledExecute(
            address(target),
            abi.encodeCall(target.noop, ()),
            2,
            100e3
        );
        pool.join{value: 1}();
        assertEq(uint8(pool.executeResult()), uint8(PooledExecute.ExecuteResult.NotExecuted));
    }

    function test_cannotReenterJoin() external {
        PooledExecute pool = new PooledExecute(
            address(target),
            abi.encodeCall(target.reenterJoin, ()),
            1,
            100e3
        );
        vm.expectEmit(false, false, false, true);
        emit ExecuteFailed(abi.encodeWithSignature('Error(string)', 'already executed'));
        pool.join{value: 1}();
    }

    function test_cannotReenterWithdraw() external {
        PooledExecute pool = new PooledExecute(
            address(target),
            abi.encodeCall(target.reenterWithdraw, ()),
            1,
            100e3
        );
        vm.expectEmit(false, false, false, true);
        emit ExecuteFailed(abi.encodeWithSignature('Error(string)', 'execution hasn\'t failed'));
        pool.join{value: 1}();
    }

    function test_cannotExecuteTwice() external {
        PooledExecute pool = new PooledExecute(
            address(target),
            abi.encodeCall(target.noop, ()),
            1,
            100e3
        );
        vm.expectEmit(false, false, false, true);
        emit ExecuteSucceeded('');
        pool.join{value: 1}();
        vm.expectRevert('already executed');
        pool.join{value: 1}();
    }

    function test_cannotExecuteWithTooLittleGas() external {
        PooledExecute pool = new PooledExecute(
            address(target),
            abi.encodeCall(target.reenterWithdraw, ()),
            1,
            100e3
        );
        vm.expectRevert('not enough gas left');
        pool.join{value: 1, gas: 100e3}();
    }

    function test_cannotWithdrawBeforeFailing() external {
        PooledExecute pool = new PooledExecute(
            address(target),
            abi.encodeCall(target.noop, ()),
            2,
            100e3
        );
        pool.join{value: 1}();
        vm.expectRevert('execution hasn\'t failed');
        pool.withdraw();
    }

    function test_canWithdrawAfterFailing() external {
        PooledExecute pool = new PooledExecute(
            address(target),
            abi.encodeCall(target.fail, ()),
            1,
            100e3
        );
        address contributor = _randomAddress();
        vm.deal(contributor, 1);
        vm.expectEmit(false, false, false, true);
        emit ExecuteFailed(abi.encodeWithSignature('Error(string)', 'fail'));
        vm.prank(contributor);
        pool.join{value: 1}();
        assertEq(contributor.balance, 0);
        vm.prank(contributor);
        pool.withdraw();
        assertEq(contributor.balance, 1);
    }

    function test_cannotWithdrawTwice() external {
        PooledExecute pool = new PooledExecute(
            address(target),
            abi.encodeCall(target.fail, ()),
            1,
            100e3
        );
        address contributor = _randomAddress();
        vm.deal(contributor, 1);
        vm.expectEmit(false, false, false, true);
        emit ExecuteFailed(abi.encodeWithSignature('Error(string)', 'fail'));
        vm.prank(contributor);
        pool.join{value: 1}();
        assertEq(contributor.balance, 0);
        vm.prank(contributor);
        pool.withdraw();
        assertEq(contributor.balance, 1);
        vm.prank(contributor);
        pool.withdraw();
        assertEq(contributor.balance, 1);
    }
}

contract ExecuteTarget {
    event TargetCalled(uint256 value);

    function noop() external payable {
        emit TargetCalled(msg.value);
    }

    function fail() external payable {
        revert('fail');
    }

    function reenterJoin() external payable {
        PooledExecute(msg.sender).join();
    }

    function reenterWithdraw() external payable {
        PooledExecute(msg.sender).withdraw();
    }
}
