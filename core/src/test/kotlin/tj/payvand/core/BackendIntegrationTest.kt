package tj.payvand.core

import kotlinx.coroutines.async
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout
import kotlinx.coroutines.withTimeoutOrNull
import org.junit.jupiter.api.Assumptions.assumeTrue
import org.junit.jupiter.api.BeforeAll
import org.junit.jupiter.api.DisplayName
import org.junit.jupiter.api.MethodOrderer
import org.junit.jupiter.api.Order
import org.junit.jupiter.api.TestInstance
import org.junit.jupiter.api.TestMethodOrder
import java.net.URI
import java.net.URLEncoder
import java.net.http.HttpClient
import java.net.http.HttpRequest
import java.net.http.HttpResponse
import java.util.UUID
import kotlin.test.Test
import kotlin.test.assertContentEquals
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

/**
 * Сквозные тесты против НАСТОЯЩЕГО сервера Supabase (локальный стек `supabase start`).
 * Ничего не подменяется: регистрация идёт с кодом из реального письма (почтовый ящик Mailpit),
 * сообщения проходят через Postgres, RLS, Storage и Realtime.
 *
 * Запуск:
 *   PAYVAND_TEST_URL=http://127.0.0.1:54321 PAYVAND_TEST_ANON_KEY=... \
 *   PAYVAND_TEST_MAIL_URL=http://127.0.0.1:54324 ./gradlew :core:test
 * Без этих переменных тесты пропускаются.
 */
@TestInstance(TestInstance.Lifecycle.PER_CLASS)
@TestMethodOrder(MethodOrderer.OrderAnnotation::class)
class BackendIntegrationTest {

    private val url = System.getenv("PAYVAND_TEST_URL")
    private val anon = System.getenv("PAYVAND_TEST_ANON_KEY")
    private val mailUrl = System.getenv("PAYVAND_TEST_MAIL_URL")
    private val http = HttpClient.newBuilder().proxy(HttpClient.Builder.NO_PROXY).build()
    private val run = UUID.randomUUID().toString().take(8)

    class MemStore : SessionStore {
        @Volatile var value: String? = null
        override suspend fun save(json: String) { value = json }
        override suspend fun load(): String? = value
        override suspend fun clear() { value = null }
    }

    class User(val api: SupabaseApi, val store: MemStore, val email: String, val password: String, val username: String) {
        val id: String get() = api.currentUserId!!
    }

    private lateinit var alice: User
    private lateinit var bob: User
    private lateinit var eve: User   // посторонний пользователь для проверки защиты

    private fun newApi(store: MemStore = MemStore()) = SupabaseApi(BackendConfig(url, anon), store)

    private fun get(u: String, headers: Map<String, String> = emptyMap()): HttpResponse<String> {
        val b = HttpRequest.newBuilder(URI(u)).GET()
        headers.forEach { (k, v) -> b.header(k, v) }
        return http.send(b.build(), HttpResponse.BodyHandlers.ofString())
    }

    private fun post(u: String, body: String, headers: Map<String, String>): HttpResponse<String> {
        val b = HttpRequest.newBuilder(URI(u)).POST(HttpRequest.BodyPublishers.ofString(body)).header("Content-Type", "application/json")
        headers.forEach { (k, v) -> b.header(k, v) }
        return http.send(b.build(), HttpResponse.BodyHandlers.ofString())
    }

    /** Достаёт самый свежий 6-значный код из письма, реально отправленного сервером на [email]. */
    private suspend fun codeFromEmail(email: String, skip: Set<String> = emptySet()): String {
        repeat(40) {
            val list = get("$mailUrl/api/v1/search?query=" + URLEncoder.encode("to:$email", "UTF-8")).body()
            val ids = Regex("\"ID\":\"([^\"]+)\"").findAll(list).map { it.groupValues[1] }.toList()
            for (id in ids) {
                val msg = get("$mailUrl/api/v1/message/$id").body()
                val text = Regex("\"Text\":\"(.*?)\",\"", RegexOption.DOT_MATCHES_ALL).find(msg)?.groupValues?.get(1) ?: msg
                val code = Regex("(?<![0-9])([0-9]{6})(?![0-9])").find(text)?.groupValues?.get(1)
                if (code != null && code !in skip) return code
            }
            delay(250)
        }
        error("письмо с кодом для $email не пришло")
    }

