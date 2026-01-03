# Day 5 - 数据索引与 K 线（Indexer & Candles）

本节目标：配置 Indexer（Envio）解析链上事件，生成 Trade、Order、Candle（OHLC）等数据结构，并在前端集成图表库展示专业的 K 线行情看板。

---

## 1) 学习目标

完成本节后，你将能够：

- 理解区块链 Indexer 的作用：将链上事件转换为可查询的结构化数据。
- 配置 Envio Indexer：定义 schema、编写 event handler。
- 实现 K 线（Candle）数据生成：从 TradeExecuted 事件构建 OHLC。
- 在前端集成图表库展示 K 线。

---

## 2) 前置准备

Day 5 建立在 Day 4 之上，请先确认：

- Day 1-4 功能已实现（保证金、订单簿、撮合、价格服务）
- 本地 Anvil 和合约部署正常

你可以先跑：

```bash
./quickstart.sh
# 确认前端能正常下单和成交
```

---

## 3) 当天完成标准

- Indexer 能正确解析 `MarginDeposited`、`OrderPlaced`、`TradeExecuted` 等事件
- GraphQL API 可查询 `trades`、`orders`、`candles`
- 前端 Recent Trades 列表从 Indexer 获取数据
- 前端 K 线图表显示历史价格走势
- 前端 OrderBook 深度从 Indexer 获取

---

## 4) 开发步骤（边理解边写代码）

### Step 1: 理解 Indexer 架构

Indexer 的作用是：

```
链上事件 (Event Logs) → Indexer 解析 → 数据库存储 → GraphQL API → 前端查询
```

本课程使用 **Envio** 作为 Indexer 框架，配置文件：

- `indexer/config.yaml`：定义监听的合约和事件
- `indexer/schema.graphql`：定义数据模型
- `indexer/src/EventHandlers.ts`：事件处理逻辑

---

### Step 2: 查看 Schema 定义

打开 `indexer/schema.graphql`，你会看到以下实体：

```graphql
type Trade @entity {
  id: ID!
  buyer: String!
  seller: String!
  price: BigInt!
  amount: BigInt!
  timestamp: Int!
  txHash: String!
  buyOrderId: BigInt!
  sellOrderId: BigInt!
}

type Candle @entity {
  id: ID! # "1m-timestamp"
  resolution: String!
  timestamp: Int!
  openPrice: BigInt!
  highPrice: BigInt!
  lowPrice: BigInt!
  closePrice: BigInt!
  volume: BigInt!
}

type Position @entity {
  id: ID!
  trader: Bytes!
  size: BigInt!
  entryPrice: BigInt!
}

type Order @entity {
  id: ID!
  trader: String!
  isBuy: Boolean!
  price: BigInt!
  initialAmount: BigInt!
  amount: BigInt!
  status: String! # OPEN, FILLED, CANCELLED
  timestamp: Int!
}

type LatestCandle @entity {
  id: ID! # "1"
  closePrice: BigInt!
  timestamp: Int!
}
```

---

### Step 2.5: 生成类型定义 (Codegen)
在编写代码之前，必须先根据 `config.yaml` 和 `schema.graphql` 生成 TypeScript 类型定义。

```bash
cd indexer
pnpm codegen
```

> [!IMPORTANT]
> 每当你修改了 `config.yaml` 或 `schema.graphql`，都必须重新运行 `pnpm codegen`，否则 `src/EventHandlers.ts` 会报错找不到类型。

---

### Step 3: 实现 Event Handlers

修改：

- `indexer/src/EventHandlers.ts`

#### 3.1 MarginDeposited Handler

```typescript
Exchange.MarginDeposited.handler(async ({ event, context }) => {
    const entity: MarginEvent = {
        id: `${event.transaction.hash}-${event.logIndex}`,
        trader: event.params.trader,
        amount: event.params.amount,
        eventType: "DEPOSIT",
        timestamp: event.block.timestamp,
    };
    context.MarginEvent.set(entity);
});
```

#### 3.1.1 MarginWithdrawn Handler

```typescript
Exchange.MarginWithdrawn.handler(async ({ event, context }) => {
    const entity: MarginEvent = {
        id: `${event.transaction.hash}-${event.logIndex}`,
        trader: event.params.trader,
        amount: event.params.amount,
        eventType: "WITHDRAW",
        timestamp: event.block.timestamp,
    };
    context.MarginEvent.set(entity);
});
```

#### 3.2 OrderPlaced Handler

```typescript
Exchange.OrderPlaced.handler(async ({ event, context }) => {
    const order: Order = {
        id: event.params.id.toString(),
        trader: event.params.trader,
        isBuy: event.params.isBuy,
        price: event.params.price,
        initialAmount: event.params.amount,
        amount: event.params.amount,
        status: "OPEN",
        timestamp: event.block.timestamp,
    };
    context.Order.set(order);
});
```

