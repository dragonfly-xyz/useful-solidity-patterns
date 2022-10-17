# useful-solidity-patterns
---
This repo is an ongoing collection of useful, and occasionally clever, solidity/EVM patterns that actually get used in the wild. These guides are written for busy engineers with better things to do, so there should be minimal cruft, designed to get people running quickly. Guides range from from basic to advanced, are expressed in approachable terms, and presented with self-contained, concise, believable, working examples and tests that you can play with. I ([@merklejerk](https://github.com/merklejerk)) will be adding new patterns weekly but contributions are absolutely welcome!

*The code examples herein are meant to be educational. While the patterns are sound, the examples are not always designed with utmost security or robustness in mind, and sometimes will even forgo best practices in order to best illustrate a concept. They should not be deployed without an independent security review.*

## [Solidity Patterns](./patterns)
- [Advanced Error Handling](./patterns/error-handling)
    - Write resilient code that intercepts and reacts to errors thrown by other contracts.
- [Basic Proxies](./patterns/basic-proxies)
    - Contracts with upgradeable logic.
- [Commit + Reveal](./patterns/commit-reveal)
    - A two-step process for performing partially obscured on-chain actions that can't be front or back runned.
- [EIP712 Signed Messages](./patterns/eip712-signed-messages)
    - Human-readable off-chain messages that can be consumed on-chain.
- [ERC20 (In)Compatibility](./patterns/erc20-compatibility)
    - Working with both compliant and non-compliant (which are more common than you think) ERC20 tokens.
- [ERC20 Permit](./patterns/erc20-permit)
    - Perform an ERC20 approve and transfer in a *single* transaction.
- [`eth_call` Tricks](./patterns/eth_call-tricks)
    - Perform fast, complex queries of on-chain data and simulations with zero deployment cost using `eth_call`.
- [Explicit Storage Buckets](./patterns/explicit-storage-buckets)
    - Safer, guaranteed non-overlapping storage for upgradeable contracts.
- [Factory Proofs](./patterns/factory-proofs)
    - Proving on-chain that a contract was deployed by a trusted deployer.
- [Merkle Proofs](./patterns/merkle-proofs)
    - Storage efficient method of proving membership to a potentially large fixed set.
- [Off-Chain Storage](./patterns/off-chain-storage)
    - Reduce gas costs tremendously by moving contract state off-chain.
- [Packing Storage](./patterns/packing-storage)
    - Arranging your storage variables to minimize expensive storage access.
- Stay tuned for more 😉

## Installing, Building, Testing

Make sure you have [foundry](https://book.getfoundry.sh/getting-started/installation) installed and up-to-date first.

```bash
# Clone the repo
$> git clone git@github.com:dragonfly-xyz/useful-solidity-patterns.git
# Install foundry dependencies
$> forge install
# Run tests
$> forge test -vvv
# Run forked tests
$> forge test -vvv --fork-url $YOUR_NODE_RPC_URL -m testFork
```
