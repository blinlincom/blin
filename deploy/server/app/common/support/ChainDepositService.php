<?php

declare(strict_types=1);

namespace app\common\support;

use think\facade\Db;

final class ChainDepositService
{
    public static function addresses(int $limit = 500, int $afterId = 0): array
    {
        $limit=max(1,min(1000,$limit));$gasOffset=1000000000000;
        if($afterId<$gasOffset){$rows=Db::name('wallet_chain_address')->alias('ca')
            ->join('wallet_chain_config c', 'c.appid=ca.appid and c.asset_id=ca.asset_id and c.network_id=ca.network_id')
            ->where('ca.status', 1)->where('ca.accept_deposit',1)->where('c.status', 1)->where('c.deposit_enabled', 1)
            ->where('ca.id', '>', $afterId)
            ->field('ca.id,ca.appid,ca.user_id,ca.asset_id,ca.network_id,ca.address_base58,c.contract_address,c.decimals,c.min_deposit')
            ->order('ca.id')->limit($limit)->select()->toArray();if(count($rows)>=$limit)return $rows;$remaining=$limit-count($rows);$gasAfter=0;}else{$rows=[];$remaining=$limit;$gasAfter=$afterId-$gasOffset;}
        $gas=Db::name('wallet_gasfree_account')->alias('g')->join('wallet_chain_config c','c.appid=g.appid and c.asset_id=g.asset_id and c.network_id=g.network_id')->join('wallet_gasfree_config gc','gc.appid=g.appid and gc.asset_id=g.asset_id and gc.network_id=g.network_id')->where('g.status',1)->where('gc.enabled',1)->where('c.status',1)->where('c.deposit_enabled',1)->where('g.id','>',$gasAfter)->field('g.id,g.appid,g.user_id,g.asset_id,g.network_id,g.gasfree_address address_base58,c.contract_address,c.decimals,c.min_deposit')->order('g.id')->limit($remaining)->select()->toArray();foreach($gas as &$item)$item['id']=$gasOffset+(int)$item['id'];return array_merge($rows,$gas);
    }

