// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

// Contract that we will fake deploy and call directly into to evaluate
// the outcome of a complex swap between two protocols.
contract EthSwapForwarder {
    IUniswapForkRouter private constant SUSHI_SWAP_ROUTER =
        IUniswapForkRouter(0xd9e1cE17f2641f24aE83637ab66a2cca9C378B9F);
    IUniswapForkRouter private constant UNISWAP_ROUTER =
        IUniswapForkRouter(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);
    IERC20 private constant WETH = IERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    IERC20 private constant USDC = IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    IERC20 private constant DAI = IERC20(0x6B175474E89094C44Da98b954EedeAC495271d0F);

    // Function we will eth_call from our script.
    // Performs an ETH -> USDC swap on sushiswap then a USDC -> DAI swap on uniswap
    // and returns the final amount of DAI we receive.
    function swap() external payable returns (uint256 daiAmount) {
        IERC20[] memory path = new IERC20[](2);
        // WETH -> USDC leg on sushiswap.
        (path[0], path[1]) = (WETH, USDC);
        SUSHI_SWAP_ROUTER.swapExactETHForTokens{value: msg.value}(
            0, path, address(this), block.timestamp
        );
        // USDC -> DAI leg on uniswap (v2).
        USDC.approve(address(UNISWAP_ROUTER), type(uint256).max);
        (path[0], path[1]) = (USDC, DAI);
        UNISWAP_ROUTER.swapExactTokensForTokens(
            USDC.balanceOf(address(this)), 0, path, address(this), block.timestamp
        );
        return DAI.balanceOf(address(this));
    }
}

// Minimal ERC20 interface.
interface IERC20 {
    function balanceOf(address owner) external view returns (uint256);
    function approve(address spender, uint256 allowance) external;
}

// Minimal Uniswap/Sushiswap router interface.
interface IUniswapForkRouter {
    function swapExactETHForTokens(
        uint256 minOut,
        IERC20[] memory path,
        address receiver,
        uint256 deadline
    ) external payable;
    function swapExactTokensForTokens(
        uint256 exactIn,
        uint256 minOut,
        IERC20[] memory path,
        address receiver,
        uint256 deadline
    ) external;
}
