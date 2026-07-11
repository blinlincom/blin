<?php

declare(strict_types=1);

require '/www/wwwroot/blin/vendor/autoload.php';

$app = new think\App();
$app->initialize();

use app\common\support\OtcAdEscrowService;
use think\facade\Db;

$schema = Db::query("SELECT COLUMN_NAME FROM information_schema.COLUMNS WHERE TABLE_SCHEMA=DATABASE() AND TABLE_NAME='mr_otc_ad'");
$columns = array_column($schema, 'COLUMN_NAME');
foreach ([
    'asset_hold_id' => "ALTER TABLE mr_otc_ad ADD asset_hold_id bigint unsigned NOT NULL DEFAULT 0 AFTER deposit_reserved",
    'fiat_hold_id' => "ALTER TABLE mr_otc_ad ADD fiat_hold_id bigint unsigned NOT NULL DEFAULT 0 AFTER asset_hold_id",
    'escrow_remaining' => "ALTER TABLE mr_otc_ad ADD escrow_remaining decimal(30,8) NOT NULL DEFAULT 0.00000000 AFTER fiat_hold_id",
] as $column => $sql) if (!in_array($column, $columns, true)) Db::execute($sql);
Db::execute("CREATE TABLE IF NOT EXISTS mr_otc_ad_fiat_hold (`id` bigint unsigned NOT NULL AUTO_INCREMENT,`appid` int unsigned NOT NULL,`merchant_id` bigint unsigned NOT NULL,`user_id` bigint unsigned NOT NULL,`ad_id` bigint unsigned NOT NULL,`amount` decimal(18,2) NOT NULL,`remaining_amount` decimal(18,2) NOT NULL,`status` tinyint unsigned NOT NULL DEFAULT 1,`create_time` datetime NOT NULL,`update_time` datetime NOT NULL,PRIMARY KEY (`id`),UNIQUE KEY `uk_otc_ad_fiat_ad` (`appid`,`ad_id`),KEY `idx_otc_ad_fiat_user` (`appid`,`user_id`,`status`)) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4");

$ads=Db::name('otc_ad')->whereIn('status',[0,1])->where('asset_hold_id',0)->where('fiat_hold_id',0)->order('id')->select()->toArray();
foreach($ads as $ad){
    Db::startTrans();
    try{
        $ad=Db::name('otc_ad')->where('id',(int)$ad['id'])->lock(true)->find();
        if(!$ad||!in_array((int)$ad['status'],[0,1],true)){Db::commit();continue;}
        $merchant=Db::name('otc_merchant')->where('id',(int)$ad['merchant_id'])->lock(true)->find();
        if(!$merchant)throw new RuntimeException('商家不存在');
        try{
            $holdId=(string)$ad['side']==='sell'?OtcAdEscrowService::createSell($ad,(int)$merchant['user_id']):OtcAdEscrowService::createBuy($ad,(int)$merchant['user_id']);
            $field=(string)$ad['side']==='sell'?'asset_hold_id':'fiat_hold_id';$escrow=(string)$ad['side']==='sell'?(string)$ad['available_asset']:bcmul((string)$ad['price'],(string)$ad['available_asset'],2);
            Db::name('otc_ad')->where('id',(int)$ad['id'])->update([$field=>$holdId,'escrow_remaining'=>$escrow,'update_time'=>date('Y-m-d H:i:s')]);
            echo "migrated ad {$ad['id']}\n";
        }catch(Throwable $e){
            $deposit=bcadd((string)($ad['deposit_reserved']??0),'0',2);$next=bcsub((string)($merchant['deposit_ad_reserved']??0),$deposit,2);if(bccomp($next,'0',2)<0)$next='0.00';Db::name('otc_merchant')->where('id',(int)$merchant['id'])->update(['deposit_ad_reserved'=>$next,'version'=>Db::raw('version+1'),'update_time'=>date('Y-m-d H:i:s')]);Db::name('otc_ad')->where('id',(int)$ad['id'])->update(['status'=>3,'deposit_reserved'=>'0.00','update_time'=>date('Y-m-d H:i:s')]);echo "suspended ad {$ad['id']}: {$e->getMessage()}\n";
        }
        Db::commit();
    }catch(Throwable $e){Db::rollback();throw $e;}
}
echo "migration ok\n";
