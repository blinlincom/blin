<?php

declare(strict_types=1);

namespace app\admin\controller;

use app\common\support\ResponseHelper;
use app\common\support\WalletNoticeService;
use app\common\tool\WukongIM;
use think\facade\Db;
use think\facade\Request;
use think\facade\View;

class Wallet extends Backend
{
    public $no_need_login = [];
    public $no_need_right = [];

    public function index()
    {
        if (Request::isAjax()) {
            $limit = input('limit/d') ?: 10;
            $page = input('page/d') ?: 1;
            $query = Db::name('wallet_order')->alias('o')
                ->leftJoin('app a', 'a.appid=o.appid')
                ->leftJoin('user pu', 'pu.id=o.payer_id and pu.appid=o.appid')
                ->leftJoin('user ru', 'ru.id=o.payee_id and ru.appid=o.appid')
                ->field('o.*,a.appname,pu.username as payer_username,pu.nickname as payer_nickname,ru.username as payee_username,ru.nickname as payee_nickname');
            $this->applyOrderFilters($query);
            $rows = $query->order('o.id', 'desc')->page($page, $limit)->select()->toArray();

            $countQuery = Db::name('wallet_order')->alias('o');
            $this->applyOrderFilters($countQuery);
            return $this->tableResponse([
                'rows' => $this->formatOrderRows($rows),
                'total' => $countQuery->count(),
            ]);
        }
        return View::fetch();
    }

    public function asset_accounts()
    {
        if (Request::isAjax()) {
            $limit=input('limit/d')?:20;$page=input('page/d')?:1;$appid=input('appid/d');$username=trim((string)input('username',''));
            $query=Db::name('wallet_asset_account')->alias('wa')->leftJoin('user u','u.id=wa.user_id and u.appid=wa.appid')->leftJoin('app a','a.appid=wa.appid')->leftJoin('otc_asset x','x.id=wa.asset_id and x.appid=wa.appid')->field('wa.*,u.username,u.nickname,a.appname,x.symbol');
            if($appid>0)$query->where('wa.appid',$appid);if($username!=='')$query->where('u.username|u.nickname','like','%'.$username.'%');
            $count=clone $query;return $this->tableResponse(['rows'=>$query->order('wa.id desc')->page($page,$limit)->select()->toArray(),'total'=>$count->count()]);
        }
        return View::fetch();
    }

    public function chain_addresses()
    {
        if(Request::isAjax()){$limit=input('limit/d')?:20;$page=input('page/d')?:1;$query=Db::name('wallet_chain_address')->alias('ca')->leftJoin('user u','u.id=ca.user_id and u.appid=ca.appid')->leftJoin('app a','a.appid=ca.appid')->leftJoin('otc_asset x','x.id=ca.asset_id')->leftJoin('otc_network n','n.id=ca.network_id')->field('ca.*,u.username,u.nickname,a.appname,x.symbol,n.code network_code');return $this->tableResponse(['rows'=>$query->order('ca.id desc')->page($page,$limit)->select()->toArray(),'total'=>(clone $query)->count()]);}return View::fetch();
    }

    public function asset_withdrawals()
    {
        if(Request::isAjax()){$limit=input('limit/d')?:20;$page=input('page/d')?:1;$status=trim((string)input('status',''));$query=Db::name('wallet_withdraw_order')->alias('w')->leftJoin('user u','u.id=w.user_id and u.appid=w.appid')->leftJoin('app a','a.appid=w.appid')->leftJoin('otc_asset x','x.id=w.asset_id')->leftJoin('otc_network n','n.id=w.network_id')->field('w.*,u.username,u.nickname,a.appname,x.symbol,n.code network_code');if($status!=='')$query->where('w.status',$status);return $this->tableResponse(['rows'=>$query->order('w.id desc')->page($page,$limit)->select()->toArray(),'total'=>(clone $query)->count()]);}return View::fetch();
    }

    public function asset_chain_config()
    {
        if(Request::isPost()){$appid=input('appid/d');$assetId=input('asset_id/d');$networkId=input('network_id/d');if($appid<=0||$assetId<=0||$networkId<=0)return ResponseHelper::error('应用、资产和网络不能为空');$now=date('Y-m-d H:i:s');$values=['contract_address'=>mb_substr(trim((string)input('contract_address','')),0,64),'decimals'=>max(0,min(18,input('decimals/d')?:6)),'deposit_enabled'=>input('deposit_enabled/d')===1?1:0,'withdraw_enabled'=>input('withdraw_enabled/d')===1?1:0,'transfer_enabled'=>input('transfer_enabled/d')===1?1:0,'min_deposit'=>$this->assetAmount(input('min_deposit','1')),'min_withdraw'=>$this->assetAmount(input('min_withdraw','10')),'withdraw_fee'=>$this->assetAmount(input('withdraw_fee','1')),'daily_withdraw_limit'=>$this->assetAmount(input('daily_withdraw_limit','10000')),'wallet_service_url'=>mb_substr(trim((string)input('wallet_service_url','')),0,255),'status'=>input('status/d')===1?1:0,'update_time'=>$now];if(($values['deposit_enabled']===1||$values['withdraw_enabled']===1)&&($values['status']!==1||$values['wallet_service_url']===''||$values['contract_address']===''))return ResponseHelper::error('开放链上功能前必须配置合约地址和钱包服务');$row=Db::name('wallet_chain_config')->where(['appid'=>$appid,'asset_id'=>$assetId,'network_id'=>$networkId])->find();if($row)Db::name('wallet_chain_config')->where('id',(int)$row['id'])->update($values+['config_version'=>Db::raw('config_version+1')]);else Db::name('wallet_chain_config')->insert($values+['appid'=>$appid,'asset_id'=>$assetId,'network_id'=>$networkId,'config_version'=>1,'create_time'=>$now]);return ResponseHelper::success('配置已保存');}
        $rows=Db::name('otc_asset')->alias('a')->join('otc_asset_network an','an.asset_id=a.id and an.appid=a.appid')->join('otc_network n','n.id=an.network_id and n.appid=a.appid')->leftJoin('wallet_chain_config c','c.appid=a.appid and c.asset_id=a.id and c.network_id=n.id')->leftJoin('app p','p.appid=a.appid')->where('a.symbol','USDT')->whereIn('n.code',['TRC20','TRON'])->field('a.appid,p.appname,a.id asset_id,a.symbol,n.id network_id,n.code network_code,c.*')->select()->toArray();View::assign('rows',$rows);return View::fetch();
    }

