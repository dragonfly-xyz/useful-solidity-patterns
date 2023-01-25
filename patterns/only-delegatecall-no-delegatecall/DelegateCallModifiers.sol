pragma solidity ^0.8.17;

abstract contract DelegateCallModifiers {
    // The true address of this contract. Where the bytecode lives.
    address immutable public DEPLOYED_ADDRESS;

    constructor() {
        // Store the deployed address of this contract in an immutable,
        // which maintains the same value across delegatecalls.
        DEPLOYED_ADDRESS = address(this);
    }

    // The address of the current executing contract MUST NOT match the
    // deployed address of this logic contract.
    modifier onlyDelegateCall() {
        require(address(this) != DEPLOYED_ADDRESS, 'must be a delegatecall');
        _;
    }

    // The address of the current executing contract MUST match the
    // deployed address of this logic contract.
    modifier noDelegateCall() {
        require(address(this) == DEPLOYED_ADDRESS, 'must not be delegatecall');
        _;
    }
}

// Naive Logic contract for a proxy.
contract Logic {
    string public hello = "hello";
    address public owner;

    function initialize(address owner_) external {
        require(owner == address(0), 'already initialized');
        owner = owner_;
    }

    // Allow this contract to receive ETH.
    receive() external payable {}

    // Withdraw any ETH mistakenly sent to this contract.
    function skim(address payable to) public virtual {
        to.transfer(address(this).balance);
    }

    // Destroy this contract.
    function die(address payable to) public virtual {
        // Only let the owner call this function.
        require(msg.sender == owner);
        selfdestruct(payable(to));
    }

    // ...
}

// Logic contract for a proxy.
contract SafeLogic is Logic, DelegateCallModifiers {

    // Override skim() but with a noDelegateCall modifer
    // to prevent it being called through a proxy contract.
    function skim(address payable to) public override noDelegateCall {
        // Call the overridden function.
        Logic.skim(to);
    }

    // Override die() but with an onlyDelegateCall modifier
    // to prevent this function being called directly on the
    // logic contract.
    function die(address payable to) public override onlyDelegateCall {
        // Call the overridden function.
        Logic.die(to);
    }
}

// Basic EIP-1822 proxy.
contract Proxy {
    constructor(Logic logic, address owner) {
        // Set the logic contract.
        _setLogic(address(logic));
        // Initialize state via the logic contract.
        _forwardToLogic(abi.encodeCall(Logic.initialize, (owner)));
    }

    fallback(bytes calldata callData) external payable returns (bytes memory) {
        return _forwardToLogic(callData);
    }

    function _forwardToLogic(bytes memory callData) private returns (bytes memory) {
        (bool s, bytes memory r) = _getLogic().delegatecall(callData);
        if (!s) {
            assembly { revert(add(r, 0x20), mload(r)) }
        }
        return r;
    }

    function _setLogic(address logic) internal {
        assembly {
            sstore(0xc5f16f0fcc639fa48a6947836d9850f504798523bf8c9a3a87d5876cf622bcf7, logic)
        }
    }
    
    function _getLogic() internal view virtual returns (address logic) {
        assembly {
            logic := sload(0xc5f16f0fcc639fa48a6947836d9850f504798523bf8c9a3a87d5876cf622bcf7)
        }
    }
}
