// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "./TestUtils.sol";
import "../patterns/stack-too-deep/StackTooDeep.sol";

contract StackTooDeepTest is TestUtils {
    ScopedHeavyStack scopedSolution = new ScopedHeavyStack(new TestOther());

    function test_scoped() external view {
        // This is our control, so just make sure it doesn't explode.
        scopedSolution.operate(_randomBytes32());
    }

    function test_struct() external {
        bytes32 x = _randomBytes32();
        StructHeavyStack solution = new StructHeavyStack(scopedSolution.other());
        assertEq(scopedSolution.operate(x), solution.operate(x));
    }

    function test_extCall() external {
        bytes32 x = _randomBytes32();
        ExternalCallHeavyStack solution = new ExternalCallHeavyStack(scopedSolution.other());
        assertEq(scopedSolution.operate(x), solution.operate(x));
    }
}

contract TestOther is IOther {
    function step1(bytes32 x)
        external
        pure
        returns (bytes32 a1, bytes32 a2, bytes32 a3)
    {
        (a1, a2, a3) = _h(x);
    }

    function step2(bytes32 a)
        external
        pure
        returns (bytes32 b1, bytes32 b2, bytes32 b3)
    {
        (b1, b2, b3) = _h(a);
    }

    function step3(bytes32 b)
        external
        pure
        returns (bytes32 c1, bytes32 c2, bytes32 c3)
    {
        (c1, c2, c3) = _h(b);
    }

    function step4(bytes32 c)
        external
        pure
        returns (bytes32 d1, bytes32 d2, bytes32 d3)
    {
        (d1, d2, d3) = _h(c);
    }

    function step5(bytes32 d)
        external
        pure
        returns (bytes32 e1, bytes32 e2, bytes32 e3)
    {
        (e1, e2, e3) = _h(d);
    }

    function _h(bytes32 v) private pure returns (bytes32 o1, bytes32 o2, bytes32 o3) {
        o1 = keccak256(abi.encode(msg.sig, v));
        o2 = keccak256(abi.encode(o1));
        o3 = keccak256(abi.encode(o2));
    }
}