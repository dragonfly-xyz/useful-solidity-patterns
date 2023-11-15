pragma solidity ^0.8.23;

import "../patterns/only-delegatecall-no-delegatecall/DelegateCallModifiers.sol";
import "./TestUtils.sol";

contract DelegateCallModifiersTest is TestUtils {
    Logic logic = new Logic();
    SafeLogic safeLogic = new SafeLogic();
    
    function test_unsafe_canSkimFromProxy() external {
        Logic inst = Logic(payable(new Proxy(logic, address(this))));
        payable(inst).transfer(100);
        address payable receiver = _randomAddress();
        inst.skim(receiver);
        assertEq(receiver.balance, 100);
    }

    function test_safe_cannotSkimFromProxy() external {
        Logic inst = Logic(payable(new Proxy(safeLogic, address(this))));
        payable(inst).transfer(100);
        address payable receiver = _randomAddress();
        vm.expectRevert('must not be delegatecall');
        inst.skim(receiver);
    }

    function test_unsafe_canDieProxy() external {
        Logic inst = Logic(payable(new Proxy(logic, address(this))));
        payable(inst).transfer(100);
        address payable receiver = _randomAddress();
        inst.die(receiver);
        assertEq(receiver.balance, 100);
        // Note: No way currently to assert selfdestruct in foundry since bytecode is
        // cleared after the TX (this test) ends.
    }

    function test_safe_canDieProxy() external {
        Logic inst = Logic(payable(new Proxy(safeLogic, address(this))));
        payable(inst).transfer(100);
        address payable receiver = _randomAddress();
        inst.die(receiver);
        assertEq(receiver.balance, 100);
        // Note: No way currently to assert selfdestruct in foundry since bytecode is
        // cleared after the TX (this test) ends.
    }

    function test_unsafe_canDieLogic() external {
        payable(logic).transfer(100);
        address payable receiver = _randomAddress();
        logic.initialize(address(this));
        logic.die(receiver);
        assertEq(receiver.balance, 100);
        // Note: No way currently to assert selfdestruct in foundry since bytecode is
        // cleared after the TX (this test) ends.
    }

    function test_safe_cannotDieLogic() external {
        payable(safeLogic).transfer(100);
        address payable receiver = _randomAddress();
        safeLogic.initialize(address(this));
        vm.expectRevert('must be a delegatecall');
        safeLogic.die(receiver);
        // Note: No way currently to assert selfdestruct in foundry since bytecode is
        // cleared after the TX (this test) ends.
    }
}

