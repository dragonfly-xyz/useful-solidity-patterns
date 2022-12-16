// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "../patterns/multicall/TeamFarm.sol";
import "./TestUtils.sol";

contract TeamFarmTest is TestUtils {
    IERC20 NATIVE_TOKEN = IERC20(address(0));
    ERC20 asset = new ERC20();
    WETH weth = new WETH();
    TeamFarm farm;
    TestVault vault;

    constructor() {
        farm = new TeamFarm(weth, address(this));
        vault = new TestVault(weth);
    }

    function test_canMulticallDepositWrapStake() external {
        uint256 amount = 100;
        bytes[] memory calls = new bytes[](3);
        calls[0] = abi.encodeCall(farm.deposit, (NATIVE_TOKEN, amount));
        calls[1] = abi.encodeCall(farm.wrap, (amount));
        calls[2] = abi.encodeCall(farm.stake, (vault, amount));
        farm.multicall{value: amount}(calls);
        assertEq(weth.balanceOf(address(vault)), amount);
        assertEq(vault.balanceOf(address(farm)), amount * 10);
    }

    function test_canMulticallUnstakeUnwrapWithdraw() external {
        uint256 amount = 100;
        bytes[] memory calls = new bytes[](3);
        calls[0] = abi.encodeCall(farm.deposit, (NATIVE_TOKEN, amount));
        calls[1] = abi.encodeCall(farm.wrap, (amount));
        calls[2] = abi.encodeCall(farm.stake, (vault, amount));
        farm.multicall{value: amount}(calls);

        address payable receiver = _randomAddress();
        calls[0] = abi.encodeCall(farm.unstake, (vault, amount * 10));
        calls[1] = abi.encodeCall(farm.unwrap, (amount));
        calls[2] = abi.encodeCall(farm.withdraw, (NATIVE_TOKEN, amount, receiver));
        farm.multicall(calls);
        assertEq(weth.balanceOf(address(vault)), 0);
        assertEq(receiver.balance, amount);
    }

    // TODO: More tests...
}

contract ERC20 is IERC20 {
    mapping (address => uint256) public balanceOf;
    mapping (address => mapping (address => uint256)) public allowance;

    function transfer(address to, uint256 amount) external returns (bool) {
        transferFrom(msg.sender, to, amount);
        return true;
    }

    function transferFrom(address owner, address to, uint256 amount) public returns (bool) {
        if (msg.sender != owner) {
            allowance[owner][msg.sender] -= amount;
        }
        balanceOf[owner] -= amount;
        balanceOf[to] += amount;
        return true;
    }

    function approve(address spender, uint256 allowance_) external returns (bool) {
        allowance[msg.sender][spender] = allowance_;
        return true;
    }
}

contract WETH is IWETH, ERC20 {
    function deposit() external payable {
        balanceOf[msg.sender] += msg.value;
    }

    function withdraw(uint256 amt) external {
        balanceOf[msg.sender] -= amt;
        (bool s, bytes memory r) = payable(msg.sender).call{value: amt}("");
        if (!s) {
            assembly { revert(add(r, 0x20), mload(r)) }
        }
    }
}

contract TestVault is IERC4626, ERC20 {
    IERC20 public immutable asset;

    constructor(IERC20 asset_) {
        asset = asset_;
    }

    function deposit(uint256 assets, address receiver) external returns (uint256 shares) {
        shares = assets * 10;
        asset.transferFrom(msg.sender, address(this), assets);
        balanceOf[receiver] += shares;
    }

    function redeem(uint256 shares, address receiver, address owner) external returns (uint256 assets) {
        assets = shares / 10;
        require(msg.sender == owner, 'allowances not implemented');
        balanceOf[owner] -= shares;
        asset.transfer(receiver, assets);
    }
}