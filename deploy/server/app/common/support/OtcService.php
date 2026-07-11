<?php

declare(strict_types=1);

namespace app\common\support;

use think\facade\Db;

final class OtcService
{
    public function __construct(private int $appid, private array $user)
    {
    }

    public function config(): array
    {
        $row = Db::name('otc_config')->where('appid', $this->appid)->find() ?: [];
        return [
            'enabled' => (int)($row['enabled'] ?? 0) === 1,
            'manual_escrow' => true,
            'merchant_deposit' => $this->decimal($row['merchant_deposit'] ?? 1000, 2),
            'ad_deposit_rate' => $this->decimal($row['ad_deposit_rate'] ?? 5, 2),
            'max_merchant_ads' => max(1, (int)($row['max_merchant_ads'] ?? 10)),
            'payment_timeout_minutes' => max(5, (int)($row['payment_timeout_minutes'] ?? 15)),
            'max_open_orders' => max(1, (int)($row['max_open_orders'] ?? 5)),
            'payment_methods' => ['balance'],
            'risk_notice' => (string)($row['risk_notice'] ?? ''),
            'assets' => $this->assets(),
            'merchant' => $this->merchant(),
        ];
    }

    public function assets(): array
    {
        $rows = Db::name('otc_asset')->alias('a')
            ->join('otc_asset_network an', 'an.asset_id=a.id and an.appid=a.appid and an.status=1')
            ->join('otc_network n', 'n.id=an.network_id and n.appid=a.appid and n.status=1')
            ->where('a.appid', $this->appid)->where('a.status', 1)
            ->field('a.id,a.symbol,a.name,a.precision_scale,n.id network_id,n.code network_code,n.name network_name,an.min_amount,an.max_amount,an.fee_amount')
            ->order('a.sort desc,n.sort desc')->select()->toArray();
        $result = [];
        foreach ($rows as $row) {
            $id = (int)$row['id'];
            $result[$id] ??= ['id' => $id, 'symbol' => $row['symbol'], 'name' => $row['name'], 'precision' => (int)$row['precision_scale'], 'networks' => []];
            $result[$id]['networks'][] = [
                'id' => (int)$row['network_id'], 'code' => $row['network_code'], 'name' => $row['network_name'],
                'min_amount' => $this->decimal($row['min_amount'], 8), 'max_amount' => $this->decimal($row['max_amount'], 8),
                'fee_amount' => $this->decimal($row['fee_amount'], 8),
            ];
        }
        return array_values($result);
    }

    public function addresses(): array
    {
        return Db::name('otc_user_address')->alias('x')
            ->join('otc_asset a', 'a.id=x.asset_id and a.appid=x.appid')
            ->join('otc_network n', 'n.id=x.network_id and n.appid=x.appid')
            ->where('x.appid', $this->appid)->where('x.user_id', $this->uid())->where('x.status', 1)
            ->field('x.id,x.label,x.address,x.asset_id,a.symbol,x.network_id,n.code network_code,n.name network_name,x.create_time')
            ->order('x.id desc')->select()->toArray();
    }

    public function saveAddress(array $data): array
    {
        $assetId = (int)($data['asset_id'] ?? 0);
        $networkId = (int)($data['network_id'] ?? 0);
        $address = trim((string)($data['address'] ?? ''));
        $network = $this->assetNetwork($assetId, $networkId);
        if ($address === '' || strlen($address) > 255) throw new \InvalidArgumentException('收币地址格式错误');
        $pattern = (string)$network['address_pattern'];
        if ($pattern !== '' && @preg_match($pattern, $address) !== 1) throw new \InvalidArgumentException('地址与所选网络不匹配');
        $now = date('Y-m-d H:i:s');
        $hash = hash('sha256', strtolower($address));
        $row = Db::name('otc_user_address')->where(['appid'=>$this->appid,'user_id'=>$this->uid(),'asset_id'=>$assetId,'network_id'=>$networkId,'address_hash'=>$hash])->find();
        $values = ['label'=>mb_substr(trim((string)($data['label'] ?? '')),0,64),'address'=>$address,'status'=>1,'update_time'=>$now];
        if ($row) {
            Db::name('otc_user_address')->where('id', (int)$row['id'])->update($values);
            $id = (int)$row['id'];
        } else {
            $id = (int)Db::name('otc_user_address')->insertGetId($values + ['appid'=>$this->appid,'user_id'=>$this->uid(),'asset_id'=>$assetId,'network_id'=>$networkId,'address_hash'=>$hash,'create_time'=>$now]);
        }
        foreach ($this->addresses() as $item) if ((int)$item['id'] === $id) return $item;
        throw new \RuntimeException('保存地址失败');
    }

    public function paymentMethods(): array
    {
        $rows = Db::name('otc_payment_method')->where('appid',$this->appid)->where('user_id',$this->uid())->where('status',1)->order('id desc')->select()->toArray();
        return array_map(fn($row) => $this->paymentView($row), $rows);
    }

    public function tradeOptions(array $data): array
    {
        $side=strtolower(trim((string)($data['side']??'')));
        if(!in_array($side,['buy','sell'],true))throw new \InvalidArgumentException('交易方向错误');
        $ad=Db::name('otc_ad')->where('appid',$this->appid)->where('id',(int)($data['ad_id']??0))->where('status',1)->find();
        if(!$ad||(string)$ad['side']!==($side==='buy'?'sell':'buy'))throw new \RuntimeException('广告已不可交易');
        $merchant=Db::name('otc_merchant')->where('appid',$this->appid)->where('id',(int)$ad['merchant_id'])->where('status',1)->find();
        if(!$merchant||(int)$merchant['user_id']===$this->uid())throw new \RuntimeException('商家不可交易');
        return ['side'=>$side,'payments'=>[['id'=>0,'method_type'=>'balance','account_name'=>'平台余额','account_no_masked'=>'平台余额','bank_name'=>'','qr_url'=>'']],'addresses'=>[['id'=>0,'label'=>'平台数字资产账户','address'=>'平台数字资产账户','asset_id'=>(int)$ad['asset_id'],'network_id'=>(int)$ad['network_id']]],'payment_owner'=>'platform','address_owner'=>'platform'];
    }

