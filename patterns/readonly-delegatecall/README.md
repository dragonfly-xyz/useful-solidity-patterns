# Read-Only Delegatecall

- [📜 Example Code](./ReadOnlyDelegatecall.sol)
- [🐞 Tests](../../test/ReadOnlyDelegatecall.t.sol)

Delegatecalls can be used to extend the functionality of your contract by executing different bytecode/logic inside its state context. It's also an efficient way to get around code size limits. Unfortunately, `delegatecall()` has no "static" (read-only) version that reverts on state changes like `staticcall()` is to `call()`. So, by nature, delegatecalls are free to modify your contract's state or perform state-altering operations elsewhere while impersonating your contract 😱! For this reason, you definitely would *never* perform a `delegatecall()` into arbitrary bytecode... right?

Well, what if you could guarantee that the code being executed results in no state changes? In that case, your contract could happily `delegatecall()` into arbitrary bytecode with no consequences to itself. This could unlock new, read-only functionaility that make on-chain and off-chain integrations easier or more efficient.

All we have to do is figure how to emulate a "static" `delegatecall()`, or two 🤗.

## Case Study: Permisionless, Arbitrary, Read-Only Delegatecalls

Our end goal will be to create a public function on our contract that lets *anyone* pass in the address of a logic contract and call data to `delegatecall()` into. This could be used to "fill in" missing or unexpected `view` functions on a contract after deployment. It'll look something like:

```solidity
function exec(address logic, bytes memory callData) external view;
```

It should also return *exactly* whatever the `delegatecall()` returns. But we won't declare that in our hypothetical function because we can't actually know ahead of time what the return data for an arbitrary call looks like. But even without declaring it, we can (and will) use some low level assembly tricks to simply bubble up the return data without having to understand its structure. So this is fine.

## Method 1: Wrapping it in a `staticcall()`

`staticcall()` reverts if *anything* that occurs inside of it attempts to alter state. This protection also extends to nested `call()`s and even `delegatecall()`s at any depth! So if we make an external `staticcall()` to the function that actually perofrms the `delegatecall()` we can force the `delegatecall()` to also revert if any code it executes attempts to alter state.

So we'll need to define 2 `external` functions, `staticExec()` (permissionless) and `doDelegateCall()` (restricted), which work together like this:

1. User calls `staticExec(logic, callData)` on our contract.
2. `staticExec()` performs a `staticcall()` to `this.doDelegateCall(logic, callData)` (on our own contract).
3. `doDelegateCall()` delegatecalls into `logic`, calling a function with `callData`.
4. We bubble up the result/revert back to the user.

Let's work our way up by writing the function that actually performs the delegatecall, `doDelegateCall()`. If it reverts, we'll just bubble up (re-throw) the revert, but if it succeeds, we'll return the result as `bytes`.

Note that even though the function is *not intended to be called by the user*, it still needs to be declared `external` so `staticExec()` can actually call it through `this` semantics. Also, this function doesn't inherently have any `staticcall()` protection on it (that comes next) so it's **super important** that this function is not callable from outside the contract by anyone but the contract itself!

```solidity
function doDelegateCall(address logic, bytes memory callData)
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
```

Next we define the function users will actually interact with, `staticExec()`. It calls the `doDelegateCall()` function we just defined but through a `staticcall` context, then bubbles up the raw return `bytes` as if it returned it itself. Recognize that simply doing `this.doDelegateCall()` will perform a `call()` instead of a `staticcall()` because `doDelegateCall()` is not declared as `view` or `pure`, which is not what we want. However, if we re-cast `this` into an interface that *does* declare `doDelegateCall()` as `view` then it will be called via `staticcall()` 🧙!

```solidity
interface IReadOnlyDelegateCall {
    function doDelegateCall(address logic, bytes memory callData)
        external view
        returns (bytes memory returnData);
}

...

function staticExec(address logic, bytes calldata callData)
    external view
{
    // Cast this to an IReadOnlyDelegateCall interface where doDelegateCall() is
    // defined as view. This will cause the compiler to generate a staticcall
    // to doDelegateCall(), preventing it from altering state.
    bytes memory returnData =
        IReadOnlyDelegateCall(address(this)).doDelegateCall(logic, callData);
    // Return the raw return data so it's as if the caller called the intended
    // function directly.
    assembly { return(add(returnData, 0x20), mload(returnData)) }
}
```

