// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {SignedMath} from "@openzeppelin/contracts/utils/math/SignedMath.sol";
import "../core/ExchangeStorage.sol";

/// @notice Funding settlement and shared math helpers.
/// @dev Day 5: 资金费率计算与结算
abstract contract FundingModule is ExchangeStorage {

    /// @notice 结算全局资金费率
    /// @dev 每隔 fundingInterval 调用一次，更新 cumulativeFundingRate
    function settleFunding() public virtual {
        // TODO: 请实现此函数
        // 步骤:
        // 1. 检查是否已过 fundingInterval
        // 2. 计算 premium = (markPrice - indexPrice) / indexPrice
        // 3. 应用利率和钳位
        // 4. 更新 cumulativeFundingRate
        // 5. 更新 lastFundingTime
        // 6. 触发 FundingUpdated 事件
    }

    /// @notice 结算特定用户的资金费
    /// @param trader 用户地址
    function settleUserFunding(address trader) external virtual {
        _applyFunding(trader);
    }

    /// @notice 设置资金费率参数 (仅管理员)
    function setFundingParams(uint256 interval, int256 maxRatePerInterval) external virtual onlyRole(DEFAULT_ADMIN_ROLE) {
        require(interval > 0, "interval=0");
        require(maxRatePerInterval >= 0, "cap<0");
        fundingInterval = interval;
        maxFundingRatePerInterval = maxRatePerInterval;
        emit FundingParamsUpdated(interval, maxRatePerInterval);
    }

    /// @notice 应用资金费到用户账户
    /// @dev 内部函数，计算用户应付/应收的资金费
    function _applyFunding(address trader) internal virtual {
        // TODO: 请实现此函数
        // 步骤:
        // 1. 获取用户持仓
        // 2. 如果持仓为 0，更新 lastFundingIndex 并返回
        // 3. 调用 settleFunding() 确保全局费率最新
        // 4. 计算 diff = cumulativeFundingRate - lastFundingIndex[trader]
        // 5. 计算 payment = size * markPrice * diff / 1e36
        // 6. 更新用户 margin
        // 7. 更新 lastFundingIndex[trader]
        // 8. 触发 FundingPaid 事件
    }

    /// @notice 计算未实现盈亏
    /// @param p 持仓结构体
    /// @return 未实现盈亏 (可为负)
    function _unrealizedPnl(Position memory p) internal view returns (int256) {
        // TODO: 请实现此函数
        // 公式: (markPrice - entryPrice) * size / 1e18
        // 注意: 空头方向需要取反
        return 0;
    }

    /// @notice 钩子：子模块可覆盖以在操作前拉取最新价格
    function _pullLatestPrice() internal virtual {}
}
