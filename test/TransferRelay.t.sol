// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "./TestUtils.sol";
import "../patterns/bitmap-nonces/TransferRelay.sol";
import "solmate/tokens/ERC20.sol";

contract TestERC20 is ERC20("TEST", "TEST", 18) {
    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract TransferRelayTest is TestUtils {
    TransferRelay relay = new TransferRelay();
    TestERC20 token = new TestERC20();
    address receiver;
    address signer;
    uint256 signerKey;

    function setUp() external {
        receiver = makeAddr('receiver');
        (signer, signerKey) = makeAddrAndKey('sender');
        token.mint(signer, 1e6);
        vm.prank(signer);
        token.approve(address(relay), type(uint256).max);
    }

    function test_canExecuteTransfer() external {
        TransferRelay.Message memory mess = TransferRelay.Message({
            from: signer,
            to: receiver,
            validAfter: block.timestamp - 1,
            token: IERC20(address(token)),
            amount: 0.25e6,
            nonce: _randomUint256()
        });
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerKey, _hashMessage(mess));
        relay.executeTransferMessage(mess, v, r, s);
        assertEq(token.balanceOf(receiver), 0.25e6);
        assertEq(token.balanceOf(signer), 0.75e6);
    }

    function test_cannotExecuteTransferFromZero() external {
        TransferRelay.Message memory mess = TransferRelay.Message({
            from: address(0),
            to: receiver,
            validAfter: block.timestamp - 1,
            token: IERC20(address(token)),
            amount: 0.25e6,
            nonce: _randomUint256()
        });
        vm.expectRevert('bad from');
        relay.executeTransferMessage(mess, 0, 0, 0);
    }

    function test_cannotExecuteTransferTooEarly() external {
        TransferRelay.Message memory mess = TransferRelay.Message({
            from: signer,
            to: receiver,
            validAfter: block.timestamp,
            token: IERC20(address(token)),
            amount: 0.25e6,
            nonce: _randomUint256()
        });
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerKey, _hashMessage(mess));
        vm.expectRevert('not ready');
        relay.executeTransferMessage(mess, v, r, s);
    }

    function test_cannotExecuteTransferWithBadSignature() external {
        TransferRelay.Message memory mess = TransferRelay.Message({
            from: signer,
            to: receiver,
            validAfter: block.timestamp - 1,
            token: IERC20(address(token)),
            amount: 0.25e6,
            nonce: _randomUint256()
        });
        (, uint256 notSignerKey) = makeAddrAndKey('not signer');
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(notSignerKey, _hashMessage(mess));
        vm.expectRevert('bad signature');
        relay.executeTransferMessage(mess, v, r, s);
    }

    // This checks that the bitmap nonce works.
    function test_cannotExecuteTransferTwice() external {
        TransferRelay.Message memory mess = TransferRelay.Message({
            from: signer,
            to: receiver,
            validAfter: block.timestamp - 1,
            token: IERC20(address(token)),
            amount: 0.25e6,
            nonce: _randomUint256()
        });
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerKey, _hashMessage(mess));
        relay.executeTransferMessage(mess, v, r, s);
        vm.expectRevert('already consumed');
        relay.executeTransferMessage(mess, v, r, s);
    }

    // This checks that the bitmap nonce writes to the same storage slot.
    function test_reusesNonceSlot() external {
        TransferRelay.Message memory mess = TransferRelay.Message({
            from: signer,
            to: receiver,
            validAfter: block.timestamp - 1,
            token: IERC20(address(token)),
            amount: 0.1e6,
            nonce: _randomUint256() & ~uint256(0xFF)
        });
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerKey, _hashMessage(mess));
        // Use gas usage to determine if the same slot was written to or not.
        uint256 gasUsed = gasleft();
        relay.executeTransferMessage(mess, v, r, s);
        gasUsed -= gasleft();
        // Writing to an empty slot costs at least 20k.
        assertGt(gasUsed, 20e3);
        mess.nonce += 1;
        (v, r, s) = vm.sign(signerKey, _hashMessage(mess));
        gasUsed = gasleft();
        relay.executeTransferMessage(mess, v, r, s);
        gasUsed -= gasleft();
        // Writing to a non-empty slot costs less than 20k.
        assertLt(gasUsed, 20e3);
    }

    function _hashMessage(TransferRelay.Message memory mess)
        private
        view
        returns (bytes32 h)
    {
        return keccak256(abi.encode(block.chainid, address(relay), mess));
    }
}