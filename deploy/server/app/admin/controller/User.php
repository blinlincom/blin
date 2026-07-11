<?php

namespace app\admin\controller;

use app\common\support\RandomAvatarService;

use app\common\tool\IpLocation;
use app\common\tool\WukongIM;
use app\common\support\ResponseHelper;
use think\facade\Db;
use think\facade\Request;

class User extends Backend
{

    public $no_need_login = [];
    public $no_need_right = ['obtain_user_action_logs'];

    public function index()
    {
        if (Request::isAjax()) {
            $sort = input('?sort') ? input('sort') : 'id';
            $sortOrder = input("?sortOrder") ? input("sortOrder") : "asc";
            $username = input("username");
            $nickname = input("nickname");
            $user_id = input("user_id");
            $appid = input("appid");
            $limit = input('limit/d') ?: 10;
            $page = input('page/d') ?: 1;
            $where = " 1 ";
            if (input("user_id") != "") {
                $where .= " and u.id = {$user_id}";
            }
            if (input("username") != "") {
                $where .= " and u.username like '%" . $username . "%'";
            }
            if (input("nickname") != "") {
                $where .= " and u.nickname like '%" . $nickname . "%'";
            }
            if (input("appid") != "") {
                $where .= " and u.appid = {$appid}";
            }
            $rows = Db::name("user")
                ->alias("u")
                ->join("app a", "u.appid = a.appid")
                ->where($where)
                ->field("u.*,a.appname")
                ->order("u." . $sort, $sortOrder)
                ->page($page, $limit)
                ->select()->toArray();
            $rows_list = [];
            $ip = new IpLocation();
            foreach ($rows as $key => $value) {
                $rows_list[$key]["id"] = $value["id"];
                $rows_list[$key]["username"] = $value["username"];
                $rows_list[$key]["usertx"] = $value["usertx"];
                $rows_list[$key]["nickname"] = $value["nickname"];
                $rows_list[$key]["appname"] = $value["appname"];
                $rows_list[$key]["create_time"] = $value["create_time"];
                $rows_list[$key]["ip"] = $value["ip"] == "" ? "" : $value["ip"] . "(" . $ip->getDetail($value["ip"])["dataA"] . ")";
                $rows_list[$key]["viptime"] = $value["viptime"] > time() ? 0 : 1;
                $rows_list[$key]["reasons"] = $value["reasons"];
                $rows_list[$key]["chat_mute"] = $this->activeChatMuteLabel((int)$value["appid"], (int)$value["id"]);
            }
            $count = Db::name("user")
                ->alias("u")
                ->join("app a", "u.appid = a.appid")
                ->where($where)
                ->count();
            $result = [
                "rows" => $rows_list,
                "total" => $count,
            ];
            return $this->tableResponse($result);
        }
        return \think\facade\View::fetch();
    }

    //新增用户
    public function add()
    {
        if (Request::isAjax()) {
            $data = input("post.");
            if ($data["username"] == "" || $data["password"] == "" || $data["appid"] == "") {
                return \app\common\support\ResponseHelper::error("请输入完整！");
            }
            $salt = getRandChar(6);
            $password = md5($data["password"] . $salt);
            $app_info = Db::name("app")->where("appid", "=", $data["appid"])->find();
            if (!$app_info) {
                return \app\common\support\ResponseHelper::error("该APP不存在！");
            }
            $user_info = Db::name("user")->where([
                ["username", "=", $data["username"]],
                ["appid", "=", $data["appid"]]
            ])->find();
            if ($user_info) {
                return \app\common\support\ResponseHelper::error("该用户名已存在！");
            }
            $userinfo_configuration = json_decode($app_info["userinfo_configuration"], true);
            $registration_configuration = json_decode($app_info["registration_configuration"], true);
            $add_data = [
                "appid" => $data["appid"],
                "username" => $data["username"],
                "password" => $password,
                "salt" => $salt,
                "usertx" => RandomAvatarService::choose($userinfo_configuration),
                "nickname" => $userinfo_configuration['nickname'],
                "money" => (int)$registration_configuration["money"],
                "integral" => (int)$registration_configuration["integral"],
                'viptime' => time() + (int)$registration_configuration["vip"],
                "userbg" => $userinfo_configuration['userbg'],
                "signature" => $userinfo_configuration['signature'],
                "create_time" => date("Y-m-d H:i:s", time()),
                "register_ip" => get_client_ip(),
                "invitecode" => enerate_invitation_code()
            ];
            Db::name("user")->insert($add_data);
            return \app\common\support\ResponseHelper::success("添加成功", '', $add_data);
        }
    }

