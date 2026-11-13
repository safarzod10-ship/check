package tj.payvand.app.ui.community

import android.net.Uri
import android.widget.Toast
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ExitToApp
import androidx.compose.material.icons.filled.CameraAlt
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material.icons.filled.Flag
import androidx.compose.material.icons.filled.PersonAdd
import androidx.compose.material.icons.outlined.Circle
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshots.SnapshotStateMap
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import coil3.compose.AsyncImage
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import tj.payvand.app.ChatSession
import tj.payvand.app.R
import tj.payvand.app.data.MediaTools
import tj.payvand.app.ui.components.Avatar
import tj.payvand.app.ui.components.ErrorText
import tj.payvand.app.ui.components.Fmt
import tj.payvand.app.ui.components.Pill
import tj.payvand.app.ui.components.PrimaryButton
import tj.payvand.app.ui.components.PvField
import tj.payvand.app.ui.components.PvTopBar
import tj.payvand.app.ui.components.SearchField
import tj.payvand.app.ui.components.SectionLabel
import tj.payvand.app.ui.components.errorMessage
import tj.payvand.app.ui.home.PersonRow
import tj.payvand.app.ui.profile.ConfirmDialog
import tj.payvand.app.ui.profile.copyText
import tj.payvand.core.ConversationSummary
import tj.payvand.core.ConversationType
import tj.payvand.core.MemberProfile
import tj.payvand.core.Profile
import tj.payvand.core.Time

private fun toast(ctx: android.content.Context, e: Throwable) = Toast.makeText(ctx, errorMessage(ctx, e), Toast.LENGTH_SHORT).show()

