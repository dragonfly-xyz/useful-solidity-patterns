# useful-solidity-patterns
---
This repo is an ongoing collection of useful (and sometimes clever) solidity/EVM patterns, actually used in the wild, ranging from basic to advanced, demonstrated with concise, working examples and tests. I ([@merklejerk](https://github.com/merklejerk)) will be adding new patterns weekly but contributions are absolutely welcome!

The code examples herein are meant to be educational. Most have not been audited and are not intended to be deployed as-is without an independent security review.

## [Solidity Patterns](./patterns)
- [Advanced Error Handling](./patterns/error-handling)
    - Write resilient code that intercepts and reacts to errors thrown by other contracts.
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
```
