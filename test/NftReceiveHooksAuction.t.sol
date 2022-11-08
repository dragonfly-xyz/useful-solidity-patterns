// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "solmate/tokens/ERC721.sol";
import "../patterns/nft-receive-hooks/NftReceiveHooksAuction.sol";
import "./TestUtils.sol";

contract NftReceiveHooksAuctionTest is TestUtils {
    NftReceiveHooksAuction ah = new NftReceiveHooksAuction();
    TestERC721 token = new TestERC721();

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

    function test_canCreateAuction() external {
        address seller = _randomAddress();
        uint256 tokenId = token.mint(seller);
        uint256 reservePrice = 1;
        uint256 duration = 1 days;
        bytes32 auctionId = _getAuctionId(tokenId);
        vm.expectEmit(false, false, false, true);
        emit AuctionCreated(
            auctionId,
            seller,
            IERC721(address(token)),
            tokenId,
            reservePrice,
            block.timestamp + duration
        );
        vm.prank(seller);
        token.safeTransferFrom(
            seller,
            address(ah),
            tokenId,
            abi.encode(reservePrice, duration)
        );
        assertEq(token.ownerOf(tokenId), address(ah));
    }

    function test_cannotCreateAuctionWithBadReservePrice() external {
        address seller = _randomAddress();
        uint256 tokenId = token.mint(seller);
        uint256 reservePrice = 0;
        uint256 duration = 1 days;
        vm.expectRevert('invalid reserve price');
        vm.prank(seller);
        token.safeTransferFrom(
            seller,
            address(ah),
            tokenId,
            abi.encode(reservePrice, duration)
        );
    }

    function test_cannotCreateAuctionWithBadDuration() external {
        address seller = _randomAddress();
        uint256 tokenId = token.mint(seller);
        uint256 reservePrice = 1;
        uint256 duration = 0;
        vm.expectRevert('invalid duration');
        vm.prank(seller);
        token.safeTransferFrom(
            seller,
            address(ah),
            tokenId,
            abi.encode(reservePrice, duration)
        );
    }

    function test_canBidOnAuction() external {
        address seller = _randomAddress();
        uint256 tokenId = token.mint(seller);
        uint256 reservePrice = 1;
        uint256 duration = 1 days;
        bytes32 auctionId = _getAuctionId(tokenId);
        vm.prank(seller);
        token.safeTransferFrom(
            seller,
            address(ah),
            tokenId,
            abi.encode(reservePrice, duration)
        );
        address bidder1 = _randomAddress();
        vm.deal(bidder1, 1);
        vm.prank(bidder1);
        vm.expectEmit(false, false, false, true);
        emit Bid(auctionId, bidder1, 1);
        ah.bid{ value: 1 }(auctionId);
        address bidder2 = _randomAddress();
        vm.deal(bidder2, 2);
        vm.prank(bidder2);
        vm.expectEmit(false, false, false, true);
        emit Bid(auctionId, bidder2, 2);
        ah.bid{ value: 2 }(auctionId);
        assertEq(bidder1.balance, 1);
    }

    function test_cannotBidTooLow() external {
        address seller = _randomAddress();
        uint256 tokenId = token.mint(seller);
        uint256 reservePrice = 2;
        uint256 duration = 1 days;
        bytes32 auctionId = _getAuctionId(tokenId);
        vm.prank(seller);
        token.safeTransferFrom(
            seller,
            address(ah),
            tokenId,
            abi.encode(reservePrice, duration)
        );
        address bidder1 = _randomAddress();
        vm.deal(bidder1, 1);
        vm.expectRevert('bid too low');
        vm.prank(bidder1);
        ah.bid{ value:1  }(auctionId);
    }

    function test_cannotBidOnInvalidAuction() external {
        address bidder1 = _randomAddress();
        vm.deal(bidder1, 1);
        vm.expectRevert('auction over');
        vm.prank(bidder1);
        ah.bid{ value:1  }(_randomBytes32());
    }

    function test_canSettleWon() external {
        address seller = _randomAddress();
        uint256 tokenId = token.mint(seller);
        uint256 reservePrice = 1;
        uint256 duration = 1 days;
        bytes32 auctionId = _getAuctionId(tokenId);
        vm.prank(seller);
        token.safeTransferFrom(
            seller,
            address(ah),
            tokenId,
            abi.encode(reservePrice, duration)
        );
        address bidder1 = _randomAddress();
        vm.deal(bidder1, 1);
        vm.prank(bidder1);
        ah.bid{ value: 1 }(auctionId);
        skip(duration);
        vm.expectEmit(false, false, false, true);
        emit Settled(auctionId, bidder1, 1);
        ah.settle(auctionId);
        assertEq(bidder1.balance, 0);
        assertEq(seller.balance, 1);
        assertEq(token.ownerOf(tokenId), bidder1);
    }

    function test_canSettleLost() external {
        address seller = _randomAddress();
        uint256 tokenId = token.mint(seller);
        uint256 reservePrice = 1;
        uint256 duration = 1 days;
        bytes32 auctionId = _getAuctionId(tokenId);
        vm.prank(seller);
        token.safeTransferFrom(
            seller,
            address(ah),
            tokenId,
            abi.encode(reservePrice, duration)
        );
        skip(duration);
        vm.expectEmit(false, false, false, true);
        emit Settled(auctionId, address(0), 0);
        ah.settle(auctionId);
        assertEq(token.ownerOf(tokenId), seller);
    }

    function test_cannotSettleTwice() external {
        address seller = _randomAddress();
        uint256 tokenId = token.mint(seller);
        uint256 reservePrice = 1;
        uint256 duration = 1 days;
        bytes32 auctionId = _getAuctionId(tokenId);
        vm.prank(seller);
        token.safeTransferFrom(
            seller,
            address(ah),
            tokenId,
            abi.encode(reservePrice, duration)
        );
        skip(duration);
        ah.settle(auctionId);
        vm.expectRevert('invalid auction');
        ah.settle(auctionId);
    }

    function test_cannotSettleEarly() external {
        address seller = _randomAddress();
        uint256 tokenId = token.mint(seller);
        uint256 reservePrice = 1;
        uint256 duration = 1 days;
        bytes32 auctionId = _getAuctionId(tokenId);
        vm.prank(seller);
        token.safeTransferFrom(
            seller,
            address(ah),
            tokenId,
            abi.encode(reservePrice, duration)
        );
        skip(duration - 1);
        vm.expectRevert('not over');
        ah.settle(auctionId);
    }

    function test_cannotBidAfterSettle() external {
        address seller = _randomAddress();
        uint256 tokenId = token.mint(seller);
        uint256 reservePrice = 1;
        uint256 duration = 1 days;
        bytes32 auctionId = _getAuctionId(tokenId);
        vm.prank(seller);
        token.safeTransferFrom(
            seller,
            address(ah),
            tokenId,
            abi.encode(reservePrice, duration)
        );
        skip(duration);
        ah.settle(auctionId);
        address bidder1 = _randomAddress();
        vm.deal(bidder1, 1);
        vm.prank(bidder1);
        vm.expectRevert('auction over');
        ah.bid{ value: 1 }(auctionId);
    }

    function _getAuctionId(uint256 tokenId) private view returns (bytes32) {
        return keccak256(abi.encode(token, tokenId));
    }
}

contract TestERC721 is ERC721 {
    uint256 lastTokenId;

    constructor() ERC721('Dummy', 'DUM') {}
    function tokenURI(uint256 tokenId) public override pure returns (string memory r) {}
    function mint(address owner) external returns (uint256 tokenId) {
        tokenId = ++lastTokenId;
        _mint(owner, tokenId);
    }
}
