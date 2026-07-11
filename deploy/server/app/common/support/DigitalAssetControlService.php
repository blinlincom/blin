<?php

declare(strict_types=1);

namespace app\common\support;

use think\facade\Db;

final class DigitalAssetControlService
{
    public static function assertAllowed(int $appid, int $userId, int $assetId, string $scene): void
    {
        $field = ['transfer'=>'block_transfer','otc'=>'block_otc','withdraw'=>'block_withdraw','exchange'=>'block_exchange'][$scene] ?? '';
        if ($field === '') return;
        $row = Db::name('wallet_asset_control')->where(compact('appid'))->where('user_id',$userId)->where('asset_id',$assetId)->find();
        if (!$row || (int)$row['status'] !== 1) return;
        if (!empty($row['end_time']) && strtotime((string)$row['end_time']) <= time()) return;
        if ((int)$row[$field] === 1) throw new \RuntimeException('该数字资产账户因风险控制暂不可进行此操作');
    }

    public static function createHold(int $appid, int $userId, int $assetId, string $amount, string $bizType, string $bizNo, string $reason, string $requestId, string $operatorType='system', int $operatorId=0, ?string $expireTime=null): array
    {
        $amount = self::amount($amount);
        if (bccomp($amount,'0',8) <= 0) throw new \InvalidArgumentException('冻结金额必须大于0');
        $existing = Db::name('wallet_asset_hold')->where('appid',$appid)->where('request_id',$requestId)->find();
        if ($existing) return $existing;
        $account = Db::name('wallet_asset_account')->where(compact('appid'))->where('user_id',$userId)->where('asset_id',$assetId)->lock(true)->find();
        if (!$account) throw new \RuntimeException('数字资产账户不存在');
        if (bccomp((string)$account['available_balance'],$amount,8)<0) throw new \RuntimeException('USDT可用余额不足');
        $now=date('Y-m-d H:i:s');$holdNo=self::number('H');$afterA=bcsub((string)$account['available_balance'],$amount,8);$afterF=bcadd((string)$account['frozen_balance'],$amount,8);
        $holdId=(int)Db::name('wallet_asset_hold')->insertGetId(['appid'=>$appid,'hold_no'=>$holdNo,'account_id'=>(int)$account['id'],'user_id'=>$userId,'asset_id'=>$assetId,'biz_type'=>$bizType,'biz_no'=>$bizNo,'amount'=>$amount,'original_amount'=>$amount,'remaining_amount'=>$amount,'status'=>1,'reason'=>$reason,'operator_type'=>$operatorType,'operator_id'=>$operatorId,'request_id'=>$requestId,'expire_time'=>$expireTime,'create_time'=>$now,'update_time'=>$now]);
        Db::name('wallet_asset_account')->where('id',(int)$account['id'])->update(['available_balance'=>$afterA,'frozen_balance'=>$afterF,'version'=>Db::raw('version+1'),'update_time'=>$now]);
        self::journal($appid,$account,$userId,$assetId,'asset_hold',$bizNo,$requestId,'hold','-'.$amount,$amount,$afterA,$afterF,$reason);
        self::holdLog($appid,$holdId,$holdNo,'create',$amount,'0',$amount,$operatorType,$operatorId,$reason,$requestId.'-log');
        return Db::name('wallet_asset_hold')->where('id',$holdId)->find() ?: [];
    }

