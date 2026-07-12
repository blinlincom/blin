# BIM GasFree 归集对接方案书

## 1. 文档目标

本方案是在 BIM 已有数字资产系统中新增 GasFree 充值和归集能力，不另建一套孤立钱包系统。

现有架构继续保留：

```text
Flutter 多端客户端
    ↓ HTTPS 加密业务接口
TP8 业务端与后台
    ↓ HMAC 内部回调
Go 独立钱包服务
    ↓
TRON / GasFree Provider
```

GasFree 仅替换“新 GasFree 地址如何归集 USDT”的链上执行方式，不替换以下业务：

- 平台 USDT 总账和分录；
- 用户余额与冻结余额；
- 站内转账、红包、OTC 和闪兑；
- 提现审核与提现热钱包；
- 现有普通 TRON 地址扫描；
- 后台数字资产管理。

## 2. 核心结论

1. GasFree Account 不是现有普通 TRON 地址，必须由用户 EOA 地址按 GasFree 规则映射生成。
2. 用户充值页面展示 GasFree Address，不能展示 EOA 作为 GasFree 收款地址。
3. EOA 私钥仍由 Go 钱包服务通过主种子派生，只用于签署 TIP-712 授权。
4. API Key、API Secret、主种子和派生私钥只能存在于独立钱包服务环境。
5. GasFree 手续费从 GasFree 地址中的 USDT 扣除，不使用用户地址中的 TRX。
6. 费率必须实时读取，不能将激活费和转账费写死。
7. 同一 GasFree Account 当前最多存在一笔待处理授权，任务必须串行。
8. Provider 接受授权不代表链上成功，必须等到 `SUCCEED + SOLIDITY`。
9. 现有普通地址及其中的资金不能直接转换成 GasFree 资金，必须继续按普通链上方式处理。

## 3. 地址体系

每个用户将同时存在两类地址：

```text
普通 EOA 地址
用途：控制权地址、TIP-712签名、旧充值地址

GasFree Address
用途：新 GasFree USDT 充值地址
```

建议地址状态：

```text
legacy_active       旧地址仍扫描，但不再默认展示
gasfree_primary     新充值默认展示
disabled            禁止继续使用
```

客户端只能看到当前后台指定的主充值地址。旧地址不能停止扫描，因为用户可能保存过旧二维码并再次充值。

## 4. 官方接口

主网基础地址：

```text
https://open.gasfree.io/tron
```

需要对接：

```text
GET  /api/v1/config/token/all
GET  /api/v1/config/provider/all
GET  /api/v1/address/{eoaAddress}
POST /api/v1/gasfree/submit
GET  /api/v1/gasfree/{traceId}
```

API 请求认证：

```text
message   = HTTP_METHOD + REQUEST_PATH + TIMESTAMP
signature = Base64(HMAC-SHA256(API_SECRET, message))
```

请求头：

```http
Timestamp: 1731912286
Authorization: ApiKey {API_KEY}:{signature}
```

服务端必须校验 HTTP 状态码和响应体中的 `code`，不能只判断 HTTP 200。

## 5. 钱包服务配置

在 `/etc/bim/tron-wallet.env` 增加：

```dotenv
# 功能总开关。完成 Nile 测试和主网小额验收前必须为 false。
TRON_GASFREE_ENABLED=false
TRON_GASFREE_AUTO_ENABLED=false

# 主网 Provider API。
TRON_GASFREE_API_URL=https://open.gasfree.io/tron
TRON_GASFREE_API_KEY=
TRON_GASFREE_API_SECRET=

# TRON 主网 TIP-712 Domain。
TRON_GASFREE_CHAIN_ID=728126428
TRON_GASFREE_VERIFYING_CONTRACT=TFFAMQLZybALaLb4uxHA9RBE7pxhUAjF3U

# 运营安全阈值，单位 USDT。
TRON_GASFREE_MAX_TRANSFER_FEE_USDT=2.000000
TRON_GASFREE_MAX_FIRST_FEE_USDT=4.000000
TRON_GASFREE_MIN_NET_AMOUNT_USDT=10.000000
TRON_GASFREE_MAX_FEE_RATE_PERCENT=10.00

# 状态查询和任务控制。
TRON_GASFREE_POLL_SECONDS=5
TRON_GASFREE_CONFIRM_TIMEOUT_SECONDS=600
TRON_GASFREE_RECONCILE_SECONDS=60
TRON_GASFREE_WORKER_ID=gasfree-1
```