    public function asset_exchange()
    {
        if(Request::isPost()){$id=input('id/d');$row=Db::name('wallet_exchange_config')->where('id',$id)->find();if(!$row)return ResponseHelper::error('闪兑配置不存在');$rate=$this->assetAmount(input('rate','0'));$fee=trim((string)input('fee_rate','0'));$min=$this->assetAmount(input('min_amount','1'));$max=$this->assetAmount(input('max_amount','10000'));$daily=$this->assetAmount(input('daily_limit','50000'));if(bccomp($rate,'0',8)<=0)return ResponseHelper::error('汇率必须大于0');if(!preg_match('/^\d+(\.\d{1,6})?$/',$fee)||bccomp($fee,'100',6)>=0)return ResponseHelper::error('手续费率必须在0到100之间');if(bccomp($max,$min,8)<0||bccomp($daily,$min,8)<0)return ResponseHelper::error('限额配置不正确');Db::name('wallet_exchange_config')->where('id',$id)->update(['rate'=>$rate,'fee_rate'=>$fee,'min_amount'=>$min,'max_amount'=>$max,'daily_limit'=>$daily,'quote_ttl'=>max(15,min(300,input('quote_ttl/d')?:60)),'status'=>input('status/d')===1?1:0,'config_version'=>Db::raw('config_version+1'),'update_time'=>date('Y-m-d H:i:s')]);return ResponseHelper::success('闪兑配置已保存');}
        if(Request::isAjax()){$limit=input('limit/d')?:20;$page=input('page/d')?:1;$query=Db::name('wallet_exchange_order')->alias('o')->leftJoin('user u','u.id=o.user_id and u.appid=o.appid')->leftJoin('app a','a.appid=o.appid')->field('o.*,u.username,u.nickname,a.appname');return $this->tableResponse(['rows'=>$query->order('o.id desc')->page($page,$limit)->select()->toArray(),'total'=>(clone $query)->count()]);}
        $configs=Db::name('wallet_exchange_config')->alias('c')->join('otc_asset x','x.id=c.source_asset_id and x.appid=c.appid')->leftJoin('app a','a.appid=c.appid')->field('c.*,x.symbol,a.appname')->select()->toArray();View::assign('configs',$configs);return View::fetch();
    }

    public function bills()
    {
        if (Request::isAjax()) {
            $limit = input('limit/d') ?: 10;
            $page = input('page/d') ?: 1;
            $query = Db::name('transaction_statement')->alias('b')
                ->leftJoin('app a', 'a.appid=b.appid')
                ->leftJoin('user u', 'u.id=b.userid and u.appid=b.appid')
                ->where('b.type', 0)
                ->field('b.*,a.appname,u.username,u.nickname');
            $this->applyBillFilters($query);
            $rows = $query->order('b.id', 'desc')->page($page, $limit)->select()->toArray();

            $countQuery = Db::name('transaction_statement')->alias('b')
                ->leftJoin('user u', 'u.id=b.userid and u.appid=b.appid')
                ->where('b.type', 0);
            $this->applyBillFilters($countQuery);
            return $this->tableResponse([
                'rows' => $this->formatBillRows($rows),
                'total' => $countQuery->count(),
            ]);
        }
        return View::fetch();
    }

    public function pay_passwords()
    {
        if (Request::isAjax()) {
            $limit = input('limit/d') ?: 10;
            $page = input('page/d') ?: 1;
            $query = Db::name('wallet_pay_password')->alias('p')
                ->leftJoin('app a', 'a.appid=p.appid')
                ->leftJoin('user u', 'u.id=p.user_id and u.appid=p.appid')
                ->field('p.*,a.appname,u.username,u.nickname,u.mobile,u.email');
            $this->applyPayPasswordFilters($query);
            $rows = $query->order('p.id', 'desc')->page($page, $limit)->select()->toArray();

            $countQuery = Db::name('wallet_pay_password')->alias('p')
                ->leftJoin('user u', 'u.id=p.user_id and u.appid=p.appid');
            $this->applyPayPasswordFilters($countQuery);
            return $this->tableResponse([
                'rows' => $this->formatPayPasswordRows($rows),
                'total' => $countQuery->count(),
            ]);
        }
        return View::fetch();
    }

    public function risk()
    {
        if (Request::isAjax()) {
            $limit = input('limit/d') ?: 10;
            $page = input('page/d') ?: 1;
            $query = Db::name('user')->alias('u')
                ->leftJoin('app a', 'a.appid=u.appid')
                ->field('u.id,u.appid,u.username,u.nickname,u.mobile,u.email,u.money,u.wallet_status,u.wallet_frozen_money,u.wallet_lock_reason,u.wallet_lock_time,u.wallet_unlock_time,a.appname');
            $this->applyRiskFilters($query);
            $rows = $query->order('u.id', 'desc')->page($page, $limit)->select()->toArray();

            $countQuery = Db::name('user')->alias('u');
            $this->applyRiskFilters($countQuery);
            return $this->tableResponse([
                'rows' => $this->formatRiskRows($rows),
                'total' => $countQuery->count(),
            ]);
        }
        return View::fetch();
    }

