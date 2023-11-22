// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

// An "NFT" contract that holds a sealed bid auction every 24 hours for the right
// to mint a token. The auction is a sealed auction using commit reveal to hide
// bid amounts.
contract SealedAuctionMint {
    struct SealedBid {
        uint256 ethAttached;
        bytes32 commitHash;
    }

    uint256 public constant AUCTION_COMMIT_DURATION = 1 days;
    uint256 public constant AUCTION_REVEAL_DURATION = 1 days;
    uint256 public constant AUCTION_TOTAL_DURATION =
        AUCTION_COMMIT_DURATION + AUCTION_REVEAL_DURATION;

    uint256 public immutable launchTime;
    uint256 public lastTokenId;
    mapping (uint256 => mapping (address => SealedBid))  public bidsByAuction;
    mapping (uint256 => address) public winningBidderByAuction;
    mapping (uint256 => uint256) public winningBidAmountByAuction;
    mapping (uint256 => address) public ownerOf;

    constructor() {
        launchTime = block.timestamp;
    }

    // Place a sealed bid on the current auction.
    // This can only be called during the bidding/commit phase of an auction.
    // The amount of ETH attached should exceed the true bid by orders of magnitude to
    // adequately mask the true bid.
    // `commitHash` is `keccak256(bidAmount, salt)`, where `bidAmount` and `salt`
    // are only known to the bidder.
    function bid(uint256 auctionId, bytes32 commitHash) external payable {
        require(auctionId == getCurrentAuctionId(), 'auction not accepting bids');
        require(commitHash != 0, 'invalid commit hash');
        require(bidsByAuction[auctionId][msg.sender].commitHash == 0, 'already bid');
        require(msg.value != 0, 'invalid bid');
        bidsByAuction[auctionId][msg.sender] = SealedBid({
            ethAttached: msg.value,
            commitHash: commitHash
        });
    }

    // Reveal a previously placed sealed bid.
    // This can only be called during the reveal phase of an auction.
    function reveal(uint256 auctionId, uint256 bidAmount, bytes32 salt) external {
        require(auctionId < getCurrentAuctionId(), 'bidding still ongoing');
        require(!isAuctionOver(auctionId), 'auction over');
        SealedBid memory bid_ = bidsByAuction[auctionId][msg.sender];
        // Ensure the prior commitHash matches the hash of the bid and salt.
        require(bid_.commitHash == keccak256(abi.encode(bidAmount, salt)), 'invalid reveal');
        uint256 cappedBidAmount = bidAmount > bid_.ethAttached
            ? bid_.ethAttached : bidAmount;
        // If caller's bid is > the winning bid amount, they're the new winner.
        uint256 winningBidAmount = winningBidAmountByAuction[auctionId];
        if (cappedBidAmount > winningBidAmount) {
            // Caller is the new winning bidder.
            winningBidderByAuction[auctionId] = msg.sender;
            winningBidAmountByAuction[auctionId] = cappedBidAmount;
        }
    }

    // Refund ETH attached to a losing (or unrevealed) bid.
    // This can only be called after the bidding/commit phase of an auction has ended.
    function reclaim(uint256 auctionId) external {
        require(auctionId < getCurrentAuctionId(), 'bidding still ongoing');
        address winningBidder = winningBidderByAuction[auctionId];
        require(winningBidder != msg.sender, 'winner cannot reclaim');
        SealedBid storage bid_ = bidsByAuction[auctionId][msg.sender];
        uint256 refund = bid_.ethAttached;
        require(refund != 0, 'already reclaimed');
        // Set ethAttached to 0 to prevent double redeeming.
        bid_.ethAttached = 0;
        payable(msg.sender).transfer(refund);
    }

    // Mint a new token to the caller.
    // Must be called by the auction winner, and only after the reveal phase
    // has expired (the auction has fully concluded).
    function mint(uint256 auctionId) external {
        require(isAuctionOver(auctionId), 'auction not over');
        address winningBidder = winningBidderByAuction[auctionId];
        require(winningBidder == msg.sender, 'not the winner');
        SealedBid storage bid_ = bidsByAuction[auctionId][msg.sender];
        uint256 ethAttached = bid_.ethAttached;
        require(ethAttached != 0, 'already minted');
        // Set ethAttached to 0 to prevent further minting.
        bid_.ethAttached = 0;
        _mintTo(msg.sender);
        // Refund any excess ETH attached to the bid.
        uint256 refund = ethAttached - winningBidAmountByAuction[auctionId];
        payable(msg.sender).transfer(refund);
    }

    function getCurrentAuctionId() public view returns (uint256 auctionId) {
        return (block.timestamp - launchTime) / AUCTION_COMMIT_DURATION + 1;
    }

    function getAuctionStartTime(uint256 auctionId) public view returns (uint256 startTime) {
        return ((auctionId - 1) * AUCTION_COMMIT_DURATION) + launchTime;
    }

    function isAuctionOver(uint256 auctionId) public view returns (bool) {
        return getAuctionStartTime(auctionId) + AUCTION_TOTAL_DURATION <= block.timestamp;
    }

    function _mintTo(address owner) private {
        ownerOf[++lastTokenId] = owner;
    }
}
