package tj.payvand.app.push

import androidx.appcompat.app.AppCompatDelegate
import com.google.firebase.FirebaseApp
import com.google.firebase.FirebaseOptions
import com.google.firebase.messaging.FirebaseMessaging
import com.google.firebase.messaging.FirebaseMessagingService
import com.google.firebase.messaging.RemoteMessage
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.suspendCancellableCoroutine
import tj.payvand.app.AppContainer
import tj.payvand.app.BuildConfig
import tj.payvand.app.MessageText
import tj.payvand.app.PayvandApp
import tj.payvand.core.PayvandApi
import kotlin.coroutines.resume

/**
 * Push через Firebase Cloud Messaging (бесплатно). Включается, только если при сборке заданы
 * PAYVAND_FCM_* (см. docs/SETUP.md). Без них приложение работает, но уведомления приходят лишь
 * пока процесс жив и держит realtime-соединение.
 */
object Push {
    val configured: Boolean get() = BuildConfig.FCM_APP_ID.isNotBlank() && BuildConfig.FCM_API_KEY.isNotBlank() &&
        BuildConfig.FCM_PROJECT_ID.isNotBlank() && BuildConfig.FCM_SENDER_ID.isNotBlank()

    private fun ensureInit(c: AppContainer): Boolean {
        if (!configured) return false
        if (FirebaseApp.getApps(c.app).isEmpty()) {
            FirebaseApp.initializeApp(c.app, FirebaseOptions.Builder()
                .setApplicationId(BuildConfig.FCM_APP_ID).setApiKey(BuildConfig.FCM_API_KEY)
                .setProjectId(BuildConfig.FCM_PROJECT_ID).setGcmSenderId(BuildConfig.FCM_SENDER_ID).build())
        }
        return true
    }

    fun language(): String = AppCompatDelegate.getApplicationLocales().get(0)?.language ?: java.util.Locale.getDefault().language

    suspend fun registerIfConfigured(c: AppContainer, api: PayvandApi) {
        if (!runCatching { ensureInit(c) }.getOrDefault(false)) return
        val token = suspendCancellableCoroutine<String?> { cont ->
            FirebaseMessaging.getInstance().token.addOnCompleteListener { t -> cont.resume(if (t.isSuccessful) t.result else null) }
        } ?: return
        c.prefs.pushToken = token
        runCatching { api.registerPushToken(token, language()) }
    }
}

class PayvandMessagingService : FirebaseMessagingService() {
    override fun onNewToken(token: String) {
        val c = (application as PayvandApp).container
        c.prefs.pushToken = token
        val api = c.session.value?.api ?: return
        if (api.currentUserId != null) CoroutineScope(Dispatchers.IO).launch { runCatching { api.registerPushToken(token, Push.language()) } }
    }

    override fun onMessageReceived(message: RemoteMessage) {
        val c = (application as PayvandApp).container
        val d = message.data
        val conv = d["conversation_id"] ?: return
        // приложение на экране и подключено — сообщение уже показано через realtime
        if (c.foreground.value) return
        val body = if (d["kind"] == "system") return else MessageText.preview(this, d["kind"], d["body"], false)
        val sender = d["sender"].orEmpty()
        val title = d["title"].orEmpty()
        c.notifier.message(conv, title.ifBlank { sender }, if (d["direct"] == "true" || sender.isBlank()) body else "$sender: $body")
    }
}
