// A restricted NFT sale that can be minted/bought via buy() which is
//  vulnerable to reentrancy.
contract ReentrantNftSale is RestrictedNftSaleBase {
    constructor(address[] memory allowList)
        RestrictedNftSaleBase(allowList)
    {}

    function buy() payable external override {
        require(msg.value == PRICE);
        require(canBuy[msg.sender], 'already bought');
        _mintTo(msg.sender);
        canBuy[msg.sender] = false;
    }
}

// A restricted NFT sale that can be minted/bought via buy() which is
//  secured by a reentrancy guard.
contract GuardedNftSale is RestrictedNftSaleBase {
    bool _lock;

    constructor(address[] memory allowList)
        RestrictedNftSaleBase(allowList)
    {}

    modifier nonReentrant() {
        require(!_lock, 'reentered');
        _lock = true; _; _lock = false;
    }

    function buy() payable external override nonReentrant {
        require(msg.value == PRICE);
        require(canBuy[msg.sender], 'already bought');
        _mintTo(msg.sender);
        canBuy[msg.sender] = false;
    }
}

// A restricted NFT sale that can be minted/bought via buy() which
// follows the check-effects-interactions pattern and validates an
// invariant.
contract CheckedNftSale is RestrictedNftSaleBase {
    uint256 immutable _maxSupply;

    constructor(address[] memory allowList)
        RestrictedNftSaleBase(allowList)
    {
        _maxSupply = allowList.length;
    }

    function buy() payable external override {
        require(msg.value == PRICE);
        require(canBuy[msg.sender], 'already bought');
        canBuy[msg.sender] = false;
        _mintTo(msg.sender);
        require(totalSupply <= _maxSupply);
    }
}

// Base contract for a restricted NFT sale where certain
// addresses are allowed to mint exactly one token.
abstract contract RestrictedNftSaleBase is ERC721ish {
    address payable immutable public OWNER;
    uint256 constant public PRICE = 0.01 ether;
    mapping (address => bool) public canBuy;

    constructor(address[] memory allowList) {
        OWNER = payable(msg.sender);
        for (uint256 i; i < allowList.length; ++i) {
            canBuy[i] = true;
        }
    }

    function withdraw() external {
        require(msg.sender == OWNER);
        OWNER.transfer(address(this).balance);
    }

    function buy() payable external virtual;
}

// Base contract for an NFT contract implementing a heavily simplified
// version of the ERC721 spec. Notably, it implements the callback on transfer
// mechanism of ERC721.
abstract contract ERC721ish {
    uint256 private _lastTokenId;
    uint256 public totalSupply;
    mapping (address => uint256) public balanceOf;
    mapping (uint256 => address) public ownerOf;

    function transfer(address to, uint256 tokenId)
        external
    {
        require(to != address(0) && ownerOf[tokenId] == msg.sender);
        ownerOf[tokenId] = to;
        --balanceOf[msg.sender];
        ++balanceOf[to];
        _callReceiver(msg.sender, to, tokenId, "");
    }

    function _mintTo(address to) internal {
        uint256 tokenId = ++_lastTokenId;
        ownerOf[tokenId] = to;
        ++balanceOf[to];
        ++totalSupply;
        _callReceiver(address(0), to, tokenId, "");
    } 

    function _callReceiver(address from, address to, uint256 tokenId, bytes memory data)
        private
    {
        if (to.code.length != 0) {
            require(IERC721Receiver(to).onERC721Received(
                msg.sender,
                from,
                tokenId,
                ""
            ) == IERC721Receiver.onERC721Received.selector);
        }
    }
}

interface IERC721Receiver {
    function onERC721Received(
        address operator,
        address from,
        uint256 tokenId,
        bytes calldata  data
    ) external returns (bytes4);
}