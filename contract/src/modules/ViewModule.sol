// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../core/ExchangeStorage.sol";

/// @notice Read-only helpers for offchain consumers.
/// @dev Day 1: 这些是视图函数，用于读取合约状态
abstract contract ViewModule is ExchangeStorage {
    
    /// @notice 获取订单详情
    /// @param id 订单 ID
    /// @return 订单结构体
    function getOrder(uint256 id) external view virtual returns (Order memory) {
        // TODO: 请实现此函数
        // 提示: 从 orders mapping 中读取订单
        revert("Not implemented");
    }

    /// @notice 获取用户可用保证金
    /// @param trader 用户地址
    /// @return 可用保证金数量
    function margin(address trader) external view virtual returns (uint256) {
        // TODO: 请实现此函数
        // 提示: 从 accounts[trader].freeMargin 读取
        revert("Not implemented");
    }

    /// @notice 获取用户持仓
    /// @param trader 用户地址
    /// @return 持仓结构体
    function getPosition(address trader) external view virtual returns (Position memory) {
        // TODO: 请实现此函数
        revert("Not implemented");
    }
}