    public static function releaseHold(int $appid, int $holdId, string $amount, string $reason, string $requestId, string $operatorType='admin', int $operatorId=0): array
    {
        $oldLog=Db::name('wallet_asset_hold_log')->where('appid',$appid)->where('request_id',$requestId)->find();if($oldLog)return Db::name('wallet_asset_hold')->where('id',(int)$oldLog['hold_id'])->find()?:[];
        $hold=Db::name('wallet_asset_hold')->where('appid',$appid)->where('id',$holdId)->lock(true)->find();if(!$hold||!in_array((int)$hold['status'],[1,4],true))throw new \RuntimeException('冻结记录不可解冻');
        $amount=self::amount($amount);$remaining=(string)$hold['remaining_amount'];if(bccomp($amount,'0',8)<=0||bccomp($amount,$remaining,8)>0)throw new \RuntimeException('解冻金额不正确');
        $account=Db::name('wallet_asset_account')->where('id',(int)$hold['account_id'])->lock(true)->find();if(!$account)throw new \RuntimeException('数字资产账户不存在');
        $afterRemaining=bcsub($remaining,$amount,8);$afterA=bcadd((string)$account['available_balance'],$amount,8);$afterF=bcsub((string)$account['frozen_balance'],$amount,8);if(bccomp($afterF,'0',8)<0)throw new \RuntimeException('冻结账目不一致，请先对账');
        $now=date('Y-m-d H:i:s');$status=bccomp($afterRemaining,'0',8)===0?2:4;
        Db::name('wallet_asset_account')->where('id',(int)$account['id'])->update(['available_balance'=>$afterA,'frozen_balance'=>$afterF,'version'=>Db::raw('version+1'),'update_time'=>$now]);
        Db::name('wallet_asset_hold')->where('id',$holdId)->update(['remaining_amount'=>$afterRemaining,'status'=>$status,'released_time'=>$status===2?$now:null,'update_time'=>$now]);
        self::journal($appid,$account,(int)$hold['user_id'],(int)$hold['asset_id'],'asset_release',self::journalBusinessNo((string)$hold['biz_no'],$requestId),$requestId,'release',$amount,'-'.$amount,$afterA,$afterF,$reason);
        self::holdLog($appid,$holdId,(string)$hold['hold_no'],'release',$amount,$remaining,$afterRemaining,$operatorType,$operatorId,$reason,$requestId);
        return Db::name('wallet_asset_hold')->where('id',$holdId)->find()?:[];
    }

    public static function consumeHold(int $appid, int $holdId, string $requestId, string $reason='业务结算'): array
    {
        $hold=Db::name('wallet_asset_hold')->where('appid',$appid)->where('id',$holdId)->lock(true)->find();if(!$hold||!in_array((int)$hold['status'],[1,4],true))throw new \RuntimeException('冻结记录不可扣除');
        $amount=(string)$hold['remaining_amount'];$account=Db::name('wallet_asset_account')->where('id',(int)$hold['account_id'])->lock(true)->find();$afterF=bcsub((string)$account['frozen_balance'],$amount,8);if(bccomp($afterF,'0',8)<0)throw new \RuntimeException('冻结账目不一致，请先对账');
        $now=date('Y-m-d H:i:s');Db::name('wallet_asset_account')->where('id',(int)$account['id'])->update(['frozen_balance'=>$afterF,'total_out'=>bcadd((string)$account['total_out'],$amount,8),'version'=>Db::raw('version+1'),'update_time'=>$now]);Db::name('wallet_asset_hold')->where('id',$holdId)->update(['remaining_amount'=>'0.00000000','status'=>3,'consumed_time'=>$now,'update_time'=>$now]);
        self::journal($appid,$account,(int)$hold['user_id'],(int)$hold['asset_id'],'asset_consume',self::journalBusinessNo((string)$hold['biz_no'],$requestId),$requestId,'consume','0','-'.$amount,(string)$account['available_balance'],$afterF,$reason);self::holdLog($appid,$holdId,(string)$hold['hold_no'],'consume',$amount,$amount,'0','system',0,$reason,$requestId.'-log');return Db::name('wallet_asset_hold')->where('id',$holdId)->find()?:[];
    }

