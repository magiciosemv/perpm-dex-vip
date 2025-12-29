# Day 3 - 撮合与持仓更新（Matching & Positions）

本节目标：在 Day 2 的订单簿基础上，完成成交后的核心状态更新：撮合触发 `_executeTrade`，并正确维护 `Position.size` / `entryPrice` / `realizedPnl`，将已实现盈亏计入 `freeMargin`。

---

## 1) 学习目标（面向学生）

完成本节后，你将能够：

- 理解 maker 价成交的撮合规则（成交价来自挂在簿上的订单）。
- 实现 `_executeTrade` / `_updatePosition` 两个核心函数。
- 正确处理三种持仓更新：加仓、减仓、反向开仓。

---

## 2) 前置准备（必须满足）

Day3 建立在 Day2 之上，请先确认：

- Day1 / Day2 测试已通过
- 订单簿已能正确插入与撮合入口可用（`placeOrder` → `_matchBuy/_matchSell`）

你可以先跑：

```bash
cd contract
forge test --match-contract Day2OrderbookTest -vvv
```

---

## 3) 当天完成标准（Definition of Done）

- `forge test --match-contract Day3MatchingTest -vvv` 全部通过
- 部分成交后订单 `amount` 正确减少
- 双方持仓 `size` 更新正确（多头为正、空头为负）
- 反向平仓后 `realizedPnl` 正确，并同步更新 `freeMargin`

---

## 4) 开发步骤（边理解边写代码）

### Step 1: 读测试，先把规则写清楚

打开：

- `contract/test/Day3Matching.t.sol`

你会看到四类要求：

1. **部分成交更新持仓**：成交后订单剩余数量正确
2. **价格不交叉不成交**：买价 < 最优卖价时不成交
3. **反向平仓结算 PnL**：`realizedPnl` 与 `freeMargin` 必须更新
4. **taker 跨多档吃单**：多档成交后订单簿清空

---

### Step 2: 明确成交价规则（maker 价成交）

当前 `_matchBuy/_matchSell` 会把成交价设为 **链表头订单的价格**：

- 买单成交：`price = bestSell.price`
- 卖单成交：`price = bestBuy.price`

因此 Day3 的 `_executeTrade` 只需使用传入的 `price`，不需要重新计算。

---

### Step 3: 实现 `_executeTrade`（撮合后的统一入口）

修改：

- `contract/src/modules/LiquidationModule.sol`

`_executeTrade` 只做四件事：

1. 对买卖双方应用资金费（Day5 才有真实逻辑，先调用钩子）
2. 更新买方持仓
3. 更新卖方持仓
4. 触发成交事件 `TradeExecuted`

参考实现：

```solidity
function _executeTrade(
    address buyer,
    address seller,
    uint256 buyOrderId,
    uint256 sellOrderId,
    uint256 amount,
    uint256 price
) internal virtual {
    _applyFunding(buyer);
    _applyFunding(seller);

    _updatePosition(buyer, true, amount, price);
    _updatePosition(seller, false, amount, price);

    emit TradeExecuted(buyOrderId, sellOrderId, price, amount, buyer, seller);
}
```

---

### Step 4: 实现 `_updatePosition`（加仓 / 减仓 / 反向）

仍在：

- `contract/src/modules/LiquidationModule.sol`

核心规则：

- **同方向加仓**：按加权平均价更新 `entryPrice`
- **反方向减仓/平仓**：计算已实现盈亏并更新 `freeMargin`
- **反向开仓**：完全对冲后还有剩余，则按成交价开新仓

关键公式：

- 加权平均价：`(oldSize * oldEntry + newSize * tradePrice) / (oldSize + newSize)`
- 已实现盈亏（多头）：`(tradePrice - entryPrice) * closing / 1e18`
- 已实现盈亏（空头）：`(entryPrice - tradePrice) * closing / 1e18`

参考实现：

```solidity
function _updatePosition(
    address trader,
    bool isBuy,
    uint256 amount,
    uint256 tradePrice
) internal virtual {
    Position storage p = accounts[trader].position;
    int256 signed = isBuy ? int256(amount) : -int256(amount);
    uint256 existingAbs = SignedMath.abs(p.size);

    // 1) 同方向加仓
    if (p.size == 0 || (p.size > 0) == (signed > 0)) {
        uint256 newAbs = existingAbs + amount;
        uint256 weighted = existingAbs == 0
            ? tradePrice
            : (existingAbs * p.entryPrice + amount * tradePrice) / newAbs;
        p.entryPrice = weighted;
        p.size += signed;
        return;
    }

    // 2) 反向减仓/平仓
    uint256 closing = amount < existingAbs ? amount : existingAbs;
    int256 pnlPerUnit = p.size > 0
        ? int256(tradePrice) - int256(p.entryPrice)
        : int256(p.entryPrice) - int256(tradePrice);
    int256 pnl = (pnlPerUnit * int256(closing)) / int256(SCALE);

    p.realizedPnl += pnl;

    int256 newMargin = int256(accounts[trader].freeMargin) + pnl;
    if (newMargin < 0) accounts[trader].freeMargin = 0;
    else accounts[trader].freeMargin = uint256(newMargin);

    // 3) 是否反向开仓
    uint256 remaining = amount - closing;
    if (closing == existingAbs) {
        if (remaining == 0) {
            p.size = 0;
            p.entryPrice = tradePrice;
        } else {
            p.size = signed > 0 ? int256(remaining) : -int256(remaining);
            p.entryPrice = tradePrice;
        }
    } else {
        if (p.size > 0) p.size -= int256(closing);
        else p.size += int256(closing);
    }
}
```

