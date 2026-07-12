<?php

declare(strict_types=1);

namespace app\common\support;

use think\facade\Db;

final class ChainTaskService
{
    public static function claim(string $worker): ?array
    {
        if ($worker === '') throw new \InvalidArgumentException('worker不能为空');
        self::seedSweeps();
        Db::startTrans();
        try {
            $now = date('Y-m-d H:i:s');
            $order = self::claimRow('wallet_sweep_order', $now);
            $kind = 'sweep';
            if (!$order) { $order = self::claimRow('wallet_withdraw_order', $now); $kind = 'withdraw'; }
            if (!$order) { Db::commit(); return null; }
            $table = self::table($kind);
            Db::name($table)->where('id', $order['id'])->update(['status'=>'processing','lease_owner'=>$worker,'lease_until'=>date('Y-m-d H:i:s',time()+120),'update_time'=>$now]);
            $config = Db::name('wallet_chain_config')->where(['appid'=>$order['appid'],'asset_id'=>$order['asset_id'],'network_id'=>$order['network_id']])->find();
            if (!$config) throw new \RuntimeException('链上配置不存在');
            Db::commit();
            return ['id'=>(int)$order['id'],'kind'=>$kind,'appid'=>(int)$order['appid'],'user_id'=>(int)$order['user_id'],'address_id'=>(int)($order['address_id']??0),'from_address'=>$kind==='sweep'?(string)$order['from_address']:'','to_address'=>(string)$order['to_address'],'contract_address'=>(string)$config['contract_address'],'amount'=>$kind==='sweep'?(string)$order['amount']:(string)$order['receive_amount'],'decimals'=>(int)$config['decimals']];
        } catch (\Throwable $e) { Db::rollback(); throw $e; }
    }

    public static function report(array $data): array
    {
        $kind=(string)($data['kind']??'');$table=self::table($kind);
        Db::startTrans();
        try {
            $order=Db::name($table)->where('id',(int)($data['id']??0))->lock(true)->find();
            if(!$order||$order['lease_owner']!==(string)($data['worker']??''))throw new \RuntimeException('任务租约无效');
            $now=date('Y-m-d H:i:s');
            $txid=trim((string)($data['txid']??''));
            if(!empty($data['success'])||$txid!=='') Db::name($table)->where('id',$order['id'])->update(['status'=>'broadcasted','txid'=>$txid,'lease_owner'=>'','lease_until'=>null,'last_error'=>empty($data['success'])?'广播响应未知，按交易哈希确认':'','update_time'=>$now]);
            else { $retry=(int)$order['retry_count']+1;Db::name($table)->where('id',$order['id'])->update(['status'=>$retry>=5?'manual_review':'retry','retry_count'=>$retry,'last_error'=>mb_substr((string)($data['error']??''),0,500),'next_retry_time'=>date('Y-m-d H:i:s',time()+min(3600,30*(2**min($retry,6)))),'lease_owner'=>'','lease_until'=>null,'update_time'=>$now]); }
            Db::commit();return ['accepted'=>1];
        } catch(\Throwable $e){Db::rollback();throw $e;}
    }

    public static function claimConfirmation(string $worker): ?array
    {
        Db::startTrans();
        try {
            $now=date('Y-m-d H:i:s');$order=self::claimConfirmationRow('wallet_sweep_order',$now);$kind='sweep';
            if(!$order){$order=self::claimConfirmationRow('wallet_withdraw_order',$now);$kind='withdraw';}
            if(!$order){Db::commit();return null;}
            Db::name(self::table($kind))->where('id',$order['id'])->update(['lease_owner'=>$worker,'lease_until'=>date('Y-m-d H:i:s',time()+60),'update_time'=>$now]);Db::commit();
            return ['id'=>(int)$order['id'],'kind'=>$kind,'txid'=>(string)$order['txid']];
        }catch(\Throwable $e){Db::rollback();throw $e;}
    }

