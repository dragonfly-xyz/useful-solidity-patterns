// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

// A king of the hill game where each new king must pay the old king
// more than they paid. Vulnerable to a DoS attack if the old king
// was a smart contract that reverts when receiving ETH.
contract BrickableKingOfTheHill {
    // The message set by the king.
    string public message;
    // The current king.
    address payable public king;
    // How much it costs to become the new king.
    uint256 public price;

    function takeCrown(string memory message_)
        public
        virtual
        payable
    {
        require(msg.value >= price, 'not enough payment');
        price = msg.value + 1;
        address payable oldKing = king;
        king = payable(msg.sender);
        message = message_;
        _transferEth(oldKing, msg.value);
    }

    function _transferEth(address payable to, uint256 amount)
        internal
        virtual
    {
        to.transfer(amount);
    }
}

// The same king of the hill game but enforces that every king
// is an EOA, which cannot revert when receving ETH, by checking that
// the caller is the tx.origin.
contract OnlyEOAKingOfTheHill is BrickableKingOfTheHill {
    
    modifier onlyEOA() {
        require(tx.origin == msg.sender, 'only EOA');
        _;
    }

    function takeCrown(string memory message_)
        public
        override
        payable
        onlyEOA // Add a modifier.
    {
        super.takeCrown(message_);
    }
}

// The same king of the hill game but if a king is a contract when
// being paid, it will set aside the ETH to be claimed in a separate call to
// claim(). 
contract ClaimableKingOfTheHill is BrickableKingOfTheHill {
    mapping (address => uint256) public owed;

    function _transferEth(address payable to, uint256 amount)
        internal
        override
    {
        if (to.code.length == 0) {
            // Receiver is not a contract and can safely receive ETH.
            super._transferEth(to, amount);
            return;
        }
        // The receiver has code. It may revert or do other things if we
        // try to transfer it ETH. Instead, hold on to the ETH and let the
        // receiver call claim() to claim it separately.
        owed[to] += amount;
    }

    function claim() external {
        uint256 amount = owed[msg.sender];
        owed[msg.sender] = 0;
        super._transferEth(payable(msg.sender), amount);
    }
}

// A malicious king contract that will revert if the game tries to send it
// ETH.
contract EvilKing {
    // The receive() function gets called when a plain ETH transfer is
    // sent to this contract.
    receive() external virtual payable {
        revert('king forever');
    }

    function becomeKing(
        BrickableKingOfTheHill game,
        string calldata message_
    )
        payable
        external
    {
        // Call takeCrown() on the game contract.
        game.takeCrown{ value: msg.value }(message_);
    }
}