    private suspend fun register(name: String): User {
        val email = "$name.$run@example.com"
        val password = "Pv-$run-$name!"
        val store = MemStore()
        val api = newApi(store)
        assertEquals(SignUpResult.NeedsEmailCode, api.signUp(email, password))
        assertNull(api.currentUserId, "до подтверждения почты сессии быть не должно")
        api.confirmSignUp(email, codeFromEmail(email))
        val username = "${name}_$run"
        api.updateProfile(username, name.replaceFirstChar { it.uppercase() }, "")
        return User(api, store, email, password, username)
    }

    @BeforeAll
    fun setUp() = runBlocking {
        assumeTrue(!url.isNullOrBlank() && !anon.isNullOrBlank() && !mailUrl.isNullOrBlank(), "PAYVAND_TEST_* не заданы — пропуск")
        alice = register("alice")
        bob = register("bob")
        eve = register("eve")
    }

    @Test @Order(1)
    @DisplayName("регистрация по коду из письма создаёт профиль с уникальным PAYVAND ID")
    fun t01(): Unit = runBlocking {
        val a = alice.api.myProfile(); val b = bob.api.myProfile()
        assertTrue(Regex("^PV[0-9]{8}$").matches(a.payvandId), a.payvandId)
        assertTrue(a.payvandId != b.payvandId)
        assertEquals(alice.username, a.username)
        assertTrue(a.isComplete)
        assertTrue(alice.api.authState.first { it !is AuthState.Loading } is AuthState.SignedIn)
    }

    @Test @Order(2)
    @DisplayName("неверный код и неверный пароль отклоняются")
    fun t02(): Unit = runBlocking {
        val email = "mallory.$run@example.com"
        val api = newApi()
        api.signUp(email, "Correct-horse-1")
        val e = assertFailsWith<PayvandException> { api.confirmSignUp(email, "000000") }
        assertEquals(PayvandException.Code.INVALID_CODE, e.code)
        val e2 = assertFailsWith<PayvandException> { newApi().signIn(alice.email, "wrong-password") }
        assertEquals(PayvandException.Code.INVALID_CREDENTIALS, e2.code)
        val e3 = assertFailsWith<PayvandException> { newApi().signIn(email, "Correct-horse-1") }
        assertEquals(PayvandException.Code.EMAIL_NOT_CONFIRMED, e3.code)
        val e4 = assertFailsWith<PayvandException> { newApi().signUp(alice.email, "Another-pass-1") }
        assertEquals(PayvandException.Code.USER_EXISTS, e4.code)
    }

    @Test @Order(3)
    @DisplayName("имя пользователя уникально и проверяется")
    fun t03(): Unit = runBlocking {
        val e = assertFailsWith<PayvandException> { eve.api.updateProfile(alice.username, "Eve", "") }
        assertEquals(PayvandException.Code.USERNAME_TAKEN, e.code)
        val e2 = assertFailsWith<PayvandException> { eve.api.updateProfile("1bad name", "Eve", "") }
        assertEquals(PayvandException.Code.INVALID_USERNAME, e2.code)
        assertEquals(eve.username, eve.api.myProfile().username)
    }

    @Test @Order(4)
    @DisplayName("поиск по имени пользователя и PAYVAND ID")
    fun t04(): Unit = runBlocking {
        val byName = alice.api.searchUsers("@" + bob.username)
        assertEquals(listOf(bob.id), byName.map { it.id })
        val byId = alice.api.searchUsers(bob.api.myProfile().payvandId)
        assertEquals(listOf(bob.id), byId.map { it.id })
        assertTrue(alice.api.searchUsers(alice.username).none { it.id == alice.id }, "себя в поиске нет")
    }

