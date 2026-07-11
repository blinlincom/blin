<?php

declare(strict_types=1);

namespace app\common\support;

use think\facade\Db;
use think\facade\Env;

final class GasFreeAccountService
{
    public static function enabledFor(int $appid,int $userId,int $assetId,int $networkId):bool
    {
        $config=Db::name('wallet_gasfree_config')->where(['appid'=>$appid,'asset_id'=>$assetId,'network_id'=>$networkId])->find();
        if(!$config||(int)$config['enabled']!==1)return false;$mode=(string)$config['rollout_mode'];if($mode==='all')return true;if($mode!=='whitelist')return false;
        return Db::name('wallet_gasfree_whitelist')->where(['appid'=>$appid,'user_id'=>$userId])->where('status',1)->count()>0;
    }

    public static function address(int $appid,int $userId,int $assetId,int $networkId,string $token,int $decimals):array
    {
        $row=Db::name('wallet_gasfree_account')->where(['appid'=>$appid,'user_id'=>$userId,'asset_id'=>$assetId,'network_id'=>$networkId])->find();if($row&&(int)$row['status']===1)return $row;
        $result=self::walletCall('/internal/gasfree/account',['appid'=>$appid,'user_id'=>$userId]);$eoa=trim((string)($result['eoa_address']??''));$address=trim((string)($result['gasfree_address']??''));if(!preg_match('/^T[1-9A-HJ-NP-Za-km-z]{33}$/',$eoa)||!preg_match('/^T[1-9A-HJ-NP-Za-km-z]{33}$/',$address))throw new \RuntimeException('GasFree地址返回异常');
        Db::startTrans();try{$existing=Db::name('wallet_gasfree_account')->where(['appid'=>$appid,'user_id'=>$userId,'asset_id'=>$assetId,'network_id'=>$networkId])->lock(true)->find();$now=date('Y-m-d H:i:s');$values=['eoa_address'=>$eoa,'gasfree_address'=>$address,'provider_address'=>trim((string)($result['provider_address']??'')),'token_address'=>$token,'token_decimals'=>$decimals,'active'=>!empty($result['active'])?1:0,'allow_submit'=>!empty($result['allow_submit'])?1:0,'recommended_nonce'=>(int)($result['recommended_nonce']??0),'status'=>1,'last_sync_time'=>$now,'update_time'=>$now];if($existing){Db::name('wallet_gasfree_account')->where('id',$existing['id'])->update($values);$id=(int)$existing['id'];}else{$id=(int)Db::name('wallet_gasfree_account')->insertGetId($values+['appid'=>$appid,'user_id'=>$userId,'asset_id'=>$assetId,'network_id'=>$networkId,'onchain_balance'=>'0.00000000','provider_frozen'=>'0.00000000','create_time'=>$now]);}Db::commit();return Db::name('wallet_gasfree_account')->where('id',$id)->find()?:[];}catch(\Throwable $e){Db::rollback();throw $e;}
    }

    private static function walletCall(string $path,array $payload):array
    {
        $url=rtrim((string)Env::get('tron.wallet_service_url','http://127.0.0.1:9088'),'/');$secret=(string)Env::get('tron.internal_secret','');if($secret===''||strlen($secret)<32)throw new \RuntimeException('GasFree内部认证未配置');$body=json_encode($payload,JSON_UNESCAPED_SLASHES);$timestamp=(string)time();$signature=hash_hmac('sha256',$timestamp."\n".$body,$secret);$ch=curl_init($url.$path);curl_setopt_array($ch,[CURLOPT_POST=>true,CURLOPT_POSTFIELDS=>$body,CURLOPT_RETURNTRANSFER=>true,CURLOPT_CONNECTTIMEOUT=>3,CURLOPT_TIMEOUT=>10,CURLOPT_HTTPHEADER=>['Content-Type: application/json','X-BIM-Timestamp: '.$timestamp,'X-BIM-Signature: '.$signature]]);$raw=curl_exec($ch);$code=(int)curl_getinfo($ch,CURLINFO_HTTP_CODE);$error=curl_error($ch);curl_close($ch);$result=json_decode((string)$raw,true);if($code!==200||!is_array($result))throw new \RuntimeException($code===503?'GasFree充值暂未开放':'GasFree地址服务异常'.($error!==''?'：'.$error:''));return $result;
    }
}
