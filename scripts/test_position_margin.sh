#!/usr/bin/env bash
# 详细测试脚本 - 逐笔交易测试新的 position-based margin 系统

set -e

RPC_URL="http://localhost:8545"
EXCHANGE="0x5fbdb2315678afecb367f032d93f642f64180aa3"
ALICE_PK="0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80"
ALICE="0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266"
BOB_PK="0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d"
BOB="0x70997970C51812dc3A010C7d01b50e0d17dc79C8"

echo "=============================================="
echo "Position-Based Margin System Test"
echo "=============================================="
echo ""

# 辅助函数
get_free_margin() {
    local addr=$1
    cast call --rpc-url $RPC_URL $EXCHANGE "margin(address)(uint256)" $addr
}

get_position() {
    local addr=$1
    cast call --rpc-url $RPC_URL $EXCHANGE "getPosition(address)((int256,uint256,int256))" $addr
}

count_pending_orders() {
    local addr=$1
    # 简化：通过查看事件数量估算
    echo "0"
}

place_order_verbose() {
    local pk=$1
    local name=$2
    local is_buy=$3
    local price=$4
    local amount=$5
    
    echo ""
    echo ">>> $name 下单: Buy=$is_buy, Price=$price, Amount=$amount"
    echo "  Before:"
    local margin_before=$(get_free_margin $([ "$name" = "Alice" ] && echo $ALICE || echo $BOB))
    echo "    Free Margin: $(cast --to-unit $margin_before ether) ETH"
    
    local result=$(cast send --rpc-url $RPC_URL --private-key $pk $EXCHANGE \
        "placeOrder(bool,uint256,uint256,uint256)" $is_buy $price $amount 0 2>&1)
    
    if echo "$result" | grep -qi "error\|revert"; then
        echo "  ❌ 交易失败!"
        echo "$result" | grep -i "revert\|error" | head -3
        
        # 尝试获取详细错误
        if echo "$result" | grep -q "insufficient margin"; then
            echo ""
            echo "  🔍 详细分析："
            echo "    - 检查是否超过最大挂单数"
            echo "    - 检查 worst-case margin 计算"
            echo ""
        fi
        return 1
    else
        echo "  ✅ 交易成功"
        local margin_after=$(get_free_margin $([ "$name" = "Alice" ] && echo $ALICE || echo $BOB))
        echo "  After:"
        echo "    Free Margin: $(cast --to-unit $margin_after ether) ETH"
        
        local pos=$(get_position $([ "$name" = "Alice" ] && echo $ALICE || echo $BOB))
        echo "    Position:"
        echo "$pos" | head -3 | sed 's/^/      /'
        return 0
    fi
}

echo "Step 0: 初始状态"
echo "----------------------------------------"
echo "Alice Free Margin: $(cast --to-unit $(get_free_margin $ALICE) ether 2>/dev/null || echo '0') ETH"
echo "Bob Free Margin: $(cast --to-unit $(get_free_margin $BOB) ether 2>/dev/null || echo '0') ETH"

echo ""
echo "Step 1: 存款 500 ETH"
echo "----------------------------------------"
cast send --rpc-url $RPC_URL --private-key $ALICE_PK $EXCHANGE "deposit()" --value 500ether > /dev/null 2>&1
cast send --rpc-url $RPC_URL --private-key $BOB_PK $EXCHANGE "deposit()" --value 500ether > /dev/null 2>&1
echo "✅ 存款完成"
echo "Alice Free Margin: $(cast --to-unit $(get_free_margin $ALICE) ether) ETH"
echo "Bob Free Margin: $(cast --to-unit $(get_free_margin $BOB) ether) ETH"

echo ""
echo "Step 2: 设置 Index Price = 1500"
echo "----------------------------------------"
cast send --rpc-url $RPC_URL --private-key $ALICE_PK $EXCHANGE "updateIndexPrice(uint256)" 1500ether > /dev/null 2>&1
echo "✅ Index Price 已设置"

