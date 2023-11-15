// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.23;

import "../patterns/reentrancy/AppleDAO.sol";
import "./TestUtils.sol";

contract AppleDAOTestBase is TestUtils {
    Bob internal bob;
    Alice internal alice;
    Apples internal apples;

    constructor(Alice alice_) {
        alice = alice_;
        apples = alice.APPLES();
        bob = new Bob(alice_);
    }

    function test_canClaimApple() external {
        assertEq(apples.balanceOf(address(this)), 0);
        alice.claimApple();
        assertEq(apples.balanceOf(address(this)), 1);
    }

    function test_cannotClaimAppleTwice() external {
        assertEq(apples.balanceOf(address(this)), 0);
        alice.claimApple();
        vm.expectRevert('already got an apple');
        alice.claimApple();
    }

    function onNftReceived(address owner, uint256) external {
        assertEq(owner, address(0));
        assertEq(msg.sender, address(apples));
    }
}

contract AppleDAOTest_DumbAlice is AppleDAOTestBase {
    constructor() AppleDAOTestBase(new Alice()) {}

    function test_canExploitAlice() external {
        assertEq(apples.balanceOf(address(bob)), 0);
        bob.exploit();
        assertEq(apples.balanceOf(address(bob)), 10);
    }
}

contract AppleDAOTest_SmartAlice is AppleDAOTestBase {
    constructor() AppleDAOTestBase(new SmartAlice()) {}

    function test_cannotExploitAlice() external {
        assertEq(apples.balanceOf(address(bob)), 0);
        vm.expectRevert('already got an apple');
        bob.exploit();
    }
}

contract AppleDAOTest_NonReentrantAlice is AppleDAOTestBase {
    constructor() AppleDAOTestBase(new NonReentrantAlice()) {}

    function test_cannotExploitAlice() external {
        assertEq(apples.balanceOf(address(bob)), 0);
        vm.expectRevert('reentrancy detected');
        bob.exploit();
    }
}