    public function merchants()
    {
        if (Request::isAjax()) {
            $limit = input('limit/d') ?: 10;
            $page = input('page/d') ?: 1;
            $query = Db::name('user')->alias('u')
                ->leftJoin('app a', 'a.appid=u.appid')
                ->field('u.id,u.appid,u.username,u.nickname,u.mobile,u.email,u.money,u.wallet_status,u.merchant_status,u.merchant_name,u.merchant_open_time,u.merchant_close_time,u.merchant_admin_id,a.appname');
            $this->applyMerchantFilters($query);
            $rows = $query->order('u.id', 'desc')->page($page, $limit)->select()->toArray();

            $countQuery = Db::name('user')->alias('u');
            $this->applyMerchantFilters($countQuery);
            return $this->tableResponse([
                'rows' => $this->formatMerchantRows($rows),
                'total' => $countQuery->count(),
            ]);
        }
        return View::fetch();
    }

    public function risk_logs()
    {
        if (Request::isAjax()) {
            $limit = input('limit/d') ?: 10;
            $page = input('page/d') ?: 1;
            $query = Db::name('wallet_risk_log')->alias('l')
                ->leftJoin('app a', 'a.appid=l.appid')
                ->leftJoin('user u', 'u.id=l.user_id and u.appid=l.appid')
                ->leftJoin('admin ad', 'ad.id=l.admin_id')
                ->field('l.*,a.appname,u.username,u.nickname,ad.nickname as admin_nickname,ad.username as admin_username');
            $this->applyRiskLogFilters($query);
            $rows = $query->order('l.id', 'desc')->page($page, $limit)->select()->toArray();

            $countQuery = Db::name('wallet_risk_log')->alias('l')
                ->leftJoin('user u', 'u.id=l.user_id and u.appid=l.appid');
            $this->applyRiskLogFilters($countQuery);
            return $this->tableResponse([
                'rows' => $this->formatRiskLogRows($rows),
                'total' => $countQuery->count(),
            ]);
        }
        return $this->tableResponse(['rows' => [], 'total' => 0]);
    }

    public function lock_wallet()
    {
        $userId = input('user_id/d');
        $appid = input('appid/d');
        $reason = mb_substr(trim((string)input('reason', '')), 0, 255);
        $noticeUser = [];
        if ($userId <= 0 || $appid <= 0) {
            return ResponseHelper::error('用户不存在');
        }
        if ($reason === '') {
            return ResponseHelper::error('锁定原因不能为空');
        }
        Db::startTrans();
        try {
            $user = Db::name('user')->where('id', $userId)->where('appid', $appid)->lock(true)->find();
            if (!$user) {
                throw new \Exception('用户不存在');
            }
            $beforeStatus = (int)($user['wallet_status'] ?? 1);
            $beforeFrozen = $this->amountLabel($user['wallet_frozen_money'] ?? 0);
            Db::name('user')->where('id', $userId)->where('appid', $appid)->update([
                'wallet_status' => 2,
                'wallet_lock_reason' => $reason,
                'wallet_lock_time' => date('Y-m-d H:i:s'),
                'wallet_lock_admin_id' => $this->adminId(),
            ]);
            $this->writeRiskLog($user, 'lock', '0.00', $beforeStatus, 2, $beforeFrozen, $beforeFrozen, $reason);
            $noticeUser = $user;
            $noticeUser['wallet_status'] = 2;
            $noticeUser['wallet_lock_reason'] = $reason;
            Db::commit();
        } catch (\Throwable $e) {
            Db::rollback();
            return ResponseHelper::error($e->getMessage());
        }
        $this->sendWalletRiskNotice($noticeUser, 'wallet_lock', '0.00', $reason);
        return ResponseHelper::success('钱包已锁定');
    }

    public function unlock_wallet()
    {
        $userId = input('user_id/d');
        $appid = input('appid/d');
        $reason = mb_substr(trim((string)input('reason', '')), 0, 255);
        $noticeUser = [];
        if ($userId <= 0 || $appid <= 0) {
            return ResponseHelper::error('用户不存在');
        }
        Db::startTrans();
        try {
            $user = Db::name('user')->where('id', $userId)->where('appid', $appid)->lock(true)->find();
            if (!$user) {
                throw new \Exception('用户不存在');
            }
            $beforeStatus = (int)($user['wallet_status'] ?? 1);
            $beforeFrozen = $this->amountLabel($user['wallet_frozen_money'] ?? 0);
            Db::name('user')->where('id', $userId)->where('appid', $appid)->update([
                'wallet_status' => 1,
                'wallet_lock_reason' => '',
                'wallet_unlock_time' => date('Y-m-d H:i:s'),
                'wallet_unlock_admin_id' => $this->adminId(),
            ]);
            $this->writeRiskLog($user, 'unlock', '0.00', $beforeStatus, 1, $beforeFrozen, $beforeFrozen, $reason);
            $noticeUser = $user;
            $noticeUser['wallet_status'] = 1;
            $noticeUser['wallet_lock_reason'] = '';
            Db::commit();
        } catch (\Throwable $e) {
            Db::rollback();
            return ResponseHelper::error($e->getMessage());
        }
        $this->sendWalletRiskNotice($noticeUser, 'wallet_unlock', '0.00', $reason);
        return ResponseHelper::success('钱包已解锁');
    }

