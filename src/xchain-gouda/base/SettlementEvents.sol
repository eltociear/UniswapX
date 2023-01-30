// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.16;

/// @notice standardized events that should be emitted by all cross-chain reactors
/// @dev collated into one library to help with forge expectEmit integration
/// @dev and for reactors which dont use base
contract SettlementEvents {
    /// @notice emitted when a settlement is initiated
    /// @param orderHash The hash of the order to be filled
    /// @param offerer The offerer of the filled order
    /// @param fillRecipient The address to receive the input tokens once the order is filled
    /// @param crossChainFiller The cross chain listener which provides information on the cross chain order fulfillment
    /// @param settlementOracle The settlementOracle to be used to determine fulfillment of order
    /// @param settlementDeadline The timestamp starting at which the settlement may be cancelled if not filled
    event InitiateSettlement(
        bytes32 indexed orderHash,
        address indexed fillRecipient,
        address indexed offerer,
        address crossChainFiller,
        address settlementOracle,
        uint256 settlementDeadline
    );

    /// @notice emitted when a settlement has been filled successfully
    event FinalizeSettlement(bytes32 indexed orderId);

    /// @notice emitted when a settlement has been cancelled
    event CancelSettlement(bytes32 indexed orderId);
}