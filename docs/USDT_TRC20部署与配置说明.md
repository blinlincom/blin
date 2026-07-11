# BIM USDT-TRC20 部署与配置说明

## 当前部署状态

已部署：

- TP8 数字资产总览接口。
- USDT 资产账户和复式账本。
- BIM 用户之间的 USDT 站内转账。
- 支付密码校验、钱包锁定校验、幂等号和参数哈希校验。
- USDT 提币申请、余额冻结和后台提币订单。
- 用户 TRC20 地址分配接口。
- 独立 Go Wallet Service。
- TRON HD 地址派生。
- TRON Base58Check 地址校验。
- 后台数字资产账户、地址、提币订单和链上配置页面。
- Flutter USDT 钱包、充值、站内转账、提币和账单页面。

当前安全关闭：

- 用户充值地址生成。
- TRC20 链上充值扫描和自动入账。
- 用户地址自动归集。
- 链上提币签名、广播和确认。

关闭原因：生产服务器尚未配置正式 HD 主种子/HSM、TRON FullNode、SolidityNode、提现热钱包和资源钱包。不得使用测试种子或随机临时私钥开放生产充值。

## 服务器位置

```text
TP8：/www/wwwroot/blin
Wallet Service：/opt/bim-tron-wallet/tron-wallet
Wallet Service 配置：/etc/bim/tron-wallet.env
systemd：bim-tron-wallet.service
监听：127.0.0.1:9088
```

服务只监听本机，不允许通过 Nginx 或公网暴露。

## 当前数据库配置

当前 `mr_wallet_chain_config` 默认配置：

```text
status = 0
deposit_enabled = 0
withdraw_enabled = 0
transfer_enabled = 1
wallet_service_url = http://127.0.0.1:9088
```

因此客户端可以查看 USDT 余额和进行站内转账，但不能生成充值地址或提交链上提币。

## 正式开放前的强制配置

### 1. 密钥体系

生产推荐使用 HSM/KMS。若首期必须使用独立签名机：

- 生成至少 256 位随机主种子；
- 主种子只能配置在独立 Wallet Service；
- TP8 `.env`、MySQL、Redis、Git 和日志中禁止出现主种子；
- 完成离线备份和地址恢复演练；
- 至少两名负责人分别保管恢复材料。

配置文件：

```text
/etc/bim/tron-wallet.env
```

```dotenv
TRON_WALLET_LISTEN=127.0.0.1:9088
TRON_INTERNAL_SECRET=<现有随机密钥，不要与其他系统共用>
TRON_MASTER_SEED_HEX=<正式主种子或改接HSM>
TRON_FULLNODE_URL=<正式FullNode>
TRON_SOLIDITYNODE_URL=<正式SolidityNode>
TRON_API_KEY=<节点需要时填写>
```

修改后：

```bash
systemctl restart bim-tron-wallet
curl http://127.0.0.1:9088/health
```

只有返回：

```json
{"ok":true,"address_derivation_enabled":true}
```

才说明地址派生已启用。

### 2. 后台链上配置

后台随机入口登录后：

```text
钱包管理 → 链上钱包配置
```

需要配置：

- 正式 USDT-TRC20 合约地址；
- Wallet Service 内网地址；
- 最低充值；
- 最低提币；
- 提币手续费；
- 单日提币上限；
- 服务状态；
- 充值开关；
- 站内转账开关；
- 提币开关。

顺序必须是：

1. 配置节点和正式密钥。
2. 完成测试网地址、充值、归集、提币测试。
3. 完成主网小额人工测试。
4. 先开启服务状态。
5. 再开启充值。
6. 充值和归集稳定后，最后开启提币。

## systemd 操作

```bash
systemctl status bim-tron-wallet
systemctl restart bim-tron-wallet
journalctl -u bim-tron-wallet -n 100 --no-pager
```

## 安全规则

- 不允许把 Wallet Service 映射到公网。
- 不允许后台查看或下载私钥。
- 不允许直接修改 `wallet_asset_account` 余额。
- 所有余额修复必须创建账本补偿分录。
- 已广播状态未知的提币不能直接退款。
- 对账异常时必须关闭 `withdraw_enabled`。
- 修改合约地址、主种子、节点和提现热钱包必须双人复核。

## 尚需实现的链上工作进程

在正式开放充值和提币前还必须完成并验证：

1. SolidityNode 固化区块扫描器。
2. USDT `Transfer` Event 解析。
3. `txid + log_index` 充值幂等入账。
4. 用户地址 Energy/TRX 资源准备。
5. 自动归集状态机。
6. 提现热钱包交易构建与隔离签名。
7. 广播结果查询和最终确认。
8. 热钱包、归集钱包、用户地址和用户负债对账。
9. 节点切换、漏扫重扫和未知交易恢复。

当前版本已为这些模块建立数据库表和服务边界，但没有在缺少正式密钥及节点的情况下伪造链上执行。

