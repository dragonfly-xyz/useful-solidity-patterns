// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

// A proxy contract that delegatecalls all calls to it to an underlying logic
// contract. An arbitrary initialization delegatecall can be made in the
// constructor.
contract Proxy {
    address public immutable LOGIC;

    constructor(address logic, bytes memory initCallData) {
        LOGIC = logic;
        // Automatically execute `initCallData` as a delegatecall.
        _forwardCall(initCallData);
    }

    fallback(bytes calldata callData) external payable
        returns (bytes memory returnData)
    {
        // Forward any calls to the logic contract via delegatecall.
        returnData = _forwardCall(callData);
    }

    function _forwardCall(bytes memory callData)
        private returns (bytes memory returnData)
    {
        (bool s, bytes memory r) = LOGIC.delegatecall(callData);
        if (!s) assembly { revert(add(r, 0x20), mload(r)) }
        return r;
    }
}

// The intended logic contract for `Proxy` instances.
// A simple ETH wallet that only allows its owner (established in the initializer)
// to move funds out.
contract WalletLogic {
    address public owner;

    // Set the owner. Only runs from within the context of a constructor.
    function initialize(address owner_) external {
        require(address(this).code.length == 0, 'not in constructor');
        owner = owner_;
    }

    // Move ETH out of this contract.
    function transferOut(address payable to, uint256 amount) external {
        require(msg.sender == owner, 'only owner');
        to.transfer(amount);
    }

    // Allow this contract to receive ETH.
    receive() external payable {}
}
