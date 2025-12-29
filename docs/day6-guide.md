# Day 6 - 资金费率机制（Funding Rate）

本节目标：实现币安风格的资金费率机制，包括全局 `settleFunding()` 计算费率，用户级 `_applyFunding()` 结算资金费，以及 Keeper 定时触发结算。

---

## 1) 学习目标（面向学生）

完成本节后，你将能够：

- 理解永续合约资金费率的作用：锚定现货价格。
- 实现 `settleFunding()`：币安公式计算资金费率。
- 实现 `_applyFunding()`：根据用户持仓计算应付/应收资金费。
- 实现 `_unrealizedPnl()`：计算未实现盈亏。
- 配置 Keeper 定时触发资金费率结算。

---

## 2) 前置准备（必须满足）

Day 6 建立在 Day 5 之上，请先确认：

- Day 1-5 功能已实现
- `updateIndexPrice()` 和 `_calculateMarkPrice()` 可用

你可以先跑：

```bash
cd contract
forge test --match-contract "Day1|Day2|Day3|Day4" -v
```

---

## 3) 当天完成标准（Definition of Done）

- `forge test --match-contract Day6FundingTest -vvv` 全部通过（6 个测试）
- 多头在 mark > index 时支付资金费
- 空头在 mark < index 时支付资金费
- 资金费按 interval 累计
- 资金费有上限保护（maxFundingRatePerInterval）
- 前端显示"未结资金费"与"强平价格"

---

## 4) 开发步骤（边理解边写代码）

### Step 1: 理解资金费率机制

永续合约没有到期日，需要"资金费率"让价格锚定现货：

| 情况 | 资金费方向 | 目的 |
|------|-----------|------|
| Mark > Index | 多头付空头 | 压低合约价格 |
| Mark < Index | 空头付多头 | 抬高合约价格 |

**币安公式：**

```
FundingRate = PremiumIndex + clamp(InterestRate - PremiumIndex, -0.05%, +0.05%)
PremiumIndex = (MarkPrice - IndexPrice) / IndexPrice
InterestRate = 0.01% (固定)
```

---

### Step 2: 实现 `settleFunding()`

修改：

- `contract/src/modules/FundingModule.sol`

```solidity
function settleFunding() public virtual {
    // Step 1: 检查是否已过 fundingInterval
    if (block.timestamp < lastFundingTime + fundingInterval) return;
    if (indexPrice == 0) return;

    // Step 2: 计算 Premium Index
    int256 mark = int256(markPrice);
    int256 index = int256(indexPrice);
    int256 premiumIndex = ((mark - index) * 1e18) / index;

    // Step 3: 应用利率和钳位
    int256 interestRate = 1e14; // 0.01%
    int256 clampRange = 5e14;   // 0.05%
    
    int256 diff = interestRate - premiumIndex;
    int256 clamped = diff;
    if (diff > clampRange) clamped = clampRange;
    if (diff < -clampRange) clamped = -clampRange;
    
    int256 rate = premiumIndex + clamped;

    // Step 4: 应用全局上限
    if (maxFundingRatePerInterval > 0) {
        if (rate > maxFundingRatePerInterval) rate = maxFundingRatePerInterval;
        if (rate < -maxFundingRatePerInterval) rate = -maxFundingRatePerInterval;
    }

    // Step 5: 累加到全局费率
    cumulativeFundingRate += rate;
    lastFundingTime = block.timestamp;

    // Step 6: 触发事件
    emit FundingUpdated(cumulativeFundingRate, block.timestamp);
}
```

---

### Step 3: 实现 `_applyFunding()`

