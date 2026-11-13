package tj.payvand.app.ui.components

import android.content.Context
import androidx.compose.foundation.background
import androidx.compose.foundation.border
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
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Search
import androidx.compose.material.icons.filled.Close
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LocalContentColor
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextField
import androidx.compose.material3.TextFieldDefaults
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.VisualTransformation
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import coil3.compose.AsyncImage
import tj.payvand.app.R
import tj.payvand.app.ui.theme.Brand
import tj.payvand.app.ui.theme.pv
import tj.payvand.core.PayvandException
import tj.payvand.core.Time
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.format.DateTimeFormatter

private val avatarPalette = listOf(
    listOf(Color(0xFF12C777), Color(0xFF0A7F56)), listOf(Color(0xFF22D3C5), Color(0xFF0B7D8C)),
    listOf(Color(0xFFF2C14E), Color(0xFFD9822B)), listOf(Color(0xFFE5383B), Color(0xFF9D1F3F)),
    listOf(Color(0xFF5B8DEF), Color(0xFF3A4FC4)), listOf(Color(0xFFB07CF5), Color(0xFF6B3FC4)),
)

fun initials(name: String): String {
    val parts = name.trim().split(Regex("\\s+")).filter { it.isNotEmpty() }
    return when {
        parts.isEmpty() -> "?"
        parts.size == 1 -> parts[0].take(1).uppercase()
        else -> (parts[0].take(1) + parts[1].take(1)).uppercase()
    }
}

@Composable
fun Avatar(url: String?, name: String, size: Dp = 52.dp, online: Boolean = false, modifier: Modifier = Modifier) {
    Box(modifier.size(size)) {
        val colors = avatarPalette[(name.hashCode() and 0x7fffffff) % avatarPalette.size]
        Box(Modifier.fillMaxSize().clip(CircleShape).background(Brush.linearGradient(colors)), contentAlignment = Alignment.Center) {
            Text(initials(name), color = Color.White, fontWeight = FontWeight.SemiBold, fontSize = (size.value * 0.38f).sp)
            if (!url.isNullOrBlank()) {
                AsyncImage(model = url, contentDescription = stringResource(R.string.avatar), modifier = Modifier.fillMaxSize().clip(CircleShape), contentScale = ContentScale.Crop)
            }
        }
        if (online) {
            Box(Modifier.align(Alignment.BottomEnd).size(size * 0.28f).clip(CircleShape).background(MaterialTheme.colorScheme.background).padding(2.dp).clip(CircleShape).background(pv.online))
        }
    }
}

/** Главная кнопка с фирменным градиентом. */
@Composable
fun PrimaryButton(text: String, onClick: () -> Unit, modifier: Modifier = Modifier, enabled: Boolean = true, loading: Boolean = false, icon: ImageVector? = null) {
    val shape = RoundedCornerShape(28.dp)
    val active = enabled && !loading
    Box(
        modifier.fillMaxWidth().heightIn(min = 54.dp).clip(shape)
            .background(if (enabled) Brand.Gradient else Brush.horizontalGradient(listOf(MaterialTheme.colorScheme.surfaceVariant, MaterialTheme.colorScheme.surfaceVariant)))
            .clickable(enabled = active, onClick = onClick).padding(horizontal = 20.dp),
        contentAlignment = Alignment.Center,
    ) {
        val fg = if (enabled) Color(0xFF00210F) else MaterialTheme.colorScheme.onSurfaceVariant
        if (loading) CircularProgressIndicator(Modifier.size(22.dp), color = fg, strokeWidth = 2.5.dp)
        else Row(verticalAlignment = Alignment.CenterVertically) {
            Text(text, color = fg, style = MaterialTheme.typography.labelLarge, fontSize = 16.sp)
            if (icon != null) { Spacer(Modifier.width(8.dp)); Icon(icon, null, tint = fg, modifier = Modifier.size(20.dp)) }
        }
    }
}

@Composable
fun SecondaryButton(text: String, onClick: () -> Unit, modifier: Modifier = Modifier, enabled: Boolean = true) {
    val shape = RoundedCornerShape(28.dp)
    Box(
        modifier.fillMaxWidth().heightIn(min = 54.dp).clip(shape).border(1.5.dp, MaterialTheme.colorScheme.primary.copy(alpha = if (enabled) 0.9f else 0.3f), shape)
            .clickable(enabled = enabled, onClick = onClick).padding(horizontal = 20.dp),
        contentAlignment = Alignment.Center,
    ) { Text(text, color = MaterialTheme.colorScheme.onBackground, style = MaterialTheme.typography.labelLarge, fontSize = 16.sp) }
}

