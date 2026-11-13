package tj.payvand.core

import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.auth.Auth
import io.github.jan.supabase.auth.OtpType
import io.github.jan.supabase.auth.SessionManager
import io.github.jan.supabase.auth.auth
import io.github.jan.supabase.auth.exception.AuthRestException
import io.github.jan.supabase.auth.providers.builtin.Email
import io.github.jan.supabase.auth.status.SessionStatus
import io.github.jan.supabase.auth.user.UserSession
import io.github.jan.supabase.createSupabaseClient
import io.github.jan.supabase.exceptions.RestException
import io.github.jan.supabase.postgrest.Postgrest
import io.github.jan.supabase.postgrest.exception.PostgrestRestException
import io.github.jan.supabase.postgrest.from
import io.github.jan.supabase.postgrest.postgrest
import io.github.jan.supabase.postgrest.query.Order
import io.github.jan.supabase.realtime.PostgresAction
import io.github.jan.supabase.realtime.Realtime
import io.github.jan.supabase.realtime.RealtimeChannel
import io.github.jan.supabase.realtime.channel
import io.github.jan.supabase.realtime.postgresChangeFlow
import io.github.jan.supabase.realtime.realtime
import io.github.jan.supabase.storage.Storage
import io.github.jan.supabase.storage.storage
import io.ktor.client.engine.okhttp.OkHttp
import io.ktor.http.ContentType
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharedFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.launchIn
import kotlinx.coroutines.flow.onEach
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.decodeFromJsonElement
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.put
import java.io.IOException
import kotlin.time.Duration.Companion.seconds

private val json = Json { ignoreUnknownKeys = true; explicitNulls = false; coerceInputValues = true }

private class StoreSessionManager(private val store: SessionStore) : SessionManager {
    override suspend fun saveSession(session: UserSession) = store.save(json.encodeToString(UserSession.serializer(), session))
    override suspend fun loadSession(): UserSession? =
        runCatching { store.load()?.let { json.decodeFromString(UserSession.serializer(), it) } }.getOrNull()
    override suspend fun deleteSession() = store.clear()
}

class SupabaseApi(config: BackendConfig, sessionStore: SessionStore) : PayvandApi {

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    private val client: SupabaseClient = createSupabaseClient(config.url.trim().trimEnd('/'), config.anonKey.trim()) {
        httpEngine = OkHttp.create()
        install(Auth) {
            sessionManager = StoreSessionManager(sessionStore)
            alwaysAutoRefresh = true
            autoLoadFromStorage = true
        }
        install(Postgrest)
        install(Storage)
        install(Realtime) { reconnectDelay = 4.seconds }
    }

    private val _authState = MutableStateFlow<AuthState>(AuthState.Loading)
    override val authState: StateFlow<AuthState> = _authState
    private val _connection = MutableStateFlow(ConnectionState.CONNECTING)
    override val connection: StateFlow<ConnectionState> = _connection
    private val _events = MutableSharedFlow<RealtimeEvent>(extraBufferCapacity = 256)
    override val events: SharedFlow<RealtimeEvent> = _events

    private var channel: RealtimeChannel? = null
    private var channelJob: Job? = null
    private val realtimeLock = Mutex()
    private var wasConnected = false

    init {
        client.auth.sessionStatus.onEach { st ->
            _authState.value = when (st) {
                is SessionStatus.Authenticated -> AuthState.SignedIn(st.session.user?.id ?: client.auth.currentUserOrNull()?.id.orEmpty(), st.session.user?.email)
                is SessionStatus.NotAuthenticated -> AuthState.SignedOut
                is SessionStatus.Initializing -> AuthState.Loading
                // не удалось обновить токен (нет сети): сессия остаётся, пользователь не разлогинивается
                is SessionStatus.RefreshFailure -> _authState.value.let { if (it is AuthState.Loading) currentSignedIn() ?: AuthState.SignedOut else it }
            }
        }.launchIn(scope)
        client.realtime.status.onEach { st ->
            // CONNECTED выставляется только когда канал реально подписан (см. connectRealtime)
            if (st == Realtime.Status.DISCONNECTED) _connection.value = ConnectionState.DISCONNECTED
            else if (st == Realtime.Status.CONNECTING) _connection.value = ConnectionState.CONNECTING
        }.launchIn(scope)
    }

