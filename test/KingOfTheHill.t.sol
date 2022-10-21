// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "./TestUtils.sol";
import "../patterns/eoa-checks/KingOfTheHill.sol";

contract KingOfTheHillTest is TestUtils {
    BrickableKingOfTheHill brickableGame =  new BrickableKingOfTheHill();
    OnlyEOAKingOfTheHill eoaGame = new OnlyEOAKingOfTheHill();
    ClaimableKingOfTheHill claimableGame = new ClaimableKingOfTheHill();
    EvilKing evilKing = new EvilKing();
    SmartKing smartKing = new SmartKing();
    address initialKing;

    constructor() {
        initialKing = _randomAddress();
        vm.deal(initialKing, 0.01 ether * 3);
        // Set up an original king for each game.
        vm.prank(initialKing, initialKing);
        brickableGame.takeCrown{ value: 0.01 ether }('first');
        vm.prank(initialKing, initialKing);
        eoaGame.takeCrown{ value: 0.01 ether }('first');
        vm.prank(initialKing, initialKing);
        claimableGame.takeCrown{ value: 0.01 ether }('first');
    }

    function test_brickableGame_canTakeCrown() external {
        uint256 price = brickableGame.price();
        address king = _randomAddress();
        vm.deal(king, price);
        vm.prank(king);
        brickableGame.takeCrown{ value: price }('foo');
        assertEq(brickableGame.message(), 'foo');
        assertEq(brickableGame.price(), price + 1);
        assertEq(brickableGame.king(), king);
        assertEq(initialKing.balance, price);
    }

    function test_brickableGame_cannotTakeCrownWithLessThanPrice() external {
        uint256 price = brickableGame.price();
        address king = _randomAddress();
        vm.deal(king, price);
        vm.prank(king);
        vm.expectRevert('not enough payment');
        brickableGame.takeCrown{ value: price - 1 }('foo');
    }

    function test_brickableGame_canBrickGame() external {
        uint256 price = brickableGame.price();
        evilKing.becomeKing{ value: price }(brickableGame, 'foo');
        assertEq(brickableGame.king(), address(evilKing));
        address king = _randomAddress();
        vm.deal(king, price + 1);
        vm.prank(king);
        vm.expectRevert('king forever');
        brickableGame.takeCrown{ value: price + 1 }('my turn');
    }
    
    function test_eoaGame_eoaCanTakeCrown() external {
        uint256 price = eoaGame.price();
        address king = _randomAddress();
        vm.deal(king, price);
        vm.prank(king, king);
        eoaGame.takeCrown{ value: price }('foo');
        assertEq(eoaGame.message(), 'foo');
        assertEq(eoaGame.price(), price + 1);
        assertEq(eoaGame.king(), king);
        assertEq(initialKing.balance, price);
    }

    function test_eoaGame_contractCannotTakeCrown() external {
        uint256 price = eoaGame.price();
        vm.deal(address(evilKing), price);
        vm.expectRevert('only EOA');
        evilKing.becomeKing{ value: price }(eoaGame, 'foo');
    }

    function test_claimableGame_eoaCanTakeCrown() external {
        uint256 price = claimableGame.price();
        address king = _randomAddress();
        vm.deal(king, price);
        vm.prank(king);
        claimableGame.takeCrown{ value: price }('foo');
        assertEq(claimableGame.message(), 'foo');
        assertEq(claimableGame.price(), price + 1);
        assertEq(claimableGame.king(), king);
        assertEq(initialKing.balance, price);
    }

    function test_claimableGame_contractCanTakeCrown() external {
        uint256 price = claimableGame.price();
        evilKing.becomeKing{ value: price }(claimableGame, 'foo');
        assertEq(claimableGame.message(), 'foo');
        assertEq(claimableGame.price(), price + 1);
        assertEq(claimableGame.king(), address(evilKing));
        assertEq(initialKing.balance, price);
    }

    function test_claimableGame_contractCanClaim() external {
        uint256 price = claimableGame.price();
        smartKing.becomeKing{ value: price }(claimableGame, 'foo');
        assertEq(claimableGame.king(), address(smartKing));
        address king = _randomAddress();
        vm.deal(king, price + 1);
        vm.prank(king);
        claimableGame.takeCrown{ value: price + 1 }('my turn');
        assertEq(claimableGame.king(), king);
        assertEq(address(smartKing).balance, 0);
        assertEq(claimableGame.owed(address(smartKing)), price + 1);
        vm.prank(address(smartKing));
        claimableGame.claim();
        assertEq(address(smartKing).balance, price + 1);
    }
}

contract SmartKing is EvilKing {
    receive() external override payable {}
}