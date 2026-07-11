<?php

declare(strict_types=1);

namespace app\admin\controller;

use app\common\support\ResponseHelper;
use think\facade\Db;
use think\facade\Request;
use think\facade\View;

class Otc extends Backend
{
    public $no_need_login = [];
    public $no_need_right = [];

    public function index()
    {
        if (Request::isAjax()) {
            $limit=input('limit/d')?:20;$page=input('page/d')?:1;
            $q=Db::name('otc_order')->alias('o')->leftJoin('app a','a.appid=o.appid')->leftJoin('user b','b.id=o.buyer_id and b.appid=o.appid')->leftJoin('user s','s.id=o.seller_id and s.appid=o.appid')->field('o.*,a.appname,b.username buyer_username,b.nickname buyer_nickname,s.username seller_username,s.nickname seller_nickname');
            $this->filter($q,['appid'=>'o.appid','status'=>'o.status','order_no'=>'o.order_no']);
            $rows=$q->order('o.id desc')->page($page,$limit)->select()->toArray();
            return $this->tableResponse(['rows'=>$rows,'total'=>$q->count()]);
        }
        return View::fetch();
    }

    public function merchants()
    {
        if(Request::isAjax()){$limit=input('limit/d')?:20;$page=input('page/d')?:1;$q=Db::name('otc_merchant')->alias('m')->leftJoin('app a','a.appid=m.appid')->leftJoin('user u','u.id=m.user_id and u.appid=m.appid')->field('m.*,a.appname,u.username,u.nickname,u.money');$this->filter($q,['appid'=>'m.appid','status'=>'m.status','merchant_no'=>'m.merchant_no']);return $this->tableResponse(['rows'=>$q->order('m.id desc')->page($page,$limit)->select()->toArray(),'total'=>$q->count()]);}
        return View::fetch();
    }

    public function review_merchant()
    {
        $id=input('id/d');$status=input('status/d');$reason=mb_substr(trim((string)input('reason','')),0,255);
        if(!in_array($status,[1,2,3],true)||$reason==='')return ResponseHelper::error('审核状态或原因不能为空');
        Db::startTrans();try{$row=Db::name('otc_merchant')->where('id',$id)->lock(true)->find();if(!$row)throw new \Exception('商家不存在');$before=$row;$now=date('Y-m-d H:i:s');
            if($status===1&&bccomp((string)$row['deposit_amount'],(string)$row['deposit_required'],2)<0)throw new \Exception('保证金不足，不能通过审核');
            if($status===2){$active=Db::name('otc_ad')->where('appid',(int)$row['appid'])->where('merchant_id',$id)->whereIn('status',[0,1])->count();if($active>0)throw new \Exception('存在待审核或上架广告，不能驳回商家');$amount=bcsub((string)$row['deposit_amount'],(string)($row['deposit_ad_reserved']??0),2);if(bccomp($amount,'0.00',2)>0){$user=Db::name('user')->where('appid',(int)$row['appid'])->where('id',(int)$row['user_id'])->lock(true)->find();Db::name('user')->where('id',(int)$row['user_id'])->where('appid',(int)$row['appid'])->update(['money'=>bcadd((string)$user['money'],$amount,2)]);$bill=(int)Db::name('transaction_statement')->insertGetId(['appid'=>(int)$row['appid'],'userid'=>(int)$row['user_id'],'transaction_type'=>12,'transaction_date'=>$now,'transaction_amount'=>$amount,'remark'=>'OTC商家审核驳回退还保证金','type'=>0,'frozen'=>0]);Db::name('otc_merchant_deposit_log')->insert(['appid'=>(int)$row['appid'],'merchant_id'=>$id,'request_id'=>'reject-'.$id.'-'.time(),'action'=>'merchant_rejected_release','amount'=>$amount,'before_amount'=>(string)$row['deposit_amount'],'after_amount'=>'0.00','wallet_bill_id'=>$bill,'operator_type'=>'admin','operator_id'=>(int)($this->admin_info['id']??0),'reason'=>$reason,'create_time'=>$now]);}Db::name('otc_merchant')->where('id',$id)->update(['deposit_amount'=>'0.00','deposit_frozen'=>'0.00','deposit_ad_reserved'=>'0.00']);}
            Db::name('otc_merchant')->where('id',$id)->update(['status'=>$status,'review_reason'=>$reason,'version'=>Db::raw('version+1'),'update_time'=>$now]);$after=Db::name('otc_merchant')->where('id',$id)->find();$this->audit((int)$row['appid'],'merchant_review','merchant',$id,$before,$after,$reason);Db::commit();return ResponseHelper::success('审核完成');}catch(\Throwable $e){Db::rollback();return ResponseHelper::error($e->getMessage());}
    }