    //修改用户状态
    public function edit_status()
    {
        $id = explode(",", input('id'));
        $userstate = input("userstate");
        foreach ($id as $key => $value) {
            $updateData["reasons"] = $userstate;
            if ($userstate == 0) {
                $updateData["reasons_ban"] = "";
                $updateData["reasons_time"] = 0;
            } else {
                $updateData["reasons_ban"] = input("reason_content");
                $days = max(0, (int)input("prohibition_time/d"));
                $updateData["reasons_time"] = $days > 0 ? $days * 60 * 60 * 24 + time() : 0;
            }
            Db::name("user")->where("id", "=", $value)->update($updateData);
        }
        return \app\common\support\ResponseHelper::success("修改成功");
    }

    public function muteChat()
    {
        $userId = (int)input('id');
        $scope = trim((string)input('scope', 'all'));
        if (!in_array($scope, ['private', 'group', 'all'], true)) {
            return ResponseHelper::error('禁言范围不合法');
        }
        $user = Db::name('user')->where('id', $userId)->find();
        if (!$user) {
            return ResponseHelper::error('用户不存在');
        }

        $expireSeconds = max(0, (int)input('expire_seconds', 0));
        $now = date('Y-m-d H:i:s');
        $data = [
            'appid' => (int)$user['appid'],
            'user_id' => (int)$user['id'],
            'uid' => WukongIM::uid($user['appid'], $user['id']),
            'scope' => $scope,
            'status' => 1,
            'reason' => mb_substr(trim((string)input('reason', '管理员限制')), 0, 255),
            'admin_id' => $this->adminId(),
            'mute_time' => $now,
            'expire_time' => $expireSeconds > 0 ? date('Y-m-d H:i:s', time() + $expireSeconds) : null,
            'unmute_time' => null,
            'update_time' => $now,
        ];

        $exists = Db::name('chat_user_mute')
            ->where('appid', $user['appid'])
            ->where('user_id', $user['id'])
            ->lock(true)
            ->find();
        if ($exists) {
            Db::name('chat_user_mute')->where('id', $exists['id'])->update($data);
        } else {
            $data['create_time'] = $now;
            Db::name('chat_user_mute')->insert($data);
        }

        return ResponseHelper::success('聊天禁言成功', '', [
            'scope' => $scope,
            'expire_time' => $data['expire_time'],
            'permanent' => $expireSeconds <= 0 ? 1 : 0,
        ]);
    }

    public function unmuteChat()
    {
        $userId = (int)input('id');
        $user = Db::name('user')->where('id', $userId)->find();
        if (!$user) {
            return ResponseHelper::error('用户不存在');
        }
        Db::name('chat_user_mute')
            ->where('appid', $user['appid'])
            ->where('user_id', $user['id'])
            ->where('status', 1)
            ->update([
                'status' => 0,
                'admin_id' => $this->adminId(),
                'unmute_time' => date('Y-m-d H:i:s'),
                'update_time' => date('Y-m-d H:i:s'),
            ]);
        return ResponseHelper::success('解除聊天禁言成功');
    }

