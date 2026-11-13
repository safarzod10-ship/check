package tj.payvand.app.ui.chat

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import tj.payvand.app.AppContainer
import tj.payvand.app.ChatSession
import tj.payvand.core.DeliveryStatus
import tj.payvand.core.Member
import tj.payvand.core.Message
import tj.payvand.core.OutgoingMedia
import tj.payvand.core.PayvandException
import tj.payvand.core.RealtimeEvent
import tj.payvand.core.Receipts
import tj.payvand.core.Time
import java.time.Instant
import java.util.UUID

data class ChatUi(
    val messages: List<Message> = emptyList(),          // от старых к новым, включая ещё не отправленные
    val pending: Map<String, DeliveryStatus> = emptyMap(), // SENDING / FAILED для локальных сообщений
    val members: List<Member> = emptyList(),
    val loading: Boolean = true,
    val hasMore: Boolean = false,
    val loadingMore: Boolean = false,
    val replyTo: Message? = null,
    val editing: Message? = null,
)

class ChatViewModel(private val session: ChatSession, private val container: AppContainer, val conversationId: String) : ViewModel() {
    private val api = session.api
    val myId: String = api.currentUserId.orEmpty()
    private val _ui = MutableStateFlow(ChatUi())
    val ui: StateFlow<ChatUi> = _ui
    val errors = MutableSharedFlow<Throwable>(extraBufferCapacity = 4)

    private sealed interface Outgoing { val replyTo: String? }
    private data class OutText(val text: String, override val replyTo: String?) : Outgoing
    private class OutMedia(val media: OutgoingMedia, val caption: String, override val replyTo: String?) : Outgoing
    private val outbox = HashMap<String, Outgoing>()
    private var active = false
    private var readJob: Job? = null

    init {
        viewModelScope.launch { reload() }
        viewModelScope.launch {
            api.events.collect { e ->
                when (e) {
                    is RealtimeEvent.MessageInserted -> if (e.message.conversationId == conversationId) {
                        merge(listOf(e.message))
                        if (e.message.senderId != myId) { markRead(); ensureProfile(e.message.senderId) }
                    }
                    is RealtimeEvent.MessageUpdated -> if (e.message.conversationId == conversationId) merge(listOf(e.message))
                    is RealtimeEvent.MembersChanged -> if (e.conversationId == null || e.conversationId == conversationId) loadMembers()
                    RealtimeEvent.Reconnected -> reload()
                }
            }
        }
    }

    private fun sort(list: Collection<Message>): List<Message> =
        list.sortedBy { Time.parse(it.createdAt) ?: Instant.MAX }

    private fun merge(incoming: List<Message>) = _ui.update { s ->
        val map = LinkedHashMap<String, Message>(s.messages.size + incoming.size)
        s.messages.forEach { map[it.id] = it }
        incoming.forEach { map[it.id] = it }
        s.copy(messages = sort(map.values), pending = s.pending - incoming.map { it.id }.toSet())
    }

    private suspend fun reload() {
        runCatching { api.messages(conversationId) }
            .onSuccess { page ->
                merge(page)
                _ui.update { it.copy(loading = false, hasMore = page.size >= 50) }
                page.mapNotNull { it.senderId }.distinct().forEach { ensureProfile(it) }
                markRead()
            }
            .onFailure { _ui.update { s -> s.copy(loading = false) }; if (_ui.value.messages.isEmpty()) errors.tryEmit(it) }
        loadMembers()
    }

    private suspend fun loadMembers() {
        runCatching { api.members(conversationId) }.onSuccess { list ->
            session.remember(list.map { it.profile })
            _ui.update { it.copy(members = list.map { m -> m.member }) }
        }
    }

    private fun ensureProfile(id: String?) {
        if (id == null || session.profiles.value.containsKey(id)) return
        viewModelScope.launch { session.profile(id) }
    }

    fun loadMore() {
        val s = _ui.value
        if (s.loadingMore || !s.hasMore) return
        val oldest = s.messages.firstOrNull { it.id !in s.pending }?.createdAt ?: return
        _ui.update { it.copy(loadingMore = true) }
        viewModelScope.launch {
            runCatching { api.messages(conversationId, before = oldest) }
                .onSuccess { page -> merge(page); _ui.update { it.copy(hasMore = page.size >= 50) }; page.mapNotNull { it.senderId }.distinct().forEach { ensureProfile(it) } }
            _ui.update { it.copy(loadingMore = false) }
        }
    }

