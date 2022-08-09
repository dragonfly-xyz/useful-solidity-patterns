// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8;

import "forge-std/Test.sol";

contract TestUtils is Test {
    uint256 private immutable _nonce;

    constructor() {
        _nonce = uint256(keccak256(abi.encode(
            tx.origin,
            tx.origin.balance,
            block.number,
            block.timestamp,
            block.coinbase,
            gasleft()
        )));
    }

    function _randomBytes32() internal view returns (bytes32) {
        bytes memory seed = abi.encode(
            _nonce,
            block.timestamp,
            gasleft()
        );
        return keccak256(seed);
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
}
