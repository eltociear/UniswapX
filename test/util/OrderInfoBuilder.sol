// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.16;

import {OrderInfo} from "../../src/base/ReactorStructs.sol";

library OrderInfoBuilder {
    function init(address reactor) internal view returns (OrderInfo memory) {
        return OrderInfo({
            reactor: reactor,
            offerer: address(0),
            nonce: 0,
            deadline: block.timestamp + 100,
            preparationContract: address(0),
            preparationData: bytes("")
        });
    }

    function withOfferer(OrderInfo memory info, address _offerer) internal pure returns (OrderInfo memory) {
        info.offerer = _offerer;
        return info;
    }

    function withNonce(OrderInfo memory info, uint256 _nonce) internal pure returns (OrderInfo memory) {
        info.nonce = _nonce;
        return info;
    }

    function withDeadline(OrderInfo memory info, uint256 _deadline) internal pure returns (OrderInfo memory) {
        info.deadline = _deadline;
        return info;
    }

    function withPreparationContract(OrderInfo memory info, address _preparationContract)
        internal
        pure
        returns (OrderInfo memory)
    {
        info.preparationContract = _preparationContract;
        return info;
    }

    function withPreparationData(OrderInfo memory info, bytes memory _preparationData)
        internal
        pure
        returns (OrderInfo memory)
    {
        info.preparationData = _preparationData;
        return info;
    }
}
