<?php

declare(strict_types=1);

namespace app\common\support;

use think\facade\Db;
use think\facade\Env;

final class DigitalAssetService
{
    public function __construct(private int $appid, private array $user)
    {
    }

    public function overview(): array
    {
        $asset = $this->usdtAsset();
        $network = $this->trc20Network($asset);
        $account = $this->account((int)$asset['id'], false);
        $config = $this->chainConfig((int)$asset['id'], (int)$network['id']);
        $address = Db::name('wallet_chain_address')
            ->where('appid', $this->appid)->where('user_id', $this->uid())
            ->where('asset_id', (int)$asset['id'])->where('network_id', (int)$network['id'])->find() ?: [];
        return [
            'asset_id' => (int)$asset['id'],
            'symbol' => 'USDT',
            'asset_name' => (string)$asset['name'],
            'network_id' => (int)$network['id'],
            'network_code' => 'TRC20',
            'available_balance' => $this->amount($account['available_balance'] ?? 0),
            'frozen_balance' => $this->amount($account['frozen_balance'] ?? 0),
            'total_balance' => $this->amount(bcadd((string)($account['available_balance'] ?? 0), (string)($account['frozen_balance'] ?? 0), 8)),
            'deposit_enabled' => (int)($config['deposit_enabled'] ?? 0) === 1,
            'withdraw_enabled' => (int)($config['withdraw_enabled'] ?? 0) === 1,
            'transfer_enabled' => (int)($config['transfer_enabled'] ?? 1) === 1,
            'min_deposit' => $this->amount($config['min_deposit'] ?? 1),
            'min_withdraw' => $this->amount($config['min_withdraw'] ?? 10),
            'withdraw_fee' => $this->amount($config['withdraw_fee'] ?? 1),
            'address_assigned' => $address ? 1 : 0,
            'deposit_address' => (string)($address['address_base58'] ?? ''),
        ];
    }

    public function depositAddress(): array
    {
        $asset = $this->usdtAsset();
        $network = $this->trc20Network($asset);
        $config = $this->chainConfig((int)$asset['id'], (int)$network['id']);
        if ((int)($config['status'] ?? 0) !== 1 || (int)($config['deposit_enabled'] ?? 0) !== 1) {
            throw new \RuntimeException('USDT充值暂未开放');
        }
        $row = Db::name('wallet_chain_address')->where('appid', $this->appid)->where('user_id', $this->uid())
            ->where('asset_id', (int)$asset['id'])->where('network_id', (int)$network['id'])->find();
        if (!$row) {
            $row = $this->deriveAddress((int)$asset['id'], (int)$network['id'], $config);
        }
        return [
            'asset' => 'USDT', 'network' => 'TRC20',
            'address' => (string)$row['address_base58'],
            'min_deposit' => $this->amount($config['min_deposit'] ?? 1),
            'notice' => '仅支持向此地址充值USDT-TRC20，其他资产或网络将无法找回。',
        ];
    }

    public function transferPreview(array $data): array
    {
        $this->assertWalletActive();
        $asset = $this->usdtAsset();$network=$this->trc20Network($asset);$config=$this->chainConfig((int)$asset['id'],(int)$network['id']);if((int)($config['transfer_enabled']??0)!==1)throw new \RuntimeException('USDT站内转账暂未开放');
        DigitalAssetControlService::assertAllowed($this->appid,$this->uid(),(int)$asset['id'],'transfer');
        $receiver = $this->receiver(trim((string)($data['username'] ?? '')));
        $amount = $this->positiveAmount($data['amount'] ?? '0');
        $account = $this->account((int)$asset['id'], false);
        if (bccomp((string)$account['available_balance'], $amount, 8) < 0) throw new \RuntimeException('USDT可用余额不足');
        return ['receiver' => $this->userView($receiver), 'amount' => $amount, 'fee' => '0.00000000', 'receive_amount' => $amount];
    }