    public function savePaymentMethod(array $data): array
    {
        $type = strtolower(trim((string)($data['method_type'] ?? '')));
        $name = mb_substr(trim((string)($data['account_name'] ?? '')), 0, 80);
        $number = trim((string)($data['account_no'] ?? ''));
        if (!in_array($type,['alipay','wechat','bank'],true)) throw new \InvalidArgumentException('不支持的收款方式');
        if ($name === '' || $number === '' || strlen($number) > 120) throw new \InvalidArgumentException('收款信息不完整');
        $hash = hash('sha256', strtolower(preg_replace('/\s+/', '', $number)));
        $now = date('Y-m-d H:i:s');
        $row = Db::name('otc_payment_method')->where(['appid'=>$this->appid,'user_id'=>$this->uid(),'method_type'=>$type,'account_no_hash'=>$hash])->find();
        $values = ['account_name'=>$name,'account_no_cipher'=>$this->seal($number),'bank_name'=>mb_substr(trim((string)($data['bank_name']??'')),0,80),'qr_url'=>mb_substr(trim((string)($data['qr_url']??'')),0,500),'status'=>1,'update_time'=>$now];
        if ($row) { Db::name('otc_payment_method')->where('id',(int)$row['id'])->update($values); $id=(int)$row['id']; }
        else { $id=(int)Db::name('otc_payment_method')->insertGetId($values + ['appid'=>$this->appid,'user_id'=>$this->uid(),'method_type'=>$type,'account_no_hash'=>$hash,'create_time'=>$now]); }
        return $this->paymentView(Db::name('otc_payment_method')->where('id',$id)->find() ?: []);
    }

    public function merchant(): array
    {
        $row = Db::name('otc_merchant')->where('appid',$this->appid)->where('user_id',$this->uid())->find();
        if (!$row) return ['applied'=>false,'status'=>-1,'status_name'=>'未申请'];
        $names=[0=>'审核中',1=>'正常',2=>'已驳回',3=>'已冻结',4=>'退出中'];
        $amount=$this->decimal($row['deposit_amount'],2);$reserved=$this->decimal($row['deposit_ad_reserved']??0,2);
        return ['applied'=>true,'id'=>(int)$row['id'],'merchant_no'=>$row['merchant_no'],'status'=>(int)$row['status'],'status_name'=>$names[(int)$row['status']]??'未知','level'=>(int)$row['level'],'deposit_required'=>$this->decimal($row['deposit_required'],2),'deposit_amount'=>$amount,'deposit_ad_reserved'=>$reserved,'deposit_available'=>bcsub($amount,$reserved,2),'completed_orders'=>(int)$row['completed_orders'],'completion_rate'=>(string)$row['completion_rate'],'positive_rate'=>(string)$row['positive_rate'],'review_reason'=>(string)$row['review_reason']];
    }

    public function applyMerchant(array $data): array
    {
        if (!$this->paymentMethods()) throw new \RuntimeException('请先绑定至少一种实名收款方式');
        $requestId=trim((string)($data['request_id']??''));if(!preg_match('/^[A-Za-z0-9_-]{8,64}$/',$requestId))throw new \InvalidArgumentException('request_id不合法');
        Db::startTrans();try{
            $user=Db::name('user')->where('appid',$this->appid)->where('id',$this->uid())->lock(true)->find();if(!$user)throw new \RuntimeException('用户不存在');
            $row=Db::name('otc_merchant')->where('appid',$this->appid)->where('user_id',$this->uid())->lock(true)->find();
            if($row&&(string)($row['apply_request_id']??'')===$requestId){Db::commit();return $this->merchant();}
            if($row&&in_array((int)$row['status'],[0,1,3,4],true))throw new \RuntimeException('当前状态不允许重复申请');
            $cfg=$this->configRow();$required=$this->decimal($cfg['merchant_deposit']??1000,2);$available=bcsub($this->decimal($user['money']??0,2),$this->decimal($user['wallet_frozen_money']??0,2),2);
            if(bccomp($available,$required,2)<0)throw new \RuntimeException('钱包可用余额不足，无法申请商家');
            $now=date('Y-m-d H:i:s');$merchantId=0;$before=$row?$this->decimal($row['deposit_amount']??0,2):'0.00';
            Db::name('user')->where('appid',$this->appid)->where('id',$this->uid())->update(['money'=>bcsub($this->decimal($user['money'],2),$required,2)]);
            $billId=(int)Db::name('transaction_statement')->insertGetId(['appid'=>$this->appid,'userid'=>$this->uid(),'transaction_type'=>12,'transaction_date'=>$now,'transaction_amount'=>'-'.$required,'remark'=>'OTC商家申请保证金冻结','type'=>0,'frozen'=>1]);
            $values=['apply_request_id'=>$requestId,'status'=>0,'deposit_required'=>$required,'deposit_amount'=>$required,'deposit_frozen'=>$required,'deposit_ad_reserved'=>'0.00','review_reason'=>mb_substr(trim((string)($data['remark']??'')),0,255),'version'=>Db::raw('version+1'),'update_time'=>$now];
            if($row){$merchantId=(int)$row['id'];Db::name('otc_merchant')->where('id',$merchantId)->update($values);}else{$merchantId=(int)Db::name('otc_merchant')->insertGetId(['appid'=>$this->appid,'user_id'=>$this->uid(),'merchant_no'=>$this->number('M'),'apply_request_id'=>$requestId,'status'=>0,'level'=>1,'deposit_required'=>$required,'deposit_amount'=>$required,'deposit_frozen'=>$required,'deposit_ad_reserved'=>'0.00','completed_orders'=>0,'completion_rate'=>'0.00','positive_rate'=>'0.00','average_release_seconds'=>0,'review_reason'=>mb_substr(trim((string)($data['remark']??'')),0,255),'version'=>1,'create_time'=>$now,'update_time'=>$now]);}
            Db::name('otc_merchant_deposit_log')->insert(['appid'=>$this->appid,'merchant_id'=>$merchantId,'request_id'=>$requestId,'action'=>'merchant_apply_hold','amount'=>$required,'before_amount'=>$before,'after_amount'=>$required,'wallet_bill_id'=>$billId,'operator_type'=>'user','operator_id'=>$this->uid(),'reason'=>'商家申请冻结保证金','create_time'=>$now]);
            Db::commit();return $this->merchant();
        }catch(\Throwable $e){Db::rollback();$existing=Db::name('otc_merchant')->where('appid',$this->appid)->where('apply_request_id',$requestId)->find();if($existing)return $this->merchant();throw $e;}
    }

