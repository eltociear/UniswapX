// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.16;

import {console} from "forge-std/console.sol";
import {SafeTransferLib} from "solmate/src/utils/SafeTransferLib.sol";
import {ISignatureTransfer} from "permit2/src/interfaces/ISignatureTransfer.sol";
import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {SettlementEvents} from "../base/SettlementEvents.sol";
import {IOrderSettler} from "../interfaces/IOrderSettler.sol";
import {ISettlementOracle} from "../interfaces/ISettlementOracle.sol";
import {
    ResolvedOrder,
    SettlementInfo,
    ActiveSettlement,
    OutputToken,
    SettlementStatus
} from "../base/SettlementStructs.sol";
import {SignedOrder, InputToken} from "../../base/ReactorStructs.sol";
import {ResolvedOrderLib} from "../lib/ResolvedOrderLib.sol";

/// @notice Generic cross-chain settler logic for settling off-chain signed orders
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
    function initiateSettlement(SignedOrder calldata order, address targetChainFiller) external override {
        ResolvedOrder[] memory resolvedOrders = new ResolvedOrder[](1);
        resolvedOrders[0] = resolve(order);
        _initiateSettlements(resolvedOrders, targetChainFiller);
    }

    function _initiateSettlements(ResolvedOrder[] memory orders, address targetChainFiller) internal {
        unchecked {
            for (uint256 i = 0; i < orders.length; i++) {
                ResolvedOrder memory order = orders[i];
                order.validate(msg.sender);
                collectEscrowTokens(order);

                if (settlements[order.hash].optimisticDeadline != 0) revert SettlementAlreadyInitiated(order.hash);

                // TODO: may not be the most gas efficient, look into setting with dynamic array
                ActiveSettlement storage settlement = settlements[order.hash];
                settlement.status = SettlementStatus.Pending;
                settlement.offerer = order.info.offerer;
                settlement.originChainFiller = msg.sender;
                settlement.targetChainFiller = targetChainFiller;
                settlement.settlementOracle = order.info.settlementOracle;
                settlement.fillDeadline = block.timestamp + order.info.fillPeriod;
                settlement.optimisticDeadline = block.timestamp + order.info.optimisticSettlementPeriod;
                settlement.challengeDeadline = block.timestamp + order.info.challengePeriod;
                settlement.input = order.input;
                settlement.fillerCollateral = order.fillerCollateral;
                settlement.challengerCollateral = order.challengerCollateral;
                for (uint256 j = 0; j < order.outputs.length; j++) {
                    settlement.outputs.push(order.outputs[j]);
                }

                emit InitiateSettlement(
                    order.hash,
                    order.info.offerer,
                    msg.sender,
                    targetChainFiller,
                    order.info.settlementOracle,
                    settlement.fillDeadline,
                    settlement.optimisticDeadline,
                    settlement.challengeDeadline
                    );
            }
        }
    }

    /// @inheritdoc IOrderSettler
    function cancelSettlement(bytes32 orderId) external override {
        ActiveSettlement storage settlement = settlements[orderId];
        if (settlement.optimisticDeadline == 0) revert SettlementDoesNotExist(orderId);
        if (settlement.challengeDeadline > block.timestamp) revert CannotCancelBeforeDeadline(orderId);
        if (settlement.status > SettlementStatus.Challenged) revert SettlementAlreadyCompleted(orderId);

        settlement.status = SettlementStatus.Cancelled;
        ERC20(settlement.input.token).safeTransfer(settlement.offerer, settlement.input.amount);
        ERC20(settlement.fillerCollateral.token).safeTransfer(settlement.offerer, settlement.input.amount);
        emit CancelSettlement(orderId);
    }

    /// @inheritdoc IOrderSettler
    function finalizeSettlement(bytes32 orderId) external override {
        ActiveSettlement memory settlement = settlements[orderId];
        if (settlement.optimisticDeadline == 0) revert SettlementDoesNotExist(orderId);

        if (settlement.status == SettlementStatus.Pending) {
            if (block.timestamp < settlement.optimisticDeadline) revert CannotFinalizeBeforeDeadline(orderId);

            settlements[orderId].status = SettlementStatus.Success;
            _compensateFiller(orderId, settlement);
        } else if (settlement.status == SettlementStatus.Challenged) {
            OutputToken[] memory filledOutputs =
                ISettlementOracle(settlement.settlementOracle).getSettlementInfo(orderId, settlement.targetChainFiller);

            if (filledOutputs.length != settlement.outputs.length) revert OutputsLengthMismatch(orderId);

            // validate outputs
            for (uint16 i; i < settlement.outputs.length; i++) {
                OutputToken memory expectedOutput = settlement.outputs[i];
                OutputToken memory receivedOutput = filledOutputs[i];
                if (expectedOutput.recipient != receivedOutput.recipient) revert InvalidRecipient(orderId, i);
                if (expectedOutput.token != receivedOutput.token) revert InvalidToken(orderId, i);
                if (expectedOutput.amount < receivedOutput.amount) revert InvalidAmount(orderId, i);
                if (expectedOutput.chainId != receivedOutput.chainId) revert InvalidChain(orderId, i);
            }

            settlements[orderId].status = SettlementStatus.Success;
            ERC20(settlement.challengerCollateral.token).safeTransfer(settlement.originChainFiller, settlement.challengerCollateral.amount);
            _compensateFiller(orderId, settlement);
        } else {
            revert SettlementAlreadyCompleted(orderId);
        }
    }

    function challengeSettlement(bytes32 orderId) external {
        ActiveSettlement memory settlement = settlements[orderId];
        if (settlement.optimisticDeadline == 0) revert SettlementDoesNotExist(orderId);
        if (settlement.status != SettlementStatus.Pending) revert CanOnlyChallengePendingSettlements(orderId);

        settlements[orderId].status = SettlementStatus.Challenged;
        collectChallengeBond(settlement);
        emit SettlementChallenged(orderId, msg.sender);
    }

    function _compensateFiller(bytes32 orderId, ActiveSettlement memory settlement) internal {
        settlements[orderId].status = SettlementStatus.Success;
        ERC20(settlement.input.token).safeTransfer(settlement.originChainFiller, settlement.input.amount);
        ERC20(settlement.fillerCollateral.token).safeTransfer(settlement.originChainFiller, settlement.input.amount);
        emit FinalizeSettlement(orderId);
    }

    function getSettlement(bytes32 orderHash) external view returns (ActiveSettlement memory) {
        return settlements[orderHash];
    }

    /// @notice Resolve order-type specific requirements into a generic order with the final inputs and outputs.
    /// @param order The encoded order to resolve
    /// @return resolvedOrder generic resolved order of inputs and outputs
    /// @dev should revert on any order-type-specific validation errors
    function resolve(SignedOrder calldata order) internal view virtual returns (ResolvedOrder memory resolvedOrder);

    /// @notice Collects swapper input tokens as well as collateral tokens of filler to escrow them until settlement is
    /// finalized or cancelled
    /// @param order The encoded order to transfer tokens for
    function collectEscrowTokens(ResolvedOrder memory order) internal virtual;

    /// @notice Collects swapper input tokens as well as collateral tokens of filler to escrow them until settlement is
    /// finalized or cancelled
    /// @param settlement The current information associated with the active settlement
    function collectChallengeBond(ActiveSettlement memory settlement) internal virtual;
}
