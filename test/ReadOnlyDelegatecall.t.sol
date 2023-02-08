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
        IStaticExec_ReadFunction(address(rodc))
            .staticExec(address(logic), abi.encodeCall(logic.writeFunction, ()));
    }

    function test_cannotCallDelegateCallDirectly() external {
        vm.expectRevert('only self');
        rodc.delegateCall(address(logic), abi.encodeCall(logic.readFunction, ()));
    }
}

// Some interfaces recasting staticExec() so the compiler will automatically
// decode the return value for us.
interface IStaticExec_ReadFunction {
    function staticExec(address logic, bytes memory callData) external view returns (uint256);
}

interface IStaticExec_WriteFunction {
    function staticExec(address logic, bytes memory callData) external returns (uint256);
}