    @Test @Order(5)
    @DisplayName("сессия сохраняется а выход и повторный вход работают")
    fun t05(): Unit = runBlocking {
        // «перезапуск приложения»: новый клиент с тем же хранилищем сессии
        val restarted = newApi(bob.store)
        val st = withTimeout(10_000) { restarted.authState.first { it !is AuthState.Loading } }
        assertTrue(st is AuthState.SignedIn && st.userId == bob.id, "сессия должна восстановиться: $st")
        assertEquals(bob.username, restarted.myProfile().username)
        restarted.close()

        val bobId = bob.id
        bob.api.signOut()
        assertNull(bob.store.value, "после выхода сессия стёрта")
        withTimeout(10_000) { bob.api.authState.first { it is AuthState.SignedOut } }   // состояние приходит асинхронно
        bob.api.signIn(bob.email, bob.password)
        assertEquals(bobId, bob.id)
        assertNotNull(bob.store.value)
        withTimeout(10_000) { bob.api.authState.first { it is AuthState.SignedIn } }
    }

    @Test @Order(6)
    @DisplayName("два пользователя переписываются в реальном времени со статусами доставки и прочтения")
    fun t06(): Unit = runBlocking {
        alice.api.connectRealtime(); bob.api.connectRealtime()
        withTimeout(15_000) { bob.api.connection.first { it == ConnectionState.CONNECTED } }
        withTimeout(15_000) { alice.api.connection.first { it == ConnectionState.CONNECTED } }
        delay(2500) // сервер Realtime подключается к репликации Postgres

        val conv = alice.api.openDirect(bob.id)
        assertEquals(conv, bob.api.openDirect(alice.id), "личный чат один на двоих")

        val incoming = async {
            withTimeoutOrNull(10_000) {
                bob.api.events.first { it is RealtimeEvent.MessageInserted && it.message.conversationId == conv }
            } as RealtimeEvent.MessageInserted?
        }
        delay(200)
        val sent = alice.api.sendText(conv, UUID.randomUUID().toString(), "Салом, Боб! Чӣ хел ҳастӣ? ӣ ӯ қ ғ ҳ ҷ")
        val got = incoming.await()
        assertNotNull(got, "Боб должен получить сообщение через Realtime")
        assertEquals("Салом, Боб! Чӣ хел ҳастӣ? ӣ ӯ қ ғ ҳ ҷ", got.message.body, "таджикская кириллица не искажается")
        assertEquals(alice.id, got.message.senderId)

        // у Боба: один непрочитанный
        val bobList = bob.api.conversations().first { it.id == conv }
        assertEquals(1, bobList.unreadCount)
        assertEquals("Alice", bobList.displayTitle)
        assertEquals(sent.id, bobList.lastId)

        // статус у Алисы: SENT -> DELIVERED -> READ
        suspend fun status() = Receipts.statusOf(sent, alice.id, alice.api.members(conv).map { it.member })
        assertEquals(DeliveryStatus.SENT, status())
        bob.api.markDelivered()
        assertEquals(DeliveryStatus.DELIVERED, status())
        bob.api.markRead(conv)
        assertEquals(DeliveryStatus.READ, status())
        assertEquals(0, bob.api.conversations().first { it.id == conv }.unreadCount)

        // ответ с цитатой
        val reply = bob.api.sendText(conv, UUID.randomUUID().toString(), "Хорошо, брат!", replyTo = sent.id)
        assertEquals(sent.id, reply.replyToId)
        val history = alice.api.messages(conv)
        assertEquals(listOf(reply.id, sent.id), history.map { it.id }, "история хранится в базе, новые сверху")

        // повтор отправки с тем же id (обрыв сети) не создаёт дубликат
        val again = bob.api.sendText(conv, reply.id, "Хорошо, брат!", replyTo = sent.id)
        assertEquals(reply.id, again.id)
        assertEquals(2, alice.api.messages(conv).size)
    }