    private fun currentSignedIn(): AuthState.SignedIn? =
        client.auth.currentSessionOrNull()?.user?.let { AuthState.SignedIn(it.id, it.email) }

    override val currentUserId: String? get() = client.auth.currentUserOrNull()?.id

    private fun uid(): String = currentUserId ?: throw PayvandException(PayvandException.Code.FORBIDDEN)

    // ------------------------------------------------------------ ошибки ---
    private suspend fun <T> call(block: suspend () -> T): T = try {
        block()
    } catch (e: CancellationException) {
        throw e
    } catch (e: PayvandException) {
        throw e
    } catch (e: Throwable) {
        throw mapError(e)
    }

    private fun mapError(e: Throwable): PayvandException {
        val msg = (e.message ?: "").lowercase()
        val code = when (e) {
            is AuthRestException -> when (e.error) {
                "invalid_credentials" -> PayvandException.Code.INVALID_CREDENTIALS
                "email_not_confirmed" -> PayvandException.Code.EMAIL_NOT_CONFIRMED
                "user_already_exists", "email_exists" -> PayvandException.Code.USER_EXISTS
                "weak_password" -> PayvandException.Code.WEAK_PASSWORD
                "otp_expired", "otp_disabled", "flow_state_expired" -> PayvandException.Code.INVALID_CODE
                "over_email_send_rate_limit", "over_request_rate_limit", "over_sms_send_rate_limit" -> PayvandException.Code.RATE_LIMIT
                "email_address_invalid", "email_address_not_authorized" -> PayvandException.Code.INVALID_EMAIL
                "validation_failed" -> if ("password" in msg) PayvandException.Code.WEAK_PASSWORD else PayvandException.Code.INVALID_EMAIL
                "same_password" -> PayvandException.Code.WEAK_PASSWORD
                else -> when {
                    e.statusCode == 429 -> PayvandException.Code.RATE_LIMIT
                    "token" in msg && ("expired" in msg || "invalid" in msg) -> PayvandException.Code.INVALID_CODE
                    else -> PayvandException.Code.UNKNOWN
                }
            }
            is PostgrestRestException -> when {
                "rate_limit" in msg -> PayvandException.Code.RATE_LIMIT
                e.code == "23505" && "username" in msg -> PayvandException.Code.USERNAME_TAKEN
                e.code == "23514" && "username" in msg -> PayvandException.Code.INVALID_USERNAME
                e.code == "42501" && "blocked" in msg -> PayvandException.Code.BLOCKED
                e.code == "42501" -> PayvandException.Code.FORBIDDEN
                e.code == "PGRST202" || e.code == "PGRST205" || e.code == "42P01" || e.code == "42883" -> PayvandException.Code.SERVER_MISCONFIGURED
                e.statusCode == 401 || e.statusCode == 403 -> PayvandException.Code.FORBIDDEN
                else -> PayvandException.Code.UNKNOWN
            }
            is RestException -> when {
                e.statusCode == 413 || "too large" in msg || "exceeded the maximum" in msg -> PayvandException.Code.FILE_TOO_LARGE
                e.statusCode == 429 -> PayvandException.Code.RATE_LIMIT
                e.statusCode == 401 || e.statusCode == 403 || "row-level security" in msg -> PayvandException.Code.FORBIDDEN
                e.statusCode == 404 && "bucket" in msg -> PayvandException.Code.SERVER_MISCONFIGURED
                else -> PayvandException.Code.UNKNOWN
            }
            is IOException -> PayvandException.Code.NETWORK
            else -> if (e::class.simpleName?.contains("Timeout") == true) PayvandException.Code.NETWORK else PayvandException.Code.UNKNOWN
        }
        return PayvandException(code, e)
    }

    // --------------------------------------------------------- авторизация ---
    override suspend fun signUp(email: String, password: String): SignUpResult = call {
        val user = client.auth.signUpWith(Email) { this.email = email.trim(); this.password = password }
        if (client.auth.currentSessionOrNull() != null) return@call SignUpResult.SignedIn
        // GoTrue скрывает существование адреса: возвращает «пустого» пользователя без identities
        if (user != null && user.identities.isNullOrEmpty()) throw PayvandException(PayvandException.Code.USER_EXISTS)
        SignUpResult.NeedsEmailCode
    }

