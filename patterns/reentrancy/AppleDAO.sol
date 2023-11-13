// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

interface INftReceiver {
    function onNftReceived(address owner, uint256 tokenId)
        external;
}

// EC721-inspired contract, simplified and "soulbound" for brevity.
contract Apples {
    address immutable public MINTER;
    uint256 public totalSupply;
    mapping (uint256 => address) public ownerOf;
    mapping (address => uint256) public balanceOf;

    constructor(address minter) { MINTER = minter; }

    function safeMint(address to) external returns (uint256 tokenId) {
        require(msg.sender == MINTER, 'only minter');
        tokenId = totalSupply++;
        ownerOf[tokenId] = to;
        ++balanceOf[to];
        if (to.code.length != 0) {
            INftReceiver(to).onNftReceived(address(0), tokenId);
        }
    }
}

// Alice wants to give exactly one apple NFT to everyone that
// calls claimApple().
contract Alice {
    Apples public immutable APPLES = new Apples(address(this));
    mapping (address => bool) _hasReceivedApple;

    function claimApple() public virtual {
        require(!_hasReceivedApple[msg.sender], 'already got an apple');
        // safeMint() calls the receiver's onNftReceived() handler. 
        APPLES.safeMint(msg.sender);
        _hasReceivedApple[msg.sender] = true;
    }
}

// Bob wants to get lots of apples from Alice.
contract Bob {
    Alice immutable public ALICE;

    constructor(Alice alice) { ALICE = alice; }

    function exploit() external {
        _claim();
    }

    // Gets called whenver bob gets an NFT.
    function onNftReceived(address, uint256) external {
        require(msg.sender == address(ALICE.APPLES()));
        _claim();
    }

    function _claim() private {
        // Keep claiming apples until we have 10.
        if (ALICE.APPLES().balanceOf(address(this)) < 10) {
            ALICE.claimApple();
        }
    }
}

// Alice but with Checks-Effects-Interactions pattern applied.
contract SmartAlice is Alice {
    // Simple reordering of statements secures this function from reentrancy.
    function claimApple() public override {
        // CHECKS: Sender hasn't received an apple yet.
        require(!_hasReceivedApple[msg.sender], 'already got an apple');
        // EFFECTS: Record that the sender has claimed an apple.
        _hasReceivedApple[msg.sender] = true;
        // INTERACTIONS: Give the sender an apple.
        APPLES.safeMint(msg.sender);
    }
}

// Alice but with a reentrancy guard.
contract NonReentrantAlice is Alice {
    bool private _reentrancyGuard;

    modifier nonReentrant() {
        require(!_reentrancyGuard, 'reentrancy detected');
        _reentrancyGuard = true;
        _;
        _reentrancyGuard = false;
    }

    // Overrides claimApple to add a reentrancy guard check before execution.
    function claimApple() public override nonReentrant {
        super.claimApple();
    }
}
