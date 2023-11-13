// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.23;

import "../patterns/eip712-signed-messages/MintVouchers.sol";
import "./TestUtils.sol";

contract TestableMintVouchersERC721 is MintVouchersERC721 {
    function getVoucherHash(uint256 tokenId, uint256 price) external view returns (bytes32) {
        return _getVoucherHash(tokenId, price);
    }
}

contract MintVouchersTest is TestUtils {
    event Transfer(address indexed from, address indexed to, uint256 indexed tokenId);

    uint256 ownerPrivateKey;
    address payable owner;
    address payable minter;
    TestableMintVouchersERC721 nftContract;

    function setUp() external {
        ownerPrivateKey = _randomUint256();
        minter = _randomAddress();
        owner = payable(vm.addr(ownerPrivateKey));
        vm.prank(owner);
        nftContract = new TestableMintVouchersERC721();
        vm.deal(minter, 1e18);
    }

    function test_cannotMintWithWrongPrice() external {
        uint256 tokenId = _randomUint256();
        uint256 price = _randomUint256() % 100;
        (uint8 v, bytes32 r, bytes32 s) = _signVoucher(tokenId, price);
        vm.expectRevert('invalid signature');
        vm.prank(minter);
        nftContract.mint{value: price + 1}(tokenId, v, r, s);
    }

    function test_cannotMintWithWrongTokenId() external {
        uint256 tokenId = _randomUint256();
        uint256 price = _randomUint256() % 100;
        (uint8 v, bytes32 r, bytes32 s) = _signVoucher(tokenId, price);
        vm.expectRevert('invalid signature');
        vm.prank(minter);
        nftContract.mint{value: price}(tokenId + 1, v, r, s);
    }

    function test_canMint() external {
        uint256 tokenId = _randomUint256();
        uint256 price = _randomUint256() % 100;
        (uint8 v, bytes32 r, bytes32 s) = _signVoucher(tokenId, price);
        vm.expectEmit(true, true, true, false);
        emit Transfer(address(0), minter, tokenId);
        vm.prank(minter);
        nftContract.mint{value: price}(tokenId, v, r, s);
        assertEq(owner.balance, price);
    }

    function test_cannotMintTwice() external {
        uint256 tokenId = _randomUint256();
        uint256 price = _randomUint256() % 100;
        (uint8 v, bytes32 r, bytes32 s) = _signVoucher(tokenId, price);
        vm.prank(minter);
        nftContract.mint{value: price}(tokenId, v, r, s);
        vm.expectRevert('already minted');
        vm.prank(minter);
        nftContract.mint{value: price}(tokenId, v, r, s);
    }

    function test_canCancel() external {
        uint256 tokenId = _randomUint256();
        uint256 price = _randomUint256() % 100;
        (uint8 v, bytes32 r, bytes32 s) = _signVoucher(tokenId, price);
        vm.prank(owner);
        nftContract.cancel(tokenId, price);
        vm.expectRevert('mint voucher has been cancelled');
        vm.prank(minter);
        nftContract.mint{value: price}(tokenId, v, r, s);
    }

    function _signVoucher(uint256 tokenId, uint256 price)
        private
        returns (uint8 v, bytes32 r, bytes32 s)
    {
        return vm.sign(ownerPrivateKey, nftContract.getVoucherHash(tokenId, price));
    }

}