以下配置禁止保存到数据库、日志或客户端：

```text
TRON_GASFREE_API_SECRET
TRON_MASTER_SEED_HEX
用户派生私钥
```

## 6. 数据库设计

### 6.1 GasFree 用户账户

表：`mr_wallet_gasfree_account`

```text
id
appid
user_id
asset_id
network_id
eoa_address
gasfree_address
provider_address
active
recommended_nonce
allow_submit
token_address
token_decimals
onchain_balance
provider_frozen
status
last_sync_time
create_time
update_time
```

约束：

```text
UNIQUE(appid,user_id,asset_id,network_id)
UNIQUE(gasfree_address)
UNIQUE(eoa_address,provider_address)
```

### 6.2 GasFree 归集任务

表：`mr_wallet_gasfree_transfer`

```text
id
appid
request_id UUID
sweep_no
account_id
user_id
asset_id
network_id
eoa_address
gasfree_address
provider_address
receiver_address
token_address
value
max_fee
estimated_activate_fee
estimated_transfer_fee
estimated_total_fee
nonce
deadline
signature_version
signature_hash
trace_id
state
txn_state
txn_hash
txn_amount
txn_activate_fee
txn_transfer_fee
txn_total_fee
txn_total_cost
retry_count
last_error
lease_owner
lease_until
submitted_time
confirmed_time
create_time
update_time
```

约束：

```text
UNIQUE(request_id)
UNIQUE(sweep_no)
UNIQUE(trace_id)
INDEX(account_id,state,txn_state)
```

同一账户不能同时存在两个以下状态的任务：

```text
preparing
signed
submitted
WAITING
INPROGRESS
CONFIRMING
```

该限制必须通过账户行锁和事务实现，不能仅依赖应用内存。

### 6.3 费用快照

表：`mr_wallet_gasfree_fee_snapshot`

```text
id
provider_address
token_address
symbol
decimals
activate_fee
transfer_fee
supported
provider_config_json
fetched_time
```

每次提交任务必须把使用的费用快照复制到任务订单，不能事后用新费率解释旧订单。

### 6.4 地址表扩展

现有 `mr_wallet_chain_address` 增加：

```text
address_type: eoa | gasfree
display_priority
accept_deposit
gasfree_account_id
```

旧地址统一标记为 `eoa`，继续扫描。

## 7. Go 钱包服务改造

新增模块：

```text
internal/gasfree/client.go       API认证、请求与响应
internal/gasfree/eip712.go       TIP-712结构和摘要
internal/gasfree/model.go        Provider数据模型
cmd/server/gasfree_worker.go     串行任务执行器
cmd/server/gasfree_reconcile.go  状态补偿与对账
```

### 7.1 账户创建/查询

1. 根据 `appid + user_id` 使用现有主种子派生 EOA。
2. 调用 `/address/{eoaAddress}`。
3. 验证返回的 `accountAddress` 与本地 EOA 一致。
4. 保存 `gasFreeAddress`、Provider、nonce、active 和 allowSubmit。
5. 注册该 GasFree Address 进入充值扫描列表。

### 7.2 TIP-712 授权

主网 Domain：

```text
name: GasFreeController
version: V1.0.0
chainId: 728126428
verifyingContract: TFFAMQLZybALaLb4uxHA9RBE7pxhUAjF3U
```

签名字段：

```text
token
serviceProvider
user
receiver
value
maxFee
deadline
version
nonce
```

签名前必须校验：

- receiver 等于后台归集白名单地址；
- token 等于启用的 USDT 合约；
- provider 来自实时 Provider 配置；
- nonce 等于 Provider 推荐 nonce；
- deadline 在 Provider 允许范围内；
- maxFee 不超过后台上限；
- value 与任务订单完全一致；
- 用户当前没有其他待处理 GasFree 授权。

### 7.3 提交与确认

执行状态：

```text
queued
preparing
signed
submitted
WAITING
INPROGRESS
CONFIRMING
success
failed
manual_review
```

Provider 返回 `traceId` 后，禁止重新签署同 nonce 的另一笔任务。

成功条件必须同时满足：

```text
state = SUCCEED
txnState = SOLIDITY
txnHash 非空
targetAddress = 归集钱包
tokenAddress = USDT合约
txnAmount = 预期净转账金额
txnTotalFee <= maxFee
```