    public static function reportConfirmation(array $data):array
    {
        $kind=(string)($data['kind']??'');$table=self::table($kind);Db::startTrans();
        try{$order=Db::name($table)->where('id',(int)($data['id']??0))->lock(true)->find();if(!$order||$order['lease_owner']!==(string)($data['worker']??''))throw new \RuntimeException('确认任务租约无效');$now=date('Y-m-d H:i:s');
            if(empty($data['confirmed'])){Db::name($table)->where('id',$order['id'])->update(['lease_owner'=>'','lease_until'=>null,'update_time'=>$now]);Db::commit();return ['pending'=>1];}
            if(empty($data['success'])){if($kind==='withdraw'){self::releaseWithdraw($order,'链上执行失败');$failed='failed_refunded';}else{$failed='failed';}Db::name($table)->where('id',$order['id'])->update(['status'=>$failed,'last_error'=>mb_substr((string)($data['error']??'链上执行失败'),0,500),'confirmed_time'=>$now,'lease_owner'=>'','lease_until'=>null,'update_time'=>$now]);}
            elseif($kind==='withdraw')self::completeWithdraw($order);else{Db::name('wallet_chain_address')->where('id',$order['address_id'])->update(['last_sweep_time'=>$now]);Db::name($table)->where('id',$order['id'])->update(['status'=>'success','confirmed_time'=>$now,'lease_owner'=>'','lease_until'=>null,'update_time'=>$now]);}
            Db::commit();return ['confirmed'=>1];
        }catch(\Throwable $e){Db::rollback();throw $e;}
    }

    public static function approveWithdraw(int $id,int $adminId):void{Db::startTrans();try{$o=Db::name('wallet_withdraw_order')->where('id',$id)->lock(true)->find();if(!$o||$o['status']!=='risk_review')throw new \RuntimeException('提币订单状态不可审核');$cfg=Db::name('wallet_chain_config')->where(['appid'=>$o['appid'],'asset_id'=>$o['asset_id'],'network_id'=>$o['network_id']])->find();if(!$cfg||(int)$cfg['withdraw_enabled']!==1)throw new \RuntimeException('链上提币未开放');Db::name('wallet_withdraw_order')->where('id',$id)->update(['status'=>'queued','review_admin_id'=>$adminId,'risk_reason'=>'审核通过','version'=>Db::raw('version+1'),'update_time'=>date('Y-m-d H:i:s')]);Db::commit();}catch(\Throwable $e){Db::rollback();throw $e;}}
    public static function rejectWithdraw(int $id,int $adminId,string $reason):void{if(trim($reason)==='')throw new \InvalidArgumentException('驳回原因不能为空');Db::startTrans();try{$o=Db::name('wallet_withdraw_order')->where('id',$id)->lock(true)->find();if(!$o||!in_array($o['status'],['risk_review','manual_review'],true))throw new \RuntimeException('提币订单状态不可驳回');self::releaseWithdraw($o,$reason);Db::name('wallet_withdraw_order')->where('id',$id)->update(['status'=>'rejected','review_admin_id'=>$adminId,'risk_reason'=>$reason,'version'=>Db::raw('version+1'),'update_time'=>date('Y-m-d H:i:s')]);Db::commit();}catch(\Throwable $e){Db::rollback();throw $e;}}

