// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8;

import "forge-std/Test.sol";

contract TestUtils is Test {  uint256 internal constant PANIC_ASSERT = 0x01;
    uint256 internal constant PANIC_MATH_UNDEROVERFLOW = 0x11;
    uint256 internal constant PANIC_MATH_DIVIDE_BY_ZERO = 0x12;
    uint256 internal constant INDEX_OUT_OF_BOUNDS = 0x32;

    bytes4 internal constant PANIC_SELECTOR = bytes4(keccak256("Panic(uint256)"));

    modifier onlyForked() {
        if (block.number > 1e6) {
            _;
        }
    }

    function _randomBytes32() internal view returns (bytes32) {
        return keccak256(abi.encode(
            tx.origin,
            block.number,
            block.timestamp,
            block.coinbase,
            address(this).codehash,
            gasleft()
        ));
    }

    function _randomUint256() internal view returns (uint256) {
        return uint256(_randomBytes32());
    }

    function _randomAddress() internal view returns (address payable) {
        return payable(address(uint160(_randomUint256())));
    }

    function _randomRange(uint256 lo, uint256 hi) internal view returns (uint256) {
        return lo + (_randomUint256() % (hi - lo));
    }

    function _toAddressArray(address v) internal pure returns (address[] memory arr) {
        arr = new address[](1);
        arr[0] = v;
    }

    function _toUint256Array(uint256 v) internal pure returns (uint256[] memory arr) {
        arr = new uint256[](1);
        arr[0] = v;
    }

    function _expectNonIndexedEmit() internal {
        vm.expectEmit(false, false, false, true);
    }
    
    function _expectPanic(uint256 code_) internal {
        vm.expectRevert(abi.encodeWithSelector(PANIC_SELECTOR, code_));
    }
}
