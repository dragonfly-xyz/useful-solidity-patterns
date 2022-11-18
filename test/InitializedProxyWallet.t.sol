// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "../patterns/initializing-upgradeable-contracts/InitializedProxyWallet.sol";
import "./TestUtils.sol";

contract InitializedProxyWalletTest is TestUtils {
    Proxy proxy;
    WalletLogic logic = new WalletLogic();
    WalletLogic wallet;
    address owner;
    
    constructor() {
        owner = _randomAddress();
        proxy = new Proxy(
            address(logic),
            abi.encodeCall(WalletLogic.initialize, (owner))
        );
        wallet = WalletLogic(payable(proxy));
    }

    function test_hasOwner() external {
        assertEq(wallet.owner(), owner);
    }
    
    function test_canReceiveEth() external {
        _sendEth(payable(wallet), 1337);
        assertEq(address(wallet).balance, 1337);
    }

    function test_ownerCanTransferEthOut() external {
        _sendEth(payable(wallet), 1337);
        vm.prank(owner);
        address payable recipient = _randomAddress();
        wallet.transferOut(recipient, 1337);
        assertEq(recipient.balance, 1337);
    }

    function test_nonOwnerCannotTransferEthOut() external {
        _sendEth(payable(wallet), 1337);
        vm.prank(_randomAddress());
        address payable recipient = _randomAddress();
        vm.expectRevert('only owner');
        wallet.transferOut(recipient, 1337);
    }

    function test_cannotInitializeAgain() external {
        vm.expectRevert('not in constructor');
        wallet.initialize(_randomAddress());
    }

    function test_cannotInitializeLogicContract() external {
        vm.expectRevert('not in constructor');
        logic.initialize(_randomAddress());
    }

    function _sendEth(address payable to, uint256 amount) private {
        (bool s,) = to.call{value: amount}("");
        require(s, 'ETH transfer failed');
    }
}