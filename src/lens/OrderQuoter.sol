// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.16;

import {IReactorCallback} from "../interfaces/IReactorCallback.sol";
import {BaseReactor} from "../reactors/BaseReactor.sol";
import {OrderInfo, ResolvedOrder, SignedOrder} from "../base/ReactorStructs.sol";

/// @notice Quoter contract for orders
/// @dev note this is meant to be used as an off-chain lens contract to pre-validate generic orders
contract OrderQuoter is IReactorCallback {
    // OrderInfo struct is dynamic so this is the offset to the tail pointer
    uint256 constant ORDER_INFO_OFFSET = 64;
    // Offset to reactor field in OrderInfo struct
    uint256 constant REACTOR_OFFSET = 64;

    /// @notice Quote the given order, returning the ResolvedOrder object which defines
    /// the current input and output token amounts required to satisfy it
    /// Also bubbles up any reverts that would occur during the processing of the order
    /// @param order abi-encoded order, including `reactor` as the first encoded struct member
    /// @param sig The order signature
    /// @return result The ResolvedOrder
    function quote(bytes memory order, bytes memory sig) external returns (ResolvedOrder memory result) {
        try BaseReactor(getReactor(order)).execute(SignedOrder(order, sig), address(this), bytes("")) {}
        catch (bytes memory reason) {
            result = parseRevertReason(reason);
        }
    }

    function getReactor(bytes memory order) private pure returns (address reactor) {
        assembly {
            let reactorOffset := mload(add(order, ORDER_INFO_OFFSET))
            reactor := mload(add(order, add(reactorOffset, REACTOR_OFFSET)))
        }
    }

    function parseRevertReason(bytes memory reason) private pure returns (ResolvedOrder memory order) {
        if (reason.length < 192) {
            assembly {
                revert(add(32, reason), mload(reason))
            }
        } else {
            return abi.decode(reason, (ResolvedOrder));
        }
    }

    function reactorCallback(ResolvedOrder[] memory resolvedOrders, address filler, bytes memory) external view {
        require(filler == address(this));
        bytes memory order = abi.encode(resolvedOrders[0]);
        assembly {
            revert(add(32, order), mload(order))
        }
    }
}
