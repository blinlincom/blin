<?php

namespace app\admin\controller;

use app\common\support\RandomAvatarService;
use app\common\support\ResponseHelper;

use app\common\support\AppConfig;
use app\common\tool\WukongIM;
use think\facade\Db;
use think\facade\Env;
use think\facade\Request;

class App extends Backend
{

    public $no_need_login = [];
    public $no_need_right = [];

    public function index()
    {
        if (Request::isAjax()) {
            $appname = input("appname");
            $limit = input('limit/d') ?: 10;
            $page = input('page/d') ?: 1;
            $where = " 1 ";
            if ($appname) {
                $where .= " and appname like '%{$appname}%'";
            }
            $rows = Db::name("app")
                ->where($where)
                ->field("appid,appname,appicon,app_switch,create_time")
                ->page($page, $limit)
                ->select()->toArray();
            $onlineCounts = $this->wukongOnlineCounts();
            foreach ($rows as $key => $value) {
                //加入版本号
                $updates_info = Db::name("app_updates")->where("appid", "=", $value["appid"])->order("create_time", "desc")->find();
                $rows[$key]["version"] = $updates_info["update_version"] ?? "";
                //加入用户量
                $usercount = Db::name("user")->where("appid", "=", $value["appid"])->count();
                $rows[$key]["usercount"] = $usercount;
                //加入访问数量
                $countview = Db::name("polymorphic")->where("type = 0 and appid=" . $value["appid"])->count();
                $rows[$key]["countview"] = $countview;
                //加入签到数量
                $signcount = Db::name("user_log")->where("appid", "=", $value["appid"])->count();
                $rows[$key]["signcount"] = $signcount;
                $rows[$key]["online_number"] = $onlineCounts[(int)$value["appid"]] ?? 0;
            }
            $count = Db::name("app")->where($where)->count();
            $result = [
                "rows" => $rows,
                "total" => $count
            ];
            return $this->tableResponse($result);
        }
        return \think\facade\View::fetch();
    }

    protected function wukongOnlineCounts(): array
    {
        try {
            $connz = (new WukongIM())->connections('', 0, 10000);
        } catch (\Exception $e) {
            return [];
        }
        $counts = [];
        $seen = [];
        foreach ((array)($connz["connections"] ?? []) as $connection) {
            $uidInfo = WukongIM::parseUid((string)($connection["uid"] ?? ""));
            if (!$uidInfo) {
                continue;
            }
            $key = $uidInfo["appid"] . ':' . $uidInfo["user_id"];
            if (isset($seen[$key])) {
                continue;
            }
            $seen[$key] = true;
            $counts[$uidInfo["appid"]] = ($counts[$uidInfo["appid"]] ?? 0) + 1;
        }
        return $counts;
    }

