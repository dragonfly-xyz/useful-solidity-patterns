# Explicit Storage Buckets

- [📜 Example Code](./ExplicitStorageBuckets.sol)
- [🐞 Tests](../../test/ExplicitStorageBuckets.t.sol)

Upgradeable contracts, contracts which can replace their bytecode, are an extremely common pattern these days due to their flexibility. This pattern is usually accomplished by using a thin "proxy" contract that uses the `delegatecall` opcode to run another contract's bytecode in the proxy's execution context, such that the proxy's state (address, storage, balance, etc) is inherited.

## Storage Slots

To get a better understanding of the problem and solution, It's helpful to have a basic understanding of how storage works in the EVM and the solidity compiler.

Storage in the EVM is slot based, with each slot being 32 bytes wide. Any 256-bit number is a valid slot index. There is no requirement that storage is used contiguously, meaning you can read and write to any slot at any time. Additionally, the solidity compiler will attempt to pack adjacent storage variables into the same slot if they can all fit in 32 bytes.

![storage slots](./storage-slots.png)

## Footguns

Shared storage state is particularly precarious for a few reasons:
- Upgrading a proxy's implementation will only effectively replace the bytecode but not the storage state. Meaning if the storage layout for the implementation contract changes (say a new storage variable was inserted), it may read/write from invalid storage slots and offsets.
- The compiler will only safely stack storage variables from contracts that inherit from one another. It is not obvious to the compiler that a proxy contract and its implementation contract will actually share the same state. So it's very possible storage slots used by the proxy will unintentionally overlap with those used by the implementation contract, leading to corrupted data.

## Take Destiny Into Your Own Hands

The compiler can't know that you're intending to use your contracts in a proxy pattern, but you do. So, rather than relying on the compiler to assign storage slots, you can manually define "storage buckets" that point to explicit storage slots of your choosing. Because the 256-bit integer space is so vast, choosing a unique hash for the starting slot of your storage bucket will never overlap with any automatically assigned slot, nor any other storage bucket should you decide to use this pattern across multiple contracts that share the execution context.

Storage buckets are implemented by defining a `struct` type that holds all the fields you would normally define at the root level of your contract as storage variables. You can even define non-primitive and non-contiguous types (e.g., mappings, arrays, other structs) in the bucket struct and they will inherit the benefits. Also, the compiler will still tightly pack adjacent fields in structs, so you still benefit from slot optimization.

To get a reference to the storage bucket, some low level assembly is used to manually point a reference to this struct to a storage slot. From there you can access your storage variables through familiar struct syntax.

```solidity
contract StorageBucketExample {
    struct Storage {
        // Declare your private storage variables here rather than in the contract.
        uint256 foo;
    }

    constructor(uint256 foo_) {
        _getStorage().foo = foo_;
    }

    function foo() external view returns (uint256) {
        return _getStorage().foo;
    }

    function _getStorage() private pure returns (Storage storage stor) {
        assembly {
            // This value is just the hash of 'StorageBucketExample.Storage'
            stor.slot := 0x25440fdf23e3d55e3155d04a31ec5db1619e37c5a77b5eccf89b670f03ab1382
        }
    }
}
```

## Real World Usage

- As far as I know, the first major protocol to use this pattern in production is the [0x V4 contracts](https://github.com/0xProject/protocol/tree/development/contracts/zero-ex/contracts/src/storage).
- There is also a newer standard for upgradable contracts called the ["diamond proxy"](https://eips.ethereum.org/EIPS/eip-2535) which leverages storage buckets.
- The [Standard Proxy Storage Slots](https://eips.ethereum.org/EIPS/eip-1967) standard, which is implemented by many simple proxies in the wild, is a spiritual precursor to this pattern because it explicitly chooses a storage slot to store its implementation address.

## Example

The [example code](./ExplicitStorageBuckets.sol) provided here implements an extremely basic upgradable wallet using a proxy. The intent is that after creation, it can be initialized *exactly once* to set the list of addresses allowed to withdraw ETH from the wallet. However, there are two proxy contracts given, one of which (`UnsafeProxy`) is vulnerable to a reinitialization attack because it relies on compiler-assigned storage slots that overlap with the implementation contract's storage variables. The safe version (`SafeProxy`) is not vulnerable because it uses explicit storage buckets. The successful execution of this attack is demonstrated in the [tests](../../test/ExplicitStorageBuckets.t.sol).
