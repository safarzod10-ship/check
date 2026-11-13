package tj.payvand.app.ui.home

import android.widget.Toast
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.expandVertically
import androidx.compose.animation.shrinkVertically
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.Chat
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Call
import androidx.compose.material.icons.filled.Campaign
import androidx.compose.material.icons.filled.Contacts
import androidx.compose.material.icons.filled.Done
import androidx.compose.material.icons.filled.DoneAll
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material.icons.filled.Groups
import androidx.compose.material.icons.filled.Person
import androidx.compose.material.icons.filled.PersonSearch
import androidx.compose.material.icons.filled.Share
import androidx.compose.material.icons.filled.Videocam
import androidx.compose.material.icons.outlined.ChatBubbleOutline
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.FloatingActionButton
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.NavigationBarItemDefaults
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import tj.payvand.app.ChatSession
import tj.payvand.app.MessageText
import tj.payvand.app.R
import tj.payvand.app.ui.components.Avatar
import tj.payvand.app.ui.components.EmptyState
import tj.payvand.app.ui.components.Fmt
import tj.payvand.app.ui.components.Pill
import tj.payvand.app.ui.components.PrimaryButton
import tj.payvand.app.ui.components.SearchField
import tj.payvand.app.ui.components.SectionLabel
import tj.payvand.app.ui.components.errorMessage
import tj.payvand.app.ui.profile.ProfileTab
import tj.payvand.app.ui.theme.Brand
import tj.payvand.app.ui.theme.pv
import tj.payvand.core.ConnectionState
import tj.payvand.core.ConversationSummary
import tj.payvand.core.ConversationType
import tj.payvand.core.Profile
import tj.payvand.core.PublicConversation
import tj.payvand.core.Time

class HomeNav(
    val openChat: (String) -> Unit,
    val create: (ConversationType) -> Unit,
    val editProfile: () -> Unit,
    val blocked: () -> Unit,
    val changeServer: (() -> Unit)?,
)

private data class Tab(val icon: ImageVector, val label: Int)

@Composable
fun HomeScreen(session: ChatSession, nav: HomeNav) {
    var tab by rememberSaveable { mutableIntStateOf(0) }
    val conversations by session.conversations.collectAsState()
    val unread = conversations.sumOf { it.unreadCount }
    val tabs = listOf(
        Tab(Icons.AutoMirrored.Filled.Chat, R.string.tab_chats), Tab(Icons.Filled.Call, R.string.tab_calls),
        Tab(Icons.Filled.Groups, R.string.tab_communities), Tab(Icons.Filled.Contacts, R.string.tab_contacts), Tab(Icons.Filled.Person, R.string.tab_profile),
    )
    Scaffold(
        containerColor = MaterialTheme.colorScheme.background,
        bottomBar = {
            NavigationBar(containerColor = MaterialTheme.colorScheme.surfaceContainerLow, tonalElevation = 0.dp) {
                tabs.forEachIndexed { i, t ->
                    NavigationBarItem(
                        selected = tab == i, onClick = { tab = i },
                        icon = {
                            Box {
                                Icon(t.icon, null)
                                if (i == 0 && unread > 0) Box(Modifier.align(Alignment.TopEnd).size(9.dp).clip(CircleShape).background(MaterialTheme.colorScheme.primary))
                            }
                        },
                        label = { Text(stringResource(t.label), fontSize = 10.5.sp, maxLines = 1, overflow = TextOverflow.Clip, softWrap = false) },
                        colors = NavigationBarItemDefaults.colors(
                            selectedIconColor = MaterialTheme.colorScheme.primary, selectedTextColor = MaterialTheme.colorScheme.primary,
                            indicatorColor = MaterialTheme.colorScheme.primaryContainer,
                            unselectedIconColor = MaterialTheme.colorScheme.onSurfaceVariant, unselectedTextColor = MaterialTheme.colorScheme.onSurfaceVariant,
                        ),
                    )
                }
            }
        },
    ) { pad ->
        Box(Modifier.fillMaxSize().padding(bottom = pad.calculateBottomPadding()).statusBarsPadding()) {
            when (tab) {
                0 -> ChatsTab(session, conversations, nav)
                1 -> CallsTab()
                2 -> CommunitiesTab(session, conversations, nav)
                3 -> ContactsTab(session, conversations, nav)
                else -> ProfileTab(session, nav)
            }
        }
    }
}