echo ""
echo "Step 3: Trade #1 - 1500 @ 0.01 ETH"
echo "----------------------------------------"
echo "理论保证金需求: 1500 * 0.01 * 1% = 0.15 ETH"
place_order_verbose $BOB_PK "Bob" false 1500ether 0.01ether
place_order_verbose $ALICE_PK "Alice" true 1500ether 0.01ether

echo ""
echo "⏰ Time Travel: +60 seconds"
cast rpc --rpc-url $RPC_URL evm_increaseTime 60 > /dev/null 2>&1
cast rpc --rpc-url $RPC_URL evm_mine > /dev/null 2>&1

echo ""
echo "Step 4: Trade #2 - 1520 @ 0.02 ETH"
echo "----------------------------------------"
echo "理论保证金需求: 1520 * 0.02 * 1% = 0.304 ETH"
place_order_verbose $BOB_PK "Bob" false 1520ether 0.02ether
if place_order_verbose $ALICE_PK "Alice" true 1520ether 0.02ether; then
    echo "  继续..."
else
    echo ""
    echo "=========================================="
    echo "Trade #2 失败 - 停止测试"
    echo "=========================================="
    echo ""
    echo "分析："
    echo "1. Alice 有 ~500 ETH 可用"
    echo "2. 需要 0.304 ETH 保证金"
    echo "3. 应该足够，但失败了"
    echo ""
    echo "可能原因："
    echo "- _calculateWorstCaseMargin 计算错误"
    echo "- pending orders 被重复计算"
    echo "- unrealized PnL 计算异常"
    echo ""
    exit 1
fi

echo ""
echo "⏰ Time Travel: +60 seconds"
cast rpc --rpc-url $RPC_URL evm_increaseTime 60 > /dev/null 2>&1
cast rpc --rpc-url $RPC_URL evm_mine > /dev/null 2>&1

echo ""
echo "Step 5: Trade #3 - 1490 @ 0.015 ETH"
echo "----------------------------------------"
echo "理论保证金需求: 1490 * 0.015 * 1% = 0.2235 ETH"
place_order_verbose $BOB_PK "Bob" false 1490ether 0.015ether
if place_order_verbose $ALICE_PK "Alice" true 1490ether 0.015ether; then
    echo "  继续..."
else
    echo ""
    echo "=========================================="
    echo "Trade #3 失败 - 停止测试"
    echo "=========================================="
    exit 1
fi

echo ""
echo "⏰ Time Travel: +60 seconds"
cast rpc --rpc-url $RPC_URL evm_increaseTime 60 > /dev/null 2>&1
cast rpc --rpc-url $RPC_URL evm_mine > /dev/null 2>&1

echo ""
echo "Step 6: Trade #4 - 1550 @ 0.03 ETH"
echo "----------------------------------------"
echo "理论保证金需求: 1550 * 0.03 * 1% = 0.465 ETH"
place_order_verbose $BOB_PK "Bob" false 1550ether 0.03ether
if place_order_verbose $ALICE_PK "Alice" true 1550ether 0.03ether; then
    echo "  继续..."
else
    echo ""
    echo "=========================================="
    echo "Trade #4 失败 - 停止测试"
    echo "=========================================="
    exit 1
fi

echo ""
echo "=============================================="
echo "✅ 所有 4 笔匹配交易都成功！"
echo "=============================================="
echo ""
echo "继续测试挂单..."

echo ""
echo "Step 7: 挂买单 - 1400 @ 0.01 ETH"
echo "----------------------------------------"
place_order_verbose $ALICE_PK "Alice" true 1400ether 0.01ether || true

echo ""
echo "Step 8: 挂买单 - 1450 @ 0.02 ETH"
echo "----------------------------------------"
place_order_verbose $ALICE_PK "Alice" true 1450ether 0.02ether || true

echo ""
echo "=============================================="
echo "测试完成"
echo "=============================================="