    override suspend fun confirmSignUp(email: String, code: String) = call {
        client.auth.verifyEmailOtp(OtpType.Email.SIGNUP, email.trim(), code.trim())
    }

    override suspend fun resendSignUpCode(email: String) = call {
        client.auth.resendEmail(OtpType.Email.SIGNUP, email.trim())
    }

    override suspend fun signIn(email: String, password: String) = call {
        client.auth.signInWith(Email) { this.email = email.trim(); this.password = password }
    }

    override suspend fun requestPasswordRecovery(email: String) = call {
        client.auth.resetPasswordForEmail(email.trim())
    }

    override suspend fun confirmPasswordRecovery(email: String, code: String, newPassword: String) = call {
        client.auth.verifyEmailOtp(OtpType.Email.RECOVERY, email.trim(), code.trim())
        client.auth.updateUser { password = newPassword }
        Unit
    }

    override suspend fun signOut() {
        runCatching { disconnectRealtime() }
        try {
            client.auth.signOut()
        } catch (e: CancellationException) {
            throw e
        } catch (_: Throwable) {
            // без сети серверный logout невозможен — всё равно стираем локальную сессию
            runCatching { client.auth.clearSession() }
        }
    }

    override suspend fun deleteAccount() {
        call { client.postgrest.rpc("delete_account") }
        runCatching { disconnectRealtime() }
        runCatching { client.auth.clearSession() }
    }

    // ------------------------------------------------------------- профиль ---
    override suspend fun myProfile(): Profile = call {
        val id = uid()
        profile(id) ?: throw PayvandException(PayvandException.Code.SERVER_MISCONFIGURED)
    }

    override suspend fun myPhone(): String? = call {
        val rows = json.decodeFromString<JsonArray>(
            client.from("profile_private").select { filter { eq("user_id", uid()) } }.data
        )
        rows.firstOrNull()?.jsonObject?.get("phone")?.let { if (it is JsonNull) null else it.jsonPrimitive.content }
    }

    override suspend fun setPhone(phone: String?) = call {
        val p = phone?.trim().orEmpty()
        if (p.isNotEmpty() && !Limits.PHONE_REGEX.matches(p)) throw PayvandException(PayvandException.Code.UNKNOWN)
        client.postgrest.rpc("set_phone", buildJsonObject { put("p", p) })
        Unit
    }

    override suspend fun updateProfile(username: String, displayName: String, bio: String) = call {
        val u = username.trim().lowercase().removePrefix("@")
        if (!Limits.USERNAME_REGEX.matches(u)) throw PayvandException(PayvandException.Code.INVALID_USERNAME)
        client.from("profiles").update({
            set("username", u); set("display_name", displayName.trim().take(64)); set("bio", bio.trim().take(200))
        }) { filter { eq("id", uid()) } }
        Unit
    }

    override suspend fun uploadAvatar(jpeg: ByteArray): String = call {
        if (jpeg.size > Limits.MAX_AVATAR_BYTES) throw PayvandException(PayvandException.Code.FILE_TOO_LARGE)
        val path = "${uid()}/${java.util.UUID.randomUUID()}.jpg"
        client.storage.from("avatars").upload(path, jpeg) { contentType = ContentType.Image.JPEG }
        path
    }

    override suspend fun setMyAvatar(path: String?) = call {
        client.from("profiles").update({ set("avatar_path", path) }) { filter { eq("id", uid()) } }
        Unit
    }

    override suspend fun profile(userId: String): Profile? = profiles(listOf(userId)).firstOrNull()

    override suspend fun profiles(userIds: Collection<String>): List<Profile> = call {
        if (userIds.isEmpty()) return@call emptyList()
        json.decodeFromString<List<Profile>>(
            client.from("profiles").select { filter { isIn("id", userIds.distinct()) } }.data
        )
    }

    override suspend fun searchUsers(query: String): List<Profile> = call {
        if (query.trim().length < 2) return@call emptyList()
        json.decodeFromString<List<Profile>>(client.postgrest.rpc("search_users", buildJsonObject { put("q", query) }).data)
    }