    fun setActive(on: Boolean) {
        active = on
        session.openConversationId = if (on) conversationId else null
        if (on) { container.notifier.cancel(conversationId); markRead() }
    }

    private fun markRead() {
        if (!active) return
        readJob?.cancel()
        readJob = viewModelScope.launch {
            delay(250)
            runCatching { api.markRead(conversationId) }.onSuccess { session.refresh() }
        }
    }

    fun statusOf(m: Message): DeliveryStatus = _ui.value.pending[m.id] ?: Receipts.statusOf(m, myId, _ui.value.members)

    fun reply(m: Message?) = _ui.update { it.copy(replyTo = m, editing = null) }
    fun edit(m: Message?) = _ui.update { it.copy(editing = m, replyTo = null) }

    fun submit(text: String) {
        val t = text.trim()
        if (t.isEmpty()) return
        val editing = _ui.value.editing
        if (editing != null) {
            _ui.update { it.copy(editing = null) }
            if (t != editing.body) viewModelScope.launch { runCatching { api.editMessage(editing.id, t) }.onFailure { errors.tryEmit(it) } }
            return
        }
        enqueue(OutText(t, _ui.value.replyTo?.id), "text", t, null)
    }

    fun sendMedia(media: OutgoingMedia, caption: String = "") = enqueue(OutMedia(media, caption, _ui.value.replyTo?.id), media.kind, caption, media)

    private fun enqueue(out: Outgoing, kind: String, body: String, media: OutgoingMedia?) {
        val id = UUID.randomUUID().toString()
        outbox[id] = out
        val local = Message(id, conversationId, myId, kind, body, null, media?.fileName, media?.mime, media?.bytes?.size?.toLong(), media?.durationMs, out.replyTo, null, Instant.now().toString())
        _ui.update { it.copy(messages = it.messages + local, pending = it.pending + (id to DeliveryStatus.SENDING), replyTo = null) }
        deliver(id)
    }

    private fun deliver(id: String) {
        val out = outbox[id] ?: return
        _ui.update { it.copy(pending = it.pending + (id to DeliveryStatus.SENDING)) }
        viewModelScope.launch {
            try {
                val saved = when (out) {
                    is OutText -> api.sendText(conversationId, id, out.text, out.replyTo)
                    is OutMedia -> api.sendMedia(conversationId, id, out.media, out.caption, out.replyTo).also { m ->
                        m.mediaPath?.let { container.mediaCache.put(it, m.mediaName, out.media.bytes) }
                    }
                }
                outbox.remove(id)
                merge(listOf(saved))
                session.refresh()
            } catch (e: PayvandException) {
                _ui.update { it.copy(pending = it.pending + (id to DeliveryStatus.FAILED)) }
                if (e.code != PayvandException.Code.NETWORK) errors.tryEmit(e)
            }
        }
    }

    fun retry(id: String) = deliver(id)

    fun discard(id: String) {
        outbox.remove(id)
        _ui.update { it.copy(messages = it.messages.filter { m -> m.id != id }, pending = it.pending - id) }
    }

    fun delete(m: Message) {
        if (m.id in _ui.value.pending) { discard(m.id); return }
        viewModelScope.launch { runCatching { api.deleteMessage(m.id) }.onSuccess { session.refresh() }.onFailure { errors.tryEmit(it) } }
    }

    fun forward(m: Message, toConversationId: String, onDone: () -> Unit) {
        viewModelScope.launch {
            runCatching { api.forward(m, toConversationId, UUID.randomUUID().toString()) }
                .onSuccess { if (toConversationId == conversationId) merge(listOf(it)); session.refresh(); onDone() }
                .onFailure { errors.tryEmit(it) }
        }
    }

    fun report(m: Message, reason: String, onDone: () -> Unit) {
        viewModelScope.launch {
            runCatching { api.report(m.senderId, conversationId, m.id, reason) }.onSuccess { onDone() }.onFailure { errors.tryEmit(it) }
        }
    }

    override fun onCleared() { if (session.openConversationId == conversationId) session.openConversationId = null }
}
