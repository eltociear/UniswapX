// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.16;

import {ResolvedOrder, SignedOrder} from "../base/ReactorStructs.sol";

/// @notice Interface for order execution reactors
interface IReactor {
    /// @notice Execute a single order using the given fill specification
    /// @param order The order definition and valid signature to execute
    /// @param fillData The fillData to pass to the taker callback
    function execute(SignedOrder calldata order, bytes calldata fillData) external;

    /// @notice Execute the given orders at once with the specified fill specification
    /// @param orders The order definitions and valid signatures to execute
    /// @param fillData The fillData to pass to the taker callback
    function executeBatch(SignedOrder[] calldata orders, bytes calldata fillData) external;
}
