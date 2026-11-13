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

/** Палитра Payvan: чёрный бархат и золото логотипа; красный и зелёный — из флага Таджикистана. */
object Brand {
    val Gold = Color(0xFFE9B955)
    val GoldLight = Color(0xFFFFE6A3)
    val GoldDeep = Color(0xFFB07F25)
    val OnGold = Color(0xFF1C1300)
    val Emerald = Color(0xFF1FCB7A)
    val FlagRed = Color(0xFFE5383B)
    val Night = Color(0xFF040404)
    val Night2 = Color(0xFF0B0B0D)
    val Night3 = Color(0xFF131316)
    val Night4 = Color(0xFF1B1B20)
    val Gradient = Brush.linearGradient(listOf(Color(0xFFC8932F), Color(0xFFF2CE78), Color(0xFFFFE9B0), Color(0xFFE2AE4A)))
    val GoldText = Brush.linearGradient(listOf(Color(0xFFFFF1C9), Color(0xFFE9B955), Color(0xFFB07F25)))
}

@Immutable
data class PayvandColors(
    val bubbleOut: Brush, val bubbleIn: Color, val bubbleInBorder: Color, val onBubbleOut: Color, val onBubbleIn: Color,
    val bubbleMeta: Color, val read: Color, val readOnBubble: Color, val online: Color, val chatBackground: Color,
    val glass: Color, val isDark: Boolean,
)

val LocalPayvandColors = staticCompositionLocalOf<PayvandColors> { error("PayvandTheme is missing") }

private val DarkScheme = darkColorScheme(
    primary = Brand.Gold, onPrimary = Brand.OnGold,
    primaryContainer = Color(0xFF2E2410), onPrimaryContainer = Brand.GoldLight,
    secondary = Brand.Emerald, onSecondary = Color(0xFF00210F),
    secondaryContainer = Color(0xFF0F2A1D), onSecondaryContainer = Color(0xFFB9F3D5),
    tertiary = Brand.FlagRed, onTertiary = Color.White,
    background = Brand.Night, onBackground = Color(0xFFF4EFE3),
    surface = Brand.Night, onSurface = Color(0xFFF4EFE3),
    surfaceVariant = Brand.Night4, onSurfaceVariant = Color(0xFFA39C8C),
    surfaceContainerLowest = Color(0xFF000000), surfaceContainerLow = Brand.Night2,
    surfaceContainer = Brand.Night3, surfaceContainerHigh = Brand.Night4, surfaceContainerHighest = Color(0xFF25252B),
    outline = Color(0xFF5C5340), outlineVariant = Color(0xFF2A2720),
    error = Color(0xFFFF6B6B), onError = Color(0xFF3B0000), errorContainer = Color(0xFF4A1414), onErrorContainer = Color(0xFFFFD9D6),
)

private val LightScheme = lightColorScheme(
    primary = Color(0xFF8A6100), onPrimary = Color.White,
    primaryContainer = Color(0xFFFBE7B8), onPrimaryContainer = Color(0xFF2B1D00),
    secondary = Color(0xFF0B7A49), onSecondary = Color.White,
    secondaryContainer = Color(0xFFD2F2E0), onSecondaryContainer = Color(0xFF00301B),
    tertiary = Color(0xFFC62828), onTertiary = Color.White,
    background = Color(0xFFFBF7EE), onBackground = Color(0xFF17130A),
    surface = Color(0xFFFBF7EE), onSurface = Color(0xFF17130A),
    surfaceVariant = Color(0xFFEFE8D8), onSurfaceVariant = Color(0xFF6A6252),
    surfaceContainerLowest = Color.White, surfaceContainerLow = Color(0xFFFFFDF8),
    surfaceContainer = Color(0xFFF4EEDF), surfaceContainerHigh = Color(0xFFEDE6D4), surfaceContainerHighest = Color(0xFFE5DDC9),
    outline = Color(0xFFB3A88F), outlineVariant = Color(0xFFE2D9C4),
    error = Color(0xFFC62828), onError = Color.White, errorContainer = Color(0xFFFFDAD6), onErrorContainer = Color(0xFF410002),
)

private val DarkExtra = PayvandColors(
    bubbleOut = Brush.linearGradient(listOf(Color(0xFFF5D689), Color(0xFFDDA945))), bubbleIn = Color(0xE616161A), bubbleInBorder = Color(0x33E9B955),
    onBubbleOut = Brand.OnGold, onBubbleIn = Color(0xFFF4EFE3), bubbleMeta = Color(0xFF9B9484),
    read = Brand.Emerald, readOnBubble = Color(0xFF0A6B3F), online = Brand.Emerald, chatBackground = Color(0xFF040404),
    glass = Color(0xD9101013), isDark = true,
)
private val LightExtra = PayvandColors(
    bubbleOut = Brush.linearGradient(listOf(Color(0xFFF7DC98), Color(0xFFE6B95A))), bubbleIn = Color(0xF2FFFFFF), bubbleInBorder = Color(0x33B07F25),
    onBubbleOut = Brand.OnGold, onBubbleIn = Color(0xFF17130A), bubbleMeta = Color(0xFF7A715F),
    read = Color(0xFF0B7A49), readOnBubble = Color(0xFF0A6B3F), online = Color(0xFF10B46F), chatBackground = Color(0xFFF6F0E2),
    glass = Color(0xE6FFFDF8), isDark = false,
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