    public function freeze_balance()
    {
        $userId = input('user_id/d');
        $appid = input('appid/d');
        $reason = mb_substr(trim((string)input('reason', '')), 0, 255);
        $noticeUser = [];
        if ($userId <= 0 || $appid <= 0) {
            return ResponseHelper::error('用户不存在');
        }
        if ($reason === '') {
            return ResponseHelper::error('冻结原因不能为空');
        }
        try {
            $amount = $this->normalizeMoney(input('amount', ''));
        } catch (\Throwable $e) {
            return ResponseHelper::error($e->getMessage());
        }
        Db::startTrans();
        try {
            $user = Db::name('user')->where('id', $userId)->where('appid', $appid)->lock(true)->find();
            if (!$user) {
                throw new \Exception('用户不存在');
            }
            $beforeStatus = (int)($user['wallet_status'] ?? 1);
            $beforeFrozen = $this->amountLabel($user['wallet_frozen_money'] ?? 0);
            if ($this->amountCompare($this->availableMoney($user), $amount) < 0) {
                throw new \Exception('冻结金额不能超过可用余额');
            }
            $freezeNo = $this->riskNo('FRZ');
            Db::name('wallet_freeze')->insert([
                'appid' => $appid,
                'user_id' => $userId,
                'freeze_no' => $freezeNo,
                'original_amount' => $amount,
                'amount' => $amount,
                'status' => 1,
                'reason' => $reason,
                'admin_id' => $this->adminId(),
                'create_time' => date('Y-m-d H:i:s'),
                'update_time' => date('Y-m-d H:i:s'),
            ]);
            Db::name('user')->where('id', $userId)->where('appid', $appid)->update([
                'wallet_frozen_money' => Db::raw('wallet_frozen_money + ' . $amount),
            ]);
            $afterFrozen = $this->amountAdd($beforeFrozen, $amount);
            $this->writeRiskLog($user, 'freeze', $amount, $beforeStatus, $beforeStatus, $beforeFrozen, $afterFrozen, $reason);
            $noticeUser = $user;
            $noticeUser['wallet_frozen_money'] = $afterFrozen;
            Db::commit();
        } catch (\Throwable $e) {
            Db::rollback();
            return ResponseHelper::error($e->getMessage());
        }
        $this->sendWalletRiskNotice($noticeUser, 'wallet_freeze', $amount, $reason);
        return ResponseHelper::success('余额已冻结');
    }

    public function unfreeze_balance()
    {
        $userId = input('user_id/d');
        $appid = input('appid/d');
        $reason = mb_substr(trim((string)input('reason', '')), 0, 255);
        $noticeUser = [];
        if ($userId <= 0 || $appid <= 0) {
            return ResponseHelper::error('用户不存在');
        }
        if ($reason === '') {
            return ResponseHelper::error('解冻原因不能为空');
        }
        try {
            $amount = $this->normalizeMoney(input('amount', ''));
        } catch (\Throwable $e) {
            return ResponseHelper::error($e->getMessage());
        }
        Db::startTrans();
        try {
            $user = Db::name('user')->where('id', $userId)->where('appid', $appid)->lock(true)->find();
            if (!$user) {
                throw new \Exception('用户不存在');
            }
            $beforeStatus = (int)($user['wallet_status'] ?? 1);
            $beforeFrozen = $this->amountLabel($user['wallet_frozen_money'] ?? 0);
            if ($this->amountCompare($beforeFrozen, $amount) < 0) {
                throw new \Exception('解冻金额不能超过冻结余额');
            }
            $remaining = $amount;
            $records = Db::name('wallet_freeze')
                ->where('appid', $appid)
                ->where('user_id', $userId)
                ->where('status', 1)
                ->order('id', 'asc')
                ->lock(true)
                ->select()
                ->toArray();
            foreach ($records as $record) {
                if ($this->amountCompare($remaining, '0.00') <= 0) {
                    break;
                }
                $recordAmount = $this->amountLabel($record['amount'] ?? 0);
                $deduct = $this->amountCompare($recordAmount, $remaining) > 0 ? $remaining : $recordAmount;
                $left = $this->amountSub($recordAmount, $deduct);
                Db::name('wallet_freeze')->where('id', (int)$record['id'])->update([
                    'amount' => $left,
                    'status' => $this->amountCompare($left, '0.00') <= 0 ? 2 : 1,
                    'unfreeze_admin_id' => $this->adminId(),
                    'unfreeze_reason' => $reason,
                    'unfreeze_time' => date('Y-m-d H:i:s'),
                    'update_time' => date('Y-m-d H:i:s'),
                ]);
                $remaining = $this->amountSub($remaining, $deduct);
            }
            if ($this->amountCompare($remaining, '0.00') > 0) {
                throw new \Exception('冻结记录余额不足');
            }
            Db::name('user')->where('id', $userId)->where('appid', $appid)->update([
                'wallet_frozen_money' => Db::raw('GREATEST(wallet_frozen_money - ' . $amount . ', 0)'),
            ]);
            $afterFrozen = $this->amountSub($beforeFrozen, $amount);
            $this->writeRiskLog($user, 'unfreeze', $amount, $beforeStatus, $beforeStatus, $beforeFrozen, $afterFrozen, $reason);
            $noticeUser = $user;
            $noticeUser['wallet_frozen_money'] = $afterFrozen;
            Db::commit();
        } catch (\Throwable $e) {
            Db::rollback();
            return ResponseHelper::error($e->getMessage());
        }
        $this->sendWalletRiskNotice($noticeUser, 'wallet_unfreeze', $amount, $reason);
        return ResponseHelper::success('余额已解冻');
    }