@Composable
fun TabHeader(title: String, actions: @Composable () -> Unit = {}) {
    Row(Modifier.fillMaxWidth().padding(start = 20.dp, end = 8.dp, top = 10.dp, bottom = 6.dp), verticalAlignment = Alignment.CenterVertically) {
        Text(title, style = MaterialTheme.typography.headlineMedium, modifier = Modifier.weight(1f))
        actions()
    }
}

@Composable
fun ConnectionBanner(session: ChatSession) {
    val state by session.api.connection.collectAsState()
    var show by remember { mutableStateOf(false) }
    // короткие переподключения не показываем, чтобы интерфейс не мигал
    LaunchedEffect(state) { if (state == ConnectionState.CONNECTED) show = false else { delay(2500); show = true } }
    AnimatedVisibility(show, enter = expandVertically(), exit = shrinkVertically()) {
        Text(
            stringResource(if (state == ConnectionState.CONNECTING) R.string.connecting else R.string.no_connection),
            Modifier.fillMaxWidth().background(MaterialTheme.colorScheme.tertiary.copy(alpha = 0.18f)).padding(vertical = 6.dp),
            textAlign = TextAlign.Center, style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.tertiary,
        )
    }
}

@Composable
private fun rememberUserSearch(session: ChatSession, query: String): List<Profile> {
    var people by remember { mutableStateOf<List<Profile>>(emptyList()) }
    LaunchedEffect(query) {
        if (query.trim().length < 2) people = emptyList()
        else { delay(350); people = runCatching { session.api.searchUsers(query) }.getOrDefault(emptyList()).also { session.remember(it) } }
    }
    return people
}

@Composable
private fun rememberOpenDirect(session: ChatSession, openChat: (String) -> Unit): (String) -> Unit {
    val scope = rememberCoroutineScope()
    val ctx = LocalContext.current
    return { userId ->
        scope.launch {
            runCatching { session.api.openDirect(userId) }
                .onSuccess { session.refresh(); openChat(it) }
                .onFailure { Toast.makeText(ctx, errorMessage(ctx, it), Toast.LENGTH_SHORT).show() }
        }
    }
}