    public function transfer(array $data): array
    {
        $this->assertWalletActive();
        $requestId = $this->requestId($data['request_id'] ?? '');
        $receiver = $this->receiver(trim((string)($data['username'] ?? '')));
        $amount = $this->positiveAmount($data['amount'] ?? '0');
        $remark = mb_substr(trim((string)($data['remark'] ?? '')), 0, 120);
        $asset = $this->usdtAsset();
        DigitalAssetControlService::assertAllowed($this->appid,$this->uid(),(int)$asset['id'],'transfer');
        $params = ['sender_id'=>$this->uid(),'receiver_id'=>(int)$receiver['id'],'asset_id'=>(int)$asset['id'],'amount'=>$amount,'remark'=>$remark];
        $hash = hash('sha256', json_encode($params, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES));
        $existing = Db::name('wallet_asset_journal')->where('appid',$this->appid)->where('request_id',$requestId)->find();
        if ($existing) {
            if (!hash_equals((string)$existing['param_hash'], $hash)) throw new \RuntimeException('request_id已被其他交易使用');
            return $this->transferByNo((string)$existing['business_no']);
        }
        $transferNo = $this->number('AT');
        Db::startTrans();
        try {
            $senderAccount = $this->account((int)$asset['id'], false, $this->uid());
            $receiverAccount = $this->account((int)$asset['id'], false, (int)$receiver['id']);
            $ids = [(int)$senderAccount['id'], (int)$receiverAccount['id']]; sort($ids);
            $locked = Db::name('wallet_asset_account')->whereIn('id',$ids)->order('id')->lock(true)->select()->toArray();
            $byId=[]; foreach($locked as $item)$byId[(int)$item['id']]=$item;
            $senderAccount=$byId[(int)$senderAccount['id']];$receiverAccount=$byId[(int)$receiverAccount['id']];
            if (bccomp((string)$senderAccount['available_balance'],$amount,8)<0) throw new \RuntimeException('USDT可用余额不足');
            $journalId=(int)Db::name('wallet_asset_journal')->insertGetId(['appid'=>$this->appid,'journal_no'=>$this->number('J'),'request_id'=>$requestId,'business_type'=>'internal_transfer','business_no'=>$transferNo,'asset_id'=>(int)$asset['id'],'status'=>1,'param_hash'=>$hash,'create_time'=>date('Y-m-d H:i:s')]);
            $senderAfter=bcsub((string)$senderAccount['available_balance'],$amount,8);$receiverAfter=bcadd((string)$receiverAccount['available_balance'],$amount,8);$now=date('Y-m-d H:i:s');
            Db::name('wallet_asset_account')->where('id',(int)$senderAccount['id'])->update(['available_balance'=>$senderAfter,'total_out'=>bcadd((string)$senderAccount['total_out'],$amount,8),'version'=>Db::raw('version+1'),'update_time'=>$now]);
            Db::name('wallet_asset_account')->where('id',(int)$receiverAccount['id'])->update(['available_balance'=>$receiverAfter,'total_in'=>bcadd((string)$receiverAccount['total_in'],$amount,8),'version'=>Db::raw('version+1'),'update_time'=>$now]);
            Db::name('wallet_asset_entry')->insertAll([
                ['journal_id'=>$journalId,'account_id'=>(int)$senderAccount['id'],'user_id'=>$this->uid(),'direction'=>'debit','available_delta'=>'-'.$amount,'frozen_delta'=>'0.00000000','available_after'=>$senderAfter,'frozen_after'=>(string)$senderAccount['frozen_balance'],'remark'=>$remark,'create_time'=>$now],
                ['journal_id'=>$journalId,'account_id'=>(int)$receiverAccount['id'],'user_id'=>(int)$receiver['id'],'direction'=>'credit','available_delta'=>$amount,'frozen_delta'=>'0.00000000','available_after'=>$receiverAfter,'frozen_after'=>(string)$receiverAccount['frozen_balance'],'remark'=>$remark,'create_time'=>$now],
            ]);
            Db::name('wallet_asset_transfer')->insert(['appid'=>$this->appid,'transfer_no'=>$transferNo,'request_id'=>$requestId,'asset_id'=>(int)$asset['id'],'sender_id'=>$this->uid(),'receiver_id'=>(int)$receiver['id'],'amount'=>$amount,'remark'=>$remark,'status'=>'success','create_time'=>$now]);
            Db::commit();
        } catch (\Throwable $e) {
            Db::rollback();
            $duplicate=Db::name('wallet_asset_journal')->where('appid',$this->appid)->where('request_id',$requestId)->find();
            if($duplicate&&hash_equals((string)$duplicate['param_hash'],$hash))return $this->transferByNo((string)$duplicate['business_no']);
            throw $e;
        }
        return $this->transferByNo($transferNo);
    }