    public function reset_pay_password()
    {
        $id = input('id/d');
        if ($id <= 0) {
            return ResponseHelper::error('记录不存在');
        }
        $row = Db::name('wallet_pay_password')->where('id', $id)->find();
        if (!$row) {
            return ResponseHelper::error('记录不存在');
        }
        Db::name('wallet_pay_password')->where('id', $id)->update([
            'salt' => '',
            'password_hash' => '',
            'status' => 0,
            'failed_count' => 0,
            'locked_until' => null,
            'last_failed_time' => null,
            'reset_time' => date('Y-m-d H:i:s'),
            'reset_admin_id' => $this->adminId(),
            'update_time' => date('Y-m-d H:i:s'),
        ]);
        return ResponseHelper::success('支付密码已重置，用户需重新设置');
    }

    public function unlock_pay_password()
    {
        $id = input('id/d');
        if ($id <= 0) {
            return ResponseHelper::error('记录不存在');
        }
        $row = Db::name('wallet_pay_password')->where('id', $id)->find();
        if (!$row) {
            return ResponseHelper::error('记录不存在');
        }
        if ((string)($row['password_hash'] ?? '') === '' || (int)($row['status'] ?? 0) === 0) {
            return ResponseHelper::error('用户未设置支付密码');
        }
        Db::name('wallet_pay_password')->where('id', $id)->update([
            'status' => 1,
            'failed_count' => 0,
            'locked_until' => null,
            'last_failed_time' => null,
            'unlock_time' => date('Y-m-d H:i:s'),
            'unlock_admin_id' => $this->adminId(),
            'update_time' => date('Y-m-d H:i:s'),
        ]);
        return ResponseHelper::success('解锁成功');
    }

    public function enable_merchant()
    {
        $userId = input('user_id/d');
        $appid = input('appid/d');
        $merchantName = mb_substr(trim((string)input('merchant_name', '')), 0, 120);
        $reason = mb_substr(trim((string)input('reason', '')), 0, 255);
        if ($userId <= 0 || $appid <= 0) {
            return ResponseHelper::error('用户不存在');
        }
        Db::startTrans();
        try {
            $user = Db::name('user')->where('id', $userId)->where('appid', $appid)->lock(true)->find();
            if (!$user) {
                throw new \Exception('用户不存在');
            }
            if ($merchantName === '') {
                $merchantName = trim((string)($user['nickname'] ?? '')) ?: (string)($user['username'] ?? '');
            }
            Db::name('user')->where('id', $userId)->where('appid', $appid)->update([
                'merchant_status' => 1,
                'merchant_name' => $merchantName,
                'merchant_open_time' => date('Y-m-d H:i:s'),
                'merchant_close_time' => null,
                'merchant_admin_id' => $this->adminId(),
            ]);
            $this->writeRiskLog($user, 'merchant_enable', '0.00', (int)($user['wallet_status'] ?? 1), (int)($user['wallet_status'] ?? 1), $this->amountLabel($user['wallet_frozen_money'] ?? 0), $this->amountLabel($user['wallet_frozen_money'] ?? 0), $reason);
            Db::commit();
        } catch (\Throwable $e) {
            Db::rollback();
            return ResponseHelper::error($e->getMessage());
        }
        return ResponseHelper::success('商户权限已开通');
    }

    public function disable_merchant()
    {
        $userId = input('user_id/d');
        $appid = input('appid/d');
        $reason = mb_substr(trim((string)input('reason', '')), 0, 255);
        if ($userId <= 0 || $appid <= 0) {
            return ResponseHelper::error('用户不存在');
        }
        if ($reason === '') {
            return ResponseHelper::error('停用原因不能为空');
        }
        Db::startTrans();
        try {
            $user = Db::name('user')->where('id', $userId)->where('appid', $appid)->lock(true)->find();
            if (!$user) {
                throw new \Exception('用户不存在');
            }
            Db::name('user')->where('id', $userId)->where('appid', $appid)->update([
                'merchant_status' => 2,
                'merchant_close_time' => date('Y-m-d H:i:s'),
                'merchant_admin_id' => $this->adminId(),
            ]);
            $this->writeRiskLog($user, 'merchant_disable', '0.00', (int)($user['wallet_status'] ?? 1), (int)($user['wallet_status'] ?? 1), $this->amountLabel($user['wallet_frozen_money'] ?? 0), $this->amountLabel($user['wallet_frozen_money'] ?? 0), $reason);
            Db::commit();
        } catch (\Throwable $e) {
            Db::rollback();
            return ResponseHelper::error($e->getMessage());
        }
        return ResponseHelper::success('商户权限已停用');
    }

    protected function applyOrderFilters($query): void
    {
        if ((string)input('appid', '') !== '') {
            $query->where('o.appid', (int)input('appid'));
        }
        if ((string)input('order_no', '') !== '') {
            $query->whereLike('o.order_no', '%' . trim((string)input('order_no')) . '%');
        }
        if ((string)input('status', '') !== '') {
            $query->where('o.status', (int)input('status'));
        }
        if ((string)input('order_type', '') !== '') {
            $query->where('o.order_type', trim((string)input('order_type')));
        }
        if ((string)input('user_id', '') !== '') {
            $userId = (int)input('user_id');
            $query->where(function ($query) use ($userId) {
                $query->where('o.payer_id', $userId)->whereOr('o.payee_id', $userId);
            });
        }
    }

    protected function applyBillFilters($query): void
    {
        if ((string)input('appid', '') !== '') {
            $query->where('b.appid', (int)input('appid'));
        }
        if ((string)input('username', '') !== '') {
            $keyword = trim((string)input('username'));
            $query->whereLike('u.username|u.nickname', '%' . $keyword . '%');
        }
        if ((string)input('scene', '') !== '') {
            $scene = trim((string)input('scene'));
            if ($scene === 'income') {
                $query->whereLike('b.transaction_amount', '+%');
            } elseif ($scene === 'expense') {
                $query->whereLike('b.transaction_amount', '-%');
            } elseif ($scene === 'withdraw') {
                $query->where('b.transaction_type', 7);
            } elseif ($scene === 'charge') {
                $query->where('b.transaction_type', 8);
            } elseif ($scene === 'im') {
                $query->where('b.transaction_type', 9);
            } elseif ($scene === 'scan') {
                $query->where('b.transaction_type', 11);
            }
        }
    }