    public static function consumeHoldAmount(int $appid,int $holdId,string $amount,string $requestId,string $reason='业务部分结算'):array
    {
        $oldLog=Db::name('wallet_asset_hold_log')->where('appid',$appid)->where('request_id',$requestId.'-log')->find();if($oldLog)return Db::name('wallet_asset_hold')->where('id',(int)$oldLog['hold_id'])->find()?:[];
        $hold=Db::name('wallet_asset_hold')->where('appid',$appid)->where('id',$holdId)->lock(true)->find();if(!$hold||!in_array((int)$hold['status'],[1,4],true))throw new \RuntimeException('冻结记录不可扣除');
        $amount=self::amount($amount);$remaining=(string)$hold['remaining_amount'];if(bccomp($amount,'0',8)<=0||bccomp($amount,$remaining,8)>0)throw new \RuntimeException('冻结扣除金额不正确');
        $account=Db::name('wallet_asset_account')->where('id',(int)$hold['account_id'])->lock(true)->find();if(!$account)throw new \RuntimeException('数字资产账户不存在');$afterRemaining=bcsub($remaining,$amount,8);$afterF=bcsub((string)$account['frozen_balance'],$amount,8);if(bccomp($afterF,'0',8)<0)throw new \RuntimeException('冻结账目不一致，请先对账');
        $now=date('Y-m-d H:i:s');$status=bccomp($afterRemaining,'0',8)===0?3:4;Db::name('wallet_asset_account')->where('id',(int)$account['id'])->update(['frozen_balance'=>$afterF,'total_out'=>bcadd((string)$account['total_out'],$amount,8),'version'=>Db::raw('version+1'),'update_time'=>$now]);Db::name('wallet_asset_hold')->where('id',$holdId)->update(['remaining_amount'=>$afterRemaining,'status'=>$status,'consumed_time'=>$status===3?$now:null,'update_time'=>$now]);
        self::journal($appid,$account,(int)$hold['user_id'],(int)$hold['asset_id'],'asset_consume',self::journalBusinessNo((string)$hold['biz_no'],$requestId),$requestId,'consume','0','-'.$amount,(string)$account['available_balance'],$afterF,$reason);self::holdLog($appid,$holdId,(string)$hold['hold_no'],'consume',$amount,$remaining,$afterRemaining,'system',0,$reason,$requestId.'-log');return Db::name('wallet_asset_hold')->where('id',$holdId)->find()?:[];
    }

    private static function journal(int $appid,array $account,int $userId,int $assetId,string $type,string $bizNo,string $requestId,string $direction,string $availableDelta,string $frozenDelta,string $afterA,string $afterF,string $remark):void
    {$jid=(int)Db::name('wallet_asset_journal')->insertGetId(['appid'=>$appid,'journal_no'=>self::number('J'),'request_id'=>$requestId,'business_type'=>$type,'business_no'=>$bizNo,'asset_id'=>$assetId,'status'=>1,'param_hash'=>hash('sha256',$requestId),'create_time'=>date('Y-m-d H:i:s')]);Db::name('wallet_asset_entry')->insert(['journal_id'=>$jid,'account_id'=>(int)$account['id'],'user_id'=>$userId,'direction'=>$direction,'available_delta'=>$availableDelta,'frozen_delta'=>$frozenDelta,'available_after'=>$afterA,'frozen_after'=>$afterF,'remark'=>$remark,'create_time'=>date('Y-m-d H:i:s')]);}
    private static function holdLog(int $appid,int $holdId,string $holdNo,string $action,string $amount,string $before,string $after,string $operatorType,int $operatorId,string $reason,string $requestId):void{Db::name('wallet_asset_hold_log')->insert(['appid'=>$appid,'hold_id'=>$holdId,'hold_no'=>$holdNo,'action'=>$action,'amount'=>$amount,'remaining_before'=>$before,'remaining_after'=>$after,'operator_type'=>$operatorType,'operator_id'=>$operatorId,'reason'=>$reason,'request_id'=>$requestId,'create_time'=>date('Y-m-d H:i:s')]);}
    private static function amount(string $v):string{$v=trim($v);if(!preg_match('/^\d+(\.\d{1,8})?$/',$v))throw new \InvalidArgumentException('金额格式错误');return bcadd($v,'0',8);}
    private static function journalBusinessNo(string $bizNo,string $requestId):string{return mb_substr($bizNo.'-'.substr(hash('sha256',$requestId),0,8),0,48);}
    private static function number(string $prefix):string{return $prefix.date('YmdHis').strtoupper(bin2hex(random_bytes(5)));}
}
