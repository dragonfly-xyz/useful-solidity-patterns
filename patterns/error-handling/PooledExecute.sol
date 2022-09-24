// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

// Allows strangers to pool their ETH together to attach to a single arbitrary call
// that will be made once enough ETH is raised.
// If the call fails, each contributor can withdraw their contribution.
contract PooledExecute {
    enum ExecuteResult {
        NotExecuted,
        Succeeded,
        Failed
    }
    // Whether the call was executed (failed or not).
    ExecuteResult public executeResult;
    address public callTarget;
    bytes public callData;
    uint256 public callValue;
    uint256 public callGas;
    // How much each contributor has donated through join().
    mapping (address => uint256) public contributionsByUser;

    event ExecuteSucceeded(bytes returnData);
    event ExecuteFailed(bytes revertData);

    constructor(address callTarget_, bytes memory callData_, uint256 callValue_, uint256 callGas_) {
        callTarget = callTarget_;
        callData = callData_;
        callValue = callValue_;
        callGas = callGas_;
    }

    // Contribute ETH to be spent on the call.
    // If enough ETH is raised, the call will be executed immediately.
    function join() payable external {
        require(executeResult == ExecuteResult.NotExecuted, 'already executed');
        uint256 callValue_ = callValue;
        uint256 currBalance = address(this).balance;
        // Don't let users contribute more ETH than necessary.
        uint256 refund;
        if (msg.value > 0) {
            uint256 prevBalance = currBalance - msg.value;
            if (prevBalance >= callValue_) {
                refund = msg.value;
            } else {
                uint256 ethNeeded = callValue_ - prevBalance;
                if (msg.value > ethNeeded) {
                    refund = msg.value - ethNeeded;
                }
            }
        }
        // Credit the contributor.
        contributionsByUser[msg.sender] += msg.value - refund;
        // If we have enough ETH to call the function, do so.
        if (currBalance >= callValue_) {
            _execute();
        }
        // Refund excess contribution.
        if (refund > 0) {
            payable(msg.sender).transfer(refund);
        }
    }

    // Withdraw contributed funds after the call has failed.
    function withdraw() external {
        require(executeResult == ExecuteResult.Failed, 'execution hasn\'t failed');
        uint256 amount = contributionsByUser[msg.sender];
        contributionsByUser[msg.sender] = 0;
        payable(msg.sender).transfer(amount);
    }

    // Try to execute the arbitrary call.
    function _execute() private {
        // Temporarily set the executeResult to Succeeded to prevent reentrancy
        // in join() and withdraw().
        executeResult = ExecuteResult.Succeeded;
        // Enforce the gas limit to mitigate griefing by forcing the call to
        // to revert by an EOA setting a low gas limit in their transaction.
        require(gasleft() >= callGas + 3000, 'not enough gas left');
        // Make the call with attached ETH and manual gas limit.
        (bool success, bytes memory returnOrRevertData) =
            callTarget.call{ value: callValue, gas: callGas }(callData);
        if (!success) {
            executeResult = ExecuteResult.Failed;
            emit ExecuteFailed(returnOrRevertData);
            return;
        }
        // Leave executeResult as Succeeded.
        emit ExecuteSucceeded(returnOrRevertData);
    }
}
