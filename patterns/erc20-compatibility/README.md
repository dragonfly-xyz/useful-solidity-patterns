# ERC20 (In)Compatibility

- [📜 Example Code](./ERC20Compatibility.sol)
- [🐞 Tests](../../test/ERC20Compatibility.t.sol)

Inevitably, anyone writing smart contracts on Ethereum will have to interact with ERC20s. On its surface the [standard](https://eips.ethereum.org/EIPS/eip-20) seems straightforward enough, but inconsistencies in how the standard has been historically implemented can completely break critical components of a protocol. These inconsistencies aren't confined to uncommon tokens, either. For a real-world example, try trading [USDT on Uniswap V1](https://etherscan.io/address/0xc8313c965C47D1E0B5cDCD757B210356AD0e400C) 😉.

This guide will cover the two issues most developers working with arbitrary ERC20 tokens will run into and how to get around them.

## Inconsistent Return Value Behavior

According to the standard, all state modifying ERC20 functions should return a single `bool`, indicating success. Thus, if the operation fails, the function should either return `false` or simply revert. Typically ERC20 contracts will elect to (whether they want to or not) revert on failure (e.g., when attempting to transferring beyond a balance), but a few will instead choose to return `false` when it can. Thus, it's important to also check the return value of the call.

Where things go especially awry is when some tokens ([USDT](https://etherscan.io/address/0xdac17f958d2ee523a2206206994597c13d831ec7#code), [BNB](https://etherscan.io/address/0xB8c77482e45F1F44dE1745F52C74426C631bDD52#code), and more) define ERC20 functions that will revert on failure and do not return *any* value on success. If you interact with these contracts through a generic, compliant ERC20 interface your calls will revert when they attempt to decode the `bool` return value, because it sometimes isn't there.

To properly handle these cases ourselves, we need to use [low-level call](https://docs.soliditylang.org/en/v0.8.17/units-and-global-variables.html#members-of-address-types) semantics so the return value is not automatically decoded. Only if it exists should we attempt to decode it and check that it is `true`. Example:

```solidity
// Attempt to call ERC20(token).transfer(address to, uint256 amount) returns (bool success)
// treating the return value as optional.
(bool success, bytes memory returnOrRevertData) =
    address(token).call(abi.encodeCall(IERC20.transfer, (to, amount)));
// Did the call revert?
require(success, 'transfer failed');
// The call did not revert. If we got enough return data to encode a bool, decode it.
if (returnOrRevertData.length >= 32) {
    // Ensure that the returned bool is true.
    require(abi.decode(returnOrRevertData, (bool)), 'transfer failed');
}
// Otherwise, we're gucci.
```

### Libraries

The above solution is the same for all mutating ERC20 functions and modern solidity syntax is clear enough that implementing universal handling of ERC20 tokens yourself is not too intense. But for a more foolproof, out-of-the-box solution, you should just integrate [OpenZeppelin's `SafeERC20` library](https://docs.openzeppelin.com/contracts/4.x/api/token/erc20#SafeERC20), which wraps all ERC20 functions with "`safe`" variants that do the work for you.

## Inconsistent Approval Behavior

Another quirk found in some prominent ERC20s has to do with setting allowances. On ERC20s, allowances are set by calling the `approve(spender, allowance)` function, which allows a `spender` to transfer up to `allowance` number of the caller's tokens. Normally, calling `approve()` will simply overwrite the previous allowance with the new one. However, some tokens (USDT, KNC, and more), will only allow changes in `allowance` either from or to `0`. That is, if you have allowance `X` (where `X != 0`), in order to set it to `Y` (where `Y != 0`), you must first set it to `0` 😵. This is a precaution to mitigate a rare front-running attack [outlined here](https://docs.google.com/document/d/1YLPtQxZu1UAvO9cZ1O2RPXBbT0mooh4DYKjA_jp-RLM/edit#heading=h.b32yfk54vyg9).

So for universal support when updating allowances, you should also (in addition to handling the optional return value) first clear an allowance before setting it to a non-zero value:

```solidity
// Updating spender's allowance to newAllowance, compatible with tokens that require it
// to be reset first. Assume _safeApprove() is a wrapper to approve() that performs the
// optional call return value check as described earlier.
_safeApprove(token, spender, 0); // Reset to 0.
if (newAllowance != 0) {
    _safeApprove(token, spender, newAllowance); // Set to new value.
}
```

## Resources

This guide highlights the two most common integration issues when working with arbitrary ERC20s on Ethereum mainnet, but for more exotic applications there can be others. For a more exhaustive list of ERC20 issues check out this excellent [Weird ERC20 Tokens repo](https://github.com/d-xo/weird-erc20).
