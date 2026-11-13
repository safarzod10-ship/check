package tj.payvand.app.ui.components

import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.compositionLocalOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import tj.payvand.app.ui.theme.Brand
import tj.payvand.app.ui.theme.pv
import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.sin

/** Включена ли анимация фона (настройка в профиле; выключение экономит батарею). */
val LocalAnimatedBackground = compositionLocalOf { true }

/**
 * Фирменный «живой» фон Payvan: медленно плывущее золотое сияние, отсветы цветов флага,
 * золотые ленты как на логотипе и силуэт гор внизу.
 * [intensity] — яркость (1 — экраны входа, ~0.5 — списки и чат, чтобы текст оставался читаемым).
 */
@Composable
fun LivingBackground(modifier: Modifier = Modifier, intensity: Float = 1f, mountains: Boolean = true, content: @Composable () -> Unit = {}) {
    val dark = pv.isDark
    val base = MaterialTheme.colorScheme.background
    val animated = LocalAnimatedBackground.current
    val phase = if (animated) {
        val t = rememberInfiniteTransition(label = "bg")
        val v by t.animateFloat(0f, 1f, infiniteRepeatable(tween(36_000, easing = LinearEasing), RepeatMode.Restart), label = "phase")
        v
    } else 0.18f
    val ridge = remember { Path() }
    val ribbon = remember { Path() }
    Box(modifier.fillMaxSize().background(base)) {
        Canvas(Modifier.fillMaxSize()) { drawScene(phase, intensity, dark, mountains, ridge, ribbon) }
        content()
    }
}

private fun DrawScope.drawScene(phase: Float, k: Float, dark: Boolean, mountains: Boolean, ridge: Path, ribbon: Path) {
    val w = size.width; val h = size.height
    val a = (phase * 2 * PI).toFloat()
    val glow = if (dark) 1f else 0.75f
    fun blob(color: Color, alpha: Float, cx: Float, cy: Float, r: Float) =
        drawCircle(Brush.radialGradient(listOf(color.copy(alpha = alpha * k * glow), Color.Transparent), Offset(cx, cy), r), r, Offset(cx, cy))

    // три плывущих пятна света: золото и цвета флага
    blob(Brand.Gold, 0.24f, w * (0.5f + 0.38f * cos(a)), h * (0.22f + 0.10f * sin(a * 2)), w * 0.95f)
    blob(Brand.FlagRed, 0.10f, w * (0.15f + 0.20f * sin(a + 1.3f)), h * (0.55f + 0.18f * cos(a)), w * 0.80f)
    blob(Brand.Emerald, 0.10f, w * (0.85f + 0.18f * cos(a + 2.1f)), h * (0.78f + 0.12f * sin(a)), w * 0.85f)

    // золотые ленты
    for (i in 0 until 3) {
        val p = a + i * 2.1f
        val y0 = h * (0.30f + 0.22f * i)
        ribbon.reset()
        ribbon.moveTo(-w * 0.1f, y0 + h * 0.05f * sin(p))
        ribbon.cubicTo(w * 0.25f, y0 - h * 0.10f * cos(p * 1f), w * 0.65f, y0 + h * 0.12f * sin(p + 1f), w * 1.1f, y0 - h * 0.06f * cos(p + 0.6f))
        val c = if (dark) Brand.GoldLight else Brand.GoldDeep
        drawPath(ribbon, Brush.horizontalGradient(listOf(Color.Transparent, c.copy(alpha = 0.34f * k), c.copy(alpha = 0.10f * k), Color.Transparent)),
            style = Stroke(width = (1.2f + i * 0.5f) * density, cap = StrokeCap.Round))
    }

    if (mountains) {
        // горный хребет — узнаваемый силуэт Таджикистана
        val pts = floatArrayOf(0f, .62f, .08f, .40f, .15f, .52f, .24f, .18f, .31f, .44f, .40f, .30f, .47f, .50f, .56f, .12f, .64f, .42f, .72f, .26f, .80f, .48f, .89f, .22f, 1f, .55f)
        val top = h * 0.80f; val amp = h * 0.16f
        ridge.reset(); ridge.moveTo(0f, h)
        var i = 0
        while (i < pts.size) { ridge.lineTo(w * pts[i], top + amp * pts[i + 1]); i += 2 }
        ridge.lineTo(w, h); ridge.close()
        val tone = if (dark) Color.White else Brand.GoldDeep
        drawPath(ridge, Brush.verticalGradient(listOf(tone.copy(alpha = 0.085f * k), Color.Transparent), top, h))
    }
}