    protected function applyPayPasswordFilters($query): void
    {
        if ((string)input('appid', '') !== '') {
            $query->where('p.appid', (int)input('appid'));
        }
        if ((string)input('username', '') !== '') {
            $keyword = trim((string)input('username'));
            $query->whereLike('u.username|u.nickname', '%' . $keyword . '%');
        }
        if ((string)input('status', '') !== '') {
            $query->where('p.status', (int)input('status'));
        }
    }

    protected function applyRiskFilters($query): void
    {
        if ((string)input('appid', '') !== '') {
            $query->where('u.appid', (int)input('appid'));
        }
        if ((string)input('user_id', '') !== '') {
            $query->where('u.id', (int)input('user_id'));
        }
        if ((string)input('username', '') !== '') {
            $keyword = trim((string)input('username'));
            $query->whereLike('u.username|u.nickname|u.mobile|u.email', '%' . $keyword . '%');
        }
        if ((string)input('wallet_status', '') !== '') {
            $query->where('u.wallet_status', (int)input('wallet_status'));
        }
        if ((string)input('frozen', '') === '1') {
            $query->where('u.wallet_frozen_money', '>', 0);
        }
    }

    protected function applyMerchantFilters($query): void
    {
        if ((string)input('appid', '') !== '') {
            $query->where('u.appid', (int)input('appid'));
        }
        if ((string)input('user_id', '') !== '') {
            $query->where('u.id', (int)input('user_id'));
        }
        if ((string)input('username', '') !== '') {
            $keyword = trim((string)input('username'));
            $query->whereLike('u.username|u.nickname|u.mobile|u.email|u.merchant_name', '%' . $keyword . '%');
        }
        if ((string)input('merchant_status', '') !== '') {
            $query->where('u.merchant_status', (int)input('merchant_status'));
        }
    }

    protected function applyRiskLogFilters($query): void
    {
        if ((string)input('appid', '') !== '') {
            $query->where('l.appid', (int)input('appid'));
        }
        if ((string)input('user_id', '') !== '') {
            $query->where('l.user_id', (int)input('user_id'));
        }
        if ((string)input('username', '') !== '') {
            $keyword = trim((string)input('username'));
            $query->whereLike('u.username|u.nickname', '%' . $keyword . '%');
        }
        if ((string)input('action', '') !== '') {
            $query->where('l.action', trim((string)input('action')));
        }
    }

    protected function formatOrderRows(array $rows): array
    {
        foreach ($rows as &$row) {
            $row['amount_label'] = $this->amountLabel($row['amount'] ?? 0);
            $row['order_type_name'] = $row['order_type'] === 'pay' ? '付款码' : '收款码';
            $row['status_name'] = $this->orderStatusName((int)$row['status']);
            $row['payer_name'] = trim((string)($row['payer_nickname'] ?? '')) ?: (string)($row['payer_username'] ?? '');
            $row['payee_name'] = trim((string)($row['payee_nickname'] ?? '')) ?: (string)($row['payee_username'] ?? '');
            unset($row['qr_token_hash']);
        }
        unset($row);
        return $rows;
    }

    protected function formatBillRows(array $rows): array
    {
        foreach ($rows as &$row) {
            $raw = (string)($row['transaction_amount'] ?? '0');
            $amount = ltrim($raw, '+-');
            $row['amount_label'] = (($raw[0] ?? '') === '-' ? '-' : '+') . $this->amountLabel($amount);
            $row['direction_name'] = (($raw[0] ?? '') === '-') ? '支出' : '收入';
            $row['scene_name'] = $this->billSceneName((int)($row['transaction_type'] ?? 0));
            $row['user_name'] = trim((string)($row['nickname'] ?? '')) ?: (string)($row['username'] ?? '');
        }
        unset($row);
        return $rows;
    }

    protected function formatPayPasswordRows(array $rows): array
    {
        foreach ($rows as &$row) {
            $row['user_name'] = trim((string)($row['nickname'] ?? '')) ?: (string)($row['username'] ?? '');
            $row['status_name'] = $this->payPasswordStatusName((int)($row['status'] ?? 0));
            $row['locked_name'] = $this->payPasswordLocked($row) ? '已锁定' : '正常';
            $row['mobile_mask'] = $this->maskMobile((string)($row['mobile'] ?? ''));
            $row['email_mask'] = $this->maskEmail((string)($row['email'] ?? ''));
            unset($row['salt'], $row['password_hash']);
        }
        unset($row);
        return $rows;
    }

    protected function formatRiskRows(array $rows): array
    {
        foreach ($rows as &$row) {
            $row['user_name'] = trim((string)($row['nickname'] ?? '')) ?: (string)($row['username'] ?? '');
            $row['mobile_mask'] = $this->maskMobile((string)($row['mobile'] ?? ''));
            $row['email_mask'] = $this->maskEmail((string)($row['email'] ?? ''));
            $row['balance_label'] = $this->amountLabel($row['money'] ?? 0);
            $row['frozen_label'] = $this->amountLabel($row['wallet_frozen_money'] ?? 0);
            $row['available_label'] = $this->availableMoney($row);
            $row['wallet_status'] = (int)($row['wallet_status'] ?? 1);
            $row['wallet_status_name'] = $row['wallet_status'] === 2 ? '已锁定' : '正常';
        }
        unset($row);
        return $rows;
    }