#### 3.2.1 OrderRemoved Handler

```typescript
Exchange.OrderRemoved.handler(async ({ event, context }) => {
    const order = await context.Order.get(event.params.id.toString());
    if (order) {
        context.Order.set({
            ...order,
            status: order.amount === 0n ? "FILLED" : "CANCELLED",
        });
    }
});
```

#### 3.3 TradeExecuted Handler（核心）

```typescript
Exchange.TradeExecuted.handler(async ({ event, context }) => {
    // 1. 创建 Trade 记录
    const trade: Trade = {
        id: `${event.transaction.hash}-${event.logIndex}`,
        buyer: event.params.buyer,
        seller: event.params.seller,
        price: event.params.price,
        amount: event.params.amount,
        timestamp: event.block.timestamp,
        txHash: event.transaction.hash,
        buyOrderId: event.params.buyOrderId,
        sellOrderId: event.params.sellOrderId,
    };
    context.Trade.set(trade);

    // 2. 更新买卖双方的 Order 剩余数量
    const buyOrder = await context.Order.get(event.params.buyOrderId.toString());
    if (buyOrder) {
        const newAmount = buyOrder.amount - event.params.amount;
        context.Order.set({
            ...buyOrder,
            amount: newAmount,
            status: newAmount === 0n ? "FILLED" : "OPEN",
        });
    }

    const sellOrder = await context.Order.get(event.params.sellOrderId.toString());
    if (sellOrder) {
        const newAmount = sellOrder.amount - event.params.amount;
        context.Order.set({
            ...sellOrder,
            amount: newAmount,
            status: newAmount === 0n ? "FILLED" : "OPEN",
        });
    }

    // 3. 更新 K 线 (Candle)
    // TODO: 将在 Step 4 中实现 K 线更新逻辑...

    // 4. 更新 Position (持仓)
    // TODO: 将在 Step 5 中实现持仓更新逻辑...
});
```


---

### Step 4: 实现 K 线（Candle）更新逻辑

K 线的关键是按时间窗口聚合交易数据：

```typescript
// 3. 更新 K 线 (1m)
const resolution = "1m";
// 向下取整到最近的分钟
const timestamp = event.block.timestamp - (event.block.timestamp % 60);
const candleId = `${resolution}-${timestamp}`;

const existingCandle = await context.Candle.get(candleId);

if (!existingCandle) {
    // 新 K 线：使用上一根 K 线的 close 作为 open
    const latestCandleState = await context.LatestCandle.get("1");
    const openPrice = latestCandleState ? latestCandleState.closePrice : event.params.price;
    
    const candle: Candle = {
        id: candleId,
        resolution,
        timestamp,
        openPrice: openPrice,
        highPrice: event.params.price > openPrice ? event.params.price : openPrice,
        lowPrice: event.params.price < openPrice ? event.params.price : openPrice,
        closePrice: event.params.price,
        volume: event.params.amount,
    };
    context.Candle.set(candle);
} else {
    // 更新现有 K 线
    const newHigh = event.params.price > existingCandle.highPrice ? event.params.price : existingCandle.highPrice;
    const newLow = event.params.price < existingCandle.lowPrice ? event.params.price : existingCandle.lowPrice;

    context.Candle.set({
        ...existingCandle,
        highPrice: newHigh,
        lowPrice: newLow,
        closePrice: event.params.price,
        volume: existingCandle.volume + event.params.amount,
    });
}

// 更新全局最新价格状态
context.LatestCandle.set({
    id: "1",
    closePrice: event.params.price,
    timestamp: event.block.timestamp
});
```

---

### Step 5: 实现 Position 更新逻辑

// 在 TradeExecuted handler 中，不需要再手动计算 Position 更新
// 只需要监听 PositionUpdated 事件即可

Exchange.PositionUpdated.handler(async ({ event, context }) => {
    const entity: Position = {
        id: event.params.trader,
        trader: event.params.trader,
        size: event.params.size,
        entryPrice: event.params.entryPrice,
    };
    context.Position.set(entity);
});
```

---

### Step 6: 启动 Indexer

```bash
# 安装依赖
cd indexer
pnpm install

# 启动（需要先启动 Anvil）
pnpm dev
```

验证 GraphQL playground：

```
http://localhost:8080/graphql
```

查询示例：

```graphql
query {
  trades(limit: 10, orderBy: timestamp, orderDirection: desc) {
    id
    buyer
    seller
    price
    amount
    timestamp
  }
}

query {
  candles(where: { resolution: "1m" }, orderBy: timestamp, orderDirection: desc) {
    timestamp
    openPrice
    highPrice
    lowPrice
    closePrice
    volume
  }
}