    override suspend fun heartbeat() = call { client.postgrest.rpc("heartbeat"); Unit }

    override fun avatarUrl(path: String?): String? =
        path?.takeIf { it.isNotBlank() }?.let { client.storage.from("avatars").publicUrl(it) }

    // -------------------------------------------------------------- беседы ---
    override suspend fun conversations(): List<ConversationSummary> = call {
        json.decodeFromString<List<ConversationSummary>>(client.postgrest.rpc("my_conversations").data)
    }

    private fun scalarString(data: String): String = json.decodeFromString<JsonPrimitive>(data).content

    override suspend fun openDirect(userId: String): String = call {
        scalarString(client.postgrest.rpc("create_direct", buildJsonObject { put("other", userId) }).data)
    }

    override suspend fun createConversation(
        type: ConversationType, title: String, description: String, isPublic: Boolean,
        memberIds: List<String>, avatarPath: String?,
    ): String = call {
        scalarString(client.postgrest.rpc("create_conversation", buildJsonObject {
            put("p_type", type.wire); put("p_title", title.trim()); put("p_description", description.trim())
            put("p_is_public", isPublic); put("p_member_ids", JsonArray(memberIds.map { JsonPrimitive(it) }))
            put("p_avatar_path", avatarPath)
        }).data)
    }

    override suspend fun updateConversation(id: String, title: String, description: String, isPublic: Boolean, avatarPath: String?) = call {
        client.postgrest.rpc("update_conversation", buildJsonObject {
            put("c", id); put("p_title", title.trim()); put("p_description", description.trim())
            put("p_is_public", isPublic); put("p_avatar_path", avatarPath)
        })
        Unit
    }

    override suspend fun members(conversationId: String): List<MemberProfile> = call {
        val members = json.decodeFromString<List<Member>>(
            client.from("members").select { filter { eq("conversation_id", conversationId) } }.data
        )
        val byId = profiles(members.map { it.userId }).associateBy { it.id }
        members.mapNotNull { m -> byId[m.userId]?.let { MemberProfile(m, it) } }
            .sortedWith(compareBy({ when (it.member.role) { "owner" -> 0; "admin" -> 1; else -> 2 } }, { it.profile.displayName.lowercase() }))
    }

    override suspend fun addMembers(conversationId: String, userIds: List<String>): Int = call {
        client.postgrest.rpc("add_members", buildJsonObject {
            put("c", conversationId); put("ids", JsonArray(userIds.map { JsonPrimitive(it) }))
        }).data.trim().toIntOrNull() ?: 0
    }

    override suspend fun removeMember(conversationId: String, userId: String) = call {
        client.postgrest.rpc("remove_member", buildJsonObject { put("c", conversationId); put("target", userId) })
        Unit
    }

    override suspend fun leave(conversationId: String) = removeMember(conversationId, uid())

    override suspend fun setRole(conversationId: String, userId: String, admin: Boolean) = call {
        client.postgrest.rpc("set_member_role", buildJsonObject {
            put("c", conversationId); put("target", userId); put("new_role", if (admin) "admin" else "member")
        })
        Unit
    }

    override suspend fun searchPublic(query: String): List<PublicConversation> = call {
        json.decodeFromString<List<PublicConversation>>(client.postgrest.rpc("search_public", buildJsonObject { put("q", query) }).data)
    }

    override suspend fun joinPublic(conversationId: String) = call {
        client.postgrest.rpc("join_public", buildJsonObject { put("c", conversationId) })
        Unit
    }

    // ----------------------------------------------------------- сообщения ---
    override suspend fun messages(conversationId: String, before: String?, limit: Int): List<Message> = call {
        json.decodeFromString<List<Message>>(
            client.from("messages").select {
                filter {
                    eq("conversation_id", conversationId)
                    if (before != null) lt("created_at", before)
                }
                order("created_at", Order.DESCENDING)
                limit(limit.toLong())
            }.data
        )
    }