    protected function formatMerchantRows(array $rows): array
    {
        foreach ($rows as &$row) {
            $row['user_name'] = trim((string)($row['nickname'] ?? '')) ?: (string)($row['username'] ?? '');
            $row['merchant_name'] = trim((string)($row['merchant_name'] ?? ''));
            $row['mobile_mask'] = $this->maskMobile((string)($row['mobile'] ?? ''));
            $row['email_mask'] = $this->maskEmail((string)($row['email'] ?? ''));
            $row['balance_label'] = $this->amountLabel($row['money'] ?? 0);
            $row['wallet_status'] = (int)($row['wallet_status'] ?? 1);
            $row['wallet_status_name'] = $row['wallet_status'] === 2 ? '已锁定' : '正常';
            $row['merchant_status'] = (int)($row['merchant_status'] ?? 0);
            $row['merchant_status_name'] = $this->merchantStatusName($row['merchant_status']);
        }
        unset($row);
        return $rows;
    }

    protected function formatRiskLogRows(array $rows): array
    {
        foreach ($rows as &$row) {
            $row['user_name'] = trim((string)($row['nickname'] ?? '')) ?: (string)($row['username'] ?? '');
            $row['admin_name'] = trim((string)($row['admin_nickname'] ?? '')) ?: (string)($row['admin_username'] ?? '');
            $row['action_name'] = match ((string)($row['action'] ?? '')) {
                'lock' => '锁定钱包',
                'unlock' => '解锁钱包',
                'freeze' => '冻结余额',
                'unfreeze' => '解冻余额',
                'merchant_enable' => '开通商户',
                'merchant_disable' => '停用商户',
                default => (string)($row['action'] ?? ''),
            };
            $row['amount_label'] = $this->amountLabel($row['amount'] ?? 0);
            $row['before_frozen_label'] = $this->amountLabel($row['before_frozen_money'] ?? 0);
            $row['after_frozen_label'] = $this->amountLabel($row['after_frozen_money'] ?? 0);
        }
        unset($row);
        return $rows;
    }

    protected function payPasswordLocked(array $row): bool
    {
        if ((int)($row['status'] ?? 0) === 2) {
            return true;
        }
        $lockedUntil = strtotime((string)($row['locked_until'] ?? ''));
        return $lockedUntil > time();
    }

    protected function payPasswordStatusName(int $status): string
    {
        return match ($status) {
            1 => '已设置',
            2 => '已锁定',
            default => '未设置',
        };
    }

    protected function merchantStatusName(int $status): string
    {
        return match ($status) {
            1 => '已开通',
            2 => '已停用',
            default => '未开通',
        };
    }

    protected function maskMobile(string $mobile): string
    {
        if (strlen($mobile) < 7) {
            return $mobile;
        }
        return substr($mobile, 0, 3) . '****' . substr($mobile, -4);
    }

    protected function maskEmail(string $email): string
    {
        $parts = explode('@', $email, 2);
        if (count($parts) !== 2) {
            return $email;
        }
        return mb_substr($parts[0], 0, 1) . '***@' . $parts[1];
    }

    protected function amountLabel($amount): string
    {
        $text = trim((string)$amount);
        if ($text === '') {
            return '0.00';
        }
        $negative = false;
        if ($text[0] === '-') {
            $negative = true;
            $text = substr($text, 1);
        }
        if (!preg_match('/^\d+(\.\d+)?$/', $text)) {
            return '0.00';
        }
        [$yuan, $cent] = array_pad(explode('.', $text, 2), 2, '');
        $yuan = ltrim($yuan, '0');
        if ($yuan === '') {
            $yuan = '0';
        }
        $cent = substr(str_pad($cent, 2, '0'), 0, 2);
        return ($negative ? '-' : '') . $yuan . '.' . $cent;
    }

    protected function normalizeMoney($amount): string
    {
        $text = trim((string)$amount);
        if ($text === '' || !preg_match('/^\d+(\.\d{1,2})?$/', $text)) {
            throw new \Exception('金额格式不正确，最多支持小数点后两位');
        }
        $amount = $this->amountLabel($text);
        if ($this->amountCompare($amount, '0.00') <= 0) {
            throw new \Exception('金额必须大于0');
        }
        return $amount;
    }

    protected function amountToCents($amount): int
    {
        $label = $this->amountLabel($amount);
        $negative = ($label[0] ?? '') === '-';
        $label = ltrim($label, '-');
        [$yuan, $cent] = explode('.', $label, 2);
        $cents = ((int)$yuan * 100) + (int)$cent;
        return $negative ? -$cents : $cents;
    }

    protected function centsToAmount(int $cents): string
    {
        $negative = $cents < 0;
        $cents = abs($cents);
        return ($negative ? '-' : '') . intdiv($cents, 100) . '.' . str_pad((string)($cents % 100), 2, '0', STR_PAD_LEFT);
    }

    protected function amountCompare($left, $right): int
    {
        return $this->amountToCents($left) <=> $this->amountToCents($right);
    }

    protected function amountAdd($left, $right): string
    {
        return $this->centsToAmount($this->amountToCents($left) + $this->amountToCents($right));
    }

    protected function amountSub($left, $right): string
    {
        return $this->centsToAmount(max(0, $this->amountToCents($left) - $this->amountToCents($right)));
    }

    protected function availableMoney(array $row): string
    {
        return $this->amountSub($row['money'] ?? 0, $row['wallet_frozen_money'] ?? 0);
    }

