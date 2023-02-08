// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "../patterns/readonly-delegatecall/ReadOnlyDelegatecall.sol";
import "./TestUtils.sol";

contract ReadOnlyDelegatecallTest is TestUtils {

    ReadOnlyDelegateCall rodc = new ReadOnlyDelegateCall(1337);
    LogicContract logic = new LogicContract();

    function test_canStaticExecReadFunction() external {
        uint256 r = IStaticExec_ReadFunction(address(rodc))
            .staticExec(address(logic), abi.encodeCall(logic.readFunction, ()));
        assertEq(r, 1337);
    }

    function test_cannotStaticExecWriteFunction() external {
        vm.expectRevert();
        rodc
            .staticExec(address(logic), abi.encodeCall(logic.writeFunction, ()));
    }

    function test_cannotCallDelegateCallDirectly() external {
        vm.expectRevert('only self');
        rodc.delegateCall(address(logic), abi.encodeCall(logic.readFunction, ()));
    }

    function test_canRevertExecReadFunction() external {
        uint256 r = IStaticExec_ReadFunction(address(rodc))
            .revertExec(address(logic), abi.encodeCall(logic.readFunction, ()));
        assertEq(r, 1337);
    }

    function test_canRevertExecRevertingReadFunction() external {
        vm.expectRevert('uh oh');
        IStaticExec_ReadFunction(address(rodc))
            .revertExec(address(logic), abi.encodeCall(logic.revertingReadFunction, ()));
    }

    function test_cannotRevertExecWriteFunction() external {
        vm.expectRevert();
        rodc.revertExec(address(logic), abi.encodeCall(logic.writeFunction, ()));
    }

    function test_canCallDelegateCallAndRevertDirectly() external {
        try rodc.delegateCallAndRevert(address(logic), abi.encodeCall(logic.readFunction, ()))
        {
            revert('expected revert');
        } catch (bytes memory revertData) {
            assertEq(revertData, abi.encode(true, abi.encode(1337)));
        }
    }

    function test_canCallDelegateCallAndRevertDirectlyWithWriteFunction() external {
        try rodc.delegateCallAndRevert(address(logic), abi.encodeCall(logic.writeFunction, ()))
        {
            revert('expected revert');
        } catch (bytes memory revertData) {
            assertEq(revertData, abi.encode(true, abi.encode(123)));
        }
    }
}

contract LogicContract is StorageLayout {
    function readFunction() external view returns (uint256) {
        return foo;
    }

    function revertingReadFunction() external pure returns (uint256) {
        revert('uh oh');
    }

    function writeFunction() external returns (uint256) {
        return foo = 123;
    }
}

// An interface recasting staticExec() and revertExec() so the compiler will automatically
// decode the return value for us.
interface IStaticExec_ReadFunction {
    function staticExec(address logic, bytes memory callData) external view returns (uint256);
    function revertExec(address logic, bytes memory callData) external view returns (uint256);
}