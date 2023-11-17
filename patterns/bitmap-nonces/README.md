# Bitmap Nonces

- [📜 Example Code](./TransferRelay.sol)
- [🐞 Tests](../../test/TransferRelay.t.sol)

What do filling a stop-loss order, executing a governance proposal, or meta transactions have in common? They're all operations meant to be consumed once and only once. This guarantee needs to be enforced on-chain to prevent replay attacks. To do this, many protocols will derive some unique identifier from the operation's parameters, then map that identifier to a storage slot dedicated to that operation which holds a status flag.

## Naive Approach

Take the following example of a protocol that executes off-chain signed messages to transfer (compliant) ERC20 tokens on behalf of the signer after a given time:

```solidity
contract TransferRelay {
    struct Message {
        address from;
        address to;
        uint256 validAfter;
        IERC20 token;
        uint256 amount;
        uint256 nonce;
    }

    mapping (address => mapping (uint256 => bool)) public isSignerNonceConsumed;

    function executeTransferMessage(
        Message calldata mess,
        uint8 v,
        bytes32 r,
        bytes32 s
    )
        external
    {
        require(mess.from != address(0), 'bad from');
        require(mess.validAfter < block.timestamp, 'not ready');
        require(!isSignerNonceConsumed[mess.from][mess.nonce], 'already consumed');
        {
            bytes32 messHash = keccak256(abi.encode(block.chainid, address(this), mess));
            require(ecrecover(messHash, v, r, s) == mess.from, 'bad signature');
        }
        // Mark the message consumed.
        isSignerNonceConsumed[mess.from][mess.nonce] = true;
        // Perform the transfer.
        mess.token.transferFrom(address(mess.from), mess.to, mess.amount);
    }
}
```

We expect the signer to choose a `nonce` value that is unique across all their messages. Our contract uses this `nonce` value to identify and record the status of the message in the `isSignerNonceConsumed` mapping. Pretty straight-forward and intuitive... but we can do better!

## Looking At Gas costs

Let's look at the gas cost associated with this operation. Because every `Message.nonce` maps to a unique storage slot, we write to an **empty** slot each time a message gets consumed. Writing to an empty storage slot costs 20k(\*) gas. This can represent 15% of the total gas cost for a simple AMM swap. For high frequency defi operations, the costs can add up. In contrast, writing to a non-empty storage slot only costs 3k(\*) gas. Bitmap nonces minimize how often we write to empty slots, cuting down the cost down by 85% for 99% of operations.

*(\*) Not accounting for EIP-2929 cold/warm state access costs.*

## One More Time, With Bitmap Nonces

If we think about it, we don't need a whole 32-byte word, or even a whole  8-bit boolean to represent whether a message was consumed; we only need one bit (`0` or `1`). Therefore, if we wanted to minimize the frequency of writes to empty slots, instead of mapping nonces to entire storage slots, we could map nonces to bit positions within storage slots. Each storage slot is a 32-byte word so we have 256 bits to work with before we have to move on to a different slot.

![nonces slot usage](./???.png)

We accomplish this by mapping the upper 248 bits of the `nonce` to a unique slot (similar to before), then mapping the lower 8 bits to a bit inside that slot. If the user assigns nonces to operations incrementally instead of randomly they will only write to a new slot every 255 operations!

Let's apply bitmap nonces to our contract:

```solidity
contract TransferRelay {
    // ...

    mapping (address => mapping (uint248 => uint256)) public signerNonceBitmap;

    function executeTransferMessage(
        Message calldata mess,
        uint8 v,
        bytes32 r,
        bytes32 s
    )
        external
    {
        require(mess.from != address(0), 'bad from');
        require(mess.validAfter < block.timestamp, 'not ready');
        require(!_getSignerNonceState(mess.from, mess.nonce), 'already consumed');
        {
            bytes32 messHash = keccak256(abi.encode(block.chainid, address(this), mess));
            require(ecrecover(messHash, v, r, s) == mess.from, 'bad signature');
        }
        // Mark the message consumed.
        _setSignerNonce(mess.from, mess.nonce);
        // Perform the transfer.
        mess.token.transferFrom(address(mess.from), mess.to, mess.amount);
    }

    function _getSignerNonceState(address signer, uint256 nonce) private view returns (bool) {
        uint256 bitmap = signerNonceBitmap[signer][uint248(nonce >> 8)];
        return bitmap & (1 << (nonce & 0xFF)) != 0;
    }

    function _setSignerNonce(address signer, uint256 nonce) private {
        signerNonceBitmap[signer][uint248(nonce >> 8)] |= 1 << (nonce & 0xFF);
    }
}
```

## In the Wild

You can find bitmap nonces being used in major protocols such as Uniswap's [Permit2](https://github.com/Uniswap/permit2/blob/cc56ad0f3439c502c246fc5cfcc3db92bb8b7219/src/SignatureTransfer.sol#L142) and 0x's [Exchange Proxy](https://github.com/0xProject/protocol/blob/e66307ba319e8c3e2a456767403298b576abc85e/contracts/zero-ex/contracts/src/features/nft_orders/ERC721OrdersFeature.sol#L662).

## The Demo

The full, working example can be found [here](./TransferRelay.sol) with complete tests detailing its usage [here](../../test/TransferRelay.sol).