    public function payDeposit(string $requestId): array
    {
        if (!preg_match('/^[A-Za-z0-9_-]{8,64}$/', $requestId)) throw new \InvalidArgumentException('request_id不合法');
        Db::startTrans();
        try {
            $merchant=Db::name('otc_merchant')->where('appid',$this->appid)->where('user_id',$this->uid())->lock(true)->find();
            if(!$merchant)throw new \RuntimeException('请先提交商家认证');
            $old=Db::name('otc_merchant_deposit_log')->where('appid',$this->appid)->where('merchant_id',(int)$merchant['id'])->where('request_id',$requestId)->find();
            if($old){Db::commit();return $this->merchant();}
            $required=$this->decimal($merchant['deposit_required'],2);$paid=$this->decimal($merchant['deposit_amount'],2);$amount=bcsub($required,$paid,2);
            if(bccomp($amount,'0.00',2)<=0){Db::commit();return $this->merchant();}
            $user=Db::name('user')->where('appid',$this->appid)->where('id',$this->uid())->lock(true)->find();if(!$user)throw new \RuntimeException('用户不存在');
            $available=bcsub($this->decimal($user['money']??0,2),$this->decimal($user['wallet_frozen_money']??0,2),2);if(bccomp($available,$amount,2)<0)throw new \RuntimeException('钱包可用余额不足');
            $now=date('Y-m-d H:i:s');Db::name('user')->where('id',$this->uid())->where('appid',$this->appid)->update(['money'=>bcsub($this->decimal($user['money'],2),$amount,2)]);
            $billId=(int)Db::name('transaction_statement')->insertGetId(['appid'=>$this->appid,'userid'=>$this->uid(),'transaction_type'=>12,'transaction_date'=>$now,'transaction_amount'=>'-'.$amount,'remark'=>'OTC商家保证金','type'=>0,'frozen'=>1]);
            Db::name('otc_merchant')->where('id',(int)$merchant['id'])->update(['deposit_amount'=>bcadd($paid,$amount,2),'deposit_frozen'=>bcadd($this->decimal($merchant['deposit_frozen'],2),$amount,2),'version'=>Db::raw('version+1'),'update_time'=>$now]);
            Db::name('otc_merchant_deposit_log')->insert(['appid'=>$this->appid,'merchant_id'=>(int)$merchant['id'],'request_id'=>$requestId,'action'=>'pay','amount'=>$amount,'before_amount'=>$paid,'after_amount'=>bcadd($paid,$amount,2),'wallet_bill_id'=>$billId,'operator_type'=>'user','operator_id'=>$this->uid(),'reason'=>'商家保证金缴纳','create_time'=>$now]);
            Db::commit();return $this->merchant();
        }catch(\Throwable $e){Db::rollback();throw $e;}
    }

    public function ads(array $data): array
    {
        $side=strtolower(trim((string)($data['side']??'sell')));
        if(!in_array($side,['buy','sell'],true)) throw new \InvalidArgumentException('交易方向错误');
        $q=Db::name('otc_ad')->alias('ad')->join('otc_merchant m','m.id=ad.merchant_id and m.appid=ad.appid and m.status=1')->join('user u','u.id=m.user_id and u.appid=m.appid')->join('otc_asset a','a.id=ad.asset_id and a.appid=ad.appid')->join('otc_network n','n.id=ad.network_id and n.appid=ad.appid')->where('ad.appid',$this->appid)->where('ad.side',$side)->where('ad.status',1);
        if((int)($data['asset_id']??0)>0)$q->where('ad.asset_id',(int)$data['asset_id']);
        if((int)($data['network_id']??0)>0)$q->where('ad.network_id',(int)$data['network_id']);
        $rows=$q->field('ad.*,m.completed_orders,m.completion_rate,m.positive_rate,u.nickname,u.username,u.usertx,a.symbol,n.code network_code')->order($side==='sell'?'ad.price asc':'ad.price desc')->limit(100)->select()->toArray();
        return array_map(fn($row)=>$this->adView($row),$rows);
    }

    public function createAd(array $data): array
    {
        $cfg=$this->configRow();
        $side=strtolower(trim((string)($data['side']??'')));
        if(!in_array($side,['buy','sell'],true))throw new \InvalidArgumentException('广告方向错误');
        $assetId=(int)($data['asset_id']??0);$networkId=(int)($data['network_id']??0);$this->assetNetwork($assetId,$networkId);
        $price=$this->positive($data['price']??'',4,'单价');$min=$this->positive($data['min_fiat']??'',2,'最小限额');$max=$this->positive($data['max_fiat']??'',2,'最大限额');$available=$this->positive($data['available_asset']??'',8,'可交易数量');
        if(bccomp($min,$max,2)>0)throw new \InvalidArgumentException('最小限额不能大于最大限额');
        $methods=['balance'];
        $exposure=bcmul($price,$available,2);$reserved=bcdiv(bcmul($exposure,$this->decimal($cfg['ad_deposit_rate']??5,2),2),'100',2);
        Db::startTrans();try{$merchant=Db::name('otc_merchant')->where('appid',$this->appid)->where('user_id',$this->uid())->lock(true)->find();if(!$merchant||(int)$merchant['status']!==1)throw new \RuntimeException('商家尚未认证通过');
            $active=Db::name('otc_ad')->where('appid',$this->appid)->where('merchant_id',(int)$merchant['id'])->whereIn('status',[0,1])->count();if($active>=(int)($cfg['max_merchant_ads']??10))throw new \RuntimeException('广告数量已达上限');
            $depositAvailable=bcsub($this->decimal($merchant['deposit_amount'],2),$this->decimal($merchant['deposit_ad_reserved']??0,2),2);if(bccomp($depositAvailable,$reserved,2)<0)throw new \RuntimeException('可用保证金不足，无法申请广告上架');
            $merchantUserId=(int)$merchant['user_id'];
            if($side==='sell'){
                DigitalAssetControlService::assertAllowed($this->appid,$merchantUserId,$assetId,'otc');
                $account=$this->assetAccount($merchantUserId,$assetId);
                if(bccomp($available,(string)$account['available_balance'],8)>0)throw new \RuntimeException('广告数量不能超过USDT可用余额');
            }else{
                $merchantUser=Db::name('user')->where('appid',$this->appid)->where('id',$merchantUserId)->lock(true)->find();if(!$merchantUser||(int)($merchantUser['wallet_status']??1)!==1)throw new \RuntimeException('商家平台钱包不可用');
                if(bccomp($exposure,(string)$merchantUser['money'],2)>0)throw new \RuntimeException('广告金额不能超过平台可用余额');
            }
            $now=date('Y-m-d H:i:s');Db::name('otc_merchant')->where('id',(int)$merchant['id'])->update(['deposit_ad_reserved'=>bcadd($this->decimal($merchant['deposit_ad_reserved']??0,2),$reserved,2),'version'=>Db::raw('version+1'),'update_time'=>$now]);
            $escrow=$side==='sell'?$available:$exposure;$id=(int)Db::name('otc_ad')->insertGetId(['appid'=>$this->appid,'merchant_id'=>(int)$merchant['id'],'side'=>$side,'asset_id'=>$assetId,'network_id'=>$networkId,'fiat_currency'=>'CNY','price'=>$price,'min_fiat'=>$min,'max_fiat'=>$max,'available_asset'=>$available,'deposit_reserved'=>$reserved,'asset_hold_id'=>0,'fiat_hold_id'=>0,'escrow_remaining'=>$escrow,'payment_methods'=>implode(',',$methods),'terms'=>mb_substr(trim((string)($data['terms']??'')),0,500),'status'=>0,'version'=>1,'create_time'=>$now,'update_time'=>$now]);$ad=Db::name('otc_ad')->where('id',$id)->lock(true)->find();if(!$ad)throw new \RuntimeException('广告创建失败');$holdId=$side==='sell'?OtcAdEscrowService::createSell($ad,$merchantUserId):OtcAdEscrowService::createBuy($ad,$merchantUserId);$holdField=$side==='sell'?'asset_hold_id':'fiat_hold_id';Db::name('otc_ad')->where('id',$id)->update([$holdField=>$holdId]);Db::commit();return $this->adView(Db::name('otc_ad')->where('id',$id)->find()?:[]);
        }catch(\Throwable $e){Db::rollback();throw $e;}
    }

