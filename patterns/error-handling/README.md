# Error Handling

- [📜 Example Code](./PooledExecute.sol)
- [🐞 Tests](../../test/PooledExecute.t.sol)

If you want to build a resilient contract that interacts with other contracts outside of your own, you should at least consider whether you need to gracefully handle errors when calling into them. In extreme cases, failure to do so could lead to scenarios where your contract becomes permanently frozen because some external contract it relies on reverts unexpectedly. Here we'll explore ways to handle those reverts.

## Reverts and Call Contexts

To understand what a revert really is, first let's quickly go over how reverts are related to EVM call contexts.

Each time a contract makes an external call (even to itself using `this.fn()` syntax), a new call context is entered. When a revert is encountered in that call, execution within that call context ends immediately and all state changes (aside from gas used) that occurred within that call (including calls it made itself) are undone (hence why it's called a "revert"). If all callers in the call chain use vanilla Solidity calling constructs, reverts will cascade upwards causing the entire transaction to eventually fail.

![call-context-revert](solidity-call-reverts.png)

### Internal Calls

Note that calls to `internal`/`private` functions as well as calls to `public` functions without using `this` (e.g., `foo()` instead of `this.foo()`) are not true calls and will actually be implemented as `JUMP` instructions, effectively running as if they were defined inside the function that called it. This means that they stay within the same call context of the function that called them, so reverting inside them is has the same same effect as reverting inside their caller. As such, the caller cannot actually recover from a revert from an `internal` function since it will never have an opportunity to regain execution control. So these *are not* the types of function calls we're covering here.

## A Tale of Two Reverts

Typically contracts will explicitly revert using the `require()` or `revert()` built-in functions, or the `revert` keyword, which all issue a `REVERT` opcode. This is the recommended way of failing in a contract. As illustrated earlier, this ends execution of the current call context and returns control to the caller, signaling that the call failed with the provided revert data (e.g., the error string parameter to `require()` ).

But there is another, more insidious type of revert that can be raised with the `INVALID` opcode. You will rarely see people throw these intentionally. These types of reverts are sometimes employed by older versions of the solidity compiler when generating safeguarding code, such as checks for integer overflows. EVM violations, such as running out of gas or exceeding the call stack depth will also automatically throw this kind of revert. The critical difference between this type of revert and standard reverts (`REVERT` opcode) is that, with `INVALID`, all gas provided to the call will be consumed! This can have major implications when trying to design a resilient contract which we'll dig into [later](#adding-more-resiliency).

## Handling Reverts

As illustrated earlier, when making a vanilla call through solidity, the compiler will generate code that bubbles up any revert, meaning your function that made the failing call will immediately also revert in response. This revert data is bubbled up unmolested (e.g., no stack trace will be generated), so usually there is no easy way to identify which underlying call the revert originated from while on-chain.

Now let's look at ways to avoid this default behavior and eventually respond to a revert instead of just giving up 😛.

### `try` + `catch`

Solidity `0.6.0` introduced the `try`/`catch` contstruct which lets you handle call reverts with syntax familiar to other languages. Unlike other, visually similar languages, Solidity's `try`/`catch` only wraps *a single external call*, which immediately follows the `try` keyword.

```solidity
try someContract.someFunction(arg1, arg2) returns (uint256 someResult) {
    // Call succeeded. Work on someResult.
} catch (bytes memory revertData) {
    // Call failed. Work on revertData.
}
// Rest of function...
```

If you're used to reverts thrown with `require()` or `revert()` syntax, it may seem odd that `catch()` accepts a `bytes` for the `revertData` instead of a `string`. Indeed, this is the only parameter allowed for `catch()`. We'll dig into why and what this means [later](#inspecting-revert-data).

### Low-Level Calls

Prior to solidity `0.6.0`, low-level calls (or the equivalent assembly) were the only way to capture revert data and bypass the automatic bubbling up of reverts. Low-level calls use the `call()`, `staticcall()`, or `delegatecall()` methods on an `address` type, and we must ABI-encode the call data (which encodes the function to call and the parameters) ourselves. Instead of reverting if the call fails, you get back a tuple `(bool success, bytes returnOrRevertData)`, where the meaning of `returnOrRevertData` depends on whether the function succeeded or not.

```solidity
(bool success, bytes memory returnOrRevertData) = address(someContract).call(
    // Encode the call data (function on someContract to call + arguments)
    abi.encodeCall(someContract.someFunction, (arg1, arg2))
);
if (success) {
    // Process `returnOrRevertData` as encoded return data.
    uint256 someResult = abi.decode(returnOrRevertData, (uint256));
} else {
    // Process `returnOrRevertData` as encoded revert data.
}
```

Now, this is obviously more long-winded and error-prone than `try`/`catch`, which can give you type-safety on the contract, arguments, and return value, rendering low-level calls less appealing. But there are still extremely compelling reasons to use low-level calls as will be demonstrated [next](#adding-even-more-resiliency).

## Inspecting Revert Data

Now that we have prevented automatic failure and have access to the revert data, what can we do with it it?

You'll notice that, in all examples, the revert data is of type `bytes`. If you're used to throwing string reverts via `require()` or `revert()` syntax, you may wonder why this is not just of type `string`. The reason is that revert data (just like return data) can be any sequence of bytes. Using the `revert` keyword (not function) will allow you to throw a custom ABI-encoded error type. In fact, when you throw a string revert, the revert data is not simply the bytes of the string but actually the ABI-encoded call to a function with a signature of `Error(string)`:

```solidity
revert('hello')
// ^ is equivalent to:
error Error(string); // Declare custom error type
...
revert Error('hello'); // Throw custom error type
```

So, let's say we want to act differently if the contract reverts with the string 'foo':

```solidity
try someContract.someFunction(arg1, arg2) returns (uint256 someResult) {
    ...
} catch (bytes memory revertData) {
    if (keccak256(revertData) == keccak256(abi.encodeWithSignature('Error(string)', ('foo')))) {
        // someContract.someFunction() failed with error string 'foo'
        ...
    }
}
```

## Manually Bubbling Up Reverts

In either approach, we've interrupted the compiler default behavior of bubbling up the revert error to our own caller. We may find that we do not want to gracefully handle certain errors and want them to bubble up for the caller above us to handle. Often novice solidity engineers will do something like:

```solidity
(bool success, bytes memory returnOrRevertData) = someContract.call(...);
if (!success) {
    // Try to bubble up the revert data to our caller by force-casting the
    // revert data to a string type because `revert()` only accepts a string.
    // This is wrong!!! 🪲
    revert(string(returnOrRevertData));
}
```

But remember that `returnOrRevertData` can potentially be (and usually is) an ABI-encoded `Error(string)` type, not a string at all (i.e., `08c379a00000000000000000000000000000000000000000000000000000000000000020...`)! And since `revert()` ABI-encodes its argument as an `Error(string)` type, what actually ends up being bubbled up to the caller is a double-encoded `Error(string)` (an error within an error), which makes absolutely no sense. The correct way to bubble up a captured revert without altering the data is to drop to some simple assembly:

```solidity
(bool success, bytes memory returnOrRevertData) = someContract.call(...);
if (!success) {
    // Bubble up the revert data unmolested.
    assembly {
        revert(
            // Start of revert data bytes. The 0x20 offset is always the same.
            add(returnOrRevertData, 0x20),
            // Length of revert data.
            mload(returnOrRevertData)
        )
    }
}
```

### Adding More Resiliency

If your code is calling contracts that you either haven't vetted and/or if those contracts (or one they call) can realistically encounter an `INVALID` opcode, then it might make sense to also add a gas limit to your call. This limit the *maximum* amount of gas the call can consume. This way, you can be sure to still have enough gas remaining after the call returns to perform failover logic. You can do this with both `try`/`catch` and low-level call constructs:

```solidity
// Restrict a try/catch call to 500k max gas.
try someContract.someFunction{gas: 500e3}(arg1, arg2) returns (uint256 someResult) {
    ...
} catch {
    ...
}
// Restrict a low-level call to 500k max gas.
(bool success, bytes memory returnOrRevertData) = address(someContract).call{gas: 500e3}(
    abi.encodeCall(someContract.someFunction, (arg1, arg2))
);
...
```

### Adding Even More Resiliency

There's also sneakier way a call can fail that `try`/`catch` won't be able to handle, because the revert will actually be thrown by code generated by the solidity compiler *as part of your function*. This can happen if:

- You're making a standard (not low-level) function call *that expects no return value* to an address that does not have any code.
    - This is because the compiler will generate code that first asserts that the address has code in it.
    - Perhaps the contract never existed or self-destructed.
- The call returns data that cannot be abi-decoded as the expected return type.
    - To illustrate, say your the function is supposed to return a `uint256` but actually returns 0 data.
    - Perhaps the contract is malicious or implements a token standard incorrectly.

To handle these cases gracefully, we may want to return to low-level calls because:
- The default behavior of performing a call on an address without code is to *succeed* and return empty data.
    - So if the call succeeds and is expected to return something, we can avoid checking if there is code at the contract by simply checking that the return data is non-zero length.
    - *However, be wary that if the call succeeds and is expected to return nothing, and does indeed return nothing, that this is not proof that there is a contract at that address*.
- We can perform validation on the abi-encoded return data before passing it into `abi.decode()` to avoid causing ourselves to revert the way `try`/`catch` would.

```solidity
(bool success, bytes memory returnOrRevertData) = address(someContract).call(
    abi.encodeCall(someContract.someFunction, (arg1, arg2))
);
if (success) {
    if (returnOrRevertData.length >= 32) {
        // Successful and returned a decodable uint256.
        uint256 someResult = abi.decode(returnOrRevertData, (uint256));
        ...
        return;
    }
}
// Either the call failed or the return data was too short to hold a uint256.
...
```

## Who Really Needs This?

Remember that these strategies are only necessary when it's important that your contract be able to gracefully recover from a revert. Also, your contract may not even care what the contents of the revert data are, but may just want to treat any revert equally. Many times, especially for simpler protocols that do not interact with other protocols, not handling the revert and simply allowing the entire transaction to fail is actually the simpler and also perfectly acceptable approach... but not always 😉.

To illustrate a case where this need might arise, take an example of a protocol that tracks an unrestricted basket of assets owned by an address, where you still want users to be able to perform interactions even if one asset in the basket no longer functions (e.g., an ERC721 token getting burned causing `ownerOf()` to fail).

## Runnable Example

The [included example](./PooledExecute.sol) is a contract that will execute an arbitrary call with value (set in the constructor) once enough users have contributed enough ETH via `join()`. If the call fails, everyone who contributed can withdraw their contribution via `withdraw()`.

## References

This guide provides an embarrassingly condensed overview of Solidity reverts and error handling. For the full technical details, visit [the official docs](https://docs.soliditylang.org/en/v0.8.16/control-structures.html#error-handling-assert-require-revert-and-exceptions).
