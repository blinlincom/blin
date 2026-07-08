package bimotc.com

import android.Manifest
import android.app.Activity
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.view.WindowManager
import io.flutter.plugin.common.MethodChannel
import kotlin.math.abs

class RealtimeNotificationBridge(private val activity: Activity) {
    private val manager =
        activity.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

    fun configure(channel: MethodChannel) {
        ensureChannels()
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "ensureNotificationPermission" -> result.success(ensureNotificationPermission())
                "getLaunchPayload" -> result.success(consumePayload(activity.intent))
                "showIncomingCall" -> runCatching {
                    showIncomingCall(
                        callId = call.argument<Int>("call_id") ?: 0,
                        title = call.argument<String>("title").orEmpty(),
                        text = call.argument<String>("text").orEmpty(),
                        video = call.argument<Boolean>("video") ?: false
                    )
                    true
                }.onSuccess(result::success).onFailure {
                    result.error("SHOW_CALL_NOTIFICATION_ERROR", it.message, null)
                }
                "cancelIncomingCall" -> runCatching {
                    cancelIncomingCall(call.argument<Int>("call_id") ?: 0)
                    true
                }.onSuccess(result::success).onFailure {
                    result.error("CANCEL_CALL_NOTIFICATION_ERROR", it.message, null)
                }
                "showMessageNotification" -> runCatching {
                    showMessageNotification(
                        channelId = call.argument<String>("channel_id").orEmpty(),
                        channelType = call.argument<Int>("channel_type") ?: 0,
                        clientMsgNo = call.argument<String>("client_msg_no").orEmpty(),
                        title = call.argument<String>("title").orEmpty(),
                        text = call.argument<String>("text").orEmpty()
                    )
                    true
                }.onSuccess(result::success).onFailure {
                    result.error("SHOW_MESSAGE_NOTIFICATION_ERROR", it.message, null)
                }
                "showFriendRequestNotification" -> runCatching {
                    showFriendRequestNotification(
                        applyId = call.argument<String>("apply_id").orEmpty(),
                        title = call.argument<String>("title").orEmpty(),
                        text = call.argument<String>("text").orEmpty()
                    )
                    true
                }.onSuccess(result::success).onFailure {
                    result.error("SHOW_FRIEND_REQUEST_NOTIFICATION_ERROR", it.message, null)
                }
                "cancelMessageNotification" -> runCatching {
                    cancelMessageNotification(
                        channelId = call.argument<String>("channel_id").orEmpty(),
                        channelType = call.argument<Int>("channel_type") ?: 0
                    )
                    true
                }.onSuccess(result::success).onFailure {
                    result.error("CANCEL_MESSAGE_NOTIFICATION_ERROR", it.message, null)
                }
                else -> result.notImplemented()
            }
        }
    }

    fun dispatchIntent(intent: Intent?, channel: MethodChannel?) {
        val payload = consumePayload(intent) ?: return
        channel?.invokeMethod("notificationTap", payload)
    }

    private fun ensureNotificationPermission(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
            return true
        }
        if (activity.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) ==
            PackageManager.PERMISSION_GRANTED
        ) {
            return true
        }
        activity.requestPermissions(
            arrayOf(Manifest.permission.POST_NOTIFICATIONS),
            REQUEST_POST_NOTIFICATIONS
        )
        return activity.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) ==
            PackageManager.PERMISSION_GRANTED
    }

    private fun showIncomingCall(callId: Int, title: String, text: String, video: Boolean) {
        if (callId <= 0 || !notificationsEnabled()) {
            return
        }
        val safeTitle = title.ifBlank { if (video) "视频通话" else "语音通话" }
        val safeText = text.ifBlank { if (video) "邀请你进行视频通话" else "邀请你进行语音通话" }
        val intent = payloadIntent(
            type = TYPE_CALL,
            callId = callId,
            channelId = "",
            channelType = 0,
            clientMsgNo = ""
        )
        val pendingIntent = PendingIntent.getActivity(
            activity,
            CALL_REQUEST_BASE + callId,
            intent,
            pendingIntentFlags()
        )
        val builder = notificationBuilder(CALL_CHANNEL_ID)
            .setSmallIcon(activity.applicationInfo.icon)
            .setContentTitle(safeTitle)
            .setContentText(safeText)
            .setCategory(Notification.CATEGORY_CALL)
            .setPriority(Notification.PRIORITY_MAX)
            .setOngoing(true)
            .setAutoCancel(false)
            .setShowWhen(true)
            .setContentIntent(pendingIntent)
            .setFullScreenIntent(pendingIntent, true)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
            builder.setVisibility(Notification.VISIBILITY_PUBLIC)
        }
        manager.notify(callNotificationId(callId), builder.build())
    }

    private fun cancelIncomingCall(callId: Int) {
        if (callId <= 0) {
            return
        }
        manager.cancel(callNotificationId(callId))
        clearCallWindowFlags()
    }

    private fun showMessageNotification(
        channelId: String,
        channelType: Int,
        clientMsgNo: String,
        title: String,
        text: String
    ) {
        if (channelId.isBlank() || clientMsgNo.isBlank() || !notificationsEnabled()) {
            return
        }
        val safeTitle = title.ifBlank { "新消息" }
        val safeText = text.ifBlank { "[消息]" }
        val intent = payloadIntent(
            type = TYPE_MESSAGE,
            callId = 0,
            channelId = channelId,
            channelType = channelType,
            clientMsgNo = clientMsgNo
        )
        val notificationId = messageNotificationId(channelId, channelType)
        val pendingIntent = PendingIntent.getActivity(
            activity,
            MESSAGE_REQUEST_BASE + abs(notificationId),
            intent,
            pendingIntentFlags()
        )
        val builder = notificationBuilder(MESSAGE_CHANNEL_ID)
            .setSmallIcon(activity.applicationInfo.icon)
            .setContentTitle(safeTitle)
            .setContentText(safeText)
            .setStyle(Notification.BigTextStyle().bigText(safeText))
            .setCategory(Notification.CATEGORY_MESSAGE)
            .setPriority(Notification.PRIORITY_HIGH)
            .setAutoCancel(true)
            .setShowWhen(true)
            .setContentIntent(pendingIntent)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
            builder.setVisibility(Notification.VISIBILITY_PRIVATE)
        }
        manager.notify(notificationId, builder.build())
    }

    private fun cancelMessageNotification(channelId: String, channelType: Int) {
        if (channelId.isBlank()) {
            return
        }
        manager.cancel(messageNotificationId(channelId, channelType))
    }

    private fun showFriendRequestNotification(applyId: String, title: String, text: String) {
        if (applyId.isBlank() || !notificationsEnabled()) {
            return
        }
        val safeTitle = title.ifBlank { "新的朋友" }
        val safeText = text.ifBlank { "请求添加你为联系人" }
        val intent = payloadIntent(
            type = TYPE_FRIEND_REQUEST,
            callId = 0,
            channelId = "",
            channelType = 0,
            clientMsgNo = applyId
        )
        val notificationId = friendRequestNotificationId(applyId)
        val pendingIntent = PendingIntent.getActivity(
            activity,
            FRIEND_REQUEST_BASE + abs(notificationId),
            intent,
            pendingIntentFlags()
        )
        val builder = notificationBuilder(MESSAGE_CHANNEL_ID)
            .setSmallIcon(activity.applicationInfo.icon)
            .setContentTitle(safeTitle)
            .setContentText(safeText)
            .setStyle(Notification.BigTextStyle().bigText(safeText))
            .setCategory(Notification.CATEGORY_MESSAGE)
            .setPriority(Notification.PRIORITY_HIGH)
            .setAutoCancel(true)
            .setShowWhen(true)
            .setContentIntent(pendingIntent)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
            builder.setVisibility(Notification.VISIBILITY_PRIVATE)
        }
        manager.notify(notificationId, builder.build())
    }

    private fun payloadIntent(
        type: String,
        callId: Int,
        channelId: String,
        channelType: Int,
        clientMsgNo: String
    ): Intent {
        return Intent(activity, MainActivity::class.java)
            .setAction(ACTION_NOTIFICATION_TAP)
            .addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP)
            .putExtra(EXTRA_TYPE, type)
            .putExtra(EXTRA_CALL_ID, callId)
            .putExtra(EXTRA_CHANNEL_ID, channelId)
            .putExtra(EXTRA_CHANNEL_TYPE, channelType)
            .putExtra(EXTRA_CLIENT_MSG_NO, clientMsgNo)
    }

    private fun consumePayload(intent: Intent?): Map<String, Any>? {
        if (intent?.action != ACTION_NOTIFICATION_TAP) {
            return null
        }
        val payload = mapOf(
            "type" to intent.getStringExtra(EXTRA_TYPE).orEmpty(),
            "call_id" to intent.getIntExtra(EXTRA_CALL_ID, 0),
            "channel_id" to intent.getStringExtra(EXTRA_CHANNEL_ID).orEmpty(),
            "channel_type" to intent.getIntExtra(EXTRA_CHANNEL_TYPE, 0),
            "client_msg_no" to intent.getStringExtra(EXTRA_CLIENT_MSG_NO).orEmpty()
        )
        intent.action = Intent.ACTION_MAIN
        intent.removeExtra(EXTRA_TYPE)
        intent.removeExtra(EXTRA_CALL_ID)
        intent.removeExtra(EXTRA_CHANNEL_ID)
        intent.removeExtra(EXTRA_CHANNEL_TYPE)
        intent.removeExtra(EXTRA_CLIENT_MSG_NO)
        return payload
    }

    private fun notificationBuilder(channelId: String): Notification.Builder {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(activity, channelId)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(activity)
        }
    }

    private fun ensureChannels() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            return
        }
        if (manager.getNotificationChannel(CALL_CHANNEL_ID) == null) {
            val callChannel = NotificationChannel(
                CALL_CHANNEL_ID,
                "BIM 通话提醒",
                NotificationManager.IMPORTANCE_HIGH
            )
            callChannel.description = "用于语音和视频通话来电提醒"
            callChannel.lockscreenVisibility = Notification.VISIBILITY_PUBLIC
            callChannel.enableVibration(true)
            manager.createNotificationChannel(callChannel)
        }
        if (manager.getNotificationChannel(MESSAGE_CHANNEL_ID) == null) {
            val messageChannel = NotificationChannel(
                MESSAGE_CHANNEL_ID,
                "BIM 消息提醒",
                NotificationManager.IMPORTANCE_HIGH
            )
            messageChannel.description = "用于聊天消息提醒"
            messageChannel.lockscreenVisibility = Notification.VISIBILITY_PRIVATE
            messageChannel.enableVibration(true)
            manager.createNotificationChannel(messageChannel)
        }
    }

    private fun notificationsEnabled(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
            return true
        }
        return activity.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) ==
            PackageManager.PERMISSION_GRANTED
    }

    private fun clearCallWindowFlags() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            activity.setShowWhenLocked(false)
            activity.setTurnScreenOn(false)
        } else {
            @Suppress("DEPRECATION")
            activity.window.clearFlags(
                WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                    WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON
            )
        }
    }

    private fun pendingIntentFlags(): Int {
        return PendingIntent.FLAG_UPDATE_CURRENT or
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                PendingIntent.FLAG_IMMUTABLE
            } else {
                0
            }
    }

    private fun callNotificationId(callId: Int): Int = CALL_NOTIFICATION_BASE + callId

    private fun messageNotificationId(channelId: String, channelType: Int): Int {
        return MESSAGE_NOTIFICATION_BASE + abs("$channelType:$channelId".hashCode() % 100000)
    }

    private fun friendRequestNotificationId(applyId: String): Int {
        return FRIEND_REQUEST_NOTIFICATION_BASE + abs(applyId.hashCode() % 100000)
    }

    companion object {
        private const val REQUEST_POST_NOTIFICATIONS = 29001
        private const val CALL_CHANNEL_ID = "bim_realtime_calls"
        private const val MESSAGE_CHANNEL_ID = "bim_realtime_messages"
        private const val ACTION_NOTIFICATION_TAP = "bimotc.com.ACTION_NOTIFICATION_TAP"
        private const val TYPE_CALL = "call"
        private const val TYPE_MESSAGE = "message"
        private const val TYPE_FRIEND_REQUEST = "friend_request"
        private const val EXTRA_TYPE = "type"
        private const val EXTRA_CALL_ID = "call_id"
        private const val EXTRA_CHANNEL_ID = "channel_id"
        private const val EXTRA_CHANNEL_TYPE = "channel_type"
        private const val EXTRA_CLIENT_MSG_NO = "client_msg_no"
        private const val CALL_NOTIFICATION_BASE = 910000
        private const val MESSAGE_NOTIFICATION_BASE = 920000
        private const val FRIEND_REQUEST_NOTIFICATION_BASE = 925000
        private const val CALL_REQUEST_BASE = 930000
        private const val MESSAGE_REQUEST_BASE = 940000
        private const val FRIEND_REQUEST_BASE = 950000
    }
}