    public function withdrawPreview(array $data): array
    {
        $this->assertWalletActive();
        $asset=$this->usdtAsset();DigitalAssetControlService::assertAllowed($this->appid,$this->uid(),(int)$asset['id'],'withdraw');$network=$this->trc20Network($asset);$config=$this->chainConfig((int)$asset['id'],(int)$network['id']);
        if((int)($config['status']??0)!==1||(int)($config['withdraw_enabled']??0)!==1)throw new \RuntimeException('USDT提币暂未开放');
        $address=$this->validateAddress((string)($data['address']??''));$amount=$this->positiveAmount($data['amount']??'0');$fee=$this->amount($config['withdraw_fee']??1);$min=$this->amount($config['min_withdraw']??10);
        if(bccomp($amount,$min,8)<0)throw new \RuntimeException('提币数量低于最低限额');if(bccomp($amount,$fee,8)<=0)throw new \RuntimeException('提币数量必须大于手续费');
        $account=$this->account((int)$asset['id'],false);if(bccomp((string)$account['available_balance'],$amount,8)<0)throw new \RuntimeException('USDT可用余额不足');
        $today=(string)(Db::name('wallet_withdraw_order')->where('appid',$this->appid)->where('user_id',$this->uid())->whereDay('create_time')->whereNotIn('status',['rejected'])->sum('amount')??'0');$limit=$this->amount($config['daily_withdraw_limit']??10000);if(bccomp(bcadd($today,$amount,8),$limit,8)>0)throw new \RuntimeException('超过USDT单日提币限额');
        return ['address'=>$address,'amount'=>$amount,'fee'=>$fee,'receive_amount'=>bcsub($amount,$fee,8),'network'=>'TRC20'];
    }

    public function withdraw(array $data): array
    {
        $preview=$this->withdrawPreview($data);$requestId=$this->requestId($data['request_id']??'');$asset=$this->usdtAsset();$network=$this->trc20Network($asset);$config=$this->chainConfig((int)$asset['id'],(int)$network['id']);
        $params=['user_id'=>$this->uid(),'asset_id'=>(int)$asset['id'],'network_id'=>(int)$network['id'],'address'=>$preview['address'],'amount'=>$preview['amount'],'fee'=>$preview['fee']];$hash=hash('sha256',json_encode($params,JSON_UNESCAPED_SLASHES));
        $existing=Db::name('wallet_asset_journal')->where('appid',$this->appid)->where('request_id',$requestId)->find();if($existing){if(!hash_equals((string)$existing['param_hash'],$hash))throw new \RuntimeException('request_id已被其他交易使用');return $this->withdrawByNo((string)$existing['business_no']);}
        $withdrawNo=$this->number('AW');Db::startTrans();try{$account=$this->account((int)$asset['id'],true);if(bccomp((string)$account['available_balance'],(string)$preview['amount'],8)<0)throw new \RuntimeException('USDT可用余额不足');$now=date('Y-m-d H:i:s');$afterA=bcsub((string)$account['available_balance'],(string)$preview['amount'],8);$afterF=bcadd((string)$account['frozen_balance'],(string)$preview['amount'],8);
            $journalId=(int)Db::name('wallet_asset_journal')->insertGetId(['appid'=>$this->appid,'journal_no'=>$this->number('J'),'request_id'=>$requestId,'business_type'=>'withdraw_freeze','business_no'=>$withdrawNo,'asset_id'=>(int)$asset['id'],'status'=>1,'param_hash'=>$hash,'create_time'=>$now]);
            Db::name('wallet_asset_account')->where('id',(int)$account['id'])->update(['available_balance'=>$afterA,'frozen_balance'=>$afterF,'version'=>Db::raw('version+1'),'update_time'=>$now]);
            Db::name('wallet_asset_entry')->insert(['journal_id'=>$journalId,'account_id'=>(int)$account['id'],'user_id'=>$this->uid(),'direction'=>'hold','available_delta'=>'-'.(string)$preview['amount'],'frozen_delta'=>(string)$preview['amount'],'available_after'=>$afterA,'frozen_after'=>$afterF,'remark'=>'TRC20提币冻结','create_time'=>$now]);
            Db::name('wallet_withdraw_order')->insert(['appid'=>$this->appid,'withdraw_no'=>$withdrawNo,'request_id'=>$requestId,'user_id'=>$this->uid(),'asset_id'=>(int)$asset['id'],'network_id'=>(int)$network['id'],'to_address'=>$preview['address'],'amount'=>$preview['amount'],'fee'=>$preview['fee'],'receive_amount'=>$preview['receive_amount'],'status'=>'risk_review','risk_level'=>0,'config_version'=>(int)($config['config_version']??1),'version'=>1,'create_time'=>$now,'update_time'=>$now]);Db::commit();
        }catch(\Throwable $e){Db::rollback();$duplicate=Db::name('wallet_asset_journal')->where('appid',$this->appid)->where('request_id',$requestId)->find();if($duplicate&&hash_equals((string)$duplicate['param_hash'],$hash))return $this->withdrawByNo((string)$duplicate['business_no']);throw $e;}return $this->withdrawByNo($withdrawNo);
    }

