// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

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
        address expected;
        assembly {
            mstore(0x02, shl(96, deployer))
            let rlpNonceLength
            switch gt(deployNonce, 0xFFFFFF)
                case 1 { // 4 byte nonce
                    rlpNonceLength := 5
                    mstore8(0x00, 0xD8)
                    mstore8(0x16, 0x84)
                    mstore(0x17, shl(224, deployNonce))
                }
                default {
                    switch gt(deployNonce, 0xFFFF)
                        case 1 {
                            // 3 byte nonce
                            rlpNonceLength := 4
                            mstore8(0x16, 0x83)
                            mstore(0x17, shl(232, deployNonce))
                        }
                        default {
                            switch gt(deployNonce, 0xFF)
                                case 1 {
                                    // 2 byte nonce
                                    rlpNonceLength := 3
                                    mstore8(0x16, 0x82)
                                    mstore(0x17, shl(240, deployNonce))
                                }
                                default {
                                    switch gt(deployNonce, 0x7F)
                                        case 1 {
                                            // 1 byte nonce >= 0x80
                                            rlpNonceLength := 2
                                            mstore8(0x16, 0x81)
                                            mstore8(0x17, deployNonce)
                                        }
                                        default {
                                            rlpNonceLength := 1
                                            switch iszero(deployNonce)
                                                case 1 {
                                                    // zero nonce
                                                    mstore8(0x16, 0x80)
                                                }
                                                default {
                                                    // 1 byte nonce < 0x80
                                                    mstore8(0x16, deployNonce)
                                                }
                                        }
                                }
                        }
                }
            mstore8(0x00, add(0xD5, rlpNonceLength))
            mstore8(0x01, 0x94)
            expected := and(
                keccak256(0x00, add(0x16, rlpNonceLength)),
                0xffffffffffffffffffffffffffffffffffffffff
            )
        }
        return deployed == expected;
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
}
