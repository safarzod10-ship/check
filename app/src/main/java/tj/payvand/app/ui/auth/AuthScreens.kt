package tj.payvand.app.ui.auth

import androidx.activity.compose.BackHandler
import androidx.appcompat.app.AppCompatDelegate
import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInHorizontally
import androidx.compose.animation.slideOutHorizontally
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
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
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.ArrowForward
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Language
import androidx.compose.material.icons.filled.Visibility
import androidx.compose.material.icons.filled.VisibilityOff
import androidx.compose.material.icons.outlined.Info
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.input.VisualTransformation
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.os.LocaleListCompat
import tj.payvand.app.R
import tj.payvand.app.ui.components.ErrorText
import tj.payvand.app.ui.components.PayvandMark
import tj.payvand.app.ui.components.PrimaryButton
import tj.payvand.app.ui.components.PvField
import tj.payvand.app.ui.components.SecondaryButton
import tj.payvand.app.ui.components.Slogan
import tj.payvand.app.ui.components.Wordmark
import tj.payvand.app.ui.components.errorMessage
import tj.payvand.app.ui.theme.Brand
import tj.payvand.app.ui.theme.pv

data class AppLanguage(val tag: String, val native: String, val latin: String)

val Languages = listOf(
    AppLanguage("tg", "Тоҷикӣ", "Tajik"),
    AppLanguage("ru", "Русский", "Russian"),
    AppLanguage("en", "English", "English"),
)

fun currentLanguageTag(): String {
    val tag = AppCompatDelegate.getApplicationLocales().get(0)?.language ?: java.util.Locale.getDefault().language
    return Languages.firstOrNull { it.tag == tag }?.tag ?: "en"
}

fun applyLanguage(tag: String) = AppCompatDelegate.setApplicationLocales(LocaleListCompat.forLanguageTags(tag))

/** Фирменный фон: ночной градиент с изумрудным свечением. */
@Composable
fun BrandBackground(content: @Composable () -> Unit) {
    val dark = pv.isDark
    Box(
        Modifier.fillMaxSize().background(MaterialTheme.colorScheme.background).background(
            Brush.radialGradient(
                listOf(Brand.Emerald.copy(alpha = if (dark) 0.16f else 0.14f), Color.Transparent),
                center = androidx.compose.ui.geometry.Offset(200f, 250f), radius = 1100f,
            )
        )
    ) { content() }
}

