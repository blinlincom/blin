<?php

namespace app\api\controller;

use app\common\tool\AlibabaSample;
use app\common\tool\Email;
use app\common\tool\IpLocation;
use app\common\tool\Upload;
use app\common\tool\WukongIM;
use app\common\tool\AliyunPay;
use app\common\tool\Epay;
use app\common\tool\QrCodeTool;
use app\common\support\CaptchaService;
use app\common\support\ChatControl;
use app\common\support\GatewayStream;
use app\common\support\LiveKitToken;
use app\common\support\MomentsControl;
use app\common\support\OtcService;
use app\common\support\DigitalAssetService;
use app\common\support\AssetExchangeService;
use app\common\support\WalletNoticeService;
use app\common\support\UserDeviceSession;
use Exception;
use think\facade\Db;
use think\facade\Cache;
use think\facade\Config;
use think\facade\Env;
use think\facade\Request;
use think\Validate;

class Api extends BaseController
{
    protected array $chatRequest = [];
    protected string $liveKitLastError = '';

    protected function wukongUid($userId): string
    {
        return WukongIM::uid($this->appid, $userId);
    }

    protected function chatGroupChannelId($groupId): string
    {
        return 'app' . (int)$this->appid . 'group' . (int)$groupId;
    }

    protected function parseChatGroupChannelId(string $channelId): array
    {
        if (preg_match('/^app(\d+)group(\d+)$/', $channelId, $matches)) {
            return [
                "appid" => (int)$matches[1],
                "group_id" => (int)$matches[2],
            ];
        }
        return [];
    }

    protected function chatRequestContext(bool $requireUsertoken = true): array
    {
        if ($this->chatRequest) {
            return $this->chatRequest;
        }

        $data = input('');
        if ($requireUsertoken && trim((string)($data["usertoken"] ?? "")) === "") {
            $this->json(0, "usertoken不能为空");
        }
        if (trim((string)($data["device"] ?? "")) === "") {
            $this->json(0, "device不能为空");
        }
        $platform = $this->clientPlatform($data);
        // 新版聊天接口只接受 IM 协议的 device/device_flag，旧端类型字段不再处理。
        if (isset($data["device_type"]) && trim((string)$data["device_type"]) !== "") {
            $this->json(0, "device_type不支持，请使用device_flag");
        }
        if (!isset($data["device_flag"]) || trim((string)$data["device_flag"]) === "") {
            $this->json(0, "device_flag不能为空");
        }
        if (trim((string)($data["timestamp"] ?? "")) === "") {
            $this->json(0, "timestamp不能为空");
        }
        if (trim((string)($data["nonce"] ?? "")) === "") {
            $this->json(0, "nonce不能为空");
        }
        if (trim((string)($data["sign"] ?? "")) === "") {
            $this->json(0, "sign不能为空");
        }

        $this->checkTimeOffset($data["timestamp"], $this->chatTimestampWindow());
        $this->assertChatRequestSign($data);
        $this->assertChatRequestNonce($data);
        $this->chatRequest = [
            "device" => trim((string)$data["device"]),
            "client_platform" => $platform,
            "timestamp" => (string)$data["timestamp"],
            "nonce" => trim((string)$data["nonce"]),
            "device_flag" => $this->chatDeviceFlag($data),
            "device_level" => $this->chatDeviceLevel($data),
        ];
        return $this->chatRequest;
    }

    protected function secureChatInput(array $data): array
    {
        return $this->decodeSecureChatInput($data, true);
    }

    protected function decodeSecureChatInput(array $data, bool $requirePayload): array
    {
        $plainKeys = ["username", "password", "mobile", "email", "captcha", "code", "verify_code", "verification_method", "invitecode", "type", "state", "openid", "access_token", "qq_appid", "user_id", "target_user_id", "target_username", "payee_id", "payee_username", "receiver_id", "group_id", "content_type", "content", "money", "amount", "asset_type", "remark", "url", "key", "km", "name", "account", "pay_password", "new_pay_password", "qr_token", "order_no", "request_id", "mime", "size", "width", "height", "duration", "cover_url", "sticker_id", "emoji_code", "emoji_id", "pack_id", "format", "animated", "emoji_asset", "sticker_asset", "card_user_id", "mention", "mention_user_ids", "at_user_ids", "mention_all", "at_all", "reply_client_msg_no", "burn_after_read", "burn_after_read_seconds", "packet_type", "quantity", "red_packet_id", "transfer_id", "post_id", "comment_id", "reply_comment_id", "reply_user_id", "media", "media_type", "visibility", "visible_user_ids", "remind_user_ids", "location", "call_id", "call_type", "invite_user_ids", "end_call", "title", "unread_only", "unread_limit"];
        foreach ($plainKeys as $plainKey) {
            if (array_key_exists($plainKey, $data) && trim((string)$data[$plainKey]) !== "") {
                $this->json(0, "聊天业务字段必须使用secure_payload加密提交");
            }
        }
        $cipherText = trim((string)($data["secure_payload"] ?? ""));
        if ($cipherText === "") {
            if (!$requirePayload) {
                return $data;
            }
            $this->json(0, "secure_payload不能为空");
        }
        if ((string)($data["secure_payload_alg"] ?? "") !== "AES-128-CBC") {
            $this->json(0, "secure_payload_alg不支持");
        }
        $key = substr(md5((int)$this->appid . '|' . $this->appkey . '|' . (string)($data["usertoken"] ?? "")), 0, 16);
        $iv = substr(md5((string)($data["device"] ?? "") . '|' . (string)($data["client_msg_no"] ?? "") . '|' . (string)($data["timestamp"] ?? "") . '|' . (string)($data["nonce"] ?? "")), 0, 16);
        $plain = openssl_decrypt(base64_decode($cipherText), 'AES-128-CBC', $key, OPENSSL_RAW_DATA, $iv);
        if ($plain === false || $plain === "") {
            $this->json(0, "secure_payload解密失败");
        }
        $decoded = json_decode($plain, true);
        if (!is_array($decoded)) {
            $this->json(0, "secure_payload格式错误");
        }
        foreach (["appid", "usertoken", "device", "client_platform", "device_flag", "device_level", "timestamp", "nonce", "sign", "client_msg_no"] as $reservedKey) {
            if (array_key_exists($reservedKey, $data)) {
                unset($decoded[$reservedKey]);
            }
        }
        unset($data["secure_payload"]);
        $data = array_merge($data, $decoded);
        $this->chatRequest["secure_input"] = $data;
        return $data;
    }

    protected function secureChatRequestInput(bool $requirePayload = true): array
    {
        $this->chatRequestContext();
        $data = $this->decodeSecureChatInput(input(''), $requirePayload);
        if (isset($data["page"]) && is_numeric($data["page"])) {
            $this->page = max(1, (int)$data["page"]);
        }
        if (isset($data["limit"]) && is_numeric($data["limit"])) {
            $this->limit = max(1, min(200, (int)$data["limit"]));
        }
        return $data;
    }

    protected function secureChatResponse(array $data): array
    {
        if ((string)input("secure_response", "0") !== "1") {
            $this->json(0, "secure_response不能为空");
        }
        $request = $this->chatRequestContext();
        $plain = json_encode($data, JSON_UNESCAPED_UNICODE);
        if ($plain === false) {
            $this->json(0, "secure_payload编码失败");
        }
        $key = substr(md5((int)$this->appid . '|' . $this->appkey . '|' . (string)input("usertoken", "")), 0, 16);
        $iv = substr(md5((string)$request["device"] . '|response|' . (string)$request["timestamp"] . '|' . (string)$request["nonce"]), 0, 16);
        $cipher = openssl_encrypt($plain, 'AES-128-CBC', $key, OPENSSL_RAW_DATA, $iv);
        if ($cipher === false || $cipher === "") {
            $this->json(0, "secure_payload加密失败");
        }
        return [
            "secure_payload" => base64_encode($cipher),
            "secure_payload_alg" => "AES-128-CBC",
            "secure_payload_version" => "1",
        ];
    }

    protected function chatJson($code = 1, $msg = 'success', $data = [])
    {
        if ((int)$code === 1 && (string)input("secure_response", "0") === "1") {
            $this->json($code, $msg, $this->secureChatResponse(is_array($data) ? $data : ["value" => $data]));
        }
        $this->json($code, $msg, $data);
    }

    protected function securePublicRequestInput(): array
    {
        $data = input('');
        if (trim((string)($data["device"] ?? "")) === "") {
            $this->json(0, "device不能为空");
        }
        $platform = $this->clientPlatform($data);
        if (trim((string)($data["timestamp"] ?? "")) === "") {
            $this->json(0, "timestamp不能为空");
        }
        if (trim((string)($data["nonce"] ?? "")) === "") {
            $this->json(0, "nonce不能为空");
        }
        if (trim((string)($data["client_msg_no"] ?? "")) === "") {
            $this->json(0, "client_msg_no不能为空");
        }
        if (trim((string)($data["sign"] ?? "")) === "") {
            $this->json(0, "sign不能为空");
        }
        $this->checkTimeOffset($data["timestamp"], $this->chatTimestampWindow());
        $this->assertChatRequestSign($data);
        $this->assertChatRequestNonce($data);
        $this->chatRequest = [
            "device" => trim((string)$data["device"]),
            "client_platform" => $platform,
            "timestamp" => (string)$data["timestamp"],
            "nonce" => trim((string)$data["nonce"]),
            "device_flag" => $this->chatDeviceFlag($data),
            "device_level" => $this->chatDeviceLevel($data),
        ];
        return $this->decodeSecureChatInput($data, true);
    }

    protected function securePublicJson($code = 1, $msg = 'success', $data = [])
    {
        if ((int)$code === 1 && (string)input("secure_response", "0") === "1") {
            $this->json($code, $msg, $this->secureChatResponse(is_array($data) ? $data : ["value" => $data]));
        }
        $this->json($code, $msg, $data);
    }

    protected function decodeSecureChatFile(array $data): array
    {
        if ((string)($data["secure_file_alg"] ?? "") !== "AES-128-CBC") {
            $this->json(0, "secure_file_alg不支持");
        }
        $file = $_FILES["secure_file"];
        $tmpName = is_array($file["tmp_name"] ?? null) ? ($file["tmp_name"][0] ?? "") : (string)($file["tmp_name"] ?? "");
        if ($tmpName === "" || !is_uploaded_file($tmpName)) {
            $this->json(0, "secure_file不能为空");
        }
        $cipher = file_get_contents($tmpName);
        if ($cipher === false || $cipher === "") {
            $this->json(0, "secure_file读取失败");
        }
        $expectedHash = strtolower(trim((string)($data["secure_file_sha256"] ?? "")));
        if ($expectedHash === "" || !hash_equals($expectedHash, hash("sha256", $cipher))) {
            $this->json(0, "secure_file校验失败");
        }
        $key = substr(hash("sha256", "file-key|" . (string)($data["device"] ?? "") . "|" . (string)($data["client_msg_no"] ?? "") . "|" . (string)($data["timestamp"] ?? "") . "|" . (string)($data["nonce"] ?? "")), 0, 16);
        $iv = substr(hash("sha256", "file-iv|" . (string)($data["device"] ?? "") . "|" . (string)($data["client_msg_no"] ?? "") . "|" . (string)($data["timestamp"] ?? "") . "|" . (string)($data["nonce"] ?? "")), 0, 16);
        $plain = openssl_decrypt($cipher, "AES-128-CBC", $key, OPENSSL_RAW_DATA, $iv);
        if ($plain === false) {
            $this->json(0, "secure_file解密失败");
        }
        $name = trim((string)($data["secure_file_name"] ?? ""));
        if ($name === "") {
            $name = is_array($file["name"] ?? null) ? ($file["name"][0] ?? "file") : (string)($file["name"] ?? "file");
        }
        $size = (int)($data["secure_file_size"] ?? strlen($plain));
        if ($size > 0 && $size !== strlen($plain)) {
            $this->json(0, "secure_file_size不匹配");
        }
        return $this->saveSecureChatFile(
            $plain,
            basename($name),
            $size > 0 ? $size : strlen($plain),
            trim((string)($data["mime"] ?? ""))
        );
    }

    protected function saveSecureChatFile(string $plain, string $name, int $size, string $expectedMime = ""): array
    {
        $extension = strtolower(pathinfo($name, PATHINFO_EXTENSION));
        $allowedExtensions = [
            "jpg", "jpeg", "png", "gif", "webp", "bmp",
            "mp3", "wav", "m4a", "aac", "amr", "ogg",
            "mp4", "mov", "avi", "mkv", "webm",
            "pdf", "doc", "docx", "xls", "xlsx", "ppt", "pptx",
            "txt", "csv", "zip", "rar", "7z",
        ];
        if (!in_array($extension, $allowedExtensions, true)) {
            $extension = "bin";
        }
        $dir = public_path() . "uploads/chat/" . date("Ymd") . "/";
        if (!is_dir($dir) && !mkdir($dir, 0755, true)) {
            $this->json(0, "secure_file保存目录创建失败");
        }
        $filename = date("His") . "_" . substr(md5((string)$this->appid . "|" . microtime(true) . "|" . $name), 0, 16) . "." . $extension;
        $path = $dir . $filename;
        if (file_put_contents($path, $plain) === false) {
            $this->json(0, "secure_file保存失败");
        }
        $relative = "/uploads/chat/" . date("Ymd") . "/" . $filename;
        $mime = function_exists("mime_content_type") ? (string)mime_content_type($path) : "application/octet-stream";
        $mime = $this->normalizeUploadedChatMime($extension, $mime, $expectedMime);
        Db::name("file")->insert([
            "name" => $name,
            "type" => $mime,
            "size" => $size,
            "filePath" => $relative,
            "create_time" => date("Y-m-d H:i:s"),
            "oss_type" => 0,
            "key" => "",
            "uploader_id" => (int)($this->user_info["id"] ?? 0),
            "uploader" => 1,
        ]);
        return [
            "filePath" => $relative,
            "key" => "",
            "name" => $name,
            "type" => $mime,
            "size" => $size,
        ];
    }

    protected function normalizeUploadedChatMime(string $extension, string $detectedMime, string $expectedMime = ""): string
    {
        $extension = strtolower(trim($extension));
        $detectedMime = strtolower(trim($detectedMime));
        $expectedMime = strtolower(trim($expectedMime));
        $byExtension = [
            "jpg" => "image/jpeg",
            "jpeg" => "image/jpeg",
            "png" => "image/png",
            "gif" => "image/gif",
            "webp" => "image/webp",
            "bmp" => "image/bmp",
            "mp3" => "audio/mpeg",
            "wav" => "audio/wav",
            "m4a" => "audio/mp4",
            "aac" => "audio/aac",
            "amr" => "audio/amr",
            "ogg" => "audio/ogg",
            "mp4" => "video/mp4",
            "mov" => "video/quicktime",
            "m4v" => "video/x-m4v",
            "avi" => "video/x-msvideo",
            "mkv" => "video/x-matroska",
            "webm" => "video/webm",
            "pdf" => "application/pdf",
            "txt" => "text/plain",
            "csv" => "text/csv",
            "zip" => "application/zip",
            "rar" => "application/vnd.rar",
            "7z" => "application/x-7z-compressed",
        ];
        $extensionMime = (string)($byExtension[$extension] ?? "");
        if ($expectedMime !== "" && $expectedMime !== "application/octet-stream") {
            $expectedMajor = strstr($expectedMime, "/", true) ?: "";
            $extensionMajor = $extensionMime !== "" ? (strstr($extensionMime, "/", true) ?: "") : "";
            if ($extensionMajor !== "" && $expectedMajor === $extensionMajor) {
                return $expectedMime;
            }
        }
        if ($detectedMime !== "" && $detectedMime !== "application/octet-stream") {
            return $detectedMime;
        }
        return $extensionMime !== "" ? $extensionMime : "application/octet-stream";
    }

    protected function chatInput(string $key, $default = null)
    {
        $secureInput = (array)($this->chatRequest["secure_input"] ?? []);
        if (array_key_exists($key, $secureInput)) {
            return $secureInput[$key];
        }
        return $default;
    }

    protected function absolutePublicUrl(string $url): string
    {
        $url = trim($url);
        if ($url === '') {
            return '';
        }
        if (str_starts_with($url, 'http://') || str_starts_with($url, 'https://')) {
            return $url;
        }
        return rtrim(request()->domain(), '/') . '/' . ltrim($url, '/');
    }

    protected function assertChatRequestSign(array $data): void
    {
        $sign = strtolower(trim((string)($data["sign"] ?? "")));
        $params = $this->chatSignParams($data);
        $expected = strtolower($this->generateSignature($params, $this->appkey));
        if ($sign === '' || !hash_equals($expected, $sign)) {
            $this->json(0, "sign错误");
        }
    }

    protected function assertChatRequestNonce(array $data): void
    {
        $nonce = trim((string)($data["nonce"] ?? ""));
        if ($nonce === "") {
            $this->json(0, "nonce不能为空");
        }
        if (!preg_match('/^[A-Za-z0-9._:-]{8,128}$/', $nonce)) {
            $this->json(0, "nonce不合法");
        }

        $window = max(300, $this->chatTimestampWindow());
        $cacheKey = 'chat_api_nonce:' . (int)$this->appid . ':' . md5(
            (string)($data["usertoken"] ?? "") . '|' .
            (string)($data["device"] ?? "") . '|' .
            (string)($data["timestamp"] ?? "") . '|' .
            $nonce
        );
        $lock = fopen(sys_get_temp_dir() . '/bim_chat_nonce_' . md5($cacheKey) . '.lock', 'c');
        if ($lock === false || !flock($lock, LOCK_EX)) {
            $this->json(429, "请求繁忙，请稍后重试", [], 429);
        }
        try {
            if (Cache::get($cacheKey)) {
                $this->json(409, "请求已处理，请勿重复提交", [], 409);
            }
            Cache::set($cacheKey, 1, $window);
        } finally {
            flock($lock, LOCK_UN);
            fclose($lock);
        }
    }

    protected function chatSignParams(array $data): array
    {
        unset($data["sign"], $data["callback"], $data["action"]);
        foreach ($data as $key => $value) {
            if ($value === null) {
                unset($data[$key]);
                continue;
            }
            $data[$key] = $this->normalizeChatSignValue($value);
        }
        ksort($data, SORT_STRING);
        return $data;
    }

    protected function normalizeChatSignValue($value)
    {
        if (is_array($value)) {
            $normalized = [];
            foreach ($value as $key => $item) {
                if ($item !== null) {
                    $normalized[$key] = $this->normalizeChatSignValue($item);
                }
            }
            ksort($normalized, SORT_STRING);
            return $normalized;
        }
        if (is_bool($value)) {
            return $value ? "1" : "0";
        }
        if (is_scalar($value)) {
            return (string)$value;
        }
        return $value;
    }

    protected function chatTimestampWindow(): int
    {
        $security = (array)($this->app_info["security_configuration"] ?? []);
        $window = (int)($security["time_difference_verification"] ?? 0);
        return $window > 0 ? $window : 300;
    }

    protected function chatDeviceFlag(array $data = []): int
    {
        $flag = $data["device_flag"] ?? input("device_flag", "");
        if ($flag !== "" && !is_numeric($flag)) {
            $this->json(0, "device_flag不合法");
        }
        if ($flag !== "") {
            $flag = (int)$flag;
            if (!in_array($flag, [
                (int)config('wukongim.device_flag_app', WukongIM::DEVICE_FLAG_APP),
                (int)config('wukongim.device_flag_web', WukongIM::DEVICE_FLAG_WEB),
                (int)config('wukongim.device_flag_pc', WukongIM::DEVICE_FLAG_PC),
            ], true)) {
                $this->json(0, "device_flag不合法");
            }
            return $flag;
        }
        return (int)config('wukongim.device_flag_app', WukongIM::DEVICE_FLAG_APP);
    }

    protected function clientPlatform(array $data = []): string
    {
        try {
            return UserDeviceSession::normalizePlatform($data['client_platform'] ?? input('client_platform', ''));
        } catch (\InvalidArgumentException $e) {
            $this->json(0, $e->getMessage());
        }
    }

    protected function issueUserDeviceSession(int $userId, string $device, array $data = []): string
    {
        try {
            return UserDeviceSession::issue(
                (int)$this->appid,
                $userId,
                $this->clientPlatform($data),
                $device
            );
        } catch (\Throwable $e) {
            $this->json(0, '登录会话创建失败');
        }
    }

    protected function chatDeviceLevel(array $data = []): int
    {
        $level = $data["device_level"] ?? input("device_level", "");
        if ($level !== "" && is_numeric($level)) {
            return max(0, min(1, (int)$level));
        }
        return (int)config('wukongim.device_level_master', WukongIM::DEVICE_LEVEL_MASTER);
    }

    protected function chatDevicePayload(): array
    {
        return [
            "device" => (string)$this->chatInput("device", ""),
            "device_flag" => $this->chatDeviceFlag(),
            "device_level" => $this->chatDeviceLevel(),
            "client_timestamp" => (string)$this->chatInput("timestamp", ""),
        ];
    }

    protected function appendWukongLoginPayload(array $result, int $userId, string $token): array
    {
        $im = new WukongIM();
        $uid = $this->wukongUid($userId);
        $deviceFlag = $this->chatDeviceFlag();
        $deviceLevel = $this->chatDeviceLevel();
        try {
            $im->updateToken($uid, $token, $deviceFlag, $deviceLevel);
            $route = $im->route();
        } catch (\Exception $e) {
            $this->json(0, $e->getMessage());
        }
        $result["chat"] = [
            "uid" => $uid,
            "device_flag" => $deviceFlag,
            "device_level" => $deviceLevel,
            "channel_type_person" => (int)config('wukongim.channel_type_person', WukongIM::CHANNEL_TYPE_PERSON),
            "channel_type_group" => (int)config('wukongim.channel_type_group', WukongIM::CHANNEL_TYPE_GROUP),
            "route" => [],
            "require_im_connect" => 1,
        ] + $this->historySyncPayload();
        return $result;
    }

    protected function appendGatewayStreamPayload(array $chat, string $uid, int $userId, string $device): array
    {
        $gateway = new GatewayStream();
        $streamAddr = $gateway->publicStreamAddr();
        if (!$gateway->enabled() || $streamAddr === '' || $device === '') {
            return $chat;
        }
        $ticket = $gateway->ticket([
            'appid' => (string)$this->appid,
            'uid' => $uid,
            'user_id' => (string)$userId,
            'device' => $device,
            'platform' => $this->clientPlatform(),
        ], (int)config('wukongim.gateway_ticket_ttl', 120));
        if ($ticket === '') {
            return $chat;
        }
        $frameKey = $gateway->frameKey($ticket);
        if ($frameKey === '') {
            return $chat;
        }
        $chat['route']['https_stream_addr'] = $streamAddr;
        $chat['stream'] = [
            'ticket' => $ticket,
            'frame_key' => $frameKey,
            'frame_alg' => 'AES-256-GCM',
            'expire_in' => (int)config('wukongim.gateway_ticket_ttl', 120),
            'last_cursor' => $gateway->ackCursor($uid, $device),
        ];
        return $chat;
    }

    protected function formatImUserProfile(array $user): array
    {
        $profile = [
            "userid" => $user["id"],
            "id" => $user["id"],
            "username" => $user["username"],
            "nickname" => $user["nickname"],
            "usertx" => $user["usertx"],
            "title" => array_filter(explode(",", $user["title"] ?? "")),
            "vip" => false,
            "hierarchy" => "",
            "badge" => [],
        ];
        if (!empty($user["viptime"]) && $user["viptime"] > time()) {
            $profile["vip"] = true;
        }
        $grades = eval("return " . $this->app_info["grade"] . ";");
        if (is_array($grades)) {
            foreach ($grades as $exp => $name) {
                if ($user["exp"] >= $exp) {
                    $profile["hierarchy"] = $name;
                } else {
                    break;
                }
            }
        }
        $profile["badge"] = Db::name("polymorphic")
            ->alias("p")
            ->join("bagge b", "b.id=p.other_id")
            ->where("p.userid", $user["id"])
            ->where("p.type", 5)
            ->where("b.is_view", 0)
            ->where("p.wearing", 0)
            ->order(["b.type" => $this->medal_sorting, "b.sort" => "desc"])
            ->field("b.id,b.name,b.icon,b.type,case when p.expiration_time = '9999' then '永久' else p.expiration_time end as expiration_time")
            ->select()->toArray();
        return $profile;
    }

    protected function formatChatUser(array $user): array
    {
        $profile = $this->formatImUserProfile($user);
        $profile["sex"] = $user["sex"] ?? 0;
        $profile["sexName"] = ($user["sex"] ?? 0) == 0 ? "男" : "女";
        return $profile;
    }

    protected function wukongMessagePayload(array $message): array
    {
        return WukongIM::decodePayload($message["payload"] ?? "");
    }

    protected function isDisplayableWukongChatMessage(array $message): bool
    {
        return $this->isDisplayableChatPayload($this->wukongMessagePayload($message));
    }

    protected function isDisplayableChatPayload(array $payload): bool
    {
        $contentType = (string)($payload["content_type"] ?? "");
        if ((string)($payload["protocol"] ?? "") !== "blin.chat.v1") {
            return false;
        }
        if ($contentType === "cmd") {
            return false;
        }
        return in_array($contentType, $this->displayableChatContentTypes(), true);
    }

    protected function displayableChatContentTypes(): array
    {
        return array_merge($this->chatMessageContentTypes(), [
            "transfer",
            "red_packet",
            "red_packet_received",
            "transfer_received",
            "call",
            "wallet_notice",
        ]);
    }

    protected function wukongPayloadToMessage(array $message): array
    {
        $payload = $this->wukongMessagePayload($message);
        $timestamp = (int)($message["timestamp"] ?? 0);
        $createTime = $payload["create_time"] ?? ($timestamp > 0 ? date("Y-m-d H:i:s", $timestamp) : date("Y-m-d H:i:s"));
        return [
            "id" => (string)($message["message_idstr"] ?? $message["message_id"] ?? ""),
            "client_msg_no" => (string)($message["client_msg_no"] ?? ""),
            "message_seq" => (int)($message["message_seq"] ?? 0),
            "create_time" => $createTime,
            "content" => (string)($payload["content"] ?? ""),
            "content_type" => (string)($payload["content_type"] ?? ""),
            "image_path" => (string)($payload["image_path"] ?? $payload["url"] ?? ""),
            "file_url" => (string)($payload["file_url"] ?? ""),
            "media" => $payload["media"] ?? [],
            "contact_card" => $payload["contact_card"] ?? [],
            "mention" => $payload["mention"] ?? [],
            "mention_users" => $payload["mention_users"] ?? [],
            "asset_type" => (string)($payload["asset_type"] ?? ""),
            "payload" => $payload,
            "reply" => $payload["reply"] ?? "",
            "scene" => (string)($payload["scene"] ?? ""),
            "sender_id" => (int)($payload["sender_id"] ?? 0),
            "receiver_id" => (int)($payload["receiver_id"] ?? 0),
            "group_id" => (int)($payload["group_id"] ?? 0),
        ];
    }

    protected function checkChatMessageText(string $content): void
    {
        if ($content === '') {
            return;
        }
        $prohibitedWordPath = public_path() . 'prohibited_word.txt';
        if (!is_file($prohibitedWordPath)) {
            return;
        }
        $words = array_filter(explode("，", file_get_contents($prohibitedWordPath)));
        foreach ($words as $word) {
            if ($word !== '' && strpos($content, $word) !== false) {
                $this->json(0, "内容包含违禁词");
            }
        }
    }

    protected function baseWukongMessagePayload(array $sender, array $receiver, string $contentType): array
    {
        return [
            "protocol" => "blin.chat.v1",
            "type" => $this->wukongContentTypeCode($contentType),
            "appid" => (int)$this->appid,
            "scene" => "private_chat",
            "content_type" => $contentType,
            "channel_type" => (int)config('wukongim.channel_type_person', WukongIM::CHANNEL_TYPE_PERSON),
            "channel_type_name" => "person",
            "sender_id" => (int)$sender["id"],
            "receiver_id" => (int)$receiver["id"],
            "sender_uid" => $this->wukongUid($sender["id"]),
            "receiver_uid" => $this->wukongUid($receiver["id"]),
            "sender_username" => (string)($sender["username"] ?? ""),
            "sender_nickname" => (string)($sender["nickname"] ?? ""),
            "sender_avatar" => (string)($sender["usertx"] ?? ""),
        ] + $this->chatDevicePayload();
    }

    protected function baseGroupMessagePayload(array $sender, array $group, string $contentType): array
    {
        return [
            "protocol" => "blin.chat.v1",
            "type" => $this->wukongContentTypeCode($contentType),
            "appid" => (int)$this->appid,
            "scene" => "group_chat",
            "content_type" => $contentType,
            "channel_type" => (int)config('wukongim.channel_type_group', WukongIM::CHANNEL_TYPE_GROUP),
            "channel_type_name" => "group",
            "channel_id" => (string)$group["channel_id"],
            "group_id" => (int)$group["id"],
            "group_name" => (string)$group["name"],
            "sender_id" => (int)$sender["id"],
            "sender_uid" => $this->wukongUid($sender["id"]),
            "sender_username" => (string)($sender["username"] ?? ""),
            "sender_nickname" => (string)($sender["nickname"] ?? ""),
            "sender_avatar" => (string)($sender["usertx"] ?? ""),
        ] + $this->chatDevicePayload();
    }

    protected function wukongContentTypeCode(string $contentType): int
    {
        $map = [
            "text" => (int)config('wukongim.content_type_text', WukongIM::CONTENT_TYPE_TEXT),
            "image" => (int)config('wukongim.content_type_image', WukongIM::CONTENT_TYPE_IMAGE),
            "transfer" => (int)config('wukongim.content_type_transfer', WukongIM::CONTENT_TYPE_TRANSFER),
            "red_packet" => (int)config('wukongim.content_type_red_packet', WukongIM::CONTENT_TYPE_RED_PACKET),
            "red_packet_received" => (int)config('wukongim.content_type_red_packet_received', WukongIM::CONTENT_TYPE_RED_PACKET_RECEIVED),
            "transfer_received" => (int)config('wukongim.content_type_transfer_received', WukongIM::CONTENT_TYPE_TRANSFER_RECEIVED),
            "emoji" => (int)config('wukongim.content_type_emoji', WukongIM::CONTENT_TYPE_EMOJI),
            "gif" => (int)config('wukongim.content_type_gif', WukongIM::CONTENT_TYPE_GIF),
            "sticker" => (int)config('wukongim.content_type_sticker', WukongIM::CONTENT_TYPE_STICKER),
            "video" => (int)config('wukongim.content_type_video', WukongIM::CONTENT_TYPE_VIDEO),
            "voice" => (int)config('wukongim.content_type_voice', WukongIM::CONTENT_TYPE_VOICE),
            "file" => (int)config('wukongim.content_type_file', WukongIM::CONTENT_TYPE_FILE),
            "contact_card" => (int)config('wukongim.content_type_contact_card', WukongIM::CONTENT_TYPE_CONTACT_CARD),
            "call" => (int)config('wukongim.content_type_call', WukongIM::CONTENT_TYPE_CALL),
            "wallet_notice" => (int)config('wukongim.content_type_wallet_notice', WukongIM::CONTENT_TYPE_WALLET_NOTICE),
            "recall" => WukongIM::CONTENT_TYPE_RECALL,
        ];
        return $map[$contentType] ?? 0;
    }

    protected function chatMessageContentTypes(): array
    {
        return ["text", "image", "emoji", "gif", "sticker", "video", "voice", "file", "contact_card"];
    }

    protected function chatMediaContentTypes(): array
    {
        return ["image", "emoji", "gif", "sticker", "video", "voice", "file"];
    }

    protected function normalizeIncomingChatContentType(array &$data): string
    {
        $contentType = trim((string)($data["content_type"] ?? "text"));
        if ($contentType !== "emoji" || !$this->emojiInputShouldBeText($data)) {
            return $contentType;
        }
        $content = trim((string)($data["content"] ?? $data["text"] ?? ""));
        if ($content === "" || in_array($content, ["[表情]", "[消息]"], true)) {
            $this->json(0, "系统表情请按文本消息发送");
        }
        $data["content_type"] = "text";
        $data["content"] = $content;
        $this->chatRequest["secure_input"] = $data;
        return "text";
    }

    protected function emojiInputShouldBeText(array $data): bool
    {
        if ((string)($data["content_type"] ?? "") !== "emoji") {
            return false;
        }
        $mediaInput = $this->chatArrayInputFromData($data, "media");
        $url = $this->firstStringValue($data, ["url", "file_url", "image_url", "gif_url", "emoji_url", "sticker_url", "path"]);
        if ($url === "") {
            $url = $this->firstStringValue($mediaInput, ["url", "file_url", "image_url", "gif_url", "emoji_url", "sticker_url", "path"]);
        }
        if ($url !== "" || (!empty($_FILES) && !empty($_FILES["secure_file"]))) {
            return false;
        }
        $content = trim((string)($data["content"] ?? $data["text"] ?? ""));
        if ($content !== "" && !in_array($content, ["[表情]", "[消息]"], true)) {
            return true;
        }
        $packId = trim((string)($data["pack_id"] ?? $mediaInput["pack_id"] ?? ""));
        $asset = $this->firstStringValue($data, ["emoji_asset", "emoji_path", "sticker_asset", "asset"]);
        if ($asset === "") {
            $asset = $this->firstStringValue($mediaInput, ["emoji_asset", "emoji_path", "sticker_asset", "asset"]);
        }
        return $packId === "" || $packId === "default" || str_starts_with($asset, "assets/emoji/default/");
    }

    protected function chatArrayInputFromData(array $data, string $key): array
    {
        $value = $data[$key] ?? [];
        if (is_array($value)) {
            return $value;
        }
        if (is_string($value) && trim($value) !== "") {
            $decoded = json_decode($value, true);
            return is_array($decoded) ? $decoded : [];
        }
        return [];
    }

    protected function firstStringValue(array $source, array $keys): string
    {
        foreach ($keys as $key) {
            if (!array_key_exists($key, $source)) {
                continue;
            }
            $value = trim((string)$source[$key]);
            if ($value !== "") {
                return $value;
            }
        }
        return "";
    }

    protected function assertChatMediaType(string $contentType, array $media): void
    {
        $mime = strtolower(trim((string)($media["mime"] ?? "")));
        $ext = strtolower(trim((string)($media["ext"] ?? "")));
        if ($contentType === "image") {
            if ($mime !== "" && !str_starts_with($mime, "image/")) {
                $this->json(0, "图片消息文件类型不合法");
            }
            if ($ext !== "" && !in_array($ext, ["jpg", "jpeg", "png", "gif", "webp", "bmp"], true)) {
                $this->json(0, "图片消息文件扩展名不合法");
            }
            return;
        }
        if ($contentType === "gif") {
            if ($mime !== "" && !in_array($mime, ["image/gif", "image/webp"], true)) {
                $this->json(0, "GIF消息文件类型不合法");
            }
            if ($ext !== "" && !in_array($ext, ["gif", "webp"], true)) {
                $this->json(0, "GIF消息文件扩展名不合法");
            }
            return;
        }
        if ($contentType === "video" && $mime !== "" && !str_starts_with($mime, "video/")) {
            $this->json(0, "视频消息文件类型不合法");
        }
        if ($contentType === "voice" && $mime !== "" && !str_starts_with($mime, "audio/")) {
            $this->json(0, "语音消息文件类型不合法");
        }
    }

    protected function normalizeChatMediaMime(string $contentType, array $media): string
    {
        $mime = strtolower(trim((string)($media["mime"] ?? "")));
        $ext = strtolower(trim((string)($media["ext"] ?? "")));
        if ($contentType === "voice") {
            $voiceMimes = [
                "m4a" => "audio/mp4",
                "aac" => "audio/aac",
                "mp3" => "audio/mpeg",
                "wav" => "audio/wav",
                "amr" => "audio/amr",
                "ogg" => "audio/ogg",
            ];
            if (isset($voiceMimes[$ext])) {
                return $voiceMimes[$ext];
            }
        }
        if ($contentType === "video") {
            $videoMimes = [
                "mp4" => "video/mp4",
                "mov" => "video/quicktime",
                "m4v" => "video/x-m4v",
                "avi" => "video/x-msvideo",
                "mkv" => "video/x-matroska",
                "webm" => "video/webm",
            ];
            if (isset($videoMimes[$ext]) && ($mime === "" || $mime === "application/octet-stream")) {
                return $videoMimes[$ext];
            }
        }
        return $mime;
    }

    protected function normalizeChatMediaPayload(string $contentType, array $user): array
    {
        $content = trim((string)$this->chatInput("content", ""));
        if ($contentType === "text") {
            if ($content === "") {
                $this->json(0, "content不能为空");
            }
            $this->checkChatMessageText($content);
            return [
                "content" => $content,
                "image_path" => "",
            ];
        }

        if (!in_array($contentType, $this->chatMediaContentTypes(), true)) {
            $this->json(0, "content_type不合法");
        }

        $secureInput = (array)($this->chatRequest["secure_input"] ?? []);
        $mediaInput = $this->chatArrayInputFromData($secureInput, "media");
        $media = [
            "url" => trim((string)$this->chatInput("url", "")),
            "key" => trim((string)$this->chatInput("key", "")),
            "name" => trim((string)$this->chatInput("name", "")),
            "mime" => trim((string)$this->chatInput("mime", "")),
            "size" => max(0, (int)$this->chatInput("size", 0)),
            "width" => max(0, (int)$this->chatInput("width", 0)),
            "height" => max(0, (int)$this->chatInput("height", 0)),
            "duration" => max(0, (int)$this->chatInput("duration", 0)),
            "cover_url" => trim((string)$this->chatInput("cover_url", "")),
            "sticker_id" => trim((string)$this->chatInput("sticker_id", "")),
            "emoji_code" => trim((string)$this->chatInput("emoji_code", "")),
            "emoji_id" => trim((string)$this->chatInput("emoji_id", "")),
            "pack_id" => trim((string)$this->chatInput("pack_id", "default")),
            "format" => strtolower(trim((string)$this->chatInput("format", ""))),
            "animated" => (int)$this->chatInput("animated", 0) === 1 ? 1 : 0,
            "emoji_asset" => trim((string)$this->chatInput("emoji_asset", "")),
            "sticker_asset" => trim((string)$this->chatInput("sticker_asset", "")),
        ];
        if ($media["url"] === "") {
            $media["url"] = $this->firstStringValue($mediaInput, ["url", "file_url", "image_url", "gif_url", "emoji_url", "sticker_url", "path"]);
        }
        foreach (["key", "name", "mime", "cover_url", "sticker_id", "emoji_code", "emoji_id", "pack_id", "format", "emoji_asset", "sticker_asset"] as $mediaKey) {
            if ((string)$media[$mediaKey] === "" && array_key_exists($mediaKey, $mediaInput)) {
                $media[$mediaKey] = trim((string)$mediaInput[$mediaKey]);
            }
        }
        if ($media["emoji_asset"] === "") {
            $media["emoji_asset"] = $this->firstStringValue($mediaInput, ["asset", "emoji_path"]);
        }
        if ($media["sticker_asset"] === "") {
            $media["sticker_asset"] = $this->firstStringValue($mediaInput, ["asset", "sticker_path"]);
        }
        foreach (["size", "width", "height", "duration"] as $numericKey) {
            if ((int)$media[$numericKey] <= 0 && array_key_exists($numericKey, $mediaInput)) {
                $media[$numericKey] = max(0, (int)$mediaInput[$numericKey]);
            }
        }
        $media["format"] = strtolower((string)$media["format"]);

        if (!empty($_FILES) && !empty($_FILES["secure_file"])) {
            $uploadResult = $this->decodeSecureChatFile($this->chatRequest["secure_input"] ?? []);
            $media["url"] = (string)$uploadResult["filePath"];
            $media["key"] = (string)($uploadResult["key"] ?? "");
            $media["name"] = (string)($uploadResult["name"] ?? "");
            $media["mime"] = (string)($uploadResult["type"] ?? "");
            $media["size"] = (int)($uploadResult["size"] ?? 0);
        } elseif (!empty($_FILES) && !empty($_FILES["file"])) {
            $this->json(0, "file不支持，请使用secure_file");
        }

        if ($media["name"] === "" && $media["url"] !== "") {
            $path = (string)(parse_url($media["url"], PHP_URL_PATH) ?: $media["url"]);
            $media["name"] = basename($path);
        }
        $media["ext"] = strtolower((string)pathinfo($media["name"] ?: (string)(parse_url($media["url"], PHP_URL_PATH) ?: $media["url"]), PATHINFO_EXTENSION));
        $media["mime"] = $this->normalizeChatMediaMime($contentType, $media);
        $this->assertChatMediaType($contentType, $media);

        if ($contentType === "emoji" && $media["emoji_code"] === "" && $content !== "") {
            $media["emoji_code"] = $content;
        }
        if ($contentType === "emoji" && $media["emoji_id"] === "" && $media["emoji_code"] !== "") {
            $media["emoji_id"] = $media["emoji_code"];
        }
        if ($contentType === "sticker" && $media["sticker_id"] === "" && $content !== "") {
            $media["sticker_id"] = $content;
        }
        if (in_array($contentType, ["gif", "sticker"], true) && $media["sticker_id"] !== "" && $media["pack_id"] === "") {
            $media["pack_id"] = "default";
        }
        if (in_array($contentType, ["image", "gif"], true) && $media["url"] === "") {
            $this->json(0, "file或url不能为空");
        }
        if ($contentType === "emoji" && $media["url"] === "" && $media["emoji_code"] === "") {
            $this->json(0, "表情消息file、url或emoji_code至少传一个");
        }
        if ($contentType === "sticker" && $media["url"] === "" && $media["sticker_id"] === "") {
            $this->json(0, "贴纸消息file、url或sticker_id至少传一个");
        }
        if ($contentType === "video" && $media["url"] === "") {
            $this->json(0, "视频消息file或url不能为空");
        }
        if ($contentType === "voice" && $media["url"] === "") {
            $this->json(0, "语音消息file或url不能为空");
        }
        if ($contentType === "file" && $media["url"] === "") {
            $this->json(0, "文件消息file或url不能为空");
        }

        $payload = [
            "content" => $content !== "" ? $content : $this->chatMediaDefaultContent($contentType, $media),
            "image_path" => in_array($contentType, ["image", "emoji", "gif", "sticker"], true) ? $media["url"] : "",
            "url" => $media["url"],
            "media" => $media,
        ];
        if (in_array($contentType, ["image", "emoji", "gif", "sticker"], true)) {
            $payload["width"] = $media["width"];
            $payload["height"] = $media["height"];
        }
        if (in_array($contentType, ["video", "voice"], true)) {
            $payload["duration"] = $media["duration"];
        }
        if ($contentType === "video") {
            $payload["video_url"] = $media["url"];
            $payload["cover_url"] = $media["cover_url"];
        }
        if ($contentType === "voice") {
            $payload["voice_url"] = $media["url"];
        }
        if ($contentType === "file") {
            $payload["file_url"] = $media["url"];
            $payload["file_name"] = $media["name"];
            $payload["file_size"] = $media["size"];
            $payload["file_ext"] = $media["ext"];
        }
        if ($contentType === "emoji") {
            $payload["emoji_code"] = $media["emoji_code"];
            $payload["emoji_id"] = $media["emoji_id"];
            $payload["pack_id"] = $media["pack_id"] !== "" ? $media["pack_id"] : "default";
            $payload["format"] = $media["format"] !== "" ? $media["format"] : "png";
            $payload["animated"] = $media["animated"];
            $payload["emoji_asset"] = $media["emoji_asset"];
            $payload["sticker_asset"] = $media["sticker_asset"];
        }
        if (in_array($contentType, ["gif", "sticker"], true)) {
            $payload["sticker_id"] = $media["sticker_id"];
            $payload["emoji_code"] = $media["emoji_code"];
            $payload["emoji_id"] = $media["emoji_id"];
            $payload["pack_id"] = $media["pack_id"] !== "" ? $media["pack_id"] : "default";
            $payload["format"] = $media["format"];
            $payload["animated"] = $media["animated"];
            $payload["emoji_asset"] = $media["emoji_asset"];
            $payload["sticker_asset"] = $media["sticker_asset"];
        }
        return $payload;
    }

    protected function chatMediaDefaultContent(string $contentType, array $media): string
    {
        $map = [
            "image" => "[图片]",
            "emoji" => "[表情]",
            "gif" => "[GIF]",
            "sticker" => "[贴纸]",
            "video" => "[视频]",
            "voice" => "[语音]",
            "file" => "[文件]",
        ];
        if ($contentType === "emoji" && (string)($media["emoji_code"] ?? "") !== "") {
            return (string)$media["emoji_code"];
        }
        if ($contentType === "file" && (string)($media["name"] ?? "") !== "") {
            return "[文件]" . (string)$media["name"];
        }
        return $map[$contentType] ?? "";
    }

    protected function normalizeContactCardPayload(): array
    {
        $cardUserId = (int)$this->chatInput("card_user_id", $this->chatInput("user_id", 0));
        if ($cardUserId <= 0) {
            $this->json(0, "card_user_id不能为空");
        }
        $cardUser = Db::name("user")
            ->where("appid", $this->appid)
            ->where("id", $cardUserId)
            ->find();
        if (!$cardUser) {
            $this->json(0, "名片用户不存在");
        }
        $card = $this->formatChatUser($cardUser);
        $card["uid"] = $this->wukongUid($cardUser["id"]);
        return [
            "content" => trim((string)$this->chatInput("content", "")) ?: "[名片]",
            "image_path" => "",
            "card_user_id" => (int)$cardUser["id"],
            "contact_card" => [
                "user_id" => (int)$cardUser["id"],
                "uid" => $this->wukongUid($cardUser["id"]),
                "username" => (string)$cardUser["username"],
                "nickname" => (string)$cardUser["nickname"],
                "avatar" => (string)$cardUser["usertx"],
                "sex" => (int)($cardUser["sex"] ?? 0),
                "signature" => (string)($cardUser["signature"] ?? ""),
                "profile" => $card,
            ],
        ];
    }

    protected function chatSendResponse(array $sendResult, string $clientMsgNo, array $payload): array
    {
        $gatewayPublish = $this->publishSendResultToGateway($sendResult, $clientMsgNo, $payload);
        return [
            "client_msg_no" => $sendResult["client_msg_no"] ?? $clientMsgNo,
            "message_id" => (string)($sendResult["message_id"] ?? ""),
            "message_seq" => (int)($sendResult["message_seq"] ?? 0),
            "send_ack" => [
                "client_msg_no" => $sendResult["client_msg_no"] ?? $clientMsgNo,
                "message_id" => (string)($sendResult["message_id"] ?? ""),
                "message_seq" => (int)($sendResult["message_seq"] ?? 0),
                "queued" => (bool)($sendResult["queued"] ?? false),
                "duplicate" => (bool)($sendResult["duplicate"] ?? false),
                "queue_status" => (int)($sendResult["queue_status"] ?? 0),
                "gateway_publish" => $gatewayPublish,
            ],
            "queued" => (bool)($sendResult["queued"] ?? false),
            "duplicate" => (bool)($sendResult["duplicate"] ?? false),
            "gateway_publish" => $gatewayPublish,
        ];
    }

    protected function publishSendResultToGateway(array $sendResult, string $clientMsgNo, array $payload): array
    {
        $result = [
            "enabled" => false,
            "published" => 0,
            "source" => "api_send",
            "error" => "",
        ];
        try {
            $gateway = new GatewayStream();
            if (!$gateway->enabled()) {
                return $result;
            }
            $result["enabled"] = true;
            if (empty($payload)) {
                return $result;
            }
            $clientMsgNo = (string)($sendResult["client_msg_no"] ?? $clientMsgNo);
            if ($clientMsgNo === "") {
                return $result;
            }
            $record = (new WukongIM())->queueRecord($clientMsgNo);
            if (!$record) {
                return $result;
            }
            $message = [
                "client_msg_no" => $clientMsgNo,
                "message_id" => (string)($sendResult["message_id"] ?? $record["message_id"] ?? ""),
                "message_idstr" => (string)($sendResult["message_idstr"] ?? $sendResult["message_id"] ?? $record["message_id"] ?? ""),
                "message_seq" => (int)($sendResult["message_seq"] ?? $record["message_seq"] ?? 0),
                "from_uid" => (string)$record["from_uid"],
                "channel_id" => (string)$record["channel_id"],
                "channel_type" => (int)$record["channel_type"],
                "timestamp" => time(),
                "payload" => (string)($record["payload_base64"] ?? ""),
            ];
            $payload["client_msg_no"] = $clientMsgNo;
            $payload["message_id"] = $message["message_idstr"];
            $payload["message_seq"] = $message["message_seq"];
            $payload["channel_id"] = $message["channel_id"];
            $payload["channel_type"] = $message["channel_type"];
            $payload["from_uid"] = $message["from_uid"];
            $result["published"] = $gateway->publishMessage($message, $payload);
        } catch (\Throwable $e) {
            $result["error"] = mb_substr($e->getMessage(), 0, 200);
        }
        return $result;
    }

    protected function buildReplyPayload(array $record, array $payload): array
    {
        $replyPayload = $payload;
        unset($replyPayload["reply"]);
        $fromName = (string)$record["from_uid"];
        $uidInfo = WukongIM::parseUid((string)$record["from_uid"]);
        if ($uidInfo) {
            $user = Db::name("user")
                ->where("appid", (int)$uidInfo["appid"])
                ->where("id", (int)$uidInfo["user_id"])
                ->find();
            if ($user) {
                $fromName = (string)($user["nickname"] ?: $user["username"] ?: $record["from_uid"]);
            }
        }
        $messageId = (string)($record["message_id"] ?? "");
        return [
            "root_mid" => (string)($payload["reply"]["root_mid"] ?? $messageId),
            "message_id" => $messageId,
            "message_seq" => (int)($record["message_seq"] ?? 0),
            "client_msg_no" => (string)$record["client_msg_no"],
            "from_uid" => (string)$record["from_uid"],
            "from_name" => $fromName,
            "payload" => $replyPayload,
        ];
    }

    protected function replyRecordByClientMsgNo(string $clientMsgNo): array
    {
        if ($clientMsgNo === "") {
            return [];
        }
        $record = Db::name("wukongim_message_queue")
            ->where("appid", $this->appid)
            ->where("client_msg_no", $clientMsgNo)
            ->where("status", WukongIM::QUEUE_SENT)
            ->find();
        if (!$record) {
            $this->json(0, "引用消息不存在或未发送成功");
        }
        $payload = json_decode((string)($record["payload_text"] ?? ""), true);
        if (!is_array($payload)) {
            $this->json(0, "引用消息payload异常");
        }
        if (in_array((string)($payload["content_type"] ?? ""), ["cmd", "recall"], true)) {
            $this->json(0, "该消息不能被引用");
        }
        $record["decoded_payload"] = $payload;
        return $record;
    }

    protected function appendPersonReplyPayload(array &$payload, array $sender, array $receiver, string $contentType): void
    {
        $replyClientMsgNo = trim((string)$this->chatInput("reply_client_msg_no", ""));
        if ($replyClientMsgNo === "") {
            return;
        }
        if ($contentType !== "text") {
            $this->json(0, "消息引用仅支持文本消息");
        }
        $record = $this->replyRecordByClientMsgNo($replyClientMsgNo);
        $senderUid = $this->wukongUid($sender["id"]);
        $receiverUid = $this->wukongUid($receiver["id"]);
        $channelType = (int)config('wukongim.channel_type_person', WukongIM::CHANNEL_TYPE_PERSON);
        $sameDirection = (string)$record["from_uid"] === $senderUid && (string)$record["channel_id"] === $receiverUid;
        $oppositeDirection = (string)$record["from_uid"] === $receiverUid && (string)$record["channel_id"] === $senderUid;
        if ((int)$record["channel_type"] !== $channelType || (!$sameDirection && !$oppositeDirection)) {
            $this->json(0, "只能引用当前私聊会话内的消息");
        }
        $payload["reply"] = $this->buildReplyPayload($record, (array)$record["decoded_payload"]);
    }

    protected function appendGroupReplyPayload(array &$payload, array $group, string $contentType): void
    {
        $replyClientMsgNo = trim((string)$this->chatInput("reply_client_msg_no", ""));
        if ($replyClientMsgNo === "") {
            return;
        }
        if ($contentType !== "text") {
            $this->json(0, "消息引用仅支持文本消息");
        }
        $record = $this->replyRecordByClientMsgNo($replyClientMsgNo);
        if (
            (int)$record["channel_type"] !== (int)config('wukongim.channel_type_group', WukongIM::CHANNEL_TYPE_GROUP)
            || (string)$record["channel_id"] !== (string)$group["channel_id"]
        ) {
            $this->json(0, "只能引用当前群聊内的消息");
        }
        $payload["reply"] = $this->buildReplyPayload($record, (array)$record["decoded_payload"]);
    }

    protected function hasReplyInput(): bool
    {
        return trim((string)$this->chatInput("reply_client_msg_no", "")) !== "";
    }

    protected function receiptStatusForMessage(string $clientMsgNo, array $record = []): array
    {
        if (!$record) {
            $record = Db::name('wukongim_message_queue')->where('client_msg_no', $clientMsgNo)->find() ?: [];
        }
        $readCount = (int)Db::name('wukongim_message_receipt')->where('client_msg_no', $clientMsgNo)->where('status', 1)->count();
        $readUids = Db::name('wukongim_message_receipt')
            ->where('client_msg_no', $clientMsgNo)
            ->where('status', 1)
            ->column('reader_uid');
        $payload = [];
        if ($record && (string)($record['payload_text'] ?? '') !== '') {
            $decoded = json_decode((string)$record['payload_text'], true);
            $payload = is_array($decoded) ? $decoded : [];
        }
        $total = 0;
        if ($record && (int)$record['channel_type'] === (int)config('wukongim.channel_type_group', WukongIM::CHANNEL_TYPE_GROUP)) {
            $group = Db::name('chat_group')->where('appid', $this->appid)->where('channel_id', $record['channel_id'])->find();
            if ($group) {
                $total = (int)Db::name('chat_group_member')
                    ->where('appid', $this->appid)
                    ->where('group_id', $group['id'])
                    ->where('status', 1)
                    ->where('user_id', '<>', (int)($payload['sender_id'] ?? 0))
                    ->count();
            }
        } elseif ($record) {
            $total = 1;
        }
        $status = [
            "read_count" => $readCount,
            "read_uids" => array_values(array_map('strval', $readUids)),
            "unread_count" => max(0, $total - $readCount),
            "total_receivers" => $total,
        ];
        if (($payload['content_type'] ?? '') === 'red_packet' && isset($payload['red_packet']['red_packet_id'])) {
            $packet = $this->refreshExpiredRedPacket((int)$payload['red_packet']['red_packet_id']);
            if ($packet) {
                $assetType = (string)($packet['asset_type'] ?? 'money');
                $status['red_packet'] = [
                    "red_packet_id" => (int)$packet['id'],
                    "transaction_no" => (string)($packet['transaction_no'] ?? ''),
                    "amount" => $this->chatAssetAmountLabel($packet['amount'] ?? 0, $assetType),
                    "amount_label" => $this->chatAssetAmountLabel($packet['amount'] ?? 0, $assetType),
                    "asset_type" => $assetType,
                    "status" => (int)$packet['status'],
                    "status_name" => $this->redPacketStatusName((int)$packet['status']),
                    "packet_type" => (string)($packet['packet_type'] ?? 'ordinary'),
                    "receiver_id" => (int)($packet['receiver_id'] ?? 0),
                    "receive_count" => (int)$packet['receive_count'],
                    "quantity" => (int)$packet['quantity'],
                    "remaining_amount" => $this->chatAssetAmountLabel($packet['remaining_amount'] ?? 0, $assetType),
                    "refund_amount" => $this->chatAssetAmountLabel($packet['refund_amount'] ?? 0, $assetType),
                    "expire_time" => (string)($packet['expire_time'] ?? ''),
                    "receive_time" => (string)($packet['receive_time'] ?? ''),
                    "refund_time" => (string)($packet['refund_time'] ?? ''),
                ];
            }
        }
        if (($payload['content_type'] ?? '') === 'transfer' && isset($payload['transfer']['transfer_id'])) {
            $transfer = $this->refreshExpiredTransfer((int)$payload['transfer']['transfer_id']);
            if ($transfer) {
                $assetType = (string)($transfer['asset_type'] ?? 'money');
                $status['transfer'] = [
                    "transfer_id" => (int)$transfer['id'],
                    "transaction_no" => (string)($transfer['transaction_no'] ?? ''),
                    "amount" => $this->chatAssetAmountLabel($transfer['amount'] ?? 0, $assetType),
                    "amount_label" => $this->chatAssetAmountLabel($transfer['amount'] ?? 0, $assetType),
                    "asset_type" => $assetType,
                    "status" => (int)$transfer['status'],
                    "status_name" => $this->transferStatusName((int)$transfer['status']),
                    "receiver_id" => (int)$transfer['receiver_id'],
                    "group_id" => (int)($transfer['group_id'] ?? 0),
                    "receive_time" => (string)($transfer['receive_time'] ?? ''),
                    "expire_time" => (string)($transfer['expire_time'] ?? ''),
                    "refund_time" => (string)($transfer['refund_time'] ?? ''),
                ];
            }
        }
        return $status;
    }

    protected function appendReceiptStatus(array &$messageData): void
    {
        $clientMsgNo = (string)($messageData['client_msg_no'] ?? '');
        if ($clientMsgNo === '') {
            return;
        }
        $messageData['receipt'] = $this->receiptStatusForMessage($clientMsgNo);
    }

    protected function recordMessageReadReceipt(array $record, array $reader, int $messageSeq = 0, WukongIM $im = null): array
    {
        $settings = $this->chatControl();
        if ((int)$settings['read_receipt_enabled'] !== 1) {
            return $this->receiptStatusForMessage((string)$record['client_msg_no'], $record);
        }
        $readerUid = $this->wukongUid($reader['id']);
        if ((string)$record['from_uid'] === $readerUid) {
            return $this->receiptStatusForMessage((string)$record['client_msg_no'], $record);
        }
        if ((int)$record['channel_type'] === (int)config('wukongim.channel_type_group', WukongIM::CHANNEL_TYPE_GROUP)) {
            $group = Db::name('chat_group')->where('appid', $this->appid)->where('channel_id', $record['channel_id'])->where('status', 1)->find();
            if (!$group) {
                return $this->receiptStatusForMessage((string)$record['client_msg_no'], $record);
            }
            $this->assertGroupMember($group, $reader);
            if ((int)$settings['group_read_count_enabled'] !== 1) {
                return $this->receiptStatusForMessage((string)$record['client_msg_no'], $record);
            }
        } elseif ((string)$record['channel_id'] !== $readerUid) {
            return $this->receiptStatusForMessage((string)$record['client_msg_no'], $record);
        }

        $now = date('Y-m-d H:i:s');
        $exists = Db::name('wukongim_message_receipt')
            ->where('client_msg_no', $record['client_msg_no'])
            ->where('reader_uid', $readerUid)
            ->where('status', 1)
            ->find();
        if ($exists) {
            return $this->receiptStatusForMessage((string)$record['client_msg_no'], $record);
        }

        Db::name('wukongim_message_receipt')->insert([
            "appid" => $this->appid,
            "client_msg_no" => (string)$record['client_msg_no'],
            "message_id" => (string)($record['message_id'] ?? ''),
            "channel_id" => (string)$record['channel_id'],
            "channel_type" => (int)$record['channel_type'],
            "message_seq" => $messageSeq,
            "from_uid" => (string)$record['from_uid'],
            "reader_uid" => $readerUid,
            "reader_id" => (int)$reader['id'],
            "status" => 1,
            "read_time" => $now,
            "create_time" => $now,
            "update_time" => $now,
        ]);

        $status = $this->receiptStatusForMessage((string)$record['client_msg_no'], $record);
        $payload = [
            "protocol" => "blin.chat.v1",
            "type" => WukongIM::CONTENT_TYPE_CMD,
            "content_type" => "cmd",
            "cmd" => "message_read_receipt",
            "scene" => (int)$record['channel_type'] === (int)config('wukongim.channel_type_group', WukongIM::CHANNEL_TYPE_GROUP) ? "group_chat" : "private_chat",
            "appid" => (int)$this->appid,
            "channel_id" => (string)$record['channel_id'],
            "channel_type" => (int)$record['channel_type'],
            "operator_id" => (int)$reader['id'],
            "operator_uid" => $readerUid,
            "target_client_msg_no" => (string)$record['client_msg_no'],
            "target_message_id" => (string)($record['message_id'] ?? ''),
            "receipt" => [
                "action" => "read",
                "read_count" => (int)$status['read_count'],
                "unread_count" => (int)$status['unread_count'],
                "total_receivers" => (int)$status['total_receivers'],
                "reader_uid" => $readerUid,
                "reader_id" => (int)$reader['id'],
                "read_time" => time(),
            ],
        ] + $this->chatDevicePayload();
        $im = $im ?: new WukongIM();
        try {
            $eventId = 'read-' . (int)$reader['id'] . '-' . (string)$record['client_msg_no'];
            $im->appendMessageEvent((string)$record['channel_id'], (int)$record['channel_type'], (string)$record['from_uid'], (string)$record['client_msg_no'], $payload['receipt'], 'message.read', 'receipt', (string)($record['message_id'] ?? ''), $eventId);
        } catch (\Exception $ignore) {
        }
        try {
            $cmdClientMsgNo = 'read-' . md5((string)$record['client_msg_no'] . '-' . $readerUid);
            $cmdChannelId = (int)$record['channel_type'] === (int)config('wukongim.channel_type_person', WukongIM::CHANNEL_TYPE_PERSON)
                ? (string)$record['from_uid']
                : (string)$record['channel_id'];
            $send = $im->sendCommandMessage($readerUid, $cmdChannelId, (int)$record['channel_type'], $payload, $cmdClientMsgNo);
            Db::name('wukongim_message_receipt')
                ->where('client_msg_no', $record['client_msg_no'])
                ->where('reader_uid', $readerUid)
                ->where('status', 1)
                ->update([
                    "event_client_msg_no" => (string)($send['client_msg_no'] ?? $cmdClientMsgNo),
                    "event_message_id" => (string)($send['message_id'] ?? ''),
                    "event_payload" => json_encode($payload, JSON_UNESCAPED_UNICODE),
                    "update_time" => $now,
                ]);
        } catch (\Exception $e) {
            if (strpos($e->getMessage(), 'client_msg_no已被其它消息内容占用') === false) {
                throw $e;
            }
            $queued = $im->queuedMessage($cmdClientMsgNo);
            if (!$queued) {
                throw $e;
            }
            Db::name('wukongim_message_receipt')
                ->where('client_msg_no', $record['client_msg_no'])
                ->where('reader_uid', $readerUid)
                ->where('status', 1)
                ->update([
                    "event_client_msg_no" => (string)($queued['client_msg_no'] ?? $cmdClientMsgNo),
                    "event_message_id" => (string)($queued['message_id'] ?? ''),
                    "event_payload" => json_encode($payload, JSON_UNESCAPED_UNICODE),
                    "update_time" => $now,
                ]);
        }
        return $status;
    }

    protected function recordMessageActionReceipt(array $record, array $operator, string $action, array $detail, string $clientMsgNo, WukongIM $im = null): array
    {
        $settings = $this->chatControl();
        if ($action === 'red_packet_received' && (int)$settings['red_packet_receipt_enabled'] !== 1) {
            return $this->receiptStatusForMessage((string)$record['client_msg_no'], $record);
        }
        if ($action === 'transfer_received' && (int)$settings['transfer_receipt_enabled'] !== 1) {
            return $this->receiptStatusForMessage((string)$record['client_msg_no'], $record);
        }

        $operatorUid = $this->wukongUid($operator['id']);
        $statusCode = $action === 'transfer_received' ? 3 : 2;
        $now = date('Y-m-d H:i:s');
        $receiptPayload = [
            "action" => $action,
            "operator_id" => (int)$operator['id'],
            "operator_uid" => $operatorUid,
            "operate_time" => time(),
        ] + $detail;

        $exists = Db::name('wukongim_message_receipt')
            ->where('client_msg_no', $record['client_msg_no'])
            ->where('reader_uid', $operatorUid)
            ->where('status', $statusCode)
            ->find();
        if (!$exists) {
            Db::name('wukongim_message_receipt')->insert([
                "appid" => $this->appid,
                "client_msg_no" => (string)$record['client_msg_no'],
                "message_id" => (string)($record['message_id'] ?? ''),
                "channel_id" => (string)$record['channel_id'],
                "channel_type" => (int)$record['channel_type'],
                "message_seq" => 0,
                "from_uid" => (string)$record['from_uid'],
                "reader_uid" => $operatorUid,
                "reader_id" => (int)$operator['id'],
                "status" => $statusCode,
                "event_payload" => json_encode($receiptPayload, JSON_UNESCAPED_UNICODE),
                "read_time" => $now,
                "create_time" => $now,
                "update_time" => $now,
            ]);
        }

        $cmdPayload = [
            "protocol" => "blin.chat.v1",
            "type" => WukongIM::CONTENT_TYPE_CMD,
            "content_type" => "cmd",
            "cmd" => $action . "_receipt",
            "scene" => (int)$record['channel_type'] === (int)config('wukongim.channel_type_group', WukongIM::CHANNEL_TYPE_GROUP) ? "group_chat" : "private_chat",
            "appid" => (int)$this->appid,
            "channel_id" => (string)$record['channel_id'],
            "channel_type" => (int)$record['channel_type'],
            "operator_id" => (int)$operator['id'],
            "operator_uid" => $operatorUid,
            "target_client_msg_no" => (string)$record['client_msg_no'],
            "target_message_id" => (string)($record['message_id'] ?? ''),
            "receipt" => $receiptPayload,
        ] + $this->chatDevicePayload();

        $im = $im ?: new WukongIM();
        try {
            $eventId = $action . '-' . (int)$operator['id'] . '-' . (string)$record['client_msg_no'];
            $im->appendMessageEvent((string)$record['channel_id'], (int)$record['channel_type'], (string)$record['from_uid'], (string)$record['client_msg_no'], $receiptPayload, 'message.' . str_replace('_', '.', $action), 'receipt', (string)($record['message_id'] ?? ''), $eventId);
        } catch (\Exception $ignore) {
        }

        $cmdClientMsgNo = $action . '-' . md5((string)$record['client_msg_no'] . '-' . $operatorUid);
        $cmdChannelId = (int)$record['channel_type'] === (int)config('wukongim.channel_type_person', WukongIM::CHANNEL_TYPE_PERSON)
            ? (string)$record['from_uid']
            : (string)$record['channel_id'];
        $send = $im->sendCommandMessage($operatorUid, $cmdChannelId, (int)$record['channel_type'], $cmdPayload, $cmdClientMsgNo);
        Db::name('wukongim_message_receipt')
            ->where('client_msg_no', $record['client_msg_no'])
            ->where('reader_uid', $operatorUid)
            ->where('status', $statusCode)
            ->update([
                "event_client_msg_no" => (string)($send['client_msg_no'] ?? $cmdClientMsgNo),
                "event_message_id" => (string)($send['message_id'] ?? ''),
                "event_payload" => json_encode($cmdPayload, JSON_UNESCAPED_UNICODE),
                "update_time" => $now,
            ]);

        return $this->receiptStatusForMessage((string)$record['client_msg_no'], $record);
    }

    protected function chatControl(): array
    {
        return ChatControl::get();
    }

    protected function privateHistorySyncEnabled(): bool
    {
        $settings = $this->chatControl();
        return (int)($settings['private_history_sync_enabled'] ?? 1) === 1;
    }

    protected function groupHistorySyncEnabled(): bool
    {
        $settings = $this->chatControl();
        return (int)($settings['group_history_sync_enabled'] ?? 1) === 1;
    }

    protected function historySyncPayload(): array
    {
        $private = $this->privateHistorySyncEnabled() ? 1 : 0;
        $group = $this->groupHistorySyncEnabled() ? 1 : 0;
        return [
            "server_history_sync_enabled" => ($private === 1 || $group === 1) ? 1 : 0,
            "private_history_sync_enabled" => $private,
            "group_history_sync_enabled" => $group,
        ];
    }

    protected function imageCaptchaKey(string $scene): string
    {
        return $this->appid . $scene . get_client_ip();
    }

    protected function assertImageCaptchaScene(string $scene, string $captcha, bool $clear = true): void
    {
        $captcha = trim($captcha);
        if ($captcha === '') {
            $this->json(0, "请先输入图片验证码");
        }
        if (!CaptchaService::check($this->imageCaptchaKey($scene), $captcha, $clear)) {
            $this->json(0, "图片验证码错误");
        }
    }

    protected function codeCaptchaSceneForType(string $type, bool $register = false): string
    {
        if ($register || $type === "2") {
            return "register";
        }
        return "security";
    }

    protected function readVerificationCodeCache(string $prefix, string $target): array
    {
        $targetCache = $target !== "" ? Cache::get($this->appid . $prefix . $target) : null;
        if ($targetCache) {
            return (array)$targetCache;
        }
        $ipCache = Cache::get($this->appid . $prefix . get_client_ip());
        return $ipCache ? (array)$ipCache : [];
    }

    protected function writeVerificationCodeCache(string $prefix, string $target, array $payload, int $ttl): void
    {
        if ($target !== "") {
            Cache::set($this->appid . $prefix . $target, $payload, $ttl);
        }
        Cache::set($this->appid . $prefix . get_client_ip(), $payload, $ttl);
    }

    protected function deleteVerificationCodeCache(string $prefix, string $target = ""): void
    {
        if ($target !== "") {
            Cache::delete($this->appid . $prefix . $target);
        }
        Cache::delete($this->appid . $prefix . get_client_ip());
    }

    protected function emptyHistoryResponse(): array
    {
        return [
            "list" => [],
            "pagecount" => (int)$this->page,
            "current_number" => (int)$this->page,
            "more" => 0,
        ];
    }

    protected function syncGatewayPresenceTargetsForUserAndFriends(int $userId): void
    {
        if ($userId <= 0) {
            return;
        }
        $gateway = new GatewayStream();
        $gateway->syncPresenceTargetsForUser((int)$this->appid, $userId);
        $rows = Db::name("chat_friend")
            ->where("appid", $this->appid)
            ->where("status", 1)
            ->where(function ($query) use ($userId) {
                $query->where("user_id", $userId)->whereOr("friend_id", $userId);
            })
            ->field("user_id,friend_id")
            ->select()
            ->toArray();
        foreach ($rows as $row) {
            $friendId = (int)$row["user_id"] === $userId ? (int)$row["friend_id"] : (int)$row["user_id"];
            if ($friendId > 0) {
                $gateway->syncPresenceTargetsForUser((int)$this->appid, $friendId);
            }
        }
    }

    protected function queueRecordToWukongMessage(array $record): array
    {
        $sentTime = $this->normalizedChatTimestamp($record["sent_time"] ?? $record["update_time"] ?? $record["create_time"] ?? null);
        $payload = (string)($record["payload_base64"] ?? "");
        if ($payload === "" && (string)($record["payload_text"] ?? "") !== "") {
            $payload = base64_encode((string)$record["payload_text"]);
        }
        return [
            "message_id" => (string)($record["message_id"] ?? ""),
            "message_idstr" => (string)($record["message_id"] ?? ""),
            "client_msg_no" => (string)($record["client_msg_no"] ?? ""),
            "message_seq" => (int)($record["message_seq"] ?? 0),
            "from_uid" => (string)($record["from_uid"] ?? ""),
            "channel_id" => (string)($record["channel_id"] ?? ""),
            "channel_type" => (int)($record["channel_type"] ?? 0),
            "timestamp" => $sentTime > 0 ? $sentTime : time(),
            "payload" => $payload,
        ];
    }

    protected function nextHistoryStartMessageSeq(array $messages): int
    {
        $minSeq = 0;
        foreach ($messages as $message) {
            $seq = (int)($message["message_seq"] ?? 0);
            if ($seq <= 0) {
                continue;
            }
            $minSeq = $minSeq === 0 ? $seq : min($minSeq, $seq);
        }
        return $minSeq > 1 ? $minSeq - 1 : 0;
    }

    protected function queueHistoryPage($query, int $limit, int $startMessageSeq): array
    {
        $limit = min(max(1, $limit), 200);
        if ($startMessageSeq > 0) {
            $query->where("message_seq", "<=", $startMessageSeq);
        }
        $rows = $query
            ->where("message_seq", ">", 0)
            ->order("message_seq", "desc")
            ->limit($limit + 1)
            ->select()
            ->toArray();
        $more = count($rows) > $limit ? 1 : 0;
        if ($more) {
            $rows = array_slice($rows, 0, $limit);
        }
        $messages = array_map(function ($row) {
            return $this->queueRecordToWukongMessage($row);
        }, $rows);
        return [
            "rows" => $rows,
            "messages" => $messages,
            "more" => $more,
            "next_start_message_seq" => $more ? $this->nextHistoryStartMessageSeq($messages) : 0,
        ];
    }

    protected function privateQueueHistoryPage(array $user, array $receiver, int $limit, int $startMessageSeq): array
    {
        $channelType = (int)config('wukongim.channel_type_person', WukongIM::CHANNEL_TYPE_PERSON);
        $selfUid = $this->wukongUid($user["id"]);
        $peerUid = $this->wukongUid($receiver["id"]);
        $query = Db::name("wukongim_message_queue")
            ->where("appid", $this->appid)
            ->where("status", WukongIM::QUEUE_SENT)
            ->where("channel_type", $channelType)
            ->where("content_type", "<>", "cmd")
            ->where(function ($query) use ($selfUid, $peerUid) {
                $query->where(function ($q) use ($selfUid, $peerUid) {
                    $q->where("from_uid", $selfUid)->where("channel_id", $peerUid);
                })->whereOr(function ($q) use ($selfUid, $peerUid) {
                    $q->where("from_uid", $peerUid)->where("channel_id", $selfUid);
                });
            });
        return $this->queueHistoryPage($query, $limit, $startMessageSeq);
    }

    protected function groupQueueHistoryPage(array $group, int $limit, int $startMessageSeq): array
    {
        $channelType = (int)config('wukongim.channel_type_group', WukongIM::CHANNEL_TYPE_GROUP);
        $query = Db::name("wukongim_message_queue")
            ->where("appid", $this->appid)
            ->where("status", WukongIM::QUEUE_SENT)
            ->where("channel_type", $channelType)
            ->where("content_type", "<>", "cmd")
            ->where("channel_id", (string)$group["channel_id"]);
        return $this->queueHistoryPage($query, $limit, $startMessageSeq);
    }

    protected function appendStoredMessageConversations(array $user, array $result, int $limit): array
    {
        $privateType = (int)config('wukongim.channel_type_person', WukongIM::CHANNEL_TYPE_PERSON);
        $groupType = (int)config('wukongim.channel_type_group', WukongIM::CHANNEL_TYPE_GROUP);
        $existing = [];
        foreach ($result as $item) {
            $key = (int)($item["channel_type"] ?? 0) . ":" . (string)($item["channel_id"] ?? "");
            $existing[$key] = true;
        }
        if ($this->privateHistorySyncEnabled()) {
            $result = $this->appendPrivateStoredMessageConversations($user, $result, $existing, $privateType, $limit);
        }
        if ($this->groupHistorySyncEnabled()) {
            $result = $this->appendGroupStoredMessageConversations($user, $result, $existing, $groupType, $limit);
        }
        usort($result, function ($a, $b) {
            return $this->normalizedChatTimestamp($b["msg_time"] ?? null) <=> $this->normalizedChatTimestamp($a["msg_time"] ?? null);
        });
        return array_slice($result, 0, max(1, $limit));
    }

    protected function appendPrivateStoredMessageConversations(array $user, array $result, array &$existing, int $channelType, int $limit): array
    {
        $selfUid = $this->wukongUid($user["id"]);
        $rows = Db::name("wukongim_message_queue")
            ->where("appid", $this->appid)
            ->where("status", WukongIM::QUEUE_SENT)
            ->where("channel_type", $channelType)
            ->where(function ($query) use ($selfUid) {
                $query->where("from_uid", $selfUid)->whereOr("channel_id", $selfUid);
            })
            ->order("id", "desc")
            ->limit(max(500, $limit * 12))
            ->select()
            ->toArray();
        foreach ($rows as $row) {
            $message = $this->queueRecordToWukongMessage($row);
            if (!$this->isDisplayableWukongChatMessage($message)) {
                continue;
            }
            $peerUid = (string)$row["from_uid"] === $selfUid ? (string)$row["channel_id"] : (string)$row["from_uid"];
            $key = $channelType . ":" . $peerUid;
            if (isset($existing[$key])) {
                continue;
            }
            $uidInfo = WukongIM::parseUid($peerUid);
            if (!$uidInfo || (int)$uidInfo["appid"] !== (int)$this->appid) {
                continue;
            }
            $messageData = $this->wukongPayloadToMessage($message);
            $hiddenClientMsgNos = $this->hiddenChatClientMsgNos((int)$user["id"], $peerUid, $channelType, [$message]);
            $clearBoundary = $this->chatClearBoundaryTimestamp((int)$user["id"], $peerUid, $channelType);
            if (!$this->isChatMessageVisibleForUser((int)$user["id"], $peerUid, $channelType, $message, $messageData, $hiddenClientMsgNos, $clearBoundary)) {
                continue;
            }
            $peer = Db::name("user")->where("appid", $this->appid)->where("id", (int)$uidInfo["user_id"])->find();
            if (!$peer) {
                continue;
            }
            $item = $this->formatImUserProfile($peer);
            $item["conversation_type"] = "private";
            $item["msg_time"] = $messageData["create_time"];
            $item["content"] = $messageData["content"];
            $item["image_path"] = $messageData["image_path"];
            $item["content_type"] = $messageData["content_type"];
            $item["asset_type"] = $messageData["asset_type"];
            $item["payload"] = $messageData["payload"];
            $item["unread_quantity"] = 0;
            $item["channel_id"] = $peerUid;
            $item["channel_type"] = $channelType;
            $item["last_msg_seq"] = (int)$message["message_seq"];
            $item["last_client_msg_no"] = (string)$message["client_msg_no"];
            $result[] = $item;
            $existing[$key] = true;
        }
        return $result;
    }

    protected function appendGroupStoredMessageConversations(array $user, array $result, array &$existing, int $channelType, int $limit): array
    {
        $memberRows = Db::name("chat_group_member")
            ->where("appid", $this->appid)
            ->where("user_id", (int)$user["id"])
            ->where("status", 1)
            ->select()
            ->toArray();
        if (!$memberRows) {
            return $result;
        }
        $groups = [];
        foreach ($memberRows as $member) {
            $group = Db::name("chat_group")
                ->where("appid", $this->appid)
                ->where("id", (int)$member["group_id"])
                ->where("status", 1)
                ->find();
            if ($group) {
                $groups[(string)$group["channel_id"]] = [
                    "group" => $group,
                    "member" => $member,
                ];
            }
        }
        if (!$groups) {
            return $result;
        }
        $rows = Db::name("wukongim_message_queue")
            ->where("appid", $this->appid)
            ->where("status", WukongIM::QUEUE_SENT)
            ->where("channel_type", $channelType)
            ->whereIn("channel_id", array_keys($groups))
            ->order("id", "desc")
            ->limit(max(500, $limit * 12))
            ->select()
            ->toArray();
        foreach ($rows as $row) {
            $channelId = (string)$row["channel_id"];
            $key = $channelType . ":" . $channelId;
            if (isset($existing[$key]) || empty($groups[$channelId])) {
                continue;
            }
            $message = $this->queueRecordToWukongMessage($row);
            if (!$this->isDisplayableWukongChatMessage($message)) {
                continue;
            }
            $messageData = $this->wukongPayloadToMessage($message);
            if (!$this->isGroupMessageVisibleForMember($groups[$channelId]["member"], $message, $messageData)) {
                continue;
            }
            $hiddenClientMsgNos = $this->hiddenChatClientMsgNos((int)$user["id"], $channelId, $channelType, [$message]);
            $clearBoundary = $this->chatClearBoundaryTimestamp((int)$user["id"], $channelId, $channelType);
            if (!$this->isChatMessageVisibleForUser((int)$user["id"], $channelId, $channelType, $message, $messageData, $hiddenClientMsgNos, $clearBoundary)) {
                continue;
            }
            $item = $this->formatChatGroup($groups[$channelId]["group"]);
            $item["conversation_type"] = "group";
            $item["msg_time"] = $messageData["create_time"];
            $item["content"] = $messageData["content"];
            $item["image_path"] = $messageData["image_path"];
            $item["content_type"] = $messageData["content_type"];
            $item["asset_type"] = $messageData["asset_type"];
            $item["payload"] = $messageData["payload"];
            $item["unread_quantity"] = 0;
            $item["channel_id"] = $channelId;
            $item["channel_type"] = $channelType;
            $item["last_msg_seq"] = (int)$message["message_seq"];
            $item["last_client_msg_no"] = (string)$message["client_msg_no"];
            $result[] = $item;
            $existing[$key] = true;
        }
        return $result;
    }

    protected function chatHistoryClientMsgNoSet(array $result): array
    {
        $set = [];
        foreach ($result as $item) {
            $clientMsgNo = (string)($item["message"]["client_msg_no"] ?? $item["raw"]["client_msg_no"] ?? "");
            if ($clientMsgNo !== "") {
                $set[$clientMsgNo] = true;
            }
        }
        return $set;
    }

    protected function sortChatHistoryResult(array $result, int $limit): array
    {
        usort($result, function ($a, $b) {
            $seqA = (int)($a["message"]["message_seq"] ?? $a["raw"]["message_seq"] ?? 0);
            $seqB = (int)($b["message"]["message_seq"] ?? $b["raw"]["message_seq"] ?? 0);
            if ($seqA > 0 && $seqB > 0 && $seqA !== $seqB) {
                return $seqA <=> $seqB;
            }
            return $this->normalizedChatTimestamp($a["message"]["create_time"] ?? null) <=> $this->normalizedChatTimestamp($b["message"]["create_time"] ?? null);
        });
        if (count($result) > $limit) {
            $result = array_slice($result, -$limit);
        }
        return $result;
    }

    protected function appendPrivateStoredMessages(array $user, array $receiver, array $result, array &$users, int &$maxMessageSeq, WukongIM $im, int $limit): array
    {
        $channelType = (int)config('wukongim.channel_type_person', WukongIM::CHANNEL_TYPE_PERSON);
        $selfUid = $this->wukongUid($user["id"]);
        $peerUid = $this->wukongUid($receiver["id"]);
        $existing = $this->chatHistoryClientMsgNoSet($result);
        $rows = Db::name("wukongim_message_queue")
            ->where("appid", $this->appid)
            ->where("status", WukongIM::QUEUE_SENT)
            ->where("channel_type", $channelType)
            ->where(function ($query) use ($selfUid, $peerUid) {
                $query->where(function ($q) use ($selfUid, $peerUid) {
                    $q->where("from_uid", $selfUid)->where("channel_id", $peerUid);
                })->whereOr(function ($q) use ($selfUid, $peerUid) {
                    $q->where("from_uid", $peerUid)->where("channel_id", $selfUid);
                });
            })
            ->order("id", "desc")
            ->limit(max(100, $limit * 4))
            ->select()
            ->toArray();
        $channelId = $peerUid;
        foreach ($rows as $row) {
            $clientMsgNo = (string)($row["client_msg_no"] ?? "");
            if ($clientMsgNo === "" || isset($existing[$clientMsgNo])) {
                continue;
            }
            $message = $this->queueRecordToWukongMessage($row);
            if (!$this->isDisplayableWukongChatMessage($message)) {
                continue;
            }
            $messageData = $this->wukongPayloadToMessage($message);
            $hiddenClientMsgNos = $this->hiddenChatClientMsgNos((int)$user["id"], $channelId, $channelType, [$message]);
            $clearBoundary = $this->chatClearBoundaryTimestamp((int)$user["id"], $channelId, $channelType);
            if (!$this->isChatMessageVisibleForUser((int)$user["id"], $channelId, $channelType, $message, $messageData, $hiddenClientMsgNos, $clearBoundary)) {
                continue;
            }
            $fromUid = (string)$row["from_uid"];
            $fromUser = $users[$fromUid] ?? null;
            if (!$fromUser) {
                $uidInfo = WukongIM::parseUid($fromUid);
                if (!$uidInfo || (int)$uidInfo["appid"] !== (int)$this->appid) {
                    continue;
                }
                $fromUser = Db::name("user")->where("id", (int)$uidInfo["user_id"])->where("appid", $this->appid)->find();
                if (!$fromUser) {
                    continue;
                }
                $users[$fromUid] = $fromUser;
            }
            try {
                $this->recordMessageReadReceipt($row, $user, (int)$message["message_seq"], $im);
                $this->appendReceiptStatus($messageData);
            } catch (\Exception $e) {
                $this->json(0, $e->getMessage());
            }
            $result[] = [
                "fromUser" => $this->formatChatUser($fromUser),
                "message" => $messageData,
                "raw" => [
                    "message_id" => $message["message_id"] ?? "",
                    "message_idstr" => $message["message_idstr"] ?? "",
                    "client_msg_no" => $clientMsgNo,
                    "message_seq" => $message["message_seq"] ?? 0,
                    "channel_id" => $message["channel_id"] ?? "",
                    "channel_type" => $message["channel_type"] ?? $channelType,
                ],
            ];
            $existing[$clientMsgNo] = true;
            $maxMessageSeq = max($maxMessageSeq, (int)($message["message_seq"] ?? 0));
        }
        return $this->sortChatHistoryResult($result, $limit);
    }

    protected function appendGroupStoredMessages(array $group, array $member, array $result, array &$users, int &$maxMessageSeq, WukongIM $im, int $limit): array
    {
        $channelType = (int)config('wukongim.channel_type_group', WukongIM::CHANNEL_TYPE_GROUP);
        $channelId = (string)$group["channel_id"];
        $existing = $this->chatHistoryClientMsgNoSet($result);
        $rows = Db::name("wukongim_message_queue")
            ->where("appid", $this->appid)
            ->where("status", WukongIM::QUEUE_SENT)
            ->where("channel_type", $channelType)
            ->where("channel_id", $channelId)
            ->order("id", "desc")
            ->limit(max(100, $limit * 4))
            ->select()
            ->toArray();
        foreach ($rows as $row) {
            $clientMsgNo = (string)($row["client_msg_no"] ?? "");
            if ($clientMsgNo === "" || isset($existing[$clientMsgNo])) {
                continue;
            }
            $message = $this->queueRecordToWukongMessage($row);
            if (!$this->isDisplayableWukongChatMessage($message)) {
                continue;
            }
            $messageData = $this->wukongPayloadToMessage($message);
            if (!$this->isGroupMessageVisibleForMember($member, $message, $messageData)) {
                continue;
            }
            $hiddenClientMsgNos = $this->hiddenChatClientMsgNos((int)$this->user_info["id"], $channelId, $channelType, [$message]);
            $clearBoundary = $this->chatClearBoundaryTimestamp((int)$this->user_info["id"], $channelId, $channelType);
            if (!$this->isChatMessageVisibleForUser((int)$this->user_info["id"], $channelId, $channelType, $message, $messageData, $hiddenClientMsgNos, $clearBoundary)) {
                continue;
            }
            $fromUid = (string)$row["from_uid"];
            $uidInfo = WukongIM::parseUid($fromUid);
            if (!$uidInfo || (int)$uidInfo["appid"] !== (int)$this->appid) {
                continue;
            }
            if (!isset($users[$fromUid])) {
                $users[$fromUid] = Db::name("user")->where("id", (int)$uidInfo["user_id"])->where("appid", $this->appid)->find();
            }
            if (!$users[$fromUid]) {
                continue;
            }
            try {
                $this->recordMessageReadReceipt($row, $this->user_info, (int)$message["message_seq"], $im);
                $this->appendReceiptStatus($messageData);
            } catch (\Exception $e) {
                $this->json(0, $e->getMessage());
            }
            $result[] = [
                "fromUser" => $this->formatChatUser($users[$fromUid]),
                "group" => $this->formatChatGroup($group),
                "message" => $messageData,
                "raw" => [
                    "message_id" => $message["message_id"] ?? "",
                    "message_idstr" => $message["message_idstr"] ?? "",
                    "client_msg_no" => $clientMsgNo,
                    "message_seq" => $message["message_seq"] ?? 0,
                    "channel_id" => $message["channel_id"] ?? "",
                    "channel_type" => $message["channel_type"] ?? $channelType,
                ],
            ];
            $existing[$clientMsgNo] = true;
            $maxMessageSeq = max($maxMessageSeq, (int)($message["message_seq"] ?? 0));
        }
        return $this->sortChatHistoryResult($result, $limit);
    }

    protected function chatGroupMemberJoinTimestamp(array $member): int
    {
        foreach (["join_time", "create_time"] as $field) {
            $time = strtotime((string)($member[$field] ?? ""));
            if ($time > 0) {
                return $time;
            }
        }
        return 0;
    }

    protected function normalizedChatTimestamp($value): int
    {
        if (is_numeric($value)) {
            $time = (int)$value;
            if ($time > 1000000000000) {
                $time = (int)floor($time / 1000);
            }
            return $time > 0 ? $time : 0;
        }
        $time = strtotime((string)$value);
        return $time > 0 ? $time : 0;
    }

    protected function wukongMessageTimestamp(array $message, array $messageData = []): int
    {
        foreach (["timestamp", "message_time", "messageTime", "client_timestamp", "create_time"] as $field) {
            $time = $this->normalizedChatTimestamp($message[$field] ?? null);
            if ($time > 0) {
                return $time;
            }
        }
        $payload = $this->wukongMessagePayload($message);
        foreach (["create_time", "client_timestamp", "timestamp"] as $field) {
            $time = $this->normalizedChatTimestamp($payload[$field] ?? null);
            if ($time > 0) {
                return $time;
            }
        }
        return 0;
    }

    protected function chatClearBoundaryTimestamp(int $userId, string $channelId, int $channelType): int
    {
        $allTime = Db::name("chat_message_visibility")
            ->where("appid", $this->appid)
            ->where("user_id", $userId)
            ->where("scope", "all")
            ->max("hide_before_time");
        $channelTime = Db::name("chat_message_visibility")
            ->where("appid", $this->appid)
            ->where("user_id", $userId)
            ->where("scope", "conversation")
            ->where("channel_id", $channelId)
            ->where("channel_type", $channelType)
            ->max("hide_before_time");
        $peerTime = null;
        if ($channelType === (int)config('wukongim.channel_type_person', WukongIM::CHANNEL_TYPE_PERSON)) {
            $uidInfo = WukongIM::parseUid($channelId);
            if ($uidInfo && (int)$uidInfo["appid"] === (int)$this->appid) {
                $peerTime = Db::name("chat_message_visibility")
                    ->where("appid", $this->appid)
                    ->where("user_id", $userId)
                    ->where("scope", "conversation")
                    ->where("peer_user_id", (int)$uidInfo["user_id"])
                    ->where("channel_type", $channelType)
                    ->max("hide_before_time");
            }
        }
        return max(
            $this->normalizedChatTimestamp($allTime),
            $this->normalizedChatTimestamp($channelTime),
            $this->normalizedChatTimestamp($peerTime)
        );
    }

    protected function hiddenChatClientMsgNos(int $userId, string $channelId, int $channelType, array $messages): array
    {
        $clientMsgNos = [];
        foreach ($messages as $message) {
            if (!is_array($message)) {
                continue;
            }
            $clientMsgNo = (string)($message["client_msg_no"] ?? "");
            if ($clientMsgNo !== "") {
                $clientMsgNos[$clientMsgNo] = $clientMsgNo;
            }
        }
        if (!$clientMsgNos) {
            return [];
        }
        $rows = Db::name("chat_message_visibility")
            ->where("appid", $this->appid)
            ->where("user_id", $userId)
            ->where("scope", "message")
            ->where("channel_id", $channelId)
            ->where("channel_type", $channelType)
            ->whereIn("client_msg_no", array_values($clientMsgNos))
            ->column("client_msg_no");
        if ($channelType === (int)config('wukongim.channel_type_person', WukongIM::CHANNEL_TYPE_PERSON)) {
            $uidInfo = WukongIM::parseUid($channelId);
            if ($uidInfo && (int)$uidInfo["appid"] === (int)$this->appid) {
                $peerRows = Db::name("chat_message_visibility")
                    ->where("appid", $this->appid)
                    ->where("user_id", $userId)
                    ->where("scope", "message")
                    ->where("peer_user_id", (int)$uidInfo["user_id"])
                    ->where("channel_type", $channelType)
                    ->whereIn("client_msg_no", array_values($clientMsgNos))
                    ->column("client_msg_no");
                $rows = array_merge($rows, $peerRows);
            }
        }
        $hidden = [];
        foreach ($rows as $clientMsgNo) {
            $hidden[(string)$clientMsgNo] = true;
        }
        return $hidden;
    }

    protected function privateConversationPeerUid(string $currentUid, string $channelId, array $messages): string
    {
        foreach ($messages as $message) {
            if (!is_array($message)) {
                continue;
            }
            $payload = $this->wukongMessagePayload($message);
            $candidates = [
                (string)($payload["sender_uid"] ?? ""),
                (string)($message["from_uid"] ?? ""),
                (string)($payload["receiver_uid"] ?? ""),
                $channelId,
            ];
            foreach ($candidates as $uid) {
                $uid = trim($uid);
                if ($uid === "" || $uid === $currentUid) {
                    continue;
                }
                $uidInfo = WukongIM::parseUid($uid);
                if ($uidInfo && (int)$uidInfo["appid"] === (int)$this->appid) {
                    return $uid;
                }
            }
        }
        return $channelId === $currentUid ? "" : $channelId;
    }

    protected function isChatMessageVisibleForUser(
        int $userId,
        string $channelId,
        int $channelType,
        array $message,
        array $messageData = [],
        array $hiddenClientMsgNos = [],
        int $clearBoundary = 0
    ): bool {
        $clientMsgNo = (string)($message["client_msg_no"] ?? ($messageData["client_msg_no"] ?? ""));
        if ($clientMsgNo !== "" && isset($hiddenClientMsgNos[$clientMsgNo])) {
            return false;
        }
        if ($clearBoundary <= 0) {
            return true;
        }
        $messageTime = $this->wukongMessageTimestamp($message, $messageData);
        if ($messageTime <= 0 && $clientMsgNo !== "") {
            $record = Db::name("wukongim_message_queue")
                ->where("appid", $this->appid)
                ->where("client_msg_no", $clientMsgNo)
                ->find();
            if ($record) {
                $messageTime = $this->normalizedChatTimestamp($record["sent_time"] ?? $record["create_time"] ?? null);
            }
        }
        return $messageTime > $clearBoundary;
    }

    protected function upsertChatVisibility(array $where, array $data): void
    {
        $now = date("Y-m-d H:i:s");
        $row = Db::name("chat_message_visibility")->where($where)->find();
        if ($row) {
            Db::name("chat_message_visibility")->where("id", $row["id"])->update($data + [
                "update_time" => $now,
            ]);
            return;
        }
        Db::name("chat_message_visibility")->insert($where + $data + [
            "create_time" => $now,
            "update_time" => $now,
        ]);
    }

    protected function hideChatConversationForUser(
        int $userId,
        string $channelId,
        int $channelType,
        int $peerUserId = 0,
        int $groupId = 0,
        string $clearTime = ""
    ): void {
        $this->upsertChatVisibility([
            "appid" => $this->appid,
            "user_id" => $userId,
            "scope" => "conversation",
            "channel_id" => $channelId,
            "channel_type" => $channelType,
            "client_msg_no" => "",
        ], [
            "peer_user_id" => $peerUserId,
            "group_id" => $groupId,
            "message_seq" => 0,
            "hide_before_time" => $clearTime !== "" ? $clearTime : date("Y-m-d H:i:s"),
        ]);
    }

    protected function hideAllChatConversationsForUser(int $userId, string $clearTime = ""): void
    {
        $this->upsertChatVisibility([
            "appid" => $this->appid,
            "user_id" => $userId,
            "scope" => "all",
            "channel_id" => "*",
            "channel_type" => 0,
            "client_msg_no" => "",
        ], [
            "peer_user_id" => 0,
            "group_id" => 0,
            "message_seq" => 0,
            "hide_before_time" => $clearTime !== "" ? $clearTime : date("Y-m-d H:i:s"),
        ]);
    }

    protected function hideChatMessageForUser(int $userId, array $record): void
    {
        $clientMsgNo = (string)($record["client_msg_no"] ?? "");
        if ($clientMsgNo === "") {
            $this->json(0, "消息标识不能为空");
        }
        $channelId = (string)$record["channel_id"];
        $channelType = (int)$record["channel_type"];
        $peerUserId = 0;
        $groupId = 0;
        if ($channelType === (int)config('wukongim.channel_type_person', WukongIM::CHANNEL_TYPE_PERSON)) {
            $userUid = $this->wukongUid($userId);
            $peerUid = (string)$record["from_uid"] === $userUid ? (string)$record["channel_id"] : (string)$record["from_uid"];
            $channelId = $peerUid;
            $uidInfo = WukongIM::parseUid($peerUid);
            $peerUserId = (int)($uidInfo["user_id"] ?? 0);
        } else {
            $group = Db::name("chat_group")->where("appid", $this->appid)->where("channel_id", $channelId)->find();
            $groupId = (int)($group["id"] ?? 0);
        }
        $this->upsertChatVisibility([
            "appid" => $this->appid,
            "user_id" => $userId,
            "scope" => "message",
            "channel_id" => $channelId,
            "channel_type" => $channelType,
            "client_msg_no" => $clientMsgNo,
        ], [
            "peer_user_id" => $peerUserId,
            "group_id" => $groupId,
            "message_seq" => (int)($record["message_seq"] ?? 0),
            "hide_before_time" => $record["sent_time"] ?: ($record["create_time"] ?? date("Y-m-d H:i:s")),
        ]);
    }

    protected function privateChatParticipantIdsByRecord(array $record): array
    {
        $ids = [];
        foreach ([(string)($record["from_uid"] ?? ""), (string)($record["channel_id"] ?? "")] as $uid) {
            $uidInfo = WukongIM::parseUid($uid);
            if ($uidInfo && (int)$uidInfo["appid"] === (int)$this->appid) {
                $ids[(int)$uidInfo["user_id"]] = (int)$uidInfo["user_id"];
            }
        }
        return array_values($ids);
    }

    protected function hideChatMessageForRecordParticipants(array $record): void
    {
        $channelType = (int)$record["channel_type"];
        if ($channelType === (int)config('wukongim.channel_type_person', WukongIM::CHANNEL_TYPE_PERSON)) {
            foreach ($this->privateChatParticipantIdsByRecord($record) as $userId) {
                $this->hideChatMessageForUser($userId, $record);
            }
            return;
        }

        $group = Db::name("chat_group")
            ->where("appid", $this->appid)
            ->where("channel_id", (string)$record["channel_id"])
            ->where("status", 1)
            ->find();
        if (!$group) {
            return;
        }
        $memberIds = Db::name("chat_group_member")
            ->where("appid", $this->appid)
            ->where("group_id", (int)$group["id"])
            ->where("status", 1)
            ->column("user_id");
        foreach ($memberIds as $userId) {
            $this->hideChatMessageForUser((int)$userId, $record);
        }
    }

    protected function hideBurnAfterReadMessage(array $record, array $reader): void
    {
        $this->hideChatMessageForUser((int)$reader["id"], $record);
        if ((int)$record["channel_type"] !== (int)config('wukongim.channel_type_person', WukongIM::CHANNEL_TYPE_PERSON)) {
            return;
        }
        foreach ($this->privateChatParticipantIdsByRecord($record) as $userId) {
            if ($userId !== (int)$reader["id"]) {
                $this->hideChatMessageForUser($userId, $record);
            }
        }
    }

    protected function assertCanHideChatRecordForUser(array $record, array $user): void
    {
        $userUid = $this->wukongUid($user["id"]);
        $channelType = (int)$record["channel_type"];
        if ($channelType === (int)config('wukongim.channel_type_group', WukongIM::CHANNEL_TYPE_GROUP)) {
            $group = Db::name("chat_group")
                ->where("appid", $this->appid)
                ->where("channel_id", $record["channel_id"])
                ->where("status", 1)
                ->find();
            if (!$group) {
                $this->json(0, "群聊不存在");
            }
            try {
                $this->assertGroupMember($group, $user);
            } catch (\Exception $e) {
                $this->json(0, $e->getMessage());
            }
            return;
        }
        if ((string)$record["from_uid"] !== $userUid && (string)$record["channel_id"] !== $userUid) {
            $this->json(0, "无权操作该消息");
        }
    }

    protected function deleteWukongConversationsForUser(string $uid, int $limit = 200): array
    {
        $deleted = 0;
        $failed = 0;
        $im = new WukongIM();
        $list = $im->syncConversations($uid, 1, $limit, 5);
        foreach ($list as $conversation) {
            $channelId = (string)($conversation["channel_id"] ?? "");
            $channelType = (int)($conversation["channel_type"] ?? 0);
            if ($channelId === "" || $channelType <= 0) {
                continue;
            }
            try {
                $im->deleteConversation($uid, $channelId, $channelType);
                $deleted++;
            } catch (\Exception $e) {
                $failed++;
            }
        }
        return [
            "deleted" => $deleted,
            "failed" => $failed,
        ];
    }

    protected function isGroupMessageVisibleForMember(array $member, array $message, array $messageData = []): bool
    {
        $joinTime = $this->chatGroupMemberJoinTimestamp($member);
        if ($joinTime <= 0) {
            return true;
        }
        $messageTime = $this->wukongMessageTimestamp($message, $messageData);
        if ($messageTime > 0) {
            return $messageTime >= $joinTime;
        }
        $clientMsgNo = (string)($message["client_msg_no"] ?? ($messageData["client_msg_no"] ?? ""));
        if ($clientMsgNo === "") {
            return false;
        }
        $record = Db::name('wukongim_message_queue')->where('client_msg_no', $clientMsgNo)->find();
        if (!$record) {
            return false;
        }
        $recordTime = $this->normalizedChatTimestamp($record['sent_time'] ?? $record['create_time'] ?? null);
        return $recordTime > 0 && $recordTime >= $joinTime;
    }

    protected function appendBurnAfterReadPayload(array &$payload, array $settings, bool $group = false): void
    {
        $burn = $this->chatInput('burn_after_read', '');
        if ($burn === '' && $this->chatInput('burn_after_read_seconds', '') === '') {
            return;
        }
        if ((int)$burn !== 1 && $this->chatInput('burn_after_read_seconds', '') === '') {
            return;
        }
        if ((int)$settings['burn_after_read_enabled'] !== 1) {
            $this->json(0, '阅后即焚已关闭');
        }
        if ($group && (int)$settings['burn_after_read_allow_group'] !== 1) {
            $this->json(0, '群聊阅后即焚已关闭');
        }
        $maxSeconds = max(1, (int)$settings['burn_after_read_max_seconds']);
        $seconds = (int)$this->chatInput('burn_after_read_seconds', (int)$settings['burn_after_read_default_seconds']);
        $seconds = max(1, min($maxSeconds, $seconds));
        $payload['burn_after_read'] = [
            'enabled' => true,
            'seconds' => $seconds,
            'read_destroy' => true,
        ];
    }

    protected function queueRecordByClientMsgNo(string $clientMsgNo): array
    {
        $record = Db::name('wukongim_message_queue')->where('client_msg_no', $clientMsgNo)->find();
        if (!$record) {
            $this->json(0, '消息不存在');
        }
        if ((int)$record['appid'] !== (int)$this->appid) {
            $this->json(0, '消息不存在');
        }
        return $record;
    }

    protected function assertCanRecallQueueRecord(array $record, array $settings): void
    {
        if ((int)$settings['recall_enabled'] !== 1) {
            $this->json(0, '消息撤回已关闭');
        }
        $fromUid = $this->wukongUid($this->user_info['id']);
        $isSender = (string)$record['from_uid'] === $fromUid;
        $isGroupManager = false;
        if ((int)$record['channel_type'] === (int)config('wukongim.channel_type_group', WukongIM::CHANNEL_TYPE_GROUP)) {
            $group = Db::name('chat_group')->where('appid', $this->appid)->where('channel_id', $record['channel_id'])->find();
            if ($group) {
                $member = Db::name('chat_group_member')
                    ->where('appid', $this->appid)
                    ->where('group_id', $group['id'])
                    ->where('user_id', $this->user_info['id'])
                    ->where('status', 1)
                    ->find();
                $isGroupManager = $member && in_array((int)$member['role'], [1, 2], true);
            }
        }
        if (!$isSender && !$isGroupManager) {
            $this->json(0, '无权撤回该消息');
        }
        $limit = (int)$settings['recall_time_limit'];
        if ($limit > 0 && !$isGroupManager) {
            $sentTime = strtotime((string)($record['sent_time'] ?: $record['create_time']));
            if ($sentTime > 0 && time() - $sentTime > $limit) {
                $this->json(0, '消息已超过可撤回时间');
            }
        }
    }

    protected function formatChatGroup(array $group): array
    {
        return [
            "id" => (int)$group["id"],
            "group_id" => (int)$group["id"],
            "appid" => (int)$group["appid"],
            "channel_id" => (string)$group["channel_id"],
            "name" => (string)$group["name"],
            "avatar" => (string)($group["avatar"] ?? ""),
            "owner_id" => (int)$group["owner_id"],
            "notice" => (string)($group["notice"] ?? ""),
            "member_count" => (int)($group["member_count"] ?? 0),
            "status" => (int)$group["status"],
            "create_time" => (string)($group["create_time"] ?? ""),
            "update_time" => (string)($group["update_time"] ?? ""),
        ];
    }

    protected function chatMemberIds($value, int $mustInclude = 0): array
    {
        if (is_array($value)) {
            $source = $value;
        } else {
            $text = trim((string)$value);
            $decoded = $text !== '' ? json_decode($text, true) : null;
            $source = is_array($decoded) ? $decoded : preg_split('/[,\s]+/', $text);
        }
        $ids = [];
        foreach ((array)$source as $id) {
            $id = (int)$id;
            if ($id > 0) {
                $ids[$id] = $id;
            }
        }
        if ($mustInclude > 0) {
            $ids[$mustInclude] = $mustInclude;
        }
        return array_values($ids);
    }

    protected function assertGroupMember(array $group, array $user, bool $manager = false): array
    {
        $member = Db::name("chat_group_member")
            ->where("appid", $this->appid)
            ->where("group_id", $group["id"])
            ->where("user_id", $user["id"])
            ->where("status", 1)
            ->find();
        if (!$member) {
            throw new \Exception("无权操作该群聊");
        }
        if ($manager && !in_array((int)$member["role"], [1, 2], true)) {
            throw new \Exception("只有群主或管理员可以操作");
        }
        return $member;
    }

    protected function groupMemberUser(array $group, int $userId): array
    {
        if ($userId <= 0) {
            throw new \Exception("群成员不存在");
        }
        $member = Db::name("chat_group_member")
            ->where("appid", $this->appid)
            ->where("group_id", $group["id"])
            ->where("user_id", $userId)
            ->where("status", 1)
            ->find();
        if (!$member) {
            throw new \Exception("指定用户不是有效群成员");
        }
        $user = Db::name("user")->where("id", $userId)->where("appid", $this->appid)->find();
        if (!$user) {
            throw new \Exception("指定用户不存在");
        }
        return $user;
    }

    protected function chatRequestValue(string $key, $default = null)
    {
        $secureInput = (array)($this->chatRequest["secure_input"] ?? []);
        if (array_key_exists($key, $secureInput)) {
            return $secureInput[$key];
        }
        if (array_key_exists($key, $_POST)) {
            return $_POST[$key];
        }
        if (array_key_exists($key, $_GET)) {
            return $_GET[$key];
        }
        return $default;
    }

    protected function hasChatMentionInput(): bool
    {
        foreach (["mention_user_ids", "at_user_ids"] as $key) {
            $value = $this->chatRequestValue($key, null);
            if (is_array($value) ? !empty($value) : trim((string)$value) !== "") {
                return true;
            }
        }
        foreach (["mention_all", "at_all"] as $key) {
            if ((int)$this->chatRequestValue($key, 0) === 1) {
                return true;
            }
        }
        $mention = $this->chatMentionArray();
        if ((int)($mention["all"] ?? 0) === 1) {
            return true;
        }
        if (!empty($mention["user_ids"]) || !empty($mention["ids"]) || !empty($mention["uids"])) {
            return true;
        }
        return false;
    }

    protected function chatMentionArray(): array
    {
        $raw = $this->chatRequestValue("mention", []);
        if (is_array($raw)) {
            return $raw;
        }
        $raw = trim((string)$raw);
        if ($raw === "") {
            return [];
        }
        $decoded = json_decode($raw, true);
        return is_array($decoded) ? $decoded : [];
    }

    protected function normalizeGroupMentionPayload(array $group, array $senderMember, string $contentType): array
    {
        if (!$this->hasChatMentionInput()) {
            return [];
        }
        if ($contentType !== "text") {
            $this->json(0, "只有群聊文本消息支持@");
        }

        $mention = $this->chatMentionArray();
        $allValue = $this->chatRequestValue("mention_all", $this->chatRequestValue("at_all", $mention["all"] ?? 0));
        if ((int)$allValue === 1) {
            if (!in_array((int)($senderMember["role"] ?? 0), [1, 2], true)) {
                $this->json(0, "只有群主或管理员可以@所有人");
            }
            return [
                "mention" => [
                    "all" => 1,
                    "uids" => [],
                ],
                "mention_users" => [],
            ];
        }

        $idsValue = $this->chatRequestValue(
            "mention_user_ids",
            $this->chatRequestValue("at_user_ids", $mention["user_ids"] ?? ($mention["ids"] ?? ""))
        );
        if ($idsValue === "" && empty($mention["user_ids"]) && empty($mention["ids"]) && !empty($mention["uids"])) {
            $this->json(0, "@用户请传mention_user_ids，uids由服务端生成");
        }

        $ids = $this->chatMemberIds($idsValue);
        if (!$ids) {
            $this->json(0, "@用户不能为空");
        }

        $memberRows = Db::name("chat_group_member")
            ->where("appid", $this->appid)
            ->where("group_id", $group["id"])
            ->where("status", 1)
            ->whereIn("user_id", $ids)
            ->field("user_id")
            ->select()->toArray();
        $validIds = array_map("intval", array_column($memberRows, "user_id"));
        $missingIds = array_values(array_diff($ids, $validIds));
        if ($missingIds) {
            $this->json(0, "被@用户必须是有效群成员");
        }

        $users = Db::name("user")
            ->where("appid", $this->appid)
            ->whereIn("id", $ids)
            ->select()->toArray();
        $userMap = [];
        foreach ($users as $user) {
            $userMap[(int)$user["id"]] = $user;
        }

        $uids = [];
        $mentionUsers = [];
        foreach ($ids as $id) {
            if (empty($userMap[$id])) {
                $this->json(0, "被@用户不存在");
            }
            $uid = $this->wukongUid($id);
            $uids[] = $uid;
            $mentionUsers[] = [
                "user_id" => $id,
                "uid" => $uid,
                "username" => (string)$userMap[$id]["username"],
                "nickname" => (string)$userMap[$id]["nickname"],
                "avatar" => (string)$userMap[$id]["usertx"],
            ];
        }

        return [
            "mention" => [
                "all" => 0,
                "uids" => $uids,
            ],
            "mention_users" => $mentionUsers,
        ];
    }

    protected function assertMutableGroupMember(array $group, int $userId, array $operatorMember, bool $allowInactiveMute = false): array
    {
        if ($userId <= 0) {
            throw new \Exception("群成员不存在");
        }
        $query = Db::name("chat_group_member")
            ->where("appid", $this->appid)
            ->where("group_id", $group["id"])
            ->where("user_id", $userId);
        if (!$allowInactiveMute) {
            $query->where("status", 1);
        }
        $member = $query->find();
        if (!$member) {
            throw new \Exception("指定用户不是有效群成员");
        }
        if ((int)$member["role"] === 1) {
            throw new \Exception("不能限制群主发言");
        }
        if ((int)$operatorMember["role"] === 2 && (int)$member["role"] === 2) {
            throw new \Exception("管理员不能限制管理员发言");
        }
        return $member;
    }

    protected function activeGroupMute(int $groupId, int $userId): array
    {
        $row = Db::name("chat_group_mute")
            ->where("appid", $this->appid)
            ->where("group_id", $groupId)
            ->where("user_id", $userId)
            ->where("status", 1)
            ->where(function ($query) {
                $query->whereNull("expire_time")->whereOr("expire_time", ">", date("Y-m-d H:i:s"));
            })
            ->order("id", "desc")
            ->find();
        return $row ?: [];
    }

    protected function groupMuteState(array $group, array $member): array
    {
        $mute = $this->activeGroupMute((int)$group["id"], (int)$member["user_id"]);
        $muted = $mute ? 1 : 0;
        $expireTime = $mute ? (string)($mute["expire_time"] ?? "") : "";
        $permanent = $muted && $expireTime === "" ? 1 : 0;
        $reason = $mute ? (string)($mute["reason"] ?? "") : "";
        $notice = $muted
            ? ("你已被管理员禁言" . ($reason !== "" ? "，原因：" . $reason : "") . ($permanent ? "，永久生效" : "，至 " . $expireTime))
            : "你已恢复群内发言";
        return [
            "group_id" => (int)$group["id"],
            "channel_id" => (string)$group["channel_id"],
            "channel_type" => (int)config('wukongim.channel_type_group', WukongIM::CHANNEL_TYPE_GROUP),
            "member_id" => (int)$member["user_id"],
            "member_uid" => $this->wukongUid($member["user_id"]),
            "muted" => $muted,
            "reason" => $reason,
            "expire_time" => $expireTime,
            "permanent" => $permanent,
            "notice" => $notice,
        ];
    }

    protected function sendGroupMuteCommand(array $group, array $member, array $state, string $operatorType, int $operatorId): void
    {
        $payload = [
            "protocol" => "blin.chat.v1",
            "type" => WukongIM::CONTENT_TYPE_CMD,
            "content_type" => "cmd",
            "cmd" => "group_member_mute_changed",
            "scene" => "group_chat",
            "appid" => (int)$this->appid,
            "channel_id" => (string)$group["channel_id"],
            "channel_type" => (int)config('wukongim.channel_type_group', WukongIM::CHANNEL_TYPE_GROUP),
            "group_id" => (int)$group["id"],
            "target_user_id" => (int)$member["user_id"],
            "target_uid" => $this->wukongUid($member["user_id"]),
            "muted" => (int)$state["muted"],
            "reason" => (string)$state["reason"],
            "expire_time" => (string)$state["expire_time"],
            "permanent" => (int)$state["permanent"],
            "notice" => (string)$state["notice"],
            "operator_type" => $operatorType === "system" ? "system" : "admin",
            "operator_id" => $operatorId,
            "operate_time" => time(),
        ] + $this->chatDevicePayload();
        $clientMsgNo = "group-mute-" . md5((string)$group["id"] . "-" . (int)$member["user_id"] . "-" . (int)$state["muted"] . "-" . microtime(true));
        (new WukongIM())->sendCommandMessage($this->wukongUid($operatorId > 0 ? $operatorId : $member["user_id"]), (string)$group["channel_id"], (int)config('wukongim.channel_type_group', WukongIM::CHANNEL_TYPE_GROUP), $payload, $clientMsgNo);
    }

    protected function assertGroupCanSend(array $group, array $member): void
    {
        $mute = $this->activeGroupMute((int)$group["id"], (int)$member["user_id"]);
        if (!$mute) {
            return;
        }
        $reason = trim((string)($mute["reason"] ?? ""));
        $expire = (string)($mute["expire_time"] ?? "");
        $message = "你已被管理员禁言";
        if ($reason !== "") {
            $message .= "，原因：" . $reason;
        }
        $message .= $expire === "" ? "，永久生效" : "，至 " . $expire;
        throw new \Exception($message);
    }

    protected function clearCurrentUserGroupMuteBlacklists(): void
    {
        $rows = Db::name("chat_group_member")
            ->alias("m")
            ->join("chat_group g", "g.id=m.group_id")
            ->where("m.appid", $this->appid)
            ->where("m.user_id", (int)$this->user_info["id"])
            ->where("m.status", 1)
            ->where("g.status", 1)
            ->field("g.channel_id")
            ->select()->toArray();
        if (!$rows) {
            return;
        }
        $im = new WukongIM();
        $uid = $this->wukongUid($this->user_info["id"]);
        foreach ($rows as $row) {
            try {
                $im->blacklistRemove((string)$row["channel_id"], (int)config('wukongim.channel_type_group', WukongIM::CHANNEL_TYPE_GROUP), [$uid]);
            } catch (\Exception $ignore) {
            }
        }
    }

    protected function setGroupMemberMute(array $group, array $member, int $expireSeconds, string $reason): array
    {
        $expireSeconds = max(0, $expireSeconds);
        $now = date("Y-m-d H:i:s");
        $uid = $this->wukongUid($member["user_id"]);
        $data = [
            "appid" => $this->appid,
            "group_id" => (int)$group["id"],
            "channel_id" => (string)$group["channel_id"],
            "user_id" => (int)$member["user_id"],
            "uid" => $uid,
            "status" => 1,
            "reason" => mb_substr(trim($reason) !== "" ? trim($reason) : "管理员限制", 0, 255),
            "operator_type" => "user",
            "operator_id" => (int)$this->user_info["id"],
            "mute_time" => $now,
            "expire_time" => $expireSeconds > 0 ? date("Y-m-d H:i:s", time() + $expireSeconds) : null,
            "unmute_time" => null,
            "update_time" => $now,
        ];
        $exists = Db::name("chat_group_mute")
            ->where("appid", $this->appid)
            ->where("group_id", $group["id"])
            ->where("user_id", $member["user_id"])
            ->lock(true)
            ->find();
        if ($exists) {
            Db::name("chat_group_mute")->where("id", $exists["id"])->update($data);
        } else {
            $data["create_time"] = $now;
            Db::name("chat_group_mute")->insert($data);
        }
        try {
            (new WukongIM())->blacklistRemove($group["channel_id"], (int)config('wukongim.channel_type_group', WukongIM::CHANNEL_TYPE_GROUP), [$uid]);
        } catch (\Exception $ignore) {
        }
        $state = $this->groupMuteState($group, $member);
        $this->sendGroupMuteCommand($group, $member, $state, "user", (int)$this->user_info["id"]);
        return $state;
    }

    protected function removeGroupMemberMute(array $group, array $member, string $operatorType, int $operatorId): array
    {
        Db::name("chat_group_mute")
            ->where("appid", $this->appid)
            ->where("group_id", $group["id"])
            ->where("user_id", $member["user_id"])
            ->where("status", 1)
            ->update([
                "status" => 0,
                "operator_type" => $operatorType,
                "operator_id" => $operatorId,
                "unmute_time" => date("Y-m-d H:i:s"),
                "update_time" => date("Y-m-d H:i:s"),
            ]);
        $state = $this->groupMuteState($group, $member);
        $this->sendGroupMuteCommand($group, $member, $state, $operatorType, $operatorId);
        return $state;
    }

    protected function isChatFriend(int $userId, int $friendId): bool
    {
        if ($userId <= 0 || $friendId <= 0 || $userId === $friendId) {
            return false;
        }
        return (bool)Db::name("chat_friend")
            ->where("appid", $this->appid)
            ->where("user_id", $userId)
            ->where("friend_id", $friendId)
            ->where("status", 1)
            ->find();
    }

    protected function activeChatFriendApply(int $fromUserId, int $toUserId): array
    {
        return Db::name("chat_friend_apply")
            ->where("appid", $this->appid)
            ->where("from_user_id", $fromUserId)
            ->where("to_user_id", $toUserId)
            ->where("status", 0)
            ->order("id", "desc")
            ->find() ?: [];
    }

    protected function upsertChatFriend(int $userId, int $friendId, int $applyId = 0): void
    {
        $now = date("Y-m-d H:i:s");
        $row = Db::name("chat_friend")
            ->where("appid", $this->appid)
            ->where("user_id", $userId)
            ->where("friend_id", $friendId)
            ->lock(true)
            ->find();
        $data = [
            "status" => 1,
            "source_apply_id" => $applyId,
            "update_time" => $now,
        ];
        if ($row) {
            Db::name("chat_friend")->where("id", $row["id"])->update($data);
            return;
        }
        Db::name("chat_friend")->insert($data + [
            "appid" => $this->appid,
            "user_id" => $userId,
            "friend_id" => $friendId,
            "create_time" => $now,
        ]);
    }

    protected function acceptChatFriendApply(array $apply, array $handler, string $handleMsg = ""): void
    {
        if ((int)$apply["to_user_id"] !== (int)$handler["id"]) {
            throw new \Exception("无权处理该好友申请");
        }
        if ((int)$apply["status"] !== 0) {
            throw new \Exception("好友申请已处理");
        }
        $now = date("Y-m-d H:i:s");
        $this->upsertChatFriend((int)$apply["from_user_id"], (int)$apply["to_user_id"], (int)$apply["id"]);
        $this->upsertChatFriend((int)$apply["to_user_id"], (int)$apply["from_user_id"], (int)$apply["id"]);
        $gateway = new GatewayStream();
        $gateway->syncPresenceTargetsForUser((int)$this->appid, (int)$apply["from_user_id"]);
        $gateway->syncPresenceTargetsForUser((int)$this->appid, (int)$apply["to_user_id"]);
        Db::name("chat_friend_apply")->where("id", $apply["id"])->update([
            "status" => 1,
            "handle_msg" => $handleMsg,
            "handle_time" => $now,
            "update_time" => $now,
        ]);
    }

    protected function applyNewUserChatDefaults(int $userId): void
    {
        if ($userId <= 0) {
            return;
        }
        $user = Db::name("user")->where("appid", $this->appid)->where("id", $userId)->find();
        if (!$user) {
            return;
        }

        $friendIds = ChatControl::idList("new_user_default_friend_ids");
        foreach ($friendIds as $friendId) {
            if ($friendId === $userId) {
                continue;
            }
            $friend = Db::name("user")->where("appid", $this->appid)->where("id", $friendId)->find();
            if (!$friend || $this->isWalletServiceUser($friend)) {
                continue;
            }
            $this->upsertChatFriend($userId, $friendId, 0);
            $this->upsertChatFriend($friendId, $userId, 0);
        }

        $groupIds = ChatControl::idList("new_user_default_group_ids");
        foreach ($groupIds as $groupId) {
            $group = Db::name("chat_group")
                ->where("appid", $this->appid)
                ->where("id", $groupId)
                ->where("status", 1)
                ->find();
            if (!$group) {
                continue;
            }
            $this->upsertDefaultGroupMember($group, $userId);
        }

        if ($friendIds) {
            $this->syncGatewayPresenceTargetsForUserAndFriends($userId);
        }
    }

    protected function upsertDefaultGroupMember(array $group, int $userId): void
    {
        $now = date("Y-m-d H:i:s");
        $member = Db::name("chat_group_member")
            ->where("appid", $this->appid)
            ->where("group_id", (int)$group["id"])
            ->where("user_id", $userId)
            ->lock(true)
            ->find();
        if ($member) {
            Db::name("chat_group_member")->where("id", $member["id"])->update([
                "status" => 1,
                "update_time" => $now,
            ]);
        } else {
            Db::name("chat_group_member")->insert([
                "appid" => $this->appid,
                "group_id" => (int)$group["id"],
                "channel_id" => (string)$group["channel_id"],
                "user_id" => $userId,
                "role" => 0,
                "status" => 1,
                "join_time" => $now,
                "update_time" => $now,
            ]);
        }
        (new WukongIM())->addSubscribers(
            (string)$group["channel_id"],
            (int)config('wukongim.channel_type_group', WukongIM::CHANNEL_TYPE_GROUP),
            [$this->wukongUid($userId)],
            0
        );
        $this->refreshGroupMemberCount((int)$group["id"]);
    }

    protected function personTopMessageCount(int $userId, int $friendId, string $ignoreClientMsgNo = ""): int
    {
        $userUid = $this->wukongUid($userId);
        $friendUid = $this->wukongUid($friendId);
        $query = Db::name("wukongim_message_queue")
            ->where("appid", $this->appid)
            ->where("channel_type", (int)config('wukongim.channel_type_person', WukongIM::CHANNEL_TYPE_PERSON))
            ->where("from_uid", $userUid)
            ->where("channel_id", $friendUid)
            ->whereIn("status", [WukongIM::QUEUE_PENDING, WukongIM::QUEUE_SENT, WukongIM::QUEUE_RETRY])
            ->where("content_type", "text");
        if ($ignoreClientMsgNo !== "") {
            $query->where("client_msg_no", "<>", $ignoreClientMsgNo);
        }
        return (int)$query->count();
    }

    protected function assertPersonChatAllowed(array $sender, array $receiver, string $clientMsgNo, string $contentType = "text"): void
    {
        if ((int)$sender["id"] === (int)$receiver["id"]) {
            throw new \Exception("不能给自己发送消息");
        }
        if ($this->isWalletServiceUser($receiver)) {
            throw new \Exception("该会话仅用于服务通知");
        }
        if ($this->isChatFriend((int)$sender["id"], (int)$receiver["id"])) {
            return;
        }
        if ($contentType !== "text") {
            throw new \Exception("非好友只能发送文字消息，请先添加好友");
        }
        $limit = 3;
        $count = $this->personTopMessageCount((int)$sender["id"], (int)$receiver["id"], $clientMsgNo);
        if ($count >= $limit) {
            throw new \Exception("非好友最多只能聊三句，请先添加好友");
        }
    }

    protected function isWalletServiceUser(array $user): bool
    {
        return WalletNoticeService::isServiceUser((int)$this->appid, $user);
    }

    protected function sendFriendCommand(array $fromUser, array $toUser, string $cmd, array $detail): array
    {
        $event = [
            "friend_apply" => "friend_apply_created",
            "friend_accepted" => "friend_apply_accepted",
            "friend_rejected" => "friend_apply_rejected",
        ][$cmd] ?? $cmd;
        $payload = [
            "protocol" => "blin.chat.v1",
            "type" => WukongIM::CONTENT_TYPE_CMD,
            "content_type" => "cmd",
            "cmd" => $cmd,
            "event" => $event,
            "scene" => "private_chat",
            "appid" => (int)$this->appid,
            "sender_id" => (int)$fromUser["id"],
            "receiver_id" => (int)$toUser["id"],
            "sender_uid" => $this->wukongUid($fromUser["id"]),
            "receiver_uid" => $this->wukongUid($toUser["id"]),
            "sender_nickname" => (string)($fromUser["nickname"] ?? $fromUser["username"] ?? ""),
            "sender_username" => (string)($fromUser["username"] ?? ""),
            "sender_avatar" => (string)($fromUser["usertx"] ?? ""),
            "receiver_nickname" => (string)($toUser["nickname"] ?? $toUser["username"] ?? ""),
            "receiver_username" => (string)($toUser["username"] ?? ""),
            "receiver_avatar" => (string)($toUser["usertx"] ?? ""),
            "friend" => $detail,
        ] + $this->chatDevicePayload();
        $clientMsgNo = "friend-" . md5($cmd . "-" . (int)$fromUser["id"] . "-" . (int)$toUser["id"] . "-" . json_encode($detail, JSON_UNESCAPED_UNICODE) . "-" . microtime(true));
        return (new WukongIM())->sendCommandMessage($this->wukongUid($fromUser["id"]), $this->wukongUid($toUser["id"]), (int)config('wukongim.channel_type_person', WukongIM::CHANNEL_TYPE_PERSON), $payload, $clientMsgNo);
    }

    protected function formatChatFriendApply(array $row): array
    {
        $fromUser = Db::name("user")->where("id", $row["from_user_id"])->where("appid", $this->appid)->find();
        $toUser = Db::name("user")->where("id", $row["to_user_id"])->where("appid", $this->appid)->find();
        return [
            "id" => (int)$row["id"],
            "from_user_id" => (int)$row["from_user_id"],
            "to_user_id" => (int)$row["to_user_id"],
            "status" => (int)$row["status"],
            "remark" => (string)($row["remark"] ?? ""),
            "handle_msg" => (string)($row["handle_msg"] ?? ""),
            "from_user" => $fromUser ? $this->formatChatUser($fromUser) : [],
            "to_user" => $toUser ? $this->formatChatUser($toUser) : [],
            "create_time" => (string)($row["create_time"] ?? ""),
            "handle_time" => (string)($row["handle_time"] ?? ""),
        ];
    }

    protected function momentFriendUserIds(int $userId): array
    {
        $ids = Db::name("chat_friend")
            ->where("appid", $this->appid)
            ->where("user_id", $userId)
            ->where("status", 1)
            ->column("friend_id");
        $ids[] = $userId;
        $ids = array_map("intval", $ids);
        $ids = array_values(array_unique(array_filter($ids, fn($id) => $id > 0)));
        return $ids ?: [$userId];
    }

    protected function normalizeMomentIdList($value, int $max = 100): array
    {
        if (is_string($value)) {
            $trimmed = trim($value);
            if ($trimmed === "") {
                return [];
            }
            $decoded = json_decode($trimmed, true);
            $value = is_array($decoded) ? $decoded : explode(",", $trimmed);
        }
        if (!is_array($value)) {
            return [];
        }
        $ids = [];
        foreach ($value as $item) {
            $id = (int)$item;
            if ($id > 0) {
                $ids[] = $id;
            }
            if (count($ids) >= $max) {
                break;
            }
        }
        return array_values(array_unique($ids));
    }

    protected function momentIdsCsv(array $ids): string
    {
        $ids = array_values(array_unique(array_filter(array_map("intval", $ids), fn($id) => $id > 0)));
        return implode(",", $ids);
    }

    protected function normalizeMomentMediaList($value): array
    {
        if (is_string($value)) {
            $trimmed = trim($value);
            if ($trimmed === "") {
                return [];
            }
            $decoded = json_decode($trimmed, true);
            if (!is_array($decoded)) {
                $this->json(0, "media格式错误");
            }
            $value = $decoded;
        }
        if (!is_array($value)) {
            return [];
        }
        if ($value && array_key_exists("url", $value)) {
            $value = [$value];
        }
        $media = [];
        foreach ($value as $item) {
            if (!is_array($item)) {
                continue;
            }
            $type = trim((string)($item["type"] ?? $item["media_type"] ?? ""));
            if ($type === "") {
                $mime = strtolower((string)($item["mime"] ?? ""));
                $type = str_starts_with($mime, "video/") ? "video" : (str_starts_with($mime, "image/") ? "image" : "file");
            }
            if (!in_array($type, ["image", "video", "file"], true)) {
                $this->json(0, "media_type不合法");
            }
            $url = trim((string)($item["url"] ?? $item["file_url"] ?? $item["image_url"] ?? $item["video_url"] ?? ""));
            if ($url === "") {
                $this->json(0, "media.url不能为空");
            }
            $path = (string)(parse_url($url, PHP_URL_PATH) ?: $url);
            if (!str_starts_with($path, "/uploads/") && !str_starts_with($path, "uploads/")) {
                $this->json(0, "media.url必须来自安全上传接口");
            }
            $media[] = [
                "type" => $type,
                "url" => $url,
                "thumb_url" => trim((string)($item["thumb_url"] ?? $item["cover_url"] ?? "")),
                "name" => mb_substr(trim((string)($item["name"] ?? basename($path))), 0, 120),
                "mime" => mb_substr(trim((string)($item["mime"] ?? "")), 0, 120),
                "size" => max(0, (int)($item["size"] ?? 0)),
                "width" => max(0, (int)($item["width"] ?? 0)),
                "height" => max(0, (int)($item["height"] ?? 0)),
                "duration" => max(0, (int)($item["duration"] ?? 0)),
            ];
            if (count($media) >= 9) {
                break;
            }
        }
        return $media;
    }

    protected function momentMediaType(array $media): string
    {
        if (!$media) {
            return "text";
        }
        $types = array_values(array_unique(array_map(fn($item) => (string)($item["type"] ?? ""), $media)));
        return count($types) === 1 ? $types[0] : "mixed";
    }

    protected function momentPostVisibleToUser(array $post, int $viewerId): bool
    {
        if ((int)$post["user_id"] === $viewerId) {
            return true;
        }
        if ((int)($post["review_status"] ?? 1) !== 1) {
            return false;
        }
        if (!$this->isChatFriend($viewerId, (int)$post["user_id"])) {
            return false;
        }
        $visibility = (int)($post["visibility"] ?? 0);
        if ($visibility === 1) {
            return false;
        }
        if ($visibility === 2) {
            $ids = $this->normalizeMomentIdList((string)($post["visible_user_ids"] ?? ""));
            return in_array($viewerId, $ids, true);
        }
        return true;
    }

    protected function momentPostOrFail(int $postId, int $viewerId): array
    {
        $post = Db::name("moments_post")
            ->where("appid", $this->appid)
            ->where("id", $postId)
            ->where("status", 1)
            ->find();
        if (!$post || !$this->momentPostVisibleToUser($post, $viewerId)) {
            $this->json(0, "朋友圈动态不存在");
        }
        return $post;
    }

    protected function formatMomentPost(array $post, int $viewerId): array
    {
        $user = Db::name("user")
            ->where("appid", $this->appid)
            ->where("id", (int)$post["user_id"])
            ->field("id,username,nickname,usertx,sex,signature,title,viptime,exp")
            ->find();
        $likes = Db::name("moments_like")
            ->alias("l")
            ->join("user u", "u.id=l.user_id and u.appid=l.appid")
            ->where("l.appid", $this->appid)
            ->where("l.post_id", (int)$post["id"])
            ->where("l.status", 1)
            ->field("l.id,l.user_id,l.create_time,u.username,u.nickname,u.usertx,u.sex,u.signature,u.title,u.viptime,u.exp")
            ->order("l.id", "asc")
            ->select()
            ->toArray();
        $comments = Db::name("moments_comment")
            ->alias("c")
            ->join("user u", "u.id=c.user_id and u.appid=c.appid")
            ->leftJoin("user ru", "ru.id=c.reply_user_id and ru.appid=c.appid")
            ->where("c.appid", $this->appid)
            ->where("c.post_id", (int)$post["id"])
            ->where("c.status", 1)
            ->where(function ($query) use ($viewerId) {
                $query->where("c.review_status", 1)->whereOr("c.user_id", $viewerId);
            })
            ->field("c.id,c.user_id,c.reply_comment_id,c.reply_user_id,c.content,c.review_status,c.review_mode,c.review_reason,c.create_time,u.username,u.nickname,u.usertx,u.sex,u.signature,u.title,u.viptime,u.exp,ru.username as reply_username,ru.nickname as reply_nickname,ru.usertx as reply_usertx")
            ->order("c.id", "asc")
            ->select()
            ->toArray();
        $liked = false;
        $formattedLikes = [];
        foreach ($likes as $like) {
            if ((int)$like["user_id"] === $viewerId) {
                $liked = true;
            }
            $formattedLikes[] = [
                "id" => (int)$like["id"],
                "user_id" => (int)$like["user_id"],
                "user" => $this->formatChatUser([
                    "id" => (int)$like["user_id"],
                    "username" => $like["username"] ?? "",
                    "nickname" => $like["nickname"] ?? "",
                    "usertx" => $like["usertx"] ?? "",
                    "sex" => $like["sex"] ?? 0,
                    "signature" => $like["signature"] ?? "",
                    "title" => $like["title"] ?? "",
                    "viptime" => $like["viptime"] ?? 0,
                    "exp" => $like["exp"] ?? 0,
                ]),
                "create_time" => (string)$like["create_time"],
            ];
        }
        $formattedComments = [];
        foreach ($comments as $comment) {
            $replyUser = [];
            if ((int)$comment["reply_user_id"] > 0) {
                $replyUser = [
                    "userid" => (int)$comment["reply_user_id"],
                    "id" => (int)$comment["reply_user_id"],
                    "username" => (string)($comment["reply_username"] ?? ""),
                    "nickname" => (string)($comment["reply_nickname"] ?? ""),
                    "usertx" => (string)($comment["reply_usertx"] ?? ""),
                ];
            }
            $formattedComments[] = [
                "id" => (int)$comment["id"],
                "user_id" => (int)$comment["user_id"],
                "reply_comment_id" => (int)$comment["reply_comment_id"],
                "reply_user_id" => (int)$comment["reply_user_id"],
                "content" => (string)$comment["content"],
                "user" => $this->formatChatUser([
                    "id" => (int)$comment["user_id"],
                    "username" => $comment["username"] ?? "",
                    "nickname" => $comment["nickname"] ?? "",
                    "usertx" => $comment["usertx"] ?? "",
                    "sex" => $comment["sex"] ?? 0,
                    "signature" => $comment["signature"] ?? "",
                    "title" => $comment["title"] ?? "",
                    "viptime" => $comment["viptime"] ?? 0,
                    "exp" => $comment["exp"] ?? 0,
                ]),
                "reply_user" => $replyUser,
                "review_status" => (int)($comment["review_status"] ?? 1),
                "review_status_name" => $this->momentReviewStatusName((int)($comment["review_status"] ?? 1)),
                "review_mode" => (string)($comment["review_mode"] ?? ""),
                "review_reason" => (string)($comment["review_reason"] ?? ""),
                "can_delete" => (int)$comment["user_id"] === $viewerId || (int)$post["user_id"] === $viewerId,
                "create_time" => (string)$comment["create_time"],
            ];
        }
        $media = json_decode((string)($post["media_json"] ?? "[]"), true);
        if (!is_array($media)) {
            $media = [];
        }
        return [
            "id" => (int)$post["id"],
            "post_id" => (int)$post["id"],
            "user_id" => (int)$post["user_id"],
            "user" => $user ? $this->formatChatUser($user) : [],
            "content" => (string)($post["content"] ?? ""),
            "media" => $media,
            "media_type" => (string)($post["media_type"] ?? "text"),
            "visibility" => (int)($post["visibility"] ?? 0),
            "review_status" => (int)($post["review_status"] ?? 1),
            "review_status_name" => $this->momentReviewStatusName((int)($post["review_status"] ?? 1)),
            "review_mode" => (string)($post["review_mode"] ?? ""),
            "review_reason" => (string)($post["review_reason"] ?? ""),
            "location" => (string)($post["location"] ?? ""),
            "like_count" => count($formattedLikes),
            "comment_count" => count($formattedComments),
            "likes" => $formattedLikes,
            "comments" => $formattedComments,
            "liked" => $liked,
            "can_delete" => (int)$post["user_id"] === $viewerId,
            "create_time" => (string)($post["create_time"] ?? ""),
            "update_time" => (string)($post["update_time"] ?? ""),
        ];
    }

    protected function momentReviewStatusName(int $status): string
    {
        return [0 => "待审核", 1 => "审核通过", 2 => "审核拒绝"][$status] ?? "未知";
    }

    protected function refreshGroupMemberCount(int $groupId): int
    {
        $count = Db::name("chat_group_member")->where("group_id", $groupId)->where("status", 1)->count();
        Db::name("chat_group")->where("id", $groupId)->update([
            "member_count" => $count,
            "update_time" => date("Y-m-d H:i:s"),
        ]);
        return (int)$count;
    }

    protected function queuedRedPacketReceive(WukongIM $im, string $clientMsgNo, int $redPacketId): array
    {
        $record = Db::name("wukongim_message_queue")->where("client_msg_no", $clientMsgNo)->find();
        if (!$record) {
            return [];
        }
        $payload = json_decode((string)($record["payload_text"] ?? ""), true);
        if (!is_array($payload)) {
            throw new \Exception("client_msg_no已被其它消息占用");
        }
        $packet = (array)($payload["red_packet"] ?? []);
        if ((string)($payload["content_type"] ?? "") !== "red_packet_received" || (int)($packet["red_packet_id"] ?? 0) !== $redPacketId) {
            throw new \Exception("client_msg_no已被其它业务内容占用");
        }
        return $im->queuedMessage($clientMsgNo);
    }

    protected function assetBillType(string $assetType): int
    {
        return $this->normalizeAssetType($assetType) === "integral" ? 1 : 0;
    }

    protected function assetField(string $assetType): string
    {
        return $this->normalizeAssetType($assetType) === "integral" ? "integral" : "money";
    }

    protected function assetName(string $assetType): string
    {
        return $this->normalizeAssetType($assetType) === "integral" ? "积分" : "金币";
    }

    protected function normalizeAssetType(string $assetType): string
    {
        $assetType = strtolower(trim($assetType));
        if (in_array($assetType, ["integral", "point", "points", "score"], true) || $assetType === "积分") {
            return "integral";
        }
        return "money";
    }

    protected function assertAssetBalance(array $user, string $assetType, $required): void
    {
        $assetType = $this->normalizeAssetType($assetType);
        $field = $this->assetField($assetType);
        $name = $this->assetName($assetType);
        $this->assertWalletUsable($user);
        if ($assetType === "money") {
            $requiredAmount = $this->walletAmountLabel($required);
            $available = $this->walletAvailableMoney($user);
            if ($this->walletCompare($available, $requiredAmount) < 0) {
                throw new \Exception("可用余额不足");
            }
            return;
        }
        $requiredAmount = (int)$required;
        $balance = (int)($user[$field] ?? 0);
        if ($balance < $requiredAmount) {
            throw new \Exception($name . "不足，当前" . $name . "余额：" . $balance);
        }
    }

    protected function walletOrderNo(string $prefix = "W"): string
    {
        $prefix = strtoupper(preg_replace('/[^A-Z0-9]/', '', $prefix));
        if ($prefix === '') {
            $prefix = 'W';
        }
        for ($i = 0; $i < 5; $i++) {
            $orderNo = $prefix . date("YmdHis") . strtoupper(substr(md5((string)$this->appid . "|" . microtime(true) . "|" . random_int(100000, 999999)), 0, 12));
            if (!Db::name("wallet_order")->where("order_no", $orderNo)->find()) {
                return $orderNo;
            }
            usleep(1000);
        }
        throw new \Exception("钱包订单号生成失败");
    }

    protected function walletQrToken(): string
    {
        return bin2hex(random_bytes(24));
    }

    protected function walletQrTokenHash(string $token): string
    {
        return hash("sha256", $this->appkey . "|" . $token);
    }

    protected function walletPayPasswordSalt(): string
    {
        return bin2hex(random_bytes(8));
    }

    protected function walletPayPasswordHash(string $password, string $salt): string
    {
        return hash("sha256", $this->appid . "|" . $salt . "|" . $password);
    }

    protected function assertWalletPayPasswordFormat(string $password): void
    {
        if (!preg_match("/^\\d{6}$/", $password)) {
            throw new \Exception("支付密码必须是6位数字");
        }
    }

    protected function walletPasswordRecord(int $userId): array
    {
        return Db::name("wallet_pay_password")
            ->where("appid", $this->appid)
            ->where("user_id", $userId)
            ->find() ?: [];
    }

    protected function walletSecurityMethods(array $user): array
    {
        $methods = [];
        $mobile = trim((string)($user["mobile"] ?? ""));
        if ($mobile !== "") {
            $methods[] = [
                "method" => "mobile",
                "label" => "手机号",
                "target" => $this->walletMaskMobile($mobile),
            ];
        }
        $email = trim((string)($user["email"] ?? ""));
        if ($email !== "") {
            $methods[] = [
                "method" => "email",
                "label" => "邮箱",
                "target" => $this->walletMaskEmail($email),
            ];
        }
        return $methods;
    }

    protected function userSecurityPayload(array $user): array
    {
        $methods = $this->walletSecurityMethods($user);
        return [
            "user_id" => (int)($user["id"] ?? 0),
            "mobile_bound" => trim((string)($user["mobile"] ?? "")) !== "" ? 1 : 0,
            "email_bound" => trim((string)($user["email"] ?? "")) !== "" ? 1 : 0,
            "mobile" => $this->walletMaskMobile(trim((string)($user["mobile"] ?? ""))),
            "email" => $this->walletMaskEmail(trim((string)($user["email"] ?? ""))),
            "security_bound" => $methods ? 1 : 0,
            "security_methods" => $methods,
        ];
    }

    protected function walletMaskMobile(string $mobile): string
    {
        if (strlen($mobile) < 7) {
            return $mobile;
        }
        return substr($mobile, 0, 3) . "****" . substr($mobile, -4);
    }

    protected function walletMaskEmail(string $email): string
    {
        $parts = explode("@", $email, 2);
        if (count($parts) !== 2) {
            return $email;
        }
        $name = $parts[0];
        $prefix = mb_substr($name, 0, 1);
        return $prefix . "***@" . $parts[1];
    }

    protected function walletSecurityCodeCacheKey(int $userId, string $method): string
    {
        return $this->appid . "wallet_pay_password_" . $userId . "_" . $method;
    }

    protected function walletSecurityTarget(array $user, string $method): string
    {
        if ($method === "mobile") {
            return trim((string)($user["mobile"] ?? ""));
        }
        if ($method === "email") {
            return trim((string)($user["email"] ?? ""));
        }
        return "";
    }

    protected function walletServiceUser(): array
    {
        return WalletNoticeService::serviceUser((int)$this->appid);
    }

    protected function serviceAccountEnsureDefaults(): void
    {
        $walletUser = $this->walletServiceUser();
        if (!$walletUser) {
            return;
        }
        $now = date("Y-m-d H:i:s");
        $row = Db::name("service_account")
            ->where("appid", $this->appid)
            ->where("code", "payment_service")
            ->find();
        $save = [
            "appid" => $this->appid,
            "code" => "payment_service",
            "user_id" => (int)$walletUser["id"],
            "name" => "支付通知",
            "avatar" => (string)($walletUser["usertx"] ?? ""),
            "description" => "钱包交易与收付款通知",
            "status" => 1,
            "allow_reply" => 0,
            "allow_unfollow" => 0,
            "show_in_contacts" => 1,
            "show_in_conversation" => 1,
            "menu_mode" => "menu",
            "sort" => 100,
            "update_time" => $now,
        ];
        if ($row) {
            Db::name("service_account")->where("id", (int)$row["id"])->update($save);
            $serviceId = (int)$row["id"];
        } else {
            $save["create_time"] = $now;
            $serviceId = Db::name("service_account")->insertGetId($save);
        }
        $existsMenu = Db::name("service_account_menu")
            ->where("appid", $this->appid)
            ->where("service_id", $serviceId)
            ->count();
        if ((int)$existsMenu <= 0) {
            $menus = [
                ["title" => "我的账单", "icon" => "receipt_long", "action_type" => "wallet_bills", "sort" => 10],
                ["title" => "支付服务", "icon" => "account_balance_wallet", "action_type" => "wallet_home", "sort" => 20],
                ["title" => "收付款", "icon" => "qr_code_2", "action_type" => "wallet_pay_receive", "sort" => 30],
            ];
            foreach ($menus as $menu) {
                Db::name("service_account_menu")->insert([
                    "appid" => $this->appid,
                    "service_id" => $serviceId,
                    "title" => $menu["title"],
                    "icon" => $menu["icon"],
                    "action_type" => $menu["action_type"],
                    "action_value" => "",
                    "need_merchant" => 0,
                    "status" => 1,
                    "sort" => $menu["sort"],
                    "create_time" => $now,
                    "update_time" => $now,
                ]);
            }
        }
    }

    protected function serviceAccountMenus(int $serviceId): array
    {
        if ($serviceId <= 0) {
            return [];
        }
        return Db::name("service_account_menu")
            ->where("appid", $this->appid)
            ->where("service_id", $serviceId)
            ->where("status", 1)
            ->order("sort asc,id asc")
            ->field("id,title,icon,action_type,action_value,need_merchant,sort")
            ->select()
            ->toArray();
    }

    protected function formatServiceAccount(array $row, bool $includeMenus = true): array
    {
        $serviceId = (int)($row["id"] ?? $row["service_id"] ?? 0);
        $userId = (int)($row["user_id"] ?? 0);
        $avatar = (string)($row["avatar"] ?? "");
        if ($avatar === "") {
            $avatar = (string)($row["usertx"] ?? "");
        }
        return [
            "id" => $serviceId,
            "service_id" => $serviceId,
            "code" => (string)($row["code"] ?? ""),
            "name" => (string)($row["name"] ?? ""),
            "avatar" => $this->absolutePublicUrl($avatar),
            "description" => (string)($row["description"] ?? ""),
            "status" => (int)($row["status"] ?? 0),
            "allow_reply" => (int)($row["allow_reply"] ?? 0),
            "allow_unfollow" => (int)($row["allow_unfollow"] ?? 0),
            "show_in_contacts" => (int)($row["show_in_contacts"] ?? 1),
            "show_in_conversation" => (int)($row["show_in_conversation"] ?? 1),
            "menu_mode" => (string)($row["menu_mode"] ?? "menu"),
            "sort" => (int)($row["sort"] ?? 0),
            "user_id" => $userId,
            "channel_id" => $userId > 0 ? WukongIM::uid((int)$this->appid, $userId) : "",
            "channel_type" => (int)config('wukongim.channel_type_person', WukongIM::CHANNEL_TYPE_PERSON),
            "muted" => (int)($row["muted"] ?? 0),
            "pinned" => (int)($row["pinned"] ?? 0),
            "following" => (int)($row["following"] ?? 1),
            "menus" => $includeMenus ? $this->serviceAccountMenus($serviceId) : [],
        ];
    }

    protected function walletNoticeTitle(string $scene): string
    {
        return match ($scene) {
            "pay_code_confirm_required" => "待确认付款",
            "scan_pay_success" => "扫码付款成功",
            "scan_collect_success" => "收款到账",
            default => "钱包通知",
        };
    }

    protected function sendWalletServiceNotice(int $targetUserId, array $order, string $scene): void
    {
        if ($targetUserId <= 0 || !$order) {
            return;
        }
        try {
            $serviceUser = $this->walletServiceUser();
            $targetUser = Db::name("user")
                ->where("appid", $this->appid)
                ->where("id", $targetUserId)
                ->find();
            if (!$serviceUser || !$targetUser || (int)$serviceUser["id"] === (int)$targetUser["id"]) {
                return;
            }
            $orderPayload = $this->formatWalletOrder($order);
            $orderPayload["current_user_role"] = (int)($orderPayload["payer_id"] ?? 0) === $targetUserId
                ? "payer"
                : (((int)($orderPayload["payee_id"] ?? 0) === $targetUserId) ? "payee" : "scanner");
            $amount = (string)($orderPayload["amount_label"] ?? $orderPayload["amount"] ?? "0.00");
            $title = $this->walletNoticeTitle($scene);
            $summary = match ($scene) {
                "pay_code_confirm_required" => "商户请求收款 ¥" . $amount,
                "scan_collect_success" => "已收款 ¥" . $amount,
                default => "已付款 ¥" . $amount,
            };
            $clientMsgNo = "wallet-notice-" . md5((string)$this->appid . "|" . (string)$order["order_no"] . "|" . $targetUserId . "|" . $scene);
            $payload = [
                "protocol" => "blin.chat.v1",
                "type" => $this->wukongContentTypeCode("wallet_notice"),
                "appid" => (int)$this->appid,
                "scene" => "wallet_service",
                "content_type" => "wallet_notice",
                "content" => "[" . $title . "] " . $summary,
                "channel_type" => (int)config('wukongim.channel_type_person', WukongIM::CHANNEL_TYPE_PERSON),
                "channel_type_name" => "person",
                "sender_id" => (int)$serviceUser["id"],
                "receiver_id" => (int)$targetUser["id"],
                "sender_uid" => $this->wukongUid($serviceUser["id"]),
                "receiver_uid" => $this->wukongUid($targetUser["id"]),
                "sender_username" => (string)$serviceUser["username"],
                "sender_nickname" => (string)$serviceUser["nickname"],
                "sender_avatar" => (string)($serviceUser["usertx"] ?? ""),
                "system_message" => true,
                "wallet_notice" => [
                    "scene" => $scene,
                    "title" => $title,
                    "summary" => $summary,
                    "amount" => (string)$orderPayload["amount"],
                    "amount_label" => "¥" . $amount,
                    "order_no" => (string)$orderPayload["order_no"],
                    "order_type" => (string)$orderPayload["order_type"],
                    "status_name" => (string)$orderPayload["status_name"],
                    "paid_time" => (string)$orderPayload["paid_time"],
                    "payer_id" => (int)$orderPayload["payer_id"],
                    "payer_name" => (string)$orderPayload["payer_name"],
                    "payer_avatar" => (string)$orderPayload["payer_avatar"],
                    "payee_id" => (int)$orderPayload["payee_id"],
                    "payee_name" => (string)$orderPayload["payee_name"],
                    "payee_avatar" => (string)$orderPayload["payee_avatar"],
                    "confirmable" => $scene === "pay_code_confirm_required" ? 1 : 0,
                    "requires_pay_password" => $scene === "pay_code_confirm_required" ? 1 : 0,
                ],
                "order" => $orderPayload,
            ] + $this->chatDevicePayload();
            (new WukongIM())->sendPersonMessage(
                $this->wukongUid($serviceUser["id"]),
                $this->wukongUid($targetUser["id"]),
                $payload,
                $clientMsgNo
            );
        } catch (\Throwable $e) {
            error_log("wallet service notice failed: " . $e->getMessage());
        }
    }

    protected function sendWalletRefundNotice(array $sender, string $sourceType, $amount, string $assetType, string $transactionNo): void
    {
        $targetUserId = (int)($sender['id'] ?? 0);
        if ($targetUserId <= 0) {
            return;
        }
        $assetType = $this->normalizeAssetType($assetType);
        $amountLabel = $this->chatAssetAmountLabel($amount, $assetType);
        $assetName = $this->assetName($assetType);
        $isTransfer = $sourceType === 'transfer';
        $title = $isTransfer ? '转账已退回' : '红包已退回';
        $summary = ($isTransfer ? '转账' : '红包') . '已过期，已退回 ' . $amountLabel . $assetName;
        WalletNoticeService::send(
            (int)$this->appid,
            $targetUserId,
            $isTransfer ? 'transfer_refund' : 'red_packet_refund',
            $title,
            $summary,
            [
                'source_type' => $sourceType,
                'amount' => (string)$amountLabel,
                'amount_label' => $amountLabel . $assetName,
                'asset_type' => $assetType,
                'asset_name' => $assetName,
                'transaction_no' => $transactionNo,
                'status_name' => '已退回',
            ],
            'wallet-refund-' . md5((string)$this->appid . '|' . $sourceType . '|' . $transactionNo . '|' . $targetUserId . '|' . $amountLabel)
        );
    }

    protected function walletPayPasswordIsLocked(array $record): bool
    {
        if (!$record) {
            return false;
        }
        if ((int)($record["status"] ?? 0) === 2) {
            return true;
        }
        $lockedUntil = strtotime((string)($record["locked_until"] ?? ""));
        return $lockedUntil > time();
    }

    protected function walletPayPasswordLockedUntil(array $record): string
    {
        if (!$this->walletPayPasswordIsLocked($record)) {
            return "";
        }
        return (string)($record["locked_until"] ?? "2099-12-31 23:59:59");
    }

    protected function assertWalletSecurityVerification(array $user, array $data): void
    {
        $methods = $this->walletSecurityMethods($user);
        if (!$methods) {
            throw new \Exception("请先绑定手机号、邮箱或安全验证方式");
        }
        $method = trim((string)($data["verification_method"] ?? ""));
        if ($method === "") {
            $method = (string)$methods[0]["method"];
        }
        $allowed = array_column($methods, "method");
        if (!in_array($method, $allowed, true)) {
            throw new \Exception("安全验证方式不可用");
        }
        $code = trim((string)($data["verify_code"] ?? $data["code"] ?? ""));
        if ($code === "") {
            throw new \Exception("验证码不能为空");
        }
        $cache = Cache::get($this->walletSecurityCodeCacheKey((int)$user["id"], $method));
        if (!$cache || (string)($cache["code"] ?? "") !== $code) {
            throw new \Exception("验证码错误或已过期");
        }
        Cache::delete($this->walletSecurityCodeCacheKey((int)$user["id"], $method));
    }

    protected function verifyWalletPayPassword(int $userId, string $password): void
    {
        $user = Db::name("user")->where("appid", $this->appid)->where("id", $userId)->find();
        $this->assertWalletUsable($user ?: []);
        $this->assertWalletPayPasswordFormat($password);
        $record = $this->walletPasswordRecord($userId);
        if (!$record || (int)($record["status"] ?? 0) !== 1) {
            if ($this->walletPayPasswordIsLocked($record)) {
                throw new \Exception("支付密码已锁定，请联系管理员解锁");
            }
            throw new \Exception("请先设置支付密码");
        }
        if ($this->walletPayPasswordIsLocked($record)) {
            throw new \Exception("支付密码已锁定，请联系管理员解锁");
        }
        $hash = $this->walletPayPasswordHash($password, (string)$record["salt"]);
        if (!hash_equals((string)$record["password_hash"], $hash)) {
            $failedCount = (int)($record["failed_count"] ?? 0) + 1;
            $update = [
                "failed_count" => $failedCount,
                "last_failed_time" => date("Y-m-d H:i:s"),
                "update_time" => date("Y-m-d H:i:s"),
            ];
            if ($failedCount >= 3) {
                $update["status"] = 2;
                $update["locked_until"] = "2099-12-31 23:59:59";
                Db::name("wallet_pay_password")->where("id", (int)$record["id"])->update($update);
                throw new \Exception("支付密码错误次数过多，已锁定");
            }
            Db::name("wallet_pay_password")->where("id", (int)$record["id"])->update($update);
            throw new \Exception("支付密码错误，还可输入" . (3 - $failedCount) . "次");
        }
        if ((int)($record["failed_count"] ?? 0) > 0 || !empty($record["last_failed_time"]) || !empty($record["locked_until"])) {
            Db::name("wallet_pay_password")->where("id", (int)$record["id"])->update([
                "failed_count" => 0,
                "last_failed_time" => null,
                "locked_until" => null,
                "status" => 1,
                "update_time" => date("Y-m-d H:i:s"),
            ]);
        }
    }

    protected function walletAmountLabel($amount): string
    {
        $text = trim((string)$amount);
        if ($text === "") {
            return "0.00";
        }
        $negative = false;
        if ($text[0] === "-") {
            $negative = true;
            $text = substr($text, 1);
        }
        if (!preg_match("/^\\d+(\\.\\d+)?$/", $text)) {
            return "0.00";
        }
        [$yuan, $cent] = array_pad(explode(".", $text, 2), 2, "");
        $yuan = ltrim($yuan, "0");
        if ($yuan === "") {
            $yuan = "0";
        }
        $cent = substr(str_pad($cent, 2, "0"), 0, 2);
        return ($negative ? "-" : "") . $yuan . "." . $cent;
    }

    protected function walletAmountToCents($amount): int
    {
        $label = $this->walletAmountLabel($amount);
        $negative = str_starts_with($label, "-");
        $label = ltrim($label, "-");
        [$yuan, $cent] = explode(".", $label, 2);
        $cents = ((int)$yuan * 100) + (int)$cent;
        return $negative ? -$cents : $cents;
    }

    protected function walletCentsToAmount(int $cents): string
    {
        $negative = $cents < 0;
        $cents = abs($cents);
        $yuan = intdiv($cents, 100);
        $cent = $cents % 100;
        return ($negative ? "-" : "") . $yuan . "." . str_pad((string)$cent, 2, "0", STR_PAD_LEFT);
    }

    protected function walletCompare($left, $right): int
    {
        return $this->walletAmountToCents($left) <=> $this->walletAmountToCents($right);
    }

    protected function walletFrozenMoney(array $user): string
    {
        return $this->walletAmountLabel($user["wallet_frozen_money"] ?? 0);
    }

    protected function walletAvailableMoney(array $user): string
    {
        $balance = $this->walletAmountToCents($user["money"] ?? 0);
        $frozen = max(0, $this->walletAmountToCents($user["wallet_frozen_money"] ?? 0));
        return $this->walletCentsToAmount(max(0, $balance - $frozen));
    }

    protected function walletStatusName(array $user): string
    {
        return (int)($user["wallet_status"] ?? 1) === 2 ? "已锁定" : "正常";
    }

    protected function walletMerchantStatus(array $user): int
    {
        return (int)($user["merchant_status"] ?? 0);
    }

    protected function walletMerchantEnabled(array $user): bool
    {
        return $this->walletMerchantStatus($user) === 1;
    }

    protected function walletMerchantStatusName(array $user): string
    {
        return match ($this->walletMerchantStatus($user)) {
            1 => "已开通",
            2 => "已停用",
            default => "未开通",
        };
    }

    protected function assertMerchantEnabled(array $user): void
    {
        $this->assertWalletUsable($user);
        if (!$this->walletMerchantEnabled($user)) {
            throw new \Exception("当前账号未开通商户收款权限");
        }
    }

    protected function assertWalletPayPasswordReady(int $userId): void
    {
        $record = $this->walletPasswordRecord($userId);
        if (!$record || (int)($record["status"] ?? 0) === 0 || (string)($record["password_hash"] ?? "") === "") {
            throw new \Exception("请先设置支付密码");
        }
        if ($this->walletPayPasswordIsLocked($record)) {
            throw new \Exception("支付密码已锁定，请联系管理员解锁");
        }
    }

    protected function assertWalletUsable(array $user): void
    {
        if (!$user) {
            throw new \Exception("用户不存在");
        }
        if ((int)($user["wallet_status"] ?? 1) === 2) {
            throw new \Exception("当前钱包暂不可用，请稍后再试");
        }
    }

    protected function assertWalletMoneyAvailable(array $user, $required): void
    {
        $this->assertWalletUsable($user);
        $requiredAmount = $this->walletAmountLabel($required);
        if ($this->walletCompare($this->walletAvailableMoney($user), $requiredAmount) < 0) {
            throw new \Exception("可用余额不足");
        }
    }

    protected function normalizeWalletMoney($value): string
    {
        $text = trim((string)$value);
        if ($text === "" || !preg_match("/^\\d+(\\.\\d{1,2})?$/", $text)) {
            throw new \Exception("金额格式不正确，最多支持小数点后两位");
        }
        $amount = $this->walletAmountLabel($text);
        if ($this->walletAmountToCents($amount) <= 0) {
            throw new \Exception("金额必须大于0");
        }
        return $amount;
    }

    protected function normalizeWalletOptionalMoney($value): string
    {
        $text = trim((string)$value);
        if ($text === "") {
            return "0.00";
        }
        return $this->normalizeWalletMoney($text);
    }

    protected function normalizeChatAssetAmount($value, string $assetType): string
    {
        $assetType = $this->normalizeAssetType($assetType);
        if ($assetType === "money") {
            return $this->normalizeWalletMoney($value);
        }
        $text = trim((string)$value);
        if ($text === "" || !preg_match("/^[1-9]\\d*$/", $text)) {
            throw new \Exception("积分数量必须是正整数");
        }
        return (string)(int)$text;
    }

    protected function chatAssetAmountLabel($amount, string $assetType): string
    {
        return $this->normalizeAssetType($assetType) === "money"
            ? $this->walletAmountLabel($amount)
            : (string)max(0, (int)$amount);
    }

    protected function chatAssetCompare($left, $right, string $assetType): int
    {
        return $this->normalizeAssetType($assetType) === "money"
            ? $this->walletCompare($left, $right)
            : ((int)$left <=> (int)$right);
    }

    protected function chatAssetAdd($left, $right, string $assetType): string
    {
        if ($this->normalizeAssetType($assetType) === "money") {
            return $this->walletCentsToAmount($this->walletAmountToCents($left) + $this->walletAmountToCents($right));
        }
        return (string)((int)$left + (int)$right);
    }

    protected function chatAssetSub($left, $right, string $assetType): string
    {
        if ($this->normalizeAssetType($assetType) === "money") {
            return $this->walletCentsToAmount(max(0, $this->walletAmountToCents($left) - $this->walletAmountToCents($right)));
        }
        return (string)max(0, (int)$left - (int)$right);
    }

    protected function chatAssetUnitValue($amount, string $assetType): int
    {
        return $this->normalizeAssetType($assetType) === "money"
            ? $this->walletAmountToCents($amount)
            : (int)$amount;
    }

    protected function chatAssetFromUnitValue(int $value, string $assetType): string
    {
        return $this->normalizeAssetType($assetType) === "money"
            ? $this->walletCentsToAmount($value)
            : (string)$value;
    }

    protected function chatPaymentUserPayload(array $user): array
    {
        if (!$user) {
            return [];
        }
        return [
            "id" => (int)$user["id"],
            "userid" => (int)$user["id"],
            "username" => (string)($user["username"] ?? ""),
            "nickname" => (string)($user["nickname"] ?? ""),
            "display_name" => trim((string)($user["nickname"] ?? "")) ?: (string)($user["username"] ?? ""),
            "avatar" => (string)($user["usertx"] ?? ""),
            "usertx" => (string)($user["usertx"] ?? ""),
        ];
    }

    protected function transferStatusName(int $status): string
    {
        return match ($status) {
            1 => "已收款",
            2 => "已退回",
            default => "待收款",
        };
    }

    protected function redPacketStatusName(int $status): string
    {
        return match ($status) {
            1 => "已领完",
            2 => "已过期",
            default => "待领取",
        };
    }

    protected function canCurrentUserReceiveTransfer(array $transfer): bool
    {
        return (int)($transfer["status"] ?? 0) === 0
            && (int)($transfer["receiver_id"] ?? 0) === (int)$this->user_info["id"]
            && (empty($transfer["expire_time"]) || strtotime((string)$transfer["expire_time"]) >= time());
    }

    protected function canCurrentUserReceiveRedPacket(array $redPacket): bool
    {
        if ((int)($redPacket["status"] ?? 0) !== 0 || (!empty($redPacket["expire_time"]) && strtotime((string)$redPacket["expire_time"]) < time())) {
            return false;
        }
        if ((int)($redPacket["group_id"] ?? 0) <= 0) {
            return (int)($redPacket["receiver_id"] ?? 0) === (int)$this->user_info["id"];
        }
        if ((int)($redPacket["receiver_id"] ?? 0) > 0 && (int)$redPacket["receiver_id"] !== (int)$this->user_info["id"]) {
            return false;
        }
        $received = Db::name("wukongim_red_packet_receive")
            ->where("red_packet_id", (int)$redPacket["id"])
            ->where("receiver_id", (int)$this->user_info["id"])
            ->find();
        if ($received) {
            return false;
        }
        $assetType = (string)($redPacket["asset_type"] ?? "money");
        return (int)($redPacket["receive_count"] ?? 0) < max(1, (int)($redPacket["quantity"] ?? 1))
            && $this->chatAssetCompare($redPacket["remaining_amount"] ?? 0, 0, $assetType) > 0;
    }

    protected function assertTransferVisible(array $transfer): void
    {
        $userId = (int)$this->user_info["id"];
        if ((int)($transfer["group_id"] ?? 0) > 0) {
            $group = Db::name("chat_group")
                ->where("id", (int)$transfer["group_id"])
                ->where("appid", $this->appid)
                ->where("status", 1)
                ->find();
            if (!$group) {
                throw new \Exception("群聊不存在");
            }
            $this->assertGroupMember($group, $this->user_info);
            return;
        }
        if (!in_array($userId, [(int)$transfer["sender_id"], (int)$transfer["receiver_id"]], true)) {
            throw new \Exception("无权查看该转账");
        }
    }

    protected function assertRedPacketVisible(array $redPacket): void
    {
        $userId = (int)$this->user_info["id"];
        if ((int)($redPacket["group_id"] ?? 0) > 0) {
            $group = Db::name("chat_group")
                ->where("id", (int)$redPacket["group_id"])
                ->where("appid", $this->appid)
                ->where("status", 1)
                ->find();
            if (!$group) {
                throw new \Exception("群聊不存在");
            }
            $this->assertGroupMember($group, $this->user_info);
            return;
        }
        if (!in_array($userId, [(int)$redPacket["sender_id"], (int)$redPacket["receiver_id"]], true)) {
            throw new \Exception("无权查看该红包");
        }
    }

    protected function formatTransferDetail(array $transfer): array
    {
        $assetType = (string)($transfer["asset_type"] ?? "money");
        $sender = Db::name("user")->where("appid", $this->appid)->where("id", (int)$transfer["sender_id"])->find() ?: [];
        $receiver = Db::name("user")->where("appid", $this->appid)->where("id", (int)$transfer["receiver_id"])->find() ?: [];
        $group = [];
        if ((int)($transfer["group_id"] ?? 0) > 0) {
            $group = Db::name("chat_group")->where("appid", $this->appid)->where("id", (int)$transfer["group_id"])->find() ?: [];
        }
        $amount = $this->chatAssetAmountLabel($transfer["amount"] ?? 0, $assetType);
        $receiveAmount = $this->chatAssetAmountLabel($transfer["receiver_increase"] ?? 0, $assetType);
        return [
            "transfer_id" => (int)$transfer["id"],
            "transaction_no" => (string)($transfer["transaction_no"] ?? ""),
            "amount" => $amount,
            "amount_label" => $amount,
            "asset_type" => $assetType,
            "fee" => $this->chatAssetAmountLabel($transfer["fee"] ?? 0, $assetType),
            "sender_deduct" => $this->chatAssetAmountLabel($transfer["sender_deduct"] ?? 0, $assetType),
            "receiver_increase" => $receiveAmount,
            "receive_amount" => $receiveAmount,
            "status" => (int)$transfer["status"],
            "status_name" => $this->transferStatusName((int)$transfer["status"]),
            "sender_id" => (int)$transfer["sender_id"],
            "receiver_id" => (int)$transfer["receiver_id"],
            "group_id" => (int)($transfer["group_id"] ?? 0),
            "channel_id" => (string)($transfer["channel_id"] ?? ""),
            "sender" => $this->chatPaymentUserPayload($sender),
            "receiver" => $this->chatPaymentUserPayload($receiver),
            "group" => $group ? $this->formatChatGroup($group) : [],
            "can_receive" => $this->canCurrentUserReceiveTransfer($transfer) ? 1 : 0,
            "is_sender" => (int)$transfer["sender_id"] === (int)$this->user_info["id"] ? 1 : 0,
            "is_receiver" => (int)$transfer["receiver_id"] === (int)$this->user_info["id"] ? 1 : 0,
            "client_msg_no" => (string)($transfer["client_msg_no"] ?? ""),
            "message_id" => (string)($transfer["message_id"] ?? ""),
            "expire_time" => (string)($transfer["expire_time"] ?? ""),
            "receive_time" => (string)($transfer["receive_time"] ?? ""),
            "refund_time" => (string)($transfer["refund_time"] ?? ""),
            "create_time" => (string)($transfer["create_time"] ?? ""),
            "update_time" => (string)($transfer["update_time"] ?? ""),
        ];
    }

    protected function formatRedPacketDetail(array $redPacket): array
    {
        $assetType = (string)($redPacket["asset_type"] ?? "money");
        $sender = Db::name("user")->where("appid", $this->appid)->where("id", (int)$redPacket["sender_id"])->find() ?: [];
        $receiver = [];
        if ((int)($redPacket["receiver_id"] ?? 0) > 0) {
            $receiver = Db::name("user")->where("appid", $this->appid)->where("id", (int)$redPacket["receiver_id"])->find() ?: [];
        }
        $group = [];
        if ((int)($redPacket["group_id"] ?? 0) > 0) {
            $group = Db::name("chat_group")->where("appid", $this->appid)->where("id", (int)$redPacket["group_id"])->find() ?: [];
        }
        $receiveRows = Db::name("wukongim_red_packet_receive")
            ->alias("r")
            ->leftJoin("user u", "u.id=r.receiver_id and u.appid=r.appid")
            ->where("r.appid", $this->appid)
            ->where("r.red_packet_id", (int)$redPacket["id"])
            ->order("r.id", "asc")
            ->field("r.*,u.username,u.nickname,u.usertx")
            ->select()
            ->toArray();
        $receives = [];
        foreach ($receiveRows as $row) {
            $receives[] = [
                "id" => (int)$row["id"],
                "receiver_id" => (int)$row["receiver_id"],
                "receiver" => $this->chatPaymentUserPayload([
                    "id" => (int)$row["receiver_id"],
                    "username" => (string)($row["username"] ?? ""),
                    "nickname" => (string)($row["nickname"] ?? ""),
                    "usertx" => (string)($row["usertx"] ?? ""),
                ]),
                "amount" => $this->chatAssetAmountLabel($row["amount"] ?? 0, $assetType),
                "amount_label" => $this->chatAssetAmountLabel($row["amount"] ?? 0, $assetType),
                "asset_type" => $assetType,
                "create_time" => (string)($row["create_time"] ?? ""),
            ];
        }
        $amount = $this->chatAssetAmountLabel($redPacket["amount"] ?? 0, $assetType);
        return [
            "red_packet_id" => (int)$redPacket["id"],
            "transaction_no" => (string)($redPacket["transaction_no"] ?? ""),
            "amount" => $amount,
            "amount_label" => $amount,
            "remaining_amount" => $this->chatAssetAmountLabel($redPacket["remaining_amount"] ?? 0, $assetType),
            "refund_amount" => $this->chatAssetAmountLabel($redPacket["refund_amount"] ?? 0, $assetType),
            "asset_type" => $assetType,
            "remark" => (string)($redPacket["remark"] ?? ""),
            "packet_type" => (string)($redPacket["packet_type"] ?? "ordinary"),
            "quantity" => (int)($redPacket["quantity"] ?? 1),
            "receive_count" => (int)($redPacket["receive_count"] ?? 0),
            "status" => (int)$redPacket["status"],
            "status_name" => $this->redPacketStatusName((int)$redPacket["status"]),
            "sender_id" => (int)$redPacket["sender_id"],
            "receiver_id" => (int)($redPacket["receiver_id"] ?? 0),
            "group_id" => (int)($redPacket["group_id"] ?? 0),
            "channel_id" => (string)($redPacket["channel_id"] ?? ""),
            "sender" => $this->chatPaymentUserPayload($sender),
            "receiver" => $this->chatPaymentUserPayload($receiver),
            "group" => $group ? $this->formatChatGroup($group) : [],
            "receives" => $receives,
            "can_receive" => $this->canCurrentUserReceiveRedPacket($redPacket) ? 1 : 0,
            "received_by_me" => Db::name("wukongim_red_packet_receive")->where("red_packet_id", (int)$redPacket["id"])->where("receiver_id", (int)$this->user_info["id"])->find() ? 1 : 0,
            "is_sender" => (int)$redPacket["sender_id"] === (int)$this->user_info["id"] ? 1 : 0,
            "client_msg_no" => (string)($redPacket["client_msg_no"] ?? ""),
            "message_id" => (string)($redPacket["message_id"] ?? ""),
            "expire_time" => (string)($redPacket["expire_time"] ?? ""),
            "receive_time" => (string)($redPacket["receive_time"] ?? ""),
            "refund_time" => (string)($redPacket["refund_time"] ?? ""),
            "create_time" => (string)($redPacket["create_time"] ?? ""),
            "update_time" => (string)($redPacket["update_time"] ?? ""),
        ];
    }

    protected function walletBalancePayload(array $user): array
    {
        $balance = $this->walletAmountLabel($user["money"] ?? 0);
        $record = $this->walletPasswordRecord((int)$user["id"]);
        $methods = $this->walletSecurityMethods($user);
        $freezeRecords = $this->walletActiveFreezeRecords((int)$user["id"]);
        $otcMerchant = Db::name('otc_merchant')->where('appid', $this->appid)->where('user_id', (int)$user['id'])->find() ?: [];
        $otcDeposit = $this->walletAmountLabel($otcMerchant['deposit_amount'] ?? 0);
        $otcReserved = $this->walletAmountLabel($otcMerchant['deposit_ad_reserved'] ?? 0);
        $otcAvailableRaw = bcsub($otcDeposit, $otcReserved, 2);
        $otcAvailable = $this->walletAmountLabel(bccomp($otcAvailableRaw, '0.00', 2) < 0 ? '0.00' : $otcAvailableRaw);
        $freezeReason = trim((string)($user["wallet_lock_reason"] ?? ""));
        if ($freezeReason === "" && $freezeRecords) {
            $freezeReason = (string)($freezeRecords[0]["reason"] ?? "");
        }
        return [
            "user_id" => (int)$user["id"],
            "balance" => $balance,
            "balance_label" => $balance,
            "available_balance" => $this->walletAvailableMoney($user),
            "available_balance_label" => $this->walletAvailableMoney($user),
            "frozen_balance" => $this->walletFrozenMoney($user),
            "frozen_balance_label" => $this->walletFrozenMoney($user),
            "wallet_status" => (int)($user["wallet_status"] ?? 1),
            "wallet_status_name" => $this->walletStatusName($user),
            "wallet_lock_reason" => trim((string)($user["wallet_lock_reason"] ?? "")),
            "freeze_reason" => $freezeReason,
            "freeze_records" => $freezeRecords,
            "otc_merchant_deposit" => $otcDeposit,
            "otc_merchant_deposit_label" => $otcDeposit,
            "otc_ad_deposit_reserved" => $otcReserved,
            "otc_ad_deposit_reserved_label" => $otcReserved,
            "otc_deposit_available" => $otcAvailable,
            "otc_deposit_available_label" => $otcAvailable,
            "otc_merchant_status" => isset($otcMerchant['status']) ? (int)$otcMerchant['status'] : -1,
            "pay_password_set" => ($record && (int)($record["status"] ?? 0) > 0) ? 1 : 0,
            "pay_password_locked" => $this->walletPayPasswordIsLocked($record) ? 1 : 0,
            "pay_password_locked_until" => $this->walletPayPasswordLockedUntil($record),
            "pay_password_failed_count" => (int)($record["failed_count"] ?? 0),
            "security_bound" => $methods ? 1 : 0,
            "security_methods" => $methods,
            "merchant_enabled" => $this->walletMerchantEnabled($user) ? 1 : 0,
            "merchant_status" => $this->walletMerchantStatus($user),
            "merchant_status_name" => $this->walletMerchantStatusName($user),
            "merchant_name" => (string)($user["merchant_name"] ?? ""),
            "server_time" => time(),
        ];
    }

    protected function walletActiveFreezeRecords(int $userId): array
    {
        if ($userId <= 0) {
            return [];
        }
        return Db::name("wallet_freeze")
            ->where("appid", $this->appid)
            ->where("user_id", $userId)
            ->where("status", 1)
            ->whereRaw("amount > 0")
            ->order("id", "desc")
            ->limit(10)
            ->select()
            ->map(function ($row) {
                $amount = $this->walletAmountLabel($row["amount"] ?? 0);
                return [
                    "freeze_no" => (string)($row["freeze_no"] ?? ""),
                    "amount" => $amount,
                    "amount_label" => "¥" . $amount,
                    "reason" => (string)($row["reason"] ?? ""),
                    "create_time" => (string)($row["create_time"] ?? ""),
                    "update_time" => (string)($row["update_time"] ?? ""),
                ];
            })
            ->toArray();
    }

    protected function walletOrderStatusName(int $status): string
    {
        return match ($status) {
            1 => "已支付",
            2 => "已取消",
            3 => "已过期",
            default => "待支付",
        };
    }

    protected function assertWalletQrOrderActive(array $order): void
    {
        if (!$order) {
            throw new \Exception("二维码无效");
        }
        $status = (int)($order["status"] ?? 0);
        $type = (string)($order["order_type"] ?? "");
        $name = $type === "pay" ? "付款码" : "收款码";
        if ($status === 0) {
            $expireTime = strtotime((string)($order["expire_time"] ?? ""));
            if ($expireTime > 0 && $expireTime < time()) {
                Db::name("wallet_order")->where("id", (int)$order["id"])->where("status", 0)->update([
                    "status" => 3,
                    "update_time" => date("Y-m-d H:i:s"),
                ]);
                throw new \Exception($name . "已过期");
            }
            return;
        }
        if ($status === 1) {
            throw new \Exception($name . "已使用");
        }
        if ($status === 2) {
            throw new \Exception($name . "已取消");
        }
        if ($status === 3) {
            throw new \Exception($name . "已过期");
        }
        throw new \Exception($name . "状态异常");
    }

    protected function walletPayCodeVerifyCacheKey(array $data): string
    {
        $device = trim((string)($data["device"] ?? Request::header("device", "")));
        $device = preg_replace("/[^A-Za-z0-9_-]/", "", $device) ?: "unknown";
        return $this->appid . ":wallet_pay_code_verified:" . (int)$this->user_info["id"] . ":" . md5($device);
    }

    protected function assertWalletPayCodeVerified(array $data): void
    {
        $this->assertWalletPayPasswordReady((int)$this->user_info["id"]);
        $cacheKey = $this->walletPayCodeVerifyCacheKey($data);
        if (Cache::get($cacheKey)) {
            return;
        }
        $payPassword = trim((string)($data["pay_password"] ?? ""));
        if ($payPassword === "") {
            throw new \Exception("请输入支付密码");
        }
        $this->verifyWalletPayPassword((int)$this->user_info["id"], $payPassword);
        Cache::set($cacheKey, 1, 300);
    }

    protected function walletBillSceneName(int $type): string
    {
        return match ($type) {
            7 => "提现",
            8 => "卡密充值",
            9 => "红包/转账",
            11 => "扫码收付款",
            12 => "OTC保证金",
            default => "余额变动",
        };
    }

    protected function walletRequestId($value): string
    {
        $requestId = trim((string)$value);
        if (!preg_match("/^[A-Za-z0-9_-]{8,64}$/", $requestId)) {
            throw new \Exception("request_id不合法");
        }
        return $requestId;
    }

    protected function walletOrderQuery()
    {
        return Db::name("wallet_order")
            ->alias("o")
            ->leftJoin("user pu", "pu.id=o.payer_id and pu.appid=o.appid")
            ->leftJoin("user ru", "ru.id=o.payee_id and ru.appid=o.appid")
            ->field("o.*,pu.username as payer_username,pu.nickname as payer_nickname,pu.usertx as payer_avatar,ru.username as payee_username,ru.nickname as payee_nickname,ru.usertx as payee_avatar");
    }

    protected function walletOrderWithUsers(int $orderId): array
    {
        return $this->walletOrderQuery()->where("o.id", $orderId)->find() ?: [];
    }

    protected function walletQrPayload(array $order): string
    {
        $token = (string)($order["qr_token"] ?? "");
        if ($token === "") {
            return "";
        }
        $host = (string)($order["order_type"] ?? "") === "pay" ? "pay" : "collect";
        return "bim://wallet/" . $host . "?token=" . rawurlencode($token);
    }

    protected function formatWalletOrder(array $order, bool $exposeQrToken = false): array
    {
        $payerName = trim((string)($order["payer_nickname"] ?? "")) ?: (string)($order["payer_username"] ?? "");
        $payeeName = trim((string)($order["payee_nickname"] ?? "")) ?: (string)($order["payee_username"] ?? "");
        $amount = $this->walletAmountLabel($order["amount"] ?? 0);
        $amountRequired = $this->walletAmountToCents($amount) > 0 ? 1 : 0;
        $expireAt = strtotime((string)($order["expire_time"] ?? ""));
        $expireSeconds = $expireAt > 0 ? max(0, $expireAt - time()) : 0;
        $payload = [
            "id" => (int)$order["id"],
            "order_no" => (string)$order["order_no"],
            "order_type" => (string)$order["order_type"],
            "amount" => $amount,
            "amount_label" => $amount,
            "amount_required" => $amountRequired,
            "remark" => (string)($order["remark"] ?? ""),
            "status" => (int)$order["status"],
            "status_name" => $this->walletOrderStatusName((int)$order["status"]),
            "payer_id" => (int)($order["payer_id"] ?? 0),
            "payer_name" => $payerName,
            "payer_avatar" => (string)($order["payer_avatar"] ?? ""),
            "payee_id" => (int)($order["payee_id"] ?? 0),
            "payee_name" => $payeeName,
            "payee_avatar" => (string)($order["payee_avatar"] ?? ""),
            "expire_time" => (string)($order["expire_time"] ?? ""),
            "expire_seconds" => $expireSeconds,
            "refresh_in" => (string)($order["order_type"] ?? "") === "pay" ? min(55, $expireSeconds) : 0,
            "paid_time" => (string)($order["paid_time"] ?? ""),
            "create_time" => (string)($order["create_time"] ?? ""),
            "current_user_role" => (int)($order["payer_id"] ?? 0) === (int)$this->user_info["id"] ? "payer" : (((int)($order["payee_id"] ?? 0) === (int)$this->user_info["id"]) ? "payee" : "scanner"),
        ];
        if ($exposeQrToken) {
            $payload["qr_token"] = (string)($order["qr_token"] ?? "");
            $payload["qr_payload"] = $this->walletQrPayload($order);
            $payload["bar_payload"] = (string)($order["qr_token"] ?? "");
        }
        return $payload;
    }

    protected function walletApplyBillSceneFilter($query, string $scene): void
    {
        if ($scene === "income") {
            $query->whereLike("transaction_amount", "+%");
        } elseif ($scene === "expense") {
            $query->whereLike("transaction_amount", "-%");
        } elseif ($scene === "withdraw") {
            $query->where("transaction_type", 7);
        } elseif ($scene === "charge") {
            $query->where("transaction_type", 8);
        } elseif ($scene === "im") {
            $query->where("transaction_type", 9);
        } elseif ($scene === "scan") {
            $query->where("transaction_type", 11);
        } elseif ($scene === "otc") {
            $query->where("transaction_type", 12);
        }
    }

    protected function walletBillOrderNo(string $remark): string
    {
        if (preg_match("/订单号[:：]\\s*([A-Za-z0-9_-]+)/u", $remark, $match)) {
            return (string)$match[1];
        }
        if (preg_match("/交易单号[:：]\\s*([A-Za-z0-9_-]+)/u", $remark, $match)) {
            return (string)$match[1];
        }
        return "";
    }

    protected function walletBillTargetName(string $remark): string
    {
        $patterns = [
            "/扫码付款给([^，,]+)/u",
            "/扫码收款来自([^，,]+)/u",
            "/付款码付款给([^，,]+)/u",
            "/付款码收款来自([^，,]+)/u",
            "/转账给([^，,]+)/u",
            "/收到([^，,]+)转账/u",
            "/领取([^，,]+)的红包/u",
            "/发送红包给([^，,]+)/u",
        ];
        foreach ($patterns as $pattern) {
            if (preg_match($pattern, $remark, $match)) {
                return trim((string)$match[1]);
            }
        }
        return "";
    }

    protected function formatWalletBill(array $row): array
    {
        $raw = trim((string)($row["transaction_amount"] ?? "0"));
        if ($raw === "") {
            $raw = "0";
        }
        $negative = ($raw[0] ?? "") === "-";
        $amount = $this->walletAmountLabel(ltrim($raw, "+-"));
        $type = (int)($row["transaction_type"] ?? 0);
        $remark = (string)($row["remark"] ?? "");
        $orderNo = $this->walletBillOrderNo($remark);
        return [
            "id" => (int)($row["id"] ?? 0),
            "bill_no" => "BILL" . (int)($row["id"] ?? 0),
            "order_no" => $orderNo,
            "scene" => (string)$type,
            "scene_name" => $this->walletBillSceneName($type),
            "transaction_type" => $type,
            "direction" => $negative ? "expense" : "income",
            "direction_name" => $negative ? "支出" : "收入",
            "amount" => $amount,
            "amount_label" => ($negative ? "-¥" : "+¥") . $amount,
            "target_name" => $this->walletBillTargetName($remark),
            "target_avatar" => "",
            "status" => (int)($row["frozen"] ?? 0) === 1 ? 0 : 1,
            "status_name" => (int)($row["frozen"] ?? 0) === 1 ? "冻结中" : "交易成功",
            "remark" => $remark,
            "balance_after" => "",
            "created_at" => (string)($row["transaction_date"] ?? ""),
            "transaction_date" => (string)($row["transaction_date"] ?? ""),
            "frozen" => (int)($row["frozen"] ?? 0),
        ];
    }

    protected function expireWalletOrderIfNeeded(array $order): void
    {
        if ((int)($order["status"] ?? 0) !== 0) {
            return;
        }
        $expireTime = strtotime((string)($order["expire_time"] ?? ""));
        if ($expireTime > 0 && $expireTime < time()) {
            Db::name("wallet_order")->where("id", (int)$order["id"])->where("status", 0)->update([
                "status" => 3,
                "update_time" => date("Y-m-d H:i:s"),
            ]);
        }
    }

    protected function walletOrderByToken(string $token): array
    {
        if (!preg_match("/^[a-f0-9]{48}$/", $token)) {
            throw new \Exception("二维码无效");
        }
        $query = $this->walletOrderQuery()
            ->where("o.appid", $this->appid)
            ->where("o.qr_token_hash", $this->walletQrTokenHash($token));
        $order = $query->find();
        if (!$order) {
            throw new \Exception("二维码无效");
        }
        $this->expireWalletOrderIfNeeded($order);
        return $this->walletOrderWithUsers((int)$order["id"]);
    }

    protected function walletOrderByNoForCurrentUser(string $orderNo): array
    {
        $orderNo = trim($orderNo);
        if ($orderNo === "" || !preg_match("/^[A-Za-z0-9_-]{8,64}$/", $orderNo)) {
            throw new \Exception("订单号无效");
        }
        $order = $this->walletOrderQuery()
            ->where("o.appid", $this->appid)
            ->where("o.order_no", $orderNo)
            ->where(function ($query) {
                $query->where("o.payer_id", (int)$this->user_info["id"])->whereOr("o.payee_id", (int)$this->user_info["id"]);
            })
            ->find();
        if (!$order) {
            throw new \Exception("订单不存在");
        }
        $this->expireWalletOrderIfNeeded($order);
        return $this->walletOrderWithUsers((int)$order["id"]);
    }

    protected function payWalletOrder(array $order, array $payer, string $payPassword, string $amountInput, string $requestId): array
    {
        if ((string)($order["order_type"] ?? "") !== "collect") {
            throw new \Exception("订单类型不正确");
        }
        if ((int)$order["payee_id"] === (int)$payer["id"]) {
            throw new \Exception("不能向自己付款");
        }
        if ((int)$order["payer_id"] > 0 && (int)$order["payer_id"] !== (int)$payer["id"]) {
            throw new \Exception("该付款码不属于当前用户");
        }
        $this->verifyWalletPayPassword((int)$payer["id"], $payPassword);
        Db::startTrans();
        try {
            $lockedOrder = Db::name("wallet_order")->where("id", (int)$order["id"])->lock(true)->find();
            if (!$lockedOrder) {
                throw new \Exception("订单不存在");
            }
            $this->expireWalletOrderIfNeeded($lockedOrder);
            $lockedOrder = Db::name("wallet_order")->where("id", (int)$order["id"])->lock(true)->find();
            if ((int)$lockedOrder["status"] !== 0) {
                if ((int)$lockedOrder["status"] === 1 && (string)($lockedOrder["confirm_request_id"] ?? "") === $requestId) {
                    Db::commit();
                    return $this->walletOrderWithUsers((int)$lockedOrder["id"]);
                }
                throw new \Exception($this->walletOrderStatusName((int)$lockedOrder["status"]));
            }
            $payee = Db::name("user")->where("appid", $this->appid)->where("id", (int)$lockedOrder["payee_id"])->lock(true)->find();
            $payerLocked = Db::name("user")->where("appid", $this->appid)->where("id", (int)$payer["id"])->lock(true)->find();
            if (!$payee || !$payerLocked) {
                throw new \Exception("用户不存在");
            }
            $orderAmount = $this->walletAmountLabel($lockedOrder["amount"] ?? 0);
            $amount = $this->walletAmountToCents($orderAmount) > 0 ? $orderAmount : $this->normalizeWalletMoney($amountInput);
            $this->assertWalletMoneyAvailable($payerLocked, $amount);
            Db::name("user")->where("id", $payerLocked["id"])->where("appid", $this->appid)->update(["money" => Db::raw("money - " . $amount)]);
            Db::name("user")->where("id", $payee["id"])->where("appid", $this->appid)->update(["money" => Db::raw("money + " . $amount)]);
            add_user_bill($payerLocked, 11, "-" . $amount, "扫码付款给" . ($payee["nickname"] ?: $payee["username"]) . "，订单号：" . $lockedOrder["order_no"], 0, 0);
            add_user_bill($payee, 11, "+" . $amount, "扫码收款来自" . ($payerLocked["nickname"] ?: $payerLocked["username"]) . "，订单号：" . $lockedOrder["order_no"], 0, 0);
            Db::name("wallet_order")->where("id", (int)$lockedOrder["id"])->update([
                "payer_id" => (int)$payerLocked["id"],
                "amount" => $amount,
                "confirm_request_id" => $requestId,
                "status" => 1,
                "paid_time" => date("Y-m-d H:i:s"),
                "update_time" => date("Y-m-d H:i:s"),
            ]);
            Db::commit();
        } catch (\Throwable $e) {
            Db::rollback();
            throw $e;
        }
        return $this->walletOrderWithUsers((int)$order["id"]);
    }

    protected function requestWalletPayCodeCollection(array $order, array $payee, string $amountInput): array
    {
        if ((string)($order["order_type"] ?? "") !== "pay") {
            throw new \Exception("订单类型不正确");
        }
        if ((int)$order["payer_id"] === (int)$payee["id"]) {
            throw new \Exception("不能扫描自己的付款码");
        }
        $this->assertMerchantEnabled($payee);
        $amount = $this->normalizeWalletMoney($amountInput);
        Db::startTrans();
        try {
            $lockedOrder = Db::name("wallet_order")->where("id", (int)$order["id"])->lock(true)->find();
            if (!$lockedOrder) {
                throw new \Exception("订单不存在");
            }
            $this->expireWalletOrderIfNeeded($lockedOrder);
            $lockedOrder = Db::name("wallet_order")->where("id", (int)$order["id"])->lock(true)->find();
            if ((int)$lockedOrder["status"] !== 0) {
                throw new \Exception($this->walletOrderStatusName((int)$lockedOrder["status"]));
            }
            if ((int)$lockedOrder["payer_id"] <= 0 || (int)$lockedOrder["payer_id"] === (int)$payee["id"]) {
                throw new \Exception("付款码付款方不正确");
            }
            if ((int)($lockedOrder["payee_id"] ?? 0) > 0 && (int)$lockedOrder["payee_id"] !== (int)$payee["id"]) {
                throw new \Exception("付款码已被其他收款方处理");
            }
            $existingAmount = $this->walletAmountLabel($lockedOrder["amount"] ?? 0);
            if ((int)($lockedOrder["payee_id"] ?? 0) === (int)$payee["id"] && $this->walletAmountToCents($existingAmount) > 0 && $existingAmount !== $amount) {
                throw new \Exception("付款确认已发起，请等待付款方确认");
            }
            Db::name("wallet_order")->where("id", (int)$lockedOrder["id"])->update([
                "payee_id" => (int)$payee["id"],
                "amount" => $amount,
                "expire_time" => date("Y-m-d H:i:s", time() + 300),
                "update_time" => date("Y-m-d H:i:s"),
            ]);
            Db::commit();
        } catch (\Throwable $e) {
            Db::rollback();
            throw $e;
        }
        return $this->walletOrderWithUsers((int)$order["id"]);
    }

    protected function confirmWalletPayCodeByOwner(array $order, array $payer, string $payPassword, string $requestId): array
    {
        if ((string)($order["order_type"] ?? "") !== "pay") {
            throw new \Exception("订单类型不正确");
        }
        if ((int)$order["payer_id"] !== (int)$payer["id"]) {
            throw new \Exception("付款码不属于当前用户");
        }
        $this->verifyWalletPayPassword((int)$payer["id"], $payPassword);
        Db::startTrans();
        try {
            $lockedOrder = Db::name("wallet_order")->where("id", (int)$order["id"])->lock(true)->find();
            if (!$lockedOrder) {
                throw new \Exception("订单不存在");
            }
            $this->expireWalletOrderIfNeeded($lockedOrder);
            $lockedOrder = Db::name("wallet_order")->where("id", (int)$order["id"])->lock(true)->find();
            if ((int)$lockedOrder["status"] !== 0) {
                if ((int)$lockedOrder["status"] === 1 && (string)($lockedOrder["confirm_request_id"] ?? "") === $requestId) {
                    Db::commit();
                    return $this->walletOrderWithUsers((int)$lockedOrder["id"]);
                }
                throw new \Exception($this->walletOrderStatusName((int)$lockedOrder["status"]));
            }
            if ((int)($lockedOrder["payee_id"] ?? 0) <= 0) {
                throw new \Exception("商户收款请求不存在");
            }
            $amount = $this->walletAmountLabel($lockedOrder["amount"] ?? 0);
            if ($this->walletAmountToCents($amount) <= 0) {
                throw new \Exception("付款金额无效");
            }
            $payerLocked = Db::name("user")->where("appid", $this->appid)->where("id", (int)$lockedOrder["payer_id"])->lock(true)->find();
            $payeeLocked = Db::name("user")->where("appid", $this->appid)->where("id", (int)$lockedOrder["payee_id"])->lock(true)->find();
            if (!$payerLocked || !$payeeLocked) {
                throw new \Exception("用户不存在");
            }
            $this->assertMerchantEnabled($payeeLocked);
            $this->assertWalletMoneyAvailable($payerLocked, $amount);
            Db::name("user")->where("id", $payerLocked["id"])->where("appid", $this->appid)->update(["money" => Db::raw("money - " . $amount)]);
            Db::name("user")->where("id", $payeeLocked["id"])->where("appid", $this->appid)->update(["money" => Db::raw("money + " . $amount)]);
            add_user_bill($payerLocked, 11, "-" . $amount, "付款码付款给" . ($payeeLocked["nickname"] ?: $payeeLocked["username"]) . "，订单号：" . $lockedOrder["order_no"], 0, 0);
            add_user_bill($payeeLocked, 11, "+" . $amount, "付款码收款来自" . ($payerLocked["nickname"] ?: $payerLocked["username"]) . "，订单号：" . $lockedOrder["order_no"], 0, 0);
            Db::name("wallet_order")->where("id", (int)$lockedOrder["id"])->update([
                "amount" => $amount,
                "confirm_request_id" => $requestId,
                "status" => 1,
                "paid_time" => date("Y-m-d H:i:s"),
                "update_time" => date("Y-m-d H:i:s"),
            ]);
            Db::commit();
        } catch (\Throwable $e) {
            Db::rollback();
            throw $e;
        }
        return $this->walletOrderWithUsers((int)$order["id"]);
    }

    protected function chatTransactionNo(string $table, string $prefix): string
    {
        $prefix = strtoupper(preg_replace('/[^A-Z0-9]/', '', $prefix));
        if ($prefix === '') {
            $prefix = 'TX';
        }
        for ($i = 0; $i < 5; $i++) {
            $random = strtoupper(substr(md5(uniqid((string)mt_rand(), true)), 0, 16));
            $transactionNo = $prefix . date('YmdHis') . $random;
            if (!Db::name($table)->where('transaction_no', $transactionNo)->find()) {
                return $transactionNo;
            }
            usleep(1000);
        }
        throw new \Exception("交易单号生成失败");
    }

    protected function createPersonTransfer(array $sender, array $receiver, $money, string $assetType, string $clientMsgNo): array
    {
        return $this->createTransfer($sender, $receiver, $money, $assetType, $clientMsgNo, 0, $this->wukongUid($receiver["id"]));
    }

    protected function createGroupTransfer(array $sender, array $receiver, array $group, $money, string $assetType, string $clientMsgNo): array
    {
        if ((int)$sender["id"] === (int)$receiver["id"]) {
            throw new \Exception("不能给自己转账");
        }
        return $this->createTransfer($sender, $receiver, $money, $assetType, $clientMsgNo, (int)$group["id"], (string)$group["channel_id"]);
    }

    protected function createTransfer(array $sender, array $receiver, $money, string $assetType, string $clientMsgNo, int $groupId, string $channelId): array
    {
        $assetType = $this->normalizeAssetType($assetType);
        $amount = $this->normalizeChatAssetAmount($money, $assetType);
        if ($sender["id"] == $receiver["id"]) {
            throw new \Exception("不能给自己转账");
        }

        $sender = Db::name("user")->where("id", $sender["id"])->where("appid", $this->appid)->lock(true)->find();
        $receiver = Db::name("user")->where("id", $receiver["id"])->where("appid", $this->appid)->lock(true)->find();
        if (!$sender || !$receiver) {
            throw new \Exception("用户不存在");
        }

        $field = $this->assetField($assetType);
        $billType = $this->assetBillType($assetType);
        $feeRate = max(0, (float)($this->app_info["forum_configuration"]["transfer_handling_fee"] ?? 0));
        $amountUnits = $this->chatAssetUnitValue($amount, $assetType);
        $feeUnits = (int)floor($amountUnits * $feeRate);
        $fee = $this->chatAssetFromUnitValue($feeUnits, $assetType);
        $deductionMethod = (int)($this->app_info["forum_configuration"]["deduction_method_for_handling_fees"] ?? 1);
        $senderDeductUnits = $deductionMethod === 1 ? $amountUnits + $feeUnits : $amountUnits;
        $receiverIncreaseUnits = $deductionMethod === 1 ? $amountUnits : max(0, $amountUnits - $feeUnits);
        $senderDeduct = $this->chatAssetFromUnitValue($senderDeductUnits, $assetType);
        $receiverIncrease = $this->chatAssetFromUnitValue($receiverIncreaseUnits, $assetType);

        $this->assertAssetBalance($sender, $assetType, $senderDeduct);

        $transactionNo = $this->chatTransactionNo("wukongim_transfer", "TR");
        $expireSeconds = (int)$this->chatControl()['transfer_receive_expire'];
        $expireTime = date("Y-m-d H:i:s", time() + $expireSeconds);

        Db::name("user")->where("id", $sender["id"])->where("appid", $this->appid)->update([$field => Db::raw($field . " - " . $senderDeduct)]);
        add_user_bill($sender, 9, "-" . $senderDeduct, "转账给" . $receiver["nickname"] . "，交易单号：" . $transactionNo . "，待收款，手续费：" . $fee, $billType);

        $transferId = Db::name("wukongim_transfer")->insertGetId([
            "appid" => $this->appid,
            "transaction_no" => $transactionNo,
            "sender_id" => (int)$sender["id"],
            "receiver_id" => (int)$receiver["id"],
            "group_id" => $groupId,
            "channel_id" => $channelId,
            "amount" => $amount,
            "asset_type" => $assetType,
            "fee" => $fee,
            "sender_deduct" => $senderDeduct,
            "receiver_increase" => $receiverIncrease,
            "status" => 0,
            "client_msg_no" => $clientMsgNo,
            "message_id" => "",
            "expire_time" => $expireTime,
            "create_time" => date("Y-m-d H:i:s"),
            "update_time" => date("Y-m-d H:i:s"),
        ]);

        return [
            "transfer_id" => $transferId,
            "transaction_no" => $transactionNo,
            "amount" => $amount,
            "amount_label" => $this->chatAssetAmountLabel($amount, $assetType),
            "asset_type" => $assetType,
            "fee" => $fee,
            "sender_deduct" => $senderDeduct,
            "receiver_increase" => $receiverIncrease,
            "status" => 0,
            "status_name" => "待收款",
            "group_id" => $groupId,
            "channel_id" => $channelId,
            "receiver_id" => (int)$receiver["id"],
            "receiver_uid" => $this->wukongUid($receiver["id"]),
            "expire_time" => $expireTime,
        ];
    }

    protected function refundExpiredTransfer(array $transfer): void
    {
        if ((int)$transfer['status'] !== 0) {
            return;
        }
        $assetType = (string)$transfer["asset_type"];
        $refundAmount = $this->chatAssetAmountLabel($transfer["sender_deduct"] ?? 0, $assetType);
        $sender = Db::name("user")->where("id", $transfer["sender_id"])->where("appid", $this->appid)->lock(true)->find();
        if (!$sender) {
            throw new \Exception("发送用户不存在");
        }
        $field = $this->assetField($assetType);
        Db::name("user")->where("id", $sender["id"])->where("appid", $this->appid)->update([
            $field => Db::raw($field . ' + ' . $refundAmount),
        ]);
        $transactionNo = (string)($transfer["transaction_no"] ?? "");
        $remark = "转账超时退回" . ($transactionNo !== "" ? "，交易单号：" . $transactionNo : "");
        add_user_bill($sender, 9, "+" . $refundAmount, $remark, $this->assetBillType($assetType));
        Db::name("wukongim_transfer")->where("id", $transfer["id"])->where("status", 0)->update([
            "status" => 2,
            "refund_time" => date("Y-m-d H:i:s"),
            "update_time" => date("Y-m-d H:i:s"),
        ]);
        $this->sendWalletRefundNotice($sender, "transfer", $refundAmount, $assetType, $transactionNo);
    }

    protected function refreshExpiredTransfer(int $transferId): array
    {
        $transfer = Db::name("wukongim_transfer")->where("id", $transferId)->find();
        if (!$transfer || (int)$transfer['status'] !== 0 || empty($transfer['expire_time']) || strtotime((string)$transfer['expire_time']) >= time()) {
            return $transfer ?: [];
        }
        Db::startTrans();
        try {
            $locked = Db::name("wukongim_transfer")->where("id", $transferId)->lock(true)->find();
            if ($locked && (int)$locked['status'] === 0 && !empty($locked['expire_time']) && strtotime((string)$locked['expire_time']) < time()) {
                $this->refundExpiredTransfer($locked);
            }
            Db::commit();
        } catch (\Exception $e) {
            Db::rollback();
            throw $e;
        }
        return Db::name("wukongim_transfer")->where("id", $transferId)->find() ?: [];
    }

    protected function refundExpiredRedPacket(array $redPacket): void
    {
        if ((int)$redPacket['status'] !== 0) {
            return;
        }
        $assetType = (string)$redPacket["asset_type"];
        $refundAmount = $this->chatAssetAmountLabel($redPacket["remaining_amount"] ?? $redPacket["amount"] ?? 0, $assetType);
        $now = date("Y-m-d H:i:s");
        $sender = [];
        $transactionNo = (string)($redPacket["transaction_no"] ?? "");
        if ($this->chatAssetCompare($refundAmount, 0, $assetType) > 0) {
            $sender = Db::name("user")->where("id", $redPacket["sender_id"])->where("appid", $this->appid)->lock(true)->find();
            if (!$sender) {
                throw new \Exception("发送用户不存在");
            }
            $field = $this->assetField($assetType);
            Db::name("user")->where("id", $sender["id"])->where("appid", $this->appid)->update([
                $field => Db::raw($field . ' + ' . $refundAmount),
            ]);
            $remark = "红包过期退回" . ($transactionNo !== "" ? "，交易单号：" . $transactionNo : "");
            add_user_bill($sender, 9, "+" . $refundAmount, $remark, $this->assetBillType($assetType));
        }
        Db::name("wukongim_red_packet")->where("id", $redPacket["id"])->where("status", 0)->update([
            "status" => 2,
            "remaining_amount" => $this->chatAssetAmountLabel(0, $assetType),
            "refund_amount" => $refundAmount,
            "refund_time" => $now,
            "update_time" => $now,
        ]);
        if ($sender) {
            $this->sendWalletRefundNotice($sender, "red_packet", $refundAmount, $assetType, $transactionNo);
        }
    }

    protected function refreshExpiredRedPacket(int $redPacketId): array
    {
        $redPacket = Db::name("wukongim_red_packet")->where("id", $redPacketId)->find();
        if (!$redPacket || (int)$redPacket['status'] !== 0 || empty($redPacket['expire_time']) || strtotime((string)$redPacket['expire_time']) >= time()) {
            return $redPacket ?: [];
        }
        Db::startTrans();
        try {
            $locked = Db::name("wukongim_red_packet")->where("id", $redPacketId)->lock(true)->find();
            if ($locked && (int)$locked['status'] === 0 && !empty($locked['expire_time']) && strtotime((string)$locked['expire_time']) < time()) {
                $this->refundExpiredRedPacket($locked);
            }
            Db::commit();
        } catch (\Exception $e) {
            Db::rollback();
            throw $e;
        }
        return Db::name("wukongim_red_packet")->where("id", $redPacketId)->find() ?: [];
    }

    protected function createPersonRedPacket(array $sender, array $receiver, $money, string $assetType, string $remark): array
    {
        $assetType = $this->normalizeAssetType($assetType);
        $amount = $this->normalizeChatAssetAmount($money, $assetType);
        if ($sender["id"] == $receiver["id"]) {
            throw new \Exception("不能给自己发红包");
        }

        $sender = Db::name("user")->where("id", $sender["id"])->where("appid", $this->appid)->lock(true)->find();
        $receiver = Db::name("user")->where("id", $receiver["id"])->where("appid", $this->appid)->lock(true)->find();
        if (!$sender || !$receiver) {
            throw new \Exception("用户不存在");
        }

        $field = $this->assetField($assetType);
        $billType = $this->assetBillType($assetType);
        $this->assertAssetBalance($sender, $assetType, $amount);

        $transactionNo = $this->chatTransactionNo("wukongim_red_packet", "RP");
        $expireSeconds = (int)$this->chatControl()['red_packet_receive_expire'];
        $expireTime = date("Y-m-d H:i:s", time() + $expireSeconds);

        Db::name("user")->where("id", $sender["id"])->where("appid", $this->appid)->update([$field => Db::raw($field . " - " . $amount)]);
        add_user_bill($sender, 9, "-" . $amount, "发送红包给" . $receiver["nickname"] . "，交易单号：" . $transactionNo, $billType);

        $redPacketId = Db::name("wukongim_red_packet")->insertGetId([
            "appid" => $this->appid,
            "transaction_no" => $transactionNo,
            "sender_id" => $sender["id"],
            "receiver_id" => $receiver["id"],
            "amount" => $amount,
            "remaining_amount" => $amount,
            "quantity" => 1,
            "packet_type" => "ordinary",
            "receive_count" => 0,
            "asset_type" => $assetType,
            "status" => 0,
            "remark" => $remark,
            "expire_time" => $expireTime,
            "create_time" => date("Y-m-d H:i:s"),
            "update_time" => date("Y-m-d H:i:s"),
        ]);

        return [
            "red_packet_id" => $redPacketId,
            "transaction_no" => $transactionNo,
            "amount" => $amount,
            "amount_label" => $this->chatAssetAmountLabel($amount, $assetType),
            "asset_type" => $assetType,
            "remark" => $remark,
            "status" => 0,
            "status_name" => "待领取",
            "remaining_amount" => $amount,
            "quantity" => 1,
            "packet_type" => "ordinary",
            "receiver_id" => (int)$receiver["id"],
            "receive_count" => 0,
            "expire_time" => $expireTime,
        ];
    }

    protected function normalizeGroupRedPacketType(string $packetType): string
    {
        $packetType = strtolower(trim($packetType));
        if ($packetType === '') {
            return 'ordinary';
        }
        if (!in_array($packetType, ['ordinary', 'luck', 'specified'], true)) {
            throw new \Exception("红包类型不合法");
        }
        return $packetType;
    }

    protected function normalizeGroupRedPacketOptions(array $sender, array $group, string $packetType, int $quantity, int $receiverId): array
    {
        $packetType = $this->normalizeGroupRedPacketType($packetType);
        $memberCount = (int)Db::name("chat_group_member")->where("appid", $this->appid)->where("group_id", $group["id"])->where("status", 1)->count();
        if ($memberCount < 2) {
            throw new \Exception("群红包至少需要两名群成员");
        }
        if ($packetType === 'specified') {
            $receiver = $this->groupMemberUser($group, $receiverId);
            if ((int)$receiver["id"] === (int)$sender["id"]) {
                throw new \Exception("不能给自己发红包");
            }
            return [
                "packet_type" => $packetType,
                "quantity" => 1,
                "receiver_id" => (int)$receiver["id"],
                "member_count" => $memberCount,
            ];
        }
        return [
            "packet_type" => $packetType,
            "quantity" => max(1, min($quantity, $memberCount)),
            "receiver_id" => 0,
            "member_count" => $memberCount,
        ];
    }

    protected function createGroupRedPacket(array $sender, array $group, $money, string $assetType, string $remark, int $quantity, string $packetType, int $receiverId = 0): array
    {
        $assetType = $this->normalizeAssetType($assetType);
        $amount = $this->normalizeChatAssetAmount($money, $assetType);
        $options = $this->normalizeGroupRedPacketOptions($sender, $group, $packetType, $quantity, $receiverId);
        $packetType = (string)$options["packet_type"];
        $quantity = (int)$options["quantity"];
        $receiverId = (int)$options["receiver_id"];
        if ($this->chatAssetUnitValue($amount, $assetType) < $quantity) {
            throw new \Exception("红包金额不能小于领取份数");
        }

        $sender = Db::name("user")->where("id", $sender["id"])->where("appid", $this->appid)->lock(true)->find();
        if (!$sender) {
            throw new \Exception("用户不存在");
        }

        $field = $this->assetField($assetType);
        $billType = $this->assetBillType($assetType);
        $this->assertAssetBalance($sender, $assetType, $amount);

        $transactionNo = $this->chatTransactionNo("wukongim_red_packet", "RP");
        $expireSeconds = (int)$this->chatControl()['red_packet_receive_expire'];
        $expireTime = date("Y-m-d H:i:s", time() + $expireSeconds);

        Db::name("user")->where("id", $sender["id"])->where("appid", $this->appid)->update([$field => Db::raw($field . " - " . $amount)]);
        add_user_bill($sender, 9, "-" . $amount, "发送群红包到" . $group["name"] . "，交易单号：" . $transactionNo, $billType);

        $redPacketId = Db::name("wukongim_red_packet")->insertGetId([
            "appid" => $this->appid,
            "transaction_no" => $transactionNo,
            "sender_id" => $sender["id"],
            "receiver_id" => $receiverId,
            "group_id" => (int)$group["id"],
            "channel_id" => (string)$group["channel_id"],
            "amount" => $amount,
            "remaining_amount" => $amount,
            "quantity" => $quantity,
            "packet_type" => $packetType,
            "receive_count" => 0,
            "asset_type" => $assetType,
            "status" => 0,
            "remark" => $remark,
            "expire_time" => $expireTime,
            "create_time" => date("Y-m-d H:i:s"),
            "update_time" => date("Y-m-d H:i:s"),
        ]);

        return [
            "red_packet_id" => $redPacketId,
            "transaction_no" => $transactionNo,
            "amount" => $amount,
            "amount_label" => $this->chatAssetAmountLabel($amount, $assetType),
            "asset_type" => $assetType,
            "remark" => $remark,
            "status" => 0,
            "status_name" => "待领取",
            "group_id" => (int)$group["id"],
            "channel_id" => (string)$group["channel_id"],
            "quantity" => $quantity,
            "packet_type" => $packetType,
            "receiver_id" => $receiverId,
            "remaining_amount" => $amount,
            "receive_count" => 0,
            "expire_time" => $expireTime,
        ];
    }

    protected function groupRedPacketReceiveAmount(array $redPacket): string
    {
        $assetType = (string)($redPacket["asset_type"] ?? "money");
        $quantity = max(1, (int)($redPacket["quantity"] ?? 1));
        $receiveCount = (int)($redPacket["receive_count"] ?? 0);
        $remainingAmount = $this->chatAssetUnitValue($redPacket["remaining_amount"] ?? $redPacket["amount"], $assetType);
        if ($receiveCount + 1 >= $quantity) {
            return $this->chatAssetFromUnitValue($remainingAmount, $assetType);
        }
        $packetType = (string)($redPacket["packet_type"] ?? 'ordinary');
        if ($packetType === 'luck') {
            $remainingQuantity = max(1, $quantity - $receiveCount);
            $max = $remainingAmount - ($remainingQuantity - 1);
            return $this->chatAssetFromUnitValue(mt_rand(1, max(1, $max)), $assetType);
        }
        $baseAmount = max(1, (int)floor($this->chatAssetUnitValue($redPacket["amount"], $assetType) / $quantity));
        return $this->chatAssetFromUnitValue(min($remainingAmount, $baseAmount), $assetType);
    }

    //获取APP信息
    public function get_app_info()
    {
        $result["appname"] = $this->app_info["appname"];
        $result["appicon"] = $this->app_info["appicon"];
        $result["application_introduction"] = $this->app_info["application_introduction"];
        $result["developer_contact_info"] = $this->app_info["developer_contact_info"];
        $result["official_group"] = $this->app_info["official_group"];
        $result["announcement_configuration"] = $this->app_info["announcement_configuration"];
        $arr = $this->app_info["grade"];
        $grades = eval("return $arr;");
        $result["grade"] = $grades;
        $app_exten_info = Db::name('app_exten')->where("appid={$this->appid}")->select()->toArray();
        $updates_info = Db::name("app_updates")->where("appid", "=", $this->appid)->order("create_time", "desc")->find();
        unset($updates_info["id"]);
        unset($updates_info["appid"]);
        unset($updates_info["create_time"]);
        $result["updates_info"] = $updates_info;
        $app_exten_array = [];
        foreach ($app_exten_info as $key => $value) {
            $app_exten_array[$value["name"]] = json_decode($value["data"], true) == null ? $value["data"] : json_decode($value["data"], true);
        }
        if (count($app_exten_array) == 0) {
            $app_exten_array = (object)[];
        }
        $result["app_exten_info"] = $app_exten_array;
        $login_configuration = $this->app_info["login_configuration"] ?? [];
        $registration_configuration = $this->app_info["registration_configuration"] ?? [];
        $login_switch = (int)($login_configuration["login_switch"] ?? 0);
        $login_code_switch = (int)($login_configuration["login_code_switch"] ?? 0);
        $registration_switch = (int)($registration_configuration["registration_switch"] ?? 0);
        $registration_code_switch = (int)($registration_configuration["registration_code_switch"] ?? 0);
        $registration_open = $registration_switch === 0;
        $result["login_configuration"] = $login_configuration;
        $result["registration_configuration"] = $registration_configuration;
        $result["auth_config"] = [
            "password_login_enabled" => $login_switch === 0 ? 1 : 0,
            "mobile_login_enabled" => $login_switch === 0 ? 1 : 0,
            "login_captcha_enabled" => ($login_switch === 0 && $login_code_switch === 1) ? 1 : 0,
            "login_image_captcha_enabled" => ($login_switch === 0 && $login_code_switch === 1) ? 1 : 0,
            "login_code_switch" => $login_code_switch,
            "register_enabled" => $registration_open ? 1 : 0,
            "username_register_enabled" => ($registration_open && in_array($registration_code_switch, [0, 1], true)) ? 1 : 0,
            "mobile_register_enabled" => ($registration_open && $registration_code_switch === 3) ? 1 : 0,
            "email_register_enabled" => ($registration_open && $registration_code_switch === 2) ? 1 : 0,
            "register_captcha_enabled" => ($registration_open && $registration_code_switch === 1) ? 1 : 0,
            "register_image_captcha_enabled" => ($registration_open && $registration_code_switch === 1) ? 1 : 0,
            "registration_code_switch" => $registration_code_switch,
        ];
        $bagge_list = Db::name("bagge")->where("appid", "=", $this->appid)->where("is_view", "=", 0)->field("is_view,appid", true)->select()->toArray();
        $result["bagge_list"] = $bagge_list;
        $this->json(1, 'success', $result);
    }

    //获取APP更新记录
    public function get_app_update_records()
    {
        $result = Db::name("app_updates")->where("appid", "=", $this->appid)->order("id", "desc")->select()->toArray();
        $pagecount = Db::name("app_updates")->where("appid", "=", $this->appid)->order("id", "desc")->count();
        $data_rs["list"] = $result;
        $data_rs["pagecount"] = ceil($pagecount / $this->limit) == 0 ? 1 : ceil($pagecount / $this->limit);
        $data_rs["current_number"] = $this->page;
        $this->json(1, "success", $data_rs);
    }

    //增加APP访问量
    public function add_view()
    {
        Db::name("polymorphic")->insert([
            "appid" => $this->appid,
            "create_time" => date("Y-m-d H:i:s", time()),
            "type" => 0
        ]);
        $this->json(1, 'success');
    }

    //获取APP相关统计数据
    public function get_app_statistical_data()
    {
        $data["today_view_count"] = Db::name('polymorphic')->where("appid", $this->appid)->where("type", 0)->whereTime('create_time', 'today')->count();
        $data["week_view_count"] = Db::name('polymorphic')->where("appid", $this->appid)->where("type", 0)->whereTime('create_time', 'week')->count();
        $data["month_view_count"] = Db::name('polymorphic')->where("appid", $this->appid)->where("type", 0)->whereTime('create_time', 'month')->count();
        $data["year_view_count"] = Db::name('polymorphic')->where("appid", $this->appid)->where("type", 0)->whereTime('create_time', 'year')->count();
        $data["view_count"] = Db::name('polymorphic')->where("appid", $this->appid)->where("type", 0)->count();
        $data["today_user_count"] = Db::name('user')->where("appid", $this->appid)->whereTime('create_time', 'today')->count();
        $data["week_user_count"] = Db::name('user')->where("appid", $this->appid)->whereTime('create_time', 'week')->count();
        $data["month_user_count"] = Db::name('user')->where("appid", $this->appid)->whereTime('create_time', 'month')->count();
        $data["year_user_count"] = Db::name('user')->where("appid", $this->appid)->whereTime('create_time', 'year')->count();
        $data["user_count"] = Db::name('user')->where("appid", $this->appid)->count();
        $this->json(1, 'success', $data);
    }

    //用户登录
    public function login()
    {
        //判断是否开启登录
        if ($this->app_info["login_configuration"]["login_switch"] == 1) {
            $this->json(102, $this->app_info["login_configuration"]["login_closing_prompt"]);
        }
        $data = $this->securePublicRequestInput();
        $username = (string)($data["username"] ?? "");
        $password = (string)($data["password"] ?? "");
        $captcha = (string)($data["captcha"] ?? "");
        $device = (string)($data["device"] ?? "");
        $rule = [
            'username|用户名' => 'require|min:4',
            'password|密码' => 'require|min:4',
        ];
        $validate = new Validate();
        $validate->rule($rule);
        $result = $validate->check($data);
        if (!$validate->check($data)) {
            $this->json(0, $validate->getError());
        }
        //判断是否开启图片验证码
        if ($this->app_info["login_configuration"]["login_code_switch"] == 1) {
            $this->assertImageCaptchaScene("login", $captcha, true);
        }
        $user_info = Db::name('user')->where("appid", $this->appid)->where("username='{$username}'")->find();
        $update_user_info = [];
        if ($user_info) {
            //判断账号是否被封禁
            if ($user_info["reasons"] == 1) {
                if ($user_info["reasons_time"] > time()) {
                    $this->json(403, "你账号已被封禁，封禁理由为：" . $user_info["reasons_ban"] . ",解封时间为" . date("Y-m-d H:i:s", $user_info["reasons_time"]));
                } else {
                    Db::name("user")->where("id", $user_info["id"])->update([
                        'reasons' => 0,
                        'reasons_time' => 0,
                        'reasons_ban' => '',
                    ]);
                }
            }
            if (md5($password . $user_info['salt']) == $user_info['password']) {
                //判断异地登录是否开启
                if ($this->app_info["login_configuration"]["remote_login"] == 0 && $user_info['email'] != "") {
                    $now_user_ip = get_client_ip();
                    if ($user_info["ip"] != "" && $now_user_ip != $user_info["ip"]) {
                        $ip = new IpLocation();
                        $ip_address = $ip->getDetail($user_info["ip"])["dataA"];
                        $ip_now_address = $ip->getDetail($now_user_ip)["dataA"];
                        if ($ip_address != $ip_now_address) {
                            $mail = new Email($user_info['email']);
                            $temdata = [
                                '{appname}' => $this->app_info["appname"],
                                '{time}' => date("Y-m-d H:i:s", time()),
                                '{username}' => $user_info["username"],
                                '{nickname}' => $user_info["nickname"],
                                '{address}' => $ip_now_address,
                                '{ip}' => $now_user_ip
                            ];
                            //获取邮件模板
                            $tplList = '../extend/EmailTpl/tpl.php';
                            //获取邮件模板列表
                            if (file_exists($tplList)) {
                                $tplList = include $tplList;
                            } else {
                                $tplList = [];
                            }
                            if (!isset($tplList[2])) {
                                throw new \Exception('邮件模板不存在');
                            }
                            $tpl = $tplList[2];
                            $templateString = file_get_contents(app()->getRootPath() . $tpl['path']);
                            $templateString = strtr($templateString, $temdata);
                            $mail->setBody($templateString);
                            $mail->setSubject($this->app_info["appname"] . $tpl['name']);
                            $mail->setFrom($this->app_info["appname"]);
                            $result = $mail->send();
                        }
                    }
                }
                $usertoken = $this->issueUserDeviceSession((int)$user_info["id"], $device, $data);
                $update_user_info["ip"] = get_client_ip();
                Db::name("user")->where("id", $user_info["id"])->update($update_user_info);
                $result = [
                    "id" => $user_info["id"],
                    "username" => $username,
                    "usertoken" => $usertoken
                ];
                //判断当前发帖的用户是否是版主
                $plate_list = Db::name("forum_section")->where("appid", $this->appid)->select()->toArray();
                $result["is_section_moderator"] = 0;
                foreach ($plate_list as $key => $value) {
                    $section_id_array = explode(",", $value["forum_section"]);
                    if (in_array($user_info["id"], $section_id_array)) {
                        $result["is_section_moderator"] = 1;
                        break;
                    }
                }
                Cache::delete($this->appid . "login" . get_client_ip());
                $result = $this->appendWukongLoginPayload($result, (int)$user_info["id"], $usertoken);
                $this->securePublicJson(1, '登录成功', $result);
            }
            $this->json(0, '密码错误');
        }
        $this->json(0, '不存在此账号');
    }

    //获取图片验证码
    public function get_image_verification_code()
    {
        $type = input("type");
        if (!in_array($type, [1, 2, 3])) {
            $this->json(0, '请输入正确的type值');
        }
        //登录验证码
        if ($type == 1) {
            return CaptchaService::make($this->imageCaptchaKey("login"), 120);
        }
        //注册验证码
        if ($type == 2) {
            return CaptchaService::make($this->imageCaptchaKey("register"), 120);
        }
        return CaptchaService::make($this->imageCaptchaKey("security"), 120);
    }

    //手机号登录
    public function mobile_login()
    {
        //判断登录是否开启
        if ($this->app_info["login_configuration"]["login_switch"] == 1) {
            $this->json(102, $this->app_info["login_configuration"]["login_closing_prompt"]);
        }
        $data = $this->securePublicRequestInput();
        $mobile = (string)($data["mobile"] ?? "");
        $code = (string)($data["code"] ?? "");
        $captcha = (string)($data["captcha"] ?? "");
        $device = (string)($data["device"] ?? "");
        $rule = [
            'mobile|手机号' => 'require|mobile',
            'code|短信验证码' => 'require',
        ];
        $validate = new Validate();
        $validate->rule($rule);
        $result = $validate->check($data);
        if (!$result) {
            $this->json(0, $validate->getError());
        }
        //判断短信验证码是否正确
        $mobile_code_cache = $this->readVerificationCodeCache("mobile_login", $mobile);
        $phone_code_time = config("?system.phone_code_time") ? config("system.phone_code_time") : 300;
        if ($mobile_code_cache) {
            if (time() - $mobile_code_cache["time"] > $phone_code_time) {
                $this->json(0, "短信验证码已过期");
            }
            if ($code != $mobile_code_cache["code"]) {
                $this->json(0, "短信验证码不正确");
            }
            $mobile = $mobile_code_cache["mobile"];
        } else {
            $this->json(0, "请先发送短信验证码");
        }
        //判断图片验证码是否正确
        if ($this->app_info["login_configuration"]["login_code_switch"] == 1) {
            $this->assertImageCaptchaScene("login", $captcha, true);
        }
        $user_info = Db::name('user')->where("appid", $this->appid)->where("mobile='{$mobile}'")->find();
        $update_user_info = [];
        if ($user_info) {
            //判断账号是否被封禁
            if ($user_info["reasons"] == 1) {
                if ($user_info["reasons_time"] > time()) {
                    $this->json(403, "你账号已被封禁，封禁理由为：" . $user_info["reasons_ban"] . ",解封时间为" . date("Y-m-d H:i:s", $user_info["reasons_time"]));
                } else {
                    Db::name("user")->where("id", $user_info["id"])->update([
                        'reasons' => 0,
                        'reasons_time' => 0,
                        'reasons_ban' => '',
                    ]);
                }
            }
            //判断异地登录是否开启
            if ($this->app_info["login_configuration"]["remote_login"] == 0 && $user_info['email'] != "") {
                $now_user_ip = get_client_ip();
                if ($user_info["ip"] != "" && $now_user_ip != $user_info["ip"]) {
                    $ip = new IpLocation();
                    $ip_address = $ip->getDetail($user_info["ip"])["dataA"];
                    $ip_now_address = $ip->getDetail($now_user_ip)["dataA"];
                    if ($ip_address != $ip_now_address) {
                        $mail = new Email($user_info['email']);
                        $temdata = [
                            '{appname}' => $this->app_info["appname"],
                            '{time}' => date("Y-m-d H:i:s", time()),
                            '{username}' => $user_info["username"],
                            '{nickname}' => $user_info["nickname"],
                            '{address}' => $ip_now_address,
                            '{ip}' => $now_user_ip
                        ];
                        //获取邮件模板
                        $tplList = '../extend/EmailTpl/tpl.php';
                        //获取邮件模板列表
                        if (file_exists($tplList)) {
                            $tplList = include $tplList;
                        } else {
                            $tplList = [];
                        }
                        if (!isset($tplList[2])) {
                            throw new \Exception('邮件模板不存在');
                        }
                        $tpl = $tplList[2];
                        $templateString = file_get_contents(app()->getRootPath() . $tpl['path']);
                        $templateString = strtr($templateString, $temdata);
                        $mail->setBody($templateString);
                        $mail->setSubject($this->app_info["appname"] . $tpl['name']);
                        $mail->setFrom($this->app_info["appname"]);
                        $result = $mail->send();
                    }
                }
            }
            $usertoken = $this->issueUserDeviceSession((int)$user_info["id"], $device, $data);
            $update_user_info["ip"] = get_client_ip();
            Db::name("user")->where("id", $user_info["id"])->update($update_user_info);
            $result = [
                "id" => $user_info["id"],
                "username" => $user_info["username"],
                "usertoken" => $usertoken
            ];
            //判断当前发帖的用户是否是版主
            $plate_list = Db::name("forum_section")->where("appid", $this->appid)->select()->toArray();
            $result["is_section_moderator"] = 0;
            foreach ($plate_list as $key => $value) {
                $section_id_array = explode(",", $value["forum_section"]);
                if (in_array($user_info["id"], $section_id_array)) {
                    $result["is_section_moderator"] = 1;
                    break;
                }
            }
            Cache::delete($this->appid . "login" . get_client_ip());
            $this->deleteVerificationCodeCache("mobile_login", $mobile);
            $result = $this->appendWukongLoginPayload($result, (int)$user_info["id"], $usertoken);
            $this->securePublicJson(1, '登录成功', $result);
            //清楚短信验证码缓存
            $this->deleteVerificationCodeCache("mobile_login", $mobile);
        }
        $this->json(0, '该手机号未注册');
    }

    //聊天连接信息
    public function im_connect()
    {
        $chat = $this->chatRequestContext();
        $data = $this->secureChatRequestInput();
        $rule = [
            'usertoken|用户token' => 'require',
        ];
        $validate = new Validate();
        $validate->rule($rule);
        $result = $validate->check($data);
        if (!$result) {
            $this->json(0, $validate->getError());
        }
        $user_info = $this->user_info;
        $uid = $this->wukongUid($user_info["id"]);
        $sessionToken = (string)$this->usertoken;
        if ($sessionToken === '') {
            $this->json(401, '登录状态已失效');
        }
        // Connection ticket issuance must remain a fast, side-effect-free path.
        // WuKong token registration is completed during login and presence targets
        // are maintained by friend lifecycle events, not by every reconnect.
        $chatPayload = [
            "uid" => $uid,
            "token" => $sessionToken,
            "device" => $chat["device"],
            "device_flag" => (int)$chat["device_flag"],
            "device_level" => (int)$chat["device_level"],
            "channel_type_person" => (int)config('wukongim.channel_type_person', WukongIM::CHANNEL_TYPE_PERSON),
            "channel_type_group" => (int)config('wukongim.channel_type_group', WukongIM::CHANNEL_TYPE_GROUP),
            "route" => [],
        ] + $this->historySyncPayload();
        $this->chatJson(1, 'success', $this->appendGatewayStreamPayload($chatPayload, $uid, (int)$user_info["id"], (string)$chat["device"]));
    }

    //获取短信验证码
    public function get_mobile_verification_code()
    {
        $data = $this->securePublicRequestInput();
        $type = (string)($data["type"] ?? "");
        if (!in_array($type, [1, 2, 3, 4])) {
            $this->json(0, '请输入正确的type值');
        }
        //验证码有效时间
        $phone_code_time = config("?system.phone_code_time") ? config("system.phone_code_time") : 300;
        $phone_code_time_f = intval($phone_code_time / 60);
        //验证码间隔时间
        $phone_code_interval_time = config("?system.phone_code_interval_time") ? config("system.phone_code_interval_time") : 60;
        $phone_code_interval_time_f = intval($phone_code_interval_time / 60);
        try {
            //登录
            if ($type == 1) {
                $mobile = (string)($data["mobile"] ?? "");
                $this->assertImageCaptchaScene("login", (string)($data["captcha"] ?? ""), false);
                $rule = [
                    'mobile|手机号' => 'require|mobile'
                ];
                $validate = new Validate();
                $validate->rule($rule);
                $result = $validate->check($data);
                if (!$result) {
                    throw new \Exception((string)$validate->getError());
                }
                $mobile_code_cache = Cache::get($this->appid . "mobile_login" . $mobile);
                if ($mobile_code_cache) {
                    if (time() - $mobile_code_cache["time"] < $phone_code_interval_time) {
                        throw new \Exception($phone_code_interval_time_f . "分钟内只能发送一次验证码");
                    }
                }
                $user_info = Db::name('user')->where("appid", $this->appid)->where("mobile='{$mobile}'")->find();
                if (!$user_info) {
                    throw new \Exception("该手机未注册");
                }
                $captcha = rand(100000, 999999);
                $AliyunSms = new AlibabaSample();
                $AliyunSms->setCode($captcha);
                $result = $AliyunSms->send($mobile);
                if ($result == 1) {
                    $this->writeVerificationCodeCache("mobile_login", $mobile, ["code" => $captcha, "mobile" => $mobile, "time" => time()], $phone_code_time);
                    $this->json(1, "发送成功");
                } else {
                    throw new \Exception((string)$result);
                }
            }
            //注册
            if ($type == 2) {
                $mobile = (string)($data["mobile"] ?? "");
                $this->assertImageCaptchaScene("register", (string)($data["captcha"] ?? ""), true);
                $rule = [
                    'mobile|手机号' => 'require|mobile'
                ];
                $validate = new Validate();
                $validate->rule($rule);
                $result = $validate->check($data);
                if (!$result) {
                    throw new \Exception((string)$validate->getError());
                }
                $mobile_code_cache = Cache::get($this->appid . "mobile_register" . $mobile);
                if ($mobile_code_cache) {
                    if (time() - $mobile_code_cache["time"] < $phone_code_interval_time) {
                        throw new \Exception($phone_code_interval_time_f . "分钟内只能发送一次验证码");
                    }
                }
                $user_info = Db::name('user')->where("appid", $this->appid)->where("mobile='{$mobile}'")->find();
                if (!$user_info) {
                    $captcha = rand(100000, 999999);
                    $AliyunSms = new AlibabaSample();
                    $AliyunSms->setCode($captcha);
                    $result = $AliyunSms->send($mobile);
                    if ($result == 1) {
                        $this->writeVerificationCodeCache("mobile_register", $mobile, ["code" => $captcha, "mobile" => $mobile, "time" => time()], $phone_code_time);
                        $this->json(1, "发送成功");
                    } else {
                        throw new \Exception((string)$result);
                    }
                }
                throw new \Exception("该手机号已注册");
            }
            //找回密码
            if ($type == 3) {
                $this->assertImageCaptchaScene("security", (string)($data["captcha"] ?? ""), true);
                $mobile_code_cache = Cache::get($this->appid . "mobile_retrieve" . get_client_ip());
                if ($mobile_code_cache) {
                    if (time() - $mobile_code_cache["time"] < $phone_code_time) {
                        throw new \Exception($phone_code_interval_time_f . "分钟内只能发送一次验证码");
                    }
                }
                $mobile = (string)($data["mobile"] ?? "");
                $rule = [
                    'mobile|手机号' => 'require|mobile'
                ];
                $validate = new Validate();
                $validate->rule($rule);
                $result = $validate->check($data);
                if (!$result) {
                    throw new \Exception((string)$validate->getError());
                }
                $user_info = Db::name('user')->where("appid", $this->appid)->where("mobile='{$mobile}'")->find();
                if ($user_info) {
                    $captcha = rand(100000, 999999);
                    $AliyunSms = new AlibabaSample();
                    $AliyunSms->setCode($captcha);
                    $result = $AliyunSms->send($mobile);
                    if ($result == 1) {
                        Cache::set($this->appid . "mobile_retrieve" . get_client_ip(), ["code" => $captcha, "mobile" => $mobile, "time" => time()], $phone_code_time);
                        $this->json(1, "发送成功");
                    } else {
                        throw new \Exception((string)$result);
                    }
                }
                throw new \Exception("该手机号没绑定任何用户");
            }
            //修改手机号
            if ($type == 4) {
                $this->assertImageCaptchaScene("security", (string)($data["captcha"] ?? ""), true);
                $mobile_code_cache = Cache::get($this->appid . "phone_update" . get_client_ip());
                if ($mobile_code_cache) {
                    if (time() - $mobile_code_cache["time"] < $phone_code_time) {
                        throw new \Exception($phone_code_interval_time_f . "分钟内只能发送一次验证码");
                    }
                }
                $mobile = (string)($data["mobile"] ?? "");
                $rule = [
                    'mobile|手机号' => 'require|mobile'
                ];
                $validate = new Validate();
                $validate->rule($rule);
                $result = $validate->check($data);
                if (!$result) {
                    throw new \Exception((string)$validate->getError());
                }
                $user_info = Db::name('user')->where("appid", $this->appid)->where("mobile='{$mobile}'")->find();
                if (!$user_info) {
                    $captcha = rand(100000, 999999);
                    $AliyunSms = new AlibabaSample();
                    $AliyunSms->setCode($captcha);
                    $result = $AliyunSms->send($mobile);
                    if ($result == 1) {
                        Cache::set($this->appid . "phone_update" . get_client_ip(), ["code" => $captcha, "mobile" => $mobile, "time" => time()], $phone_code_time);
                        $this->json(1, "发送成功");
                    } else {
                        throw new \Exception((string)$result);
                    }
                }
                throw new \Exception("该手机号已绑定用户");
            }
        } catch (\Exception $th) {
            $this->json(0, $th->getMessage());
        }
    }

    //获取邮箱验证码
    public function get_email_verification_code()
    {
        $data = $this->securePublicRequestInput();
        $type = (string)($data["type"] ?? "");
        if (!in_array($type, [1, 2, 3])) {
            $this->json(0, '请输入正确的type值');
        }
        //验证码有效时间
        $email_code_time = config("?system.email_code_time") ? config("system.email_code_time") : 300;
        $email_code_time_f = intval($email_code_time / 60);
        //验证码间隔时间
        $email_code_interval_time = config("?system.email_code_interval_time") ? config("system.email_code_interval_time") : 60;
        $email_code_interval_time_f = intval($email_code_interval_time / 60);
        try {
            //注册
            if ($type == 1) {
                $email = (string)($data["email"] ?? "");
                $this->assertImageCaptchaScene("register", (string)($data["captcha"] ?? ""), true);
                $rule = [
                    'email|邮箱' => 'require|email'
                ];
                $validate = new Validate();
                $validate->rule($rule);
                $result = $validate->check($data);
                if (!$result) {
                    throw new \Exception((string)$validate->getError());
                }
                $email_register_code_cache = Cache::get($this->appid . "email_register" . $email);
                if ($email_register_code_cache) {
                    if (time() - $email_register_code_cache["time"] < $email_code_interval_time) {
                        throw new \Exception("{$email_code_interval_time_f}分钟内只能发送一次验证码");
                    }
                }
                $email_info = Db::name('user')->where("appid", $this->appid)->where("email='{$email}'")->find();
                if ($email_info) {
                    throw new \Exception('该邮箱已注册');
                }
                $mail = new Email($email);
                $code = rand(10000, 99999);
                $temdata = [
                    '{appname}' => $this->app_info["appname"],
                    '{useremail}' => $email,
                    '{code}' => $code,
                    '{email_code_time}' => $email_code_time_f,
                ];
                //获取邮件模板
                $tplList = '../extend/EmailTpl/tpl.php';
                //获取邮件模板列表
                if (file_exists($tplList)) {
                    $tplList = include $tplList;
                } else {
                    $tplList = [];
                }
                if (!isset($tplList[0])) {
                    throw new \Exception('邮件模板不存在');
                }
                $tpl = $tplList[0];
                $templateString = file_get_contents(app()->getRootPath() . $tpl['path']);
                $templateString = strtr($templateString, $temdata);
                $mail->setBody($templateString);
                $mail->setSubject($this->app_info["appname"] . $tpl['name']);
                $mail->setFrom($this->app_info["appname"]);
                $result = $mail->send();
                if ($result == 1) {
                    Cache::set($this->appid . "email_register" . $email, ["code" => $code, "email" => $email, "time" => time()], $email_code_time);
                    $this->json(1, "发送成功");
                } else {
                    throw new \Exception($result);
                }
            }
            //找回密码
            if ($type == 2) {
                $this->assertImageCaptchaScene("security", (string)($data["captcha"] ?? ""), true);
                $email_retrieve_code_cache = Cache::get($this->appid . "email_retrieve" . get_client_ip());
                if ($email_retrieve_code_cache) {
                    if (time() - $email_retrieve_code_cache["time"] < $email_code_interval_time) {
                        throw new \Exception("{$email_code_interval_time_f}分钟内只能发送一次验证码");
                    }
                }
                $username = (string)($data["username"] ?? "");
                $rule = [
                    'username|用户名' => 'require|min:5',
                ];
                $validate = new Validate();
                $validate->rule($rule);
                $result = $validate->check($data);
                if (!$result) {
                    throw new \Exception((string)$validate->getError());
                }
                $email_info = Db::name('user')->where("appid", $this->appid)->where("username='{$username}'")->find();
                if (!$email_info) {
                    throw new \Exception("该用户未绑定邮箱");
                }
                $mail = new Email($email_info['email']);
                $code = rand(10000, 99999);
                $temdata = [
                    '{appname}' => $this->app_info["appname"],
                    '{username}' => $username,
                    '{code}' => $code,
                    '{email_code_time}' => $email_code_time_f,
                ];
                //获取邮件模板
                $tplList = '../extend/EmailTpl/tpl.php';
                //获取邮件模板列表
                if (file_exists($tplList)) {
                    $tplList = include $tplList;
                } else {
                    $tplList = [];
                }
                if (!isset($tplList[1])) {
                    throw new \Exception('邮件模板不存在');
                }
                $tpl = $tplList[1];
                $templateString = file_get_contents(app()->getRootPath() . $tpl['path']);
                $templateString = strtr($templateString, $temdata);
                $mail->setBody($templateString);
                $mail->setSubject($this->app_info["appname"] . $tpl['name']);
                $mail->setFrom($this->app_info["appname"]);
                $result = $mail->send();
                if ($result == 1) {
                    Cache::set($this->appid . "email_retrieve" . get_client_ip(), ["code" => $code, "email" => $email_info["email"], "time" => time()], $email_code_time);
                    $this->json(1, "发送成功");
                } else {
                    throw new \Exception($result);
                }
            }
            //修改绑定邮箱
            if ($type == 3) {
                $this->assertImageCaptchaScene("security", (string)($data["captcha"] ?? ""), true);
                $email_update_code_cache = Cache::get($this->appid . "email_update" . get_client_ip());
                if ($email_update_code_cache) {
                    if (time() - $email_update_code_cache["time"] < $email_code_interval_time) {
                        throw new \Exception("{$email_code_interval_time_f}分钟内只能发送一次验证码");
                    }
                }
                $email = (string)($data["email"] ?? "");
                $rule = [
                    'email|邮箱' => 'require|email'
                ];
                $validate = new Validate();
                $validate->rule($rule);
                $result = $validate->check($data);
                if (!$result) {
                    throw new \Exception((string)$validate->getError());
                }
                $email_info = Db::name('user')->where("appid", $this->appid)->where("email='{$email}'")->find();
                if ($email_info) {
                    throw new \Exception("该邮箱已被绑定");
                }
                $mail = new Email($email);
                $code = rand(10000, 99999);
                $temdata = [
                    '{appname}' => $this->app_info["appname"],
                    '{code}' => $code,
                    '{email_code_time}' => $email_code_time_f,
                ];
                //获取邮件模板
                $tplList = '../extend/EmailTpl/tpl.php';
                //获取邮件模板列表
                if (file_exists($tplList)) {
                    $tplList = include $tplList;
                } else {
                    $tplList = [];
                }
                if (!isset($tplList[3])) {
                    throw new \Exception('邮件模板不存在');
                }
                $tpl = $tplList[3];
                $templateString = file_get_contents(app()->getRootPath() . $tpl['path']);
                $templateString = strtr($templateString, $temdata);
                $mail->setBody($templateString);
                $mail->setSubject($this->app_info["appname"] . $tpl['name']);
                $mail->setFrom($this->app_info["appname"]);
                $result = $mail->send();
                if ($result == 1) {
                    Cache::set($this->appid . "email_update" . get_client_ip(), ["code" => $code, "email" => $email, "time" => time()], $email_code_time);
                    $this->json(1, "发送成功");
                } else {
                    throw new \Exception($result);
                }
            }
        } catch (\Exception $th) {
            $this->json(0, $th->getMessage());
        }
    }

    //用户注册
    public function register()
    {
        //判断是否开启注册
        if ($this->app_info["registration_configuration"]["registration_switch"] == 1) {
            $this->json(103, $this->app_info["registration_configuration"]["registration_closing_prompt"]);
        }
        $data = $this->securePublicRequestInput();
        $username = (string)($data["username"] ?? "");
        $password = (string)($data["password"] ?? "");
        $mobile = (string)($data["mobile"] ?? "");
        $email = (string)($data["email"] ?? "");
        $captcha = (string)($data["captcha"] ?? "");
        $device = (string)($data["device"] ?? "");
        $rule = [
            'username|用户名' => 'require|min:5',
            'password|密码' => 'require|min:5',
        ];
        $validate = new Validate();
        $validate->rule($rule);
        $result = $validate->check($data);
        if (!$result) {
            $this->json(0, $validate->getError());
        }
        $add = [];
        //判断用什么方式发的验证码
        if ($this->app_info["registration_configuration"]["registration_code_switch"] == 1) {
            $rule = [
                'captcha|验证码' => 'require',
            ];
            $validate = new Validate();
            $validate->rule($rule);
            $result = $validate->check($data);
            if (!$result) {
                $this->json(0, $validate->getError());
            }
            $this->assertImageCaptchaScene("register", $captcha, true);
        }
        //邮箱验证码
        if ($this->app_info["registration_configuration"]["registration_code_switch"] == 2) {
            $rule = [
                'email|邮箱' => 'require|email',
                'captcha|验证码' => 'require',
            ];
            $validate = new Validate();
            $validate->rule($rule);
            $result = $validate->check($data);
            if (!$result) {
                $this->json(0, $validate->getError());
            }
            $email_code_cache = Cache::get($this->appid . "email_register" . $data["email"]);
            $email_code_time = config("?system.email_code_time") ? config("system.email_code_time") : 300;
            if ($email_code_cache) {
                if (time() - $email_code_cache["time"] > $email_code_time) {
                    $this->json(0, "验证码已过期");
                }
                if ($captcha != $email_code_cache["code"]) {
                    $this->json(0, "验证码不正确");
                }
                //验证当前提交的邮箱是否和发送验证码的邮箱一致
                if ($email != $email_code_cache["email"]) {
                    $this->json(0, "系统检测到您更换了邮箱，请重新发送验证码");
                }
                $email = $email_code_cache["email"];
            } else {
                $this->json(0, "请先发送验证码");
            }
            $email_info = Db::name("user")->where("appid", $this->appid)->where("email='{$email}'")->find();
            if ($email_info) {
                $this->json(0, "邮箱已存在");
            }
            $add["email"] = $email;
        }
        //手机号验证码
        if ($this->app_info["registration_configuration"]["registration_code_switch"] == 3) {
            $rule = [
                'mobile|手机号' => 'require|mobile',
                'captcha|验证码' => 'require',
            ];
            $validate = new Validate();
            $validate->rule($rule);
            $result = $validate->check($data);
            if (!$result) {
                $this->json(0, $validate->getError());
            }
            $mobile_code_cache = $this->readVerificationCodeCache("mobile_register", (string)$data["mobile"]);
            $phone_code_time = config("system.phone_code_time");
            if ($mobile_code_cache) {
                if (time() - $mobile_code_cache["time"] > $phone_code_time) {
                    $this->json(0, "验证码已过期");
                }
                if ($captcha != $mobile_code_cache["code"]) {
                    $this->json(0, "验证码不正确");
                }
                //验证当前提交的手机号是否和发送验证码的手机号一致
                if ($mobile != $mobile_code_cache["mobile"]) {
                    $this->json(0, "系统检测到您更换了手机号，请重新发送验证码");
                }
                $mobile = $mobile_code_cache["mobile"];
            } else {
                $this->json(0, "请先发送验证码");
            }
            $mobile_info = Db::name("user")->where("appid", $this->appid)->where("mobile='{$mobile}'")->find();
            if ($mobile_info) {
                $this->json(0, "该手机号已注册");
            }
            $add["mobile"] = $mobile;
            $this->deleteVerificationCodeCache("mobile_register", $mobile);
        }
        //判断是否开启单设备注册限制
        if ($this->app_info["registration_configuration"]["single_device_registration_limit"] != 0) {
            $rule = [
                'device|设备码' => 'require',
            ];
            $validate = new Validate();
            $validate->rule($rule);
            $result = $validate->check($data);
            if (!$result) {
                $this->json(0, $validate->getError());
            }
            $device_count = Db::name("user")->where("appid", $this->appid)->where("register_device='{$device}'")->count();
            if ($device_count >= $this->app_info["registration_configuration"]["single_device_registration_limit"]) {
                $this->json(0, "该设备注册已达到上限");
            }
            $add["register_device"] = $device;
            $add["login_device"] = $device;
        }

        //执行注册
        //开启事务
        Db::startTrans();
        try {
            $username_info = Db::name("user")->where("appid", $this->appid)->where("username", $username)->find();
            if ($username_info) {
                $this->json(0, "用户名已存在");
            }
            $salt = getRandChar(6);
            $userinfo_configuration = $this->app_info["userinfo_configuration"];
            $add["appid"] = $this->appid;
            $add["username"] = $username;
            $add["password"] = md5($password . $salt);
            $add["salt"] = $salt;
            $add["usertx"] = $userinfo_configuration['usertx'];
            $add["nickname"] = $userinfo_configuration['nickname'];
            $add["money"] = $this->app_info["registration_configuration"]["money"];
            $add["integral"] = $this->app_info["registration_configuration"]["integral"];
            $add["viptime"] = time() + ($this->app_info["registration_configuration"]["vip"] * 60 * 60 * 24);
            $add["userbg"] = $userinfo_configuration['userbg'];
            $add["signature"] = $userinfo_configuration['signature'];
            $add["create_time"] = date("Y-m-d H:i:s", time());
            $add["register_ip"] = get_client_ip();
            $add["invitecode"] = enerate_invitation_code();
            $user_id = Db::name("user")->insertGetId($add);
            $this->applyNewUserChatDefaults((int)$user_id);

            //增加用户的交易账单
            if ($this->app_info["registration_configuration"]["money"] != 0) {
                add_user_bill(["id" => $user_id, "appid" => $this->appid], 1, "+" . $this->app_info["registration_configuration"]["money"], "注册奖励", 0);
            }
            if ($this->app_info["registration_configuration"]["integral"] != 0) {
                add_user_bill(["id" => $user_id, "appid" => $this->appid], 1, "+" . $this->app_info["registration_configuration"]["integral"], "注册奖励", 1);
            }

            //邀请配置
            if ($this->app_info["invitation_configuration"]["invitation_switch"] == 0) {
                $invitation_configuration = $this->app_info["invitation_configuration"];
                $invitecode = (string)($data['invitecode'] ?? '');
                if ($invitecode != "") {
                    //邀请人的赠送
                    $invitecode_userinfo = Db::name("user")->where("appid", $this->appid)->where("invitecode", $invitecode)->find();
                    if (!$invitecode_userinfo) {
                        $this->json(0, "不存在此邀请码");
                    }
                    if ($invitecode_userinfo["viptime"] >= time()) {
                        $userviptime = $invitecode_userinfo["viptime"];
                    } else {
                        $userviptime = time();
                    }
                    $updateinvitecode = [
                        "money" => $invitecode_userinfo["money"] + $invitation_configuration["money"],
                        "integral" => $invitecode_userinfo["integral"] + $invitation_configuration["integral"],
                        "exp" => $invitecode_userinfo["exp"] + $invitation_configuration["exp"],
                        "viptime" => $userviptime + ($invitation_configuration["vip"] * 24 * 3600),
                    ];
                    Db::name("user")->where("id", $invitecode_userinfo["id"])->update($updateinvitecode);
                    $adddata = [
                        "userid" => $invitecode_userinfo["id"],
                        "other_id" => $user_id,
                        "appid" => $data["appid"],
                        "create_time" => date("Y-m-d H:i:s", time()),
                        "type" => 1
                    ];
                    Db::name("polymorphic")->insert($adddata);
                    //增加用户的交易账单
                    if ($invitation_configuration["money"] != 0) {
                        add_user_bill($invitecode_userinfo, 0, "+" . $invitation_configuration["money"], "邀请好友" . $data["username"] . "奖励", 0);
                    }
                    if ($invitation_configuration["integral"] != 0) {
                        add_user_bill($invitecode_userinfo, 0, "+" . $invitation_configuration["integral"], "邀请好友" . $data["username"] . "奖励", 1);
                    }
                    //被邀请人的赠送
                    //查询被邀请人的信息
                    $add = Db::name("user")->where("id", $user_id)->find();
                    $updateinvitecode = [
                        "money" => $add["money"] + $invitation_configuration["bmoney"],
                        "integral" => $add["integral"] + $invitation_configuration["bintegral"],
                        "exp" => $add["exp"] + $invitation_configuration["bexp"],
                        "viptime" => $add["viptime"] + ($invitation_configuration["bvip"] * 24 * 3600),
                    ];
                    Db::name("user")->where("id", $user_id)->update($updateinvitecode);
                    //增加用户的交易账单
                    if ($invitation_configuration["bmoney"] != 0) {
                        add_user_bill($add, 0, "+" . $invitation_configuration["bmoney"], "被好友" . $invitecode_userinfo["username"] . "邀请加入奖励", 0);
                    }
                    if ($invitation_configuration["bintegral"] != 0) {
                        add_user_bill($add, 0, "+" . $invitation_configuration["bintegral"], "被好友" . $invitecode_userinfo["username"] . "邀请加入奖励", 1);
                    }
                }
            }
            Db::commit();
        } catch (\Exception $th) {
            Db::rollback();
            $this->json(0, "注册失败");
        }

        Cache::delete($this->appid . "register" . get_client_ip());
        Cache::delete($this->appid . "mobile_register" . @$data["mobile"]);
        Cache::delete($this->appid . "email_register" . @$data["email"]);
        $this->json(1, "注册成功");
    }

    //聊天退出登录
    public function im_logout()
    {
        $chat = $this->chatRequestContext();
        $data = $this->secureChatRequestInput();
        $usertoken = (string)($data["usertoken"] ?? "");
        $rule = [
            'usertoken|用户token' => 'require',
        ];
        $validate = new Validate();
        $validate->rule($rule);
        $result = $validate->check($data);
        if (!$result) {
            $this->json(0, $validate->getError());
        }
        $user_info = $this->user_info;
        try {
            (new WukongIM())->deviceQuit($this->wukongUid($user_info["id"]), (int)$chat["device_flag"]);
        } catch (\Exception $e) {
            $this->json(0, $e->getMessage());
        }
        UserDeviceSession::revoke(
            (int)$this->appid,
            (int)$user_info['id'],
            $this->clientPlatform(),
            (string)$chat['device'],
            'logout'
        );
        $this->chatJson(1, "success", []);
    }

    //获取用户信息
    public function get_user_information()
    {
        $userid = input("userid");
        $data = input('');
        $rule = [
            'userid|用户id' => 'require|integer',
            'usertoken|用户token' => 'require',
        ];
        $validate = new Validate();
        $validate->rule($rule);
        $result = $validate->check($data);
        if (!$result) {
            $this->json(0, $validate->getError());
        }
        //判断是否是自己
        $user_all_info = $this->user_info;
        if ($userid == $user_all_info["id"]) {
            $result = $this->user_info;
        } else {
            $result = Db::name('user')->where("appid", $this->appid)->where("id={$userid}")->find();
        }
        if ($result) {
            $ip = new IpLocation();
            $res = [
                "id" => $result["id"],
                "username" => $result["username"],
                "usertx" => $result["usertx"],
                "nickname" => $result["nickname"],
                "money" => $result["money"],
                "exp" => $result["exp"],
                "integral" => $result["integral"],
                "viptime" => date("Y-m-d H:i:s", $result["viptime"]),
                "sex" => $result["sex"],
                "sexName" => $result["sex"] == 0 ? "男" : "女",
                "signature" => $result["signature"],
                "title" => array_filter(explode(",", $result["title"])),
                "invitecode" => $result["invitecode"],
                "reasons" => $result["reasons"] == 0 ? "正常" : "已封禁",
                "reasons_time" => $result["reasons_time"],
                "reasons_ban" => $result["reasons_ban"],
                "userbg" => $result["userbg"],
                "ipaddress" => $result["ip"] == "" ? "" : $ip->getDetail($result["ip"])["dataA"],
                "create_time" => $result["create_time"],
            ];
            //经验等级
            $arr = $this->app_info["grade"];
            $grades = eval("return $arr;");
            $res["hierarchy"] = "";
            if (is_array($grades)) {
                foreach ($grades as $key => $value) {
                    if ($result['exp'] >= $key) {
                        $res["hierarchy"] = $value;
                    } else {
                        break;
                    }
                }
            }
            //获取用户的徽章
            $res["badge"] = Db::name("polymorphic")
                ->alias("p")
                ->join("bagge b", "b.id=p.other_id")
                ->where("p.userid", $result["id"])
                ->where("p.type", 5)
                ->where("b.is_view", 0)
                ->where("p.wearing", 0)
                ->order(["b.type" => $this->medal_sorting, "b.sort" => "desc"])
                ->field("b.id,b.name,b.icon,b.type,case when p.expiration_time = '9999' then '永久' else p.expiration_time end as expiration_time")
                ->select()->toArray();
            //是否是会员
            if (time() < $result["viptime"]) {
                $res["vip"] = true;
            } else {
                $res["vip"] = false;
            }
            //签到天数
            $signinfo = Db::name("sign_record")->where("userid", $result["id"])->find();
            $res["signlasttime"] = isset($signinfo["lasttime"]) ? date("Y-m-d H:i:s", $signinfo["lasttime"]) : "您还没有签到过呢";
            if ($res["signlasttime"] >= date("Y-m-d 00:00:00") && $res["signlasttime"] <= date("Y-m-d 23:59:59")) {
                $res["sign_today"] = true;
            } else {
                $res["sign_today"] = false;
            }
            $res["series_days"] = isset($signinfo["series_days"]) ? $signinfo["series_days"] : 0;
            $res["continuity_days"] = isset($signinfo["continuity_days"]) ? $signinfo["continuity_days"] : 0;
            //邀请总数
            $res["invitationcount"] = Db::name("polymorphic")->where("type", 1)->where("userid", $result["id"])->count();
            $res["invitationcount"] = formatNumber($res["invitationcount"]);
            //关注数量
            $res["followerscount"] = Db::name("polymorphic")->where("type", 2)->where("userid", $result["id"])->count();
            $res["followerscount"] = formatNumber($res["followerscount"]);
            //粉丝数量
            $res["fanscount"] = Db::name("polymorphic")->where("type", 2)->where("other_id", $result["id"])->count();
            $res["fanscount"] = formatNumber($res["fanscount"]);
            //帖子数量
            $res["postcount"] = Db::name("forum_posts")->where("userid", $result["id"])->count();
            $res["postcount"] = formatNumber($res["postcount"]);
            //点赞数量
            $res["likecount"] = Db::name("polymorphic")->where("type", 3)->where("userid", $result["id"])->count();
            $res["likecount"] = formatNumber($res["likecount"]);
            //评论数量
            $res["commentcount"] = Db::name("comments")->where("userid", $result["id"])->count();
            $res["commentcount"] = formatNumber($res["commentcount"]);
            //应用数量
            $res["appcount"] = Db::name("apps")->where("userid", $result["id"])->count();
            $res["appcount"] = formatNumber($res["appcount"]);
            $online = [];
            try {
                $online = (new WukongIM())->onlineStatus([$this->wukongUid($result["id"])]);
            } catch (\Exception $e) {
                $online = [];
            }
            $res["online"] = !empty($online);
            $res["last_activity_time"] = $res["online"] ? "在线" : "离线";
            //查询关注状态
            $status = 3;
            // $status 0互相关注 1他关注了我 2我关注了他 3互相都没有关注
            $followinfo = Db::name("polymorphic")->where("appid", $data["appid"])->where("type", 2)->where("userid", $user_all_info["id"])->where("other_id", $data["userid"])->find();
            $ffollowinfo = Db::name("polymorphic")->where("appid", $data["appid"])->where("type", 2)->where("userid", $data["userid"])->where("other_id", $user_all_info["id"])->find();
            if ($followinfo) {
                if ($ffollowinfo) {
                    $status = 0;
                } else {
                    $status = 2;
                }
            } else {
                if ($ffollowinfo) {
                    $status = 1;
                } else {
                    $status = 3;
                }
            }
            $res["follow_status"] = $status;
            //判断当前发帖的用户是否是版主
            $plate_list = Db::name("forum_section")->where("appid", $this->appid)->select()->toArray();
            $res["is_section_moderator"] = 0;
            foreach ($plate_list as $key => $value) {
                $section_id_array = explode(",", $value["forum_section"]);
                if (in_array($res["id"], $section_id_array)) {
                    $res["is_section_moderator"] = 1;
                    break;
                }
            }
            $this->json(1, "success", $res);
        } else {
            $this->json(0, "该用户不存在");
        }
    }

    //获取登录用户其他信息
    public function get_user_other_information()
    {
        $data = $this->secureChatRequestInput();
        $rule = [
            'usertoken|用户token' => 'require',
        ];
        $validate = new Validate();
        $validate->rule($rule);
        $result = $validate->check($data);
        if (!$result) {
            $this->json(0, $validate->getError());
        }
        $result = $this->user_info;
        if ($result) {
            $ip = new IpLocation();
            $res = [
                "id" => $result["id"],
                "username" => $result["username"],
                "usertx" => $result["usertx"],
                "nickname" => $result["nickname"],
                "qq" => $result['qq'],
                "email" => $result['email'],
                "mobile" => $result['mobile'],
                "openid_wx" => !($result['openid_wx'] == ""),
                "openid_qq" => !($result['openid_qq'] == ""),
                "reasons" => $result["reasons"] == 0 ? "正常" : "已封禁",
                "reasons_time" => $result["reasons_time"],
                "reasons_ban" => $result["reasons_ban"],
                "userbg" => $result["userbg"],
                "ipaddress" => $result["ip"] == "" ? "" : $ip->getDetail($result["ip"])["dataA"],
                "money" => $result["money"],
                "exp" => $result["exp"],
                "integral" => $result["integral"],
                "viptime" => date("Y-m-d H:i:s", $result["viptime"]),
                "sex" => $result["sex"],
                "sexName" => $result["sex"] == 0 ? "男" : "女",
                "signature" => $result["signature"],
                "title" => array_filter(explode(",", $result["title"])),
                "invitecode" => $result["invitecode"],
                "create_time" => $result["create_time"],
            ];
            //经验等级
            $arr = $this->app_info["grade"];
            $grades = eval("return $arr;");
            $res["hierarchy"] = "";
            if (is_array($grades)) {
                foreach ($grades as $key => $value) {
                    if ($result['exp'] >= $key) {
                        $res["hierarchy"] = $value;
                    } else {
                        $res["next_level_exp_required"] = ($key - $result['exp']) > 0 ? ($key - $result['exp']) : 0;
                        $res["next_level_exp"] = $key;
                        $res["max_exp"] = ($key - $result['exp']) > 0 ? ($key - $result['exp']) : 0;
                        break;
                    }
                }
            }
            //获取用户的徽章
            $res["badge"] = Db::name("polymorphic")
                ->alias("p")
                ->join("bagge b", "b.id=p.other_id")
                ->where("p.userid", $result["id"])
                ->where("p.type", 5)
                ->where("b.is_view", 0)
                ->where("p.wearing", 0)
                ->order(["b.type" => $this->medal_sorting, "b.sort" => "desc"])
                ->field("b.id,b.name,b.icon,b.type,b.create_time,case when p.expiration_time = '9999' then '永久' else p.expiration_time end as expiration_time")
                ->select()->toArray();
            //是否是会员
            if (time() < $result["viptime"]) {
                $res["vip"] = true;
            } else {
                $res["vip"] = false;
            }
            //判断用户是否是版主
            $plate_list = Db::name("forum_section")->where("appid", $this->appid)->select()->toArray();
            $res["is_section_moderator"] = 0;
            foreach ($plate_list as $k1 => $v1) {
                $section_id_array = explode(",", $v1["forum_section"]);
                if (in_array($res["id"], $section_id_array)) {
                    $res["is_section_moderator"] = 1;
                    break;
                }
            }
            //签到天数
            $signinfo = Db::name("sign_record")->where("userid", $result["id"])->find();
            $res["signlasttime"] = isset($signinfo["lasttime"]) ? date("Y-m-d H:i:s", $signinfo["lasttime"]) : "您还没有签到过呢";
            if ($res["signlasttime"] >= date("Y-m-d 00:00:00") && $res["signlasttime"] <= date("Y-m-d 23:59:59")) {
                $res["sign_today"] = true;
            } else {
                $res["sign_today"] = false;
            }
            $res["series_days"] = isset($signinfo["series_days"]) ? $signinfo["series_days"] : 0;
            $res["continuity_days"] = isset($signinfo["continuity_days"]) ? $signinfo["continuity_days"] : 0;
            //邀请总数
            $res["invitationcount"] = Db::name("polymorphic")->where("type", 1)->where("userid", $result["id"])->count();
            $res["invitationcount"] = formatNumber($res["invitationcount"]);
            //关注数量
            $res["followerscount"] = Db::name("polymorphic")->where("type", 2)->where("userid", $result["id"])->count();
            $res["followerscount"] = formatNumber($res["followerscount"]);
            //粉丝数量
            $res["fanscount"] = Db::name("polymorphic")->where("type", 2)->where("other_id", $result["id"])->count();
            $res["fanscount"] = formatNumber($res["fanscount"]);
            //帖子数量
            $res["postcount"] = Db::name("forum_posts")->where("userid", $result["id"])->count();
            $res["postcount"] = formatNumber($res["postcount"]);
            //点赞数量
            $res["likecount"] = Db::name("polymorphic")->where("type", 3)->where("userid", $result["id"])->count();
            $res["likecount"] = formatNumber($res["likecount"]);
            //评论数量
            $res["commentcount"] = Db::name("comments")->where("userid", $result["id"])->count();
            $res["commentcount"] = formatNumber($res["commentcount"]);
            //上传应用数量
            $res["appcount"] = Db::name("apps")->where("userid", $result["id"])->count();
            $res["appcount"] = formatNumber($res["appcount"]);
            //判断当前登录的用户是否是版主
            $plate_list = Db::name("forum_section")->where("appid", $this->appid)->select()->toArray();
            $this->chatJson(1, "success", $res);
        } else {
            $this->json(0, "该用户不存在");
        }
    }

    //用户签到
    public function user_sign_in()
    {
        if ($this->app_info["sign_configuration"]["sign_switch"] == 1) {
            $this->json(0, "此APP已关闭签到配置");
        }
        $data = input('');
        $rule = [
            'usertoken|用户token' => 'require',
        ];
        $validate = new Validate();
        $validate->rule($rule);
        $result = $validate->check($data);
        if (!$result) {
            $this->json(0, $validate->getError());
        }
        $user_all_info = $this->user_info;
        //经验等级
        $arr = $this->app_info["grade"];
        $grades = eval("return $arr;");
        $return["hierarchy"] = "";
        $return["exp"] = $user_all_info["exp"] + $this->app_info["sign_configuration"]["exp"];
        $return["max_exp"] = "";
        if (is_array($grades)) {
            foreach ($grades as $key => $value) {
                if (($user_all_info["exp"] + $this->app_info["sign_configuration"]["exp"]) >= $key) {
                    $return["hierarchy"] = $value;
                } else {
                    $return["max_exp"] = $key;
                    break;
                }
            }
        }
        //查询签到信息
        $signinfo = Db::name("sign_record")->where("userid", $user_all_info["id"])->find();
        if ($signinfo) {
            //判断是否已经签到
            if (date("Y-m-d H:i:s", $signinfo["lasttime"]) >= date("Y-m-d 00:00:00") && date("Y-m-d H:i:s", $signinfo["lasttime"]) <= date("Y-m-d 23:59:59")) {
                $return["series_days"] = isset($signinfo["series_days"]) ? $signinfo["series_days"] : 0;
                $return["continuity_days"] = isset($signinfo["continuity_days"]) ? $signinfo["continuity_days"] : 0;
                $this->json(0, "今天已经签到了", $return);
            } else {
                //判断是否连续签到
                if (date("Y-m-d H:i:s", $signinfo["lasttime"]) >= date("Y-m-d 00:00:00", strtotime("-1day", time())) && date("Y-m-d H:i:s", $signinfo["lasttime"]) <= date("Y-m-d 23:59:59", strtotime("-1day", time()))) {
                    $resdata = [
                        "continuity_days" => $signinfo["continuity_days"] + 1,
                    ];
                } else {
                    $resdata = [
                        "continuity_days" => 1,
                    ];
                }
                $resdata["lasttime"] = time();
                $resdata["series_days"] = $signinfo["series_days"] + 1;
                $rs = Db::name("sign_record")->where("userid", $user_all_info["id"])->update($resdata);
                if ($rs > 0) {
                    $user_info = $this->user_info;
                    if ($user_info["viptime"] >= time()) {
                        $userviptime = $user_info["viptime"];
                    } else {
                        $userviptime = time();
                    }
                    $updateuser = [
                        "money" => $user_info["money"] + $this->app_info["sign_configuration"]["money"],
                        "integral" => $user_info["integral"] + $this->app_info["sign_configuration"]["integral"],
                        "viptime" => $userviptime + $this->app_info["sign_configuration"]["vip"] * 24 * 3600,
                        "exp" => $user_info["exp"] + $this->app_info["sign_configuration"]["exp"],
                    ];
                    Db::name("user")->where("id", $user_info["id"])->update($updateuser);
                    $sign_configuration = $this->app_info["sign_configuration"];
                    $sign_configuration["appid"] = $this->appid;
                    increase_system_notifications_to_users("签到成功", $sign_configuration, $user_info["id"], 0);
                    //增加用户账单
                    if ($this->app_info["sign_configuration"]["money"] != 0) {
                        add_user_bill($this->user_info, 2, "+" . $this->app_info["sign_configuration"]["money"], "签到奖励", 0);
                    }
                    if ($this->app_info["sign_configuration"]["integral"] != 0) {
                        add_user_bill($this->user_info, 2, "+" . $this->app_info["sign_configuration"]["integral"], "签到奖励", 1);
                    }
                    //加入签到记录
                    Db::name('user_log')->insert([
                        "userid" => $user_all_info["id"],
                        "type" => 0,
                        "appid" => $this->appid,
                        "create_time" => date("Y-m-d H:i:s", time())
                    ]);
                    $signinfo = Db::name("sign_record")->where("userid", $user_all_info["id"])->find();
                    $return["series_days"] = isset($signinfo["series_days"]) ? $signinfo["series_days"] : 0;
                    $return["continuity_days"] = isset($signinfo["continuity_days"]) ? $signinfo["continuity_days"] : 0;
                    $this->json(1, "签到成功", $return);
                } else {
                    $this->json(0, "签到失败");
                }
            }
        } else {
            //没有签到信息
            $adddata = [
                "continuity_days" => 1,
                "series_days" => 1,
                "lasttime" => time(),
                "userid" => $user_all_info["id"],
                "appid" => $this->appid,
                "create_time" => date("Y-m-d H:i:s", time())
            ];
            $rs = Db::name("sign_record")->strict(false)->insert($adddata);
            if ($rs > 0) {
                $user_info = $this->user_info;
                if ($user_info["viptime"] >= time()) {
                    $userviptime = $user_info["viptime"];
                } else {
                    $userviptime = time();
                }
                $updateuser = [
                    "money" => $user_info["money"] + $this->app_info["sign_configuration"]["money"],
                    "integral" => $user_info["integral"] + $this->app_info["sign_configuration"]["integral"],
                    "viptime" => $userviptime + $this->app_info["sign_configuration"]["vip"] * 24 * 3600,
                    "exp" => $user_info["exp"] + $this->app_info["sign_configuration"]["exp"],
                ];
                Db::name("user")->where("id", $user_info["id"])->update($updateuser);
                $sign_configuration = $this->app_info["sign_configuration"];
                $sign_configuration["appid"] = $this->appid;
                increase_system_notifications_to_users("签到成功", $sign_configuration, $user_info["id"], 0);
                //增加用户账单
                if ($this->app_info["sign_configuration"]["money"] != 0) {
                    add_user_bill($this->user_info, 2, "+" . $this->app_info["sign_configuration"]["money"], "签到奖励", 0);
                }
                if ($this->app_info["sign_configuration"]["integral"] != 0) {
                    add_user_bill($this->user_info, 2, "+" . $this->app_info["sign_configuration"]["integral"], "签到奖励", 1);
                }
                //加入签到记录
                Db::name('user_log')->insert([
                    "userid" => $user_all_info["id"],
                    "type" => 0,
                    "appid" => $this->appid,
                    "create_time" => date("Y-m-d H:i:s", time())
                ]);
                $signinfo = Db::name("sign_record")->where("userid", $user_all_info["id"])->find();
                $return["series_days"] = isset($signinfo["series_days"]) ? $signinfo["series_days"] : 0;
                $return["continuity_days"] = isset($signinfo["continuity_days"]) ? $signinfo["continuity_days"] : 0;
                $this->json(1, "签到成功", $return);
            } else {
                $this->json(0, "签到失败");
            }
        }
    }

    //找回密码
    public function retrieve_password()
    {
        $username = input("username");
        $password = input("password");
        $captcha = input("captcha");
        $data = input();
        $rule = [
            'username|用户名' => 'require|min:5',
            'password|密码' => 'require|min:5',
            'captcha|验证码' => 'require',
            'type|找回方式' => 'require',
        ];
        $validate = new Validate();
        $validate->rule($rule);
        $result = $validate->check($data);
        if (!$result) {
            $this->json(0, $validate->getError());
        }
        $type = input("type");
        if (!in_array($type, [1, 2])) {
            $this->json(0, '请输入正确的type值');
        }
        $userinfo = Db::name("user")->where("username", $username)->where('appid', $this->appid)->find();
        if ($userinfo == null) {
            $this->json(0, "账号不存在");
        }
        if ($type == 1) {
            $retrieve_email_code_cache = Cache::get($this->appid . "email_retrieve" . get_client_ip());
            $email_code_time = config("system.email_code_time");
            if ($retrieve_email_code_cache) {
                if (time() - $retrieve_email_code_cache["time"] > $email_code_time) {
                    $this->json(0, "验证码已过期");
                }
                if ($captcha != $retrieve_email_code_cache["code"]) {
                    $this->json(0, "验证码不正确");
                }
                $userinfo = Db::name("user")->where("email", $retrieve_email_code_cache["email"])->where('appid', $this->appid)->find();
            } else {
                $this->json(0, "请先发送验证码");
            }
        }
        if ($type == 2) {
            $mobile_code_cache = Cache::get($this->appid . "mobile_retrieve" . get_client_ip());
            $phone_code_time = config("system.phone_code_time");
            if ($mobile_code_cache) {
                if (time() - $mobile_code_cache["time"] > $phone_code_time) {
                    $this->json(0, "短信验证码已过期");
                }
                if ($captcha != $mobile_code_cache["code"]) {
                    $this->json(0, "短信验证码不正确");
                }
                $userinfo = Db::name("user")->where("mobile", $mobile_code_cache["mobile"])->where('appid', $this->appid)->find();
            } else {
                $this->json(0, "请先发送短信验证码");
            }
        }
        $salt = getRandChar(6);
        $update = [
            "password" => md5($password . $salt),
            "salt" => $salt
        ];
        Cache::delete($this->appid . "mobile_retrieve" . get_client_ip());
        Cache::delete($this->appid . "email_retrieve" . get_client_ip());
        Db::name('user')->where('id', $userinfo["id"])->update($update);
        $this->json(1, "修改成功");
    }

    //上传头像
    public function upload_avatar()
    {
        $data = input('');
        $rule = [
            'usertoken|用户token' => 'require',
        ];
        $validate = new Validate();
        $validate->rule($rule);
        $result = $validate->check($data);
        if (!$result) {
            $this->json(0, $validate->getError());
        }
        try {
            $user_all_info = $this->user_info;
            $upload = new Upload($user_all_info['id']);
            $result = $upload->upload('file');
            $usertx = $result["filePath"];
            $userinfo_configuration = $this->app_info["userinfo_configuration"];
            if ($userinfo_configuration['update_userinfo_audit'] == 0) {
                $add_audit_user_info = [
                    "userid" => $user_all_info['id'],
                    "nickname" => $user_all_info['nickname'],
                    "signature" => $user_all_info['signature'],
                    "usertx" => $usertx,
                    "userbg" => $user_all_info['userbg'],
                    "create_time" => date("Y-m-d H:i:s", time()),
                ];
                $audit_info = Db::name('user_information_review')->where("userid", "=", $user_all_info['id'])->find();
                if ($audit_info) {
                    $add_audit_user_info["audit_status"] = 0;
                    $add_audit_user_info["reason_review"] = "";
                    $add_audit_user_info["nickname"] = $audit_info["nickname"];
                    $add_audit_user_info["signature"] = $audit_info["signature"];
                    $add_audit_user_info["userbg"] = $audit_info["userbg"];
                    Db::name('user_information_review')->where("userid", "=", $user_all_info['id'])->update($add_audit_user_info);
                } else {
                    Db::name('user_information_review')->insert($add_audit_user_info);
                }
                $this->json(1, "上传成功,等待审核");
            }
            Db::name("user")->where("id", $user_all_info["id"])->update(["usertx" => $usertx]);
            if ($user_all_info["usertx"]) {
                $file_url = substr($user_all_info["usertx"], strpos($user_all_info["usertx"], config("upload.file_path")));
                $file = Db::name("file")->where("filePath", $file_url)->find();
                if ($file) {
                    Db::name("file")->where("id", $file['id'])->delete();
                    //删除本地文件 
                    @unlink($file_url);
                }
            }
            $this->json(1, "success", ["url" => $usertx]);
        } catch (\Exception $th) {
            $this->json(0, $th->getMessage());
        }
    }

    //上传背景
    public function upload_background()
    {
        $data = input('');
        $rule = [
            'usertoken|用户token' => 'require',
        ];
        $validate = new Validate();
        $validate->rule($rule);
        $result = $validate->check($data);
        if (!$result) {
            $this->json(0, $validate->getError());
        }
        $user_all_info = $this->user_info;
        try {
            $upload = new Upload($user_all_info['id']);
            $result = $upload->upload('file');
            $userbg = $result["filePath"];
            $userinfo_configuration = $this->app_info["userinfo_configuration"];
            if ($userinfo_configuration['update_userinfo_audit'] == 0) {
                $add_audit_user_info = [
                    "userid" => $user_all_info['id'],
                    "nickname" => $user_all_info['nickname'],
                    "signature" => $user_all_info['signature'],
                    "usertx" => $user_all_info['usertx'],
                    "userbg" => $userbg,
                    "create_time" => date("Y-m-d H:i:s", time()),
                ];
                $audit_info = Db::name('user_information_review')->where("userid", "=", $user_all_info['id'])->find();
                if ($audit_info) {
                    $add_audit_user_info["audit_status"] = 0;
                    $add_audit_user_info["reason_review"] = "";
                    $add_audit_user_info["nickname"] = $audit_info["nickname"];
                    $add_audit_user_info["signature"] = $audit_info["signature"];
                    $add_audit_user_info["usertx"] = $audit_info["usertx"];
                    Db::name('user_information_review')->where("userid", "=", $user_all_info['id'])->update($add_audit_user_info);
                } else {
                    Db::name('user_information_review')->insert($add_audit_user_info);
                }
                $this->json(1, "上传成功,等待审核");
            }
            Db::name("user")->where("id", $user_all_info["id"])->update(["userbg" => $userbg]);
            $this->json(1, "success", ["url" => $userbg]);
        } catch (\Exception $th) {
            $this->json(0, $th->getMessage());
        }
    }

    //修改密码
    public function change_password()
    {
        $data = input('');
        $rule = [
            'usertoken|用户token' => 'require',
            'password|旧密码' => 'require|min:5',
            'new_password|新密码' => 'require|min:5',
        ];
        $validate = new Validate();
        $validate->rule($rule);
        $result = $validate->check($data);
        if (!$result) {
            $this->json(0, $validate->getError());
        }
        $user_info = $this->user_info;
        if ($user_info['password'] != md5($data['password'] . $user_info["salt"])) {
            $this->json(0, "旧密码错误");
        }
        if ($user_info['password'] == md5($data['new_password'] . $user_info["salt"])) {
            $this->json(1, "修改成功");
        }
        Db::name('user')->where("id", $user_info["id"])->update(['password' => md5($data['new_password'] . $user_info["salt"])]);
        $this->json(1, "修改成功");
    }

    //修改用户信息
    public function modify_user_information()
    {
        $data = input('');
        $rule = [
            'usertoken|用户token' => 'require',
            'sex|性别' => 'integer',
            'qq|QQ' => 'number',
        ];
        $validate = new Validate();
        $validate->rule($rule);
        $result = $validate->check($data);
        if (!$result) {
            $this->json(0, $validate->getError());
        }
        $update_user_info = [];
        $other_update_user_info = [];
        $add_audit_user_info = [];
        $user_all_info = $this->user_info;
        if (input("?nickname")) {
            if ($data["nickname"] == "") {
                $this->json(0, "昵称不能为空！");
            }
            $update_user_info["nickname"] = $data["nickname"];
            $add_audit_user_info["nickname"] = $data["nickname"];
        }
        if (input("?sex")) {
            if (!in_array($data["sex"], [0, 1])) {
                $this->json(0, '请输入正确的sex值');
            }
            $other_update_user_info["sex"] = $data["sex"];
        }
        if (input("?qq")) {
            $other_update_user_info["qq"] = $data["qq"];
        }
        if (input("?signature")) {
            $update_user_info["signature"] = $data["signature"];
            $add_audit_user_info["signature"] = $data["signature"];
        }
        if (input("?usertx")) {
            $update_user_info["usertx"] = $data["usertx"];
            $add_audit_user_info["usertx"] = $data["usertx"];
        }
        if (input("?userbg")) {
            $update_user_info["userbg"] = $data["userbg"];
            $add_audit_user_info["userbg"] = $data["userbg"];
        }
        if (!empty($other_update_user_info)) {
            Db::name("user")->where("id", $user_all_info["id"])->update($other_update_user_info);
        }
        if (empty($update_user_info)) {
            $this->json(1, "修改成功");
        }
        $userinfo_configuration = $this->app_info["userinfo_configuration"];
        if ($userinfo_configuration['update_userinfo_audit'] == 0) {
            if (!isset($add_audit_user_info["usertx"])) $add_audit_user_info["usertx"] = $user_all_info['usertx'];
            if (!isset($add_audit_user_info["userbg"])) $add_audit_user_info["userbg"] = $user_all_info['userbg'];
            if (!isset($add_audit_user_info["nickname"])) $add_audit_user_info["nickname"] = $user_all_info['nickname'];
            if (!isset($add_audit_user_info["signature"])) $add_audit_user_info["signature"] = $user_all_info['signature'];
            $add_audit_user_info["userid"] = $user_all_info['id'];
            $add_audit_user_info["create_time"] = date("Y-m-d H:i:s", time());
            $audit_info = Db::name('user_information_review')->where("userid", "=", $user_all_info['id'])->find();
            if ($audit_info) {
                if (!isset($add_audit_user_info["usertx"])) $add_audit_user_info["usertx"] = $audit_info['usertx'];
                if (!isset($add_audit_user_info["userbg"])) $add_audit_user_info["userbg"] = $audit_info['userbg'];
                if (!isset($add_audit_user_info["nickname"])) $add_audit_user_info["nickname"] = $audit_info['nickname'];
                if (!isset($add_audit_user_info["signature"])) $add_audit_user_info["signature"] = $audit_info['signature'];
                $add_audit_user_info["audit_status"] = 0;
                $add_audit_user_info["reason_review"] = "";
                Db::name('user_information_review')->where("userid", "=", $user_all_info['id'])->update($add_audit_user_info);
            } else {
                Db::name('user_information_review')->insert($add_audit_user_info);
            }
            $this->json(1, "修改成功,等待审核");
        }
        Db::name("user")->where("id", $user_all_info["id"])->update($update_user_info);
        $this->json(1, "修改成功");
    }

    //修改用户邮箱
    public function modify_user_email()
    {
        $data = input('');
        $rule = [
            'usertoken|用户token' => 'require',
            'email|邮箱' => 'require|email',
            'code|邮箱验证码' => 'require|number',
        ];
        $validate = new Validate();
        $validate->rule($rule);
        $result = $validate->check($data);
        if (!$result) {
            $this->json(0, $validate->getError());
        }
        $email_update_code_cache = Cache::get($this->appid . "email_update" . get_client_ip());
        $email_code_time = config("system.email_code_time");
        if ($email_update_code_cache) {
            if (time() - $email_update_code_cache["time"] > $email_code_time) {
                $this->json(0, "验证码已过期，请重新获取");
            }
            if ($email_update_code_cache["code"] != $data["code"]) {
                $this->json(0, "验证码错误");
            }
            $user_all_info = $this->user_info;
            $update_user_info = [];
            $update_user_info["email"] = $email_update_code_cache["email"];
            Db::name("user")->where("id", $user_all_info["id"])->update($update_user_info);
            Cache::delete($this->appid . "email_update" . get_client_ip());
            $this->json(1, "修改成功");
        } else {
            $this->json(0, "验证码已过期，请重新获取");
        }
    }

    //修改手机号
    public function modify_user_phone()
    {
        $data = input('');
        $rule = [
            'usertoken|用户token' => 'require',
            'phone|手机号' => 'require|number',
            'code|手机验证码' => 'require|number',
        ];
        $validate = new Validate();
        $validate->rule($rule);
        $result = $validate->check($data);
        if (!$result) {
            $this->json(0, $validate->getError());
        }
        $phone_update_code_cache = Cache::get($this->appid . "phone_update" . get_client_ip());
        $phone_code_time = config("system.phone_code_time");
        if ($phone_update_code_cache) {
            if (time() - $phone_update_code_cache["time"] > $phone_code_time) {
                $this->json(0, "验证码已过期，请重新获取");
            }
            if ($phone_update_code_cache["code"] != $data["code"]) {
                $this->json(0, "验证码错误");
            }
            $user_all_info = $this->user_info;
            $update_user_info = [];
            $update_user_info["mobile"] = $phone_update_code_cache["mobile"];
            Db::name("user")->where("id", $user_all_info["id"])->update($update_user_info);
            Cache::delete($this->appid . "phone_update" . get_client_ip());
            $this->json(1, "修改成功");
        } else {
            $this->json(0, "验证码已过期，请重新获取");
        }
    }

    //填写邀请码
    public function fill_invitation_code()
    {
        if ($this->app_info["invitation_configuration"]["invitation_switch"] == 1) {
            $this->json(0, "此APP已关闭邀请配置");
        }
        $invitation_configuration = $this->app_info["invitation_configuration"];
        $data = input('');
        $rule = [
            'usertoken|用户token' => 'require',
            'invitecode|邀请码' => 'require',
        ];
        $validate = new Validate();
        $validate->rule($rule);
        $result = $validate->check($data);
        if (!$result) {
            $this->json(0, $validate->getError());
        }
        $user_all_info = $this->user_info;
        $is_fill_invitation_code = Db::name("polymorphic")->where("other_id", $user_all_info["id"])->where("type", 1)->find();
        if ($is_fill_invitation_code) {
            $this->json(0, "已经填写过邀请码了");
        }
        $invitecode_userinfo = Db::name("user")->where("appid", $this->appid)->where("invitecode", $data["invitecode"])->find();
        if (!$invitecode_userinfo) {
            $this->json(0, "不存在此邀请码");
        }
        if ($invitecode_userinfo["viptime"] >= time()) {
            $userviptime = $invitecode_userinfo["viptime"];
        } else {
            $userviptime = time();
        }
        $updateinvitecode = [
            "money" => $invitecode_userinfo["money"] + $invitation_configuration["money"],
            "integral" => $invitecode_userinfo["integral"] + $invitation_configuration["integral"],
            "exp" => $invitecode_userinfo["exp"] + $invitation_configuration["exp"],
            "viptime" => $userviptime + $invitation_configuration["vip"] * 24 * 3600,
        ];
        Db::name("user")->where("id", $invitecode_userinfo["id"])->update($updateinvitecode);
        $adddata = [
            "userid" => $invitecode_userinfo["id"],
            "other_id" => $user_all_info["id"],
            "appid" => $data["appid"],
            "create_time" => date("Y-m-d H:i:s", time()),
            "type" => 1
        ];
        //增加用户的交易账单
        if ($invitation_configuration["money"] != 0) {
            add_user_bill($invitecode_userinfo, 0, "+" . $invitation_configuration["money"], "邀请好友" . $user_all_info["username"] . "奖励", 0);
        }
        if ($invitation_configuration["integral"] != 0) {
            add_user_bill($invitecode_userinfo, 0, "+" . $invitation_configuration["integral"], "邀请好友" . $user_all_info["username"] . "奖励", 1);
        }
        Db::name("polymorphic")->insert($adddata);
        $this->json();
    }

    //用户金币/经验/积分排行榜
    public function ranking_list()
    {
        $sort = input("sort");
        $sortOrder = input("sortOrder");
        $sortOrder = $sortOrder != "" ? input('sortOrder') : 'desc';
        if (!in_array($sort, ["money", "exp", "integral"])) {
            $this->json(0, '请输入正确的sort值');
        }
        if (!in_array($sortOrder, ["asc", "desc"])) {
            $this->json(0, '请输入正确的sortOrder值');
        }
        if ($sort == "money") {
            $need_field = ['id', 'username', 'nickname', 'usertx', 'money', 'title'];
        } elseif ($sort == "exp") {
            $need_field = ['id', 'username', 'nickname', 'usertx', 'exp', 'title'];
        } else {
            $need_field = ['id', 'username', 'nickname', 'usertx', 'integral', 'title'];
        }
        $res = Db::name('user')->where('appid', $this->appid)->order($sort, $sortOrder)->field($need_field)->page($this->page)->limit($this->limit)->select()->toArray();
        foreach ($res as $key => $value) {
            $res[$key]["title"] = array_filter(explode(",", $value["title"]));
            $res[$key]["badge"] = Db::name("polymorphic")
                ->alias("p")
                ->join("bagge b", "b.id=p.other_id")
                ->where("p.userid", $value["id"])
                ->where("p.type", 5)
                ->where("b.is_view", 0)
                ->where("p.wearing", 0)
                ->order(["b.type" => $this->medal_sorting, "b.sort" => "desc"])
                ->field("b.id,b.name,b.icon,case when p.expiration_time = '9999' then '永久' else p.expiration_time end as expiration_time")
                ->select()->toArray();
        }
        $this->json(1, "查询成功", $res);
    }

    //邀请排行榜
    public function invitation_ranking()
    {
        $sortOrder = input("sortOrder");
        if (!in_array($sortOrder, ["asc", "desc"])) {
            $this->json(0, '请输入正确的sortOrder值');
        }
        $sql = "SELECT u.id,u.username,u.nickname,u.usertx,u.title,IFNULL(i.invited_count, 0) as invited_count FROM mr_user as u LEFT JOIN (SELECT userid,COUNT(other_id) AS invited_count FROM mr_polymorphic WHERE type = 1 and appid = {$this->appid} GROUP BY userid) AS i on i.userid = u.id where appid = {$this->appid} order by invited_count {$sortOrder} limit {$this->limit}";
        $result = Db::query($sql);
        foreach ($result as $key => $value) {
            $result[$key]["title"] = array_filter(explode(",", $value["title"]));
            $result[$key]["badge"] = Db::name("polymorphic")
                ->alias("p")
                ->join("bagge b", "b.id=p.other_id")
                ->where("p.userid", $value["id"])
                ->where("p.type", 5)
                ->where("b.is_view", 0)
                ->where("p.wearing", 0)
                ->order(["b.type" => $this->medal_sorting, "b.sort" => "desc"])
                ->field("b.id,b.name,b.icon,case when p.expiration_time = '9999' then '永久' else p.expiration_time end as expiration_time")
                ->select()->toArray();
        }
        $this->json(1, "查询成功", $result);
    }

    //关注用户 or 取消关注
    public function follow_users()
    {
        $data = input();
        $rule = [
            'followedid|关注的用户ID' => 'require|number',
            'usertoken' => 'require',
        ];
        $validate = new Validate();
        $validate->rule($rule);
        $result = $validate->check($data);
        if (!$result) {
            $this->json(0, $validate->getError());
        }
        $user_all_info = $this->user_info;
        $followeduserinfo = Db::name("user")->where("appid", $data["appid"])->where("id", $data["followedid"])->find();
        if (!$followeduserinfo) {
            $this->json(0, "用户不存在");
        }
        if ($user_all_info["id"] == $data["followedid"]) {
            $this->json(0, "不能关注自己");
        }
        $followinfo = Db::name("polymorphic")->where("appid", $data["appid"])->where("type", 2)->where("userid", $user_all_info["id"])->where("other_id", $data["followedid"])->find();
        if ($followinfo) {
            Db::name("polymorphic")->where("id", $followinfo["id"])->delete();
            $this->json(1, "取消关注成功");
        }
        $adddata = [
            "userid" => $user_all_info["id"],
            "other_id" => $data["followedid"],
            "appid" => $data["appid"],
            "create_time" => date("Y-m-d H:i:s", time()),
            "type" => 2
        ];
        Db::name("polymorphic")->insert($adddata);
        $this->json(1, "关注成功");
    }

    //查询关注状态
    public function get_follow_status()
    {
        $data = input();
        $rule = [
            'followedid|关注的用户ID' => 'require|number',
            'usertoken' => 'require',
        ];
        $validate = new Validate();
        $validate->rule($rule);
        $result = $validate->check($data);
        if (!$result) {
            $this->json(0, $validate->getError());
        }
        $user_all_info = $this->user_info;
        $followeduserinfo = Db::name("user")->where("appid", $data["appid"])->where("id", $data["followedid"])->find();
        if (!$followeduserinfo) {
            $this->json(0, "用户不存在");
        }
        $status = 3;
        $followinfo = Db::name("polymorphic")->where("appid", $data["appid"])->where("type", 2)->where("userid", $user_all_info["id"])->where("other_id", $data["followedid"])->find();
        $ffollowinfo = Db::name("polymorphic")->where("appid", $data["appid"])->where("type", 2)->where("userid", $data["followedid"])->where("other_id", $user_all_info["id"])->find();
        // $status 0互相关注 1他关注了我 2我关注了他 3互相都没有关注
        if ($followinfo) {
            if ($ffollowinfo) {
                $status = 0;
            } else {
                $status = 2;
            }
        } else {
            if ($ffollowinfo) {
                $status = 1;
            } else {
                $status = 3;
            }
        }
        $this->json(1, "success", ["status" => $status]);
    }

    //查询关注列表
    public function get_follow_list()
    {
        $data = input();
        $rule = [
            'usertoken' => 'require',
        ];
        $validate = new Validate();
        $validate->rule($rule);
        $result = $validate->check($data);
        if (!$result) {
            $this->json(0, $validate->getError());
        }
        $user_all_info = $this->user_info;
        $result = Db::name("polymorphic")
            ->alias("f")
            ->join("user u", "u.id=f.other_id")
            ->where("f.type", 2)
            ->where("f.appid", $data["appid"])
            ->where("f.userid", $user_all_info["id"])
            ->field("u.id,f.other_id,u.username,u.nickname,u.usertx,u.sex,u.signature,u.title,u.viptime,u.exp")
            ->limit($this->limit)
            ->page($this->page)
            ->select()->toArray();
        $pagecount = Db::name("polymorphic")
            ->alias("f")
            ->join("user u", "u.id=f.other_id")
            ->where("f.type", 2)
            ->where("f.appid", $data["appid"])
            ->where("f.userid", $user_all_info["id"])
            ->field("u.id,u.username,u.nickname,u.usertx,u.sex,u.signature,u.title,u.exp")
            ->count();
        foreach ($result as $key => $value) {
            //获取用户的徽章
            $result[$key]["badge"] = Db::name("polymorphic")
                ->alias("p")
                ->join("bagge b", "b.id=p.other_id")
                ->where("p.userid", $value["other_id"])
                ->where("p.type", 5)
                ->where("b.is_view", 0)
                ->where("p.wearing", 0)
                ->order(["b.type" => $this->medal_sorting, "b.sort" => "desc"])
                ->field("b.id,b.name,b.icon,b.type,case when p.expiration_time = '9999' then '永久' else p.expiration_time end as expiration_time")
                ->select()->toArray();
            $result[$key]["status"] = 2;
            $result[$key]["sex"] = $value["sex"];
            $result[$key]["sexName"] = $value["sex"] == 0 ? "男" : "女";
            $ffollowinfo = Db::name("polymorphic")->where("type", 2)->where("userid", $value["other_id"])->where("other_id", $user_all_info["id"])->find();
            if ($ffollowinfo) {
                $result[$key]["status"] = 0;
            }
            //是否是会员
            if (time() < $value["viptime"]) {
                $result[$key]["vip"] = true;
            } else {
                $result[$key]["vip"] = false;
            }
            //经验等级
            $arr = $this->app_info["grade"];
            $grades = eval("return $arr;");
            $result[$key]["hierarchy"] = "";
            if (is_array($grades)) {
                foreach ($grades as $k1 => $v1) {
                    if ($result[$key]['exp'] >= $k1) {
                        $result[$key]["hierarchy"] = $v1;
                    } else {
                        break;
                    }
                }
            }
            $result[$key]["title"] = array_filter(explode(",", $value["title"]));
            unset($result[$key]["other_id"]);
            unset($result[$key]["viptime"]);
            unset($result[$key]["exp"]);
        }
        $data_rs["list"] = $result;
        $data_rs["pagecount"] = ceil($pagecount / $this->limit) == 0 ? 1 : ceil($pagecount / $this->limit);
        $data_rs["current_number"] = $this->page;
        $this->json(1, "success", $data_rs);
    }

    //查询粉丝列表
    public function get_fan_list()
    {
        $data = input();
        $rule = [
            'usertoken' => 'require',
        ];
        $validate = new Validate();
        $validate->rule($rule);
        $result = $validate->check($data);
        if (!$result) {
            $this->json(0, $validate->getError());
        }
        $user_all_info = $this->user_info;
        $result = Db::name("polymorphic")
            ->alias("f")
            ->join("user u", "u.id=f.userid")
            ->where("f.type", 2)
            ->where("f.appid", $data["appid"])
            ->where("f.other_id", $user_all_info["id"])
            ->field("u.id,u.username,u.nickname,u.usertx,u.sex,u.signature,u.title,u.viptime,u.exp")
            ->limit($this->limit)
            ->page($this->page)
            ->select()->toArray();
        $pagecount = Db::name("polymorphic")
            ->alias("f")
            ->join("user u", "u.id=f.userid")
            ->where("f.type", 2)
            ->where("f.appid", $data["appid"])
            ->where("f.other_id", $user_all_info["id"])
            ->field("u.id,u.username,u.nickname,u.usertx,u.sex,u.signature,u.title,u.exp")
            ->count();
        foreach ($result as $key => $value) {
            //获取用户的徽章
            $result[$key]["badge"] = Db::name("polymorphic")
                ->alias("p")
                ->join("bagge b", "b.id=p.other_id")
                ->where("p.userid", $value["id"])
                ->where("p.type", 5)
                ->where("b.is_view", 0)
                ->where("p.wearing", 0)
                ->order(["b.type" => $this->medal_sorting, "b.sort" => "desc"])
                ->field("b.id,b.name,b.icon,b.type,case when p.expiration_time = '9999' then '永久' else p.expiration_time end as expiration_time")
                ->select()->toArray();
            //是否是会员
            if (time() < $value["viptime"]) {
                $result[$key]["vip"] = true;
            } else {
                $result[$key]["vip"] = false;
            }
            //经验等级
            $arr = $this->app_info["grade"];
            $grades = eval("return $arr;");
            $result[$key]["hierarchy"] = "";
            if (is_array($grades)) {
                foreach ($grades as $k1 => $v1) {
                    if ($result[$key]['exp'] >= $k1) {
                        $result[$key]["hierarchy"] = $v1;
                    } else {
                        break;
                    }
                }
            }
            $result[$key]["status"] = 1;
            $result[$key]["sex"] = $value["sex"];
            $result[$key]["sexName"] = $value["sex"] == 0 ? "男" : "女";
            $ffollowinfo = Db::name("polymorphic")->where("type", 2)->where("userid", $value['id'])->where("other_id", $user_all_info["id"])->find();
            if ($ffollowinfo) {
                $result[$key]["status"] = 0;
            }
            $result[$key]["title"] = array_filter(explode(",", $value["title"]));
            unset($result[$key]["viptime"]);
            unset($result[$key]["exp"]);
        }
        $data_rs["list"] = $result;
        $data_rs["pagecount"] = ceil($pagecount / $this->limit) == 0 ? 1 : ceil($pagecount / $this->limit);
        $data_rs["current_number"] = $this->page;
        $this->json(1, "success", $data_rs);
    }

    //获取用户账单
    public function get_user_billing()
    {
        $data = $this->secureChatRequestInput(false);
        $rule = [
            'usertoken|用户token' => 'require',
        ];
        $validate = new Validate();
        $validate->rule($rule);
        $result = $validate->check($data);
        if (!$result) {
            $this->json(0, $validate->getError());
        }
        $user_info = $this->user_info;
        $where = "userid = {$user_info['id']} and appid = {$this->appid}";
        if (isset($data["transaction_type"]) && (string)$data["transaction_type"] !== "") {
            if (!in_array((int)$data["transaction_type"], [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 11], true)) {
                $this->json(0, "请输入正确的transaction_type值");
            }
            $where .= " and transaction_type = " . (int)$data['transaction_type'];
        }
        if (isset($data["deduction_type"]) && (string)$data["deduction_type"] !== "") {
            if (!in_array((int)$data["deduction_type"], [0, 1], true)) {
                $this->json(0, "请输入正确的deduction_type值");
            }
            $where .= " and type = " . (int)$data['deduction_type'];
        }
        if (isset($data["type"]) && (string)$data["type"] !== "") {
            if (!in_array((int)$data["type"], [0, 1], true)) {
                $this->json(0, "请输入正确的type值");
            }
            if ((int)$data["type"] === 0) {
                $where .= " and transaction_amount like '-%'";
            } else {
                $where .= " and transaction_amount like '+%'";
            }
        }
        //获取用户的账单
        $result = Db::name("transaction_statement")
            ->where($where)
            ->field("userid,appid,frozen", true)
            ->order("transaction_date desc")
            ->limit($this->limit)
            ->page($this->page)
            ->select()->toArray();
        $pagecount = Db::name("transaction_statement")
            ->where($where)
            ->order("transaction_date desc")
            ->count();
        $data_rs["list"] = $result;
        $data_rs["pagecount"] = ceil($pagecount / $this->limit) == 0 ? 1 : ceil($pagecount / $this->limit);
        $data_rs["current_number"] = $this->page;
        $this->chatJson(1, "success", $data_rs);
    }

    //用户提现金币、积分
    public function user_withdraw_cash()
    {
        $data = $this->secureChatRequestInput();
        $rule = [
            'usertoken|用户token' => 'require',
            'account|收款账户' => 'require',
            'name|收款人姓名' => 'require',
            'money|提现金额' => 'require|number',
            'type|提现类型' => 'require|number',
        ];
        $validate = new Validate();
        $validate->rule($rule);
        $result = $validate->check($data);
        if (!$result) {
            $this->json(0, $validate->getError());
        }
        //判断type值是否正确
        if (!in_array((int)$data["type"], [0, 1], true)) {
            $this->json(0, "请输入正确的type值");
        }
        if ((int)$data["type"] === 0) {
            try {
                $data["money"] = $this->normalizeWalletMoney($data["money"]);
            } catch (\Throwable $e) {
                $this->json(0, $e->getMessage());
            }
        } else {
            $moneyText = trim((string)$data["money"]);
            if ($moneyText === "" || !preg_match("/^\\d+$/", $moneyText) || (int)$moneyText <= 0) {
                $this->json(0, "提现积分必须是正整数");
            }
            $data["money"] = (string)(int)$moneyText;
        }
        $user_all_info = $this->user_info;
        try {
            $this->assertAssetBalance($user_all_info, (int)$data["type"] === 0 ? "money" : "integral", $data["money"]);
        } catch (\Throwable $e) {
            $this->json(0, $e->getMessage());
        }
        //验证提现金额是否大于用户余额
        if ((int)$data["type"] === 0) {
            $minimum = $this->walletAmountLabel($this->app_info["forum_configuration"]["money_minimum_withdrawal_amount"] ?? 0);
            //验证提现金额是否大于最低提现金额
            if ($this->walletCompare($data["money"], $minimum) < 0) {
                $this->json(0, "最低提现金额为" . $minimum);
            }
        } else {
            //验证提现金额是否大于最低提现金额
            if ($this->app_info["forum_configuration"]["integral_minimum_withdrawal_amount"] > $data["money"]) {
                $this->json(0, "最低提现积分为" . $this->app_info["forum_configuration"]["integral_minimum_withdrawal_amount"]);
            }
        }
        // 开启数据库事务
        Db::startTrans();
        try {
            $user_info = Db::name("user")
                ->where("id", $user_all_info["id"])
                ->where("appid", $this->appid)
                ->lock(true)
                ->find();
            if (!$user_info) {
                throw new Exception("系统繁忙，请稍后再试!");
            }
            //扣除用户余额
            if ((int)$data["type"] === 0) {
                $this->assertAssetBalance($user_info, "money", $data["money"]);
                $update_user_info = Db::name("user")
                    ->where("id", $user_all_info["id"])
                    ->where("appid", $this->appid)
                    ->where("money", ">=", $data["money"])
                    ->update(["money" => Db::raw("money - " . $data["money"])]);
            } else {
                $this->assertAssetBalance($user_info, "integral", $data["money"]);
                $update_user_info = Db::name("user")
                    ->where("id", $user_all_info["id"])
                    ->where("appid", $this->appid)
                    ->where("integral", ">=", (int)$data["money"])
                    ->update(["integral" => Db::raw("integral - " . (int)$data["money"])]);
            }
            if (!$update_user_info) {
                throw new Exception("系统繁忙，请稍后再试!");
            }
            //添加交易记录
            $bill_id = add_user_bill($user_all_info, 7, "-" . $data["money"], $data["type"] == 0 ? "提现金币" : "提现积分" . $data['money'], $data["type"], 1);
            if (!$bill_id) {
                throw new Exception("系统繁忙，请稍后再试!");
            }
            //添加提现记录
            $add_data = [
                "userid" => $user_all_info["id"],
                "withdrawal_note_number" => $this->generateOrderNumber(''),
                "receivable_account" => $data["account"],
                "name" => $data["name"],
                "withdraw_fee" => $data["money"],
                "type" => $data["type"],
                "ip" => get_client_ip(),
                "appid" => $this->appid,
                "create_time" => date("Y-m-d H:i:s", time()),
                "bill_id" => $bill_id,
                "remarks" => (string)($data["remarks"] ?? $data["remark"] ?? ""),
            ];
            $add_withdrawal_record = Db::name("withdrawal_record")->insert($add_data);
            if (!$add_withdrawal_record) {
                throw new Exception("系统繁忙，请稍后再试!");
            }
            // 提交事务
            Db::commit();
            $freshUser = Db::name("user")->where("id", $user_all_info["id"])->where("appid", $this->appid)->find() ?: $user_info;

            $this->chatJson(1, "提现成功，请等待审核", [
                "balance" => $this->walletAmountLabel($freshUser["money"] ?? 0),
            ]);
        } catch (\Throwable $th) {
            // 回滚事务
            Db::rollback();
            $this->json(0, $th->getMessage());
        }
    }

    //获取用户提现记录
    public function get_user_withdraw_cash_list()
    {
        $data = $this->secureChatRequestInput(false);
        $rule = [
            'usertoken|用户token' => 'require',
        ];
        $validate = new Validate();
        $validate->rule($rule);
        $result = $validate->check($data);
        if (!$result) {
            $this->json(0, $validate->getError());
        }
        $user_all_info = $this->user_info;
        $where = "appid = {$this->appid} and userid = {$user_all_info['id']} ";
        if (isset($data["type"]) && (string)$data["type"] !== "") {
            $where .= " and type = " . (int)$data["type"];
        }
        $result = Db::name("withdrawal_record")
            ->field('bill_id,userid,appid,ip', true)
            ->where($where)
            ->order("id desc")
            ->limit($this->limit)
            ->page($this->page)
            ->select()->toArray();
        $pagecount = Db::name("withdrawal_record")
            ->where($where)
            ->order("id desc")
            ->count();
        $data_rs["list"] = $result;
        $data_rs["pagecount"] = ceil($pagecount / $this->limit) == 0 ? 1 : ceil($pagecount / $this->limit);
        $data_rs["current_number"] = $this->page;
        $this->chatJson(1, "success", $data_rs);
    }

    //使用直冲卡密
    public function apply_direct_charge_km()
    {
        $data = $this->secureChatRequestInput();
        $rule = [
            'usertoken|用户token' => 'require',
            'km|卡密' => 'require',
        ];
        $validate = new Validate();
        $validate->rule($rule);
        $result = $validate->check($data);
        if (!$result) {
            $this->json(0, $validate->getError());
        }
        $km_info = Db::name("km")->where("type", 0)->where("appid", $this->appid)->where("km", $data["km"])->find();
        if (!$km_info) {
            $this->json(0, "卡密不存在");
        }
        if ($km_info["state"] == 1) {
            $this->json(0, "卡密已被使用");
        }
        $user_info = $this->user_info;
        $currentTime = time();
        // 开启数据库事务
        Db::startTrans();

        try {
            // 使用悲观锁锁定卡密记录
            $kmRecord = Db::name("km")
                ->where("id", $km_info["id"])
                ->where("state", 0)
                ->lock(true)
                ->find();

            if (!$kmRecord) {
                throw new Exception("卡密已被使用");
            }

            // 计算用户的会员到期时间
            if ($user_info["viptime"] >= time()) {
                $userviptime = $user_info["viptime"];
            } else {
                $userviptime = $currentTime;
            }
            $update_user_info = [
                "money" => $user_info["money"] + $km_info["money"],
                "integral" => $user_info["integral"] + $km_info["integral"],
                "viptime" => $userviptime + $km_info["viptime"] * 3600 * 24,
            ];
            $update_userinfo = Db::name("user")->where("id", $user_info["id"])->update($update_user_info);

            if (!$update_userinfo) {
                throw new Exception("使用失败");
            }
            //更新卡密信息
            $update_km_info = Db::name("km")->where("id", $km_info["id"])->update([
                "state" => 1,
                "username" => $user_info["username"],
                "usage_time" => date("Y-m-d H:i:s",  $currentTime),
            ]);
            if (!$update_km_info) {
                throw new Exception("更新卡密信息失败");
            }
            //添加用户账单
            if ($km_info["money"] > 0) {
                add_user_bill($user_info, 8, "+" . $km_info["money"], "使用卡密", 0, 0);
            }
            if ($km_info["integral"] > 0) {
                add_user_bill($user_info, 8, "+" . $km_info["integral"], "使用卡密", 1, 0);
            }
            increase_system_notifications_to_users("使用卡密成功", $km_info, $user_info["id"], 1);
            // 提交事务
            Db::commit();
            $this->chatJson(1, "使用成功");
        } catch (\Exception $e) {
            // 回滚事务
            Db::rollback();
            $this->json(0, "使用失败");
        }
    }

    public function service_account_list()
    {
        $this->secureChatRequestInput(false);
        try {
            $this->serviceAccountEnsureDefaults();
            $rows = Db::name("service_account")
                ->alias("s")
                ->leftJoin("user u", "u.id=s.user_id and u.appid=s.appid")
                ->leftJoin("service_account_user su", "su.service_id=s.id and su.appid=s.appid and su.user_id=" . (int)$this->user_info["id"])
                ->where("s.appid", $this->appid)
                ->where("s.status", 1)
                ->where("s.show_in_contacts", 1)
                ->where(function ($query) {
                    $query->whereNull("su.following")->whereOr("su.following", "<>", 0);
                })
                ->field("s.*,u.usertx,su.muted,su.pinned,su.following")
                ->order("s.sort desc,s.id asc")
                ->select()
                ->toArray();
            $list = [];
            foreach ($rows as $row) {
                $item = $this->formatServiceAccount($row);
                if ($item["channel_id"] !== "") {
                    $list[] = $item;
                }
            }
            $this->chatJson(1, "success", ["list" => $list]);
        } catch (\Throwable $e) {
            $this->json(0, $e->getMessage());
        }
    }

    public function service_account_detail()
    {
        $data = $this->secureChatRequestInput(false);
        try {
            $this->serviceAccountEnsureDefaults();
            $serviceId = (int)($data["service_id"] ?? 0);
            $code = trim((string)($data["code"] ?? ""));
            $query = Db::name("service_account")
                ->alias("s")
                ->leftJoin("user u", "u.id=s.user_id and u.appid=s.appid")
                ->leftJoin("service_account_user su", "su.service_id=s.id and su.appid=s.appid and su.user_id=" . (int)$this->user_info["id"])
                ->where("s.appid", $this->appid)
                ->where("s.status", 1)
                ->field("s.*,u.usertx,su.muted,su.pinned,su.following");
            if ($serviceId > 0) {
                $query->where("s.id", $serviceId);
            } elseif ($code !== "") {
                $query->where("s.code", $code);
            } else {
                throw new \Exception("service_id不能为空");
            }
            $row = $query->find();
            if (!$row) {
                throw new \Exception("服务号不存在或已停用");
            }
            $this->chatJson(1, "success", $this->formatServiceAccount($row));
        } catch (\Throwable $e) {
            $this->json(0, $e->getMessage());
        }
    }

    public function service_account_settings_update()
    {
        $data = $this->secureChatRequestInput();
        try {
            $serviceId = (int)($data["service_id"] ?? 0);
            if ($serviceId <= 0) {
                throw new \Exception("service_id不能为空");
            }
            $service = Db::name("service_account")
                ->where("appid", $this->appid)
                ->where("id", $serviceId)
                ->where("status", 1)
                ->find();
            if (!$service) {
                throw new \Exception("服务号不存在或已停用");
            }
            $muted = array_key_exists("muted", $data) ? (int)($data["muted"] ? 1 : 0) : null;
            $pinned = array_key_exists("pinned", $data) ? (int)($data["pinned"] ? 1 : 0) : null;
            $following = array_key_exists("following", $data) ? (int)($data["following"] ? 1 : 0) : null;
            if ($following === 0 && (int)($service["allow_unfollow"] ?? 0) !== 1) {
                throw new \Exception("该服务号不支持取消关注");
            }
            $now = date("Y-m-d H:i:s");
            $exists = Db::name("service_account_user")
                ->where("appid", $this->appid)
                ->where("service_id", $serviceId)
                ->where("user_id", (int)$this->user_info["id"])
                ->find();
            $save = [
                "appid" => $this->appid,
                "service_id" => $serviceId,
                "user_id" => (int)$this->user_info["id"],
                "update_time" => $now,
            ];
            if ($muted !== null) {
                $save["muted"] = $muted;
            }
            if ($pinned !== null) {
                $save["pinned"] = $pinned;
            }
            if ($following !== null) {
                $save["following"] = $following;
            }
            if ($exists) {
                Db::name("service_account_user")->where("id", (int)$exists["id"])->update($save);
            } else {
                $save += ["muted" => $muted ?? 0, "pinned" => $pinned ?? 0, "following" => $following ?? 1, "create_time" => $now];
                Db::name("service_account_user")->insert($save);
            }
            $row = Db::name("service_account")
                ->alias("s")
                ->leftJoin("user u", "u.id=s.user_id and u.appid=s.appid")
                ->leftJoin("service_account_user su", "su.service_id=s.id and su.appid=s.appid and su.user_id=" . (int)$this->user_info["id"])
                ->where("s.id", $serviceId)
                ->where("s.appid", $this->appid)
                ->field("s.*,u.usertx,su.muted,su.pinned,su.following")
                ->find();
            $this->chatJson(1, "设置成功", $this->formatServiceAccount($row ?: $service));
        } catch (\Throwable $e) {
            $this->json(0, $e->getMessage());
        }
    }

    public function wallet_balance()
    {
        $this->secureChatRequestInput(false);
        $user = Db::name("user")->where("appid", $this->appid)->where("id", (int)$this->user_info["id"])->find();
        if (!$user) {
            $this->json(0, "用户不存在");
        }
        $this->chatJson(1, "success", $this->walletBalancePayload($user));
    }

    public function wallet_bill_list()
    {
        $data = $this->secureChatRequestInput(false);
        $user = $this->user_info;
        $query = Db::name("transaction_statement")
            ->where("appid", $this->appid)
            ->where("userid", (int)$user["id"])
            ->where("type", 0);
        $scene = trim((string)($data["scene"] ?? "all"));
        $this->walletApplyBillSceneFilter($query, $scene);
        $rows = $query
            ->order("transaction_date", "desc")
            ->page($this->page, $this->limit)
            ->select()->toArray();
        $list = array_map(fn($row) => $this->formatWalletBill($row), $rows);
        $countQuery = Db::name("transaction_statement")
            ->where("appid", $this->appid)
            ->where("userid", (int)$user["id"])
            ->where("type", 0);
        $this->walletApplyBillSceneFilter($countQuery, $scene);
        $count = $countQuery->count();
        $this->chatJson(1, "success", [
            "list" => $list,
            "pagecount" => ceil($count / $this->limit) == 0 ? 1 : ceil($count / $this->limit),
            "current_number" => $this->page,
        ]);
    }

    public function wallet_bill_detail()
    {
        $data = $this->secureChatRequestInput(false);
        $id = (int)($data["id"] ?? $data["bill_id"] ?? 0);
        if ($id <= 0) {
            $this->json(0, "账单不存在");
        }
        $row = Db::name("transaction_statement")
            ->where("appid", $this->appid)
            ->where("userid", (int)$this->user_info["id"])
            ->where("type", 0)
            ->where("id", $id)
            ->find();
        if (!$row) {
            $this->json(0, "账单不存在");
        }
        $bill = $this->formatWalletBill($row);
        $order = [];
        if ($bill["order_no"] !== "") {
            $order = $this->walletOrderQuery()
                ->where("o.appid", $this->appid)
                ->where("o.order_no", $bill["order_no"])
                ->where(function ($query) {
                    $query->where("o.payer_id", (int)$this->user_info["id"])->whereOr("o.payee_id", (int)$this->user_info["id"]);
                })
                ->find() ?: [];
        }
        if ($order) {
            $bill["order"] = $this->formatWalletOrder($order);
            $bill["target_name"] = $bill["direction"] === "expense"
                ? (string)($bill["order"]["payee_name"] ?? $bill["target_name"])
                : (string)($bill["order"]["payer_name"] ?? $bill["target_name"]);
            $bill["target_avatar"] = $bill["direction"] === "expense"
                ? (string)($bill["order"]["payee_avatar"] ?? "")
                : (string)($bill["order"]["payer_avatar"] ?? "");
        } else {
            $bill["order"] = new \stdClass();
        }
        $this->chatJson(1, "success", $bill);
    }

    public function wallet_recharge_km()
    {
        $this->apply_direct_charge_km();
    }

    public function wallet_withdraw()
    {
        $this->user_withdraw_cash();
    }

    public function wallet_withdraw_list()
    {
        $this->get_user_withdraw_cash_list();
    }

    public function user_security_info()
    {
        $this->secureChatRequestInput(false);
        $user = Db::name("user")
            ->where("appid", $this->appid)
            ->where("id", (int)$this->user_info["id"])
            ->find();
        if (!$user) {
            $this->json(0, "用户不存在");
        }
        $this->chatJson(1, "success", $this->userSecurityPayload($user));
    }

    public function user_mobile_bind_code_send()
    {
        $data = $this->secureChatRequestInput(false);
        try {
            $mobile = trim((string)($data["mobile"] ?? ""));
            $validate = new Validate();
            $validate->rule(['mobile|手机号' => 'require|mobile']);
            if (!$validate->check(["mobile" => $mobile])) {
                throw new \Exception((string)$validate->getError());
            }
            $this->assertImageCaptchaScene("security", (string)($data["captcha"] ?? ""), true);
            $exists = Db::name("user")
                ->where("appid", $this->appid)
                ->where("mobile", $mobile)
                ->where("id", "<>", (int)$this->user_info["id"])
                ->find();
            if ($exists) {
                throw new \Exception("该手机号已绑定其他账号");
            }
            $cacheKey = $this->appid . "bind_mobile_" . (int)$this->user_info["id"];
            $cache = Cache::get($cacheKey);
            if ($cache && time() - (int)($cache["time"] ?? 0) < 60) {
                throw new \Exception("验证码发送太频繁");
            }
            $code = (string)random_int(100000, 999999);
            $sms = new AlibabaSample();
            $sms->setCode($code);
            $result = $sms->send($mobile);
            if ($result != 1) {
                throw new \Exception((string)$result);
            }
            Cache::set($cacheKey, ["code" => $code, "mobile" => $mobile, "time" => time()], 300);
            $this->chatJson(1, "发送成功", ["expire_in" => 300]);
        } catch (\Throwable $e) {
            $this->json(0, $e->getMessage());
        }
    }

    public function user_mobile_bind_confirm()
    {
        $data = $this->secureChatRequestInput();
        try {
            $mobile = trim((string)($data["mobile"] ?? ""));
            $code = trim((string)($data["code"] ?? $data["verify_code"] ?? ""));
            if ($code === "") {
                throw new \Exception("验证码不能为空");
            }
            $validate = new Validate();
            $validate->rule(['mobile|手机号' => 'require|mobile']);
            if (!$validate->check(["mobile" => $mobile])) {
                throw new \Exception((string)$validate->getError());
            }
            $cacheKey = $this->appid . "bind_mobile_" . (int)$this->user_info["id"];
            $cache = Cache::get($cacheKey);
            if (!$cache || (string)($cache["code"] ?? "") !== $code || (string)($cache["mobile"] ?? "") !== $mobile || time() - (int)($cache["time"] ?? 0) > 300) {
                throw new \Exception("验证码错误或已过期");
            }
            $exists = Db::name("user")
                ->where("appid", $this->appid)
                ->where("mobile", $mobile)
                ->where("id", "<>", (int)$this->user_info["id"])
                ->find();
            if ($exists) {
                throw new \Exception("该手机号已绑定其他账号");
            }
            Db::name("user")->where("appid", $this->appid)->where("id", (int)$this->user_info["id"])->update(["mobile" => $mobile]);
            Cache::delete($cacheKey);
            $user = Db::name("user")->where("appid", $this->appid)->where("id", (int)$this->user_info["id"])->find();
            $this->chatJson(1, "绑定成功", $this->userSecurityPayload($user ?: []));
        } catch (\Throwable $e) {
            $this->json(0, $e->getMessage());
        }
    }

    public function user_email_bind_code_send()
    {
        $data = $this->secureChatRequestInput(false);
        try {
            $email = trim((string)($data["email"] ?? ""));
            $validate = new Validate();
            $validate->rule(['email|邮箱' => 'require|email']);
            if (!$validate->check(["email" => $email])) {
                throw new \Exception((string)$validate->getError());
            }
            $this->assertImageCaptchaScene("security", (string)($data["captcha"] ?? ""), true);
            $exists = Db::name("user")
                ->where("appid", $this->appid)
                ->where("email", $email)
                ->where("id", "<>", (int)$this->user_info["id"])
                ->find();
            if ($exists) {
                throw new \Exception("该邮箱已绑定其他账号");
            }
            $cacheKey = $this->appid . "bind_email_" . (int)$this->user_info["id"];
            $cache = Cache::get($cacheKey);
            if ($cache && time() - (int)($cache["time"] ?? 0) < 60) {
                throw new \Exception("验证码发送太频繁");
            }
            $code = (string)random_int(100000, 999999);
            $mail = new Email($email);
            $mail->setBody("您正在绑定安全邮箱，验证码为：" . $code . "，5分钟内有效。");
            $mail->setSubject($this->app_info["appname"] . "安全邮箱验证");
            $mail->setFrom($this->app_info["appname"]);
            $result = $mail->send();
            if ($result != 1) {
                throw new \Exception((string)$result);
            }
            Cache::set($cacheKey, ["code" => $code, "email" => $email, "time" => time()], 300);
            $this->chatJson(1, "发送成功", ["expire_in" => 300]);
        } catch (\Throwable $e) {
            $this->json(0, $e->getMessage());
        }
    }

    public function user_email_bind_confirm()
    {
        $data = $this->secureChatRequestInput();
        try {
            $email = trim((string)($data["email"] ?? ""));
            $code = trim((string)($data["code"] ?? $data["verify_code"] ?? ""));
            if ($code === "") {
                throw new \Exception("验证码不能为空");
            }
            $validate = new Validate();
            $validate->rule(['email|邮箱' => 'require|email']);
            if (!$validate->check(["email" => $email])) {
                throw new \Exception((string)$validate->getError());
            }
            $cacheKey = $this->appid . "bind_email_" . (int)$this->user_info["id"];
            $cache = Cache::get($cacheKey);
            if (!$cache || (string)($cache["code"] ?? "") !== $code || (string)($cache["email"] ?? "") !== $email || time() - (int)($cache["time"] ?? 0) > 300) {
                throw new \Exception("验证码错误或已过期");
            }
            $exists = Db::name("user")
                ->where("appid", $this->appid)
                ->where("email", $email)
                ->where("id", "<>", (int)$this->user_info["id"])
                ->find();
            if ($exists) {
                throw new \Exception("该邮箱已绑定其他账号");
            }
            Db::name("user")->where("appid", $this->appid)->where("id", (int)$this->user_info["id"])->update(["email" => $email]);
            Cache::delete($cacheKey);
            $user = Db::name("user")->where("appid", $this->appid)->where("id", (int)$this->user_info["id"])->find();
            $this->chatJson(1, "绑定成功", $this->userSecurityPayload($user ?: []));
        } catch (\Throwable $e) {
            $this->json(0, $e->getMessage());
        }
    }

    public function wallet_security_code_send()
    {
        $data = $this->secureChatRequestInput(false);
        try {
            $user = Db::name("user")->where("appid", $this->appid)->where("id", (int)$this->user_info["id"])->find();
            if (!$user) {
                throw new \Exception("用户不存在");
            }
            $this->assertImageCaptchaScene("security", (string)($data["captcha"] ?? ""), true);
            $methods = $this->walletSecurityMethods($user);
            if (!$methods) {
                throw new \Exception("请先绑定手机号、邮箱或安全验证方式");
            }
            $method = trim((string)($data["verification_method"] ?? ""));
            if ($method === "") {
                $method = (string)$methods[0]["method"];
            }
            $allowed = array_column($methods, "method");
            if (!in_array($method, $allowed, true)) {
                throw new \Exception("安全验证方式不可用");
            }
            $cacheKey = $this->walletSecurityCodeCacheKey((int)$user["id"], $method);
            $cache = Cache::get($cacheKey);
            if ($cache && time() - (int)($cache["time"] ?? 0) < 60) {
                throw new \Exception("验证码发送太频繁");
            }
            $code = (string)random_int(100000, 999999);
            $target = $this->walletSecurityTarget($user, $method);
            if ($target === "") {
                throw new \Exception("安全验证方式不可用");
            }
            if ($method === "mobile") {
                $sms = new AlibabaSample();
                $sms->setCode($code);
                $result = $sms->send($target);
                if ($result != 1) {
                    throw new \Exception((string)$result);
                }
            } else {
                $mail = new Email($target);
                $mail->setBody("您正在设置钱包支付密码，验证码为：" . $code . "，5分钟内有效。");
                $mail->setSubject($this->app_info["appname"] . "钱包安全验证");
                $mail->setFrom($this->app_info["appname"]);
                $result = $mail->send();
                if ($result != 1) {
                    throw new \Exception((string)$result);
                }
            }
            Cache::set($cacheKey, [
                "code" => $code,
                "method" => $method,
                "time" => time(),
            ], 300);
            $selected = [];
            foreach ($methods as $item) {
                if ((string)$item["method"] === $method) {
                    $selected = $item;
                    break;
                }
            }
            $this->chatJson(1, "发送成功", [
                "method" => $method,
                "target" => (string)($selected["target"] ?? ""),
                "expire_in" => 300,
                "security_methods" => $methods,
            ]);
        } catch (\Throwable $e) {
            $this->json(0, $e->getMessage());
        }
    }

    public function wallet_pay_password_set()
    {
        $data = $this->secureChatRequestInput();
        $password = trim((string)($data["new_pay_password"] ?? $data["pay_password"] ?? ""));
        try {
            $user = Db::name("user")->where("appid", $this->appid)->where("id", (int)$this->user_info["id"])->find();
            if (!$user) {
                throw new \Exception("用户不存在");
            }
            $this->assertWalletUsable($user);
            $this->assertWalletSecurityVerification($user, $data);
            $this->assertWalletPayPasswordFormat($password);
            $salt = $this->walletPayPasswordSalt();
            $now = date("Y-m-d H:i:s");
            $row = $this->walletPasswordRecord((int)$this->user_info["id"]);
            $save = [
                "salt" => $salt,
                "password_hash" => $this->walletPayPasswordHash($password, $salt),
                "status" => 1,
                "failed_count" => 0,
                "locked_until" => null,
                "last_failed_time" => null,
                "reset_time" => null,
                "reset_admin_id" => 0,
                "unlock_time" => null,
                "unlock_admin_id" => 0,
                "update_time" => $now,
            ];
            if ($row) {
                Db::name("wallet_pay_password")->where("id", (int)$row["id"])->update($save);
            } else {
                Db::name("wallet_pay_password")->insert($save + [
                    "appid" => $this->appid,
                    "user_id" => (int)$this->user_info["id"],
                    "create_time" => $now,
                ]);
            }
            $this->chatJson(1, "设置成功", ["pay_password_set" => 1]);
        } catch (\Throwable $e) {
            $this->json(0, $e->getMessage());
        }
    }

    public function wallet_collect_code_current()
    {
        $data = $this->secureChatRequestInput();
        try {
            $user = Db::name("user")->where("appid", $this->appid)->where("id", (int)$this->user_info["id"])->find();
            $this->assertWalletUsable($user ?: []);
            $amount = $this->normalizeWalletOptionalMoney($data["amount"] ?? "");
            $token = $this->walletQrToken();
            $now = date("Y-m-d H:i:s");
            $order = [
                "appid" => $this->appid,
                "order_no" => $this->walletOrderNo("WC"),
                "order_type" => "collect",
                "payer_id" => 0,
                "payee_id" => (int)$this->user_info["id"],
                "amount" => $amount,
                "remark" => mb_substr(trim((string)($data["remark"] ?? "")), 0, 120),
                "qr_token_hash" => $this->walletQrTokenHash($token),
                "status" => 0,
                "expire_time" => date("Y-m-d H:i:s", time() + 86400),
                "create_time" => $now,
                "update_time" => $now,
                "ip" => get_client_ip(),
            ];
            $order["id"] = Db::name("wallet_order")->insertGetId($order);
            $order["qr_token"] = $token;
            $order["payee_username"] = (string)$this->user_info["username"];
            $order["payee_nickname"] = (string)$this->user_info["nickname"];
            $this->chatJson(1, "success", $this->formatWalletOrder($order, true));
        } catch (\Throwable $e) {
            $this->json(0, $e->getMessage());
        }
    }

    public function wallet_collect_code_create()
    {
        $this->wallet_collect_code_current();
    }

    public function wallet_collect_code_update()
    {
        $this->wallet_collect_code_current();
    }

    public function wallet_pay_code_current()
    {
        $data = $this->secureChatRequestInput();
        try {
            $user = Db::name("user")->where("appid", $this->appid)->where("id", (int)$this->user_info["id"])->find();
            $this->assertWalletUsable($user ?: []);
            $this->assertWalletPayCodeVerified($data);
            $token = $this->walletQrToken();
            $now = date("Y-m-d H:i:s");
            $order = [
                "appid" => $this->appid,
                "order_no" => $this->walletOrderNo("WP"),
                "order_type" => "pay",
                "payer_id" => (int)$this->user_info["id"],
                "payee_id" => 0,
                "amount" => "0.00",
                "remark" => mb_substr(trim((string)($data["remark"] ?? "")), 0, 120),
                "qr_token_hash" => $this->walletQrTokenHash($token),
                "status" => 0,
                "expire_time" => date("Y-m-d H:i:s", time() + 60),
                "create_time" => $now,
                "update_time" => $now,
                "ip" => get_client_ip(),
            ];
            $order["id"] = Db::name("wallet_order")->insertGetId($order);
            $order["qr_token"] = $token;
            $order["payer_username"] = (string)$this->user_info["username"];
            $order["payer_nickname"] = (string)$this->user_info["nickname"];
            $order["payer_avatar"] = (string)($this->user_info["usertx"] ?? "");
            $this->chatJson(1, "success", $this->formatWalletOrder($order, true));
        } catch (\Throwable $e) {
            $this->json(0, $e->getMessage());
        }
    }

    public function wallet_pay_code_create()
    {
        $this->wallet_pay_code_current();
    }

    public function wallet_qr_scan()
    {
        $data = $this->secureChatRequestInput();
        try {
            $order = $this->walletOrderByToken(trim((string)($data["qr_token"] ?? "")));
            if (!$order) {
                throw new \Exception("二维码无效");
            }
            $this->assertWalletQrOrderActive($order);
            if ((string)$order["order_type"] === "collect" && (int)$order["payee_id"] === (int)$this->user_info["id"]) {
                throw new \Exception("不能扫描自己的收款码");
            }
            if ((string)$order["order_type"] === "pay" && (int)$order["payer_id"] === (int)$this->user_info["id"]) {
                throw new \Exception("不能扫描自己的付款码");
            }
            if ((string)$order["order_type"] === "pay") {
                $scanner = Db::name("user")->where("appid", $this->appid)->where("id", (int)$this->user_info["id"])->find();
                $this->assertMerchantEnabled($scanner ?: []);
            }
            $this->chatJson(1, "success", $this->formatWalletOrder($order));
        } catch (\Throwable $e) {
            $this->json(0, $e->getMessage());
        }
    }

    public function wallet_qr_pay_confirm()
    {
        $data = $this->secureChatRequestInput();
        try {
            $requestId = $this->walletRequestId($data["request_id"] ?? "");
            $qrToken = trim((string)($data["qr_token"] ?? ""));
            $order = $qrToken !== ""
                ? $this->walletOrderByToken($qrToken)
                : $this->walletOrderByNoForCurrentUser(trim((string)($data["order_no"] ?? "")));
            if (!$order) {
                throw new \Exception("二维码无效");
            }
            $idempotentPaidRetry = (int)($order["status"] ?? 0) === 1
                && (string)($order["confirm_request_id"] ?? "") === $requestId;
            if (!$idempotentPaidRetry) {
                $this->assertWalletQrOrderActive($order);
            }
            if ((string)$order["order_type"] === "pay") {
                if ((int)$order["payer_id"] === (int)$this->user_info["id"]) {
                    $paid = $this->confirmWalletPayCodeByOwner($order, $this->user_info, trim((string)($data["pay_password"] ?? "")), $requestId);
                    $this->sendWalletServiceNotice((int)($paid["payer_id"] ?? 0), $paid, "scan_pay_success");
                    $this->sendWalletServiceNotice((int)($paid["payee_id"] ?? 0), $paid, "scan_collect_success");
                    $message = "支付成功";
                } else {
                    $payee = Db::name("user")->where("appid", $this->appid)->where("id", (int)$this->user_info["id"])->find();
                    $pending = $this->requestWalletPayCodeCollection($order, $payee ?: $this->user_info, (string)($data["amount"] ?? ""));
                    $this->sendWalletServiceNotice((int)($pending["payer_id"] ?? 0), $pending, "pay_code_confirm_required");
                    $paid = $pending;
                    $message = "已向付款方发起确认";
                }
            } else {
                $paid = $this->payWalletOrder($order, $this->user_info, trim((string)($data["pay_password"] ?? "")), (string)($data["amount"] ?? ""), $requestId);
                $this->sendWalletServiceNotice((int)($paid["payer_id"] ?? 0), $paid, "scan_pay_success");
                $this->sendWalletServiceNotice((int)($paid["payee_id"] ?? 0), $paid, "scan_collect_success");
                $message = "操作成功";
            }
            $this->chatJson(1, $message, [
                "order" => $this->formatWalletOrder($paid),
                "balance" => $this->walletBalancePayload(Db::name("user")->where("id", $this->user_info["id"])->where("appid", $this->appid)->find() ?: $this->user_info),
            ]);
        } catch (\Throwable $e) {
            $this->json(0, $e->getMessage());
        }
    }

    public function wallet_order_status()
    {
        $data = $this->secureChatRequestInput();
        $orderNo = trim((string)($data["order_no"] ?? ""));
        if ($orderNo === "") {
            $this->json(0, "order_no不能为空");
        }
        $order = Db::name("wallet_order")
            ->alias("o")
            ->leftJoin("user pu", "pu.id=o.payer_id and pu.appid=o.appid")
            ->leftJoin("user ru", "ru.id=o.payee_id and ru.appid=o.appid")
            ->where("o.appid", $this->appid)
            ->where("o.order_no", $orderNo)
            ->where(function ($query) {
                $query->where("o.payer_id", (int)$this->user_info["id"])->whereOr("o.payee_id", (int)$this->user_info["id"]);
            })
            ->field("o.*,pu.username as payer_username,pu.nickname as payer_nickname,ru.username as payee_username,ru.nickname as payee_nickname")
            ->find();
        if (!$order) {
            $this->json(0, "订单不存在");
        }
        $this->expireWalletOrderIfNeeded($order);
        $order = Db::name("wallet_order")
            ->alias("o")
            ->leftJoin("user pu", "pu.id=o.payer_id and pu.appid=o.appid")
            ->leftJoin("user ru", "ru.id=o.payee_id and ru.appid=o.appid")
            ->where("o.id", (int)$order["id"])
            ->field("o.*,pu.username as payer_username,pu.nickname as payer_nickname,ru.username as payee_username,ru.nickname as payee_nickname")
            ->find();
        $this->chatJson(1, "success", $this->formatWalletOrder($order ?: []));
    }

    //使用登录卡密
    public function apply_login_km()
    {
        $data = $this->securePublicRequestInput();
        $rule = [
            'device|设备码' => 'require',
            'km|卡密' => 'require',
        ];
        $validate = new Validate();
        $validate->rule($rule);
        $result = $validate->check($data);
        if (!$result) {
            $this->json(0, $validate->getError());
        }
        $km_info = Db::name("km")->where("type", 1)->where("appid", $this->appid)->where("km", $data["km"])->find();
        if (!$km_info) {
            $this->json(0, "卡密不存在");
        }
        if ($km_info["state"] == 1) {
            $this->json(0, "卡密已被使用");
        }
        Db::name("km")->where("id", $km_info["id"])->update([
            "device" => $data["device"],
            "state" => 1,
            "usage_time" => date("Y-m-d H:i:s", time()),
            "expire_time" => date("Y-m-d H:i:s", strtotime("+{$km_info['expire']}day", time())),
        ]);
        $this->securePublicJson(1, "使用成功");
    }

    //卡密自动登录
    public function automatic_login()
    {
        $data = $this->securePublicRequestInput();
        $rule = [
            'device|设备码' => 'require',
        ];
        $validate = new Validate();
        $validate->rule($rule);
        $result = $validate->check($data);
        if (!$result) {
            $this->json(0, $validate->getError());
        }
        $km_info = Db::name("km")->where("device", $data["device"])->where("type", 1)->where("appid", $this->appid)->whereTime('expire_time', '>=', date("Y-m-d H:i:s", time()))->find();
        if ($km_info) {
            $result = [
                "device" => $km_info["device"],
                "usage_time" => $km_info["usage_time"],
                "expire_time" => $km_info["expire_time"],
            ];
            $this->securePublicJson(1, "登录成功", $result);
        }
        $this->json(0, "已过期");
    }

    //商品列表
    public function product_list()
    {
        $result = Db::name("shop_products")
            ->where("appid", $this->appid)
            ->field('received_quantity', true)
            ->page($this->page)
            ->limit($this->limit)
            ->select()->toArray();
        $pagecount = Db::name("shop_products")
            ->where("appid", $this->appid)
            ->count();
        $data_rs["list"] = $result;
        $data_rs["pagecount"] = ceil($pagecount / $this->limit) == 0 ? 1 : ceil($pagecount / $this->limit);
        $data_rs["current_number"] = $this->page;
        $this->json(1, "success", $data_rs);
    }

    //获取商品信息
    public function get_product_information()
    {
        $data = input();
        $rule = [
            'shopid|商品id' => 'require|number',
        ];
        $validate = new Validate();
        $validate->rule($rule);
        $result = $validate->check($data);
        if (!$result) {
            $this->json(0, $validate->getError());
        }
        $result = Db::name("shop_products")->where("id", $data["shopid"])->field("received_quantity", true)->find();
        $this->json(1, "查询成功", $result);
    }

    //购买商品
    public function buy_goods()
    {
        $data = input();
        $rule = [
            'usertoken|用户token' => 'require',
            'shopid|商品id' => 'require|number',
        ];
        $validate = new Validate();
        $validate->rule($rule);
        $result = $validate->check($data);
        if (!$result) {
            $this->json(0, $validate->getError());
        }
        $user_info = $this->user_info;
        Db::startTrans(); // 开启事务
        try {
            $shopinfo = Db::name("shop_products")->where("id", $data["shopid"])->find();
            if (!$shopinfo) {
                throw new Exception("商品不存在");
            }
            if ($shopinfo["commodity_inventory"] == 0) {
                throw new Exception("库存不足");
            }
            //生成唯一的订单号
            $order_number = $this->generateOrderNumber();
            //判断支付方式类型支付方式0金币支付1积分支付2支付宝当面付3易支付4源支付
            //0金币支付
            if ($shopinfo["payment_method"] == 0) {
                $this->assertAssetBalance($user_info, "money", $shopinfo["commodity_price"]);
                $status = 1;
            }
            //1积分支付
            if ($shopinfo["payment_method"] == 1) {
                $this->assertAssetBalance($user_info, "integral", $shopinfo["commodity_price"]);
                $status = 1;
            }
            //2支付宝当面付
            if ($shopinfo["payment_method"] == 2) {
                $order_data = [
                    "out_trade_no" => $order_number,
                    "total_amount" => $shopinfo["commodity_price"],
                    "subject" => $shopinfo["product_name"] . "(" . $shopinfo["commodity_details"] . ")",
                ];
                // echo json_encode($order_data);die();
                $alipay = new AliyunPay();
                $result = $alipay->pay($order_data);
                if (!isset($result["qr_code"])) {
                    $this->json(0, "生成支付二维码失败");
                }
                QrCodeTool::lineQrCode($result["qr_code"], $order_number);
                $status = 0;
                $return_result = [
                    "money" => $shopinfo["commodity_price"],
                    "out_trade_no" => $order_number,
                    "pay_url" => Request::domain() . "/pay/payment_order?order_no=" . $order_number,
                ];
            }
            //3易支付4源支付
            if ($shopinfo["payment_method"] == 3 || $shopinfo["payment_method"] == 4) {
                if (input("payment_type") == "") {
                    $this->json(0, "缺少支付方式参数");
                }
                $order_data = [
                    "type" => input("payment_type"),
                    "out_trade_no" => $order_number,
                    "notify_url" => request()->domain() . "/callback/pay/EverifyNotify_notify",
                    "return_url" => request()->domain() . "/callback/pay/EverifyNotify_return",
                    "name" => $shopinfo["product_name"] . "(" . $shopinfo["commodity_details"] . ")",
                    "money" => $shopinfo["commodity_price"],
                ];
                $alipay = new Epay();
                $pay_url = $alipay->getPayLink($order_data);
                $return_result = [
                    "money" => $shopinfo["commodity_price"],
                    "out_trade_no" => $order_number,
                    "pay_url" => $pay_url
                ];
                $status = 0;
            }
            //减少库存
            $updateResult = Db::name("shop_products")
                ->where("id", $data["shopid"])
                ->where("commodity_inventory", ">", 0)
                ->update([
                    "commodity_inventory" => $shopinfo["commodity_inventory"] - 1,
                ]);

            if (!$updateResult) {
                throw new Exception("库存不足");
            }
            //订单记录
            $addshoporder = [
                "order_number" => $order_number,
                "shop_id" => $data["shopid"],
                "product_type" => $shopinfo["type"],
                "product_name" => $shopinfo["product_name"],
                "total_amount" => $shopinfo["commodity_price"],
                "payment_method" => $shopinfo["payment_method"],
                "status" => $status,
                "create_time" => date("Y-m-d H:i:s", time()),
                "payment_time" => date("Y-m-d H:i:s", time()),
                "appid" => $this->appid,
                "userid" => $user_info["id"],
                "received_quantity" => $shopinfo["received_quantity"],
                "bagge_id" => $shopinfo["bagge_id"],
            ];
            $order_records_insertId = Db::name("order_records")->insertGetId($addshoporder);
            if (!$order_records_insertId) {
                throw new Exception("订单生成失败");
            }
            //增加会员权益  只在 金币支付和积分支付的时候增加
            if ($shopinfo["payment_method"] == 0 || $shopinfo["payment_method"] == 1) {
                add_user_rights($order_records_insertId);
            }

            Db::commit(); // 提交事务
            if ($shopinfo["payment_method"] == 0 || $shopinfo["payment_method"] == 1) {
                $this->json(1, "购买成功");
            } else {
                $this->json(1, "提交成功", $return_result);
            }
        } catch (Exception $e) {
            Db::rollback(); // 回滚事务
            $this->json(0, $e->getMessage());
        }
    }

    //获取订单记录
    public function get_order_record()
    {
        $data = input();
        $rule = [
            'usertoken|用户token' => 'require',
        ];
        $validate = new Validate();
        $validate->rule($rule);
        $result = $validate->check($data);
        if (!$result) {
            $this->json(0, $validate->getError());
        }
        $user_all_info = $this->user_info;
        $result = Db::name('order_records')->alias('o')
            ->join("user u", "u.id = o.userid")
            ->where("o.userid", $user_all_info["id"])
            ->field("o.id,o.order_number,o.transaction_no,o.product_type,o.product_name,o.total_amount,o.payment_method,o.status,o.create_time,o.payment_time,u.username,o.shop_id")
            ->limit($this->limit)
            ->page($this->page)
            ->select()->toArray();
        foreach ($result as $key => $value) {
            $result[$key]["other_content"] = "";
            $result[$key]["commodity_details"] = "";
            $order_data = Db::name('shop_products')->where("id", $value['shop_id'])->find();
            if ($order_data) {
                $result[$key]["other_content"] = $order_data['other_content'];
                $result[$key]["commodity_details"] = $order_data['commodity_details'];
            }
        }
        $pagecount = Db::name('order_records')->alias('o')
            ->join("user u", "u.id = o.userid")
            ->where("o.userid", $user_all_info["id"])
            ->field("o.id,o.order_number,o.transaction_no,o.product_type,o.product_name,o.total_amount,o.payment_method,o.status,o.create_time,o.payment_time,u.username")
            ->count();
        $data_rs["list"] = $result;
        $data_rs["pagecount"] = ceil($pagecount / $this->limit) == 0 ? 1 : ceil($pagecount / $this->limit);
        $data_rs["current_number"] = $this->page;
        $this->json(1, "success", $data_rs);
    }

    //获取板块列表
    public function get_section_list()
    {
        $result = Db::name('forum_section')
            ->where("appid", $this->appid)
            ->where("pid", 0)
            ->where("status", 1)
            ->limit($this->limit)
            ->page($this->page)
            // ->field("id,section_name,section_icon,section_background,section_description,section_announcement,create_time,forum_section")
            ->order("sort", "desc")
            ->select()->toArray();
        foreach ($result as $key => $value) {
            if ($value["section_description"] == "") {
                $result[$key]["section_description"] = "暂无版块描述";
            }
            if ($value["section_announcement"] == "") {
                $result[$key]["section_announcement"] = "暂无版块公告";
            }
            $result[$key]["postnum"] = Db::name("forum_posts")->where("section_id", $value["id"])->count();
            $result[$key]["postnum"] = formatNumber($result[$key]["postnum"]);
            $result[$key]["viewnum"] = Db::name("polymorphic")
                ->alias("p")
                ->join("forum_posts f", "f.id = p.other_id")
                ->where("p.type", 4)
                ->where("f.section_id", $value["id"])
                ->count();
            $result[$key]["viewnum"] = formatNumber($result[$key]["viewnum"]);
            //查询板块评论数量
            $result[$key]["commentnum"] = Db::name("comments")->alias("c")->join("forum_posts p", "p.id=c.postid")->where("p.section_id", $value["id"])->count();
            $result[$key]["commentnum"] = formatNumber($result[$key]["commentnum"]);
            //版主
            $forum_section = array_filter(explode(",", $value["forum_section"]));
            $forum_section_array = [];
            foreach ($forum_section as $k1 => $v1) {
                $user_info = Db::name("user")->where("id", $v1)->find();
                if ($user_info) {
                    $forum_section_array[$k1]["id"] = $user_info["id"];
                    $forum_section_array[$k1]["username"] = $user_info["username"];
                    $forum_section_array[$k1]["usertx"] = $user_info["usertx"];
                    $forum_section_array[$k1]["nickname"] = $user_info["nickname"];
                    $forum_section_array[$k1]["title"] = $user_info["title"] == "" ? [] : explode(",", $user_info["title"]);
                }
            }
            $forum_section_array = array_map('unserialize', array_unique(array_map('serialize', $forum_section_array)));
            $result[$key]["forum_section"] = array_values($forum_section_array);
            if (input('usertoken') != '') {
                $user_all_info = $this->user_info;
                if ($value["conditional_relation"] == 0) {
                    $vip_display = 0;
                    if ($value["vip_display"] == 0) {
                        if (time() <= $user_all_info["viptime"]) {
                            $vip_display = 1;
                        } else {
                            $vip_display = 0;
                        }
                    } else {
                        $vip_display = 1;
                    }
                    $exp_display = 0;
                    if ($value["exp_display"] != 0) {
                        if ($value["exp_display"] <= $user_all_info["exp"]) {
                            $exp_display = 1;
                        } else {
                            $exp_display = 0;
                        }
                    } else {
                        $exp_display = 1;
                    }
                    if ($vip_display == 1 || $exp_display == 1) {
                    } else {
                        unset($result[$key]);
                        continue;
                    }
                } else {
                    $vip_display = 0;
                    if ($value["vip_display"] == 0) {
                        if (time() <= $user_all_info["viptime"]) {
                            $vip_display = 1;
                        } else {
                            $vip_display = 0;
                        }
                    } else {
                        $vip_display = 1;
                    }
                    $exp_display = 0;
                    if ($value["exp_display"] != 0) {
                        if ($value["exp_display"] <= $user_all_info["exp"]) {
                            $exp_display = 1;
                        } else {
                            $exp_display = 0;
                        }
                    } else {
                        $exp_display = 1;
                    }
                    if ($vip_display == 1 && $exp_display == 1) {
                    } else {
                        unset($result[$key]);
                        continue;
                    }
                }
            } else {
                if ($value["vip_display"] == 0 || $value["exp_display"] > 0) {
                    unset($result[$key]);
                    continue;
                }
            }
            //查询子版块
            $sub_section = Db::name('forum_section')
                ->where("appid", $this->appid)
                ->where("pid", $value["id"])
                ->where("status", 1)
                ->field("id,section_name,section_icon")
                ->order("sort", "desc")
                ->select()->toArray();
            //查询子版块的数据
            foreach ($sub_section as $k1 => $v1) {
                $sub_section[$k1]["postnum"] = Db::name("forum_posts")->where("sub_section_id", $v1["id"])->count();
                $sub_section[$k1]["postnum"] = formatNumber($sub_section[$k1]["postnum"]);
                //查询子板块评论数量
                $sub_section[$k1]["commentnum"] = Db::name("comments")->alias("c")->join("forum_posts p", "p.id=c.postid")->where("p.sub_section_id", $v1["id"])->count();
                $sub_section[$k1]["commentnum"] = formatNumber($sub_section[$k1]["commentnum"]);
                $sub_section[$k1]["viewnum"] = Db::name("polymorphic")
                    ->alias("p")
                    ->join("forum_posts f", "f.id = p.other_id")
                    ->where("p.type", 4)
                    ->where("f.sub_section_id", $value["id"])
                    ->count();
                $sub_section[$k1]["viewnum"] = formatNumber($sub_section[$k1]["viewnum"]);
            }
            $result[$key]["sub_section"] = $sub_section;
        }
        $data_rs["list"] = array_values($result);
        $data_rs["pagecount"] = 1;
        $data_rs["current_number"] = $this->page;
        $this->json(1, "success", $data_rs);
    }

    //获取板块信息
    public function get_section_information()
    {
        $data = input();
        $rule = [
            'sectionid|板块id' => 'require|number',
        ];
        $validate = new Validate();
        $validate->rule($rule);
        $result = $validate->check($data);
        if (!$result) {
            $this->json(0, $validate->getError());
        }
        $result = Db::name('forum_section')
            ->where("appid", $this->appid)
            ->where("id", $data["sectionid"])
            ->limit($this->limit)
            ->page($this->page)
            ->field("id,section_name,section_icon,section_background,section_description,section_announcement,create_time,forum_section,pid")
            ->order("sort", "desc")
            ->find();
        if (!$result) {
            $this->json(0, "不存在此板块");
        }
        $forum_section = array_filter(explode(",", $result["forum_section"]));
        $forum_section_array = [];
        foreach ($forum_section as $k1 => $v1) {
            $user_info = Db::name("user")->where("id", $v1)->find();
            if ($user_info) {
                $forum_section_array[$k1]["id"] = $user_info["id"];
                $forum_section_array[$k1]["username"] = $user_info["username"];
                $forum_section_array[$k1]["usertx"] = $user_info["usertx"];
                $forum_section_array[$k1]["nickname"] = $user_info["nickname"];
                $forum_section_array[$k1]["title"] = $user_info["title"] == "" ? [] : explode(",", $user_info["title"]);
            }
        }
        $result["forum_section"] = array_values($forum_section_array);
        if ($result["pid"] == 0) {
            $result["postnum"] = Db::name("forum_posts")->where("section_id", $result["id"])->count();
            $result["postnum"] = formatNumber($result["postnum"]);
            $result["commentnum"] = Db::name("comments")->alias("c")->join("forum_posts p", "p.id=c.postid")->where("p.section_id", $result["id"])->count();
            $result["commentnum"] = formatNumber($result["commentnum"]);
            $result["viewnum"] = Db::name("polymorphic")
                ->alias("p")
                ->join("forum_posts f", "f.id = p.other_id")
                ->where("p.type", 4)
                ->where("f.section_id", $result["id"])
                ->count();
            $result["viewnum"] = formatNumber($result["viewnum"]);
        } else {
            $result["postnum"] = Db::name("forum_posts")->where("sub_section_id", $result["id"])->count();
            $result["postnum"] = formatNumber($result["postnum"]);
            $result["commentnum"] = Db::name("comments")->alias("c")->join("forum_posts p", "p.id=c.postid")->where("p.sub_section_id", $result["id"])->count();
            $result["commentnum"] = formatNumber($result["commentnum"]);
            $result["viewnum"] = Db::name("polymorphic")
                ->alias("p")
                ->join("forum_posts f", "f.id = p.other_id")
                ->where("p.type", 4)
                ->where("f.sub_section_id", $result["id"])
                ->count();
            $result["viewnum"] = formatNumber($result["viewnum"]);
        }
        //查询子版块
        $result["sub_section"] = Db::name('forum_section')
            ->where("appid", $this->appid)
            ->where("pid", $result["id"])
            ->where("status", 1)
            ->field("id,section_name,section_icon")
            ->order("sort", "desc")
            ->select()->toArray();
        if ($result["section_description"] == "") {
            $result["section_description"] = "暂无版块描述";
        }
        if ($result["section_announcement"] == "") {
            $result["section_announcement"] = "暂无版块公告";
        }
        unset($result["pid"]);
        $this->json(1, "查询成功", $result);
    }

    //获取帖子列表
    public function get_posts_list()
    {
        $data = input();
        $where = " p.appid={$data['appid']} ";
        //用户id
        if (input("userid") && input("userid") != '') {
            $where .= " and p.userid = {$data['userid']}";
        }
        //板块id
        if (input("sectionid") && input("sectionid") != '') {
            $where .= " and p.section_id = {$data['sectionid']}";
        }
        //子板块id
        if (input("sub_sectionid") && input("sub_sectionid") != '') {
            $where .= " and p.sub_section_id = {$data['sub_sectionid']}";
        }
        //是否置顶
        if (input("sticky") != "") {
            $where .= " and p.sticky = {$data['sticky']}";
        }
        //是否热门
        if (input("popular") != "") {
            $where .= " and p.popular = {$data['popular']}";
        }
        //是否热门
        if (input("featured") != "") {
            $where .= " and p.featured = {$data['featured']}";
        }
        //状态
        if (input("userid") != "") {
            if (input("status") != "") {
                //0待审核 1审核通过 2审核失败 3已锁定
                //判断status是否为 1 3  只能查询审核通过和已锁定的帖子
                if ($data["status"] == 0 || $data["status"] == 1 || $data["status"] == 2 || $data["status"] == 3) {
                    if ($data["status"] == 0) {
                        $data["status"] = 1;
                    } else if ($data["status"] == 1) {
                        $data["status"] = 3;
                    } else if ($data["status"] == 2) {
                        $data["status"] = 0;
                    } else {
                        $data["status"] = 2;
                    }
                    $where .= " and p.status = {$data['status']}";
                } else {
                    $this->json(0, "status参数错误");
                }
            }
        } else {
            if (input("status") != "") {
                //0待审核 1审核通过 2审核失败 3已锁定
                //判断status是否为 1 3  只能查询审核通过和已锁定的帖子
                if ($data["status"] == 0 || $data["status"] == 1) {
                    if ($data["status"] == 0) {
                        $data["status"] = 1;
                    } else {
                        $data["status"] = 3;
                    }
                    $where .= " and p.status = {$data['status']}";
                } else {
                    $this->json(0, "status参数错误");
                }
            } else {
                $where .= " and (p.status = 1 or p.status = 3)";
            }
        }
        //关键词
        if (input("keyword") != "") {
            $where .= " and (p.title like '%{$data['keyword']}%' or p.content like '%{$data['keyword']}%')";
        }
        $section_id = input("sectionid");
        $sub_section_id = input("sub_sectionid");
        //这里增加限制条件 板块是否显示
        if (input("usertoken") == '') {
            if (input("sectionid") != '' || input("sub_sectionid") != '') {
                if ($section_id != '') {
                    //判断该板块是否是隐藏的
                    $show_plate_info = Db::name("forum_section")->where("id", $section_id)->find();
                    if ($show_plate_info["vip_display"] == 0 || $show_plate_info["exp_display"] != 0) {
                        $this->json(0, "该板块不存在");
                    }
                }
                if ($section_id == '' && $sub_section_id != '') {
                    //判断该板块是否是隐藏的
                    $show_plate_info = Db::name("forum_section")->where("id", $sub_section_id)->find();
                    if (!$show_plate_info) {
                        $this->json(0, "该板块不存在");
                    }
                    //查询子板块的父板块
                    $show_plate_info = Db::name("forum_section")->where("id", $show_plate_info["pid"])->find();
                    if ($show_plate_info["vip_display"] == 0 || $show_plate_info["exp_display"] != 0) {
                        $this->json(0, "该板块不存在");
                    }
                }
            } else {
                //查询不隐藏的板块
                $show_plate_list = Db::name("forum_section")->where("pid = 0 and vip_display = 1 and exp_display = 0")->select()->toArray();
                //获取数组中所有的id
                $show_plate_id = array_column($show_plate_list, "id");
                if (count($show_plate_id) > 0) {
                    $show_plate_id = implode(",", $show_plate_id);
                    $where .= " and section_id in({$show_plate_id})";
                }
            }
        } else {
            if ($section_id == '' && $sub_section_id == '') {
                $show_plate_list = Db::name("forum_section")->where("pid = 0")->select()->toArray();
                //筛选出符合条件的板块
                $show_plate_id = [];
                foreach ($show_plate_list as $key => $value) {
                    if ($value["conditional_relation"] == 0) {
                        $vip_display = 0;
                        if ($value["vip_display"] == 0) {
                            if (time() <= $this->user_info["viptime"]) {
                                $vip_display = 1;
                            } else {
                                $vip_display = 0;
                            }
                        } else {
                            $vip_display = 1;
                        }
                        $exp_display = 0;
                        if ($value["exp_display"] != 0) {
                            if ($value["exp_display"] <= $this->user_info["exp"]) {
                                $exp_display = 1;
                            } else {
                                $exp_display = 0;
                            }
                        } else {
                            $exp_display = 1;
                        }
                        if ($vip_display == 1 || $exp_display == 1) {
                            $show_plate_id[] = $value["id"];
                        }
                    } else {
                        $vip_display = 0;
                        if ($value["vip_display"] == 0) {
                            if (time() <= $this->user_info["viptime"]) {
                                $vip_display = 1;
                            } else {
                                $vip_display = 0;
                            }
                        } else {
                            $vip_display = 1;
                        }
                        $exp_display = 0;
                        if ($value["exp_display"] != 0) {
                            if ($value["exp_display"] <= $this->user_info["exp"]) {
                                $exp_display = 1;
                            } else {
                                $exp_display = 0;
                            }
                        } else {
                            $exp_display = 1;
                        }
                        if ($vip_display == 1 && $exp_display == 1) {
                            $show_plate_id[] = $value["id"];
                        }
                    }
                }
                if (count($show_plate_id) > 0) {
                    $show_plate_id = implode(",", $show_plate_id);
                    $where .= " and p.section_id in({$show_plate_id})";
                }
            } else {
                if ($section_id != '') {
                    //判断该板块是否是隐藏的
                    $show_plate_info = Db::name("forum_section")->where("id", $section_id)->find();
                    if ($show_plate_info["conditional_relation"] == 0) {
                        $vip_display = 0;
                        if ($show_plate_info["vip_display"] == 0) {
                            if (time() <= $this->user_info["viptime"]) {
                                $vip_display = 1;
                            } else {
                                $vip_display = 0;
                            }
                        } else {
                            $vip_display = 1;
                        }
                        $exp_display = 0;
                        if ($show_plate_info["exp_display"] != 0) {
                            if ($show_plate_info["exp_display"] <= $this->user_info["exp"]) {
                                $exp_display = 1;
                            } else {
                                $exp_display = 0;
                            }
                        } else {
                            $exp_display = 1;
                        }
                        if ($vip_display == 1 || $exp_display == 1) {
                        } else {
                            $this->json(0, "该板块不存在");
                        }
                    } else {
                        $vip_display = 0;
                        if ($show_plate_info["vip_display"] == 0) {
                            if (time() <= $this->user_info["viptime"]) {
                                $vip_display = 1;
                            } else {
                                $vip_display = 0;
                            }
                        } else {
                            $vip_display = 1;
                        }
                        $exp_display = 0;
                        if ($show_plate_info["exp_display"] != 0) {
                            if ($show_plate_info["exp_display"] <= $this->user_info["exp"]) {
                                $exp_display = 1;
                            } else {
                                $exp_display = 0;
                            }
                        } else {
                            $exp_display = 1;
                        }
                        if ($vip_display == 1 && $exp_display == 1) {
                        } else {
                            $this->json(0, "该板块不存在");
                        }
                    }
                }
                if ($section_id == '' && $sub_section_id != '') {
                    //判断该板块是否是隐藏的
                    $show_plate_info = Db::name("forum_section")->where("id", $sub_section_id)->find();
                    if (!$show_plate_info) {
                        $this->json(0, "该板块不存在");
                    }
                    //查询子板块的父板块
                    $show_plate_info = Db::name("forum_section")->where("id", $show_plate_info["pid"])->find();
                    if ($show_plate_info["conditional_relation"] == 0) {
                        $vip_display = 0;
                        if ($show_plate_info["vip_display"] == 0) {
                            if (time() <= $this->user_info["viptime"]) {
                                $vip_display = 1;
                            } else {
                                $vip_display = 0;
                            }
                        } else {
                            $vip_display = 1;
                        }
                        $exp_display = 0;
                        if ($show_plate_info["exp_display"] != 0) {
                            if ($show_plate_info["exp_display"] <= $this->user_info["exp"]) {
                                $exp_display = 1;
                            } else {
                                $exp_display = 0;
                            }
                        } else {
                            $exp_display = 1;
                        }
                        if ($vip_display == 1 || $exp_display == 1) {
                        } else {
                            $this->json(0, "该板块不存在");
                        }
                    } else {
                        $vip_display = 0;
                        if ($show_plate_info["vip_display"] == 0) {
                            if (time() <= $this->user_info["viptime"]) {
                                $vip_display = 1;
                            } else {
                                $vip_display = 0;
                            }
                        } else {
                            $vip_display = 1;
                        }
                        $exp_display = 0;
                        if ($show_plate_info["exp_display"] != 0) {
                            if ($show_plate_info["exp_display"] <= $this->user_info["exp"]) {
                                $exp_display = 1;
                            } else {
                                $exp_display = 0;
                            }
                        } else {
                            $exp_display = 1;
                        }
                        if ($vip_display == 1 && $exp_display == 1) {
                        } else {
                            $this->json(0, "该板块不存在2");
                        }
                    }
                }
            }
        }
        $sort = input("?sort") ? $data["sort"] : "score";
        $sortOrder = input("?sortOrder") ? $data["sortOrder"] : 'desc';
        //定义sort 只能为那几个
        $sort_array = ['create_time', 'update_time', 'score', 'sticky', 'popular', 'featured'];
        //sort可能为多个 用逗号隔开
        $where_sort = [];
        $sortOrder_array = explode(",", $sortOrder);
        foreach ($sortOrder_array as $k => $v) {
            if ($v != "desc" && $v != "asc") {
                $this->json(0, "sortOrder参数错误");
            }
        }
        if (count(explode(",", $sort)) != count(explode(",", $sortOrder))) {
            $default_sortOrder = explode(",", $sortOrder)[0];
        }
        foreach (explode(",", $sort) as $k => $v) {
            if (!in_array($v, $sort_array)) {
                $this->json(0, "sort参数错误");
            }
            $where_sort["p." . $v] = isset($sortOrder_array[$k]) ? $sortOrder_array[$k] : $default_sortOrder;
        }
        if (input("sectionid") != '' || input("sub_sectionid") != '') {
            $where_sort["p.sticky"] =  "desc";
        }
        $result = Db::name("forum_posts")
            ->alias("p")
            ->join("user u", "u.id=p.userid")
            ->join("forum_section s", "s.id=p.section_id")
            ->join("forum_section sub", "sub.id=p.sub_section_id")
            ->field("p.id as postid,p.*,u.username,u.nickname,u.usertx,u.title as usertitle,u.sex,u.signature,u.viptime,u.exp,s.section_name,s.section_icon,s.forum_section,sub.section_name as sub_section_name")
            ->order($where_sort)
            ->where($where)
            ->page($this->page)
            ->limit($this->limit)
            ->select()->toArray();
        $ip = new IpLocation();
        foreach ($result as $key => $value) {
            //截取帖子内容
            //判断改帖子是否是付费阅读
            if ($value["paid_reading"] == 0) {
                //如果内容字数小于设置的字数或者等于0则全部显示
                if (mb_strlen($value["content"], "utf-8") <= $this->app_info["forum_configuration"]["number_text_intercepted"] || $this->app_info["forum_configuration"]["number_text_intercepted"] == 0) {
                    $result[$key]["content"] = $value["content"];
                } else {
                    $result[$key]["content"] = mb_substr($value["content"], 0, $this->app_info["forum_configuration"]["number_text_intercepted"], "utf-8") . "...";
                }
            } else {
                $result[$key]["content"] = mb_substr($value["content"], 0, $value["preview_word_count"], "utf-8") . "...";
            }
            $result[$key]["ip_address"] = $value["ip"] == "" ? "" : $ip->getDetail($value["ip"])["dataA"];
            $result[$key]["img_url"] = array_filter(explode(",", $value["img_url"]));
            $result[$key]["usertitle"] = array_filter(explode(",", $value["usertitle"]));
            $result[$key]["sex"] = $value["sex"];
            $result[$key]["sexName"] = $value["sex"] == 0 ? "男" : "女";
            //判断当前发帖的用户是否是版主
            $result[$key]["is_section_moderator"] = 0;
            $section_id_array = explode(",", $value["forum_section"]);
            if (in_array($value["userid"], $section_id_array)) {
                $result[$key]["is_section_moderator"] = 1;
            }
            //获取用户的徽章
            $result[$key]["badge"] = Db::name("polymorphic")
                ->alias("p")
                ->join("bagge b", "b.id=p.other_id")
                ->where("p.userid", $value["userid"])
                ->where("p.type", 5)
                ->where("b.is_view", 0)
                ->where("p.wearing", 0)
                ->order(["b.type" => $this->medal_sorting, "b.sort" => "desc"])
                ->field("b.id,b.name,b.icon,b.type,case when p.expiration_time = '9999' then '永久' else p.expiration_time end as expiration_time")
                ->select()->toArray();
            //是否是会员
            if (time() < $value["viptime"]) {
                $result[$key]["vip"] = true;
            } else {
                $result[$key]["vip"] = false;
            }
            //经验等级
            $arr = $this->app_info["grade"];
            $grades = eval("return $arr;");
            $result[$key]["hierarchy"] = "";
            if (is_array($grades)) {
                foreach ($grades as $k1 => $v1) {
                    if ($result[$key]['exp'] >= $k1) {
                        $result[$key]["hierarchy"] = $v1;
                    } else {
                        break;
                    }
                }
            }
            $result[$key]["create_time_ago"] = change_time_type($value["create_time"]);
            $result[$key]["update_time_ago"] = change_time_type($value["update_time"]);
            //帖子访问量
            $result[$key]["view"] = Db::name("polymorphic")->where("other_id", $value["id"])->where("type", 4)->count();
            $result[$key]["view"] = formatNumber($result[$key]["view"]);
            //点赞量
            $result[$key]["thumbs"] = Db::name("polymorphic")->where("other_id", $value["id"])->where("type", 3)->count();
            $result[$key]["thumbs"] = formatNumber($result[$key]["thumbs"]);
            //评论量
            $result[$key]["comment"] = Db::name("comments")->where("postid", $value["id"])->count();
            $result[$key]["comment"] = formatNumber($result[$key]["comment"]);
            //去除不需要的字段
            unset($result[$key]["id"]);
            unset($result[$key]["ip"]);
            unset($result[$key]["viptime"]);
            unset($result[$key]["file"]);
            unset($result[$key]["reading_price"]);
            unset($result[$key]["preview_word_count"]);
            unset($result[$key]["file_download_price"]);
            unset($result[$key]["forum_section"]);
            //获取帖子的打赏金额
            $result[$key]["reward"] = Db::name("post_payment")->where("postid", $value["id"])->where("type", 2)->sum("amount");
            $result[$key]["payers"] = Db::name("post_payment")->where("postid", $value["id"])->where("type = 0 or type = 1")->count();
            $result[$key]["payers"] = formatNumber($result[$key]["payers"]);
        }
        $pagecount = Db::name("forum_posts")
            ->alias("p")
            ->join("user u", "u.id=p.userid")
            ->join("forum_section s", "s.id=p.section_id")
            ->join("forum_section sub", "sub.id=p.sub_section_id")
            ->field("p.id as postid,p.*,u.username,u.nickname,u.usertx,u.title as usertitle,u.sex,u.signature,u.viptime,s.section_name,s.section_icon,sub.section_name as sub_section_name")
            ->where($where)
            ->count();
        $data_rs["list"] = $result;
        $data_rs["pagecount"] = ceil($pagecount / $this->limit) == 0 ? 1 : ceil($pagecount / $this->limit);
        $data_rs["current_number"] = $this->page;
        $this->json(1, "success", $data_rs);
    }

    //获取推荐帖子(只有正常帖子才会推荐)
    public function get_recommended_posts()
    {
        $data = input();
        $where = " p.appid={$data['appid']} and p.status=1";
        if (input("usertoken") != "") {
            $user_all_info = $this->user_info;
            //去访问记录查用户访问过的版块
            $user_section = Db::name("polymorphic")
                ->alias('p')
                ->join("forum_posts s", "s.id=p.other_id")
                ->where("p.userid = {$user_all_info["id"]} and (p.type = 3 or p.type = 4)")
                ->group('s.sub_section_id')
                ->field("s.sub_section_id,count(*) as count")
                ->order("count", "desc")
                ->select()->toArray();
            //查询出全部的版块列表，并按照用户的访问记录进行排序
            $all_sections = Db::name("forum_section")
                ->where("status = 1 and pid != 0")
                ->select()->toArray();
            $sorted_sections = [];
            foreach ($all_sections as $section) {
                $section_id = $section['id'];
                $visit_count = 0;
                // 在用户访问记录中查找对应版块的访问次数
                foreach ($user_section as $visit) {
                    if ($visit['sub_section_id'] == $section_id) {
                        $visit_count = $visit['count'];
                        break;
                    }
                }
                $sorted_sections[$section_id] = $visit_count;
            }
            arsort($sorted_sections); // 按照访问次数排序
            $like_section_order = implode(",", array_keys($sorted_sections));
            if ($like_section_order != "") {
                $where .= " and p.sub_section_id in ({$like_section_order})";
            }
        }
        $section_id = input("sectionid");
        $sub_section_id = input("sub_sectionid");
        //这里增加限制条件 板块是否显示
        if (input("usertoken") == '') {
            //查询不隐藏的板块
            $not_show_plate_list = Db::name("forum_section")->where("pid = 0 and (vip_display = 0 or exp_display != 0)")->select()->toArray();
            //获取数组中所有的id
            $not_show_plate_id = array_column($not_show_plate_list, "id");
            if (count($not_show_plate_id) > 0) {
                $not_show_plate_id = implode(",", $not_show_plate_id);
                $where .= " and p.section_id not in({$not_show_plate_id})";
            }
        } else {
            //查询隐藏的板块
            $show_plate_list = Db::name("forum_section")->where("pid = 0")->select()->toArray();
            //筛选出不符合条件的板块
            $not_show_plate_id = [];
            foreach ($show_plate_list as $key => $value) {
                if ($value["conditional_relation"] == 0) {
                    $vip_display = 0;
                    if ($value["vip_display"] == 0) {
                        if (time() <= $this->user_info["viptime"]) {
                            $vip_display = 1;
                        } else {
                            $vip_display = 0;
                        }
                    } else {
                        $vip_display = 1;
                    }
                    $exp_display = 0;
                    if ($value["exp_display"] != 0) {
                        if ($value["exp_display"] <= $this->user_info["exp"]) {
                            $exp_display = 1;
                        } else {
                            $exp_display = 0;
                        }
                    } else {
                        $exp_display = 1;
                    }
                    if ($vip_display == 1 || $exp_display == 1) {
                    } else {
                        $not_show_plate_id[] = $value["id"];
                    }
                } else {
                    $vip_display = 0;
                    if ($value["vip_display"] == 0) {
                        if (time() <= $this->user_info["viptime"]) {
                            $vip_display = 1;
                        } else {
                            $vip_display = 0;
                        }
                    } else {
                        $vip_display = 1;
                    }
                    $exp_display = 0;
                    if ($value["exp_display"] != 0) {
                        if ($value["exp_display"] <= $this->user_info["exp"]) {
                            $exp_display = 1;
                        } else {
                            $exp_display = 0;
                        }
                    } else {
                        $exp_display = 1;
                    }
                    if ($vip_display == 1 && $exp_display == 1) {
                    } else {
                        $not_show_plate_id[] = $value["id"];
                    }
                }
            }
            if (count($not_show_plate_id) > 0) {
                $not_show_plate_id = implode(",", $not_show_plate_id);
                $where .= " and p.section_id not in({$not_show_plate_id})";
            }
        }
        $result = Db::name("forum_posts")
            ->alias("p")
            ->join("user u", "u.id=p.userid")
            ->join("forum_section s", "s.id=p.section_id")
            ->join("forum_section sub", "sub.id=p.sub_section_id")
            ->field("p.id as postid,p.*,u.username,u.nickname,u.usertx,u.title as usertitle,u.sex,u.signature,u.viptime,u.exp,s.section_name,s.section_icon,s.forum_section,sub.section_name as sub_section_name")
            ->where($where)
            ->order("p.update_time", "desc")
            ->order("p.score", "desc")
            ->page($this->page)
            ->limit($this->limit)
            ->select()->toArray();
        $pagecount = Db::name("forum_posts")
            ->alias("p")
            ->join("user u", "u.id=p.userid")
            ->join("forum_section s", "s.id=p.section_id")
            ->join("forum_section sub", "sub.id=p.sub_section_id")
            ->field("p.id as postid,p.*,u.username,u.nickname,u.usertx,u.title as usertitle,u.sex,u.signature,u.viptime,s.section_name,s.section_icon,sub.section_name as sub_section_name")
            ->where($where)
            ->order("p.update_time", "desc")
            ->order("p.score", "desc")
            ->count();

        $ip = new IpLocation();
        foreach ($result as $key => $value) {
            //截取帖子内容
            //判断改帖子是否是付费阅读
            if ($value["paid_reading"] == 0) {
                //如果内容字数小于设置的字数或者等于0则全部显示
                if (mb_strlen($value["content"], "utf-8") <= $this->app_info["forum_configuration"]["number_text_intercepted"] || $this->app_info["forum_configuration"]["number_text_intercepted"] == 0) {
                    $result[$key]["content"] = $value["content"];
                } else {
                    $result[$key]["content"] = mb_substr($value["content"], 0, $this->app_info["forum_configuration"]["number_text_intercepted"], "utf-8") . "...";
                }
            } else {
                $result[$key]["content"] = mb_substr($value["content"], 0, $value["preview_word_count"], "utf-8") . "...";
            }
            $result[$key]["ip_address"] = $value["ip"] == "" ? "" : $ip->getDetail($value["ip"])["dataA"];
            $result[$key]["img_url"] = array_filter(explode(",", $value["img_url"]));
            $result[$key]["usertitle"] = array_filter(explode(",", $value["usertitle"]));
            $result[$key]["sex"] = $value["sex"];
            $result[$key]["sexName"] = $value["sex"] == 0 ? "男" : "女";
            //判断当前发帖的用户是否是版主
            $result[$key]["is_section_moderator"] = 0;
            $section_id_array = explode(",", $value["forum_section"]);
            if (in_array($value["userid"], $section_id_array)) {
                $result[$key]["is_section_moderator"] = 1;
            }
            //获取用户的徽章
            $result[$key]["badge"] = Db::name("polymorphic")
                ->alias("p")
                ->join("bagge b", "b.id=p.other_id")
                ->where("p.userid", $value["userid"])
                ->where("p.type", 5)
                ->where("b.is_view", 0)
                ->where("p.wearing", 0)
                ->order(["b.type" => $this->medal_sorting, "b.sort" => "desc"])
                ->field("b.id,b.name,b.icon,b.type,case when p.expiration_time = '9999' then '永久' else p.expiration_time end as expiration_time")
                ->select()->toArray();
            //是否是会员
            if (time() < $value["viptime"]) {
                $result[$key]["vip"] = true;
            } else {
                $result[$key]["vip"] = false;
            }
            //经验等级
            $arr = $this->app_info["grade"];
            $grades = eval("return $arr;");
            $result[$key]["hierarchy"] = "";
            if (is_array($grades)) {
                foreach ($grades as $k1 => $v1) {
                    if ($result[$key]['exp'] >= $k1) {
                        $result[$key]["hierarchy"] = $v1;
                    } else {
                        break;
                    }
                }
            }
            $result[$key]["create_time_ago"] = change_time_type($value["create_time"]);
            $result[$key]["update_time_ago"] = change_time_type($value["update_time"]);
            //帖子访问量
            $result[$key]["view"] = Db::name("polymorphic")->where("other_id", $value["id"])->where("type", 4)->count();
            $result[$key]["view"] = formatNumber($result[$key]["view"]);
            //点赞量
            $result[$key]["thumbs"] = Db::name("polymorphic")->where("other_id", $value["id"])->where("type", 3)->count();
            $result[$key]["thumbs"] = formatNumber($result[$key]["thumbs"]);
            //评论量
            $result[$key]["comment"] = Db::name("comments")->where("postid", $value["id"])->count();
            $result[$key]["comment"] = formatNumber($result[$key]["comment"]);
            //去除不需要的字段
            unset($result[$key]["id"]);
            unset($result[$key]["ip"]);
            unset($result[$key]["viptime"]);
            unset($result[$key]["file"]);
            unset($result[$key]["reading_price"]);
            unset($result[$key]["preview_word_count"]);
            unset($result[$key]["file_download_price"]);
            unset($result[$key]["forum_section"]);
            //获取帖子的打赏金额
            $result[$key]["reward"] = Db::name("post_payment")->where("postid", $value["id"])->where("type", 2)->sum("amount");
            $result[$key]["payers"] = Db::name("post_payment")->where("postid", $value["id"])->where("type = 0 or type = 1")->count();
            $result[$key]["payers"] = formatNumber($result[$key]["payers"]);
        }
        $data_rs["list"] = $result;
        $data_rs["pagecount"] = ceil($pagecount / $this->limit) == 0 ? 1 : ceil($pagecount / $this->limit);
        $data_rs["current_number"] = $this->page;
        $this->json(1, "success", $data_rs);
    }

    //获取帖子信息
    public function get_post_information()
    {
        $data = input();
        $rule = [
            'postid|帖子id' => 'require|number',
        ];
        $validate = new Validate();
        $validate->rule($rule);
        $result = $validate->check($data);
        if (!$result) {
            $this->json(0, $validate->getError());
        }
        $posts_info = Db::name("forum_posts")
            ->alias("p")
            ->join("user u", "u.id=p.userid")
            ->join("forum_section s", "s.id=p.section_id")
            ->join("forum_section sub", "sub.id=p.sub_section_id")
            ->field("p.*,u.username,u.nickname,u.usertx,u.title as usertitle,u.sex,u.signature,u.viptime,u.exp,s.section_name,s.section_icon,s.forum_section,sub.section_name as sub_section_name")
            ->where("p.id", $data["postid"])
            ->where("p.appid", $this->appid)
            ->find();
        if (!$posts_info) {
            $this->json(0, "不存在此文章");
        }
        //定义用户是否付费了 0未付费 1已付费
        $posts_info["is_read_pay"] = 1;
        $posts_info["is_file_pay"] = 1;
        //判读当前用户是否是版主
        $posts_info["is_section_moderator"] = 0;
        if (input("usertoken") == "") {
            $posts_info["is_section_moderator"] = 0;
        } else {
            $user_all_info = $this->user_info;
            $forum_section = explode(",", $posts_info["forum_section"]);
            if (in_array($user_all_info["id"], $forum_section)) {
                $posts_info["is_section_moderator"] = 1;
            }
        }
        //判断该帖子是否是作者本人
        if (input("usertoken") == "") {
            //判断改帖子是否是付费阅读
            if ($posts_info["paid_reading"] != 0) {
                $posts_info["is_read_pay"] = 0;
                //判断该帖子是否是评论后可见
                if ($posts_info["paid_reading"] == 1) {
                    $posts_info["content"] = mb_substr($posts_info["content"], 0, $posts_info["preview_word_count"], "utf-8") . "...(更多内容请评论后查看)";
                } else {
                    $posts_info["content"] = mb_substr($posts_info["content"], 0, $posts_info["preview_word_count"], "utf-8") . "...(更多内容请付费查看)";
                }
            }
            //判断该帖子的附件下载方式
            if ($posts_info["file_download_method"] != 0) {
                $posts_info["is_file_pay"] = 0;
                //判断该帖子是否是评论后可见
                if ($posts_info["file_download_method"] == 1) {
                    $posts_info["file"] = get_file_download_method_Status()[$posts_info["file_download_method"]];
                } else {
                    $posts_info["file"] = get_file_download_method_Status()[$posts_info["file_download_method"]];
                }
            }
        } else {
            //查询用户是不是板块版主
            if ($posts_info["userid"] != $this->user_info["id"]) {
                if ($posts_info["is_section_moderator"] == 1 && $posts_info["status"] == 0) {
                } else {
                    //判断是否开启了 会员免付费模式
                    if ($this->app_info["forum_configuration"]["members_not_need_pay"] == 1 || $this->user_info["viptime"] < time()) {
                        //判断改帖子是否是付费阅读
                        if ($posts_info["paid_reading"] != 0) {
                            //判断该帖子是否是评论后可见
                            if ($posts_info["paid_reading"] == 1) {
                                //判断用户是否评论过该帖子
                                $is_comment = Db::name("comments")
                                    ->where("postid", $data["postid"])
                                    ->where("userid", $this->user_info["id"])
                                    ->find();
                                if (!$is_comment) {
                                    $posts_info["is_read_pay"] = 0;
                                    $posts_info["content"] = mb_substr($posts_info["content"], 0, $posts_info["preview_word_count"], "utf-8") . "...(更多内容请评论后查看)";
                                }
                            } else {
                                //判断用户是否购买过该帖子
                                $is_buy = Db::name("post_payment")
                                    ->where("postid", $data["postid"])
                                    ->where("userid", $this->user_info["id"])
                                    ->where("type", 0)
                                    ->find();
                                if (!$is_buy) {
                                    $posts_info["is_read_pay"] = 0;
                                    $posts_info["content"] = mb_substr($posts_info["content"], 0, $posts_info["preview_word_count"], "utf-8") . "...(更多内容请付费查看)";
                                }
                            }
                        }
                        //判断该帖子的附件下载方式
                        if ($posts_info["file_download_method"] != 0) {
                            //判断该帖子是否是评论后可见
                            if ($posts_info["file_download_method"] == 1) {
                                //判断用户是否评论过该帖子
                                $is_comment = Db::name("comments")
                                    ->where("postid", $data["postid"])
                                    ->where("userid", $this->user_info["id"])
                                    ->find();
                                if (!$is_comment) {
                                    $posts_info["is_file_pay"] = 0;
                                    $posts_info["file"] = get_file_download_method_Status()[$posts_info["file_download_method"]];
                                }
                            } else {
                                //判断用户是否购买过
                                $is_buy = Db::name("post_payment")
                                    ->where("postid", $data["postid"])
                                    ->where("userid", $this->user_info["id"])
                                    ->where("type", 1)
                                    ->find();
                                if (!$is_buy) {
                                    $posts_info["is_file_pay"] = 0;
                                    $posts_info["file"] = get_file_download_method_Status()[$posts_info["file_download_method"]];
                                }
                            }
                        }
                    }
                }
            }
        }

        $ip = new IpLocation();
        $posts_info["ip_address"] = $posts_info["ip"] == "" ? "" : $ip->getDetail($posts_info["ip"])["dataA"];
        $posts_info["img_url"] = array_filter(explode(",", $posts_info["img_url"]));
        $posts_info["usertitle"] = array_filter(explode(",", $posts_info["usertitle"]));
        $posts_info["sex"] = $posts_info["sex"];
        $posts_info["sexName"] = $posts_info["sex"] == 0 ? "男" : "女";
        //获取用户的徽章
        $posts_info["badge"] = Db::name("polymorphic")
            ->alias("p")
            ->join("bagge b", "b.id=p.other_id")
            ->where("p.userid", $posts_info["userid"])
            ->where("p.type", 5)
            ->where("b.is_view", 0)
            ->where("p.wearing", 0)
            ->order(["b.type" => $this->medal_sorting, "b.sort" => "desc"])
            ->field("b.id,b.name,b.icon,b.type,case when p.expiration_time = '9999' then '永久' else p.expiration_time end as expiration_time")
            ->select()->toArray();
        //是否是会员
        if (time() < $posts_info["viptime"]) {
            $posts_info["vip"] = true;
        } else {
            $posts_info["vip"] = false;
        }
        unset($posts_info["viptime"]);
        //帖子访问量
        $posts_info["view"] = Db::name("polymorphic")->where("other_id", $posts_info["id"])->where("type", 4)->count();
        //点赞量
        $posts_info["thumbs"] = Db::name("polymorphic")->where("other_id", $posts_info["id"])->where("type", 3)->count();
        //评论量
        $posts_info["comment"] = Db::name("comments")->where("postid", $data["postid"])->count();
        //计算帖子的评分
        //综合评分 = (访问量 × 0.4) + (点赞量 × 0.3) + (评论量 × 0.3)
        //访问量
        $post_view_count = $posts_info["view"];
        //点赞量
        $post_thumbs_count = $posts_info["thumbs"];
        //评论量
        $post_comment_count = $posts_info["comment"];
        //综合评分 只要两位小数
        $post_score = round(($post_view_count * 0.4) + ($post_thumbs_count * 0.3) + ($post_comment_count * 0.3), 2);
        $posts_info["view"] = formatNumber($posts_info["view"]);
        $posts_info["thumbs"] = formatNumber($posts_info["thumbs"]);
        $posts_info["comment"] = formatNumber($posts_info["comment"]);
        Db::name("forum_posts")->where("id", $data["postid"])->update(["score" => $post_score]);
        $posts_info["score"] = $post_score;
        //获取用户是否点赞了帖子 0未点赞 1点赞
        $posts_info["is_thumbs"] = 0;
        if (input("usertoken") != "") {
            $user_all_info = $this->user_info;
            $is_thumbs = Db::name("polymorphic")->where("other_id", $data["postid"])->where("userid", $user_all_info["id"])->where("type", 3)->find();
            if ($is_thumbs) {
                $posts_info["is_thumbs"] = 1;
            }
            $adddata["userid"] = $user_all_info["id"];
            $adddata = [
                "appid" => $data["appid"],
                "create_time" => date("Y-m-d H:i:s", time()),
                "userid" => $user_all_info["id"],
                "other_id" => $data["postid"],
                "type" => 4
            ];
        } else {
            $adddata = [
                "appid" => $data["appid"],
                "create_time" => date("Y-m-d H:i:s", time()),
                "userid" => 0,
                "other_id" => $data["postid"],
                "type" => 4
            ];
        }
        //新增访问量
        if ($posts_info["status"] == 1 || $posts_info["status"] == 3) {
            Db::name("polymorphic")->insert($adddata);
        }
        //判断用户是否关注了该作者  //0互相关注 1他关注了我 2我关注了他 3互相都没有关注
        $posts_info["is_follow"] = 3;
        if (input("usertoken") != "") {
            $user_all_info = $this->user_info;
            $is_follow = Db::name("polymorphic")->where("type", 2)->where("userid", $user_all_info["id"])->where("other_id", $posts_info["userid"])->find();
            $is_ffollow = Db::name("polymorphic")->where("type", 2)->where("userid", $posts_info["userid"])->where("other_id", $user_all_info["id"])->find();
            if ($is_follow) {
                if ($is_ffollow) {
                    $posts_info["is_follow"] = 0;
                } else {
                    $posts_info["is_follow"] = 2;
                }
            } else {
                if ($is_ffollow) {
                    $posts_info["is_follow"] = 1;
                }
            }
        }
        $posts_info["is_collection"] = 0;
        if (input("usertoken") != "") {
            $collection_info = Db::name("polymorphic")->where("other_id", $data["postid"])->where("userid", $user_all_info["id"])->where("type", 6)->find();
            if ($collection_info) {
                $posts_info["is_collection"] = 1;
            }
        }
        $posts_info["create_time_ago"] = change_time_type($posts_info["create_time"]);
        $posts_info["update_time_ago"] = change_time_type($posts_info["update_time"]);
        //经验等级
        $arr = $this->app_info["grade"];
        $grades = eval("return $arr;");
        $posts_info["hierarchy"] = "";
        if (is_array($grades)) {
            foreach ($grades as $k1 => $v1) {
                if ($posts_info['exp'] >= $k1) {
                    $posts_info["hierarchy"] = $v1;
                } else {
                    break;
                }
            }
        }
        //获取帖子的打赏金额
        $posts_info["reward"] = Db::name("post_payment")->where("postid", $posts_info["id"])->where("type", 2)->sum("amount");
        //获取帖子打赏的人
        $posts_info["reward_user_list"] = Db::name("post_payment")
            ->alias("a")
            ->join("user b", "a.userid = b.id")
            ->field("a.amount,a.payment,b.id,b.username,b.nickname,b.usertx")
            ->where("postid", $posts_info["id"])
            ->where("type", 2)
            ->select()->toArray();
        //获取帖子的打赏人数
        $posts_info["payers"] = Db::name("post_payment")->where("postid", $posts_info["id"])->where("type = 0 or type = 1")->count();
        $posts_info["payers"] = formatNumber($posts_info["payers"]);
        //去除不需要的字段
        unset($posts_info["forum_section"]);
        unset($posts_info["ip"]);
        unset($posts_info["preview_word_count"]);
        $posts_info["posturl"] = Request::domain() . "/post/" . $data["postid"] . ".html";
        $this->json(1, "success", $posts_info);
    }

    //发布帖子
    public function post()
    {
        if ($this->app_info["forum_configuration"]["post_switch"] == 1) {
            $this->json(0, "此APP已关闭发贴配置");
        }
        $data = input();
        $rule = [
            'title|标题' => 'require',
            'content|内容' => 'require',
            'subsectionid|子板块id' => 'require|number',
            'usertoken|用户token' => 'require',
            'paid_reading|是否开启付费阅读' => 'require|number',
            'file_download_method|是否开启付费下载附件' => 'require|number',
        ];
        $validate = new Validate();
        $validate->rule($rule);
        $result = $validate->check($data);
        if (!$result) {
            $this->json(0, $validate->getError());
        }
        //看一下上次发帖的时间是什么时候
        if ($this->app_info["forum_configuration"]["posting_interval_time"] != 0) {
            $last_post_time = Db::name("forum_posts")->where("userid", $this->user_info["id"])->order("create_time", "desc")->value("create_time");
            if ($last_post_time) {
                if (time() - strtotime($last_post_time) < $this->app_info["forum_configuration"]["posting_interval_time"]) {
                    $this->json(0, "请求太频繁，请稍后再试！");
                }
            }
        }
        // 限制发帖数量
        if ($this->app_info["forum_configuration"]["max_number_post_day"] != 0) {
            $now_time = date("Y-m-d", time());
            $user_post_number = Db::name("forum_posts")->where("userid", $this->user_info["id"])->where("create_time", "like", "%{$now_time}%")->count();
            if ($user_post_number != 0) {
                if ($user_post_number >= $this->app_info["forum_configuration"]["max_number_post_day"]) {
                    $this->json(0, "今天发帖数量已达上限");
                }
            }
        }
        if (!in_array($data["paid_reading"], [0, 1, 2, 3])) {
            $this->json(0, "付费阅读参数不合法");
        }
        if (!in_array($data["file_download_method"], [0, 1, 2, 3])) {
            $this->json(0, "付费下载附件参数不合法");
        }
        //验证付费阅读是否合法
        if ($data["paid_reading"] == 1) {
            $rule = [
                'preview_word_count|未付费预览字数' => 'require|number',
            ];
            $validate = new Validate();
            $validate->rule($rule);
            $result = $validate->check($data);
            if (!$result) {
                $this->json(0, $validate->getError());
            }
            if ($data["preview_word_count"] == 0) {
                $this->json(0, "未付费预览字数不能为0");
            }
            if (mb_strlen($data["content"], "utf-8") <= $data["preview_word_count"]) {
                $this->json(0, "未付费预览字数不能大于帖子内容字数");
            }
        }
        //判断付费阅读金额是否合法
        if ($data["paid_reading"] == 2 || $data["paid_reading"] == 3) {
            $rule = [
                'reading_price|付费价格' => 'require|number',
                'preview_word_count|未付费预览字数' => 'require|number',
            ];
            $validate = new Validate();
            $validate->rule($rule);
            $result = $validate->check($data);
            if (!$result) {
                $this->json(0, $validate->getError());
            }
            if ($data["paid_reading"] == 2 || $data["paid_reading"] == 3) {
                if ($data["reading_price"] == 0) {
                    $this->json(0, "付费阅读金额不能为0");
                }
            }
            if ($data["preview_word_count"] == 0) {
                $this->json(0, "未付费预览字数不能为0");
            }
            if (mb_strlen($data["content"], "utf-8") <= $data["preview_word_count"]) {
                $this->json(0, "未付费预览字数不能大于帖子内容字数");
            }
        }
        //判断付费下载附件金额是否合法
        if ($data["file_download_method"] == 2 || $data["file_download_method"] == 3) {
            $rule = [
                'file_download_price|付费价格' => 'require|number',
            ];
            $validate = new Validate();
            $validate->rule($rule);
            $result = $validate->check($data);
            if (!$result) {
                $this->json(0, $validate->getError());
            }
            if ($data["file_download_method"] == 2 || $data["file_download_method"] == 3) {
                if ($data["file_download_price"] == 0) {
                    $this->json(0, "付费下载附件金额不能为0");
                }
            }
        }
        $user_all_info = $this->user_info;
        $sub_section_info = Db::name('forum_section')->where("id", $data["subsectionid"])->where("pid", "<>", 0)->where("appid", $data["appid"])->find();
        if (!$sub_section_info) {
            $this->json(0, "板块不存在");
        }
        $plateinfo = Db::name("forum_section")->where("id", $sub_section_info["pid"])->find();
        if (!$plateinfo) {
            $this->json(0, "板块不存在");
        }
        //判断是否有权限发帖
        //发帖权限 0管理员 1全部用户 2不允许任何人发布
        $plateadmin_array = array_filter(explode(",", $plateinfo["forum_section"]));
        if ($plateinfo["section_permissions"] == 0) {
            if (!in_array($user_all_info["id"], $plateadmin_array)) {
                $this->json(0, "本版块只限管理员发布");
            }
        }
        if ($plateinfo["section_permissions"] == 2) {
            $this->json(0, "不允许任何人发布");
        }
        //查询用户今天的发帖数量
        $today_start_time = strtotime(date("Y-m-d 00:00:00", time()));
        $today_end_time = strtotime(date("Y-m-d 23:59:59", time()));
        $today_post_count = Db::name("forum_posts")->where("userid", $user_all_info["id"])->where("create_time", "between", [$today_start_time, $today_end_time])->count();
        if ($this->app_info["forum_configuration"]["max_number_post_day"] < $today_post_count && $this->app_info["forum_configuration"]["max_number_post_day"] != 0) {
            $this->json(0, "今天发帖数量已达上限");
        }
        $img_url = [];
        $video_url = "";
        $file = "";
        $video_img = "";

        if (!empty($_FILES) && !empty($_FILES["img"])) {
            try {
                $upload = new Upload($user_all_info["id"]);
                $result = $upload->upload('img');
            } catch (\Exception $e) {
                $this->json(0, $e->getMessage());
            }
            foreach ($result as $key => $value) {
                $img_url[] = $value["filePath"];
            }
            $img_url = array_filter($img_url);
            $img_url = implode(",", $img_url);
        }
        if (substr(input('video'), 0, 4) == "http") {
            $video_url = $data["video"];
        } else {
            if (!empty($_FILES) && !empty($_FILES["video"])) {
                try {
                    $upload = new Upload($user_all_info["id"]);
                    $result = $upload->upload('video');
                } catch (\Exception $e) {
                    $this->json(0, $e->getMessage());
                }
                $video_url = $result["filePath"];
            }
        }
        //file 字段可以上传文件 也可以直接填写链接 这里判断一下 如果是链接 判断file是否是http开头的
        //截取前四位 如果是http开头的 就是链接
        if (substr(input('file'), 0, 4) == "http") {
            $file = $data["file"];
        } else {
            if (!empty($_FILES) && !empty($_FILES["file"])) {
                try {
                    $upload = new Upload($user_all_info["id"]);
                    $result = $upload->upload('file');
                } catch (\Exception $e) {
                    $this->json(0, $e->getMessage());
                }
                $file = $result["filePath"];
            } else {
                if ($data["file_download_method"] > 0) {
                    $this->json(0, "选择付费下载附件，请上传附件");
                }
            }
        }
        if (substr(input('video_img'), 0, 4) == "http") {
            $video_img = $data["video_img"];
        } else {
            if (!empty($_FILES) && !empty($_FILES["video_img"])) {
                try {
                    $upload = new Upload($user_all_info["id"]);
                    $result = $upload->upload('video_img');
                } catch (\Exception $e) {
                    $this->json(0, $e->getMessage());
                }
                $video_img = $result["filePath"];
            }
        }
        if ($data["paid_reading"] > 0) {
            if ($data["paid_reading"] == 2 || $data["paid_reading"] == 3) {
                $data["reading_price"] = $data["reading_price"];
                $data["preview_word_count"] = $data["preview_word_count"];
            } else {
                $data["reading_price"] = 0;
                $data["preview_word_count"] = 0;
            }
        } else {
            $data["reading_price"] = 0;
            $data["preview_word_count"] = 0;
        }
        if ($data["file_download_method"] > 0) {
            if ($data["file_download_method"] == 2 || $data["file_download_method"] == 3) {
                $data["file_download_price"] = $data["file_download_price"];
            } else {
                $data["file_download_price"] = 0;
            }
        } else {
            $data["file_download_price"] = 0;
        }
        $network_picture = array_filter(explode(",", input('network_picture')));
        //合并图片 本地图片和网络图片
        $img_url_expolde = array_merge((array)$img_url, (array)$network_picture);
        $post_info_array = [
            "title" => $data["title"],
            "content" => $data["content"],
            "create_time" => date("Y-m-d H:i:s", time()),
            "userid" => $user_all_info["id"],
            "update_time" => date("Y-m-d H:i:s", time()),
            "status" => $plateinfo["post_review"],
            "appid" => $this->appid,
            "section_id" => $plateinfo["id"],
            "ip" => get_client_ip(),
            "video_url" => $video_url,
            "img_url" => implode(",", $img_url_expolde),
            "file" => $file,
            "paid_reading" => $data["paid_reading"],
            "reading_price" => isset($data["reading_price"]) ? $data["reading_price"] : 0,
            "file_download_method" => $data["file_download_method"],
            "file_download_price" => isset($data["file_download_price"]) ? $data["file_download_price"] : 0,
            "preview_word_count" => isset($data["preview_word_count"]) ? $data["preview_word_count"] : 0,
            "sub_section_id" => $data["subsectionid"],
            "video_img" => $video_img,
        ];
        $add_posts_info_id = Db::name("forum_posts")->insert($post_info_array);
        if (!$add_posts_info_id) {
            $this->json(0, "发布失败");
        }
        if ($plateinfo["post_review"] == 1) {
            if ($this->app_info["forum_configuration"]["max_number_post_reward"] <= $today_post_count || $this->app_info["forum_configuration"]["max_number_post_reward"] == 0) {
                forum_add_equity($add_posts_info_id, $user_all_info["id"], 0);
            }
            $this->json(1, "发布成功");
        }
        $this->json(1, "你的帖子已提交审核，请耐心等待！");
    }

    //删除帖子
    public function delete_post()
    {
        $data = input();
        $rule = [
            'postid|帖子id' => 'require|number',
            'usertoken|用户token' => 'require',
        ];
        $validate = new Validate();
        $validate->rule($rule);
        $result = $validate->check($data);
        if (!$result) {
            $this->json(0, $validate->getError());
        }
        $user_all_info = $this->user_info;
        $postinfo = Db::name("forum_posts")->where("id", $data["postid"])->where("appid", $data["appid"])->find();
        if (!$postinfo) {
            $this->json(0, "帖子不存在");
        }
        $plateinfo = Db::name('forum_section')->where("id", $postinfo["section_id"])->where("appid", $data["appid"])->find();
        if (!$plateinfo) {
            $this->json(0, "系统错误！");
        }
        if ($this->app_info["forum_configuration"]["moderator_delete_post"] == 0 && $postinfo["userid"] != $user_all_info["id"]) {
            $plateadmin_array = array_filter(explode(",", $plateinfo["forum_section"]));
            if (in_array($user_all_info["id"], $plateadmin_array)) {
                Db::name("forum_posts")->where("id", $data["postid"])->delete();
                //删除帖子后，删除帖子的点赞记录
                Db::name("polymorphic")->where("type", 3)->where("other_id", $data["postid"])->delete();
                //删除帖子后，删除帖子的评论
                Db::name("comments")->where("postid", $data["postid"])->delete();
                //删除帖子后，删除帖子的访问
                Db::name("polymorphic")->where("type", 4)->where("other_id", $data["postid"])->delete();
                //删除帖子后，删除帖子的图片
                if ($postinfo["img_url"]) {
                    $img_url_array = array_filter(explode(",", $postinfo["img_url"]));
                    foreach ($img_url_array as $key => $value) {
                        //因为存储的是带域名的路径  所以需要截取域名之后的去数据库查询
                        $value = substr($value, strpos($value, config("upload.file_path")));
                        $file = Db::name("file")->where("filePath", $value)->find();
                        if ($file) {
                            Db::name("file")->where("filePath", $value)->delete();
                            //删除本地文件 
                            @unlink($value);
                        }
                    }
                }
                //删除帖子后，删除帖子的视频
                if ($postinfo["video_url"]) {
                    $video_url = substr($postinfo["video_url"], strpos($postinfo["video_url"], config("upload.file_path")));
                    $file = Db::name("file")->where("filePath", $video_url)->find();
                    if ($file) {
                        Db::name("file")->where("id", $file['id'])->delete();
                        //删除本地文件 
                        @unlink($video_url);
                    }
                }
                //删除帖子后，删除帖子的视频封面
                if ($postinfo["video_img"]) {
                    $video_img_url = substr($postinfo["video_img"], strpos($postinfo["video_img"], config("upload.file_path")));
                    $file = Db::name("file")->where("filePath", $video_img_url)->find();
                    if ($file) {
                        Db::name("file")->where("id", $file['id'])->delete();
                        //删除本地文件 
                        @unlink($video_img_url);
                    }
                }
                //删除帖子后，删除帖子的附件
                if ($postinfo["file"]) {
                    $file_url = substr($postinfo["file"], strpos($postinfo["file"], config("upload.file_path")));
                    $file = Db::name("file")->where("filePath", $file_url)->find();
                    if ($file) {
                        Db::name("file")->where("id", $file['id'])->delete();
                        //删除本地文件 
                        @unlink($file_url);
                    }
                }
                $addmessagedata = [
                    "title" => "删除通知",
                    "content" => "您的帖子《" . $postinfo["title"] . "》被" . $user_all_info["nickname"] . "删除了",
                    "send_to" => 0,
                    "appid" => $postinfo["appid"],
                    "time" => date("Y-m-d H:i:s", time()),
                    "type" => 9,
                    "user_id" => $postinfo["userid"],
                    "postid" => 0,
                ];
                Db::name("message_notification")->insert($addmessagedata);
                $this->json(1, "删除成功！");
            }
        }
        if ($postinfo["userid"] != $user_all_info["id"]) {
            $this->json(0, "系统错误！");
        }
        try {
            //删除帖子 先看看用户的金币、积分、经验是否足够
            if ($this->app_info["forum_configuration"]["del_post_money"] > 0) {
                $this->assertAssetBalance($user_all_info, "money", $this->app_info["forum_configuration"]["del_post_money"]);
            }
            if ($this->app_info["forum_configuration"]["del_post_integral"] > 0) {
                $this->assertAssetBalance($user_all_info, "integral", $this->app_info["forum_configuration"]["del_post_integral"]);
            }
            if ($this->app_info["forum_configuration"]["del_post_exp"] > $user_all_info["exp"]) {
                $this->json(0, "经验不足，无法删除帖子！");
            }
            if ($this->app_info["forum_configuration"]["del_post_money"] > 0) {
                add_user_bill($user_all_info, 14, "-" . $this->app_info["forum_configuration"]["del_post_money"], "删除帖子", 0, 0);
            }
            if ($this->app_info["forum_configuration"]["del_post_integral"] > 0) {
                add_user_bill($user_all_info, 14, "-" . $this->app_info["forum_configuration"]["del_post_integral"], "删除帖子", 1, 0);
            }
            //扣除用户的金币、积分、经验
            $update_user_data["money"] = $user_all_info["money"] - $this->app_info["forum_configuration"]["del_post_money"];
            $update_user_data["integral"] = $user_all_info["integral"] - $this->app_info["forum_configuration"]["del_post_integral"];
            $update_user_data["exp"] = $user_all_info["exp"] - $this->app_info["forum_configuration"]["del_post_exp"];
            Db::name("user")->where("id", $user_all_info["id"])->update($update_user_data);

            Db::name("forum_posts")->where("id", $data["postid"])->delete();
            //删除帖子后，删除帖子的点赞记录
            Db::name("polymorphic")->where("type", 3)->where("other_id", $data["postid"])->delete();
            //删除帖子后，删除帖子的评论
            Db::name("comments")->where("postid", $data["postid"])->delete();
            //删除帖子后，删除帖子的访问
            Db::name("polymorphic")->where("type", 4)->where("other_id", $data["postid"])->delete();
            //删除帖子后，删除帖子的图片
            if ($postinfo["img_url"]) {
                $img_url_array = array_filter(explode(",", $postinfo["img_url"]));
                foreach ($img_url_array as $key => $value) {
                    //因为存储的是带域名的路径  所以需要截取域名之后的去数据库查询
                    $value = substr($value, strpos($value, config("upload.file_path")));
                    $file = Db::name("file")->where("filePath", $value)->find();
                    if ($file) {
                        Db::name("file")->where("filePath", $value)->delete();
                        //删除本地文件 
                        @unlink($value);
                    }
                }
            }
            //删除帖子后，删除帖子的视频
            if ($postinfo["video_url"]) {
                $video_url = substr($postinfo["video_url"], strpos($postinfo["video_url"], config("upload.file_path")));
                $file = Db::name("file")->where("filePath", $video_url)->find();
                if ($file) {
                    Db::name("file")->where("id", $file['id'])->delete();
                    //删除本地文件 
                    @unlink($video_url);
                }
            }
            //删除帖子后，删除帖子的视频封面
            if ($postinfo["video_img"]) {
                $video_img_url = substr($postinfo["video_img"], strpos($postinfo["video_img"], config("upload.file_path")));
                $file = Db::name("file")->where("filePath", $video_img_url)->find();
                if ($file) {
                    Db::name("file")->where("id", $file['id'])->delete();
                    //删除本地文件 
                    @unlink($video_img_url);
                }
            }
            //删除帖子后，删除帖子的附件
            if ($postinfo["file"]) {
                $file_url = substr($postinfo["file"], strpos($postinfo["file"], config("upload.file_path")));
                $file = Db::name("file")->where("filePath", $file_url)->find();
                if ($file) {
                    Db::name("file")->where("id", $file['id'])->delete();
                    //删除本地文件 
                    @unlink($file_url);
                }
            }
            $this->json(1, "删除成功！");
        } catch (\Exception $e) {
            $this->json(0, $e->getMessage());
        }
    }

    //编辑帖子
    public function edit_post()
    {
        $data = input();
        $rule = [
            'postid' => 'require|number',
            'title|标题' => 'require',
            'content|内容' => 'require',
            'subsectionid|子板块id' => 'require|number',
            'usertoken|用户token' => 'require',
            'paid_reading|是否开启付费阅读' => 'require|number',
            'file_download_method|是否开启付费下载附件' => 'require|number',
        ];
        $validate = new Validate();
        $validate->rule($rule);
        $result = $validate->check($data);
        if (!$result) {
            $this->json(0, $validate->getError());
        }
        if (!in_array($data["paid_reading"], [0, 1, 2, 3])) {
            $this->json(0, "付费阅读参数不合法");
        }
        if (!in_array($data["file_download_method"], [0, 1, 2, 3])) {
            $this->json(0, "付费下载附件参数不合法");
        }
        //验证付费阅读是否合法
        if ($data["paid_reading"] == 1) {
            $rule = [
                'preview_word_count|未付费预览字数' => 'require|number',
            ];
            $validate = new Validate();
            $validate->rule($rule);
            $result = $validate->check($data);
            if (!$result) {
                $this->json(0, $validate->getError());
            }
            if ($data["preview_word_count"] == 0) {
                $this->json(0, "未付费预览字数不能为0");
            }
            if (mb_strlen($data["content"], "utf-8") <= $data["preview_word_count"]) {
                $this->json(0, "未付费预览字数不能大于帖子内容字数");
            }
        }
        //判断付费阅读金额是否合法
        if ($data["paid_reading"] == 2 || $data["paid_reading"] == 3) {
            $rule = [
                'reading_price|付费价格' => 'require|number',
                'preview_word_count|未付费预览字数' => 'require|number',
            ];
            $validate = new Validate();
            $validate->rule($rule);
            $result = $validate->check($data);
            if (!$result) {
                $this->json(0, $validate->getError());
            }
            if ($data["paid_reading"] == 2) {
                if ($data["reading_price"] == 0) {
                    $this->json(0, "付费阅读金额不能为0");
                }
            }
            if ($data["paid_reading"] == 3) {
                if ($data["reading_price"] == 0) {
                    $this->json(0, "付费阅读金额不能为0");
                }
            }
            if ($data["preview_word_count"] == 0) {
                $this->json(0, "未付费预览字数不能为0");
            }
            if (mb_strlen($data["content"], "utf-8") <= $data["preview_word_count"]) {
                $this->json(0, "未付费预览字数不能大于帖子内容字数");
            }
        }
        //判断付费下载附件金额是否合法
        if ($data["file_download_method"] == 2 || $data["file_download_method"] == 3) {
            $rule = [
                'file_download_price|付费价格' => 'require|number',
            ];
            $validate = new Validate();
            $validate->rule($rule);
            $result = $validate->check($data);
            if (!$result) {
                $this->json(0, $validate->getError());
            }
            if ($data["file_download_method"] == 2) {
                if ($data["file_download_price"] == 0) {
                    $this->json(0, "付费下载附件金额不能为0");
                }
            }
            if ($data["file_download_method"] == 3) {
                if ($data["file_download_price"] == 0) {
                    $this->json(0, "付费下载附件金额不能为0");
                }
            }
        }
        $user_all_info = $this->user_info;
        //查询帖子是否存在
        $post_info = Db::name("forum_posts")->where("id", $data["postid"])->find();
        if (!$post_info) {
            $this->json(0, "帖子不存在");
        }
        //检测帖子是否是自己的
        if ($post_info["userid"] != $user_all_info["id"]) {
            $this->json(0, "系统错误！");
        }
        $sub_section_info = Db::name('forum_section')->where("id", $data["subsectionid"])->where("pid", "<>", 0)->where("appid", $data["appid"])->find();
        if (!$sub_section_info) {
            $this->json(0, "板块不存在");
        }
        $plateinfo = Db::name("forum_section")->where("id", $sub_section_info["pid"])->find();
        if (!$plateinfo) {
            $this->json(0, "板块不存在");
        }
        //判断是否有权限发帖
        //发帖权限 0管理员 1全部用户 2不允许任何人发布
        $plateadmin_array = array_filter(explode(",", $plateinfo["forum_section"]));
        if ($plateinfo["section_permissions"] == 0) {
            if (!in_array($user_all_info["id"], $plateadmin_array)) {
                $this->json(0, "本版块只限管理员发布");
            }
        }
        if ($plateinfo["section_permissions"] == 2) {
            $this->json(0, "不允许任何人发布");
        }
        $img_url = [];
        $video_url = "";
        $file = "";
        if (!empty($_FILES) && !empty($_FILES["img"])) {
            try {
                $upload = new Upload($user_all_info["id"]);
                $result = $upload->upload('img');
            } catch (\Exception $e) {
                $this->json(0, $e->getMessage());
            }
            foreach ($result as $key => $value) {
                $img_url[] = $value["filePath"];
            }
            $img_url = array_filter($img_url);
            $img_url = implode(",", $img_url);
        }
        if (input('video') != '') {
            if (substr(input('video'), 0, 4) == "http") {
                $video_url = $data["video"];
            } else {
                if (!empty($_FILES) && !empty($_FILES["video"])) {
                    try {
                        $upload = new Upload($user_all_info["id"]);
                        $result = $upload->upload('video');
                    } catch (\Exception $e) {
                        $this->json(0, $e->getMessage());
                    }
                    $video_url = $result["filePath"];
                }
            }
        }
        if (input('file') != '') {
            if (substr(input('file'), 0, 4) == "http") {
                $file = $data["file"];
            } else {
                if (!empty($_FILES) && !empty($_FILES["file"])) {
                    try {
                        $upload = new Upload($user_all_info["id"]);
                        $result = $upload->upload('file');
                    } catch (\Exception $e) {
                        $this->json(0, $e->getMessage());
                    }
                    $file = $result["filePath"];
                } else {
                    if ($data["file_download_method"] > 0) {
                        $this->json(0, "选择付费下载附件，请上传附件");
                    }
                }
            }
        }
        if ($data["paid_reading"] > 0) {
            if ($data["paid_reading"] == 2 || $data["paid_reading"] == 3) {
                $data["reading_price"] = $data["reading_price"];
                $data["preview_word_count"] = $data["preview_word_count"];
            } else {
                $data["reading_price"] = 0;
                $data["preview_word_count"] = 0;
            }
        } else {
            $data["reading_price"] = 0;
            $data["preview_word_count"] = 0;
        }
        if ($data["file_download_method"] > 0) {
            if ($data["file_download_method"] == 2 || $data["file_download_method"] == 3) {
                $data["file_download_price"] = $data["file_download_price"];
            } else {
                $data["file_download_price"] = 0;
            }
        } else {
            $data["file_download_price"] = 0;
        }
        $network_picture = array_filter(explode(",", input('network_picture')));
        //合并图片 本地图片和网络图片
        $img_url_expolde = array_merge((array)$img_url, (array)$network_picture);
        $post_info_array = [
            "title" => $data["title"],
            "content" => $data["content"],
            "update_time" => date("Y-m-d H:i:s", time()),
            "status" => $plateinfo["post_review"],
            "ip" => get_client_ip(),
            "video_url" => $video_url,
            "img_url" => implode(",", $img_url_expolde),
            "file" => $file,
            "paid_reading" => $data["paid_reading"],
            "reading_price" => isset($data["reading_price"]) ? $data["reading_price"] : 0,
            "file_download_method" => $data["file_download_method"],
            "file_download_price" => isset($data["file_download_price"]) ? $data["file_download_price"] : 0,
            "preview_word_count" => isset($data["preview_word_count"]) ? $data["preview_word_count"] : 0,
            "sub_section_id" => $data["subsectionid"],
            "video_img" => input('video_img'),
        ];
        Db::name("forum_posts")->where("id", $data["postid"])->update($post_info_array);
        if ($plateinfo["post_review"] == 1) {
            $this->json(1, "保存成功");
        }
        //添加帖子状态的表更记录
        $add_status_record_data = [
            "object_id" => $data["postid"],
            "original_status" => $post_info["status"],
            "changing_status" => 0,
            "type" => 0,
            "create_time" => date("Y-m-d H:i:s", time()),
        ];
        Db::name("status_record")->insert($add_status_record_data);
        $this->json(1, "你的帖子已提交审核，请耐心等待！");
    }

    //发表评论
    public function post_comment()
    {
        $data = input();
        $rule = [
            'usertoken|用户token' => 'require',
            'postid|帖子id' => 'require|number',
            'content|内容' => 'require',
            'parentid|评论的id' => 'require|number',
        ];
        $validate = new Validate();
        $validate->rule($rule);
        $result = $validate->check($data);
        if (!$result) {
            $this->json(0, $validate->getError());
        }
        //看一下上次评论的时间是什么时候
        if ($this->app_info["forum_configuration"]["comment_interval_time"] != 0) {
            $last_comment_time = Db::name("comments")->where("userid", $this->user_info["id"])->order("id desc")->value("time");
            if ($last_comment_time) {
                $last_comment_time = strtotime($last_comment_time);
                $now_time = time();
                $time_difference = $now_time - $last_comment_time;
                if ($time_difference < $this->app_info["forum_configuration"]["comment_interval_time"]) {
                    $this->json(0, "评论太频繁，请稍后再试！");
                }
            }
        }
        $user_all_info = $this->user_info;
        $postinfo = Db::name("forum_posts")->where("id", $data["postid"])->where("appid", $data["appid"])->find();
        if (!$postinfo) {
            $this->json(0, "帖子不存在");
        }
        $plateinfo = Db::name("forum_section")->where("id", $postinfo["section_id"])->where("appid", $data["appid"])->find();
        if (!$plateinfo) {
            $this->json(0, "系统错误，请联系管理员");
        }
        if ($postinfo["status"] != 1) {
            $this->json(0, "该文章暂未通过审核，无法评论！");
        }
        if ($data["parentid"] != 0) {
            $comment_info = Db::name("comments")->where("id", $data["parentid"])->where("appid", $data["appid"])->find();
            if (!$comment_info) {
                $this->json(0, "回复的评论不存在");
            }
        }
        $image_path = "";
        if (substr(input('img'), 0, 4) == "http") {
            $image_path = $data["img"];
        } else {
            if (!empty($_FILES) && !empty($_FILES["img"])) {
                try {
                    $upload = new Upload($user_all_info["id"]);
                    $result = $upload->upload('img');
                } catch (\Exception $e) {
                    $this->json(0, $e->getMessage());
                }
                foreach ($result as $key => $value) {
                    $img_url[] = $value["filePath"];
                }
                $img_url = array_filter($img_url);
                $image_path = implode(",", $img_url);
            }
        }
        $addcommentdata = [
            "parentid" => $data["parentid"],
            "postid" => $data["postid"],
            "content" => $data["content"],
            "userid" => $user_all_info["id"],
            "appid" => $data["appid"],
            "time" => date("Y-m-d H:i:s", time()),
            "status" => $plateinfo['comment_review'],
            "ip" => get_client_ip(),
            "image_path" => $image_path,
        ];
        $comment_id = Db::name("comments")->insert($addcommentdata);
        if (!$comment_id) {
            $this->json(0, "评论失败");
        }
        if ($plateinfo['comment_review'] == 1) {
            //刷新帖子的更新时间
            Db::name("forum_posts")->where("id", $data["postid"])->update(["update_time" => date("Y-m-d H:i:s", time())]);
            forum_add_equity($postinfo['id'], $user_all_info["id"], 1, $addcommentdata);
            $this->json(1, "评论成功");
        }
        $this->json(1, "你的评论已提交，等待审核");
    }

    //删除评论
    public function delete_comment()
    {
        $data = input();
        $rule = [
            'usertoken' => 'require',
            'commentid|评论id' => 'require|number',
        ];
        $validate = new Validate();
        $validate->rule($rule);
        $result = $validate->check($data);
        if (!$result) {
            $this->json(0, $validate->getError());
        }
        $comment_info = Db::name("comments")->where("status", 1)->where("id", $data["commentid"])->where("appid", $data["appid"])->find();
        if (!$comment_info) {
            $this->json(0, "评论不存在");
        }
        $postinfo = Db::name("forum_posts")->where("id", $comment_info["postid"])->where("appid", $data["appid"])->find();
        if (!$postinfo) {
            $this->json(0, "系统错误");
        }
        $plateinfo = Db::name('forum_section')->where("id", $postinfo["section_id"])->where("appid", $data["appid"])->find();
        if (!$plateinfo) {
            $this->json(0, "系统错误！");
        }
        $user_all_info = $this->user_info;
        if ($this->app_info["forum_configuration"]["moderator_delete_comment"] == 0 && $comment_info["userid"] != $user_all_info["id"]) {
            $plateadmin_array = array_filter(explode(",", $plateinfo["forum_section"]));
            if (in_array($user_all_info["id"], $plateadmin_array)) {
                recursive_deletion_comment($data["commentid"]);
                $addmessagedata = [
                    "title" => "删除通知",
                    "content" => "您的评论《" . $comment_info["content"] . "》被" . $user_all_info["nickname"] . "删除了",
                    "send_to" => 0,
                    "appid" => $comment_info["appid"],
                    "time" => date("Y-m-d H:i:s", time()),
                    "type" => 9,
                    "user_id" => $comment_info["userid"],
                    "postid" => 0,
                ];
                Db::name("message_notification")->insert($addmessagedata);
                $this->json(1, "删除成功！");
            }
        }
        if ($comment_info["userid"] != $user_all_info["id"]) {
            $this->json(0, "系统错误！");
        }
        try {
            //开启数据库事务
            Db::startTrans();
            //删除帖子 先看看用户的金币、积分、经验是否足够
            if ($this->app_info["forum_configuration"]["del_comment_money"] > 0) {
                $this->assertAssetBalance($user_all_info, "money", $this->app_info["forum_configuration"]["del_comment_money"]);
            }
            if ($this->app_info["forum_configuration"]["del_comment_integral"] > 0) {
                $this->assertAssetBalance($user_all_info, "integral", $this->app_info["forum_configuration"]["del_comment_integral"]);
            }
            if ($this->app_info["forum_configuration"]["del_comment_exp"] > $user_all_info["exp"]) {
                $this->json(0, "经验不足，无法删除评论！");
            }
            if ($this->app_info["forum_configuration"]["del_comment_money"] > 0) {
                add_user_bill($user_all_info, 14, "-" . $this->app_info["forum_configuration"]["del_comment_money"], "删除评论", 0, 0);
            }
            if ($this->app_info["forum_configuration"]["del_comment_integral"] > 0) {
                add_user_bill($user_all_info, 14, "-" . $this->app_info["forum_configuration"]["del_comment_integral"], "删除评论", 1, 0);
            }
            //扣除用户的金币、积分、经验
            $update_user_data["money"] = $user_all_info["money"] - $this->app_info["forum_configuration"]["del_comment_money"];
            $update_user_data["integral"] = $user_all_info["integral"] - $this->app_info["forum_configuration"]["del_comment_integral"];
            $update_user_data["exp"] = $user_all_info["exp"] - $this->app_info["forum_configuration"]["del_comment_exp"];
            Db::name("user")->where("id", $user_all_info["id"])->update($update_user_data);
            recursive_deletion_comment($data["commentid"]);
            Db::commit();
            $this->json(1, "删除成功！");
        } catch (\Exception $e) {
            Db::rollback();
            $this->json(0, $e->getMessage());
        }
        $this->json(1, "删除成功！");
    }

    //获取评论列表
    public function get_list_comments()
    {
        $data = input();
        $rule = [
            'postid|帖子id' => 'number',
            'userid|用户id' => 'number',
        ];
        $validate = new Validate();
        $validate->rule($rule);
        $result = $validate->check($data);
        if (!$result) {
            $this->json(0, $validate->getError());
        }
        if (!input("?postid") && !input("?userid")) {
            $this->json(0, "userid和postid必须传一个");
        }
        $where = " c.appid = {$this->appid} ";
        if (input("?postid")) {
            $postinfo = Db::name("forum_posts")->where("id", $data["postid"])->where("appid", $data["appid"])->find();
            if (!$postinfo) {
                $this->json(0, "帖子不存在");
            }
            $where .= "and c.status = 1 and c.postid = {$data['postid']}";
        }
        if (input("?userid")) {
            $userinfo = Db::name("user")->where("id", $data["userid"])->where("appid", $data["appid"])->find();
            if (!$userinfo) {
                $this->json(0, "用户不存在");
            }
            $where .= " and c.userid = {$data['userid']}";
            if (input("status") != "") {
                $where .= " and c.status = {$data['status']}";
            }
        }
        if (input("?comment_id")) {
            if ($data["comment_id"] != 0) {
                $userinfo = Db::name("comments")->where("id", $data["comment_id"])->where("appid", $data["appid"])->find();
                if (!$userinfo) {
                    $this->json(0, "评论不存在");
                }
            }
            $where .= " and c.parentid = {$data['comment_id']}";
        }
        $sort = input("?sort") ? $data["sort"] : "time";
        $sortOrder = input("?sortOrder") ? $data["sortOrder"] : 'desc';
        if ($sort != "time" && $sort != "id") {
            $this->json(0, "sort参数错误");
        }
        if ($sortOrder != "desc" && $sortOrder != "asc") {
            $this->json(0, "sortOrder参数错误");
        }
        $result = Db::name('comments')
            ->alias("c")
            ->join("user u", "u.id = c.userid")
            ->join("forum_posts a", "a.id = c.postid")
            ->where($where)
            ->field("c.*,u.username,u.nickname,u.usertx,u.title as usertitle,u.exp,a.title as posttitle,u.viptime")
            ->order("c.topping", "desc")
            ->order("c." . $sort, $sortOrder)
            ->limit($this->limit)
            ->page($this->page)
            ->select()->toArray();
        $pagecount = db("comments")
            ->alias("c")
            ->join("user u", "u.id = c.userid")
            ->join("forum_posts a", "a.id = c.postid")
            ->field("c.*")
            ->where($where)
            ->order("c.id", "desc")
            ->count();
        $ip = new IpLocation();
        foreach ($result as $key => $value) {
            $result[$key]["ip_address"] = $value["ip"] == "" ? "未知" : $ip->getDetail($value["ip"])["dataA"];
            $result[$key]["image_path"] = $value["image_path"] == "" ? "" : $value["image_path"];
            unset($result[$key]["ip"]);
            $result[$key]["usertitle"] = array_filter(explode(",", $value["usertitle"]));
            //假入有上级评论则插入
            //上级评论者用户昵称
            $result[$key]["parentnickname"] = "";
            $result[$key]["parentusername"] = "";
            //上级评论内容
            $result[$key]["parentcontent"] = "";
            if ($value["parentid"] != 0) {
                $parentcommentinfo = Db::name("comments")
                    ->alias("c")
                    ->join("user u", "u.id = c.userid")
                    ->join("forum_posts a", "a.id = c.postid")
                    ->where("c.id", $value["parentid"])
                    ->field("c.id,c.content,u.nickname,u.username")
                    ->order("c.topping", "desc")
                    ->find();
                if ($parentcommentinfo) {
                    //上级评论者用户昵称
                    $result[$key]["parentnickname"] = $parentcommentinfo["nickname"];
                    $result[$key]["parentusername"] = $parentcommentinfo["username"];
                    //上级评论内容
                    $result[$key]["parentcontent"] = $parentcommentinfo["content"];
                } else {
                    //上级评论者用户昵称
                    $result[$key]["parentnickname"] = "用户已注销";
                    $result[$key]["parentusername"] = "用户已注销";
                    //上级评论内容
                    $result[$key]["parentcontent"] = "评论已删除";
                }
            }
            $result[$key]["image_path"] = array_filter(explode(",", $value["image_path"]));
            unset($result[$key]["status"]);
            //经验等级
            $arr = $this->app_info["grade"];
            $grades = eval("return $arr;");
            $result[$key]["hierarchy"] = "";
            if (is_array($grades)) {
                foreach ($grades as $k1 => $v1) {
                    if ($result[$key]['exp'] >= $k1) {
                        $result[$key]["hierarchy"] = $v1;
                    } else {
                        break;
                    }
                }
            }
            //判断用户是否是版主
            $plate_list = Db::name("forum_section")->where("appid", $this->appid)->select()->toArray();
            $result[$key]["is_section_moderator"] = 0;
            foreach ($plate_list as $k1 => $v1) {
                $section_id_array = explode(",", $v1["forum_section"]);
                if (in_array($value["userid"], $section_id_array)) {
                    $result[$key]["is_section_moderator"] = 1;
                    break;
                }
            }
            //是否是会员
            if (time() < $value["viptime"]) {
                $result[$key]["vip"] = true;
            } else {
                $result[$key]["vip"] = false;
            }
            unset($result[$key]["viptime"]);
            //获取用户的徽章
            $result[$key]["badge"] = Db::name("polymorphic")
                ->alias("p")
                ->join("bagge b", "b.id=p.other_id")
                ->where("p.userid", $value["userid"])
                ->where("p.type", 5)
                ->where("b.is_view", 0)
                ->where("p.wearing", 0)
                ->order(["b.type" => $this->medal_sorting, "b.sort" => "desc"])
                ->field("b.id,b.name,b.icon,b.type,case when p.expiration_time = '9999' then '永久' else p.expiration_time end as expiration_time")
                ->select()->toArray();
            $result[$key]["reward"] = Db::name("post_payment")->where("comment_id", $value["id"])->where("type", 3)->sum("amount");
            $result[$key]["reward_user_list"] = Db::name("post_payment")
                ->alias("a")
                ->join("user b", "a.userid = b.id")
                ->field("a.amount,a.payment,b.id,b.username,b.nickname,b.usertx")
                ->where("comment_id", $value["id"])
                ->where("type", 3)
                ->select()->toArray();
            $result[$key]["sub_comments_count"] = Db::name('comments')->where("parentid", $value["id"])->count();
            $result[$key]["sub_comments_count"] = formatNumber($result[$key]["sub_comments_count"]);
            $result[$key]["time_ago"] = change_time_type($value["time"]);
            $result[$key]["is_landlord"] = 0;
            if (input("?postid")) {
                $result[$key]["is_landlord"] = $postinfo["userid"] == $value["userid"] ? 1 : 0;
            }
        }
        $data_rs["list"] = $result;
        $data_rs["pagecount"] = ceil($pagecount / $this->limit) == 0 ? 1 : ceil($pagecount / $this->limit);
        $data_rs["current_number"] = (int)$this->page;
        $this->json(1, "success", $data_rs);
    }

    //点赞帖子 or 取消点赞
    public function like_posts()
    {
        $data = input();
        $rule = [
            'usertoken' => 'require',
            'postid|帖子id' => 'require|number',
        ];
        $validate = new Validate();
        $validate->rule($rule);
        $result = $validate->check($data);
        if (!$result) {
            $this->json(0, $validate->getError());
        }
        $postinfo = Db::name("forum_posts")->where("id", $data["postid"])->where("appid", $data["appid"])->find();
        if (!$postinfo) {
            $this->json(0, "系统错误");
        }
        if ($postinfo["status"] != 1) {
            $this->json(0, "该文章暂未通过审核，无法点赞！");
        }
        $user_all_info = $this->user_info;
        $thumbsinfo = Db::name("polymorphic")->where("other_id", $data["postid"])->where("userid", $user_all_info["id"])->where("type", 3)->find();
        if ($thumbsinfo) {
            Db::name("polymorphic")->where("other_id", $data["postid"])->where("userid", $user_all_info["id"])->where("type", 3)->delete();
            $thumbs_count = Db::name("polymorphic")->where("other_id", $data["postid"])->where("type", 3)->count();
            $thumbs_count = formatNumber($thumbs_count);
            $this->json(1, "取消点赞成功", ["thumbs_count" => $thumbs_count]);
        }
        $adddata = [
            "appid" => $data["appid"],
            "create_time" => date("Y-m-d H:i:s", time()),
            "userid" => $user_all_info["id"],
            "other_id" => $data["postid"],
            "type" => 3
        ];
        Db::name("polymorphic")->insert($adddata);
        increase_user_notifications_to_users($this->user_info, 2, $postinfo);
        //获取点赞数量
        $thumbs_count = Db::name("polymorphic")->where("other_id", $data["postid"])->where("type", 3)->count();
        $thumbs_count = formatNumber($thumbs_count);
        $this->json(1, "点赞成功", ["thumbs_count" => $thumbs_count]);
    }

    //获取点赞记录
    public function get_likes_records()
    {
        $data = input();
        $rule = [
            'usertoken' => 'require',
        ];
        $validate = new Validate();
        $validate->rule($rule);
        $result = $validate->check($data);
        if (!$result) {
            $this->json(0, $validate->getError());
        }
        $user_all_info = $this->user_info;
        $where = "v.type = 3 and v.userid = {$user_all_info["id"]}";
        //板块id
        if (input("sectionid")) {
            $where .= " and a.section_id = {$data['sectionid']}";
        }
        //板块id
        if (input("sub_sectionid")) {
            $where .= " and a.sub_section_id = {$data['sub_sectionid']}";
        }
        $result = Db::name("polymorphic")
            ->alias("v")
            ->join("forum_posts p", "p.id=v.other_id")
            ->join("user u", "u.id=p.userid")
            ->join("forum_section s", "s.id=p.section_id")
            ->join("forum_section sub", "sub.id=p.sub_section_id")
            ->field("p.id as postid,p.*,u.username,u.nickname,u.usertx,u.title as usertitle,u.sex,u.signature,u.viptime,u.exp,s.section_name,s.section_icon,s.forum_section,sub.section_name as sub_section_name")
            ->where($where)
            ->order("v.id", "desc")
            ->limit($this->limit)
            ->page($this->page)
            ->select()->toArray();
        $pagecount = Db::name("polymorphic")
            ->alias("v")
            ->join("forum_posts a", "a.id=v.other_id")
            ->join("user u", "u.id=a.userid")
            ->join("forum_section s", "s.id=a.section_id")
            ->join("forum_section sub", "sub.id=a.sub_section_id")
            ->field("a.id as postid,a.*,u.username,u.nickname,u.usertx,u.title as usertitle,u.sex,u.signature,s.section_name,s.section_icon,sub.section_name as sub_section_name")
            ->where($where)
            ->count();
        $ip = new IpLocation();
        foreach ($result as $key => $value) {
            //截取帖子内容
            //判断改帖子是否是付费阅读
            if ($value["paid_reading"] == 0) {
                //如果内容字数小于设置的字数或者等于0则全部显示
                if (mb_strlen($value["content"], "utf-8") <= $this->app_info["forum_configuration"]["number_text_intercepted"] || $this->app_info["forum_configuration"]["number_text_intercepted"] == 0) {
                    $result[$key]["content"] = $value["content"];
                } else {
                    $result[$key]["content"] = mb_substr($value["content"], 0, $this->app_info["forum_configuration"]["number_text_intercepted"], "utf-8") . "...";
                }
            } else {
                $result[$key]["content"] = mb_substr($value["content"], 0, $value["preview_word_count"], "utf-8") . "...";
            }
            $result[$key]["ip_address"] = $value["ip"] == "" ? "" : $ip->getDetail($value["ip"])["dataA"];
            $result[$key]["img_url"] = array_filter(explode(",", $value["img_url"]));
            $result[$key]["usertitle"] = array_filter(explode(",", $value["usertitle"]));
            $result[$key]["sex"] = $value["sex"];
            $result[$key]["sexName"] = $value["sex"] == 0 ? "男" : "女";
            //判断当前发帖的用户是否是版主
            $result[$key]["is_section_moderator"] = 0;
            $section_id_array = explode(",", $value["forum_section"]);
            if (in_array($value["userid"], $section_id_array)) {
                $result[$key]["is_section_moderator"] = 1;
            }
            //获取用户的徽章
            $result[$key]["badge"] = Db::name("polymorphic")
                ->alias("p")
                ->join(
                    "bagge b",
                    "b.id=p.other_id"
                )
                ->where("p.userid", $value["userid"])
                ->where("p.type", 5)
                ->where("b.is_view", 0)
                ->where("p.wearing", 0)
                ->order(["b.type" => $this->medal_sorting, "b.sort" => "desc"])
                ->field("b.id,b.name,b.icon,b.type,case when p.expiration_time = '9999' then '永久' else p.expiration_time end as expiration_time")
                ->select()->toArray();
            //是否是会员
            if (time() < $value["viptime"]) {
                $result[$key]["vip"] = true;
            } else {
                $result[$key]["vip"] = false;
            }
            //经验等级
            $arr = $this->app_info["grade"];
            $grades = eval("return $arr;");
            $result[$key]["hierarchy"] = "";
            if (is_array($grades)) {
                foreach ($grades as $k1 => $v1) {
                    if ($result[$key]['exp'] >= $k1) {
                        $result[$key]["hierarchy"] = $v1;
                    } else {
                        break;
                    }
                }
            }
            $result[$key]["create_time_ago"] = change_time_type($value["create_time"]);
            $result[$key]["update_time_ago"] = change_time_type($value["update_time"]);
            //帖子访问量
            $result[$key]["view"] = Db::name("polymorphic")->where("other_id", $value["id"])->where("type", 4)->count();
            $result[$key]["view"] = formatNumber($result[$key]["view"]);
            //点赞量
            $result[$key]["thumbs"] = Db::name("polymorphic")->where("other_id", $value["id"])->where("type", 3)->count();
            $result[$key]["thumbs"] = formatNumber($result[$key]["thumbs"]);
            //评论量
            $result[$key]["comment"] = Db::name("comments")->where("postid", $value["id"])->count();
            $result[$key]["comment"] = formatNumber($result[$key]["comment"]);
            //去除不需要的字段
            unset($result[$key]["id"]);
            unset($result[$key]["ip"]);
            unset($result[$key]["viptime"]);
            unset($result[$key]["file"]);
            unset($result[$key]["reading_price"]);
            unset($result[$key]["preview_word_count"]);
            unset($result[$key]["file_download_price"]);
            unset($result[$key]["forum_section"]);
            $result[$key]["reward"] = Db::name("post_payment")->where("postid", $value["id"])->where("type", 2)->sum("amount");
            $result[$key]["payers"] = Db::name("post_payment")->where("postid", $value["id"])->where("type = 0 or type = 1")->count();
            $result[$key]["payers"] = formatNumber($result[$key]["payers"]);
        }
        $data_rs["list"] = $result;
        $data_rs["pagecount"] = ceil($pagecount / $this->limit) == 0 ? 1 : ceil($pagecount / $this->limit);
        $data_rs["current_number"] = (int)$this->page;
        $this->json(1, "success", $data_rs);
    }

    //浏览历史
    public function browse_history()
    {
        $data = input();
        $rule = [
            'usertoken' => 'require',
        ];
        $validate = new Validate();
        $validate->rule($rule);
        $result = $validate->check($data);
        if (!$result) {
            $this->json(0, $validate->getError());
        }
        $user_all_info = $this->user_info;
        $where = "v.type = 4 and v.userid = {$user_all_info["id"]}";
        //板块id
        if (input("sectionid")) {
            $where .= " and a.section_id = {$data['sectionid']}";
        }
        //板块id
        if (input("sub_sectionid")) {
            $where .= " and a.sub_section_id = {$data['sub_sectionid']}";
        }
        $result = Db::name("polymorphic")
            ->alias("v")
            ->join("forum_posts a", "a.id=v.other_id")
            ->join("user u", "u.id=a.userid")
            ->join("forum_section s", "s.id=a.section_id")
            ->join("forum_section sub", "sub.id=a.sub_section_id")
            ->field("MAX(v.create_time) as max_create_time,a.id as postid,a.*,u.username,u.nickname,u.usertx,u.title as usertitle,u.sex,u.signature,u.viptime,u.exp,s.section_name,s.section_icon,s.forum_section,sub.section_name as sub_section_name")
            ->where($where)
            ->group("v.other_id")
            ->order("max_create_time", "desc")
            ->limit($this->limit)
            ->page($this->page)
            ->select()->toArray();
        $pagecount = Db::name("polymorphic")
            ->alias("v")
            ->join("forum_posts a", "a.id=v.other_id")
            ->join("user u", "u.id=a.userid")
            ->join("forum_section s", "s.id=a.section_id")
            ->join("forum_section sub", "sub.id=a.sub_section_id")
            ->field("MAX(v.create_time) as max_create_time,a.id as postid,a.*,u.username,u.nickname,u.usertx,u.title as usertitle,u.sex,u.signature,u.viptime,u.exp,s.section_name,s.section_icon,s.forum_section,sub.section_name as sub_section_name")
            ->where($where)
            ->group("v.other_id")
            ->order("max_create_time", "desc")
            ->where($where)
            ->distinct(true)
            ->count();
        $ip = new IpLocation();
        foreach ($result as $key => $value) {
            unset($result[$key]["max_create_time"]);
            //截取帖子内容
            //判断改帖子是否是付费阅读
            if ($value["paid_reading"] == 0) {
                //如果内容字数小于设置的字数或者等于0则全部显示
                if (mb_strlen($value["content"], "utf-8") <= $this->app_info["forum_configuration"]["number_text_intercepted"] || $this->app_info["forum_configuration"]["number_text_intercepted"] == 0) {
                    $result[$key]["content"] = $value["content"];
                } else {
                    $result[$key]["content"] = mb_substr($value["content"], 0, $this->app_info["forum_configuration"]["number_text_intercepted"], "utf-8") . "...";
                }
            } else {
                $result[$key]["content"] = mb_substr($value["content"], 0, $value["preview_word_count"], "utf-8") . "...";
            }
            $result[$key]["ip_address"] = $value["ip"] == "" ? "" : $ip->getDetail($value["ip"])["dataA"];
            $result[$key]["img_url"] = array_filter(explode(",", $value["img_url"]));
            $result[$key]["usertitle"] = array_filter(explode(",", $value["usertitle"]));
            $result[$key]["sex"] = $value["sex"];
            $result[$key]["sexName"] = $value["sex"] == 0 ? "男" : "女";
            //判断当前发帖的用户是否是版主
            $result[$key]["is_section_moderator"] = 0;
            $section_id_array = explode(",", $value["forum_section"]);
            if (in_array($value["userid"], $section_id_array)) {
                $result[$key]["is_section_moderator"] = 1;
            }
            //获取用户的徽章
            $result[$key]["badge"] = Db::name("polymorphic")
                ->alias("p")
                ->join("bagge b", "b.id=p.other_id")
                ->where("p.userid", $value["userid"])
                ->where("p.type", 5)
                ->where("b.is_view", 0)
                ->where("p.wearing", 0)
                ->order(["b.type" => $this->medal_sorting, "b.sort" => "desc"])
                ->field("b.id,b.name,b.icon,case when p.expiration_time = '9999' then '永久' else p.expiration_time end as expiration_time")
                ->select()->toArray();
            //是否是会员
            if (time() < $value["viptime"]) {
                $result[$key]["vip"] = true;
            } else {
                $result[$key]["vip"] = false;
            }
            //经验等级
            $arr = $this->app_info["grade"];
            $grades = eval("return $arr;");
            $result[$key]["hierarchy"] = "";
            if (is_array($grades)) {
                foreach ($grades as $k1 => $v1) {
                    if ($result[$key]['exp'] >= $k1) {
                        $result[$key]["hierarchy"] = $v1;
                    } else {
                        break;
                    }
                }
            }
            $result[$key]["create_time_ago"] = change_time_type($value["create_time"]);
            $result[$key]["update_time_ago"] = change_time_type($value["update_time"]);
            //帖子访问量
            $result[$key]["view"] = Db::name("polymorphic")->where("other_id", $value["id"])->where("type", 4)->count();
            $result[$key]["view"] = formatNumber($result[$key]["view"]);
            //点赞量
            $result[$key]["thumbs"] = Db::name("polymorphic")->where("other_id", $value["id"])->where("type", 3)->count();
            $result[$key]["thumbs"] = formatNumber($result[$key]["thumbs"]);
            //评论量
            $result[$key]["comment"] = Db::name("comments")->where("postid", $value["id"])->count();
            $result[$key]["comment"] = formatNumber($result[$key]["comment"]);
            //去除不需要的字段
            unset($result[$key]["id"]);
            unset($result[$key]["ip"]);
            unset($result[$key]["viptime"]);
            unset($result[$key]["file"]);
            unset($result[$key]["reading_price"]);
            unset($result[$key]["preview_word_count"]);
            unset($result[$key]["file_download_price"]);
            unset($result[$key]["forum_section"]);
            $result[$key]["reward"] = Db::name("post_payment")->where("postid", $value["id"])->where("type", 2)->sum("amount");
            $result[$key]["payers"] = Db::name("post_payment")->where("postid", $value["id"])->where("type = 0 or type = 1")->count();
            $result[$key]["payers"] = formatNumber($result[$key]["payers"]);
        }
        $data_rs["list"] = $result;
        $data_rs["pagecount"] = ceil($pagecount / $this->limit) == 0 ? 1 : ceil($pagecount / $this->limit);
        $data_rs["current_number"] = (int)$this->page;
        $this->json(1, "success", $data_rs);
    }

    //获取我的关注的帖子
    public function get_my_following_posts()
    {
        $data = input();
        $rule = [
            'usertoken' => 'require',
        ];
        $validate = new Validate();
        $validate->rule($rule);
        $result = $validate->check($data);
        if (!$result) {
            $this->json(0, $validate->getError());
        }
        $user_all_info = $this->user_info;
        $where = "f.type = 2 and f.userid = {$user_all_info["id"]} and f.appid = {$data["appid"]} ";
        //板块id
        if (input("sectionid")) {
            $where .= " and p.section_id = {$data['sectionid']}";
        }
        //板块id
        if (input("sub_sectionid")) {
            $where .= " and p.sub_section_id = {$data['sub_sectionid']}";
        }
        $result = Db::name("polymorphic")
            ->alias("f")
            ->join("user u", "u.id=f.other_id")
            ->join("forum_posts p", "p.userid=f.other_id")
            ->join("forum_section s", "s.id=p.section_id")
            ->join("forum_section sub", "sub.id=p.sub_section_id")
            ->where($where)
            ->field("p.id as postid,p.*,u.username,u.nickname,u.usertx,u.title as usertitle,u.sex,u.signature,u.viptime,u.exp,s.section_name,s.section_icon,s.forum_section,sub.section_name as sub_section_name")
            ->order("p.create_time desc")
            ->limit($this->limit)
            ->page($this->page)
            ->select()->toArray();
        $pagecount = Db::name("polymorphic")
            ->alias("f")
            ->join("user u", "u.id=f.other_id")
            ->join("forum_posts p", "p.userid=f.other_id")
            ->join("forum_section s", "s.id=p.section_id")
            ->join("forum_section sub", "sub.id=p.sub_section_id")
            ->where($where)
            ->order("p.create_time desc")
            ->count();
        $ip = new IpLocation();
        foreach ($result as $key => $value) {
            //截取帖子内容
            //判断改帖子是否是付费阅读
            if ($value["paid_reading"] == 0) {
                //如果内容字数小于设置的字数或者等于0则全部显示
                if (mb_strlen($value["content"], "utf-8") <= $this->app_info["forum_configuration"]["number_text_intercepted"] || $this->app_info["forum_configuration"]["number_text_intercepted"] == 0) {
                    $result[$key]["content"] = $value["content"];
                } else {
                    $result[$key]["content"] = mb_substr($value["content"], 0, $this->app_info["forum_configuration"]["number_text_intercepted"], "utf-8") . "...";
                }
            } else {
                $result[$key]["content"] = mb_substr($value["content"], 0, $value["preview_word_count"], "utf-8") . "...";
            }
            $result[$key]["ip_address"] = $value["ip"] == "" ? "" : $ip->getDetail($value["ip"])["dataA"];
            $result[$key]["img_url"] = array_filter(explode(",", $value["img_url"]));
            $result[$key]["usertitle"] = array_filter(explode(",", $value["usertitle"]));
            $result[$key]["sex"] = $value["sex"];
            $result[$key]["sexName"] = $value["sex"] == 0 ? "男" : "女";
            //判断当前发帖的用户是否是版主
            $result[$key]["is_section_moderator"] = 0;
            $section_id_array = explode(",", $value["forum_section"]);
            if (in_array($value["userid"], $section_id_array)) {
                $result[$key]["is_section_moderator"] = 1;
            }
            //获取用户的徽章
            $result[$key]["badge"] = Db::name("polymorphic")
                ->alias("p")
                ->join(
                    "bagge b",
                    "b.id=p.other_id"
                )
                ->where("p.userid", $value["userid"])
                ->where("p.type", 5)
                ->where("b.is_view", 0)
                ->where("p.wearing", 0)
                ->order(["b.type" => $this->medal_sorting, "b.sort" => "desc"])
                ->field("b.id,b.name,b.icon,b.type,case when p.expiration_time = '9999' then '永久' else p.expiration_time end as expiration_time")
                ->select()->toArray();
            //是否是会员
            if (time() < $value["viptime"]) {
                $result[$key]["vip"] = true;
            } else {
                $result[$key]["vip"] = false;
            }
            //经验等级
            $arr = $this->app_info["grade"];
            $grades = eval("return $arr;");
            $result[$key]["hierarchy"] = "";
            if (is_array($grades)) {
                foreach ($grades as $k1 => $v1) {
                    if ($value['exp'] >= $k1) {
                        $result[$key]["hierarchy"] = $v1;
                    } else {
                        break;
                    }
                }
            }
            $result[$key]["create_time_ago"] = change_time_type($value["create_time"]);
            $result[$key]["update_time_ago"] = change_time_type($value["update_time"]);
            //帖子访问量
            $result[$key]["view"] = Db::name("polymorphic")->where("other_id", $value["id"])->where("type", 4)->count();
            $result[$key]["view"] = formatNumber($result[$key]["view"]);
            //点赞量
            $result[$key]["thumbs"] = Db::name("polymorphic")->where("other_id", $value["id"])->where("type", 3)->count();
            $result[$key]["thumbs"] = formatNumber($result[$key]["thumbs"]);
            //评论量
            $result[$key]["comment"] = Db::name("comments")->where("postid", $value["id"])->count();
            $result[$key]["comment"] = formatNumber($result[$key]["comment"]);
            //去除不需要的字段
            unset($result[$key]["id"]);
            unset($result[$key]["ip"]);
            unset($result[$key]["viptime"]);
            unset($result[$key]["file"]);
            unset($result[$key]["reading_price"]);
            unset($result[$key]["preview_word_count"]);
            unset($result[$key]["file_download_price"]);
            unset($result[$key]["forum_section"]);
            //获取帖子的打赏金额
            $result[$key]["reward"] = Db::name("post_payment")->where("postid", $value["id"])->where("type", 2)->sum("amount");
            $result[$key]["payers"] = Db::name("post_payment")->where("postid", $value["id"])->where("type = 0 or type = 1")->count();
            $result[$key]["payers"] = formatNumber($result[$key]["payers"]);
        }
        $data_rs["list"] = $result;
        $data_rs["pagecount"] = ceil($pagecount / $this->limit) == 0 ? 1 : ceil($pagecount / $this->limit);
        $data_rs["current_number"] = $this->page;
        $this->json(1, "success", $data_rs);
    }

    //审核帖子
    public function review_posts()
    {
        $data = input();
        $rule = [
            'usertoken|用户token' => 'require',
            'postid|帖子ID' => 'require|number',
            'status|帖子状态' => 'require|number',
        ];
        $validate = new Validate();
        $validate->rule($rule);
        $result = $validate->check($data);
        if (!$result) {
            $this->json(0, $validate->getError());
        }
        //判断status 只能为 1已审核(正常)2审核未通过
        if (!in_array($data["status"], [1, 2])) {
            $this->json(0, "status参数错误");
        }
        $user_all_info = $this->user_info;
        $postsinfo = Db::name("forum_posts")->where("appid", $this->appid)->where("id", $data["postid"])->find();
        if (!$postsinfo) {
            $this->json(0, "帖子不存在");
        }
        if ($postsinfo["status"] == 1) {
            $this->json(0, "帖子已审核");
        }
        //获取版块管理员
        $sectioninfo = Db::name("forum_section")->where("id", $postsinfo["section_id"])->find();
        if (!$sectioninfo) {
            $this->json(0, "版块不存在");
        }
        $section_admin = array_filter(explode(",", $sectioninfo["forum_section"]));
        if (!in_array($user_all_info["id"], $section_admin)) {
            $this->json(0, "您不是版块管理员");
        }
        //审核帖子
        $result = Db::name("forum_posts")->where("id", $data["postid"])->update(["status" => $data["status"]]);
        if ($result) {
            Db::name("forum_posts")->where("id", "=", $postsinfo["id"])->update([
                "update_time" => date("Y-m-d H:i:s", time()),
            ]);
            if ($data["status"] == 2) {
                $addmessagedata = [
                    "title" => "帖子审核未通过",
                    "content" => "您的帖子【" . $postsinfo['title'] . "】审核未通过，原因：" . input('reason_review') == "" ? "违规" : input('reason_review'),
                    "send_to" => 0,
                    "appid" => $postsinfo['appid'],
                    "time" => date("Y-m-d H:i:s", time()),
                    "type" => 0,
                    "user_id" => $postsinfo['userid'],
                ];
                Db::name("message_notification")->insert($addmessagedata);
            } else {
                $addmessagedata = [
                    "title" => "帖子审核通过",
                    "content" => "您的帖子【" . $postsinfo['title'] . "】审核通过",
                    "send_to" => 0,
                    "appid" => $postsinfo['appid'],
                    "time" => date("Y-m-d H:i:s", time()),
                    "type" => 0,
                    "user_id" => $postsinfo['userid'],
                ];
                Db::name("message_notification")->insert($addmessagedata);
                // 查询该帖子的状态记录 原来是否有过审核通过的记录
                $status_record = Db::name("status_record")->where("object_id", $postsinfo["id"])->where("original_status", 1)->where("type", 0)->find();
                if (!$status_record) {
                    forum_add_equity($postsinfo["id"], $postsinfo["userid"], 0);
                }
                $add_status_record_data = [
                    "object_id" => $postsinfo["id"],
                    "original_status" => $postsinfo["status"],
                    "changing_status" => 1,
                    "type" => 0,
                    "create_time" => date("Y-m-d H:i:s", time()),
                ];
                Db::name("status_record")->insert($add_status_record_data);
            }
            $this->json(1, "success", []);
        } else {
            $this->json(0, "审核失败");
        }
    }

    //获取待审核的帖子
    public function get_pending_review_posts()
    {
        $data = input();
        $rule = [
            'usertoken|用户token' => 'require',
        ];
        $validate = new Validate();
        $validate->rule($rule);
        $result = $validate->check($data);
        if (!$result) {
            $this->json(0, $validate->getError());
        }
        //获取属于当前用户的管理版块的待审核帖子
        $user_all_info = $this->user_info;
        $sectioninfo = Db::name("forum_section")->where("appid", $this->appid)->select()->toArray();
        //定义一个空数组,存储当前用户管理的版块
        $section_arr = [];
        foreach ($sectioninfo as $key => $value) {
            $section_admin = array_filter(explode(",", $value["forum_section"]));
            if (in_array($user_all_info["id"], $section_admin)) {
                $section_arr[] = $value["id"];
            }
        }
        if (count($section_arr) == 0) {
            $this->json(0, "您没有管理的版块");
        }
        //获取待审核的帖子
        $result = Db::name("forum_posts")
            ->alias("p")
            ->join("user u", "u.id=p.userid")
            ->join("forum_section s", "s.id=p.section_id")
            ->join("forum_section sub", "sub.id=p.sub_section_id")
            ->field("p.id as postid,p.*,u.username,u.nickname,u.usertx,u.title as usertitle,u.sex,u.signature,u.viptime,u.exp,s.section_name,s.section_icon,s.forum_section,sub.section_name as sub_section_name")
            ->where("p.appid", $this->appid)
            ->where("p.status", 0)
            ->where("p.section_id", "in", $section_arr)
            ->order("p.create_time", "asc")
            ->limit($this->limit)
            ->page($this->page)
            ->select()->toArray();
        $ip = new IpLocation();
        foreach ($result as $key => $value) {
            //截取帖子内容
            //判断改帖子是否是付费阅读
            if ($value["paid_reading"] == 0) {
                //如果内容字数小于设置的字数或者等于0则全部显示
                if (mb_strlen($value["content"], "utf-8") <= $this->app_info["forum_configuration"]["number_text_intercepted"] || $this->app_info["forum_configuration"]["number_text_intercepted"] == 0) {
                    $result[$key]["content"] = $value["content"];
                } else {
                    $result[$key]["content"] = mb_substr($value["content"], 0, $this->app_info["forum_configuration"]["number_text_intercepted"], "utf-8") . "...";
                }
            } else {
                $result[$key]["content"] = mb_substr($value["content"], 0, $value["preview_word_count"], "utf-8") . "...";
            }
            $result[$key]["ip_address"] = $value["ip"] == "" ? "" : $ip->getDetail($value["ip"])["dataA"];
            $result[$key]["img_url"] = array_filter(explode(",", $value["img_url"]));
            $result[$key]["usertitle"] = array_filter(explode(",", $value["usertitle"]));
            $result[$key]["sex"] = $value["sex"];
            $result[$key]["sexName"] = $value["sex"] == 0 ? "男" : "女";
            //判断当前发帖的用户是否是版主
            $result[$key]["is_section_moderator"] = 0;
            $section_id_array = explode(",", $value["forum_section"]);
            if (in_array($value["userid"], $section_id_array)) {
                $result[$key]["is_section_moderator"] = 1;
            }
            //获取用户的徽章
            $result[$key]["badge"] = Db::name("polymorphic")
                ->alias("p")
                ->join(
                    "bagge b",
                    "b.id=p.other_id"
                )
                ->where("p.userid", $value["userid"])
                ->where("p.type", 5)
                ->where("b.is_view", 0)
                ->where("p.wearing", 0)
                ->order(["b.type" => $this->medal_sorting, "b.sort" => "desc"])
                ->field("b.id,b.name,b.icon,b.type,case when p.expiration_time = '9999' then '永久' else p.expiration_time end as expiration_time")
                ->select()->toArray();
            //是否是会员
            if (time() < $value["viptime"]) {
                $result[$key]["vip"] = true;
            } else {
                $result[$key]["vip"] = false;
            }
            //经验等级
            $arr = $this->app_info["grade"];
            $grades = eval("return $arr;");
            $result[$key]["hierarchy"] = "";
            if (is_array($grades)) {
                foreach ($grades as $k1 => $v1) {
                    if ($result[$key]['exp'] >= $k1) {
                        $result[$key]["hierarchy"] = $v1;
                    } else {
                        break;
                    }
                }
            }
            $result[$key]["create_time_ago"] = change_time_type($value["create_time"]);
            $result[$key]["update_time_ago"] = change_time_type($value["update_time"]);
            //帖子访问量
            $result[$key]["view"] = Db::name("polymorphic")->where("other_id", $value["id"])->where("type", 4)->count();
            $result[$key]["view"] = formatNumber($result[$key]["view"]);
            //点赞量
            $result[$key]["thumbs"] = Db::name("polymorphic")->where("other_id", $value["id"])->where("type", 3)->count();
            $result[$key]["thumbs"] = formatNumber($result[$key]["thumbs"]);
            //评论量
            $result[$key]["comment"] = Db::name("comments")->where("postid", $value["id"])->count();
            $result[$key]["comment"] = formatNumber($result[$key]["comment"]);
            //去除不需要的字段
            unset($result[$key]["id"]);
            unset($result[$key]["ip"]);
            unset($result[$key]["viptime"]);
            unset($result[$key]["file"]);
            unset($result[$key]["reading_price"]);
            unset($result[$key]["preview_word_count"]);
            unset($result[$key]["file_download_price"]);
            unset($result[$key]["forum_section"]);
            //获取帖子的打赏金额
            $result[$key]["reward"] = Db::name("post_payment")->where("postid", $value["id"])->where("type", 2)->sum("amount");
            $result[$key]["payers"] = Db::name("post_payment")->where("postid", $value["id"])->where("type = 0 or type = 1")->count();
            $result[$key]["payers"] = formatNumber($result[$key]["payers"]);
        }
        $pagecount = Db::name("forum_posts")
            ->alias("p")
            ->join("user u", "u.id=p.userid")
            ->join("forum_section s", "s.id=p.section_id")
            ->join("forum_section sub", "sub.id=p.sub_section_id")
            ->field("p.*,u.username,u.nickname,u.usertx,u.title as usertitle,u.sex,u.signature,s.section_name,s.section_icon,sub.section_name as sub_section_name")
            ->where("p.appid", $this->appid)
            ->where("p.status", 0)
            ->where("p.section_id", "in", $section_arr)
            ->order("p.create_time", "asc")
            ->count();
        $data_rs["list"] = $result;
        $data_rs["pagecount"] = ceil($pagecount / $this->limit) == 0 ? 1 : ceil($pagecount / $this->limit);
        $data_rs["current_number"] = $this->page;
        $this->json(1, "success", $data_rs);
    }

    //置顶/热门/帖子状态修改
    public function post_status_modification()
    {
        $data = input();
        $rule = [
            'usertoken|用户token' => 'require',
            'postid|帖子ID' => 'require|number',
            'type|类型' => 'require|number',
            'status|状态' => 'require|number',
        ];
        $validate = new Validate();
        $validate->rule($rule);
        $result = $validate->check($data);
        if (!$result) {
            $this->json(0, $validate->getError());
        }
        //判断type 只能为 1置顶2热门3帖子状态4精华
        if (!in_array($data["type"], [1, 2, 3, 4])) {
            $this->json(0, "type参数错误");
        }
        //判断status 只能为状态值 当type为1时（0不置顶1置顶）当type为2时（0普通1热门）当type为3时（0正常1文章锁定）当type为4时（0不是1是精华）
        if (!in_array($data["status"], [0, 1])) {
            $this->json(0, "status参数错误");
        }
        $user_all_info = $this->user_info;
        $postsinfo = Db::name("forum_posts")->where("appid", $this->appid)->where("id", $data["postid"])->find();
        if (!$postsinfo) {
            $this->json(0, "帖子不存在");
        }
        //获取版块管理员
        $sectioninfo = Db::name("forum_section")->where("id", $postsinfo["section_id"])->find();
        if (!$sectioninfo) {
            $this->json(0, "版块不存在");
        }
        $section_admin = array_filter(explode(",", $sectioninfo["forum_section"]));
        if (!in_array($user_all_info["id"], $section_admin)) {
            $this->json(0, "您不是版块管理员");
        }
        //修改帖子状态
        if ($data["type"] == 1) {
            Db::name("forum_posts")->where("id", $data["postid"])->update(["sticky" => $data["status"]]);
        } elseif ($data["type"] == 2) {
            Db::name("forum_posts")->where("id", $data["postid"])->update(["popular" => $data["status"]]);
        } elseif ($data["type"] == 3) {
            if ($data["status"] == 0) {
                $data["status"] = 1;
            } else {
                $data["status"] = 3;
            }
            Db::name("forum_posts")->where("id", $data["postid"])->update(["status" => $data["status"]]);
        } else {
            Db::name("forum_posts")->where("id", $data["postid"])->update(["featured" => $data["status"]]);
        }
        $this->json(1, "修改成功");
    }

    //对需要支付的帖子进行支付
    public function pay_post()
    {
        $data = input();
        $rule = [
            'postid|帖子id' => 'require|number',
            'usertoken|用户token' => 'require',
            'type|类型' => 'require|number', //0帖子付费支付 1附件付费下载支付
        ];
        $validate = new Validate();
        $validate->rule($rule);
        $result = $validate->check($data);
        if (!$result) {
            $this->json(0, $validate->getError());
        }
        //判断payment是否合法
        if (!in_array($data["type"], [0, 1])) {
            $this->json(0, "类型不合法");
        }
        //判断用户是否登录
        $user_all_info = $this->user_info;
        //判断帖子是否存在
        $posts_info = Db::name("forum_posts")->where("id", $data["postid"])->where("appid", $this->appid)->find();
        if (!$posts_info) {
            $this->json(0, "不存在此文章");
        }
        if ($posts_info["status"] != 1) {
            $this->json(0, "该文章暂未通过审核，请稍后重试！");
        }
        //判断帖子是否是付费阅读
        if ($data["type"] == 0) {
            if ($posts_info["paid_reading"] == 0 || $posts_info["paid_reading"] == 1) {
                $this->json(0, "该帖子不是付费阅读");
            }
            //判断用户是否购买过该帖子
            $is_buy = Db::name("post_payment")
                ->where("postid", $data["postid"])
                ->where("userid", $user_all_info["id"])
                ->where("type", 0)
                ->find();
            if ($is_buy) {
                $this->json(0, "您已经购买过该帖子,无需重复购买");
            }
            //判断用户是否是作者
            if ($posts_info["userid"] == $user_all_info["id"]) {
                $this->json(0, "您是作者,无需购买");
            }
            //判断金额是否足够并扣除用户余额
            if ($posts_info["paid_reading"] == 2) {
                //余额
                $this->assertAssetBalance($user_all_info, "money", $posts_info["reading_price"]);
                //扣除用户余额
                $user_all_info["money"] = $user_all_info["money"] - $posts_info["reading_price"];
                Db::name("user")->where("id", $user_all_info["id"])->update(["money" => $user_all_info["money"]]);
                add_user_bill($user_all_info, 4, "-" . $posts_info["reading_price"], "购买" . $posts_info["title"] . "文章内容", 0);
                //增加用户金币
                Db::name("user")->where("id", $posts_info["userid"])->setInc("money", $posts_info["reading_price"]);
                add_user_bill(["id" => $posts_info["userid"], "appid" => $user_all_info["appid"]], 4, "+" . $posts_info["reading_price"], "被购买" . $posts_info["title"] . "文章内容", 0);
            } elseif ($posts_info["paid_reading"] == 3) {
                //积分
                $this->assertAssetBalance($user_all_info, "integral", $posts_info["reading_price"]);
                //扣除用户积分
                $user_all_info["integral"] = $user_all_info["integral"] - $posts_info["reading_price"];
                Db::name("user")->where("id", $user_all_info["id"])->update(["integral" => $user_all_info["integral"]]);
                add_user_bill($user_all_info, 4, "-" . $posts_info["reading_price"], "购买" . $posts_info["title"] . "文章内容", 1);
                //增加用户积分
                Db::name("user")->where("id", $posts_info["userid"])->setInc("integral", $posts_info["reading_price"]);
                add_user_bill(["id" => $posts_info["userid"], "appid" => $user_all_info["appid"]], 4, "+" . $posts_info["reading_price"], "被购买" . $posts_info["title"] . "文章内容", 1);
            } else {
                $this->json(0, "该帖子的付费阅读方式不合法");
            }
            //添加付费记录
            $adddata = [
                "appid" => $this->appid,
                "amount" => $posts_info["reading_price"],
                "userid" => $user_all_info["id"],
                "postid" => $data["postid"],
                "type" => 0,
                "create_time" => date("Y-m-d H:i:s", time()),
                "payment" => $posts_info["reading_price"] == 2 ? 0 : 1,
            ];
            Db::name("post_payment")->insert($adddata);
            // 发送通知
            $addmessagedata = [
                "title" => "购买帖子内容通知",
                "content" => "您的帖子《" . $posts_info["title"] . "》被" . $user_all_info["nickname"] . "购买了文章内容",
                "send_to" => 0,
                "appid" => $posts_info["appid"],
                "time" => date("Y-m-d H:i:s", time()),
                "type" => 8,
                "user_id" => $posts_info["userid"],
                "postid" => $posts_info["id"],
            ];
            Db::name("message_notification")->insert($addmessagedata);
            $this->json();
        }
        //判断该帖子的附件下载是否为付费下载
        if ($data["type"] == 1) {
            if ($posts_info["file_download_method"] == 0 || $posts_info["file_download_method"] == 1) {
                $this->json(0, "该帖子的附件下载不是付费下载");
            }
            //判断用户是否购买过该帖子的附件
            $is_buy = Db::name("post_payment")
                ->where("postid", $data["postid"])
                ->where("userid", $user_all_info["id"])
                ->where("type", 1)
                ->find();
            if ($is_buy) {
                $this->json(0, "您已经购买过该帖子的附件,无需重复购买");
            }
            //判断用户是否是作者
            if ($posts_info["userid"] == $user_all_info["id"]) {
                $this->json(0, "您是作者,无需购买");
            }
            //判断金额是否足够并扣除用户余额
            if ($posts_info["file_download_method"] == 2) {
                //余额
                $this->assertAssetBalance($user_all_info, "money", $posts_info["file_download_price"]);
                //扣除用户余额
                $user_all_info["money"] = $user_all_info["money"] - $posts_info["file_download_price"];
                Db::name("user")->where("id", $user_all_info["id"])->update(["money" => $user_all_info["money"]]);
                add_user_bill($user_all_info, 5, "-" . $posts_info["reading_price"], "购买" . $posts_info["title"] . "附件下载内容", 0);
                //增加用户金币
                Db::name("user")->where("id", $posts_info["userid"])->setInc("money", $posts_info["file_download_price"]);
                add_user_bill(["id" => $posts_info["userid"], "appid" => $user_all_info["appid"]], 5, "+" . $posts_info["file_download_price"], "被购买" . $posts_info["title"] . "附件下载内容", 0);
            } elseif ($posts_info["file_download_method"] == 3) {
                //积分
                $this->assertAssetBalance($user_all_info, "integral", $posts_info["file_download_price"]);
                //扣除用户积分
                $user_all_info["integral"] = $user_all_info["integral"] - $posts_info["file_download_price"];
                Db::name("user")->where("id", $user_all_info["id"])->update(["integral" => $user_all_info["integral"]]);
                add_user_bill($user_all_info, 5, "-" . $posts_info["reading_price"], "购买" . $posts_info["title"] . "附件下载内容", 1);
                //增加用户积分
                Db::name("user")->where("id", $posts_info["userid"])->setInc("integral", $posts_info["file_download_price"]);
                add_user_bill(["id" => $posts_info["userid"], "appid" => $user_all_info["appid"]], 5, "+" . $posts_info["file_download_price"], "被购买" . $posts_info["title"] . "附件下载内容", 1);
            } else {
                $this->json(0, "该帖子的附件下载方式不合法");
            }
            //添加付费记录
            $adddata = [
                "appid" => $this->appid,
                "amount" => $posts_info["file_download_price"],
                "userid" => $user_all_info["id"],
                "postid" => $data["postid"],
                "type" => 1,
                "create_time" => date("Y-m-d H:i:s", time()),
                "payment" => $posts_info["reading_price"] == 2 ? 0 : 1,
            ];
            Db::name("post_payment")->insert($adddata);
            // 发送通知
            $addmessagedata = [
                "title" => "购买附件通知",
                "content" => "您的帖子《" . $posts_info["title"] . "》被" . $user_all_info["nickname"] . "购买了附件下载内容",
                "send_to" => 0,
                "appid" => $posts_info["appid"],
                "time" => date("Y-m-d H:i:s", time()),
                "type" => 8,
                "user_id" => $posts_info["userid"],
                "postid" => $posts_info["id"],
            ];
            Db::name("message_notification")->insert($addmessagedata);
            $this->json();
        }
    }

    //打赏帖子
    public function reward_posts()
    {
        $data = input();
        $rule = [
            'postid|帖子id' => 'require|number',
            'usertoken|用户token' => 'require',
            'payment|打赏方式' => 'require|number', //0余额 1积分
            'money|金额' => 'require|number',
        ];
        $validate = new Validate();
        $validate->rule($rule);
        $result = $validate->check($data);
        if (!$result) {
            $this->json(0, $validate->getError());
        }
        //判断payment是否合法
        if (!in_array($data["payment"], [0, 1])) {
            $this->json(0, "打赏方式不合法");
        }
        if ($data["money"] == 0) {
            $this->json(0, "打赏金额不能为0");
        }
        //判断用户是否登录
        $user_all_info = $this->user_info;
        //判断帖子是否存在
        $posts_info = Db::name("forum_posts")->where("appid", $this->appid)->where("id", $data["postid"])->find();
        if (!$posts_info) {
            $this->json(0, "帖子不存在");
        }
        if ($posts_info["status"] != 1) {
            $this->json(0, "该文章暂未通过审核，无法打赏！");
        }
        //不能打赏自己的帖子
        if ($posts_info["userid"] == $user_all_info["id"]) {
            $this->json(0, "不能打赏自己的帖子");
        }
        //查询用户是否已经打赏过该帖子
        $is_reward = Db::name("post_payment")->where("postid", $data["postid"])->where("userid", $user_all_info["id"])->where("type", 2)->find();
        if ($is_reward) {
            if ($this->app_info["forum_configuration"]["post_tipping_time_limit"] != 0) {
                if (time() - strtotime($is_reward["create_time"]) < $this->app_info["forum_configuration"]["post_tipping_time_limit"]) {
                    $this->json(0, "您已经打赏过该帖子,请稍后再试");
                }
            }
        }
        //判断打赏金额是否足够并扣除用户余额
        if ($data["payment"] == 0) {
            //余额
            $this->assertAssetBalance($user_all_info, "money", $data["money"]);
            //扣除用户余额
            $user_all_info["money"] = $user_all_info["money"] - $data["money"];
            Db::name("user")->where("id", $user_all_info["id"])->update(["money" => $user_all_info["money"]]);
            add_user_bill($user_all_info, 6, "-" . $data["money"], "打赏" . $posts_info["title"] . "文章", 0);
            //增加用户金币
            Db::name("user")->where("id", $posts_info["userid"])->setInc("money", $data["money"]);
            $post_userinfo = [
                "id" => $posts_info["userid"],
                "appid" => $this->appid,
            ];
            add_user_bill($post_userinfo, 6, "+" . $data["money"], "被打赏" . $posts_info["title"] . "文章", 0);
            $content_payment = "金币 " . $data["money"];
        } else {
            //积分
            $this->assertAssetBalance($user_all_info, "integral", $data["money"]);
            //扣除用户积分
            $user_all_info["integral"] = $user_all_info["integral"] - $data["money"];
            Db::name("user")->where("id", $user_all_info["id"])->update(["integral" => $user_all_info["integral"]]);
            add_user_bill($user_all_info, 6, "-" . $data["money"], "打赏" . $posts_info["title"] . "文章", 1);
            //增加用户积分
            Db::name("user")->where("id", $posts_info["userid"])->setInc("integral", $data["money"]);
            add_user_bill($user_all_info, 6, "+" . $data["money"], "被打赏" . $posts_info["title"] . "文章", 1);
            $content_payment = "积分 " . $data["money"];
        }
        //添加打赏通知
        $content = [
            "appid" => $this->appid,
            "content" => "您的帖子《" . $posts_info["title"] . "》被" . $user_all_info["nickname"] . "打赏了" . $content_payment,
            "postid" => $data["postid"],
        ];
        increase_system_notifications_to_users("打赏通知", $content, $posts_info["userid"], 6);
        //添加打赏记录
        $adddata = [
            "appid" => $this->appid,
            "amount" => $data["money"],
            "userid" => $user_all_info["id"],
            "postid" => $data["postid"],
            "type" => 2,
            "create_time" => date("Y-m-d H:i:s", time()),
            "payment" => $data["payment"],
        ];
        Db::name("post_payment")->insert($adddata);
        $this->json(1, "打赏成功");
    }

    //获取消息通知
    public function get_message_notifications()
    {
        $data = input();
        $rule = [
            'usertoken|用户token' => 'require',
            'type|类型' => 'number',
        ];
        $validate = new Validate();
        $validate->rule($rule);
        $result = $validate->check($data);
        if (!$result) {
            $this->json(0, $validate->getError());
        }
        $user_all_info = $this->user_info;
        //查询用户的消息通知和管理员发送的消息通知
        $where = "m.appid = {$this->appid} and (m.user_id = {$user_all_info["id"]} or (m.send_to=0 and m.user_id=0))";
        if (input("type") != "") {
            $where .= " and m.type = {$data["type"]}";
        }
        $result = Db::name("message_notification")
            ->alias("m")
            ->leftJoin("user u", "u.id=m.user_id")
            ->field("m.*")
            ->where($where)
            ->order("m.time", "desc")
            ->limit($this->limit)
            ->page($this->page)
            ->select()->toArray();
        //修改消息通知为已读
        foreach ($result as $key => $value) {
            if ($value["status"] == 0) {
                Db::name("message_notification")->where("id", $value["id"])->update(["status" => 1]);
            }
        }
        $pagecount = Db::name("message_notification")
            ->alias("m")
            ->leftJoin("user u", "u.id=m.user_id")
            ->where($where)
            ->where("m.appid = {$this->appid} and (m.user_id = {$user_all_info["id"]} or m.send_to=0)")
            ->order("m.time", "desc")
            ->count();
        $data_rs["list"] = $result;
        $data_rs["pagecount"] = ceil($pagecount / $this->limit) == 0 ? 1 : ceil($pagecount / $this->limit);
        $data_rs["current_number"] = $this->page;
        $this->json(1, "success", $data_rs);
    }

    //一键清除消息通知
    public function clear_message_notification()
    {
        $data = input();
        $rule = [
            'usertoken|用户token' => 'require',
            'type|类型' => 'number',
        ];
        $validate = new Validate();
        $validate->rule($rule);
        $result = $validate->check($data);
        if (!$result) {
            $this->json(0, $validate->getError());
        }
        $user_all_info = $this->user_info;
        //查询用户的消息通知和管理员发送的消息通知
        $where = "m.appid = {$this->appid} and (m.user_id = {$user_all_info["id"]} or (m.send_to=0 and m.user_id=0))";
        if (input("type") != "") {
            $where .= " and m.type = {$data["type"]}";
        }
        $result = Db::name("message_notification")
            ->alias("m")
            ->leftJoin("user u", "u.id=m.user_id")
            ->field("m.*")
            ->where($where)
            ->select()->toArray();
        foreach ($result as $key => $value) {
            if ($value["status"] == 0) {
                Db::name("message_notification")->where("id", $value["id"])->update(["status" => 1]);
            }
        }
        $this->json(1, "success", []);
    }

    //获取未读消息通知数量
    public function get_unread_message_notifications()
    {
        $data = input();
        $rule = [
            'usertoken|用户token' => 'require',
            'type|类型' => 'number',
        ];
        $validate = new Validate();
        $validate->rule($rule);
        $result = $validate->check($data);
        if (!$result) {
            $this->json(0, $validate->getError());
        }
        $user_all_info = $this->user_info;
        //查询用户的消息通知和管理员发送的消息通知
        $where = "m.status = 0 and m.appid = {$this->appid} and (m.user_id = {$user_all_info["id"]} or (m.send_to=0 and m.user_id=0))";
        if (input("type") != "") {
            $where .= " and m.type = {$data["type"]}";
        }
        $result = Db::name("message_notification")
            ->alias("m")
            ->leftJoin("user u", "u.id=m.user_id")
            ->field("m.*")
            ->where($where)
            ->count();
        $this->json(1, "success", ["count" => $result]);
    }

    //发送邮件
    public function send_email()
    {
        $data = input();
        $rule = [
            'email|邮箱' => 'require|email',
            'title|标题' => 'require',
            'content|内容' => 'require',
            'appkey|appkey' => 'require',
        ];
        $validate = new Validate();
        $validate->rule($rule);
        $result = $validate->check($data);
        if (!$result) {
            $this->json(0, $validate->getError());
        }
        if ($this->app_info["appkey"] != $data["appkey"]) {
            $this->json(0, "appkey错误");
        }
        try {
            $mail = new Email($data["email"]);
            $mail->setFrom($this->app_info["appname"]);
            $mail->setSubject($data["title"]);
            $mail->setBody($data["content"]);
            $mail->send();
            $this->json(1, "发送成功");
        } catch (\Exception $e) {
            $this->json(0, $e->getMessage());
        }
    }

    //获取用户笔记
    public function get_notes_list()
    {
        $data = input();
        $rule = [
            'usertoken|用户token' => 'require',
        ];
        $validate = new Validate();
        $validate->rule($rule);
        $result = $validate->check($data);
        if (!$result) {
            $this->json(0, $validate->getError());
        }
        $user_all_info = $this->user_info;
        $result = Db::name("notes")
            ->alias("n")
            ->join("user u", "n.userid=u.id")
            ->join("app a", "n.appid=a.appid")
            ->field("n.*,u.username,a.appname")
            ->order("n.update_time", "desc")
            ->where("n.userid", $user_all_info["id"])
            ->limit($this->limit)
            ->page($this->page)
            ->select()->toArray();
        $pagecount = Db::name("notes")
            ->alias("n")
            ->join("user u", "n.userid=u.id")
            ->join("app a", "n.appid=a.appid")
            ->field("n.*,u.username,a.appname")
            ->order("n.update_time", "desc")
            ->where("n.userid", $user_all_info["id"])
            ->count();
        $ip = new IpLocation();
        foreach ($result as $key => $value) {
            //截取内容
            $result[$key]["ip_address"] = $value["ip"] == "" ? "" : $ip->getDetail($value["ip"])["dataA"];
            $result[$key]["content"] = mb_substr(strip_tags($value["content"]), 0, 50, "utf-8") . "...";
            unset($result[$key]["ip"]);
        }
        $data_rs["list"] = $result;
        $data_rs["pagecount"] = ceil($pagecount / $this->limit) == 0 ? 1 : ceil($pagecount / $this->limit);
        $data_rs["current_number"] = $this->page;
        $this->json(1, "success", $data_rs);
    }

    //获取用户笔记详情
    public function get_notes_details()
    {
        $data = input();
        $rule = [
            'notesid|笔记id' => 'require|number',
            'usertoken|用户token' => 'require',
        ];
        $validate = new Validate();
        $validate->rule($rule);
        $result = $validate->check($data);
        if (!$result) {
            $this->json(0, $validate->getError());
        }
        $user_all_info = $this->user_info;
        $notes_info = Db::name("notes")->where("id", $data["notesid"])->field("id,title,content,create_time,update_time,userid")->find();
        if (!$notes_info) {
            $this->json(0, "不存在此笔记");
        }
        if ($notes_info["userid"] != $user_all_info["id"]) {
            $this->json(0, "无权查看此笔记");
        }
        unset($notes_info["userid"]);
        $this->json(1, "success", $notes_info);
    }

    //修改笔记
    public function update_notes()
    {
        $data = input();
        $rule = [
            'notesid|笔记id' => 'require|number',
            'usertoken|用户token' => 'require',
            'title|笔记标题' => 'require',
            'content|笔记内容' => 'require',
        ];
        $validate = new Validate();
        $validate->rule($rule);
        $result = $validate->check($data);
        if (!$result) {
            $this->json(0, $validate->getError());
        }
        $user_all_info = $this->user_info;
        //查询笔记是否存在
        $notes_info = Db::name("notes")->where("id", $data["notesid"])->find();
        if (!$notes_info) {
            $this->json(0, "不存在此笔记");
        }
        if ($notes_info["userid"] != $user_all_info["id"]) {
            $this->json(0, "无权修改此笔记");
        }
        $update_data = [
            "title" => $data["title"],
            "content" => $data["content"],
            "update_time" => date("Y-m-d H:i:s", time()),
        ];
        Db::name("notes")->where("id", $data["notesid"])->update($update_data);
        $this->json(1, "修改成功");
    }

    //删除笔记
    public function delete_notes()
    {
        $data = input();
        $rule = [
            'notesid|笔记id' => 'require|number',
            'usertoken|用户token' => 'require',
        ];
        $validate = new Validate();
        $validate->rule($rule);
        $result = $validate->check($data);
        if (!$result) {
            $this->json(0, $validate->getError());
        }
        $user_all_info = $this->user_info;
        $notes_info = Db::name("notes")->where("id", $data["notesid"])->field("id,title,content,create_time,update_time,userid")->find();
        if (!$notes_info) {
            $this->json(0, "不存在此笔记");
        }
        if ($notes_info["userid"] != $user_all_info["id"]) {
            $this->json(0, "无权删除此笔记");
        }
        Db::name("notes")->where("id", $data["notesid"])->delete();
        $this->json(1, "删除成功", []);
    }

    //添加笔记
    public function add_notes()
    {
        $data = input();
        $rule = [
            'usertoken|用户token' => 'require',
            'title|笔记标题' => 'require',
            'content|笔记内容' => 'require',
        ];
        $validate = new Validate();
        $validate->rule($rule);
        $result = $validate->check($data);
        if (!$result) {
            $this->json(0, $validate->getError());
        }
        $user_all_info = $this->user_info;
        $add_data = [
            "userid" => $user_all_info["id"],
            "title" => $data["title"],
            "content" => $data["content"],
            "ip" => get_client_ip(),
            "appid" => $this->appid,
            "create_time" => date("Y-m-d H:i:s", time()),
            "update_time" => date("Y-m-d H:i:s", time()),
        ];
        Db::name("notes")->insert($add_data);
        $this->json(1, "添加成功");
    }

    //发送私聊消息、转账、红包
    public function im_person_send()
    {
        $this->chatRequestContext();
        $data = $this->secureChatInput(input());
        $rule = [
            'usertoken|用户token' => 'require',
            'receiver_id|接收者用户ID' => 'require|number',
            'client_msg_no|客户端消息号' => 'require',
        ];
        $validate = new Validate();
        $validate->rule($rule);
        $result = $validate->check($data);
        if (!$result) {
            $this->json(0, $validate->getError());
        }
        $user_all_info = $this->user_info;
        $receiver_info = Db::name("user")->where("id", $data["receiver_id"])->where("appid", $this->appid)->find();
        if (!$receiver_info) {
            $this->json(0, "用户不存在！");
        }
        if ((int)$receiver_info["id"] === (int)$user_all_info["id"]) {
            $this->json(0, "不能给自己发送消息");
        }

        $contentType = $this->normalizeIncomingChatContentType($data);
        $im = new WukongIM();
        $payload = [];
        $clientMsgNo = trim((string)$data["client_msg_no"]);
        $chatControl = $this->chatControl();
        if ($this->hasChatMentionInput()) {
            $this->json(0, "@功能仅支持群聊文本消息");
        }
        if ($this->hasReplyInput() && $contentType !== "text") {
            $this->json(0, "消息引用仅支持文本消息");
        }
        try {
            $this->assertPersonChatAllowed($user_all_info, $receiver_info, $clientMsgNo, $contentType);
        } catch (\Exception $e) {
            $this->json(0, $e->getMessage());
        }

        if (in_array($contentType, $this->chatMessageContentTypes(), true)) {
            $payload = $this->baseWukongMessagePayload($user_all_info, $receiver_info, $contentType);
            if ($contentType === "contact_card") {
                $payload = array_merge($payload, $this->normalizeContactCardPayload());
            } else {
                $payload = array_merge($payload, $this->normalizeChatMediaPayload($contentType, $user_all_info));
                if ($contentType === "text") {
                    $this->appendPersonReplyPayload($payload, $user_all_info, $receiver_info, $contentType);
                }
                $this->appendBurnAfterReadPayload($payload, $chatControl, false);
            }
            try {
                $sendResult = $im->sendPersonMessage($this->wukongUid($user_all_info["id"]), $this->wukongUid($receiver_info["id"]), $payload, $clientMsgNo);
            } catch (\Exception $e) {
                $this->json(0, $e->getMessage());
            }
            $this->chatJson(1, "success", $this->chatSendResponse($sendResult, $clientMsgNo, $payload));
        }

        if ($contentType === "transfer") {
            $rule = [
                'money|转账金额' => 'require',
                'asset_type|资产类型' => 'require|in:money,integral',
                'pay_password|支付密码' => 'require',
            ];
            $validate = new Validate();
            $validate->rule($rule);
            $result = $validate->check($data);
            if (!$result) {
                $this->json(0, $validate->getError());
            }
            try {
                $amount = $this->normalizeChatAssetAmount($data["money"], (string)$data["asset_type"]);
                $this->verifyWalletPayPassword((int)$user_all_info["id"], trim((string)($data["pay_password"] ?? "")));
            } catch (\Exception $e) {
                $this->json(0, $e->getMessage());
            }
            $payload = $this->baseWukongMessagePayload($user_all_info, $receiver_info, "transfer");
            Db::startTrans();
            try {
                $reserved = $im->reservePersonMessage($this->wukongUid($user_all_info["id"]), $this->wukongUid($receiver_info["id"]), $clientMsgNo, [
                    "content_type" => "transfer",
                    "content" => $amount,
                    "asset_type" => (string)$data["asset_type"],
                    "transfer" => [
                        "amount" => $amount,
                        "amount_label" => $this->chatAssetAmountLabel($amount, (string)$data["asset_type"]),
                        "asset_type" => (string)$data["asset_type"],
                        "receiver_id" => (int)$receiver_info["id"],
                        "group_id" => 0,
                    ],
                ]);
                if (!empty($reserved["duplicate"])) {
                    Db::commit();
                    $this->chatJson(1, "success", $this->chatSendResponse($reserved, $clientMsgNo, []));
                }
                $transfer = $this->createPersonTransfer($user_all_info, $receiver_info, $amount, (string)$data["asset_type"], $clientMsgNo);
                $payload["content"] = (string)$transfer["amount"];
                $payload["image_path"] = "";
                $payload["asset_type"] = (string)$transfer["asset_type"];
                $payload["transfer"] = $transfer;
                $sendResult = $im->sendPersonMessage($this->wukongUid($user_all_info["id"]), $this->wukongUid($receiver_info["id"]), $payload, $clientMsgNo);
                Db::name("wukongim_transfer")->where("id", $transfer["transfer_id"])->update([
                    "message_id" => (string)($sendResult["message_id"] ?? ""),
                    "update_time" => date("Y-m-d H:i:s"),
                ]);
                Db::commit();
            } catch (\Exception $e) {
                Db::rollback();
                $this->json(0, $e->getMessage());
            }
            $this->chatJson(1, "success", $this->chatSendResponse($sendResult, $clientMsgNo, $payload));
        }

        if ($contentType === "red_packet") {
            $rule = [
                'money|红包金额' => 'require',
                'asset_type|资产类型' => 'require|in:money,integral',
                'pay_password|支付密码' => 'require',
            ];
            $validate = new Validate();
            $validate->rule($rule);
            $result = $validate->check($data);
            if (!$result) {
                $this->json(0, $validate->getError());
            }
            try {
                $amount = $this->normalizeChatAssetAmount($data["money"], (string)$data["asset_type"]);
                $this->verifyWalletPayPassword((int)$user_all_info["id"], trim((string)($data["pay_password"] ?? "")));
            } catch (\Exception $e) {
                $this->json(0, $e->getMessage());
            }
            $remark = trim((string)($data["remark"] ?? "恭喜发财"));
            $payload = $this->baseWukongMessagePayload($user_all_info, $receiver_info, "red_packet");
            Db::startTrans();
            try {
                $reserved = $im->reservePersonMessage($this->wukongUid($user_all_info["id"]), $this->wukongUid($receiver_info["id"]), $clientMsgNo, [
                    "content_type" => "red_packet",
                    "content" => $remark,
                    "asset_type" => (string)$data["asset_type"],
                    "red_packet" => [
                        "amount" => $amount,
                        "amount_label" => $this->chatAssetAmountLabel($amount, (string)$data["asset_type"]),
                        "asset_type" => (string)$data["asset_type"],
                        "remark" => $remark,
                        "quantity" => 1,
                        "packet_type" => "ordinary",
                        "receiver_id" => (int)$receiver_info["id"],
                    ],
                ]);
                if (!empty($reserved["duplicate"])) {
                    Db::commit();
                    $this->chatJson(1, "success", $this->chatSendResponse($reserved, $clientMsgNo, []));
                }
                $redPacket = $this->createPersonRedPacket($user_all_info, $receiver_info, $amount, (string)$data["asset_type"], $remark);
                $payload["content"] = $remark;
                $payload["image_path"] = "";
                $payload["asset_type"] = (string)$redPacket["asset_type"];
                $payload["red_packet"] = $redPacket;
                $sendResult = $im->sendPersonMessage($this->wukongUid($user_all_info["id"]), $this->wukongUid($receiver_info["id"]), $payload, $clientMsgNo);
                Db::name("wukongim_red_packet")->where("id", $redPacket["red_packet_id"])->update([
                    "client_msg_no" => $sendResult["client_msg_no"] ?? $clientMsgNo,
                    "message_id" => (string)($sendResult["message_id"] ?? ""),
                    "update_time" => date("Y-m-d H:i:s"),
                ]);
                Db::commit();
            } catch (\Exception $e) {
                Db::rollback();
                $this->json(0, $e->getMessage());
            }
            $this->chatJson(1, "success", $this->chatSendResponse($sendResult, $clientMsgNo, $payload));
        }

        $this->json(0, "content_type不合法");
    }

    //聊天会话列表
    public function im_conversations()
    {
        $data = $this->secureChatRequestInput();
        $rule = [
            'usertoken|用户token' => 'require',
        ];
        $validate = new Validate();
        $validate->rule($rule);
        $result = $validate->check($data);
        if (!$result) {
            $this->json(0, $validate->getError());
        }
        $user_all_info = $this->user_info;
        $privateHistorySync = $this->privateHistorySyncEnabled();
        $groupHistorySync = $this->groupHistorySyncEnabled();
        $requestLimit = max(1, (int)$this->limit);
        $conversationLimit = max($requestLimit, 200);
        try {
            $this->clearCurrentUserGroupMuteBlacklists();
            $list = (new WukongIM())->syncConversations($this->wukongUid($user_all_info["id"]), (int)$this->page, $conversationLimit, 5);
        } catch (\Exception $e) {
            $this->json(0, $e->getMessage());
        }

        $result = [];
        foreach ($list as $conversation) {
            $channelType = (int)($conversation["channel_type"] ?? WukongIM::CHANNEL_TYPE_PERSON);
            $conversationChannelId = (string)($conversation["channel_id"] ?? "");
            $recents = (array)($conversation["recents"] ?? []);
            $unread = (int)($conversation["unread"] ?? 0);
            $clientChannelId = $conversationChannelId;
            if ($channelType === (int)config('wukongim.channel_type_group', WukongIM::CHANNEL_TYPE_GROUP)) {
                if (!$groupHistorySync && $unread <= 0) {
                    continue;
                }
            } else {
                $clientChannelId = $this->privateConversationPeerUid($this->wukongUid($user_all_info["id"]), $conversationChannelId, $recents);
                if ($clientChannelId === "") {
                    continue;
                }
                if (!$privateHistorySync && $unread <= 0) {
                    continue;
                }
            }
            $hiddenClientMsgNos = $this->hiddenChatClientMsgNos((int)$user_all_info["id"], $clientChannelId, $channelType, $recents);
            $clearBoundary = $this->chatClearBoundaryTimestamp((int)$user_all_info["id"], $clientChannelId, $channelType);
            $recent = [];
            $message = $recent ? $this->wukongPayloadToMessage($recent) : [
                "create_time" => "",
                "content" => "",
                "image_path" => "",
                "content_type" => "",
                "asset_type" => "",
                "payload" => [],
            ];
            if ($channelType === (int)config('wukongim.channel_type_group', WukongIM::CHANNEL_TYPE_GROUP)) {
                $group = Db::name("chat_group")
                    ->where("appid", $this->appid)
                    ->where("channel_id", $conversationChannelId)
                    ->where("status", 1)
                    ->find();
                if (!$group) {
                    continue;
                }
                $member = Db::name("chat_group_member")
                    ->where("appid", $this->appid)
                    ->where("group_id", $group["id"])
                    ->where("user_id", $user_all_info["id"])
                    ->where("status", 1)
                    ->find();
                if (!$member) {
                    continue;
                }
                foreach ($recents as $candidate) {
                    if (!is_array($candidate) || !$this->isDisplayableWukongChatMessage($candidate)) {
                        continue;
                    }
                    $candidateData = $this->wukongPayloadToMessage($candidate);
                    if (
                        $this->isGroupMessageVisibleForMember($member, $candidate, $candidateData)
                        && $this->isChatMessageVisibleForUser((int)$user_all_info["id"], $conversationChannelId, $channelType, $candidate, $candidateData, $hiddenClientMsgNos, $clearBoundary)
                    ) {
                        $recent = $candidate;
                        $message = $candidateData;
                        break;
                    }
                }
                if (!$recent) {
                    continue;
                }
                $item = $this->formatChatGroup($group);
                $item["conversation_type"] = "group";
            } else {
                foreach ($recents as $candidate) {
                    if (is_array($candidate) && $this->isDisplayableWukongChatMessage($candidate)) {
                        $candidateData = $this->wukongPayloadToMessage($candidate);
                        if (!$this->isChatMessageVisibleForUser((int)$user_all_info["id"], $clientChannelId, $channelType, $candidate, $candidateData, $hiddenClientMsgNos, $clearBoundary)) {
                            continue;
                        }
                        $recent = $candidate;
                        $message = $candidateData;
                        break;
                    }
                }
                if (!$recent) {
                    continue;
                }
                $uidInfo = WukongIM::parseUid($clientChannelId);
                if (!$uidInfo || $uidInfo["appid"] !== (int)$this->appid) {
                    continue;
                }
                $user_info = Db::name("user")->where("id", $uidInfo["user_id"])->where("appid", $this->appid)->find();
                if (!$user_info) {
                    continue;
                }
                $item = $this->formatImUserProfile($user_info);
                $item["conversation_type"] = "private";
            }
            $item["msg_time"] = $message["create_time"];
            $item["content"] = $message["content"];
            $item["image_path"] = $message["image_path"];
            $item["content_type"] = $message["content_type"];
            $item["asset_type"] = $message["asset_type"];
            $item["payload"] = $message["payload"];
            $item["unread_quantity"] = $unread;
            $item["channel_id"] = $clientChannelId;
            $item["raw_channel_id"] = $conversationChannelId;
            $item["channel_type"] = $channelType;
            if ($item["conversation_type"] === "private") {
                $item["peer_uid"] = $clientChannelId;
                $item["receiver_id"] = (int)($uidInfo["user_id"] ?? 0);
            }
            $item["last_msg_seq"] = (int)($conversation["last_msg_seq"] ?? 0);
            $item["last_client_msg_no"] = (string)($conversation["last_client_msg_no"] ?? "");
            $result[] = $item;
        }
        $result = $this->appendStoredMessageConversations($user_all_info, $result, $conversationLimit);
        $data_rs["list"] = $result;
        $data_rs["pagecount"] = count($result) < $conversationLimit ? (int)$this->page : (int)$this->page + 1;
        $data_rs["current_number"] = $this->page;
        $data_rs["history_sync"] = $this->historySyncPayload();
        $this->chatJson(1, "success", $data_rs);
    }

    //私聊聊天记录
    public function im_person_messages()
    {
        $data = $this->secureChatRequestInput();
        $rule = [
            'usertoken|用户token' => 'require',
            'receiver_id|对方用户ID' => 'require|number',
        ];
        $validate = new Validate();
        $validate->rule($rule);
        $result = $validate->check($data);
        if (!$result) {
            $this->json(0, $validate->getError());
        }
        $user_all_info = $this->user_info;
        $receiver_info = Db::name("user")->where("id", $data["receiver_id"])->where("appid", $this->appid)->find();
        if (!$receiver_info) {
            $this->json(0, "用户不存在！");
        }
        $unreadOnly = (int)($data["unread_only"] ?? 0) === 1;
        if (!$this->privateHistorySyncEnabled() && !$unreadOnly) {
            $data_rs = $this->emptyHistoryResponse();
            $data_rs["history_sync"] = $this->historySyncPayload();
            $this->chatJson(1, "success", $data_rs);
        }
        $im = new WukongIM();

        $users = [
            $this->wukongUid($user_all_info["id"]) => $user_all_info,
            $this->wukongUid($receiver_info["id"]) => $receiver_info,
        ];
        $result = [];
        $maxMessageSeq = 0;
        $channelId = $this->wukongUid($receiver_info["id"]);
        $channelType = (int)config('wukongim.channel_type_person', WukongIM::CHANNEL_TYPE_PERSON);
        $historyLimit = (int)$this->limit;
        if ($unreadOnly) {
            $historyLimit = min(200, max(1, (int)($data["unread_limit"] ?? $historyLimit)));
        }
        $history = $this->privateQueueHistoryPage(
            $user_all_info,
            $receiver_info,
            $historyLimit,
            (int)($data["start_message_seq"] ?? 0)
        );
        $messages = (array)$history["messages"];
        $nextStartMessageSeq = (int)$history["next_start_message_seq"];
        $hiddenClientMsgNos = $this->hiddenChatClientMsgNos((int)$user_all_info["id"], $channelId, $channelType, $messages);
        $clearBoundary = $this->chatClearBoundaryTimestamp((int)$user_all_info["id"], $channelId, $channelType);
        foreach ((array)$history["rows"] as $row) {
            $message = $this->queueRecordToWukongMessage($row);
            if (!$this->isDisplayableWukongChatMessage($message)) {
                continue;
            }
            $fromUid = (string)($message["from_uid"] ?? "");
            $fromUser = $users[$fromUid] ?? null;
            if (!$fromUser) {
                $uidInfo = WukongIM::parseUid($fromUid);
                if (!$uidInfo || $uidInfo["appid"] !== (int)$this->appid) {
                    continue;
                }
                $fromUser = Db::name("user")->where("id", $uidInfo["user_id"])->where("appid", $this->appid)->find();
                if (!$fromUser) {
                    continue;
                }
                $users[$fromUid] = $fromUser;
            }
            $messageData = $this->wukongPayloadToMessage($message);
            if (!$this->isChatMessageVisibleForUser((int)$user_all_info["id"], $channelId, $channelType, $message, $messageData, $hiddenClientMsgNos, $clearBoundary)) {
                continue;
            }
            $this->appendReceiptStatus($messageData);
            try {
                $this->recordMessageReadReceipt($row, $user_all_info, (int)($message['message_seq'] ?? 0), $im);
                $this->appendReceiptStatus($messageData);
            } catch (\Exception $e) {
                $this->json(0, $e->getMessage());
            }
            $result[] = [
                "fromUser" => $this->formatChatUser($fromUser),
                "message" => $messageData,
                "raw" => [
                    "message_id" => $message["message_id"] ?? "",
                    "message_idstr" => $message["message_idstr"] ?? "",
                    "client_msg_no" => $message["client_msg_no"] ?? "",
                    "message_seq" => $message["message_seq"] ?? 0,
                    "channel_id" => $message["channel_id"] ?? "",
                    "channel_type" => $message["channel_type"] ?? WukongIM::CHANNEL_TYPE_PERSON,
                ],
            ];
            $maxMessageSeq = max($maxMessageSeq, (int)($message["message_seq"] ?? 0));
        }
        $result = $this->sortChatHistoryResult($result, $historyLimit);

        if ($maxMessageSeq > 0) {
            try {
                $im->clearUnread($this->wukongUid($user_all_info["id"]), $this->wukongUid($receiver_info["id"]), $maxMessageSeq, (int)config('wukongim.channel_type_person', WukongIM::CHANNEL_TYPE_PERSON));
            } catch (\Exception $e) {
                $this->json(0, $e->getMessage());
            }
        }

        $data_rs["list"] = $result;
        $data_rs["pagecount"] = !empty($history["more"]) ? (int)$this->page + 1 : (int)$this->page;
        $data_rs["current_number"] = $this->page;
        $data_rs["more"] = (int)($history["more"] ?? 0);
        $data_rs["next_start_message_seq"] = $nextStartMessageSeq;
        $data_rs["raw_count"] = count($messages);
        $data_rs["history_sync"] = $this->historySyncPayload();
        $this->chatJson(1, "success", $data_rs);
    }

    //发送消息已读回执，记录消息状态并发送命令消息同步给对端
    public function im_message_read_receipt()
    {
        $this->json(0, '单条已读回执接口已关闭，请使用批量已读回执接口');
    }

    //批量发送消息已读回执。客户端进入会话后只能走本接口，避免历史消息逐条请求造成请求风暴。
    public function im_message_read_receipts()
    {
        $data = $this->secureChatRequestInput();
        $rule = [
            'usertoken|用户token' => 'require',
            'client_msg_no|客户端消息号' => 'require',
            'receipts|回执列表' => 'require',
        ];
        $validate = new Validate();
        $validate->rule($rule);
        if (!$validate->check($data)) {
            $this->json(0, $validate->getError());
        }
        $receipts = json_decode((string)$data['receipts'], true);
        if (!is_array($receipts)) {
            $this->json(0, '回执列表格式错误');
        }
        if (count($receipts) <= 0) {
            $this->json(0, '回执列表不能为空');
        }
        if (count($receipts) > 200) {
            $this->json(0, '单次最多上报200条回执');
        }

        $targets = [];
        $seen = [];
        foreach ($receipts as $item) {
            if (!is_array($item)) {
                $this->json(0, '回执项格式错误');
            }
            $targetClientMsgNo = trim((string)($item['target_client_msg_no'] ?? ''));
            if ($targetClientMsgNo === '') {
                $this->json(0, '目标客户端消息号不能为空');
            }
            if (isset($seen[$targetClientMsgNo])) {
                continue;
            }
            $seen[$targetClientMsgNo] = true;
            $targets[] = [
                'record' => $this->queueRecordByClientMsgNo($targetClientMsgNo),
                'message_seq' => (int)($item['message_seq'] ?? 0),
            ];
        }
        if (!$targets) {
            $this->json(0, '回执列表不能为空');
        }

        $im = new WukongIM();
        $result = [];
        $clearUnread = [];
        try {
            foreach ($targets as $target) {
                $record = $target['record'];
                $messageSeq = (int)$target['message_seq'];
                $status = $this->recordMessageReadReceipt($record, $this->user_info, $messageSeq, $im);
                $result[] = [
                    'target_client_msg_no' => (string)$record['client_msg_no'],
                    'receipt' => $status,
                ];
                if ($messageSeq > 0) {
                    $key = (int)$record['channel_type'] . ':' . (string)$record['channel_id'];
                    if (!isset($clearUnread[$key]) || $messageSeq > (int)$clearUnread[$key]['message_seq']) {
                        $clearUnread[$key] = [
                            'channel_id' => (string)$record['channel_id'],
                            'channel_type' => (int)$record['channel_type'],
                            'message_seq' => $messageSeq,
                        ];
                    }
                }
            }
            foreach ($clearUnread as $item) {
                $im->clearUnread(
                    $this->wukongUid($this->user_info['id']),
                    (string)$item['channel_id'],
                    (int)$item['message_seq'],
                    (int)$item['channel_type']
                );
            }
        } catch (\Exception $e) {
            $this->json(0, $e->getMessage());
        }

        $this->chatJson(1, 'success', [
            'processed_count' => count($result),
            'list' => $result,
        ]);
    }

    //清空当前用户自己的单聊会话，服务端历史同步也按当前用户隐藏边界过滤。
    public function im_person_conversation_delete()
    {
        $data = $this->secureChatRequestInput();
        $rule = [
            'usertoken|用户token' => 'require',
            'receiver_id|对方用户ID' => 'require|number',
        ];
        $validate = new Validate();
        $validate->rule($rule);
        if (!$validate->check($data)) {
            $this->json(0, $validate->getError());
        }
        $settings = $this->chatControl();
        if ((int)$settings['private_delete_enabled'] !== 1) {
            $this->json(0, '单聊删除已关闭');
        }
        $receiver = Db::name('user')->where('appid', $this->appid)->where('id', $data['receiver_id'])->find();
        if (!$receiver) {
            $this->json(0, '用户不存在');
        }
        if ((int)($data['delete_peer'] ?? 0) === 1) {
            $this->json(0, '只能清空自己的聊天记录');
        }
        $selfUid = $this->wukongUid($this->user_info['id']);
        $receiverUid = $this->wukongUid($receiver['id']);
        $clearTime = date("Y-m-d H:i:s");
        try {
            $this->hideChatConversationForUser(
                (int)$this->user_info["id"],
                $receiverUid,
                (int)config('wukongim.channel_type_person', WukongIM::CHANNEL_TYPE_PERSON),
                (int)$receiver["id"],
                0,
                $clearTime
            );
        } catch (\Exception $e) {
            $this->json(0, $e->getMessage());
        }
        $self = [];
        $deleteError = "";
        try {
            $im = new WukongIM();
            $self = $im->deleteConversation($selfUid, $receiverUid, (int)config('wukongim.channel_type_person', WukongIM::CHANNEL_TYPE_PERSON));
        } catch (\Exception $e) {
            $deleteError = $e->getMessage();
        }
        $this->chatJson(1, 'success', [
            'self' => $self,
            'clear_time' => $clearTime,
            'visibility' => 'self_only',
            'conversation_delete_error' => $deleteError,
        ]);
    }

    //清空当前用户自己的群聊会话和群历史可见性，不影响其他群成员。
    public function im_group_conversation_delete()
    {
        $data = $this->secureChatRequestInput();
        $rule = [
            'usertoken|用户token' => 'require',
            'group_id|群聊ID' => 'require|number',
        ];
        $validate = new Validate();
        $validate->rule($rule);
        if (!$validate->check($data)) {
            $this->json(0, $validate->getError());
        }
        $group = Db::name("chat_group")
            ->where("appid", $this->appid)
            ->where("id", $data["group_id"])
            ->where("status", 1)
            ->find();
        if (!$group) {
            $this->json(0, "群聊不存在");
        }
        try {
            $this->assertGroupMember($group, $this->user_info);
            $clearTime = date("Y-m-d H:i:s");
            $selfUid = $this->wukongUid($this->user_info["id"]);
            $channelType = (int)config('wukongim.channel_type_group', WukongIM::CHANNEL_TYPE_GROUP);
            $this->hideChatConversationForUser(
                (int)$this->user_info["id"],
                (string)$group["channel_id"],
                $channelType,
                0,
                (int)$group["id"],
                $clearTime
            );
        } catch (\Exception $e) {
            $this->json(0, $e->getMessage());
        }
        $self = [];
        $deleteError = "";
        try {
            $self = (new WukongIM())->deleteConversation($selfUid, (string)$group["channel_id"], $channelType);
        } catch (\Exception $e) {
            $deleteError = $e->getMessage();
        }
        $this->chatJson(1, "success", [
            "self" => $self,
            "clear_time" => $clearTime,
            "visibility" => "self_only",
            "conversation_delete_error" => $deleteError,
        ]);
    }

    //清空当前用户自己的全部单聊和群聊记录可见性，不删除好友、群、登录态或他人记录。
    public function im_chat_records_clear_all()
    {
        $data = $this->secureChatRequestInput();
        $rule = [
            'usertoken|用户token' => 'require',
        ];
        $validate = new Validate();
        $validate->rule($rule);
        if (!$validate->check($data)) {
            $this->json(0, $validate->getError());
        }
        $clearTime = date("Y-m-d H:i:s");
        try {
            $selfUid = $this->wukongUid($this->user_info["id"]);
            $this->hideAllChatConversationsForUser((int)$this->user_info["id"], $clearTime);
        } catch (\Exception $e) {
            $this->json(0, $e->getMessage());
        }
        $conversationDelete = ["deleted" => 0, "failed" => 0];
        $conversationDeleteError = "";
        try {
            $conversationDelete = $this->deleteWukongConversationsForUser($selfUid);
        } catch (\Exception $e) {
            $conversationDeleteError = $e->getMessage();
        }
        $this->chatJson(1, "success", [
            "clear_time" => $clearTime,
            "visibility" => "self_only",
            "conversation_delete" => $conversationDelete,
            "conversation_delete_error" => $conversationDeleteError,
        ]);
    }

    //删除当前用户视角下的一条聊天消息，历史同步不会再返回该消息。
    public function im_message_delete()
    {
        $data = $this->secureChatRequestInput();
        $rule = [
            'usertoken|用户token' => 'require',
            'target_client_msg_no|目标客户端消息号' => 'require',
        ];
        $validate = new Validate();
        $validate->rule($rule);
        if (!$validate->check($data)) {
            $this->json(0, $validate->getError());
        }
        $record = $this->queueRecordByClientMsgNo(trim((string)$data["target_client_msg_no"]));
        $this->assertCanHideChatRecordForUser($record, $this->user_info);
        $this->hideChatMessageForUser((int)$this->user_info["id"], $record);
        $this->chatJson(1, "success", [
            "target_client_msg_no" => (string)$record["client_msg_no"],
            "visibility" => "self_only",
        ]);
    }

    //发送聊天好友申请
    public function im_friend_apply()
    {
        $data = $this->secureChatRequestInput();
        $rule = [
            'usertoken|用户token' => 'require',
            'friend_id|好友用户ID' => 'require|number',
        ];
        $validate = new Validate();
        $validate->rule($rule);
        if (!$validate->check($data)) {
            $this->json(0, $validate->getError());
        }
        $fromUser = $this->user_info;
        $friendId = (int)$data["friend_id"];
        if ($friendId === (int)$fromUser["id"]) {
            $this->json(0, "不能添加自己为好友");
        }
        $toUser = Db::name("user")->where("id", $friendId)->where("appid", $this->appid)->find();
        if (!$toUser) {
            $this->json(0, "用户不存在");
        }
        if ($this->isChatFriend((int)$fromUser["id"], $friendId)) {
            $this->chatJson(1, "已经是好友", [
                "is_friend" => true,
                "friend" => $this->formatChatUser($toUser),
            ]);
        }
        $remark = mb_substr(trim((string)($data["remark"] ?? "")), 0, 200);
        $now = date("Y-m-d H:i:s");
        Db::startTrans();
        try {
            $reverseApply = $this->activeChatFriendApply($friendId, (int)$fromUser["id"]);
            if ($reverseApply) {
                $this->acceptChatFriendApply($reverseApply, $fromUser, "双方同时申请，自动通过");
                Db::commit();
                try {
                    $this->sendFriendCommand($fromUser, $toUser, "friend_accepted", [
                        "apply_id" => (int)$reverseApply["id"],
                        "friend_id" => (int)$fromUser["id"],
                    ]);
                } catch (\Exception $ignore) {
                }
                $this->chatJson(1, "已添加好友", [
                    "is_friend" => true,
                    "apply" => $this->formatChatFriendApply(Db::name("chat_friend_apply")->where("id", $reverseApply["id"])->find()),
                ]);
            }
            $apply = $this->activeChatFriendApply((int)$fromUser["id"], $friendId);
            if ($apply) {
                Db::commit();
                $this->chatJson(1, "好友申请已发送", [
                    "is_friend" => false,
                    "apply" => $this->formatChatFriendApply($apply),
                ]);
            }
            $applyId = Db::name("chat_friend_apply")->insertGetId([
                "appid" => $this->appid,
                "from_user_id" => (int)$fromUser["id"],
                "to_user_id" => $friendId,
                "remark" => $remark,
                "status" => 0,
                "handle_msg" => "",
                "create_time" => $now,
                "update_time" => $now,
            ]);
            $apply = Db::name("chat_friend_apply")->where("id", $applyId)->find();
            Db::commit();
        } catch (\Exception $e) {
            Db::rollback();
            $this->json(0, $e->getMessage());
        }
        try {
            $this->sendFriendCommand($fromUser, $toUser, "friend_apply", [
                "apply_id" => (int)$apply["id"],
                "from_user_id" => (int)$fromUser["id"],
                "remark" => $remark,
            ]);
        } catch (\Exception $ignore) {
        }
        $this->chatJson(1, "好友申请已发送", [
            "is_friend" => false,
            "apply" => $this->formatChatFriendApply($apply),
        ]);
    }

    //处理聊天好友申请，accept=1通过，accept=0拒绝
    public function im_friend_handle()
    {
        $data = $this->secureChatRequestInput();
        $rule = [
            'usertoken|用户token' => 'require',
            'apply_id|申请ID' => 'require|number',
            'accept|是否通过' => 'require|in:0,1',
        ];
        $validate = new Validate();
        $validate->rule($rule);
        if (!$validate->check($data)) {
            $this->json(0, $validate->getError());
        }
        $handler = $this->user_info;
        $handleMsg = mb_substr(trim((string)($data["handle_msg"] ?? "")), 0, 200);
        $accept = (int)$data["accept"] === 1;
        Db::startTrans();
        try {
            $apply = Db::name("chat_friend_apply")
                ->where("id", (int)$data["apply_id"])
                ->where("appid", $this->appid)
                ->lock(true)
                ->find();
            if (!$apply) {
                throw new \Exception("好友申请不存在");
            }
            if ((int)$apply["to_user_id"] !== (int)$handler["id"]) {
                throw new \Exception("无权处理该好友申请");
            }
            if ((int)$apply["status"] !== 0) {
                throw new \Exception("好友申请已处理");
            }
            if ($accept) {
                $this->acceptChatFriendApply($apply, $handler, $handleMsg);
            } else {
                Db::name("chat_friend_apply")->where("id", $apply["id"])->update([
                    "status" => 2,
                    "handle_msg" => $handleMsg,
                    "handle_time" => date("Y-m-d H:i:s"),
                    "update_time" => date("Y-m-d H:i:s"),
                ]);
            }
            $apply = Db::name("chat_friend_apply")->where("id", $apply["id"])->find();
            Db::commit();
        } catch (\Exception $e) {
            Db::rollback();
            $this->json(0, $e->getMessage());
        }
        $fromUser = Db::name("user")->where("id", $apply["from_user_id"])->where("appid", $this->appid)->find();
        if ($fromUser) {
            try {
                $this->sendFriendCommand($handler, $fromUser, $accept ? "friend_accepted" : "friend_rejected", [
                    "apply_id" => (int)$apply["id"],
                    "friend_id" => (int)$handler["id"],
                    "status" => (int)$apply["status"],
                    "handle_msg" => $handleMsg,
                ]);
            } catch (\Exception $ignore) {
            }
        }
        $this->chatJson(1, $accept ? "已添加好友" : "已拒绝好友申请", [
            "is_friend" => $accept,
            "apply" => $this->formatChatFriendApply($apply),
        ]);
    }

    //聊天好友状态
    public function im_friend_status()
    {
        $data = $this->secureChatRequestInput();
        $rule = [
            'usertoken|用户token' => 'require',
            'friend_id|好友用户ID' => 'require|number',
        ];
        $validate = new Validate();
        $validate->rule($rule);
        if (!$validate->check($data)) {
            $this->json(0, $validate->getError());
        }
        $user = $this->user_info;
        $friendId = (int)$data["friend_id"];
        $friend = Db::name("user")->where("id", $friendId)->where("appid", $this->appid)->find();
        if (!$friend) {
            $this->json(0, "用户不存在");
        }
        $gateway = new GatewayStream();
        $presence = $gateway->presenceForUid($this->wukongUid($friendId));
        $formattedFriend = array_merge($this->formatChatUser($friend), $presence);
        $pendingOut = $this->activeChatFriendApply((int)$user["id"], $friendId);
        $pendingIn = $this->activeChatFriendApply($friendId, (int)$user["id"]);
        $this->chatJson(1, "success", [
            "is_friend" => $this->isChatFriend((int)$user["id"], $friendId),
            "non_friend_message_limit" => 3,
            "non_friend_message_count" => $this->personTopMessageCount((int)$user["id"], $friendId),
            "pending_out_apply" => $pendingOut ? $this->formatChatFriendApply($pendingOut) : [],
            "pending_in_apply" => $pendingIn ? $this->formatChatFriendApply($pendingIn) : [],
            "friend" => $formattedFriend,
            "uid" => $presence["uid"],
            "online" => $presence["online"],
            "is_online" => $presence["is_online"],
            "online_status" => $presence["online_status"],
            "total_online_count" => $presence["total_online_count"],
            "presence_source" => "gateway",
        ]);
    }

    //搜索聊天好友候选用户。添加好友只能按用户名搜索，昵称、用户 ID、IMUID 不暴露搜索能力。
    public function im_friend_search()
    {
        $data = $this->secureChatRequestInput();
        $keyword = trim((string)($data["keyword"] ?? ""));
        if ($keyword === "") {
            $this->json(0, "请输入用户名");
        }
        $user = $this->user_info;
        $rows = Db::name("user")
            ->where("appid", $this->appid)
            ->where("id", "<>", (int)$user["id"])
            ->where("username", "like", "%" . $keyword . "%")
            ->field("id,username,nickname,usertx,sex,signature,title,viptime,exp")
            ->order("id", "desc")
            ->limit(min(max((int)($data["limit"] ?? 20), 1), 50))
            ->select()
            ->toArray();
        $list = [];
        foreach ($rows as $row) {
            $targetId = (int)$row["id"];
            $pendingOut = $this->activeChatFriendApply((int)$user["id"], $targetId);
            $pendingIn = $this->activeChatFriendApply($targetId, (int)$user["id"]);
            $list[] = [
                "user" => $this->formatChatUser($row),
                "friend_id" => $targetId,
                "uid" => $this->wukongUid($targetId),
                "channel_id" => $this->wukongUid($targetId),
                "channel_type" => (int)config('wukongim.channel_type_person', WukongIM::CHANNEL_TYPE_PERSON),
                "is_friend" => $this->isChatFriend((int)$user["id"], $targetId),
                "non_friend_message_limit" => 3,
                "non_friend_message_count" => $this->personTopMessageCount((int)$user["id"], $targetId),
                "pending_out_apply" => $pendingOut ? $this->formatChatFriendApply($pendingOut) : [],
                "pending_in_apply" => $pendingIn ? $this->formatChatFriendApply($pendingIn) : [],
            ];
        }
        $this->chatJson(1, "success", [
            "list" => $list,
            "keyword" => $keyword,
        ]);
    }

    //聊天好友列表
    public function im_friend_list()
    {
        $this->secureChatRequestInput();
        $user = $this->user_info;
        $rows = Db::name("chat_friend")
            ->alias("f")
            ->join("user u", "u.id=f.friend_id")
            ->where("f.appid", $this->appid)
            ->where("f.user_id", $user["id"])
            ->where("f.status", 1)
            ->field("f.*,u.username,u.nickname,u.usertx,u.sex,u.signature,u.title,u.viptime,u.exp")
            ->order("f.id", "desc")
            ->page((int)$this->page, (int)$this->limit)
            ->select()
            ->toArray();
        $count = Db::name("chat_friend")
            ->where("appid", $this->appid)
            ->where("user_id", $user["id"])
            ->where("status", 1)
            ->count();
        $list = [];
        $gateway = new GatewayStream();
        foreach ($rows as $row) {
            $friend = [
                "id" => (int)$row["friend_id"],
                "username" => $row["username"] ?? "",
                "nickname" => $row["nickname"] ?? "",
                "usertx" => $row["usertx"] ?? "",
                "sex" => $row["sex"] ?? 0,
                "signature" => $row["signature"] ?? "",
                "title" => $row["title"] ?? "",
                "viptime" => $row["viptime"] ?? 0,
                "exp" => $row["exp"] ?? 0,
            ];
            $presence = $gateway->presenceForUid($this->wukongUid((int)$row["friend_id"]));
            $formattedFriend = array_merge($this->formatChatUser($friend), $presence);
            $list[] = [
                "id" => (int)$row["id"],
                "friend_id" => (int)$row["friend_id"],
                "friend" => $formattedFriend,
                "uid" => $presence["uid"],
                "online" => $presence["online"],
                "is_online" => $presence["is_online"],
                "online_status" => $presence["online_status"],
                "total_online_count" => $presence["total_online_count"],
                "create_time" => (string)($row["create_time"] ?? ""),
            ];
        }
        $this->chatJson(1, "success", [
            "list" => $list,
            "pagecount" => ceil($count / (int)$this->limit) == 0 ? 1 : ceil($count / (int)$this->limit),
            "current_number" => (int)$this->page,
            "snapshot_complete" => (((int)$this->page - 1) * (int)$this->limit + count($list)) >= (int)$count ? 1 : 0,
            "snapshot_version" => sha1(implode("|", [
                (string)$this->appid,
                (string)$user["id"],
                (string)$count,
                (string)(Db::name("chat_friend")
                    ->where("appid", $this->appid)
                    ->where("user_id", $user["id"])
                    ->where("status", 1)
                    ->max("update_time") ?: ""),
            ])),
            "generated_at" => time(),
        ]);
    }

    //聊天好友申请列表，type=in收到，type=out发出
    public function im_friend_apply_list()
    {
        $data = $this->secureChatRequestInput();
        $user = $this->user_info;
        $type = (string)($data["type"] ?? "in");
        $status = $data["status"] ?? "";
        $query = Db::name("chat_friend_apply")->where("appid", $this->appid);
        if ($type === "out") {
            $query->where("from_user_id", $user["id"]);
        } else {
            $query->where("to_user_id", $user["id"]);
        }
        if ($status !== "") {
            $query->where("status", (int)$status);
        }
        $rows = $query->order("id", "desc")->page((int)$this->page, (int)$this->limit)->select()->toArray();
        $countQuery = Db::name("chat_friend_apply")->where("appid", $this->appid);
        if ($type === "out") {
            $countQuery->where("from_user_id", $user["id"]);
        } else {
            $countQuery->where("to_user_id", $user["id"]);
        }
        if ($status !== "") {
            $countQuery->where("status", (int)$status);
        }
        $list = [];
        foreach ($rows as $row) {
            $list[] = $this->formatChatFriendApply($row);
        }
        $count = $countQuery->count();
        $this->chatJson(1, "success", [
            "list" => $list,
            "pagecount" => ceil($count / (int)$this->limit) == 0 ? 1 : ceil($count / (int)$this->limit),
            "current_number" => (int)$this->page,
        ]);
    }

    //删除聊天好友，双方关系同时删除
    public function im_friend_delete()
    {
        $data = $this->secureChatRequestInput();
        $rule = [
            'usertoken|用户token' => 'require',
            'friend_id|好友用户ID' => 'require|number',
        ];
        $validate = new Validate();
        $validate->rule($rule);
        if (!$validate->check($data)) {
            $this->json(0, $validate->getError());
        }
        $user = $this->user_info;
        $friendId = (int)$data["friend_id"];
        $friend = Db::name("user")->where("id", $friendId)->where("appid", $this->appid)->find();
        if (!$friend) {
            $this->json(0, "好友不存在");
        }
        $clearTime = date("Y-m-d H:i:s");
        Db::startTrans();
        try {
            Db::name("chat_friend")
                ->where("appid", $this->appid)
                ->whereIn("user_id", [(int)$user["id"], $friendId])
                ->whereIn("friend_id", [(int)$user["id"], $friendId])
                ->update([
                    "status" => 0,
                    "update_time" => $clearTime,
                ]);
            $channelType = (int)config('wukongim.channel_type_person', WukongIM::CHANNEL_TYPE_PERSON);
            $this->hideChatConversationForUser(
                (int)$user["id"],
                $this->wukongUid($friendId),
                $channelType,
                $friendId,
                0,
                $clearTime
            );
            $this->hideChatConversationForUser(
                $friendId,
                $this->wukongUid($user["id"]),
                $channelType,
                (int)$user["id"],
                0,
                $clearTime
            );
            Db::commit();
        } catch (\Exception $e) {
            Db::rollback();
            $this->json(0, $e->getMessage());
        }
        $gateway = new GatewayStream();
        $gateway->syncPresenceTargetsForUser((int)$this->appid, (int)$user["id"]);
        $gateway->syncPresenceTargetsForUser((int)$this->appid, $friendId);
        if ($friend) {
            try {
                $this->sendFriendCommand($user, $friend, "friend_deleted", [
                    "friend_id" => (int)$user["id"],
                    "clear_time" => $clearTime,
                ]);
            } catch (\Exception $ignore) {
            }
        }
        $this->chatJson(1, "删除成功", [
            "clear_time" => $clearTime,
            "visibility" => "both_side_after_friend_delete",
        ]);
    }

    //撤回私聊或群聊消息，按消息服务协议发送撤回通知
    public function im_message_recall()
    {
        $data = $this->secureChatRequestInput();
        $rule = [
            'usertoken|用户token' => 'require',
            'target_client_msg_no|被撤回客户端消息号' => 'require',
            'client_msg_no|客户端消息号' => 'require',
        ];
        $validate = new Validate();
        $validate->rule($rule);
        if (!$validate->check($data)) {
            $this->json(0, $validate->getError());
        }
        $settings = $this->chatControl();
        $target = $this->queueRecordByClientMsgNo(trim((string)$data['target_client_msg_no']));
        $this->assertCanRecallQueueRecord($target, $settings);
        $payloadText = json_decode((string)($target['payload_text'] ?? ''), true);
        $payload = [
            'protocol' => 'blin.chat.v1',
            'type' => WukongIM::CONTENT_TYPE_RECALL,
            'content_type' => 'recall',
            'scene' => (int)$target['channel_type'] === (int)config('wukongim.channel_type_group', WukongIM::CHANNEL_TYPE_GROUP) ? 'group_chat' : 'private_chat',
            'appid' => (int)$this->appid,
            'channel_id' => (string)$target['channel_id'],
            'channel_type' => (int)$target['channel_type'],
            'operator_id' => (int)$this->user_info['id'],
            'operator_uid' => $this->wukongUid($this->user_info['id']),
            'target_client_msg_no' => (string)$target['client_msg_no'],
            'target_message_id' => (string)($target['message_id'] ?? ''),
            'message_id' => (string)($target['message_id'] ?? ''),
            'content' => '撤回了一条消息',
            'recall_time' => time(),
            'target_payload' => is_array($payloadText) ? [
                'content_type' => (string)($payloadText['content_type'] ?? ''),
                'sender_id' => (int)($payloadText['sender_id'] ?? 0),
            ] : [],
        ] + $this->chatDevicePayload();
        try {
            $result = (new WukongIM())->sendRecallMessage(
                $this->wukongUid($this->user_info['id']),
                (string)$target['channel_id'],
                (int)$target['channel_type'],
                $payload,
                trim((string)$data['client_msg_no'])
            );
        } catch (\Exception $e) {
            $this->json(0, $e->getMessage());
        }
        $this->hideChatMessageForRecordParticipants($target);
        $gatewayPublish = $this->publishSendResultToGateway($result, trim((string)$data['client_msg_no']), $payload);
        $this->chatJson(1, 'success', [
            'client_msg_no' => $result['client_msg_no'] ?? (string)$data['client_msg_no'],
            'message_id' => $result['message_id'] ?? '',
            'payload' => $payload,
            'gateway_publish' => $gatewayPublish,
        ]);
    }

    //阅后即焚读后触发通知，客户端收到命令后删除本地目标消息
    public function im_burn_after_read()
    {
        $data = $this->secureChatRequestInput();
        $rule = [
            'usertoken|用户token' => 'require',
            'target_client_msg_no|目标客户端消息号' => 'require',
            'client_msg_no|客户端消息号' => 'require',
        ];
        $validate = new Validate();
        $validate->rule($rule);
        if (!$validate->check($data)) {
            $this->json(0, $validate->getError());
        }
        $settings = $this->chatControl();
        if ((int)$settings['burn_after_read_enabled'] !== 1) {
            $this->json(0, '阅后即焚已关闭');
        }
        $target = $this->queueRecordByClientMsgNo(trim((string)$data['target_client_msg_no']));
        $targetPayload = json_decode((string)($target['payload_text'] ?? ''), true);
        if (empty($targetPayload['burn_after_read']['enabled'])) {
            $this->json(0, '该消息不是阅后即焚消息');
        }
        $channelType = (int)$target['channel_type'];
        $readerUid = $this->wukongUid($this->user_info['id']);
        $channelId = (string)$target['channel_id'];
        if ($channelType === (int)config('wukongim.channel_type_person', WukongIM::CHANNEL_TYPE_PERSON)) {
            if (!in_array($readerUid, [(string)$target['from_uid'], $channelId], true)) {
                $this->json(0, '无权操作该消息');
            }
            $toUid = (string)$target['from_uid'] === $readerUid ? $channelId : (string)$target['from_uid'];
        } else {
            if ((int)$settings['burn_after_read_allow_group'] !== 1) {
                $this->json(0, '群聊阅后即焚已关闭');
            }
            $group = Db::name('chat_group')->where('appid', $this->appid)->where('channel_id', $channelId)->where('status', 1)->find();
            if (!$group) {
                $this->json(0, '群聊不存在');
            }
            try {
                $this->assertGroupMember($group, $this->user_info);
            } catch (\Exception $e) {
                $this->json(0, $e->getMessage());
            }
            $toUid = $channelId;
        }
        $payload = [
            'protocol' => 'blin.chat.v1',
            'type' => WukongIM::CONTENT_TYPE_CMD,
            'cmd' => 'burn_after_read',
            'content_type' => 'cmd',
            'appid' => (int)$this->appid,
            'channel_type' => $channelType,
            'channel_id' => $channelId,
            'reader_id' => (int)$this->user_info['id'],
            'reader_uid' => $readerUid,
            'target_client_msg_no' => (string)$target['client_msg_no'],
            'target_message_id' => (string)($target['message_id'] ?? ''),
            'burn_after_read' => $targetPayload['burn_after_read'],
            'read_time' => time(),
        ] + $this->chatDevicePayload();
        try {
            $result = (new WukongIM())->sendCommandMessage(
                $readerUid,
                $toUid,
                $channelType,
                $payload,
                trim((string)$data['client_msg_no'])
            );
        } catch (\Exception $e) {
            $this->json(0, $e->getMessage());
        }
        $this->hideBurnAfterReadMessage($target, $this->user_info);
        $gatewayPublish = $this->publishSendResultToGateway($result, trim((string)$data['client_msg_no']), $payload);
        $this->chatJson(1, 'success', [
            'client_msg_no' => $result['client_msg_no'] ?? (string)$data['client_msg_no'],
            'message_id' => $result['message_id'] ?? '',
            'payload' => $payload,
            'gateway_publish' => $gatewayPublish,
        ]);
    }

    //领取私聊红包
    public function im_person_red_packet_receive()
    {
        $data = $this->secureChatRequestInput();
        $rule = [
            'usertoken|用户token' => 'require',
            'red_packet_id|红包ID' => 'require|number',
            'client_msg_no|客户端消息号' => 'require',
        ];
        $validate = new Validate();
        $validate->rule($rule);
        $result = $validate->check($data);
        if (!$result) {
            $this->json(0, $validate->getError());
        }

        $user_all_info = $this->user_info;
        $im = new WukongIM();
        $payload = [];
        $sendResult = [];
        $clientMsgNo = trim((string)$data["client_msg_no"]);
        Db::startTrans();
        try {
            $redPacket = Db::name("wukongim_red_packet")
                ->where("id", $data["red_packet_id"])
                ->where("appid", $this->appid)
                ->lock(true)
                ->find();
            if (!$redPacket) {
                throw new \Exception("红包不存在");
            }
            if ((int)$redPacket["receiver_id"] !== (int)$user_all_info["id"]) {
                throw new \Exception("无权领取该红包");
            }
            if ((int)$redPacket["status"] === 0 && !empty($redPacket["expire_time"]) && strtotime((string)$redPacket["expire_time"]) > 0 && strtotime((string)$redPacket["expire_time"]) < time()) {
                $this->refundExpiredRedPacket($redPacket);
                Db::commit();
                $this->json(0, "红包已过期");
            }
            if ((int)$redPacket["status"] !== 0) {
                $queued = $this->queuedRedPacketReceive($im, $clientMsgNo, (int)$redPacket["id"]);
                if ($queued) {
                    Db::commit();
                    $this->chatJson(1, "success", $queued);
                }
                throw new \Exception("红包已领取或已失效");
            }

            $sender = Db::name("user")->where("id", $redPacket["sender_id"])->where("appid", $this->appid)->find();
            if (!$sender) {
                throw new \Exception("发送用户不存在");
            }

            $assetType = (string)$redPacket["asset_type"];
            $receiveAmount = $this->chatAssetAmountLabel($redPacket["amount"] ?? 0, $assetType);
            $field = $this->assetField($assetType);
            Db::name("user")
                ->where("id", $user_all_info["id"])
                ->where("appid", $this->appid)
                ->update([$field => Db::raw($field . ' + ' . $receiveAmount)]);
            add_user_bill($user_all_info, 9, "+" . $receiveAmount, "领取" . $sender["nickname"] . "的红包，交易单号：" . (string)($redPacket["transaction_no"] ?? ""), $this->assetBillType($assetType));

            Db::name("wukongim_red_packet")->where("id", $redPacket["id"])->update([
                "status" => 1,
                "remaining_amount" => $this->chatAssetAmountLabel(0, $assetType),
                "receive_count" => 1,
                "receive_time" => date("Y-m-d H:i:s"),
                "update_time" => date("Y-m-d H:i:s"),
            ]);
            Db::name("wukongim_red_packet_receive")->insert([
                "appid" => $this->appid,
                "red_packet_id" => $redPacket["id"],
                "sender_id" => $redPacket["sender_id"],
                "receiver_id" => $user_all_info["id"],
                "amount" => $receiveAmount,
                "asset_type" => $assetType,
                "create_time" => date("Y-m-d H:i:s"),
            ]);

            $payload = $this->baseWukongMessagePayload($user_all_info, $sender, "red_packet_received");
            $payload["content"] = "已领取红包";
            $payload["image_path"] = "";
            $payload["asset_type"] = $assetType;
            $payload["red_packet"] = [
                "red_packet_id" => (int)$redPacket["id"],
                "transaction_no" => (string)($redPacket["transaction_no"] ?? ""),
                "amount" => $receiveAmount,
                "amount_label" => $this->chatAssetAmountLabel($receiveAmount, $assetType),
                "asset_type" => $assetType,
                "status" => 1,
                "status_name" => $this->redPacketStatusName(1),
                "packet_type" => (string)($redPacket["packet_type"] ?? "ordinary"),
                "receiver_id" => (int)$user_all_info["id"],
                "quantity" => 1,
                "receive_count" => 1,
                "remaining_amount" => $this->chatAssetAmountLabel(0, $assetType),
                "expire_time" => (string)($redPacket["expire_time"] ?? ""),
                "receive_time" => date("Y-m-d H:i:s"),
            ];
            $sendResult = $im->sendPersonMessage($this->wukongUid($user_all_info["id"]), $this->wukongUid($sender["id"]), $payload, $clientMsgNo);
            $sourceRecord = Db::name('wukongim_message_queue')->where('client_msg_no', $redPacket['client_msg_no'])->find();
            if ($sourceRecord) {
                $this->recordMessageActionReceipt($sourceRecord, $user_all_info, 'red_packet_received', [
                    "red_packet_id" => (int)$redPacket["id"],
                    "transaction_no" => (string)($redPacket["transaction_no"] ?? ""),
                    "amount" => $receiveAmount,
                    "amount_label" => $this->chatAssetAmountLabel($receiveAmount, $assetType),
                    "asset_type" => $assetType,
                    "status" => 1,
                    "status_name" => $this->redPacketStatusName(1),
                    "packet_type" => (string)($redPacket["packet_type"] ?? "ordinary"),
                    "receiver_id" => (int)$user_all_info["id"],
                    "receive_count" => 1,
                    "quantity" => 1,
                ], $clientMsgNo, $im);
            }
            Db::commit();
        } catch (\Exception $e) {
            Db::rollback();
            $this->json(0, $e->getMessage());
        }

        $this->chatJson(1, "success", $this->chatSendResponse($sendResult, $clientMsgNo, $payload));
    }

    //确认接收转账，按消息事件和命令消息同步收款回执
    public function im_person_transfer_receive()
    {
        $data = $this->secureChatRequestInput();
        $rule = [
            'usertoken|用户token' => 'require',
            'transfer_id|转账ID' => 'require|number',
            'client_msg_no|客户端消息号' => 'require',
        ];
        $validate = new Validate();
        $validate->rule($rule);
        if (!$validate->check($data)) {
            $this->json(0, $validate->getError());
        }

        $user = $this->user_info;
        $clientMsgNo = trim((string)$data["client_msg_no"]);
        $im = new WukongIM();
        $payload = [];
        $sendResult = [];
        Db::startTrans();
        try {
            $transfer = Db::name("wukongim_transfer")
                ->where("id", $data["transfer_id"])
                ->where("appid", $this->appid)
                ->lock(true)
                ->find();
            if (!$transfer) {
                throw new \Exception("转账不存在");
            }
            if ((int)$transfer["receiver_id"] !== (int)$user["id"]) {
                throw new \Exception("无权接收该转账");
            }
            if ((int)$transfer["status"] === 1) {
                $queued = $im->queuedMessage($clientMsgNo);
                if ($queued) {
                    Db::commit();
                    $this->chatJson(1, "success", $queued);
                }
                throw new \Exception("转账已收款");
            }
            if ((int)$transfer["status"] !== 0) {
                throw new \Exception("转账已失效");
            }
            if (!empty($transfer["expire_time"]) && strtotime((string)$transfer["expire_time"]) > 0 && strtotime((string)$transfer["expire_time"]) < time()) {
                $this->refundExpiredTransfer($transfer);
                Db::commit();
                $this->json(0, "转账已过期");
            }
            $sender = Db::name("user")->where("id", $transfer["sender_id"])->where("appid", $this->appid)->find();
            if (!$sender) {
                throw new \Exception("发送用户不存在");
            }
            $group = [];
            if ((int)($transfer["group_id"] ?? 0) > 0) {
                $group = Db::name("chat_group")
                    ->where("id", (int)$transfer["group_id"])
                    ->where("appid", $this->appid)
                    ->where("status", 1)
                    ->find();
                if (!$group) {
                    throw new \Exception("群聊不存在");
                }
                $this->assertGroupMember($group, $user);
            }
            $assetType = (string)$transfer["asset_type"];
            $receiveAmount = $this->chatAssetAmountLabel($transfer["receiver_increase"] ?? 0, $assetType);
            $feeAmount = $this->chatAssetAmountLabel($transfer["fee"] ?? 0, $assetType);
            $field = $this->assetField($assetType);
            Db::name("user")->where("id", $user["id"])->where("appid", $this->appid)->update([$field => Db::raw($field . ' + ' . $receiveAmount)]);
            add_user_bill($user, 9, "+" . $receiveAmount, "收到" . $sender["nickname"] . "转账，交易单号：" . (string)($transfer["transaction_no"] ?? ""), $this->assetBillType($assetType));
            $designatedAccount = (int)($this->app_info["forum_configuration"]["designated_account"] ?? 0);
            if ($this->chatAssetCompare($feeAmount, 0, $assetType) > 0 && $designatedAccount > 0) {
                $designated = Db::name("user")->where("id", $designatedAccount)->where("appid", $this->appid)->lock(true)->find();
                if ($designated) {
                    Db::name("user")->where("id", $designated["id"])->where("appid", $this->appid)->update([$field => Db::raw($field . ' + ' . $feeAmount)]);
                    add_user_bill($designated, 9, "+" . $feeAmount, "收到" . $sender["nickname"] . "的转账手续费", $this->assetBillType($assetType));
                }
            }

            Db::name("wukongim_transfer")->where("id", $transfer["id"])->update([
                "status" => 1,
                "receive_client_msg_no" => $clientMsgNo,
                "receive_time" => date("Y-m-d H:i:s"),
                "update_time" => date("Y-m-d H:i:s"),
            ]);

            $payload = $group
                ? $this->baseGroupMessagePayload($user, $group, "transfer_received")
                : $this->baseWukongMessagePayload($user, $sender, "transfer_received");
            $payload["content"] = "已收款";
            $payload["image_path"] = "";
            $payload["asset_type"] = $assetType;
            $payload["receiver_id"] = (int)$user["id"];
            $payload["receiver_uid"] = $this->wukongUid($user["id"]);
            $payload["transfer"] = [
                "transfer_id" => (int)$transfer["id"],
                "transaction_no" => (string)($transfer["transaction_no"] ?? ""),
                "amount" => $this->chatAssetAmountLabel($transfer["amount"] ?? 0, $assetType),
                "amount_label" => $this->chatAssetAmountLabel($transfer["amount"] ?? 0, $assetType),
                "asset_type" => $assetType,
                "status" => 1,
                "status_name" => $this->transferStatusName(1),
                "group_id" => (int)($transfer["group_id"] ?? 0),
                "receiver_id" => (int)$user["id"],
                "receive_amount" => $receiveAmount,
                "expire_time" => (string)($transfer["expire_time"] ?? ""),
                "receive_time" => date("Y-m-d H:i:s"),
            ];
            if ($group) {
                $sendResult = $im->sendGroupMessage($this->wukongUid($user["id"]), (string)$group["channel_id"], $payload, $clientMsgNo);
            } else {
                $sendResult = $im->sendPersonMessage($this->wukongUid($user["id"]), $this->wukongUid($sender["id"]), $payload, $clientMsgNo);
            }
            Db::name("wukongim_transfer")->where("id", $transfer["id"])->update([
                "receive_message_id" => (string)($sendResult["message_id"] ?? ""),
                "update_time" => date("Y-m-d H:i:s"),
            ]);

            $sourceRecord = Db::name('wukongim_message_queue')->where('client_msg_no', $transfer['client_msg_no'])->find();
            if ($sourceRecord) {
                $this->recordMessageActionReceipt($sourceRecord, $user, 'transfer_received', [
                    "transfer_id" => (int)$transfer["id"],
                    "transaction_no" => (string)($transfer["transaction_no"] ?? ""),
                    "amount" => $this->chatAssetAmountLabel($transfer["amount"] ?? 0, $assetType),
                    "amount_label" => $this->chatAssetAmountLabel($transfer["amount"] ?? 0, $assetType),
                    "asset_type" => $assetType,
                    "status" => 1,
                    "status_name" => $this->transferStatusName(1),
                    "group_id" => (int)($transfer["group_id"] ?? 0),
                    "receiver_id" => (int)$user["id"],
                    "receive_amount" => $receiveAmount,
                ], $clientMsgNo, $im);
            }
            Db::commit();
        } catch (\Exception $e) {
            Db::rollback();
            $this->json(0, $e->getMessage());
        }

        $this->chatJson(1, "success", $this->chatSendResponse($sendResult, $clientMsgNo, $payload));
    }

    //重试发送失败消息队列
    public function im_retry_messages()
    {
        $data = $this->secureChatRequestInput();
        $rule = [
            'usertoken|用户token' => 'require',
        ];
        $validate = new Validate();
        $validate->rule($rule);
        $result = $validate->check($data);
        if (!$result) {
            $this->json(0, $validate->getError());
        }
        try {
            $result = (new WukongIM())->retryQueuedMessages((int)($data["limit"] ?? 20));
        } catch (\Exception $e) {
            $this->json(0, $e->getMessage());
        }
        $this->chatJson(1, "success", $result);
    }

    //创建群聊并同步频道成员
    public function im_group_create()
    {
        $data = $this->secureChatRequestInput();
        $rule = [
            'usertoken|用户token' => 'require',
            'name|群聊名称' => 'require',
        ];
        $validate = new Validate();
        $validate->rule($rule);
        if (!$validate->check($data)) {
            $this->json(0, $validate->getError());
        }
        $owner = $this->user_info;
        $memberIds = $this->chatMemberIds($data["member_ids"] ?? "", (int)$owner["id"]);
        $members = Db::name("user")->where("appid", $this->appid)->whereIn("id", $memberIds)->select()->toArray();
        if (count($members) !== count($memberIds)) {
            $this->json(0, "群成员不存在");
        }

        $im = new WukongIM();
        $group = [];
        Db::startTrans();
        try {
            $groupId = Db::name("chat_group")->insertGetId([
                "appid" => $this->appid,
                "channel_id" => "",
                "name" => trim((string)$data["name"]),
                "avatar" => (string)($data["avatar"] ?? ""),
                "owner_id" => (int)$owner["id"],
                "notice" => (string)($data["notice"] ?? ""),
                "status" => 1,
                "member_count" => count($members),
                "create_time" => date("Y-m-d H:i:s"),
                "update_time" => date("Y-m-d H:i:s"),
            ]);
            $channelId = $this->chatGroupChannelId($groupId);
            Db::name("chat_group")->where("id", $groupId)->update(["channel_id" => $channelId]);
            foreach ($members as $member) {
                Db::name("chat_group_member")->insert([
                    "appid" => $this->appid,
                    "group_id" => $groupId,
                    "channel_id" => $channelId,
                    "user_id" => (int)$member["id"],
                    "role" => (int)$member["id"] === (int)$owner["id"] ? 1 : 0,
                    "status" => 1,
                    "join_time" => date("Y-m-d H:i:s"),
                    "update_time" => date("Y-m-d H:i:s"),
                ]);
            }
            $subscribers = array_map(function ($member) {
                return $this->wukongUid($member["id"]);
            }, $members);
            $im->channelCreateOrUpdate($channelId, (int)config('wukongim.channel_type_group', WukongIM::CHANNEL_TYPE_GROUP), $subscribers, 1);
            $group = Db::name("chat_group")->where("id", $groupId)->find();
            Db::commit();
        } catch (\Exception $e) {
            Db::rollback();
            if (!empty($channelId)) {
                try {
                    $im->deleteChannel($channelId, (int)config('wukongim.channel_type_group', WukongIM::CHANNEL_TYPE_GROUP));
                } catch (\Exception $ignore) {
                }
            }
            $this->json(0, $e->getMessage());
        }
        $this->chatJson(1, "success", $this->formatChatGroup($group));
    }

    //更新群聊资料
    public function im_group_update()
    {
        $data = $this->secureChatRequestInput();
        $rule = [
            'usertoken|用户token' => 'require',
            'group_id|群聊ID' => 'require|number',
        ];
        $validate = new Validate();
        $validate->rule($rule);
        if (!$validate->check($data)) {
            $this->json(0, $validate->getError());
        }
        $group = Db::name("chat_group")->where("id", $data["group_id"])->where("appid", $this->appid)->where("status", 1)->find();
        if (!$group) {
            $this->json(0, "群聊不存在");
        }
        try {
            $this->assertGroupMember($group, $this->user_info, true);
            $update = ["update_time" => date("Y-m-d H:i:s")];
            foreach (["name", "avatar", "notice"] as $field) {
                if (isset($data[$field])) {
                    $update[$field] = trim((string)$data[$field]);
                }
            }
            if (isset($update["name"]) && $update["name"] === "") {
                throw new \Exception("群聊名称不能为空");
            }
            Db::name("chat_group")->where("id", $group["id"])->update($update);
            (new WukongIM())->channelInfo($group["channel_id"], (int)config('wukongim.channel_type_group', WukongIM::CHANNEL_TYPE_GROUP));
        } catch (\Exception $e) {
            $this->json(0, $e->getMessage());
        }
        $group = Db::name("chat_group")->where("id", $group["id"])->find();
        $this->chatJson(1, "success", $this->formatChatGroup($group));
    }

    //群聊列表
    public function im_group_list()
    {
        $data = $this->secureChatRequestInput();
        $rule = [
            'usertoken|用户token' => 'require',
        ];
        $validate = new Validate();
        $validate->rule($rule);
        if (!$validate->check($data)) {
            $this->json(0, $validate->getError());
        }
        $rows = Db::name("chat_group")
            ->alias("g")
            ->join("chat_group_member m", "m.group_id=g.id")
            ->where("g.appid", $this->appid)
            ->where("g.status", 1)
            ->where("m.user_id", $this->user_info["id"])
            ->where("m.status", 1)
            ->field("g.*")
            ->page((int)$this->page, (int)$this->limit)
            ->order("g.update_time desc,g.id desc")
            ->select()->toArray();
        $list = array_map(function ($group) {
            return $this->formatChatGroup($group);
        }, $rows);
        $this->chatJson(1, "success", [
            "list" => $list,
            "pagecount" => count($list) < (int)$this->limit ? (int)$this->page : (int)$this->page + 1,
            "current_number" => $this->page,
        ]);
    }

    //群成员列表
    public function im_group_members()
    {
        $data = $this->secureChatRequestInput();
        $rule = [
            'usertoken|用户token' => 'require',
            'group_id|群聊ID' => 'require|number',
        ];
        $validate = new Validate();
        $validate->rule($rule);
        if (!$validate->check($data)) {
            $this->json(0, $validate->getError());
        }
        $group = Db::name("chat_group")->where("id", $data["group_id"])->where("appid", $this->appid)->where("status", 1)->find();
        if (!$group) {
            $this->json(0, "群聊不存在");
        }
        try {
            $this->assertGroupMember($group, $this->user_info);
        } catch (\Exception $e) {
            $this->json(0, $e->getMessage());
        }
        $rows = Db::name("chat_group_member")
            ->alias("m")
            ->join("user u", "u.id=m.user_id")
            ->where("m.group_id", $group["id"])
            ->where("m.status", 1)
            ->field("m.id as member_id,m.role,m.join_time,u.*")
            ->order("m.role desc,m.id asc")
            ->select()->toArray();
        $list = [];
        foreach ($rows as $row) {
            $user = $this->formatChatUser($row);
            $user["member_id"] = (int)$row["member_id"];
            $user["role"] = (int)$row["role"];
            $user["join_time"] = (string)$row["join_time"];
            $mute = $this->activeGroupMute((int)$group["id"], (int)$row["id"]);
            $user["muted"] = $mute ? 1 : 0;
            $user["mute_expire_time"] = $mute ? (string)($mute["expire_time"] ?? "") : "";
            $user["mute_permanent"] = $mute && empty($mute["expire_time"]) ? 1 : 0;
            $list[] = $user;
        }
        $this->chatJson(1, "success", [
            "group" => $this->formatChatGroup($group),
            "list" => $list,
        ]);
    }

    //添加群成员并同步频道订阅者
    public function im_group_members_add()
    {
        $data = $this->secureChatRequestInput();
        $rule = [
            'usertoken|用户token' => 'require',
            'group_id|群聊ID' => 'require|number',
            'member_ids|成员ID' => 'require',
        ];
        $validate = new Validate();
        $validate->rule($rule);
        if (!$validate->check($data)) {
            $this->json(0, $validate->getError());
        }
        $group = Db::name("chat_group")->where("id", $data["group_id"])->where("appid", $this->appid)->where("status", 1)->find();
        if (!$group) {
            $this->json(0, "群聊不存在");
        }
        $ids = $this->chatMemberIds($data["member_ids"]);
        if (!$ids) {
            $this->json(0, "成员ID不能为空");
        }
        $members = Db::name("user")->where("appid", $this->appid)->whereIn("id", $ids)->select()->toArray();
        if (count($members) !== count($ids)) {
            $this->json(0, "群成员不存在");
        }
        Db::startTrans();
        try {
            $this->assertGroupMember($group, $this->user_info, true);
            foreach ($members as $member) {
                $exists = Db::name("chat_group_member")->where("group_id", $group["id"])->where("user_id", $member["id"])->lock(true)->find();
                if ($exists) {
                    Db::name("chat_group_member")->where("id", $exists["id"])->update([
                        "status" => 1,
                        "update_time" => date("Y-m-d H:i:s"),
                    ]);
                } else {
                    Db::name("chat_group_member")->insert([
                        "appid" => $this->appid,
                        "group_id" => $group["id"],
                        "channel_id" => $group["channel_id"],
                        "user_id" => (int)$member["id"],
                        "role" => 0,
                        "status" => 1,
                        "join_time" => date("Y-m-d H:i:s"),
                        "update_time" => date("Y-m-d H:i:s"),
                    ]);
                }
            }
            $subscribers = array_map(function ($member) {
                return $this->wukongUid($member["id"]);
            }, $members);
            (new WukongIM())->addSubscribers($group["channel_id"], (int)config('wukongim.channel_type_group', WukongIM::CHANNEL_TYPE_GROUP), $subscribers, 0);
            $count = $this->refreshGroupMemberCount((int)$group["id"]);
            Db::commit();
        } catch (\Exception $e) {
            Db::rollback();
            $this->json(0, $e->getMessage());
        }
        $this->chatJson(1, "success", ["member_count" => $count]);
    }

    //群主或管理员禁言群成员，只限制业务发送并下发 CMD 通知，不再加入频道黑名单。
    public function im_group_member_mute()
    {
        $data = $this->secureChatRequestInput();
        $rule = [
            'usertoken|用户token' => 'require',
            'group_id|群聊ID' => 'require|number',
            'member_id|成员ID' => 'require|number',
        ];
        $validate = new Validate();
        $validate->rule($rule);
        if (!$validate->check($data)) {
            $this->json(0, $validate->getError());
        }
        $settings = $this->chatControl();
        if ((int)$settings['group_member_mute_enabled'] !== 1) {
            $this->json(0, "群成员禁言已关闭");
        }
        $group = Db::name("chat_group")->where("id", $data["group_id"])->where("appid", $this->appid)->where("status", 1)->find();
        if (!$group) {
            $this->json(0, "群聊不存在");
        }
        Db::startTrans();
        try {
            $operatorMember = $this->assertGroupMember($group, $this->user_info, true);
            $targetMember = $this->assertMutableGroupMember($group, (int)$data["member_id"], $operatorMember);
            $result = $this->setGroupMemberMute($group, $targetMember, (int)($data["expire_seconds"] ?? 0), (string)($data["reason"] ?? "管理员限制"));
            Db::commit();
        } catch (\Exception $e) {
            Db::rollback();
            $this->json(0, $e->getMessage());
        }
        $this->chatJson(1, "success", $result);
    }

    //群主或管理员解除群成员禁言，并下发 CMD 通知刷新客户端输入状态。
    public function im_group_member_unmute()
    {
        $data = $this->secureChatRequestInput();
        $rule = [
            'usertoken|用户token' => 'require',
            'group_id|群聊ID' => 'require|number',
            'member_id|成员ID' => 'require|number',
        ];
        $validate = new Validate();
        $validate->rule($rule);
        if (!$validate->check($data)) {
            $this->json(0, $validate->getError());
        }
        $group = Db::name("chat_group")->where("id", $data["group_id"])->where("appid", $this->appid)->where("status", 1)->find();
        if (!$group) {
            $this->json(0, "群聊不存在");
        }
        Db::startTrans();
        try {
            $operatorMember = $this->assertGroupMember($group, $this->user_info, true);
            $targetMember = $this->assertMutableGroupMember($group, (int)$data["member_id"], $operatorMember, true);
            $result = $this->removeGroupMemberMute($group, $targetMember, "user", (int)$this->user_info["id"]);
            Db::commit();
        } catch (\Exception $e) {
            Db::rollback();
            $this->json(0, $e->getMessage());
        }
        $this->chatJson(1, "success", $result);
    }

    //当前用户群禁言状态，客户端打开群聊时调用，实时 CMD 只是加速刷新。
    public function im_group_mute_status()
    {
        $data = $this->secureChatRequestInput();
        $rule = [
            'usertoken|用户token' => 'require',
            'group_id|群聊ID' => 'require|number',
        ];
        $validate = new Validate();
        $validate->rule($rule);
        if (!$validate->check($data)) {
            $this->json(0, $validate->getError());
        }
        $group = Db::name("chat_group")->where("id", $data["group_id"])->where("appid", $this->appid)->where("status", 1)->find();
        if (!$group) {
            $this->json(0, "群聊不存在");
        }
        try {
            $member = $this->assertGroupMember($group, $this->user_info);
        } catch (\Exception $e) {
            $this->json(0, $e->getMessage());
        }
        $this->chatJson(1, "success", $this->groupMuteState($group, $member));
    }

    //设置或取消群管理员
    public function im_group_admin_set()
    {
        $data = $this->secureChatRequestInput();
        $rule = [
            'usertoken|用户token' => 'require',
            'group_id|群聊ID' => 'require|number',
            'member_id|成员ID' => 'require|number',
            'is_admin|是否管理员' => 'require|in:0,1',
        ];
        $validate = new Validate();
        $validate->rule($rule);
        if (!$validate->check($data)) {
            $this->json(0, $validate->getError());
        }
        $group = Db::name("chat_group")->where("id", $data["group_id"])->where("appid", $this->appid)->where("status", 1)->find();
        if (!$group) {
            $this->json(0, "群聊不存在");
        }
        if ((int)$group["owner_id"] !== (int)$this->user_info["id"]) {
            $this->json(0, "只有群主可以设置管理员");
        }
        if ((int)$data["member_id"] === (int)$group["owner_id"]) {
            $this->json(0, "群主不能设置为管理员");
        }
        $member = Db::name("chat_group_member")
            ->where("appid", $this->appid)
            ->where("group_id", $group["id"])
            ->where("user_id", $data["member_id"])
            ->where("status", 1)
            ->find();
        if (!$member) {
            $this->json(0, "群成员不存在");
        }
        $role = (int)$data["is_admin"] === 1 ? 2 : 0;
        Db::name("chat_group_member")->where("id", $member["id"])->update([
            "role" => $role,
            "update_time" => date("Y-m-d H:i:s"),
        ]);
        $this->chatJson(1, "success", [
            "group_id" => (int)$group["id"],
            "member_id" => (int)$data["member_id"],
            "role" => $role,
        ]);
    }

    //转让群主
    public function im_group_owner_transfer()
    {
        $data = $this->secureChatRequestInput();
        $rule = [
            'usertoken|用户token' => 'require',
            'group_id|群聊ID' => 'require|number',
            'new_owner_id|新群主ID' => 'require|number',
        ];
        $validate = new Validate();
        $validate->rule($rule);
        if (!$validate->check($data)) {
            $this->json(0, $validate->getError());
        }
        $group = Db::name("chat_group")->where("id", $data["group_id"])->where("appid", $this->appid)->where("status", 1)->find();
        if (!$group) {
            $this->json(0, "群聊不存在");
        }
        if ((int)$group["owner_id"] !== (int)$this->user_info["id"]) {
            $this->json(0, "只有群主可以转让群主");
        }
        if ((int)$data["new_owner_id"] === (int)$group["owner_id"]) {
            $this->json(0, "新群主不能是当前群主");
        }
        $newOwner = Db::name("chat_group_member")
            ->where("appid", $this->appid)
            ->where("group_id", $group["id"])
            ->where("user_id", $data["new_owner_id"])
            ->where("status", 1)
            ->find();
        if (!$newOwner) {
            $this->json(0, "新群主必须是当前群成员");
        }
        Db::startTrans();
        try {
            Db::name("chat_group")->where("id", $group["id"])->update([
                "owner_id" => (int)$data["new_owner_id"],
                "update_time" => date("Y-m-d H:i:s"),
            ]);
            Db::name("chat_group_member")->where("group_id", $group["id"])->where("user_id", $group["owner_id"])->update([
                "role" => 0,
                "update_time" => date("Y-m-d H:i:s"),
            ]);
            Db::name("chat_group_member")->where("id", $newOwner["id"])->update([
                "role" => 1,
                "update_time" => date("Y-m-d H:i:s"),
            ]);
            Db::commit();
        } catch (\Exception $e) {
            Db::rollback();
            $this->json(0, $e->getMessage());
        }
        $group = Db::name("chat_group")->where("id", $group["id"])->find();
        $this->chatJson(1, "success", $this->formatChatGroup($group));
    }

    //移除群成员并同步频道订阅者
    public function im_group_members_remove()
    {
        $data = $this->secureChatRequestInput();
        $rule = [
            'usertoken|用户token' => 'require',
            'group_id|群聊ID' => 'require|number',
            'member_ids|成员ID' => 'require',
        ];
        $validate = new Validate();
        $validate->rule($rule);
        if (!$validate->check($data)) {
            $this->json(0, $validate->getError());
        }
        $group = Db::name("chat_group")->where("id", $data["group_id"])->where("appid", $this->appid)->where("status", 1)->find();
        if (!$group) {
            $this->json(0, "群聊不存在");
        }
        $ids = $this->chatMemberIds($data["member_ids"]);
        if (in_array((int)$group["owner_id"], $ids, true)) {
            $this->json(0, "不能移除群主");
        }
        Db::startTrans();
        try {
            $this->assertGroupMember($group, $this->user_info, true);
            Db::name("chat_group_member")->where("group_id", $group["id"])->whereIn("user_id", $ids)->update([
                "status" => 0,
                "leave_time" => date("Y-m-d H:i:s"),
                "remove_admin_id" => (int)$this->user_info["id"],
                "remove_reason" => "管理员移出",
                "update_time" => date("Y-m-d H:i:s"),
            ]);
            $subscribers = array_map(function ($id) {
                return $this->wukongUid($id);
            }, $ids);
            (new WukongIM())->removeSubscribers($group["channel_id"], (int)config('wukongim.channel_type_group', WukongIM::CHANNEL_TYPE_GROUP), $subscribers);
            (new WukongIM())->blacklistRemove($group["channel_id"], (int)config('wukongim.channel_type_group', WukongIM::CHANNEL_TYPE_GROUP), $subscribers);
            Db::name("chat_group_mute")
                ->where("appid", $this->appid)
                ->where("group_id", $group["id"])
                ->whereIn("user_id", $ids)
                ->where("status", 1)
                ->update([
                    "status" => 0,
                    "operator_type" => "user",
                    "operator_id" => (int)$this->user_info["id"],
                    "unmute_time" => date("Y-m-d H:i:s"),
                    "update_time" => date("Y-m-d H:i:s"),
                ]);
            $count = $this->refreshGroupMemberCount((int)$group["id"]);
            Db::commit();
        } catch (\Exception $e) {
            Db::rollback();
            $this->json(0, $e->getMessage());
        }
        $this->chatJson(1, "success", ["member_count" => $count]);
    }

    //退出群聊
    public function im_group_leave()
    {
        $data = $this->secureChatRequestInput();
        $rule = [
            'usertoken|用户token' => 'require',
            'group_id|群聊ID' => 'require|number',
        ];
        $validate = new Validate();
        $validate->rule($rule);
        if (!$validate->check($data)) {
            $this->json(0, $validate->getError());
        }
        $group = Db::name("chat_group")->where("id", $data["group_id"])->where("appid", $this->appid)->where("status", 1)->find();
        if (!$group) {
            $this->json(0, "群聊不存在");
        }
        if ((int)$group["owner_id"] === (int)$this->user_info["id"]) {
            $this->json(0, "群主不能直接退出，请先解散群聊或转让群主");
        }
        Db::startTrans();
        try {
            $this->assertGroupMember($group, $this->user_info);
            Db::name("chat_group_member")->where("group_id", $group["id"])->where("user_id", $this->user_info["id"])->update([
                "status" => 0,
                "leave_time" => date("Y-m-d H:i:s"),
                "remove_reason" => "主动退出",
                "update_time" => date("Y-m-d H:i:s"),
            ]);
            (new WukongIM())->removeSubscribers($group["channel_id"], (int)config('wukongim.channel_type_group', WukongIM::CHANNEL_TYPE_GROUP), [$this->wukongUid($this->user_info["id"])]);
            (new WukongIM())->blacklistRemove($group["channel_id"], (int)config('wukongim.channel_type_group', WukongIM::CHANNEL_TYPE_GROUP), [$this->wukongUid($this->user_info["id"])]);
            Db::name("chat_group_mute")
                ->where("appid", $this->appid)
                ->where("group_id", $group["id"])
                ->where("user_id", $this->user_info["id"])
                ->where("status", 1)
                ->update([
                    "status" => 0,
                    "operator_type" => "user",
                    "operator_id" => (int)$this->user_info["id"],
                    "unmute_time" => date("Y-m-d H:i:s"),
                    "update_time" => date("Y-m-d H:i:s"),
                ]);
            $count = $this->refreshGroupMemberCount((int)$group["id"]);
            Db::commit();
        } catch (\Exception $e) {
            Db::rollback();
            $this->json(0, $e->getMessage());
        }
        $this->chatJson(1, "success", ["member_count" => $count]);
    }

    //解散群聊
    public function im_group_delete()
    {
        $data = $this->secureChatRequestInput();
        $rule = [
            'usertoken|用户token' => 'require',
            'group_id|群聊ID' => 'require|number',
        ];
        $validate = new Validate();
        $validate->rule($rule);
        if (!$validate->check($data)) {
            $this->json(0, $validate->getError());
        }
        $group = Db::name("chat_group")->where("id", $data["group_id"])->where("appid", $this->appid)->where("status", 1)->find();
        if (!$group) {
            $this->json(0, "群聊不存在");
        }
        if ((int)$group["owner_id"] !== (int)$this->user_info["id"]) {
            $this->json(0, "只有群主可以解散群聊");
        }
        Db::startTrans();
        try {
            Db::name("chat_group")->where("id", $group["id"])->update([
                "status" => 0,
                "member_count" => 0,
                "disband_reason" => "群主解散",
                "disband_time" => date("Y-m-d H:i:s"),
                "update_time" => date("Y-m-d H:i:s"),
            ]);
            Db::name("chat_group_member")->where("group_id", $group["id"])->update([
                "status" => 0,
                "leave_time" => date("Y-m-d H:i:s"),
                "remove_reason" => "群聊已解散",
                "update_time" => date("Y-m-d H:i:s"),
            ]);
            Db::name("chat_group_mute")
                ->where("appid", $this->appid)
                ->where("group_id", $group["id"])
                ->where("status", 1)
                ->update([
                    "status" => 0,
                    "operator_type" => "user",
                    "operator_id" => (int)$this->user_info["id"],
                    "unmute_time" => date("Y-m-d H:i:s"),
                    "update_time" => date("Y-m-d H:i:s"),
                ]);
            (new WukongIM())->deleteChannel($group["channel_id"], (int)config('wukongim.channel_type_group', WukongIM::CHANNEL_TYPE_GROUP));
            Db::commit();
        } catch (\Exception $e) {
            Db::rollback();
            $this->json(0, $e->getMessage());
        }
        $this->chatJson(1, "success", []);
    }

    //发送群聊文本、图片、红包、指定转账
    public function im_group_send()
    {
        $this->chatRequestContext();
        $data = $this->secureChatInput(input());
        $rule = [
            'usertoken|用户token' => 'require',
            'group_id|群聊ID' => 'require|number',
            'client_msg_no|客户端消息号' => 'require',
        ];
        $validate = new Validate();
        $validate->rule($rule);
        if (!$validate->check($data)) {
            $this->json(0, $validate->getError());
        }
        $sender = $this->user_info;
        $group = Db::name("chat_group")->where("id", $data["group_id"])->where("appid", $this->appid)->where("status", 1)->find();
        if (!$group) {
            $this->json(0, "群聊不存在");
        }
        try {
            $senderMember = $this->assertGroupMember($group, $sender);
            $this->assertGroupCanSend($group, $senderMember);
        } catch (\Exception $e) {
            $this->json(0, $e->getMessage());
        }

        $contentType = $this->normalizeIncomingChatContentType($data);
        $clientMsgNo = trim((string)$data["client_msg_no"]);
        $im = new WukongIM();
        $chatControl = $this->chatControl();
        if ($this->hasChatMentionInput() && $contentType !== "text") {
            $this->json(0, "只有群聊文本消息支持@");
        }
        if ($this->hasReplyInput() && $contentType !== "text") {
            $this->json(0, "消息引用仅支持文本消息");
        }
        if (in_array($contentType, $this->chatMessageContentTypes(), true)) {
            $payload = $this->baseGroupMessagePayload($sender, $group, $contentType);
            if ($contentType === "contact_card") {
                $payload = array_merge($payload, $this->normalizeContactCardPayload());
            } else {
                $payload = array_merge($payload, $this->normalizeChatMediaPayload($contentType, $sender));
                if ($contentType === "text") {
                    $payload = array_merge($payload, $this->normalizeGroupMentionPayload($group, $senderMember, $contentType));
                    $this->appendGroupReplyPayload($payload, $group, $contentType);
                }
                $this->appendBurnAfterReadPayload($payload, $chatControl, true);
            }
            try {
                $sendResult = $im->sendGroupMessage($this->wukongUid($sender["id"]), $group["channel_id"], $payload, $clientMsgNo);
            } catch (\Exception $e) {
                $this->json(0, $e->getMessage());
            }
            $this->chatJson(1, "success", $this->chatSendResponse($sendResult, $clientMsgNo, $payload));
        }

        if ($contentType === "red_packet") {
            $rule = [
                'money|红包金额' => 'require',
                'asset_type|资产类型' => 'require|in:money,integral',
                'pay_password|支付密码' => 'require',
            ];
            $validate = new Validate();
            $validate->rule($rule);
            if (!$validate->check($data)) {
                $this->json(0, $validate->getError());
            }
            try {
                $amount = $this->normalizeChatAssetAmount($data["money"], (string)$data["asset_type"]);
                $this->verifyWalletPayPassword((int)$sender["id"], trim((string)($data["pay_password"] ?? "")));
            } catch (\Exception $e) {
                $this->json(0, $e->getMessage());
            }
            $remark = trim((string)($data["remark"] ?? "恭喜发财"));
            try {
                $packetOptions = $this->normalizeGroupRedPacketOptions($sender, $group, (string)($data["packet_type"] ?? "ordinary"), (int)($data["quantity"] ?? 1), (int)($data["receiver_id"] ?? 0));
            } catch (\Exception $e) {
                $this->json(0, $e->getMessage());
            }
            $packetType = (string)$packetOptions["packet_type"];
            $quantity = (int)$packetOptions["quantity"];
            $receiverId = (int)$packetOptions["receiver_id"];
            $payload = $this->baseGroupMessagePayload($sender, $group, "red_packet");
            Db::startTrans();
            try {
                $reserved = $im->reserveGroupMessage($this->wukongUid($sender["id"]), $group["channel_id"], $clientMsgNo, [
                    "content_type" => "red_packet",
                    "content" => $remark,
                    "asset_type" => (string)$data["asset_type"],
                    "red_packet" => [
                        "amount" => $amount,
                        "amount_label" => $this->chatAssetAmountLabel($amount, (string)$data["asset_type"]),
                        "asset_type" => (string)$data["asset_type"],
                        "remark" => $remark,
                        "quantity" => $quantity,
                        "packet_type" => $packetType,
                        "receiver_id" => $receiverId,
                    ],
                ]);
                if (!empty($reserved["duplicate"])) {
                    Db::commit();
                    $this->chatJson(1, "success", $this->chatSendResponse($reserved, $clientMsgNo, []));
                }
                $redPacket = $this->createGroupRedPacket($sender, $group, $amount, (string)$data["asset_type"], $remark, $quantity, $packetType, $receiverId);
                $payload["content"] = $remark;
                $payload["image_path"] = "";
                $payload["asset_type"] = (string)$redPacket["asset_type"];
                $payload["red_packet"] = $redPacket;
                $sendResult = $im->sendGroupMessage($this->wukongUid($sender["id"]), $group["channel_id"], $payload, $clientMsgNo);
                Db::name("wukongim_red_packet")->where("id", $redPacket["red_packet_id"])->update([
                    "client_msg_no" => $sendResult["client_msg_no"] ?? $clientMsgNo,
                    "message_id" => (string)($sendResult["message_id"] ?? ""),
                    "update_time" => date("Y-m-d H:i:s"),
                ]);
                Db::commit();
            } catch (\Exception $e) {
                Db::rollback();
                $this->json(0, $e->getMessage());
            }
            $this->chatJson(1, "success", $this->chatSendResponse($sendResult, $clientMsgNo, $payload));
        }

        if ($contentType === "transfer") {
            $rule = [
                'money|转账金额' => 'require',
                'asset_type|资产类型' => 'require|in:money,integral',
                'receiver_id|指定收款人' => 'require|number',
                'pay_password|支付密码' => 'require',
            ];
            $validate = new Validate();
            $validate->rule($rule);
            if (!$validate->check($data)) {
                $this->json(0, $validate->getError());
            }
            try {
                $amount = $this->normalizeChatAssetAmount($data["money"], (string)$data["asset_type"]);
                $this->verifyWalletPayPassword((int)$sender["id"], trim((string)($data["pay_password"] ?? "")));
            } catch (\Exception $e) {
                $this->json(0, $e->getMessage());
            }
            try {
                $receiver = $this->groupMemberUser($group, (int)$data["receiver_id"]);
            } catch (\Exception $e) {
                $this->json(0, $e->getMessage());
            }
            $payload = $this->baseGroupMessagePayload($sender, $group, "transfer");
            Db::startTrans();
            try {
                $reserved = $im->reserveGroupMessage($this->wukongUid($sender["id"]), $group["channel_id"], $clientMsgNo, [
                    "content_type" => "transfer",
                    "content" => $amount,
                    "asset_type" => (string)$data["asset_type"],
                    "receiver_id" => (int)$receiver["id"],
                    "transfer" => [
                        "amount" => $amount,
                        "amount_label" => $this->chatAssetAmountLabel($amount, (string)$data["asset_type"]),
                        "asset_type" => (string)$data["asset_type"],
                        "receiver_id" => (int)$receiver["id"],
                        "group_id" => (int)$group["id"],
                    ],
                ]);
                if (!empty($reserved["duplicate"])) {
                    Db::commit();
                    $this->chatJson(1, "success", $this->chatSendResponse($reserved, $clientMsgNo, []));
                }
                $transfer = $this->createGroupTransfer($sender, $receiver, $group, $amount, (string)$data["asset_type"], $clientMsgNo);
                $payload["content"] = (string)$transfer["amount"];
                $payload["image_path"] = "";
                $payload["asset_type"] = (string)$transfer["asset_type"];
                $payload["receiver_id"] = (int)$receiver["id"];
                $payload["receiver_uid"] = $this->wukongUid($receiver["id"]);
                $payload["transfer"] = $transfer;
                $sendResult = $im->sendGroupMessage($this->wukongUid($sender["id"]), $group["channel_id"], $payload, $clientMsgNo);
                Db::name("wukongim_transfer")->where("id", $transfer["transfer_id"])->update([
                    "message_id" => (string)($sendResult["message_id"] ?? ""),
                    "update_time" => date("Y-m-d H:i:s"),
                ]);
                Db::commit();
            } catch (\Exception $e) {
                Db::rollback();
                $this->json(0, $e->getMessage());
            }
            $this->chatJson(1, "success", $this->chatSendResponse($sendResult, $clientMsgNo, $payload));
        }

        $this->json(0, "content_type不合法");
    }

    //群聊聊天记录
    public function im_group_messages()
    {
        $data = $this->secureChatRequestInput();
        $rule = [
            'usertoken|用户token' => 'require',
            'group_id|群聊ID' => 'require|number',
        ];
        $validate = new Validate();
        $validate->rule($rule);
        if (!$validate->check($data)) {
            $this->json(0, $validate->getError());
        }
        $group = Db::name("chat_group")->where("id", $data["group_id"])->where("appid", $this->appid)->where("status", 1)->find();
        if (!$group) {
            $this->json(0, "群聊不存在");
        }
        $unreadOnly = (int)($data["unread_only"] ?? 0) === 1;
        try {
            $member = $this->assertGroupMember($group, $this->user_info);
            if (!$this->groupHistorySyncEnabled() && !$unreadOnly) {
                $data_rs = $this->emptyHistoryResponse();
                $data_rs["group"] = $this->formatChatGroup($group);
                $data_rs["history_sync"] = $this->historySyncPayload();
                $this->chatJson(1, "success", $data_rs);
            }
            $this->clearCurrentUserGroupMuteBlacklists();
            $im = new WukongIM();
            $historyLimit = (int)$this->limit;
            if ($unreadOnly) {
                $historyLimit = min(200, max(1, (int)($data["unread_limit"] ?? $historyLimit)));
            }
            $history = $this->groupQueueHistoryPage(
                $group,
                $historyLimit,
                (int)($data["start_message_seq"] ?? 0)
            );
        } catch (\Exception $e) {
            $this->json(0, $e->getMessage());
        }
        $users = [];
        $result = [];
        $maxMessageSeq = 0;
        $channelType = (int)config('wukongim.channel_type_group', WukongIM::CHANNEL_TYPE_GROUP);
        $messages = (array)$history["messages"];
        $nextStartMessageSeq = (int)$history["next_start_message_seq"];
        $hiddenClientMsgNos = $this->hiddenChatClientMsgNos((int)$this->user_info["id"], (string)$group["channel_id"], $channelType, $messages);
        $clearBoundary = $this->chatClearBoundaryTimestamp((int)$this->user_info["id"], (string)$group["channel_id"], $channelType);
        foreach ((array)$history["rows"] as $row) {
            $message = $this->queueRecordToWukongMessage($row);
            if (!$this->isDisplayableWukongChatMessage($message)) {
                continue;
            }
            $fromUid = (string)($message["from_uid"] ?? "");
            $uidInfo = WukongIM::parseUid($fromUid);
            if (!$uidInfo || $uidInfo["appid"] !== (int)$this->appid) {
                continue;
            }
            if (!isset($users[$fromUid])) {
                $users[$fromUid] = Db::name("user")->where("id", $uidInfo["user_id"])->where("appid", $this->appid)->find();
            }
            if (!$users[$fromUid]) {
                continue;
            }
            $messageData = $this->wukongPayloadToMessage($message);
            if (!$this->isGroupMessageVisibleForMember($member, $message, $messageData)) {
                continue;
            }
            if (!$this->isChatMessageVisibleForUser((int)$this->user_info["id"], (string)$group["channel_id"], $channelType, $message, $messageData, $hiddenClientMsgNos, $clearBoundary)) {
                continue;
            }
            $this->appendReceiptStatus($messageData);
            try {
                $this->recordMessageReadReceipt($row, $this->user_info, (int)($message['message_seq'] ?? 0), $im);
                $this->appendReceiptStatus($messageData);
            } catch (\Exception $e) {
                $this->json(0, $e->getMessage());
            }
            $result[] = [
                "fromUser" => $this->formatChatUser($users[$fromUid]),
                "group" => $this->formatChatGroup($group),
                "message" => $messageData,
                "raw" => [
                    "message_id" => $message["message_id"] ?? "",
                    "message_idstr" => $message["message_idstr"] ?? "",
                    "client_msg_no" => $message["client_msg_no"] ?? "",
                    "message_seq" => $message["message_seq"] ?? 0,
                    "channel_id" => $message["channel_id"] ?? "",
                    "channel_type" => $message["channel_type"] ?? WukongIM::CHANNEL_TYPE_GROUP,
                ],
            ];
            $maxMessageSeq = max($maxMessageSeq, (int)($message["message_seq"] ?? 0));
        }
        $result = $this->sortChatHistoryResult($result, $historyLimit);
        if ($maxMessageSeq > 0) {
            try {
                $im->clearUnread($this->wukongUid($this->user_info["id"]), $group["channel_id"], $maxMessageSeq, (int)config('wukongim.channel_type_group', WukongIM::CHANNEL_TYPE_GROUP));
            } catch (\Exception $e) {
                $this->json(0, $e->getMessage());
            }
        }
        $this->chatJson(1, "success", [
            "list" => $result,
            "pagecount" => !empty($history["more"]) ? (int)$this->page + 1 : (int)$this->page,
            "current_number" => $this->page,
            "more" => (int)($history["more"] ?? 0),
            "next_start_message_seq" => $nextStartMessageSeq,
            "raw_count" => count($messages),
            "history_sync" => $this->historySyncPayload(),
        ]);
    }

    //查询消息回执状态，群聊返回已读人数，红包/转账返回动作状态
    public function im_message_receipt_status()
    {
        $data = $this->secureChatRequestInput();
        $rule = [
            'usertoken|用户token' => 'require',
            'target_client_msg_no|目标客户端消息号' => 'require',
        ];
        $validate = new Validate();
        $validate->rule($rule);
        if (!$validate->check($data)) {
            $this->json(0, $validate->getError());
        }
        $record = $this->queueRecordByClientMsgNo(trim((string)$data['target_client_msg_no']));
        if ((int)$record['channel_type'] === (int)config('wukongim.channel_type_group', WukongIM::CHANNEL_TYPE_GROUP)) {
            $group = Db::name('chat_group')->where('appid', $this->appid)->where('channel_id', $record['channel_id'])->where('status', 1)->find();
            if (!$group) {
                $this->json(0, '群聊不存在');
            }
            try {
                $this->assertGroupMember($group, $this->user_info);
            } catch (\Exception $e) {
                $this->json(0, $e->getMessage());
            }
        } else {
            $selfUid = $this->wukongUid($this->user_info['id']);
            if (!in_array($selfUid, [(string)$record['from_uid'], (string)$record['channel_id']], true)) {
                $this->json(0, '无权查看该消息回执');
            }
        }
        $this->chatJson(1, 'success', [
            "target_client_msg_no" => (string)$record['client_msg_no'],
            "receipt" => $this->receiptStatusForMessage((string)$record['client_msg_no'], $record),
        ]);
    }

    //红包详情：只允许发送方、接收方或所在群成员查看
    public function im_red_packet_detail()
    {
        $data = $this->secureChatRequestInput();
        $rule = [
            'usertoken|用户token' => 'require',
            'red_packet_id|红包ID' => 'require|number',
        ];
        $validate = new Validate();
        $validate->rule($rule);
        if (!$validate->check($data)) {
            $this->json(0, $validate->getError());
        }
        $redPacket = $this->refreshExpiredRedPacket((int)$data["red_packet_id"]);
        if (!$redPacket || (int)$redPacket["appid"] !== (int)$this->appid) {
            $this->json(0, "红包不存在");
        }
        try {
            $this->assertRedPacketVisible($redPacket);
        } catch (\Exception $e) {
            $this->json(0, $e->getMessage());
        }
        $this->chatJson(1, "success", [
            "red_packet" => $this->formatRedPacketDetail($redPacket),
        ]);
    }

    //转账详情：只允许发送方、接收方或所在群成员查看
    public function im_transfer_detail()
    {
        $data = $this->secureChatRequestInput();
        $rule = [
            'usertoken|用户token' => 'require',
            'transfer_id|转账ID' => 'require|number',
        ];
        $validate = new Validate();
        $validate->rule($rule);
        if (!$validate->check($data)) {
            $this->json(0, $validate->getError());
        }
        $transfer = $this->refreshExpiredTransfer((int)$data["transfer_id"]);
        if (!$transfer || (int)$transfer["appid"] !== (int)$this->appid) {
            $this->json(0, "转账不存在");
        }
        try {
            $this->assertTransferVisible($transfer);
        } catch (\Exception $e) {
            $this->json(0, $e->getMessage());
        }
        $this->chatJson(1, "success", [
            "transfer" => $this->formatTransferDetail($transfer),
        ]);
    }

    //领取群聊红包
    public function im_group_red_packet_receive()
    {
        $data = $this->secureChatRequestInput();
        $rule = [
            'usertoken|用户token' => 'require',
            'red_packet_id|红包ID' => 'require|number',
            'client_msg_no|客户端消息号' => 'require',
        ];
        $validate = new Validate();
        $validate->rule($rule);
        if (!$validate->check($data)) {
            $this->json(0, $validate->getError());
        }
        $user = $this->user_info;
        $clientMsgNo = trim((string)$data["client_msg_no"]);
        $im = new WukongIM();
        Db::startTrans();
        try {
            $redPacket = Db::name("wukongim_red_packet")
                ->where("id", $data["red_packet_id"])
                ->where("appid", $this->appid)
                ->lock(true)
                ->find();
            if (!$redPacket || (int)$redPacket["group_id"] <= 0) {
                throw new \Exception("群红包不存在");
            }
            $group = Db::name("chat_group")->where("id", $redPacket["group_id"])->where("appid", $this->appid)->where("status", 1)->find();
            if (!$group) {
                throw new \Exception("群聊不存在");
            }
            $this->assertGroupMember($group, $user);
            if ((int)$redPacket["receiver_id"] > 0 && (int)$redPacket["receiver_id"] !== (int)$user["id"]) {
                throw new \Exception("该红包仅指定用户可领取");
            }
            if ((int)$redPacket["status"] === 0 && !empty($redPacket["expire_time"]) && strtotime((string)$redPacket["expire_time"]) > 0 && strtotime((string)$redPacket["expire_time"]) < time()) {
                $this->refundExpiredRedPacket($redPacket);
                Db::commit();
                $this->json(0, "红包已过期");
            }
            if ((int)$redPacket["status"] !== 0) {
                $queued = $this->queuedRedPacketReceive($im, $clientMsgNo, (int)$redPacket["id"]);
                if ($queued) {
                    Db::commit();
                    $this->chatJson(1, "success", $queued);
                }
                throw new \Exception("红包已领取或已失效");
            }
            $received = Db::name("wukongim_red_packet_receive")->where("red_packet_id", $redPacket["id"])->where("receiver_id", $user["id"])->find();
            if ($received) {
                $queued = $this->queuedRedPacketReceive($im, $clientMsgNo, (int)$redPacket["id"]);
                if ($queued) {
                    Db::commit();
                    $this->chatJson(1, "success", $queued);
                }
                throw new \Exception("已领取该红包");
            }
            $quantity = max(1, (int)($redPacket["quantity"] ?? 1));
            $receiveCount = (int)($redPacket["receive_count"] ?? 0);
            $assetType = (string)$redPacket["asset_type"];
            $remainingAmount = $this->chatAssetAmountLabel($redPacket["remaining_amount"] ?? $redPacket["amount"], $assetType);
            if ($receiveCount >= $quantity || $this->chatAssetCompare($remainingAmount, 0, $assetType) <= 0) {
                throw new \Exception("红包已领取完");
            }
            $sender = Db::name("user")->where("id", $redPacket["sender_id"])->where("appid", $this->appid)->find();
            if (!$sender) {
                throw new \Exception("发送用户不存在");
            }
            $receiveAmount = $this->groupRedPacketReceiveAmount($redPacket);
            $nextRemainingAmount = $this->chatAssetSub($remainingAmount, $receiveAmount, $assetType);
            $nextReceiveCount = $receiveCount + 1;
            $nextStatus = ($nextReceiveCount >= $quantity || $this->chatAssetCompare($nextRemainingAmount, 0, $assetType) <= 0) ? 1 : 0;
            $field = $this->assetField($assetType);
            Db::name("user")->where("id", $user["id"])->where("appid", $this->appid)->update([$field => Db::raw($field . ' + ' . $receiveAmount)]);
            add_user_bill($user, 9, "+" . $receiveAmount, "领取" . $sender["nickname"] . "的群红包，交易单号：" . (string)($redPacket["transaction_no"] ?? ""), $this->assetBillType($assetType));
            Db::name("wukongim_red_packet")->where("id", $redPacket["id"])->update([
                "status" => $nextStatus,
                "remaining_amount" => $nextRemainingAmount,
                "receive_count" => $nextReceiveCount,
                "receive_time" => $nextStatus === 1 ? date("Y-m-d H:i:s") : $redPacket["receive_time"],
                "update_time" => date("Y-m-d H:i:s"),
            ]);
            Db::name("wukongim_red_packet_receive")->insert([
                "appid" => $this->appid,
                "red_packet_id" => $redPacket["id"],
                "sender_id" => $redPacket["sender_id"],
                "receiver_id" => $user["id"],
                "amount" => $receiveAmount,
                "asset_type" => $assetType,
                "create_time" => date("Y-m-d H:i:s"),
            ]);
            $payload = $this->baseGroupMessagePayload($user, $group, "red_packet_received");
            $payload["content"] = "已领取红包";
            $payload["image_path"] = "";
            $payload["asset_type"] = $assetType;
            $payload["red_packet"] = [
                "red_packet_id" => (int)$redPacket["id"],
                "transaction_no" => (string)($redPacket["transaction_no"] ?? ""),
                "amount" => $receiveAmount,
                "amount_label" => $this->chatAssetAmountLabel($receiveAmount, $assetType),
                "asset_type" => $assetType,
                "status" => $nextStatus,
                "status_name" => $this->redPacketStatusName($nextStatus),
                "packet_type" => (string)($redPacket["packet_type"] ?? "ordinary"),
                "receiver_id" => (int)($redPacket["receiver_id"] ?? 0),
                "quantity" => $quantity,
                "receive_count" => $nextReceiveCount,
                "remaining_amount" => $nextRemainingAmount,
                "expire_time" => (string)($redPacket["expire_time"] ?? ""),
                "receive_time" => date("Y-m-d H:i:s"),
            ];
            $sendResult = $im->sendGroupMessage($this->wukongUid($user["id"]), $group["channel_id"], $payload, $clientMsgNo);
            $sourceRecord = Db::name('wukongim_message_queue')->where('client_msg_no', $redPacket['client_msg_no'])->find();
            if ($sourceRecord) {
                $this->recordMessageActionReceipt($sourceRecord, $user, 'red_packet_received', [
                    "red_packet_id" => (int)$redPacket["id"],
                    "transaction_no" => (string)($redPacket["transaction_no"] ?? ""),
                    "amount" => $receiveAmount,
                    "amount_label" => $this->chatAssetAmountLabel($receiveAmount, $assetType),
                    "asset_type" => $assetType,
                    "status" => $nextStatus,
                    "status_name" => $this->redPacketStatusName($nextStatus),
                    "packet_type" => (string)($redPacket["packet_type"] ?? "ordinary"),
                    "receiver_id" => (int)($redPacket["receiver_id"] ?? 0),
                    "receive_count" => $nextReceiveCount,
                    "quantity" => $quantity,
                    "remaining_amount" => $nextRemainingAmount,
                ], $clientMsgNo, $im);
            }
            Db::commit();
        } catch (\Exception $e) {
            Db::rollback();
            $this->json(0, $e->getMessage());
        }
        $this->chatJson(1, "success", $this->chatSendResponse($sendResult, $clientMsgNo, $payload));
    }

    //表情包商店列表
    public function im_sticker_packs()
    {
        $this->secureChatRequestInput(false);
        $ownedPackIds = $this->ownedStickerPackIds((int)$this->user_info["id"]);
        $rows = Db::name("chat_sticker_pack")
            ->where("appid", $this->appid)
            ->where("status", 1)
            ->order("sort", "desc")
            ->order("id", "desc")
            ->page((int)$this->page, (int)$this->limit)
            ->select()
            ->toArray();
        $count = (int)Db::name("chat_sticker_pack")
            ->where("appid", $this->appid)
            ->where("status", 1)
            ->count();
        $list = [];
        foreach ($rows as $row) {
            $list[] = $this->formatStickerPack($row, $ownedPackIds);
        }
        $this->chatJson(1, "success", [
            "list" => $list,
            "packs" => $list,
            "owned_pack_ids" => array_values($ownedPackIds),
            "pagecount" => ceil($count / (int)$this->limit) == 0 ? 1 : ceil($count / (int)$this->limit),
            "current_number" => (int)$this->page,
        ]);
    }

    //当前用户已拥有表情包
    public function im_sticker_mine()
    {
        $this->secureChatRequestInput(false);
        $ownedPackIds = $this->ownedStickerPackIds((int)$this->user_info["id"]);
        $packs = [];
        if ($ownedPackIds) {
            $rows = Db::name("chat_sticker_pack")
                ->where("appid", $this->appid)
                ->where("status", 1)
                ->whereIn("pack_id", $ownedPackIds)
                ->order("sort", "desc")
                ->order("id", "desc")
                ->select()
                ->toArray();
            foreach ($rows as $row) {
                $packs[] = $this->formatStickerPack($row, $ownedPackIds);
            }
        }
        $this->chatJson(1, "success", [
            "pack_ids" => array_values($ownedPackIds),
            "owned_pack_ids" => array_values($ownedPackIds),
            "packs" => $packs,
            "list" => $packs,
        ]);
    }

    //购买或添加表情包
    public function im_sticker_pack_buy()
    {
        $data = $this->secureChatRequestInput();
        $packId = trim((string)($data["pack_id"] ?? ""));
        if ($packId === "") {
            $this->json(0, "pack_id不能为空");
        }
        $pack = Db::name("chat_sticker_pack")
            ->where("appid", $this->appid)
            ->where("pack_id", $packId)
            ->where("status", 1)
            ->find();
        if (!$pack) {
            $this->json(0, "表情包不存在或已下架");
        }
        $user = $this->user_info;
        Db::startTrans();
        try {
            $exists = Db::name("chat_sticker_user_pack")
                ->where("appid", $this->appid)
                ->where("user_id", (int)$user["id"])
                ->where("pack_id", $packId)
                ->lock(true)
                ->find();
            if ($exists && (int)$exists["status"] === 1) {
                Db::commit();
                $this->chatJson(1, "success", [
                    "pack_id" => $packId,
                    "owned" => 1,
                    "duplicate" => true,
                    "pack" => $this->formatStickerPack($pack, [$packId]),
                ]);
            }
            $price = max(0, (int)($pack["price"] ?? 0));
            $assetType = (string)($pack["asset_type"] ?? "money");
            if ($price > 0) {
                $field = $this->assetField($assetType);
                $lockedUser = Db::name("user")->where("id", (int)$user["id"])->where("appid", $this->appid)->lock(true)->find();
                if (!$lockedUser) {
                    throw new \Exception("用户不存在");
                }
                $this->assertAssetBalance($lockedUser, $assetType, $price);
                Db::name("user")->where("id", (int)$user["id"])->where("appid", $this->appid)->update([
                    $field => Db::raw($field . ' - ' . $price),
                ]);
                add_user_bill($lockedUser, 9, "-" . $price, "购买表情包：" . (string)$pack["title"], $this->assetBillType($assetType));
            }
            $now = date("Y-m-d H:i:s");
            $ownedData = [
                "appid" => $this->appid,
                "user_id" => (int)$user["id"],
                "pack_id" => $packId,
                "order_no" => "STK" . date("YmdHis") . str_pad((string)random_int(0, 999999), 6, "0", STR_PAD_LEFT),
                "price" => $price,
                "asset_type" => $assetType,
                "status" => 1,
                "buy_time" => $now,
                "update_time" => $now,
            ];
            if ($exists) {
                Db::name("chat_sticker_user_pack")->where("id", (int)$exists["id"])->update($ownedData);
            } else {
                $ownedData["create_time"] = $now;
                Db::name("chat_sticker_user_pack")->insert($ownedData);
            }
            Db::commit();
        } catch (\Exception $e) {
            Db::rollback();
            $this->json(0, $e->getMessage());
        }
        $this->chatJson(1, "success", [
            "pack_id" => $packId,
            "owned" => 1,
            "duplicate" => false,
            "pack" => $this->formatStickerPack($pack, [$packId]),
        ]);
    }

    protected function ownedStickerPackIds(int $userId): array
    {
        if ($userId <= 0) {
            return [];
        }
        $ids = Db::name("chat_sticker_user_pack")
            ->where("appid", $this->appid)
            ->where("user_id", $userId)
            ->where("status", 1)
            ->column("pack_id");
        return array_values(array_unique(array_filter(array_map("strval", $ids))));
    }

    protected function formatStickerPack(array $pack, array $ownedPackIds): array
    {
        $packId = (string)($pack["pack_id"] ?? "");
        $items = Db::name("chat_sticker_item")
            ->where("appid", $this->appid)
            ->where("pack_id", $packId)
            ->where("status", 1)
            ->order("sort", "desc")
            ->order("id", "asc")
            ->select()
            ->toArray();
        $stickerItems = [];
        foreach ($items as $item) {
            $stickerItems[] = [
                "id" => (string)($item["sticker_id"] ?? ""),
                "sticker_id" => (string)($item["sticker_id"] ?? ""),
                "pack_id" => $packId,
                "name" => (string)($item["name"] ?? ""),
                "url" => $this->absolutePublicUrl((string)($item["url"] ?? "")),
                "asset" => (string)($item["asset"] ?? ""),
                "format" => (string)($item["format"] ?? ""),
                "animated" => (int)($item["animated"] ?? 0),
                "sort" => (int)($item["sort"] ?? 0),
            ];
        }
        $price = max(0, (int)($pack["price"] ?? 0));
        $assetType = (string)($pack["asset_type"] ?? "money");
        return [
            "id" => $packId,
            "pack_id" => $packId,
            "title" => (string)($pack["title"] ?? $pack["name"] ?? ""),
            "name" => (string)($pack["title"] ?? $pack["name"] ?? ""),
            "cover" => $this->absolutePublicUrl((string)($pack["cover"] ?? "")),
            "price" => $price,
            "asset_type" => $assetType,
            "price_text" => $price > 0 ? ($price . ($assetType === "integral" ? "积分" : "余额")) : "免费",
            "owned" => in_array($packId, $ownedPackIds, true) ? 1 : 0,
            "status" => (int)($pack["status"] ?? 1),
            "items" => $stickerItems,
            "stickers" => $stickerItems,
        ];
    }

    //QQ登录
    public function qq_login()
    {
        //判断登录是否开启
        if ($this->app_info["login_configuration"]["login_switch"] == 1) {
            $this->json(102, $this->app_info["login_configuration"]["login_closing_prompt"]);
        }
        $data = $this->securePublicRequestInput();
        $device = (string)($data["device"] ?? "");
        $rule = [
            'openid|qq互联登录授权后返回的用户openid' => 'require',
            'access_token|qq互联登录授权后返回的access_token' => 'require',
            'qq_appid|QQ互联申请的APPID' => 'require',
        ];
        $validate = new Validate();
        $validate->rule($rule);
        $result = $validate->check($data);
        if (!$result) {
            $this->json(0, $validate->getError());
        }
        $state = (string)($data["state"] ?? "");
        //state参数不为空，只能为0或者1
        if ($state != 0 && $state != 1) {
            $this->json(0, "state参数只能为0或者1");
        }
        //验证用户的access_token是否过期
        $url = "https://graph.qq.com/user/get_user_info?oauth_consumer_key={$data["qq_appid"]}&access_token={$data["access_token"]}&openid={$data["openid"]}";
        $Response = getHttpResponse($url);
        $Response = json_decode($Response, true);
        if ($Response["ret"] != 0) {
            $this->json(0, "access_token已过期，请重新登录");
        }
        $login_where = [
            "appid" => $this->appid,
            "openid_qq" => $data["openid"],
            "qq_appid" => $data["qq_appid"],
        ];
        $user_info = Db::name('user')->where($login_where)->find();
        $update_user_info = [];
        if ($user_info) {
            //判断账号是否被封禁
            if ($user_info["reasons"] == 1) {
                if ($user_info["reasons_time"] > time()) {
                    $this->json(403, "你账号已被封禁，封禁理由为：" . $user_info["reasons_ban"] . ",解封时间为" . $user_info["reasons_time"]);
                } else {
                    Db::name("user")->where("id", $user_info["id"])->update([
                        'reasons' => 1,
                        'reasons_time' => 0,
                        'reasons_ban' => ""
                    ]);
                }
            }
            //判断异地登录是否开启
            if ($this->app_info["login_configuration"]["remote_login"] == 0 && $user_info['email'] != "") {
                $now_user_ip = get_client_ip();
                if ($user_info["ip"] != "" && $now_user_ip != $user_info["ip"]) {
                    $ip = new IpLocation();
                    $ip_address = $ip->getDetail($user_info["ip"])["dataA"];
                    $ip_now_address = $ip->getDetail($now_user_ip)["dataA"];
                    if ($ip_address != $ip_now_address) {
                        $mail = new Email($user_info['email']);
                        $temdata = [
                            '{appname}' => $this->app_info["appname"],
                            '{time}' => date("Y-m-d H:i:s", time()),
                            '{username}' => $user_info["username"],
                            '{nickname}' => $user_info["nickname"],
                            '{address}' => $ip_now_address,
                            '{ip}' => $now_user_ip
                        ];
                        //获取邮件模板
                        $tplList = '../extend/EmailTpl/tpl.php';
                        //获取邮件模板列表
                        if (file_exists($tplList)) {
                            $tplList = include $tplList;
                        } else {
                            $tplList = [];
                        }
                        if (!isset($tplList[2])) {
                            throw new \Exception('邮件模板不存在');
                        }
                        $tpl = $tplList[2];
                        $templateString = file_get_contents(app()->getRootPath() . $tpl['path']);
                        $templateString = strtr($templateString, $temdata);
                        $mail->setBody($templateString);
                        $mail->setSubject($this->app_info["appname"] . $tpl['name']);
                        $mail->setFrom($this->app_info["appname"]);
                        $result = $mail->send();
                    }
                }
            }
            $usertoken = $this->issueUserDeviceSession((int)$user_info["id"], $device, $data);
            $update_user_info["ip"] = get_client_ip();
            Db::name("user")->where("id", $user_info["id"])->update($update_user_info);
            $result = [
                "id" => $user_info["id"],
                "username" => $user_info["username"],
                "usertoken" => $usertoken
            ];
            Cache::delete($this->appid . "login" . get_client_ip());
            $result = $this->appendWukongLoginPayload($result, (int)$user_info["id"], $usertoken);
            $this->securePublicJson(1, '登录成功', $result);
        } else {
            //判断是否开启注册
            if ($this->app_info["registration_configuration"]["registration_switch"] == 1) {
                $this->json(103, $this->app_info["registration_configuration"]["registration_closing_prompt"]);
            }
            $device = (string)($data["device"] ?? "");
            //判断是否开启单设备注册限制
            if ($this->app_info["registration_configuration"]["single_device_registration_limit"] != 0) {
                $rule = [
                    'device|设备码' => 'require',
                ];
                $validate = new Validate();
                $validate->rule($rule);
                $result = $validate->check($data);
                if (!$result) {
                    $this->json(0, $validate->getError());
                }
                $device_count = Db::name("user")->where("appid", $this->appid)->where("register_device='{$device}'")->count();
                if ($device_count >= $this->app_info["registration_configuration"]["single_device_registration_limit"]) {
                    $this->json(0, "该设备注册已达到上限");
                }
                $add["register_device"] = $device;
                $add["login_device"] = $device;
            }

            $salt = getRandChar(6);
            $username = enerate_username();
            $userinfo_configuration = $this->app_info["userinfo_configuration"];
            $add["appid"] = $this->appid;
            $add["username"] = $username;
            $add["password"] = md5($username . $salt);
            $add["salt"] = $salt;
            if ($state == 0) {
                $add["usertx"] = $userinfo_configuration['usertx'];
                $add["nickname"] = $userinfo_configuration['nickname'];
            } else {
                $add["usertx"] = $Response["figureurl_qq"];
                $add["sex"] = $Response["gender"] == "男" ? 0 : 1;
                $add["nickname"] = $Response["nickname"];
            }
            $add["money"] = $this->app_info["registration_configuration"]["money"];
            $add["integral"] = $this->app_info["registration_configuration"]["integral"];
            $add["viptime"] = time() + $this->app_info["registration_configuration"]["vip"];
            $add["userbg"] = $userinfo_configuration['userbg'];
            $add["signature"] = $userinfo_configuration['signature'];
            $add["create_time"] = date("Y-m-d H:i:s", time());
            $add["register_ip"] = get_client_ip();
            $add["invitecode"] = enerate_invitation_code();
            $add["openid_qq"] = $data["openid"];
            $add["qq_access_token"] = $data["access_token"];
            $add["qq_appid"] = $data["qq_appid"];

            $user_id = Db::name("user")->insertGetId($add);
            $this->applyNewUserChatDefaults((int)$user_id);

            //增加用户的交易账单
            if ($this->app_info["registration_configuration"]["money"] != 0) {
                add_user_bill(["id" => $user_id, "appid" => $this->appid], 1, "+" . $this->app_info["registration_configuration"]["money"], "注册奖励", 0);
            }
            if ($this->app_info["registration_configuration"]["integral"] != 0) {
                add_user_bill(["id" => $user_id, "appid" => $this->appid], 1, "+" . $this->app_info["registration_configuration"]["integral"], "注册奖励", 1);
            }
            //登录该用户
            $usertoken = $this->issueUserDeviceSession((int)$user_id, $device, $data);
            $update_user_info["ip"] = get_client_ip();
            Db::name("user")->where("id", $user_id)->update($update_user_info);
            $result = [
                "id" => $user_id,
                "username" => $username,
                "usertoken" => $usertoken
            ];
            $result = $this->appendWukongLoginPayload($result, (int)$user_id, $usertoken);
            $this->securePublicJson(1, "注册并登录成功", $result);
        }
    }

    //QQ注册
    public function qq_register()
    {
        //判断是否开启注册
        if ($this->app_info["registration_configuration"]["registration_switch"] == 1) {
            $this->json(103, $this->app_info["registration_configuration"]["registration_closing_prompt"]);
        }
        $data = $this->securePublicRequestInput();
        $rule = [
            'openid|qq互联登录授权后返回的用户openid' => 'require',
            'access_token|qq互联登录授权后返回的access_token' => 'require',
            'qq_appid|QQ互联申请的APPID' => 'require',
        ];
        $validate = new Validate();
        $validate->rule($rule);
        $result = $validate->check($data);
        if (!$result) {
            $this->json(0, $validate->getError());
        }
        $login_where = [
            "appid" => $this->appid,
            "openid_qq" => $data["openid"],
            "qq_appid" => $data["qq_appid"],
        ];
        $user_info = Db::name('user')->where($login_where)->find();
        if ($user_info) {
            $this->json(0, '该QQ已绑定用户，请直接登录');
        }
        $device = (string)($data["device"] ?? "");
        //判断是否开启单设备注册限制
        if ($this->app_info["registration_configuration"]["single_device_registration_limit"] != 0) {
            $rule = [
                'device|设备码' => 'require',
            ];
            $validate = new Validate();
            $validate->rule($rule);
            $result = $validate->check($data);
            if (!$result) {
                $this->json(0, $validate->getError());
            }
            $device_count = Db::name("user")->where("appid", $this->appid)->where("register_device='{$device}'")->count();
            if ($device_count >= $this->app_info["registration_configuration"]["single_device_registration_limit"]) {
                $this->json(0, "该设备注册已达到上限");
            }
            $add["register_device"] = $device;
            $add["login_device"] = $device;
        }

        $salt = getRandChar(6);
        $username = enerate_username();
        $userinfo_configuration = $this->app_info["userinfo_configuration"];
        $add["appid"] = $this->appid;
        $add["username"] = $username;
        $add["password"] = md5($salt);
        $add["salt"] = $salt;
        $add["usertx"] = $userinfo_configuration['usertx'];
        $add["nickname"] = $userinfo_configuration['nickname'];
        $add["money"] = $this->app_info["registration_configuration"]["money"];
        $add["integral"] = $this->app_info["registration_configuration"]["integral"];
        $add["viptime"] = time() + $this->app_info["registration_configuration"]["vip"];
        $add["userbg"] = $userinfo_configuration['userbg'];
        $add["signature"] = $userinfo_configuration['signature'];
        $add["create_time"] = date("Y-m-d H:i:s", time());
        $add["register_ip"] = get_client_ip();
        $add["invitecode"] = enerate_invitation_code();
        $add["openid_qq"] = $data["openid"];
        $add["qq_access_token"] = $data["access_token"];
        $add["qq_appid"] = $data["qq_appid"];

        $user_id = Db::name("user")->insertGetId($add);
        $this->applyNewUserChatDefaults((int)$user_id);

        //增加用户的交易账单
        if ($this->app_info["registration_configuration"]["money"] != 0) {
            add_user_bill(["id" => $user_id, "appid" => $this->appid], 1, "+" . $this->app_info["registration_configuration"]["money"], "注册奖励", 0);
        }
        if ($this->app_info["registration_configuration"]["integral"] != 0) {
            add_user_bill(["id" => $user_id, "appid" => $this->appid], 1, "+" . $this->app_info["registration_configuration"]["integral"], "注册奖励", 1);
        }
        //登录该用户
        $usertoken = $this->issueUserDeviceSession((int)$user_id, (string)($data['device'] ?? ''), $data);
        $update_user_info["ip"] = get_client_ip();
        Db::name("user")->where("id", $user_id)->update($update_user_info);
        $result = [
            "id" => $user_id,
            "username" => $username,
            "usertoken" => $usertoken
        ];
        Cache::delete($this->appid . "login" . get_client_ip());
        $result = $this->appendWukongLoginPayload($result, (int)$user_id, $usertoken);
        $this->securePublicJson(1, "注册成功", $result);
    }

    //绑定QQ
    public function bind_qq()
    {
        $data = input();
        $rule = [
            'usertoken|用户token' => 'require',
            'openid|qq互联登录授权后返回的用户openid' => 'require',
            'access_token|qq互联登录授权后返回的access_token' => 'require',
            'qq_appid|QQ互联申请的APPID' => 'require',
        ];
        $validate = new Validate();
        $validate->rule($rule);
        $result = $validate->check($data);
        if (!$result) {
            $this->json(0, $validate->getError());
        }
        $state = input("state") == "" ? "" : input("state");
        //state参数不为空，只能为0或者1
        if ($state != 0 && $state != 1) {
            $this->json(0, "state参数只能为0或者1");
        }
        $user_all_info = $this->user_info;
        if ($user_all_info["openid_qq"] != "") {
            $this->json(0, '该账号已绑定QQ');
        }
        //验证用户的access_token是否过期
        $url = "https://graph.qq.com/user/get_user_info?oauth_consumer_key={$data["qq_appid"]}&access_token={$data["access_token"]}&openid={$data["openid"]}";
        $Response = getHttpResponse($url);
        $Response = json_decode($Response, true);
        if ($Response["ret"] != 0) {
            $this->json(0, "access_token已过期，请重新登录");
        }
        $login_where = [
            "appid" => $this->appid,
            "openid_qq" => $data["openid"],
            "qq_appid" => $data["qq_appid"],
        ];
        $user_info = Db::name('user')->where($login_where)->find();
        if ($user_info) {
            $this->json(0, '该QQ已绑定账号');
        }
        $update_user_info = [
            "openid_qq" => $data["openid"],
            "qq_access_token" => $data["access_token"],
            "qq_appid" => $data["qq_appid"],
        ];
        if ($state == 1) {
            $update_user_info["usertx"] = $Response["figureurl_qq"];
            $update_user_info["sex"] = $Response["gender"] == "男" ? 0 : 1;
            $update_user_info["nickname"] = $Response["nickname"];
        }
        Db::name("user")->where("id", $user_all_info["id"])->update($update_user_info);
        $this->json(1, '绑定成功');
    }

    //解绑QQ
    public function unbind_qq()
    {
        $data = input();
        $rule = [
            'usertoken|用户token' => 'require',
        ];
        $validate = new Validate();
        $validate->rule($rule);
        $result = $validate->check($data);
        if (!$result) {
            $this->json(0, $validate->getError());
        }
        $user_all_info = $this->user_info;
        if ($user_all_info["openid_qq"] == "") {
            $this->json(0, '该账号未绑定QQ');
        }
        $login_where = [
            "usertoken" => $data["usertoken"],
            "appid" => $this->appid,
        ];
        $update_user_info = [
            "openid_qq" => '',
            "qq_access_token" => '',
            "qq_appid" => '',
        ];
        Db::name("user")->where("id", $user_all_info["id"])->update($update_user_info);
        $this->json(1, '解绑成功');
    }

    //获取标签
    public function get_labels()
    {
        $data = input();
        $rule = [
            'type|类型' => 'require|number|in:1,2',
        ];
        $validate = new Validate();
        $validate->rule($rule);
        $result = $validate->check($data);
        if (!$result) {
            $this->json(0, $validate->getError());
        }
        if ($data["type"] == 1) {
            $tag = Config::get("post_reporting_tag.");
        }
        if ($data["type"] == 2) {
            $tag = Config::get("comment_reporting_tag.");
        }
        $this->json(1, '获取成功', $tag);
    }

    //举报帖子或评论
    public function reporting()
    {
        $data = input();
        $rule = [
            'usertoken|用户token' => 'require',
            'type|类型' => 'require|number|in:1,2',
            'target_id|帖子或评论id' => 'require|number',
            'tag|标签' => 'require',
            'content|内容' => 'require',
        ];
        $validate = new Validate();
        $validate->rule($rule);
        $result = $validate->check($data);
        if (!$result) {
            $this->json(0, $validate->getError());
        }
        $user_all_info = $this->user_info;
        if ($data["type"] == 1) {
            $post_info = Db::name("forum_posts")->where("id", $data["target_id"])->find();
            if (!$post_info) {
                $this->json(0, '帖子不存在');
            }
            //判断标签是否存在
            $tag = Config::get("post_reporting_tag.");
            if (!in_array($data["tag"], $tag)) {
                $this->json(0, '标签不存在');
            }
        }
        if ($data["type"] == 2) {
            $comment_info = Db::name("comments")->where("id", $data["target_id"])->find();
            if (!$comment_info) {
                $this->json(0, '评论不存在');
            }
            //判断标签是否存在
            $tag = Config::get("comment_reporting_tag.");
            if (!in_array($data["tag"], $tag)) {
                $this->json(0, '标签不存在');
            }
        }
        $reporting_data = [
            "uid" => $user_all_info["id"],
            "type" => $data["type"],
            "target_id" => $data["target_id"],
            "yesapi_report_type" => $data["tag"],
            "reason" => $data["content"],
            "appid" => $data["appid"],
            "report_time" => date("Y-m-d H:i:s", time()),
        ];
        Db::name("report")->insert($reporting_data);
        $this->json(1, '举报成功');
    }

    //获取用户举报记录
    public function get_user_reporting()
    {
        $data = input();
        $rule = [
            'usertoken|用户token' => 'require',
        ];
        $validate = new Validate();
        $validate->rule($rule);
        $result = $validate->check($data);
        if (!$result) {
            $this->json(0, $validate->getError());
        }
        $user_all_info = $this->user_info;
        $reporting_where["uid"] = $user_all_info["id"];
        $reporting_where["appid"] = $data["appid"];
        //如果有type参数，就是获取某个类型的举报记录
        if (isset($data["type"])) {
            $rule = [
                'type|类型' => 'number|in:1,2',
            ];
            $validate = new Validate();
            $validate->rule($rule);
            $result = $validate->check($data);
            if (!$result) {
                $this->json(0, $validate->getError());
            }
            $reporting_where["type"] = $data["type"];
        }
        $reporting_list = Db::name("report")->where($reporting_where)->page($this->page, $this->limit)->select()->toArray();
        $pagecount = Db::name("report")->where($reporting_where)->count();
        $data_rs["list"] = $reporting_list;
        $data_rs["pagecount"] = ceil($pagecount / $this->limit) == 0 ? 1 : ceil($pagecount / $this->limit);
        $data_rs["current_number"] = $this->page;
        $this->json(1, "success", $data_rs);
    }

    //获取关注用户的帖子列表
    public function get_follow_user_post()
    {
        $data = input();
        $rule = [
            'usertoken|用户token' => 'require',
        ];
        $validate = new Validate();
        $validate->rule($rule);
        $result = $validate->check($data);
        if (!$result) {
            $this->json(0, $validate->getError());
        }
        $user_all_info = $this->user_info;
        $result = Db::name('polymorphic')
            ->alias('po')
            ->join("forum_posts p", "po.other_id=p.userid")
            ->join("user u", "u.id=p.userid")
            ->join("forum_section s", "s.id=p.section_id")
            ->join("forum_section sub", "sub.id=p.sub_section_id")
            ->field("p.id as postid,p.*,u.username,u.nickname,u.usertx,u.title as usertitle,u.sex,u.signature,u.viptime,u.exp,s.section_name,s.section_icon,sub.section_name as sub_section_name")
            ->order("p.create_time", "desc")
            ->where("po.userid = " . $user_all_info["id"] . " and po.type = 2 and po.appid = " . $data["appid"])
            ->page($this->page)
            ->limit($this->limit)
            ->select()->toArray();
        $ip = new IpLocation();
        foreach ($result as $key => $value) {
            //截取帖子内容
            //判断改帖子是否是付费阅读
            if ($value["paid_reading"] == 0) {
                $result[$key]["content"] = mb_substr($value["content"], 0, 50, "utf-8") . "...";
            } else {
                $result[$key]["content"] = mb_substr($value["content"], 0, $value["preview_word_count"], "utf-8") . "...";
            }
            $result[$key]["ip_address"] = $value["ip"] == "" ? "" : $ip->getDetail($value["ip"])["dataA"];
            $result[$key]["img_url"] = array_filter(explode(",", $value["img_url"]));
            $result[$key]["usertitle"] = array_filter(explode(",", $value["usertitle"]));
            $result[$key]["sex"] = $value["sex"];
            $result[$key]["sexName"] = $value["sex"] == 0 ? "男" : "女";
            //获取用户的徽章
            $result[$key]["badge"] = Db::name("polymorphic")
                ->alias("p")
                ->join("bagge b", "b.id=p.other_id")
                ->where("p.userid", $value["userid"])
                ->where("p.type", 5)
                ->where("b.is_view", 0)
                ->where("p.wearing", 0)
                ->order(["b.type" => $this->medal_sorting, "b.sort" => "desc"])
                ->field("b.id,b.name,b.icon,b.type,case when p.expiration_time = '9999' then '永久' else p.expiration_time end as expiration_time")
                ->select()->toArray();
            //是否是会员
            if (time() < $value["viptime"]) {
                $result[$key]["vip"] = true;
            } else {
                $result[$key]["vip"] = false;
            }
            //经验等级
            $arr = $this->app_info["grade"];
            $grades = eval("return $arr;");
            $result[$key]["hierarchy"] = "";
            if (is_array($grades)) {
                foreach ($grades as $k1 => $v1) {
                    if ($result[$key]['exp'] >= $k1) {
                        $result[$key]["hierarchy"] = $v1;
                    } else {
                        break;
                    }
                }
            }
            $result[$key]["create_time_ago"] = change_time_type($value["create_time"]);
            $result[$key]["update_time_ago"] = change_time_type($value["update_time"]);
            //帖子访问量
            $result[$key]["view"] = Db::name("polymorphic")->where("other_id", $value["id"])->where("type", 4)->count();
            $result[$key]["view"] = formatNumber($result[$key]["view"]);
            //点赞量
            $result[$key]["thumbs"] = Db::name("polymorphic")->where("other_id", $value["id"])->where("type", 3)->count();
            $result[$key]["thumbs"] = formatNumber($result[$key]["thumbs"]);
            //评论量
            $result[$key]["comment"] = Db::name("comments")->where("postid", $value["id"])->count();
            $result[$key]["comment"] = formatNumber($result[$key]["comment"]);
            //去除不需要的字段
            unset($result[$key]["id"]);
            unset($result[$key]["ip"]);
            unset($result[$key]["viptime"]);
            unset($result[$key]["file"]);
            unset($result[$key]["reading_price"]);
            unset($result[$key]["preview_word_count"]);
            unset($result[$key]["file_download_price"]);
        }
        $pagecount = Db::name('polymorphic')
            ->alias('po')
            ->join("forum_posts p", "po.other_id=p.userid")
            ->join("user u", "u.id=p.userid")
            ->join("forum_section s", "s.id=p.section_id")
            ->join("forum_section sub", "sub.id=p.sub_section_id")
            ->field("p.id as postid,p.*,u.username,u.nickname,u.usertx,u.title as usertitle,u.sex,u.signature,u.viptime,u.exp,s.section_name,s.section_icon,sub.section_name as sub_section_name")
            ->order("p.create_time", "desc")
            ->where("po.userid = " . $user_all_info["id"] . " and po.type = 2 and po.appid = " . $data["appid"])
            ->count();
        $data_rs["list"] = $result;
        $data_rs["pagecount"] = ceil($pagecount / $this->limit) == 0 ? 1 : ceil($pagecount / $this->limit);
        $data_rs["current_number"] = $this->page;
        $this->json(1, "success", $data_rs);
    }

    //对评论的打赏
    public function rewarding_comments()
    {
        $data = input();
        $rule = [
            'usertoken|用户token' => 'require',
            'commentid|评论id' => 'require|number',
            'money|打赏金额' => 'require|number',
            'type|打赏方式' => 'require',
        ];
        $validate = new Validate();
        $validate->rule($rule);
        $result = $validate->check($data);
        if (!$result) {
            $this->json(0, $validate->getError());
        }
        //判断打赏金额时积分还是金币 type 1 金币 2 积分 判断type只能为1或者2
        if ($data["type"] != 1 && $data["type"] != 2) {
            $this->json(0, "type参数错误");
        }
        $user_all_info = $this->user_info;
        //判断用户是否有足够的余额
        if ($data['type'] == 1) {
            $this->assertAssetBalance($user_all_info, "money", $data["money"]);
        } else {
            $this->assertAssetBalance($user_all_info, "integral", $data["money"]);
        }
        //判断该评论是否存在
        $comment_info = Db::name("comments")->where("id", $data["commentid"])->find();
        if (!$comment_info) {
            $this->json(0, "该评论不存在");
        }
        //判断该评论是否是自己的
        if ($comment_info["userid"] == $user_all_info["id"]) {
            $this->json(0, "不能打赏自己的评论");
        }
        //为审核的评论不能打赏
        if ($comment_info["status"] != 1) {
            $this->json(0, "该评论正在审核中，不能打赏");
        }
        //查询用户是否已经打赏过该评论
        $is_reward = Db::name("post_payment")->where("comment_id", $data["commentid"])->where("userid", $user_all_info["id"])->where("type", 3)->find();
        if ($is_reward) {
            if ($this->app_info["forum_configuration"]["post_tipping_time_limit"] != 0) {
                if (time() - strtotime($is_reward["create_time"]) < $this->app_info["forum_configuration"]["post_tipping_time_limit"]) {
                    $this->json(0, "您已经打赏过该评论,请稍后再试");
                }
            }
        }
        //判断打赏金额是否足够并扣除用户余额
        if ($data["type"] == 1) {
            //扣除用户余额
            $user_all_info["money"] = $user_all_info["money"] - $data["money"];
            Db::name("user")->where("id", $user_all_info["id"])->update(["money" => $user_all_info["money"]]);
            add_user_bill($user_all_info, 10, "-" . $data["money"], "打赏" . $comment_info["content"] . "评论", 0);
            //增加用户余额
            $user_info = Db::name("user")->where("id", $comment_info["userid"])->find();
            $user_info["money"] = $user_info["money"] + $data["money"];
            Db::name("user")->where("id", $user_info["id"])->update(["money" => $user_info["money"]]);
            add_user_bill($user_info, 10, "+" . $data["money"], "被打赏" . $comment_info["content"] . "评论", 0);
        } else {
            //扣除用户积分
            $user_all_info["integral"] = $user_all_info["integral"] - $data["money"];
            Db::name("user")->where("id", $user_all_info["id"])->update(["integral" => $user_all_info["integral"]]);
            add_user_bill($user_all_info, 10, "-" . $data["money"], "打赏" . $comment_info["content"] . "评论", 1);
            //增加用户积分
            $user_info = Db::name("user")->where("id", $comment_info["userid"])->find();
            $user_info["integral"] = $user_info["integral"] + $data["money"];
            Db::name("user")->where("id", $user_info["id"])->update(["integral" => $user_info["integral"]]);
            add_user_bill($user_info, 10, "+" . $data["money"], "被打赏" . $comment_info["content"] . "评论", 1);
        }
        //添加打赏记录
        $adddata = [
            "appid" => $this->appid,
            "amount" => $data["money"],
            "userid" => $user_all_info["id"],
            "postid" => 0,
            "comment_id" => $comment_info["id"],
            "type" => 3,
            "create_time" => date("Y-m-d H:i:s", time()),
            "payment" => $data["type"],
        ];
        Db::name("post_payment")->insert($adddata);
        $this->json(1, "打赏成功");
    }

    //利用appkey 增减 用户金币或积分 会员天数
    public function admin_increase_decrease()
    {
        if ($this->app_info["increase_decrease"] == 0) {
            $this->json(0, "该应用没有开启增减用户金币或积分或会员天数功能");
        }
        $data = input();
        $rule = [
            'appkey|应用key' => 'require',
            'number|数量' => 'require|number',
            'category|类别' => 'require|number',
            'type|类型' => 'require|number',
        ];
        $validate = new Validate();
        $validate->rule($rule);
        $result = $validate->check($data);
        if (!$result) {
            $this->json(0, $validate->getError());
        }
        //userid 和 username 必须一个
        if (!isset($data["userid"]) && !isset($data["username"])) {
            $this->json(0, "userid和username必须一个");
        }
        //判断category 1 金币 2 积分 3 会员天数 只能为这三个
        if ($data["category"] != 1 && $data["category"] != 2 && $data["category"] != 3) {
            $this->json(0, "category参数错误");
        }
        //判断type 1 增加 2 减少 只能为这两个
        if ($data["type"] != 1 && $data["type"] != 2) {
            $this->json(0, "type参数错误");
        }
        if ((float)$data["number"] <= 0) {
            $this->json(0, "数量必须大于0");
        }
        if ($data["category"] == 1 && !preg_match('/^\d+(\.\d{1,2})?$/', (string)$data["number"])) {
            $this->json(0, "金币金额格式不正确，最多支持小数点后两位");
        }
        if (in_array((int)$data["category"], [2, 3], true) && !preg_match('/^\d+$/', (string)$data["number"])) {
            $this->json(0, "积分和会员天数必须为正整数");
        }
        $appkey = $this->app_info['appkey'];
        if ($data["appkey"] != $appkey) {
            $this->json(0, "appkey错误");
        }
        if (isset($data["userid"])) {
            $user_info = Db::name("user")->where("id", $data["userid"])->where("appid", $this->appid)->find();
            if (!$user_info) {
                $this->json(0, "用户不存在");
            }
        } else {
            $user_info = Db::name("user")->where("username", $data["username"])->where("appid", $this->appid)->find();
            if (!$user_info) {
                $this->json(0, "用户不存在");
            }
        }
        Db::startTrans();
        try {
            $user_info = Db::name("user")
                ->where("id", $user_info["id"])
                ->where("appid", $this->appid)
                ->lock(true)
                ->find();
            if (!$user_info) {
                throw new \Exception("用户不存在");
            }
            if ($data["category"] == 1) {
                $number = $this->walletAmountLabel($data["number"]);
                if ($data["type"] == 1) {
                    Db::name("user")->where("id", $user_info["id"])->where("appid", $this->appid)->update(["money" => Db::raw("money + " . $number)]);
                    add_user_bill($user_info, 13, "+" . $number, "管理员赠送金币", 0);
                } else {
                    $this->assertAssetBalance($user_info, "money", $number);
                    Db::name("user")->where("id", $user_info["id"])->where("appid", $this->appid)->update(["money" => Db::raw("money - " . $number)]);
                    add_user_bill($user_info, 13, "-" . $number, "管理员减少金币", 0);
                }
            }
            if ($data["category"] == 2) {
                $number = (int)$data["number"];
                if ($number <= 0) {
                    throw new \Exception("积分数量必须为正整数");
                }
                if ($data["type"] == 1) {
                    Db::name("user")->where("id", $user_info["id"])->where("appid", $this->appid)->update(["integral" => Db::raw("integral + " . $number)]);
                    add_user_bill($user_info, 13, "+" . $number, "管理员赠送积分", 1);
                } else {
                    $this->assertAssetBalance($user_info, "integral", $number);
                    Db::name("user")->where("id", $user_info["id"])->where("appid", $this->appid)->update(["integral" => Db::raw("integral - " . $number)]);
                    add_user_bill($user_info, 13, "-" . $number, "管理员减少积分", 1);
                }
            }
            if ($data["category"] == 3) {
                //判断用户的会员是否过期
                if ($user_info["viptime"] < time()) {
                    $viptime = time();
                } else {
                    $viptime = $user_info["viptime"];
                }
                if ($data["type"] == 1) {
                    $end_viptime = $viptime + ($data["number"] * 86400);
                    Db::name("user")->where("id", $user_info["id"])->where("appid", $this->appid)->update(["viptime" => $end_viptime]);
                } else {
                    $end_viptime = $viptime - ($data["number"] * 86400);
                    Db::name("user")->where("id", $user_info["id"])->where("appid", $this->appid)->update(["viptime" => $end_viptime]);
                }
            }
            Db::commit();
        } catch (\Throwable $e) {
            Db::rollback();
            $this->json(0, $e->getMessage());
        }
        $this->json(1, "操作成功");
    }

    //收藏帖子 or 取消收藏
    public function collection_posts()
    {
        $data = input();
        $rule = [
            'usertoken' => 'require',
            'postid|帖子id' => 'require|number',
        ];
        $validate = new Validate();
        $validate->rule($rule);
        $result = $validate->check($data);
        if (!$result) {
            $this->json(0, $validate->getError());
        }
        $postinfo = Db::name("forum_posts")->where("id", $data["postid"])->where("appid", $data["appid"])->find();
        if (!$postinfo) {
            $this->json(0, "系统错误");
        }
        if ($postinfo["status"] != 1) {
            $this->json(0, "该文章暂未通过审核，无法收藏！");
        }
        $user_all_info = $this->user_info;
        $thumbsinfo = Db::name("polymorphic")->where("other_id", $data["postid"])->where("userid", $user_all_info["id"])->where("type", 6)->find();
        if ($thumbsinfo) {
            Db::name("polymorphic")->where("other_id", $data["postid"])->where("userid", $user_all_info["id"])->where("type", 6)->delete();
            $this->json(1, "取消收藏成功");
        }
        $adddata = [
            "appid" => $data["appid"],
            "create_time" => date("Y-m-d H:i:s", time()),
            "userid" => $user_all_info["id"],
            "other_id" => $data["postid"],
            "type" => 6
        ];
        Db::name("polymorphic")->insert($adddata);
        $this->json(1, "收藏成功");
    }

    //获取收藏记录
    public function get_collection_records()
    {
        $data = input();
        $rule = [
            'usertoken' => 'require',
        ];
        $validate = new Validate();
        $validate->rule($rule);
        $result = $validate->check($data);
        if (!$result) {
            $this->json(0, $validate->getError());
        }
        $user_all_info = $this->user_info;
        $where = "v.type = 6 and v.userid = {$user_all_info["id"]}";
        //板块id
        if (input("sectionid")) {
            $where .= " and a.section_id = {$data['sectionid']}";
        }
        //板块id
        if (input("sub_sectionid")) {
            $where .= " and a.sub_section_id = {$data['sub_sectionid']}";
        }
        $result = Db::name("polymorphic")
            ->alias("v")
            ->join("forum_posts a", "a.id=v.other_id")
            ->join("user u", "u.id=a.userid")
            ->join("forum_section s", "s.id=a.section_id")
            ->join("forum_section sub", "sub.id=a.sub_section_id")
            ->field("a.id as postid,a.*,u.username,u.nickname,u.usertx,u.title as usertitle,u.sex,u.signature,u.viptime,u.exp,s.section_name,s.section_icon,s.forum_section,sub.section_name as sub_section_name")
            ->where($where)
            ->order("v.id", "desc")
            ->limit($this->limit)
            ->page($this->page)
            ->select()->toArray();
        $pagecount = Db::name("polymorphic")
            ->alias("v")
            ->join("forum_posts a", "a.id=v.other_id")
            ->join("user u", "u.id=a.userid")
            ->join("forum_section s", "s.id=a.section_id")
            ->join("forum_section sub", "sub.id=a.sub_section_id")
            ->field("a.id as postid,a.*,u.username,u.nickname,u.usertx,u.title as usertitle,u.sex,u.signature,s.section_name,s.section_icon,sub.section_name as sub_section_name")
            ->where($where)
            ->count();
        $ip = new IpLocation();
        foreach ($result as $key => $value) {
            //截取帖子内容
            //判断改帖子是否是付费阅读
            if ($value["paid_reading"] == 0) {
                //如果内容字数小于设置的字数或者等于0则全部显示
                if (mb_strlen($value["content"], "utf-8") <= $this->app_info["forum_configuration"]["number_text_intercepted"] || $this->app_info["forum_configuration"]["number_text_intercepted"] == 0) {
                    $result[$key]["content"] = $value["content"];
                } else {
                    $result[$key]["content"] = mb_substr($value["content"], 0, $this->app_info["forum_configuration"]["number_text_intercepted"], "utf-8") . "...";
                }
            } else {
                $result[$key]["content"] = mb_substr($value["content"], 0, $value["preview_word_count"], "utf-8") . "...";
            }
            $result[$key]["ip_address"] = $value["ip"] == "" ? "" : $ip->getDetail($value["ip"])["dataA"];
            $result[$key]["img_url"] = array_filter(explode(",", $value["img_url"]));
            $result[$key]["usertitle"] = array_filter(explode(",", $value["usertitle"]));
            $result[$key]["sex"] = $value["sex"];
            $result[$key]["sexName"] = $value["sex"] == 0 ? "男" : "女";
            //判断当前发帖的用户是否是版主
            $result[$key]["is_section_moderator"] = 0;
            $section_id_array = explode(",", $value["forum_section"]);
            if (in_array($value["userid"], $section_id_array)) {
                $result[$key]["is_section_moderator"] = 1;
            }
            //获取用户的徽章
            $result[$key]["badge"] = Db::name("polymorphic")
                ->alias("p")
                ->join(
                    "bagge b",
                    "b.id=p.other_id"
                )
                ->where("p.userid", $value["userid"])
                ->where("p.type", 5)
                ->where("b.is_view", 0)
                ->where("p.wearing", 0)
                ->order(["b.type" => $this->medal_sorting, "b.sort" => "desc"])
                ->field("b.id,b.name,b.icon,b.type,case when p.expiration_time = '9999' then '永久' else p.expiration_time end as expiration_time")
                ->select()->toArray();
            //是否是会员
            if (time() < $value["viptime"]) {
                $result[$key]["vip"] = true;
            } else {
                $result[$key]["vip"] = false;
            }
            //经验等级
            $arr = $this->app_info["grade"];
            $grades = eval("return $arr;");
            $result[$key]["hierarchy"] = "";
            if (is_array($grades)) {
                foreach ($grades as $k1 => $v1) {
                    if ($result[$key]['exp'] >= $k1) {
                        $result[$key]["hierarchy"] = $v1;
                    } else {
                        break;
                    }
                }
            }
            $result[$key]["create_time_ago"] = change_time_type($value["create_time"]);
            $result[$key]["update_time_ago"] = change_time_type($value["update_time"]);
            //帖子访问量
            $result[$key]["view"] = Db::name("polymorphic")->where("other_id", $value["id"])->where("type", 4)->count();
            $result[$key]["view"] = formatNumber($result[$key]["view"]);
            //点赞量
            $result[$key]["thumbs"] = Db::name("polymorphic")->where("other_id", $value["id"])->where("type", 3)->count();
            $result[$key]["thumbs"] = formatNumber($result[$key]["thumbs"]);
            //评论量
            $result[$key]["comment"] = Db::name("comments")->where("postid", $value["id"])->count();
            $result[$key]["comment"] = formatNumber($result[$key]["comment"]);
            //去除不需要的字段
            unset($result[$key]["id"]);
            unset($result[$key]["ip"]);
            unset($result[$key]["file"]);
            unset($result[$key]["reading_price"]);
            unset($result[$key]["preview_word_count"]);
            unset($result[$key]["file_download_price"]);
            $result[$key]["reward"] = Db::name("post_payment")->where("postid", $value["id"])->where("type", 2)->sum("amount");
            $result[$key]["payers"] = Db::name("post_payment")->where("postid", $value["id"])->where("type = 0 or type = 1")->count();
        }
        $data_rs["list"] = $result;
        $data_rs["pagecount"] = ceil($pagecount / $this->limit) == 0 ? 1 : ceil($pagecount / $this->limit);
        $data_rs["current_number"] = (int)$this->page;
        $this->json(1, "success", $data_rs);
    }

    public function upload()
    {
        $data = input();
        $rule = [
            'usertoken' => 'require',
        ];
        $validate = new Validate();
        $validate->rule($rule);
        $result = $validate->check($data);
        if (!$result) {
            $this->json(0, $validate->getError());
        }
        $user_all_info = $this->user_info;
        try {
            $upload = new Upload($user_all_info["id"]);
            $result = $upload->upload('file');
            //兼容多文件上传
            $url = [];
            if (isset($result[0])) {
                foreach ($result as $key => $value) {
                    $url[] = $value["filePath"];
                }
            } else {
                $url = $result["filePath"];
            }
            $this->json(1, "success", ["url" => $url]);
        } catch (\Exception $th) {
            $this->json(0, $th->getMessage());
        }
    }

    //获取待审核评论列表
    public function get_pending_review_comments()
    {
        $data = input();
        $rule = [
            'usertoken|用户token' => 'require',
        ];
        $validate = new Validate();
        $validate->rule($rule);
        $result = $validate->check($data);
        if (!$result) {
            $this->json(0, $validate->getError());
        }
        //获取属于当前用户的管理版块的待审核帖子
        $user_all_info = $this->user_info;
        $sectioninfo = Db::name("forum_section")->where("appid", $this->appid)->select()->toArray();
        //定义一个空数组,存储当前用户管理的版块
        $section_arr = [];
        foreach ($sectioninfo as $key => $value) {
            $section_admin = array_filter(explode(",", $value["forum_section"]));
            if (in_array($user_all_info["id"], $section_admin)) {
                $section_arr[] = $value["id"];
            }
        }
        if (count($section_arr) == 0) {
            $this->json(0, "您没有管理的版块");
        }
        $result = Db::name("comments")
            ->alias("c")
            ->join("user u", "u.id=c.userid")
            ->join("forum_posts p", "p.id=c.postid")
            ->join("forum_section s", "s.id=p.section_id")
            ->field("c.*,p.title,u.username,s.section_name,u.username,u.nickname,u.usertx,u.title as usertitle,u.exp,u.viptime")
            ->where("c.appid", $this->appid)
            ->where("c.status", 0)
            ->where("p.section_id", "in", $section_arr)
            ->order("c.time", "asc")
            ->limit($this->limit)
            ->page($this->page)
            ->select()->toArray();
        $pagecount = Db::name("comments")
            ->alias("c")
            ->join("user u", "u.id=c.userid")
            ->join("forum_posts p", "p.id=c.postid")
            ->join("forum_section s", "s.id=p.section_id")
            ->field("c.*,p.title,u.username,s.section_name")
            ->where("c.appid", $this->appid)
            ->where("c.status", 0)
            ->where("p.section_id", "in", $section_arr)
            ->count();
        $ip = new IpLocation();
        foreach ($result as $key => $value) {
            $result[$key]["ip_address"] = $value["ip"] == "" ? "未知" : $ip->getDetail($value["ip"])["dataA"];
            $result[$key]["image_path"] = $value["image_path"] == "" ? "" : $value["image_path"];
            unset($result[$key]["ip"]);
            $result[$key]["usertitle"] = array_filter(explode(",", $value["usertitle"]));
            //假入有上级评论则插入
            //上级评论者用户昵称
            $result[$key]["parentnickname"] = "";
            $result[$key]["parentusername"] = "";
            //上级评论内容
            $result[$key]["parentcontent"] = "";
            if ($value["parentid"] != 0) {
                $parentcommentinfo = db("comments")
                    ->alias("c")
                    ->join("user u", "u.id = c.userid")
                    ->join("forum_posts a", "a.id = c.postid")
                    ->where("c.id", $value["parentid"])
                    ->field("c.id,c.content,u.nickname,u.username")
                    ->find();
                //上级评论者用户昵称
                $result[$key]["parentnickname"] = $parentcommentinfo["nickname"];
                $result[$key]["parentusername"] = $parentcommentinfo["username"];
                //上级评论内容
                $result[$key]["parentcontent"] = $parentcommentinfo["content"];
            }
            $result[$key]["image_path"] = array_filter(explode(",", $value["image_path"]));
            unset($result[$key]["status"]);
            //经验等级
            $arr = $this->app_info["grade"];
            $grades = eval("return $arr;");
            $result[$key]["hierarchy"] = "";
            if (is_array($grades)) {
                foreach ($grades as $k1 => $v1) {
                    if ($result[$key]['exp'] >= $k1) {
                        $result[$key]["hierarchy"] = $v1;
                    } else {
                        break;
                    }
                }
            }
            //判断用户是否是版主
            $plate_list = Db::name("forum_section")->where("appid", $this->appid)->select()->toArray();
            $result[$key]["is_section_moderator"] = 0;
            foreach ($plate_list as $k1 => $v1) {
                $section_id_array = explode(",", $v1["forum_section"]);
                if (in_array($value["userid"], $section_id_array)) {
                    $result[$key]["is_section_moderator"] = 1;
                    break;
                }
            }
            //是否是会员
            if (time() < $value["viptime"]) {
                $result[$key]["vip"] = true;
            } else {
                $result[$key]["vip"] = false;
            }
            unset($result[$key]["viptime"]);
            //获取用户的徽章
            $result[$key]["badge"] = Db::name("polymorphic")
                ->alias("p")
                ->join("bagge b", "b.id=p.other_id")
                ->where("p.userid", $value["userid"])
                ->where("p.type", 5)
                ->where("b.is_view", 0)
                ->where("p.wearing", 0)
                ->order(["b.type" => $this->medal_sorting, "b.sort" => "desc"])
                ->field("b.id,b.name,b.icon,b.type,case when p.expiration_time = '9999' then '永久' else p.expiration_time end as expiration_time")
                ->select()->toArray();
            $result[$key]["reward"] = Db::name("post_payment")->where("comment_id", $value["id"])->where("type", 3)->sum("amount");
            $result[$key]["reward_user_list"] = Db::name("post_payment")
                ->alias("a")
                ->join("user b", "a.userid = b.id")
                ->field("a.amount,a.payment,b.id,b.username,b.nickname,b.usertx")
                ->where("comment_id", $value["id"])
                ->where("type", 3)
                ->select()->toArray();
            $result[$key]["sub_comments_count"] = Db::name('comments')->where("parentid", $value["id"])->count();
            $result[$key]["sub_comments_count"] = formatNumber($result[$key]["sub_comments_count"]);
            $result[$key]["time_ago"] = change_time_type($value["time"]);
        }
        $data_rs["list"] = $result;
        $data_rs["pagecount"] = ceil($pagecount / $this->limit) == 0 ? 1 : ceil($pagecount / $this->limit);
        $data_rs["current_number"] = (int)$this->page;
        $this->json(1, "success", $data_rs);
    }

    //审核评论
    public function review_comments()
    {
        $data = input();
        $rule = [
            'usertoken|用户token' => 'require',
            'commentid|评论ID' => 'require|number',
            'status|评论状态' => 'require|number',
        ];
        $validate = new Validate();
        $validate->rule($rule);
        $result = $validate->check($data);
        if (!$result) {
            $this->json(0, $validate->getError());
        }
        //判断status 只能为 1已审核(正常)2审核未通过
        if (!in_array($data["status"], [1, 2])) {
            $this->json(0, "status参数错误");
        }
        $user_all_info = $this->user_info;
        //获取评论信息
        $comment_info = Db::name("comments")->where("id", $data["commentid"])->find();
        if (!$comment_info) {
            $this->json(0, "评论不存在");
        }
        if ($comment_info["status"] == 1) {
            $this->json(0, "评论已审核");
        }
        //获取帖子信息
        $postsinfo = Db::name("forum_posts")->where("appid", $this->appid)->where("id", $comment_info["postid"])->find();
        if (!$postsinfo) {
            $this->json(0, "帖子不存在");
        }
        //获取版块管理员
        $sectioninfo = Db::name("forum_section")->where("id", $postsinfo["section_id"])->find();
        if (!$sectioninfo) {
            $this->json(0, "版块不存在");
        }
        $section_admin = array_filter(explode(",", $sectioninfo["forum_section"]));
        if (!in_array($user_all_info["id"], $section_admin)) {
            $this->json(0, "您不是版块管理员");
        }
        //审核评论
        $result = Db::name("comments")->where("id", $data["commentid"])->update(["status" => $data["status"]]);
        if ($result) {
            $result = Db::name("comments")->where("id", $data["commentid"])->find();
            if ($data["status"] == 1) {
                $addmessagedata = [
                    "title" => "评论审核通过",
                    "content" => "您的评论【" . $result['content'] . "】审核通过",
                    "send_to" => 0,
                    "appid" => $result['appid'],
                    "time" => date("Y-m-d H:i:s", time()),
                    "type" => 0,
                    "user_id" => $result['userid'],
                ];
                Db::name("message_notification")->insert($addmessagedata);
                forum_add_equity($result['postid'], $result["userid"], 1, $result);
                //更新贴子的更新时间
                Db::name("forum_posts")->where("id", "=", $result['postid'])->update(["update_time" => date("Y-m-d H:i:s", time())]);
            } else {
                $addmessagedata = [
                    "title" => "评论审核未通过",
                    "content" => "您的评论【" . $result['content'] . "】审核未通过,原因：" . input("reason_review") == '' ? "违规" : input("reason_review"),
                    "send_to" => 0,
                    "appid" => $result['appid'],
                    "time" => date("Y-m-d H:i:s", time()),
                    "type" => 0,
                    "user_id" => $result['userid'],
                ];
                Db::name("message_notification")->insert($addmessagedata);
            }
            $this->json(1, "success", []);
        } else {
            $this->json(0, "审核失败");
        }
    }

    //应用商店api
    //应用分类列表
    public function app_category_list()
    {
        $list = Db::name('apps_category')
            ->where('pid', 0)
            ->where("appid", $this->appid)
            ->field('id,name,icon,create_time')
            ->order("sort", "desc")
            ->limit($this->limit)
            ->page($this->page)
            ->select()->toArray();
        $pagecount = Db::name('apps_category')
            ->where('pid', 0)
            ->where("appid", $this->appid)
            ->count();
        foreach ($list as $key => $value) {
            $list[$key]["children"] = Db::name('apps_category')
                ->where("appid", $this->appid)
                ->where("pid", $value["id"])
                ->field('id,name,icon,create_time')
                ->order("sort", "desc")
                ->select()->toArray();
        }
        $data_rs["list"] = $list;
        $data_rs["pagecount"] = ceil($pagecount / $this->limit) == 0 ? 1 : ceil($pagecount / $this->limit);
        $data_rs["current_number"] = $this->page;
        $this->json(1, "success", $data_rs);
    }

    //获取下级分类列表
    public function app_category_children_list()
    {
        $data = input();
        $rule = [
            'pid|分类id' => 'require|number',
        ];
        $validate = new Validate();
        $validate->rule($rule);
        $result = $validate->check($data);
        if (!$result) {
            $this->json(0, $validate->getError());
        }
        $list = Db::name('apps_category')
            ->where('pid', $data["pid"])
            ->where("appid", $this->appid)
            ->field('id,name,icon,create_time')
            ->order("sort", "desc")
            ->limit($this->limit)
            ->page($this->page)
            ->select()->toArray();
        $pagecount = Db::name('apps_category')
            ->where('pid', 0)
            ->where("appid", $this->appid)
            ->count();
        $data_rs["list"] = $list;
        $data_rs["pagecount"] = ceil($pagecount / $this->limit) == 0 ? 1 : ceil($pagecount / $this->limit);
        $data_rs["current_number"] = $this->page;
        $this->json(1, "success", $data_rs);
    }

    //获取分类下的应用列表
    public function get_apps_list()
    {
        $data = input();
        $where = " asv.status = 2 and as.appid = {$this->appid}";
        $category_id = input("category_id/d");
        if ($category_id != 0) {
            $where .= " and as.category_id = {$category_id}";
        }
        $sub_category_id = input("sub_category_id/d");
        if ($sub_category_id != 0) {
            $where .= " and as.sub_category_id = {$sub_category_id}";
        }
        $userid = input("userid/d");
        if ($userid != 0) {
            $where .= " and as.userid = {$userid}";
        }
        $appname = input("appname/s");
        if ($appname != "") {
            $where .= " and as.appname like '%{$appname}%'";
        }
        //定义sort 只能为那几个
        $sort_array = ['create_time', 'update_time'];
        $sort = input("?sort") ? $data["sort"] : "create_time";
        $sortOrder = input("?sortOrder") ? $data["sortOrder"] : 'desc';
        if ($sortOrder != "desc" && $sortOrder != "asc") {
            $this->json(0, "sortOrder参数错误");
        }
        if (!in_array($sort, $sort_array)) {
            $this->json(0, "sort参数错误");
        }
        $list = Db::name('apps')
            ->alias("as")
            ->join("apps_category ac", "ac.id=as.category_id")
            ->join("apps_category sub_ac", "sub_ac.id=as.sub_category_id")
            ->join("user u", "u.id=as.userid")
            ->join("app a", "a.appid=as.appid")
            //链接mr_apps_version 表 只取id最大的
            ->join("apps_version asv", "asv.apps_id=as.id and asv.id=(select max(id) from mr_apps_version where status=2 and apps_id=as.id)")
            ->where($where)
            ->field('as.*,ac.name as category_name,ac.icon as category_icon,sub_ac.name as sub_category_name
            ,u.username,u.nickname,u.usertx,u.sex,u.signature,u.exp,u.viptime,a.appname as appappname,asv.version,
            asv.id as apps_version_id,asv.create_time as version_create_time,asv.ip')
            ->order($sort, $sortOrder)
            ->limit($this->limit)
            ->page($this->page)
            ->select()->toArray();
        $pagecount = Db::name('apps')
            ->alias("as")
            ->join("apps_category ac", "ac.id=as.category_id")
            ->join("apps_category sub_ac", "sub_ac.id=as.sub_category_id")
            ->join("user u", "u.id=as.userid")
            ->join("app a", "a.appid=as.appid")
            //链接mr_apps_version 表 只取id最大的
            ->join("apps_version asv", "asv.apps_id=as.id and asv.id=(select max(id) from mr_apps_version where status=2 and apps_id=as.id)")
            ->where($where)
            ->count();
        $ip = new IpLocation();
        foreach ($list as $key => $value) {
            $list[$key]["app_introduction_image_array"] = explode(",", $value["app_introduction_image"]);
            $list[$key]["ip_address"] = $value["ip"] == "" ? "" : $ip->getDetail($value["ip"])["dataA"];
            unset($list[$key]["ip"]);
            $list[$key]["sexName"] = $value["sex"] == 0 ? "男" : "女";
            //获取用户的徽章
            $list[$key]["badge"] = Db::name("polymorphic")
                ->alias("p")
                ->join("bagge b", "b.id=p.other_id")
                ->where("p.userid", $value["userid"])
                ->where("p.type", 5)
                ->where("b.is_view", 0)
                ->where("p.wearing", 0)
                ->order(["b.type" => $this->medal_sorting, "b.sort" => "desc"])
                ->field("b.id,b.name,b.icon,b.type,case when p.expiration_time = '9999' then '永久' else p.expiration_time end as expiration_time")
                ->select()->toArray();
            //是否是会员
            if (time() < $value["viptime"]) {
                $list[$key]["vip"] = true;
            } else {
                $list[$key]["vip"] = false;
            }
            unset($list[$key]["viptime"]);
            //经验等级
            $arr = $this->app_info["grade"];
            $grades = eval("return $arr;");
            $list[$key]["hierarchy"] = "";
            if (is_array($grades)) {
                foreach ($grades as $k1 => $v1) {
                    if ($value['exp'] >= $k1) {
                        $list[$key]["hierarchy"] = $v1;
                    } else {
                        break;
                    }
                }
            }
            $list[$key]["is_user_pay"] = true;
            //查询此用户是否付费了该应用
            if ($value["is_pay"] != 0) {
                if (input("usertoken") == "") {
                    $list[$key]["is_user_pay"] = false;
                    $list[$key]["download"] = "";
                } else {
                    $user_all_info = $this->user_info;
                    if ($user_all_info["id"] == $list[$key]["userid"]) {
                        $list[$key]["is_user_pay"] = true;
                    } else {
                        $is_pay = Db::name("apps_payment")
                            ->where("userid", $user_all_info["id"])
                            ->where("apps_id", $value["id"])
                            ->where("apps_version_id", $value["apps_version_id"])
                            ->where("type", 0)
                            ->find();
                        if ($is_pay) {
                            $list[$key]["is_user_pay"] = true;
                        } else {
                            $list[$key]["is_user_pay"] = false;
                            $list[$key]["download"] = "";
                        }
                    }
                }
            }
            $list[$key]["download_count"] = Db::name("polymorphic")->where('other_id', $value["apps_version_id"])->where("type", 6)->count();
            $list[$key]["comment_count"] = Db::name("apps_comments")->where("apps_id", $value["id"])->count();
            $list[$key]["user_pay_count"] = Db::name("apps_payment")->where("apps_id", $value["id"])->where("type", 0)->count();
            $list[$key]["reward_count"] = Db::name("apps_payment")->where("apps_id", $value["id"])->where("type", 1)->count();
        }
        $data_rs["list"] = $list;
        $data_rs["pagecount"] = ceil($pagecount / $this->limit) == 0 ? 1 : ceil($pagecount / $this->limit);
        $data_rs["current_number"] = $this->page;
        $this->json(1, "success", $data_rs);
    }

    //获取应用详情
    public function get_apps_information()
    {
        $data = input();
        $rule = [
            'apps_id|应用id' => 'require|number',
            'apps_version_id|应用版本id' => 'number',
        ];
        $validate = new Validate();
        $validate->rule($rule);
        $result = $validate->check($data);
        if (!$result) {
            $this->json(0, $validate->getError(), []);
        }
        if (input('apps_version_id') == 0 || input('apps_version_id') == "") {
            $apps_version_join_info = "asv.apps_id=as.id and asv.id=(select max(id) from mr_apps_version where status=2 and apps_id=as.id)";
        } else {
            $apps_version_join_info = "asv.apps_id=as.id and asv.id={$data["apps_version_id"]}";
        }
        $list = Db::name('apps')
            ->alias("as")
            ->join("apps_category ac", "ac.id=as.category_id")
            ->join("apps_category sub_ac", "sub_ac.id=as.sub_category_id")
            ->join("user u", "u.id=as.userid")
            ->join("app a", "a.appid=as.appid")
            //链接mr_apps_version 表 只取id最大的
            ->join("apps_version asv", $apps_version_join_info)
            ->where("as.id", $data["apps_id"])
            ->field('as.*,ac.name as category_name,ac.icon as category_icon,sub_ac.name as sub_category_name
            ,u.username,u.nickname,u.usertx,u.sex,u.signature,u.exp,u.viptime,a.appname as appappname,asv.version,
            asv.id as apps_version_id,asv.create_time as version_create_time,asv.ip')
            ->find();
        $ip = new IpLocation();
        $list["app_introduction_image_array"] = explode(",", $list["app_introduction_image"]);
        $list["ip_address"] = $list["ip"] == "" ? "" : $ip->getDetail($list["ip"])["dataA"];
        unset($list["ip"]);
        $list["sexName"] = $list["sex"] == 0 ? "男" : "女";
        //获取用户的徽章
        $list["badge"] = Db::name("polymorphic")
            ->alias("p")
            ->join("bagge b", "b.id=p.other_id")
            ->where("p.userid", $list["userid"])
            ->where("p.type", 5)
            ->where("b.is_view", 0)
            ->where("p.wearing", 0)
            ->order(["b.type" => $this->medal_sorting, "b.sort" => "desc"])
            ->field("b.id,b.name,b.icon,b.type,case when p.expiration_time = '9999' then '永久' else p.expiration_time end as expiration_time")
            ->select()->toArray();
        //是否是会员
        if (time() < $list["viptime"]) {
            $list["vip"] = true;
        } else {
            $list["vip"] = false;
        }
        unset($list["viptime"]);
        //经验等级
        $arr = $this->app_info["grade"];
        $grades = eval("return $arr;");
        $list["hierarchy"] = "";
        if (is_array($grades)) {
            foreach ($grades as $k1 => $v1) {
                if ($list['exp'] >= $k1) {
                    $list["hierarchy"] = $v1;
                } else {
                    break;
                }
            }
        }
        $list["is_user_pay"] = true;
        //查询此用户是否付费了该应用
        if ($list["is_pay"] == 1) {
            if (input("usertoken") == "") {
                $list["is_user_pay"] = false;
                $list["download"] = "";
            } else {
                $user_all_info = $this->user_info;
                if ($user_all_info["id"] == $list['userid']) {
                    $list["is_user_pay"] = true;
                } else {
                    $is_pay = Db::name("apps_payment")
                        ->where("userid", $user_all_info["id"])
                        ->where("apps_id", $list["id"])
                        ->where("apps_version_id", $list["apps_version_id"])
                        ->where("type", 0)
                        ->find();
                    if ($is_pay) {
                        $list["is_user_pay"] = true;
                    } else {
                        $list["is_user_pay"] = false;
                        $list["download"] = "";
                    }
                }
            }
        }
        $list["download_count"] = Db::name("polymorphic")->where("type", 6)->where("other_id", $list["apps_version_id"])->count();
        $list["comment_count"] = Db::name("apps_comments")->where("apps_id", $list["id"])->count();
        $list["user_pay_count"] = Db::name("apps_payment")->where("apps_id", $list["id"])->where("type", 0)->count();
        $list["reward_count"] = Db::name("apps_payment")->where("apps_id", $list["id"])->where("type", 1)->count();
        $this->json(1, "success", $list);
    }

    //获取该应用的历史版本
    public function get_apps_history_version()
    {
        $data = input();
        $rule = [
            'apps_id|应用id' => 'require|number',
            'status|状态' => 'in:0,1,2,3',
        ];
        $validate = new Validate();
        $validate->rule($rule);
        $result = $validate->check($data);
        if (!$result) {
            $this->json(0, $validate->getError(), []);
        }
        //先查询该应用是否时自己的
        $appsinfo = Db::name("apps")->where("id", $data["apps_id"])->find();
        if (!$appsinfo) {
            $this->json(0, "该应用不存在");
        }
        $where = "asv.apps_id = {$data["apps_id"]}";
        if (input("usertoken") == '') {
            $where .= " and (asv.status = 2 or asv.status = 3)";
        } else {
            if (input('status') != '' && $appsinfo["userid"] == $this->user_info["id"]) {
                $where .= " and asv.status = {$data['status']}";
            }
        }
        $list = Db::name('apps_version')
            ->alias("asv")
            ->join("apps as", "as.id=asv.apps_id")
            ->where($where)
            ->order("asv.id", "desc")
            ->field("asv.*")
            ->limit($this->limit)
            ->page($this->page)
            ->select()->toArray();
        $pagecount = Db::name('apps_version')
            ->alias("asv")
            ->join("apps as", "as.id=asv.apps_id")
            ->where($where)
            ->order("asv.id", "desc")
            ->count();
        $ip = new IpLocation();
        foreach ($list as $key => $value) {
            $list[$key]["ip_address"] = $value["ip"] == "" ? "" : $ip->getDetail($value["ip"])["dataA"];
            $other_info = json_decode($value["other_info"], true);
            $list[$key]["app_size"] = $other_info["app_size"];
            $list[$key]["appname"] = $other_info["appname"];
            $list[$key]["app_icon"] = $other_info["app_icon"];
            $list[$key]["is_pay"] = $other_info["is_pay"];
            $list[$key]["pay_money"] = $other_info["pay_money"];
            //查询下载次数
            $list[$key]["download_count"] = Db::name("polymorphic")->where('other_id', $value["id"])->where("type", 6)->count();
            unset($list[$key]["other_info"]);
            unset($list[$key]["ip"]);

            $list[$key]["is_user_pay"] = true;
            $list[$key]["download"] = $other_info["download"];
            if ($other_info["is_pay"] != 0) {
                if (input("usertoken") == "") {
                    $list[$key]["is_user_pay"] = false;
                    $list[$key]["download"] = "";
                } else {
                    $user_all_info = $this->user_info;
                    if ($user_all_info["id"] == $other_info["userid"]) {
                        $list[$key]["is_user_pay"] = true;
                    } else {
                        $is_pay = Db::name("apps_payment")
                            ->where("userid", $user_all_info["id"])
                            ->where("apps_id", $value["id"])
                            ->where("apps_version_id", $other_info["id"])
                            ->where("type", 0)
                            ->find();
                        if ($is_pay) {
                            $list[$key]["is_user_pay"] = true;
                        } else {
                            $list[$key]["is_user_pay"] = false;
                            $list[$key]["download"] = "";
                        }
                    }
                }
            }
        }
        $data_rs["list"] = $list;
        $data_rs["pagecount"] = ceil($pagecount / $this->limit) == 0 ? 1 : ceil($pagecount / $this->limit);
        $data_rs["current_number"] = $this->page;
        $this->json(1, "success", $data_rs);
    }

    //发布应用
    public function release_apps()
    {
        $data = input();
        $rule = [
            'usertoken|用户token' => 'require',
            'appname|应用名称' => 'require',
            'app_size|应用大小' => 'require',
            'app_introduce|应用介绍' => 'require',
            'is_pay|是否付费' => 'require|number',
            'app_version|应用版本' => 'require',
            'category_id|应用分类id' => 'require|number',
            'sub_category_id|应用子分类id' => 'require|number',
        ];
        if (input('is_pay') == 1) {
            $rule["pay_money|应用价格"] = 'require|number';
        }
        $validate = new Validate();
        $validate->rule($rule);
        $result = $validate->check($data);
        if (!$result) {
            $this->json(0, $validate->getError(), []);
        }
        $userinfo = $this->user_info;
        if (!in_array($data["is_pay"], [0, 1, 2])) {
            $this->json(0, "is_pay参数不合法");
        }
        //查询该应用是否已经存在
        $is_exist = Db::name("apps")->where("appid", $this->appid)->where("appname", $data["appname"])->find();
        if ($is_exist) {
            $this->json(0, "该应用已存在");
        }
        try {
            if (substr(input('icon'), 0, 4) == "http") {
                $icon_url = $data["icon"];
            } else {
                if (!empty($_FILES) && !empty($_FILES["icon"])) {
                    try {
                        $upload = new Upload($userinfo["id"]);
                        $result = $upload->upload('icon');
                    } catch (\Exception $th) {
                        $this->json(0, $th->getMessage());
                    }
                    $icon_url = $result["filePath"];
                } else {
                    $this->json(0, "请上传应用图标");
                }
            }
            if (substr(input('file'), 0, 4) == "http") {
                $download_url = $data["file"];
            } else {
                if (!empty($_FILES) && !empty($_FILES["file"])) {
                    try {
                        $upload = new Upload($userinfo["id"]);
                        $result = $upload->upload('file');
                    } catch (\Exception $th) {
                        $this->json(0, $th->getMessage());
                    }
                    $download_url = $result["filePath"];
                } else {
                    $this->json(0, "请上传应用文件");
                }
            }
            //应用介绍图
            if (substr(input('app_introduction_image'), 0, 4) == "http") {
                $app_introduction_image = $data["app_introduction_image"];
            } else {
                if (!empty($_FILES) && !empty($_FILES["app_introduction_image"])) {
                    try {
                        $upload = new Upload($userinfo["id"]);
                        $result = $upload->upload('app_introduction_image');
                    } catch (\Exception $th) {
                        $this->json(0, $th->getMessage());
                    }
                    $app_introduction_image = [];
                    foreach ($result as $key => $value) {
                        $app_introduction_image[] = $value["filePath"];
                    }
                    $app_introduction_image = array_filter($app_introduction_image);
                    $app_introduction_image = implode(",", $app_introduction_image);
                } else {
                    $this->json(0, "请上传应用介绍图");
                }
            }
            Db::startTrans();
            $add_data = [
                "appid" => $this->appid,
                "userid" => $userinfo["id"],
                "appname" => $data["appname"],
                "app_icon" => $icon_url,
                "app_size" => $data["app_size"],
                "app_explain" => input("app_explain"),
                "app_introduce" => $data["app_introduce"],
                "app_introduction_image" => $app_introduction_image,
                "is_pay" => $data["is_pay"],
                "pay_money" => $data["pay_money"],
                "download" => $download_url,
                "category_id" => $data["category_id"],
                "sub_category_id" => $data["sub_category_id"],
                "create_time" => date("Y-m-d H:i:s", time()),
                "update_time" => date("Y-m-d H:i:s", time()),
            ];
            $apps_id = Db::name("apps")->insertGetId($add_data);
            //查询apps信息
            $apps_info = Db::name("apps")->where("id", $apps_id)->find();
            $add_data_version = [
                "apps_id" => $apps_id,
                "version" => $data["app_version"],
                "other_info" => json_encode($apps_info, JSON_UNESCAPED_UNICODE),
                "status" => 0,
                "create_time" => date("Y-m-d H:i:s", time()),
                "ip" => get_client_ip(),
                "update_content" => input("update_content"),
            ];
            Db::name("apps_version")->insert($add_data_version);
            Db::commit();
            $this->json(1, "提交成功,请等待审核");
        } catch (\Exception $th) {
            Db::rollback();
            $this->json(0, $th->getMessage());
        }
    }

    //发布新版本
    public function release_new_version()
    {
        $data = input();
        $rule = [
            'usertoken|用户token' => 'require',
            'apps_id|应用id' => 'require|number',
            'appname|应用名称' => 'require',
            'app_size|应用大小' => 'require',
            'app_introduce|应用介绍' => 'require',
            'is_pay|是否付费' => 'require|number',
            'app_version|应用版本' => 'require',
            'category_id|应用分类id' => 'require|number',
            'sub_category_id|应用子分类id' => 'require|number',
        ];
        if (isset($data["is_pay"]) && $data["is_pay"] == 1) {
            $rule["pay_money|应用价格"] = 'require|number';
        }
        $validate = new Validate();
        $validate->rule($rule);
        $result = $validate->check($data);
        if (!$result) {
            $this->json(0, $validate->getError(), []);
        }
        $userinfo = $this->user_info;
        if (!in_array($data["is_pay"], [0, 1, 2])) {
            $this->json(0, "is_pay参数不合法");
        }
        //查询该应用是否已经存在
        $is_exist = Db::name("apps")->where("id", $data["apps_id"])->find();
        if (!$is_exist) {
            $this->json(0, "该应用不存在");
        }
        //查询版本是否存在
        $is_exist_version = Db::name("apps_version")->where("apps_id", $data["apps_id"])->where("version", $data["app_version"])->find();
        if ($is_exist_version) {
            $this->json(0, "该版本已存在");
        }
        //判断是不是自己的
        if ($is_exist["userid"] != $userinfo["id"]) {
            $this->json(0, "系统错误");
        }
        try {
            if (substr(input('icon'), 0, 4) == "http") {
                $icon_url = $data["icon"];
            } else {
                if (!empty($_FILES) && !empty($_FILES["icon"])) {
                    try {
                        $upload = new Upload($userinfo["id"]);
                        $result = $upload->upload('icon');
                    } catch (\Exception $th) {
                        $this->json(0, $th->getMessage());
                    }
                    $icon_url = $result["filePath"];
                } else {
                    $this->json(0, "请上传应用图标");
                }
            }
            if (substr(input('file'), 0, 4) == "http") {
                $download_url = $data["file"];
            } else {
                if (!empty($_FILES) && !empty($_FILES["file"])) {
                    try {
                        $upload = new Upload($userinfo["id"]);
                        $result = $upload->upload('file');
                    } catch (\Exception $th) {
                        $this->json(0, $th->getMessage());
                    }
                    $download_url = $result["filePath"];
                } else {
                    $this->json(0, "请上传应用文件");
                }
            }
            //应用介绍图
            if (substr(input('app_introduction_image'), 0, 4) == "http") {
                $app_introduction_image = $data["app_introduction_image"];
            } else {
                if (!empty($_FILES) && !empty($_FILES["app_introduction_image"])) {
                    try {
                        $upload = new Upload($userinfo["id"]);
                        $result = $upload->upload('app_introduction_image');
                    } catch (\Exception $th) {
                        $this->json(0, $th->getMessage());
                    }
                    $app_introduction_image = [];
                    foreach ($result as $key => $value) {
                        $app_introduction_image[] = $value["filePath"];
                    }
                    $app_introduction_image = array_filter($app_introduction_image);
                    $app_introduction_image = implode(",", $app_introduction_image);
                } else {
                    $this->json(0, "请上传应用介绍图");
                }
            }
            Db::startTrans();
            $app_info_data = [
                "id" => $is_exist["id"],
                "appname" => $data["appname"],
                "app_icon" => $icon_url,
                "app_size" => $data["app_size"],
                "app_explain" => input("app_explain"),
                "app_introduce" => $data["app_introduce"],
                "app_introduction_image" => $app_introduction_image,
                "is_pay" => $data["is_pay"],
                "pay_money" => $data["pay_money"],
                "download" => $download_url,
                "create_time" => date("Y-m-d H:i:s", time()),
                "update_time" => date("Y-m-d H:i:s", time()),
                "appid" => $this->appid,
                "userid" => $userinfo["id"],
                "category_id" => $data["category_id"],
                "sub_category_id" => $data["sub_category_id"],
            ];
            $add_data_version = [
                "apps_id" => $is_exist["id"],
                "version" => $data["app_version"],
                "other_info" => json_encode($app_info_data, JSON_UNESCAPED_UNICODE),
                "status" => 0,
                "create_time" => date("Y-m-d H:i:s", time()),
                "ip" => get_client_ip(),
                "update_content" => input("update_content"),
            ];
            Db::name("apps_version")->insert($add_data_version);
            Db::commit();
            $this->json(1, "提交成功,请等待审核");
        } catch (\Exception $th) {
            Db::rollback();
            $this->json(0, $th->getMessage());
        }
    }

    //获取用户自己已上传的应用列表
    public function get_user_apps_list()
    {
        $data = input();
        $rule = [
            'usertoken|用户token' => 'require'
        ];
        $validate = new Validate();
        $validate->rule($rule);
        $result = $validate->check($data);
        if (!$result) {
            $this->json(0, $validate->getError(), []);
        }
        $where = " as.appid = {$this->appid} and as.userid = {$this->user_info["id"]}";
        $list = Db::name('apps')
            ->alias("as")
            ->join("apps_category ac", "ac.id=as.category_id")
            ->join("apps_category sub_ac", "sub_ac.id=as.sub_category_id")
            ->where($where)
            ->field('as.*,ac.name as category_name,ac.icon as category_icon,sub_ac.name as sub_category_name')
            ->limit($this->limit)
            ->page($this->page)
            ->select()->toArray();
        $pagecount = Db::name('apps')
            ->alias("as")
            ->join("apps_category ac", "ac.id=as.category_id")
            ->join("apps_category sub_ac", "sub_ac.id=as.sub_category_id")
            ->where($where)
            ->field('as.*,ac.name as category_name,ac.icon as category_icon,sub_ac.name as sub_category_name')
            ->count();
        $data_rs["list"] = $list;
        $data_rs["pagecount"] = ceil($pagecount / $this->limit) == 0 ? 1 : ceil($pagecount / $this->limit);
        $data_rs["current_number"] = $this->page;
        $this->json(1, "success", $data_rs);
    }

    //修改应用信息
    public function edit_apps_info()
    {
        $data = input();
        $rule = [
            'usertoken|用户token' => 'require',
            'appname|应用名称' => 'require',
            'apps_id|应用id' => 'require|number',
            'app_version_id|应用版本id' => 'require|number',
            'app_size|应用大小' => 'require',
            'app_introduce|应用介绍' => 'require',
            'is_pay|是否付费' => 'require|number',
        ];
        if (input('is_pay') == 1) {
            $rule["pay_money|应用价格"] = 'require|number';
        }
        $validate = new Validate();
        $validate->rule($rule);
        $result = $validate->check($data);
        if (!$result) {
            $this->json(0, $validate->getError(), []);
        }
        $userinfo = $this->user_info;
        if (!in_array($data["is_pay"], [0, 1, 2])) {
            $this->json(0, "is_pay参数不合法");
        }
        //查询apps是否存在
        $apps_info = Db::name("apps")->where("id", $data["apps_id"])->find();
        if (!$apps_info) {
            $this->json(0, "该应用不存在");
        }
        //查询版本是否存在
        $apps_version_info = Db::name("apps_version")->where("apps_id", $data["apps_id"])->where("id", $data["app_version_id"])->find();
        if (!$apps_version_info) {
            $this->json(0, "该版本不存在");
        }
        //判断是不是自己的
        if ($apps_info["userid"] != $userinfo["id"]) {
            $this->json(0, "系统错误");
        }
        try {
            if (substr(input('icon'), 0, 4) == "http") {
                $icon_url = $data["icon"];
            } else {
                if (!empty($_FILES) && !empty($_FILES["icon"])) {
                    try {
                        $upload = new Upload($userinfo["id"]);
                        $result = $upload->upload('icon');
                    } catch (\Exception $th) {
                        $this->json(0, $th->getMessage());
                    }
                    $icon_url = $result["filePath"];
                } else {
                    $this->json(0, "请上传应用图标");
                }
            }
            if (substr(input('file'), 0, 4) == "http") {
                $download_url = $data["file"];
            } else {
                if (!empty($_FILES) && !empty($_FILES["file"])) {
                    try {
                        $upload = new Upload($userinfo["id"]);
                        $result = $upload->upload('file');
                    } catch (\Exception $th) {
                        $this->json(0, $th->getMessage());
                    }
                    $download_url = $result["filePath"];
                } else {
                    $this->json(0, "请上传应用文件");
                }
            }
            //应用介绍图
            if (substr(input('app_introduction_image'), 0, 4) == "http") {
                $app_introduction_image = $data["app_introduction_image"];
            } else {
                if (!empty($_FILES) && !empty($_FILES["app_introduction_image"])) {
                    try {
                        $upload = new Upload($userinfo["id"]);
                        $result = $upload->upload('app_introduction_image');
                    } catch (\Exception $th) {
                        $this->json(0, $th->getMessage());
                    }
                    $app_introduction_image = [];
                    foreach ($result as $key => $value) {
                        $app_introduction_image[] = $value["filePath"];
                    }
                    $app_introduction_image = array_filter($app_introduction_image);
                    $app_introduction_image = implode(",", $app_introduction_image);
                } else {
                    $this->json(0, "请上传应用介绍图");
                }
            }
            Db::startTrans();
            $app_info_data = [
                "id" => $apps_info["id"],
                "appname" => $data["appname"],
                "app_icon" => $icon_url,
                "app_size" => $data["app_size"],
                "app_explain" => input("app_explain"),
                "app_introduce" => $data["app_introduce"],
                "app_introduction_image" => $app_introduction_image,
                "is_pay" => $data["is_pay"],
                "pay_money" => $data["pay_money"],
                "download" => $download_url,
                "create_time" => $apps_info["create_time"],
                "update_time" => date("Y-m-d H:i:s", time()),
                "appid" => $apps_info["appid"],
                "userid" => $apps_info["userid"],
                "category_id" => $apps_info["category_id"],
                "sub_category_id" => $apps_info["sub_category_id"],
            ];
            $add_data_version = [
                "other_info" => json_encode($app_info_data, JSON_UNESCAPED_UNICODE),
                "status" => 0,
            ];
            Db::name("apps_version")->where("id", $data["app_version_id"])->update($add_data_version);
            Db::commit();
            $this->json(1, "提交成功,请等待审核");
        } catch (\Exception $th) {
            Db::rollback();
            $this->json(0, $th->getMessage());
        }
    }

    //删除应用
    public function delete_apps()
    {
        $data = input();
        $rule = [
            'usertoken|用户token' => 'require',
            'apps_id|应用id' => 'require|number',
            'app_version_id|应用版本id' => 'number',
        ];
        $validate = new Validate();
        $validate->rule($rule);
        $result = $validate->check($data);
        if (!$result) {
            $this->json(0, $validate->getError(), []);
        }
        $userinfo = $this->user_info;
        //查询apps是否存在
        $apps_info = Db::name("apps")->where("id", $data["apps_id"])->find();
        if (!$apps_info) {
            $this->json(0, "该应用不存在");
        }
        //查询版本是否存在
        if (input("app_version_id") != "") {
            $apps_version_info = Db::name("apps_version")->where("apps_id", $data["apps_id"])->where("id", $data["app_version_id"])->find();
            if (!$apps_version_info) {
                $this->json(0, "该版本不存在");
            }
        }
        //判断是不是自己的
        if ($apps_info["userid"] != $userinfo["id"]) {
            $this->json(0, "系统错误");
        }
        try {
            Db::startTrans();
            if (input("app_version_id") != "") {
                Db::name("apps_version")->where("id", $data["app_version_id"])->delete();
                //删除评论
                Db::name("apps_comments")->where("apps_version_id", $data["app_version_id"])->delete();
            } else {
                Db::name("apps")->where("id", $data["apps_id"])->delete();
                Db::name("apps_version")->where("apps_id", $data["apps_id"])->delete();
                Db::name("apps_comments")->where("apps_version_id", $data["app_version_id"])->delete();
            }
            Db::commit();
            $this->json(1, "删除成功", []);
        } catch (\Exception $th) {
            Db::rollback();
            $this->json(0, $th->getMessage());
        }
    }

    //发表评论
    public function apps_add_comment()
    {
        $data = input();
        $rule = [
            'usertoken|用户token' => 'require',
            'apps_id|应用id' => 'require|number',
            'apps_version_id|版本id' => 'require|number',
            'content|内容' => 'require',
            'parentid|评论的id' => 'require|number',
        ];
        $validate = new Validate();
        $validate->rule($rule);
        $result = $validate->check($data);
        if (!$result) {
            $this->json(0, $validate->getError());
        }
        $user_all_info = $this->user_info;
        //查询该app是否存在
        $appinfo = Db::name("apps")->where("id", $data["apps_id"])->find();
        if (!$appinfo) {
            $this->json(0, "该应用不存在");
        }
        //查询该版本是否存在
        $app_version_info = Db::name("apps_version")->where("id", $data["apps_version_id"])->find();
        if (!$app_version_info) {
            $this->json(0, "该版本不存在");
        }
        if ($app_version_info["status"] != 2) {
            $this->json(0, "该应用暂未通过审核，无法评论！");
        }
        if ($data["parentid"] != 0) {
            $comment_info = Db::name("apps_comments")->where("id", $data["parentid"])->where("appid", $data["appid"])->find();
            if (!$comment_info) {
                $this->json(0, "回复的评论不存在");
            }
        }
        $image_path = "";
        if (substr(input('img'), 0, 4) == "http") {
            $image_path = $data["img"];
        } else {
            if (!empty($_FILES) && !empty($_FILES["img"])) {
                try {
                    $upload = new Upload($user_all_info["id"]);
                    $result = $upload->upload('img');
                } catch (\Exception $th) {
                    $this->json(0, $th->getMessage());
                }
                foreach ($result as $key => $value) {
                    $img_url[] = $value["filePath"];
                }
                $img_url = array_filter($img_url);
                $image_path = implode(",", $img_url);
            }
        }
        $addcommentdata = [
            "parentid" => $data["parentid"],
            "apps_id" => $data["apps_id"],
            "apps_version_id" => $data["apps_version_id"],
            "content" => $data["content"],
            "userid" => $user_all_info["id"],
            "appid" => $data["appid"],
            "time" => date("Y-m-d H:i:s", time()),
            "status" => 1,
            "ip" => get_client_ip(),
            "image_path" => $image_path,
        ];
        $comment_id = Db::name("apps_comments")->insert($addcommentdata);
        if (!$comment_id) {
            $this->json(0, "评论失败");
        }
        $this->json(1, "评论成功");
    }

    //获取评论列表
    public function get_apps_comment_list()
    {
        $data = input();
        $rule = [
            'user_id|用户id' => 'number',
            'apps_id|应用id' => 'number',
            'apps_version_id|版本id' => 'number',
        ];
        $validate = new Validate();
        $validate->rule($rule);
        $result = $validate->check($data);
        if (!$result) {
            $this->json(0, $validate->getError());
        }
        if (!input("?apps_id") && !input("?userid")) {
            $this->json(0, "userid和apps_id必须传一个");
        }
        $where = " c.appid = {$this->appid} ";
        if (input("?apps_id")) {
            //查询该app是否存在
            $appinfo = Db::name("apps")->where("id", $data["apps_id"])->find();
            if (!$appinfo) {
                $this->json(0, "该应用不存在");
            }
            $where .= "and c.status = 1 and c.apps_id = {$data['apps_id']}";
            if (input("?apps_version_id")) {
                //查询该版本是否存在
                $app_version_info = Db::name("apps_version")->where("id", $data["apps_version_id"])->find();
                if (!$app_version_info) {
                    $this->json(0, "该版本不存在");
                }
                $where .= " and c.apps_version_id = {$data['apps_version_id']}";
            }
        }
        if (input("?userid")) {
            $userinfo = Db::name("user")->where("id", $data["userid"])->where("appid", $data["appid"])->find();
            if (!$userinfo) {
                $this->json(0, "用户不存在");
            }
            $where .= " and c.userid = {$data['userid']}";
        }
        if (input("?comment_id")) {
            if ($data["comment_id"] != 0) {
                $userinfo = Db::name("comments")->where("id", $data["comment_id"])->where("appid", $data["appid"])->find();
                if (!$userinfo) {
                    $this->json(0, "评论不存在");
                }
            }
            $where .= " and c.parentid = {$data['comment_id']}";
        }
        $sort = input("?sort") ? $data["sort"] : "time";
        $sortOrder = input("?sortOrder") ? $data["sortOrder"] : 'desc';
        if ($sort != "time" && $sort != "id") {
            $this->json(0, "sort参数错误");
        }
        if ($sortOrder != "desc" && $sortOrder != "asc") {
            $this->json(0, "sortOrder参数错误");
        }
        $result = Db::name('apps_comments')
            ->alias("c")
            ->join("user u", "u.id = c.userid")
            ->join("apps as", "as.id = c.apps_id")
            ->join("apps_version asv", "asv.id = c.apps_version_id")
            ->where($where)
            ->field("c.*,u.username,u.nickname,u.usertx,u.exp,u.viptime")
            ->order("c." . $sort, $sortOrder)
            ->limit($this->limit)
            ->page($this->page)
            ->select()->toArray();
        $pagecount = db("apps_comments")
            ->alias("c")
            ->join("user u", "u.id = c.userid")
            ->join("apps as", "as.id = c.apps_id")
            ->join("apps_version asv", "asv.id = c.apps_version_id")
            ->field("c.*")
            ->where($where)
            ->order("c.id", "desc")
            ->count();
        $ip = new IpLocation();
        foreach ($result as $key => $value) {
            $result[$key]["ip_address"] = $value["ip"] == "" ? "未知" : $ip->getDetail($value["ip"])["dataA"];
            $result[$key]["image_path"] = $value["image_path"] == "" ? "" : $value["image_path"];
            unset($result[$key]["ip"]);
            //假入有上级评论则插入
            //上级评论者用户昵称
            $result[$key]["parentnickname"] = "";
            $result[$key]["parentusername"] = "";
            //上级评论内容
            $result[$key]["parentcontent"] = "";
            if ($value["parentid"] != 0) {
                $parentcommentinfo = db("apps_comments")
                    ->alias("c")
                    ->join("user u", "u.id = c.userid")
                    ->where("c.id", $value["parentid"])
                    ->field("c.id,c.content,u.nickname,u.username")
                    ->find();
                //上级评论者用户昵称
                $result[$key]["parentnickname"] = $parentcommentinfo["nickname"];
                $result[$key]["parentusername"] = $parentcommentinfo["username"];
                //上级评论内容
                $result[$key]["parentcontent"] = $parentcommentinfo["content"];
            }
            $result[$key]["image_path"] = array_filter(explode(",", $value["image_path"]));
            unset($result[$key]["status"]);
            //经验等级
            $arr = $this->app_info["grade"];
            $grades = eval("return $arr;");
            $result[$key]["hierarchy"] = "";
            if (is_array($grades)) {
                foreach ($grades as $k1 => $v1) {
                    if ($result[$key]['exp'] >= $k1) {
                        $result[$key]["hierarchy"] = $v1;
                    } else {
                        break;
                    }
                }
            }
            //是否是会员
            if (time() < $value["viptime"]) {
                $result[$key]["vip"] = true;
            } else {
                $result[$key]["vip"] = false;
            }
            unset($result[$key]["viptime"]);
            //获取用户的徽章
            $result[$key]["badge"] = Db::name("polymorphic")
                ->alias("p")
                ->join("bagge b", "b.id=p.other_id")
                ->where("p.userid", $value["userid"])
                ->where("p.type", 5)
                ->where("b.is_view", 0)
                ->where("p.wearing", 0)
                ->order(["b.type" => $this->medal_sorting, "b.sort" => "desc"])
                ->field("b.id,b.name,b.icon,b.type,case when p.expiration_time = '9999' then '永久' else p.expiration_time end as expiration_time")
                ->select()->toArray();
        }
        $data_rs["list"] = $result;
        $data_rs["pagecount"] = ceil($pagecount / $this->limit) == 0 ? 1 : ceil($pagecount / $this->limit);
        $data_rs["current_number"] = (int)$this->page;
        $this->json(1, "success", $data_rs);
    }

    //删除评论
    public function delete_apps_comment()
    {
        $data = input();
        $rule = [
            'usertoken|用户token' => 'require',
            'comment_id|评论id' => 'require|number',
        ];
        $validate = new Validate();
        $validate->rule($rule);
        $result = $validate->check($data);
        if (!$result) {
            $this->json(0, $validate->getError());
        }
        $user_all_info = $this->user_info;
        //查询该app是否存在
        $comment_info = Db::name("apps_comments")->where("id", $data["comment_id"])->find();
        if (!$comment_info) {
            $this->json(0, "该评论不存在");
        }
        //判断是不是自己的
        if ($comment_info["userid"] != $user_all_info["id"]) {
            $this->json(0, "系统错误");
        }
        try {
            Db::startTrans();
            Db::name("apps_comments")->where("id", $data["comment_id"])->delete();
            Db::commit();
            $this->json(1, "删除成功", []);
        } catch (\Exception $th) {
            Db::rollback();
            $this->json(0, $th->getMessage());
        }
    }

    //增加下载量
    public function add_download_count()
    {
        $data = input();
        $rule = [
            'usertoken|用户token' => 'require',
            'apps_id|应用id' => 'require|number',
            'apps_version_id|版本id' => 'require|number',
        ];
        $validate = new Validate();
        $validate->rule($rule);
        $result = $validate->check($data);
        if (!$result) {
            $this->json(0, $validate->getError());
        }
        $user_all_info = $this->user_info;
        //查询该app是否存在
        $appinfo = Db::name("apps")->where("id", $data["apps_id"])->find();
        if (!$appinfo) {
            $this->json(0, "该应用不存在");
        }
        //查询该版本是否存在
        $app_version_info = Db::name("apps_version")->where("id", $data["apps_version_id"])->find();
        if (!$app_version_info) {
            $this->json(0, "该版本不存在");
        }
        if ($app_version_info["status"] != 2) {
            $this->json(0, "该应用暂未通过审核，无法下载！");
        }
        try {
            Db::startTrans();
            $add_data = [
                "userid" => $user_all_info["id"],
                "appid" => $data["appid"],
                "type" => 6,
                "other_id" => $data["apps_version_id"],
                "create_time" => date("Y-m-d H:i:s", time()),
            ];
            Db::name("polymorphic")->insert($add_data);
            Db::commit();
            $this->json(1, "success", []);
        } catch (\Exception $th) {
            Db::rollback();
            $this->json(0, $th->getMessage());
        }
    }

    //对需要支付的应用进行支付
    public function pay_for_apps()
    {
        $data = input();
        $rule = [
            'usertoken|用户token' => 'require',
            'apps_id|应用id' => 'require|number',
            'apps_version_id|版本id' => 'require|number',
        ];
        $validate = new Validate();
        $validate->rule($rule);
        $result = $validate->check($data);
        if (!$result) {
            $this->json(0, $validate->getError());
        }
        $user_all_info = $this->user_info;
        //查询该app是否存在
        $appinfo = Db::name("apps")->where("id", $data["apps_id"])->find();
        if (!$appinfo) {
            $this->json(0, "该应用不存在");
        }
        //查询该版本是否存在
        $app_version_info = Db::name("apps_version")->where("id", $data["apps_version_id"])->find();
        if (!$app_version_info) {
            $this->json(0, "该版本不存在");
        }
        if ($app_version_info["status"] != 2) {
            $this->json(0, "该应用暂未通过审核，无法下载！");
        }
        $appinfo_other_info = json_decode($app_version_info["other_info"], true);
        if ($appinfo_other_info["is_pay"] == 0) {
            $this->json(0, "该应用不需要付费");
        }
        if ($appinfo_other_info["pay_money"] <= 0) {
            $this->json(0, "该应用价格错误");
        }
        if ($appinfo_other_info["userid"] == $user_all_info["id"]) {
            $this->json(0, "不能购买自己的应用");
        }
        // 查询用户是否已经购买过
        $is_pay = Db::name("apps_payment")->where("userid", $user_all_info["id"])->where("apps_id", $data["apps_id"])->where("apps_version_id", $data["apps_version_id"])->where("type", 0)->find();
        if ($is_pay) {
            $this->json(0, "您已购买过该应用");
        }
        try {
            Db::startTrans();
            $lockedUser = Db::name("user")
                ->where("id", $user_all_info["id"])
                ->where("appid", $this->appid)
                ->lock(true)
                ->find();
            if (!$lockedUser) {
                throw new \Exception("用户不存在");
            }
            $add_data = [
                "userid" => $user_all_info["id"],
                "appid" => $data["appid"],
                "amount" => $appinfo_other_info["pay_money"],
                "apps_id" => $data["apps_id"],
                "apps_version_id" => $data["apps_version_id"],
                "create_time" => date("Y-m-d H:i:s", time()),
                "payment" => $appinfo_other_info["is_pay"] == 1 ? 0 : 1,
                "type" => 0,
            ];
            //扣除用户金币
            if ($appinfo_other_info["is_pay"] == 1) {
                $price = $this->walletAmountLabel($appinfo_other_info["pay_money"]);
                $this->assertAssetBalance($lockedUser, "money", $price);
                Db::name("user")
                    ->where("id", $lockedUser["id"])
                    ->where("appid", $this->appid)
                    ->update(["money" => Db::raw("money - " . $price)]);
            }
            //扣除用户积分
            if ($appinfo_other_info["is_pay"] == 2) {
                $price = (int)$appinfo_other_info["pay_money"];
                $this->assertAssetBalance($lockedUser, "integral", $price);
                Db::name("user")
                    ->where("id", $lockedUser["id"])
                    ->where("appid", $this->appid)
                    ->update(["integral" => Db::raw("integral - " . $price)]);
            }
            Db::name("apps_payment")->insert($add_data);
            Db::commit();
            $this->json(1, "success", ["download" => $appinfo_other_info["download"]]);
        } catch (\Exception $th) {
            Db::rollback();
            $this->json(0, $th->getMessage());
        }
    }

    //对应用打赏
    public function reward_for_apps()
    {
        $data = input();
        $rule = [
            'usertoken|用户token' => 'require',
            'apps_id|应用id' => 'require|number',
            'apps_version_id|版本id' => 'require|number',
            'money|打赏金额' => 'require|number',
            'type|打赏方式 0金币 1积分' => 'require|number|in:0,1',
        ];
        $validate = new Validate();
        $validate->rule($rule);
        $result = $validate->check($data);
        if (!$result) {
            $this->json(0, $validate->getError());
        }
        if ($data["money"] <= 0) {
            $this->json(0, "打赏金额错误");
        }
        $user_all_info = $this->user_info;
        //查询该app是否存在
        $appinfo = Db::name("apps")->where("id", $data["apps_id"])->find();
        if (!$appinfo) {
            $this->json(0, "该应用不存在");
        }
        //查询该版本是否存在
        $app_version_info = Db::name("apps_version")->where("id", $data["apps_version_id"])->find();
        if (!$app_version_info) {
            $this->json(0, "该版本不存在");
        }
        if ($app_version_info["status"] != 2) {
            $this->json(0, "该应用暂未通过审核，无法打赏！");
        }
        $appinfo_other_info = json_decode($app_version_info["other_info"], true);
        if ($appinfo_other_info["userid"] == $user_all_info["id"]) {
            $this->json(0, "不能打赏自己的应用");
        }
        try {
            Db::startTrans();
            $add_data = [
                "userid" => $user_all_info["id"],
                "appid" => $data["appid"],
                "amount" => $data["money"],
                "apps_id" => $data["apps_id"],
                "apps_version_id" => $data["apps_version_id"],
                "create_time" => date("Y-m-d H:i:s", time()),
                "payment" => $data["type"],
                "type" => 1,
            ];
            Db::name("apps_payment")->insert($add_data);
            Db::commit();
            $this->json(1, "success", []);
        } catch (\Exception $th) {
            Db::rollback();
            $this->json(0, $th->getMessage());
        }
    }

    //搜索用户接口
    public function search_user()
    {
        $result = Db::name("user")
            ->where("appid", $this->appid)
            ->where("username|nickname", "like", "%" . input("search") . "%")
            ->field("id,username,nickname,usertx,title")
            ->limit($this->limit)
            ->page($this->page)
            ->select()->toArray();
        foreach ($result as $key => $value) {
            $result[$key]["title"] = array_filter(explode(",", $value["title"]));
            $result[$key]["badge"] = Db::name("polymorphic")
                ->alias("p")
                ->join("bagge b", "b.id=p.other_id")
                ->where("p.userid", $value["id"])
                ->where("p.type", 5)
                ->where("b.is_view", 0)
                ->where("p.wearing", 0)
                ->order(["b.type" => $this->medal_sorting, "b.sort" => "desc"])
                ->field("b.id,b.name,b.icon,case when p.expiration_time = '9999' then '永久' else p.expiration_time end as expiration_time")
                ->select()->toArray();
        }
        $pagecount = Db::name("user")
            ->where("appid", $this->appid)
            ->where("username|nickname", "like", "%" . input("search") . "%")
            ->count();
        $data_rs["list"] = $result;
        $data_rs["pagecount"] = ceil($pagecount / $this->limit) == 0 ? 1 : ceil($pagecount / $this->limit);
        $data_rs["current_number"] = $this->page;
        $this->json(1, "success", $data_rs);
    }

    //修改评论置顶状态
    public function edit_comment_top()
    {
        $data = input();
        $rule = [
            'usertoken|用户token' => 'require',
            'comment_id|评论id' => 'require|number',
            'is_top|是否置顶' => 'require|number|in:0,1',
        ];
        $validate = new Validate();
        $validate->rule($rule);
        $result = $validate->check($data);
        if (!$result) {
            $this->json(0, $validate->getError());
        }
        $user_all_info = $this->user_info;
        //查询该app是否存在
        $comment_info = Db::name("comments")->where("id", $data["comment_id"])->find();
        if (!$comment_info) {
            $this->json(0, "该评论不存在");
        }
        if ($comment_info["status"] != 1) {
            $this->json(0, "该评论暂未通过审核，无法操作！");
        }
        //查询该评论的帖子信息是否存在
        $post_info = Db::name("forum_posts")->where("id", $comment_info["postid"])->find();
        if (!$post_info) {
            $this->json(0, "该评论的帖子不存在");
        }
        //判断是不是自己的
        if ($post_info["userid"] != $user_all_info["id"]) {
            $this->json(0, "系统错误");
        }
        try {
            Db::startTrans();
            Db::name("comments")->where("id", $data["comment_id"])->update(["topping" => $data["is_top"]]);
            Db::commit();
            $this->json(1, "修改成功");
        } catch (\Exception $th) {
            Db::rollback();
            $this->json(0, $th->getMessage());
        }
    }

    //获取当前用户已有的徽章/称号
    public function get_user_badge()
    {
        $data = input();
        $rule = [
            'usertoken|用户token' => 'require',
        ];
        $validate = new Validate();
        $validate->rule($rule);
        $result = $validate->check($data);
        if (!$result) {
            $this->json(0, $validate->getError());
        }
        $where = "p.userid = {$this->user_info['id']} and p.type = 5 and b.is_view = 0";
        if (input("type") != '') {
            $where .= " and b.type = {$data['type']}";
        }
        $user_all_info = $this->user_info;
        $result = Db::name("polymorphic")
            ->alias("p")
            ->join("bagge b", "b.id=p.other_id")
            ->where($where)
            ->order(["b.type" => $this->medal_sorting, "b.sort" => "desc"])
            ->field("b.id,b.name,b.icon,b.type,p.wearing,case when p.expiration_time = '9999' then '永久' else p.expiration_time end as expiration_time")
            ->select()->toArray();
        $this->json(1, "success", $result);
    }

    //勋章的摘下及佩戴
    public function medal_wear()
    {
        $data = input();
        $rule = [
            'usertoken|用户token' => 'require',
            'medal_id|勋章id' => 'require|number',
            'type|操作类型 0佩戴 1摘下' => 'require|number|in:0,1',
        ];
        $validate = new Validate();
        $validate->rule($rule);
        $result = $validate->check($data);
        if (!$result) {
            $this->json(0, $validate->getError());
        }
        $user_all_info = $this->user_info;
        //查询该勋章是否存在
        $medal_info = Db::name("bagge")->where("id", $data["medal_id"])->find();
        if (!$medal_info) {
            $this->json(0, "该勋章不存在");
        }
        //查询该用户是否有该勋章
        $polymorphic_info = Db::name("polymorphic")->where("userid", $user_all_info["id"])->where("other_id", $data["medal_id"])->where("type", 5)->find();
        if (!$polymorphic_info) {
            $this->json(0, "您没有该勋章");
        }
        //检查勋章是否过期
        if ($polymorphic_info["expiration_time"] != "9999" && strtotime($polymorphic_info["expiration_time"]) < time()) {
            $this->json(0, "该勋章已过期");
        }
        if ($data["type"] == 0) {
            if ($polymorphic_info["wearing"] == 0) {
                $this->json(0, "您已经佩戴了该勋章");
            }
            $update_data = [
                "wearing" => 0,
            ];
            Db::name("polymorphic")->where("id", $polymorphic_info["id"])->update($update_data);
        } else {
            if ($polymorphic_info["wearing"] == 1) {
                $this->json(0, "您已经摘下了该勋章");
            }
            $update_data = [
                "wearing" => 1,
            ];
            Db::name("polymorphic")->where("id", $polymorphic_info["id"])->update($update_data);
        }
        $this->json(1, "success", []);
    }

    //朋友圈信息流
    public function moments_feed()
    {
        $this->secureChatRequestInput();
        $user = $this->user_info;
        $viewerId = (int)$user["id"];
        $friendIds = $this->momentFriendUserIds($viewerId);
        $visibilitySql = "(user_id = {$viewerId} OR ((review_status = 1) AND (visibility = 0 OR (visibility = 2 AND FIND_IN_SET('{$viewerId}', visible_user_ids)))))";
        $query = Db::name("moments_post")
            ->where("appid", $this->appid)
            ->where("status", 1)
            ->whereIn("user_id", $friendIds)
            ->whereRaw($visibilitySql);
        $countQuery = clone $query;
        $count = (int)$countQuery->count();
        $rows = $query
            ->order("id", "desc")
            ->page((int)$this->page, (int)$this->limit)
            ->select()
            ->toArray();
        $list = [];
        foreach ($rows as $row) {
            $list[] = $this->formatMomentPost($row, $viewerId);
        }
        $this->chatJson(1, "success", [
            "list" => $list,
            "pagecount" => ceil($count / (int)$this->limit) == 0 ? 1 : ceil($count / (int)$this->limit),
            "current_number" => (int)$this->page,
        ]);
    }

    //指定用户朋友圈
    public function moments_user()
    {
        $data = $this->secureChatRequestInput(false);
        $viewerId = (int)$this->user_info["id"];
        $targetId = (int)($data["user_id"] ?? $data["target_user_id"] ?? $viewerId);
        if ($targetId <= 0) {
            $targetId = $viewerId;
        }
        $target = Db::name("user")->where("appid", $this->appid)->where("id", $targetId)->find();
        if (!$target) {
            $this->json(0, "用户不存在");
        }
        if ($targetId !== $viewerId && !$this->isChatFriend($viewerId, $targetId)) {
            $this->chatJson(1, "success", [
                "list" => [],
                "user" => $this->formatChatUser($target),
                "pagecount" => 1,
                "current_number" => (int)$this->page,
            ]);
        }
        $query = Db::name("moments_post")
            ->where("appid", $this->appid)
            ->where("user_id", $targetId)
            ->where("status", 1);
        if ($targetId !== $viewerId) {
            $query->where("review_status", 1)
                ->whereRaw("(visibility = 0 OR (visibility = 2 AND FIND_IN_SET('{$viewerId}', visible_user_ids)))");
        }
        $countQuery = clone $query;
        $count = (int)$countQuery->count();
        $rows = $query
            ->order("id", "desc")
            ->page((int)$this->page, (int)$this->limit)
            ->select()
            ->toArray();
        $list = [];
        foreach ($rows as $row) {
            $list[] = $this->formatMomentPost($row, $viewerId);
        }
        $this->chatJson(1, "success", [
            "list" => $list,
            "user" => $this->formatChatUser($target),
            "pagecount" => ceil($count / (int)$this->limit) == 0 ? 1 : ceil($count / (int)$this->limit),
            "current_number" => (int)$this->page,
        ]);
    }

    //朋友圈详情
    public function moments_detail()
    {
        $data = $this->secureChatRequestInput();
        $postId = (int)($data["post_id"] ?? 0);
        if ($postId <= 0) {
            $this->json(0, "post_id不能为空");
        }
        $post = $this->momentPostOrFail($postId, (int)$this->user_info["id"]);
        $this->chatJson(1, "success", [
            "post" => $this->formatMomentPost($post, (int)$this->user_info["id"]),
        ]);
    }

    //朋友圈加密媒体上传
    public function moments_media_upload()
    {
        $this->chatRequestContext();
        $data = $this->secureChatInput(input());
        if (empty($_FILES) || empty($_FILES["secure_file"])) {
            $this->json(0, "secure_file不能为空");
        }
        $result = $this->decodeSecureChatFile($data);
        $type = trim((string)($data["media_type"] ?? $data["type"] ?? ""));
        if ($type === "") {
            $mime = strtolower((string)($result["type"] ?? ""));
            $type = str_starts_with($mime, "video/") ? "video" : (str_starts_with($mime, "image/") ? "image" : "file");
        }
        if (!in_array($type, ["image", "video", "file"], true)) {
            $this->json(0, "media_type不合法");
        }
        $media = [
            "type" => $type,
            "url" => (string)$result["filePath"],
            "thumb_url" => trim((string)($data["thumb_url"] ?? $data["cover_url"] ?? "")),
            "name" => (string)($result["name"] ?? ""),
            "mime" => (string)($result["type"] ?? ""),
            "size" => (int)($result["size"] ?? 0),
            "width" => max(0, (int)($data["width"] ?? 0)),
            "height" => max(0, (int)($data["height"] ?? 0)),
            "duration" => max(0, (int)($data["duration"] ?? 0)),
        ];
        $this->chatJson(1, "success", ["media" => $media]);
    }

    //发布朋友圈
    public function moments_publish()
    {
        $data = $this->secureChatRequestInput(false);
        $user = $this->user_info;
        $content = mb_substr(trim((string)($data["content"] ?? "")), 0, 2000);
        $media = $this->normalizeMomentMediaList($data["media"] ?? []);
        if ($content === "" && !$media) {
            $this->json(0, "内容和媒体不能同时为空");
        }
        $visibility = (int)($data["visibility"] ?? 0);
        if (!in_array($visibility, [0, 1, 2], true)) {
            $this->json(0, "visibility不合法");
        }
        $visibleIds = $visibility === 2 ? $this->normalizeMomentIdList($data["visible_user_ids"] ?? []) : [];
        foreach ($visibleIds as $visibleId) {
            if (!$this->isChatFriend((int)$user["id"], $visibleId)) {
                $this->json(0, "部分可见用户必须是好友");
            }
        }
        $remindIds = $this->normalizeMomentIdList($data["remind_user_ids"] ?? [], 20);
        foreach ($remindIds as $remindId) {
            if (!$this->isChatFriend((int)$user["id"], $remindId)) {
                $this->json(0, "提醒用户必须是好友");
            }
        }
        $review = MomentsControl::audit(MomentsControl::get(), $content, $media);
        $now = date("Y-m-d H:i:s");
        $postId = Db::name("moments_post")->insertGetId([
            "appid" => $this->appid,
            "user_id" => (int)$user["id"],
            "content" => $content,
            "media_json" => json_encode($media, JSON_UNESCAPED_UNICODE),
            "media_type" => $this->momentMediaType($media),
            "visibility" => $visibility,
            "visible_user_ids" => $this->momentIdsCsv($visibleIds),
            "remind_user_ids" => $this->momentIdsCsv($remindIds),
            "location" => mb_substr(trim((string)($data["location"] ?? "")), 0, 255),
            "status" => 1,
            "review_status" => (int)$review["review_status"],
            "review_mode" => (string)$review["review_mode"],
            "review_reason" => (string)$review["review_reason"],
            "review_time" => (int)$review["review_status"] === 0 ? null : $now,
            "create_time" => $now,
            "update_time" => $now,
        ]);
        $post = Db::name("moments_post")->where("id", $postId)->find();
        $message = (int)$review["review_status"] === 0 ? "已提交审核" : ((int)$review["review_status"] === 2 ? "发布未通过审核" : "发布成功");
        $this->chatJson(1, $message, [
            "post" => $this->formatMomentPost($post, (int)$user["id"]),
        ]);
    }

    //删除朋友圈动态
    public function moments_delete()
    {
        $data = $this->secureChatRequestInput();
        $postId = (int)($data["post_id"] ?? 0);
        if ($postId <= 0) {
            $this->json(0, "post_id不能为空");
        }
        $post = Db::name("moments_post")
            ->where("appid", $this->appid)
            ->where("id", $postId)
            ->where("status", 1)
            ->find();
        if (!$post || (int)$post["user_id"] !== (int)$this->user_info["id"]) {
            $this->json(0, "无权删除该动态");
        }
        Db::name("moments_post")->where("id", $postId)->update([
            "status" => 0,
            "delete_time" => date("Y-m-d H:i:s"),
            "update_time" => date("Y-m-d H:i:s"),
        ]);
        $this->chatJson(1, "删除成功", ["post_id" => $postId]);
    }

    //朋友圈点赞
    public function moments_like()
    {
        $data = $this->secureChatRequestInput();
        $postId = (int)($data["post_id"] ?? 0);
        if ($postId <= 0) {
            $this->json(0, "post_id不能为空");
        }
        $post = $this->momentPostOrFail($postId, (int)$this->user_info["id"]);
        $now = date("Y-m-d H:i:s");
        $row = Db::name("moments_like")
            ->where("appid", $this->appid)
            ->where("post_id", $postId)
            ->where("user_id", (int)$this->user_info["id"])
            ->find();
        if ($row) {
            Db::name("moments_like")->where("id", $row["id"])->update([
                "status" => 1,
                "update_time" => $now,
            ]);
        } else {
            Db::name("moments_like")->insert([
                "appid" => $this->appid,
                "post_id" => $postId,
                "user_id" => (int)$this->user_info["id"],
                "status" => 1,
                "create_time" => $now,
                "update_time" => $now,
            ]);
        }
        $this->chatJson(1, "success", [
            "post" => $this->formatMomentPost($post, (int)$this->user_info["id"]),
        ]);
    }

    //取消朋友圈点赞
    public function moments_unlike()
    {
        $data = $this->secureChatRequestInput();
        $postId = (int)($data["post_id"] ?? 0);
        if ($postId <= 0) {
            $this->json(0, "post_id不能为空");
        }
        $post = $this->momentPostOrFail($postId, (int)$this->user_info["id"]);
        Db::name("moments_like")
            ->where("appid", $this->appid)
            ->where("post_id", $postId)
            ->where("user_id", (int)$this->user_info["id"])
            ->update([
                "status" => 0,
                "update_time" => date("Y-m-d H:i:s"),
            ]);
        $this->chatJson(1, "success", [
            "post" => $this->formatMomentPost($post, (int)$this->user_info["id"]),
        ]);
    }

    //朋友圈评论
    public function moments_comment_add()
    {
        $data = $this->secureChatRequestInput();
        $postId = (int)($data["post_id"] ?? 0);
        $content = mb_substr(trim((string)($data["content"] ?? "")), 0, 500);
        if ($postId <= 0) {
            $this->json(0, "post_id不能为空");
        }
        if ($content === "") {
            $this->json(0, "评论内容不能为空");
        }
        $post = $this->momentPostOrFail($postId, (int)$this->user_info["id"]);
        $replyCommentId = (int)($data["reply_comment_id"] ?? 0);
        $replyUserId = 0;
        if ($replyCommentId > 0) {
            $reply = Db::name("moments_comment")
                ->where("appid", $this->appid)
                ->where("id", $replyCommentId)
                ->where("post_id", $postId)
                ->where("status", 1)
                ->where(function ($query) {
                    $query->where("review_status", 1)->whereOr("user_id", (int)$this->user_info["id"]);
                })
                ->find();
            if (!$reply) {
                $this->json(0, "回复的评论不存在");
            }
            $replyUserId = (int)$reply["user_id"];
        } else {
            $replyUserId = (int)($data["reply_user_id"] ?? 0);
        }
        $review = MomentsControl::audit(MomentsControl::get(), $content, []);
        $now = date("Y-m-d H:i:s");
        $commentId = Db::name("moments_comment")->insertGetId([
            "appid" => $this->appid,
            "post_id" => $postId,
            "user_id" => (int)$this->user_info["id"],
            "reply_comment_id" => $replyCommentId,
            "reply_user_id" => $replyUserId,
            "content" => $content,
            "status" => 1,
            "review_status" => (int)$review["review_status"],
            "review_mode" => (string)$review["review_mode"],
            "review_reason" => (string)$review["review_reason"],
            "review_time" => (int)$review["review_status"] === 0 ? null : $now,
            "create_time" => $now,
            "update_time" => $now,
        ]);
        Db::name("moments_post")->where("id", $postId)->update(["update_time" => $now]);
        $comment = Db::name("moments_comment")->where("id", $commentId)->find();
        $message = (int)$review["review_status"] === 0 ? "评论已提交审核" : ((int)$review["review_status"] === 2 ? "评论未通过审核" : "评论成功");
        $this->chatJson(1, $message, [
            "comment_id" => (int)$commentId,
            "comment" => $comment,
            "post" => $this->formatMomentPost($post, (int)$this->user_info["id"]),
        ]);
    }

    //删除朋友圈评论
    public function moments_comment_delete()
    {
        $data = $this->secureChatRequestInput();
        $commentId = (int)($data["comment_id"] ?? 0);
        if ($commentId <= 0) {
            $this->json(0, "comment_id不能为空");
        }
        $comment = Db::name("moments_comment")
            ->where("appid", $this->appid)
            ->where("id", $commentId)
            ->where("status", 1)
            ->find();
        if (!$comment) {
            $this->json(0, "评论不存在");
        }
        $post = Db::name("moments_post")
            ->where("appid", $this->appid)
            ->where("id", (int)$comment["post_id"])
            ->where("status", 1)
            ->find();
        if (!$post || ((int)$comment["user_id"] !== (int)$this->user_info["id"] && (int)$post["user_id"] !== (int)$this->user_info["id"])) {
            $this->json(0, "无权删除该评论");
        }
        Db::name("moments_comment")->where("id", $commentId)->update([
            "status" => 0,
            "delete_time" => date("Y-m-d H:i:s"),
            "update_time" => date("Y-m-d H:i:s"),
        ]);
        $this->chatJson(1, "删除成功", [
            "comment_id" => $commentId,
            "post" => $this->formatMomentPost($post, (int)$this->user_info["id"]),
        ]);
    }

    //发起音视频通话：private/group/meeting。媒体层使用LiveKit，邀请信令走Gateway。
    public function im_call_create()
    {
        $data = $this->secureChatRequestInput(false);
        $user = $this->user_info;
        $callType = trim((string)($data["call_type"] ?? "private"));
        $mediaType = trim((string)($data["media_type"] ?? "audio"));
        if (!in_array($callType, ["private", "group", "meeting"], true)) {
            $this->json(0, "call_type不合法");
        }
        if (!in_array($mediaType, ["audio", "video"], true)) {
            $this->json(0, "media_type不合法");
        }
        if (!LiveKitToken::enabled()) {
            $this->json(0, "音视频服务未配置");
        }
        $now = date("Y-m-d H:i:s");
        $callNo = $this->liveKitCallNo();
        $roomName = $this->liveKitRoomName($callType);
        $channelId = "";
        $channelType = 0;
        $receiverId = 0;
        $groupId = 0;
        $title = mb_substr(trim((string)($data["title"] ?? "")), 0, 120);
        $inviteUserIds = [];
        if ($callType === "private") {
            $receiverId = (int)($data["receiver_id"] ?? 0);
            $receiver = Db::name("user")->where("appid", $this->appid)->where("id", $receiverId)->find();
            if (!$receiver) {
                $this->json(0, "用户不存在");
            }
            if (!$this->isChatFriend((int)$user["id"], $receiverId)) {
                $this->json(0, "非好友不能发起音视频通话");
            }
            $channelId = $this->wukongUid($receiverId);
            $channelType = (int)config('wukongim.channel_type_person', WukongIM::CHANNEL_TYPE_PERSON);
            $title = $title !== "" ? $title : ($mediaType === "video" ? "视频通话" : "语音通话");
            $inviteUserIds = [$receiverId];
        } elseif ($callType === "group") {
            $groupId = (int)($data["group_id"] ?? 0);
            $group = Db::name("chat_group")->where("appid", $this->appid)->where("id", $groupId)->where("status", 1)->find();
            if (!$group) {
                $this->json(0, "群聊不存在");
            }
            try {
                $this->assertGroupMember($group, $user);
            } catch (\Exception $e) {
                $this->json(0, $e->getMessage());
            }
            $channelId = (string)$group["channel_id"];
            $channelType = (int)config('wukongim.channel_type_group', WukongIM::CHANNEL_TYPE_GROUP);
            $title = $title !== "" ? $title : (string)($group["name"] ?? "群聊通话");
            $inviteUserIds = $this->normalizeMomentIdList($data["invite_user_ids"] ?? [], (int)config('livekit.max_group_participants', 16));
            $inviteUserIds = array_values(array_unique(array_filter($inviteUserIds, fn($id) => $id > 0 && $id !== (int)$user["id"])));
            if (!$inviteUserIds) {
                $this->json(0, "请选择通话成员");
            }
            $validInviteUserIds = Db::name("chat_group_member")
                ->where("appid", $this->appid)
                ->where("group_id", $groupId)
                ->where("status", 1)
                ->whereIn("user_id", $inviteUserIds)
                ->column("user_id");
            $validInviteUserIds = array_values(array_unique(array_map("intval", $validInviteUserIds)));
            sort($validInviteUserIds);
            $requestedInviteUserIds = $inviteUserIds;
            sort($requestedInviteUserIds);
            if ($validInviteUserIds !== $requestedInviteUserIds) {
                $this->json(0, "通话成员必须是有效群成员");
            }
            $inviteUserIds = $validInviteUserIds;
        } else {
            $title = $title !== "" ? $title : "会议";
            $inviteUserIds = $this->normalizeMomentIdList($data["invite_user_ids"] ?? [], (int)config('livekit.max_meeting_participants', 50));
            $inviteUserIds = array_values(array_filter($inviteUserIds, fn($id) => $id !== (int)$user["id"]));
            $channelId = "meeting:" . $callNo;
            $channelType = 0;
        }
        $timeout = $this->liveKitCallTimeout($callType);
        $expireTime = date("Y-m-d H:i:s", time() + $timeout);
        Db::startTrans();
        try {
            $callId = Db::name("livekit_call")->insertGetId([
                "appid" => $this->appid,
                "call_no" => $callNo,
                "room_name" => $roomName,
                "call_type" => $callType,
                "media_type" => $mediaType,
                "channel_id" => $channelId,
                "channel_type" => $channelType,
                "creator_id" => (int)$user["id"],
                "receiver_id" => $receiverId,
                "group_id" => $groupId,
                "title" => $title,
                "status" => 0,
                "expire_time" => $expireTime,
                "create_time" => $now,
                "update_time" => $now,
            ]);
            $this->upsertLiveKitParticipant($callId, (int)$user["id"], "host", 1, (string)($data["device"] ?? input("device", "")));
            foreach ($inviteUserIds as $inviteUserId) {
                $this->upsertLiveKitParticipant($callId, (int)$inviteUserId, "member", 0, "");
            }
            Db::commit();
        } catch (\Exception $e) {
            Db::rollback();
            $this->json(0, $e->getMessage());
        }
        $call = Db::name("livekit_call")->where("id", $callId)->find();
        $this->publishLiveKitCallEvent($call, "call.invite", $inviteUserIds, (int)$user["id"]);
        $this->chatJson(1, "success", $this->liveKitCallPayload($call, (int)$user["id"], true));
    }

    public function im_call_accept()
    {
        $data = $this->secureChatRequestInput(false);
        $call = $this->liveKitCallForUser((int)($data["call_id"] ?? 0), (int)$this->user_info["id"]);
        if (in_array((int)$call["status"], [2, 3, 4, 5], true)) {
            $this->json(0, "通话已结束");
        }
        $now = date("Y-m-d H:i:s");
        Db::name("livekit_call_participant")
            ->where("call_id", (int)$call["id"])
            ->where("user_id", (int)$this->user_info["id"])
            ->update([
                "status" => 1,
                "device" => (string)input("device", ""),
                "join_time" => $now,
                "update_time" => $now,
            ]);
        if ((int)$call["status"] === 0) {
            Db::name("livekit_call")->where("id", (int)$call["id"])->update([
                "status" => 1,
                "start_time" => $now,
                "update_time" => $now,
            ]);
        }
        $call = Db::name("livekit_call")->where("id", (int)$call["id"])->find();
        $this->publishLiveKitCallEvent($call, "call.accept", $this->liveKitCallParticipantUserIds((int)$call["id"], (int)$this->user_info["id"]), (int)$this->user_info["id"]);
        $this->chatJson(1, "success", $this->liveKitCallPayload($call, (int)$this->user_info["id"], true));
    }

    public function im_call_reject()
    {
        $data = $this->secureChatRequestInput(false);
        $call = $this->liveKitCallForUser((int)($data["call_id"] ?? 0), (int)$this->user_info["id"]);
        $this->liveKitRemoveParticipant((string)$call["room_name"], $this->liveKitIdentity((int)$this->user_info["id"]));
        $now = date("Y-m-d H:i:s");
        Db::name("livekit_call_participant")
            ->where("call_id", (int)$call["id"])
            ->where("user_id", (int)$this->user_info["id"])
            ->update(["status" => 2, "leave_time" => $now, "update_time" => $now]);
        if ((string)$call["call_type"] === "private") {
            Db::name("livekit_call")->where("id", (int)$call["id"])->update(["status" => 3, "end_time" => $now, "update_time" => $now]);
        }
        $call = Db::name("livekit_call")->where("id", (int)$call["id"])->find();
        $this->publishLiveKitCallEvent($call, "call.reject", $this->liveKitCallParticipantUserIds((int)$call["id"], (int)$this->user_info["id"]), (int)$this->user_info["id"]);
        if ((string)$call["call_type"] === "private") {
            $this->publishLiveKitFinalMessage($call, "rejected", (int)$this->user_info["id"]);
        }
        $this->chatJson(1, "已拒绝", $this->liveKitCallPayload($call, (int)$this->user_info["id"], false));
    }

    public function im_call_cancel()
    {
        $data = $this->secureChatRequestInput(false);
        $call = $this->liveKitCallForUser((int)($data["call_id"] ?? 0), (int)$this->user_info["id"]);
        if ((int)$call["creator_id"] !== (int)$this->user_info["id"]) {
            $this->json(0, "只有发起人可以取消");
        }
        if ((int)$call["status"] !== 0) {
            $this->json(0, "当前通话不能取消");
        }
        $this->liveKitDeleteRoom((string)$call["room_name"]);
        $now = date("Y-m-d H:i:s");
        Db::name("livekit_call")->where("id", (int)$call["id"])->update(["status" => 4, "end_time" => $now, "update_time" => $now]);
        Db::name("livekit_call_participant")->where("call_id", (int)$call["id"])->where("status", 0)->update(["status" => 4, "leave_time" => $now, "update_time" => $now]);
        $call = Db::name("livekit_call")->where("id", (int)$call["id"])->find();
        $this->publishLiveKitCallEvent($call, "call.cancel", $this->liveKitCallParticipantUserIds((int)$call["id"], (int)$this->user_info["id"]), (int)$this->user_info["id"]);
        $this->publishLiveKitFinalMessage($call, "canceled", (int)$this->user_info["id"]);
        $this->chatJson(1, "已取消", $this->liveKitCallPayload($call, (int)$this->user_info["id"], false));
    }

    public function im_call_hangup()
    {
        $data = $this->secureChatRequestInput(false);
        $call = $this->liveKitCallForUser((int)($data["call_id"] ?? 0), (int)$this->user_info["id"]);
        $now = date("Y-m-d H:i:s");
        $endCall = (string)$call["call_type"] === "private" || (int)($data["end_call"] ?? 0) === 1 || (int)$call["creator_id"] === (int)$this->user_info["id"];
        if ($endCall) {
            $this->liveKitDeleteRoom((string)$call["room_name"]);
        } else {
            $this->liveKitRemoveParticipant((string)$call["room_name"], $this->liveKitIdentity((int)$this->user_info["id"]));
        }
        Db::name("livekit_call_participant")
            ->where("call_id", (int)$call["id"])
            ->where("user_id", (int)$this->user_info["id"])
            ->update(["status" => 3, "leave_time" => $now, "update_time" => $now]);
        if ($endCall) {
            Db::name("livekit_call")->where("id", (int)$call["id"])->update(["status" => 2, "end_time" => $now, "update_time" => $now]);
        }
        $call = Db::name("livekit_call")->where("id", (int)$call["id"])->find();
        $this->publishLiveKitCallEvent($call, $endCall ? "call.hangup" : "call.left", $this->liveKitCallParticipantUserIds((int)$call["id"], (int)$this->user_info["id"]), (int)$this->user_info["id"]);
        if ($endCall) {
            $this->publishLiveKitFinalMessage($call, "ended", (int)$this->user_info["id"]);
        }
        $this->chatJson(1, "success", $this->liveKitCallPayload($call, (int)$this->user_info["id"], false));
    }

    public function im_call_token()
    {
        $data = $this->secureChatRequestInput(false);
        $call = $this->liveKitCallForUser((int)($data["call_id"] ?? 0), (int)$this->user_info["id"]);
        if (in_array((int)$call["status"], [2, 3, 4, 5], true)) {
            $this->json(0, "通话已结束");
        }
        $this->chatJson(1, "success", $this->liveKitCallPayload($call, (int)$this->user_info["id"], true));
    }

    public function livekit_webhook()
    {
        $raw = file_get_contents("php://input") ?: "";
        $auth = (string)($_SERVER["HTTP_AUTHORIZATION"] ?? "");
        $secret = (string)config("livekit.webhook_secret", "");
        $headerSecret = (string)($_SERVER["HTTP_X_LIVEKIT_SECRET"] ?? "");
        $staticSecretOk = $secret !== "" && (
            hash_equals("Bearer " . $secret, $auth) || hash_equals($secret, $headerSecret)
        );
        $liveKitJwtOk = LiveKitToken::apiKey() !== ""
            && LiveKitToken::apiSecret() !== ""
            && LiveKitToken::verifyWebhook($raw, $auth);
        if (!$staticSecretOk && !$liveKitJwtOk) {
            $this->json(0, "invalid livekit webhook signature");
        }
        $payload = json_decode($raw, true);
        if (!is_array($payload)) {
            $payload = input("");
        }
        $roomName = (string)($payload["room"]["name"] ?? $payload["room_name"] ?? "");
        $call = $roomName !== "" ? Db::name("livekit_call")->where("room_name", $roomName)->find() : [];
        Db::name("livekit_event_log")->insert([
            "appid" => (int)($call["appid"] ?? $this->appid ?? 0),
            "call_id" => (int)($call["id"] ?? 0),
            "event" => mb_substr((string)($payload["event"] ?? ""), 0, 64),
            "room_name" => mb_substr($roomName, 0, 128),
            "participant_identity" => mb_substr((string)($payload["participant"]["identity"] ?? ""), 0, 128),
            "payload" => json_encode($payload, JSON_UNESCAPED_UNICODE),
            "create_time" => date("Y-m-d H:i:s"),
        ]);
        if ($call) {
            $this->handleLiveKitWebhookEvent($call, $payload);
        }
        $this->json(1, "success");
    }

    protected function liveKitDeleteRoom(string $roomName): void
    {
        if ($roomName === "") {
            $this->json(0, "LiveKit房间不能为空");
        }
        if (!$this->liveKitRoomServiceRequest("DeleteRoom", ["room" => $roomName], $roomName)) {
            $this->json(0, "LiveKit删除房间失败：" . $this->liveKitLastError);
        }
    }

    protected function liveKitRemoveParticipant(string $roomName, string $identity): void
    {
        if ($roomName === "" || $identity === "") {
            $this->json(0, "LiveKit参与者参数不能为空");
        }
        $payload = [
            "room" => $roomName,
            "identity" => $identity,
            "revoke_token_ts" => time(),
        ];
        if (!$this->liveKitRoomServiceRequest("RemoveParticipant", $payload, $roomName)) {
            $this->json(0, "LiveKit移除参与者失败：" . $this->liveKitLastError);
        }
    }

    protected function liveKitRoomServiceRequest(string $method, array $payload, string $roomName): bool
    {
        $this->liveKitLastError = "";
        $baseUrl = LiveKitToken::internalUrl();
        $token = LiveKitToken::adminToken($roomName);
        if ($baseUrl === "" || $token === "") {
            $this->liveKitLastError = "服务端管理参数缺失";
            return false;
        }
        $url = $baseUrl . "/twirp/livekit.RoomService/" . $method;
        $body = json_encode($payload, JSON_UNESCAPED_UNICODE);
        $headers = [
            "Content-Type: application/json",
            "Authorization: Bearer " . $token,
        ];
        $response = false;
        $httpCode = 0;
        if (function_exists("curl_init")) {
            $ch = curl_init($url);
            curl_setopt_array($ch, [
                CURLOPT_POST => true,
                CURLOPT_POSTFIELDS => $body,
                CURLOPT_HTTPHEADER => $headers,
                CURLOPT_RETURNTRANSFER => true,
                CURLOPT_CONNECTTIMEOUT => 2,
                CURLOPT_TIMEOUT => 5,
            ]);
            $response = curl_exec($ch);
            $httpCode = (int)curl_getinfo($ch, CURLINFO_HTTP_CODE);
            if ($response === false) {
                $this->liveKitLastError = (string)curl_error($ch);
            }
            curl_close($ch);
        } else {
            $context = stream_context_create([
                "http" => [
                    "method" => "POST",
                    "header" => implode("\r\n", $headers),
                    "content" => (string)$body,
                    "timeout" => 5,
                    "ignore_errors" => true,
                ],
            ]);
            $response = @file_get_contents($url, false, $context);
            $statusLine = (string)($http_response_header[0] ?? "");
            if (preg_match("/\s(\d{3})\s/", $statusLine, $matches)) {
                $httpCode = (int)$matches[1];
            }
            if ($response === false) {
                $this->liveKitLastError = "HTTP请求失败";
            }
        }
        if ($httpCode >= 200 && $httpCode < 300) {
            return true;
        }
        $error = is_string($response) ? json_decode($response, true) : [];
        $code = is_array($error) ? (string)($error["code"] ?? "") : "";
        $message = is_array($error) ? (string)($error["msg"] ?? $error["message"] ?? "") : "";
        if (in_array($code, ["not_found"], true)) {
            return true;
        }
        $this->liveKitLastError = trim("HTTP " . $httpCode . " " . ($code ?: "") . " " . ($message ?: (string)$response));
        return false;
    }

    protected function liveKitCallNo(): string
    {
        return "LC" . date("YmdHis") . strtoupper(bin2hex(random_bytes(6)));
    }

    protected function liveKitRoomName(string $callType): string
    {
        $safeType = preg_replace("/[^a-z0-9_]/i", "", strtolower($callType));
        return "bim_" . (int)$this->appid . "_" . ($safeType ?: "call") . "_" . bin2hex(random_bytes(8));
    }

    protected function liveKitCallTimeout(string $callType): int
    {
        $key = match ($callType) {
            "group" => "livekit.group_timeout",
            "meeting" => "livekit.meeting_timeout",
            default => "livekit.private_timeout",
        };
        return max(30, (int)config($key, 60));
    }

    protected function liveKitIdentity(int $userId): string
    {
        return $this->wukongUid($userId);
    }

    protected function liveKitParticipantName(int $userId): string
    {
        $user = Db::name("user")
            ->where("appid", $this->appid)
            ->where("id", $userId)
            ->field("username,nickname")
            ->find();
        if (!$user) {
            return "用户" . $userId;
        }
        return (string)($user["nickname"] ?: $user["username"] ?: ("用户" . $userId));
    }

    protected function upsertLiveKitParticipant(int $callId, int $userId, string $role, int $status, string $device): void
    {
        $now = date("Y-m-d H:i:s");
        $data = [
            "appid" => $this->appid,
            "call_id" => $callId,
            "user_id" => $userId,
            "uid" => $this->liveKitIdentity($userId),
            "role" => in_array($role, ["host", "member"], true) ? $role : "member",
            "status" => $status,
            "device" => mb_substr($device, 0, 128),
            "update_time" => $now,
        ];
        if ($status === 1) {
            $data["join_time"] = $now;
        }
        $exists = Db::name("livekit_call_participant")
            ->where("appid", $this->appid)
            ->where("call_id", $callId)
            ->where("user_id", $userId)
            ->find();
        if ($exists) {
            Db::name("livekit_call_participant")->where("id", (int)$exists["id"])->update($data);
            return;
        }
        $data["create_time"] = $now;
        Db::name("livekit_call_participant")->insert($data);
    }

    protected function liveKitCallParticipantUserIds(int $callId, int $excludeUserId = 0): array
    {
        $query = Db::name("livekit_call_participant")
            ->where("appid", $this->appid)
            ->where("call_id", $callId);
        if ($excludeUserId > 0) {
            $query->where("user_id", "<>", $excludeUserId);
        }
        $ids = $query->column("user_id");
        return array_values(array_unique(array_filter(array_map("intval", $ids), fn($id) => $id > 0)));
    }

    protected function liveKitCallForUser(int $callId, int $userId): array
    {
        if ($callId <= 0) {
            $this->json(0, "call_id不能为空");
        }
        $call = Db::name("livekit_call")
            ->where("appid", $this->appid)
            ->where("id", $callId)
            ->find();
        if (!$call) {
            $this->json(0, "通话不存在");
        }
        $participant = Db::name("livekit_call_participant")
            ->where("appid", $this->appid)
            ->where("call_id", $callId)
            ->where("user_id", $userId)
            ->find();
        if (!$participant) {
            $this->json(0, "无权访问该通话");
        }
        if ((int)$call["status"] === 0 && !empty($call["expire_time"]) && strtotime((string)$call["expire_time"]) < time()) {
            $now = date("Y-m-d H:i:s");
            Db::name("livekit_call")->where("id", $callId)->update([
                "status" => 5,
                "end_time" => $now,
                "update_time" => $now,
            ]);
            Db::name("livekit_call_participant")
                ->where("call_id", $callId)
                ->where("status", 0)
                ->update(["status" => 4, "leave_time" => $now, "update_time" => $now]);
            $call = Db::name("livekit_call")->where("id", $callId)->find();
            $this->publishLiveKitFinalMessage($call, "missed", 0);
        }
        return $call;
    }

    protected function liveKitCallPayload(array $call, int $userId, bool $includeToken): array
    {
        $rows = Db::name("livekit_call_participant")
            ->where("appid", $this->appid)
            ->where("call_id", (int)$call["id"])
            ->order("id", "asc")
            ->select()
            ->toArray();
        $participants = $this->formatLiveKitParticipantRows($rows);
        $self = [];
        foreach ($participants as $participant) {
            if ((int)$participant["user_id"] === $userId) {
                $self = $participant;
                break;
            }
        }
        $payload = [
            "id" => (int)$call["id"],
            "call_id" => (int)$call["id"],
            "call_no" => (string)$call["call_no"],
            "room_name" => (string)$call["room_name"],
            "call_type" => (string)$call["call_type"],
            "media_type" => (string)$call["media_type"],
            "channel_id" => (string)$call["channel_id"],
            "channel_type" => (int)$call["channel_type"],
            "creator_id" => (int)$call["creator_id"],
            "receiver_id" => (int)$call["receiver_id"],
            "group_id" => (int)$call["group_id"],
            "title" => (string)$call["title"],
            "status" => (int)$call["status"],
            "status_text" => $this->liveKitCallStatusText((int)$call["status"]),
            "start_time" => (string)($call["start_time"] ?? ""),
            "end_time" => (string)($call["end_time"] ?? ""),
            "expire_time" => (string)($call["expire_time"] ?? ""),
            "create_time" => (string)($call["create_time"] ?? ""),
            "participants" => $participants,
            "self" => $self,
            "livekit" => [
                "url" => LiveKitToken::url(),
            ],
        ];
        if ($includeToken) {
            $token = LiveKitToken::issue([
                "identity" => $this->liveKitIdentity($userId),
                "room" => (string)$call["room_name"],
                "name" => $this->liveKitParticipantName($userId),
                "metadata" => [
                    "appid" => (int)$this->appid,
                    "user_id" => $userId,
                    "call_id" => (int)$call["id"],
                    "call_no" => (string)$call["call_no"],
                    "call_type" => (string)$call["call_type"],
                    "media_type" => (string)$call["media_type"],
                ],
            ]);
            $payload["livekit"]["token"] = $token;
            $payload["livekit"]["token_ttl"] = (int)config("livekit.token_ttl", 3600);
        }
        return $payload;
    }

    protected function formatLiveKitParticipantRows(array $rows): array
    {
        $userIds = array_values(array_unique(array_filter(array_map(fn($row) => (int)$row["user_id"], $rows), fn($id) => $id > 0)));
        $users = [];
        if ($userIds) {
            foreach (Db::name("user")->where("appid", $this->appid)->whereIn("id", $userIds)->select()->toArray() as $user) {
                $users[(int)$user["id"]] = $user;
            }
        }
        $result = [];
        foreach ($rows as $row) {
            $userId = (int)$row["user_id"];
            $user = $users[$userId] ?? [];
            $result[] = [
                "user_id" => $userId,
                "uid" => (string)$row["uid"],
                "role" => (string)$row["role"],
                "status" => (int)$row["status"],
                "status_text" => $this->liveKitParticipantStatusText((int)$row["status"]),
                "muted_audio" => (int)$row["muted_audio"],
                "muted_video" => (int)$row["muted_video"],
                "join_time" => (string)($row["join_time"] ?? ""),
                "leave_time" => (string)($row["leave_time"] ?? ""),
                "name" => $user ? (string)($user["nickname"] ?: $user["username"] ?: ("用户" . $userId)) : ("用户" . $userId),
                "avatar" => $user ? (string)($user["usertx"] ?? "") : "",
                "user" => $user ? $this->formatChatUser($user) : [],
            ];
        }
        return $result;
    }

    protected function publishLiveKitCallEvent(array $call, string $event, array $targetUserIds, int $operatorId): int
    {
        $targetUserIds = array_values(array_unique(array_filter(array_map("intval", $targetUserIds), fn($id) => $id > 0)));
        if (!$targetUserIds) {
            return 0;
        }
        $targetUids = array_map(fn($id) => $this->liveKitIdentity((int)$id), $targetUserIds);
        $payload = [
            "type" => "call",
            "event" => $event,
            "client_msg_no" => "call-" . (string)$call["call_no"] . "-" . md5($event . "|" . $operatorId . "|" . microtime(true)),
            "channel_id" => (string)$call["channel_id"],
            "channel_type" => (int)$call["channel_type"],
            "operator_id" => $operatorId,
            "operator_uid" => $this->liveKitIdentity($operatorId),
            "call" => $this->liveKitCallPayload($call, $operatorId, false),
        ];
        return (new GatewayStream())->publishEvent($payload, $targetUids);
    }

    protected function publishLiveKitFinalMessage(array $call, string $status, int $operatorId): void
    {
        if (empty($call) || (int)($call["id"] ?? 0) <= 0) {
            return;
        }
        $callType = (string)($call["call_type"] ?? "");
        if (!in_array($callType, ["private", "group"], true)) {
            return;
        }
        $clientMsgNo = $this->liveKitFinalClientMsgNo($call);
        if ($clientMsgNo === "") {
            return;
        }
        if (Db::name("wukongim_message_queue")->where("client_msg_no", $clientMsgNo)->find()) {
            return;
        }
        $appid = (int)($call["appid"] ?? $this->appid);
        $channelType = (int)($call["channel_type"] ?? 0);
        $channelId = (string)($call["channel_id"] ?? "");
        $creatorId = (int)($call["creator_id"] ?? 0);
        $receiverId = (int)($call["receiver_id"] ?? 0);
        $groupId = (int)($call["group_id"] ?? 0);
        if ($callType === "private") {
            if ($receiverId <= 0 || $creatorId <= 0) {
                return;
            }
            $channelType = (int)config('wukongim.channel_type_person', WukongIM::CHANNEL_TYPE_PERSON);
            $channelId = WukongIM::uid($appid, $receiverId);
        } else {
            $groupQuery = Db::name("chat_group")
                ->where("appid", $appid)
                ->where("status", 1);
            if ($groupId > 0) {
                $groupQuery->where("id", $groupId);
            } elseif ($channelId !== "") {
                $groupQuery->where("channel_id", $channelId);
            } else {
                return;
            }
            $group = $groupQuery->find();
            if (!$group) {
                return;
            }
            $groupId = (int)$group["id"];
            $channelId = (string)$group["channel_id"];
            $channelType = (int)config('wukongim.channel_type_group', WukongIM::CHANNEL_TYPE_GROUP);
        }
        if ($channelId === "" || $channelType <= 0) {
            return;
        }
        $sender = $creatorId > 0 ? $this->liveKitCallUserBrief($appid, $creatorId) : [];
        $receiver = $receiverId > 0 ? $this->liveKitCallUserBrief($appid, $receiverId) : [];
        $duration = $this->liveKitCallDurationSeconds($call, $status);
        $content = $this->liveKitCallFinalContent($call, $status, $duration);
        $fromUid = $creatorId > 0 ? WukongIM::uid($appid, $creatorId) : (string)config('wukongim.system_uid', '____system');
        $payload = [
            "protocol" => "blin.chat.v1",
            "type" => (int)config('wukongim.content_type_call', WukongIM::CONTENT_TYPE_CALL),
            "appid" => $appid,
            "scene" => $callType === "group" ? "group_chat" : "private_chat",
            "content_type" => "call",
            "content" => $content,
            "channel_type" => $channelType,
            "channel_type_name" => $callType === "group" ? "group" : "person",
            "channel_id" => $channelId,
            "sender_id" => $creatorId,
            "sender_uid" => $fromUid,
            "sender_username" => (string)($sender["username"] ?? ""),
            "sender_nickname" => (string)($sender["nickname"] ?? ""),
            "sender_avatar" => (string)($sender["usertx"] ?? ""),
            "operator_id" => $operatorId,
            "operator_uid" => $operatorId > 0 ? WukongIM::uid($appid, $operatorId) : "",
            "call_id" => (int)$call["id"],
            "call_no" => (string)$call["call_no"],
            "call_type" => $callType,
            "media_type" => (string)$call["media_type"],
            "call_status" => $status,
            "duration" => $duration,
            "system_message" => true,
            "call" => [
                "call_id" => (int)$call["id"],
                "call_no" => (string)$call["call_no"],
                "call_type" => $callType,
                "media_type" => (string)$call["media_type"],
                "status" => $status,
                "duration" => $duration,
                "started_at" => $this->liveKitTimeSeconds($call["start_time"] ?? ""),
                "ended_at" => $this->liveKitTimeSeconds($call["end_time"] ?? ""),
                "creator_id" => $creatorId,
                "receiver_id" => $receiverId,
                "group_id" => $groupId,
                "operator_id" => $operatorId,
            ],
        ];
        if ($callType === "private") {
            $payload["receiver_id"] = $receiverId;
            $payload["receiver_uid"] = WukongIM::uid($appid, $receiverId);
            $payload["receiver_username"] = (string)($receiver["username"] ?? "");
            $payload["receiver_nickname"] = (string)($receiver["nickname"] ?? "");
            $payload["receiver_avatar"] = (string)($receiver["usertx"] ?? "");
        } else {
            $payload["group_id"] = $groupId;
            $payload["group_name"] = (string)($group["name"] ?? "群聊");
        }
        try {
            $sendResult = (new WukongIM())->sendConversationNotice($fromUid, $channelId, $channelType, $payload, $clientMsgNo);
            $this->publishSendResultToGateway($sendResult, $clientMsgNo, $payload);
        } catch (\Throwable $e) {
            Db::name("livekit_event_log")->insert([
                "appid" => $appid,
                "call_id" => (int)$call["id"],
                "event" => "call_final_message_failed",
                "room_name" => mb_substr((string)($call["room_name"] ?? ""), 0, 128),
                "participant_identity" => "",
                "payload" => json_encode([
                    "client_msg_no" => $clientMsgNo,
                    "status" => $status,
                    "error" => $e->getMessage(),
                ], JSON_UNESCAPED_UNICODE),
                "create_time" => date("Y-m-d H:i:s"),
            ]);
        }
    }

    protected function liveKitFinalClientMsgNo(array $call): string
    {
        $callNo = preg_replace("/[^A-Za-z0-9_-]/", "", (string)($call["call_no"] ?? ""));
        return $callNo === "" ? "" : "call-final-" . $callNo;
    }

    protected function liveKitFinalStatusFromCall(array $call): string
    {
        return match ((int)($call["status"] ?? 0)) {
            3 => "rejected",
            4 => "canceled",
            5 => "missed",
            default => "ended",
        };
    }

    protected function liveKitCallDurationSeconds(array $call, string $status): int
    {
        if ($status !== "ended") {
            return 0;
        }
        $start = $this->liveKitTimeSeconds($call["start_time"] ?? "");
        $end = $this->liveKitTimeSeconds($call["end_time"] ?? "");
        if ($start <= 0 || $end <= 0 || $end < $start) {
            return 0;
        }
        return max(1, $end - $start);
    }

    protected function liveKitTimeSeconds($value): int
    {
        if (is_numeric($value)) {
            $number = (int)$value;
            return $number > 100000000000 ? (int)floor($number / 1000) : $number;
        }
        $time = strtotime((string)$value);
        return $time === false ? 0 : $time;
    }

    protected function liveKitCallFinalContent(array $call, string $status, int $duration): string
    {
        if ($status === "canceled") {
            return "已取消";
        }
        if ($status === "rejected") {
            return "已拒绝";
        }
        if ($status === "missed") {
            return "未接听";
        }
        if ($status === "failed") {
            return "通话异常结束";
        }
        $media = (string)($call["media_type"] ?? "audio") === "video" ? "视频通话" : "语音通话";
        if ((string)($call["call_type"] ?? "") === "group") {
            $media = "群" . $media;
        }
        return $media . " " . $this->liveKitDurationLabel($duration);
    }

    protected function liveKitDurationLabel(int $seconds): string
    {
        $seconds = max(0, $seconds);
        $hours = intdiv($seconds, 3600);
        $minutes = intdiv($seconds % 3600, 60);
        $remain = $seconds % 60;
        if ($hours > 0) {
            return sprintf("%d:%02d:%02d", $hours, $minutes, $remain);
        }
        return sprintf("%02d:%02d", $minutes, $remain);
    }

    protected function liveKitCallUserBrief(int $appid, int $userId): array
    {
        if ($appid <= 0 || $userId <= 0) {
            return [];
        }
        return Db::name("user")
            ->where("appid", $appid)
            ->where("id", $userId)
            ->field("id,username,nickname,usertx")
            ->find() ?: [];
    }

    protected function handleLiveKitWebhookEvent(array $call, array $payload): void
    {
        $event = strtolower((string)($payload["event"] ?? ""));
        $identity = (string)($payload["participant"]["identity"] ?? "");
        $userId = $this->liveKitUserIdFromIdentity($identity);
        $now = date("Y-m-d H:i:s");
        if ($event === "participant_joined" && $userId > 0) {
            Db::name("livekit_call_participant")
                ->where("appid", (int)$call["appid"])
                ->where("call_id", (int)$call["id"])
                ->where("user_id", $userId)
                ->update(["status" => 1, "join_time" => $now, "update_time" => $now]);
            if ((int)$call["status"] === 0) {
                Db::name("livekit_call")->where("id", (int)$call["id"])->update(["status" => 1, "start_time" => $now, "update_time" => $now]);
            }
            return;
        }
        if ($event === "participant_left" && $userId > 0) {
            Db::name("livekit_call_participant")
                ->where("appid", (int)$call["appid"])
                ->where("call_id", (int)$call["id"])
                ->where("user_id", $userId)
                ->update(["status" => 3, "leave_time" => $now, "update_time" => $now]);
            return;
        }
        if (in_array($event, ["room_finished", "room_deleted"], true)) {
            Db::name("livekit_call")
                ->where("id", (int)$call["id"])
                ->whereNotIn("status", [2, 3, 4, 5])
                ->update(["status" => 2, "end_time" => $now, "update_time" => $now]);
            $latest = Db::name("livekit_call")->where("id", (int)$call["id"])->find();
            if ($latest) {
                $this->publishLiveKitFinalMessage($latest, $this->liveKitFinalStatusFromCall($latest), 0);
            }
        }
    }

    protected function liveKitUserIdFromIdentity(string $identity): int
    {
        if (preg_match("/user(\d+)$/", $identity, $matches)) {
            return (int)$matches[1];
        }
        return 0;
    }

    protected function liveKitCallStatusText(int $status): string
    {
        return match ($status) {
            1 => "通话中",
            2 => "已结束",
            3 => "已拒绝",
            4 => "已取消",
            5 => "未接听",
            default => "呼叫中",
        };
    }

    protected function liveKitParticipantStatusText(int $status): string
    {
        return match ($status) {
            1 => "已加入",
            2 => "已拒绝",
            3 => "已离开",
            4 => "未接听",
            default => "已邀请",
        };
    }

    //当前在线用户列表
    public function im_online_users()
    {
        $this->secureChatRequestInput();
        $gateway = new GatewayStream();
        $this->syncGatewayPresenceTargetsForUserAndFriends((int)$this->user_info["id"]);
        $uids = $gateway->onlineUids((int)$this->appid, (int)$this->page, (int)$this->limit);
        $seen = [];
        $result = [];
        foreach ($uids as $uid) {
            $uidInfo = WukongIM::parseUid($uid);
            if (!$uidInfo || $uidInfo["appid"] !== (int)$this->appid || isset($seen[$uidInfo["user_id"]])) {
                continue;
            }
            $user = Db::name("user")->where("id", $uidInfo["user_id"])->where("appid", $this->appid)->find();
            if (!$user) {
                continue;
            }
            $profile = array_merge($this->formatImUserProfile($user), $gateway->presenceForUid($uid));
            $result[] = $profile;
            $seen[$uidInfo["user_id"]] = true;
            if (count($result) >= (int)$this->limit) {
                break;
            }
        }

        $data_rs["list"] = $result;
        $data_rs["pagecount"] = count($result) < (int)$this->limit ? (int)$this->page : (int)$this->page + 1;
        $data_rs["current_number"] = $this->page;
        $data_rs["total_connections"] = count($result);
        $data_rs["presence_source"] = "gateway";
        $this->chatJson(1, "success", $data_rs);
    }

    protected function otcService(): OtcService
    {
        return new OtcService((int)$this->appid, (array)$this->user_info);
    }

    protected function digitalAssetService(): DigitalAssetService
    {
        return new DigitalAssetService((int)$this->appid, (array)$this->user_info);
    }

    public function wallet_asset_overview()
    {
        $this->secureChatRequestInput(false);
        try { $this->chatJson(1, 'success', $this->digitalAssetService()->overview()); }
        catch (\Throwable $e) { $this->json(0, $e->getMessage()); }
    }

    public function wallet_asset_deposit_address()
    {
        $this->secureChatRequestInput(false);
        try { $this->chatJson(1, 'success', $this->digitalAssetService()->depositAddress()); }
        catch (\Throwable $e) { $this->json(0, $e->getMessage()); }
    }

    public function wallet_asset_transfer_preview()
    {
        $data=$this->secureChatRequestInput();
        try { $this->chatJson(1, 'success', $this->digitalAssetService()->transferPreview($data)); }
        catch (\Throwable $e) { $this->json(0, $e->getMessage()); }
    }

    public function wallet_asset_transfer_create()
    {
        $data=$this->secureChatRequestInput();
        try { $this->verifyWalletPayPassword((int)$this->user_info['id'],trim((string)($data['pay_password']??'')));$this->chatJson(1, '转账成功', $this->digitalAssetService()->transfer($data)); }
        catch (\Throwable $e) { $this->json(0, $e->getMessage()); }
    }

    public function wallet_asset_withdraw_preview()
    {
        $data=$this->secureChatRequestInput();
        try { $this->chatJson(1, 'success', $this->digitalAssetService()->withdrawPreview($data)); }
        catch (\Throwable $e) { $this->json(0, $e->getMessage()); }
    }

    public function wallet_asset_withdraw_create()
    {
        $data=$this->secureChatRequestInput();
        try { $this->verifyWalletPayPassword((int)$this->user_info['id'],trim((string)($data['pay_password']??'')));$this->chatJson(1, '提币申请已提交', $this->digitalAssetService()->withdraw($data)); }
        catch (\Throwable $e) { $this->json(0, $e->getMessage()); }
    }

    public function wallet_asset_bill_list()
    {
        $data=$this->secureChatRequestInput(false);
        try { $this->chatJson(1, 'success', ['list'=>$this->digitalAssetService()->bills($data)]); }
        catch (\Throwable $e) { $this->json(0, $e->getMessage()); }
    }

    public function wallet_asset_withdraw_list()
    {
        $this->secureChatRequestInput(false);
        try { $this->chatJson(1, 'success', ['list'=>$this->digitalAssetService()->withdrawals()]); }
        catch (\Throwable $e) { $this->json(0, $e->getMessage()); }
    }

    protected function assetExchangeService(): AssetExchangeService
    {
        return new AssetExchangeService((int)$this->appid, (array)$this->user_info);
    }

    public function wallet_asset_exchange_overview()
    {
        $this->secureChatRequestInput(false);
        try { $this->chatJson(1, 'success', $this->assetExchangeService()->overview()); }
        catch (\Throwable $e) { $this->json(0, $e->getMessage()); }
    }

    public function wallet_asset_exchange_quote()
    {
        $data=$this->secureChatRequestInput();
        try { $this->chatJson(1, 'success', $this->assetExchangeService()->quote($data)); }
        catch (\Throwable $e) { $this->json(0, $e->getMessage()); }
    }

    public function wallet_asset_exchange_execute()
    {
        $data=$this->secureChatRequestInput();
        try {$this->verifyWalletPayPassword((int)$this->user_info['id'],trim((string)($data['pay_password']??'')));$this->chatJson(1,'兑换成功',$this->assetExchangeService()->execute($data));}
        catch (\Throwable $e) { $this->json(0, $e->getMessage()); }
    }

    public function wallet_asset_exchange_orders()
    {
        $this->secureChatRequestInput(false);
        try { $this->chatJson(1, 'success', ['list'=>$this->assetExchangeService()->orders()]); }
        catch (\Throwable $e) { $this->json(0, $e->getMessage()); }
    }

    public function otc_config() { $this->otcCall('config', false); }
    public function otc_asset_list() { $this->otcCall('assets', false, true); }
    public function wallet_asset_address_list() { $this->otcCall('addresses', false, true); }
    public function otc_payment_method_list() { $this->otcCall('paymentMethods', false, true); }
    public function otc_trade_options() { $this->otcCall('tradeOptions'); }
    public function otc_merchant_status() { $this->otcCall('merchant', false); }
    public function otc_ad_list() { $this->otcCall('ads', false, true); }
    public function otc_order_list() { $this->otcCall('orders', false, true); }

    public function wallet_asset_address_add() { $this->otcCall('saveAddress'); }
    public function otc_payment_method_save() { $this->otcCall('savePaymentMethod'); }
    public function otc_merchant_apply()
    {
        $data=$this->secureChatRequestInput();
        try{$this->verifyWalletPayPassword((int)$this->user_info['id'],trim((string)($data['pay_password']??'')));$this->chatJson(1,'申请已提交',$this->otcService()->applyMerchant($data));}
        catch(\Throwable $e){$this->json(0,$e->getMessage());}
    }
    public function otc_merchant_deposit_pay()
    {
        $data=$this->secureChatRequestInput();
        try {
            $this->verifyWalletPayPassword((int)$this->user_info['id'], trim((string)($data['pay_password'] ?? '')));
            $this->chatJson(1, '保证金缴纳成功', $this->otcService()->payDeposit($this->walletRequestId($data['request_id'] ?? '')));
        } catch (\Throwable $e) { $this->json(0, $e->getMessage()); }
    }
    public function otc_merchant_ad_create()
    {
        $data=$this->secureChatRequestInput();
        try{$this->verifyWalletPayPassword((int)$this->user_info['id'],trim((string)($data['pay_password']??'')));$this->chatJson(1,'广告已提交审核',$this->otcService()->createAd($data));}
        catch(\Throwable $e){$this->json(0,$e->getMessage());}
    }

    public function otc_order_buy_create()
    {
        $data = $this->secureChatRequestInput();
        try { $this->verifyWalletPayPassword((int)$this->user_info['id'],trim((string)($data['pay_password']??'')));$this->chatJson(1, '买入成功，USDT已存入数字钱包', $this->otcService()->createOrder($data, 'buy')); }
        catch (\Throwable $e) { $this->json(0, $e->getMessage()); }
    }

    public function otc_order_sell_create()
    {
        $data = $this->secureChatRequestInput();
        try { $this->verifyWalletPayPassword((int)$this->user_info['id'],trim((string)($data['pay_password']??'')));$this->chatJson(1, '卖出成功，款项已存入平台钱包', $this->otcService()->createOrder($data, 'sell')); }
        catch (\Throwable $e) { $this->json(0, $e->getMessage()); }
    }

    public function otc_order_detail()
    {
        $data = $this->secureChatRequestInput();
        try { $this->chatJson(1, 'success', $this->otcService()->order(trim((string)($data['order_no'] ?? '')))); }
        catch (\Throwable $e) { $this->json(0, $e->getMessage()); }
    }

    public function otc_order_mark_paid() { $this->otcCall('markPaid'); }
    public function otc_order_confirm_received() { $this->otcCall('confirmRelease'); }
    public function otc_order_cancel() { $this->otcCall('cancel'); }
    public function otc_order_appeal() { $this->otcCall('appeal'); }
    public function otc_order_review() { $this->otcCall('review'); }

    protected function otcCall(string $method, bool $requirePayload = true, bool $wrapList = false): void
    {
        $data = $this->secureChatRequestInput($requirePayload);
        try {
            $result = $requirePayload || in_array($method, ['ads', 'orders'], true)
                ? $this->otcService()->{$method}($data)
                : $this->otcService()->{$method}();
            $this->chatJson(1, 'success', $wrapList ? ['list' => $result] : $result);
        } catch (\Throwable $e) {
            $this->json(0, $e->getMessage());
        }
    }
}