    public function add()
    {
        if (request()->isAjax()) {
            $appname = input("post.appname");
            if ($appname == "") {
                return \app\common\support\ResponseHelper::error("请输入APP名称！");
            }
            $add_data = [
                "appname" => $appname,
                "appkey" => getRandChar(32),
                "appicon" => request()->domain() . "/static/images/initial_photo/android.png",
                "application_introduction" => "",
                "developer_contact_info" => "",
                "official_group" => "",
                "create_time" => date("Y-m-d H:i:s", time()),
                "registration_configuration" => '{"registration_switch":"0","registration_closing_prompt":"","registration_code_switch":"0","single_device_registration_limit":"0","money":"0","integral":"0","vip":"0"}',
                "sign_configuration" => '{"sign_switch":"0","money":"10","integral":"10","exp":"10","vip":"10"}',
                "invitation_configuration" => '{"invitation_switch":0,"money":"10","integral":"10","exp":"10","vip":"10","bmoney":"10","bintegral":"10","bexp":"10","bvip":"10"}',
                "login_configuration" => '{"login_switch":"0","login_closing_prompt":"","login_code_switch":"0","new_device_login_switch":"0","remote_login":"1"}',
                "security_configuration" => '{"security_switch":"1","encryption_type":"0","encryption_key":"","encryption_section":"0","data_signature":"0","time_difference_verification":"0"}',
                "announcement_configuration" => '{"title":"","content":""}',
                "forum_configuration" => '{"post_switch":"0","comment_switch":"0","moderator_delete_post":"0","moderator_delete_comment":"0","members_not_need_pay":"0","post_money":"10","post_integral":"0","post_exp":"0","post_vip":"0","comment_money":"10","comment_integral":"0","comment_exp":"0","comment_vip":"0","money_withdrawal_ratio":"100","money_minimum_withdrawal_amount":"100","integral_withdrawal_ratio":"100","integral_minimum_withdrawal_amount":"100","number_text_intercepted":"50","del_post_money":"0","del_post_integral":"0","del_post_exp":"0","del_comment_money":"0","del_comment_integral":"0","del_comment_exp":"0","max_number_post_day":"0","max_number_post_reward":"0","max_number_comment_reward":"0","posting_interval_time":"0","comment_interval_time":"0","transfer_handling_fee":"0","post_tipping_time_limit":"0","comment_tipping_time_limit":"0"}',
                "userinfo_configuration" => '{"nickname":"这个人暂未设置昵称","signature":"这个人暂未设置个性签名","usertx":"' . request()->domain() . '/static/images/initial_photo/user.png","userbg":"' . request()->domain() . '/static/images/initial_photo/userbg.png","update_userinfo_audit":0,"title_medal_priority":"0","random_avatar_enabled":0,"random_avatar_pool":[]}',
                "app_switch" => 0,
                "app_closing_prompt" => "",
                "grade" => "[0 => '名称1',100=>'名称2',200=>'名称3',300=>'名称4',400=>'名称5']",
            ];
            $appid = Db::name("app")->insertGetId($add_data);
            if ($appid) {
                //在更新表插入一条
                $app_update_data = [
                    "appid" => $appid,
                    "update_version" => "1.0",
                    "create_time" => date("Y-m-d H:i:s", time())
                ];
                Db::name("app_updates")->insert($app_update_data);

                $app_download_data = [
                    "appid" => $appid,
                    "template" => 'default',
                    "code" => md5(time() . rand(0, 10000)),
                    "website_template" => '{"name":"默认官网模板","describe":"系统自带模板-所有应用的默认官网模板","file_route":"default","screenshot":"http://moranhtpro.cn/template/default/screenshot.png"}'
                ];
                Db::name("app_download")->insert($app_download_data);
                return \app\common\support\ResponseHelper::success("新增成功！");
            } else {
                return \app\common\support\ResponseHelper::error("新增失败！");
            }
        } else {
            return \think\facade\View::fetch();
        }
    }

    public function edit_switch()
    {
        $appid = input("appid");
        $app_switch = input("app_switch");
        $appid_array = explode(",", $appid);
        foreach ($appid_array as $key => $value) {
            Db::name("app")->where(["appid" => $value])->update(["app_switch" => $app_switch]);
        }
        return \app\common\support\ResponseHelper::success("修改成功！");
    }

    public function del()
    {
        $appid = input("appid");
        $appid_array = explode(",", $appid);
        foreach ($appid_array as $key => $value) {
            $database = Env::get('database.database', 'root');
            $tables = Db::query("SHOW TABLES FROM $database");
            foreach ($tables as $table) {
                $tableName = reset($table);
                // 查询表结构
                $columns = Db::query("DESCRIBE $tableName");
                // 检查是否存在 'appid' 字段
                $hasAppId = false;
                foreach ($columns as $column) {
                    if ($column['Field'] === 'appid') {
                        $hasAppId = true;
                        break;
                    }
                }
                if ($hasAppId) {
                    // 构建查询条件
                    $condition = [
                        'appid' => $value,
                    ];
                    // 执行删除操作
                    Db::table($tableName)->where($condition)->delete();
                }
            }
        }
        return \app\common\support\ResponseHelper::success("删除成功！");
    }

