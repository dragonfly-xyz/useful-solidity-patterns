// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "../patterns/erc20-compatibility/ERC20Compatibility.sol";
import "./TestUtils.sol";

interface IERC20Mintable is IERC20 {
    function mint(address owner, uint256 amount) external;
}

contract ERC20CompatibilityTest is TestUtils {
    using LibERC20Compat for IERC20Mintable;

    IERC20Mintable goodToken = IERC20Mintable(address(new GoodERC20()));
    IERC20Mintable badToken = IERC20Mintable(address(new BadERC20()));

    function test_good_canMint() external {
        goodToken.mint(address(this), 1e18);
        assertEq(goodToken.balanceOf(address(this)), 1e18);
    }

    function test_good_canSafeTransfer() external {
        address recipient = _randomAddress();
        goodToken.mint(address(this), 1e18);
        goodToken.safeTransfer(recipient, 0.25e18);
        assertEq(goodToken.balanceOf(address(this)), 0.75e18);
        assertEq(goodToken.balanceOf(recipient), 0.25e18);
    }

    function test_good_canSafeApprove() external {
        address spender = _randomAddress();
        goodToken.mint(address(this), 1e18);
        goodToken.safeApprove(spender, 0.25e18);
        assertEq(goodToken.allowance(address(this), spender), 0.25e18);
        goodToken.safeApprove(spender, 0.5e18);
        assertEq(goodToken.allowance(address(this), spender), 0.5e18);
    }

    function test_good_canSafeTransferFrom() external {
        address spender = _randomAddress();
        address recipient = _randomAddress();
        goodToken.mint(address(this), 1e18);
        goodToken.safeApprove(spender, 0.25e18);
        vm.prank(spender);
        goodToken.safeTransferFrom(address(this), recipient, 0.25e18);
        assertEq(goodToken.balanceOf(address(this)), 0.75e18);
        assertEq(goodToken.balanceOf(recipient), 0.25e18);
        assertEq(goodToken.allowance(address(this), spender), 0);
    }

    function test_good_safeTransferWithBadRecipientFails() external {
        goodToken.mint(address(this), 1e18);
        vm.expectRevert('call failed');
        this._extCallSafeTransfer(address(this), goodToken, address(0), 0.25e18);
    }

    function test_bad_canMint() external {
        badToken.mint(address(this), 1e18);
        assertEq(badToken.balanceOf(address(this)), 1e18);
    }

    function test_bad_rawTransferFails() external {
        address recipient = _randomAddress();
        badToken.mint(address(this), 1e18);
        // Call in a new call context to capture the revert.
        vm.expectRevert();
        this._extCallTransfer(address(this), badToken, recipient, 0.25e18);
    }

    function test_bad_rawApproveFails() external {
        address spender = _randomAddress();
        badToken.mint(address(this), 1e18);
        vm.expectRevert();
        // Call in a new call context to capture the revert.
        this._extCallApprove(address(this), badToken, spender, 0.25e18);
    }

    function test_bad_rawTransferFromFails() external {
        address spender = _randomAddress();
        address recipient = _randomAddress();
        badToken.mint(address(this), 1e18);
        BadERC20(address(badToken)).approve(spender, 0.25e18);
        // Call in a new call context to capture the revert.
        vm.expectRevert();
        this._extCallTransferFrom(spender, badToken, address(this), recipient, 0.25e18);
    }

    function test_bad_approveWithoutResetFails() external {
        address spender = _randomAddress();
        badToken.mint(address(this), 1e18);
        BadERC20(address(badToken)).approve(spender, 0.25e18);
        // Call in a new call context to capture the revert.
        vm.expectRevert('allowance must be reset');
        this._extCallApprove(address(this), badToken, spender, 0.33e18);
    }

    function test_bad_canApproveWithReset() external {
        address spender = _randomAddress();
        badToken.mint(address(this), 1e18);
        assertEq(goodToken.allowance(address(this), spender), 0);
        BadERC20(address(badToken)).approve(spender, 0.25e18);
        assertEq(badToken.allowance(address(this), spender), 0.25e18);
        BadERC20(address(badToken)).approve(spender, 0);
        assertEq(badToken.allowance(address(this), spender), 0);
        BadERC20(address(badToken)).approve(spender, 0.5e18);
        assertEq(badToken.allowance(address(this), spender), 0.5e18);
    }

    function test_bad_canSafeTransfer() external {
        address recipient = _randomAddress();
        badToken.mint(address(this), 1e18);
        badToken.safeTransfer(recipient, 0.25e18);
        assertEq(badToken.balanceOf(address(this)), 0.75e18);
        assertEq(badToken.balanceOf(recipient), 0.25e18);
    }

    function test_bad_canSafeApprove() external {
        address spender = _randomAddress();
        badToken.mint(address(this), 1e18);
        badToken.safeApprove(spender, 0.5e18);
        assertEq(badToken.allowance(address(this), spender), 0.5e18);
    }

    function test_bad_canSafeApproveWithoutExplicitReset() external {
        address spender = _randomAddress();
        badToken.mint(address(this), 1e18);
        badToken.safeApprove(spender, 0.5e18);
        assertEq(badToken.allowance(address(this), spender), 0.5e18);
        badToken.safeApprove(spender, 0.6e18);
        assertEq(badToken.allowance(address(this), spender), 0.6e18);
    }

    function test_bad_canSafeTransferFrom() external {
        address spender = _randomAddress();
        address recipient = _randomAddress();
        badToken.mint(address(this), 1e18);
        badToken.safeApprove(spender, 0.25e18);
        vm.prank(spender);
        badToken.safeTransferFrom(address(this), recipient, 0.25e18);
        assertEq(badToken.balanceOf(address(this)), 0.75e18);
        assertEq(badToken.balanceOf(recipient), 0.25e18);
        assertEq(badToken.allowance(address(this), spender), 0);
    }

    // External indirect call functions. These allows us to call an ERC20 function
    // in a new call context, so the test can capture any revert that occurs without
    // immediately failing the test function.

    function _extCallApprove(
        address caller,
        IERC20Mintable token,
        address spender,
        uint256 allowance
    )
        external
    {
        vm.prank(caller);
        token.approve(spender, allowance);
    }

    function _extCallTransfer(
        address caller,
        IERC20Mintable token,
        address to,
        uint256 amount
    )
        external
    {
        vm.prank(caller);
        token.transfer(to, amount);
    }

    function _extCallTransferFrom(
        address caller,
        IERC20Mintable token,
        address owner,
        address to,
        uint256 amount
    )
        external
    {
        vm.prank(caller);
        token.transferFrom(owner, to, amount);
    }

    function _extCallSafeTransfer(
        address caller,
        IERC20Mintable token,
        address to,
        uint256 amount
    )
        external
    {
        vm.prank(caller);
        token.safeTransfer(to, amount);
    }
}
