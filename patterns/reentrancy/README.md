# Reentrancy

- [📜 Example Code](./AppleDAO.sol)
- [🐞 Tests](../../test/AppleDAO.t.sol)

Virtually all protocol contracts will make some form of an external call, either directly or indirectly, to an untrusted, uncontrolled address. Any time an external call is made, execution control is lost to another party. There is no concept of parallelism in Ethereum contracts, so when a protocol loses execution control in the middle of an operation that has yet to finish it must wait for the executor to return and opens itself up to the notorious reentrancy attack.

External calls can come in the obvious form of a simple call to a function on a contract, the less obvious transfer of ETH to an address (which is just an empty call), deploying a contract, or the transfer of tokens with a callback or hook mechanism (such as ERC777 and ERC721).

## Losing All Your Apples

Imagine your protocol is Alice, who is handing out apples to people, but only one per person. Unfortunately Alice is also suffering from short-term memory loss and must write everything down to remember it. Now greedy Bob comes along, who actually wants *2 apples*! How can he trick Alice into getting them?

1. Bob asks Alice for an apple.
2. Alice checks her notebook to see if she's already given Bob an apple, sees that she hasn't, and hands over an apple to Bob.
    1. *Before* Alice can write down that she has given Bob an apple, Bob immediately asks Alice for another apple.
    2. Alice again checks her notebook and sees Bob hasn't received an apple, so she hands him another.
    3. Alice now crosses Bob's name off in her notebook, indicating he's received an apple.
3. Alice (again) crosses Bob's name off in her notebook, indicating he's received an apple.

Taking it further, if Bob wanted ALL of Alice's apples, he could simply keep nesting requests for apples before Alice gets a chance to record the exchange until she ran out. This is exactly how the infamous [DAO hack](https://www.immunebytes.com/blog/an-insight-into-the-dao-attack/) was carried out.

What would Alice and Bob look like in Solidity? Let's say apples are actually ERC721 NFTs that Alice is in charge of minting.

```solidity
contract Apples is ERC721("Apples") { /* ... */ }

contract Alice {
    Apples public immutable APPLES = new Apples();
    mapping (address => boolean) _hasReceivedApple;

    function claimApple() external {
        require(!_hasReceivedApple[msg.sender]);
        // safeMint() calls the receiver's onERC721Received() handler. 
        APPLES.safeMint(msg.sender);
        _hasReceivedApple[msg.sender] = true;
    }
}

contract Bob {
    function exploit(Alice alice) external {
        _claim(alice);
    }

    function onERC721Received(address operator, address, uint256, bytes calldata) external {
        _claim(Alice(operator));
        return this.onERC721Received.selector;
    }

    function _claim(Alice alice) private {
        // Stop claiming once we have 100 apples.
        if (alice.APPLES().balanceOf(address(this)) < 100) {
            alice.claimApple();
        }    
    }
}

```

*⚠️ Note that this is just one, relatively simple example of what a reentrancy attack could look like. The actual topology can vary greatly, involving more or less intermediary contracts/actors. It's also important to be aware that reentrancy is often spoken about at the individual contract level, but it can also manifest itself at the protocol level when an operation spans multiple contracts (or even multiple protocols). Reentrancy attacks can also (and often does) exploit multiple functions/operations that rely on some shared state.*

## Protecting Your Apples

Let's see how we can apply two common patterns/mechanisms to help keep Alice from getting exploited.

### Checks-Effects-Interactions Pattern
The "Checks-Effects-Interactions" (abbreviated to just "CEI") pattern is a mantra for organizing the logic in your operation to minimize reentrancy opportunities. It also often has a nice side effect of making your code easier to follow, so you should strongly consider applying the technique even when you're confident that the impact of a reentrancy attack is negligible. Most seasoned solidity devs do it by reflex now.

The sequence goes as follows:

1. **Checks**: Verify inputs, access control, and initial state for the function/operation.
2. **Effects**: Perform any internal accounting and commit any state changes to storage that would be affected by the operation.
3. **Interactions**: Make untrusted/external calls and asset transfers.

By placing the external call at the end of your logic, you can avoid being in an incomplete state when you hand over execution control.

If we look at the Alice example, she actually does all these things but in the wrong order! Instead of C-E-I, she does C-I-E. Correcting the order removes the reentrancy vulnerability because she will have already recorded that Bob received an apple before he gets the opportunity to request another.

```solidity
contract Alice {
    ...
    function claimApple() external {
        // CHECKS: Sender hasn't received an apple yet.
        require(!_hasReceivedApple[msg.sender]);
        // EFFECTS: Record that the sender has claimed an apple.
        _hasReceivedApple[msg.sender] = true;
        // INTERACTIONS: Give the sender an apple.
        APPLES.safeMint(msg.sender);
    }
}

```

### Reentrancy Guards (Mutex)
Sometimes you can't organize your code according to CEI. Maybe you depend on the output of an external interaction to compute the final state to be committed. In these cases, you can use some form of a reentrancy guard.

Reentrancy guards are essentially temporary state that indicates an operation is ongoing, which you can check to prevent two mutually exclusive operations (or the same operation) from occurring before the first one has completed. Many contracts use a dedicated storage variable as this mutex (see the [standard OpenZeppelin implementation](https://docs.openzeppelin.com/contracts/4.x/api/security#ReentrancyGuard)) and share it across any at-risk functions. Often reentrancy guards are wrapped in a modifier that asserts the state flag, toggles on the flag, executes the function body, then resets the flag.

Here is Alice with a reentrancy guard:


```solidity
contract Alice {
    ...
    bool private _reentrancyGuard;

    modifier nonReentrant() {
        require(!_reentrancyGuard);
        _reentrancyGuard = true;
        _;
        _reentrancyGuard = false;
    }

    // Unaltered, vulnerable code from original example but with reentrancy guard
    // modifier added.
    function claimApple() external nonReentrant {
        require(!_hasReceivedApple[msg.sender]);
        APPLES.safeMint(msg.sender);
        _hasReceivedApple[msg.sender] = true;

    }
}
```

Now if Bob attempts to call `claimApple()` again before it has completed the modifier will see that the reentrancy guard is activated and the call will revert.

The reentrancy guard approach is pretty convenient and takes much less thought to apply, which makes it a very popular solution. However, it comes with some considerations.

- The reentrancy flag usually occupies its own storage slot. Writing to a new storage slot (especially an empty one) introduces significant gas cost. Even though the majority of it will be refunded (because the slot is reset by the modifier), it raises the execution gas limit of the transaction which causes some extra sticker shock to users.
    - Sometimes you can avoid using a dedicated reentrancy guard state variable. Instead you can reuse a state variable that you would write to during the operation anyway, checking and setting it to some preordained invalid value that would act the same way a dedicated reentrancy guard would.
- The naive version of a reentrancy guard can only protect reentrancy within a single contract. Protocols are often composed of several contracts with mutually exclusive operations across them. In these situations, you may need to come up with a way to surface the reentrancy guard state across the rest of the system.

## Demo
The [demo](./AppleDAO.sol) is the complete implementation of the scenario and solutions described here. An abridged and simplified version of an ERC721 style token contract is used for brevity. You can inspect the traces of the [tests](.../../test/AppleDAO.t.sol) with `forge test -vvvv --match-path test/AppleDAO.t.sol` to get a better understanding of the flow of execution.