---

## 5) 解析：为什么这样写

### 5.1 为什么用 maker 价成交？

在订单簿交易所中，成交价通常取**被动方（maker）的挂单价格**，而非主动方（taker）的报价。原因：

- **价格发现更公平**：maker 先挂单承担了流动性风险，应该以他愿意成交的价格成交
- **防止价格操纵**：如果用 taker 价，恶意用户可以用极端价格扫单
- **符合行业惯例**：CEX（如币安、OKX）均采用 maker 价成交

在代码中体现为：

```solidity
// _matchBuy 中
_executeTrade(..., head.price);  // head 是卖单链表头，即 bestSell
```

### 5.2 加权平均价公式详解

当用户**同方向加仓**时，新的 `entryPrice` 需要按加权平均计算：

```
newEntry = (oldSize × oldEntry + addSize × tradePrice) / (oldSize + addSize)
```

示例：
- 原持仓：10 ETH @ $1000
- 加仓：5 ETH @ $1200
- 新均价：`(10×1000 + 5×1200) / 15 = 16000/15 ≈ $1066.67`

代码实现：

```solidity
uint256 weighted = (existingAbs * p.entryPrice + amount * tradePrice) / newAbs;
```

### 5.3 realizedPnl 的符号处理

盈亏方向取决于**持仓方向**与**价格变动方向**：

| 持仓方向 | 价格变动 | 盈亏 |
|---------|---------|------|
| 多头 (size > 0) | 价格上涨 | 盈利 (+) |
| 多头 (size > 0) | 价格下跌 | 亏损 (-) |
| 空头 (size < 0) | 价格下跌 | 盈利 (+) |
| 空头 (size < 0) | 价格上涨 | 亏损 (-) |

代码中用条件表达式处理：

```solidity
int256 pnlPerUnit = p.size > 0
    ? int256(tradePrice) - int256(p.entryPrice)   // 多头：卖出价 - 入场价
    : int256(p.entryPrice) - int256(tradePrice);  // 空头：入场价 - 买回价
```

### 5.4 反向开仓的边界情况

当 taker 的成交量**大于**原持仓时，会触发"反向开仓"：

1. 先平掉全部原仓位（`closing = existingAbs`）
2. 剩余量按成交价开新仓（`remaining = amount - closing`）

例如：
- 原持仓：多头 5 ETH @ $1000
- 卖出 8 ETH @ $1100
- 结果：先平 5 ETH（盈利 $500），再开空头 3 ETH @ $1100

代码分支：

```solidity
if (closing == existingAbs) {
    if (remaining == 0) { p.size = 0; }           // 刚好平仓
    else { p.size = signed > 0 ? int256(remaining) : -int256(remaining); }  // 反向开仓
}
```

### Step 9: 前端持仓实时更新

为了在 UI 上看到 Alice 和 Bob 的持仓变化，我们需要更新 `frontend/hooks/useExchange.tsx` 中的 `refresh` 函数，使其能够调用我们在 Day 1 实现的 `getPosition` 视图函数。

```typescript
// 更新 refresh 函数
const refresh = useCallback(async () => {
    if (!EXCHANGE_ADDRESS || !account) return;
    setSyncing(true);
    try {
        const [marginBal, pos] = await Promise.all([
            publicClient.readContract({
                address: EXCHANGE_ADDRESS,
                abi: EXCHANGE_ABI,
                functionName: 'margin',
                args: [account],
            }),
            publicClient.readContract({
                address: EXCHANGE_ADDRESS,
                abi: EXCHANGE_ABI,
                functionName: 'getPosition',
                args: [account],
            }),
        ]);
        setMargin(marginBal as bigint);
        setPosition(pos as PositionSnapshot);
        setError(undefined);
    } catch (e: any) {
        console.error(e);
    } finally {
        setSyncing(false);
    }
}, [account]);
```

> [!NOTE]
> 使用 `Promise.all` 可以并发请求多个数据，显著提升页面加载速度。

---

## 6) 测试与验证

### 6.1 运行合约测试

