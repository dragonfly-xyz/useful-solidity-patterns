// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

// A contract that users grant an ERC20 allowance to, via approve() mechanism.
// Other (authorized) contracts in the protocol can call `spendFrom()`
// to transfer tokens on a user's behalf. This contract instance can be
// reused even as other contracts in the protocol are replaced to avoid having to
// migrate user allowances. 
contract AllowanceTarget {
    // Who can add new authorities.
    address public immutable admin;
    // Whether an address is allowed to call `spendFrom()`.
    mapping (address => bool) public authorized;

    modifier onlyAuthorized() {
        require(authorized[msg.sender], 'only authorized');
        _;
    }

    constructor(address admin_) {
        admin = admin_;
    }

    // Grant an address or revoke the ability to call `spendFrom()`.
    // `admin` should do this for new versions of protocol contracts.
    function setAuthority(address authority, bool enabled) external {
        require(msg.sender == admin, 'only admin can call this');
        authorized[authority] = enabled;
    }

    // Transfers `value` `token`s from `from` to `to`.
    // Only callable by authorized addresses. 
    function spendFrom(IERC20 token, address from, address to, uint256 value)
        external
        onlyAuthorized
    {
        // Call `token.transferFrom()`, supporting non-compliant ERC20 tokens (e.g., USDT).
        // See https://github.com/dragonfly-xyz/useful-solidity-patterns/tree/main/patterns/erc20-compatibility
        // for more details on handling non-compliant ERC20 tokens.
        (bool s, bytes memory r) = address(token).call(abi.encodeCall(
            IERC20.transferFrom,
            (from, to, value)
        ));
        if (!s) {
            // Call failed. Bubble up the revert.
            assembly { revert(add(r, 0x20), mload(r)) }
        }
        // Call succeeded. If it returned a value, make sure it was `true`.
        require(r.length == 0 || abi.decode(r, (bool)), 'transferFrom call failed');
    }
}

// (Very) Minimal ERC20 interface.
interface IERC20 {
    function transferFrom(address admin, address to, uint256 value) external returns (bool);
}