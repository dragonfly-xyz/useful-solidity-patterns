// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "./TestUtils.sol";

// Tests for a collection of short assembly tricks.
contract AssemblyTricks1Test is TestUtils {

    struct Foo {
        address addr;
        uint256 x;
    }

    struct Bar {
        AssemblyTricks1Test tricks;
        bytes32 x;
    }
    
    error RevertTriggeredError(uint256 payload);

    function triggerRevert(uint256 revertPayload) external pure {
        revert RevertTriggeredError(revertPayload);
    }

    function bubbleUpRevert(uint256 revertPayload) external view {
        try this.triggerRevert(revertPayload) {}
        catch (bytes memory revertData) {
            assembly { revert(add(revertData, 0x20), mload(revertData)) }
        }
    }

    function test_bubbleUpRevert() external {
        uint256 payload = _randomUint256();
        try this.bubbleUpRevert(payload) {
            revert('Expected revert');
        } catch (bytes memory revertData) {
            assertEq(
                keccak256(revertData),
                keccak256(abi.encodeWithSelector(RevertTriggeredError.selector, (payload)))
            );
        }
    }

    function test_hashTwoWords() external {
        uint256 word1 = _randomUint256();
        bytes32 word2 = _randomBytes32();
        bytes32 regHash = keccak256(abi.encode(word1, word2));
        bytes32 asmHash;
        assembly { 
            mstore(0x00, word1)
            mstore(0x20, word2)
            asmHash := keccak256(0x00, 0x40)
        }
        assertEq(regHash, asmHash);
    }

    function test_castDynamicArrays() external {
        address[] memory addressArr = new address[](10);
        for (uint256 i; i < addressArr.length; ++i) {
            addressArr[i] = _randomAddress();
        }
        AssemblyTricks1Test[] memory contractArr;
        assembly { contractArr := addressArr }
        assertEq(contractArr.length, addressArr.length);
        assertEq(keccak256(abi.encode(addressArr)), keccak256(abi.encode(contractArr)));
    }

    function test_castStaticArrays() external {
        address[8] memory addressArr;
        for (uint256 i; i < addressArr.length; ++i) {
            addressArr[i] = _randomAddress();
        }
        AssemblyTricks1Test[8] memory contractArr;
        assembly { contractArr := addressArr }
        assertEq(contractArr.length, addressArr.length);
        assertEq(keccak256(abi.encode(addressArr)), keccak256(abi.encode(contractArr)));
    }

    function test_castStructs() external {
        Foo memory foo = Foo({
            addr: _randomAddress(),
            x: _randomUint256()
        });
        Bar memory bar;
        assembly { bar := foo }
        assertEq(keccak256(abi.encode(foo)), keccak256(abi.encode(bar)));
    }

    function test_shortenDynamicArray() external {
        uint256[] memory arr = new uint256[](10);
        for (uint256 i; i < arr.length; ++i) {
            arr[i] = _randomUint256();
        }
        uint256[] memory shortArrCopy = new uint256[](9);
        for (uint256 i; i < shortArrCopy.length; ++i) {
            shortArrCopy[i] = arr[i];
        }
        assembly { mstore(arr, 9) }
        assertEq(arr.length, 9);
        assertEq(keccak256(abi.encode(arr)), keccak256(abi.encode(shortArrCopy)));
    }

    function test_shortenFixedArray() external {
        uint256[10] memory arr;
        for (uint256 i; i < arr.length; ++i) {
            arr[i] = _randomUint256();
        }
        uint256[9] memory shortArrCopy;
        for (uint256 i; i < shortArrCopy.length; ++i) {
            shortArrCopy[i] = arr[i];
        }
        uint256[9] memory shortArr;
        assembly { shortArr := arr }
        assertEq(shortArr.length, 9);
        assertEq(keccak256(abi.encode(shortArr)), keccak256(abi.encode(shortArrCopy)));
    }
}