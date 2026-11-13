package tj.payvand.core

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

/** Адрес сервера и ПУБЛИЧНЫЙ (anon) ключ. Секретный service_role сюда попадать не должен. */
data class BackendConfig(val url: String, val anonKey: String)

/** Хранилище сессии. На Android реализовано через Android Keystore (AES-GCM). */
interface SessionStore {
    suspend fun save(json: String)
    suspend fun load(): String?
    suspend fun clear()
}

@Serializable
data class Profile(
    val id: String,
    @SerialName("payvand_id") val payvandId: String = "",
    val username: String? = null,
    @SerialName("display_name") val displayName: String = "",
    val bio: String = "",
    @SerialName("avatar_path") val avatarPath: String? = null,
    @SerialName("last_seen") val lastSeen: String? = null,
) {
    val isComplete: Boolean get() = !username.isNullOrBlank() && displayName.isNotBlank()
}

enum class ConversationType { DIRECT, GROUP, CHANNEL;
    companion object { fun of(s: String) = when (s) { "group" -> GROUP; "channel" -> CHANNEL; else -> DIRECT } }
    val wire: String get() = name.lowercase()
}

@Serializable
data class ConversationSummary(
    val id: String,
    val type: String,
    val title: String? = null,
    val description: String = "",
    @SerialName("avatar_path") val avatarPath: String? = null,
    @SerialName("is_public") val isPublic: Boolean = false,
    @SerialName("my_role") val myRole: String = "member",
    @SerialName("last_message_at") val lastMessageAt: String? = null,
    @SerialName("unread_count") val unreadCount: Int = 0,
    @SerialName("member_count") val memberCount: Int = 0,
    @SerialName("last_id") val lastId: String? = null,
    @SerialName("last_kind") val lastKind: String? = null,
    @SerialName("last_body") val lastBody: String? = null,
    @SerialName("last_sender_id") val lastSenderId: String? = null,
    @SerialName("last_sender_name") val lastSenderName: String? = null,
    @SerialName("last_created_at") val lastCreatedAt: String? = null,
    @SerialName("last_deleted") val lastDeleted: Boolean? = null,
    @SerialName("peer_id") val peerId: String? = null,
    @SerialName("peer_name") val peerName: String? = null,
    @SerialName("peer_username") val peerUsername: String? = null,
    @SerialName("peer_avatar") val peerAvatar: String? = null,
    @SerialName("peer_last_seen") val peerLastSeen: String? = null,
    @SerialName("peer_last_read_at") val peerLastReadAt: String? = null,
    @SerialName("peer_last_delivered_at") val peerLastDeliveredAt: String? = null,
    val blocked: Boolean = false,
) {
    val kind: ConversationType get() = ConversationType.of(type)
    val isDirect: Boolean get() = kind == ConversationType.DIRECT
    val displayTitle: String get() = if (isDirect) (peerName?.takeIf { it.isNotBlank() } ?: peerUsername ?: "") else (title ?: "")
    val displayAvatar: String? get() = if (isDirect) peerAvatar else avatarPath
    val isAdmin: Boolean get() = myRole == "owner" || myRole == "admin"
    val canPost: Boolean get() = when (kind) {
        ConversationType.CHANNEL -> isAdmin
        ConversationType.DIRECT -> !blocked
        else -> true
    }
}

@Serializable
data class Message(
    val id: String,
    @SerialName("conversation_id") val conversationId: String,
    @SerialName("sender_id") val senderId: String? = null,
    val kind: String = "text",
    val body: String = "",
    @SerialName("media_path") val mediaPath: String? = null,
    @SerialName("media_name") val mediaName: String? = null,
    @SerialName("media_mime") val mediaMime: String? = null,
    @SerialName("media_size") val mediaSize: Long? = null,
    @SerialName("duration_ms") val durationMs: Int? = null,
    @SerialName("reply_to_id") val replyToId: String? = null,
    @SerialName("forwarded_from") val forwardedFrom: String? = null,
    @SerialName("created_at") val createdAt: String = "",
    @SerialName("edited_at") val editedAt: String? = null,
    @SerialName("deleted_at") val deletedAt: String? = null,
) {
    val isDeleted: Boolean get() = deletedAt != null
    val isSystem: Boolean get() = kind == "system"
}

@Serializable
data class Member(
    @SerialName("conversation_id") val conversationId: String,
    @SerialName("user_id") val userId: String,
    val role: String = "member",
    @SerialName("last_read_at") val lastReadAt: String? = null,
    @SerialName("last_delivered_at") val lastDeliveredAt: String? = null,
)

data class MemberProfile(val member: Member, val profile: Profile)

@Serializable
data class PublicConversation(
    val id: String,
    val type: String,
    val title: String = "",
    val description: String = "",
    @SerialName("avatar_path") val avatarPath: String? = null,
    @SerialName("member_count") val memberCount: Int = 0,
    val joined: Boolean = false,
)

/** Вложение, подготовленное клиентом к отправке. */
class OutgoingMedia(
    val kind: String,           // image | video | file | voice
    val bytes: ByteArray,
    val fileName: String,
    val mime: String,
    val durationMs: Int? = null,
)

sealed interface AuthState {
    data object Loading : AuthState
    data object SignedOut : AuthState
    data class SignedIn(val userId: String, val email: String?) : AuthState
}

sealed interface SignUpResult {
    data object NeedsEmailCode : SignUpResult
    data object SignedIn : SignUpResult
}

sealed interface RealtimeEvent {
    data class MessageInserted(val message: Message) : RealtimeEvent
    data class MessageUpdated(val message: Message) : RealtimeEvent
    data class MembersChanged(val conversationId: String?) : RealtimeEvent
    data object Reconnected : RealtimeEvent
}

enum class ConnectionState { CONNECTING, CONNECTED, DISCONNECTED }

/** Ошибка с кодом, который UI переводит на язык пользователя. */
class PayvandException(val code: Code, cause: Throwable? = null) : Exception(code.name + (cause?.message?.let { ": $it" } ?: ""), cause) {
    enum class Code {
        NETWORK, INVALID_CREDENTIALS, EMAIL_NOT_CONFIRMED, USER_EXISTS, WEAK_PASSWORD, INVALID_CODE,
        RATE_LIMIT, FORBIDDEN, USERNAME_TAKEN, INVALID_USERNAME, FILE_TOO_LARGE, BLOCKED, INVALID_EMAIL,
        SERVER_MISCONFIGURED, UNKNOWN
    }
}

object Limits {
    const val MAX_MEDIA_BYTES = 20L * 1024 * 1024
    const val MAX_AVATAR_BYTES = 2L * 1024 * 1024
    const val MAX_MESSAGE_CHARS = 4000
    val USERNAME_REGEX = Regex("^[a-z][a-z0-9_]{3,23}$")
    val PHONE_REGEX = Regex("^\\+[0-9]{7,15}$")
}
