// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.16;

import {Test} from "forge-std/Test.sol";
import {OrderInfo, InputToken, OutputToken, ResolvedOrder, SignedOrder} from "../../src/base/ReactorStructs.sol";
import {ReactorEvents} from "../../src/base/ReactorEvents.sol";
import {MockERC20} from "../util/mock/MockERC20.sol";
import {LimitOrder, LimitOrderLib} from "../../src/lib/LimitOrderLib.sol";
import {ISignatureTransfer} from "permit2/src/interfaces/ISignatureTransfer.sol";
import {DeployPermit2} from "../util/DeployPermit2.sol";
import {MockValidationContract} from "../util/mock/MockValidationContract.sol";
import {MockMaker} from "../util/mock/users/MockMaker.sol";
import {MockFillContract} from "../util/mock/MockFillContract.sol";
import {LimitOrderReactor, LimitOrder} from "../../src/reactors/LimitOrderReactor.sol";
import {BaseReactor} from "../../src/reactors/BaseReactor.sol";
import {OrderInfoBuilder} from "../util/OrderInfoBuilder.sol";
import {OutputsBuilder} from "../util/OutputsBuilder.sol";
import {PermitSignature} from "../util/PermitSignature.sol";
import {BaseReactorTest} from '../base/BaseReactor.t.sol';