    //删除用户
    public function del()
    {
        if (Request::isAjax()) {
            $id = explode(",", input('id'));
            foreach ($id as $key => $value) {
                $user = Db::name("user")->where("id", "=", $value)->find();
                if ($user) {
                    try {
                        (new WukongIM())->deviceQuit(WukongIM::uid($user["appid"], $user["id"]));
                    } catch (\Exception $e) {
                    }
                }
                //删除用户其他信息
                Db::name("user")->where("id", "=", $value)->delete();
                Db::name("comments")->where("userid", "=", $value)->delete();
                Db::name("forum_posts")->where("userid", "=", $value)->delete();
                Db::name("message_notification")->where("user_id = {$value} or send_to = {$value}")->delete();
                Db::name("notes")->where("userid", "=", $value)->delete();
                Db::name("operation_log")->where("uid", "=", $value)->delete();
                Db::name("order_records")->where("userid", "=", $value)->delete();
                Db::name("polymorphic")->where("userid = {$value} and (type = 1 or type = 2 or type = 5)")->delete();
                Db::name("polymorphic")->where("other_id = {$value}")->delete();
                Db::name("post_payment")->where("userid", "=", $value)->delete();
                Db::name("report")->where("uid", "=", $value)->delete();
                Db::name("sign_record")->where("userid", "=", $value)->delete();
                Db::name("transaction_statement")->where("userid", "=", $value)->delete();
                Db::name("user_information_review")->where("userid", "=", $value)->delete();
                Db::name("user_log")->where("userid", "=", $value)->delete();
                Db::name("wukongim_red_packet")->where("sender_id = {$value} or receiver_id = {$value}")->delete();
                Db::name("wukongim_red_packet_receive")->where("sender_id = {$value} or receiver_id = {$value}")->delete();
                Db::name("withdrawal_record")->where("userid", "=", $value)->delete();
            }
            return \app\common\support\ResponseHelper::success("删除成功");
        }
    }

    protected function activeChatMuteLabel(int $appid, int $userId): string
    {
        Db::name('chat_user_mute')
            ->where('appid', $appid)
            ->where('user_id', $userId)
            ->where('status', 1)
            ->whereNotNull('expire_time')
            ->where('expire_time', '<=', date('Y-m-d H:i:s'))
            ->update([
                'status' => 0,
                'unmute_time' => date('Y-m-d H:i:s'),
                'update_time' => date('Y-m-d H:i:s'),
            ]);

        $row = Db::name('chat_user_mute')
            ->where('appid', $appid)
            ->where('user_id', $userId)
            ->where('status', 1)
            ->where(function ($query) {
                $query->whereNull('expire_time')->whereOr('expire_time', '>', date('Y-m-d H:i:s'));
            })
            ->order('id', 'desc')
            ->find();
        if (!$row) {
            return '';
        }
        $map = ['private' => '私聊禁言', 'group' => '群聊禁言', 'all' => '全部禁言'];
        $label = $map[(string)$row['scope']] ?? '聊天禁言';
        return $label . (!empty($row['expire_time']) ? (' 至 ' . $row['expire_time']) : ' 永久');
    }

    protected function adminId(): int
    {
        return (int)($this->admin_info['id'] ?? session('admin.id') ?? 0);
    }