## 8. 充值扫描与账务

### 8.1 入账

用户转入 GasFree Address 后，充值扫描仍按链上 USDT Transfer 事件入账：

```text
txid + log_index 唯一
达到确认要求
写 wallet_chain_event
写 wallet_asset_journal
增加用户平台USDT可用余额
```

GasFree 只影响后续归集，不改变用户充值入账金额。

### 8.2 归集账务

GasFree 手续费由链上地址中的 USDT 支付，不再从用户平台余额二次扣除。

系统需要分别记录：

```text
用户充值总额
实际归集到账
GasFree实际手续费
GasFree激活费
地址未归集余额
```

关系：

```text
充值地址支出 = txnAmount + txnTotalFee
归集钱包收入 = txnAmount
```

不能把 `txnTotalFee` 记成用户钱包再次扣款，否则会重复扣用户资产。

## 9. 自动归集规则

每次执行前实时查询账户：

```text
balance
frozen
active
nonce
allowSubmit
activateFee
transferFee
```

可用链上金额：

```text
available = balance - frozen
```

预计费用：

```text
active=true  → transferFee
active=false → activateFee + transferFee
```

允许归集必须全部满足：

```text
allowSubmit = true
available > estimatedFee
estimatedFee <= 后台绝对费用上限
estimatedFee / available <= 后台费用比例上限
available - estimatedFee >= 最低净归集金额
没有待处理任务
Provider和Token处于supported状态
```

推荐首期策略：

```text
已激活最低净归集：10 USDT
未激活最低净归集：20 USDT
最高费用比例：10%
自动归集默认关闭
```

## 10. TP8 接口改造

### 10.1 充值地址接口

现有：

```text
wallet_asset_deposit_address
```

响应增加：

```json
{
  "address": "T...",
  "address_type": "gasfree",
  "network": "TRC20",
  "asset": "USDT",
  "minimum_deposit": "20.00000000",
  "fee_mode": "token",
  "legacy_address_available": false
}
```

客户端不需要知道 EOA、Provider、nonce 或 TIP-712。

### 10.2 内部钱包回调

新增 HMAC 保护接口：

```text
/callback/tron/gasfree/accounts
/callback/tron/gasfree/task
/callback/tron/gasfree/task_report
/callback/tron/gasfree/reconcile
```

继续使用现有：

```text
X-BIM-Timestamp
X-BIM-Signature
30秒时间窗口
原始请求体HMAC-SHA256
```

## 11. 后台管理

在“数字钱包”下新增“GasFree 管理”：

### 配置状态

- API 是否配置；
- Provider 是否可用；
- USDT 是否支持；
- 当前激活费和转账费；
- 主网/测试网；
- 自动归集开关；
- 最低净归集金额；
- 单笔最高费用；
- 最高费用比例；
- 最近同步时间。

### 用户账户

- 用户名；
- EOA 地址；
- GasFree 地址；
- 是否激活；
- 链上余额；
- Provider 冻结金额；
- nonce；
- allowSubmit；
- 最近充值和归集时间。

### 任务管理

- sweep_no；
- traceId；
- txnHash；
- 预计费用；
- 实际费用；
- 实际归集金额；
- Provider 状态；
- 链上状态；
- 失败原因；
- 人工重查；
- 暂停任务。

后台禁止提供“任意接收地址”输入框。归集目标只能来自已审核的归集钱包白名单。

## 12. Flutter 客户端改造

客户端只改充值展示层：

- 展示后台返回的主充值地址；
- 二维码内容与地址一致；
- 显示 USDT-TRC20；
- 显示实时最低充值金额；
- 地址切换时清除旧二维码缓存；
- 不展示 GasFree、EOA、Provider、nonce 等开发术语；
- 用户复制地址后保留风险提示；
- 旧地址不再作为默认地址展示。

平台 USDT 余额、账单、OTC、红包、转账和提币页面不需要改变账务模型。

## 13. 旧地址迁移

现有普通地址不能删除：

```text
继续扫描充值
继续给用户入账
不再作为默认地址展示
达到经济归集阈值后使用Energy/TRX处理
```

当前已有 `2.97 USDT` 的普通地址：

```text
TV41sgpeZAaWJMGbn43AySVUdQEx4j6Yv4
```

该资金不迁移到 GasFree 地址，也不能通过 GasFree 授权转出。应等待金额增加、租用 Energy，或使用自有 Energy 委托归集。

