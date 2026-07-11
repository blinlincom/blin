<?php

declare(strict_types=1);

namespace app\common\support;

use think\facade\Db;

final class GasFreeTaskService
{
    public static function accounts(int $limit = 100, int $afterId = 0): array
    {
        $limit = max(1, min(200, $limit));
        return Db::name('wallet_gasfree_account')->alias('g')
            ->join('wallet_gasfree_config c', 'c.appid=g.appid and c.asset_id=g.asset_id and c.network_id=g.network_id')
            ->join('wallet_chain_config cc', 'cc.appid=g.appid and cc.asset_id=g.asset_id and cc.network_id=g.network_id')
            ->leftJoin('wallet_sweep_config s', 's.appid=g.appid and s.asset_id=g.asset_id and s.network_id=g.network_id')
            ->where('g.id', '>', $afterId)->where('g.status', 1)->where('c.enabled', 1)->where('cc.status', 1)
            ->field('g.id,g.appid,g.user_id,g.asset_id,g.network_id,g.eoa_address,g.gasfree_address,g.token_address,g.token_decimals,c.auto_enabled,c.max_transfer_fee,c.max_first_fee,c.min_net_amount,c.max_fee_rate,s.target_address')
            ->order('g.id')->limit($limit)->select()->toArray();
    }

    public static function sync(array $data): array
    {
        $id = (int)($data['id'] ?? 0);
        $row = Db::name('wallet_gasfree_account')->where('id', $id)->find();
        if (!$row) throw new \RuntimeException('GasFree账户不存在');
        $now = date('Y-m-d H:i:s');
        $provider = trim((string)($data['provider_address'] ?? ''));
        $token = trim((string)($data['token_address'] ?? ''));
        if (!self::tronAddress($provider) || !self::tronAddress($token)) throw new \RuntimeException('GasFree同步地址异常');
        $balance = self::amount($data['onchain_balance'] ?? 0);
        $frozen = self::amount($data['provider_frozen'] ?? 0);
        $activateFee = self::amount($data['activate_fee'] ?? 0);
        $transferFee = self::amount($data['transfer_fee'] ?? 0);
        Db::startTrans();
        try {
            Db::name('wallet_gasfree_account')->where('id', $id)->update([
                'provider_address' => $provider, 'token_address' => $token,
                'active' => !empty($data['active']) ? 1 : 0, 'allow_submit' => !empty($data['allow_submit']) ? 1 : 0,
                'recommended_nonce' => (int)($data['recommended_nonce'] ?? 0), 'onchain_balance' => $balance,
                'provider_frozen' => $frozen, 'last_sync_time' => $now, 'update_time' => $now,
            ]);
            Db::name('wallet_gasfree_fee_snapshot')->insert([
                'provider_address' => $provider, 'token_address' => $token, 'symbol' => 'USDT',
                'decimals' => max(0, min(18, (int)($data['decimals'] ?? 6))), 'activate_fee' => $activateFee,
                'transfer_fee' => $transferFee, 'supported' => !empty($data['supported']) ? 1 : 0,
                'provider_config_json' => json_encode($data['provider_config'] ?? [], JSON_UNESCAPED_SLASHES), 'fetched_time' => $now,
            ]);
            self::createTask($id, $activateFee, $transferFee, $now);
            Db::commit();
            return ['synced' => 1];
        } catch (\Throwable $e) {
            Db::rollback();
            throw $e;
        }
    }

    public static function claim(string $worker): ?array
    {
        if ($worker === '') throw new \InvalidArgumentException('worker不能为空');
        Db::startTrans();
        try {
            $row = Db::name('wallet_gasfree_transfer')->whereIn('state', ['queued', 'retry'])
                ->where(function ($q) { $q->whereNull('lease_until')->whereOr('lease_until', '<', date('Y-m-d H:i:s')); })
                ->order('id')->lock(true)->find();
            if (!$row) { Db::commit(); return null; }
            $until = date('Y-m-d H:i:s', time() + 90);
            Db::name('wallet_gasfree_transfer')->where('id', $row['id'])->update(['state'=>'signing','lease_owner'=>$worker,'lease_until'=>$until,'update_time'=>date('Y-m-d H:i:s')]);
            Db::commit();
            $row['state'] = 'signing';
            $row['token_decimals'] = (int)(Db::name('wallet_gasfree_account')->where('id', $row['account_id'])->value('token_decimals') ?: 6);
            return $row;
        } catch (\Throwable $e) { Db::rollback(); throw $e; }
    }

    public static function report(array $data): array
    {
        $id=(int)($data['id']??0);$worker=trim((string)($data['worker']??''));
        $row=Db::name('wallet_gasfree_transfer')->where('id',$id)->find();
        if(!$row||!hash_equals((string)$row['lease_owner'],$worker))throw new \RuntimeException('GasFree任务租约无效');
        $now=date('Y-m-d H:i:s');
        if(!empty($data['success'])){
            $trace=trim((string)($data['trace_id']??''));if($trace==='')throw new \RuntimeException('GasFree trace_id不能为空');
            Db::name('wallet_gasfree_transfer')->where('id',$id)->update(['trace_id'=>$trace,'state'=>strtoupper((string)($data['state']??'WAITING')),'txn_state'=>strtoupper((string)($data['txn_state']??'')),'signature_hash'=>trim((string)($data['signature_hash']??'')),'submitted_time'=>$now,'lease_owner'=>'','lease_until'=>null,'last_error'=>'','update_time'=>$now]);
            return ['accepted'=>1];
        }
        $reason=mb_substr(trim((string)($data['reason']??$data['error']??'GasFree提交失败')),0,500);
        $permanent=in_array((string)($data['reason']??''),['InvalidSignatureException','UnsupportedTokenException','VersionNotSupportedException','ProviderAddressNotMatchException'],true);
        $retry=(int)$row['retry_count']+1;
        Db::name('wallet_gasfree_transfer')->where('id',$id)->update(['state'=>($permanent||$retry>=5)?'failed':'retry','retry_count'=>$retry,'last_error'=>$reason,'lease_owner'=>'','lease_until'=>null,'update_time'=>$now]);
        return ['accepted'=>1];
    }

