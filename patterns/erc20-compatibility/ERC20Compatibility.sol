// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

// Compliant ERC20 interface: https://eips.ethereum.org/EIPS/eip-20
interface IERC20 {
    function name() external view returns (string memory name_);
    function symbol() external view returns (string memory symbol_);
    function decimals() external view returns (uint8 decimals_);
    function totalSupply() external view returns (uint256 totalSupply_);
    function allowance(address owner, address spender) external view returns (uint256 allowance_);
    function balanceOf(address owner) external view returns (uint256 balance);
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address owner, address to, uint256 amount) external returns (bool);
    function approve(address spender, uint256 allowance) external returns (bool);
}

// A library for working with both compliant and non-compliant ERC20s.
library LibERC20Compat {
    function safeTransfer(IERC20 token, address to, uint256 amount) internal {
        _callAndCheckOptionalResult(address(token), abi.encodeCall(IERC20.transfer, (to, amount)));
    }

    function safeTransferFrom(IERC20 token, address owner, address to, uint256 amount) internal {
        _callAndCheckOptionalResult(address(token), abi.encodeCall(IERC20.transferFrom, (owner, to, amount)));
    }

    function safeApprove(IERC20 token, address spender, uint256 amount) internal {
        // First reset allowance to 0 for tokens that require this step.
        _callAndCheckOptionalResult(address(token), abi.encodeCall(IERC20.approve, (spender, 0)));
        if (amount != 0) {
            // Then set it to desired amount.
            _callAndCheckOptionalResult(address(token), abi.encodeCall(IERC20.approve, (spender, amount)));
        }
    }

    function _callAndCheckOptionalResult(address target, bytes memory callData) private {
        // Attempt to call a function that returns an optional boolean success value.
        (bool success, bytes memory returnOrRevertData) = address(target).call(callData);
        // Did the call revert?
        require(success, 'call failed');
        // The call did not revert. If we got enough return data to encode a bool, decode it.
        if (returnOrRevertData.length >= 32) {
            // Ensure that the returned bool is true.
            require(abi.decode(returnOrRevertData, (bool)), 'call failed');
        }
        // Otherwise, we're gucci.
    }
}

// ERC20 token that correctly implements the ERC20 standard.
contract GoodERC20 {
    address public immutable minter;
    string public constant name = 'GoodERC20';
    string public constant symbol = 'GUD';
    uint8 public constant decimals = 18;

    uint256 public totalSupply;
    mapping (address => uint256) public balanceOf;
    mapping (address => mapping (address => uint256)) public allowance;

    constructor() {
        minter = msg.sender;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        return transferFrom(msg.sender, to, amount);
    }

    function transferFrom(address owner, address to, uint256 amount) public returns (bool) {
        if (to == address(0)) {
            return false;
        }
        // Allow the compiler's overflow guard to revert to keep balances
        // and allowances consistent.
        if (owner != msg.sender) {
            allowance[owner][msg.sender] -= amount;
        }
        balanceOf[owner] -= amount;
        balanceOf[to] += amount;
        return true;
    }

    function approve(address spender, uint256 allowance_) external returns (bool) {
        allowance[msg.sender][spender] = allowance_;
        return true;
    }

    function mint(address owner, uint256 amount) external {
        require(msg.sender == minter, 'only minter');
        totalSupply += amount;
        balanceOf[owner] += amount;
    }
}

// ERC20 token that incorrectly implements the ERC20 standard by not returning
// anything for transfer(), transferFrom(), and approve().
// Also requires allowances to be reset to 0 before setting to non-zero (USDT).
contract BadERC20 {
    address public immutable minter;
    string public constant name = 'BadERC20';
    string public constant symbol = 'BAD';
    uint8 public immutable decimals = 18;

    uint256 public totalSupply;
    mapping (address => uint256) public balanceOf;
    mapping (address => mapping (address => uint256)) public allowance;

    constructor() {
        minter = msg.sender;
    }

    function transfer(address to, uint256 amount) external {
        transferFrom(msg.sender, to, amount);
    }

    function transferFrom(address owner, address to, uint256 amount) public {
        // Allow the compiler's overflow guard to revert to keep balances
        // and allowances consistent.
        if (owner != msg.sender) {
            allowance[owner][msg.sender] -= amount;
        }
        balanceOf[owner] -= amount;
        balanceOf[to] += amount;
    }

    function approve(address spender, uint256 allowance_) external {
        if (allowance_ != 0 && allowance[msg.sender][spender] != 0) {
            require(allowance[msg.sender][spender] == 0, 'allowance must be reset');
        }
        allowance[msg.sender][spender] = allowance_;
    }

    function mint(address owner, uint256 amount) external {
        require(msg.sender == minter, 'only minter');
        totalSupply += amount;
        balanceOf[owner] += amount;
    }
}
