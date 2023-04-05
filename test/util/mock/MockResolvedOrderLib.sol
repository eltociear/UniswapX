pragma solidity ^0.8.16;

import {OrderInfo, ResolvedOrder} from "../../../src/base/ReactorStructs.sol";
import {ResolvedOrderLib} from "../../../src/lib/ResolvedOrderLib.sol";

contract MockResolvedOrderLib {
    using ResolvedOrderLib for ResolvedOrder;

    function prepare(ResolvedOrder memory resolvedOrder, address filler) external view {
        resolvedOrder.prepare(filler);
    }
}
