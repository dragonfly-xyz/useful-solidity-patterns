// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import "../patterns/merkle-proofs/MerkleProofs.sol";
import "./TestUtils.sol";

contract MerkleProofsTest is Test, TestUtils {
    MerkleDropHelper immutable helper = new MerkleDropHelper();

    function _createDrop(uint256 size)
        private
        returns (
            address[] memory members,
            uint256[] memory claimAmounts,
            bytes32[][] memory tree,
            MerkleDrop drop
        )
    {
        uint256 numMembers = size;
        uint256 totalEth = 0;
        members = new address[](numMembers);
        claimAmounts = new uint256[](numMembers);
        for (uint256 i = 0; i < numMembers; ++i) {
            members[i] = _randomAddress();
            uint256 a = 1 + _randomUint256() % 1e18;
            claimAmounts[i] = a;
            totalEth += a;
        }
        bytes32 root;
        (root, tree) = helper.constructTree(members, claimAmounts);
        vm.deal(address(this), totalEth);
        drop = new MerkleDrop{ value: totalEth }(root);
    }

    function test_constructTree1() external {
        (
            ,
            ,
            bytes32[][] memory tree,
            MerkleDrop drop
        ) = _createDrop(1);
        assertEq(tree.length, 1);
        assertEq(tree[0].length, 1);
        assertEq(drop.ROOT(), tree[0][0]);
    }

    function test_constructTree2() external {
        (
            ,
            ,
            bytes32[][] memory tree,
            MerkleDrop drop
        ) = _createDrop(2);
        assertEq(tree.length, 2);
        assertEq(tree[0].length, 2);
        assertEq(tree[1].length, 1);
        assertTrue(tree[0][0] != 0);
        assertTrue(tree[0][1] != 0);
        assertEq(drop.ROOT(), tree[1][0]);
    }

    function test_constructTree3() external {
        (
            ,
            ,
            bytes32[][] memory tree,
            MerkleDrop drop
        ) = _createDrop(3);
        assertEq(tree.length, 3);
        assertEq(tree[0].length, 3);
        assertEq(tree[1].length, 2);
        assertEq(tree[2].length, 1);
        assertTrue(tree[0][0] != 0);
        assertTrue(tree[0][1] != 0);
        assertTrue(tree[0][2] != 0);
        assertEq(drop.ROOT(), tree[2][0]);
    }

    function test_constructTree4() external {
        (
            ,
            ,
            bytes32[][] memory tree,
            MerkleDrop drop
        ) = _createDrop(4);
        assertEq(tree.length, 3);
        assertEq(tree[0].length, 4);
        assertEq(tree[1].length, 2);
        assertEq(tree[2].length, 1);
        assertTrue(tree[0][0] != 0);
        assertTrue(tree[0][1] != 0);
        assertTrue(tree[0][2] != 0);
        assertTrue(tree[0][3] != 0);
        assertEq(drop.ROOT(), tree[2][0]);
    }

    function test_constructTree5() external {
        (
            ,
            ,
            bytes32[][] memory tree,
            MerkleDrop drop
        ) = _createDrop(5);
        assertEq(tree.length, 4);
        assertEq(tree[0].length, 5);
        assertEq(tree[1].length, 3);
        assertEq(tree[2].length, 2);
        assertEq(tree[3].length, 1);
        assertTrue(tree[0][0] != 0);
        assertTrue(tree[0][1] != 0);
        assertTrue(tree[0][2] != 0);
        assertTrue(tree[0][3] != 0);
        assertTrue(tree[0][4] != 0);
        assertEq(drop.ROOT(), tree[3][0]);
    }

    function test_constructTree6() external {
        (
            ,
            ,
            bytes32[][] memory tree,
            MerkleDrop drop
        ) = _createDrop(6);
        assertEq(tree.length, 4);
        assertEq(tree[0].length, 6);
        assertEq(tree[1].length, 3);
        assertEq(tree[2].length, 2);
        assertEq(tree[3].length, 1);
        assertTrue(tree[0][0] != 0);
        assertTrue(tree[0][1] != 0);
        assertTrue(tree[0][2] != 0);
        assertTrue(tree[0][3] != 0);
        assertTrue(tree[0][4] != 0);
        assertTrue(tree[0][5] != 0);
        assertEq(drop.ROOT(), tree[3][0]);
    }

    function test_constructTreeRandom() external {
        (
            address[] memory members,
            ,
            bytes32[][] memory tree,
            MerkleDrop drop
        ) = _createDrop(1 + _randomUint256() % 128);
        assertTrue(tree[0].length >= members.length);
        for (uint256 i = 0; i < members.length; ++i) {
            assertTrue(tree[0][i] != 0);
        }
        assertEq(drop.ROOT(), tree[tree.length - 1][0]);
    }

    function test_createProof() external {
        (
            address[] memory members,
            uint256[] memory claimAmounts,
            bytes32[][] memory tree,
        ) = _createDrop(1 + _randomUint256() % 128);
        uint256 memberIndex = _randomUint256() % members.length;
        bytes32[] memory proof = helper.createProof(memberIndex, tree);
        assertEq(proof.length, tree.length - 1, 'wrong proof length');
        bytes32 leafHash = ~keccak256(abi.encode(
            members[memberIndex],
            claimAmounts[memberIndex]
        ));
        assertEq(tree[0][memberIndex], leafHash);
        for (uint256 i = 0; i < proof.length; ++i) {
            assertTrue(proof[i] != leafHash, 'leaf hash should not be in proof');
        }
    }

    function test_prove() external {
        (
            address[] memory members,
            uint256[] memory claimAmounts,
            bytes32[][] memory tree,
            MerkleDrop drop
        ) = _createDrop(1 + _randomUint256() % 256);
        uint256 memberIndex = _randomUint256() % members.length;
        bytes32 leafHash = ~keccak256(abi.encode(
            members[memberIndex],
            claimAmounts[memberIndex]
        ));
        bytes32[] memory proof = helper.createProof(memberIndex, tree);
        assertTrue(drop.prove(leafHash, proof));
    }

    function test_failingProve() external {
        (
            address[] memory members,
            uint256[] memory claimAmounts,
            bytes32[][] memory tree,
            MerkleDrop drop
        ) = _createDrop(1 + _randomUint256() % 256);
        uint256 memberIndex = _randomUint256() % members.length;
        bytes32 leafHash = ~keccak256(abi.encode(
            members[memberIndex],
            claimAmounts[memberIndex] + 1
        ));
        bytes32[] memory proof = helper.createProof(memberIndex, tree);
        assertTrue(!drop.prove(leafHash, proof));
    }

    function test_invalidProve() external {
        (
            address[] memory members,
            uint256[] memory claimAmounts,
            bytes32[][] memory tree,
            MerkleDrop drop
        ) = _createDrop(1 + _randomUint256() % 256);
        uint256 memberIndex = _randomUint256() % members.length;
        bytes32 leafHash = keccak256(abi.encode(
            members[memberIndex],
            claimAmounts[memberIndex]
        ));
        bytes32[] memory proof = helper.createProof(memberIndex, tree);
        assembly { mstore(proof, add(mload(proof), 1)) }
        assertFalse(drop.prove(leafHash, proof));
    }

    function test_claim() external {
        (
            address[] memory members,
            uint256[] memory claimAmounts,
            bytes32[][] memory tree,
            MerkleDrop drop
        ) = _createDrop(1 + _randomUint256() % 256);
        uint256 memberIndex = _randomUint256() % members.length;
        bytes32[] memory proof = helper.createProof(memberIndex, tree);
        vm.prank(members[memberIndex]);
        drop.claim(payable(members[memberIndex]), claimAmounts[memberIndex], proof);
        assertEq(members[memberIndex].balance, claimAmounts[memberIndex]);
    }

    function test_cannotclaimTwice() external {
        (
            address[] memory members,
            uint256[] memory claimAmounts,
            bytes32[][] memory tree,
            MerkleDrop drop
        ) = _createDrop(1 + _randomUint256() % 256);
        uint256 memberIndex = _randomUint256() % members.length;
        bytes32[] memory proof = helper.createProof(memberIndex, tree);
        vm.prank(members[memberIndex]);
        drop.claim(payable(members[memberIndex]), claimAmounts[memberIndex], proof);
        vm.prank(members[memberIndex]);
        vm.expectRevert('already claimed');
        drop.claim(payable(members[memberIndex]), claimAmounts[memberIndex], proof);
    }

    function _logTree(bytes32[][] memory tree) private {
        emit log_named_uint('tree height', tree.length);
        emit log_named_uint('tree width', tree[0].length);
        for (uint256 h = 0; h < tree.length; ++h) {
            bytes32[] memory row = tree[h];
            uint256[] memory row_;
            assembly { row_ := row }
            emit log_array(row_);
        }
    }

    function _logBytes32Array(bytes32[] memory arr) private {
        uint256[] memory arr_;
        assembly { arr_ := arr}
        emit log_array(arr_);
    }
}
