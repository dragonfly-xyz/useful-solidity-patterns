# Factory Proofs

- [📜 Example Code](./FactoryProofs.sol)
- [🐞 Tests](../../test/FactoryProofs.t.sol)

Many protocols deploy multiple, interoperable contracts which are not known/established at launch. Well-known examples can be found amongst the various [Uniswap](https://github.com/Uniswap/v2-core/blob/master/contracts/UniswapV2Factory.sol#L23) versions and forks, which all deploy a distinct pool contract for each token pair. Within these protocols, these contracts are often given implicit trust to be well-behaved (e.g., the amount returned by a swap call is what you actually received).

Another, more exotic/extreme example is buried deep within the 0x protocol, which has a concept of pluggable "transformer" contracts chosen by the caller [that will actually be `delegatecall`ed into](https://github.com/0xProject/protocol/blob/development/contracts/zero-ex/contracts/src/features/TransformERC20Feature.sol#L272). Obviously it's highly risky to `delegatecall` into arbitrary contracts so the protocol only allows contracts that have been deployed by a fixed address they control.

Usually some kind of factory pattern is used to both deploy and validate the authenticity of a contract on-chain. The naive approach is just to always deploy through a factory contract and store a mapping of valid deployed addresses inside of it, which can be looked up later. This was the approach with Uniswap V1. However, this has some storage and indirection gas overhead associated with both deploying and validating.

## `CREATE2` Proofs

From Uniswap V2 onward, the `CREATE2` opcode was used by factories to deploy pool contracts, which meant pool addresses could be deterministic, provided the creation salt was unique for each one. Under `CREATE2` semantics, the address of a deployed contract will be given by:

```solidity
address(keccak256(abi.encodePacked(
    bytes1('\xff'),
    address(deployer),
    bytes32(salt),
    bytes32(keccak256(type(DEPLOYED_CONTRACT).creationCode))
)))
```

So long as you are given (or can derive) the unique salt for an instance of `DEPLOYED_CONTRACT`, you can simply perform this hash on-chain to validate that the address in question was deployed by `deployer` and can be trusted-- no storage lookups required!

## `CREATE` Proofs

But what if you don't want to use a factory contract (`CREATE2` can only be performed by a contract), or maybe you don't really need fully deterministic addresses, or you're working with a legacy protocol/factory? You can still prove on-chain, without lookups, that a contract was deployed by a certain address if you know the account nonce of the deployer when it deployed the contract.

This is possible because even `CREATE` addresses are also somewhat deterministic, though a user has less direct control over it than with `CREATE2`. Under `CREATE`, the only inputs to deriving a deployment address are (1) the deployer's address and (2) the deployer's account nonce at the time of deployment, which are simply RLP-encoded and hashed:

```solidity
// For how to implement rlpEncode, see: https://github.com/ethereum/wiki/wiki/RLP
address(keccak256(rlpEncode(deployer, deployerAccountNonce)))
```

For EOAs (externally owned accounts), the account nonce starts at `0` and increments for each transaction they send that gets mined. For smart contracts, the account nonce starts at `1` and increments for each successful call to `CREATE` they make. In either case, you can use the [`eth_getTransactionCount` JSONRPC command](https://ethereum.org/en/developers/docs/apis/json-rpc/#eth_gettransactioncount) on a provider/node to obtain the account nonce of an address at any block.


## Example

The [example code](./FactoryProofs.sol) provided here demonstrates how to validate both kinds of deployments on-chain. `verifyDeployedBy()` verifies an address was deployed by a deployer under `CREATE` opcode semantics and `verifySaltedDeployedBy()` verifies an address was deployed by a deployer under `CREATE2` semantics.
