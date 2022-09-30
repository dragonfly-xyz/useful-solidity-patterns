// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

// Minimal ERC20 interface.
interface IERC20 {
    function balanceOf(address owner) external view returns (uint256);
    function transferFrom(address owner, address to, uint256 amount) external returns (bool);
    function approve(address spender, uint256 amount) external returns (bool);
}

// ERC20 with EIP2612 extension functions.
interface IERC2612 is IERC20 {
    function permit(
        address owner,
        address spender,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external;
    function nonces(address owner) external view returns (uint);
    function DOMAIN_SEPARATOR() external view returns (bytes32);
}

// Minimal Uniswap V2 Router interface.
interface IUniswapV2Router {
    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts);
}

contract PermitSwap {
    IUniswapV2Router public constant UNISWAP_V2_ROUTER =
        IUniswapV2Router(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);

    function swapWithPermit(
        uint256 sellAmount,
        uint256 minBuyAmount,
        uint256 deadline,
        address[] calldata path,
        uint8 v,
        bytes32 r,
        bytes32 s
    )
        external
        returns (uint256 boughtAmount)
    {
        IERC2612 sellToken = IERC2612(path[0]);
        // Consume the permit message. Note that we don't need to pass in `nonce`--
        // that value will be looked up on-chain.
        sellToken.permit(msg.sender, address(this), sellAmount, deadline, v, r, s);
        // Use our allowance to transfer `sellToken` to ourself.
        sellToken.transferFrom(msg.sender, address(this), sellAmount);
        // Grant the uniswap v2 router an allowance to spend our tokens.
        sellToken.approve(address(UNISWAP_V2_ROUTER), sellAmount);
        // Perform the swap.
        uint256[] memory amounts = UNISWAP_V2_ROUTER.swapExactTokensForTokens(
            sellAmount,
            minBuyAmount,
            path,
            msg.sender,
            deadline
        );
        return amounts[amounts.length - 1];
    }
}