    private static function completeWithdraw(array $o):void{$account=self::account($o);$after=bcsub((string)$account['frozen_balance'],(string)$o['amount'],8);if(bccomp($after,'0',8)<0)throw new \RuntimeException('提币冻结余额不一致');$now=date('Y-m-d H:i:s');$jid=self::journal($o,'withdraw_complete','withdraw-complete-'.$o['withdraw_no'],'TRC20提币完成，含手续费 '.$o['fee']);Db::name('wallet_asset_account')->where('id',$account['id'])->update(['frozen_balance'=>$after,'total_out'=>bcadd((string)$account['total_out'],(string)$o['amount'],8),'version'=>Db::raw('version+1'),'update_time'=>$now]);Db::name('wallet_asset_entry')->insert(['journal_id'=>$jid,'account_id'=>$account['id'],'user_id'=>$o['user_id'],'direction'=>'debit','available_delta'=>'0.00000000','frozen_delta'=>'-'.(string)$o['amount'],'available_after'=>$account['available_balance'],'frozen_after'=>$after,'remark'=>'TRC20提币完成，含手续费 '.$o['fee'],'create_time'=>$now]);Db::name('wallet_withdraw_order')->where('id',$o['id'])->update(['status'=>'success','confirmed_time'=>$now,'lease_owner'=>'','lease_until'=>null,'update_time'=>$now]);}
    private static function releaseWithdraw(array $o,string $reason):void{$account=self::account($o);$afterA=bcadd((string)$account['available_balance'],(string)$o['amount'],8);$afterF=bcsub((string)$account['frozen_balance'],(string)$o['amount'],8);if(bccomp($afterF,'0',8)<0)throw new \RuntimeException('提币冻结余额不一致');$now=date('Y-m-d H:i:s');$jid=self::journal($o,'withdraw_release','withdraw-release-'.$o['withdraw_no'],'TRC20提币退回：'.$reason);Db::name('wallet_asset_account')->where('id',$account['id'])->update(['available_balance'=>$afterA,'frozen_balance'=>$afterF,'version'=>Db::raw('version+1'),'update_time'=>$now]);Db::name('wallet_asset_entry')->insert(['journal_id'=>$jid,'account_id'=>$account['id'],'user_id'=>$o['user_id'],'direction'=>'release','available_delta'=>$o['amount'],'frozen_delta'=>'-'.(string)$o['amount'],'available_after'=>$afterA,'frozen_after'=>$afterF,'remark'=>'TRC20提币退回：'.$reason,'create_time'=>$now]);}
    private static function seedSweeps():void{$rows=Db::name('wallet_chain_address')->alias('a')->join('wallet_sweep_config s','s.appid=a.appid and s.asset_id=a.asset_id and s.network_id=a.network_id')->where('s.auto_enabled',1)->where('s.signing_enabled',1)->where('s.target_address','<>','')->field('a.*,s.target_address,s.min_sweep_amount')->select()->toArray();foreach($rows as $a){$in=(string)(Db::name('wallet_chain_event')->where('to_address',$a['address_base58'])->where('process_status','credited')->sum('amount')?:0);$out=(string)(Db::name('wallet_sweep_order')->where('address_id',$a['id'])->whereIn('status',['broadcasted','success'])->sum('amount')?:0);$amount=bcsub($in,$out,8);if(bccomp($amount,(string)$a['min_sweep_amount'],8)<0)continue;if(Db::name('wallet_sweep_order')->where('address_id',$a['id'])->whereIn('status',['queued','processing','retry','broadcasted'])->count())continue;$now=date('Y-m-d H:i:s');Db::name('wallet_sweep_order')->insert(['sweep_no'=>self::number('SW'),'appid'=>$a['appid'],'address_id'=>$a['id'],'user_id'=>$a['user_id'],'asset_id'=>$a['asset_id'],'network_id'=>$a['network_id'],'from_address'=>$a['address_base58'],'to_address'=>$a['target_address'],'amount'=>$amount,'status'=>'queued','txid'=>'','retry_count'=>0,'last_error'=>'','create_time'=>$now,'update_time'=>$now]);}}
    private static function claimRow(string $table,string $now):?array{return Db::name($table)->whereIn('status',['queued','retry'])->where(function($q)use($now){$q->whereNull('next_retry_time')->whereOr('next_retry_time','<=',$now);})->where(function($q)use($now){$q->whereNull('lease_until')->whereOr('lease_until','<',$now);})->order('id')->lock(true)->find();}
    private static function claimConfirmationRow(string $table,string $now):?array{return Db::name($table)->where('status','broadcasted')->where('txid','<>','')->where(function($q)use($now){$q->whereNull('lease_until')->whereOr('lease_until','<',$now);})->order('id')->lock(true)->find();}
    private static function table(string $kind):string{if($kind==='sweep')return 'wallet_sweep_order';if($kind==='withdraw')return 'wallet_withdraw_order';throw new \InvalidArgumentException('任务类型错误');}
    private static function account(array $o):array{$a=Db::name('wallet_asset_account')->where(['appid'=>$o['appid'],'user_id'=>$o['user_id'],'asset_id'=>$o['asset_id']])->lock(true)->find();if(!$a)throw new \RuntimeException('数字资产账户不存在');return $a;}
    private static function journal(array $o,string $type,string $request,string $remark):int{return (int)Db::name('wallet_asset_journal')->insertGetId(['appid'=>$o['appid'],'journal_no'=>self::number('J'),'request_id'=>$request,'business_type'=>$type,'business_no'=>$o['withdraw_no'],'asset_id'=>$o['asset_id'],'status'=>1,'param_hash'=>hash('sha256',$remark),'create_time'=>date('Y-m-d H:i:s')]);}
    private static function number(string $prefix):string{return $prefix.date('YmdHis').strtoupper(bin2hex(random_bytes(5)));}
}