    public function edit()
    {
        if (request()->isAjax()) {
            $data = input();
            //获取注册配置
            $registration_configuration = [
                "registration_switch" => isset($data["registration_switch"]) ? 0 : 1,
                "registration_closing_prompt" => $data["registration_closing_prompt"],
                "registration_code_switch" => $data["registration_code_switch"],
                "single_device_registration_limit" => $data["single_device_registration_limit"],
                "money" => $data["zc_money"],
                "integral" => $data["zc_integral"],
                "vip" => $data["zc_vip"]
            ];
            //获取签到配置
            $sign_configuration = [
                "sign_switch" => isset($data["sign_switch"]) ? 0 : 1,
                "money" => $data["sign_money"],
                "integral" => $data["sign_integral"],
                "exp" => $data["sign_exp"],
                "vip" => $data["sign_vip"]
            ];
            //获取邀请配置
            $invitation_configuration = [
                "invitation_switch" => isset($data["invitation_switch"]) ? 0 : 1,
                "money" => $data["invitation_money"],
                "integral" => $data["invitation_integral"],
                "exp" => $data["invitation_exp"],
                "vip" => $data["invitation_vip"],
                "bmoney" => $data["invitation_bmoney"],
                "bintegral" => $data["invitation_bintegral"],
                "bexp" => $data["invitation_bexp"],
                "bvip" => $data["invitation_bvip"]
            ];
            //获取登录配置
            $login_configuration = [
                "login_switch" => isset($data["login_switch"]) ? 0 : 1,
                "login_closing_prompt" => $data["login_closing_prompt"],
                "login_code_switch" => $data["login_code_switch"],
                "new_device_login_switch" => $data["new_device_login_switch"],
                "remote_login" => $data["remote_login"]
            ];
            //获取论坛配置
            $forum_configuration = [
                "post_switch" => $data["post_switch"],
                "comment_switch" => $data["comment_switch"],
                "moderator_delete_post" => $data["moderator_delete_post"],
                "moderator_delete_comment" => $data["moderator_delete_comment"],
                "members_not_need_pay" => $data["members_not_need_pay"],
                "post_money" => $data["post_money"],
                "post_integral" => $data["post_integral"],
                "post_exp" => $data["post_exp"],
                "post_vip" => $data["post_vip"],
                "comment_money" => $data["comment_money"],
                "comment_integral" => $data["comment_integral"],
                "comment_exp" => $data["comment_exp"],
                "comment_vip" => $data["comment_vip"],
                "money_withdrawal_ratio" => $data["money_withdrawal_ratio"],
                "money_minimum_withdrawal_amount" => $data["money_minimum_withdrawal_amount"],
                "integral_withdrawal_ratio" => $data["integral_withdrawal_ratio"],
                "integral_minimum_withdrawal_amount" => $data["integral_minimum_withdrawal_amount"],
                "number_text_intercepted" => $data["number_text_intercepted"],
                "del_post_money" => $data["del_post_money"],
                "del_post_integral" => $data["del_post_integral"],
                "del_post_exp" => $data["del_post_exp"],
                "del_comment_money" => $data["del_comment_money"],
                "del_comment_integral" => $data["del_comment_integral"],
                "del_comment_exp" => $data["del_comment_exp"],
                "max_number_post_day" => $data["max_number_post_day"],
                "max_number_post_reward" => $data["max_number_post_reward"],
                "max_number_comment_reward" => $data["max_number_comment_reward"],
                "posting_interval_time" => $data["posting_interval_time"],
                "comment_interval_time" => $data["comment_interval_time"],
                "transfer_handling_fee" => $data["transfer_handling_fee"],
                "deduction_method_for_handling_fees" => $data["deduction_method_for_handling_fees"],
                "designated_account" => $data["designated_account"],
                "post_tipping_time_limit" => $data["post_tipping_time_limit"],
                "comment_tipping_time_limit" => $data["comment_tipping_time_limit"],
            ];
            //获取安全配置
            $security_configuration = [
                "security_switch" => isset($data["security_switch"]) ? 0 : 1,
                "encryption_type" => $data["encryption_type"],
                "encryption_key" => $data["aes_key"],
                "encryption_section" => $data["encryption_section"],
                "data_signature" => $data["data_signature"],
                "time_difference_verification" => $data["time_difference_verification"]
            ];
            //获取公告配置
            $announcement_configuration = [
                "title" => $data["announcement_title"],
                "content" => $data["announcement_content"]
            ];
            //获取用户信息配置
            $randomAvatarPool = RandomAvatarService::pool($data["random_avatar_pool"] ?? []);
            $randomAvatarEnabled = isset($data["random_avatar_enabled"]) ? 1 : 0;
            if ($randomAvatarEnabled === 1 && !$randomAvatarPool) {
                return ResponseHelper::error("开启随机头像前请至少配置一张头像");
            }
            $userinfo_configuration = [
                "nickname" => $data["user_nickname"],
                "signature" => $data["user_signature"],
                "usertx" => $data["user_usertx"],
                "userbg" => $data["user_userbg"],
                "update_userinfo_audit" => isset($data["update_userinfo_audit"]) ? 0 : 1,
                "title_medal_priority" => $data["title_medal_priority"],
                "random_avatar_enabled" => $randomAvatarEnabled,
                "random_avatar_pool" => $randomAvatarPool,
            ];
            $update_data = [
                "appname" => $data["appname"],
                "appkey" => $data["appkey"],
                "appicon" => $data["appicon"],
                "application_introduction" => $data["application_introduction"],
                "developer_contact_info" => $data["developer_contact_info"],
                "official_group" => $data["official_group"],
                "app_switch" => isset($data["app_switch"]) ? 0 : 1,
                "app_closing_prompt" => $data["app_closing_prompt"],
                "increase_decrease" => isset($data["increase_decrease"]) ? 1 : 0,
                "grade" => $data["grade"],
                "registration_configuration" => json_encode($registration_configuration, JSON_UNESCAPED_UNICODE),
                "sign_configuration" => json_encode($sign_configuration, JSON_UNESCAPED_UNICODE),
                "invitation_configuration" => json_encode($invitation_configuration, JSON_UNESCAPED_UNICODE),
                "login_configuration" => json_encode($login_configuration, JSON_UNESCAPED_UNICODE),
                "security_configuration" => json_encode($security_configuration, JSON_UNESCAPED_UNICODE),
                "announcement_configuration" => json_encode($announcement_configuration, JSON_UNESCAPED_UNICODE),
                "forum_configuration" => json_encode($forum_configuration, JSON_UNESCAPED_UNICODE),
                "userinfo_configuration" => json_encode($userinfo_configuration, JSON_UNESCAPED_UNICODE),
            ];
            // echo json_encode($update_data);die();
            Db::name("app")->where("appid=" . $data["appid"])->update($update_data);
            //获取更新记录
            $update_configuration = [
                "update_version" => $data["update_version"],
                "update_url" => $data["update_url"],
                "update_content" => $data["update_content"],
            ];
            //查询是否存在该更新版本
            $update_version_info = Db::name("app_updates")->where("appid='{$data['appid']}' and update_version = '{$data['update_version']}'")->find();
            if ($update_version_info) {
                //查询下是有比这个大的版本号 如果有就直接删除大于这个版本号的所有版本
                $update_version_info_list = Db::name("app_updates")->where("appid='{$data['appid']}' and update_version > '{$data['update_version']}'")->select()->toArray();
                if ($update_version_info_list) {
                    foreach ($update_version_info_list as $key => $value) {
                        Db::name("app_updates")->where("id", "=", $value["id"])->delete();
                    }
                }
                Db::name("app_updates")->where("id", "=", $update_version_info["id"])->update($update_configuration);
            } else {
                $update_configuration["create_time"] = date("Y-m-d H:i:s", time());
                $update_configuration["appid"] = $data['appid'];
                Db::name("app_updates")->insert($update_configuration);
            }
            return \app\common\support\ResponseHelper::success("修改成功！");
        } else {
            $appid = input("appid");
            if ($appid == "") {
                return \app\common\support\ResponseHelper::error("服务器错误！");
            }
            $result = Db::name("app")->where("appid={$appid}")->find();
            if ($result) {
                $result["registration_configuration"] = AppConfig::registration($result["registration_configuration"]);
                $result["sign_configuration"] = AppConfig::sign($result["sign_configuration"]);
                $result["invitation_configuration"] = AppConfig::invitation($result["invitation_configuration"]);
                $result["login_configuration"] = AppConfig::login($result["login_configuration"]);
                $result["security_configuration"] = AppConfig::security($result["security_configuration"]);
                $result["forum_configuration"] = AppConfig::forum($result["forum_configuration"]);
                $result["userinfo_configuration"] = AppConfig::userinfo($result["userinfo_configuration"]);
                $result["announcement_configuration"] = AppConfig::announcement($result["announcement_configuration"]);
                //更新记录
                $result["update_configuration"] = Db::name("app_updates")->where("appid", "=", $appid)->order("create_time", "desc")->find() ?: [
                    "update_version" => "",
                    "update_url" => "",
                    "update_content" => "",
                ];

                \think\facade\View::assign("data", $result);
                return \think\facade\View::fetch();
            } else {
                return \app\common\support\ResponseHelper::error("服务器错误！");
            }
        }
    }