    public function ads()
    {
        if(Request::isAjax()){$limit=input('limit/d')?:20;$page=input('page/d')?:1;$q=Db::name('otc_ad')->alias('ad')->leftJoin('app a','a.appid=ad.appid')->leftJoin('otc_merchant m','m.id=ad.merchant_id')->leftJoin('user u','u.id=m.user_id and u.appid=m.appid')->leftJoin('otc_asset x','x.id=ad.asset_id')->leftJoin('otc_network n','n.id=ad.network_id')->field('ad.*,a.appname,m.merchant_no,u.username,u.nickname,x.symbol,n.code network_code');$this->filter($q,['appid'=>'ad.appid','status'=>'ad.status','side'=>'ad.side']);return $this->tableResponse(['rows'=>$q->order('ad.id desc')->page($page,$limit)->select()->toArray(),'total'=>$q->count()]);}return View::fetch();
    }

    public function review_ad()
    {
        $id=input('id/d');$status=input('status/d');$reason=mb_substr(trim((string)input('reason','')),0,255);if(!in_array($status,[1,2,3],true)||$reason==='')return ResponseHelper::error('审核参数不完整');
        Db::startTrans();try{$row=Db::name('otc_ad')->where('id',$id)->lock(true)->find();if(!$row)throw new \Exception('广告不存在');$before=$row;$now=date('Y-m-d H:i:s');if(in_array($status,[2,3],true)&&in_array((int)$row['status'],[0,1],true)&&bccomp((string)($row['deposit_reserved']??0),'0.00',2)>0){$merchant=Db::name('otc_merchant')->where('id',(int)$row['merchant_id'])->lock(true)->find();$next=bcsub((string)($merchant['deposit_ad_reserved']??0),(string)$row['deposit_reserved'],2);if(bccomp($next,'0.00',2)<0)$next='0.00';Db::name('otc_merchant')->where('id',(int)$merchant['id'])->update(['deposit_ad_reserved'=>$next,'version'=>Db::raw('version+1'),'update_time'=>$now]);Db::name('otc_ad')->where('id',$id)->update(['deposit_reserved'=>'0.00']);}Db::name('otc_ad')->where('id',$id)->update(['status'=>$status,'version'=>Db::raw('version+1'),'update_time'=>$now]);$after=Db::name('otc_ad')->where('id',$id)->find();$this->audit((int)$row['appid'],'ad_review','ad',$id,$before,$after,$reason);Db::commit();return ResponseHelper::success('广告状态已更新');}catch(\Throwable $e){Db::rollback();return ResponseHelper::error($e->getMessage());}
    }

    public function config()
    {
        if(Request::isPost()){$appid=input('appid/d');if($appid<=0)return ResponseHelper::error('APPID不能为空');$now=date('Y-m-d H:i:s');$rate=$this->money(input('ad_deposit_rate','5'));if(bccomp($rate,'0.00',2)<0||bccomp($rate,'100.00',2)>0)return ResponseHelper::error('广告保证金比例必须在0到100之间');$values=['enabled'=>input('enabled/d')===1?1:0,'manual_escrow'=>1,'payment_balance_enabled'=>input('payment_balance_enabled/d')===1?1:0,'payment_alipay_enabled'=>input('payment_alipay_enabled/d')===1?1:0,'payment_wechat_enabled'=>input('payment_wechat_enabled/d')===1?1:0,'payment_bank_enabled'=>input('payment_bank_enabled/d')===1?1:0,'merchant_deposit'=>$this->money(input('merchant_deposit','1000')),'ad_deposit_rate'=>$rate,'payment_timeout_minutes'=>max(5,min(120,input('payment_timeout_minutes/d')?:15)),'max_open_orders'=>max(1,min(20,input('max_open_orders/d')?:5)),'max_merchant_ads'=>max(1,min(100,input('max_merchant_ads/d')?:10)),'risk_notice'=>mb_substr(trim((string)input('risk_notice','')),0,500),'update_time'=>$now];if($values['payment_balance_enabled']!==1)return ResponseHelper::error('当前OTC必须开启平台余额结算');$row=Db::name('otc_config')->where('appid',$appid)->find();if($row)Db::name('otc_config')->where('id',(int)$row['id'])->update($values);else Db::name('otc_config')->insert($values+['appid'=>$appid,'create_time'=>$now]);$this->audit($appid,'config_update','config',(int)($row['id']??0),$row?:[],$values,'更新OTC配置');return ResponseHelper::success('配置已保存');}
        return View::fetch();
    }

    private function filter($query,array $fields):void{foreach($fields as $input=>$field){$value=trim((string)input($input,''));if($value!=='')$query->where($field,$input==='order_no'||$input==='merchant_no'?'like':'=',$input==='order_no'||$input==='merchant_no'?"%{$value}%":$value);}}
    private function audit(int $appid,string $action,string $type,int $id,array $before,array $after,string $reason):void{Db::name('otc_admin_audit')->insert(['appid'=>$appid,'admin_id'=>(int)($this->admin_info['id']??0),'action'=>$action,'target_type'=>$type,'target_id'=>$id,'before_json'=>json_encode($before,JSON_UNESCAPED_UNICODE),'after_json'=>json_encode($after,JSON_UNESCAPED_UNICODE),'reason'=>$reason,'ip'=>(string)Request::ip(),'create_time'=>date('Y-m-d H:i:s')]);}
    private function money(mixed $value):string{$text=trim((string)$value);if(!preg_match('/^\d+(\.\d{1,2})?$/',$text))throw new \InvalidArgumentException('金额格式错误');return bcadd($text,'0',2);}
}
