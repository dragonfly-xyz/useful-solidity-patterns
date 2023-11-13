// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

// Minimal ERC20 interface.
interface IERC20 {
    function approve(address spender, uint256 amount) external returns (bool);
    function transferFrom(address owner, address to, uint256 amount) external returns (bool);
}

// Payout calculation logic shared between PackedPayouts and NaivePayouts
contract PayoutCalc {
    function _computeVestingOwed(
        uint256 cliff,
        uint256 period,
        uint256 totalAmount,
        uint256 vestedAmount
    )
        internal
        view
        returns (uint256 owed)
    {
        if (block.timestamp < cliff || period == 0 || vestedAmount >= totalAmount) {
            return 0;
        }
        uint256 dt = block.timestamp - cliff;
        if (dt > period) {
            dt = period;
        }
        return totalAmount * dt / period - vestedAmount;
    }
}

// Pays out ETH to recipients on a vesting schedule. Not using packed storage.
contract NaivePayouts is PayoutCalc {
    struct Vesting {
        // When payouts begin.
        uint256 cliff;
        // How long the payouts will be made for (after cliff).
        uint256 period;
        // The total amount of ETH that will be paid out.
        uint256 totalAmount;
        // How much ETH has been claimed.
        uint256 vestedAmount;
    }

    event VestingCreated(address indexed recipient, uint256 id, uint256 totalAmount);
    event Vested(address indexed recipient, uint256 indexed id, uint256 amount);

    uint256 _lastId;
    // Recipient -> vesting ID -> Vesting.
    mapping (address => mapping(uint256 => Vesting)) _vestings;

    function vest(address recipient, uint256 cliff, uint256 period)
        external
        payable
        returns (uint256 id)
    {
        require(msg.value > 0 && period > 0);
        id = ++_lastId;
        _vestings[recipient][id] = Vesting({
            cliff: cliff,
            period: period,
            totalAmount: msg.value,
            vestedAmount: 0
        });
        emit VestingCreated(recipient, id, msg.value);
    }

    function claim(uint256 id) external {
        Vesting memory vesting = _vestings[msg.sender][id];
        uint256 owed = _computeVestingOwed(
            vesting.cliff,
            vesting.period,
            vesting.totalAmount,
            vesting.vestedAmount
        );
        require(owed != 0, 'nothing owed');
        _vestings[msg.sender][id].vestedAmount = vesting.vestedAmount + owed;
        payable(msg.sender).transfer(owed);
        emit Vested(msg.sender, id, owed);
    }
}

// Same as NaivePayouts but using packed storage.
contract PackedPayouts is PayoutCalc {
    struct Vesting {
        // When payouts begin.
        uint40 cliff;
        // How many _days_ the payouts will be made for (after cliff).
        uint24 periodInDays;
        // The total amount of ETH that will be paid out.
        uint96 totalAmount;
        // How much ETH has been claimed.
        uint96 vestedAmount;
    }

    event VestingCreated(address indexed recipient, uint256 id, uint96 totalAmount);
    event Vested(address indexed recipient, uint256 indexed id, uint256 amount);

    uint256 _lastId;
    // Recipient -> vesting ID -> Vesting.
    mapping (address => mapping(uint256 => Vesting)) _vestings;

    function vest(address recipient, uint40 cliff, uint24 periodInDays)
        external
        payable
        returns (uint256 id)
    {
        require(msg.value > 0 && periodInDays > 0);
        id = ++_lastId;
        _vestings[recipient][id] = Vesting({
            cliff: cliff,
            periodInDays: periodInDays,
            totalAmount: uint96(msg.value),
            vestedAmount: 0
        });
        emit VestingCreated(recipient, id, uint96(msg.value));
    }

    function claim(uint256 id) external {
        Vesting memory vesting = _vestings[msg.sender][id];
        uint256 owed = _computeVestingOwed(
            vesting.cliff,
            uint256(vesting.periodInDays) * 1 days,
            vesting.totalAmount,
            vesting.vestedAmount
        );
        require(owed != 0, 'nothing owed');
        vesting.vestedAmount += uint96(owed);
        _vestings[msg.sender][id] = vesting;
        payable(msg.sender).transfer(owed);
        emit Vested(msg.sender, id, owed);
    }
}
