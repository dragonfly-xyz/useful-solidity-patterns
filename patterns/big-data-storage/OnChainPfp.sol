// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

// An ERC721-like NFT contract where users can mint a token with
// custom image metadata, stored on-chain.
contract OnChainPfp {
    event Transfer(address indexed from, address indexed to, uint256 indexed tokenId);
    event ApprovalForAll(address indexed owner, address indexed spender, bool approved);

    uint256 public lastTokenId = 0;
    mapping (uint256 => address) public tokenIdToStorage;
    mapping (uint256 => address) public ownerOf;
    mapping (address => mapping (address => bool)) public isApprovedForAll;

    function tokenURI(uint256 tokenId)
        external
        view
        returns (string memory r)
    {
        return string(abi.encodePacked(
            'data:image/png;base64,',
            _loadBigData(tokenIdToStorage[tokenId])
        ));
    }

    function mint(string memory base64PngImageData)
        external
        returns (uint256 tokenId)
    {
        tokenId = ++lastTokenId;
        tokenIdToStorage[tokenId] = _storeBigData(base64PngImageData);
        ownerOf[tokenId] = msg.sender;
        emit Transfer(address(0), msg.sender, tokenId);
    }

    function transferFrom(address from, address to, uint256 tokenId) external {
        require(ownerOf[tokenId] == from, 'wrong owner');
        if (from != msg.sender) {
            require(isApprovedForAll[from][msg.sender], 'not approved');
        }
        ownerOf[tokenId] = to;
        emit Transfer(from, to, tokenId);
    }

    function setApprovalForAll(address spender, bool approved) external {
        isApprovedForAll[msg.sender][spender] = approved;
        emit ApprovalForAll(msg.sender, spender, approved);
    }

    function _storeBigData(string memory data)
        internal
        returns (address loc)
    {
        return address(new BigDataStore(bytes(data)));
    }

    function _loadBigData(address loc)
        internal
        view
        returns (string memory data)
    {
        // Use extcodecopy instead of loc.code because we don't
        // want the first (00) byte.
        uint256 dataSize = loc.code.length - 1;
        data = new string(dataSize);
        assembly {
            extcodecopy(loc, add(data, 0x20), 0x01, dataSize)
        }
    }
}

contract BigDataStore {
    constructor(bytes memory data) {
        assembly {
            let size := mload(data)
            // Overwrite the length prefix with '00'
            // to avoid having to copy all the data again
            // with abi.encodePacked(hex"00", data).
            mstore(data, 0x00)
            return(add(data, 0x1F), add(size, 1))
        }
    }
}