@Composable
private fun ChatsTab(session: ChatSession, conversations: List<ConversationSummary>, nav: HomeNav) {
    var query by rememberSaveable { mutableStateOf("") }
    var menu by remember { mutableStateOf(false) }
    val loaded by session.loaded.collectAsState()
    val people = rememberUserSearch(session, query)
    val openDirect = rememberOpenDirect(session, nav.openChat)
    val myId = session.api.currentUserId
    val q = query.trim()
    val shown = if (q.isEmpty()) conversations else conversations.filter { it.displayTitle.contains(q, true) || it.peerUsername?.contains(q.removePrefix("@"), true) == true }
    Box(Modifier.fillMaxSize()) {
        Column {
            TabHeader(stringResource(R.string.tab_chats)) {
                Box {
                    IconButton(onClick = { menu = true }) { Icon(Icons.Filled.Add, stringResource(R.string.new_chat)) }
                    NewMenu(menu, { menu = false }, nav)
                }
            }
            SearchField(query, { query = it }, stringResource(R.string.search_people_hint), Modifier.padding(horizontal = 16.dp, vertical = 6.dp))
            ConnectionBanner(session)
            if (loaded && conversations.isEmpty() && q.isEmpty()) {
                EmptyState(Icons.Outlined.ChatBubbleOutline, stringResource(R.string.no_chats_title), stringResource(R.string.no_chats_sub), Modifier.weight(1f))
            } else LazyColumn(Modifier.weight(1f), contentPadding = PaddingValues(bottom = 88.dp)) {
                items(shown, key = { it.id }) { c -> ConversationRow(session, c, myId) { nav.openChat(c.id) } }
                val known = conversations.mapNotNull { it.peerId }.toSet()
                val fresh = people.filter { it.id !in known || q.isNotEmpty() && shown.none { c -> c.peerId == it.id } }
                if (fresh.isNotEmpty()) {
                    item { SectionLabel(stringResource(R.string.people)) }
                    items(fresh, key = { "u" + it.id }) { p -> PersonRow(session, p) { openDirect(p.id) } }
                }
                if (q.length >= 2 && shown.isEmpty() && fresh.isEmpty()) item {
                    Text(stringResource(R.string.nothing_found), Modifier.fillMaxWidth().padding(32.dp), textAlign = TextAlign.Center, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }
        }
        var fabMenu by remember { mutableStateOf(false) }
        Box(Modifier.align(Alignment.BottomEnd).padding(18.dp)) {
            FloatingActionButton(onClick = { fabMenu = true }, containerColor = Brand.Emerald, contentColor = Color(0xFF00210F), shape = CircleShape) {
                Icon(Icons.Filled.Edit, stringResource(R.string.new_chat))
            }
            NewMenu(fabMenu, { fabMenu = false }, nav)
        }
    }
}

@Composable
private fun NewMenu(open: Boolean, close: () -> Unit, nav: HomeNav) {
    DropdownMenu(open, close) {
        DropdownMenuItem(text = { Text(stringResource(R.string.new_group)) }, leadingIcon = { Icon(Icons.Filled.Groups, null) }, onClick = { close(); nav.create(ConversationType.GROUP) })
        DropdownMenuItem(text = { Text(stringResource(R.string.new_channel)) }, leadingIcon = { Icon(Icons.Filled.Campaign, null) }, onClick = { close(); nav.create(ConversationType.CHANNEL) })
    }
}

@Composable
fun ConversationRow(session: ChatSession, c: ConversationSummary, myId: String?, onClick: () -> Unit) {
    val ctx = LocalContext.current
    Row(Modifier.fillMaxWidth().clickable(onClick = onClick).padding(horizontal = 16.dp, vertical = 9.dp), verticalAlignment = Alignment.CenterVertically) {
        Avatar(session.api.avatarUrl(c.displayAvatar), c.displayTitle, 54.dp, online = c.isDirect && Time.isOnline(c.peerLastSeen))
        Spacer(Modifier.width(14.dp))
        Column(Modifier.weight(1f)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                if (c.kind == ConversationType.CHANNEL) { Icon(Icons.Filled.Campaign, null, Modifier.size(16.dp), tint = MaterialTheme.colorScheme.primary); Spacer(Modifier.width(4.dp)) }
                Text(c.displayTitle, style = MaterialTheme.typography.titleMedium, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f))
                Spacer(Modifier.width(8.dp))
                Text(Fmt.listTime(c.lastCreatedAt ?: c.lastMessageAt), style = MaterialTheme.typography.labelMedium,
                    color = if (c.unreadCount > 0) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurfaceVariant)
            }
            Spacer(Modifier.height(3.dp))
            Row(verticalAlignment = Alignment.CenterVertically) {
                val mine = c.lastSenderId != null && c.lastSenderId == myId
                if (mine && c.lastKind != "system" && c.isDirect) {
                    val created = Time.parse(c.lastCreatedAt)
                    val read = created != null && Time.parse(c.peerLastReadAt)?.let { !it.isBefore(created) } == true
                    val delivered = read || created != null && Time.parse(c.peerLastDeliveredAt)?.let { !it.isBefore(created) } == true
                    Icon(if (delivered) Icons.Filled.DoneAll else Icons.Filled.Done, null, Modifier.size(16.dp), tint = if (read) pv.read else MaterialTheme.colorScheme.onSurfaceVariant)
                    Spacer(Modifier.width(4.dp))
                }
                val preview = when {
                    c.lastId == null -> ""
                    c.lastKind == "system" -> MessageText.system(ctx, c.lastBody.orEmpty(), c.lastSenderName.orEmpty())
                    else -> {
                        val body = MessageText.preview(ctx, c.lastKind, c.lastBody, c.lastDeleted == true)
                        if (!c.isDirect && c.kind != ConversationType.CHANNEL) (if (mine) stringResource(R.string.you) else c.lastSenderName.orEmpty()) + ": " + body else body
                    }
                }
                Text(preview, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f))
                if (c.unreadCount > 0) {
                    Spacer(Modifier.width(8.dp))
                    Box(Modifier.clip(RoundedCornerShape(50)).background(MaterialTheme.colorScheme.primary).padding(horizontal = 7.dp, vertical = 2.dp), contentAlignment = Alignment.Center) {
                        Text(if (c.unreadCount > 99) "99+" else c.unreadCount.toString(), color = MaterialTheme.colorScheme.onPrimary, fontSize = 12.sp, fontWeight = FontWeight.Bold)
                    }
                }
            }
        }
    }
}