    //修改用户信息
    public function edit()
    {
        if (request()->isAjax()) {
            $data = input();
            if (!isset($data["reasons"])) {
                $data["reasons"] = 0;
                $data["reasons_ban"] = "";
                $data["reasons_time"] = 0;
            } else {
                $data["reasons"] = 1;
                $reasonTime = trim((string)($data["reasons_time"] ?? ""));
                $parsedReasonTime = $reasonTime === "" ? 0 : strtotime($reasonTime);
                $data["reasons_time"] = $parsedReasonTime === false ? 0 : (int)$parsedReasonTime;
            }
            if ($data["password"] != "") {
                $salt = getRandChar(6);
                $data["salt"] = $salt;
                $data["password"] = md5($data["password"] . $salt);
            } else {
                unset($data["password"]);
            }
            $data["viptime"] = strtotime($data["viptime"]);
            $id =  $data["id"];
            unset($data["id"]);
            $is_user_info = Db::name("user")->where("id", $id)->find();
            if (!$is_user_info) {
                return \app\common\support\ResponseHelper::error("系统错误！");
            }
            //验证手机号
            if ($data["mobile"]) {
                $user_info = Db::name("user")->where([
                    ["mobile", "=", $data["mobile"]],
                    ["appid", "=", $is_user_info["appid"]],
                    ["id", "<>", $id],
                ])->find();
                if ($user_info) {
                    return \app\common\support\ResponseHelper::error("该手机号已存在！");
                }
            }
            if ($data["email"]) {
                $user_info = Db::name("user")->where([
                    ["email", "=", $data["email"]],
                    ["appid", "=", $is_user_info["appid"]],
                    ["id", "<>", $id],
                ])->find();
                if ($user_info) {
                    return \app\common\support\ResponseHelper::error("该邮箱已存在！");
                }
            }
            //判断金币 积分 经验 不能小于0
            if ($data["money"] < 0 || $data["integral"] < 0 || $data["exp"] < 0) {
                return \app\common\support\ResponseHelper::error("金币 积分 经验 不能小于0");
            }
            $result = Db::name("user")->where("id", "=", $id)->update($data);
            return \app\common\support\ResponseHelper::success("修改成功");
        } else {
            $id = input("id");
            if ($id == "") {
                return \app\common\support\ResponseHelper::error("服务器错误");
            }
            $result = Db::name("user")->alias("u")->join("app a", "a.appid=u.appid")->where("id={$id}")->find();
            if ($result == null) {
                return \app\common\support\ResponseHelper::error("服务器错误");
            }
            //获取ip地址信息
            $ip = new IpLocation();
            $result["register_ip"] = $result["register_ip"] == "" ? "" : $result["register_ip"] . "(" . $ip->getDetail($result["register_ip"])["dataA"] . ")";
            $uid = WukongIM::uid($result["appid"], $result["id"]);
            $result["online_type"] = 0;
            $result["last_activity_ip"] = "暂无信息";
            $result["last_activity_time"] = "暂无信息";
            try {
                $status = (new WukongIM())->onlineStatus([$uid]);
                if (!empty($status)) {
                    $result["online_type"] = 1;
                }
                $connz = (new WukongIM())->connections($uid, 0, 10);
                foreach ((array)($connz["connections"] ?? []) as $connection) {
                    if (($connection["uid"] ?? "") !== $uid) {
                        continue;
                    }
                    $result["last_activity_ip"] = empty($connection["ip"]) ? "消息服务" : $connection["ip"] . "(" . $ip->getDetail($connection["ip"])["dataA"] . ")";
                    $result["last_activity_time"] = $connection["last_activity"] ?? "暂无信息";
                    break;
                }
            } catch (\Exception $e) {
            }
            //获取推荐人
            $invite_info = Db::name("polymorphic")->where("type = 1 and other_id = {$result['id']}")->find();
            if ($invite_info) {
                $invite_user_info = Db::name("user")->where("id = {$invite_info['userid']}")->find();
                $result["invite_username"] = $invite_user_info["username"];
            } else {
                $result["invite_username"] = "无";
            }
            \think\facade\View::assign("user", $result);
            return \think\facade\View::fetch();
        }
    }

    //用户日志
    public function obtain_user_action_logs()
    {
        $sort = input('?sort') ? input('sort') : 'id';
        $sortOrder = input("?sortOrder") ? input("sortOrder") : "desc";
        $user_id = input("user_id");
        if ($user_id == "") {
            $result = [
                "rows" => [],
                "total" => 0,
            ];
            return $this->tableResponse($result);
        }
        $limit = input('limit/d') ?: 10;
        $page = input('page/d') ?: 1;
        $where = " uid = {$user_id} and log_type = 1";
        $rows = Db::name("operation_log")
            ->where($where)
            ->order($sort, $sortOrder)
            ->page($page, $limit)
            ->select()->toArray();
        $rows_list = [];
        $ip = new IpLocation();
        foreach ($rows as $key => $value) {
            $rows_list[] = $value;
            $rows_list[$key]["ip"] = $value["ip"] == "" ? "" : $value["ip"] . "(" . $ip->getDetail($value["ip"])["dataA"] . ")";
        }
        $count = Db::name("operation_log")
            ->where($where)
            ->count();
        $result = [
            "rows" => $rows_list,
            "total" => $count,
        ];
        return $this->tableResponse($result);
    }

