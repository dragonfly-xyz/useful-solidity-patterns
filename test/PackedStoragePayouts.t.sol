// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.23;

import "../patterns/packing-storage/PackedStoragePayouts.sol";
import "./TestUtils.sol";

contract PackedStoragePayoutsTest is TestUtils {
    NaivePayouts naive = new NaivePayouts();
    PackedPayouts packed = new PackedPayouts();

    function _vest()
        private
        returns (
            address payable recipient,
            uint256 vestAmount,
            uint40 cliff,
            uint24 periodInDays,
            uint256 id
        )
    {
        recipient = _randomAddress();
        vestAmount = _randomUint256() % 1e18;
        cliff = uint40(block.timestamp + _randomUint256() % (365 days));
        periodInDays = uint24(_randomUint256() % (4 * 365)) + 1;
        vm.deal(address(this), vestAmount);
        id = naive.vest{value: vestAmount}(
            recipient,
            cliff,
            uint256(periodInDays) * 1 days
        );
        vm.deal(address(this), vestAmount);
        id = packed.vest{value: vestAmount}(
            recipient,
            cliff,
            periodInDays
        );
    }

    function test_canVest() external {
        // TODO: This test sucks.
        _vest();
    }

    function test_naive_canClaimInFull() external {
        (
            address payable recipient,
            uint256 vestAmount,
            uint40 cliff,
            uint24 periodInDays,
            uint256 id
        ) = _vest();
        vm.warp(cliff + uint256(periodInDays) * 1 days);
        vm.prank(recipient);
        naive.claim(id);
        assertEq(recipient.balance, vestAmount);
    }

    function test_packed_canClaimInFull() external {
        (
            address payable recipient,
            uint256 vestAmount,
            uint40 cliff,
            uint24 periodInDays,
            uint256 id
        ) = _vest();
        vm.warp(cliff + uint256(periodInDays) * 1 days);
        vm.prank(recipient);
        packed.claim(id);
        assertEq(recipient.balance, vestAmount);
    }

    function test_naive_canClaimPartially() external {
        (
            address payable recipient,
            uint256 vestAmount,
            uint40 cliff,
            uint24 periodInDays,
            uint256 id
        ) = _vest();
        vm.warp(cliff + uint256(periodInDays) * 1 days / 2);
        vm.prank(recipient);
        naive.claim(id);
        assertEq(recipient.balance, vestAmount / 2);
    }

    function test_packed_canClaimPartially() external {
        (
            address payable recipient,
            uint256 vestAmount,
            uint40 cliff,
            uint24 periodInDays,
            uint256 id
        ) = _vest();
        vm.warp(cliff + uint256(periodInDays) * 1 days / 2);
        vm.prank(recipient);
        packed.claim(id);
        assertEq(recipient.balance, vestAmount / 2);
    }

    function test_naive_canClaimInInstallments() external {
        (
            address payable recipient,
            uint256 vestAmount,
            uint40 cliff,
            uint24 periodInDays,
            uint256 id
        ) = _vest();
        vm.warp(cliff + uint256(periodInDays) * 1 days / 4);
        vm.prank(recipient);
        naive.claim(id);
        assertEq(recipient.balance, vestAmount / 4);
        skip(uint256(periodInDays) * 1 days / 4);
        vm.prank(recipient);
        naive.claim(id);
        assertEq(recipient.balance, vestAmount / 2);
    }

    function test_packed_canClaimInInstallments() external {
        (
            address payable recipient,
            uint256 vestAmount,
            uint40 cliff,
            uint24 periodInDays,
            uint256 id
        ) = _vest();
        vm.warp(cliff + uint256(periodInDays) * 1 days / 4);
        vm.prank(recipient);
        packed.claim(id);
        assertEq(recipient.balance, vestAmount / 4);
        skip(uint256(periodInDays) * 1 days / 4);
        vm.prank(recipient);
        packed.claim(id);
        assertEq(recipient.balance, vestAmount / 2);
    }

    function test_naive_cannotClaimTwice() external {
        (
            address payable recipient,
            ,
            uint40 cliff,
            uint24 periodInDays,
            uint256 id
        ) = _vest();
        vm.warp(cliff + uint256(periodInDays) * 1 days / 2);
        vm.prank(recipient);
        naive.claim(id);
        vm.expectRevert('nothing owed');
        vm.prank(recipient);
        naive.claim(id);
    }

    function test_packed_cannotClaimTwice() external {
        (
            address payable recipient,
            ,
            uint40 cliff,
            uint24 periodInDays,
            uint256 id
        ) = _vest();
        vm.warp(cliff + uint256(periodInDays) * 1 days / 2);
        vm.prank(recipient);
        packed.claim(id);
        vm.expectRevert('nothing owed');
        vm.prank(recipient);
        packed.claim(id);
    }

    function test_naive_cannotClaimBeyondPeriod() external {
        (
            address payable recipient,
            uint256 vestAmount,
            uint40 cliff,
            uint24 periodInDays,
            uint256 id
        ) = _vest();
        vm.warp(cliff + uint256(periodInDays) * 1 days * 2);
        vm.prank(recipient);
        naive.claim(id);
        assertEq(recipient.balance, vestAmount);
    }

    function test_packed_cannotClaimBeyondPeriod() external {
        (
            address payable recipient,
            uint256 vestAmount,
            uint40 cliff,
            uint24 periodInDays,
            uint256 id
        ) = _vest();
        vm.warp(cliff + uint256(periodInDays) * 1 days * 2);
        vm.prank(recipient);
        packed.claim(id);
        assertEq(recipient.balance, vestAmount);
    }

    function test_naive_cannotClaimBeforeCliff() external {
        (
            address payable recipient,
            ,
            uint40 cliff,
            ,
            uint256 id
        ) = _vest();
        vm.warp(cliff - 1);
        vm.expectRevert('nothing owed');
        vm.prank(recipient);
        naive.claim(id);
    }

    function test_packed_cannotClaimBeforeCliff() external {
        (
            address payable recipient,
            ,
            uint40 cliff,
            ,
            uint256 id
        ) = _vest();
        vm.warp(cliff - 1);
        vm.expectRevert('nothing owed');
        vm.prank(recipient);
        packed.claim(id);
    }

    function test_naive_cannotClaimForAnother() external {
        (
            ,
            ,
            uint40 cliff,
            uint24 periodInDays,
            uint256 id
        ) = _vest();
        vm.warp(cliff + uint256(periodInDays) * 1 days);
        vm.expectRevert('nothing owed');
        vm.prank(_randomAddress());
        naive.claim(id);
    }

    function test_packed_cannotClaimForAnother() external {
        (
            ,
            ,
            uint40 cliff,
            uint24 periodInDays,
            uint256 id
        ) = _vest();
        vm.warp(cliff + uint256(periodInDays) * 1 days);
        vm.expectRevert('nothing owed');
        vm.prank(_randomAddress());
        packed.claim(id);
    }
}
