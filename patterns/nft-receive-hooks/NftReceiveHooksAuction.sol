// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

// A simple ERC721 auction house that uses the `onERC721Received()` hook
// to create auctions with a single transfer transaction.
contract NftReceiveHooksAuction {
    struct Auction {
        address payable seller;
        IERC721 token;
        uint256 tokenId;
        uint256 topBid;
        address payable topBidder;
        uint256 endTime;
    }

    event AuctionCreated(
        bytes32 id,
        address seller,
        IERC721 token,
        uint256 tokenId,
        uint256 reservePrice,
        uint256 endTime
    );
    event Bid(bytes32 auctionId, address bidder, uint256 amount);
    event Settled(bytes32 auctionId, address topBidder, uint256 topBid);

    mapping (bytes32 => Auction) public auctionsById;

    // The ERC721 receive hook, called by the token contract when
    // the token is transferred to us. Creates an auction with properly
    // encoded `data`.
    function onERC721Received(
        address /* operator */,
        address payable from,
        uint256 tokenId,
        bytes memory data
    )
        external
        returns (bytes4)
    {
        // The caller will always be the 
        // `data` should be encoded as
        // `abi.encode(uint256(reservePrice), uint256(duration))`.
        (uint256 reservePrice, uint256 duration) =
            abi.decode(data, (uint256, uint256));
        _createListing(from, IERC721(msg.sender), tokenId, reservePrice, duration);
        return this.onERC721Received.selector;
    }

    // Bid on an auction.
    function bid(bytes32 auctionId) external payable {
        Auction storage auction = auctionsById[auctionId];
        {
            // Make sure the auction is not expired. This will
            // also enforce that the auction exists. 
            uint256 endTime = auction.endTime;
            require(endTime > block.timestamp, 'auction over');
        }
        address payable topBidder = auction.topBidder;
        uint256 topBid = auction.topBid;
        require(address(topBidder) != msg.sender, 'already top bidder');
        require(topBid < msg.value, 'bid too low');
        auction.topBid = msg.value;
        auction.topBidder = payable(msg.sender);
        // Transfer the last top bid to the last top bidder.
        _pay(topBidder, topBid);
        emit Bid(auctionId, msg.sender, msg.value);
    }

    // Settle an expired or won auction.
    function settle(bytes32 auctionId) external {
        Auction memory auction = auctionsById[auctionId];
        // Auction must exist and be over.
        require(auction.seller != address(0), 'invalid auction');
        require(auction.endTime <= block.timestamp, 'not over');
        // Clear the auction.
        delete auctionsById[auctionId];
        if (auction.topBidder == address(0)) {
            // No one bid. Return NFT to seller.
            _sendNft(auction.seller, auction.token, auction.tokenId);
        } else { // We have a winner.
            // Pay the seller.
            _pay(auction.seller, auction.topBid);
            // Transfer the NFT to the top bidder.
            _sendNft(auction.topBidder, auction.token, auction.tokenId);
        }
        emit Settled(
            auctionId,
            auction.topBidder,
            auction.topBidder == address(0) ? 0 : auction.topBid
        );
    }

    function _createListing(
        address payable owner,
        IERC721 token,
        uint256 tokenId,
        uint256 reservePrice,
        uint256 duration
    )
        private
    {
        require(reservePrice > 0, 'invalid reserve price');
        require(duration > 0, 'invalid duration');
        bytes32 id = keccak256(abi.encode(token, tokenId));
        uint256 endTime = duration + block.timestamp;
        auctionsById[id] = Auction({
            seller: owner,
            token: token,
            tokenId: tokenId,
            topBid: reservePrice - 1,
            topBidder: payable(0),
            endTime: endTime
        });
        emit AuctionCreated(
            id,
            owner,
            token,
            tokenId,
            reservePrice,
            endTime
        );
    }

    function _pay(address payable to, uint256 amount) private {
        // TODO: Properly handle failure and wrap to WETH or defer to
        // a withdraw() function if so.
        !!to.send(amount);
    }
    
    function _sendNft(address to, IERC721 token, uint256 tokenId) private {
        // TODO: Use `safeTransferFrom()` instead and handle failure,
        // possibly deferring to a withdrawNft() function if so.
        token.transferFrom(address(this), to, tokenId);
    }
}

// Minimal ERC721 interface.
interface IERC721 {
    function safeTransferFrom(address owner, address to, uint256 tokenId, bytes memory data) external;
    function transferFrom(address owner, address to, uint256 tokenId) external;
}