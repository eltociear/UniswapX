// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.16;

import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {ResolvedOrder} from "../../../src/base/ReactorStructs.sol";
import {ProtocolFees} from "../../../src/base/ProtocolFees.sol";

contract MockProtocolFees is ProtocolFees {
    constructor(address _protocolFeeOwner) ProtocolFees(_protocolFeeOwner) {}

    function takeFees(ResolvedOrder[] memory orders) external view returns (ResolvedOrder[] memory) {
        _takeFees(orders);
        return orders;
    }
}