    //消息页面
    public function messages()
    {
        return \think\facade\View::fetch();
    }

    public function messages_list()
    {
        $sort = input('?sort') ? input('sort') : 'appid';
        $sortOrder = input("?sortOrder") ? input("sortOrder") : "asc";
        $title = input("title");
        $appid = input("appid");
        $limit = input('limit/d') ?: 10;
        $page = input('page/d') ?: 1;
        $where = " m.type = 0 ";
        if ($title) {
            $where .= " and m.title like '%{$title}%'";
        }
        if ($appid) {
            $where .= " and m.appid = {$appid}";
        }
        $rows = Db::name("message_notification")
            ->alias("m")
            ->join("app a", "m.appid = a.appid")
            ->leftJoin("user u", "m.user_id = u.id")
            ->where($where)
            ->field("m.*,a.appname,u.username")
            ->order("m." . $sort, $sortOrder)
            ->page($page, $limit)
            ->select()->toArray();
        $count = Db::name("message_notification")
            ->alias("m")
            ->join("app a", "m.appid = a.appid")
            ->leftJoin("user u", "m.user_id = u.id")
            ->where($where)
            ->count();
        $result = [
            "rows" => $rows,
            "total" => $count,
        ];
        return $result;
    }

    //消息页面
    public function addmessages()
    {
        $data = [
            "pic_url" => input("post.pic_url"),
            "title" => input("post.title"),
            "content" => input("post.content"),
            "appid" => input("post.appid"),
            "send_to" => 0,
        ];
        if ($data["title"] == "" || $data["content"] == "" || $data["appid"] == "") {
            return \app\common\support\ResponseHelper::error("请填写完整");
        }
        $data["user_id"] = input("post.send_to");
        $data["type"] = 0;
        $data["time"] = date("Y-m-d H:i:s", time());
        Db::name("message_notification")->insert($data);
        return \app\common\support\ResponseHelper::success("添加成功");
    }

