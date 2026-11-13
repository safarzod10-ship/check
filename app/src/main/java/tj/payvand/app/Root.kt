package tj.payvand.app

import android.Manifest
import android.app.Activity
import android.os.Build
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.animation.Crossfade
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInHorizontally
import androidx.compose.animation.slideOutHorizontally
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.SideEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import androidx.core.view.WindowCompat
import androidx.lifecycle.viewmodel.compose.viewModel
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.rememberNavController
import kotlinx.coroutines.delay
import tj.payvand.app.ui.auth.AuthFlow
import tj.payvand.app.ui.auth.AuthViewModel
import tj.payvand.app.ui.auth.BrandBackground
import tj.payvand.app.ui.auth.LanguageScreen
import tj.payvand.app.ui.auth.ServerSetupScreen
import tj.payvand.app.ui.auth.applyLanguage
import tj.payvand.app.ui.auth.currentLanguageTag
import tj.payvand.app.ui.chat.ChatScreen
import tj.payvand.app.ui.chat.ChatViewModel
import tj.payvand.app.ui.community.ConversationInfoScreen
import tj.payvand.app.ui.community.CreateConversationScreen
import tj.payvand.app.ui.components.AnimatedBrand
import tj.payvand.app.ui.home.HomeNav
import tj.payvand.app.ui.home.HomeScreen
import tj.payvand.app.ui.profile.BlockedScreen
import tj.payvand.app.ui.profile.ProfileEditor
import tj.payvand.app.ui.theme.PayvandTheme
import tj.payvand.app.ui.theme.pv
import tj.payvand.core.AuthState
import tj.payvand.core.BackendConfig
import tj.payvand.core.ConversationType

@Composable
fun PayvandRoot(container: AppContainer) {
    val theme by container.prefs.theme.collectAsState()
    PayvandTheme(theme) {
        val dark = pv.isDark
        val view = LocalView.current
        SideEffect {
            (view.context as? Activity)?.window?.let { w ->
                WindowCompat.getInsetsController(w, view).apply { isAppearanceLightStatusBars = !dark; isAppearanceLightNavigationBars = !dark }
            }
        }
        val langChosen by container.prefs.languageChosen.collectAsState()
        val session by container.session.collectAsState()
        var splashDone by rememberSaveable { mutableStateOf(false) }
        LaunchedEffect(Unit) { if (!splashDone) { delay(2000); splashDone = true } }
        var serverError by rememberSaveable { mutableStateOf(false) }

        Box(Modifier.fillMaxSize().background(MaterialTheme.colorScheme.background)) {
            val stage = when { !splashDone -> 0; !langChosen -> 1; session == null -> 2; else -> 3 }
            Crossfade(stage, label = "root") { st ->
                when (st) {
                    0 -> Splash(animate = true)
                    1 -> LanguageScreen(currentLanguageTag(), onSelect = { applyLanguage(it) }, onContinue = { applyLanguage(currentLanguageTag()); container.prefs.setLanguageChosen() })
                    2 -> ServerSetupScreen("https://", serverError, onConnect = { url, key ->
                        val ok = Regex("^https?://[^\\s/]+(:\\d+)?/?$").matches(url) && !key.contains(" ") && !isServiceRole(key)
                        serverError = !ok
                        if (ok) { val cfg = BackendConfig(url, key); container.prefs.setServer(cfg); container.connect(cfg) }
                    })
                    else -> session?.let { SessionRoot(it, container) }
                }
            }
        }
    }
}

/** Не даём по ошибке вставить секретный ключ администратора. */
private fun isServiceRole(key: String): Boolean = runCatching {
    key.startsWith("sb_secret_") || String(android.util.Base64.decode(key.split(".")[1], android.util.Base64.URL_SAFE)).contains("service_role")
}.getOrDefault(false)

