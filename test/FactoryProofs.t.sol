// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import "../patterns/factory-proofs/FactoryProofs.sol";
import "./TestUtils.sol";

contract FactoryProofsTest is Test, TestUtils {
    Deployer deployer = new Deployer();
    FactoryProofs proofs = new FactoryProofs();

    function test_verifyCreate1() external {
        address deployed = deployer.deploy1();
        assertTrue(
            proofs.verifyDeployedBy(deployed, address(deployer), uint32(deployer.lastNonce()))
        );
    }

    function test_verifyCreate1_multiple() external {
        for (uint256 i = 0; i < 10; ++i) {
            address deployed = deployer.deploy1();
            assertTrue(
                proofs.verifyDeployedBy(deployed, address(deployer), uint32(deployer.lastNonce()))
            );
        }
    }

    function test_verifyCreate1_wrongNonceFails() external {
        address deployed = deployer.deploy1();
        assertFalse(
            proofs.verifyDeployedBy(deployed, address(deployer), uint32(_randomUint256()))
        );
    }

    function test_verifyCreate2() external {
        bytes32 salt = _randomBytes32();
        address deployed = deployer.deploy2(salt);
        assertTrue(
            proofs.verifySaltedDeployedBy(
                deployed,
                address(deployer),
                keccak256(type(NewContract).creationCode),
                salt
            )
        );
    }

    function test_verifyCreate2_multiple() external {
        for (uint256 i = 0; i < 10; ++i) {
            bytes32 salt = _randomBytes32();
            address deployed = deployer.deploy2(salt);
            assertTrue(
                proofs.verifySaltedDeployedBy(
                    deployed,
                    address(deployer),
                    keccak256(type(NewContract).creationCode),
                    salt
                )
            );
        }
    }

    function test_verifyCreate2_wrongSaltFails() external {
        bytes32 salt = _randomBytes32();
        address deployed = deployer.deploy2(salt);
        assertFalse(
            proofs.verifySaltedDeployedBy(
                deployed,
                address(deployer),
                keccak256(type(NewContract).creationCode),
                _randomBytes32()
            )
        );
    }

    function test_verifyCreate2_wrongInitCodeHashFails() external {
        bytes32 salt = _randomBytes32();
        address deployed = deployer.deploy2(salt);
        assertFalse(
            proofs.verifySaltedDeployedBy(
                deployed,
                address(deployer),
                _randomBytes32(),
                salt
            )
        );
    }

    function test_verifyCreate1AndCreate2() external {
        address deployed = deployer.deploy1();
        assertTrue(
            proofs.verifyDeployedBy(deployed, address(deployer), uint32(deployer.lastNonce()))
        );
        bytes32 salt = _randomBytes32();
        deployed = deployer.deploy2(salt);
        assertTrue(
            proofs.verifySaltedDeployedBy(
                deployed,
                address(deployer),
                keccak256(type(NewContract).creationCode),
                salt
            )
        );
    }

    function test_verifyCreate1_EOA() external {
        address eoaDeployer = _randomAddress();
        vm.prank(eoaDeployer, eoaDeployer);
        address deployed = address(new NewContract());
        assertTrue(
            proofs.verifyDeployedBy(deployed, address(eoaDeployer), 0)
        );
    }
}

// The contract to deploy.
contract NewContract {}

// The contract doing the deploying.
contract Deployer {
    // All contracts start with a nonce of 1, which goes up
    // each time it deploys a new contract via create().
    uint256 public lastNonce = 0;

    function deploy1() external returns (address deployed) {
        ++lastNonce;
        return address(new NewContract());
    }

    function deploy2(bytes32 salt) external returns (address deployed) {
        return address(new NewContract{salt: salt}());
    }
}
