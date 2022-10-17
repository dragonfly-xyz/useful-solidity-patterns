// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "../patterns/commit-reveal/SealedAuctionMint.sol";
import "./TestUtils.sol";

contract SealedAuctionMintTest is TestUtils {
    SealedAuctionMint proto = new SealedAuctionMint();

    function test_canBid() external {
        uint256 auctionId = proto.getCurrentAuctionId();
        uint256 bidAmount = _getRandomBidAmount();
        (address bidder, uint256 maskAmount, , bytes32 commitHash) =
            _placeBid(auctionId, bidAmount);
        (uint256 bidEthAttached, bytes32 bidCommitHash) =
            proto.bidsByAuction(auctionId, bidder);
        assertEq(bidEthAttached, maskAmount);
        assertEq(bidCommitHash, commitHash);
    }

    function test_cannotBidWithZeroCommitHash() external {
        uint256 auctionId = proto.getCurrentAuctionId();
        uint256 bidAmount = _getRandomBidAmount();
        uint256 maskAmount = bidAmount * 10;
        address bidder = _randomAddress();
        vm.deal(bidder, maskAmount);
        vm.prank(bidder);
        vm.expectRevert('invalid commit hash');
        proto.bid{value: maskAmount}(auctionId, 0);
    }

    function test_cannotBidOnFutureAuction() external {
        uint256 auctionId = proto.getCurrentAuctionId();
        vm.expectRevert('auction not accepting bids');
        _placeBid(auctionId + 1, _getRandomBidAmount());
    }

    function test_cannotBidWithZeroValue() external {
        uint256 auctionId = proto.getCurrentAuctionId();
        vm.expectRevert('invalid bid');
        _placeBid(auctionId, 0);
    }

    function test_cannotBidPastCommitPhase() external {
        uint256 auctionId = proto.getCurrentAuctionId();
        uint256 bidAmount = _getRandomBidAmount();
        skip(proto.AUCTION_COMMIT_DURATION());
        vm.expectRevert('auction not accepting bids');
        _placeBid(auctionId, bidAmount);
    }

    function test_cannotBidPastRevealPhase() external {
        uint256 auctionId = proto.getCurrentAuctionId();
        uint256 bidAmount = _getRandomBidAmount();
        skip(proto.AUCTION_TOTAL_DURATION());
        vm.expectRevert('auction not accepting bids');
        _placeBid(auctionId, bidAmount);
    }

    function test_canRevealAndWin() external {
        uint256 bidAmount = _getRandomBidAmount();
        uint256 auctionId = proto.getCurrentAuctionId();
        (address bidder, , bytes32 salt, ) =
            _placeBid(auctionId, bidAmount);
        skip(proto.AUCTION_COMMIT_DURATION());
        vm.prank(bidder);
        proto.reveal(auctionId, bidAmount, salt);
        assertEq(proto.winningBidderByAuction(auctionId), bidder);
        assertEq(proto.winningBidAmountByAuction(auctionId), bidAmount);
    }

    function test_revealCapsBidAmountToEthAttached() external {
        uint256 bidAmount = _getRandomBidAmount() + 1;
        uint256 auctionId = proto.getCurrentAuctionId();
        uint256 maskAmount = bidAmount - 1;
        bytes32 salt = _randomBytes32();
        address bidder = _randomAddress();
        bytes32 commitHash = _getCommitHash(bidAmount, salt);
        vm.deal(bidder, maskAmount);
        vm.prank(bidder);
        proto.bid{value: maskAmount}(auctionId, commitHash);
        skip(proto.AUCTION_COMMIT_DURATION());
        vm.prank(bidder);
        proto.reveal(auctionId, bidAmount, salt);
        assertEq(proto.winningBidderByAuction(auctionId), bidder);
        assertEq(proto.winningBidAmountByAuction(auctionId), maskAmount);
    }

    function test_canRevealAndLose() external {
        uint256 auctionId = proto.getCurrentAuctionId();
        uint256 winnerBidAmount = _getRandomBidAmount();
        uint256 loserBidAmount = winnerBidAmount - 1;
        (address winner, , bytes32 winnerSalt, ) =
            _placeBid(auctionId, winnerBidAmount);
        (address loser, , bytes32 loserSalt, ) =
            _placeBid(auctionId, loserBidAmount);
        skip(proto.AUCTION_COMMIT_DURATION());
        vm.prank(winner);
        proto.reveal(auctionId, winnerBidAmount, winnerSalt);
        vm.prank(loser);
        proto.reveal(auctionId, loserBidAmount, loserSalt);
        assertEq(proto.winningBidderByAuction(auctionId), winner);
        assertEq(proto.winningBidAmountByAuction(auctionId), winnerBidAmount);
    }

    function test_canRevealWinThenLose() external {
        uint256 auctionId = proto.getCurrentAuctionId();
        uint256 winnerBidAmount = _getRandomBidAmount();
        uint256 loserBidAmount = winnerBidAmount - 1;
        (address winner, , bytes32 winnerSalt, ) =
            _placeBid(auctionId, winnerBidAmount);
        (address loser, , bytes32 loserSalt, ) =
            _placeBid(auctionId, loserBidAmount);
        skip(proto.AUCTION_COMMIT_DURATION());
        vm.prank(loser);
        proto.reveal(auctionId, loserBidAmount, loserSalt);
        assertEq(proto.winningBidderByAuction(auctionId), loser);
        assertEq(proto.winningBidAmountByAuction(auctionId), loserBidAmount);
        vm.prank(winner);
        proto.reveal(auctionId, winnerBidAmount, winnerSalt);
        assertEq(proto.winningBidderByAuction(auctionId), winner);
        assertEq(proto.winningBidAmountByAuction(auctionId), winnerBidAmount);
    }

    function test_cannotRevealWithBadBidAmount() external {
        uint256 bidAmount = _getRandomBidAmount();
        uint256 auctionId = proto.getCurrentAuctionId();
        (address bidder, , bytes32 salt, ) =
            _placeBid(auctionId, bidAmount);
        skip(proto.AUCTION_COMMIT_DURATION());
        vm.prank(bidder);
        vm.expectRevert('invalid reveal');
        proto.reveal(auctionId, bidAmount + 1, salt);
    }

    function test_cannotRevealWithBadSalt() external {
        uint256 bidAmount = _getRandomBidAmount();
        uint256 auctionId = proto.getCurrentAuctionId();
        (address bidder, , , ) =
            _placeBid(auctionId, bidAmount);
        skip(proto.AUCTION_COMMIT_DURATION());
        vm.prank(bidder);
        vm.expectRevert('invalid reveal');
        proto.reveal(auctionId, bidAmount, _randomBytes32());
    }

    function test_cannotRevealWhenAuctionOver() external {
        uint256 bidAmount = _getRandomBidAmount();
        uint256 auctionId = proto.getCurrentAuctionId();
        (address bidder, , bytes32 salt, ) =
            _placeBid(auctionId, bidAmount);
        skip(proto.AUCTION_TOTAL_DURATION());
        vm.prank(bidder);
        vm.expectRevert('auction over');
        proto.reveal(auctionId, bidAmount, salt);
    }

    function test_canReclaimDuringRevealPhase() external {
        uint256 bidAmount = _getRandomBidAmount();
        uint256 auctionId = proto.getCurrentAuctionId();
        (address bidder, uint256 maskAmount, , ) =
            _placeBid(auctionId, bidAmount);
        skip(proto.AUCTION_COMMIT_DURATION());
        vm.prank(bidder);
        proto.reclaim(auctionId);
        assertEq(bidder.balance, maskAmount);
    }

    function test_loserCanReclaim() external {
        uint256 auctionId = proto.getCurrentAuctionId();
        uint256 winnerBidAmount = _getRandomBidAmount();
        uint256 loserBidAmount = winnerBidAmount - 1;
        (address winner, , bytes32 winnerSalt, ) =
            _placeBid(auctionId, winnerBidAmount);
        (address loser, uint256 loserMaskAmount, bytes32 loserSalt, ) =
            _placeBid(auctionId, loserBidAmount);
        skip(proto.AUCTION_COMMIT_DURATION());
        vm.prank(loser);
        proto.reveal(auctionId, loserBidAmount, loserSalt);
        vm.prank(winner);
        proto.reveal(auctionId, winnerBidAmount, winnerSalt);
        vm.prank(loser);
        proto.reclaim(auctionId);
        assertEq(loser.balance, loserMaskAmount);
    }

    function test_winnerCannotReclaim() external {
        uint256 auctionId = proto.getCurrentAuctionId();
        uint256 winnerBidAmount = _getRandomBidAmount();
        uint256 loserBidAmount = winnerBidAmount - 1;
        (address winner, , bytes32 winnerSalt, ) =
            _placeBid(auctionId, winnerBidAmount);
        (address loser, , bytes32 loserSalt, ) =
            _placeBid(auctionId, loserBidAmount);
        skip(proto.AUCTION_COMMIT_DURATION());
        vm.prank(loser);
        proto.reveal(auctionId, loserBidAmount, loserSalt);
        vm.prank(winner);
        proto.reveal(auctionId, winnerBidAmount, winnerSalt);
        vm.expectRevert('winner cannot reclaim');
        vm.prank(winner);
        proto.reclaim(auctionId);
    }

    function test_canReclaimAfterAuctionConcludes() external {
        uint256 bidAmount = _getRandomBidAmount();
        uint256 auctionId = proto.getCurrentAuctionId();
        (address bidder, uint256 maskAmount, , ) =
            _placeBid(auctionId, bidAmount);
        skip(proto.AUCTION_TOTAL_DURATION());
        vm.prank(bidder);
        proto.reclaim(auctionId);
        assertEq(bidder.balance, maskAmount);
    }

    function test_cannotReclaimTwice() external {
        uint256 bidAmount = _getRandomBidAmount();
        uint256 auctionId = proto.getCurrentAuctionId();
        (address bidder, , , ) =
            _placeBid(auctionId, bidAmount);
        skip(proto.AUCTION_COMMIT_DURATION());
        vm.prank(bidder);
        proto.reclaim(auctionId);
        vm.expectRevert('already reclaimed');
        vm.prank(bidder);
        proto.reclaim(auctionId);
    }

    function test_cannotReclaimWithoutBid() external {
        uint256 auctionId = proto.getCurrentAuctionId();
        address bidder = _randomAddress();
        skip(proto.AUCTION_COMMIT_DURATION());
        vm.expectRevert('already reclaimed');
        vm.prank(bidder);
        proto.reclaim(auctionId);
    }

    function test_winnerCanMintAfterAuctionConcludes() external {
        uint256 bidAmount = _getRandomBidAmount();
        uint256 auctionId = proto.getCurrentAuctionId();
        (address bidder, uint256 maskAmount, bytes32 salt, ) =
            _placeBid(auctionId, bidAmount);
        skip(proto.AUCTION_COMMIT_DURATION());
        vm.prank(bidder);
        proto.reveal(auctionId, bidAmount, salt);
        skip(proto.AUCTION_REVEAL_DURATION());
        vm.prank(bidder);
        proto.mint(auctionId);
        assertEq(bidder.balance, maskAmount - bidAmount);
        assertEq(proto.ownerOf(proto.lastTokenId()), bidder);
    }

    function test_winnerCannotMintTwice() external {
        uint256 bidAmount = _getRandomBidAmount();
        uint256 auctionId = proto.getCurrentAuctionId();
        (address bidder, , bytes32 salt, ) =
            _placeBid(auctionId, bidAmount);
        skip(proto.AUCTION_COMMIT_DURATION());
        vm.prank(bidder);
        proto.reveal(auctionId, bidAmount, salt);
        skip(proto.AUCTION_REVEAL_DURATION());
        vm.prank(bidder);
        proto.mint(auctionId);
        vm.expectRevert('already minted');
        vm.prank(bidder);
        proto.mint(auctionId);
    }

    function test_winnerCannotMintThenReclaim() external {
        uint256 bidAmount = _getRandomBidAmount();
        uint256 auctionId = proto.getCurrentAuctionId();
        (address bidder, , bytes32 salt, ) =
            _placeBid(auctionId, bidAmount);
        skip(proto.AUCTION_COMMIT_DURATION());
        vm.prank(bidder);
        proto.reveal(auctionId, bidAmount, salt);
        skip(proto.AUCTION_REVEAL_DURATION());
        vm.prank(bidder);
        proto.mint(auctionId);
        vm.expectRevert('winner cannot reclaim');
        vm.prank(bidder);
        proto.reclaim(auctionId);
    }

    function test_loserCannotMint() external {
        uint256 auctionId = proto.getCurrentAuctionId();
        uint256 winnerBidAmount = _getRandomBidAmount();
        uint256 loserBidAmount = winnerBidAmount - 1;
        (address winner, , bytes32 winnerSalt, ) =
            _placeBid(auctionId, winnerBidAmount);
        (address loser, , bytes32 loserSalt, ) =
            _placeBid(auctionId, loserBidAmount);
        skip(proto.AUCTION_COMMIT_DURATION());
        vm.prank(loser);
        proto.reveal(auctionId, loserBidAmount, loserSalt);
        vm.prank(winner);
        proto.reveal(auctionId, winnerBidAmount, winnerSalt);
        skip(proto.AUCTION_REVEAL_DURATION());
        vm.expectRevert('not the winner');
        vm.prank(loser);
        proto.mint(auctionId);
    }

    function test_canBidOnNewAuction() external {
        uint256 auctionId = proto.getCurrentAuctionId();
        uint256 bidAmount = _getRandomBidAmount();
        _placeBid(auctionId, bidAmount);
        skip(proto.AUCTION_COMMIT_DURATION());
        assertEq(proto.getCurrentAuctionId(), auctionId + 1);
        (address bidder, uint256 maskAmount, , bytes32 commitHash) =
            _placeBid(auctionId + 1, bidAmount);
        (uint256 bidEthAttached, bytes32 bidCommitHash) =
            proto.bidsByAuction(auctionId + 1, bidder);
        assertEq(bidEthAttached, maskAmount);
        assertEq(bidCommitHash, commitHash);
    }

    function _placeBid(uint256 auctionId, uint256 bidAmount)
        private
        returns (address bidder, uint256 maskAmount, bytes32 salt, bytes32 commitHash)
    {
        maskAmount = bidAmount * 10;
        salt = _randomBytes32();
        bidder = _randomAddress();
        commitHash = _getCommitHash(bidAmount, salt);
        vm.deal(bidder, maskAmount);
        vm.prank(bidder);
        proto.bid{value: maskAmount}(auctionId, commitHash);
    }

    function _getRandomBidAmount() private view returns (uint256) {
        return _randomUint256() % 1 ether + 1;
    }

    function _getCommitHash(uint256 bidAmount, bytes32 salt)
        private
        pure
        returns (bytes32)
    {
        return keccak256(abi.encode(bidAmount, salt));
    }
}