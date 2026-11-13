package tj.payvand.app.ui.profile

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
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
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.systemBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.Logout
import androidx.compose.material.icons.filled.AutoAwesome
import androidx.compose.material.icons.filled.Block
import androidx.compose.material.icons.filled.CameraAlt
import androidx.compose.material.icons.filled.ContentCopy
import androidx.compose.material.icons.filled.DarkMode
import androidx.compose.material.icons.filled.DeleteForever
import androidx.compose.material.icons.filled.Dns
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material.icons.filled.Language
import androidx.compose.material.icons.filled.Phone
import androidx.compose.material.icons.filled.Shield
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.RadioButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
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
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import coil3.compose.AsyncImage
import kotlinx.coroutines.launch
import tj.payvand.app.BuildConfig
import tj.payvand.app.ChatSession
import tj.payvand.app.PayvandApp
import tj.payvand.app.R
import tj.payvand.app.data.MediaTools
import tj.payvand.app.ui.auth.BrandBackground
import tj.payvand.app.ui.auth.Languages
import tj.payvand.app.ui.auth.applyLanguage
import tj.payvand.app.ui.auth.currentLanguageTag
import tj.payvand.app.ui.components.Avatar
import tj.payvand.app.ui.components.EmptyState
import tj.payvand.app.ui.components.ErrorText
import tj.payvand.app.ui.components.PrimaryButton
import tj.payvand.app.ui.components.PvField
import tj.payvand.app.ui.components.PvTopBar
import tj.payvand.app.ui.components.errorMessage
import tj.payvand.app.ui.home.HomeNav
import tj.payvand.app.ui.home.PersonRow
import tj.payvand.app.ui.home.TabHeader
import tj.payvand.app.ui.theme.ThemeMode
import tj.payvand.core.Limits
import tj.payvand.core.PayvandException
import tj.payvand.core.Profile

fun Context.copyText(text: String) {
    getSystemService(ClipboardManager::class.java).setPrimaryClip(ClipData.newPlainText("PAYVAND", text))
    Toast.makeText(this, R.string.copied, Toast.LENGTH_SHORT).show()
}

@Composable
fun PayvandIdCard(id: String, modifier: Modifier = Modifier) {
    val ctx = LocalContext.current
    Surface(modifier.fillMaxWidth(), shape = RoundedCornerShape(18.dp), color = MaterialTheme.colorScheme.primaryContainer) {
        Row(Modifier.clickable { ctx.copyText(id) }.padding(horizontal = 18.dp, vertical = 12.dp), verticalAlignment = Alignment.CenterVertically) {
            Column(Modifier.weight(1f)) {
                Text(stringResource(R.string.your_payvand_id), style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onPrimaryContainer.copy(alpha = 0.75f))
                Text(id, style = MaterialTheme.typography.titleLarge, fontFamily = FontFamily.Monospace, color = MaterialTheme.colorScheme.onPrimaryContainer)
            }
            Icon(Icons.Filled.ContentCopy, stringResource(R.string.copy), tint = MaterialTheme.colorScheme.onPrimaryContainer)
        }
    }
}