    public static function credit(array $data): array
    {
        $address=trim((string)($data['to_address']??''));$txid=trim((string)($data['txid']??''));$contract=trim((string)($data['contract_address']??''));$from=trim((string)($data['from_address']??''));$amount=self::amount($data['amount']??'0');$logIndex=max(0,(int)($data['log_index']??0));$block=max(0,(int)($data['block_number']??0));
        if($address===''||$txid===''||$contract==='')throw new \InvalidArgumentException('链上事件参数不完整');
        $binding=Db::name('wallet_chain_address')->alias('ca')->join('wallet_chain_config c','c.appid=ca.appid and c.asset_id=ca.asset_id and c.network_id=ca.network_id')->where('ca.address_base58',$address)->where('ca.status',1)->where('c.status',1)->where('c.deposit_enabled',1)->field('ca.*,c.contract_address,c.min_deposit')->find();
        $gasfree=false;if(!$binding){$binding=Db::name('wallet_gasfree_account')->alias('g')->join('wallet_chain_config c','c.appid=g.appid and c.asset_id=g.asset_id and c.network_id=g.network_id')->join('wallet_gasfree_config gc','gc.appid=g.appid and gc.asset_id=g.asset_id and gc.network_id=g.network_id')->where('g.gasfree_address',$address)->where('g.status',1)->where('gc.enabled',1)->where('c.status',1)->where('c.deposit_enabled',1)->field('g.*,c.contract_address,c.min_deposit')->find();$gasfree=(bool)$binding;}if(!$binding) return ['ignored'=>1,'reason'=>'address_not_managed'];
        if(!hash_equals((string)$binding['contract_address'],$contract))throw new \RuntimeException('USDT合约地址不匹配');
        Db::startTrans();try{
            $event=Db::name('wallet_chain_event')->where(['network_id'=>(int)$binding['network_id'],'contract_address'=>$contract,'txid'=>$txid,'log_index'=>$logIndex])->lock(true)->find();
            if($event&&in_array((string)$event['process_status'],['credited','below_minimum'],true)){Db::commit();return ['duplicate'=>1,'status'=>$event['process_status']];}
            $now=date('Y-m-d H:i:s');
            if(!$event){$eventId=(int)Db::name('wallet_chain_event')->insertGetId(['network_id'=>(int)$binding['network_id'],'contract_address'=>$contract,'block_number'=>$block,'block_hash'=>(string)($data['block_hash']??''),'txid'=>$txid,'log_index'=>$logIndex,'from_address'=>$from,'to_address'=>$address,'amount'=>$amount,'solidified'=>1,'execute_success'=>1,'process_status'=>'detected','create_time'=>$now,'update_time'=>$now]);}else{$eventId=(int)$event['id'];}
            if(bccomp($amount,(string)$binding['min_deposit'],8)<0){Db::name('wallet_chain_event')->where('id',$eventId)->update(['process_status'=>'below_minimum','update_time'=>$now]);Db::commit();return ['credited'=>0,'status'=>'below_minimum'];}
            $account=Db::name('wallet_asset_account')->where(['appid'=>(int)$binding['appid'],'user_id'=>(int)$binding['user_id'],'asset_id'=>(int)$binding['asset_id']])->lock(true)->find();
            if(!$account){Db::name('wallet_asset_account')->insert(['appid'=>(int)$binding['appid'],'user_id'=>(int)$binding['user_id'],'asset_id'=>(int)$binding['asset_id'],'available_balance'=>'0.00000000','frozen_balance'=>'0.00000000','total_in'=>'0.00000000','total_out'=>'0.00000000','version'=>1,'create_time'=>$now,'update_time'=>$now]);$account=Db::name('wallet_asset_account')->where(['appid'=>(int)$binding['appid'],'user_id'=>(int)$binding['user_id'],'asset_id'=>(int)$binding['asset_id']])->lock(true)->find();}
            $businessNo='DEP-'.substr($txid,0,32).'-'.$logIndex;$requestId='deposit-'.$txid.'-'.$logIndex;$hash=hash('sha256',$contract.'|'.$txid.'|'.$logIndex.'|'.$address.'|'.$amount);
            $journal=Db::name('wallet_asset_journal')->where('appid',(int)$binding['appid'])->where('request_id',$requestId)->find();
            if(!$journal){$after=bcadd((string)$account['available_balance'],$amount,8);$journalId=(int)Db::name('wallet_asset_journal')->insertGetId(['appid'=>(int)$binding['appid'],'journal_no'=>self::number('J'),'request_id'=>$requestId,'business_type'=>'deposit','business_no'=>$businessNo,'asset_id'=>(int)$binding['asset_id'],'status'=>1,'param_hash'=>$hash,'create_time'=>$now]);Db::name('wallet_asset_account')->where('id',(int)$account['id'])->update(['available_balance'=>$after,'total_in'=>bcadd((string)$account['total_in'],$amount,8),'version'=>Db::raw('version+1'),'update_time'=>$now]);Db::name('wallet_asset_entry')->insert(['journal_id'=>$journalId,'account_id'=>(int)$account['id'],'user_id'=>(int)$binding['user_id'],'direction'=>'credit','available_delta'=>$amount,'frozen_delta'=>'0.00000000','available_after'=>$after,'frozen_after'=>(string)$account['frozen_balance'],'remark'=>'USDT-TRC20充值','create_time'=>$now]);}
            Db::name('wallet_chain_event')->where('id',$eventId)->update(['process_status'=>'credited','update_time'=>$now]);if($gasfree)Db::name('wallet_gasfree_account')->where('id',(int)$binding['id'])->update(['onchain_balance'=>Db::raw('onchain_balance+'.$amount),'last_sync_time'=>$now,'update_time'=>$now]);else Db::name('wallet_chain_address')->where('id',(int)$binding['id'])->update(['last_deposit_time'=>$now]);Db::commit();return ['credited'=>1,'user_id'=>(int)$binding['user_id'],'amount'=>$amount,'txid'=>$txid];
        }catch(\Throwable $e){Db::rollback();throw $e;}
    }

    private static function amount(mixed $value):string{$text=trim((string)$value);if(!preg_match('/^\d+(\.\d{1,8})?$/',$text))throw new \InvalidArgumentException('充值数量格式错误');return bcadd($text,'0',8);}
    private static function number(string $prefix):string{return $prefix.date('YmdHis').strtoupper(bin2hex(random_bytes(6)));}
}