    protected function riskNo(string $prefix): string
    {
        for ($i = 0; $i < 5; $i++) {
            $no = strtoupper($prefix) . date('YmdHis') . strtoupper(substr(md5((string)microtime(true) . random_int(100000, 999999)), 0, 10));
            if (!Db::name('wallet_freeze')->where('freeze_no', $no)->find()) {
                return $no;
            }
            usleep(1000);
        }
        throw new \Exception('冻结单号生成失败');
    }

    protected function writeRiskLog(array $user, string $action, string $amount, int $beforeStatus, int $afterStatus, string $beforeFrozen, string $afterFrozen, string $reason): void
    {
        Db::name('wallet_risk_log')->insert([
            'appid' => (int)$user['appid'],
            'user_id' => (int)$user['id'],
            'action' => $action,
            'amount' => $amount,
            'before_wallet_status' => $beforeStatus,
            'after_wallet_status' => $afterStatus,
            'before_frozen_money' => $beforeFrozen,
            'after_frozen_money' => $afterFrozen,
            'reason' => $reason,
            'admin_id' => $this->adminId(),
            'ip' => Request::ip(),
            'create_time' => date('Y-m-d H:i:s'),
        ]);
    }

    protected function walletServiceUser(int $appid): array
    {
        return WalletNoticeService::serviceUser($appid);
    }

    protected function sendWalletRiskNotice(array $targetUser, string $scene, string $amount, string $reason): void
    {
        $appid = (int)($targetUser['appid'] ?? 0);
        $targetUserId = (int)($targetUser['id'] ?? 0);
        if ($appid <= 0 || $targetUserId <= 0) {
            return;
        }

        try {
            $serviceUser = $this->walletServiceUser($appid);
            if (!$serviceUser || (int)$serviceUser['id'] === $targetUserId) {
                return;
            }

            $titleMap = [
                'wallet_lock' => '钱包已锁定',
                'wallet_unlock' => '钱包已解锁',
                'wallet_freeze' => '余额已冻结',
                'wallet_unfreeze' => '余额已解冻',
            ];
            $summaryMap = [
                'wallet_lock' => '当前钱包暂不可用',
                'wallet_unlock' => '钱包功能已恢复',
                'wallet_freeze' => '冻结金额 ¥' . $this->amountLabel($amount),
                'wallet_unfreeze' => '解冻金额 ¥' . $this->amountLabel($amount),
            ];
            $title = $titleMap[$scene] ?? '钱包通知';
            $summary = $summaryMap[$scene] ?? $title;
            $walletStatus = (int)($targetUser['wallet_status'] ?? 1);
            $frozen = $this->amountLabel($targetUser['wallet_frozen_money'] ?? 0);
            $now = date('Y-m-d H:i:s');
            $clientMsgNo = 'wallet-risk-' . md5($appid . '|' . $targetUserId . '|' . $scene . '|' . $amount . '|' . $now . '|' . microtime(true));
            $payload = [
                'protocol' => 'blin.chat.v1',
                'type' => (int)config('wukongim.content_type_wallet_notice', WukongIM::CONTENT_TYPE_WALLET_NOTICE),
                'appid' => $appid,
                'scene' => 'wallet_service',
                'content_type' => 'wallet_notice',
                'content' => '[' . $title . '] ' . $summary,
                'channel_type' => (int)config('wukongim.channel_type_person', WukongIM::CHANNEL_TYPE_PERSON),
                'channel_type_name' => 'person',
                'sender_id' => (int)$serviceUser['id'],
                'receiver_id' => $targetUserId,
                'sender_uid' => WukongIM::uid($appid, (int)$serviceUser['id']),
                'receiver_uid' => WukongIM::uid($appid, $targetUserId),
                'sender_username' => (string)$serviceUser['username'],
                'sender_nickname' => (string)$serviceUser['nickname'],
                'sender_avatar' => (string)($serviceUser['usertx'] ?? ''),
                'system_message' => true,
                'device' => 'admin',
                'device_flag' => WukongIM::DEVICE_FLAG_WEB,
                'device_level' => WukongIM::DEVICE_LEVEL_MASTER,
                'client_timestamp' => (string)time(),
                'wallet_notice' => [
                    'scene' => $scene,
                    'title' => $title,
                    'summary' => $summary,
                    'amount' => $this->amountLabel($amount),
                    'amount_label' => '¥' . $this->amountLabel($amount),
                    'reason' => $reason,
                    'wallet_status' => $walletStatus,
                    'wallet_status_name' => $walletStatus === 2 ? '已锁定' : '正常',
                    'frozen_balance' => $frozen,
                    'frozen_balance_label' => '¥' . $frozen,
                    'create_time' => $now,
                ],
            ];

            (new WukongIM())->sendPersonMessage(
                WukongIM::uid($appid, (int)$serviceUser['id']),
                WukongIM::uid($appid, $targetUserId),
                $payload,
                $clientMsgNo
            );
        } catch (\Throwable $e) {
            error_log('wallet risk notice failed: ' . $e->getMessage());
        }
    }

    protected function orderStatusName(int $status): string
    {
        return match ($status) {
            1 => '已支付',
            2 => '已取消',
            3 => '已过期',
            default => '待支付',
        };
    }

    protected function billSceneName(int $type): string
    {
        return match ($type) {
            7 => '提现',
            8 => '卡密充值',
            9 => '红包/转账',
            11 => '扫码收付款',
            default => '余额变动',
        };
    }

    protected function adminId(): int
    {
        return (int)($this->admin_info['id'] ?? session('admin.id') ?? 0);
    }

    protected function assetAmount(mixed $value): string
    {
        $text=trim((string)$value);if(!preg_match('/^\d+(\.\d{1,8})?$/',$text))throw new \InvalidArgumentException('数字资产数量格式错误');return bcadd($text,'0',8);
    }
}