    public function bills(array $data): array
    {
        $asset=$this->usdtAsset();$limit=max(1,min(100,(int)($data['limit']??30)));$rows=Db::name('wallet_asset_entry')->alias('e')->join('wallet_asset_journal j','j.id=e.journal_id')->where('j.appid',$this->appid)->where('j.asset_id',(int)$asset['id'])->where('e.user_id',$this->uid())->field('e.id,j.business_type,j.business_no,e.direction,e.available_delta,e.frozen_delta,e.available_after,e.frozen_after,e.remark,e.create_time')->order('e.id desc')->limit($limit)->select()->toArray();return $rows;
    }

    public function withdrawals(): array { return Db::name('wallet_withdraw_order')->where('appid',$this->appid)->where('user_id',$this->uid())->order('id desc')->limit(100)->select()->toArray(); }

    private function deriveAddress(int $assetId,int $networkId,array $config):array
    {
        $result=$this->walletServiceCall('/internal/address/derive',['appid'=>$this->appid,'user_id'=>$this->uid(),'asset_id'=>$assetId,'network_id'=>$networkId],$config);if(empty($result['address'])||!isset($result['index']))throw new \RuntimeException('地址服务返回异常');
        $now=date('Y-m-d H:i:s');try{Db::name('wallet_chain_address')->insert(['appid'=>$this->appid,'user_id'=>$this->uid(),'asset_id'=>$assetId,'network_id'=>$networkId,'address_base58'=>(string)$result['address'],'address_hex'=>(string)($result['address_hex']??''),'derivation_index'=>(int)$result['index'],'derivation_path'=>(string)($result['path']??''),'status'=>1,'assigned_time'=>$now]);}catch(\Throwable){}$row=Db::name('wallet_chain_address')->where('appid',$this->appid)->where('user_id',$this->uid())->where('asset_id',$assetId)->where('network_id',$networkId)->find();if(!$row)throw new \RuntimeException('充值地址分配失败');return $row;
    }

    private function account(int $assetId,bool $lock=true,?int $userId=null):array
    {
        $userId??=$this->uid();$query=Db::name('wallet_asset_account')->where('appid',$this->appid)->where('user_id',$userId)->where('asset_id',$assetId);if($lock)$query->lock(true);$row=$query->find();if(!$row){$now=date('Y-m-d H:i:s');try{Db::name('wallet_asset_account')->insert(['appid'=>$this->appid,'user_id'=>$userId,'asset_id'=>$assetId,'available_balance'=>'0.00000000','frozen_balance'=>'0.00000000','total_in'=>'0.00000000','total_out'=>'0.00000000','version'=>1,'create_time'=>$now,'update_time'=>$now]);}catch(\Throwable){}$query=Db::name('wallet_asset_account')->where('appid',$this->appid)->where('user_id',$userId)->where('asset_id',$assetId);if($lock)$query->lock(true);$row=$query->find();}if(!$row)throw new \RuntimeException('数字资产账户创建失败');return $row;
    }

