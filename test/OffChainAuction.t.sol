// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import "solmate/tokens/ERC721.sol";

import "../patterns/off-chain-storage/OffChainAuction.sol";
import "./TestUtils.sol";

contract OffChainAuctionTest is Test, TestUtils {
    OffChainAuction protocol = new OffChainAuction();
    MintableERC721 token = new MintableERC721();

    function test_canCreateAuction() external {
        (uint256 auctionId, OffChainAuction.AuctionState memory state) =
            _createAuction(0.1 ether, 10 seconds);
        assertTrue(protocol.auctionStateHashes(auctionId) != 0);
        assertEq(address(state.token), address(token));
        assertEq(state.topBid, 0.1 ether);
        assertEq(state.topBidder, address(0));
        assertEq(token.ownerOf(state.tokenId), address(protocol));
    }

    function test_canBidOnAuction() external {
        (uint256 auctionId, OffChainAuction.AuctionState memory state) =
            _createAuction(0.1 ether, 10 seconds);
        address firstBidder = _randomAddress();
        uint256 firstBid = state.topBid;
        vm.deal(firstBidder, firstBid);
        vm.prank(firstBidder);
        state = protocol.bid{ value: firstBid }(auctionId, state);
        assertEq(state.topBidder, firstBidder);
        assertEq(state.topBid, firstBid);
        assertEq(firstBidder.balance, 0);
        address nextBidder = _randomAddress();
        uint256 nextBid = state.topBid + 1;
        vm.deal(nextBidder, nextBid);
        vm.prank(nextBidder);
        state = protocol.bid{ value: nextBid }(auctionId, state);
        assertEq(state.topBidder, nextBidder);
        assertEq(state.topBid, nextBid);
        assertEq(firstBidder.balance, firstBid);
        assertEq(nextBidder.balance, 0);
    }

    function test_canExpireAuction() external {
        (uint256 auctionId, OffChainAuction.AuctionState memory state) =
            _createAuction(0.1 ether, 10 seconds);
        skip(10 seconds);
        protocol.settle(auctionId, state);
        assertEq(token.ownerOf(state.tokenId), state.owner);
        assertEq(protocol.auctionStateHashes(auctionId), 0);
    }

    function test_canSettleAuction() external {
        (uint256 auctionId, OffChainAuction.AuctionState memory state) =
            _createAuction(0.1 ether, 10 seconds);
        address bidder = _randomAddress();
        uint256 bid = state.topBid;
        vm.deal(bidder, bid);
        vm.prank(bidder);
        state = protocol.bid{ value: bid }(auctionId, state);
        skip(state.duration);
        protocol.settle(auctionId, state);
        assertEq(token.ownerOf(state.tokenId), bidder);
        assertEq(state.owner.balance, state.topBid);
        assertEq(state.topBidder.balance, 0);
        assertEq(protocol.auctionStateHashes(auctionId), 0);
    }

    function test_cannotStartBiddingTooLow() external {
        (uint256 auctionId, OffChainAuction.AuctionState memory state) =
            _createAuction(0.1 ether, 10 seconds);
        address bidder = _randomAddress();
        uint256 bid = state.topBid - 1;
        vm.deal(bidder, bid);
        vm.prank(bidder);
        vm.expectRevert('bid too low');
        state = protocol.bid{ value: bid }(auctionId, state);
    }

    function test_cannotContinueBiddingTooLow() external {
        (uint256 auctionId, OffChainAuction.AuctionState memory state) =
            _createAuction(0.1 ether, 10 seconds);
        address firstBidder = _randomAddress();
        uint256 firstBid = state.topBid;
        vm.deal(firstBidder, firstBid);
        vm.prank(firstBidder);
        state = protocol.bid{ value: firstBid }(auctionId, state);
        address nextBidder = _randomAddress();
        uint256 nextBid = state.topBid;
        vm.deal(nextBidder, nextBid);
        vm.prank(nextBidder);
        vm.expectRevert('bid too low');
        state = protocol.bid{ value: nextBid }(auctionId, state);
    }

    function test_cannotBidIfExpired() external {
        (uint256 auctionId, OffChainAuction.AuctionState memory state) =
            _createAuction(0.1 ether, 10 seconds);
        address bidder = _randomAddress();
        uint256 bid = state.topBid;
        skip(state.duration);
        vm.deal(bidder, bid);
        vm.prank(bidder);
        vm.expectRevert('expired');
        state = protocol.bid{ value: bid }(auctionId, state);
    }

    function test_cannotBidIfConcluded() external {
        (uint256 auctionId, OffChainAuction.AuctionState memory state) =
            _createAuction(0.1 ether, 10 seconds);
        address bidder = _randomAddress();
        uint256 bid = state.topBid;
        vm.deal(bidder, bid);
        vm.prank(bidder);
        state = protocol.bid{ value: bid }(auctionId, state);
        skip(state.duration);
        bid = state.topBid + 1;
        vm.deal(bidder, bid);
        vm.prank(bidder);
        vm.expectRevert('concluded');
        state = protocol.bid{ value: bid }(auctionId, state);
    }

    function test_cannotBidWithBadState() external {
        (uint256 auctionId, OffChainAuction.AuctionState memory state) =
            _createAuction(0.1 ether, 10 seconds);
        address bidder = _randomAddress();
        uint256 bid = state.topBid;
        vm.deal(bidder, bid);
        vm.prank(bidder);
        vm.expectRevert('invalid auction');
        state.owner = _randomAddress();
        state = protocol.bid{ value: bid }(auctionId, state);
    }

    function test_cannotSettleBeforeExpiry() external {
        (uint256 auctionId, OffChainAuction.AuctionState memory state) =
            _createAuction(0.1 ether, 10 seconds);
        skip(state.duration - 1);
        address bidder = _randomAddress();
        uint256 bid = state.topBid;
        vm.deal(bidder, bid);
        vm.prank(bidder);
        state = protocol.bid{ value: bid }(auctionId, state);
        skip(state.duration - 1);
        vm.expectRevert('not concluded');
        protocol.settle(auctionId, state);
    }

    function test_cannotSettleBeforeConclusion() external {
        (uint256 auctionId, OffChainAuction.AuctionState memory state) =
            _createAuction(0.1 ether, 10 seconds);
        skip(state.duration - 1);
        vm.expectRevert('not expired');
        protocol.settle(auctionId, state);
    }

    function test_cannotSettleTwice() external {
        (uint256 auctionId, OffChainAuction.AuctionState memory state) =
            _createAuction(0.1 ether, 10 seconds);
        address bidder = _randomAddress();
        uint256 bid = state.topBid;
        vm.deal(bidder, bid);
        vm.prank(bidder);
        state = protocol.bid{ value: bid }(auctionId, state);
        skip(state.duration);
        protocol.settle(auctionId, state);
        vm.expectRevert('invalid auction');
        protocol.settle(auctionId, state);
    }

    function test_cannotSettleWithBadState() external {
        (uint256 auctionId, OffChainAuction.AuctionState memory state) =
            _createAuction(0.1 ether, 10 seconds);
        address bidder = _randomAddress();
        uint256 bid = state.topBid;
        vm.deal(bidder, bid);
        vm.prank(bidder);
        state = protocol.bid{ value: bid }(auctionId, state);
        skip(state.duration);
        state.owner = _randomAddress();
        vm.expectRevert('invalid auction');
        protocol.settle(auctionId, state);
    }

    function _createAuction(uint256 minBid, uint256 duration)
        private
        returns (uint256 auctionId, OffChainAuction.AuctionState memory state)
    {
        address owner = _randomAddress();
        uint256 tokenId = _randomUint256();
        token.mint(owner, tokenId);
        vm.prank(owner);
        token.approve(address(protocol), tokenId);
        vm.prank(owner);
        (auctionId, state) =
            protocol.createAuction(IERC721(address(token)), tokenId, minBid, duration);
    }
}

contract MintableERC721 is ERC721 {
    constructor() ERC721('TEST', 'TST') {}

    function mint(address owner, uint256 id) external {
        _mint(owner, id);
    }

    function tokenURI(uint256) public pure override returns (string memory) {}
}
