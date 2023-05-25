# Assembly Tricks (Part 1)
- [🐞 Tests](../../test/AssemblyTricks1.t.sol)

Here's a quick collection of some short and sweet assembly tricks seen in the wild which can save you significant gas and help get around some solidity shortcomings. Remember to be extremely mindful of how and when you use these techniques, as improper implementation and usage of assembly can lead to extremely bad and difficult to find bugs.

## Bubble Up Reverts
There are some commonly used ways to make an external call to another contract (or EOA) where a revert in the call itself doesn't cause your code (the caller) to instantly revert as well:

1. Using low-level `call()`, `delegatecall()`, `staticcall()` semantics.
2. Using `try`/`catch` blocks.

In these scenarios, your code regains execution control after the called function reverts but you receive the error data the call reverted with as an encoded `bytes` array. You may want to [handle certain errors](../error-handling) but not others, re-throwing the error if not. Often people will naively cast the `bytes` error data to a `string` and pass it into `revert()`, but this is actually wrong because it re-encodes the raw error data as a string revert, effectively double-encoding it:

```solidity
// This is the WRONG way to re-throw raw revert data (`revertBytes`) because it
// re-encodes the revert data as an `Error(string)` revert type. 
revert(string(revertBytes))
```

Instead, you can just dip down into assembly to throw the actual error data unmolested (note that this only works if `revertBytes` is in `memory`, which it almost always will be):

```solidity
// Re-throw `revertBytes` revert data as-is.
assembly { revert(add(revertBytes, 0x20), mload(revertBytes)) }
```

Here's what it looks like in the context of a `try`/`catch` call. Easy!
```solidity
try otherContract.foo() {
    // handle successful call...
} catch (bytes memory revertBytes) {
    // call failed, do some error processing
    // if all else fails, bubble up the revert
    assembly { revert(add(revertBytes, 0x20), mload(revertBytes)) }
}
```

## Hash Two Words

Hashing the concatenation of two words (32 byte values) comes up often, like in [traversing merkle trees](../merkle-proofs/). `keccak256()` (the built-in hash function) takes a `bytes` array, so naturally one would concatenate the data they want to hash with an `abi.encode()` first:

```solidity
uint256 word1 = ...;
bytes32 word2 = ...;
// Concatenate `word1` and `word2` then compute their hash.
bytes32 hash = keccak256(abi.encode(word1, word2));
```

This works universally for arbitrary data types and counts, but if you only need to hash two 32-byte values (or values that combined fit into 64 bytes), you can use some quick assembly to do the same thing for significantly cheaper:

```solidity
bytes32 hash;
assembly {
    mstore(0x00, word1)
    mstore(0x20, word2)
    hash := keccak256(0x00, 0x40)
}
```

This is cheaper than the vanilla `keccak256(abi.encode())` method because `abi.encode()` allocates a new memory buffer to concatenate the two values together into, to eventually pass into `keccak256()`. The assembly version instead just concatenates the values in the first 2 words of memory (`0x00`-`0x40`), which are considered freely usable scratch space, avoiding expanding memory entirely.

## Casting Between Array Types

Solidity won't let you directly cast entire arrays of different element types (with an exception between `bytes` and `string` types). If you're importing third-party libraries in your build you can sometimes run into a scenario where an imported function accepts a different array type from what you use within your own code, but you know that they are fundamentally bit-compatible. Examples include:

- `address[]` vs `address payable[]`
- `address[]` vs `interface[]`
- `address[]` vs `contract[]`
- `uint160[]` vs `address[]`
- `uint256[]` vs `bytes32[]`
- `uint256[N]` vs `bytes32[N]` 
- etc.

Naively, you could do these conversions by recreating the array and casting each element, but duplicating the array is pretty wasteful for obvious reasons:

```solidity
// Doing a conversion between compatible array types the hard way.
address[] memory addressArr = ...;
IERC20[] memory erc20Arr = new IERC20[](addressArr.length);
for (uint256 i; i < addressArr.length; ++i) {
    erc20Arr[i] = addressArr[i];
}
```

Under the hood, stack variables holding `memory` arrays are just pointers to memory locations, and assembly lets you set this pointer value directly. Thus, you can very easily satisfy the needs of the previous example with:

```solidity
// Cheaply cast between compatible dynamic arrays. 
address[] memory addressArr = ...;
IERC20Token[] memory erc20Arr; // No need to allocate new memory.
// Point `erc20Arr` to the same location as `addressArr`
assembly { erc20Arr := addressArr }
```

This also works between statically sized `memory` arrays, though this is a bit less efficient than with dynamic arrays because declaring a statically sized array will also immediately allocate new memory for it:

```solidity
// Cheaply cast between compatible statically sized arrays. 
address[3] memory addressArr = ...;
IERC20Token[3] memory erc20Arr;
// Point `erc20Arr` to the same location as `addressArr`
assembly { erc20Arr := addressArr }
```

Note that these approaches *won't* work with `calldata` arrays, which have completely different pointer semantics.

## Casting Between Structs

You can also cast between *compatible* `memory` structs as well using the prior array casting trick:

```solidity
struct Foo {
    address addr;
    uint256 x;
}

// All fields in `Bar` are bit-compatible with `Foo`. 
struct Bar {
    IERC20 erc20;
    bytes32 x;
}

Foo memory foo = MyStruct({...});
// Point `bar` to the contents of `foo`.
Bar memory bar;
assembly { bar := foo }
```

Structs and statically sized arrays are actually closely related memory-wise so this approach incurs the same wasted memory expansion cost as with statically sized arrays, but still saves the cost of manually copying fields.

## Shortening Dynamic Memory Arrays
The first 32-bytes/word of the memory location pointed to by a dynamically sized `memory` array variable holds the length of the array, with the elements following directly after.

```
                               ┌────────────────────────┐
arr = new uint256[N]() ───────►│      Length = N        │  ptr + 0x00
                               ├────────────────────────┤
                               │      Element 0         │  ptr + 0x20
                               ├────────────────────────┤
                               │      Element 1         │  ptr + 0x40
                               ├────────────────────────┤
                               │         ...            │
                               ├────────────────────────┤
                               │      Element N         │  ptr + 0x20 * N
                               └────────────────────────┘
```


Using assembly, you can write directly to this location to change the stored length of the array! ⚠️ Keep in mind that it's usually only safe to resize an array *shorter* since resizing it longer could cause you to read from or write to a memory location that has been provisioned for another variable ⚠️.



```solidity
uint256[] memory arr = new uint256[](100);
assert(arr.length == 100);
// Shorten the `arr` dynamic array by 1 (ignoring the last element).
assembly { mstore(arr, 99) }
assert(arr.length == 99);
```

This modifies the array in place, so double check that other areas of your code do not expect the array length to remain the same.

## Shortening Statically Sized Memory Arrays

Statically sized arrays *do not* store a length prefix because it's already known at compile-time, so the above approach will not work for them. But you can use the array casting trick to create a fixed-length reference to a subset of the original array. Again, this does require a new variable declaration, which for statically sized arrays needlessly expands memory, but you still avoid having to copy each element this way:

```solidity
uint256[10] memory arr;
// Shorten the `arr` fixed array by 1 (ignoring the last element).
uint256[9] memory shortArr;
assembly { shortArr := arr }
```

Because statically sized arrays don't have a length prefix, you can technically even point the new variable to an offset within the original array to create a shared slice!

```solidity
uint256[10] memory arr;
// Create a shared slice of the original array, starting at the 2nd (idx 1) element to the 9th (idx 8).
uint256[8] memory shortArr;
assembly { shortArr := add(arr, 0x20) }
```

