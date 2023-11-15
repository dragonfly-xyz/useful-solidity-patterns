// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "../patterns/big-data-storage/OnChainPfp.sol";
import "./TestUtils.sol";

contract OnChainPfpTest is TestUtils {
    OnChainPfp pfp = new OnChainPfp();
    // string constant BASE64_PNG = "iVBORw0KGgoAAAANSUhEUgAAAEAAAABACAIAAAAlC+aJAAAAAklEQVR4nGKkkSsAAAEXSURBVO3WIQ7CMBQG4Np5HME2CAwKicfgMEhOAHfgCmiugOUAnAHNRcbCkmZ53Wv7miWl7f/ymy1t+L+k21Cn6y3rqOQNAEjdAIDUDQBI3eDvAIoZAABw9zOj17vRuHcBENyb60fSvlWfwPXREgBKBUgDQPEAW9L+hlyaO+TSu15aAwBr8jtCAKQGnLeLYTiYdACoBzDt2D90fzy7AOA7Qt5m5KQdtCIBoBIAV0gKMPcvm6YPAJUDOAm3jNsIQDAgoiIAAIxK9qtZl8B+DjYAlQNMpEffbOQAoX0AkMV+m7kHgGoBy3lD0u96Bc/nqLt4JQDkCyBvw/yegUIA9odJKpEWAKBUAPf3M/pwA1A5YKp+AAAAgCdfgXWDFWuL1n4AAAAASUVORK5CYII=";
    string constant BASE64_PNG = "";

    function test_canMint() external {
        uint256 tokenId = pfp.mint(BASE64_PNG);
        assertEq(tokenId, pfp.lastTokenId());
        assertEq(pfp.tokenURI(tokenId), string(abi.encodePacked('data:image/png;base64,', BASE64_PNG)));
    }

    function test_canTransfer() external {
        uint256 tokenId = pfp.mint(BASE64_PNG);
        address to = _randomAddress();
        pfp.transferFrom(address(this), to, tokenId);
        assertEq(pfp.ownerOf(tokenId), to);
    }

    function test_canTransferWithApproval() external {
        uint256 tokenId = pfp.mint(BASE64_PNG);
        address to = _randomAddress();
        address spender = _randomAddress();
        pfp.setApprovalForAll(spender, true);
        vm.prank(spender);
        pfp.transferFrom(address(this), to, tokenId);
        assertEq(pfp.ownerOf(tokenId), to);
    }

    function test_canRevokeApproval() external {
        address spender = _randomAddress();
        pfp.setApprovalForAll(spender, true);
        assertTrue(pfp.isApprovedForAll(address(this), spender));
        pfp.setApprovalForAll(spender, false);
        assertFalse(pfp.isApprovedForAll(address(this), spender));
    }

    function test_cannotTransferTwice() external {
        uint256 tokenId = pfp.mint(BASE64_PNG);
        address to = _randomAddress();
        pfp.transferFrom(address(this), to, tokenId);
        vm.expectRevert('wrong owner');
        pfp.transferFrom(address(this), to, tokenId);
    }

    function test_cannotTransferUnmintedTokenId() external {
        address to = _randomAddress();
        uint256 tokenId = pfp.lastTokenId() + 1;
        vm.expectRevert('wrong owner');
        pfp.transferFrom(address(this), to, tokenId);
    }

    function test_cannotTransferFromWithoutApproval() external {
        uint256 tokenId = pfp.mint(BASE64_PNG);
        address to = _randomAddress();
        address spender = _randomAddress();
        vm.prank(spender);
        vm.expectRevert('not approved');
        pfp.transferFrom(address(this), to, tokenId);
    }
}