// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

// Shared contract declaring storage variables.
contract StorageLayout {
    // A private storage variable.
    uint256 internal _foo;
}

// A contract demonstrating twos ways to perform a read-only delegatecall:
//  staticExec() and revertExec().
contract ReadOnlyDelegateCall is StorageLayout {

    constructor(uint256 foo_) {
        _foo = foo_;
    }

    // ------ Method 1: staticExec() ------------ //

    // This function wraps an arbitrary delegatecall in a staticcall context so
    // that any attempts by the delegatecall to alter state causes the EVM to revert.
    // If it doesn't revert, the raw return data is returned.
    function staticExec(address logic, bytes calldata callData)
        external view
    {
        // Cast this to an IReadOnlyDelegateCall interface where doDelegateCall() is
        // defined as view. This will cause the compiler to generate a staticcall
        // to doDelegateCall(), preventing it from altering state.
        bytes memory returnData =
            IReadOnlyDelegateCall(address(this)).doDelegateCall(logic, callData);
        // Bubble up the return data as if it's ours.
        assembly { return(add(returnData, 0x20), mload(returnData)) }
    }

    // Performs an arbitrary delegatecall, returning ABI-encoded return data if
    // it succeeds.
    // It's important that only this contract is allowed to call this function
    // and that it is called through the context of a staticcall.
    function doDelegateCall(address logic, bytes calldata callData)
        external
        returns (bytes memory)
    {
        require(msg.sender == address(this), 'only self');
        (bool success, bytes memory returnOrRevertData) = logic.delegatecall(callData);
        if (!success) {
            // Bubble up reverts.
            assembly { revert(add(returnOrRevertData, 0x20), mload(returnOrRevertData)) }
        }
        // Return successful return data as bytes.
        return returnOrRevertData;
    }

    // ------ Method 2: revertExec() ------------ //

    // This function does a delegatecall through delegatecallAndRevert(), transforming
    // the revert data thrown by delegatecallAndRevert() into a successful return
    // or revert, depending on the delegatecall's outcome.
    function revertExec(address logic, bytes calldata callData) external view {
        try IReadOnlyDelegateCall(address(this)).doDelegateCallAndRevert(logic, callData) {
            revert('expected revert'); // Should never happen.
        } catch (bytes memory revertData) {
            // Decode revert data.
            (bool success, bytes memory returnOrRevertData) =
                abi.decode(revertData, (bool, bytes));
            if (!success) {
                // Bubble up revert.
                assembly { revert(add(returnOrRevertData, 0x20), mload(returnOrRevertData)) }
            }
            // Bubble up the return data as if it's ours.
            assembly { return(add(returnOrRevertData, 0x20), mload(returnOrRevertData)) }
        }
    }

    // Performs an arbitrary delegatecall, always reverting with the result
    // of that call.
    function doDelegateCallAndRevert(address logic, bytes calldata callData) external {
        (bool success, bytes memory returnOrRevertData) = logic.delegatecall(callData);
        // We always revert with the abi-encoded success + returnOrRevertData values.
        bytes memory wrappedResult = abi.encode(success, returnOrRevertData);
        assembly { revert(add(wrappedResult, 0x20), mload(wrappedResult)) }
    }
}

// Sample logic contract with functions that can be executed by
// `staticExec()` or `revertExec()`.
contract LogicContract is StorageLayout {
    // A function that just outputs the value of the private storage variable
    // _foo.
    function readFunction() external view returns (uint256) {
        return _foo;
    }

    // A function that reverts.
    function revertingReadFunction() external pure returns (uint256) {
        revert('uh oh');
    }

    // A function that writes to the storage variable _foo.
    function writeFunction() external returns (uint256) {
        return _foo = 123;
    }
}

// Convenience interface that we use to get the compiler to call
// ReadOnlyDelegateCall.delegateCall() and
// ReadOnlyDelegateCall.doDelegateCallAndRevert() in a staticcall() context.
// Same function signatures but declared view.
interface IReadOnlyDelegateCall {
    function doDelegateCall(address logic, bytes memory callData)
        external view
        returns (bytes memory returnData);
    function doDelegateCallAndRevert(address logic, bytes memory callData)
        external view;
}