    @Test @Order(7)
    @DisplayName("редактирование и удаление только своих сообщений")
    fun t07(): Unit = runBlocking {
        val conv = alice.api.openDirect(bob.id)
        val m = alice.api.sendText(conv, UUID.randomUUID().toString(), "с ошибкай")
        val updated = async {
            withTimeoutOrNull(10_000) { bob.api.events.first { it is RealtimeEvent.MessageUpdated && it.message.id == m.id } }
        }
        delay(200)
        alice.api.editMessage(m.id, "без ошибки")
        assertNotNull(updated.await(), "правка приходит собеседнику в реальном времени")
        val after = bob.api.messages(conv).first { it.id == m.id }
        assertEquals("без ошибки", after.body); assertNotNull(after.editedAt)

        assertEquals(PayvandException.Code.FORBIDDEN, assertFailsWith<PayvandException> { bob.api.editMessage(m.id, "взлом") }.code)
        assertEquals(PayvandException.Code.FORBIDDEN, assertFailsWith<PayvandException> { bob.api.deleteMessage(m.id) }.code)
        alice.api.deleteMessage(m.id)
        val deleted = bob.api.messages(conv).first { it.id == m.id }
        assertTrue(deleted.isDeleted); assertEquals("", deleted.body, "текст удалённого сообщения стирается на сервере")
    }

    @Test @Order(8)
    @DisplayName("фото и документы доходят собеседнику и недоступны посторонним")
    fun t08(): Unit = runBlocking {
        val conv = alice.api.openDirect(bob.id)
        val bytes = ByteArray(40_000) { (it * 31 % 251).toByte() }
        val photo = alice.api.sendMedia(conv, UUID.randomUUID().toString(), OutgoingMedia("image", bytes, "душанбе.jpg", "image/jpeg"), caption = "Душанбе")
        assertEquals("image", photo.kind); assertNotNull(photo.mediaPath)
        assertContentEquals(bytes, bob.api.downloadMedia(photo.mediaPath!!), "Боб скачивает ровно то, что отправила Алиса")

        val voice = bob.api.sendMedia(conv, UUID.randomUUID().toString(), OutgoingMedia("voice", ByteArray(5000) { 7 }, "voice.m4a", "audio/mp4", durationMs = 12000))
        assertEquals(12000, voice.durationMs)
        assertEquals(5000, alice.api.downloadMedia(voice.mediaPath!!).size)

        // посторонний: ни сообщений, ни файла, ни записи в чужой чат, ни загрузки в чужую папку
        assertTrue(eve.api.messages(conv).isEmpty(), "RLS: чужая переписка не видна")
        assertFailsWith<PayvandException> { eve.api.downloadMedia(photo.mediaPath!!) }
        assertEquals(PayvandException.Code.FORBIDDEN, assertFailsWith<PayvandException> { eve.api.sendText(conv, UUID.randomUUID().toString(), "я посторонний") }.code)
        assertFailsWith<PayvandException> { eve.api.sendMedia(conv, UUID.randomUUID().toString(), OutgoingMedia("image", bytes, "x.jpg", "image/jpeg")) }
        assertTrue(eve.api.members(conv).isEmpty())

        // пересылка с файлом в другой чат
        val conv2 = bob.api.openDirect(eve.id)
        val fwd = bob.api.forward(photo, conv2, UUID.randomUUID().toString())
        assertEquals(alice.id, fwd.forwardedFrom)
        assertContentEquals(bytes, eve.api.downloadMedia(fwd.mediaPath!!))

        // удаление сообщения удаляет и файл
        alice.api.deleteMessage(photo.id)
        assertFailsWith<PayvandException> { bob.api.downloadMedia(photo.mediaPath!!) }

        val tooBig = assertFailsWith<PayvandException> {
            alice.api.sendMedia(conv, UUID.randomUUID().toString(), OutgoingMedia("file", ByteArray(21 * 1024 * 1024), "big.bin", "application/octet-stream"))
        }
        assertEquals(PayvandException.Code.FILE_TOO_LARGE, tooBig.code)
    }

