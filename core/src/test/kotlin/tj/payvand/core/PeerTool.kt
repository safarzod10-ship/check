package tj.payvand.core

import kotlinx.coroutines.delay
import kotlinx.coroutines.runBlocking
import java.io.File
import java.net.URI
import java.net.http.HttpClient
import java.net.http.HttpRequest
import java.net.http.HttpResponse
import java.util.UUID
import kotlin.system.exitProcess

/**
 * Инструмент ручного тестирования: «второй пользователь» из командной строки.
 * Работает через тот же [SupabaseApi], что и приложение, — то есть это настоящий второй клиент.
 *
 *   ./gradlew :core:peer --args="signup said@example.com Pass-12345 saidali Саидали"
 *   ./gradlew :core:peer --args="text said@example.com Pass-12345 alisher_tj Салом!"
 */
object PeerTool {
    private val url = System.getenv("PAYVAND_TEST_URL") ?: "http://127.0.0.1:54321"
    private val anon = System.getenv("PAYVAND_TEST_ANON_KEY") ?: error("PAYVAND_TEST_ANON_KEY")
    private val mail = System.getenv("PAYVAND_TEST_MAIL_URL") ?: "http://127.0.0.1:54324"

    private class Mem : SessionStore {
        var v: String? = null
        override suspend fun save(json: String) { v = json }
        override suspend fun load() = v
        override suspend fun clear() { v = null }
    }

    private fun http(u: String) = HttpClient.newBuilder().proxy(HttpClient.Builder.NO_PROXY).build()
        .send(HttpRequest.newBuilder(URI(u)).GET().build(), HttpResponse.BodyHandlers.ofString()).body()

    private suspend fun code(email: String): String {
        repeat(40) {
            val id = Regex("\"ID\":\"([^\"]+)\"").find(http("$mail/api/v1/search?query=to:$email"))?.groupValues?.get(1)
            if (id != null) Regex("(?<![0-9])([0-9]{6})(?![0-9])").find(http("$mail/api/v1/message/$id").substringAfter("\"Text\":"))?.let { return it.groupValues[1] }
            delay(300)
        }
        error("no email")
    }

    @JvmStatic
    fun main(args: Array<String>): Unit = runBlocking {
        val api = SupabaseApi(BackendConfig(url, anon), Mem())
        val cmd = args[0]; val email = args[1]; val password = args[2]
        if (cmd == "signup") {
            api.signUp(email, password); api.confirmSignUp(email, code(email))
            api.updateProfile(args[3], args.drop(4).joinToString(" "), "")
            println("OK " + api.myProfile())
            exitProcess(0)
        }
        api.signIn(email, password)
        suspend fun direct(username: String): String =
            api.openDirect(api.searchUsers("@$username").firstOrNull { it.username == username }?.id ?: error("user $username not found"))
        fun id() = UUID.randomUUID().toString()
        when (cmd) {
            "rename" -> { api.updateProfile(api.myProfile().username!!, args.drop(3).joinToString(" "), ""); println(api.myProfile()) }
            "text" -> println(api.sendText(direct(args[3]), id(), args.drop(4).joinToString(" ")))
            "image" -> { val f = File(args[4]); println(api.sendMedia(direct(args[3]), id(), OutgoingMedia("image", f.readBytes(), f.name, "image/jpeg"), args.drop(5).joinToString(" "))) }
            "voice" -> { val f = File(args[4]); println(api.sendMedia(direct(args[3]), id(), OutgoingMedia("voice", f.readBytes(), f.name, "audio/mp4", args[5].toInt()))) }
            "file" -> { val f = File(args[4]); println(api.sendMedia(direct(args[3]), id(), OutgoingMedia("file", f.readBytes(), f.name, "application/pdf"))) }
            "read" -> { val c = direct(args[3]); api.markRead(c); api.heartbeat(); println(api.messages(c).joinToString("\n") { "${it.createdAt} ${it.senderId?.take(8)} [${it.kind}] ${it.body} ${it.mediaName ?: ""} del=${it.isDeleted} edited=${it.editedAt != null}" }) }
            "delivered" -> { api.markDelivered(); api.heartbeat(); println("ok") }
            "group" -> {
                val ids = args.drop(4).map { u -> api.searchUsers("@$u").first { it.username == u }.id }
                val g = api.createConversation(ConversationType.GROUP, args[3], "", false, ids)
                api.sendText(g, id(), "Привет, друзья! 🇹🇯"); println(g)
            }
            "channel" -> { val g = api.createConversation(ConversationType.CHANNEL, args[3], args.drop(4).joinToString(" "), true, emptyList()); api.sendText(g, id(), "Новые возможности PAYVAND"); println(g) }
            "list" -> api.conversations().forEach { println("${it.id} ${it.type} '${it.displayTitle}' unread=${it.unreadCount} last=[${it.lastKind}] ${it.lastBody} members=${it.memberCount}") }
            "grouptext" -> { val c = api.conversations().first { it.title == args[3] }; println(api.sendText(c.id, id(), args.drop(4).joinToString(" "))) }
            "groupread" -> { val c = api.conversations().first { it.title == args[3] }; println(api.messages(c.id).joinToString("\n") { "${it.senderId?.take(8)} [${it.kind}] ${it.body} ${it.mediaName ?: ""}" }) }
            else -> error("unknown command")
        }
        exitProcess(0)
    }
}
