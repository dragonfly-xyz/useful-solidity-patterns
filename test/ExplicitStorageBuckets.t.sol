// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import "../patterns/explicit-storage-buckets/ExplicitStorageBuckets.sol";
import "./TestUtils.sol";

contract ExplicitStorageBuckets is Test, TestUtils {
    // Who will be the deployer and owner of the proxy contracts.
    // Notably, ends with a 0 byte.
    address owner = 0x1111111111111111111111111111111111111100;
    address[] allowedWithdrawers;
    Impl impl = new Impl();
    Impl unsafe;
    Impl safe;

    constructor() {
        for (uint256 i = 0; i < 3; ++i) {
            allowedWithdrawers.push(_randomAddress());
        }
        vm.prank(owner);
        unsafe = Impl(payable(new UnsafeProxy(address(impl), allowedWithdrawers)));
        vm.prank(owner);
        safe = Impl(payable(new SafeProxy(address(impl), allowedWithdrawers)));
        vm.deal(payable(unsafe), 1e18);
        vm.deal(payable(safe), 1e18);
    }

    function _getRandomWithdrawer() private view returns (address) {
        return allowedWithdrawers[_randomUint256() % allowedWithdrawers.length];
    }

    function test_unsafeWorks() external {
        address payable recipient = _randomAddress();
        vm.prank(_getRandomWithdrawer());
        unsafe.withdraw(recipient, 1);
        assertEq(recipient.balance, 1);
    }

    function test_safeWorks() external {
        address payable recipient = _randomAddress();
        vm.prank(_getRandomWithdrawer());
        safe.withdraw(recipient, 1);
        assertEq(recipient.balance, 1);
    }

    function test_safeIsInitiailized() external {
        assertTrue(safe.isInitialized());
        for (uint256 i = 0; i < allowedWithdrawers.length; ++i) {
            assertTrue(safe.isAllowed(allowedWithdrawers[i]));
        }
    }

    function test_unsafeIsPartiallyInitiailized() external {
        assertFalse(unsafe.isInitialized());
        for (uint256 i = 0; i < allowedWithdrawers.length; ++i) {
            assertTrue(unsafe.isAllowed(allowedWithdrawers[i]));
        }
    }

    function test_safeCannotBeReinitialized() external {
        address[] memory newAllowedWithdrawers = new address[](1);
        newAllowedWithdrawers[0] = _randomAddress();
        vm.expectRevert('already initialized');
        safe.initialize(newAllowedWithdrawers);
    }

    function test_unsafeCanBeReinitializedAndExploited() external {
        address[] memory newAllowedWithdrawers = new address[](1);
        newAllowedWithdrawers[0] = _randomAddress();
        // Reinitialize and perform an unauthorized withdraw.
        unsafe.initialize(newAllowedWithdrawers);
        assertTrue(unsafe.isAllowed(newAllowedWithdrawers[0]));
        address payable recipient = _randomAddress();
        vm.prank(newAllowedWithdrawers[0]);
        unsafe.withdraw(recipient, 1);
        assertEq(recipient.balance, 1);
    }
}