    private suspend fun insertMessage(row: JsonObject, id: String): Message = try {
        json.decodeFromString<List<Message>>(client.from("messages").insert(row) { select() }.data).first()
    } catch (e: PostgrestRestException) {
        // повторная отправка после обрыва сети: сообщение с этим id уже сохранено
        if (e.code == "23505") fetchMessage(id) ?: throw e else throw e
    }

    private suspend fun fetchMessage(id: String): Message? =
        json.decodeFromString<List<Message>>(client.from("messages").select { filter { eq("id", id) } }.data).firstOrNull()

    override suspend fun sendText(conversationId: String, id: String, text: String, replyTo: String?): Message = call {
        val body = text.trim().take(Limits.MAX_MESSAGE_CHARS)
        insertMessage(buildJsonObject {
            put("id", id); put("conversation_id", conversationId); put("sender_id", uid())
            put("kind", "text"); put("body", body); if (replyTo != null) put("reply_to_id", replyTo)
        }, id)
    }

    private fun safeName(name: String): String =
        name.replace(Regex("[^A-Za-z0-9._-]"), "_").takeLast(60).ifBlank { "file" }

    override suspend fun sendMedia(conversationId: String, id: String, media: OutgoingMedia, caption: String, replyTo: String?): Message = call {
        if (media.bytes.size > Limits.MAX_MEDIA_BYTES) throw PayvandException(PayvandException.Code.FILE_TOO_LARGE)
        val me = uid()
        val path = "$conversationId/$me/$id-${safeName(media.fileName)}"
        val ct = runCatching { ContentType.parse(media.mime) }.getOrDefault(ContentType.Application.OctetStream)
        client.storage.from("media").upload(path, media.bytes) { upsert = true; contentType = ct }
        try {
            insertMessage(buildJsonObject {
                put("id", id); put("conversation_id", conversationId); put("sender_id", me)
                put("kind", media.kind); put("body", caption.trim().take(Limits.MAX_MESSAGE_CHARS))
                put("media_path", path); put("media_name", media.fileName.take(200)); put("media_mime", media.mime.take(100))
                put("media_size", media.bytes.size.toLong()); if (media.durationMs != null) put("duration_ms", media.durationMs)
                if (replyTo != null) put("reply_to_id", replyTo)
            }, id)
        } catch (e: Throwable) {
            if (e !is IOException) runCatching { client.storage.from("media").delete(listOf(path)) }
            throw e
        }
    }

    override suspend fun forward(message: Message, toConversationId: String, id: String): Message = call {
        val me = uid()
        var newPath: String? = null
        if (message.mediaPath != null) {
            newPath = "$toConversationId/$me/$id-${safeName(message.mediaName ?: "file")}"
            client.storage.from("media").copy(message.mediaPath, newPath)
        }
        val origin = message.forwardedFrom ?: message.senderId
        insertMessage(buildJsonObject {
            put("id", id); put("conversation_id", toConversationId); put("sender_id", me)
            put("kind", message.kind); put("body", message.body)
            if (newPath != null) {
                put("media_path", newPath); put("media_name", message.mediaName); put("media_mime", message.mediaMime)
                put("media_size", message.mediaSize); put("duration_ms", message.durationMs)
            }
            if (origin != null && origin != me) put("forwarded_from", origin)
        }, id)
    }

    override suspend fun editMessage(messageId: String, text: String) = call {
        client.postgrest.rpc("edit_message", buildJsonObject { put("m", messageId); put("new_body", text.trim()) })
        Unit
    }

    override suspend fun deleteMessage(messageId: String) = call {
        val data = client.postgrest.rpc("delete_message", buildJsonObject { put("m", messageId) }).data
        val path = runCatching { json.decodeFromString<JsonPrimitive>(data) }.getOrNull()
            ?.takeIf { it !is JsonNull }?.content
        if (!path.isNullOrBlank()) runCatching { client.storage.from("media").delete(listOf(path)) }
        Unit
    }

    override suspend fun markRead(conversationId: String) = call {
        client.postgrest.rpc("mark_read", buildJsonObject { put("c", conversationId) }); Unit
    }

    override suspend fun markDelivered() = call { client.postgrest.rpc("mark_delivered"); Unit }

    override suspend fun downloadMedia(path: String): ByteArray = call {
        client.storage.from("media").downloadAuthenticated(path)
    }

