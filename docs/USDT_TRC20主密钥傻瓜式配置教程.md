# BIM USDT-TRC20 主密钥傻瓜式配置教程

> 适用服务器：`139.196.166.181`
>
> 钱包服务配置文件：`/etc/bim/tron-wallet.env`
>
> 本教程只配置“每个用户一个 USDT-TRC20 地址”需要的主密钥和链查询参数。提币功能不要开启。

## 一、操作前必须知道

`TRON_MASTER_SEED_HEX` 是整套 TRON 钱包的总钥匙。

任何拿到它的人，都可能派生用户地址对应的私钥。因此：

- 不要把主密钥发到微信、QQ、邮箱、工单或聊天窗口。
- 不要把主密钥写入客户端、TP8 `.env`、数据库或 Git。
- 不要截图保存主密钥。
- 必须先做离线备份，再开放充值。
- 如果主密钥丢失，用户地址中的资产可能永远无法取回。

## 二、登录服务器

在 Termux 中执行：

```bash
ssh root@139.196.166.181
```

看到类似下面的提示，说明已经进入服务器：

```text
root@服务器名称:~#
```

后面的命令都在服务器里执行。

## 三、备份当前配置

直接复制执行：

```bash
cp /etc/bim/tron-wallet.env /etc/bim/tron-wallet.env.backup.$(date +%Y%m%d-%H%M%S)
```

检查备份是否存在：

```bash
ls -l /etc/bim/tron-wallet.env*
```

能看到一个带日期的 `.backup` 文件即可。

## 四、生成正式主密钥

### 4.1 生成密钥

执行：

```bash
openssl rand -hex 64
```

终端会显示一行很长的字符，例如：

```text
此处会显示128位十六进制字符
```

这行字符就是正式的 `TRON_MASTER_SEED_HEX`。

### 4.2 立即离线备份

准备两个不同的加密 U 盘或其他离线加密介质，将下面内容分别保存一份：

```text
项目名称：BIM
网络：TRON Mainnet
币种：USDT-TRC20
派生路径：m/44'/195'/appid'/user_id'/0
主密钥：填写刚才生成的完整字符
生成日期：填写当天日期
```

两份备份不要放在同一个地方。主密钥未完成离线备份前，不要继续开启充值。

## 五、申请 TronGrid API Key

需要在 TronGrid 官方控制台创建 API Key。

申请完成后会得到一个类似下面的值：

```text
TRON-PRO-API-KEY对应的字符串
```

这个值用于稳定查询链上 USDT 充值记录。没有 API Key 时可能被公共接口限流，因此生产环境不能留空。

暂时还没有 API Key 时，可以先完成主密钥配置和地址生成验证，但不能开放正式充值。

## 六、写入钱包服务配置

### 6.1 打开配置文件

执行：

```bash
nano /etc/bim/tron-wallet.env
```

如果提示没有 `nano`，执行：

```bash
vi /etc/bim/tron-wallet.env
```

### 6.2 检查并填写下面六项

配置文件中应当存在：

```dotenv
TRON_WALLET_LISTEN=127.0.0.1:9088
TRON_INTERNAL_SECRET=这里保留服务器原来的值
TRON_MASTER_SEED_HEX=这里填写刚才生成的主密钥
TRON_EVENT_API_URL=https://api.trongrid.io
TRON_API_KEY=这里填写申请到的TronGrid_API_Key
TRON_CALLBACK_URL=https://blcold.cn/callback
```

注意：

1. `TRON_INTERNAL_SECRET` 保留原值，不要删除或随便更换。
2. `TRON_MASTER_SEED_HEX` 等号后填写完整主密钥，中间不能有空格或换行。
3. `TRON_API_KEY` 等号后填写 TronGrid API Key。
4. `TRON_CALLBACK_URL` 必须是 `https://blcold.cn/callback`。
5. 不要在值两边添加中文引号。

正确示例：

```dotenv
TRON_MASTER_SEED_HEX=完整的128位十六进制字符
```

错误示例：

```dotenv
TRON_MASTER_SEED_HEX = “主密钥”
```

### 6.3 保存文件

使用 `nano`：

```text
按 Ctrl+O
按回车确认
按 Ctrl+X退出
```

使用 `vi`：

```text
按 Esc
输入 :wq
按回车
```

## 七、保护主密钥文件

复制执行：

```bash
chown root:root /etc/bim/tron-wallet.env
chmod 600 /etc/bim/tron-wallet.env
```

检查权限：

```bash
ls -l /etc/bim/tron-wallet.env
```

正确结果开头应当是：

```text
-rw-------
```

如果不是，请重新执行 `chmod 600`。

## 八、检查配置但不显示秘密

执行下面的命令。它只显示是否填写，不打印真实主密钥：

```bash
awk -F= '
/^TRON_MASTER_SEED_HEX=/{print "主密钥长度：" length($2) "，状态：" (length($2)>=64?"已填写":"未填写或太短")}
/^TRON_API_KEY=/{print "API Key状态：" (length($2)>0?"已填写":"未填写")}
/^TRON_CALLBACK_URL=/{print "回调地址：" $2}
' /etc/bim/tron-wallet.env
```

