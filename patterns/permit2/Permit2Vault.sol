// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

// Trivial vault that allows users to deposit ERC20 tokens then claim them later.
contract Permit2Vault {
    bool private _reentrancyGuard;
    // The canonical permit2 contract.
    IPermit2 public immutable PERMIT2;
    // User -> token -> deposit balance
    mapping (address => mapping (IERC20 => uint256)) public tokenBalancesByUser;

    constructor(IPermit2 permit_) {
        PERMIT2 = permit_;
    }
    
    // Prevents reentrancy attacks via tokens with callback mechanisms. 
    modifier nonReentrant() {
        require(!_reentrancyGuard, 'no reentrancy');
        _reentrancyGuard = true;
        _;
        _reentrancyGuard = false;
    }

    // Deposit some amount of an ERC20 token from the caller
    // into this contract using Permit2.
    function depositERC20(
        IERC20 token,
        uint256 amount,
        uint256 nonce,
        uint256 deadline,
        bytes calldata signature
    ) external nonReentrant {
        // Credit the caller.
        tokenBalancesByUser[msg.sender][token] += amount;
        // Transfer tokens from the caller to ourselves.
        PERMIT2.permitTransferFrom(
            // The permit message. Spender will be inferred as the caller (us).
            IPermit2.PermitTransferFrom({
                permitted: IPermit2.TokenPermissions({
                    token: token,
                    amount: amount
                }),
                nonce: nonce,
                deadline: deadline
            }),
            // The transfer recipient and amount.
            IPermit2.SignatureTransferDetails({
                to: address(this),
                requestedAmount: amount
            }),
            // The owner of the tokens, which must also be
            // the signer of the message, otherwise this call
            // will fail.
            msg.sender,
            // The packed signature that was the result of signing
            // the EIP712 hash of `permit`.
            signature
        );
    }

    // Deposit multiple ERC20 tokens from the caller
    // into this contract using Permit2.
    function depositBatchERC20(
        IERC20[] calldata tokens,
        uint256[] calldata amounts,
        uint256 nonce,
        uint256 deadline,
        bytes calldata signature
    ) external nonReentrant {
        require(tokens.length == amounts.length, 'array mismatch');
        // The batch form of `permitTransferFrom()` takes an array of
        // transfer details, which we will all direct to ourselves.
        IPermit2.SignatureTransferDetails[] memory transferDetails =
            new IPermit2.SignatureTransferDetails[](tokens.length);
        // Credit the caller and populate the transferDetails.
        for (uint256 i; i < tokens.length; ++i) {
            tokenBalancesByUser[msg.sender][tokens[i]] += amounts[i];
            transferDetails[i] = IPermit2.SignatureTransferDetails({
                to: address(this),
                requestedAmount: amounts[i]
            });
        }
        PERMIT2.permitTransferFrom(
            // The permit message. Spender will be inferred as the caller (us).
            IPermit2.PermitBatchTransferFrom({
                permitted: _toTokenPermissionsArray(tokens, amounts),
                nonce: nonce,
                deadline: deadline
            }),
            // The transfer recipients and amounts.
            transferDetails,
            // The owner of the tokens, which must also be
            // the signer of the message, otherwise this call
            // will fail.
            msg.sender,
            // The packed signature that was the result of signing
            // the EIP712 hash of `permit`.
            signature
        );
    }

    // Return ERC20 tokens deposited by the caller.
    function withdrawERC20(IERC20 token, uint256 amount) external nonReentrant {
        tokenBalancesByUser[msg.sender][token] -= amount;
        // TODO: In production, use an ERC20 compatibility library to
        // execute thie transfer to support non-compliant tokens.
        token.transfer(msg.sender, amount);
    }

    function _toTokenPermissionsArray(IERC20[] calldata tokens, uint256[] calldata amounts)
        private pure returns (IPermit2.TokenPermissions[] memory permissions)
    {
        permissions = new IPermit2.TokenPermissions[](tokens.length);
        for (uint256 i; i < permissions.length; ++i) {
            permissions[i] = IPermit2.TokenPermissions({ token: tokens[i], amount: amounts[i] });
        }
    }
}

// Minimal Permit2 interface, derived from
// https://github.com/Uniswap/permit2/blob/main/src/interfaces/ISignatureTransfer.sol
interface IPermit2 {
    // Token and amount in a permit message.
    struct TokenPermissions {
        // Token to transfer.
        IERC20 token;
        // Amount to transfer.
        uint256 amount;
    }

    // The permit2 message.
    struct PermitTransferFrom {
        // Permitted token and maximum amount.
        TokenPermissions permitted;// deadline on the permit signature
        // Unique identifier for this permit.
        uint256 nonce;
        // Expiration for this permit.
        uint256 deadline;
    }

    // The permit2 message for batch transfers.
    struct PermitBatchTransferFrom {
        // Permitted tokens and maximum amounts.
        TokenPermissions[] permitted;
        // Unique identifier for this permit.
        uint256 nonce;
        // Expiration for this permit.
        uint256 deadline;
    }

    // Transfer details for permitTransferFrom().
    struct SignatureTransferDetails {
        // Recipient of tokens.
        address to;
        // Amount to transfer.
        uint256 requestedAmount;
    }

    // Consume a permit2 message and transfer tokens.
    function permitTransferFrom(
        PermitTransferFrom calldata permit,
        SignatureTransferDetails calldata transferDetails,
        address owner,
        bytes calldata signature
    ) external;

    // Consume a batch permit2 message and transfer tokens.
    function permitTransferFrom(
        PermitBatchTransferFrom calldata permit,
        SignatureTransferDetails[] calldata transferDetails,
        address owner,
        bytes calldata signature
    ) external;
}

// Minimal ERC20 interface.
interface IERC20 {
    function transfer(address to, uint256 amount) external returns (bool);
}

