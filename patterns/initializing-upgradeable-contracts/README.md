# Initializing Upgradeable Contracts

- [📜 Example Code](./InitializedProxyWallet.sol)
- [🐞 Tests](../../test/InitializedProxyWallet.t.sol)

When using the [proxy](../basic-proxies/) pattern, you usually deploy a hollow proxy contract that simply forwards *all* calls to a separate logic contract via `delegatecall()` mechanics. Because this proxy contract is ideally designed to be generic and deliberately doesn't understand the internal state used by the logic contract, it usually cannot perform any initialization of this (unknown) state on its own. Thus, developers will typically define an explicit intiializer function on the logic contract that the proxy can delegatecall into (just like every other function it defines) which performs this state setup from within the proxy's context.

![proxy with initializer diagram](./initializer.png)

## Demonstration

To start our code illustration of this pattern, let's define a simple, generic `Proxy` contract:

```solidity
contract Proxy {
    Logic public immutable LOGIC;

    constructor(Logic logic) { LOGIC = logic; }

    fallback(bytes calldata callData) external payable
        returns (bytes memory returnData)
    {
        // Forward any calls to the logic contract via delegatecall.
        returnData = _forwardCall(callData);
    }

    function _forwardCall(bytes memory callData)
        private returns (bytes memory returnData)
    {
        (bool s, bytes memory r) = LOGIC.delegatecall(callData);
        if (!s) assembly { revert(add(r, 0x20), mload(r)) }
        return r;
    }
}
```

Say we want to proxify a basic smart contract wallet that can receive ETH but only a designated owner can transfer it out. On the logic contract, we'll define an `initialize()` function that establishes this owner once and only once.

```solidity
contract WalletLogic {
    bool isInitialized
    address owner;

    // Set the owner once and only once.
    function initialize(address owner_) external {
        require(!isInitialized, 'already initialized');
        isInitialized = true;
        owner = owner_;
    }

    // Move ETH out of this contract.
    function transferOut(address payable to, uint256 amount) external {
        require(msg.sender == owner, 'only owner');
        to.transfer(amount);
    }

    // Allow this contract to receive ETH.
    receive() external payable {}
}
```

Now to create a new instance of the wallet we would:
1. Deploy a new `Proxy` contract, passing in the address of the already deployed `WalletLogic` contract to the constructor.
2. Call `initialize()` on the new proxy instance, which gets forwarded to the `WalletLogic` contract's implementation of `initialize()`.
    1. This will set the `owner` state variable in the context of the proxy instance.
    2. This will also set the `isInitialized` state variable to `true`, preventing further calls to `initialize()`.

This is a pretty common way of implementing initializers for upgradeable contracts, and is the way [Openzeppelin libraries](https://docs.openzeppelin.com/upgrades-plugins/1.x/writing-upgradeable) are built. It works generally fine in practice but there are some pitfalls with this approach.

## Deploy and Initialize at the Same Time

One obvious problem is that it takes two interactions with the `Proxy` instance (a deploy then a call to `initialize()`) before the wallet is usable. If you tried to do this from an externally owned account (not a contract) it would have to occur over 2 transactions, meaning it's possible for someone else to frontrun the call to `initialize()`, establishing a different `owner`. Not good.

To address this, we can modify our Proxy to perform the delegatecall to `initialize()` in its constructor. But to keep it generic (the proxy shouldn't know what its logic contract is about), we'll actually pass in the *encoded call* to `initialize()`, which you can construct with your chosen web3 library's equivalent of `abi.encodeCall(WalletLogic.initialize, (owner))`. Now once the Proxy instance is deployed, it will already be initialized!

```solidity
contract Proxy {
    constructor(Logic logic, bytes memory initCallData) {
        LOGIC = logic;
        // Automatically execute `initCallData` as a delegatecall.
        _forwardCall(initCallData);
    }
    // ... rest is the same
}
```

## Do We Really Need `isInitialized`? 

Recall that the `WalletLogic` contract uses an `isInitialized` state variable to ensure `initialize()` is only called once. This comes with its own problems as well.

The first is that there is nothing preventing someone from calling `initialize()` on the `WalletLogic` contract directly (not through a `Proxy` instance) and becoming the owner of the logic contract itself. Usually this isn't a big deal, since any state changes made in the `WalletLogic` instance does not carry over to a `Proxy` instance. But if your logic contract can call `selfdestruct` or also can do its own delegatecalls, it's possible for someone to initialize it, taking ownership, then self-destruct the logic contract, which will immediately brick every `Proxy` instance that depends on it. This is exactly what happened with the [Parity Wallet hack](https://blog.openzeppelin.com/on-the-parity-wallet-multisig-hack-405a8c12e8f7/). 

A less severe problem with this approach is the gas overhead incurred from having to write to the `isInitialized` storage slot, which is about 20k in the worst case. Our example is actually not so impacted by this because our `isInitialized` field is declared next to an `address` field that nicely [packs](../packing-storage/) together into the same slot, but the standard [OpenZeppelin implementation](https://github.com/OpenZeppelin/openzeppelin-upgrades/blob/master/packages/core/contracts/Initializable.sol#L66) most projects use adds storage padding to its contracts to prevent slot packing, so those contracts will eat the full 20k cost 🙈.

Is there a way to both get rid of the `isInitialized` state variable and protect our logic contract from being initialized directly?

Since we've moved the delegatecall to `initialize()` into our `Proxy` contract's constructor, if we can just ensure that the `initialize()` function could *only* be called from within the constructor, we shouldn't need to worry about it getting called again. In the EVM, the constructor's job is actually to return the bytecode that will live at the contract's address. So, while inside a constructor, your address (`address(this)`) will be the deployment address, but there will be no bytecode at that address! So if we check `address(this).code.length` before the constructor has finished, even from within a delegatecall, we will get `0`. So now let's update our `initialize()` function to only run if we are inside a constructor:

```solidity
contract WalletLogic {
    address owner;

    // Set the owner. Only runs from within the context of a constructor.
    function initialize(address owner_) external {
        require(address(this).code.length == 0, 'not in constructor');
        owner = owner_;
    }
    // ... rest is the same
}
```

Now the `Proxy` contract's constructor can still delegatecall `initialize()`, but if anyone attempts to call it again (after deployment) through the `Proxy` instance, or tries to call it directly on the `WalletLogic` instance, it will revert because `address(this).code.length` will be nonzero. Also, because we no longer need to write to any state to track whether `initialize()` has been called, we can avoid the 20k storage gas cost. In fact, the cost for checking our own code size is only 100 gas, which means we have a 200x gas savings over the standard version. Pretty neat!

## Real World Usage
- [OpenZeppelin's upgradeable contracts](https://docs.openzeppelin.com/upgrades-plugins/1.x/writing-upgradeable) all use a conventional initializer pattern.
- PartyDAO's [Party Protocol](https://github.com/PartyDAO/party-protocol) uses proxy contracts extensively to cut down instantiation costs. Their base class for logic contracts defines an [`onlyConstructor` modifier](https://github.com/PartyDAO/party-protocol/blob/main/contracts/utils/Implementation.sol#L24) that only allows for logic initialization during deployment of the proxy contract.
