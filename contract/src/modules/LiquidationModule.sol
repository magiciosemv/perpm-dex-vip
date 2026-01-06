// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {SignedMath} from "@openzeppelin/contracts/utils/math/SignedMath.sol";
import "./PricingModule.sol";

/// @notice Liquidation checks and execution.
/// @dev Day 6: 清算模块
abstract contract LiquidationModule is PricingModule {

    /// @notice 检查用户是否可被清算
    /// @param trader 用户地址
    /// @return 是否可清算
    function canLiquidate(address trader) public view virtual returns (bool) {
        // TODO: 请实现此函数
        // 步骤:
        // 1. 获取用户持仓，如果为 0 返回 false
        // 2. 计算当前标记价下的未实现盈亏
        // 3. 计算 marginBalance = margin + unrealizedPnl
        // 4. 计算 maintenance = positionValue * (maintenanceMarginBps + liquidationFeeBps) / 10000
        // 5. 返回 marginBalance < maintenance
        return false;
    }

    /// @notice 清算用户 (在 OrderBookModule 中实现具体逻辑)
    function liquidate(address trader) external virtual nonReentrant {
        // 将在 OrderBookModule 中实现
    }

    /// @notice 清除用户所有挂单
    /// @param trader 用户地址
    function _clearTraderOrders(address trader) internal returns (uint256 freedLocked) {
        // TODO: 请实现此函数
        // 步骤:
        // 1. 遍历买单链表，删除该用户的订单
        // 2. 遍历卖单链表，删除该用户的订单
        // 3. 触发 OrderRemoved 事件
        return 0;
    }

    /// @notice 从链表中删除指定用户的订单
    function _removeOrders(uint256 headId, address trader) internal returns (uint256 newHead) {
        // TODO: 请实现此函数
        return headId;
    }

    uint256 constant SCALE = 1e18;

    /// @notice 执行交易
    /// @dev Day 3: 撮合成交核心函数
    function _executeTrade(
        address buyer,
        address seller,
        uint256 buyOrderId,
        uint256 sellOrderId,
        uint256 amount,
        uint256 price
    ) internal virtual {
        // TODO: 请实现此函数
        // 步骤:
        // 1. 对买卖双方应用资金费 _applyFunding
        // 2. 更新买方持仓 _updatePosition(buyer, true, amount, price)
        // 3. 更新卖方持仓 _updatePosition(seller, false, amount, price)
        // 4. 触发 TradeExecuted 事件
    }

    /// @notice 更新用户持仓
    /// @dev Day 3: 持仓更新核心函数
    function _updatePosition(
        address trader,
        bool isBuy,
        uint256 amount,
        uint256 tradePrice
    ) internal virtual {
        // TODO: 请实现此函数
        // 步骤:
        // 1. 获取用户当前持仓
        // 2. 判断是加仓还是减仓/平仓
        // 3. 加仓: 计算加权平均入场价，增加持仓
        // 4. 减仓: 计算已实现盈亏，更新 margin
        // 5. 更新持仓 size 和 entryPrice
    }
}
