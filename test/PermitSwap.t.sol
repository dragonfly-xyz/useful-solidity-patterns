// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "../patterns/erc20-permit/PermitSwap.sol";
import "./TestUtils.sol";

contract PermitSwapTest is TestUtils {
    using stdStorage for StdStorage;

    uint256 userPrivateKey;
    address user;
    PermitSwap pswap = new PermitSwap();
    IERC2612 constant usdc = IERC2612(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    IERC20 constant weth = IERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);

    constructor() {
        userPrivateKey = _randomUint256();
        user = vm.addr(userPrivateKey);
    }

    function testFork_canSwapUSDCForWeth() onlyForked external {
        _setTokenBalance(address(usdc), user, 1e18);
        address[] memory path = new address[](2);
        path[0] = address(usdc);
        path[1] = address(weth);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            userPrivateKey,
            _getPermitHash(
                usdc,
                user,
                address(pswap),
                1e18,
                0, // Nonce is always 0 because user is a fresh address.
                block.timestamp
            )
        );
        vm.prank(user);
        uint256 wethAmount = pswap.swapWithPermit(
            1e18,
            1,
            block.timestamp,
            path,
            v,
            r,
            s
        );
        assertTrue(wethAmount > 0);
        assertEq(weth.balanceOf(user), wethAmount);
    }

    function _getPermitHash(
        IERC2612 token,
        address owner,
        address spender,
        uint256 value,
        uint256 nonce,
        uint256 deadline
    )
        private
        view
        returns (bytes32 h)
    {
        bytes32 domainHash = token.DOMAIN_SEPARATOR();
        bytes32 typeHash =
            keccak256('Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)');
        bytes32 structHash = keccak256(abi.encode(
            typeHash,
            owner,
            spender,
            value,
            nonce,
            deadline
        ));
        return keccak256(abi.encodePacked('\x19\x01', domainHash, structHash));
    }

    function _setTokenBalance(address erc20, address owner, uint256 bal) private {
        stdstore
            .target(erc20)
            .sig('balanceOf(address)')
            .with_key(owner)
            .checked_write(bal);
    }
}