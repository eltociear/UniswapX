pragma solidity ^0.8.16;

import {IERC20, SafeERC20} from "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";

contract MockOneInchAggregator {
    using SafeERC20 for IERC20;

    error NativeTransferFailed();
    error TooLittleReceived();

    uint256 public constant SWAP_RATE_GRANULARITY = 10000;
    uint256 public swapRate = 10000; // start with swap at 1 for 1

    function setSwapRate(uint256 newRate) public {
        swapRate = newRate;
    }

    function unoswap(address srcToken, uint256 amount, uint256 minReturn, uint256[] calldata pools)
        external
        payable
        returns (uint256 returnAmount)
    {
        returnAmount = (amount * swapRate) / SWAP_RATE_GRANULARITY;
        if (returnAmount < minReturn) revert TooLittleReceived();

        // not handling pools[] like 1inch but ok for mock
        address tokenOut = address(uint160(pools[0]));
        IERC20(srcToken).safeTransferFrom(msg.sender, address(this), amount);

        if (tokenOut == 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE) {
            (bool success,) = msg.sender.call{value: returnAmount}("");
            if (!success) revert NativeTransferFailed();
        } else {
            IERC20(tokenOut).safeTransfer(msg.sender, returnAmount);
        }
    }
}
