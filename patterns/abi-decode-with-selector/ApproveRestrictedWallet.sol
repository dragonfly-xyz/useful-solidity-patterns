// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

// Abstract base for common functionality between
// `ApproveRestrictedWallet` and `ApproveRestrictedWallet_Memory`.
abstract contract ApproveRestrictedWalletBase {
    address public immutable owner;
    mapping (address => bool) public isAllowedSpender;

    modifier onlyOwner() {
        require(msg.sender == owner, 'only owner');
        _;
    }

    constructor(address owner_) {
        owner = owner_;
    }

    function setAllowedSpender(address spender, bool allowed) external onlyOwner {
        isAllowedSpender[spender] = allowed;
    }

    receive() external payable {}

    function exec(address payable callTarget, bytes calldata fnCallData, uint256 callValue)
        external payable virtual;
    
    function _exec(address payable callTarget, bytes memory fnCallData, uint256 callValue)
        internal
    {
        (bool s,) = callTarget.call{value: callValue}(fnCallData);
        require(s, 'exec failed');
    }
}

// A smart wallet that executes arbitrary calls passed in by its owner.
// If an ERC20.approve() call is detected, it will ensure that the spender is on
// the `isAllowedSpender` list before executing it.
contract ApproveRestrictedWallet is ApproveRestrictedWalletBase {
    
    constructor(address owner_) ApproveRestrictedWalletBase(owner_) {}
    
    function exec(address payable callTarget, bytes calldata fnCallData, uint256 callValue)
        external payable override
        onlyOwner
    {
        if (bytes4(fnCallData) == IERC20.approve.selector) {
            // ABI-decode the remaining bytes of fnCallData as IERC20.approve() parameters
            // using a calldata array slice to remove the leading 4 bytes.
            (address spender,) = abi.decode(fnCallData[4:], (address, uint256));
            require(isAllowedSpender[spender], 'not an allowed spender');
        }
        _exec(callTarget, fnCallData, callValue);
    }
}

// A smart wallet that executes arbitrary calls passed in by its owner.
// If an ERC20.approve() call is detected, it will ensure that the spender is on
// the `isAllowedSpender` list before executing it.
contract ApproveRestrictedWallet_Memory is ApproveRestrictedWalletBase {
    constructor(address owner_) ApproveRestrictedWalletBase(owner_) {}

    function exec(address payable callTarget, bytes memory fnCallData, uint256 callValue)
        external payable override
        onlyOwner
    {
        // Compare the first 4 bytes (selector) of fnCallData.
        if (bytes4(fnCallData) == IERC20.approve.selector) {
            // Since fnCallData is located in memory, we cannot use calldata slices.
            // Modify the array data in-place to shift the start 4 bytes.
            bytes32 oldBits;
            assembly {
                let len := mload(fnCallData)
                fnCallData := add(fnCallData, 4)
                oldBits := mload(fnCallData)
                mstore(fnCallData, sub(len, 4))
            }
            // ABI-decode fnCallData as IERC20.approve() parameters. 
            (address spender,) = abi.decode(fnCallData, (address, uint256));
            // Undo the array modification.
            assembly {
                mstore(fnCallData, oldBits)
                fnCallData := sub(fnCallData, 4)
            }
            require(isAllowedSpender[spender], 'not an allowed spender');
        }
        _exec(callTarget, fnCallData, callValue);
    }
}

// Minimal ERC20 interface.
interface IERC20 {
    function approve(address spender, uint256 allowance) external returns (bool);
}