    public function createOrder(array $data,string $side): array
    {
        $this->assertEnabled();
        $requestId=trim((string)($data['request_id']??''));
        if($requestId===''||strlen($requestId)>80)throw new \InvalidArgumentException('request_id不能为空');
        $old=Db::name('otc_order')->where('appid',$this->appid)->where('user_id',$this->uid())->where('request_id',$requestId)->find();
        if($old)return $this->orderView($old);
        Db::startTrans();
        try{
            $lockedUser=Db::name('user')->where('appid',$this->appid)->where('id',$this->uid())->lock(true)->find();
            if(!$lockedUser)throw new \RuntimeException('用户不存在');
            $old=Db::name('otc_order')->where('appid',$this->appid)->where('user_id',$this->uid())->where('request_id',$requestId)->find();
            if($old){Db::commit();return $this->orderView($old);}
            $open=Db::name('otc_order')->where('appid',$this->appid)->where('user_id',$this->uid())->whereIn('status',['settling','appealing','manual_review'])->count();
            if($open>=(int)$this->configRow()['max_open_orders'])throw new \RuntimeException('进行中的订单数量已达上限');
            $ad=Db::name('otc_ad')->where('appid',$this->appid)->where('id',(int)($data['ad_id']??0))->lock(true)->find();
            if(!$ad||(int)$ad['status']!==1)throw new \RuntimeException('广告已不可交易');
            if((string)$ad['side']!==($side==='buy'?'sell':'buy'))throw new \RuntimeException('广告方向不匹配');
            $merchant=Db::name('otc_merchant')->where('appid',$this->appid)->where('id',(int)$ad['merchant_id'])->where('status',1)->find();
            if(!$merchant||(int)$merchant['user_id']===$this->uid())throw new \RuntimeException('商家不可交易');
            $fiat=$this->positive($data['fiat_amount']??'',2,'交易金额');
            if(bccomp($fiat,(string)$ad['min_fiat'],2)<0||bccomp($fiat,(string)$ad['max_fiat'],2)>0)throw new \RuntimeException('交易金额超出广告限额');
            $asset=bcdiv($fiat,(string)$ad['price'],8);
            if(bccomp($asset,(string)$ad['available_asset'],8)>0)throw new \RuntimeException('广告库存不足');
            $payment=['id'=>0,'method_type'=>'balance','account_name'=>'平台余额','account_no_masked'=>'平台余额'];
            $address=['id'=>0,'label'=>'平台数字资产账户','address'=>'平台数字资产账户'];
            $now=date('Y-m-d H:i:s');$orderNo=$this->number('O');
            $sellerId=$side==='sell'?$this->uid():(int)$merchant['user_id'];
            $buyerId=$side==='buy'?$this->uid():(int)$merchant['user_id'];
            DigitalAssetControlService::assertAllowed($this->appid,$sellerId,(int)$ad['asset_id'],'otc');
            DigitalAssetControlService::assertAllowed($this->appid,$buyerId,(int)$ad['asset_id'],'otc');
            if((string)$ad['side']==='sell')$this->holdFiat($buyerId,$fiat,$orderNo);else $this->holdAsset($sellerId,(int)$ad['asset_id'],$asset,$orderNo,$requestId);
            $id=(int)Db::name('otc_order')->insertGetId(['appid'=>$this->appid,'order_no'=>$orderNo,'request_id'=>$requestId,'ad_id'=>(int)$ad['id'],'merchant_id'=>(int)$merchant['id'],'user_id'=>$this->uid(),'buyer_id'=>$buyerId,'seller_id'=>$sellerId,'side'=>$side,'asset_id'=>(int)$ad['asset_id'],'network_id'=>(int)$ad['network_id'],'asset_amount'=>$asset,'price'=>$ad['price'],'fiat_amount'=>$fiat,'fiat_currency'=>$ad['fiat_currency'],'payment_method_id'=>0,'address_id'=>0,'address_snapshot'=>json_encode($address,JSON_UNESCAPED_UNICODE),'payment_snapshot'=>json_encode($payment,JSON_UNESCAPED_UNICODE),'status'=>'settling','version'=>1,'paid_time'=>$now,'expire_time'=>$now,'create_time'=>$now,'update_time'=>$now]);
            $adRemaining=bcsub((string)$ad['available_asset'],$asset,8);Db::name('otc_ad')->where('id',(int)$ad['id'])->update(['available_asset'=>$adRemaining,'version'=>Db::raw('version+1'),'update_time'=>$now]);
            $order=Db::name('otc_order')->where('id',$id)->find();if(!$order)throw new \RuntimeException('OTC订单创建失败');
            if((string)$ad['side']==='sell'){OtcAdEscrowService::consumeSell($ad,$asset,$orderNo);$this->creditAsset($buyerId,(int)$ad['asset_id'],$asset,$orderNo);$this->consumeFiat($order);}else{$this->consumeHold($order);$this->creditAsset($buyerId,(int)$ad['asset_id'],$asset,$orderNo);OtcAdEscrowService::consumeBuy($ad,$fiat,$orderNo,$sellerId);}
            $escrowDebit=(string)$ad['side']==='sell'?$asset:$fiat;$escrowScale=(string)$ad['side']==='sell'?8:2;Db::name('otc_ad')->where('id',(int)$ad['id'])->update(['escrow_remaining'=>bcsub((string)$ad['escrow_remaining'],$escrowDebit,$escrowScale)]);
            if(bccomp($adRemaining,'0',8)===0){$lockedMerchant=Db::name('otc_merchant')->where('id',(int)$merchant['id'])->lock(true)->find();$deposit=bcadd((string)($ad['deposit_reserved']??0),'0',2);$merchantReserved=bcsub((string)($lockedMerchant['deposit_ad_reserved']??0),$deposit,2);if(bccomp($merchantReserved,'0',2)<0)$merchantReserved='0.00';Db::name('otc_merchant')->where('id',(int)$merchant['id'])->update(['deposit_ad_reserved'=>$merchantReserved,'version'=>Db::raw('version+1'),'update_time'=>$now]);Db::name('otc_ad')->where('id',(int)$ad['id'])->update(['status'=>3,'deposit_reserved'=>'0.00','version'=>Db::raw('version+1'),'update_time'=>$now]);}
            $affected=Db::name('otc_order')->where('id',$id)->where('status','settling')->where('version',1)->update(['status'=>'completed','completed_time'=>$now,'version'=>Db::raw('version+1'),'update_time'=>$now]);if($affected!==1)throw new \RuntimeException('OTC订单结算状态异常');
            Db::name('otc_order_log')->insert(['appid'=>$this->appid,'order_id'=>$id,'operator_type'=>'system','operator_id'=>0,'from_status'=>'settling','to_status'=>'completed','reason'=>'平台余额与平台USDT即时结算完成','request_id'=>$requestId,'create_time'=>$now]);
            Db::name('otc_merchant')->where('id',(int)$merchant['id'])->update(['completed_orders'=>Db::raw('completed_orders+1'),'version'=>Db::raw('version+1'),'update_time'=>$now]);
            $this->suspendUncoveredAds((int)$merchant['id'],(int)$ad['asset_id']);
            Db::commit();return $this->orderView(Db::name('otc_order')->where('id',$id)->find()?:[]);
        }catch(\Throwable $e){
            Db::rollback();
            $existing=Db::name('otc_order')->where('appid',$this->appid)->where('user_id',$this->uid())->where('request_id',$requestId)->find();
            if($existing)return $this->orderView($existing);
            throw $e;
        }
    }

