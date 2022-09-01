# `eth_call` Tricks

- Example code:
    - [📜 swap forwarder](./swap-forwarder/)
    - [📜 swap forwarder with wallet unlock](./wallet-unlock-swap-forwarder/)

`eth_call` is a commonly used JSONRPC command on EVM nodes/providers. When a dapp wants to evaluate the return value of a read-only (`view` or `pure`) function on a smart contract, the underlying web3 library will make a JSONRPC `eth_call` command on the provider (Alchemy, Infura, your own node, etc). At the other end, the node handling the request will execute the function call (but not mine it) and return its result.

But there's so much more to this command than most people realize! Here I'm going to showcase tricks used by MEV bots, aggregators, data platforms, and more.

## Evaluating Non-view Functions

Surprisingly few web3 devs realize that `eth_call` doesn't just work on read-only functions; it works on any function! Every major web3 library has the ability to do evaluate any non-read-only contract function via `eth_call`:

```ts
// Assuming `doSomething()` is a non-view, non-pure function on a contract that
// returns a some value(s).

// making an eth_call in web3.js:
result = await contract.doSomething(...ARGS).call();

// making an eth_call in ethers.js:
result = await contract.callStatic.doSomething(...ARGS);
```

This can be extremely useful for simply checking if a transaction will succeed or not before you waste gas submitting it to the mempool, or if you need to anticipate the return value of that call.

## Impersonating Other Accounts and Balances

`eth_call` also allows you to override the address you're calling from as well as attach any amount of ether to the call, regardless of how much the calling address actually has.

```ts
// overriding the caller and attaching arbitrary ETH to the call in web3.js:
result = await contract.doSomething(...ARGS).call({ from: SOMEONE_ELSE, value: ONE_ETHER });

// overriding the caller and attaching arbitrary ETH to the call in ethers.js:
result = await contract.callStatic.doSomething(...ARGS, { from: SOMEONE_ELSE, value: ONE_ETHER });
```

## Geth Overrides

Now onto the really interesting stuff!

Geth nodes (which back Infura, Alchemy, and are the dominant node forked by sidechains/L2s) support extended parameters that can be passed into the `eth_call` JSONRPC command. These parameters let you to override different aspects of the EVM state when the call is being simulated, including:

- The ETH balance of any address.
- The account nonce of any address.
- The bytecode at any address.
- The value of a storage slot in any address.

Most web3 libraries will not conveniently expose the ability to use these overrides out of the box, but you can still submit them with some low level cleverness.

```ts
// geth's state overrides object
STATE_OVERRIDES = {
    [ADDRESS_TO_OVERRIDE]: {
        // Note: All fields are optional.
        balance: FAKE_BALANCE,
        nonce: FAKE_NONCE,
        code: FAKE_BYTECODE_HEX,
        stateDiff: { [SLOT_NUMBER_HEX]: FAKE_SLOT_VALUE_HEX, ...OTHER_SLOT_OVERRIDES },
    },
    ...OTHER_ADDRESS_OVERRIDES,
};
TX_OPTS = {
    to: TARGET_CONTRACT_ADDRESS,
    from: CALLER_ADDRESS,
    value: ETH_ATTACHED_HEX,
    gas: GAS_LIMIT_HEX,
    gasPrice: GAS_PRICE_HEX,
};

// making an eth_call with state overrides in web3.js:
// just need to do this bit once.
web3.eth.extend({ property: 'gethCall', methods: [{ name: 'eth_call', params: 3 }] });
// `result` will be ABI-encoded return value of the function call.
result = await web3.eth.gethCall(
    {
        data: contract.doSomething(...ARGS).encodeABI(),
        ...TX_OPTS,
    },
    'pending',
    STATE_OVERRIDES,
);

// making an eth_call with state overrides in ethers.js:
// `result` will be ABI-encoded return value of the function call.
result = await provider.send(
    'eth_call',
    [
        {
            ...contract.populateTransaction.doSomething(...ARGS),
            ...TX_OPTS,
        },
        'pending',
        STATE_OVERRIDES,
    ],
);
```

