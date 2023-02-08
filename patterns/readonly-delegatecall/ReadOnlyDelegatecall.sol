pragma solidity ^0.8.17;

contract StorageLayout {
    uint256 foo;
}

interface IReadOnlyDelegateCall {
    function delegateCall(address logic, bytes memory callData) external view
        returns (bytes memory returnData);
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
}

contract LogicContract is StorageLayout {
    function readFunction() external view returns (uint256) {
        return foo;
    }

    function writeFunction() external returns (uint256) {
        return foo = 123;
    }
}