    public function deletemsg()
    {
        $id = input("post.id");
        if (empty($id)) {
            return \app\common\support\ResponseHelper::error("服务器错误");
        }
        $id = explode(",", $id);
        foreach ($id as $key => $value) {
            Db::name("message_notification")->where("id", "=", $value)->delete();
        }
        return \app\common\support\ResponseHelper::success("删除成功");
    }

    public function app_exten()
    {
        if (Request::isAjax()) {
            $sort = input('?sort') ? input('sort') : 'appid';
            $sortOrder = input("?sortOrder") ? input("sortOrder") : "asc";
            $name = input("name");
            $note = input("note");
            $appid = input("appid");
            $limit = input('limit/d') ?: 10;
            $page = input('page/d') ?: 1;
            $where = " 1 ";
            if ($name) {
                $where .= " and m.name like '%{$name}%'";
            }
            if ($note) {
                $where .= " and m.note like '%{$note}%'";
            }
            if ($appid) {
                $where .= " and m.appid = {$appid}";
            }
            $rows = Db::name("app_exten")
                ->alias("m")
                ->join("app a", "m.appid = a.appid")
                ->where($where)
                ->field("m.*,a.appname")
                ->order("m." . $sort, $sortOrder)
                ->page($page, $limit)
                ->select()->toArray();
            $count = Db::name("app_exten")
                ->alias("m")
                ->join("app a", "m.appid = a.appid")
                ->where($where)
                ->count();
            $result = [
                "rows" => $rows,
                "total" => $count,
            ];
            return $this->tableResponse($result);
        }
        return \think\facade\View::fetch();
    }

    public function add_exten()
    {
        if (request()->isAjax()) {
            $data = [
                "name" => input("post.name"),
                "data" => input("post.data"),
                "note" => input("post.note"),
                "appid" => input("post.appid"),
            ];
            if ($data["name"] == "" || $data["data"] == "" || $data["note"] == "" || $data["appid"] == "") {
                return \app\common\support\ResponseHelper::error("请填写完整");
            }
            $exten_info = Db::name("app_exten")->where("name = '{$data['name']}' and appid = {$data['appid']}")->find();
            if ($exten_info) {
                return \app\common\support\ResponseHelper::error("该拓展变量名已存在！");
            }
            $data["create_time"] = date("Y-m-d H:i:s", time());
            Db::name("app_exten")->insert($data);
            return \app\common\support\ResponseHelper::success("添加成功");
        }
    }

    public function update_exten()
    {
        if (request()->isAjax()) {
            $data = [
                "name" => input("post.name"),
                "data" => input("post.data"),
                "note" => input("post.note"),
            ];
            $id = input("post.id");
            if ($id == "") {
                return \app\common\support\ResponseHelper::error("系统错误！");
            }
            if ($data["name"] == "" || $data["data"] == "" || $data["note"] == "") {
                return \app\common\support\ResponseHelper::error("请填写完整");
            }
            $exten_info = Db::name("app_exten")->where("id={$id}")->find();
            if (!$exten_info) {
                return \app\common\support\ResponseHelper::error("该拓展变量不存在！");
            }
            $exten_info = Db::name("app_exten")->where([
                ["name", "=", $data["name"]],
                ["appid", "=", $exten_info['appid']],
                ["id", "<>", $id],
            ])->find();
            if ($exten_info) {
                return \app\common\support\ResponseHelper::error("该拓展变量名已存在！");
            }
            Db::name("app_exten")->where("id={$id}")->update($data);
            return \app\common\support\ResponseHelper::success("修改成功！");
        }
    }

