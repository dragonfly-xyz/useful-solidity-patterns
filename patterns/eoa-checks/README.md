# EOA (Externally Owned Account) Checks
- [📜 Example Code](./KingOfTheHill.sol)
- [🐞 Tests](../../test/KingOfTheHill.t.sol)

Externally Owned Accounts (EOAs) describe network addresses whose address is derived from a private key. They are not contracts and can never become a contract. In layman's terms, these are regular (non-smart) wallets, such as Metamask accounts, hardware wallets, and paper wallets. In contrast, wallets like Argent and Gnosis Safe are "smart" wallets, where the account addresses actually hold code.

Developers often need to consider whether the addresses they interact with are EOAs or could potentially be smart contracts. Understanding the different quirks and consequences between each is essential to writing a robust and defensive protocol. Let's quickly go over the more consequential differences and explore how they can impact your contract.

### Calls To
Any function call to an address without code at it will always succeed, but no code will be executed and no data will be returned. For functions that have no return value, this behavior can be indistinguishable from a call to a contract that actually implements the function, because no return data is expected anyway. So knowing whether an address being called is or is not a contract can be critical in those scenarios.

### Calls From
True EOAs (backed by a private key) can [currently](https://eips.ethereum.org/EIPS/eip-3074) only make a single direct function call *per transaction*, whereas contract callers do not have this limitation. Reentrancy attacks, arbitrage, oracle manipulations, flash loan attacks, etc, are much easier and more profitable to perform from inside a smart contract within a single transaction than over multiple transactions directly from an EOA. This is why most major exploits will first deploy an exploit contract to perform all the logic in one go.

### ETH transfers
At the EVM level, plain ETH transfers (e.g., `address(receiver).transfer(1 ether)`, `address(receiver).send(1 ether)`, or `address(receiver).call{value: 1 ether}("")`) boil down to an empty function call (i.e., with no call data). As described previously, calls to EOAs will always succeed here and do nothing. But if the target is actually a contract, it will run the contract's bytecode, which allows them to gain execution control and perform whatever actions they wish, assuming they have enough gas to do so. Aside from using this opportunity to perform a reentrancy exploit, the contract could also simply revert, which might cause your contract to become deadlocked.

### Token Transfers
Some token standards allow for transfer handlers, where they will call a standard function (e.g., `onERC721Received()`) on the recipient in order to react to a token transfer (similar to how ETH transfers can trigger code execution). So some token transfers to contracts will also suffer from the same risks as ETH transfers.

### Stuck Assets
Assets (ETH, ERC20s, ERC721s, etc.) held by an EOA are almost always accessible and transferrable by whomever knows the private key. On the other hand, smart contracts are not controlled by a private key. If a contract does not expose functions to directly interact with an asset it holds, they may become permanently stuck in that contract. This is one of the motivations for token standards like `ERC721` and `ERC1155` having "safe" transfer functions that require a contract recipient to respond to an on-transfer hook to signal deliberate support for receiving tokens.

It should be clear by now that interactions with smart contracts are generally considered more risky because their behavior is less predictable and can kick off complex interactions that your protocol may not be designed to handle. But it can sometimes be equally disastrous to interact with an EOA when you expect a contract. For these reasons, some contracts will opt to impose restrictions on the types of accounts they interact with. But how do you identify them?

## `ADDRESS.code.length` Check
It's actually quite simple to check if an address has code in it, and is therefore a contract. Solidity exposes this with the `ADDRESS.code.length` syntax, which returns the (byte) size of the code at that `ADDRESS`. If this value is nonzero, there is a smart contract there.

```solidity
 function _isContractAt(address a) view returns (bool) {
    return a.code.length != 0;
 }
 ```

It's important to understand that this check does not guarantee that the address is an EOA. It only checks if there is code at the address *presently*. It may not be an EOA but a yet-to-be deployed contract address (which are in fact [deterministic](../factory-proofs/)). A contract could even be deployed to that address in the same transaction, right after you've performed this check and lost execution control. It's also possible for a contract to `selfdestruct()` its code away and have it reinstated with `CREATE2`. Therefore, this specific approach is considered a weak EOA check and is usually reserved for non-critical sanity checks or where it only matters that an address is not a contract during a brief call window.

 ## `tx.origin` Check
 This is a reliable and cheap way to guarantee that an address is a *certain* EOA. In solidity, `tx.origin` returns the address that signed the current transaction, which must always be an EOA. Thus, if an address in question is equal to `tx.origin`, you can be sure it's an EOA and will always be one. You will frequently see this check as a modifier on user-facing functions that seek to minimize their attack surface by ensuring that they can only be called by an EOA.
 
 ```solidity
 modifier onlyEOA() {
    require(tx.origin == msg.sender, 'only EOA can call');
    _;
 }
 ```
 
 Keep in mind that this check can only draw a definitive conclusion if the address matches `tx.origin`. Addresses that do not match `tx.origin` can still be EOAs.

 ## Transaction Proofs

 Assuming your contract has access to historical a block hash where an EOA has made a transaction, there's another definitive, albeit obscure and extremely technical, way to check that it is an EOA which doesn't require it to be the current `tx.origin`.

 Every mined Ethereum block is uniquely identified by a "block hash," which is essentially analogous to the hash of the [properties](https://ethereum.org/en/developers/docs/apis/json-rpc/#eth_getblockbyhash) that make up an Ethereum block. The one block property we're most interested here is the `transactionsRoot`. This is a [merkle root](../merkle-proofs/) of all the transactions (actually their hashes) that have been included in that block. Because only EOAs can sign/originate transactions, you can theoretically prove that an arbitrary address is an EOA if you supply proof to your contract that a transaction sent by the address in question is part of a verifiable block hash.
 
 The details of this approach are a bit of a rabbit hole so we won't go much deeper. But in case you do decide to explore it yourself, let me warn you that this approach is only immediately feasible with transactions that were mined in the last [256 blocks](https://docs.soliditylang.org/en/v0.8.17/units-and-global-variables.html#block-and-transaction-properties) on mainnet. Anything older than that, while not impossible, will require extra legwork. 

## Do You Really Need EOA Checks?
These checks are often employed as a security shortcut to mitigate reentrancy, composability attacks (e.g., arbitrage or oracle manipulation), or to just add a speed bump to certain operations (e.g., preventing a contract from minting multiple NFTs in a transaction). Depending on the type of check you use and where you use it, this protection may only be partial. It's important to be aware that EOAs can still perform multiple, direct calls in a single block (but across different transactions), which has been made even easier with the introduction of [flashbot bundles](https://docs.flashbots.net/flashbots-auction/searchers/advanced/understanding-bundles). Still, many developers will continue to opt for this strategy and it's hard to fault them because these checks are fairly cheap, can often reduce the attack surface, and sometimes partial protection is better than none at all, especially in relatively low-stakes applications.

There is a major downside to using EOA checks, and that is in limiting your protocol's composability with other contracts which may try to build on top of yours. Some audiences also have a meaningful share of users that transact from smart wallets, which could be excluded from participating. But not all protocols need to worry about composability, and they may be OK with excluding smart wallet users. It really depends on who you think will be consuming your protocol.

Another point to make is that most attack vectors that EOA checks are used to mitigate can often be better addressed through specific fixes (like reentrancy guards, timelocks, pull patterns, etc), which will not impose restrictions on what kinds of addresses your contract can interact with.

## The Demo
The [demo](./KingOfTheHill.sol) showcases 3 contracts that implement an on-chain king-of-the-hill game. Becoming king costs ETH and lets you set a custom message on the contract. Anyone can become the new king by paying more than the last king did through `takeCrown()`. The amount paid by the new king goes to the old king, and so on.

The naive version, `BrickableKingOfTheHill`, is vulnerable to a denial-of-service attack if the previous king is a contract that reverts when it receives ETH. This causes the call to `takeCrown()` to fail when the payment is sent to the old king (see the [tests](../../test/KingOfTheHill.t.sol#L48) for an example). The result is that the evil contract king remains king forever. The `OnlyEOAKingOfTheHill` version fixes this by simply adding an `onlyEOA` modifier to `takeCrown()`. This ensures that the every king is, and always will be, an EOA, which cannot revert on ETH transfers. The `ClaimableKingOfTheHill` version also fixes this by only sending ETH to the last king if they have no code at their address, otherwise it will set aside the ETH for the last king to `claim()` it in a separate call.
