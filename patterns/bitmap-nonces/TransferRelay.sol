// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

// Minimal ERC20 interface.
interface IERC20 {
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
}

// Allows anyone to execute an ERC20 token transfer on someone else's behalf.
// Payers grant an allowance to this contract on every ERC20 they wish to send.
// Then they sign an off-chain message (hash of the `Message` struct) indicating
// recipient, amount, and time. Afterwards, anyone can submit the message to this
// contract's `executeTransferMessage()` function which consumes the message and
// executes the transfer. Messages are marked consumed using bitmap nonces rather
// than traditional, dedicated nonce slots.
contract TransferRelay {
    struct Message {
        address from;
        address to;
        uint256 validAfter;
        IERC20 token;
        uint256 amount;
        uint256 nonce;
    }

    mapping (address => mapping (uint248 => uint256)) public signerNonceBitmap;

    // Consume a signed transfer message and transfer tokens specified within (if valid).
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