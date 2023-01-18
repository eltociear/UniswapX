// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.16;

import {SafeTransferLib} from "solmate/src/utils/SafeTransferLib.sol";
import {ISignatureTransfer} from "permit2/src/interfaces/ISignatureTransfer.sol";
import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {SettlementEvents} from "../base/SettlementEvents.sol";
import {IOrderSettler} from "../interfaces/IOrderSettler.sol";
import {ISettlementOracle} from "../interfaces/ISettlementOracle.sol";
import {
    ResolvedOrder, SettlementInfo, ActiveSettlement, OutputToken, OrderStatus
} from "../base/SettlementStructs.sol";
import {SignedOrder, InputToken} from "../../base/ReactorStructs.sol";
import {ResolvedOrderLib} from "../lib/ResolvedOrderLib.sol";

/// @notice Generic cross-chain reactor logic for settling off-chain signed orders
/// using arbitrary fill methods specified by a taker
abstract contract BaseOrderSettler is IOrderSettler, SettlementEvents {
    using SafeTransferLib for ERC20;
    using ResolvedOrderLib for ResolvedOrder;

    ISignatureTransfer public immutable permit2;

    mapping(bytes32 => ActiveSettlement) settlements;

    constructor(address _permit2) {
        permit2 = ISignatureTransfer(_permit2);
    }

    /// @inheritdoc IOrderSettler
    function initiateSettlement(SignedOrder calldata order, address crossChainFiller) external override {
        ResolvedOrder[] memory resolvedOrders = new ResolvedOrder[](1);
        resolvedOrders[0] = resolve(order);
        _initiateSettlements(resolvedOrders, crossChainFiller);
    }

    function _initiateSettlements(ResolvedOrder[] memory orders, address crossChainFiller) internal {
        unchecked {
            for (uint256 i = 0; i < orders.length; i++) {
                ResolvedOrder memory order = orders[i];
                order.validate(msg.sender);
                transferEscrowTokens(order);

                // settlementId: hash the order hash with the crossChainFiller address so the filler may have exclusive access
                // to this settlement. Valid cross-chain fill contracts must transmit a settlement fill by keccak256-ing
                // the msg.sender with an order hash. This prevents spam.
                settlements[keccak256(abi.encode(order.hash, crossChainFiller))] = ActiveSettlement({
                    status: OrderStatus.Pending,
                    offerer: order.info.offerer,
                    fillRecipient: msg.sender,
                    settlementOracle: order.info.settlementOracle,
                    deadline: block.timestamp + order.info.settlementPeriod,
                    input: order.input,
                    collateral: order.collateral,
                    outputs: order.outputs
                });

                emit InitiateSettlement(
                    order.hash,
                    order.info.offerer,
                    msg.sender,
                    crossChainFiller,
                    order.info.settlementOracle,
                    block.timestamp + order.info.settlementPeriod
                    );
            }
        }
    }

    /// @inheritdoc IOrderSettler
    function cancelSettlement(bytes32 settlementId) external override {
        ActiveSettlement storage settlement = settlements[settlementId];
        if (settlement.status == OrderStatus.Pending && settlement.deadline > block.timestamp) {
            settlement.status = OrderStatus.Cancelled;

            // transfer tokens and collateral back to offerer
            ERC20(settlement.input.token).safeTransfer(settlement.offerer, settlement.input.amount);
            ERC20(settlement.collateral.token).safeTransfer(settlement.offerer, settlement.input.amount);
        }
    }

    /// @inheritdoc IOrderSettler
    function finalizeSettlement(bytes32 settlementId) external override {
        ActiveSettlement storage settlement = settlements[settlementId];
        if (settlement.status == OrderStatus.Pending) {
            OutputToken[] memory receivedOutputs =
                ISettlementOracle(settlement.settlementOracle).getSettlementFillInfo(settlementId);
            for (uint256 i; i < receivedOutputs.length; i++) {}
        }
    }

    /// @notice Resolve order-type specific requirements into a generic order with the final inputs and outputs.
    /// @param order The encoded order to resolve
    /// @return resolvedOrder generic resolved order of inputs and outputs
    /// @dev should revert on any order-type-specific validation errors
    function resolve(SignedOrder calldata order) internal view virtual returns (ResolvedOrder memory resolvedOrder);

    /// @notice Transfers swapper input tokens as well as collateral tokens of filler
    /// @param order The encoded order to transfer tokens for
    function transferEscrowTokens(ResolvedOrder memory order) internal virtual;
}