And that's it! This approach is elegant because it just relies on a standard, familiar EVM construct (`staticcall`) to enforce immutability.

But for some contracts the mere existence of the `doDelegateCall()` function is too risky even though it's shielded by a `msg.sender == this` check. If your contract can make arbitrary external calls passed in by users, or if it performs delegatecalls elsewhere, it may be possible to trick the contract into calling `doDelegateCall()` outside of the safety of `staticExec()`. Because `doDelegateCall()` itself doesn't enforce a `staticcall()` context, any unauthorized calls to it can make actual, lasting state changes. For these situations, the next approach offers more robust protection.

## Method 2: Delegatecall and Revert

Instead of assuming that our delegatecall function will always be called inside of a `staticcall` context, we can enforce that no state changes inside of it persist even without a `staticcall()`. We do this by simply reverting after the `delegatecall()`, which undoes everything that happened inside the current execution context. We transmit information, i.e., the `delegatecall()`'s revert message or return data, inside the payload of our revert. This means the function will *always* revert, undoing any state changes that occurred during execution, and the contents of the revert will reveal the result of that execution. 

And because this function cannot possibly alter state, we no longer have to worry about guarding against who can call it. So here's our new, always-reverting `delegatecall` function, `doDelegateCallAndRevert()`:

```solidity
function doDelegateCallAndRevert(address logic, bytes calldata callData) external {
    (bool success, bytes memory returnOrRevertData) = logic.delegatecall(callData);
    // We revert with the abi-encoded success + returnOrRevertData values.
    bytes memory wrappedResult = abi.encode(success, returnOrRevertData);
    assembly { revert(add(wrappedResult, 0x20), mload(wrappedResult)) }
}
```

Technically that function performs and returns all the information a user needs, but expecting and having to parse a revert is non-intuitive. So we'll still implement a top-level `revertExec()` function that calls `doDelegateCallAndRevert()`, decodes the revert, and either returns or throws its result, like a normal function behaves.

```solidity
interface IReadOnlyDelegateCall {
    function doDelegateCallAndRevert(address logic, bytes memory callData)
        external view;
}

...

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
```

Compared to the first method, this one is a bit less intuitive (who writes a function that always reverts?) but provides stronger safety guarantees. Neither is really that much code so if you're unsure of which one you need, take this one. 😉

## The Example

The [example code](./ReadOnlyDelegatecall.sol) is a simple (pointless) contract that has a single, private storage variable `_foo`. Because `_foo` is `private`, external contracts wouldn't normally be able to read its value. But since it implements both `staticExec()` and `revertExec()` you can use either to pass in a logic contract that is able to read that storage slot through the magic of `delegatecall()`. In a realistic application, you would also take the opportunity to perform additional computation on that state. The [tests](../../test/ReadOnlyDelegatecall.t.sol) demonstrate how to use it and what happens if the logic function tries to alter state in both approaches (which fails, obviously).


## In The Real World
- (Gnosis) Safe uses the [delegatecall-and-revert]((https://github.com/safe-global/safe-contracts/blob/v1.3.0-libs.0/contracts/common/StorageAccessible.sol#L36)) approach to [simulate](https://github.com/safe-global/safe-contracts/blob/v1.3.0-libs.0/contracts/handler/CompatibilityFallbackHandler.sol#L87) the effect of transactions executed from the context of the safe contract.
- The Party Protocol also [uses delegatecall-and-revert](https://github.com/PartyDAO/party-protocol/blob/e5be102b2cc2304768b21a3ce913cd28f2965089/contracts/utils/ReadOnlyDelegateCall.sol#L25) to forward [unhandled functions](https://github.com/PartyDAO/party-protocol/blob/e5be102b2cc2304768b21a3ce913cd28f2965089/contracts/party/PartyGovernance.sol#L325) to an upgradeable component of their Party contracts in a read-only manner.
