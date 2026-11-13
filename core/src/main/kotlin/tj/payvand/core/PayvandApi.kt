package tj.payvand.core

import kotlinx.coroutines.flow.SharedFlow
import kotlinx.coroutines.flow.StateFlow

/**
 * Единственная граница между приложением и сервером.
 *
 * UI и ViewModel-и знают только этот интерфейс. Сейчас он реализован через Supabase
 * ([SupabaseApi]); чтобы переехать на собственный сервер, достаточно либо развернуть
 * self-hosted Supabase и сменить URL, либо написать другую реализацию этого интерфейса.
 */
interface PayvandApi {
    // --- сессия ---
    val authState: StateFlow<AuthState>
    val connection: StateFlow<ConnectionState>
    val events: SharedFlow<RealtimeEvent>
    val currentUserId: String?

    suspend fun signUp(email: String, password: String): SignUpResult
    suspend fun confirmSignUp(email: String, code: String)
    suspend fun resendSignUpCode(email: String)
    suspend fun signIn(email: String, password: String)
    suspend fun requestPasswordRecovery(email: String)
    suspend fun confirmPasswordRecovery(email: String, code: String, newPassword: String)
    suspend fun signOut()
    suspend fun deleteAccount()

    // --- профиль ---
    suspend fun myProfile(): Profile
    suspend fun myPhone(): String?
    suspend fun setPhone(phone: String?)
    suspend fun updateProfile(username: String, displayName: String, bio: String)
    suspend fun uploadAvatar(jpeg: ByteArray): String
    suspend fun setMyAvatar(path: String?)
    suspend fun profile(userId: String): Profile?
    suspend fun profiles(userIds: Collection<String>): List<Profile>
    suspend fun searchUsers(query: String): List<Profile>
    suspend fun heartbeat()
    fun avatarUrl(path: String?): String?

    // --- беседы ---
    suspend fun conversations(): List<ConversationSummary>
    suspend fun openDirect(userId: String): String
    suspend fun createConversation(
        type: ConversationType, title: String, description: String, isPublic: Boolean,
        memberIds: List<String>, avatarPath: String? = null,
    ): String
    suspend fun updateConversation(id: String, title: String, description: String, isPublic: Boolean, avatarPath: String?)
    suspend fun members(conversationId: String): List<MemberProfile>
    suspend fun addMembers(conversationId: String, userIds: List<String>): Int
    suspend fun removeMember(conversationId: String, userId: String)
    suspend fun leave(conversationId: String)
    suspend fun setRole(conversationId: String, userId: String, admin: Boolean)
    suspend fun searchPublic(query: String): List<PublicConversation>
    suspend fun joinPublic(conversationId: String)

    // --- сообщения ---
    suspend fun messages(conversationId: String, before: String? = null, limit: Int = 50): List<Message>
    suspend fun sendText(conversationId: String, id: String, text: String, replyTo: String? = null): Message
    suspend fun sendMedia(conversationId: String, id: String, media: OutgoingMedia, caption: String = "", replyTo: String? = null): Message
    suspend fun forward(message: Message, toConversationId: String, id: String): Message
    suspend fun editMessage(messageId: String, text: String)
    suspend fun deleteMessage(messageId: String)
    suspend fun markRead(conversationId: String)
    suspend fun markDelivered()
    suspend fun downloadMedia(path: String): ByteArray

    // --- безопасность ---
    suspend fun block(userId: String)
    suspend fun unblock(userId: String)
    suspend fun blockedUsers(): List<Profile>
    suspend fun report(userId: String?, conversationId: String?, messageId: String?, reason: String)

    // --- push ---
    suspend fun registerPushToken(token: String, lang: String)
    suspend fun unregisterPushToken(token: String)

    /** Запускает/останавливает realtime-подключение (вызывается при входе приложения в foreground/background). */
    suspend fun connectRealtime()
    suspend fun disconnectRealtime()
    fun close()
}
