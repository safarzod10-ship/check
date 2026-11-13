package tj.payvand.app.ui.chat

import android.Manifest
import android.content.pm.PackageManager
import android.widget.Toast
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.Forward
import androidx.compose.material.icons.automirrored.filled.InsertDriveFile
import androidx.compose.material.icons.automirrored.filled.Reply
import androidx.compose.material.icons.automirrored.filled.Send
import androidx.compose.material.icons.filled.AccessTime
import androidx.compose.material.icons.filled.AttachFile
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.ContentCopy
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Done
import androidx.compose.material.icons.filled.DoneAll
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material.icons.filled.ErrorOutline
import androidx.compose.material.icons.filled.Flag
import androidx.compose.material.icons.filled.Image
import androidx.compose.material.icons.filled.Mic
import androidx.compose.material.icons.filled.Pause
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.PlayCircle
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.derivedStateOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import androidx.core.content.ContextCompat
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LifecycleEventEffect
import coil3.compose.AsyncImage
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import tj.payvand.app.AppContainer
import tj.payvand.app.ChatSession
import tj.payvand.app.MessageText
import tj.payvand.app.R
import tj.payvand.app.data.MediaTools
import tj.payvand.app.data.VoiceRecorder
import tj.payvand.app.ui.components.Avatar
import tj.payvand.app.ui.components.Fmt
import tj.payvand.app.ui.components.PvField
import tj.payvand.app.ui.components.errorMessage
import tj.payvand.app.ui.home.ConnectionBanner
import tj.payvand.app.ui.profile.ConfirmDialog
import tj.payvand.app.ui.profile.copyText
import tj.payvand.app.ui.theme.Brand
import tj.payvand.app.ui.theme.pv
import tj.payvand.core.ConversationSummary
import tj.payvand.core.ConversationType
import tj.payvand.core.DeliveryStatus
import tj.payvand.core.Message
import tj.payvand.core.PayvandException
import tj.payvand.core.Profile
import tj.payvand.core.Time
import java.io.File