query {
  positions {
    trader
    size
    entryPrice
  }
}
```

---

### Step 7: 前端数据抓取 (Store 逻辑)

在 `frontend/store/exchangeStore.tsx` 中，我们需要通过 GraphQL 客户端抓取索引器的数据。

#### 7.1 抓取成交历史
```typescript
loadTrades = async (): Promise<Trade[]> => {
    const result = await client.query(GET_RECENT_TRADES, {}).toPromise();
    if (!result.data?.Trade) return [];
    return result.data.Trade.map((t: any) => ({
        id: t.id,
        price: Number(formatEther(t.price)),
        amount: Number(formatEther(t.amount)),
        time: new Date(t.timestamp * 1000).toLocaleTimeString(),
        side: BigInt(t.buyOrderId) > BigInt(t.sellOrderId) ? 'buy' : 'sell',
    }));
};
```

#### 7.2 抓取 K 线数据
```typescript
loadCandles = async () => {
    const result = await client.query(GET_CANDLES, {}).toPromise();
    if (result.data?.Candle) {
        const candles = result.data.Candle.map((c: any) => ({
            time: c.timestamp,
            open: Number(formatEther(c.openPrice)),
            high: Number(formatEther(c.highPrice)),
            low: Number(formatEther(c.lowPrice)),
            close: Number(formatEther(c.closePrice)),
        }));
        this.candles = candles;
    }
};
```

---


## 5) 解析：为什么这样写

### 5.1 为什么需要 Indexer？

区块链是"只写"的，查询历史数据很慢：

| 方案 | 速度 | 成本 |
|------|------|------|
| 直接查链 | 慢（需遍历区块） | 高（RPC 调用费用） |
| **Indexer** | 快（数据库查询） | 低（一次索引多次查询） |

### 5.2 OHLC K 线原理

| 字段 | 含义 |
|------|------|
| Open | 该时间段第一笔成交价 |
| High | 该时间段最高成交价 |
| Low | 该时间段最低成交价 |
| Close | 该时间段最后一笔成交价 |
| Volume | 该时间段成交量 |

### 5.3 为什么用 LatestCandle？

当开始新的 K 线时，需要知道上一根 K 线的 close 价格作为新 K 线的 open：

```
K1: [O=100, H=105, L=98, C=102]
K2: [O=102, ...]  ← 继承 K1 的 close
```

---

## 6) 测试与验证

### 6.1 Indexer 验证

```bash
# 启动完整环境
./quickstart.sh

# 打开 GraphQL Playground
open http://localhost:8080/graphql
```

执行查询确认数据：

```graphql
{ trades { id price amount } }
{ candles { timestamp openPrice closePrice } }
```

### 6.2 前端验证

打开 `http://localhost:3000`，验证：

1. **Recent Trades** 列表显示成交记录
2. **K 线图表** 显示价格走势（如果已集成）
3. 下一笔交易后，刷新页面确认数据更新

---

## 7) 常见问题（排错思路）

1. **Indexer 报错 "contract not found"**
   - 检查 `config.yaml` 中的合约地址是否与部署地址一致
   - 重新运行 `./scripts/run-anvil-deploy.sh` 并更新配置

2. **GraphQL 查询返回空数组**
   - 确认 Indexer 正在运行且已处理事件
   - 查看 Indexer 日志确认是否有错误

3. **K 线数据不连续**
   - 确认 `LatestCandle` 逻辑正确实现
   - 检查时间戳取整逻辑 `timestamp % 60`

4. **前端图表不显示**
   - 确认 GraphQL endpoint 地址正确
   - 检查浏览器 Console 是否有 CORS 错误

---

## 8) 小结 & 为 Day 6 铺垫

今天我们完成了"数据索引"层：

- 配置 Envio Indexer 解析链上事件
- 实现 Event Handlers 存储 Trade、Order、Candle
- 前端通过 GraphQL 获取历史数据

至此，系统具备了：
1. 资金管理 → 2. 订单簿 → 3. 撮合 → 4. 价格服务 → **5. 数据索引**

Day 6 会在此基础上实现"资金费率机制"：

- `settleFunding()`：全局资金费率结算
- `_applyFunding()`：用户级资金费计算
- Keeper 定时触发结算
- 前端显示"未结资金费"与"强平价格"

---

## 9) 进阶开发（必须完成）

1. **多分辨率 K 线**
   - 支持 5m、15m、1h 等多种时间粒度。
   - 修改 resolution 参数和时间戳取整逻辑。

2. **实时 WebSocket 推送**
   - 使用 Envio 的 subscription 功能。
   - 前端订阅新成交事件。

3. **深度图数据**
   - 聚合 Order 实体生成深度数据。
   - 按价格级别汇总买卖盘数量。

4. **历史数据分页**
   - 实现 GraphQL 分页查询。
   - 前端无限滚动加载更多数据。
