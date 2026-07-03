package bimotc.com

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
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
    private val channelName = "bimotc.com/cache_security"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName).setMethodCallHandler { call, result ->
            when (call.method) {
                "getCacheKey" -> runCatching {
                    SecureCacheKeyStore(applicationContext).getOrCreateCacheKey()
                }.onSuccess(result::success).onFailure {
                    result.error("CACHE_KEY_ERROR", it.message, null)
                }
                else -> result.notImplemented()
            }
        }
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