@Composable
fun PersonRow(session: ChatSession, p: Profile, trailing: @Composable (() -> Unit)? = null, onClick: () -> Unit) {
    Row(Modifier.fillMaxWidth().clickable(onClick = onClick).padding(horizontal = 16.dp, vertical = 8.dp), verticalAlignment = Alignment.CenterVertically) {
        Avatar(session.api.avatarUrl(p.avatarPath), p.displayName.ifBlank { p.username.orEmpty() }, 48.dp, online = Time.isOnline(p.lastSeen))
        Spacer(Modifier.width(14.dp))
        Column(Modifier.weight(1f)) {
            Text(p.displayName.ifBlank { p.username.orEmpty() }, style = MaterialTheme.typography.titleMedium, maxLines = 1, overflow = TextOverflow.Ellipsis)
            Text("@" + p.username.orEmpty() + " · " + p.payvandId, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant, maxLines = 1, overflow = TextOverflow.Ellipsis)
        }
        trailing?.invoke()
    }
}

@Composable
private fun CallsTab() {
    Column(Modifier.fillMaxSize()) {
        TabHeader(stringResource(R.string.tab_calls))
        EmptyState(Icons.Filled.Videocam, stringResource(R.string.calls_title), stringResource(R.string.calls_body), Modifier.weight(1f))
    }
}

@Composable
private fun CommunitiesTab(session: ChatSession, conversations: List<ConversationSummary>, nav: HomeNav) {
    var query by rememberSaveable { mutableStateOf("") }
    var menu by remember { mutableStateOf(false) }
    var public by remember { mutableStateOf<List<PublicConversation>>(emptyList()) }
    val scope = rememberCoroutineScope()
    val ctx = LocalContext.current
    val mine = conversations.filter { !it.isDirect && (query.isBlank() || it.displayTitle.contains(query.trim(), true)) }
    LaunchedEffect(query, conversations.size) {
        delay(300)
        runCatching { session.api.searchPublic(query) }.onSuccess { public = it }
    }
    Column(Modifier.fillMaxSize()) {
        TabHeader(stringResource(R.string.tab_communities)) {
            Box {
                IconButton(onClick = { menu = true }) { Icon(Icons.Filled.Add, stringResource(R.string.create)) }
                NewMenu(menu, { menu = false }, nav)
            }
        }
        SearchField(query, { query = it }, stringResource(R.string.search), Modifier.padding(horizontal = 16.dp, vertical = 6.dp))
        LazyColumn(Modifier.weight(1f), contentPadding = PaddingValues(bottom = 24.dp)) {
            item { SectionLabel(stringResource(R.string.my_communities)) }
            if (mine.isEmpty()) item {
                Text(stringResource(R.string.no_communities), Modifier.padding(horizontal = 20.dp, vertical = 10.dp), color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
            items(mine, key = { it.id }) { c -> ConversationRow(session, c, session.api.currentUserId) { nav.openChat(c.id) } }
            val others = public.filter { !it.joined }
            if (others.isNotEmpty()) {
                item { SectionLabel(stringResource(R.string.public_communities)) }
                items(others, key = { "p" + it.id }) { p ->
                    Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 8.dp), verticalAlignment = Alignment.CenterVertically) {
                        Avatar(session.api.avatarUrl(p.avatarPath), p.title, 50.dp)
                        Spacer(Modifier.width(14.dp))
                        Column(Modifier.weight(1f)) {
                            Row(verticalAlignment = Alignment.CenterVertically) {
                                Text(p.title, style = MaterialTheme.typography.titleMedium, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f, fill = false))
                                Spacer(Modifier.width(6.dp))
                                Pill(stringResource(if (p.type == "channel") R.string.channel else R.string.group))
                            }
                            Text(stringResource(if (p.type == "channel") R.string.subscribers_count else R.string.members_count, p.memberCount) + if (p.description.isNotBlank()) " · " + p.description else "",
                                style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant, maxLines = 1, overflow = TextOverflow.Ellipsis)
                        }
                        OutlinedButton(onClick = {
                            scope.launch {
                                runCatching { session.api.joinPublic(p.id) }
                                    .onSuccess { session.refresh(); nav.openChat(p.id) }
                                    .onFailure { Toast.makeText(ctx, errorMessage(ctx, it), Toast.LENGTH_SHORT).show() }
                            }
                        }) { Text(stringResource(R.string.join)) }
                    }
                }
            }
        }
    }
}

