// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title ITransferValidator
/// @notice Minimal ERC-721C-style validator interface. A collection points at a
///         validator; on every secondary transfer the collection asks the validator
///         whether the transfer is allowed. Validators keep an allowlist of
///         royalty-honoring operators/marketplaces, which is how royalties are
///         enforced on-chain rather than merely suggested.
interface ITransferValidator {
    /// @param caller   The operator moving the token (msg.sender of the transfer).
    /// @param from     Current owner.
    /// @param to       Recipient.
    /// @param tokenId  Token being moved.
    function validateTransfer(address caller, address from, address to, uint256 tokenId) external view;
}