    public function delete_exten()
    {
        if (request()->isAjax()) {
            $id = input("post.id");
            if (empty($id)) {
                return \app\common\support\ResponseHelper::error("服务器错误");
            }
            $id = explode(",", $id);
            foreach ($id as $key => $value) {
                Db::name("app_exten")->where("id", "=", $value)->delete();
            }
            return \app\common\support\ResponseHelper::success("删除成功");
        }
    }

    public function download_page()
    {
        $appid = input("appid");
        $where = " 1 ";
        if ($appid) {
            $where .= " and d.appid = {$appid}";
        }
        $list = Db::name("app_download")
            ->alias("d")
            ->join("app a", "d.appid = a.appid")
            ->where($where)
            ->field("d.id,d.appid,a.appname,d.template,d.default_official_website")
            ->paginate(10);
        $page = $list->render();
        $list = $list->items();
        foreach ($list as $key => $value) {
            $file_path = '../public/template/' . $value["template"] . '/config.json';
            if (!file_exists($file_path)) {
                $list[$key]["name"] = "";
                $list[$key]["describe"] = "";
            } else {
                $configContent = file_get_contents($file_path);
                $configContent = json_decode($configContent, true);
                $list[$key]["name"] = isset($configContent["name"]) ? $configContent["name"] : "";
                $list[$key]["describe"] = isset($configContent["describe"]) ? $configContent["describe"] : "";
            }
        }
        $search = ['appid' => $appid];
        \think\facade\View::assign('search', $search);
        \think\facade\View::assign('list', $list);
        \think\facade\View::assign('page', $page);
        return \think\facade\View::fetch();
    }

    public function edit_download_page()
    {
        if (request()->isAjax()) {
            $data = input();
            $file_path = '../public/template/' . $data["template"] . '/config.json';
            if (!file_exists($file_path)) {
                return \app\common\support\ResponseHelper::error("系统错误！");
            }
            $configContent = file_get_contents($file_path);
            $configContent = json_decode($configContent, true);
            $template_array["name"] = $configContent["name"];
            $template_array["describe"] = $configContent["describe"];
            $template_array["file_route"] = $data["template"];
            $template_array["screenshot"] = request()->domain() . '/template/' . $data["template"] . '/screenshot.png';
            $data["website_template"] = json_encode($template_array);
            $id = $data["id"];
            unset($data["id"]);
            if ($data["default_official_website"] == 0) {
                Db::name("app_download")->where("id", ">", 0)->update(["default_official_website" => 1]);
            }
            Db::name("app_download")->where("id={$id}")->update($data);
            return \app\common\support\ResponseHelper::success("修改成功！");
        } else {
            $id = input("id");
            if ($id == "") {
                return \app\common\support\ResponseHelper::error("服务器错误！");
            }
            $result = Db::name("app_download")->where("id={$id}")->find();
            if ($result["img_url"] == "" || $result["img_url"] == null) {
                $result["img_url_array"] = [];
            } else {
                $result["img_url_array"] = explode(",", $result["img_url"]);
            }
            \think\facade\View::assign("download_url", Request::domain() . "/code/" . $result["code"]);
            \think\facade\View::assign("data", $result);
            \think\facade\View::assign("website_template_list", self::get_website_template_list());
            return \think\facade\View::fetch();
        }
    }

    public static function get_website_template_list()
    {
        $Path = '../public/template/'; //定义模版目录
        $except = array('.', '..');  //排除目录其他数组
        $files_list = scandir($Path);
        $template_array = [];
        $k = 0;
        foreach ($files_list as $file) {
            if (!in_array($file, $except)) {
                $file_path = $Path . '/' . $file . '/config.json';
                if (file_exists($file_path)) {
                    $configContent = file_get_contents($file_path);
                    $configContent = json_decode($configContent, true);
                    $template_array[$k]["name"] = $configContent["name"];
                    $template_array[$k]["describe"] = $configContent["describe"];
                    $template_array[$k]["file_route"] = $file;
                    $template_array[$k]["screenshot"] = request()->domain() . '/template/' . $file . '/screenshot.png';
                    $k++;
                }
            }
        }
        return $template_array;
    }
}
