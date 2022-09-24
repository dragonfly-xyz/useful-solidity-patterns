// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

// Creates auctions for an ERC721 NFT with off-chain storage for auction state.
contract OffChainAuction {
    // Per-auction state that will be kept off-chain.
    struct AuctionState {
        // ERC721 token contract of the NFT being auctioned.
        IERC721 token;
        // ERC721 token ID of the NFT being auctioned.
        uint256 tokenId;
        // Who created the auction.
        address payable owner;
        // When the auction was created.
        uint256 created;
        // When the first bid was placed.
        uint256 started;
        // How long the auction has before it expires (no bids) and how long
        // to extend it once someone places the first bid.
        uint256 duration;
        // The current top bid. Also the minimum bid if topBidder is 0.
        uint256 topBid;
        // The current top bidder. 0 if no bidders.
        address payable topBidder;
    }

    event Created(uint256 auctionId, AuctionState state);
    event Bid(uint256 auctionId, AuctionState newState);
    event Settled(uint256 auctionId, uint256 topBid);
    event Expired(uint256 auctionId);

    // Maps an auction ID to its current state hash (hash of AuctionState).
    mapping (uint256 => bytes32) public auctionStateHashes;
    uint256 _lastAuctionId;

    // Requires the auction state to match an auction identified by `auctionId`.
    modifier onlyValidAuction(uint256 auctionId, AuctionState memory state) {
        require(auctionStateHashes[auctionId] == _hashAuctionState(state), 'invalid auction');
        _;
    }

    // Create a new auction.
    function createAuction(IERC721 token, uint256 tokenId, uint256 minBid, uint256 duration)
        external
        returns (uint256 auctionId, AuctionState memory state)
    {
        require(minBid != 0, 'invalid minimum bid');
        // Take custody of the NFT.
        token.transferFrom(msg.sender, address(this), tokenId);
        // Create the initial state for this auction.
        state.token = token;
        state.tokenId = tokenId;
        state.owner = payable(msg.sender);
        state.created = block.timestamp;
        state.topBid = minBid;
        state.duration = duration;
        auctionId = _lastAuctionId++;
        // Store ONLY the hash of the initial state for this auction on-chain.
        auctionStateHashes[auctionId] = _hashAuctionState(state);
        emit Created(auctionId, state);
    }

    // Place a bid on an active auction.
    function bid(uint256 auctionId, AuctionState memory state)
        external
        payable
        onlyValidAuction(auctionId, state)
        returns (AuctionState memory)
    {
        if (state.started == 0) {
            require(state.created + state.duration > block.timestamp, 'expired');
        } else {
            require(state.started + state.duration > block.timestamp, 'concluded');
        }
        uint256 currTopBid = state.topBid;
        address payable currTopBidder = state.topBidder;
        if (currTopBidder == address(0)) {
            // Auction hasn't started yet (no bids).
            require(msg.value >= currTopBid, 'bid too low');
            state.started = block.timestamp;
        } else {
            // Auction is in progress.
            require(msg.value > currTopBid, 'bid too low');
        }
        state.topBid = msg.value;
        state.topBidder = payable(msg.sender);
        // Update the on-chain state hash to reflect the new state values.
        auctionStateHashes[auctionId] = _hashAuctionState(state);
        // If there was a previous bidder, refund them their bid.
        if (currTopBidder != address(0)) {
            !!currTopBidder.send(currTopBid);
        }
        // Emit and return the updated state for future interactions.
        emit Bid(auctionId, state);
        return state;
    }

    // Settle an auction that is either expired or concluded.
    function settle(uint256 auctionId, AuctionState calldata state)
        external
        onlyValidAuction(auctionId, state)
    {
        // Clear state hash to prevent reentrancy.
        delete auctionStateHashes[auctionId];
        if (state.started != 0) {
            // Auction completed.
            require(state.started + state.duration <= block.timestamp, 'not concluded');
            // Send top bid to auction creator.
            !!state.owner.send(state.topBid);
            // Send NFT to auction top bidder.
            state.token.transferFrom(address(this), state.topBidder, state.tokenId);
            emit Settled(auctionId, state.topBid);
            return;
        }
        // Auction expired (no bids).
        require(state.created + state.duration <= block.timestamp, 'not expired');
        // Return NFT to auction creator.
        state.token.transferFrom(address(this), state.owner, state.tokenId);
        emit Expired(auctionId);
    }

    // Compute the hash of an auction state object.
    function _hashAuctionState(AuctionState memory state)
        private
        pure
        returns (bytes32 hash)
    {
        return keccak256(abi.encode(state));
    }
}

// Minimal ERC721 interface.
interface IERC721 {
    function transferFrom(address owner, address to, uint256 tokenId) external;
}