@Composable
private fun ContactsTab(session: ChatSession, conversations: List<ConversationSummary>, nav: HomeNav) {
    var query by rememberSaveable { mutableStateOf("") }
    val people = rememberUserSearch(session, query)
    val openDirect = rememberOpenDirect(session, nav.openChat)
    val me by session.me.collectAsState()
    val ctx = LocalContext.current
    val contacts = conversations.filter { it.isDirect && it.peerId != null }.sortedBy { it.displayTitle.lowercase() }
        .filter { query.isBlank() || it.displayTitle.contains(query.trim(), true) || it.peerUsername?.contains(query.trim().removePrefix("@"), true) == true }
    Column(Modifier.fillMaxSize()) {
        TabHeader(stringResource(R.string.tab_contacts)) {
            IconButton(onClick = {
                val id = me?.let { "@" + it.username + " · " + it.payvandId } ?: return@IconButton
                val i = android.content.Intent(android.content.Intent.ACTION_SEND).setType("text/plain").putExtra(android.content.Intent.EXTRA_TEXT, ctx.getString(R.string.invite_text, id))
                ctx.startActivity(android.content.Intent.createChooser(i, ctx.getString(R.string.share_id)))
            }) { Icon(Icons.Filled.Share, stringResource(R.string.share_id)) }
        }
        SearchField(query, { query = it }, stringResource(R.string.search_people_hint), Modifier.padding(horizontal = 16.dp, vertical = 6.dp))
        if (contacts.isEmpty() && people.isEmpty()) {
            EmptyState(Icons.Filled.PersonSearch, stringResource(if (query.trim().length >= 2) R.string.nothing_found else R.string.contacts_empty), stringResource(R.string.search_people_hint), Modifier.weight(1f))
        } else LazyColumn(Modifier.weight(1f)) {
            items(contacts, key = { it.id }) { c ->
                Row(Modifier.fillMaxWidth().clickable { nav.openChat(c.id) }.padding(horizontal = 16.dp, vertical = 8.dp), verticalAlignment = Alignment.CenterVertically) {
                    Avatar(session.api.avatarUrl(c.peerAvatar), c.displayTitle, 48.dp, online = Time.isOnline(c.peerLastSeen))
                    Spacer(Modifier.width(14.dp))
                    Column(Modifier.weight(1f)) {
                        Text(c.displayTitle, style = MaterialTheme.typography.titleMedium, maxLines = 1, overflow = TextOverflow.Ellipsis)
                        Text(Fmt.lastSeen(ctx, c.peerLastSeen), style = MaterialTheme.typography.bodySmall,
                            color = if (Time.isOnline(c.peerLastSeen)) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                }
            }
            val known = contacts.mapNotNull { it.peerId }.toSet()
            val fresh = people.filter { it.id !in known }
            if (fresh.isNotEmpty()) {
                item { SectionLabel(stringResource(R.string.people)) }
                items(fresh, key = { "u" + it.id }) { p -> PersonRow(session, p) { openDirect(p.id) } }
            }
        }
    }
}