@Composable
fun PvField(
    value: String, onValueChange: (String) -> Unit, label: String, modifier: Modifier = Modifier,
    supporting: String? = null, isError: Boolean = false, singleLine: Boolean = true,
    keyboardOptions: KeyboardOptions = KeyboardOptions.Default, keyboardActions: KeyboardActions = KeyboardActions.Default,
    visualTransformation: VisualTransformation = VisualTransformation.None,
    leading: @Composable (() -> Unit)? = null, trailing: @Composable (() -> Unit)? = null, enabled: Boolean = true,
) {
    OutlinedTextField(
        value = value, onValueChange = onValueChange, label = { Text(label) }, modifier = modifier.fillMaxWidth(),
        supportingText = supporting?.let { { Text(it) } }, isError = isError, singleLine = singleLine, enabled = enabled,
        keyboardOptions = keyboardOptions, keyboardActions = keyboardActions, visualTransformation = visualTransformation,
        leadingIcon = leading, trailingIcon = trailing, shape = RoundedCornerShape(16.dp),
        colors = OutlinedTextFieldDefaults.colors(
            unfocusedBorderColor = MaterialTheme.colorScheme.outlineVariant,
            unfocusedContainerColor = MaterialTheme.colorScheme.surfaceContainerLow,
            focusedContainerColor = MaterialTheme.colorScheme.surfaceContainerLow,
        ),
    )
}