```bash
cd contract
forge test --match-contract Day3MatchingTest -vvv
```

通过标准：4 个测试全部 `PASS`

你也可以单独跑某个测试：

```bash
forge test --match-test testClosingPositionRealizesPnl -vvv
```

### 6.2 前端验证（必须）

启动本地环境：

```bash
# 方式 A：完整启动
./quickstart.sh

# 方式 B：最小启动（终端1）
./scripts/run-anvil-deploy.sh
# 终端2
cd frontend && npm run dev
```

打开 `http://localhost:3000`，按以下路径验证：

**验收路径 1：基本成交**

1. 切换到 Alice 账号，充值 10 MON
2. 下一个买单：价格 100，数量 1
3. 切换到 Bob 账号，充值 10 MON
4. 下一个卖单：价格 100，数量 1
5. 观察 **Recent Trades** 列表出现成交记录
6. 观察 **Positions** 面板：Alice 显示多头 +1，Bob 显示空头 -1

**验收路径 2：部分成交**

1. Alice 下买单：价格 100，数量 5
2. Bob 下卖单：价格 100，数量 2
3. 观察 Alice 的挂单剩余 3（在 Orderbook 或 Open Orders 中）
4. 观察 Recent Trades 显示成交 2

**验收路径 3：平仓盈亏**

1. Alice 持有多头 1 @ 100（从路径 1 继续）
2. Alice 下卖单：价格 150，数量 1
3. Bob 下买单：价格 150，数量 1（吃掉 Alice 的卖单）
4. 观察 Alice 的 `Available Margin` 增加（包含 +50 的盈利）
5. 观察 Alice 的 Position 变为 0

---

## 7) 常见问题（排错思路）

1. **`realizedPnl` 不对**
   - 检查多头/空头的 PnL 公式符号是否相反
   - 确认 `pnlPerUnit` 的计算顺序（多头：成交价-入场价；空头：入场价-成交价）

2. **`entryPrice` 异常**
   - 加仓时必须按加权平均价更新
   - 注意 `existingAbs == 0` 时直接取 `tradePrice`

3. **平仓后仓位不为 0**
   - 检查 `closing` 与 `remaining` 的分支逻辑
   - 确认 `remaining = amount - closing` 计算正确

4. **freeMargin 没变化**
   - 确认 `pnl` 结果已写入 `freeMargin`
   - 检查 `int256 newMargin = int256(accounts[trader].freeMargin) + pnl;` 这行

5. **前端成交列表不更新**
   - 确认 Indexer 正在运行且监听 `TradeExecuted` 事件
   - 点击 Refresh 按钮手动刷新
   - 检查浏览器 Console 是否有 GraphQL 错误

---

## 8) 小结 & 为 Day 4 铺垫

今天我们完成了"撮合引擎"的核心逻辑：

- `_executeTrade`：撮合后的统一入口，触发事件、更新双方持仓
- `_updatePosition`：处理加仓、减仓、反向开仓三种场景
- `realizedPnl`：平仓时结算已实现盈亏，同步更新 `freeMargin`

至此，用户可以：
1. 充值保证金 → 2. 下单 → 3. 成交 → 4. 持仓变化 → 5. 平仓获利/亏损

Day 4 会在此基础上引入"价格服务"：

- `updateIndexPrice()`：外部预言机/Keeper 推送价格
- `_calculateMarkPrice()`：三价取中计算标记价格
- 标记价格将用于计算"未实现盈亏"与"强平价格"

---

## 9) 可选挑战 / 扩展（不影响主线）

1. **给 `TradeExecuted` 事件补断言**
   - 在 `Day3Matching.t.sol` 中新增 `vm.expectEmit(...)`，校验事件参数（buyer, seller, price, amount）

2. **测试极端边界**
   - 下单量刚好等于对手盘：`amount == head.amount`
   - 反向开仓后立刻再反向：`5 long → 10 sell → 5 short → 3 buy`

3. **验证加权平均价精度**
   - 用 Fuzz 测试验证：任意两次加仓后，`entryPrice` 始终在两次成交价之间

4. **前端增强**
   - 在 Positions 组件中显示 `realizedPnl` 字段
   - 在 Recent Trades 中高亮自己参与的成交

---

## 9) 进阶：前端持仓刷新（Alignment）

在 `useExchange.tsx` 中，我们需要在 `refresh` 函数中通过 `Promise.all` 并发读取保证金和持仓数据，以确保 UI 状态的实时性。

```typescript
const [marginBal, pos] = await Promise.all([
    publicClient.readContract({
        address: EXCHANGE_ADDRESS,
        abi: EXCHANGE_ABI,
        functionName: 'margin',
        args: [account],
    }),
    publicClient.readContract({
        address: EXCHANGE_ADDRESS,
        abi: EXCHANGE_ABI,
        functionName: 'getPosition',
        args: [account],
    }),
]);
```