    public function orders(array $data): array
    {
        $q=Db::name('otc_order')->where('appid',$this->appid)->where(function($x){$x->where('buyer_id',$this->uid())->whereOr('seller_id',$this->uid());});
        if(trim((string)($data['status']??''))!=='')$q->where('status',trim((string)$data['status']));
        return array_map(fn($row)=>$this->orderView($row),$q->order('id desc')->limit(100)->select()->toArray());
    }

    public function order(string $number): array
    {
        $row=Db::name('otc_order')->where('appid',$this->appid)->where('order_no',$number)->where(function($x){$x->where('buyer_id',$this->uid())->whereOr('seller_id',$this->uid());})->find();
        if(!$row)throw new \RuntimeException('订单不存在');return $this->orderView($row);
    }

    public function markPaid(array $data): array
    {
        throw new \RuntimeException('平台余额已在下单时完成托管，无需再次付款');
    }

    public function confirmRelease(array $data): array
    {
        throw new \RuntimeException('平台余额OTC在下单时即时结算，无需确认放币');
    }

    public function cancel(array $data): array
    {
        throw new \RuntimeException('平台余额OTC为即时成交订单，成交后不能取消');
    }

    public function appeal(array $data): array
    {
        $orderNo=trim((string)($data['order_no']??''));$requestId=trim((string)($data['request_id']??''));$description=mb_substr(trim((string)($data['description']??'')),0,1000);
        if($description===''||$requestId==='')throw new \InvalidArgumentException('申诉说明不能为空');
        Db::startTrans();try{$order=$this->lockOrder($orderNo);if(!in_array((string)$order['status'],['paid','releasing'],true))throw new \RuntimeException('当前状态不能申诉');
            $existing=Db::name('otc_dispute')->where('appid',$this->appid)->where('order_id',(int)$order['id'])->whereIn('status',[0,1])->find();
            if(!$existing)Db::name('otc_dispute')->insert(['appid'=>$this->appid,'dispute_no'=>$this->number('D'),'order_id'=>(int)$order['id'],'applicant_id'=>$this->uid(),'reason_type'=>mb_substr(trim((string)($data['reason_type']??'other')),0,32),'description'=>$description,'status'=>0,'result'=>'','result_reason'=>'','admin_id'=>0,'version'=>1,'create_time'=>date('Y-m-d H:i:s'),'update_time'=>date('Y-m-d H:i:s')]);
            Db::name('otc_order')->where('id',(int)$order['id'])->where('version',(int)$order['version'])->update(['status'=>'appealing','version'=>Db::raw('version+1'),'update_time'=>date('Y-m-d H:i:s')]);
            $this->orderLog($order,'appealing',$requestId,$description);Db::commit();return $this->order($orderNo);
        }catch(\Throwable $e){Db::rollback();throw $e;}
    }

    public function review(array $data): array
    {
        $order=$this->lockOrder(trim((string)($data['order_no']??'')),false);if((string)$order['status']!=='completed')throw new \RuntimeException('订单完成后才能评价');
        $score=(int)($data['score']??0);if($score<1||$score>5)throw new \InvalidArgumentException('评分范围为1到5');
        Db::name('otc_order_review')->insert(['appid'=>$this->appid,'order_id'=>(int)$order['id'],'user_id'=>$this->uid(),'merchant_id'=>(int)$order['merchant_id'],'score'=>$score,'content'=>mb_substr(trim((string)($data['content']??'')),0,500),'create_time'=>date('Y-m-d H:i:s')]);
        return ['success'=>true];
    }

