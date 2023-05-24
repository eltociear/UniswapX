// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.16;

import {Owned} from "solmate/src/auth/Owned.sol";
import {ResolvedOrder, OutputToken} from "../../../src/base/ReactorStructs.sol";
import {IProtocolFeeController} from "../../../src/interfaces/IProtocolFeeController.sol";

/// @notice The same as MockFeeController, but always returns a fee outputs array of length 1 and token = address(0).
// Used for testing purposes, specifically to activate `InvalidFeeToken()` error
contract MockFeeControllerZeroFee is IProtocolFeeController, Owned(msg.sender) {
    address public immutable feeRecipient;

    constructor(address _feeRecipient) {
        feeRecipient = _feeRecipient;
    }

    mapping(address tokenIn => mapping(address tokenOut => uint256)) public fees;

    /// @inheritdoc IProtocolFeeController
    function getFeeOutputs(ResolvedOrder memory) external pure override returns (OutputToken[] memory result) {
        result = new OutputToken[](1);
        result[0].token = address(0);
        result[0].recipient = address(0);
        result[0].amount = 0;
    }

    function setFee(address tokenIn, address tokenOut, uint256 fee) external onlyOwner {
        fees[tokenIn][tokenOut] = fee;
    }
}