    @Test @Order(9)
    @DisplayName("аватар загружается и доступен по публичной ссылке")
    fun t09(): Unit = runBlocking {
        val jpeg = byteArrayOf(0xFF.toByte(), 0xD8.toByte(), 0xFF.toByte(), 0xE0.toByte()) + ByteArray(600) { 1 }
        val path = alice.api.uploadAvatar(jpeg)
        alice.api.setMyAvatar(path)
        assertEquals(path, bob.api.profile(alice.id)!!.avatarPath)
        val res = http.send(HttpRequest.newBuilder(URI(alice.api.avatarUrl(path)!!)).GET().build(), HttpResponse.BodyHandlers.ofByteArray())
        assertEquals(200, res.statusCode()); assertContentEquals(jpeg, res.body())
    }

    @Test @Order(10)
    @DisplayName("группа - участники администраторы и права")
    fun t10(): Unit = runBlocking {
        val g = alice.api.createConversation(ConversationType.GROUP, "Друзья из Душанбе", "тест", false, listOf(bob.id))
        val summary = bob.api.conversations().first { it.id == g }
        assertEquals("Друзья из Душанбе", summary.displayTitle); assertEquals(2, summary.memberCount); assertEquals("member", summary.myRole)
        assertEquals("owner", alice.api.conversations().first { it.id == g }.myRole)

        bob.api.sendText(g, UUID.randomUUID().toString(), "Привет, друзья!")
        // обычный участник не может добавлять людей, менять группу и назначать админов
        assertEquals(PayvandException.Code.FORBIDDEN, assertFailsWith<PayvandException> { bob.api.addMembers(g, listOf(eve.id)) }.code)
        assertEquals(PayvandException.Code.FORBIDDEN, assertFailsWith<PayvandException> { bob.api.updateConversation(g, "Взлом", "", true, null) }.code)
        assertEquals(PayvandException.Code.FORBIDDEN, assertFailsWith<PayvandException> { bob.api.setRole(g, bob.id, true) }.code)
        // посторонний не видит закрытую группу
        assertTrue(eve.api.messages(g).isEmpty())
        assertEquals(PayvandException.Code.FORBIDDEN, assertFailsWith<PayvandException> { eve.api.joinPublic(g) }.code)

        alice.api.setRole(g, bob.id, admin = true)
        assertEquals(1, bob.api.addMembers(g, listOf(eve.id)))
        assertEquals(3, alice.api.members(g).size)
        assertTrue(eve.api.messages(g).any { it.body == "Привет, друзья!" }, "новый участник видит историю")
        // админ может удалить чужое сообщение, но не может исключить владельца
        val spam = eve.api.sendText(g, UUID.randomUUID().toString(), "спам")
        bob.api.deleteMessage(spam.id)
        assertEquals(PayvandException.Code.FORBIDDEN, assertFailsWith<PayvandException> { bob.api.removeMember(g, alice.id) }.code)
        bob.api.removeMember(g, eve.id)
        assertTrue(eve.api.conversations().none { it.id == g })
        assertTrue(eve.api.messages(g).isEmpty(), "исключённый теряет доступ")

        alice.api.updateConversation(g, "Друзья", "новое описание", false, null)
        assertEquals("Друзья", bob.api.conversations().first { it.id == g }.title)
        // владелец выходит — права переходят администратору
        alice.api.leave(g)
        assertEquals("owner", bob.api.conversations().first { it.id == g }.myRole)
    }