@Composable
fun SearchField(value: String, onValueChange: (String) -> Unit, placeholder: String, modifier: Modifier = Modifier) {
    TextField(
        value = value, onValueChange = onValueChange, modifier = modifier.fillMaxWidth().heightIn(min = 52.dp), singleLine = true,
        placeholder = { Text(placeholder, color = MaterialTheme.colorScheme.onSurfaceVariant, maxLines = 1, overflow = TextOverflow.Ellipsis) },
        leadingIcon = { Icon(Icons.Filled.Search, null, tint = MaterialTheme.colorScheme.onSurfaceVariant) },
        trailingIcon = if (value.isNotEmpty()) { { IconButton(onClick = { onValueChange("") }) { Icon(Icons.Filled.Close, stringResource(R.string.close)) } } } else null,
        shape = RoundedCornerShape(26.dp),
        colors = TextFieldDefaults.colors(
            focusedContainerColor = MaterialTheme.colorScheme.surfaceContainer, unfocusedContainerColor = MaterialTheme.colorScheme.surfaceContainer,
            focusedIndicatorColor = Color.Transparent, unfocusedIndicatorColor = Color.Transparent,
        ),
    )
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun PvTopBar(title: String, onBack: (() -> Unit)? = null, actions: @Composable () -> Unit = {}) {
    TopAppBar(
        title = { Text(title, maxLines = 1, overflow = TextOverflow.Ellipsis) },
        navigationIcon = { if (onBack != null) IconButton(onClick = onBack) { Icon(Icons.AutoMirrored.Filled.ArrowBack, stringResource(R.string.back)) } },
        actions = { actions() },
        colors = TopAppBarDefaults.topAppBarColors(containerColor = MaterialTheme.colorScheme.background),
    )
}

@Composable
fun ErrorText(text: String?, modifier: Modifier = Modifier) {
    if (!text.isNullOrBlank()) Text(text, modifier.fillMaxWidth().padding(top = 8.dp), color = MaterialTheme.colorScheme.error, style = MaterialTheme.typography.bodyMedium, textAlign = TextAlign.Center)
}

@Composable
fun EmptyState(icon: ImageVector, title: String, subtitle: String? = null, modifier: Modifier = Modifier, action: @Composable (() -> Unit)? = null) {
    Column(modifier.fillMaxWidth().padding(32.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.Center) {
        Box(Modifier.size(84.dp).clip(CircleShape).background(MaterialTheme.colorScheme.primaryContainer), contentAlignment = Alignment.Center) {
            Icon(icon, null, tint = MaterialTheme.colorScheme.primary, modifier = Modifier.size(38.dp))
        }
        Spacer(Modifier.height(18.dp))
        Text(title, style = MaterialTheme.typography.titleMedium, textAlign = TextAlign.Center)
        if (subtitle != null) {
            Spacer(Modifier.height(6.dp))
            Text(subtitle, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant, textAlign = TextAlign.Center)
        }
        if (action != null) { Spacer(Modifier.height(18.dp)); action() }
    }
}

@Composable
fun SectionLabel(text: String, modifier: Modifier = Modifier) {
    Text(text.uppercase(), modifier.padding(start = 20.dp, top = 18.dp, bottom = 6.dp), style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.primary, letterSpacing = 1.2.sp)
}

@Composable
fun Pill(text: String, modifier: Modifier = Modifier) {
    Surface(modifier, shape = RoundedCornerShape(50), color = MaterialTheme.colorScheme.primaryContainer) {
        Text(text, Modifier.padding(horizontal = 8.dp, vertical = 2.dp), style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onPrimaryContainer)
    }
}

fun errorMessage(ctx: Context, e: Throwable?): String {
    val code = (e as? PayvandException)?.code ?: PayvandException.Code.UNKNOWN
    return ctx.getString(when (code) {
        PayvandException.Code.NETWORK -> R.string.err_network
        PayvandException.Code.INVALID_CREDENTIALS -> R.string.err_invalid_credentials
        PayvandException.Code.EMAIL_NOT_CONFIRMED -> R.string.err_email_not_confirmed
        PayvandException.Code.USER_EXISTS -> R.string.err_user_exists
        PayvandException.Code.WEAK_PASSWORD -> R.string.err_weak_password
        PayvandException.Code.INVALID_CODE -> R.string.err_invalid_code
        PayvandException.Code.RATE_LIMIT -> R.string.err_rate_limit
        PayvandException.Code.FORBIDDEN -> R.string.err_forbidden
        PayvandException.Code.USERNAME_TAKEN -> R.string.err_username_taken
        PayvandException.Code.INVALID_USERNAME -> R.string.err_invalid_username
        PayvandException.Code.FILE_TOO_LARGE -> R.string.err_file_too_large
        PayvandException.Code.BLOCKED -> R.string.err_blocked
        PayvandException.Code.INVALID_EMAIL -> R.string.err_invalid_email
        PayvandException.Code.SERVER_MISCONFIGURED -> R.string.err_server
        PayvandException.Code.UNKNOWN -> R.string.err_unknown
    })
}

object Fmt {
    private val hm = DateTimeFormatter.ofPattern("HH:mm")
    private val dm = DateTimeFormatter.ofPattern("dd.MM")
    private val dmy = DateTimeFormatter.ofPattern("dd.MM.yy")
    private val full = DateTimeFormatter.ofPattern("d MMMM yyyy")

    fun time(ts: String?): String = Time.parse(ts)?.atZone(ZoneId.systemDefault())?.format(hm).orEmpty()

    /** Время для списка чатов: сегодня — часы, в этом году — день.месяц, иначе с годом. */
    fun listTime(ts: String?, now: Instant = Instant.now()): String {
        val t = Time.parse(ts)?.atZone(ZoneId.systemDefault()) ?: return ""
        val today = now.atZone(ZoneId.systemDefault()).toLocalDate()
        return when {
            t.toLocalDate() == today -> t.format(hm)
            t.year == today.year -> t.format(dm)
            else -> t.format(dmy)
        }
    }

    fun day(ts: String?): LocalDate? = Time.parse(ts)?.atZone(ZoneId.systemDefault())?.toLocalDate()

    fun dayLabel(ctx: Context, d: LocalDate, today: LocalDate = LocalDate.now()): String = when (d) {
        today -> ctx.getString(R.string.today)
        today.minusDays(1) -> ctx.getString(R.string.yesterday)
        else -> d.format(full.withLocale(ctx.resources.configuration.locales[0]))
    }

    fun lastSeen(ctx: Context, ts: String?): String {
        if (Time.isOnline(ts)) return ctx.getString(R.string.online)
        val t = Time.parse(ts)?.atZone(ZoneId.systemDefault()) ?: return ""
        val today = LocalDate.now()
        val whenText = if (t.toLocalDate() == today) t.format(hm) else t.format(dmy) + " " + t.format(hm)
        return ctx.getString(R.string.last_seen, whenText)
    }

    fun duration(ms: Int?): String { val s = ((ms ?: 0) + 500) / 1000; return "%d:%02d".format(s / 60, s % 60) }

    fun size(bytes: Long?): String {
        val b = bytes ?: 0
        return when { b >= 1 shl 20 -> "%.1f MB".format(b / 1048576.0); b >= 1024 -> "%d KB".format(b / 1024); else -> "$b B" }
    }
}