/** Редактор профиля: используется и при первом входе (обязательный шаг), и в настройках. */
@Composable
fun ProfileEditor(session: ChatSession, firstTime: Boolean, onDone: () -> Unit, onBack: (() -> Unit)? = null) {
    val me by session.me.collectAsState()
    val ctx = LocalContext.current
    val scope = rememberCoroutineScope()
    var name by rememberSaveable(me?.id) { mutableStateOf(me?.displayName.orEmpty()) }
    var username by rememberSaveable(me?.id) { mutableStateOf(me?.username.orEmpty()) }
    var bio by rememberSaveable(me?.id) { mutableStateOf(me?.bio.orEmpty()) }
    var picked by remember { mutableStateOf<Uri?>(null) }
    var loading by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    val picker = rememberLauncherForActivityResult(ActivityResultContracts.PickVisualMedia()) { if (it != null) picked = it }

    fun save() {
        if (name.isBlank()) { error = ctx.getString(R.string.err_name_required); return }
        if (!Limits.USERNAME_REGEX.matches(username.trim().lowercase())) { error = ctx.getString(R.string.err_invalid_username); return }
        loading = true; error = null
        scope.launch {
            try {
                session.api.updateProfile(username, name, bio)
                picked?.let { uri -> session.api.setMyAvatar(session.api.uploadAvatar(MediaTools.squareAvatar(ctx, uri))) }
                session.reloadMe()
                onDone()
            } catch (e: Exception) {
                error = errorMessage(ctx, e as? PayvandException)
            } finally { loading = false }
        }
    }

    BrandBackground {
        Column(Modifier.fillMaxSize().systemBarsPadding().imePadding()) {
            PvTopBar(stringResource(if (firstTime) R.string.profile_setup_title else R.string.edit_profile), onBack)
            Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(horizontal = 24.dp), horizontalAlignment = Alignment.CenterHorizontally) {
                Spacer(Modifier.height(8.dp))
                Box(Modifier.size(112.dp).clip(CircleShape).clickable { picker.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly)) }) {
                    if (picked != null) AsyncImage(picked, null, Modifier.fillMaxSize().clip(CircleShape), contentScale = ContentScale.Crop)
                    else Avatar(session.api.avatarUrl(me?.avatarPath), name.ifBlank { "?" }, 112.dp)
                    Box(Modifier.align(Alignment.BottomEnd).size(36.dp).clip(CircleShape).background(MaterialTheme.colorScheme.primary), contentAlignment = Alignment.Center) {
                        Icon(Icons.Filled.CameraAlt, stringResource(R.string.change_photo), Modifier.size(18.dp), tint = MaterialTheme.colorScheme.onPrimary)
                    }
                }
                Spacer(Modifier.height(20.dp))
                PvField(name, { name = it.take(64) }, stringResource(R.string.display_name), keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.Words))
                Spacer(Modifier.height(12.dp))
                PvField(username, { v -> username = v.lowercase().filter { it in 'a'..'z' || it.isDigit() || it == '_' }.take(24) }, stringResource(R.string.username),
                    supporting = stringResource(R.string.username_hint), leading = { Text("@", color = MaterialTheme.colorScheme.primary) },
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Ascii, autoCorrectEnabled = false))
                if (!firstTime) {
                    Spacer(Modifier.height(4.dp))
                    PvField(bio, { bio = it.take(200) }, stringResource(R.string.bio), singleLine = false)
                }
                Spacer(Modifier.height(16.dp))
                me?.let { PayvandIdCard(it.payvandId) }
                ErrorText(error)
                Spacer(Modifier.height(20.dp))
            }
            PrimaryButton(stringResource(if (firstTime) R.string.done else R.string.save), ::save, Modifier.padding(horizontal = 24.dp, vertical = 12.dp), loading = loading)
        }
    }
}

