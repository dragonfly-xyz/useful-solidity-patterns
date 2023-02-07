# Commit-Reveal

- [📜 Example Code](./SealedAuctionMint.sol)
- [🐞 Tests](../../test/SealedAuctionMint.t.sol)

Every transaction mined on Ethereum is a permanent record, visible to anyone. Even transactions in the public mempool, waiting to be mined, can be openly observed. This inherent level of transparency offers a lot in the way of convenience and accountability, but knowing exactly what another user will or has done can also encourage certain adversarial behavior (front/back-running, auction sniping, etc) on the network that can subvert the fairness of your protocol.

We could mitigate a lot of these issues if we somehow had a way to do things in "secret" on Ethereum. The commit-reveal pattern is a simple solution that protocols sometimes implement to allow users to commit to a concealed on-chain action that will be executed later. It often involves the protocol to having separate "commit" and "reveal" phases, with users making two transactions across them:

### The Commit Transaction

During the commit phase, a user first sends a "commit" transaction to the protocol, which binds them to performing a specific action later during the reveal phase. What constitutes a commitment is often just a single hash, which will be the hash of the action details and some large, random, user-chosen salt value (e.g., `commit = keccak256(ACTION, SALT)`). Because hashes are unique™ and non-reversible, without knowing the salt value it's practically impossible to discover which action was chosen to generate the commit hash.


### The Reveal Transaction

During the reveal phase, users must reveal the actions they committed to in the commit phase. Users will submit a second, "reveal" transaction to the protocol, providing the salt and action they used to generate the prior commit hash. The protocol will compute the commit hash and, only if it matches the hash from the commit phase, perform the user's chosen action. Because only actions that have a prior, secret commitment can be performed, an adversary is severely limited in how they can react to or frontrun the action.

## Case Study: Sealed Auction
Let's demonstrate the pattern by creating an "NFT" contract (not an actual ERC721) that has a daily sealed auction mechanism for the right to mint a new token. We'll call the protocol "Nowns" 😉.

Every 24 hours, a new auction kicks off where anyone can place a sealed `bid()` (commit), attaching more ETH than the true bid amount to obscure their actual bid . The `commitHash` should be `keccak(bidAmount, salt)`, where `bidAmount` and `salt` are known only to the caller, and `bidAmount <<< msg.value`.

```solidity
function bid(uint256 auctionId, bytes32 commitHash) external payable {
    require(auctionId == getCurrentAuctionId(), 'auction not accepting bids');
    require(commitHash != 0, 'invalid commit hash');
    require(bidsByAuction[auctionId][msg.sender].commitHash == 0, 'already bid');
    require(msg.value != 0, 'invalid bid');
    bidsByAuction[auctionId][msg.sender] = SealedBid({
        ethAttached: msg.value,
        commitHash: commitHash
    });
}
```

After 24 hours, the bid/commit phase ends and the auction enters the reveal phase, where bidders have another 24 hours to `reveal()` their bid.

```solidity
function reveal(uint256 auctionId, uint256 bidAmount, bytes32 salt) external {
    require(auctionId < getCurrentAuctionId(), 'bidding still ongoing');
    require(!isAuctionOver(auctionId), 'auction over');
    SealedBid memory bid_ = bidsByAuction[auctionId][msg.sender];
    // Ensure the prior commitHash matches the hash of the bid and salt.
    require(bid_.commitHash == keccak256(abi.encode(bidAmount, salt)), 'invalid reveal');
    uint256 cappedBidAmount = bidAmount > bid_.ethAttached
        ? bid_.ethAttached : bidAmount;
    // If caller's bid is > the winning bid amount, they're the new winner.
    uint256 winningBidAmount = winningBidAmountByAuction[auctionId];
    if (cappedBidAmount > winningBidAmount) {
        // Caller is the new winning bidder.
        winningBidderByAuction[auctionId] = msg.sender;
        winningBidAmountByAuction[auctionId] = cappedBidAmount;
    }
}
```

After 48 hours total, the auction is concluded and the highest bidder to reveal can call `mint()` to mint themselves a new token, as well as refund any excess ETH that was attached to their bid.

```solidity
function mint(uint256 auctionId) external {
    require(isAuctionOver(auctionId), 'auction not over');
    address winningBidder = winningBidderByAuction[auctionId];
    require(winningBidder == msg.sender, 'not the winner');
    SealedBid storage bid_ = bidsByAuction[auctionId][msg.sender];
    uint256 ethAttached = bid_.ethAttached;
    require(ethAttached != 0, 'already minted');
    // Set ethAttached to 0 to prevent further minting.
    bid_.ethAttached = 0;
    _mintTo(msg.sender);
    // Refund any excess ETH attached to the bid.
    uint256 refund = ethAttached - winningBidAmountByAuction[auctionId];
    payable(msg.sender).transfer(refund);
}
```

At any point after the bid/commit phase has ended, bidders can call `reclaim()` to reclaim the ETH attached to their losing bid.

```solidity
function reclaim(uint256 auctionId) external {
    require(auctionId < getCurrentAuctionId(), 'bidding still ongoing');
    address winningBidder = winningBidderByAuction[auctionId];
    require(winningBidder != msg.sender, 'winner cannot reclaim');
    SealedBid storage bid_ = bidsByAuction[auctionId][msg.sender];
    uint256 refund = bid_.ethAttached;
    require(refund != 0, 'already reclaimed');
    // Set ethAttached to 0 to prevent double redeeming.
    bid_.ethAttached = 0;
    payable(msg.sender).transfer(refund);
}
```

With a blind auction implemented this way, it's impractical to snipe (bid +1) or frontrun a bid because you don't know the true amount people are bidding until they explicitly reveal it, by which point you can no longer place new bids. The complete, working example can be found [here](./SealedAuctionMint.sol) with [tests](../../test/SealedAuctionMint.t.sol).

## Real-World Usage
[Ethereum Name Service](https://ens.domains/) (ENS) is probably the most recognizable adopter of the commit-reveal scheme. The [original registrar contract](https://etherscan.io/address/0x6090a6e47849629b7245dfa1ca21d94cd15878ef#code) created blind auctions for specific ENS names and had separate commit+reveal phases, similar to our example. [The newer version](https://docs.ens.domains/contract-api-reference/.eth-permanent-registrar/controller) no longer uses an auction mechanism but still employs commit+reveal (masking the name being bought) to prevent front-running of domain purchases.

