# BIM GasFree 傻瓜式配置与运营手册

> 适用范围：BIM 的 TP8 业务端、TRON 独立钱包服务、USDT-TRC20 充值与自动归集。
>
> 安全原则：主种子、GasFree API Secret、热钱包私钥只能存在于 `/etc/bim/tron-wallet.env`，不能填写到后台、数据库、客户端、Git 或聊天记录中。

## 一、上线后的地址规则

1. 普通 TRC20 用户地址生成接口已经关闭，调用会返回 HTTP 410。
2. 用户端不会展示历史普通地址，也不会把它用于新充值或新归集。
3. 新用户和未分配地址的老用户，只能获取 GasFree 充值地址。
4. 已生成的普通地址不删除私钥映射、不展示给用户，只保留后台只读扫描。
5. 用户误向旧地址充值时，系统仍能识别并入账，避免资金丢失；旧地址不得再次展示、复制或作为新业务地址。
6. 关闭 GasFree 时，不回退普通地址，客户端显示充值服务暂未开放。

## 二、配置前需要准备什么

请准备以下内容：

1. GasFree 官方控制台申请的 `API Key` 和 `API Secret`。
2. 已经使用的 `TRON_MASTER_SEED_HEX`。不能更换，否则同一用户的签名账户会变化。
3. 一个归集接收地址，即平台实际接收 USDT 的地址。
4. 可访问 TRON 节点的地址及 API Key；当前可以继续使用 TronGrid。
5. 数据库和 `/etc/bim/tron-wallet.env` 的离线备份。

## 三、先备份

在服务器执行：

```bash
mkdir -p /root/bim-backup/$(date +%Y%m%d-%H%M%S)
cp -a /www/wwwroot/blin /root/bim-backup/$(date +%Y%m%d-%H%M%S)/
cp -a /etc/bim/tron-wallet.env /root/bim-backup/$(date +%Y%m%d-%H%M%S)/tron-wallet.env
```

数据库按服务器现有账号执行全库备份。不要把备份放在网站可访问目录。

## 四、填写钱包服务配置

编辑：

```bash
nano /etc/bim/tron-wallet.env
```

填写或核对以下配置：

```dotenv
# GasFree 总开关。首次配置先保持 false。
TRON_GASFREE_ENABLED=false

# 自动归集执行开关。首次配置先保持 false。
TRON_GASFREE_AUTO_ENABLED=false

# 官方主网 API 地址，不要改成 HTTP。
TRON_GASFREE_API_URL=https://open.gasfree.io/tron

# GasFree 控制台申请的凭据。Secret 不能出现在后台或代码仓库。
TRON_GASFREE_API_KEY=这里填写API_KEY
TRON_GASFREE_API_SECRET=这里填写API_SECRET

# TRON 主网固定参数。
TRON_GASFREE_CHAIN_ID=728126428
TRON_GASFREE_VERIFYING_CONTRACT=TFFAMQLZybALaLb4uxHA9RBE7pxhUAjF3U

# 必须保持原主种子，禁止为了 GasFree 重新生成。
TRON_MASTER_SEED_HEX=这里保留现有主种子
```

设置权限：

```bash
chown root:root /etc/bim/tron-wallet.env
chmod 600 /etc/bim/tron-wallet.env
```

## 五、第一阶段：只开启查询，不自动归集

把配置改为：

```dotenv
TRON_GASFREE_ENABLED=true
TRON_GASFREE_AUTO_ENABLED=false
```

重启：

```bash
systemctl restart bim-tron-wallet
systemctl status bim-tron-wallet --no-pager
curl -s http://127.0.0.1:9088/health
```

健康检查必须满足：

```json
{
  "ok": true,
  "legacy_address_generation": false,
  "gasfree_enabled": true,
  "gasfree_credentials_ready": true,
  "gasfree_auto_enabled": false
}
```

如果 `gasfree_credentials_ready` 为 `false`，不要继续。

## 六、后台灰度开通

1. 登录后台。
2. 打开“数字钱包 -> GasFree 管理”。
3. 功能选择“开启”。
4. 自动归集保持“关闭”。
5. 灰度范围选择“白名单”。
6. 添加一个专门的小额测试账号。
7. 保存后，用该账号进入客户端数字钱包。
8. 点击充值，只能看到新的充值地址，不能看到历史普通地址。

后台与钱包进程是双开关：钱包进程关闭时后台不能强行启用；后台关闭时钱包进程不会为用户开放充值。

## 七、小额充值验收

首次只充值满足官方费用和后台最低净归集要求的小额金额。验收以下项目：

1. 用户充值地址与后台 GasFree 账户地址一致。
2. 充值达到链上确认后，用户 USDT 余额只增加一次。
3. 同一 `txid + log_index` 重复回调不会重复入账。
4. 后台账户页能看到链上余额、Nonce、激活状态、可提交状态和 Provider 冻结值。
5. 普通地址生成接口返回 410；客户端不会显示旧地址。

## 八、开启自动归集

确认小额充值正常后：

1. 在“归集管理”填写归集接收地址。
2. 在 GasFree 管理设置首次最高费用、后续最高费用、最低净归集和最高费用比例。
3. 后台开启“自动归集”。
4. 修改钱包服务：

```dotenv
TRON_GASFREE_AUTO_ENABLED=true
```

5. 重启钱包服务。

系统执行顺序：同步账户和官方费率、检查余额和冻结金额、检查费用上限、创建唯一任务、TIP-712 签名、提交官方接口、查询状态，只有 `SUCCEED + SOLIDITY` 才记为归集完成。

## 九、异常处理

### 1. Nonce 不匹配

系统不会使用旧 Nonce 无限重发。任务进入重试，下一轮先重新同步官方推荐 Nonce。

### 2. 签名错误、Token 不支持或 Provider 不匹配

属于永久错误，任务停止自动重试。保持自动归集关闭，核对主种子、主网控制器、Token 合约和 Provider。

### 3. 费用超过后台上限

不创建任务，不扣用户平台余额。管理员调整费用阈值前必须确认实际运营成本。

### 4. Provider 接口不可用

不生成普通地址，不切换旧归集逻辑。充值地址服务暂时不可用，已有地址继续扫描入账。

### 5. 关闭和回滚

先在后台关闭自动归集，再修改：

```dotenv
TRON_GASFREE_AUTO_ENABLED=false
TRON_GASFREE_ENABLED=false
```

然后重启。关闭后不会生成普通地址，也不会向客户端返回旧地址。数据库任务和流水保留用于审计，禁止直接删除。

## 十、安全检查清单

- [ ] `/etc/bim/tron-wallet.env` 权限为 `600`。
- [ ] 钱包服务只监听 `127.0.0.1:9088`。
- [ ] GasFree API URL 使用 HTTPS。
- [ ] API Secret、主种子和私钥没有进入 Git、数据库、后台页面或客户端日志。
- [ ] TP8 与钱包服务使用不少于 32 字符的独立 HMAC 密钥。
- [ ] 先白名单、后全量；先查询、后自动归集。
- [ ] 同一账户最多一个进行中的归集任务。
- [ ] 只有链上固化状态才标记成功。
- [ ] 每天核对用户负债、GasFree 地址余额、归集钱包到账和费用流水。

## 十一、日常巡检命令

```bash
systemctl status bim-tron-wallet --no-pager
journalctl -u bim-tron-wallet -n 200 --no-pager
curl -s http://127.0.0.1:9088/health
```

发现连续签名错误、Nonce 错误、Provider 不匹配或重复失败时，立即关闭自动归集，不要通过提高重试次数处理。
