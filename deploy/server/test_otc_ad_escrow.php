<?php

declare(strict_types=1);

require '/www/wwwroot/blin/vendor/autoload.php';
$app=new think\App();$app->initialize();

use app\common\support\OtcAdEscrowService;
use think\facade\Db;

function assertAmount(string $actual,string $expected,int $scale,string $label):void{if(bccomp($actual,$expected,$scale)!==0)throw new RuntimeException($label.": {$actual} != {$expected}");}

$merchant=Db::name('otc_merchant')->where('status',1)->order('id')->find();if(!$merchant)throw new RuntimeException('没有可测试商家');$uid=(int)$merchant['user_id'];$appid=(int)$merchant['appid'];$account=Db::name('wallet_asset_account')->where(['appid'=>$appid,'user_id'=>$uid])->where('available_balance','>=','0.02000000')->order('id')->find();if(!$account)throw new RuntimeException('测试账户USDT不足0.02');$user=Db::name('user')->where(['appid'=>$appid,'id'=>$uid])->find();if(!$user||bccomp((string)$user['money'],'0.20',2)<0)throw new RuntimeException('测试账户平台余额不足0.20');

Db::startTrans();try{
    $tag=(string)random_int(700000000,799999999);$now=date('Y-m-d H:i:s');
    $sell=['id'=>$tag,'appid'=>$appid,'merchant_id'=>$merchant['id'],'asset_id'=>$account['asset_id'],'side'=>'sell','available_asset'=>'0.02000000'];$before=Db::name('wallet_asset_account')->where('id',$account['id'])->find();$holdId=OtcAdEscrowService::createSell($sell,$uid);$held=Db::name('wallet_asset_account')->where('id',$account['id'])->find();assertAmount((string)$held['available_balance'],bcsub((string)$before['available_balance'],'0.02000000',8),8,'卖币广告冻结可用');assertAmount((string)$held['frozen_balance'],bcadd((string)$before['frozen_balance'],'0.02000000',8),8,'卖币广告冻结余额');$sell['asset_hold_id']=$holdId;OtcAdEscrowService::consumeSell($sell,'0.00500000','TEST'.$tag);$partial=Db::name('wallet_asset_hold')->where('id',$holdId)->find();assertAmount((string)$partial['remaining_amount'],'0.01500000',8,'卖币广告部分消费');OtcAdEscrowService::release($sell,'测试释放');$sellAfter=Db::name('wallet_asset_account')->where('id',$account['id'])->find();assertAmount((string)$sellAfter['available_balance'],bcsub((string)$before['available_balance'],'0.00500000',8),8,'卖币广告最终可用');assertAmount((string)$sellAfter['frozen_balance'],(string)$before['frozen_balance'],8,'卖币广告最终冻结');
    Db::name('otc_ad_fiat_hold')->where('ad_id',$tag)->delete();$buy=['id'=>$tag,'appid'=>$appid,'merchant_id'=>$merchant['id'],'side'=>'buy','price'=>'10.0000','available_asset'=>'0.02000000'];$moneyBefore=Db::name('user')->where(['appid'=>$appid,'id'=>$uid])->value('money');$fiatHold=OtcAdEscrowService::createBuy($buy,$uid);$buy['fiat_hold_id']=$fiatHold;assertAmount((string)Db::name('user')->where(['appid'=>$appid,'id'=>$uid])->value('money'),bcsub((string)$moneyBefore,'0.20',2),2,'买币广告冻结余额');OtcAdEscrowService::consumeBuy($buy,'0.05','TEST'.$tag,$uid);OtcAdEscrowService::release($buy,'测试释放');assertAmount((string)Db::name('user')->where(['appid'=>$appid,'id'=>$uid])->value('money'),(string)$moneyBefore,2,'同账户买卖测试净额');
    echo "escrow tests ok\n";Db::rollback();
}catch(Throwable $e){Db::rollback();throw $e;}