For the full rundown of parameters available to `eth_call`, including state overrides, under geth, see [their JSONRPC docs](https://geth.ethereum.org/docs/rpc/ns-eth). All the possible overrides are incredibly powerful in their own right, but I think the most exciting one is the `code` override, which is what we'll be exploring next.

### Fake Deploying a Contract

By overriding the `code` state at an empty (undeployed) address, any calls made within the `eth_call` to that address will act as if a contract is deployed there. This also works on the contract you are calling directly.

But why would you want to call a contract that doesn't actually exist on-chain? Often protocols will actually deploy helper contracts to support queries needed by their frontends and backends. By using this functionality of geth's `eth_call`, you can avoid having to spend time or money deploying an query/helper contract for your off-chain services!

Also, remember that `eth_call` only lets you execute a single function call, and nothing you do in that call will persist (because it isn't mined). So if you want to simulate complex interactions, spanning multiple, dependent function calls across different contracts, you can use a custom, fake-deployed contract as a middleman (we'll call it a "Forwarder" contract) to perform all that logic atomically and report the results in its return value(s).

#### Example: Simulating Complex Swaps

Let's look at an example forwarder contract that outputs the result of a complex ETH -> USDC -> DAI swap between Sushiswap and Uniswap (the full, working example can be found [here](./swap-forwarder/)):

```solidity
contract SwapForwarder {
    ...
    function swap() external payable returns (uint256 daiAmount) {
        IERC20[] memory path = new IERC20[](2);
        // WETH -> USDC leg on sushiswap.
        (path[0], path[1]) = (WETH, USDC);
        SUSHI_SWAP_ROUTER.swapExactETHForTokens{value: msg.value}(
            0, path, address(this), block.timestamp
        );
        // USDC -> DAI leg on uniswap (v2).
        USDC.approve(address(UNISWAP_ROUTER), type(uint256).max);
        (path[0], path[1]) = (USDC, DAI);
        UNISWAP_ROUTER.swapExactTokensForTokens(
            USDC.balanceOf(address(this)), 0, path, address(this), block.timestamp
        );
        return DAI.balanceOf(address(this));
    }
}
```

We then compile this contract and call it like so (using ethers):
```ts
FORWARDER_ADDRESS = '0x123...'; // Some random address of your choosing.
forwarder = new ethers.Contract(FORWARDER_ADDRESS, FORWARDER_ABI, PROVIDER);
// Find out how much selling 1 ETH for USDC then DAI across sushi and uniswap gets us.
rawResult = await provider.send(
    'eth_call',
    [
        {
            ...(await forwarder.populateTransaction.swap()),
            value: ethers.utils.hexValue(ethers.constants.WeiPerEther),
        },
        'pending',
        { [forwarder.address]: { code: FORWARDER_DEPLOYED_BYTECODE_HEX } },
    ],
);
daiAmount = ethers.utils.defaultAbiCoder.decode(['uint256'], rawResult)[0];
```

#### Example: Unlocking Token Balances
You can always create ETH as needed by either attaching some to the function call or setting the `eth_call` balance state override for a particular address. But let's say you wanted to evaluate the reverse path of the previous swap (DAI->USDC->ETH). Now we would need to supply the forwarder with DAI tokens. Even if we called the forwarder from a wallet that did have some DAI, those ERC20 tokens cannot simply be attached to the call like ETH can. Instead, the wallet would need to first `transfer()` them to the forwarder or have the forwarder pull them from the wallet with a `transferFrom()`, which requires a separate `approve()` call (also from the wallet) beforehand. But recall that we can only call one function directly in an `eth_call`. How would we get around this?

Arguably, the most robust way to acquire an arbitrary token balance in an `eth_call` is to:

1. Find a wallet with a high enough balance of the token you need. You can simply browse etherscan's [top holders rankings](https://etherscan.io/token/0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48#balances).
2. Override the code at the wallet's address with a custom contract that transfers the funds directly to your forwarder contract.

Here's an example contract that we would replace the wallet's code with (the full working example can be found [here](./wallet-unlock-swap-forwarder)):
```solidity
contract UnlockedWallet {
    function transferERC20(IERC20 token, address to, uint256 amount) external {
        token.transfer(to, amount);
    }
}
```

Here's a modified forwarder contract that uses it:
```solidity
contract SwapForwarder {
    ...
    function swap(UnlockedWallet wallet, uint256 daiAmount) external payable returns (uint256 ethAmount) {
        // Pull DAI from the wallet.
        wallet.transferERC20(DAI, address(this), daiAmount);
        IERC20[] memory path = new IERC20[](2);
        // DAI -> USDC leg on uniswap (v2).
        DAI.approve(address(UNISWAP_ROUTER), type(uint256).max);
        (path[0], path[1]) = (DAI, USDC);
        UNISWAP_ROUTER.swapExactTokensForTokens(
            daiAmount, 0, path, address(this), block.timestamp
        );
        // USDC -> WETH leg on sushiswap.
        (path[0], path[1]) = (USDC, WETH);
        SUSHI_SWAP_ROUTER.swapExactTokensForTokens(
            USDC.balanceOf(address(this)), 0, path, address(this), block.timestamp
        );
        return WETH.balanceOf(address(this));
    }
}
```

And here's how we would call the new forwarder (using ethers):
```ts
DAI_WALLET = '0xda1dadd1...'; // Address of a wallet with at least 100 DAI.
// Find out how much selling 100 DAI for USDC then ETH across uniswap and sushi gets us.
rawResult = await provider.send(
    'eth_call',
    [
        forwarder.populateTransaction.swap(DAI_WALLET, ethers.constants.WeiPerEther.mul(100)),
        'pending',
        {
            [FORWARDER_ADDRESS]: { code: FORWARDER_DEPLOYED_BYTECODE_HEX },
            [DAIL_WALLET]: { code: UNLOCKED_WALLET_DEPLOYED_BYTECODE_HEX },
        },    
    ]
);
ethAmount = ethers.utils.defaultAbiCoder.decode(['uint256'], rawResult)[0];
```

## Other Potential Uses
These examples only scratch the surface of what's possible with `eth_call` overrides. Some other things you can do include:

- Batch on-chain queries into a single RPC call, improving your responsiveness and reducing your provider bill.
- Simulate new complex deployments, migrations, user interactions, and even exploits.
- Augment deployed contracts with missing off-chain helper functions.
- Override state that allows optional code paths in a call to be hit, which `eth_estimateGas` wouldn't be able to explore, and track gas usage (using `gasleft()`) to find an exceptional upper-bound gas limit.

Also another subtle perk of code overrides is that your bytecode is not constrained by the 24KB deploy limit 😉.

## Shortcomings
There are a few issues when working with `eth_call`s in this manner, especially as the complexity of your interactions grow:

- State doesn't persist between `eth_call`s so you have to do all your interdependent interactions inside of a single function call. Sometimes this can require some non-trivial problem solving.
- `eth_call` does not expose any events that might have been emitted during execution.

## Comparing to Local Forking
[Ganache](https://github.com/trufflesuite/ganache) and [Foundry](https://book.getfoundry.sh/) support creating a local VM fork of a live network that you can mine transactions against, for free. This is usually the approach most people take when testing against deployed production protocols because the development experience is identical to working with a real network. Frameworks like foundry are even more powerful because you can override almost every aspect of the EVM from within your test contracts.

Where local forking comes up short is when your simulation needs speed and freshness. Local forks work by performing an abundance of state-reading RPC calls (e.g., `eth_getStorage`, `eth_getCode`, `eth_getBalance`, etc) for the block being simulated against and caching them (in the case of foundry). This creates significant delay (several seconds) the first time you use a local fork and can really rack up your provider bill if you do it frequently enough. In contrast, `eth_call` is a single RPC call, requires no back-and-forth communication, and usually completes in the order of milliseconds.