```solidity
function _applyFunding(address trader) internal virtual {
    Account storage a = accounts[trader];
    Position storage p = a.position;
    
    // Step 1: 无持仓则更新 index 并返回
    if (p.size == 0) {
        lastFundingIndex[trader] = cumulativeFundingRate;
        return;
    }

    // Step 2: 确保全局费率最新
    settleFunding();
    
    // Step 3: 计算费率差值
    int256 diff = cumulativeFundingRate - lastFundingIndex[trader];
    if (diff == 0) return;

    // Step 4: 计算应付金额
    // Payment = Size * MarkPrice * Diff / 1e36
    int256 payment = (int256(p.size) * int256(markPrice) * diff) / 1e36;
    
    // Step 5: 更新用户保证金
    uint256 free = a.freeMargin;
    if (payment > 0) {
        // 需要支付
        uint256 pay = uint256(payment);
        if (pay > free) {
            uint256 debt = pay - free;
            a.freeMargin = 0;
            p.realizedPnl -= int256(debt);
        } else {
            a.freeMargin = free - pay;
        }
    } else if (payment < 0) {
        // 获得收入
        uint256 credit = uint256(-payment);
        a.freeMargin = free + credit;
    }
    
    // Step 6: 更新用户费率 index
    lastFundingIndex[trader] = cumulativeFundingRate;
    
    // Step 7: 触发事件
    emit FundingPaid(trader, payment);
}

/**
 * 外部结算接口：手动为特定账户结算资金费
 */
function settleUserFunding(address trader) external virtual {
    _applyFunding(trader);
}

/**
 * 参数更新接口：设置结算周期与费率上限 (仅管理员)
 */
function setFundingParams(uint256 interval, int256 maxRatePerInterval) external virtual onlyRole(DEFAULT_ADMIN_ROLE) {
    require(interval > 0, "interval=0");
    require(maxRatePerInterval >= 0, "cap<0");
    fundingInterval = interval;
    maxFundingRatePerInterval = maxRatePerInterval;
    emit FundingParamsUpdated(interval, maxRatePerInterval);
}
```

---

### Step 4: 实现 `_unrealizedPnl()`

```solidity
function _unrealizedPnl(Position memory p) internal view returns (int256) {
    if (p.size == 0) return 0;
    int256 pnlPerUnit = int256(markPrice) - int256(p.entryPrice);
    return (pnlPerUnit * p.size) / 1e18;
}
```

---

### Step 5: 配置 Keeper 定时结算

修改：

- `keeper/src/services/FundingKeeper.ts`（如果存在）

或在现有 Keeper 中添加：

```typescript
// 每小时触发一次资金费率结算
async function settleFunding() {
    const hash = await walletClient.writeContract({
        address: EXCHANGE_ADDRESS,
        abi: EXCHANGE_ABI,
        functionName: 'settleFunding',
        args: []
    });
    console.log('[FundingKeeper] Settlement tx:', hash);
}

setInterval(settleFunding, 60 * 60 * 1000); // 1 hour
```

---

### Step 6: 前端资金费与强平展示

#### 6.1 在 Store 中计算预测资金费率
在 `exchangeStore.tsx` 的 `refresh` 中增加币安公式计算：

```typescript
const m = Number(formatEther(mark));
const i = Number(formatEther(index));
const premiumIndex = (m - i) / i;
const interestRate = 0.0001; // 0.01%
const clampRange = 0.0005;   // 0.05%

let diff = interestRate - premiumIndex;
if (diff > clampRange) diff = clampRange;
if (diff < -clampRange) diff = -clampRange;

this.fundingRate = premiumIndex + diff;
```

#### 6.2 在组件中计算强平价格
在 `Positions.tsx` 中，根据保证金和持仓计算预估强平价：

```typescript
// 多头强平价公式 (简化版): LiqPrice = (Entry*Size - Margin) / (Size * (1 - MM))
const mmRatio = 0.005; // 0.5% 维持保证金
const liqPrice = (entry * size - effectiveMargin) / (size * (1 - mmRatio));
```

---

## 5) 解析：为什么这样写

### 5.1 为什么用累计费率（cumulativeFundingRate）？

如果用户不频繁交易，结算时只需计算一次差值：

```
Payment = Size × Mark × (currentRate - lastUserRate)
```

### 5.2 资金费公式详解

币安公式分解：

