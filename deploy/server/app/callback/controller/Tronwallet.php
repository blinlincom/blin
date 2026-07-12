<?php

declare(strict_types=1);

namespace app\callback\controller;

use app\BaseController;
use app\common\support\ChainDepositService;
use app\common\support\ChainTaskService;
use app\common\support\GasFreeTaskService;
use think\facade\Env;
use think\facade\Request;

final class Tronwallet extends BaseController
{
    public function addresses(){return $this->handle(function(array $data){return ['list'=>ChainDepositService::addresses((int)($data['limit']??500),(int)($data['after_id']??0))];});}
    public function deposit(){return $this->handle(fn(array $data)=>ChainDepositService::credit($data));}
    public function task(){return $this->handle(fn(array $data)=>['task'=>ChainTaskService::claim(trim((string)($data['worker']??'')))]);}
    public function task_report(){return $this->handle(fn(array $data)=>ChainTaskService::report($data));}
    public function confirm_task(){return $this->handle(fn(array $data)=>['task'=>ChainTaskService::claimConfirmation(trim((string)($data['worker']??'')))]);}
    public function confirm_report(){return $this->handle(fn(array $data)=>ChainTaskService::reportConfirmation($data));}
    public function gasfree_accounts(){return $this->handle(fn(array $data)=>['list'=>GasFreeTaskService::accounts((int)($data['limit']??100),(int)($data['after_id']??0))]);}
    public function gasfree_sync(){return $this->handle(fn(array $data)=>GasFreeTaskService::sync($data));}
    public function gasfree_task(){return $this->handle(fn(array $data)=>['task'=>GasFreeTaskService::claim(trim((string)($data['worker']??'')))]);}
    public function gasfree_report(){return $this->handle(fn(array $data)=>GasFreeTaskService::report($data));}
    public function gasfree_confirmations(){return $this->handle(fn(array $data)=>['list'=>GasFreeTaskService::confirmations((int)($data['limit']??50))]);}
    public function gasfree_confirm(){return $this->handle(fn(array $data)=>GasFreeTaskService::confirm($data));}
    private function handle(callable $callback){$raw=file_get_contents('php://input')?:'';$timestamp=(string)Request::header('x-bim-timestamp','');$signature=strtolower(trim((string)Request::header('x-bim-signature','')));$secret=(string)Env::get('tron.internal_secret','');if($secret===''||!ctype_digit($timestamp)||abs(time()-(int)$timestamp)>30||!hash_equals(hash_hmac('sha256',$timestamp."\n".$raw,$secret),$signature))return json(['code'=>0,'msg'=>'unauthorized'],401);$data=json_decode($raw,true);if(!is_array($data))return json(['code'=>0,'msg'=>'bad request'],400);try{return json(['code'=>1,'msg'=>'success','data'=>$callback($data)]);}catch(\Throwable $e){return json(['code'=>0,'msg'=>$e->getMessage()],422);}}
}
