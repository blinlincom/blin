# BIM USDT-TRC20 部署与配置说明

## 1. 当前结论

每个用户分配独立 USDT-TRC20 地址的代码已经完成，地址按以下路径确定性派生：

```text
m/44'/195'/appid'/user_id'/0
```

同一套正式主种子、同一 `appid` 和同一用户 ID 永远得到同一个地址。数据库只保存地址和派生路径，不保存用户私钥。

生产环境当前拿不到地址的直接原因不是客户端，而是独立钱包服务没有配置 `TRON_MASTER_SEED_HEX`。健康检查会返回：

```json
{"address_derivation_enabled":false,"ok":true}
```

系统会在此状态下拒绝生成地址，防止使用临时密钥接收真实资产。

已经完成的链路：

- TP8 用户地址申请、地址列表、充值页接口。
- 独立 Go Wallet Service HD 地址派生和地址校验。
- 已固化 USDT Transfer 事件查询。
- Wallet Service 到 TP8 的 HMAC-SHA256 回调认证。
- `network + contract + txid + event_index` 唯一去重。
- 充值最低金额检查、幂等入账、账本记录和地址最近充值时间。
- 后台数字资产账户、充值地址、提币订单和链上配置入口。

仍需运营方提供的生产配置：正式主种子备份、TronGrid API Key 或自建 TRON 节点、提现热钱包和资源钱包。没有这些资产密钥时，程序不能代替资产负责人擅自生成并开放生产钱包。

## 2. 服务器目录

```text
TP8：/www/wwwroot/blin
Wallet Service：/opt/bim-tron-wallet/tron-wallet
Wallet Service 配置：/etc/bim/tron-wallet.env
systemd：bim-tron-wallet.service
监听：127.0.0.1:9088
```

Wallet Service 只能监听本机或钱包专用内网，禁止通过 Nginx 暴露到公网。

## 3. 第一次正式配置

### 3.1 生成并离线保管主种子

在隔离的可信设备生成至少 256 位随机值：

```bash
openssl rand -hex 64
```

要求：

1. 不要在聊天、工单、Git、截图或普通日志里传输主种子。
2. 至少制作两份加密离线备份，分别由两名负责人保管。
3. 在测试网执行一次“仅靠备份恢复同一地址”的恢复演练。
4. 备份与恢复未验证前，不允许打开充值。

编辑服务器文件：

```bash
chmod 600 /etc/bim/tron-wallet.env
vi /etc/bim/tron-wallet.env
```

正式配置示例：

```dotenv
# 只监听本机，不允许公网访问。
TRON_WALLET_LISTEN=127.0.0.1:9088

# TP8 与钱包服务共用的内部签名密钥，至少32个随机字符。
TRON_INTERNAL_SECRET=请填写现有内部随机密钥

# 正式 HD 主种子，只能存在钱包服务和离线备份中。
TRON_MASTER_SEED_HEX=请填写离线生成并完成备份的正式主种子

# TronGrid 或企业自建兼容事件接口。
TRON_EVENT_API_URL=https://api.trongrid.io

# TronGrid 控制台申请的 API Key；生产环境必须配置，避免公共限流漏扫。
TRON_API_KEY=请填写正式APIKey

# 必须使用业务域名，不能写 http://127.0.0.1/callback。
# 本机地址没有正确 Host 时会落入错误 Nginx 站点并返回404。
TRON_CALLBACK_URL=https://blcold.cn/callback
```

TP8 的 `/www/wwwroot/blin/.env` 只保存服务地址和内部认证密钥，不保存主种子：

```dotenv
[TRON]
# 钱包服务内网地址，禁止填写公网地址。
WALLET_SERVICE_URL = http://127.0.0.1:9088
# 必须与 /etc/bim/tron-wallet.env 的 TRON_INTERNAL_SECRET 完全一致。
INTERNAL_SECRET = 同一个内部随机密钥
# 主种子仅配置在独立钱包服务，不得写入TP8环境文件。
```

### 3.2 重启和健康检查

```bash
systemctl restart bim-tron-wallet
systemctl status bim-tron-wallet --no-pager
curl -fsS http://127.0.0.1:9088/health
journalctl -u bim-tron-wallet -n 100 --no-pager
```