    @Test @Order(11)
    @DisplayName("публичный канал - поиск вступление и запрет писать подписчикам")
    fun t11(): Unit = runBlocking {
        val title = "IT Душанбе $run"
        val ch = alice.api.createConversation(ConversationType.CHANNEL, title, "Новости", true, emptyList())
        alice.api.sendText(ch, UUID.randomUUID().toString(), "Новые возможности")
        val found = bob.api.searchPublic("душанбе $run")
        assertEquals(listOf(ch), found.map { it.id }); assertEquals(false, found[0].joined); assertEquals(1, found[0].memberCount)
        bob.api.joinPublic(ch)
        assertTrue(bob.api.searchPublic(run).first { it.id == ch }.joined)
        assertTrue(bob.api.messages(ch).any { it.body == "Новые возможности" })
        assertEquals(false, bob.api.conversations().first { it.id == ch }.canPost)
        assertEquals(PayvandException.Code.FORBIDDEN, assertFailsWith<PayvandException> { bob.api.sendText(ch, UUID.randomUUID().toString(), "я подписчик") }.code)
        bob.api.leave(ch)
        assertTrue(bob.api.conversations().none { it.id == ch })
    }

    @Test @Order(12)
    @DisplayName("блокировка запрещает личные сообщения а жалоба сохраняется")
    fun t12(): Unit = runBlocking {
        val conv = bob.api.openDirect(eve.id)
        eve.api.sendText(conv, UUID.randomUUID().toString(), "привет")
        bob.api.block(eve.id)
        assertEquals(listOf(eve.id), bob.api.blockedUsers().map { it.id })
        assertEquals(PayvandException.Code.FORBIDDEN, assertFailsWith<PayvandException> { eve.api.sendText(conv, UUID.randomUUID().toString(), "ответь!") }.code)
        assertTrue(bob.api.conversations().first { it.id == conv }.blocked)
        assertTrue(eve.api.searchUsers(bob.username).isEmpty(), "заблокировавший не находится в поиске")
        bob.api.report(eve.id, conv, null, "спам")
        bob.api.unblock(eve.id)
        eve.api.sendText(conv, UUID.randomUUID().toString(), "спасибо")
        Unit
    }

    @Test @Order(13)
    @DisplayName("защита от поддельных запросов - прямые обращения к REST API")
    fun t13(): Unit = runBlocking {
        val conv = alice.api.openDirect(bob.id)
        val anonHeaders = mapOf("apikey" to anon, "Authorization" to "Bearer $anon")
        // без входа (только публичный ключ из APK) данные недоступны
        for (t in listOf("profiles", "messages", "conversations", "members", "profile_private", "device_tokens")) {
            val r = get("$url/rest/v1/$t?select=*", anonHeaders)
            assertTrue(r.statusCode() in listOf(401, 403) || r.body().trim() == "[]", "anon не должен читать $t: ${r.statusCode()} ${r.body().take(120)}")
        }
        assertTrue(post("$url/rest/v1/rpc/my_conversations", "{}", anonHeaders).statusCode() in listOf(401, 403, 404))

        // Ева со своим настоящим токеном пытается: писать от имени Алисы, вписать себя в чат, править чужое
        val token = Regex("\"access_token\":\"([^\"]+)\"").find(eve.store.value!!)!!.groupValues[1]
        val h = mapOf("apikey" to anon, "Authorization" to "Bearer $token", "Prefer" to "return=representation")
        val spoof = post("$url/rest/v1/messages", """{"conversation_id":"$conv","sender_id":"${alice.id}","body":"подделка"}""", h)
        assertTrue(spoof.statusCode() in listOf(401, 403), "подмена отправителя: ${spoof.statusCode()} ${spoof.body()}")
        val joinSelf = post("$url/rest/v1/members", """{"conversation_id":"$conv","user_id":"${eve.id}"}""", h)
        assertTrue(joinSelf.statusCode() in listOf(401, 403), "самовольное вступление: ${joinSelf.statusCode()}")
        val sys = post("$url/rest/v1/messages", """{"conversation_id":"${eve.api.openDirect(bob.id)}","sender_id":"${eve.id}","kind":"system","body":"created"}""", h)
        assertTrue(sys.statusCode() in listOf(401, 403), "системные сообщения только с сервера: ${sys.statusCode()}")
        val patch = http.send(HttpRequest.newBuilder(URI("$url/rest/v1/profiles?id=eq.${alice.id}"))
            .method("PATCH", HttpRequest.BodyPublishers.ofString("""{"display_name":"hacked"}"""))
            .header("Content-Type", "application/json").apply { h.forEach { (k, v) -> header(k, v) } }.build(), HttpResponse.BodyHandlers.ofString())
        assertTrue(patch.body().trim() == "[]" || patch.statusCode() in listOf(401, 403), "чужой профиль: ${patch.body()}")
        assertEquals("Alice", bob.api.profile(alice.id)!!.displayName)
        // PAYVAND ID нельзя поменять даже себе
        val before = eve.api.myProfile().payvandId
        http.send(HttpRequest.newBuilder(URI("$url/rest/v1/profiles?id=eq.${eve.id}"))
            .method("PATCH", HttpRequest.BodyPublishers.ofString("""{"payvand_id":"PV00000001"}"""))
            .header("Content-Type", "application/json").apply { h.forEach { (k, v) -> header(k, v) } }.build(), HttpResponse.BodyHandlers.ofString())
        assertEquals(before, eve.api.myProfile().payvandId)
        // телефон виден только владельцу
        alice.api.setPhone("+992900000001")
        assertEquals("+992900000001", alice.api.myPhone())
        assertEquals("[]", get("$url/rest/v1/profile_private?select=*&user_id=eq.${alice.id}", h).body().trim())
    }