@Composable
fun Splash(animate: Boolean) {
    BrandBackground {
        Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
            AnimatedBrand(animate = animate, onDark = pv.isDark)
            Column(Modifier.align(Alignment.BottomCenter).padding(bottom = 72.dp), horizontalAlignment = Alignment.CenterHorizontally) {
                CircularProgressIndicator(Modifier.size(26.dp), strokeWidth = 2.5.dp)
                Spacer(Modifier.height(12.dp))
                Text(stringResource(R.string.loading), style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
    }
}

@Composable
private fun SessionRoot(session: ChatSession, container: AppContainer) {
    val auth by session.api.authState.collectAsState()
    val authVm: AuthViewModel = viewModel(key = "auth-" + System.identityHashCode(session)) { AuthViewModel(session.api) }
    val changeServer: (() -> Unit)? = if (container.hasBuiltInServer) null else ({ container.disconnectServer() })
    when (auth) {
        AuthState.Loading -> Splash(animate = false)
        AuthState.SignedOut -> {
            val ui by authVm.ui.collectAsState()
            AuthFlow(ui, authVm, changeServer)
        }
        is AuthState.SignedIn -> {
            LaunchedEffect(Unit) { authVm.reset() }
            val me by session.me.collectAsState()
            val meLoaded by session.meLoaded.collectAsState()
            when {
                !meLoaded -> Splash(animate = false)
                me?.isComplete != true -> ProfileEditor(session, firstTime = true, onDone = {})
                else -> MainNav(session, container, changeServer)
            }
        }
    }
}

@Composable
private fun MainNav(session: ChatSession, container: AppContainer, changeServer: (() -> Unit)?) {
    val nav = rememberNavController()
    val pending by container.pendingOpen.collectAsState()
    LaunchedEffect(pending) {
        pending?.let { id -> container.pendingOpen.value = null; nav.navigate("chat/$id") { launchSingleTop = true } }
    }
    if (Build.VERSION.SDK_INT >= 33) {
        val ask = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) {}
        var asked by rememberSaveable { mutableStateOf(false) }
        LaunchedEffect(Unit) { if (!asked) { asked = true; ask.launch(Manifest.permission.POST_NOTIFICATIONS) } }
    }
    val openChat: (String) -> Unit = { id -> nav.navigate("chat/$id") { launchSingleTop = true } }
    NavHost(
        nav, startDestination = "home",
        enterTransition = { slideInHorizontally { it / 5 } + fadeIn() }, exitTransition = { fadeOut() },
        popEnterTransition = { fadeIn() }, popExitTransition = { slideOutHorizontally { it / 5 } + fadeOut() },
    ) {
        composable("home") {
            HomeScreen(session, HomeNav(openChat, { nav.navigate("create/${it.wire}") }, { nav.navigate("editProfile") }, { nav.navigate("blocked") }, changeServer))
        }
        composable("chat/{id}") { entry ->
            val id = entry.arguments?.getString("id").orEmpty()
            val vm: ChatViewModel = viewModel(key = "chat-$id") { ChatViewModel(session, container, id) }
            ChatScreen(session, container, vm, onBack = { nav.popBackStack() }, onInfo = { nav.navigate("info/$id") })
        }
        composable("create/{type}") { entry ->
            val type = ConversationType.of(entry.arguments?.getString("type").orEmpty())
            CreateConversationScreen(session, type, onCreated = { id -> nav.popBackStack(); openChat(id) }, onBack = { nav.popBackStack() })
        }
        composable("info/{id}") { entry ->
            ConversationInfoScreen(session, entry.arguments?.getString("id").orEmpty(), openChat = { id -> nav.popBackStack("home", false); openChat(id) },
                onBack = { nav.popBackStack() }, onLeft = { nav.popBackStack("home", false) })
        }
        composable("editProfile") { ProfileEditor(session, firstTime = false, onDone = { nav.popBackStack() }, onBack = { nav.popBackStack() }) }
        composable("blocked") { BlockedScreen(session) { nav.popBackStack() } }
    }
}
