package tj.payvand.app

import android.app.Application
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import tj.payvand.app.data.MediaCache
import tj.payvand.app.data.Prefs
import tj.payvand.app.data.SecureSessionStore
import tj.payvand.app.data.VoicePlayer
import tj.payvand.app.push.Push
import tj.payvand.core.AuthState
import tj.payvand.core.BackendConfig
import tj.payvand.core.ConversationSummary
import tj.payvand.core.Message
import tj.payvand.core.PayvandApi
import tj.payvand.core.Profile
import tj.payvand.core.RealtimeEvent
import tj.payvand.core.SupabaseApi

/** Ручной DI-контейнер: один на процесс. */
class AppContainer(val app: Application) {
    val prefs = Prefs(app)
    val mediaCache = MediaCache(app)
    val voicePlayer = VoicePlayer()
    val notifier = Notifier(app)
    val foreground = MutableStateFlow(false)
    /** Беседа, которую нужно открыть (нажатие на уведомление). */
    val pendingOpen = MutableStateFlow<String?>(null)

    private val _session = MutableStateFlow<ChatSession?>(null)
    val session: StateFlow<ChatSession?> = _session

    init { serverConfig()?.let { connect(it) } }

    fun serverConfig(): BackendConfig? = prefs.server.value
        ?: BackendConfig(BuildConfig.SUPABASE_URL, BuildConfig.SUPABASE_ANON_KEY).takeIf { it.url.isNotBlank() && it.anonKey.isNotBlank() }

    val hasBuiltInServer: Boolean get() = BuildConfig.SUPABASE_URL.isNotBlank() && BuildConfig.SUPABASE_ANON_KEY.isNotBlank()

    fun connect(config: BackendConfig) {
        _session.value?.close()
        _session.value = ChatSession(SupabaseApi(config, SecureSessionStore(app)), this).also { it.start() }
    }

    fun disconnectServer() {
        _session.value?.close()
        _session.value = null
        prefs.setServer(null)
        serverConfig()?.let { connect(it) }
    }
}

/**
 * Состояние вошедшего пользователя, общее для всех экранов: список бесед, кэш профилей,
 * realtime-события, отметка «в сети», локальные уведомления.
 */
class ChatSession(val api: PayvandApi, private val c: AppContainer) {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    val conversations = MutableStateFlow<List<ConversationSummary>>(emptyList())
    val loaded = MutableStateFlow(false)
    val me = MutableStateFlow<Profile?>(null)
    val meLoaded = MutableStateFlow(false)
    val profiles = MutableStateFlow<Map<String, Profile>>(emptyMap())
    @Volatile var openConversationId: String? = null
    private val refreshTrigger = Channel<Unit>(Channel.CONFLATED)

    fun start() {
        scope.launch {
            // collectLatest сам отменяет задачи прежнего пользователя при смене состояния входа
            api.authState.collectLatest { st ->
                if (st is AuthState.SignedIn) {
                    coroutineScope { runUser(this) }
                } else if (st is AuthState.SignedOut) {
                    conversations.value = emptyList(); loaded.value = false
                    me.value = null; meLoaded.value = false; profiles.value = emptyMap()
                    c.notifier.cancelAll()
                }
            }
        }
    }

    private suspend fun runUser(s: CoroutineScope) {
        s.launch { loadMe() }
        s.launch { for (u in refreshTrigger) { refreshNow(); delay(350) } }
        s.launch {
            api.events.collect { e ->
                when (e) {
                    is RealtimeEvent.MessageInserted -> { onIncoming(e.message); refresh() }
                    is RealtimeEvent.MessageUpdated, is RealtimeEvent.MembersChanged, RealtimeEvent.Reconnected -> refresh()
                }
            }
        }
        s.launch {
            c.foreground.collectLatest { fg ->
                if (fg) {
                    runCatching { api.connectRealtime() }
                    refresh()
                    while (isActive) { runCatching { api.heartbeat() }; delay(60_000) }
                }
            }
        }
        s.launch { Push.registerIfConfigured(c, api) }
        runCatching { api.connectRealtime() }
        refresh()
    }

    suspend fun loadMe() {
        // при плохой сети повторяем, пока профиль не загрузится
        var wait = 1000L
        while (true) {
            val r = runCatching { api.myProfile() }
            if (r.isSuccess) { me.value = r.getOrNull(); meLoaded.value = true; remember(listOfNotNull(r.getOrNull())); return }
            delay(wait); wait = (wait * 2).coerceAtMost(15_000)
        }
    }

