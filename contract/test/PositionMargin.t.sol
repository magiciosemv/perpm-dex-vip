// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "../src/Exchange.sol";

contract PositionMarginTest is Test {
    MonadPerpExchange public exchange;
    
    address public alice = address(0x1);
    address public bob = address(0x2);
    
    uint256 constant INITIAL_DEPOSIT = 500 ether;
    uint256 constant INDEX_PRICE = 1500 ether;
    
    function setUp() public {
        // 部署交易所
        exchange = new MonadPerpExchange();
        
        // 授予角色
        exchange.grantRole(exchange.OPERATOR_ROLE(), address(this));
        
        // 给测试账户发送 ETH
        vm.deal(alice, 1000 ether);
        vm.deal(bob, 1000 ether);
        
        console.log("=== Setup Complete ===");
        console.log("Exchange:", address(exchange));
        console.log("Alice:", alice);
        console.log("Bob:", bob);
    }
    
    function testPositionBasedMarginSystem() public {
        console.log("\n===========================================");
        console.log("Position-Based Margin System Test");
        console.log("===========================================\n");
        
        // Step 1: 存款
        console.log("Step 1: Deposit 500 ETH each");
        console.log("-------------------------------------------");
        vm.prank(alice);
        exchange.deposit{value: INITIAL_DEPOSIT}();
        
        vm.prank(bob);
        exchange.deposit{value: INITIAL_DEPOSIT}();
        
        uint256 aliceMargin = exchange.margin(alice);
        uint256 bobMargin = exchange.margin(bob);
        console.log("Alice margin:", aliceMargin / 1e18, "ETH");
        console.log("Bob margin:", bobMargin / 1e18, "ETH");
        assertEq(aliceMargin, INITIAL_DEPOSIT);
        assertEq(bobMargin, INITIAL_DEPOSIT);
        
        // Step 2: 设置价格
        console.log("\nStep 2: Set Index Price = 1500 ETH");
        console.log("-------------------------------------------");
        exchange.updateIndexPrice(INDEX_PRICE);
        console.log("Mark Price:", exchange.markPrice() / 1e18, "ETH");
        
        // Step 3: Trade #1 - 1500 @ 0.01 ETH
        console.log("\nStep 3: Trade #1 - 1500 @ 0.01 ETH");
        console.log("-------------------------------------------");
        console.log("Expected margin: 1500 * 0.01 * 1% = 0.15 ETH");
        
        vm.prank(bob);
        uint256 bobOrderId1 = exchange.placeOrder(false, 1500 ether, 0.01 ether, 0);
        console.log("Bob placed sell order:", bobOrderId1);
        
        aliceMargin = exchange.margin(alice);
        console.log("Alice margin before buy:", aliceMargin / 1e18, "ETH");
        
        vm.prank(alice);
        uint256 aliceOrderId1 = exchange.placeOrder(true, 1500 ether, 0.01 ether, 0);
        
        // 检查仓位
        MonadPerpExchange.Position memory alicePos = exchange.getPosition(alice);
        MonadPerpExchange.Position memory bobPos = exchange.getPosition(bob);
        console.log("Alice position: size=", uint256(alicePos.size), "entry=", alicePos.entryPrice / 1e18);
        console.log("Bob position: size=", uint256(-bobPos.size), "entry=", bobPos.entryPrice / 1e18);
        
        // Step 4: Trade #2 - 1520 @ 0.02 ETH
        console.log("\nStep 4: Trade #2 - 1520 @ 0.02 ETH");
        console.log("-------------------------------------------");
        console.log("Expected margin: 1520 * 0.02 * 1% = 0.304 ETH");
        
        // Time travel
        vm.warp(block.timestamp + 60);
        vm.roll(block.number + 1);
        
        aliceMargin = exchange.margin(alice);
        console.log("Alice margin before trade #2:", aliceMargin / 1e18, "ETH");
        
        vm.prank(bob);
        uint256 bobOrderId2 = exchange.placeOrder(false, 1520 ether, 0.02 ether, 0);
        console.log("Bob placed sell order:", bobOrderId2);
        
        bobMargin = exchange.margin(bob);
        console.log("Bob margin after sell:", bobMargin / 1e18, "ETH");
        
        vm.prank(alice);
        try exchange.placeOrder(true, 1520 ether, 0.02 ether, 0) returns (uint256 orderId) {
            console.log("Alice placed buy order:", orderId);
            aliceMargin = exchange.margin(alice);
            console.log("Alice margin after buy:", aliceMargin / 1e18, "ETH");
        } catch Error(string memory reason) {
            console.log("FAILED: Alice buy order failed!");
            console.log("Reason:", reason);
            
            // 诊断信息
            aliceMargin = exchange.margin(alice);
            MonadPerpExchange.Position memory alicePos2 = exchange.getPosition(alice);
            console.log("\nDiagnostics:");
            console.log("  Alice margin:", aliceMargin / 1e18, "ETH");
            console.log("  Alice position size:", uint256(alicePos2.size));
            console.log("  Alice position entry:", alicePos2.entryPrice / 1e18, "ETH");
            
            // 计算理论保证金需求
            uint256 positionNotional = uint256(alicePos.size) * exchange.markPrice() / 1e18;
            uint256 positionMargin = positionNotional * exchange.initialMarginBps() / 10_000;
            console.log("  Current position margin needed:", positionMargin / 1e18, "ETH");
            
            uint256 newOrderNotional = 0.02 ether * 1520 ether / 1e18;
            uint256 newOrderMargin = newOrderNotional * exchange.initialMarginBps() / 10_000;
            console.log("  New order margin needed:", newOrderMargin / 1e18, "ETH");
            
            fail("Trade #2 failed");
        }
        
        // Step 5: Trade #3 - 1490 @ 0.015 ETH
        console.log("\nStep 5: Trade #3 - 1490 @ 0.015 ETH");
        console.log("-------------------------------------------");
        
        vm.warp(block.timestamp + 60);
        vm.roll(block.number + 1);
        
        vm.prank(bob);
        uint256 bobOrderId3 = exchange.placeOrder(false, 1490 ether, 0.015 ether, 0);
        console.log("Bob placed sell order:", bobOrderId3);
        
        vm.prank(alice);
        try exchange.placeOrder(true, 1490 ether, 0.015 ether, 0) returns (uint256 orderId) {
            console.log("Alice placed buy order:", orderId);
        } catch Error(string memory reason) {
            console.log("FAILED: Alice buy order failed!");
            console.log("Reason:", reason);
            fail("Trade #3 failed");
        }
        
        // Step 6: Trade #4 - 1550 @ 0.03 ETH
        console.log("\nStep 6: Trade #4 - 1550 @ 0.03 ETH");
        console.log("-------------------------------------------");
        
        vm.warp(block.timestamp + 60);
        vm.roll(block.number + 1);
        
        vm.prank(bob);
        uint256 bobOrderId4 = exchange.placeOrder(false, 1550 ether, 0.03 ether, 0);
        console.log("Bob placed sell order:", bobOrderId4);
        
        vm.prank(alice);
        try exchange.placeOrder(true, 1550 ether, 0.03 ether, 0) returns (uint256 orderId) {
            console.log("Alice placed buy order:", orderId);
        } catch Error(string memory reason) {
            console.log("FAILED: Alice buy order failed!");
            console.log("Reason:", reason);
            fail("Trade #4 failed");
        }
        
        console.log("\n===========================================");
        console.log("All first 4 trades completed successfully!");
        console.log("===========================================");
        
        // Step 7: Placing Open Orders (挂单)
        console.log("\nStep 7: Placing Open Orders");
        console.log("-------------------------------------------");
        
        vm.prank(alice);
        try exchange.placeOrder(true, 1400 ether, 0.01 ether, 0) returns (uint256 orderId) {
            console.log("Alice placed buy order @ 1400:", orderId);
        } catch Error(string memory reason) {
            console.log("FAILED: Alice buy @ 1400 failed!");
            console.log("Reason:", reason);
            fail("Alice buy order @ 1400 failed");
        }
        
        vm.prank(alice);
        try exchange.placeOrder(true, 1450 ether, 0.02 ether, 0) returns (uint256 orderId) {
            console.log("Alice placed buy order @ 1450:", orderId);
        } catch Error(string memory reason) {
            console.log("FAILED: Alice buy @ 1450 failed!");
            console.log("Reason:", reason);
            fail("Alice buy order @ 1450 failed");
        }
        
        vm.prank(bob);
        try exchange.placeOrder(false, 1600 ether, 0.015 ether, 0) returns (uint256 orderId) {
            console.log("Bob placed sell order @ 1600:", orderId);
        } catch Error(string memory reason) {
            console.log("FAILED: Bob sell @ 1600 failed!");
            console.log("Reason:", reason);
            fail("Bob sell order @ 1600 failed");
        }
        
        vm.prank(bob);
        try exchange.placeOrder(false, 1650 ether, 0.025 ether, 0) returns (uint256 orderId) {
            console.log("Bob placed sell order @ 1650:", orderId);
        } catch Error(string memory reason) {
            console.log("FAILED: Bob sell @ 1650 failed!");
            console.log("Reason:", reason);
            fail("Bob sell order @ 1650 failed");
        }
        
        // Step 8: Creating Partial Fills
        console.log("\nStep 8: Creating Partial Fills");
        console.log("-------------------------------------------");
        
        // Scenario 1: Alice Buy 0.01 @ 1580, Bob Sell 0.003 @ 1580
        vm.prank(alice);
        try exchange.placeOrder(true, 1580 ether, 0.01 ether, 0) returns (uint256 orderId) {
            console.log("Alice placed buy order @ 1580:", orderId);
        } catch Error(string memory reason) {
            console.log("FAILED: Alice buy @ 1580 failed!");
            console.log("Reason:", reason);
            fail("Alice buy order @ 1580 failed");
        }
        
        vm.prank(bob);
        try exchange.placeOrder(false, 1580 ether, 0.003 ether, 0) returns (uint256 orderId) {
            console.log("Bob placed sell order @ 1580:", orderId);
        } catch Error(string memory reason) {
            console.log("FAILED: Bob sell @ 1580 failed!");
            console.log("Reason:", reason);
            fail("Bob sell @ 1580 failed");
        }
        
        // Scenario 2: Bob Sell 0.02 @ 1620, Alice Buy 0.005 @ 1620
        vm.prank(bob);
        try exchange.placeOrder(false, 1620 ether, 0.02 ether, 0) returns (uint256 orderId) {
            console.log("Bob placed sell order @ 1620:", orderId);
        } catch Error(string memory reason) {
            console.log("FAILED: Bob sell @ 1620 failed!");
            console.log("Reason:", reason);
            fail("Bob sell @ 1620 failed");
        }
        
        vm.prank(alice);
        try exchange.placeOrder(true, 1620 ether, 0.005 ether, 0) returns (uint256 orderId) {
            console.log("Alice placed buy order @ 1620:", orderId);
        } catch Error(string memory reason) {
            console.log("FAILED: Alice buy @ 1620 failed!");
            console.log("Reason:", reason);
            fail("Alice buy @ 1620 failed");
        }
        
        console.log("\n===========================================");
        console.log("ALL 8 SEED.SH SCENARIOS COMPLETED!");
        console.log("===========================================");
        
        // 最终检查
        aliceMargin = exchange.margin(alice);
        bobMargin = exchange.margin(bob);
        MonadPerpExchange.Position memory aliceFinalPos = exchange.getPosition(alice);
        MonadPerpExchange.Position memory bobFinalPos = exchange.getPosition(bob);
        
        console.log("\nFinal State:");
        console.log("Alice:");
        console.log("  Margin:", aliceMargin / 1e18, "ETH");
        console.log("  Position size:", uint256(aliceFinalPos.size));
        console.log("  Entry price:", aliceFinalPos.entryPrice / 1e18, "ETH");
        console.log("Bob:");
        console.log("  Margin:", bobMargin / 1e18, "ETH");  
        console.log("  Position size:", uint256(-bobFinalPos.size));
        console.log("  Entry price:", bobFinalPos.entryPrice / 1e18, "ETH");
    }
    
    function testWorstCaseMarginCalculation() public {
        console.log("\n===========================================");
        console.log("Worst-Case Margin Calculation Test");
        console.log("===========================================\n");
        
        // Setup
        vm.prank(alice);
        exchange.deposit{value: INITIAL_DEPOSIT}();
        exchange.updateIndexPrice(INDEX_PRICE);
        
        console.log("Step 1: Place multiple pending orders");
        console.log("-------------------------------------------");
        
        // Alice 挂 3 个买单
        vm.startPrank(alice);
        exchange.placeOrder(true, 1400 ether, 0.01 ether, 0);
        console.log("Placed buy order: 1400 @ 0.01");
        
        uint256 margin1 = exchange.margin(alice);
        console.log("Margin after 1st order:", margin1 / 1e18, "ETH");
        
        exchange.placeOrder(true, 1450 ether, 0.02 ether, 0);
        console.log("Placed buy order: 1450 @ 0.02");
        
        uint256 margin2 = exchange.margin(alice);
        console.log("Margin after 2nd order:", margin2 / 1e18, "ETH");
        
        try exchange.placeOrder(true, 1480 ether, 0.015 ether, 0) {
            console.log("Placed buy order: 1480 @ 0.015");
            uint256 margin3 = exchange.margin(alice);
            console.log("Margin after 3rd order:", margin3 / 1e18, "ETH");
        } catch Error(string memory reason) {
            console.log("FAILED: 3rd order failed!");
            console.log("Reason:", reason);
        }
        
        vm.stopPrank();
    }
}
