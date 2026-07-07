package bimotc.com

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.PowerManager
import android.provider.Settings
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import android.app.NotificationManager
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.security.KeyStore
import java.security.SecureRandom
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

class MainActivity : FlutterActivity() {
    private val cacheSecurityChannelName = "bimotc.com/cache_security"
    private val backgroundReceiveChannelName = "bimotc.com/background_receive"
    private val realtimeNotificationChannelName = "bimotc.com/realtime_notifications"
    private var realtimeNotificationChannel: MethodChannel? = null
    private var realtimeNotificationBridge: RealtimeNotificationBridge? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        applyRealtimeWindowFlags(intent)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, cacheSecurityChannelName).setMethodCallHandler { call, result ->
            when (call.method) {
                "getCacheKey" -> runCatching {
                    SecureCacheKeyStore(applicationContext).getOrCreateCacheKey()
                }.onSuccess(result::success).onFailure {
                    result.error("CACHE_KEY_ERROR", it.message, null)
                }
                else -> result.notImplemented()
            }
        }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, backgroundReceiveChannelName).setMethodCallHandler { call, result ->
            when (call.method) {
                "start", "update" -> runCatching {
                    val title = call.argument<String>("title") ?: "BIM 正在接收消息"
                    val text = call.argument<String>("text") ?: "后台接收保护运行中"
                    BackgroundReceiveService.start(applicationContext, title, text)
                    true
                }.onSuccess(result::success).onFailure {
                    result.error("BACKGROUND_RECEIVE_START_ERROR", it.message, null)
                }
                "stop" -> runCatching {
                    BackgroundReceiveService.stop(applicationContext)
                    true
                }.onSuccess(result::success).onFailure {
                    result.error("BACKGROUND_RECEIVE_STOP_ERROR", it.message, null)
                }
                "status" -> result.success(backgroundReceiveStatus())
                "openNotificationSettings" -> runCatching {
                    openNotificationSettings()
                    true
                }.onSuccess(result::success).onFailure {
                    result.error("OPEN_NOTIFICATION_SETTINGS_ERROR", it.message, null)
                }
                "openBatterySettings" -> runCatching {
                    openBatterySettings()
                    true
                }.onSuccess(result::success).onFailure {
                    result.error("OPEN_BATTERY_SETTINGS_ERROR", it.message, null)
                }
                else -> result.notImplemented()
            }
        }
        realtimeNotificationChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            realtimeNotificationChannelName
        ).also { channel ->
            realtimeNotificationBridge = RealtimeNotificationBridge(this).also { bridge ->
                bridge.configure(channel)
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        applyRealtimeWindowFlags(intent)
        realtimeNotificationBridge?.dispatchIntent(intent, realtimeNotificationChannel)
    }

    private fun applyRealtimeWindowFlags(intent: Intent?) {
        val showForCall = intent?.action == realtimeNotificationTapAction &&
            intent.getStringExtra(realtimeNotificationTypeExtra) == "call"
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(showForCall)
            setTurnScreenOn(showForCall)
        } else if (showForCall) {
            @Suppress("DEPRECATION")
            window.addFlags(
                WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                    WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON
            )
        } else {
            @Suppress("DEPRECATION")
            window.clearFlags(
                WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                    WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON
            )
        }
    }

    private fun backgroundReceiveStatus(): Map<String, Any> {
        val powerManager = getSystemService(Context.POWER_SERVICE) as PowerManager
        val batteryIgnored = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            powerManager.isIgnoringBatteryOptimizations(packageName)
        } else {
            true
        }
        val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val notificationEnabled = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            notificationManager.areNotificationsEnabled()
        } else {
            true
        }
        return mapOf(
            "platform" to "android",
            "supported" to true,
            "service_running" to BackgroundReceiveService.running,
            "notification_permission_granted" to notificationEnabled,
            "battery_optimization_ignored" to batteryIgnored,
            "note" to "Android 后台接收依赖前台服务、通知权限和电池优化设置"
        )
    }

    private fun openNotificationSettings() {
        val intent = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS)
                .putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
        } else {
            Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS)
                .setData(Uri.parse("package:$packageName"))
        }
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        startActivity(intent)
    }

    private fun openBatterySettings() {
        val intent = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS)
                .setData(Uri.parse("package:$packageName"))
        } else {
            Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS)
                .setData(Uri.parse("package:$packageName"))
        }
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        startActivity(intent)
    }

    companion object {
        private const val realtimeNotificationTapAction = "bimotc.com.ACTION_NOTIFICATION_TAP"
        private const val realtimeNotificationTypeExtra = "type"
    }
}

private class SecureCacheKeyStore(private val context: Context) {
    private val prefs = context.getSharedPreferences("bim_cache_state", Context.MODE_PRIVATE)
    private val alias = "bim_cache_key_wrap_v1"
    private val valueKey = "cache_key_cipher"
    private val ivKey = "cache_key_iv"
    private val androidKeyStore = "AndroidKeyStore"
    private val transformation = "AES/GCM/NoPadding"
    private val keyAlphabet = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz"

    // MMKV only receives a short cryptKey at runtime; the persisted copy is wrapped by Android Keystore.
    fun getOrCreateCacheKey(): String {
        val storedCipher = prefs.getString(valueKey, null)
        val storedIv = prefs.getString(ivKey, null)
        if (!storedCipher.isNullOrBlank() && !storedIv.isNullOrBlank()) {
            return decrypt(storedCipher, storedIv)
        }

        val plainKey = newMmkvCryptKey()
        encryptAndStore(plainKey)
        return plainKey
    }

    private fun newMmkvCryptKey(): String {
        val random = SecureRandom()
        return buildString {
            repeat(16) {
                append(keyAlphabet[random.nextInt(keyAlphabet.length)])
            }
        }
    }

    private fun encryptAndStore(plainKey: String) {
        val cipher = Cipher.getInstance(transformation)
        cipher.init(Cipher.ENCRYPT_MODE, getOrCreateSecretKey())
        prefs.edit()
            .putString(
                valueKey,
                Base64.encodeToString(
                    cipher.doFinal(plainKey.toByteArray(Charsets.UTF_8)),
                    Base64.NO_WRAP
                )
            )
            .putString(ivKey, Base64.encodeToString(cipher.iv, Base64.NO_WRAP))
            .apply()
    }

    private fun decrypt(cipherText: String, ivText: String): String {
        val cipher = Cipher.getInstance(transformation)
        val spec = GCMParameterSpec(128, Base64.decode(ivText, Base64.NO_WRAP))
        cipher.init(Cipher.DECRYPT_MODE, getOrCreateSecretKey(), spec)
        return String(cipher.doFinal(Base64.decode(cipherText, Base64.NO_WRAP)), Charsets.UTF_8)
    }

    private fun getOrCreateSecretKey(): SecretKey {
        val keyStore = KeyStore.getInstance(androidKeyStore).apply { load(null) }
        (keyStore.getKey(alias, null) as? SecretKey)?.let { return it }

        val generator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, androidKeyStore)
        val spec = KeyGenParameterSpec.Builder(
            alias,
            KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT
        )
            .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
            .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
            .setRandomizedEncryptionRequired(true)
            .build()
        generator.init(spec)
        return generator.generateKey()
    }
}
