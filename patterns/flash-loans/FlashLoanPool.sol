// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

// Minimal ERC20 interface.
interface IERC20 {
    function balanceOf(address owner) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
    function approve(address spender, uint256 amount) external returns (bool);
}

// Interface implemented by a flash loan borrower contract.
interface IBorrower {
    function onFlashLoan(
        // Who called `flashLoan()`.
        address operator,
        // Token borrowed.
        IERC20 token,
        // Amount of tokens borrowed.
        uint256 amount,
        // Extra tokens (on top of `amount`) to return as the loan fee.
        uint256 fee,
        // Arbitrary data passed into `flashLoan()`.
        bytes calldata data
    ) external;
}

// A simple flash loan protocol with a single depositor/withdrawer (OWNER).
contract FlashLoanPool {
    uint16 public constant FEE_BPS = 0.001e4; // 0.1% fee.
    address public immutable OWNER;

    constructor(address owner) { OWNER = owner; }

    // Perform a flash loan.
    function flashLoan(
        // Token to borrow.
        IERC20 token,
        // How much to borrow.
        uint256 borrowAmount,
        // Address of the borrower (handler) contract.
        IBorrower borrower,
        // Arbitrary data to pass to borrower contract.
        bytes calldata data
    )
        external
    {
        // Snapshot our token balance before the transfer.
        uint256 balanceBefore = token.balanceOf(address(this));
        require(balanceBefore >= borrowAmount, 'too much');
        // Compute the fee, rounded up.
        uint256 fee = (FEE_BPS * borrowAmount + 1e4-1) / 1e4;
        // Transfer tokens to the borrower contract.
        token.transfer(address(borrower), borrowAmount);
        // Let the borrower do its thing.
        borrower.onFlashLoan(
            msg.sender,
            token,
            borrowAmount,
            fee,
            data
        );
        // Check that all the tokens were returned + fee.
        uint256 balanceAfter = token.balanceOf(address(this));
        require(balanceAfter >= balanceBefore + fee, 'not repaid');
    }

    // Withdraw tokens from this contract to the contract owner.
    function withdraw(IERC20 token, uint256 amount)
        external
    {
        require(msg.sender == OWNER, 'not owner');
        token.transfer(msg.sender, amount);
    }
}