@Composable
private fun SettingRow(icon: ImageVector, title: String, value: String? = null, danger: Boolean = false, onClick: () -> Unit) {
    val tint = if (danger) MaterialTheme.colorScheme.error else MaterialTheme.colorScheme.primary
    Row(Modifier.fillMaxWidth().clickable(onClick = onClick).padding(horizontal = 20.dp, vertical = 14.dp), verticalAlignment = Alignment.CenterVertically) {
        Box(Modifier.size(38.dp).clip(RoundedCornerShape(12.dp)).background(tint.copy(alpha = 0.14f)), contentAlignment = Alignment.Center) { Icon(icon, null, Modifier.size(20.dp), tint = tint) }
        Spacer(Modifier.width(14.dp))
        Column(Modifier.weight(1f)) {
            Text(title, style = MaterialTheme.typography.bodyLarge, color = if (danger) MaterialTheme.colorScheme.error else MaterialTheme.colorScheme.onBackground)
            if (value != null) Text(value, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
}

@Composable
private fun <T> ChoiceDialog(title: String, options: List<Pair<T, String>>, selected: T, onPick: (T) -> Unit, onDismiss: () -> Unit) {
    AlertDialog(onDismissRequest = onDismiss, title = { Text(title) }, confirmButton = { TextButton(onClick = onDismiss) { Text(stringResource(R.string.close)) } }, text = {
        Column { options.forEach { (v, label) ->
            Row(Modifier.fillMaxWidth().clip(RoundedCornerShape(12.dp)).clickable { onPick(v); onDismiss() }.padding(vertical = 4.dp), verticalAlignment = Alignment.CenterVertically) {
                RadioButton(selected = v == selected, onClick = { onPick(v); onDismiss() }); Text(label)
            }
        } }
    })
}

@Composable
fun ConfirmDialog(text: String, confirm: String, danger: Boolean = false, onConfirm: () -> Unit, onDismiss: () -> Unit) {
    AlertDialog(onDismissRequest = onDismiss, text = { Text(text) },
        confirmButton = { TextButton(onClick = { onDismiss(); onConfirm() }) { Text(confirm, color = if (danger) MaterialTheme.colorScheme.error else MaterialTheme.colorScheme.primary) } },
        dismissButton = { TextButton(onClick = onDismiss) { Text(stringResource(R.string.cancel)) } })
}

@Composable
fun ProfileTab(session: ChatSession, nav: HomeNav) {
    val ctx = LocalContext.current
    val container = (ctx.applicationContext as PayvandApp).container
    val me by session.me.collectAsState()
    val theme by container.prefs.theme.collectAsState()
    val scope = rememberCoroutineScope()
    var dialog by remember { mutableStateOf<String?>(null) }
    var phone by remember { mutableStateOf<String?>(null) }
    LaunchedEffect(me?.id) { phone = runCatching { session.api.myPhone() }.getOrNull() }

    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState())) {
        TabHeader(stringResource(R.string.tab_profile)) { IconButton(onClick = nav.editProfile) { Icon(Icons.Filled.Edit, stringResource(R.string.edit_profile)) } }
        Row(Modifier.fillMaxWidth().clickable(onClick = nav.editProfile).padding(horizontal = 20.dp, vertical = 10.dp), verticalAlignment = Alignment.CenterVertically) {
            Avatar(session.api.avatarUrl(me?.avatarPath), me?.displayName ?: "?", 76.dp, online = true)
            Spacer(Modifier.width(16.dp))
            Column {
                Text(me?.displayName.orEmpty(), style = MaterialTheme.typography.titleLarge)
                Text("@" + me?.username.orEmpty(), color = MaterialTheme.colorScheme.primary)
                if (!me?.bio.isNullOrBlank()) Text(me!!.bio, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
        me?.let { PayvandIdCard(it.payvandId, Modifier.padding(horizontal = 20.dp, vertical = 8.dp)) }
        Spacer(Modifier.height(8.dp))
        SettingRow(Icons.Filled.Phone, stringResource(R.string.phone), (phone ?: "—") + "\n" + stringResource(R.string.phone_unverified)) { dialog = "phone" }
        SettingRow(Icons.Filled.Language, stringResource(R.string.language), Languages.first { it.tag == currentLanguageTag() }.native) { dialog = "lang" }
        SettingRow(Icons.Filled.DarkMode, stringResource(R.string.theme), stringResource(when (theme) { ThemeMode.SYSTEM -> R.string.theme_system; ThemeMode.DARK -> R.string.theme_dark; ThemeMode.LIGHT -> R.string.theme_light })) { dialog = "theme" }
        val animatedBg by container.prefs.animatedBackground.collectAsState()
        SettingRow(Icons.Filled.AutoAwesome, stringResource(R.string.animated_background), stringResource(if (animatedBg) R.string.on else R.string.off)) { container.prefs.setAnimatedBackground(!animatedBg) }
        SettingRow(Icons.Filled.Block, stringResource(R.string.blocked_users)) { nav.blocked() }
        if (nav.changeServer != null) SettingRow(Icons.Filled.Dns, stringResource(R.string.server), container.serverConfig()?.url) { dialog = "server" }
        HorizontalDivider(Modifier.padding(vertical = 8.dp, horizontal = 20.dp), color = MaterialTheme.colorScheme.outlineVariant)
        SettingRow(Icons.AutoMirrored.Filled.Logout, stringResource(R.string.sign_out)) { dialog = "signout" }
        SettingRow(Icons.Filled.DeleteForever, stringResource(R.string.delete_account), danger = true) { dialog = "delete" }
        Row(Modifier.padding(horizontal = 20.dp, vertical = 14.dp)) {
            Icon(Icons.Filled.Shield, null, Modifier.size(18.dp), tint = MaterialTheme.colorScheme.onSurfaceVariant)
            Spacer(Modifier.width(10.dp))
            Text(stringResource(R.string.security_note), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        Text("Payvan · " + stringResource(R.string.version, BuildConfig.VERSION_NAME), Modifier.fillMaxWidth().padding(bottom = 24.dp), textAlign = TextAlign.Center, style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
    }

    when (dialog) {
        "lang" -> ChoiceDialog(stringResource(R.string.language), Languages.map { it.tag to it.native }, currentLanguageTag(), { applyLanguage(it) }) { dialog = null }
        "theme" -> ChoiceDialog(stringResource(R.string.theme), listOf(ThemeMode.SYSTEM to stringResource(R.string.theme_system), ThemeMode.DARK to stringResource(R.string.theme_dark), ThemeMode.LIGHT to stringResource(R.string.theme_light)), theme, { container.prefs.setTheme(it) }) { dialog = null }
        "signout" -> ConfirmDialog(stringResource(R.string.sign_out_confirm), stringResource(R.string.sign_out), onConfirm = { scope.launch { session.signOut() } }) { dialog = null }
        "delete" -> ConfirmDialog(stringResource(R.string.delete_account_confirm), stringResource(R.string.delete_account), danger = true, onConfirm = {
            scope.launch { runCatching { session.api.deleteAccount() }.onFailure { Toast.makeText(ctx, errorMessage(ctx, it), Toast.LENGTH_SHORT).show() } }
        }) { dialog = null }
        "server" -> ConfirmDialog(stringResource(R.string.change_server) + "?\n" + container.serverConfig()?.url.orEmpty(), stringResource(R.string.change_server), onConfirm = {
            scope.launch { runCatching { session.signOut() }; nav.changeServer?.invoke() }
        }) { dialog = null }
        "phone" -> {
            var value by remember { mutableStateOf(phone.orEmpty()) }
            var bad by remember { mutableStateOf(false) }
            AlertDialog(onDismissRequest = { dialog = null }, title = { Text(stringResource(R.string.phone)) },
                text = {
                    PvField(value, { v -> value = v.filter { it.isDigit() || it == '+' }.take(16); bad = false }, "+992…", isError = bad,
                        supporting = stringResource(if (bad) R.string.phone_invalid else R.string.phone_unverified), keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Phone))
                },
                confirmButton = { TextButton(onClick = {
                    if (value.isNotEmpty() && !Limits.PHONE_REGEX.matches(value)) bad = true
                    else scope.launch { runCatching { session.api.setPhone(value) }.onSuccess { phone = value.ifEmpty { null }; dialog = null }.onFailure { Toast.makeText(ctx, errorMessage(ctx, it), Toast.LENGTH_SHORT).show() } }
                }) { Text(stringResource(R.string.save)) } },
                dismissButton = { TextButton(onClick = { dialog = null }) { Text(stringResource(R.string.cancel)) } })
        }
    }
}

@Composable
fun BlockedScreen(session: ChatSession, onBack: () -> Unit) {
    var list by remember { mutableStateOf<List<Profile>?>(null) }
    val scope = rememberCoroutineScope()
    LaunchedEffect(Unit) { list = runCatching { session.api.blockedUsers() }.getOrDefault(emptyList()) }
    Scaffold(topBar = { PvTopBar(stringResource(R.string.blocked_users), onBack) }, containerColor = MaterialTheme.colorScheme.background) { pad ->
        val l = list
        if (l != null && l.isEmpty()) EmptyState(Icons.Filled.Block, stringResource(R.string.no_blocked), modifier = Modifier.padding(pad))
        else LazyColumn(Modifier.padding(pad)) {
            items(l.orEmpty(), key = { it.id }) { p ->
                PersonRow(session, p, trailing = {
                    TextButton(onClick = { scope.launch { runCatching { session.api.unblock(p.id) }.onSuccess { list = list?.filter { it.id != p.id }; session.refresh() } } }) { Text(stringResource(R.string.unblock)) }
                }) {}
            }
        }
    }
}