    public static function expireOrders(int $appid,int $limit=200): int
    {
        $rows=Db::name('otc_order')->where('appid',$appid)->where('status','paid')->where('expire_time','<',date('Y-m-d H:i:s'))->limit($limit)->select()->toArray();$done=0;
        foreach($rows as $row){Db::startTrans();try{$current=Db::name('otc_order')->where('id',(int)$row['id'])->where('status','paid')->lock(true)->find();if(!$current){Db::rollback();continue;}
            $hold=Db::name('wallet_asset_hold')->where('appid',$appid)->where('biz_type','otc_order')->where('biz_no',$current['order_no'])->where('status',1)->lock(true)->find();
            if($hold){$account=Db::name('wallet_asset_account')->where('id',(int)$hold['account_id'])->lock(true)->find();Db::name('wallet_asset_account')->where('id',(int)$account['id'])->update(['available_balance'=>bcadd((string)$account['available_balance'],(string)$hold['amount'],8),'frozen_balance'=>bcsub((string)$account['frozen_balance'],(string)$hold['amount'],8),'version'=>Db::raw('version+1'),'update_time'=>date('Y-m-d H:i:s')]);Db::name('wallet_asset_hold')->where('id',(int)$hold['id'])->update(['status'=>2,'update_time'=>date('Y-m-d H:i:s')]);}
            $fiat=Db::name('otc_fiat_hold')->where(['appid'=>$appid,'order_no'=>$current['order_no'],'status'=>1])->lock(true)->find();if($fiat){$buyer=Db::name('user')->where(['appid'=>$appid,'id'=>$fiat['user_id']])->lock(true)->find();Db::name('user')->where(['appid'=>$appid,'id'=>$fiat['user_id']])->update(['money'=>bcadd((string)$buyer['money'],(string)$fiat['amount'],2)]);Db::name('otc_fiat_hold')->where('id',$fiat['id'])->update(['status'=>2,'update_time'=>date('Y-m-d H:i:s')]);}
            Db::name('otc_ad')->where('id',(int)$current['ad_id'])->update(['available_asset'=>Db::raw('available_asset+'.(string)$current['asset_amount']),'version'=>Db::raw('version+1'),'update_time'=>date('Y-m-d H:i:s')]);Db::name('otc_order')->where('id',(int)$current['id'])->update(['status'=>'expired','version'=>Db::raw('version+1'),'update_time'=>date('Y-m-d H:i:s')]);Db::commit();$done++;
        }catch(\Throwable $e){Db::rollback();}}
        return $done;
    }

    private function transition(array $data,string $from,string $to,callable $before):array
    {
        $orderNo=trim((string)($data['order_no']??''));$requestId=trim((string)($data['request_id']??''));$version=(int)($data['version']??0);
        if($orderNo===''||$requestId===''||$version<=0)throw new \InvalidArgumentException('订单版本或幂等参数不完整');
        Db::startTrans();try{$order=$this->lockOrder($orderNo);if((string)$order['status']===$to){Db::commit();return $this->order($orderNo);}if((string)$order['status']!==$from||(int)$order['version']!==$version)throw new \RuntimeException('订单状态已变化，请刷新后重试');
            $extra=$before($order);$now=date('Y-m-d H:i:s');$affected=Db::name('otc_order')->where('id',(int)$order['id'])->where('version',$version)->update($extra+['status'=>$to,'version'=>Db::raw('version+1'),'update_time'=>$now]);if($affected!==1)throw new \RuntimeException('订单状态更新冲突');
            $this->orderLog($order,$to,$requestId,'');Db::commit();return $this->order($orderNo);
        }catch(\Throwable $e){Db::rollback();throw $e;}
    }

    private function lockOrder(string $orderNo,bool $participant=true):array
    {
        $q=Db::name('otc_order')->where('appid',$this->appid)->where('order_no',$orderNo);if($participant)$q->where(function($x){$x->where('buyer_id',$this->uid())->whereOr('seller_id',$this->uid());});$row=$q->lock(true)->find();if(!$row)throw new \RuntimeException('订单不存在');return $row;
    }

    private function assetAccount(int $userId,int $assetId,bool $lock=true):array
    {
        $q=Db::name('wallet_asset_account')->where('appid',$this->appid)->where('user_id',$userId)->where('asset_id',$assetId);if($lock)$q->lock(true);$row=$q->find();
        if(!$row){$now=date('Y-m-d H:i:s');try{Db::name('wallet_asset_account')->insert(['appid'=>$this->appid,'user_id'=>$userId,'asset_id'=>$assetId,'available_balance'=>'0.00000000','frozen_balance'=>'0.00000000','total_in'=>'0.00000000','total_out'=>'0.00000000','version'=>1,'create_time'=>$now,'update_time'=>$now]);}catch(\Throwable){}$row=Db::name('wallet_asset_account')->where('appid',$this->appid)->where('user_id',$userId)->where('asset_id',$assetId)->lock(true)->find();}
        if(!$row)throw new \RuntimeException('数字资产账户创建失败');return $row;
    }

    private function holdAsset(int $userId,int $assetId,string $amount,string $orderNo,string $requestId):void
    {
        DigitalAssetControlService::createHold($this->appid,$userId,$assetId,$amount,'otc_order',$orderNo,'OTC订单资产托管','otc-hold-'.$requestId,'system',0);
    }

    private function holdFiat(int $userId,string $amount,string $orderNo):void
    {
        $user=Db::name('user')->where(['appid'=>$this->appid,'id'=>$userId])->lock(true)->find();if(!$user||(int)$user['wallet_status']!==1)throw new \RuntimeException('买方钱包不可用');$available=bcsub((string)$user['money'],(string)$user['wallet_frozen_money'],2);if(bccomp($available,$amount,2)<0)throw new \RuntimeException('平台余额不足');$now=date('Y-m-d H:i:s');Db::name('user')->where(['appid'=>$this->appid,'id'=>$userId])->update(['money'=>bcsub((string)$user['money'],$amount,2)]);Db::name('otc_fiat_hold')->insert(['appid'=>$this->appid,'hold_no'=>$this->number('FH'),'order_no'=>$orderNo,'user_id'=>$userId,'amount'=>$amount,'status'=>1,'create_time'=>$now,'update_time'=>$now]);Db::name('transaction_statement')->insert(['appid'=>$this->appid,'userid'=>$userId,'transaction_type'=>13,'transaction_date'=>$now,'transaction_amount'=>'-'.$amount,'remark'=>'OTC订单平台余额托管 '.$orderNo,'type'=>0,'frozen'=>1]);
    }

    private function releaseFiat(array $order):void
    {
        $hold=Db::name('otc_fiat_hold')->where(['appid'=>$this->appid,'order_no'=>$order['order_no'],'status'=>1])->lock(true)->find();if(!$hold)return;$user=Db::name('user')->where(['appid'=>$this->appid,'id'=>$hold['user_id']])->lock(true)->find();$now=date('Y-m-d H:i:s');Db::name('user')->where(['appid'=>$this->appid,'id'=>$hold['user_id']])->update(['money'=>bcadd((string)$user['money'],(string)$hold['amount'],2)]);Db::name('otc_fiat_hold')->where('id',$hold['id'])->update(['status'=>2,'update_time'=>$now]);Db::name('transaction_statement')->insert(['appid'=>$this->appid,'userid'=>$hold['user_id'],'transaction_type'=>13,'transaction_date'=>$now,'transaction_amount'=>(string)$hold['amount'],'remark'=>'OTC订单取消退回 '.$order['order_no'],'type'=>0,'frozen'=>0]);
    }

