// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "../patterns/abi-decode-with-selector/ApproveRestrictedWallet.sol";
import "./TestUtils.sol";

interface IMockEvents {
    event ApproveCalled(address spender, uint256 allowance);
    event PayCalled(uint256 value);
}

abstract contract ApproveRestrictedWalletTestBase is IMockEvents, TestUtils {
    ApproveRestrictedWalletBase wallet;
    TestERC20 erc20 = new TestERC20();
    address allowedSpender;
    
    function setUp() external {
        wallet = _createWallet();
        allowedSpender = _randomAddress();
        wallet.setAllowedSpender(allowedSpender, true);
    }

    function pay() external payable {
        emit PayCalled(msg.value);
    }

    function _createWallet() internal virtual returns (ApproveRestrictedWalletBase);

    function test_canCallWithValue() external {
        _expectNonIndexedEmit();
        emit PayCalled(1);
        wallet.exec{value: 1}(payable(address(this)), abi.encodeCall(this.pay, ()), 1);
    }

    function test_onlyOwnerCanExec() external {
        vm.expectRevert('only owner');
        vm.prank(_randomAddress());
        wallet.exec(payable(address(this)), abi.encodeCall(this.pay, ()), 0);
    }

    function test_canExecApprove() external {
        _expectNonIndexedEmit();
        emit ApproveCalled(allowedSpender, 1);
        wallet.exec(payable(address(erc20)), abi.encodeCall(IERC20.approve, (allowedSpender, 1)), 0);
    }

    function test_canRejectApprove() external {
        vm.expectRevert('not an allowed spender');
        wallet.exec(payable(address(erc20)), abi.encodeCall(IERC20.approve, (_randomAddress(), 1)), 0);
    }
}

contract ApproveRestrictedWalletTest is ApproveRestrictedWalletTestBase {
    function _createWallet() internal override returns (ApproveRestrictedWalletBase) {
        return new ApproveRestrictedWallet(address(this));
    }
}

contract ApproveRestrictedWallet_MemoryTest is ApproveRestrictedWalletTestBase {
    function _createWallet() internal override returns (ApproveRestrictedWalletBase) {
        return new ApproveRestrictedWallet_Memory(address(this));
    }
}

contract TestERC20 is IERC20, IMockEvents {
    function approve(address spender, uint256 allowance) external returns (bool) {
        emit ApproveCalled(spender, allowance);
        return true;
    }
}