    @Test @Order(14)
    @DisplayName("восстановление доступа по коду из письма")
    fun t14(): Unit = runBlocking {
        val seen = setOf(codeFromEmail(eve.email))
        val fresh = newApi()
        fresh.requestPasswordRecovery(eve.email)
        val newPassword = "New-$run-pass!"
        fresh.confirmPasswordRecovery(eve.email, codeFromEmail(eve.email, skip = seen), newPassword)
        assertEquals(eve.id, fresh.currentUserId)
        fresh.signOut()
        assertEquals(PayvandException.Code.INVALID_CREDENTIALS, assertFailsWith<PayvandException> { newApi().signIn(eve.email, eve.password) }.code)
        val again = newApi(); again.signIn(eve.email, newPassword)
        assertEquals(eve.id, again.currentUserId)
    }

    @Test @Order(15)
    @DisplayName("ограничение частоты отправки сообщений")
    fun t15(): Unit = runBlocking {
        delay(10_500)
        val conv = alice.api.openDirect(bob.id)
        var limited: PayvandException? = null
        var ok = 0
        for (i in 1..30) {
            try { alice.api.sendText(conv, UUID.randomUUID().toString(), "флуд $i"); ok++ }
            catch (e: PayvandException) { limited = e; break }
        }
        assertEquals(PayvandException.Code.RATE_LIMIT, limited?.code, "после $ok сообщений подряд сервер должен ограничить отправку")
        assertEquals(20, ok)
    }

    @Test @Order(16)
    @DisplayName("сервер недоступен - ошибка сети а не падение")
    fun t16(): Unit = runBlocking {
        val offline = SupabaseApi(BackendConfig("http://127.0.0.1:9", anon), MemStore())
        val e = assertFailsWith<PayvandException> { offline.signIn("a@b.co", "password1") }
        assertEquals(PayvandException.Code.NETWORK, e.code)
    }

    @Test @Order(17)
    @DisplayName("удаление аккаунта")
    fun t17(): Unit = runBlocking {
        val tmp = register("temp")
        val id = tmp.id
        tmp.api.deleteAccount()
        assertNull(alice.api.profile(id))
        assertFailsWith<PayvandException> { newApi().signIn(tmp.email, tmp.password) }
        Unit
    }
}
