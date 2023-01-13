// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.16;

import {Test} from "forge-std/Test.sol";
import {DirectTakerExecutor} from "../../src/sample-executors/DirectTakerExecutor.sol";
import {DutchLimitOrderReactor, DutchLimitOrder, DutchInput} from "../../src/reactors/DutchLimitOrderReactor.sol";
import {MockERC20} from "../util/mock/MockERC20.sol";
import {OutputToken, InputToken, OrderInfo, ResolvedOrder, SignedOrder} from "../../src/base/ReactorStructs.sol";
import {ISignatureTransfer} from "permit2/src/interfaces/ISignatureTransfer.sol";
import {DeployPermit2} from "../util/DeployPermit2.sol";
import {OrderInfoBuilder} from "../util/OrderInfoBuilder.sol";
import {OutputsBuilder} from "../util/OutputsBuilder.sol";
import {PermitSignature} from "../util/PermitSignature.sol";
import {MockDirectTaker} from "../util/mock/users/MockDirectTaker.sol";

contract DirectTakerExecutorTest is Test, PermitSignature, DeployPermit2 {
    using OrderInfoBuilder for OrderInfo;

    address constant PROTOCOL_FEE_RECIPIENT = address(1);
    uint256 constant PROTOCOL_FEE_BPS = 5000;

    uint256 takerPrivateKey;
    uint256 makerPrivateKey;
    MockERC20 tokenIn;
    MockERC20 tokenOut;
    address taker;
    address maker;
    DirectTakerExecutor directTakerExecutor;
    DutchLimitOrderReactor dloReactor;
    ISignatureTransfer permit2;

    uint256 constant ONE = 10 ** 18;

    function setUp() public {
        vm.warp(1660671678);

        // Mock input/output tokens
        tokenIn = new MockERC20("Input", "IN", 18);
        tokenOut = new MockERC20("Output", "OUT", 18);

        // Mock taker
        takerPrivateKey = 0x12341234;
        taker = vm.addr(takerPrivateKey);
        makerPrivateKey = 0x12341235;
        maker = vm.addr(makerPrivateKey);

        // Instantiate relevant contracts
        directTakerExecutor = new DirectTakerExecutor(taker);
        permit2 = ISignatureTransfer(deployPermit2());
        dloReactor = new DutchLimitOrderReactor(address(permit2), PROTOCOL_FEE_BPS, PROTOCOL_FEE_RECIPIENT);

        // Do appropriate max approvals
        tokenOut.forceApprove(taker, address(directTakerExecutor), type(uint256).max);
        tokenIn.forceApprove(maker, address(permit2), type(uint256).max);
    }

    function testReactorCallback() public {
        uint256 inputAmount = ONE;
        uint256 outputAmount = ONE;

        OutputToken[] memory outputs = new OutputToken[](1);
        outputs[0].token = address(tokenOut);
        outputs[0].amount = outputAmount;
        ResolvedOrder[] memory resolvedOrders = new ResolvedOrder[](1);
        bytes memory sig = hex"1234";
        ResolvedOrder memory resolvedOrder = ResolvedOrder(
            OrderInfoBuilder.init(address(dloReactor)),
            InputToken(address(tokenIn), inputAmount, inputAmount),
            outputs,
            sig,
            keccak256(abi.encode(1))
        );
        resolvedOrders[0] = resolvedOrder;
        tokenIn.mint(address(directTakerExecutor), inputAmount);
        tokenOut.mint(taker, outputAmount);
        directTakerExecutor.reactorCallback(resolvedOrders, taker, bytes(""));
        assertEq(tokenIn.balanceOf(taker), inputAmount);
        assertEq(tokenOut.balanceOf(address(directTakerExecutor)), outputAmount);
    }

    function testReactorCallback2Outputs() public {
        uint256 inputAmount = ONE;

        OutputToken[] memory outputs = new OutputToken[](2);
        outputs[0].token = address(tokenOut);
        outputs[0].amount = ONE;
        outputs[1].token = address(tokenOut);
        outputs[1].amount = ONE * 2;
        ResolvedOrder[] memory resolvedOrders = new ResolvedOrder[](1);
        bytes memory sig = hex"1234";
        ResolvedOrder memory resolvedOrder = ResolvedOrder(
            OrderInfoBuilder.init(address(dloReactor)),
            InputToken(address(tokenIn), inputAmount, inputAmount),
            outputs,
            sig,
            keccak256(abi.encode(1))
        );
        resolvedOrders[0] = resolvedOrder;
        tokenOut.mint(taker, ONE * 3);
        tokenIn.mint(address(directTakerExecutor), inputAmount);
        directTakerExecutor.reactorCallback(resolvedOrders, taker, bytes(""));
        assertEq(tokenIn.balanceOf(taker), inputAmount);
        assertEq(tokenOut.balanceOf(address(directTakerExecutor)), ONE * 3);
    }

    function testExecute() public {
        DutchLimitOrder memory order = DutchLimitOrder({
            info: OrderInfoBuilder.init(address(dloReactor)).withOfferer(maker).withDeadline(block.timestamp + 100),
            startTime: block.timestamp - 100,
            endTime: block.timestamp + 100,
            input: DutchInput(address(tokenIn), ONE, ONE),
            // The total outputs will resolve to 1.5
            outputs: OutputsBuilder.singleDutch(address(tokenOut), ONE * 2, ONE, address(maker))
        });

        tokenIn.mint(maker, ONE);
        MockDirectTaker directTaker = new MockDirectTaker();
        DirectTakerExecutor executor = new DirectTakerExecutor(address(directTaker));

        tokenOut.mint(address(directTaker), ONE * 2);
        directTaker.approve(address(tokenOut), address(executor), type(uint256).max);

        directTaker.execute(
            dloReactor,
            SignedOrder(abi.encode(order), signOrder(makerPrivateKey, address(permit2), order)),
            address(executor),
            abi.encode(taker, dloReactor)
        );
        assertEq(tokenIn.balanceOf(maker), 0);
        assertEq(tokenIn.balanceOf(address(directTaker)), ONE);
        assertEq(tokenOut.balanceOf(address(maker)), 1500000000000000000);
        assertEq(tokenOut.balanceOf(address(directTaker)), 500000000000000000);
    }
}
