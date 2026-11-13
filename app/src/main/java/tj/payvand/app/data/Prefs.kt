package tj.payvand.app.data

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.withContext
import tj.payvand.app.ui.theme.ThemeMode
import tj.payvand.core.BackendConfig
import tj.payvand.core.SessionStore
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/** Несекретные настройки приложения. */
class Prefs(context: Context) {
    private val sp = context.getSharedPreferences("payvand_prefs", Context.MODE_PRIVATE)

    val languageChosen = MutableStateFlow(sp.getBoolean("lang_chosen", false))
    val theme = MutableStateFlow(runCatching { ThemeMode.valueOf(sp.getString("theme", null) ?: "DARK") }.getOrDefault(ThemeMode.DARK))
    val server = MutableStateFlow(loadServer())

    private fun loadServer(): BackendConfig? {
        val u = sp.getString("server_url", null); val k = sp.getString("server_key", null)
        return if (!u.isNullOrBlank() && !k.isNullOrBlank()) BackendConfig(u, k) else null
    }

    fun setLanguageChosen() { sp.edit().putBoolean("lang_chosen", true).apply(); languageChosen.value = true }
    fun setTheme(m: ThemeMode) { sp.edit().putString("theme", m.name).apply(); theme.value = m }
    fun setServer(c: BackendConfig?) {
        sp.edit().apply { if (c == null) { remove("server_url"); remove("server_key") } else { putString("server_url", c.url); putString("server_key", c.anonKey) } }.apply()
        server.value = c
    }
    var pushToken: String?
        get() = sp.getString("push_token", null)
        set(v) { sp.edit().putString("push_token", v).apply() }
}

/**
 * Сессия (access/refresh-токены) хранится зашифрованной AES-256-GCM.
 * Ключ создаётся в Android Keystore и не покидает защищённое хранилище устройства;
 * резервное копирование данных приложения отключено в манифесте.
 */
class SecureSessionStore(context: Context) : SessionStore {
    private val sp = context.getSharedPreferences("payvand_session", Context.MODE_PRIVATE)

    private fun key(): SecretKey {
        val ks = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        (ks.getKey(ALIAS, null) as? SecretKey)?.let { return it }
        return KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore").apply {
            init(KeyGenParameterSpec.Builder(ALIAS, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setKeySize(256).build())
        }.generateKey()
    }

    override suspend fun save(json: String) = withContext(Dispatchers.IO) {
        val c = Cipher.getInstance("AES/GCM/NoPadding").apply { init(Cipher.ENCRYPT_MODE, key()) }
        val ct = c.doFinal(json.toByteArray(Charsets.UTF_8))
        sp.edit().putString("s", Base64.encodeToString(c.iv + ct, Base64.NO_WRAP)).apply()
    }

    override suspend fun load(): String? = withContext(Dispatchers.IO) {
        val raw = sp.getString("s", null) ?: return@withContext null
        try {
            val all = Base64.decode(raw, Base64.NO_WRAP)
            val c = Cipher.getInstance("AES/GCM/NoPadding").apply { init(Cipher.DECRYPT_MODE, key(), GCMParameterSpec(128, all, 0, 12)) }
            String(c.doFinal(all, 12, all.size - 12), Charsets.UTF_8)
        } catch (_: Exception) {
            sp.edit().remove("s").apply()   // ключ утрачен (сброс устройства) — требуем войти заново
            null
        }
    }

    override suspend fun clear() { sp.edit().remove("s").apply() }

    private companion object { const val ALIAS = "payvand_session_key" }
}