    suspend fun reloadMe() { me.value = api.myProfile(); meLoaded.value = true; remember(listOfNotNull(me.value)) }

    fun refresh() { refreshTrigger.trySend(Unit) }

    private suspend fun refreshNow() {
        runCatching { api.conversations() }.onSuccess { list ->
            conversations.value = list; loaded.value = true
            if (list.any { it.unreadCount > 0 }) runCatching { api.markDelivered() }
        }
    }

    fun remember(list: List<Profile>) { if (list.isNotEmpty()) profiles.update { it + list.associateBy { p -> p.id } } }

    suspend fun profile(id: String): Profile? = profiles.value[id] ?: runCatching { api.profile(id) }.getOrNull()?.also { remember(listOf(it)) }

    private suspend fun onIncoming(m: Message) {
        val myId = api.currentUserId ?: return
        if (m.senderId == null || m.senderId == myId || m.isSystem) return
        if (c.foreground.value && openConversationId == m.conversationId) return
        val conv = conversations.value.firstOrNull { it.id == m.conversationId }
        val sender = profile(m.senderId!!)?.displayName.orEmpty()
        val title = conv?.takeIf { !it.isDirect }?.title ?: sender
        val text = MessageText.preview(c.app, m.kind, m.body, false)
        c.notifier.message(m.conversationId, title, if (conv != null && !conv.isDirect) "$sender: $text" else text)
    }

    suspend fun signOut() {
        runCatching { c.prefs.pushToken?.let { api.unregisterPushToken(it) } }
        c.voicePlayer.stop()
        api.signOut()
        c.mediaCache.clear()
    }

    fun close() { scope.cancel(); api.close() }
}

object MessageText {
    fun preview(ctx: Context, kind: String?, body: String?, deleted: Boolean): String = when {
        deleted -> ctx.getString(R.string.msg_deleted)
        kind == "image" -> "📷 " + (body?.takeIf { it.isNotBlank() } ?: ctx.getString(R.string.msg_photo))
        kind == "video" -> "🎬 " + (body?.takeIf { it.isNotBlank() } ?: ctx.getString(R.string.msg_video))
        kind == "file" -> "📎 " + (body?.takeIf { it.isNotBlank() } ?: ctx.getString(R.string.msg_file))
        kind == "voice" -> "🎤 " + ctx.getString(R.string.msg_voice)
        else -> body.orEmpty()
    }

    fun system(ctx: Context, body: String, actor: String): String {
        val parts = body.split('|', limit = 2)
        val who = actor.ifBlank { "…" }
        return when (parts[0]) {
            "created" -> ctx.getString(R.string.sys_created, who)
            "added" -> ctx.getString(R.string.sys_added, who, parts.getOrElse(1) { "" })
            "removed" -> ctx.getString(R.string.sys_removed, who, parts.getOrElse(1) { "" })
            "joined" -> ctx.getString(R.string.sys_joined, who)
            "left" -> ctx.getString(R.string.sys_left, who)
            else -> body
        }
    }
}

class Notifier(private val app: Application) {
    init {
        val ch = NotificationChannel(CHANNEL, app.getString(R.string.notif_channel), NotificationManager.IMPORTANCE_HIGH)
        app.getSystemService(NotificationManager::class.java).createNotificationChannel(ch)
    }

    fun message(conversationId: String, title: String, text: String) {
        if (Build.VERSION.SDK_INT >= 33 &&
            ContextCompat.checkSelfPermission(app, android.Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) return
        val intent = Intent(app, MainActivity::class.java).putExtra(EXTRA_CONVERSATION, conversationId)
            .addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP)
        val pi = PendingIntent.getActivity(app, conversationId.hashCode(), intent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val n = NotificationCompat.Builder(app, CHANNEL)
            .setSmallIcon(R.drawable.ic_notification)
            .setColor(0xFF19E28A.toInt())
            .setContentTitle(title.ifBlank { app.getString(R.string.app_name) })
            .setContentText(text)
            .setStyle(NotificationCompat.BigTextStyle().bigText(text))
            .setCategory(NotificationCompat.CATEGORY_MESSAGE)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setAutoCancel(true)
            .setContentIntent(pi)
            .build()
        runCatching { NotificationManagerCompat.from(app).notify(conversationId.hashCode(), n) }
    }

    fun cancel(conversationId: String) = NotificationManagerCompat.from(app).cancel(conversationId.hashCode())
    fun cancelAll() = NotificationManagerCompat.from(app).cancelAll()

    companion object {
        const val CHANNEL = "messages"
        const val EXTRA_CONVERSATION = "conversation_id"
    }
}