contract LimitOrderReactorTest is PermitSignature, DeployPermit2, BaseReactorTest {
    using OrderInfoBuilder for OrderInfo;
    using LimitOrderLib for LimitOrder;

    error InvalidSigner();

    string constant LIMIT_ORDER_TYPE_NAME = "LimitOrder";
    address constant PROTOCOL_FEE_RECIPIENT = address(1);
    uint256 constant PROTOCOL_FEE_BPS = 5000;

    MockValidationContract validationContract;
    function setUp() public override {
        fillContract = new MockFillContract();
        tokenIn = new MockERC20("Input", "IN", 18);
        tokenOut = new MockERC20("Output", "OUT", 18);
        makerPrivateKey = 0x12341234;
        maker = vm.addr(makerPrivateKey);
        validationContract = new MockValidationContract();
        validationContract.setValid(true);
        tokenIn.mint(address(maker), ONE);
        tokenOut.mint(address(fillContract), ONE);
        permit2 = deployPermit2();
        createReactor();
    }

    function name() public pure override returns (string memory) {
        return "LimitOrderReactor";
    }

    function createReactor() public override returns (BaseReactor) {
        reactor = new LimitOrderReactor(address(permit2), PROTOCOL_FEE_BPS, PROTOCOL_FEE_RECIPIENT);
        return reactor;
    }

    /// @dev Create and return a basic LimitOrder along with its signature, hash, and orderInfo
    function createAndSignOrder(uint256 inputAmount, uint256 outputAmount) public view override returns (SignedOrder memory signedOrder, bytes32 orderHash, OrderInfo memory orderInfo) {
        LimitOrder memory order = LimitOrder({
            info: OrderInfoBuilder.init(address(reactor)).withOfferer(address(maker)),
            input: InputToken(address(tokenIn), inputAmount, inputAmount),
            outputs: OutputsBuilder.single(address(tokenOut), outputAmount, address(maker))
        });
        orderHash = order.hash();
        return (SignedOrder(abi.encode(order), signOrder(makerPrivateKey, address(permit2), order)), orderHash, order.info);
    }

    function createAndSignBatchOrders(uint256[] memory inputAmounts, uint256[][] memory outputAmounts) public view override returns (SignedOrder[] memory signedOrders, bytes32[] memory orderHashes, OrderInfo[] memory orderInfos) {
        signedOrders = new SignedOrder[](inputAmounts.length);
        orderHashes = new bytes32[](inputAmounts.length);
        orderInfos = new OrderInfo[](inputAmounts.length);
        for (uint256 i = 0; i < inputAmounts.length; i++) {
            LimitOrder memory order = LimitOrder({
                info: OrderInfoBuilder.init(address(reactor)).withOfferer(address(maker)).withNonce(i),
                input: InputToken(address(tokenIn), inputAmounts[i], inputAmounts[i]),
                // No multiple outputs supported for limitOrder
                outputs: OutputsBuilder.single(address(tokenOut), outputAmounts[i][0], address(maker))
            });
            orderHashes[i] = order.hash();
            orderInfos[i] = order.info;
            signedOrders[i] = SignedOrder(abi.encode(order), signOrder(makerPrivateKey, address(permit2), order));
        }
        return (signedOrders, orderHashes, orderInfos);
    }

    function testExecuteWithValidationContract() public {
        tokenIn.forceApprove(maker, address(permit2), ONE);
        LimitOrder memory order = LimitOrder({
            info: OrderInfoBuilder.init(address(reactor)).withOfferer(address(maker)).withValidationContract(
                address(validationContract)
                ),
            input: InputToken(address(tokenIn), ONE, ONE),
            outputs: OutputsBuilder.single(address(tokenOut), ONE, address(maker))
        });
        bytes32 orderHash = order.hash();
        bytes memory sig = signOrder(makerPrivateKey, address(permit2), order);

        uint256 makerInputBalanceStart = tokenIn.balanceOf(address(maker));
        uint256 fillContractInputBalanceStart = tokenIn.balanceOf(address(fillContract));
        uint256 makerOutputBalanceStart = tokenOut.balanceOf(address(maker));
        uint256 fillContractOutputBalanceStart = tokenOut.balanceOf(address(fillContract));

        vm.expectEmit(false, false, false, true, address(reactor));
        emit Fill(orderHash, address(this), maker, order.info.nonce);

        reactor.execute(SignedOrder(abi.encode(order), sig), address(fillContract), bytes(""));

        assertEq(tokenIn.balanceOf(address(maker)), makerInputBalanceStart - ONE);
        assertEq(tokenIn.balanceOf(address(fillContract)), fillContractInputBalanceStart + ONE);
        assertEq(tokenOut.balanceOf(address(maker)), makerOutputBalanceStart + ONE);
        assertEq(tokenOut.balanceOf(address(fillContract)), fillContractOutputBalanceStart - ONE);
    }

    function testExecuteWithValidationContractChangeSig() public {
        tokenIn.forceApprove(maker, address(permit2), ONE);
        LimitOrder memory order = LimitOrder({
            info: OrderInfoBuilder.init(address(reactor)).withOfferer(address(maker)).withValidationContract(
                address(validationContract)
                ),
            input: InputToken(address(tokenIn), ONE, ONE),
            outputs: OutputsBuilder.single(address(tokenOut), ONE, address(maker))
        });
        bytes memory sig = signOrder(makerPrivateKey, address(permit2), order);

        // change validation contract, ensure that sig fails
        order.info.validationContract = address(0);

        vm.expectRevert(InvalidSigner.selector);
        reactor.execute(SignedOrder(abi.encode(order), sig), address(fillContract), bytes(""));
    }

    function testExecuteWithFeeOutput() public {
        tokenIn.forceApprove(maker, address(permit2), ONE);
        LimitOrder memory order = LimitOrder({
            info: OrderInfoBuilder.init(address(reactor)).withOfferer(address(maker)),
            input: InputToken(address(tokenIn), ONE, ONE),
            outputs: OutputsBuilder.single(address(tokenOut), ONE, address(maker))
        });
        order.outputs[0].isFeeOutput = true;
        bytes32 orderHash = order.hash();
        bytes memory sig = signOrder(makerPrivateKey, address(permit2), order);

        uint256 makerInputBalanceStart = tokenIn.balanceOf(address(maker));
        uint256 fillContractInputBalanceStart = tokenIn.balanceOf(address(fillContract));
        uint256 makerOutputBalanceStart = tokenOut.balanceOf(address(maker));
        uint256 fillContractOutputBalanceStart = tokenOut.balanceOf(address(fillContract));

        vm.expectEmit(false, false, false, true, address(reactor));
        emit Fill(orderHash, address(this), maker, order.info.nonce);

        reactor.execute(SignedOrder(abi.encode(order), sig), address(fillContract), bytes(""));

        assertEq(tokenIn.balanceOf(address(maker)), makerInputBalanceStart - ONE);
        assertEq(tokenIn.balanceOf(address(fillContract)), fillContractInputBalanceStart + ONE);
        assertEq(tokenOut.balanceOf(address(maker)), makerOutputBalanceStart);
        assertEq(tokenOut.balanceOf(address(fillContract)), fillContractOutputBalanceStart - ONE);
    }

    function testExecuteWithFeeOutputChangeSig() public {
        tokenIn.forceApprove(maker, address(permit2), ONE);
        LimitOrder memory order = LimitOrder({
            info: OrderInfoBuilder.init(address(reactor)).withOfferer(address(maker)),
            input: InputToken(address(tokenIn), ONE, ONE),
            outputs: OutputsBuilder.single(address(tokenOut), ONE, address(maker))
        });
        order.outputs[0].isFeeOutput = true;
        bytes memory sig = signOrder(makerPrivateKey, address(permit2), order);

        order.outputs[0].isFeeOutput = false;

        vm.expectRevert(InvalidSigner.selector);
        reactor.execute(SignedOrder(abi.encode(order), sig), address(fillContract), bytes(""));
    }

    function testExecuteNonceReuse() public {
        tokenIn.forceApprove(maker, address(permit2), ONE);
        uint256 nonce = 1234;
        LimitOrder memory order = LimitOrder({
            info: OrderInfoBuilder.init(address(reactor)).withOfferer(address(maker)).withNonce(nonce),
            input: InputToken(address(tokenIn), ONE, ONE),
            outputs: OutputsBuilder.single(address(tokenOut), ONE, address(maker))
        });
        bytes memory sig = signOrder(makerPrivateKey, address(permit2), order);
        reactor.execute(SignedOrder(abi.encode(order), sig), address(fillContract), bytes(""));

        tokenIn.mint(address(maker), ONE * 2);
        tokenOut.mint(address(fillContract), ONE * 2);
        tokenIn.forceApprove(maker, address(permit2), ONE * 2);
        LimitOrder memory order2 = LimitOrder({
            info: OrderInfoBuilder.init(address(reactor)).withOfferer(address(maker)).withNonce(nonce),
            input: InputToken(address(tokenIn), ONE * 2, ONE * 2),
            outputs: OutputsBuilder.single(address(tokenOut), ONE * 2, address(maker))
        });
        bytes memory sig2 = signOrder(makerPrivateKey, address(permit2), order2);
        vm.expectRevert(InvalidNonce.selector);
        reactor.execute(SignedOrder(abi.encode(order2), sig2), address(fillContract), bytes(""));
    }

    function testExecuteInsufficientPermit() public {
        tokenIn.forceApprove(maker, address(permit2), ONE);
        LimitOrder memory order = LimitOrder({
            info: OrderInfoBuilder.init(address(reactor)).withOfferer(address(maker)),
            input: InputToken(address(tokenIn), ONE, ONE),
            outputs: OutputsBuilder.single(address(tokenOut), ONE, address(maker))
        });

        bytes32 orderHash = order.hash();
        bytes memory sig = signOrder(
            makerPrivateKey, address(permit2), order.info, address(tokenIn), ONE / 2, LIMIT_ORDER_TYPE_HASH, orderHash
        );

        vm.expectRevert(InvalidSigner.selector);
        reactor.execute(SignedOrder(abi.encode(order), sig), address(fillContract), bytes(""));
    }

    function testExecuteIncorrectSpender() public {
        tokenIn.forceApprove(maker, address(permit2), ONE);
        LimitOrder memory order = LimitOrder({
            info: OrderInfoBuilder.init(address(reactor)).withOfferer(address(maker)),
            input: InputToken(address(tokenIn), ONE, ONE),
            outputs: OutputsBuilder.single(address(tokenOut), ONE, address(maker))
        });

        bytes32 orderHash = order.hash();
        bytes memory sig = signOrder(
            makerPrivateKey,
            address(permit2),
            OrderInfoBuilder.init(address(this)).withOfferer(address(maker)),
            order.input.token,
            order.input.amount,
            LIMIT_ORDER_TYPE_HASH,
            orderHash
        );

        vm.expectRevert(InvalidSigner.selector);
        reactor.execute(SignedOrder(abi.encode(order), sig), address(fillContract), bytes(""));
    }

    function testExecuteIncorrectToken() public {
        tokenIn.forceApprove(maker, address(permit2), ONE);
        LimitOrder memory order = LimitOrder({
            info: OrderInfoBuilder.init(address(reactor)).withOfferer(address(maker)),
            input: InputToken(address(tokenIn), ONE, ONE),
            outputs: OutputsBuilder.single(address(tokenOut), ONE, address(maker))
        });

        bytes32 orderHash = order.hash();
        bytes memory sig = signOrder(
            makerPrivateKey, address(permit2), order.info, address(tokenOut), ONE, LIMIT_ORDER_TYPE_HASH, orderHash
        );
        vm.expectRevert(InvalidSigner.selector);
        reactor.execute(SignedOrder(abi.encode(order), sig), address(fillContract), bytes(""));
    }
}
