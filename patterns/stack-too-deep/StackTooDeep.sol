pragma solidity 0.8.17;

// Mark abstract to prevent stack-too-deep compiler error.
abstract contract HeavyStack {
    IOther public immutable other;

    constructor(IOther other_) {
        other = other_;
    }

    // Will not compile in a concrete (non-abstract) contract due to stack too deep,
    function operate(bytes32 x) external virtual view returns (bytes32 r) {
        (bytes32 a1, bytes32 a2, bytes32 a3) = other.step1(x);
        r = _hash4(x, a1, a2, a3);
        (bytes32 b1, bytes32 b2, bytes32 b3) = other.step2(r);
        r = _hash4(r, b1, b2, b3);
        (bytes32 c1, bytes32 c2, bytes32 c3) = other.step3(r);
        r = _hash4(r, c1, c2, c3);
        (bytes32 d1, bytes32 d2, bytes32 d3) = other.step4(r);
        r = _hash4(r, d1, d2, d3);
        (bytes32 e1, bytes32 e2, bytes32 e3) = other.step5(r);
        r = _hash4(r, e1, e2, e3);
    }

    function _hash4(bytes32 i1, bytes32 i2, bytes32 i3, bytes32 i4) internal pure returns (bytes32 o) {
        return keccak256(abi.encode(i1, i2, i3, i4));
    }
}

contract ScopedHeavyStack is HeavyStack {
    constructor(IOther other_) HeavyStack(other_) {}

    // Override operate() with a version that does the same thing but with stack variable scoping.
    function operate(bytes32 x) external override view returns (bytes32 r) {
        {
            (bytes32 a1, bytes32 a2, bytes32 a3) = other.step1(x);
            r = _hash4(x, a1, a2, a3);
        }
        {
            (bytes32 b1, bytes32 b2, bytes32 b3) = other.step2(r);
            r = _hash4(r, b1, b2, b3);
        }
        {
            (bytes32 c1, bytes32 c2, bytes32 c3) = other.step3(r);
            r = _hash4(r, c1, c2, c3);
        }
        {
            (bytes32 d1, bytes32 d2, bytes32 d3) = other.step4(r);
            r = _hash4(r, d1, d2, d3);
        }
        {
            (bytes32 e1, bytes32 e2, bytes32 e3) = other.step5(r);
            r = _hash4(r, e1, e2, e3);
        }
    }
}

contract StructHeavyStack is HeavyStack {
    constructor(IOther other_) HeavyStack(other_) {}

    // Struct delcaring all vars used by operate().
    struct OperateVars {
        bytes32 a1;
        bytes32 a2;
        bytes32 a3;
        bytes32 b1;
        bytes32 b2;
        bytes32 b3;
        bytes32 c1;
        bytes32 c2;
        bytes32 c3;
        bytes32 d1;
        bytes32 d2;
        bytes32 d3;
        bytes32 e1;
        bytes32 e2;
        bytes32 e3;
    }

    // Override operate() with a version that does the same thing but with variables stored
    // in a struct that lives in memory.
    function operate(bytes32 x) external override view returns (bytes32 r) {
        OperateVars memory vars;
        (vars.a1, vars.a2, vars.a3) = other.step1(x);
        r = _hash4(x, vars.a1, vars.a2, vars.a3);
        (vars.b1, vars.b2, vars.b3) = other.step2(r);
        r = _hash4(r, vars.b1, vars.b2, vars.b3);
        (vars.c1, vars.c2, vars.c3) = other.step3(r);
        r = _hash4(r, vars.c1, vars.c2, vars.c3);
        (vars.d1, vars.d2, vars.d3) = other.step4(r);
        r = _hash4(r, vars.d1, vars.d2, vars.d3);
        (vars.e1, vars.e2, vars.e3) = other.step5(r);
        r = _hash4(r, vars.e1, vars.e2, vars.e3);
    }
}

contract ExternalCallHeavyStack is HeavyStack {
    constructor(IOther other_) HeavyStack(other_) {}

    // Override operate() with a version that does the same thing but
    // using external calls to get a fresh stack.
    function operate(bytes32 x) external override view returns (bytes32 r) {
        (bytes32 a1, bytes32 a2, bytes32 a3) = other.step1(x);
        r = _hash4(x, a1, a2, a3);
        (bytes32 b1, bytes32 b2, bytes32 b3) = other.step2(r);
        r = _hash4(r, b1, b2, b3);
        (bytes32 c1, bytes32 c2, bytes32 c3) = other.step3(r);
        r = _hash4(r, c1, c2, c3);
        r = this.operatePart2(r);
    }

    function operatePart2(bytes32 r3) external view returns (bytes32 r5) {
        (bytes32 d1, bytes32 d2, bytes32 d3) = other.step4(r3);
        r5 = _hash4(r3, d1, d2, d3);
        (bytes32 e1, bytes32 e2, bytes32 e3) = other.step5(r5);
        r5 = _hash4(r5, e1, e2, e3);
    }
}

// Some imaginary external contract we want to interact repeatedly with.
interface IOther {
    function step1(bytes32 x)
        external
        view
        returns (bytes32 a1, bytes32 a2, bytes32 a3);

    function step2(bytes32 a)
        external
        view
        returns (bytes32 b1, bytes32 b2, bytes32 b3);

    function step3(bytes32 b)
        external
        view
        returns (bytes32 c1, bytes32 c2, bytes32 c3);
    
    function step4(bytes32 c)
        external
        view
        returns (bytes32 d1, bytes32 d2, bytes32 d3);

    function step5(bytes32 d)
        external
        view
        returns (bytes32 e1, bytes32 e2, bytes32 e3);
}