    public static function confirmations(int $limit=50):array
    {
        return Db::name('wallet_gasfree_transfer')->where('trace_id','<>','')->whereIn('state',['WAITING','INPROGRESS','CONFIRMING'])->order('id')->limit(max(1,min(100,$limit)))->select()->toArray();
    }

    public static function confirm(array $data):array
    {
        $id=(int)($data['id']??0);$row=Db::name('wallet_gasfree_transfer')->where('id',$id)->find();if(!$row)throw new \RuntimeException('GasFree任务不存在');
        $state=strtoupper(trim((string)($data['state']??'')));$txnState=strtoupper(trim((string)($data['txn_state']??'')));$now=date('Y-m-d H:i:s');
        $values=['state'=>$state?:$row['state'],'txn_state'=>$txnState,'txn_hash'=>trim((string)($data['txn_hash']??'')),'txn_amount'=>self::amount($data['txn_amount']??0),'txn_total_fee'=>self::amount($data['txn_total_fee']??0),'last_error'=>mb_substr(trim((string)($data['error']??'')),0,500),'update_time'=>$now];
        if($state==='SUCCEED'&&$txnState==='SOLIDITY'){$values['state']='succeed';$values['confirmed_time']=$now;}
        elseif($state==='FAILED'||$txnState==='ON_CHAIN_FAILED'){$values['state']='failed';$values['confirmed_time']=$now;}
        Db::name('wallet_gasfree_transfer')->where('id',$id)->update($values);return ['accepted'=>1];
    }

    private static function createTask(int $accountId,string $activateFee,string $transferFee,string $now):void
    {
        $account=Db::name('wallet_gasfree_account')->alias('g')->join('wallet_gasfree_config c','c.appid=g.appid and c.asset_id=g.asset_id and c.network_id=g.network_id')->leftJoin('wallet_sweep_config s','s.appid=g.appid and s.asset_id=g.asset_id and s.network_id=g.network_id')->where('g.id',$accountId)->lock(true)->field('g.*,c.enabled,c.auto_enabled,c.max_transfer_fee,c.max_first_fee,c.min_net_amount,c.max_fee_rate,s.target_address')->find();
        if(!$account||(int)$account['enabled']!==1||(int)$account['auto_enabled']!==1||(int)$account['allow_submit']!==1||!self::tronAddress((string)$account['target_address']))return;
        if(Db::name('wallet_gasfree_transfer')->where('account_id',$accountId)->whereIn('state',['queued','retry','signing','WAITING','INPROGRESS','CONFIRMING'])->count()>0)return;
        $fee=(int)$account['active']===1?$transferFee:bcadd($activateFee,$transferFee,8);$max=(int)$account['active']===1?(string)$account['max_transfer_fee']:(string)$account['max_first_fee'];
        if(bccomp($fee,$max,8)>0)return;$spendable=bcsub((string)$account['onchain_balance'],(string)$account['provider_frozen'],8);$value=bcsub($spendable,$fee,8);
        if(bccomp($value,(string)$account['min_net_amount'],8)<0)return;
        $rate=bccomp($spendable,'0',8)>0?bcmul(bcdiv($fee,$spendable,8),'100',4):'100';if(bccomp($rate,(string)$account['max_fee_rate'],4)>0)return;
        $request=self::uuid4();$deadline=time()+180;
        Db::name('wallet_gasfree_transfer')->insert(['appid'=>$account['appid'],'request_id'=>$request,'sweep_no'=>'GF'.date('YmdHis').strtoupper(bin2hex(random_bytes(5))),'account_id'=>$accountId,'user_id'=>$account['user_id'],'asset_id'=>$account['asset_id'],'network_id'=>$account['network_id'],'eoa_address'=>$account['eoa_address'],'gasfree_address'=>$account['gasfree_address'],'provider_address'=>$account['provider_address'],'receiver_address'=>$account['target_address'],'token_address'=>$account['token_address'],'value'=>$value,'max_fee'=>$fee,'estimated_activate_fee'=>$activateFee,'estimated_transfer_fee'=>$transferFee,'nonce'=>$account['recommended_nonce'],'deadline'=>$deadline,'state'=>'queued','create_time'=>$now,'update_time'=>$now]);
    }

    private static function amount(mixed $v):string { return bcadd((string)$v,'0',8); }
    private static function tronAddress(string $v):bool { return (bool)preg_match('/^T[1-9A-HJ-NP-Za-km-z]{33}$/',$v); }
    private static function uuid4():string{$b=random_bytes(16);$b[6]=chr((ord($b[6])&15)|64);$b[8]=chr((ord($b[8])&63)|128);return vsprintf('%s%s-%s-%s-%s-%s%s%s',str_split(bin2hex($b),4));}
}