@Composable
fun ChatScreen(session: ChatSession, container: AppContainer, vm: ChatViewModel, onBack: () -> Unit, onInfo: () -> Unit) {
    val ui by vm.ui.collectAsState()
    val conversations by session.conversations.collectAsState()
    val profiles by session.profiles.collectAsState()
    val conv = conversations.firstOrNull { it.id == vm.conversationId }
    val ctx = LocalContext.current
    val listState = rememberLazyListState()
    var actionsFor by remember { mutableStateOf<Message?>(null) }
    var forwardMsg by remember { mutableStateOf<Message?>(null) }
    var deleteMsg by remember { mutableStateOf<Message?>(null) }
    var reportMsg by remember { mutableStateOf<Message?>(null) }
    var viewer by remember { mutableStateOf<File?>(null) }

    LifecycleEventEffect(Lifecycle.Event.ON_RESUME) { vm.setActive(true) }
    LifecycleEventEffect(Lifecycle.Event.ON_PAUSE) { vm.setActive(false) }
    DisposableEffect(Unit) { onDispose { vm.setActive(false); container.voicePlayer.stop() } }
    LaunchedEffect(Unit) { vm.errors.collect { Toast.makeText(ctx, errorMessage(ctx, it), Toast.LENGTH_SHORT).show() } }

    val reversed = remember(ui.messages) { ui.messages.asReversed() }
    val byId = remember(ui.messages) { ui.messages.associateBy { it.id } }
    // новое сообщение: прокручиваем вниз, если пользователь и так внизу или сообщение его собственное
    val newest = reversed.firstOrNull()
    LaunchedEffect(newest?.id) {
        if (newest != null && (listState.firstVisibleItemIndex <= 2 || newest.senderId == vm.myId)) listState.animateScrollToItem(0)
    }
    val nearTop by remember { derivedStateOf { (listState.layoutInfo.visibleItemsInfo.lastOrNull()?.index ?: 0) >= listState.layoutInfo.totalItemsCount - 6 } }
    LaunchedEffect(nearTop, ui.messages.size) { if (nearTop && ui.hasMore) vm.loadMore() }

    Column(Modifier.fillMaxSize().background(pv.chatBackground).imePadding()) {
        ChatTopBar(session, conv, onBack, onInfo)
        ConnectionBanner(session)
        Box(Modifier.weight(1f).fillMaxWidth()) {
            if (ui.loading && ui.messages.isEmpty()) CircularProgressIndicator(Modifier.align(Alignment.Center))
            LazyColumn(Modifier.fillMaxSize(), state = listState, reverseLayout = true, contentPadding = PaddingValues(horizontal = 10.dp, vertical = 8.dp)) {
                items(reversed.size, key = { reversed[it].id }) { i ->
                    val m = reversed[i]
                    val older = reversed.getOrNull(i + 1)
                    val day = Fmt.day(m.createdAt)
                    Column {
                        if (day != null && day != Fmt.day(older?.createdAt)) DayChip(Fmt.dayLabel(ctx, day))
                        if (m.isSystem) SystemChip(MessageText.system(ctx, m.body, profiles[m.senderId]?.displayName.orEmpty()))
                        else MessageBubble(
                            m = m, mine = m.senderId == vm.myId, status = if (m.senderId == vm.myId) vm.statusOf(m) else null,
                            showSender = conv?.kind == ConversationType.GROUP && m.senderId != vm.myId && older?.senderId != m.senderId,
                            sender = profiles[m.senderId], forwardedFrom = m.forwardedFrom?.let { profiles[it] },
                            replied = m.replyToId?.let { byId[it] }, repliedSender = m.replyToId?.let { byId[it]?.senderId }?.let { profiles[it] },
                            session = session, container = container,
                            onLongPress = { actionsFor = m }, onRetry = { vm.retry(m.id) }, onOpenImage = { viewer = it },
                        )
                    }
                }
                if (ui.loadingMore) item { Box(Modifier.fillMaxWidth().padding(8.dp), contentAlignment = Alignment.Center) { CircularProgressIndicator(Modifier.size(22.dp), strokeWidth = 2.dp) } }
            }
        }
        when {
            conv == null -> Spacer(Modifier.navigationBarsPadding())
            conv.canPost -> Composer(vm, ui, profiles, container)
            else -> Text(
                stringResource(if (conv.kind == ConversationType.CHANNEL) R.string.channel_readonly else R.string.blocked_banner),
                Modifier.fillMaxWidth().background(MaterialTheme.colorScheme.surfaceContainerLow).navigationBarsPadding().padding(16.dp),
                textAlign = TextAlign.Center, color = MaterialTheme.colorScheme.onSurfaceVariant, style = MaterialTheme.typography.bodyMedium,
            )
        }
    }

    actionsFor?.let { m ->
        MessageActions(
            m, mine = m.senderId == vm.myId, pending = m.id in ui.pending, canPost = conv?.canPost == true,
            canDelete = m.senderId == vm.myId || (conv?.isAdmin == true && conv.isDirect.not()),
            onDismiss = { actionsFor = null },
            onReply = { vm.reply(m) }, onForward = { forwardMsg = m }, onCopy = { ctx.copyText(m.body) },
            onEdit = { vm.edit(m) }, onDelete = { deleteMsg = m }, onReport = { reportMsg = m },
        )
    }
    deleteMsg?.let { m ->
        ConfirmDialog(stringResource(R.string.delete_confirm), stringResource(R.string.delete), danger = true, onConfirm = { vm.delete(m) }) { deleteMsg = null }
    }
    forwardMsg?.let { m ->
        ForwardDialog(session, conversations.filter { it.canPost }, onDismiss = { forwardMsg = null }) { target ->
            forwardMsg = null
            vm.forward(m, target) { Toast.makeText(ctx, R.string.forward, Toast.LENGTH_SHORT).show() }
        }
    }
    reportMsg?.let { m ->
        var reason by remember { mutableStateOf("") }
        AlertDialog(onDismissRequest = { reportMsg = null }, title = { Text(stringResource(R.string.report)) },
            text = { PvField(reason, { reason = it.take(500) }, stringResource(R.string.report_reason), singleLine = false) },
            confirmButton = { TextButton(enabled = reason.isNotBlank(), onClick = { vm.report(m, reason) { Toast.makeText(ctx, R.string.report_sent, Toast.LENGTH_SHORT).show() }; reportMsg = null }) { Text(stringResource(R.string.send)) } },
            dismissButton = { TextButton(onClick = { reportMsg = null }) { Text(stringResource(R.string.cancel)) } })
    }
    viewer?.let { f ->
        Dialog(onDismissRequest = { viewer = null }, properties = DialogProperties(usePlatformDefaultWidth = false)) {
            Box(Modifier.fillMaxSize().background(Color.Black).clickable { viewer = null }) {
                AsyncImage(f, null, Modifier.fillMaxSize(), contentScale = ContentScale.Fit)
                IconButton(onClick = { viewer = null }, Modifier.statusBarsPadding().padding(8.dp)) { Icon(Icons.Filled.Close, stringResource(R.string.close), tint = Color.White) }
            }
        }
    }
}

