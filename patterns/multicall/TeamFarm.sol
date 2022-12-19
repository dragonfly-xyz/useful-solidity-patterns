//  SPDX-License-Identifer: MIT
pragma solidity ^0.8.17;

// A communal wallet for managing ERC20s and ETH that can be deposited (staked)
// and withdrawn (unstaked) from ERC4626 vaults.
contract TeamFarm {
    IERC20 constant ETH_TOKEN = IERC20(address(0));
    IWETH public immutable WETH;
    
    mapping (address => bool) public isMember;
    bool _reentrancyGuard;

    modifier nonReentrant() {
        require(!_reentrancyGuard, 'no reentrancy');
        _reentrancyGuard = true;
        _;
        _reentrancyGuard = false;
    }

    modifier onlyMember() {
        require(isMember[msg.sender], 'not a member');
        _;
    }

    constructor(IWETH weth, address initialMember) {
        WETH = weth;
        isMember[initialMember] = true;
    }

    // Add or remove another member.
    function toggleMember(address member, bool toggle) external payable onlyMember {
        isMember[member] = toggle;
    }

    // Wrap an amount of ETH held by this contract into WETH.
    function wrap(uint256 ethAmount) external payable onlyMember nonReentrant {
        WETH.deposit{value: ethAmount}();
    }

    // Unwrap an amount of WETH held by this contract into ETH.
    function unwrap(uint256 wethAmount) external payable onlyMember nonReentrant {
        WETH.withdraw(wethAmount);
    }

    // Deposit an ERC20 (pull) or ETH into this contract.
    function deposit(IERC20 token, uint256 tokenAmount) external payable nonReentrant {
        if (token != ETH_TOKEN) {
            // Depositing an ERC20.
            // TODO: In production, use an ERC20 compatibility library to do this.
            token.transferFrom(msg.sender, address(this), tokenAmount);
        } else {
            // Depositing ETH. ETH is already in the contract.
        }
    }

    // Withdraw ERC20 tokens or ETH from this contract.
    function withdraw(
        IERC20 token,
        uint256 tokenAmount,
        address payable receiver
    )
        external
        payable
        onlyMember
        nonReentrant
    {
        if (token != ETH_TOKEN) {
            // Withdrawing an ERC20.
            // TODO: In production, use an ERC20 compatibility library to do this.
            token.transfer(receiver, tokenAmount);
        } else {
            // Withdrawing ETH.
            (bool s,) = receiver.call{value: tokenAmount}("");
            require(s, 'ETH transfer failed');
        }
    }

    // Stake tokens held by this contract in an ERC4626 vault, creating
    // share tokens.
    function stake(IERC4626 vault, uint256 assets)
        external
        payable
        onlyMember
        nonReentrant
        returns (uint256 shares)
    {
        vault.asset().approve(address(vault), assets);
        shares = vault.deposit(assets, address(this));
    }

    // Unstake shares/vault tokens held by this contract out of an ERC4626 vault,
    // converting shares back into (staked) asset tokens.
    function unstake(IERC4626 vault, uint256 shares)
        external
        payable
        onlyMember
        nonReentrant
        returns (uint256 assets)
    {
        assets = vault.redeem(shares, address(this), address(this));
    }

    // Execute multiple external/public functions on this contract, as the caller.
    function multicall(bytes[] calldata calls) external payable {
        for (uint256 i = 0; i < calls.length; ++i) {
            // By using delegatecall and ourselves as the target (bytecode),
            // each sub-call will inherit the same `msg.sender` and `msg.value` as this one,
            // as if they had called it directly.
            (bool s, bytes memory r) = address(this).delegatecall(calls[i]);
            if (!s) {
                // Bubble up revert on failure.
                assembly { revert(add(r, 0x20), mload(r)) }
            }
        }
    }

    // Allow this contract to receive ETH directly (WETH unwrap).
    receive() external payable {}
}

// Minimal ERC20 interface.
interface IERC20 {
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address owner, address to, uint256 amount) external returns (bool);
    function approve(address spender, uint256 allowance) external returns (bool);
}

// Minimal WETH interface.
interface IWETH is IERC20 {
    function deposit() payable external;
    function withdraw(uint256 weth) external;
}

// Minimal ERC4626 interface.
interface IERC4626 is IERC20 {
    function asset() external returns (IERC20);
    function deposit(uint256 assets, address receiver) external returns (uint256 shares);
    function redeem(uint256 shares, address receiver, address owner) external returns (uint256 assets);
}