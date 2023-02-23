# useful-solidity-patterns
---
This repo is an ongoing collection of useful, and occasionally clever, solidity/EVM patterns that actually get used in the wild. These bite-sized guides are written in approachable terms so engineers of all skill levels can understand them. Every guide comes with a concise, self-contained, working code example and tests to demonstrate the pattern. New patterns are added regularly.

*The code examples herein are meant to be educational. While the patterns are sound, the examples are not always designed with utmost security or robustness in mind, and sometimes will even forgo best practices in order to best illustrate a concept. They should not be deployed without an independent security review.*

## [Solidity Patterns](./patterns)
- [ABI Decode With Selector](./patterns/abi-decode-with-selector/)
    - Techniques for decoding function call data and revert errors. 
- [Advanced Error Handling](./patterns/error-handling)
    - Write resilient code that intercepts and reacts to errors thrown by other contracts.
- [Assembly Tricks (Part 1)](./patterns/assembly-tricks-1)
    - Short, useful assembly tricks to save some gas and make up for solidity shortcomings.
- [Basic Proxies](./patterns/basic-proxies)
    - Contracts with upgradeable logic.
- [Big Data Storage (SSTORE2)](./patterns/big-data-storage)
    - Cost efficient on-chain storage of multi-word data accessible to contracts.
- [Commit + Reveal](./patterns/commit-reveal)
    - A two-step process for performing partially obscured on-chain actions that can't be front or back runned.
- [EIP712 Signed Messages](./patterns/eip712-signed-messages)
    - Human-readable off-chain messages that can be consumed on-chain.
- [ERC20 (In)Compatibility](./patterns/erc20-compatibility)
    - Working with both compliant and non-compliant (which are more common than you think) ERC20 tokens.
- [ERC20 (EIP-2612) Permit](./patterns/erc20-permit)
    - Perform an ERC20 approve and transfer in a *single* transaction.
- [`eth_call` Tricks](./patterns/eth_call-tricks)
    - Perform fast, complex queries of on-chain data and simulations with zero deployment cost using `eth_call`.
- [Explicit Storage Buckets](./patterns/explicit-storage-buckets)
    - Safer, guaranteed non-overlapping storage for upgradeable contracts.
- [Externally Owned Account Checks](./patterns/eoa-checks)
    - The consequences of interacting with contracts vs regular wallets, and how to identify them.
- [Factory Proofs](./patterns/factory-proofs)
    - Proving on-chain that a contract was deployed by a trusted deployer.
- [Initializing Upgradeable Contracts](./patterns/initializing-upgradeable-contracts)
    - Methods to safely and efficiently initialize state for proxy contracts.
- [Merkle Proofs](./patterns/merkle-proofs)
    - Storage efficient method of proving membership to a potentially large fixed set.
- [Multicall](./patterns/multicall)
    - Allow users to arbitrarily compose and perform multiple operations on your contract in a single transaction.
- [NFT Receive Hooks](./patterns/nft-receive-hooks)
    - Use ERC721/ERC1155 transfer callbacks to avoid having users set an allowance in advance.
- [Off-Chain Storage](./patterns/off-chain-storage)
    - Reduce gas costs tremendously by moving contract state off-chain.
- [OnlyDelegateCall / NoDelegateCall](./patterns/only-delegatecall-no-delegatecall/)
    - Restrict functions from being called from only within in a delegatecall context or not.
- [Packing Storage](./patterns/packing-storage)
    - Arranging your storage variables to minimize expensive storage access.
- [Permit2](./patterns/permit2)
    - Transfer tokens securely without a direct allowance, in a way that works for all (legacy and modern) ERC20s.
- [Read-Only Delegatecall](./patterns/readonly-delegatecall)
    - Execute arbitrary delegatecalls in your contract in a read-only manner, without side-effects.
- [Separate Allowance Targets](./patterns/separate-allowance-targets/)
    - Avoid having to migrate user allowances between upgrades with a dedicated approval contract.
- [Stack-Too-Deep Workarounds](./patterns/stack-too-deep/)
    - Clean solutions for getting around and avoiding stack-too-deep errors. So clean that you should do them regardless!
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