    private function consumeFiat(array $order):void
    {
        $hold=Db::name('otc_fiat_hold')->where(['appid'=>$this->appid,'order_no'=>$order['order_no'],'status'=>1])->lock(true)->find();if(!$hold)throw new \RuntimeException('平台余额托管记录不存在');$seller=Db::name('user')->where(['appid'=>$this->appid,'id'=>$order['seller_id']])->lock(true)->find();if(!$seller||(int)$seller['wallet_status']!==1)throw new \RuntimeException('卖方钱包不可用');$now=date('Y-m-d H:i:s');Db::name('user')->where(['appid'=>$this->appid,'id'=>$order['seller_id']])->update(['money'=>bcadd((string)$seller['money'],(string)$hold['amount'],2)]);Db::name('otc_fiat_hold')->where('id',$hold['id'])->update(['status'=>3,'update_time'=>$now]);Db::name('transaction_statement')->insert(['appid'=>$this->appid,'userid'=>$order['seller_id'],'transaction_type'=>13,'transaction_date'=>$now,'transaction_amount'=>(string)$hold['amount'],'remark'=>'OTC卖币到账 '.$order['order_no'],'type'=>0,'frozen'=>0]);
    }

    private function releaseHold(array $order):void
    {
        $hold=Db::name('wallet_asset_hold')->where('appid',$this->appid)->where('biz_type','otc_order')->where('biz_no',$order['order_no'])->whereIn('status',[1,4])->lock(true)->find();if(!$hold)return;
        DigitalAssetControlService::releaseHold($this->appid,(int)$hold['id'],(string)$hold['remaining_amount'],'OTC订单取消解冻','otc-release-'.$order['order_no'],'system',0);
    }

    private function consumeHold(array $order):void
    {
        $hold=Db::name('wallet_asset_hold')->where('appid',$this->appid)->where('biz_type','otc_order')->where('biz_no',$order['order_no'])->whereIn('status',[1,4])->lock(true)->find();if(!$hold)throw new \RuntimeException('订单托管资产不存在');
        DigitalAssetControlService::consumeHold($this->appid,(int)$hold['id'],'otc-consume-'.$order['order_no'],'OTC订单完成扣除');
    }

    private function creditAsset(int $userId,int $assetId,string $amount,string $orderNo):void
    {
        $account=$this->assetAccount($userId,$assetId);$after=bcadd((string)$account['available_balance'],$amount,8);$now=date('Y-m-d H:i:s');Db::name('wallet_asset_account')->where('id',(int)$account['id'])->update(['available_balance'=>$after,'total_in'=>bcadd((string)$account['total_in'],$amount,8),'version'=>Db::raw('version+1'),'update_time'=>$now]);
        $this->assetLedger($account,$userId,$assetId,'otc_buy',$orderNo,$amount,'buy-'.$orderNo,(string)$account['available_balance'],$after,(string)$account['frozen_balance'],(string)$account['frozen_balance']);
    }

    private function assetLedger(array $account,int $userId,int $assetId,string $scene,string $bizNo,string $amount,string $request,string $beforeA,string $afterA,string $beforeF,string $afterF):void
    {Db::name('wallet_asset_ledger')->insert(['appid'=>$this->appid,'ledger_no'=>$this->number('L'),'request_id'=>$request,'user_id'=>$userId,'asset_id'=>$assetId,'direction'=>in_array($scene,['otc_buy','release_hold'],true)?'in':'out','scene'=>$scene,'biz_no'=>$bizNo,'amount'=>$amount,'before_available'=>$beforeA,'after_available'=>$afterA,'before_frozen'=>$beforeF,'after_frozen'=>$afterF,'remark'=>'','create_time'=>date('Y-m-d H:i:s')]);}