## 14. 安全控制

1. API Secret 只存 `/etc/bim/tron-wallet.env`，权限 `600`。
2. 钱包服务仅监听 `127.0.0.1` 或内网。
3. EOA 私钥只在签名瞬间存在内存，不落盘、不写日志。
4. 签名 receiver 必须来自归集地址白名单。
5. Provider、Token 和 Domain 必须与当前环境严格匹配。
6. 同账户单任务串行，使用数据库租约防止多实例并发。
7. requestId、sweepNo、traceId 全部唯一。
8. API 超时后先按 requestId/账户状态对账，禁止直接重签。
9. `NonceNotMatch` 后重新查询账户，不能自行 nonce+1。
10. `MaxFeeExceeded` 后暂停，不自动提高费用上限。
11. 日志允许记录地址、traceId、txnHash 和状态，不记录 API Secret、私钥和完整签名。
12. 归集钱包变更需要后台双人审核并经过冷却期。

## 15. 异常与补偿

| 场景 | 处理方式 |
|---|---|
| API请求超时，未拿到traceId | 查询账户和业务requestId，确认无待处理授权后人工重试 |
| Provider返回WAITING过久 | 保持任务锁定，告警，不创建第二笔 |
| nonce不匹配 | 重新查询账户推荐nonce，废弃旧签名 |
| 实时费用超过上限 | 暂缓归集并告警 |
| Provider Token停止支持 | 关闭新地址展示和自动归集 |
| state=FAILED | 保存失败原因，重新查询余额和nonce后生成新任务 |
| SUCCEED但未SOLIDITY | 继续确认，不提前标记成功 |
| txnAmount与预期不一致 | 转人工对账，不自动完成 |
| Provider不可用 | 保留资金原地，不自动切换普通归集 |

## 16. 灰度上线步骤

### 阶段一：Nile 测试网

1. 申请测试 API Key。
2. 使用独立测试主种子。
3. 创建测试 GasFree 地址。
4. 测试首次激活和后续转账。
5. 测试错误 nonce、费用不足、超时和重复请求。
6. 测试服务重启后任务恢复。

### 阶段二：主网人工模式

1. 配置正式 API Key/Secret。
2. `TRON_GASFREE_ENABLED=true`。
3. `TRON_GASFREE_AUTO_ENABLED=false`。
4. 仅给内部测试账号展示 GasFree 地址。
5. 分别测试首次和第二次归集。
6. 核对实时费用、实际费用、归集到账和平台账本。

### 阶段三：小流量自动归集

1. 仅允许白名单用户。
2. 设置较高最低净归集金额。
3. 每日人工对账。
4. 连续稳定运行至少七天。

### 阶段四：正式开放

1. 全量新用户展示 GasFree 地址。
2. 旧普通地址继续扫描。
3. 自动归集按费用规则执行。
4. 保留一键关闭开关。

## 17. 验收标准

```text
[ ] API认证签名通过
[ ] EOA与GasFree地址映射稳定
[ ] 首次激活归集成功
[ ] 后续归集成功
[ ] 同账户并发只提交一笔
[ ] Provider超时不会重复授权
[ ] nonce错误能够恢复
[ ] 费用超过上限自动暂停
[ ] SUCCEED+SOLIDITY后才完成
[ ] 充值金额、实际费用、归集到账可对账
[ ] API Secret和私钥不出现在日志/数据库/客户端
[ ] 旧普通地址继续正常入账
[ ] 功能关闭后不再生成新GasFree任务
```

## 18. 实施范围与顺序

建议按以下顺序开发：

1. 数据库迁移和后台只读状态。
2. Go GasFree API 认证客户端。
3. EOA/GasFree 地址映射。
4. TIP-712 签名测试向量。
5. 提交、查询与补偿 Worker。
6. TP8 充值地址和任务回调。
7. 后台配置、账户、任务与对账页面。
8. Flutter 充值地址展示切换。
9. Nile 全流程测试。
10. 主网白名单小额验收。

## 19. 开始实施前必须具备

你需要准备：

```text
GasFree API Key
GasFree API Secret
Developers Center账号已审核
Nile测试权限或正式主网权限
最终归集钱包地址
可接受的最高首次费用
可接受的最高后续费用
最低净归集金额
```

未取得 API Key 和 API Secret 时，可以完成数据库、接口、后台和签名模块开发，但无法做 Provider 实际提交和主网验收。
