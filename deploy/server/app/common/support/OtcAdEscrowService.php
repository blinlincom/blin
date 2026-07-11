<?php

declare(strict_types=1);

namespace app\common\support;

use think\facade\Db;

final class OtcAdEscrowService
{
    public static function createSell(array $ad,int $userId):int
    {
        $hold=DigitalAssetControlService::createHold((int)$ad['appid'],$userId,(int)$ad['asset_id'],(string)$ad['available_asset'],'otc_ad',(string)$ad['id'],'OTC卖币广告资产托管','otc-ad-hold-'.$ad['id'],'system',0);
        return (int)$hold['id'];
    }

    public static function createBuy(array $ad,int $userId):int
    {
        $amount=bcmul((string)$ad['price'],(string)$ad['available_asset'],2);$user=Db::name('user')->where(['appid'=>$ad['appid'],'id'=>$userId])->lock(true)->find();if(!$user||(int)($user['wallet_status']??1)!==1)throw new \RuntimeException('商家平台钱包不可用');if(bccomp((string)$user['money'],$amount,2)<0)throw new \RuntimeException('平台可用余额不足');$now=date('Y-m-d H:i:s');Db::name('user')->where(['appid'=>$ad['appid'],'id'=>$userId])->update(['money'=>bcsub((string)$user['money'],$amount,2)]);$id=(int)Db::name('otc_ad_fiat_hold')->insertGetId(['appid'=>$ad['appid'],'merchant_id'=>$ad['merchant_id'],'user_id'=>$userId,'ad_id'=>$ad['id'],'amount'=>$amount,'remaining_amount'=>$amount,'status'=>1,'create_time'=>$now,'update_time'=>$now]);Db::name('transaction_statement')->insert(['appid'=>$ad['appid'],'userid'=>$userId,'transaction_type'=>13,'transaction_date'=>$now,'transaction_amount'=>'-'.$amount,'remark'=>'OTC买币广告资金托管 AD'.$ad['id'],'type'=>0,'frozen'=>1]);return $id;
    }

    public static function consumeSell(array $ad,string $amount,string $orderNo):void
    {
        if((int)($ad['asset_hold_id']??0)<=0)throw new \RuntimeException('卖币广告托管记录缺失');DigitalAssetControlService::consumeHoldAmount((int)$ad['appid'],(int)$ad['asset_hold_id'],$amount,'otc-ad-consume-'.$orderNo,'OTC卖币广告成交扣除');
    }

    public static function consumeBuy(array $ad,string $amount,string $orderNo,int $sellerId):void
    {
        $hold=Db::name('otc_ad_fiat_hold')->where(['appid'=>$ad['appid'],'id'=>$ad['fiat_hold_id'],'ad_id'=>$ad['id']])->whereIn('status',[1,4])->lock(true)->find();if(!$hold)throw new \RuntimeException('买币广告托管记录缺失');if(bccomp($amount,(string)$hold['remaining_amount'],2)>0)throw new \RuntimeException('买币广告托管余额不足');$seller=Db::name('user')->where(['appid'=>$ad['appid'],'id'=>$sellerId])->lock(true)->find();if(!$seller||(int)($seller['wallet_status']??1)!==1)throw new \RuntimeException('卖方钱包不可用');$after=bcsub((string)$hold['remaining_amount'],$amount,2);$now=date('Y-m-d H:i:s');Db::name('user')->where(['appid'=>$ad['appid'],'id'=>$sellerId])->update(['money'=>bcadd((string)$seller['money'],$amount,2)]);Db::name('otc_ad_fiat_hold')->where('id',$hold['id'])->update(['remaining_amount'=>$after,'status'=>bccomp($after,'0',2)===0?3:4,'update_time'=>$now]);Db::name('transaction_statement')->insert(['appid'=>$ad['appid'],'userid'=>$sellerId,'transaction_type'=>13,'transaction_date'=>$now,'transaction_amount'=>$amount,'remark'=>'OTC卖币到账 '.$orderNo,'type'=>0,'frozen'=>0]);
    }

    public static function release(array $ad,string $reason,string $operatorType='admin',int $operatorId=0):void
    {
        if((string)$ad['side']==='sell'&&(int)($ad['asset_hold_id']??0)>0){$hold=Db::name('wallet_asset_hold')->where('id',(int)$ad['asset_hold_id'])->whereIn('status',[1,4])->lock(true)->find();if($hold&&bccomp((string)$hold['remaining_amount'],'0',8)>0)DigitalAssetControlService::releaseHold((int)$ad['appid'],(int)$hold['id'],(string)$hold['remaining_amount'],$reason,'otc-ad-release-'.$ad['id'],$operatorType,$operatorId);}
        if((string)$ad['side']==='buy'&&(int)($ad['fiat_hold_id']??0)>0){$hold=Db::name('otc_ad_fiat_hold')->where('id',(int)$ad['fiat_hold_id'])->whereIn('status',[1,4])->lock(true)->find();if($hold&&bccomp((string)$hold['remaining_amount'],'0',2)>0){$user=Db::name('user')->where(['appid'=>$ad['appid'],'id'=>$hold['user_id']])->lock(true)->find();if(!$user)throw new \RuntimeException('商家钱包不存在');$now=date('Y-m-d H:i:s');Db::name('user')->where(['appid'=>$ad['appid'],'id'=>$hold['user_id']])->update(['money'=>bcadd((string)$user['money'],(string)$hold['remaining_amount'],2)]);Db::name('otc_ad_fiat_hold')->where('id',$hold['id'])->update(['remaining_amount'=>'0.00','status'=>2,'update_time'=>$now]);Db::name('transaction_statement')->insert(['appid'=>$ad['appid'],'userid'=>$hold['user_id'],'transaction_type'=>13,'transaction_date'=>$now,'transaction_amount'=>(string)$hold['remaining_amount'],'remark'=>$reason.' AD'.$ad['id'],'type'=>0,'frozen'=>0]);}}
    }
}