```
Rate = Premium + clamp(Interest - Premium, -0.05%, +0.05%)
```

| 场景 | Premium | Interest | Rate | 效果 |
|------|---------|----------|------|------|
| 合约溢价 10% | +0.10 | +0.0001 | ~+0.10 | 多头付空头 |
| 合约折价 5% | -0.05 | +0.0001 | ~-0.05 | 空头付多头 |
| 价格平衡 | 0 | +0.0001 | +0.0001 | 多头付空头（极小） |

### 5.3 为什么需要 maxFundingRatePerInterval？

极端行情下，资金费可能过大导致用户瞬间爆仓。设置上限保护用户。

### 5.4 Payment 计算精度

```solidity
Payment = (Size × Mark × Diff) / 1e36
```

- Size: 1e18 精度
- Mark: 1e18 精度  
- Diff: 1e18 精度
- 结果: (1e18 × 1e18 × 1e18) / 1e36 = 1e18 (MON)

---

## 6) 测试与验证

### 6.1 运行合约测试

```bash
cd contract
forge test --match-contract Day6FundingTest -vvv
```

通过标准：6 个测试全部 `PASS`

测试用例覆盖：

1. `testFundingFlowsFromLongToShort` - Mark 高于 Index，多头付空头
2. `testSettleFundingNoIndexPriceSkips` - Index 为 0 时跳过
3. `testFundingAccumulatesAcrossIntervals` - 跨 interval 累加
4. `testFundingSequentialEntrantsAccruesCorrectly` - 多用户分批进入
5. `testFundingCapAndIntervalChange` - 费率上限保护
6. `testFundingShortPaysWhenMarkBelowIndex` - 空头付多头

### 6.2 前端验证

```bash
./quickstart.sh
```

打开 `http://localhost:3000`，验证：

1. 下单成交后，等待 1 小时（或修改 interval 为短时间测试）
2. 观察 Positions 组件显示资金费变化
3. 确认多头/空头保证金按预期变化

---

## 7) 常见问题（排错思路）

1. **测试报错 "funding not accumulated"**
   - 确认 `settleFunding()` 中正确累加 `cumulativeFundingRate += rate`
   - 确认 `lastFundingTime = block.timestamp` 已更新

2. **Payment 计算结果为 0**
   - 检查精度：`/ 1e36` 而不是 `/ 1e18`
   - 确认 `diff != 0`

3. **用户资金费未扣除**
   - 确认调用了 `settleUserFunding(trader)`
   - 检查 `lastFundingIndex[trader]` 是否更新

4. **资金费方向错误**
   - 检查 `payment > 0` 表示用户需要支付
   - 多头在 mark > index 时 payment > 0

5. **maxFundingRatePerInterval 不生效**
   - 确认 `setFundingParams` 被调用
   - 检查正负方向都有 cap

---

## 8) 小结 & 为 Day 7 铺垫

今天我们完成了"资金费率机制"：

- `settleFunding()`：全局费率计算（币安公式）
- `_applyFunding()`：用户级资金费结算
- `_unrealizedPnl()`：未实现盈亏计算
- Keeper 定时触发结算

至此，系统具备了：
1. 资金管理 → 2. 订单簿 → 3. 撮合 → 4. 价格 → 5. 索引 → **6. 资金费率**

Day 7 会在此基础上实现"清算系统"：

- `canLiquidate()`：健康度判定
- `liquidate()`：清算执行
- Keeper 扫描风险账户
- 完整风控闭环测试

---

## 9) 进阶开发（必须完成）

1. **动态资金费率**
   - 根据市场波动调整 clampRange。
   - 高波动时收紧，低波动时放宽。

2. **资金费率历史记录**
   - 记录每次结算的 rate。
   - 实现 `getFundingHistory()` 视图函数。

3. **前端资金费预估**
   - 显示"下次结算预估支付/收入"。
   - 显示"距下次结算剩余时间"。

4. **多 interval 支持**
   - 支持 1h / 4h / 8h 等多种结算周期。
   - 允许用户选择偏好。
