// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

contract FactoryProofs {
    // Validate that `deployed` was deployed by `deployer` using regular create opcode
    // given the `deployNonce` it was deployed with.
    function verifyDeployedBy(address deployed, address deployer, uint32 deployNonce)
        external
        pure
        returns (bool)
    {
        // The address a contract will be deployed at with the create opcode is
        // simply the hash of the RLP encoded deployer address + deployer nonce.
        // For EOA deployers, the deploy nonce is the account's nonce
        // (number of txs it has executed) when it deployed the contract.
        // For contract deployers, the deploy nonce is 1 + the number of other contracts
        // that contract has deployed (using regular create opcode).
        bytes memory rlpNonce = rlpEncodeNonce(deployNonce);
        address expected = address(uint160(uint256(keccak256(abi.encodePacked(
            bytes1(uint8(0xC0 + 21 + rlpNonce.length)),
            bytes1(uint8(0x80 + 20)),
            deployer,
            rlpNonce
        )))));
        return expected == deployed;
    }

    // Validate that `deployed` was deployed by `deployer` using create2 opcode
    // given the `initCodeHash` (hash of the deployed contract's `creationCode`)
    // and the `deploySalt` it was deployed with.
    function verifySaltedDeployedBy(
        address deployed,
        address deployer,
        bytes32 initCodeHash,
        bytes32 deploySalt
    )
        external
        pure
        returns (bool)
    {
        // The address a contract will be deployed at with the create2 opcode is
        // the hash of:
        // '\xff' + deployer address + salt + keccak256(type(DEPLOYED_CONTRACT).creationCode)
        address expected = address(uint160(uint256(keccak256(abi.encodePacked(
            hex'ff',
            deployer,
            deploySalt,
            initCodeHash
        )))));
        return expected == deployed;
    }

    // RLP-encode an (up to) 32-bit number.
    function rlpEncodeNonce(uint32 nonce)
        private
        pure
        returns (bytes memory rlpNonce)
    {
        // See https://github.com/ethereum/wiki/wiki/RLP for RLP encoding rules.
        if (nonce == 0) {
            rlpNonce = new bytes(1);
            rlpNonce[0] = 0x80;
        } else if (nonce < 0x80) {
            rlpNonce = new bytes(1);
            rlpNonce[0] = bytes1(uint8(nonce));
        } else if (nonce <= 0xFF) {
            rlpNonce = new bytes(2);
            rlpNonce[0] = 0x81;
            rlpNonce[1] = bytes1(uint8(nonce));
        } else if (nonce <= 0xFFFF) {
            rlpNonce = new bytes(3);
            rlpNonce[0] = 0x82;
            rlpNonce[1] = bytes1(uint8((nonce & 0xFF00) >> 8));
            rlpNonce[2] = bytes1(uint8(nonce));
        } else if (nonce <= 0xFFFFFF) {
            rlpNonce = new bytes(4);
            rlpNonce[0] = 0x83;
            rlpNonce[1] = bytes1(uint8((nonce & 0xFF0000) >> 16));
            rlpNonce[2] = bytes1(uint8((nonce & 0xFF00) >> 8));
            rlpNonce[3] = bytes1(uint8(nonce));
        } else {
            rlpNonce = new bytes(5);
            rlpNonce[0] = 0x84;
            rlpNonce[1] = bytes1(uint8((nonce & 0xFF000000) >> 24));
            rlpNonce[2] = bytes1(uint8((nonce & 0xFF0000) >> 16));
            rlpNonce[3] = bytes1(uint8((nonce & 0xFF00) >> 8));
            rlpNonce[4] = bytes1(uint8(nonce));
        }
    }
}
