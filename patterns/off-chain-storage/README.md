# Off-Chain Storage

- [📜 Example Code](./OffChainAuction.sol)
- [🐞 Tests](../../test/OffChainAuction.t.sol)

Storage operations often make up the bulk of smart contract execution costs. Even trivial protocols typically need to track multiple states between interactions, which naively requires writing and reading many times to on-chain/contract storage. As a general rule of thumb in EVM land, writing a non-zero value to an empty (zero) slot costs 20k, updating it costs 5k, and reading it can cost between 100-2.1k (thanks, [EIP-2929](https://eips.ethereum.org/EIPS/eip-2929)), so you can see how quickly these things can add up.

There are many gas mitigation strategies around on-chain storage, but there's no denying that the single, most effective way to reduce storage costs is simply not to store things on-chain at all. 😉

## Off-Chain Storage Basics

The idea behind off-chain storage is actually to take a hybrid approach, where we only store *the hash* of our contract's state on-chain, track the full state off-chain, and pass back it in when interacting with our contract. So instead of the usual way of declaring each storage variable inline, we instead:

1. Declare state fields in a "state object" `struct` instead.
2. Store the hash of the state object on-chain.
3. Require users to pass in the full state object for any interactions that rely on state.
4. Validate that the hash of the passed in state object matches our stored hash.
5. For interactions that need to read those storage fields:
    1. Just read it directly from state object in call data or memory, which is very cheap compared to reading from storage.
4. For interactions that need to write to those storage fields:
    1. Update fields in the (in-memory) state object as necessary.
    2. Compute the new hash of the state object and update the on-chain hash.
    3. Emit (and/or return) the updated state object in an event so users can source it and pass it into the their next interaction.

With this approach we can potentially collapse several storage reads and writes into just a single one per interaction.

## Example: NFT Auction House

The provided [example](./OffChainAuction.sol) is a simple NFT (ERC721) auction house protocol that utilizes off-chain state per auction. The user flow is:

- Sellers call `createAuction()` with the auction parameters (NFT, duration, minimum bid, etc).
    - The contract takes custody of the NFT.
    - A new `auctionId` is chosen and an associated `AuctionState` object is created in-memory with the provided parameters and state to track auction progress.
    - Store the hash of the `AuctionState`, indexed by `auctionId`.
    - Emit the full `AuctionState` object.
- Buyers call `bid()` to place an ETH bid, passing in the full `AuctionState` object.
- Anyone can call `settle()` to finalize an auction (after it has expired or completed), also passing in the full `AuctionState` object.
    - In both `bid()` and `settle()`, the `AuctionState` object is hashed and checked against the stored hash for that `auctionId`.
    - All logic just reads from and writes to the in-memory `AuctionState` object, which is cheap.
    - Before returning, overwrite the on-chain state object hash for that `auctionId` with the updated state object's hash.
    - Emit the full, updated `AuctionState` object in an event.

### Comparing to the Naive Solution

The auction house contract tracks the following 8 state variables *per auction*:

```solidity
IERC721 token;
uint256 tokenId;
address payable owner;
uint256 created;
uint256 started;
uint256 duration;
uint256 topBid;
address payable topBidder;
```

Had these storage variables been stored entirely on-chain, to initialize them all together would cost `8 * 20k = 160k` gas and `8 * 5k = 40k` gas to later update. By collapsing them into a single hash, we drop that cost down by a factor of 8 (now `20k` and `5k` respectively)!

## Caveats

While there are massive efficiency gains possible from this approach, relying on off-chain data has some notable disadvantages and concerns.

#### Infra Burden
Since your contract no longer holds the full state variables in storage, your dapp will need some kind of off-chain infrastructure to fetch the full state objects for contract interactions. Fortunately, because we emit events containing the full object, it's fairly trivial to use something like `eth_getLogs` on an archive node (e.g., Alchemy) to grab the latest state object. Without access to an archive node, you can spin up a service that consumes events as they happen and caches the objects.

#### Composability
Other contracts can't build on top of your protocol from a purely on-chain context. The initiating EOA will need to provide the contract with valid off-chain state object(s). Depending on where in the funnel your protocol sits, this pattern might not be as disruptive as it sounds, since many protocols (particularly in defi) already rely on an off-chain component for efficient usage (e.g., Uniswap pool routing).

#### TX Collisions / Stale State
If interactions needing the same state objects are frequent enough, it's possible that two pending transactions will attempt to update/interact with the same state object, causing the second one to fail because the state hash will no longer match what is stored. One way to mitigate against this is to break up your state objects into groups that frequently change together so unrelated interactions don't impact each other's state. This can also be done intentionally to grief other users. In the auction example, the current highest could maintain their top bid by frontrunning higher bidders with 1 wei increments. An improved version might require successive bids to have a minimum % increment to create a disincentivizing cost for this behavior.

#### State Object Constraints
We hash the state object in every function that needs it. This comes with some cost as well, which grows as the state object size increases. It's not a good idea to store large arrays in your state object for this reason, but you can potentially use [merkle proofs](../merkle-proofs) to achieve the same effect in constant space. Additionally, mappings are a storage-only construct that can't be easily encoded in an off-chain state object, though you may be able to invert your data structures to get around this (e.g., use a mapping of state objects instead of a state object with a mapping).
