pragma solidity ^0.8.17;

contract StorageLayout {
    uint256 foo;
}

interface IReadOnlyDelegateCall {
    function delegateCall(address logic, bytes memory callData) external view
        returns (bytes memory returnData);

    function delegateCallAndRevert(address logic, bytes memory callData) external view;
}

contract ReadOnlyDelegateCall is StorageLayout {

    constructor(uint256 foo_) {
        foo = foo_;
    }

    function staticExec(address logic, bytes memory callData) external view {
        bytes memory returnData =
            IReadOnlyDelegateCall(address(this)).delegateCall(logic, callData);
        assembly {
            return(add(returnData, 0x20), mload(returnData))
        }
    }

    function delegateCall(address logic, bytes memory callData) external returns (bytes memory) {
        require(msg.sender == address(this), 'only self');
        (bool success, bytes memory returnOrRevertData) = logic.delegatecall(callData);
        if (!success) {
            assembly { revert(add(returnOrRevertData, 0x20), mload(returnOrRevertData)) }
        }
        return returnOrRevertData;
    }

    function revertExec(address logic, bytes memory callData) external view {
        try IReadOnlyDelegateCall(address(this)).delegateCallAndRevert(logic, callData) {
            revert('expected revert'); // Should never happen.
        }
        catch (bytes memory revertData) {
            (bool success, bytes memory returnOrRevertData) =
                abi.decode(revertData, (bool, bytes));
            if (!success) {
                assembly { revert(add(returnOrRevertData, 0x20), mload(returnOrRevertData)) }
            }
            assembly { return(add(returnOrRevertData, 0x20), mload(returnOrRevertData)) }
        }
    }

    function delegateCallAndRevert(address logic, bytes memory callData) external {
        (bool success, bytes memory returnOrRevertData) = logic.delegatecall(callData);
        // Encode the return/revert data with a success prefix and revert with that.
        bytes memory wrappedResult = abi.encode(success, returnOrRevertData);
        assembly { revert(add(wrappedResult, 0x20), mload(wrappedResult)) }
    }
}