主密钥使用本教程的命令生成时，长度应当是 `128`。

## 九、重启钱包服务

执行：

```bash
systemctl restart bim-tron-wallet
```

等待两秒：

```bash
sleep 2
```

检查服务：

```bash
systemctl status bim-tron-wallet --no-pager
```

看到：

```text
Active: active (running)
```

说明服务已经启动。

## 十、检查主密钥是否生效

执行：

```bash
curl -fsS http://127.0.0.1:9088/health
```

正确结果：

```json
{"address_derivation_enabled":true,"ok":true}
```

如果仍然是：

```json
{"address_derivation_enabled":false,"ok":true}
```

说明主密钥没有被正确读取。按本教程“常见问题”检查。

## 十一、检查运行日志

执行：

```bash
journalctl -u bim-tron-wallet -n 100 --no-pager
```

正常情况下，不应该持续出现：

```text
callback status 404
unauthorized
invalid seed
tron api status 401
tron api status 403
tron api status 429
```

含义：

| 日志 | 原因 | 处理方法 |
|---|---|---|
| `callback status 404` | 回调地址错误 | 检查是否为 `https://blcold.cn/callback` |
| `unauthorized` | 两边内部密钥不一致 | 检查 TP8 与钱包服务的内部密钥 |
| `invalid seed` | 主密钥格式错误 | 重新检查是否为完整十六进制字符 |
| `tron api status 401/403` | API Key 无效 | 检查 TronGrid API Key |
| `tron api status 429` | 接口被限流 | 配置有效 API Key 或企业节点 |

## 十二、检查 TP8 内部连接配置

TP8 配置文件：

```text
/www/wwwroot/blin/.env
```

执行：

```bash
grep -A5 '^\[TRON\]' /www/wwwroot/blin/.env
```

应当包含：

```dotenv
[TRON]
WALLET_SERVICE_URL = http://127.0.0.1:9088
INTERNAL_SECRET = 服务器现有内部密钥
```

这里不能出现：

```text
TRON_MASTER_SEED_HEX
```

主密钥只能放在：

```text
/etc/bim/tron-wallet.env
```

## 十三、后台第一次配置

登录 BIM 后台，进入：

```text
钱包管理 -> 链上钱包配置
```

填写：

```text
网络：TRC20
币种：USDT
合约地址：TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t
Decimals：6
钱包服务：http://127.0.0.1:9088
最低充值：根据业务规则填写，例如1
```

第一次保存建议：

```text
服务状态：开启
站内转账：开启
充值：关闭
提币：关闭
```

不要一配置完就打开提币。

## 十四、生成测试用户地址

1. 使用一个没有真实资产的测试账号登录客户端。
2. 打开“我的 -> 钱包 -> USDT -> 充值”。
3. 系统应当显示一个以 `T` 开头的 TRON 地址。
4. 完整记录该测试地址。
5. 退出充值页后重新进入，地址必须保持不变。
6. 重启钱包服务，再次进入充值页，地址仍必须保持不变。

重启命令：

```bash
systemctl restart bim-tron-wallet
```

如果同一个用户前后生成了不同地址，不要开放充值，应立即停止检查。

## 十五、正式打开充值前的检查

以下条件全部满足才能打开充值：

```text
[ ] 主密钥已经制作两份加密离线备份
[ ] 已完成主密钥恢复演练
[ ] health返回address_derivation_enabled=true
[ ] TronGrid API Key已配置并且没有限流
[ ] 回调日志没有404和unauthorized
[ ] 同一用户重复查询得到同一个地址
[ ] 测试充值只入账一次
[ ] 重复回调不会重复增加余额
[ ] 数据库账本金额和链上金额一致
```

全部通过后，在后台打开：

```text
充值：开启
```

仍然保持：

```text
提币：关闭
```

## 十六、出现问题立即关闭

进入后台链上钱包配置，关闭：

```text
充值：关闭
提币：关闭
```

如果后台进不去，可先停止钱包服务：

```bash
systemctl stop bim-tron-wallet
```

恢复服务：

```bash
systemctl start bim-tron-wallet
```

不要直接删除用户地址、充值事件、账本或提币订单。

## 十七、恢复配置文件

先查看备份：

```bash
ls -lt /etc/bim/tron-wallet.env.backup.*
```

选择正确的备份文件后执行：

```bash
cp /etc/bim/tron-wallet.env.backup.具体日期时间 /etc/bim/tron-wallet.env
chmod 600 /etc/bim/tron-wallet.env
systemctl restart bim-tron-wallet
```

不要直接照抄“具体日期时间”，需要替换成服务器上真实存在的备份文件名。

## 十八、最终状态说明

完成本教程后：

- 每个用户可以分配一个独立 USDT-TRC20 地址。
- 同一个用户的地址保持固定。
- 系统可以扫描已确认的 USDT 充值并幂等入账。
- 主密钥只保存在独立钱包服务和离线备份中。

本教程不会自动开放链上提币。链上提币还需要单独配置热钱包、HSM/签名机、TRX/Energy 资源、审批、广播确认、对账和异常恢复。