    //用户信息审核
    public function audit()
    {
        if (request()->isAjax()) {
            $sort = input('?sort') ? input('sort') : 'id';
            $sortOrder =
                input("?sortOrder") ? input("sortOrder") : "asc";
            $audit_status = input("audit_status");
            $username = input("username");
            $appid = input("appid");
            $limit = input('limit/d') ?: 10;
            $page = input('page/d') ?: 1;
            $where = " 1 ";
            if (input("audit_status") != "") {
                $where .= " and ua.audit_status = {$audit_status}";
            }
            if (input("username") != "") {
                $where .= " and u.username like '%" . $username . "%'";
            }
            if (input("appid") != "") {
                $where .= " and a.appid = {$appid}";
            }
            $rows = Db::name("user_information_review")
                ->alias("ua")
                ->join("user u", "ua.userid = u.id")
                ->join("app a", "a.appid = u.appid")
                ->field("ua.*,u.username,a.appname")
                ->where($where)
                ->order("ua." . $sort, $sortOrder)
                ->page($page, $limit)
                ->select()->toArray();
            $count = Db::name("user_information_review")
                ->alias("ua")
                ->join("user u", "ua.userid = u.id")
                ->join("app a", "a.appid = u.appid")
                ->field("ua.*,u.username,a.appname")
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

    //审核用户信息
    public function auditing_user_info()
    {
        $id = input("post.id");
        $reason_review = input("post.reason_review");
        $audit_status = input("post.audit_status");
        //验证$audit_status 只能是 1 或者 2
        if (!in_array($audit_status, [1, 2])) {
            return \app\common\support\ResponseHelper::error("审核状态错误");
        }
        if ($audit_status == 2) {
            if (!$reason_review) {
                return \app\common\support\ResponseHelper::error("审核内容不能为空");
            }
        }
        $audit_info = Db::name("user_information_review")->where("id", $id)->find();
        if (!$audit_info) {
            return \app\common\support\ResponseHelper::error("该审核信息不存在！");
        }
        //查询用户信息
        $user_all_info = Db::name('user')->where("id", $audit_info['userid'])->find();
        $data = [
            "reason_review" => $reason_review,
            "audit_status" => $audit_status,
            "audit_time" => date("Y-m-d H:i:s", time()),
        ];
        Db::name("user_information_review")->where("id", $id)->update($data);
        //审核通过 修改用户信息 发送通知
        if ($audit_status == 1) {
            $update_user_info = [
                "nickname" => $audit_info["nickname"],
                "signature" => $audit_info["signature"],
                "usertx" => $audit_info["usertx"],
                "userbg" => $audit_info["userbg"],
            ];
            Db::name("user")->where("id", $user_all_info['id'])->update($update_user_info);
            $addmessagedata = [
                "title" => "用户信息审核成功",
                "content" => "你修改的个人信息资料已经审核通过了，快去查看吧！",
                "send_to" => 0,
                "appid" => $user_all_info["appid"],
                "time" => date("Y-m-d H:i:s", time()),
                "type" => 0,
                "user_id" => $user_all_info["id"],
            ];
            Db::name("message_notification")->insert($addmessagedata);
        } else {
            $addmessagedata = [
                "title" => "用户信息审核失败",
                "content" => "你修改的个人信息资料审核未通过了，原因为：" .  $reason_review,
                "send_to" => 0,
                "appid" => $user_all_info["appid"],
                "time" => date("Y-m-d H:i:s", time()),
                "type" => 0,
                "user_id" => $user_all_info["id"],
            ];
            Db::name("message_notification")->insert($addmessagedata);
        }
        return \app\common\support\ResponseHelper::success("审核成功");
    }

    //批量审核用户信息
    public function auditing_all_user_info()
    {
        $id = input("id");
        $id_array = explode(",", input('id'));
        foreach ($id_array as $key => $value) {
            $audit_info = Db::name("user_information_review")->where("id", $value)->find();
            if ($audit_info["audit_status"] == 1 || $audit_info["audit_status"] == 2) {
                continue;
            }
            $data = [
                "reason_review" => "",
                "audit_status" => 1,
                "audit_time" => date("Y-m-d H:i:s", time()),
            ];
            Db::name("user_information_review")->where("id", $value)->update($data);
            $user_all_info = Db::name('user')->where("id", $audit_info['userid'])->find();
            $update_user_info = [
                "nickname" => $audit_info["nickname"],
                "signature" => $audit_info["signature"],
                "usertx" => $audit_info["usertx"],
                "userbg" => $audit_info["userbg"],
            ];
            Db::name("user")->where("id", $user_all_info['id'])->update($update_user_info);
            $addmessagedata = [
                "title" => "用户信息审核成功",
                "content" => "你修改的个人信息资料已经审核通过了，快去查看吧！",
                "send_to" => 0,
                "appid" => $user_all_info["appid"],
                "time" => date("Y-m-d H:i:s", time()),
                "type" => 0,
                "user_id" => $user_all_info["id"],
            ];
            Db::name("message_notification")->insert($addmessagedata);
        }
        return \app\common\support\ResponseHelper::success("审核成功");
    }

    //删除用户审核信息
    public function delete_auditing_user_info()
    {
        $id = explode(",", input('id'));
        foreach ($id as $key => $value) {
            Db::name("user_information_review")->where("id={$value}")->delete();
        }
        return \app\common\support\ResponseHelper::success("删除成功！");
    }

    //徽章管理页面
    public function bagge()
    {
        if (request()->isAjax()) {
            $sort = input('?sort') ? input('sort') : 'id';
            $sortOrder = input("?sortOrder") ? input("sortOrder") : "asc";
            $name = input("name");
            $appid = input("appid");
            $limit = input('limit/d') ?: 10;
            $page = input('page/d') ?: 1;
            $where = " 1 ";
            if (input("name") != "") {
                $where .= " and b.name like '%" . $name . "%'";
            }
            if (input("appid") != "") {
                $where .= " and b.appid = {$appid}";
            }
            $rows = Db::name("bagge")
                ->alias("b")
                ->join("app a", "b.appid = a.appid")
                ->where($where)
                ->field("b.*,a.appname")
                ->order("b." . $sort, $sortOrder)
                ->page($page, $limit)
                ->select()->toArray();
            $count = Db::name("bagge")
                ->alias("b")
                ->join("app a", "b.appid = a.appid")
                ->where($where)
                ->count();
            $result = [
                "rows" => $rows,
                "total" => $count,
            ];
            return $this->tableResponse($result);
        }
        return \think\facade\View::fetch('bagge');
    }

    //修改徽章显示状态
    public function update_bagge_status()
    {
        $id = input("id");
        $status = input("status");
        $section_info = Db::name("bagge")->where("id={$id}")->find();
        if (!$section_info) {
            return \app\common\support\ResponseHelper::error("徽章不存在！");
        }
        Db::name("bagge")->where("id={$id}")->update(["is_view" => $status]);
        return \app\common\support\ResponseHelper::success("修改成功！");
    }

    //删除徽章
    public function delete_bagge()
    {
        $id = explode(",", input('id'));
        foreach ($id as $key => $value) {
            //删除用户其他信息
            Db::name("bagge")->where("id", "=", $value)->delete();
        }
        return \app\common\support\ResponseHelper::success("删除成功");
    }

    //添加徽章
    public function add_bagge()
    {
        $name = input("name");
        $description = input("description");
        $icon = input("icon");
        $appid = input("appid");
        $type = input("type");
        $sort = input("sort");
        if ($name == "" || $description == "" || $appid == "") {
            return \app\common\support\ResponseHelper::error("请输入完整！");
        }
        $bagge_info = Db::name("bagge")->where("name='{$name}' and appid={$appid}")->find();
        if ($bagge_info) {
            return \app\common\support\ResponseHelper::error("徽章已存在！");
        }
        $data = [
            "name" => $name,
            "description" => $description,
            "icon" => $icon,
            "appid" => $appid,
            "is_view" => 0,
            "type" => $type,
            "create_time" => date("Y-m-d H:i:s", time()),
            "sort" => $sort
        ];
        Db::name("bagge")->insert($data);
        return \app\common\support\ResponseHelper::success("添加成功！");
    }

    //修改徽章
    public function update_bagge()
    {
        $id = input("id");
        $name = input("name");
        $description = input("description");
        $icon = input("icon");
        $sort = input("sort");
        if ($name == "" || $description == "" || $icon == "") {
            return \app\common\support\ResponseHelper::error("请输入完整！");
        }
        $bagge_info = Db::name("bagge")->where("id={$id}")->find();
        if (!$bagge_info) {
            return \app\common\support\ResponseHelper::error("徽章不存在！");
        }
        $bagge_info = Db::name("bagge")->where("id != {$id} and name='{$name}' and appid = {$bagge_info['appid']}")->find();
        if ($bagge_info) {
            return \app\common\support\ResponseHelper::error("徽章已存在！");
        }
        $data = [
            "name" => $name,
            "description" => $description,
            "icon" => $icon,
            "sort" => $sort
        ];
        Db::name("bagge")->where("id={$id}")->update($data);
        return \app\common\support\ResponseHelper::success("添加成功！");
    }

    //用户徽章页面
    public function user_bagge()
    {
        if (request()->isAjax()) {
            $sort = input('?sort') ? input('sort') : 'id';
            $sortOrder = input("?sortOrder") ? input("sortOrder") : "asc";
            $nickname = input("nickname");
            $username = input("username");
            $appid = input("appid");
            $limit = input('limit/d') ?: 10;
            $page = input('page/d') ?: 1;
            $where = " p.type = 5 ";
            if (input("username") != "") {
                $where .= " and u.username like '%" . $username . "%'";
            }
            if (input("nickname") != "") {
                $where .= " and u.nickname like '%" . $nickname . "%'";
            }
            if (input("appid") != "") {
                $where .= " and b.appid = {$appid}";
            }
            $rows = Db::name("polymorphic")
                ->alias("p")
                ->join("user u", "p.userid = u.id")
                ->join("bagge b", "p.other_id = b.id")
                ->join("app a", "p.appid = a.appid")
                ->field("u.username,u.nickname,b.name as bagge_name,b.icon as bagge_icon,b.type,a.appname,p.expiration_time,p.create_time,p.id")
                ->where($where)
                ->order("b." . $sort, $sortOrder)
                ->page($page, $limit)
                ->select()->toArray();
            $count = Db::name("polymorphic")
                ->alias("p")
                ->join("user u", "p.userid = u.id")
                ->join("bagge b", "p.other_id = b.id")
                ->join("app a", "p.appid = a.appid")
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

    //添加用户徽章
    public function add_user_bagge()
    {
        $appid = input("appid");
        $userid = input("userid");
        $baggeid = input("baggeid");
        $expiration_time = input("expiration_time");
        if ($appid == "" || $userid == "" || $baggeid == "" || $expiration_time == "") {
            return \app\common\support\ResponseHelper::error("请输入完整！");
        }
        $user_info = Db::name("user")->where("id={$userid}")->find();
        if (!$user_info) {
            return \app\common\support\ResponseHelper::error("用户不存在！");
        }
        $bagge_info = Db::name("bagge")->where("id={$baggeid}")->find();
        if (!$bagge_info) {
            return \app\common\support\ResponseHelper::error("徽章不存在！");
        }
        $polymorphic_info = Db::name("polymorphic")->where("type=5 and userid={$userid} and other_id={$baggeid}")->find();
        if ($polymorphic_info) {
            return \app\common\support\ResponseHelper::error("用户已拥有该徽章！");
        }
        $data = [
            "type" => 5,
            "userid" => $userid,
            "other_id" => $baggeid,
            "appid" => $appid,
            "expiration_time" => $expiration_time,
            "create_time" => date("Y-m-d H:i:s", time()),
        ];
        Db::name("polymorphic")->insert($data);
        return \app\common\support\ResponseHelper::success("添加成功！");
    }

    //删除用户徽章
    public function delete_user_bagge()
    {
        $id = explode(",", input('id'));
        foreach ($id as $key => $value) {
            Db::name("polymorphic")->where("type", 5)->where("id={$value}")->delete();
        }
        return \app\common\support\ResponseHelper::success("删除成功！");
    }
}
