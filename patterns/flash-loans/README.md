# Flash Loans

- [📜 Example Code](./FlashLoanPool.sol)
- [🐞 Tests](../../test/FlashLoanPool.t.sol)

For better or worse, flash loans are a permanent fixture of the modern defi landscape. As the name implies, flash loans allow people to borrow massive (sometimes protocol breaking) amounts of an asset asset during the lifespan of a function call, typically for just a small (or no) fee. For protocols that custody assets, flash loans can be an additional source of yield without risking any of its assets... if implemented [securely](#security-considerations) 🤞.

Here we'll explore creating a basic flash loan protocol to illustrate the concept.

## Anatomy of a Flash Loan

At their core, flash loans are actually fairly simple, following this typical flow:

1. Transfer loaned assets to a user-provided borrower contract.
2. Call a handler function on the borrower contract to hand over execution control.
    1. Let the borrower contract perform whatever actions it needs to do with those assets.
3. After the borrower's handler function returns, verify that all of the borrowed assets have been returned + some extra as fee.


![flash loan flow](./flash-loan-flow.drawio.svg)

The entirety of the loan occurs inside of the call to the loan function. If the borrower fails to return the assets (+ fee) by the time their logic completes, the entire call frame reverts and it will be as if the loan and the actions performed within never happened, exposing no assets to any™️ risk. It's this lack of risk that helps drive the fee associated with flash loans down.

## A Simple FLash Loan Protocol

Let's write a super simple ERC20 pool contract owned and funded by a single entity. Borrowers can come along and take a flash loan against the pool's tokens, earning a small fee along the way and increasing the total value of the pool. For additional simplicity, this contract will only support [compliant](../erc20-compatibility/) ERC20 tokens that don't take fees on transfer.

We're looking at the following minimal interfaces for this protocol:

```solidity
// Interface implemented by our protocol.
interface IFLashLoanPool {
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
    ) external;

    // Withdraw tokens held by this contract to the contract owner.
    function withdraw(IERC20 token, uint256 amount) external;
}

// Interface implemented by a flash loan borrower.
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
```

Let's immediately flesh out `flashLoan()`, which is really all we need to have a functioning flash loan protocol. It needs to 1) track the token balances, 2) transfer tokens to the borrower, 3) hand over execution control to the borrower, then 4) verify all the assets were returned. We'll use the constant `FEE_BPS` to define the flash loan fee in BPS (e.g., `1% == 0.01e4`).

```solidity
function flashLoan(
    IERC20 token,
    uint256 borrowAmount,
    IBorrower borrower,
    bytes calldata data
) external {
    // Snapshot our token balance before the transfer.
    uint256 balanceBefore = token.balanceOf(address(this));
    require(balanceBefore >= borrowAmount, 'too much');
    // Compute the fee, rounded up.
    uint256 fee = FEE_BPS * (borrowAmount + 1e4-1) / 1e4;
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
```

The `withdraw()` function is trivial to implement so we'll omit it from this guide, but you can see the complete contract [here](./FlashLoanPool.sol).

## Security Considerations

Implementing flash loans might have seemed really simple but usually they're added on top of an existing, more complex product. For example, Aave, Dydx, and Uniswap all have flash loan capabilities added to their lending and exchange products. The transfer-and-call pattern used by flash loans creates a huge opportunity for [reentrancy](../reentrancy/) and price manipulation attacks when in the setting of even a small protocol.

For instance, let's say we took the natural progression of our toy example and allowed anyone to deposit assets, granting them shares that entitles them to a proportion of generated fees. Now we would have to wonder what could happen if the flash loan borrower re-deposited borrowed assets into the pool. Without proper safeguards, it's very possible that we could double count these assets and the borrower would be able to unfairly inflate the number of their own shares and then drain all the assets out of the pool after the flash loan operation!

Extreme care has to be taken any time you do any kind of arbitrary function callback, but especially if there's value associated with it.

## Test Demo: DEX Arbitrage Borrower

Check the [tests](../../test/FlashLoanPool.t.sol) for an illustration of how a user would use our flash loan feature. There you'll find a fun borrower contract designed to perform arbitrary swap operations across different DEXes to capture a zero-capital arbitrage opportunity, with profits split between the operator and fee.
