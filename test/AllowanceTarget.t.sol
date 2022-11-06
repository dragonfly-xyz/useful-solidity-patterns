// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "../patterns/separate-allowance-targets/AllowanceTarget.sol";
import "./TestUtils.sol";

contract AllowanceTargetTest is TestUtils {
    AllowanceTarget allowanceTarget = new AllowanceTarget(address(this));
    MinimalERC20 erc20 = new MinimalERC20();
    Business biz = new Business(allowanceTarget);

    event Transfer(address indexed from, address indexed to, uint256 value);

    constructor() {
        allowanceTarget.setAuthority(address(biz), true);
    }

    function test_authorityCanSpendFrom() external {
        address user = _randomAddress();
        uint256 balance = 1e18;
        erc20.mint(user, balance);
        vm.prank(user);
        erc20.approve(address(allowanceTarget), balance);
        vm.expectEmit(true, true, true, true);
        emit Transfer(user, address(biz), balance);
        vm.prank(user);
        biz.transact(erc20, balance);
    }

    function test_nonAuthorityCannotSpendFrom() external {
        address user = _randomAddress();
        uint256 balance = 1e18;
        erc20.mint(user, balance);
        vm.prank(user);
        erc20.approve(address(allowanceTarget), balance);
        vm.prank(_randomAddress());
        vm.expectRevert('only authorized');
        allowanceTarget.spendFrom(erc20, user, address(biz), balance);
    }

    function test_canRemoveAuthority() external {
        allowanceTarget.setAuthority(address(biz), false);
        address user = _randomAddress();
        uint256 balance = 1e18;
        erc20.mint(user, balance);
        vm.prank(user);
        erc20.approve(address(allowanceTarget), balance);
        vm.expectRevert('only authorized');
        vm.prank(user);
        biz.transact(erc20, balance);
    }
}

contract Business {
    AllowanceTarget immutable allowanceTarget;

    constructor(AllowanceTarget allowanceTarget_) {
        allowanceTarget = allowanceTarget_;
    }

    function transact(IERC20 token, uint256 amount) external {
        allowanceTarget.spendFrom(token, msg.sender, address(this), amount);
    }
}

contract MinimalERC20 is IERC20 {
    mapping (address => mapping (address =>uint256)) allowance;
    mapping (address => uint256) balanceOf;

    event Transfer(address indexed from, address indexed to, uint256 value);

    function mint(address owner, uint256 amount) external {
        balanceOf[owner] += amount;
        emit Transfer(address(0), owner, amount);
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }

    function transferFrom(address owner, address to, uint256 amount) external returns (bool) {
        allowance[owner][msg.sender] -= amount;
        balanceOf[owner] -= amount;
        balanceOf[to] += amount;
        emit Transfer(owner, to, amount);
        return true;
    }
}