/** Выбор людей: собеседники из личных чатов + поиск по имени пользователя / PAYVAND ID. */
@Composable
fun UserPicker(session: ChatSession, selected: SnapshotStateMap<String, Profile>, exclude: Set<String>, modifier: Modifier = Modifier) {
    var query by rememberSaveable { mutableStateOf("") }
    var found by remember { mutableStateOf<List<Profile>>(emptyList()) }
    val conversations by session.conversations.collectAsState()
    LaunchedEffect(query) {
        if (query.trim().length < 2) found = emptyList()
        else { delay(350); found = runCatching { session.api.searchUsers(query) }.getOrDefault(emptyList()) }
    }
    val contacts = conversations.filter { it.isDirect && it.peerId != null && !it.blocked }
        .map { Profile(it.peerId!!, "", it.peerUsername, it.peerName.orEmpty(), "", it.peerAvatar, it.peerLastSeen) }
    val q = query.trim()
    val list = (selected.values + found + contacts.filter { q.isEmpty() || it.displayName.contains(q, true) || it.username?.contains(q.removePrefix("@"), true) == true })
        .distinctBy { it.id }.filter { it.id !in exclude }
    Column(modifier) {
        SearchField(query, { query = it }, stringResource(R.string.search_people_hint), Modifier.padding(horizontal = 16.dp, vertical = 6.dp))
        LazyColumn(Modifier.fillMaxWidth().weight(1f, fill = false)) {
            items(list, key = { it.id }) { p ->
                val on = p.id in selected
                PersonRow(session, p, trailing = {
                    Icon(if (on) Icons.Filled.CheckCircle else Icons.Outlined.Circle, null, tint = if (on) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.outline)
                }) { if (on) selected.remove(p.id) else selected[p.id] = p }
            }
            if (list.isEmpty()) item {
                Text(stringResource(if (q.length >= 2) R.string.nothing_found else R.string.search_people_hint), Modifier.fillMaxWidth().padding(24.dp), textAlign = TextAlign.Center, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
    }
}

@Composable
fun CreateConversationScreen(session: ChatSession, type: ConversationType, onCreated: (String) -> Unit, onBack: () -> Unit) {
    val ctx = LocalContext.current
    val scope = rememberCoroutineScope()
    var title by rememberSaveable { mutableStateOf("") }
    var description by rememberSaveable { mutableStateOf("") }
    var isPublic by rememberSaveable { mutableStateOf(type == ConversationType.CHANNEL) }
    var picked by remember { mutableStateOf<Uri?>(null) }
    var loading by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    val selected = remember { mutableStateMapOf<String, Profile>() }
    val picker = rememberLauncherForActivityResult(ActivityResultContracts.PickVisualMedia()) { if (it != null) picked = it }
    val channel = type == ConversationType.CHANNEL
    Scaffold(topBar = { PvTopBar(stringResource(if (channel) R.string.new_channel else R.string.new_group), onBack) }, containerColor = MaterialTheme.colorScheme.background) { pad ->
        Column(Modifier.padding(pad).fillMaxSize().imePadding()) {
            Row(Modifier.padding(horizontal = 16.dp, vertical = 8.dp), verticalAlignment = Alignment.CenterVertically) {
                Box(Modifier.size(64.dp).clip(CircleShape).background(MaterialTheme.colorScheme.surfaceContainerHigh)
                    .clickable { picker.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly)) }, contentAlignment = Alignment.Center) {
                    if (picked != null) AsyncImage(picked, null, Modifier.fillMaxSize(), contentScale = ContentScale.Crop)
                    else Icon(Icons.Filled.CameraAlt, stringResource(R.string.add_photo), tint = MaterialTheme.colorScheme.primary)
                }
                Spacer(Modifier.width(12.dp))
                PvField(title, { title = it.take(80) }, stringResource(if (channel) R.string.channel_name else R.string.group_name))
            }
            PvField(description, { description = it.take(300) }, stringResource(R.string.description), Modifier.padding(horizontal = 16.dp), singleLine = false)
            Row(Modifier.fillMaxWidth().clickable { isPublic = !isPublic }.padding(horizontal = 20.dp, vertical = 10.dp), verticalAlignment = Alignment.CenterVertically) {
                Column(Modifier.weight(1f)) {
                    Text(stringResource(R.string.make_public), style = MaterialTheme.typography.bodyLarge)
                    Text(stringResource(R.string.make_public_sub), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
                Switch(isPublic, { isPublic = it })
            }
            SectionLabel(stringResource(R.string.add_members) + if (selected.isNotEmpty()) " · ${selected.size}" else "")
            UserPicker(session, selected, setOfNotNull(session.api.currentUserId), Modifier.weight(1f))
            ErrorText(error)
            PrimaryButton(stringResource(R.string.create), {
                loading = true; error = null
                scope.launch {
                    try {
                        val avatar = picked?.let { session.api.uploadAvatar(MediaTools.squareAvatar(ctx, it)) }
                        val id = session.api.createConversation(type, title, description, isPublic, selected.keys.toList(), avatar)
                        session.refresh(); onCreated(id)
                    } catch (e: Exception) { error = errorMessage(ctx, e) } finally { loading = false }
                }
            }, Modifier.padding(horizontal = 20.dp, vertical = 12.dp), enabled = title.isNotBlank(), loading = loading)
        }
    }
}

@Composable
fun ConversationInfoScreen(session: ChatSession, conversationId: String, openChat: (String) -> Unit, onBack: () -> Unit, onLeft: () -> Unit) {
    val conversations by session.conversations.collectAsState()
    val c = conversations.firstOrNull { it.id == conversationId }
    if (c == null) { Scaffold(topBar = { PvTopBar(stringResource(R.string.info), onBack) }) { Box(Modifier.padding(it)) }; return }
    if (c.isDirect) UserInfo(session, c, onBack) else GroupInfo(session, c, openChat, onBack, onLeft)
}

@Composable
private fun ReportDialog(session: ChatSession, userId: String?, conversationId: String?, onDismiss: () -> Unit) {
    val ctx = LocalContext.current
    val scope = rememberCoroutineScope()
    var reason by remember { mutableStateOf("") }
    AlertDialog(onDismissRequest = onDismiss, title = { Text(stringResource(R.string.report)) },
        text = { PvField(reason, { reason = it.take(500) }, stringResource(R.string.report_reason), singleLine = false) },
        confirmButton = { TextButton(enabled = reason.isNotBlank(), onClick = {
            scope.launch {
                runCatching { session.api.report(userId, conversationId, null, reason) }
                    .onSuccess { Toast.makeText(ctx, R.string.report_sent, Toast.LENGTH_SHORT).show(); onDismiss() }.onFailure { toast(ctx, it) }
            }
        }) { Text(stringResource(R.string.send)) } },
        dismissButton = { TextButton(onClick = onDismiss) { Text(stringResource(R.string.cancel)) } })
}

@Composable
private fun UserInfo(session: ChatSession, c: ConversationSummary, onBack: () -> Unit) {
    val ctx = LocalContext.current
    val scope = rememberCoroutineScope()
    var profile by remember { mutableStateOf<Profile?>(null) }
    var blockedByMe by remember { mutableStateOf<Boolean?>(null) }
    var dialog by remember { mutableStateOf<String?>(null) }
    LaunchedEffect(c.peerId) {
        profile = c.peerId?.let { runCatching { session.api.profile(it) }.getOrNull() }
        blockedByMe = runCatching { session.api.blockedUsers().any { it.id == c.peerId } }.getOrNull()
    }
    Scaffold(topBar = { PvTopBar(stringResource(R.string.info), onBack) }, containerColor = MaterialTheme.colorScheme.background) { pad ->
        Column(Modifier.padding(pad).fillMaxSize().padding(20.dp), horizontalAlignment = Alignment.CenterHorizontally) {
            Avatar(session.api.avatarUrl(c.peerAvatar), c.displayTitle, 112.dp, online = Time.isOnline(c.peerLastSeen))
            Spacer(Modifier.height(14.dp))
            Text(c.displayTitle, style = MaterialTheme.typography.headlineSmall)
            Text("@" + c.peerUsername.orEmpty(), color = MaterialTheme.colorScheme.primary)
            Text(Fmt.lastSeen(ctx, profile?.lastSeen ?: c.peerLastSeen), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            profile?.let { p ->
                Spacer(Modifier.height(10.dp))
                TextButton(onClick = { ctx.copyText(p.payvandId) }) { Text("Payvan ID · " + p.payvandId) }
                if (p.bio.isNotBlank()) Text(p.bio, textAlign = TextAlign.Center, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
            Spacer(Modifier.height(24.dp))
            if (blockedByMe != null) OutlinedButton(onClick = { if (blockedByMe == true) scope.launch {
                runCatching { session.api.unblock(c.peerId!!) }.onSuccess { blockedByMe = false; session.refresh() }.onFailure { toast(ctx, it) }
            } else dialog = "block" }, Modifier.fillMaxWidth()) { Text(stringResource(if (blockedByMe == true) R.string.unblock else R.string.block), color = MaterialTheme.colorScheme.error) }
            Spacer(Modifier.height(8.dp))
            OutlinedButton(onClick = { dialog = "report" }, Modifier.fillMaxWidth()) { Icon(Icons.Filled.Flag, null, Modifier.size(18.dp)); Spacer(Modifier.width(8.dp)); Text(stringResource(R.string.report)) }
        }
    }
    when (dialog) {
        "block" -> ConfirmDialog(stringResource(R.string.block_confirm, c.displayTitle), stringResource(R.string.block), danger = true, onConfirm = {
            scope.launch { runCatching { session.api.block(c.peerId!!) }.onSuccess { blockedByMe = true; session.refresh() }.onFailure { toast(ctx, it) } }
        }) { dialog = null }
        "report" -> ReportDialog(session, c.peerId, c.id) { dialog = null }
    }
}

@Composable
private fun GroupInfo(session: ChatSession, c: ConversationSummary, openChat: (String) -> Unit, onBack: () -> Unit, onLeft: () -> Unit) {
    val ctx = LocalContext.current
    val scope = rememberCoroutineScope()
    val myId = session.api.currentUserId
    var members by remember { mutableStateOf<List<MemberProfile>>(emptyList()) }
    var dialog by remember { mutableStateOf<String?>(null) }
    var reload by remember { mutableStateOf(0) }
    LaunchedEffect(c.id, reload, c.memberCount) { runCatching { session.api.members(c.id) }.onSuccess { members = it; session.remember(it.map { m -> m.profile }) } }
    val picker = rememberLauncherForActivityResult(ActivityResultContracts.PickVisualMedia()) { uri ->
        if (uri != null) scope.launch {
            runCatching { session.api.updateConversation(c.id, c.title.orEmpty(), c.description, c.isPublic, session.api.uploadAvatar(MediaTools.squareAvatar(ctx, uri))) }
                .onSuccess { session.refresh() }.onFailure { toast(ctx, it) }
        }
    }
    val channel = c.kind == ConversationType.CHANNEL
    Scaffold(topBar = { PvTopBar(stringResource(R.string.info), onBack) { if (c.isAdmin) IconButton(onClick = { dialog = "edit" }) { Icon(Icons.Filled.Edit, stringResource(R.string.edit)) } } },
        containerColor = MaterialTheme.colorScheme.background) { pad ->
        LazyColumn(Modifier.padding(pad).fillMaxSize()) {
            item {
                Column(Modifier.fillMaxWidth().padding(20.dp), horizontalAlignment = Alignment.CenterHorizontally) {
                    Box(Modifier.clip(CircleShape).clickable(enabled = c.isAdmin) { picker.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly)) }) {
                        Avatar(session.api.avatarUrl(c.avatarPath), c.displayTitle, 104.dp)
                    }
                    Spacer(Modifier.height(12.dp))
                    Text(c.displayTitle, style = MaterialTheme.typography.headlineSmall, textAlign = TextAlign.Center)
                    Spacer(Modifier.height(6.dp))
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Pill(stringResource(if (channel) R.string.channel else R.string.group)); Spacer(Modifier.width(6.dp))
                        Pill(stringResource(if (c.isPublic) R.string.public_ else R.string.private_))
                    }
                    if (c.description.isNotBlank()) { Spacer(Modifier.height(10.dp)); Text(c.description, textAlign = TextAlign.Center, color = MaterialTheme.colorScheme.onSurfaceVariant) }
                }
            }
            item {
                Row(Modifier.fillMaxWidth().padding(end = 12.dp), verticalAlignment = Alignment.CenterVertically) {
                    SectionLabel(stringResource(if (channel) R.string.subscribers_count else R.string.members_count, members.size.coerceAtLeast(c.memberCount)), Modifier.weight(1f))
                    if (c.isAdmin) TextButton(onClick = { dialog = "add" }) { Icon(Icons.Filled.PersonAdd, null, Modifier.size(18.dp)); Spacer(Modifier.width(6.dp)); Text(stringResource(R.string.add_members)) }
                }
            }
            items(members, key = { it.profile.id }) { m ->
                var menu by remember { mutableStateOf(false) }
                val isMe = m.profile.id == myId
                val role = m.member.role
                Box {
                    PersonRow(session, m.profile, trailing = { if (role != "member") Pill(stringResource(if (role == "owner") R.string.owner else R.string.admin)) }) { if (!isMe) menu = true }
                    DropdownMenu(menu, { menu = false }) {
                        DropdownMenuItem(text = { Text(stringResource(R.string.send_message)) }, onClick = {
                            menu = false
                            scope.launch { runCatching { session.api.openDirect(m.profile.id) }.onSuccess { session.refresh(); openChat(it) }.onFailure { toast(ctx, it) } }
                        })
                        if (c.myRole == "owner" && role != "owner") DropdownMenuItem(text = { Text(stringResource(if (role == "admin") R.string.remove_admin else R.string.make_admin)) }, onClick = {
                            menu = false
                            scope.launch { runCatching { session.api.setRole(c.id, m.profile.id, role != "admin") }.onSuccess { reload++ }.onFailure { toast(ctx, it) } }
                        })
                        if (c.myRole == "owner" && role != "owner" || c.myRole == "admin" && role == "member") DropdownMenuItem(text = { Text(stringResource(R.string.remove_from_group), color = MaterialTheme.colorScheme.error) }, onClick = {
                            menu = false
                            scope.launch { runCatching { session.api.removeMember(c.id, m.profile.id) }.onSuccess { reload++; session.refresh() }.onFailure { toast(ctx, it) } }
                        })
                    }
                }
            }
            item {
                Column(Modifier.padding(20.dp)) {
                    OutlinedButton(onClick = { dialog = "leave" }, Modifier.fillMaxWidth()) {
                        Icon(Icons.AutoMirrored.Filled.ExitToApp, null, Modifier.size(18.dp), tint = MaterialTheme.colorScheme.error); Spacer(Modifier.width(8.dp))
                        Text(stringResource(R.string.leave), color = MaterialTheme.colorScheme.error)
                    }
                    Spacer(Modifier.height(8.dp))
                    OutlinedButton(onClick = { dialog = "report" }, Modifier.fillMaxWidth()) { Icon(Icons.Filled.Flag, null, Modifier.size(18.dp)); Spacer(Modifier.width(8.dp)); Text(stringResource(R.string.report)) }
                }
            }
        }
    }
    when (dialog) {
        "leave" -> ConfirmDialog(stringResource(R.string.leave_confirm), stringResource(R.string.leave), danger = true, onConfirm = {
            scope.launch { runCatching { session.api.leave(c.id) }.onSuccess { session.refresh(); onLeft() }.onFailure { toast(ctx, it) } }
        }) { dialog = null }
        "report" -> ReportDialog(session, null, c.id) { dialog = null }
        "edit" -> {
            var title by remember { mutableStateOf(c.title.orEmpty()) }
            var description by remember { mutableStateOf(c.description) }
            var isPublic by remember { mutableStateOf(c.isPublic) }
            AlertDialog(onDismissRequest = { dialog = null }, title = { Text(stringResource(R.string.edit)) },
                text = { Column {
                    PvField(title, { title = it.take(80) }, stringResource(if (channel) R.string.channel_name else R.string.group_name))
                    Spacer(Modifier.height(8.dp))
                    PvField(description, { description = it.take(300) }, stringResource(R.string.description), singleLine = false)
                    Row(verticalAlignment = Alignment.CenterVertically) { Text(stringResource(R.string.make_public), Modifier.weight(1f)); Switch(isPublic, { isPublic = it }) }
                } },
                confirmButton = { TextButton(enabled = title.isNotBlank(), onClick = {
                    scope.launch { runCatching { session.api.updateConversation(c.id, title, description, isPublic, c.avatarPath) }.onSuccess { session.refresh(); dialog = null }.onFailure { toast(ctx, it) } }
                }) { Text(stringResource(R.string.save)) } },
                dismissButton = { TextButton(onClick = { dialog = null }) { Text(stringResource(R.string.cancel)) } })
        }
        "add" -> {
            val selected = remember { mutableStateMapOf<String, Profile>() }
            AlertDialog(onDismissRequest = { dialog = null }, title = { Text(stringResource(R.string.add_members)) },
                text = { UserPicker(session, selected, members.map { it.profile.id }.toSet(), Modifier.heightIn(max = 420.dp)) },
                confirmButton = { TextButton(enabled = selected.isNotEmpty(), onClick = {
                    scope.launch { runCatching { session.api.addMembers(c.id, selected.keys.toList()) }.onSuccess { reload++; session.refresh(); dialog = null }.onFailure { toast(ctx, it) } }
                }) { Text(stringResource(R.string.add_members)) } },
                dismissButton = { TextButton(onClick = { dialog = null }) { Text(stringResource(R.string.cancel)) } })
        }
    }
}
