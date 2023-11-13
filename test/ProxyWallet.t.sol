// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.23;

import "../patterns/basic-proxies/ProxyWallet.sol";
import "./TestUtils.sol";

contract ProxyWalletTest is TestUtils {
    WalletProxy proxy;
    WalletLogicV1 logicV1 = new WalletLogicV1();
    WalletLogicV2 logicV2 = new WalletLogicV2();
    DummyERC20 erc20 = new DummyERC20();
    
    constructor() {
        proxy = new WalletProxy(address(logicV1));
    }
    
    function test_canUpgrade() external {
        WalletLogicV1 wallet = WalletLogicV1(payable(proxy));
        assertEq(wallet.version(), 'V1');
        proxy.upgrade(address(logicV2));
        assertEq(wallet.version(), 'V2');
    }

    function test_onlyOwnerCanUpgrade() external {
        vm.prank(_randomAddress());
        vm.expectRevert('only owner');
        proxy.upgrade(address(logicV2));
    }

    function test_v1CanTransferETH() external {
        WalletLogicV1 wallet = WalletLogicV1(payable(proxy));
        payable(address(wallet)).transfer(100);
        address payable recipient = _randomAddress();
        wallet.transferETH(recipient, 1);
        assertEq(recipient.balance, 1);
    }

    function test_v1CanOnlyTransferETHAsOwner() external {
        WalletLogicV1 wallet = WalletLogicV1(payable(proxy));
        payable(address(wallet)).transfer(100);
        address payable recipient = _randomAddress();
        vm.prank(_randomAddress());
        vm.expectRevert('only owner');
        wallet.transferETH(recipient, 1);
    }

    function test_v1CanTransferERC20() external {
        proxy.upgrade(address(logicV2));
        WalletLogicV2 wallet = WalletLogicV2(payable(proxy));
        erc20.mint(address(wallet), 100);
        address recipient = _randomAddress();
        wallet.transferERC20(erc20, recipient, 1);
        assertEq(erc20.balanceOf(recipient), 1);
    }

    function test_v1CanOnlyTransferERC20AsOwner() external {
        proxy.upgrade(address(logicV2));
        WalletLogicV2 wallet = WalletLogicV2(payable(proxy));
        erc20.mint(address(wallet), 100);
        address recipient = _randomAddress();
        vm.prank(_randomAddress());
        vm.expectRevert('only owner');
        wallet.transferERC20(erc20, recipient, 1);
    }
}

contract DummyERC20 is IERC20 {
    mapping (address => uint256) public balanceOf;

    function mint(address owner, uint256 amount) external {
        balanceOf[owner] += amount;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        return true;
    }
}