package tj.payvand.app.ui.theme

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Shapes
import androidx.compose.material3.Typography
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.Immutable
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

/** Палитра PAYVAND: ночная зелень гор и изумрудный акцент; красный и белый — из ленты логотипа. */
object Brand {
    val Emerald = Color(0xFF19E28A)
    val EmeraldDeep = Color(0xFF0AA867)
    val Mint = Color(0xFF7CF5C4)
    val Teal = Color(0xFF22D3C5)
    val Night = Color(0xFF050B09)
    val Night2 = Color(0xFF0A1410)
    val Night3 = Color(0xFF101C17)
    val Night4 = Color(0xFF16261F)
    val FlagRed = Color(0xFFE5383B)
    val Gold = Color(0xFFF2C14E)
    val Gradient = Brush.horizontalGradient(listOf(Color(0xFF12C777), Color(0xFF19E28A), Color(0xFF39EBA6)))
}

@Immutable
data class PayvandColors(
    val bubbleOut: Color, val bubbleIn: Color, val onBubbleOut: Color, val onBubbleIn: Color,
    val bubbleMeta: Color, val read: Color, val online: Color, val chatBackground: Color,
    val isDark: Boolean,
)

val LocalPayvandColors = staticCompositionLocalOf {
    PayvandColors(Color.Unspecified, Color.Unspecified, Color.Unspecified, Color.Unspecified, Color.Unspecified, Color.Unspecified, Color.Unspecified, Color.Unspecified, true)
}

private val DarkScheme = darkColorScheme(
    primary = Brand.Emerald, onPrimary = Color(0xFF00210F),
    primaryContainer = Color(0xFF0C3B29), onPrimaryContainer = Brand.Mint,
    secondary = Brand.Teal, onSecondary = Color(0xFF00201D),
    secondaryContainer = Color(0xFF12302B), onSecondaryContainer = Color(0xFFB5F5EC),
    tertiary = Brand.Gold, onTertiary = Color(0xFF2B1F00),
    background = Brand.Night, onBackground = Color(0xFFE9F3EE),
    surface = Brand.Night, onSurface = Color(0xFFE9F3EE),
    surfaceVariant = Brand.Night4, onSurfaceVariant = Color(0xFF93AAA0),
    surfaceContainerLowest = Color(0xFF030705), surfaceContainerLow = Brand.Night2,
    surfaceContainer = Brand.Night3, surfaceContainerHigh = Brand.Night4, surfaceContainerHighest = Color(0xFF1D3028),
    outline = Color(0xFF3A5247), outlineVariant = Color(0xFF1C2C25),
    error = Color(0xFFFF6B6B), onError = Color(0xFF3B0000), errorContainer = Color(0xFF4A1414), onErrorContainer = Color(0xFFFFD9D6),
)

private val LightScheme = lightColorScheme(
    primary = Color(0xFF00875A), onPrimary = Color.White,
    primaryContainer = Color(0xFFC9F7E0), onPrimaryContainer = Color(0xFF00301D),
    secondary = Color(0xFF00796F), onSecondary = Color.White,
    secondaryContainer = Color(0xFFD3F3EE), onSecondaryContainer = Color(0xFF00302B),
    tertiary = Color(0xFF8A6A00), onTertiary = Color.White,
    background = Color(0xFFF5FAF7), onBackground = Color(0xFF0D1814),
    surface = Color(0xFFF5FAF7), onSurface = Color(0xFF0D1814),
    surfaceVariant = Color(0xFFE2EDE7), onSurfaceVariant = Color(0xFF52655C),
    surfaceContainerLowest = Color.White, surfaceContainerLow = Color(0xFFFFFFFF),
    surfaceContainer = Color(0xFFEDF4F0), surfaceContainerHigh = Color(0xFFE5EEE9), surfaceContainerHighest = Color(0xFFDCE7E1),
    outline = Color(0xFF9DB0A6), outlineVariant = Color(0xFFD5E1DA),
    error = Color(0xFFC62828), onError = Color.White, errorContainer = Color(0xFFFFDAD6), onErrorContainer = Color(0xFF410002),
)

private val DarkExtra = PayvandColors(
    bubbleOut = Color(0xFF0D4A34), bubbleIn = Color(0xFF14211C), onBubbleOut = Color(0xFFEFFFF7), onBubbleIn = Color(0xFFE9F3EE),
    bubbleMeta = Color(0xFF8FB3A3), read = Brand.Emerald, online = Brand.Emerald, chatBackground = Color(0xFF060D0A), isDark = true,
)
private val LightExtra = PayvandColors(
    bubbleOut = Color(0xFFCFF7E2), bubbleIn = Color.White, onBubbleOut = Color(0xFF06271A), onBubbleIn = Color(0xFF0D1814),
    bubbleMeta = Color(0xFF5E7A6E), read = Color(0xFF00875A), online = Color(0xFF10B46F), chatBackground = Color(0xFFE9F2ED), isDark = false,
)

private val AppTypography = Typography().let { t ->
    t.copy(
        headlineMedium = t.headlineMedium.copy(fontWeight = FontWeight.Bold, letterSpacing = (-0.2).sp),
        headlineSmall = t.headlineSmall.copy(fontWeight = FontWeight.Bold),
        titleLarge = t.titleLarge.copy(fontWeight = FontWeight.SemiBold),
        titleMedium = t.titleMedium.copy(fontWeight = FontWeight.SemiBold),
        labelLarge = t.labelLarge.copy(fontWeight = FontWeight.SemiBold, fontSize = 15.sp),
        bodyLarge = TextStyle(fontSize = 16.sp, lineHeight = 22.sp),
    )
}

private val AppShapes = Shapes(
    extraSmall = RoundedCornerShape(8.dp), small = RoundedCornerShape(12.dp), medium = RoundedCornerShape(16.dp),
    large = RoundedCornerShape(22.dp), extraLarge = RoundedCornerShape(28.dp),
)

enum class ThemeMode { SYSTEM, DARK, LIGHT }

@Composable
fun PayvandTheme(mode: ThemeMode = ThemeMode.SYSTEM, content: @Composable () -> Unit) {
    val dark = when (mode) { ThemeMode.SYSTEM -> isSystemInDarkTheme(); ThemeMode.DARK -> true; ThemeMode.LIGHT -> false }
    CompositionLocalProvider(LocalPayvandColors provides if (dark) DarkExtra else LightExtra) {
        MaterialTheme(colorScheme = if (dark) DarkScheme else LightScheme, typography = AppTypography, shapes = AppShapes, content = content)
    }
}

val pv: PayvandColors @Composable get() = LocalPayvandColors.current