/** Первый запуск: выбор языка. Названия языков всегда показаны на самих этих языках. */
@Composable
fun LanguageScreen(selected: String, onSelect: (String) -> Unit, onContinue: () -> Unit) {
    BrandBackground {
        Column(Modifier.fillMaxSize().systemBarsPadding().padding(24.dp), horizontalAlignment = Alignment.CenterHorizontally) {
            Spacer(Modifier.height(36.dp))
            PayvandMark(size = 84.dp, onDark = pv.isDark)
            Spacer(Modifier.height(14.dp))
            Wordmark(fontSize = 28)
            Spacer(Modifier.height(36.dp))
            Text("Забонро интихоб кунед", style = MaterialTheme.typography.titleMedium)
            Text("Выберите язык · Choose your language", style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
            Spacer(Modifier.height(20.dp))
            Languages.forEach { lang ->
                val on = lang.tag == selected
                Surface(
                    onClick = { onSelect(lang.tag) }, shape = RoundedCornerShape(18.dp),
                    color = if (on) MaterialTheme.colorScheme.primaryContainer else MaterialTheme.colorScheme.surfaceContainer,
                    border = if (on) androidx.compose.foundation.BorderStroke(1.5.dp, MaterialTheme.colorScheme.primary) else null,
                    modifier = Modifier.fillMaxWidth().padding(vertical = 6.dp),
                ) {
                    Row(Modifier.padding(horizontal = 18.dp, vertical = 16.dp), verticalAlignment = Alignment.CenterVertically) {
                        Column(Modifier.weight(1f)) {
                            Text(lang.native, style = MaterialTheme.typography.titleMedium)
                            Text(lang.latin, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                        }
                        if (on) Icon(Icons.Filled.Check, null, tint = MaterialTheme.colorScheme.primary)
                    }
                }
            }
            Spacer(Modifier.weight(1f))
            PrimaryButton(stringResource(R.string.continue_), onContinue, icon = Icons.AutoMirrored.Filled.ArrowForward)
        }
    }
}

@Composable
private fun LanguageChip(modifier: Modifier = Modifier) {
    var open by remember { mutableStateOf(false) }
    val cur = Languages.first { it.tag == currentLanguageTag() }
    Box(modifier) {
        Row(Modifier.clip(RoundedCornerShape(50)).clickable { open = true }.padding(horizontal = 12.dp, vertical = 8.dp), verticalAlignment = Alignment.CenterVertically) {
            Icon(Icons.Filled.Language, null, Modifier.size(18.dp), tint = MaterialTheme.colorScheme.onSurfaceVariant)
            Spacer(Modifier.width(6.dp))
            Text(cur.native, style = MaterialTheme.typography.labelLarge, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        DropdownMenu(open, { open = false }) {
            Languages.forEach { l -> DropdownMenuItem(text = { Text(l.native) }, onClick = { open = false; applyLanguage(l.tag) }) }
        }
    }
}

@Composable
fun AuthFlow(ui: AuthUi, vm: AuthViewModel, onChangeServer: (() -> Unit)?) {
    BackHandler(enabled = ui.step != AuthStep.WELCOME) { vm.back() }
    BrandBackground {
        AnimatedContent(
            targetState = ui.step,
            transitionSpec = {
                val dir = if (targetState.ordinal >= initialState.ordinal) 1 else -1
                (slideInHorizontally { it / 4 * dir } + fadeIn()) togetherWith (slideOutHorizontally { -it / 4 * dir } + fadeOut())
            },
            label = "auth",
        ) { step ->
            when (step) {
                AuthStep.WELCOME -> WelcomeScreen({ vm.go(AuthStep.SIGN_IN) }, { vm.go(AuthStep.SIGN_UP) }, onChangeServer)
                else -> FormScreen(step, ui, vm)
            }
        }
    }
}

@Composable
fun WelcomeScreen(onSignIn: () -> Unit, onSignUp: () -> Unit, onChangeServer: (() -> Unit)?) {
    Column(Modifier.fillMaxSize().systemBarsPadding().padding(horizontal = 24.dp, vertical = 12.dp), horizontalAlignment = Alignment.CenterHorizontally) {
        LanguageChip(Modifier.align(Alignment.End))
        Spacer(Modifier.weight(0.6f))
        Text(stringResource(R.string.welcome_title), style = MaterialTheme.typography.headlineMedium, textAlign = TextAlign.Center)
        Spacer(Modifier.height(8.dp))
        Text(stringResource(R.string.tagline), style = MaterialTheme.typography.bodyLarge, color = MaterialTheme.colorScheme.onSurfaceVariant, textAlign = TextAlign.Center)
        Spacer(Modifier.height(36.dp))
        PayvandMark(size = 132.dp, onDark = pv.isDark)
        Spacer(Modifier.height(18.dp))
        Slogan()
        Spacer(Modifier.weight(1f))
        PrimaryButton(stringResource(R.string.sign_in), onSignIn, icon = Icons.AutoMirrored.Filled.ArrowForward)
        Spacer(Modifier.height(12.dp))
        SecondaryButton(stringResource(R.string.create_account), onSignUp)
        Spacer(Modifier.height(18.dp))
        Text(stringResource(R.string.terms_note), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant, textAlign = TextAlign.Center)
        if (onChangeServer != null) TextButton(onClick = onChangeServer) { Text(stringResource(R.string.change_server), style = MaterialTheme.typography.bodySmall) }
        else Spacer(Modifier.height(12.dp))
    }
}

@Composable
private fun FormScreen(step: AuthStep, ui: AuthUi, vm: AuthViewModel) {
    val ctx = LocalContext.current
    var showPassword by remember { mutableStateOf(false) }
    Column(Modifier.fillMaxSize().systemBarsPadding().imePadding().verticalScroll(rememberScrollState()).padding(horizontal = 24.dp)) {
        IconButton(onClick = { vm.back() }, Modifier.padding(top = 4.dp)) { Icon(Icons.AutoMirrored.Filled.ArrowBack, stringResource(R.string.back)) }
        Spacer(Modifier.height(8.dp))
        PayvandMark(size = 56.dp, onDark = pv.isDark)
        Spacer(Modifier.height(16.dp))
        val (title, sub) = when (step) {
            AuthStep.SIGN_IN -> stringResource(R.string.sign_in) to stringResource(R.string.tagline)
            AuthStep.SIGN_UP -> stringResource(R.string.create_account) to stringResource(R.string.signup_sub)
            AuthStep.SIGN_UP_CODE, AuthStep.RECOVERY_CODE -> stringResource(R.string.code_title) to stringResource(R.string.code_sub, ui.email)
            else -> stringResource(R.string.recovery_title) to stringResource(R.string.recovery_sub)
        }
        Text(title, style = MaterialTheme.typography.headlineMedium)
        Spacer(Modifier.height(6.dp))
        Text(sub, style = MaterialTheme.typography.bodyLarge, color = MaterialTheme.colorScheme.onSurfaceVariant)
        Spacer(Modifier.height(24.dp))

        val passwordField: @Composable (String, () -> Unit) -> Unit = { label, onDone ->
            PvField(
                ui.password, vm::password, label, supporting = if (step != AuthStep.SIGN_IN) stringResource(R.string.password_hint) else null,
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Password, imeAction = ImeAction.Done),
                keyboardActions = KeyboardActions(onDone = { onDone() }),
                visualTransformation = if (showPassword) VisualTransformation.None else PasswordVisualTransformation(),
                trailing = { IconButton(onClick = { showPassword = !showPassword }) { Icon(if (showPassword) Icons.Filled.VisibilityOff else Icons.Filled.Visibility, null) } },
            )
        }
        val emailField: @Composable (ImeAction, () -> Unit) -> Unit = { action, onDone ->
            PvField(ui.email, vm::email, stringResource(R.string.email),
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Email, imeAction = action), keyboardActions = KeyboardActions(onDone = { onDone() }))
        }
        val codeField: @Composable () -> Unit = {
            PvField(ui.code, vm::code, stringResource(R.string.code), keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.NumberPassword, imeAction = ImeAction.Next))
        }
        val resend: @Composable () -> Unit = {
            TextButton(onClick = vm::resend, enabled = ui.resendIn == 0 && !ui.loading, modifier = Modifier.fillMaxWidth()) {
                Text(if (ui.resendIn > 0) stringResource(R.string.resend_in, ui.resendIn) else stringResource(R.string.resend_code))
            }
        }

        when (step) {
            AuthStep.SIGN_IN -> {
                emailField(ImeAction.Next) {}
                Spacer(Modifier.height(12.dp))
                passwordField(stringResource(R.string.password), vm::signIn)
                TextButton(onClick = { vm.go(AuthStep.RECOVERY) }, Modifier.align(Alignment.End)) { Text(stringResource(R.string.forgot_password)) }
                ErrorText(ui.error?.let { errorMessage(ctx, it) })
                Spacer(Modifier.height(16.dp))
                PrimaryButton(stringResource(R.string.sign_in), vm::signIn, loading = ui.loading, enabled = ui.email.isNotBlank() && ui.password.isNotEmpty())
                TextButton(onClick = { vm.go(AuthStep.SIGN_UP) }, Modifier.fillMaxWidth()) { Text(stringResource(R.string.create_account)) }
            }
            AuthStep.SIGN_UP -> {
                emailField(ImeAction.Next) {}
                Spacer(Modifier.height(12.dp))
                passwordField(stringResource(R.string.password), vm::signUp)
                Spacer(Modifier.height(8.dp))
                Surface(shape = RoundedCornerShape(14.dp), color = MaterialTheme.colorScheme.surfaceContainer) {
                    Row(Modifier.padding(12.dp)) {
                        Icon(Icons.Outlined.Info, null, Modifier.size(18.dp), tint = MaterialTheme.colorScheme.primary)
                        Spacer(Modifier.width(10.dp))
                        Text(stringResource(R.string.phone_notice), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                }
                ErrorText(ui.error?.let { errorMessage(ctx, it) })
                Spacer(Modifier.height(16.dp))
                PrimaryButton(stringResource(R.string.continue_), vm::signUp, loading = ui.loading, enabled = ui.email.isNotBlank() && ui.password.isNotEmpty())
            }
            AuthStep.SIGN_UP_CODE -> {
                codeField()
                ErrorText(ui.error?.let { errorMessage(ctx, it) })
                Spacer(Modifier.height(16.dp))
                PrimaryButton(stringResource(R.string.confirm), vm::confirmSignUp, loading = ui.loading, enabled = ui.code.length == 6)
                resend()
            }
            AuthStep.RECOVERY -> {
                emailField(ImeAction.Done, vm::requestRecovery)
                ErrorText(ui.error?.let { errorMessage(ctx, it) })
                Spacer(Modifier.height(16.dp))
                PrimaryButton(stringResource(R.string.send_code), vm::requestRecovery, loading = ui.loading, enabled = ui.email.isNotBlank())
            }
            AuthStep.RECOVERY_CODE -> {
                codeField()
                Spacer(Modifier.height(12.dp))
                passwordField(stringResource(R.string.new_password), vm::confirmRecovery)
                ErrorText(ui.error?.let { errorMessage(ctx, it) })
                Spacer(Modifier.height(16.dp))
                PrimaryButton(stringResource(R.string.save), vm::confirmRecovery, loading = ui.loading, enabled = ui.code.length == 6 && ui.password.isNotEmpty())
                resend()
            }
            else -> {}
        }
        Spacer(Modifier.height(24.dp))
    }
}

/** Экран подключения к серверу — показывается, только если адрес сервера не встроен в сборку. */
@Composable
fun ServerSetupScreen(initialUrl: String, error: Boolean, onConnect: (String, String) -> Unit, onBack: (() -> Unit)? = null) {
    var url by remember { mutableStateOf(initialUrl) }
    var key by remember { mutableStateOf("") }
    BrandBackground {
        Column(Modifier.fillMaxSize().systemBarsPadding().imePadding().verticalScroll(rememberScrollState()).padding(24.dp)) {
            if (onBack != null) IconButton(onClick = onBack) { Icon(Icons.AutoMirrored.Filled.ArrowBack, stringResource(R.string.back)) }
            Spacer(Modifier.height(12.dp))
            PayvandMark(size = 56.dp, onDark = pv.isDark)
            Spacer(Modifier.height(16.dp))
            Text(stringResource(R.string.server_title), style = MaterialTheme.typography.headlineMedium)
            Spacer(Modifier.height(6.dp))
            Text(stringResource(R.string.server_sub), style = MaterialTheme.typography.bodyLarge, color = MaterialTheme.colorScheme.onSurfaceVariant)
            Spacer(Modifier.height(24.dp))
            PvField(url, { url = it.trim() }, stringResource(R.string.server_url), keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Uri, imeAction = ImeAction.Next))
            Spacer(Modifier.height(12.dp))
            PvField(key, { key = it.trim() }, stringResource(R.string.server_key), supporting = stringResource(R.string.server_warning), singleLine = false)
            if (error) ErrorText(stringResource(R.string.server_invalid))
            Spacer(Modifier.height(16.dp))
            PrimaryButton(stringResource(R.string.connect), { onConnect(url, key) }, enabled = url.isNotBlank() && key.length > 20)
        }
    }
}