    private function restoreAd(array $order):void{Db::name('otc_ad')->where('appid',$this->appid)->where('id',(int)$order['ad_id'])->update(['available_asset'=>Db::raw('available_asset+'.(string)$order['asset_amount']),'version'=>Db::raw('version+1'),'update_time'=>date('Y-m-d H:i:s')]);}
    private function suspendUncoveredAds(int $merchantId,int $assetId):void
    {
        $merchant=Db::name('otc_merchant')->where('appid',$this->appid)->where('id',$merchantId)->find();if(!$merchant)return;$userId=(int)$merchant['user_id'];$assetAccount=$this->assetAccount($userId,$assetId,false);$assetAvailable=(string)$assetAccount['available_balance'];$sellRows=Db::name('otc_ad')->where('appid',$this->appid)->where('merchant_id',$merchantId)->where('side','sell')->where('asset_id',$assetId)->where('status',1)->order('id')->select()->toArray();$used='0.00000000';foreach($sellRows as $row){$next=bcadd($used,(string)$row['available_asset'],8);if(bccomp($next,$assetAvailable,8)>0)Db::name('otc_ad')->where('id',(int)$row['id'])->update(['status'=>3,'version'=>Db::raw('version+1'),'update_time'=>date('Y-m-d H:i:s')]);else $used=$next;}
        $user=Db::name('user')->where('appid',$this->appid)->where('id',$userId)->find();if(!$user)return;$fiatAvailable=bcsub((string)$user['money'],(string)($user['wallet_frozen_money']??0),2);$buyRows=Db::name('otc_ad')->where('appid',$this->appid)->where('merchant_id',$merchantId)->where('side','buy')->where('status',1)->order('id')->select()->toArray();$fiatUsed='0.00';foreach($buyRows as $row){$exposure=bcmul((string)$row['price'],(string)$row['available_asset'],2);$next=bcadd($fiatUsed,$exposure,2);if(bccomp($next,$fiatAvailable,2)>0)Db::name('otc_ad')->where('id',(int)$row['id'])->update(['status'=>3,'version'=>Db::raw('version+1'),'update_time'=>date('Y-m-d H:i:s')]);else $fiatUsed=$next;}
    }
    private function orderLog(array $order,string $to,string $request,string $reason):void{Db::name('otc_order_log')->insert(['appid'=>$this->appid,'order_id'=>(int)$order['id'],'operator_type'=>'user','operator_id'=>$this->uid(),'from_status'=>(string)$order['status'],'to_status'=>$to,'reason'=>$reason,'request_id'=>$request,'create_time'=>date('Y-m-d H:i:s')]);}
    private function configRow():array{return Db::name('otc_config')->where('appid',$this->appid)->find()?:['enabled'=>0,'merchant_deposit'=>'1000.00','payment_timeout_minutes'=>15,'max_open_orders'=>5];}
    private function assertEnabled():void{if((int)$this->configRow()['enabled']!==1)throw new \RuntimeException('OTC交易暂未开放');}
    private function uid():int{return (int)$this->user['id'];}
    private function assetNetwork(int $asset,int $network):array{$row=Db::name('otc_asset_network')->alias('x')->join('otc_asset a','a.id=x.asset_id and a.appid=x.appid and a.status=1')->join('otc_network n','n.id=x.network_id and n.appid=x.appid and n.status=1')->where('x.appid',$this->appid)->where('x.asset_id',$asset)->where('x.network_id',$network)->where('x.status',1)->field('x.*,n.address_pattern')->find();if(!$row)throw new \InvalidArgumentException('资产或网络不可用');return $row;}
    private function paymentView(array $row):array{$plain=$this->unseal((string)($row['account_no_cipher']??''));return ['id'=>(int)($row['id']??0),'method_type'=>(string)($row['method_type']??''),'account_name'=>(string)($row['account_name']??''),'account_no_masked'=>$this->mask($plain),'bank_name'=>(string)($row['bank_name']??''),'qr_url'=>(string)($row['qr_url']??'')];}
    private function requireMerchant():array{$row=Db::name('otc_merchant')->where('appid',$this->appid)->where('user_id',$this->uid())->find();if(!$row||(int)$row['status']!==1)throw new \RuntimeException('商家尚未认证通过');if(bccomp((string)$row['deposit_amount'],(string)$row['deposit_required'],2)<0)throw new \RuntimeException('商家保证金不足');return $row;}
    private function adView(array $r):array{return ['id'=>(int)($r['id']??0),'side'=>(string)($r['side']??''),'asset_id'=>(int)($r['asset_id']??0),'network_id'=>(int)($r['network_id']??0),'symbol'=>(string)($r['symbol']??''),'network_code'=>(string)($r['network_code']??''),'price'=>(string)($r['price']??'0'),'min_fiat'=>$this->decimal($r['min_fiat']??0,2),'max_fiat'=>$this->decimal($r['max_fiat']??0,2),'available_asset'=>$this->decimal($r['available_asset']??0,8),'payment_methods'=>array_values(array_filter(explode(',',(string)($r['payment_methods']??'')))),'terms'=>(string)($r['terms']??''),'status'=>(int)($r['status']??0),'merchant'=>['id'=>(int)($r['merchant_id']??0),'name'=>(string)($r['nickname']??$r['username']??''),'avatar'=>(string)($r['usertx']??''),'completed_orders'=>(int)($r['completed_orders']??0),'completion_rate'=>(string)($r['completion_rate']??'0.00'),'positive_rate'=>(string)($r['positive_rate']??'0.00')]];}
    private function orderPayment(int $id,string $side,int $merchantUid):array{$owner=$side==='sell'?$this->uid():$merchantUid;if($id<=0)throw new \InvalidArgumentException('请选择收付款方式');$row=Db::name('otc_payment_method')->where('appid',$this->appid)->where('id',$id)->where('user_id',$owner)->where('status',1)->find();if(!$row)throw new \RuntimeException('收付款方式不可用');return $this->paymentView($row);}
    private function orderAddress(int $id,string $side,int $asset,int $network,int $merchantUid):array{$owner=$side==='buy'?$this->uid():$merchantUid;if($id<=0)throw new \InvalidArgumentException('请选择收币地址');$row=Db::name('otc_user_address')->where('appid',$this->appid)->where('id',$id)->where('user_id',$owner)->where('asset_id',$asset)->where('network_id',$network)->where('status',1)->find();if(!$row)throw new \RuntimeException('收币地址不可用');return ['id'=>(int)$row['id'],'label'=>$row['label'],'address'=>$row['address']];}
    private function orderView(array $r):array{$names=['awaiting_payment'=>'待托管','paid'=>'平台托管待放币','releasing'=>'放币中','completed'=>'已完成','cancelled'=>'已取消','expired'=>'已过期','appealing'=>'申诉中'];return ['id'=>(int)$r['id'],'order_no'=>$r['order_no'],'side'=>$r['side'],'asset_id'=>(int)$r['asset_id'],'network_id'=>(int)$r['network_id'],'asset_amount'=>$this->decimal($r['asset_amount'],8),'price'=>(string)$r['price'],'fiat_amount'=>$this->decimal($r['fiat_amount'],2),'fiat_currency'=>$r['fiat_currency'],'buyer_id'=>(int)$r['buyer_id'],'seller_id'=>(int)$r['seller_id'],'status'=>$r['status'],'status_name'=>$names[$r['status']]??'处理中','version'=>(int)$r['version'],'expire_time'=>$r['expire_time'],'create_time'=>$r['create_time'],'payment'=>json_decode((string)($r['payment_snapshot']??''),true)?:[],'address'=>json_decode((string)($r['address_snapshot']??''),true)?:[]];}
    private function positive(mixed $v,int $scale,string $label):string{$t=trim((string)$v);if(!preg_match('/^\d+(\.\d+)?$/',$t))throw new \InvalidArgumentException($label.'格式错误');$n=bcadd($t,'0',$scale);if(bccomp($n,'0',$scale)<=0)throw new \InvalidArgumentException($label.'必须大于0');return $n;}
    private function decimal(mixed $v,int $scale):string{return bcadd((string)$v,'0',$scale);}
    private function number(string $prefix):string{return $prefix.date('ymdHis').strtoupper(bin2hex(random_bytes(5)));}
    private function seal(string $plain):string{$key=hash('sha256',(string)env('APP.CODE','bim-otc'),true);$iv=random_bytes(12);$tag='';$cipher=openssl_encrypt($plain,'aes-256-gcm',$key,OPENSSL_RAW_DATA,$iv,$tag);if($cipher===false)throw new \RuntimeException('敏感信息加密失败');return base64_encode($iv.$tag.$cipher);}
    private function unseal(string $value):string{$raw=base64_decode($value,true);if($raw===false||strlen($raw)<29)return '';$key=hash('sha256',(string)env('APP.CODE','bim-otc'),true);$out=openssl_decrypt(substr($raw,28),'aes-256-gcm',$key,OPENSSL_RAW_DATA,substr($raw,0,12),substr($raw,12,16));return is_string($out)?$out:'';}
    private function mask(string $v):string{$len=mb_strlen($v);if($len<=4)return str_repeat('*',$len);return mb_substr($v,0,2).str_repeat('*',max(4,$len-4)).mb_substr($v,-2);}
}
