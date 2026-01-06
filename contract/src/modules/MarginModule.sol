// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {SignedMath} from "@openzeppelin/contracts/utils/math/SignedMath.sol";
import "./LiquidationModule.sol";

/// @notice Margin accounting (deposit/withdraw) plus margin checks.
/// @dev Day 1: 保证金模块
abstract contract MarginModule is LiquidationModule {

    /// @notice 存入保证金
    function deposit() external payable virtual nonReentrant {
        // TODO: 请实现此函数
        // 步骤:
        // 1. 增加用户的 margin
        // 2. 触发 MarginDeposited 事件
    }

    /// @notice 提取保证金
    /// @param amount 提取金额
    function withdraw(uint256 amount) external virtual nonReentrant {
        // TODO: 请实现此函数
        // 步骤:
        // 1. 检查 amount > 0
        // 2. 应用资金费 _applyFunding
        // 3. 检查 margin >= amount
        // 4. 检查提现后仍满足维持保证金 _ensureWithdrawKeepsMaintenance
        // 5. 减少 margin
        // 6. 转账给用户
        // 7. 触发 MarginWithdrawn 事件
    }

    /// @notice 计算持仓所需保证金
    function _calculatePositionMargin(int256 size) internal view returns (uint256) {
        // TODO: 请实现此函数
        // 公式: abs(size) * markPrice * initialMarginBps / 10000 / 1e18
        return 0;
    }

    /// @notice 获取用户待成交订单数量
    function _countPendingOrders(address trader) internal view returns (uint256) {
        return pendingOrderCount[trader];
    }

    /// @notice 计算最坏情况下所需保证金
    /// @dev 假设所有挂单都成交后的保证金需求
    function _calculateWorstCaseMargin(address trader) internal view returns (uint256) {
        // TODO: 请实现此函数
        // 步骤:
        // 1. 遍历买单链表，累计该用户的买单总量
        // 2. 遍历卖单链表，累计该用户的卖单总量
        // 3. 计算两种情况: 全部买单成交 vs 全部卖单成交
        // 4. 返回两者中较大的保证金需求
        return 0;
    }

    /// @notice 检查用户是否有足够保证金
    function _checkWorstCaseMargin(address trader) internal view {
        // TODO: 请实现此函数
        // 步骤:
        // 1. 计算 required = _calculateWorstCaseMargin(trader)
        // 2. 计算 marginBalance = margin + unrealizedPnl
        // 3. require(marginBalance >= required, "insufficient margin")
    }

    /// @notice 确保提现后仍满足维持保证金要求
    function _ensureWithdrawKeepsMaintenance(address trader, uint256 amount) internal view {
        // TODO: 请实现此函数
        // 步骤:
        // 1. 如果没有持仓，直接返回
        // 2. 计算提现后的 marginBalance
        // 3. 计算持仓价值和维持保证金
        // 4. require(marginBalance >= maintenance)
    }
}
