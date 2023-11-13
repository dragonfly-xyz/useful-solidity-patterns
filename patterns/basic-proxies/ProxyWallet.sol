// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

// The proxy contract for a wallet.
contract WalletProxy {
    // Who can upgrade the logic.
    address immutable public owner;
    // explicit storage slot for logic contract address, as per EIP-1967.
    uint256 constant EIP1967_LOGIC_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

    event Upgraded(address indexed logic); // required by EIP-1967

    constructor(address logic) {
        // Creator is the owner/admin.
        owner = msg.sender;
        _setlogic(logic);
    }

    function upgrade(address logic) external {
        require(msg.sender == owner, 'only owner');
        _setlogic(logic);
    }

    fallback(bytes calldata callData) external payable returns (bytes memory resultData) {
        address logic;
        assembly { logic := sload(EIP1967_LOGIC_SLOT) }
        bool success;
        (success, resultData) = logic.delegatecall(callData);
        if (!success) {
            // bubble up the revert if the call failed.
            assembly { revert(add(resultData, 0x20), mload(resultData)) }
        }
        // Otherwise, the raw resultData will be returned.
    }

    // Allow the wallet to receive ETH.
    receive() external payable {}

    function _setlogic(address logic) private {
        emit Upgraded(logic);
        assembly { sstore(EIP1967_LOGIC_SLOT, logic) }
    }
}

// First version of the logic contract for the wallet.
contract WalletLogicV1 {
    modifier onlyOwner() {
        // owner() is a function defined on the Proxy contract, which we can
        // reach through address(this), since we'll be inside a delegatecall context.
        require(msg.sender == WalletProxy(payable(address(this))).owner(), 'only owner');
        _;
    }
    
    function version() external virtual pure returns (string memory) { return 'V1'; }

    // Transfers out ETH held by the wallet.
    function transferETH(address payable to, uint256 amount) external onlyOwner {
        to.transfer(amount);
    }
}

// Second version of the logic contract for the wallet (adds ERC20 support).
contract WalletLogicV2 is WalletLogicV1 {
    function version() external override pure returns (string memory) { return 'V2'; }

    // Transfers out ERC20s held by the wallet.
    function transferERC20(IERC20 token, address to, uint256 amount) external onlyOwner {
        token.transfer(to, amount);
    }
}

// Minimal, standard ERC20 interface.
interface IERC20 {
    function transfer(address to, uint256 amount) external returns (bool);
}