    private function receiver(string $username):array { if($username===''||strlen($username)>50)throw new \InvalidArgumentException('请输入正确的用户名');$row=Db::name('user')->where('appid',$this->appid)->where('username',$username)->find();if(!$row)throw new \RuntimeException('收款用户不存在');if((int)$row['id']===$this->uid())throw new \RuntimeException('不能向自己转账');return $row; }
    private function userView(array $row):array{return ['user_id'=>(int)$row['id'],'username'=>(string)$row['username'],'nickname'=>(string)($row['nickname']??''),'avatar'=>(string)($row['usertx']??'')];}
    private function usdtAsset():array{$row=Db::name('otc_asset')->where('appid',$this->appid)->where('symbol','USDT')->where('status',1)->find();if(!$row)throw new \RuntimeException('USDT资产未配置');return $row;}
    private function trc20Network(array $asset):array{$row=Db::name('otc_asset_network')->alias('an')->join('otc_network n','n.id=an.network_id and n.appid=an.appid')->where('an.appid',$this->appid)->where('an.asset_id',(int)$asset['id'])->where('an.status',1)->where('n.status',1)->whereIn('n.code',['TRC20','TRON'])->field('n.*')->find();if(!$row)throw new \RuntimeException('TRC20网络未配置');return $row;}
    private function chainConfig(int $assetId,int $networkId):array{return Db::name('wallet_chain_config')->where('appid',$this->appid)->where('asset_id',$assetId)->where('network_id',$networkId)->find()?:[];}
    private function validateAddress(string $value):string{$address=trim($value);if(!preg_match('/^T[1-9A-HJ-NP-Za-km-z]{33}$/',$address))throw new \InvalidArgumentException('TRC20地址格式错误');$asset=$this->usdtAsset();$network=$this->trc20Network($asset);$config=$this->chainConfig((int)$asset['id'],(int)$network['id']);$this->walletServiceCall('/internal/address/validate',['address'=>$address],$config);return $address;}
    private function positiveAmount(mixed $value):string{$text=trim((string)$value);if(!preg_match('/^\d+(\.\d{1,8})?$/',$text))throw new \InvalidArgumentException('数量格式错误');$amount=bcadd($text,'0',8);if(bccomp($amount,'0.00000000',8)<=0)throw new \InvalidArgumentException('数量必须大于0');return $amount;}
    private function amount(mixed $value):string{return bcadd((string)$value,'0',8);}
    private function requestId(mixed $value):string{$id=trim((string)$value);if(!preg_match('/^[A-Za-z0-9_-]{8,80}$/',$id))throw new \InvalidArgumentException('request_id不合法');return $id;}
    private function number(string $prefix):string{return $prefix.date('YmdHis').strtoupper(bin2hex(random_bytes(6)));}
    private function uid():int{return (int)$this->user['id'];}
    private function assertWalletActive():void{if((int)($this->user['wallet_status']??1)!==1)throw new \RuntimeException('钱包当前不可用');}
    private function transferByNo(string $no):array{$row=Db::name('wallet_asset_transfer')->where('appid',$this->appid)->where('transfer_no',$no)->find();if(!$row)throw new \RuntimeException('转账记录不存在');return $row;}
    private function withdrawByNo(string $no):array{$row=Db::name('wallet_withdraw_order')->where('appid',$this->appid)->where('withdraw_no',$no)->find();if(!$row)throw new \RuntimeException('提币记录不存在');return $row;}
    private function walletServiceCall(string $path,array $payload,array $config):array{$url=rtrim((string)($config['wallet_service_url']??Env::get('tron.wallet_service_url','')),'/');$secret=(string)Env::get('tron.internal_secret','');if($url===''||$secret==='')throw new \RuntimeException('链上钱包服务尚未配置');$body=json_encode($payload,JSON_UNESCAPED_SLASHES);$timestamp=(string)time();$signature=hash_hmac('sha256',$timestamp."\n".$body,$secret);$ch=curl_init($url.$path);curl_setopt_array($ch,[CURLOPT_POST=>true,CURLOPT_POSTFIELDS=>$body,CURLOPT_RETURNTRANSFER=>true,CURLOPT_TIMEOUT=>8,CURLOPT_HTTPHEADER=>['Content-Type: application/json','X-BIM-Timestamp: '.$timestamp,'X-BIM-Signature: '.$signature]]);$raw=curl_exec($ch);$code=(int)curl_getinfo($ch,CURLINFO_HTTP_CODE);curl_close($ch);$result=json_decode((string)$raw,true);if($raw===false||$code!==200||!is_array($result))throw new \RuntimeException('TRC20地址校验失败');return $result;}
}