必须看到：

```json
{"address_derivation_enabled":true,"ok":true}
```

日志不得持续出现 `callback status 404`、`unauthorized` 或 Tron API 限流错误。

## 4. 后台开启顺序

进入：

```text
钱包管理 -> 链上钱包配置
```

USDT-TRC20 主网合约：

```text
TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t
```

配置项：

- Wallet Service：`http://127.0.0.1:9088`
- Decimals：`6`
- 最低充值：按运营规则填写
- 最低提币、提币手续费和单日限额：按风控规则填写
- 站内转账：可独立开启
- 服务状态、充值、提币：按下列顺序开启

严格顺序：

1. 配置并验证正式主种子和 API Key。
2. 保持充值、提币关闭，生成两个测试用户地址。
3. 验证同一用户重复请求始终返回同一地址。
4. 在 Nile 测试网或隔离环境验证充值幂等和恢复流程。
5. 主网发送最小可控金额，确认只入账一次。
6. 开启服务状态和充值。
7. 完成热钱包、资源钱包、审批和广播确认后，最后开启提币。

后台菜单若刚部署后未出现，应退出后台并重新登录以刷新权限会话。钱包首页也提供了数字资产功能的直接入口。

## 5. 用户地址分配逻辑

客户端进入 USDT 充值页时调用业务 API。服务端流程为：

1. 校验登录、钱包状态、资产和网络配置。
2. 查询 `mr_wallet_chain_address` 是否已有绑定。
3. 已有绑定直接返回，绝不生成第二个地址。
4. 没有绑定时调用本机 Wallet Service 派生地址。
5. 数据库唯一键保证并发请求只能成功写入一个地址。
6. 返回地址给客户端显示二维码。

地址生成失败时客户端会显示明确的“链上充值暂未开放”，不会伪造地址或使用平台公共地址兜底。

## 6. 充值扫描和入账

Wallet Service 每 20 秒获取已启用的托管地址，并查询已确认的 USDT-TRC20 转入事件。每个事件回调 TP8 前均携带：

```text
X-BIM-Timestamp
X-BIM-Signature = HMAC-SHA256(timestamp + "\n" + raw_json, internal_secret)
```

TP8 只接受 30 秒时间窗内且签名正确的请求。入账唯一键为：

```text
network_id + contract_address + txid + event_index
```

钱包服务重启、网络重试或重复扫描不会重复增加余额。低于最低充值金额的事件会记录为 `below_minimum`，不会直接入账。

## 7. 验证清单

上线前逐项确认：

```text
[ ] 主种子有两份加密离线备份
[ ] 恢复演练能生成完全相同的地址
[ ] /etc/bim/tron-wallet.env 权限为600
[ ] Wallet Service 只监听127.0.0.1
[ ] health 的 address_derivation_enabled=true
[ ] TRON_CALLBACK_URL 使用正确HTTPS业务域名
[ ] TronGrid API Key有效且无持续限流
[ ] 同一用户并发申请只得到一个地址
[ ] 非法合约事件不能入账
[ ] 低于最小充值不入账
[ ] 同一txid/event_index重复回调只入账一次
[ ] 充值金额与链上6位精度一致
[ ] 数据库、业务余额和链上托管余额可对账
[ ] 提币未完成全链路前 withdraw_enabled=0
```

## 8. 故障关闭与回滚

发现节点异常、漏扫、余额异常或密钥风险时，立即在后台关闭：

```text
deposit_enabled = 0
withdraw_enabled = 0
```

站内转账可根据账本健康状况独立决定是否关闭。不要删除链事件、账本和提币订单；修复必须通过补偿分录和可审计状态迁移完成。

## 9. 当前不能直接代配的内容

以下内容属于真实资产控制权，必须由资产负责人提供或确认，不能写死在源码：

- 正式 HD 主种子及离线备份。
- TronGrid 企业 API Key 或自建节点地址。
- 提现热钱包私钥/HSM Key ID。
- Energy/TRX 资源钱包与归集策略。
- 热钱包限额、双人审批和告警接收人。

在这些配置完成之前，可以使用站内 USDT 账本和转账；用户链上充值地址、自动归集和链上提币必须保持关闭。