@Composable
private fun ChatTopBar(session: ChatSession, conv: ConversationSummary?, onBack: () -> Unit, onInfo: () -> Unit) {
    val ctx = LocalContext.current
    Surface(color = MaterialTheme.colorScheme.surfaceContainerLow) {
        Row(Modifier.fillMaxWidth().statusBarsPadding().height(60.dp), verticalAlignment = Alignment.CenterVertically) {
            IconButton(onClick = onBack) { Icon(Icons.AutoMirrored.Filled.ArrowBack, stringResource(R.string.back)) }
            Row(Modifier.weight(1f).clip(RoundedCornerShape(14.dp)).clickable(enabled = conv != null, onClick = onInfo).padding(vertical = 6.dp, horizontal = 4.dp), verticalAlignment = Alignment.CenterVertically) {
                val online = conv?.isDirect == true && Time.isOnline(conv.peerLastSeen)
                Avatar(session.api.avatarUrl(conv?.displayAvatar), conv?.displayTitle ?: "…", 42.dp, online = online)
                Spacer(Modifier.width(12.dp))
                Column {
                    Text(conv?.displayTitle.orEmpty(), style = MaterialTheme.typography.titleMedium, maxLines = 1, overflow = TextOverflow.Ellipsis)
                    val sub = when {
                        conv == null -> ""
                        conv.isDirect -> Fmt.lastSeen(ctx, conv.peerLastSeen)
                        conv.kind == ConversationType.CHANNEL -> stringResource(R.string.subscribers_count, conv.memberCount)
                        else -> stringResource(R.string.members_count, conv.memberCount)
                    }
                    Text(sub, style = MaterialTheme.typography.bodySmall, color = if (online) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurfaceVariant, maxLines = 1)
                }
            }
            Spacer(Modifier.width(8.dp))
        }
    }
}