    // --------------------------------------------------------- безопасность ---
    override suspend fun block(userId: String) = call {
        client.from("blocks").upsert(buildJsonObject { put("blocker_id", uid()); put("blocked_id", userId) }) {
            onConflict = "blocker_id,blocked_id"; ignoreDuplicates = true
        }
        Unit
    }

    override suspend fun unblock(userId: String) = call {
        client.from("blocks").delete { filter { eq("blocker_id", uid()); eq("blocked_id", userId) } }
        Unit
    }

    override suspend fun blockedUsers(): List<Profile> = call {
        val ids = json.decodeFromString<JsonArray>(
            client.from("blocks").select { filter { eq("blocker_id", uid()) } }.data
        ).map { it.jsonObject.getValue("blocked_id").jsonPrimitive.content }
        profiles(ids)
    }

    override suspend fun report(userId: String?, conversationId: String?, messageId: String?, reason: String) = call {
        client.from("reports").insert(buildJsonObject {
            put("reporter_id", uid()); put("reported_user_id", userId); put("conversation_id", conversationId)
            put("message_id", messageId); put("reason", reason.trim().take(500).ifBlank { "-" })
        })
        Unit
    }

    // ----------------------------------------------------------------- push ---
    override suspend fun registerPushToken(token: String, lang: String) = call {
        // токен устройства мог остаться за прежним аккаунтом — тогда RLS не даст его перезаписать
        client.from("device_tokens").upsert(buildJsonObject {
            put("token", token); put("user_id", uid()); put("lang", lang); put("platform", "android")
        }) { onConflict = "token" }
        Unit
    }

    override suspend fun unregisterPushToken(token: String) = call {
        client.from("device_tokens").delete { filter { eq("token", token) } }
        Unit
    }

    // ------------------------------------------------------------- realtime ---
    override suspend fun connectRealtime() = realtimeLock.withLock {
        if (channel != null || currentUserId == null) return@withLock
        val ch = client.channel("payvand-" + uid())
        val msgFlow = ch.postgresChangeFlow<PostgresAction>(schema = "public") { table = "messages" }
        val memFlow = ch.postgresChangeFlow<PostgresAction>(schema = "public") { table = "members" }
        val job = SupervisorJob()
        val s = CoroutineScope(scope.coroutineContext + job)
        msgFlow.onEach { a ->
            runCatching {
                when (a) {
                    is PostgresAction.Insert -> _events.emit(RealtimeEvent.MessageInserted(json.decodeFromJsonElement<Message>(a.record)))
                    is PostgresAction.Update -> _events.emit(RealtimeEvent.MessageUpdated(json.decodeFromJsonElement<Message>(a.record)))
                    else -> {}
                }
            }
        }.launchIn(s)
        memFlow.onEach { a ->
            val rec = when (a) {
                is PostgresAction.Insert -> a.record
                is PostgresAction.Update -> a.record
                is PostgresAction.Delete -> a.oldRecord
                else -> null
            }
            val cid = rec?.get("conversation_id")?.let { if (it is JsonNull) null else it.jsonPrimitive.content }
            _events.emit(RealtimeEvent.MembersChanged(cid))
        }.launchIn(s)
        ch.status.onEach { st ->
            when (st) {
                RealtimeChannel.Status.SUBSCRIBED -> {
                    _connection.value = ConnectionState.CONNECTED
                    if (wasConnected) _events.tryEmit(RealtimeEvent.Reconnected)
                    wasConnected = true
                }
                RealtimeChannel.Status.SUBSCRIBING -> _connection.value = ConnectionState.CONNECTING
                else -> _connection.value = ConnectionState.DISCONNECTED
            }
        }.launchIn(s)
        channel = ch
        channelJob = job
        s.launch { runCatching { ch.subscribe() } }
        Unit
    }

    override suspend fun disconnectRealtime() = realtimeLock.withLock {
        val ch = channel ?: return@withLock
        channel = null
        channelJob?.cancel(); channelJob = null
        runCatching { client.realtime.removeChannel(ch) }
        runCatching { client.realtime.disconnect() }
        wasConnected = false
        Unit
    }

    override fun close() {
        scope.launch { runCatching { client.close() }; scope.cancel() }
    }
}