@Composable
private fun DayChip(text: String) {
    Box(Modifier.fillMaxWidth().padding(vertical = 8.dp), contentAlignment = Alignment.Center) {
        Text(text, Modifier.clip(RoundedCornerShape(50)).background(MaterialTheme.colorScheme.surfaceContainerHigh.copy(alpha = 0.9f)).padding(horizontal = 12.dp, vertical = 4.dp),
            style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}

@Composable
private fun SystemChip(text: String) {
    Box(Modifier.fillMaxWidth().padding(vertical = 4.dp, horizontal = 24.dp), contentAlignment = Alignment.Center) {
        Text(text, style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant, textAlign = TextAlign.Center)
    }
}

@Composable
private fun rememberMediaFile(session: ChatSession, container: AppContainer, path: String?, name: String?, auto: Boolean): Pair<File?, () -> Unit> {
    var trigger by remember(path) { mutableIntStateOf(if (auto) 1 else 0) }
    val file by produceState(path?.let { container.mediaCache.cached(it, name) }, path, trigger) {
        if (value == null && path != null && trigger > 0) value = runCatching { container.mediaCache.get(session.api, path, name) }.getOrNull()
    }
    return file to { trigger++ }
}

@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun MessageBubble(
    m: Message, mine: Boolean, status: DeliveryStatus?, showSender: Boolean, sender: Profile?, forwardedFrom: Profile?,
    replied: Message?, repliedSender: Profile?, session: ChatSession, container: AppContainer,
    onLongPress: () -> Unit, onRetry: () -> Unit, onOpenImage: (File) -> Unit,
) {
    val ctx = LocalContext.current
    val bg = if (mine) pv.bubbleOut else pv.bubbleIn
    val fg = if (mine) pv.onBubbleOut else pv.onBubbleIn
    val meta = if (mine) fg.copy(alpha = 0.65f) else pv.bubbleMeta
    val shape = RoundedCornerShape(18.dp, 18.dp, if (mine) 5.dp else 18.dp, if (mine) 18.dp else 5.dp)
    BoxWithConstraints(Modifier.fillMaxWidth().padding(vertical = 2.dp)) {
        val maxBubble = maxWidth * 0.8f
        Column(Modifier.align(if (mine) Alignment.CenterEnd else Alignment.CenterStart), horizontalAlignment = if (mine) Alignment.End else Alignment.Start) {
            Column(
                Modifier.widthIn(min = 72.dp, max = maxBubble).clip(shape).background(bg)
                    .combinedClickable(onClick = { if (status == DeliveryStatus.FAILED) onRetry() }, onLongClick = { if (!m.isDeleted) onLongPress() })
                    .padding(start = 10.dp, end = 10.dp, top = 7.dp, bottom = 6.dp),
            ) {
                if (showSender) Text(sender?.displayName.orEmpty(), color = MaterialTheme.colorScheme.primary, style = MaterialTheme.typography.labelLarge, fontSize = 13.sp, maxLines = 1)
                if (m.isDeleted) {
                    Text(stringResource(R.string.msg_deleted), color = meta, fontStyle = FontStyle.Italic)
                } else {
                    if (m.forwardedFrom != null) Row(verticalAlignment = Alignment.CenterVertically) {
                        Icon(Icons.AutoMirrored.Filled.Forward, null, Modifier.size(14.dp), tint = MaterialTheme.colorScheme.primary); Spacer(Modifier.width(4.dp))
                        Text(forwardedFrom?.displayName?.takeIf { it.isNotBlank() }?.let { stringResource(R.string.forwarded_from, it) } ?: stringResource(R.string.forwarded),
                            style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.primary, maxLines = 1, overflow = TextOverflow.Ellipsis)
                    }
                    if (m.replyToId != null) Row(Modifier.padding(bottom = 4.dp, top = 2.dp).clip(RoundedCornerShape(8.dp)).background(fg.copy(alpha = 0.08f)).height(androidx.compose.foundation.layout.IntrinsicSize.Min)) {
                        Box(Modifier.width(3.dp).fillMaxSize().background(MaterialTheme.colorScheme.primary))
                        Column(Modifier.padding(horizontal = 8.dp, vertical = 4.dp)) {
                            Text(repliedSender?.displayName.orEmpty().ifBlank { "…" }, style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.primary, maxLines = 1)
                            Text(replied?.let { MessageText.preview(ctx, it.kind, it.body, it.isDeleted) } ?: "…", style = MaterialTheme.typography.bodySmall, color = fg.copy(alpha = 0.8f), maxLines = 1, overflow = TextOverflow.Ellipsis)
                        }
                    }
                    when (m.kind) {
                        "image" -> ImageContent(m, session, container, onOpenImage, onLongPress)
                        "voice" -> VoiceContent(m, session, container, fg)
                        "video", "file" -> FileContent(m, session, container, fg)
                    }
                    if (m.body.isNotBlank()) Text(m.body, color = fg, style = MaterialTheme.typography.bodyLarge, modifier = Modifier.padding(top = if (m.kind == "text") 0.dp else 4.dp))
                }
                Row(Modifier.align(Alignment.End).padding(top = 2.dp), verticalAlignment = Alignment.CenterVertically) {
                    if (m.editedAt != null && !m.isDeleted) Text(stringResource(R.string.edited) + " · ", fontSize = 11.sp, color = meta)
                    Text(Fmt.time(m.createdAt), fontSize = 11.sp, color = meta)
                    if (status != null && !m.isDeleted) {
                        Spacer(Modifier.width(4.dp))
                        val (icon, tint) = when (status) {
                            DeliveryStatus.SENDING -> Icons.Filled.AccessTime to meta
                            DeliveryStatus.FAILED -> Icons.Filled.ErrorOutline to MaterialTheme.colorScheme.error
                            DeliveryStatus.SENT -> Icons.Filled.Done to meta
                            DeliveryStatus.DELIVERED -> Icons.Filled.DoneAll to meta
                            DeliveryStatus.READ -> Icons.Filled.DoneAll to pv.read
                        }
                        Icon(icon, status.name, Modifier.size(15.dp), tint = tint)
                    }
                }
            }
            if (status == DeliveryStatus.FAILED) Text(stringResource(R.string.not_sent), Modifier.clickable(onClick = onRetry).padding(top = 2.dp, end = 4.dp), fontSize = 11.sp, color = MaterialTheme.colorScheme.error)
        }
    }
}

@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun ImageContent(m: Message, session: ChatSession, container: AppContainer, onOpen: (File) -> Unit, onLongPress: () -> Unit) {
    val (file, _) = rememberMediaFile(session, container, m.mediaPath, m.mediaName, auto = true)
    Box(Modifier.padding(top = 2.dp).widthIn(max = 260.dp).fillMaxWidth().aspectRatio(1.25f).clip(RoundedCornerShape(12.dp)).background(Color.Black.copy(alpha = 0.25f))
        .combinedClickable(onClick = { file?.let(onOpen) }, onLongClick = onLongPress), contentAlignment = Alignment.Center) {
        if (file != null) AsyncImage(file, stringResource(R.string.msg_photo), Modifier.fillMaxSize(), contentScale = ContentScale.Crop)
        else CircularProgressIndicator(Modifier.size(26.dp), strokeWidth = 2.dp)
    }
}

@Composable
private fun FileContent(m: Message, session: ChatSession, container: AppContainer, fg: Color) {
    val (file, load) = rememberMediaFile(session, container, m.mediaPath, m.mediaName, auto = false)
    var wantOpen by remember { mutableStateOf(false) }
    LaunchedEffect(file, wantOpen) { if (wantOpen && file != null) { wantOpen = false; container.mediaCache.open(file, m.mediaMime) } }
    val video = m.kind == "video"
    Row(Modifier.padding(top = 2.dp).clip(RoundedCornerShape(12.dp)).clickable(enabled = m.mediaPath != null) { wantOpen = true; if (file == null) load() }.padding(4.dp), verticalAlignment = Alignment.CenterVertically) {
        Box(Modifier.size(44.dp).clip(CircleShape).background(MaterialTheme.colorScheme.primary.copy(alpha = 0.18f)), contentAlignment = Alignment.Center) {
            if (wantOpen && file == null || m.mediaPath == null) CircularProgressIndicator(Modifier.size(22.dp), strokeWidth = 2.dp)
            else Icon(if (video) Icons.Filled.PlayCircle else Icons.AutoMirrored.Filled.InsertDriveFile, null, tint = MaterialTheme.colorScheme.primary)
        }
        Spacer(Modifier.width(10.dp))
        Column {
            Text(m.mediaName ?: stringResource(if (video) R.string.msg_video else R.string.msg_file), color = fg, maxLines = 1, overflow = TextOverflow.Ellipsis, fontWeight = FontWeight.Medium)
            Text(listOfNotNull(if (video) stringResource(R.string.msg_video) else null, m.durationMs?.takeIf { video }?.let { Fmt.duration(it) }, Fmt.size(m.mediaSize)).joinToString(" · "), fontSize = 12.sp, color = fg.copy(alpha = 0.65f))
        }
    }
}

@Composable
private fun VoiceContent(m: Message, session: ChatSession, container: AppContainer, fg: Color) {
    val (file, load) = rememberMediaFile(session, container, m.mediaPath, m.mediaName, auto = false)
    val player by container.voicePlayer.state.collectAsState()
    val isThis = player.id == m.id
    var wantPlay by remember { mutableStateOf(false) }
    LaunchedEffect(file, wantPlay) { if (wantPlay && file != null) { wantPlay = false; container.voicePlayer.toggle(m.id, file) } }
    LaunchedEffect(isThis, player.playing) { while (isThis && player.playing) { container.voicePlayer.tick(); delay(120) } }
    Row(Modifier.padding(top = 2.dp).widthIn(min = 190.dp), verticalAlignment = Alignment.CenterVertically) {
        Box(Modifier.size(42.dp).clip(CircleShape).background(MaterialTheme.colorScheme.primary)
            .clickable(enabled = m.mediaPath != null) { if (file != null) container.voicePlayer.toggle(m.id, file) else { wantPlay = true; load() } }, contentAlignment = Alignment.Center) {
            if (wantPlay && file == null || m.mediaPath == null) CircularProgressIndicator(Modifier.size(20.dp), strokeWidth = 2.dp, color = MaterialTheme.colorScheme.onPrimary)
            else Icon(if (isThis && player.playing) Icons.Filled.Pause else Icons.Filled.PlayArrow, stringResource(if (isThis && player.playing) R.string.pause else R.string.play), tint = MaterialTheme.colorScheme.onPrimary)
        }
        Spacer(Modifier.width(10.dp))
        Column(Modifier.width(130.dp)) {
            val total = (m.durationMs ?: player.durationMs).coerceAtLeast(1)
            LinearProgressIndicator(progress = { if (isThis) (player.positionMs.toFloat() / total).coerceIn(0f, 1f) else 0f }, Modifier.fillMaxWidth().height(4.dp).clip(RoundedCornerShape(2.dp)),
                color = MaterialTheme.colorScheme.primary, trackColor = fg.copy(alpha = 0.18f), drawStopIndicator = {})
            Spacer(Modifier.height(4.dp))
            Text(Fmt.duration(if (isThis) player.positionMs else m.durationMs), fontSize = 12.sp, color = fg.copy(alpha = 0.7f))
        }
    }
}

@Composable
private fun Composer(vm: ChatViewModel, ui: ChatUi, profiles: Map<String, Profile>, container: AppContainer) {
    val ctx = LocalContext.current
    val scope = rememberCoroutineScope()
    var text by rememberSaveable { mutableStateOf("") }
    var attach by remember { mutableStateOf(false) }
    var recording by remember { mutableStateOf(false) }
    var seconds by remember { mutableIntStateOf(0) }
    var preparing by remember { mutableStateOf(false) }
    val recorder = remember { VoiceRecorder(ctx) }
    DisposableEffect(Unit) { onDispose { recorder.cancel() } }
    LaunchedEffect(ui.editing?.id) { ui.editing?.let { text = it.body } }
    LaunchedEffect(recording) { seconds = 0; while (recording) { delay(1000); seconds++; if (seconds >= 300) { recording = false; recorder.stop()?.let { vm.sendMedia(it) } } } }

    fun sendUri(uri: android.net.Uri?) {
        if (uri == null) return
        preparing = true
        scope.launch {
            try { vm.sendMedia(MediaTools.prepare(ctx, uri), text.trim()); text = "" }
            catch (e: PayvandException) { Toast.makeText(ctx, errorMessage(ctx, e), Toast.LENGTH_SHORT).show() }
            catch (e: Exception) { Toast.makeText(ctx, R.string.err_unknown, Toast.LENGTH_SHORT).show() }
            finally { preparing = false }
        }
    }
    val pickMedia = rememberLauncherForActivityResult(ActivityResultContracts.PickVisualMedia()) { sendUri(it) }
    val pickFile = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { sendUri(it) }
    fun startRecording() { if (recorder.start()) recording = true else Toast.makeText(ctx, R.string.mic_permission, Toast.LENGTH_SHORT).show() }
    val micPermission = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { ok -> if (ok) startRecording() else Toast.makeText(ctx, R.string.mic_permission, Toast.LENGTH_LONG).show() }

    Surface(color = MaterialTheme.colorScheme.surfaceContainerLow) {
        Column(Modifier.navigationBarsPadding()) {
            val ctxMsg = ui.editing ?: ui.replyTo
            AnimatedVisibility(ctxMsg != null) {
                Row(Modifier.fillMaxWidth().padding(start = 14.dp, end = 4.dp, top = 6.dp), verticalAlignment = Alignment.CenterVertically) {
                    Icon(if (ui.editing != null) Icons.Filled.Edit else Icons.AutoMirrored.Filled.Reply, null, tint = MaterialTheme.colorScheme.primary, modifier = Modifier.size(20.dp))
                    Spacer(Modifier.width(10.dp))
                    Column(Modifier.weight(1f)) {
                        Text(if (ui.editing != null) stringResource(R.string.editing) else profiles[ctxMsg?.senderId]?.displayName.orEmpty(), style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.primary, maxLines = 1)
                        Text(ctxMsg?.let { MessageText.preview(ctx, it.kind, it.body, it.isDeleted) }.orEmpty(), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant, maxLines = 1, overflow = TextOverflow.Ellipsis)
                    }
                    IconButton(onClick = { if (ui.editing != null) { vm.edit(null); text = "" } else vm.reply(null) }) { Icon(Icons.Filled.Close, stringResource(R.string.cancel)) }
                }
            }
            if (recording) {
                Row(Modifier.fillMaxWidth().padding(horizontal = 8.dp, vertical = 8.dp), verticalAlignment = Alignment.CenterVertically) {
                    IconButton(onClick = { recording = false; recorder.cancel() }) { Icon(Icons.Filled.Delete, stringResource(R.string.cancel), tint = MaterialTheme.colorScheme.error) }
                    Box(Modifier.size(10.dp).clip(CircleShape).background(Brand.FlagRed))
                    Spacer(Modifier.width(8.dp))
                    Text("%d:%02d".format(seconds / 60, seconds % 60), fontWeight = FontWeight.SemiBold)
                    Spacer(Modifier.width(10.dp))
                    Text(stringResource(R.string.recording), Modifier.weight(1f), color = MaterialTheme.colorScheme.onSurfaceVariant)
                    RoundAction(Icons.AutoMirrored.Filled.Send, stringResource(R.string.send)) { recording = false; recorder.stop()?.let { vm.sendMedia(it) } }
                }
            } else Row(Modifier.fillMaxWidth().padding(horizontal = 6.dp, vertical = 6.dp), verticalAlignment = Alignment.Bottom) {
                Box {
                    IconButton(onClick = { attach = true }, enabled = ui.editing == null && !preparing) {
                        if (preparing) CircularProgressIndicator(Modifier.size(22.dp), strokeWidth = 2.dp) else Icon(Icons.Filled.AttachFile, stringResource(R.string.attach), tint = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                    DropdownMenu(attach, { attach = false }) {
                        DropdownMenuItem(text = { Text(stringResource(R.string.attach_photo_video)) }, leadingIcon = { Icon(Icons.Filled.Image, null) },
                            onClick = { attach = false; pickMedia.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageAndVideo)) })
                        DropdownMenuItem(text = { Text(stringResource(R.string.attach_file)) }, leadingIcon = { Icon(Icons.AutoMirrored.Filled.InsertDriveFile, null) },
                            onClick = { attach = false; pickFile.launch(arrayOf("*/*")) })
                    }
                }
                Box(Modifier.weight(1f).padding(vertical = 2.dp).heightIn(min = 44.dp, max = 140.dp).clip(RoundedCornerShape(22.dp)).background(MaterialTheme.colorScheme.surfaceContainerHigh).padding(horizontal = 16.dp, vertical = 11.dp), contentAlignment = Alignment.CenterStart) {
                    if (text.isEmpty()) Text(stringResource(R.string.message_hint), color = MaterialTheme.colorScheme.onSurfaceVariant)
                    BasicTextField(text, { text = it.take(4000) }, Modifier.fillMaxWidth(), textStyle = TextStyle(color = MaterialTheme.colorScheme.onSurface, fontSize = 16.sp, lineHeight = 21.sp),
                        cursorBrush = SolidColor(MaterialTheme.colorScheme.primary), keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.Sentences))
                }
                Spacer(Modifier.width(6.dp))
                if (text.isBlank() && ui.editing == null) RoundAction(Icons.Filled.Mic, stringResource(R.string.voice)) {
                    if (ContextCompat.checkSelfPermission(ctx, Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED) startRecording() else micPermission.launch(Manifest.permission.RECORD_AUDIO)
                } else RoundAction(if (ui.editing != null) Icons.Filled.Check else Icons.AutoMirrored.Filled.Send, stringResource(R.string.send)) { vm.submit(text); text = "" }
            }
        }
    }
}

@Composable
private fun RoundAction(icon: ImageVector, description: String, onClick: () -> Unit) {
    Box(Modifier.padding(bottom = 2.dp).size(46.dp).clip(CircleShape).background(Brand.Gradient).clickable(onClick = onClick), contentAlignment = Alignment.Center) {
        Icon(icon, description, tint = Color(0xFF00210F))
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun MessageActions(
    m: Message, mine: Boolean, pending: Boolean, canPost: Boolean, canDelete: Boolean, onDismiss: () -> Unit,
    onReply: () -> Unit, onForward: () -> Unit, onCopy: () -> Unit, onEdit: () -> Unit, onDelete: () -> Unit, onReport: () -> Unit,
) {
    ModalBottomSheet(onDismissRequest = onDismiss, containerColor = MaterialTheme.colorScheme.surfaceContainer) {
        @Composable fun action(icon: ImageVector, label: Int, danger: Boolean = false, run: () -> Unit) {
            val color = if (danger) MaterialTheme.colorScheme.error else MaterialTheme.colorScheme.onSurface
            Row(Modifier.fillMaxWidth().clickable { onDismiss(); run() }.padding(horizontal = 24.dp, vertical = 14.dp), verticalAlignment = Alignment.CenterVertically) {
                Icon(icon, null, tint = if (danger) color else MaterialTheme.colorScheme.primary); Spacer(Modifier.width(18.dp)); Text(stringResource(label), color = color, style = MaterialTheme.typography.bodyLarge)
            }
        }
        Column(Modifier.navigationBarsPadding().padding(bottom = 8.dp)) {
            if (!pending && canPost) action(Icons.AutoMirrored.Filled.Reply, R.string.reply, run = onReply)
            if (!pending) action(Icons.AutoMirrored.Filled.Forward, R.string.forward, run = onForward)
            if (m.body.isNotBlank()) action(Icons.Filled.ContentCopy, R.string.copy, run = onCopy)
            if (mine && !pending && m.kind == "text" && canPost) action(Icons.Filled.Edit, R.string.edit, run = onEdit)
            if (!mine && !pending) action(Icons.Filled.Flag, R.string.report, run = onReport)
            if (canDelete) action(Icons.Filled.Delete, R.string.delete, danger = true, run = onDelete)
        }
    }
}

@Composable
private fun ForwardDialog(session: ChatSession, targets: List<ConversationSummary>, onDismiss: () -> Unit, onPick: (String) -> Unit) {
    AlertDialog(onDismissRequest = onDismiss, title = { Text(stringResource(R.string.forward_to)) },
        text = {
            LazyColumn(Modifier.heightIn(max = 420.dp)) {
                items(targets, key = { it.id }) { c ->
                    Row(Modifier.fillMaxWidth().clip(RoundedCornerShape(12.dp)).clickable { onPick(c.id) }.padding(vertical = 8.dp), verticalAlignment = Alignment.CenterVertically) {
                        Avatar(session.api.avatarUrl(c.displayAvatar), c.displayTitle, 40.dp); Spacer(Modifier.width(12.dp))
                        Text(c.displayTitle, maxLines = 1, overflow = TextOverflow.Ellipsis)
                    }
                }
            }
        },
        confirmButton = {}, dismissButton = { TextButton(onClick = onDismiss) { Text(stringResource(R.string.cancel)) } })
}
