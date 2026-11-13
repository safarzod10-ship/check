package tj.payvand.app.ui.components

import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.CubicBezierEasing
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.size
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.PathMeasure
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import tj.payvand.app.ui.theme.Brand

/**
 * Знак PAYVAND: буква «P» и лента цветов флага Таджикистана («пайванд» — связь, узы).
 * Рисуется кодом, чтобы линии можно было «прорисовывать» в анимации запуска.
 * [progress] 0..1 — доля прорисовки (1 = готовый знак).
 */
@Composable
fun PayvandMark(modifier: Modifier = Modifier, size: Dp = 96.dp, progress: Float = 1f, onDark: Boolean = true) {
    Canvas(modifier.size(size)) { drawMark(progress, onDark) }
}

private fun DrawScope.drawMark(progress: Float, onDark: Boolean) {
    // система координат знака 0..60
    val u = this.size.minDimension / 60f
    fun p(x: Float, y: Float) = Offset(x * u, y * u)
    val white = if (onDark) Color.White else Color(0xFF0D1814)
    val bowl = Path().apply {
        moveTo(16f * u, 41f * u); lineTo(16f * u, 9f * u); lineTo(35f * u, 9f * u)
        arcTo(Rect(p(23f, 9f), Size(24f * u, 24f * u)), -90f, 180f, false)
        lineTo(26f * u, 33f * u)
    }
    val stroke = Stroke(width = 8f * u, cap = StrokeCap.Round, join = StrokeJoin.Round)
    val pm = PathMeasure().apply { setPath(bowl, false) }
    val seg = Path()
    val a = (progress / 0.6f).coerceIn(0f, 1f)
    pm.getSegment(0f, pm.length * a, seg, true)
    drawPath(seg, Brush.linearGradient(listOf(white, if (onDark) Brand.Mint else Brand.EmeraldDeep), p(12f, 6f), p(52f, 38f)), style = stroke)

    val colors = listOf(Brand.FlagRed, if (onDark) Color.White else Color(0xFFDDE7E1), Brand.Emerald)
    colors.forEachIndexed { i, c ->
        val t = ((progress - 0.45f - i * 0.08f) / 0.4f).coerceIn(0f, 1f)
        if (t > 0f) {
            val dy = i * 4.6f
            val ribbon = Path().apply {
                moveTo(6f * u, (49f + dy) * u)
                cubicTo(22f * u, (51f + dy) * u, 34f * u, (45f + dy) * u, 54f * u, (40f + dy) * u)
            }
            val m = PathMeasure().apply { setPath(ribbon, false) }
            val s = Path(); m.getSegment(0f, m.length * t, s, true)
            drawPath(s, c, style = Stroke(width = 3.8f * u, cap = StrokeCap.Round))
        }
    }
}

@Composable
fun Wordmark(modifier: Modifier = Modifier, fontSize: Int = 34, color: Color = MaterialTheme.colorScheme.onBackground) {
    Text("PAYVAND", modifier, color = color, fontSize = fontSize.sp, fontWeight = FontWeight.Black, letterSpacing = (fontSize / 9f).sp)
}

@Composable
fun Slogan(modifier: Modifier = Modifier, fontSize: Int = 14) {
    Text(buildAnnotatedString {
        withStyle(SpanStyle(color = MaterialTheme.colorScheme.onBackground.copy(alpha = 0.85f))) { append("One World. One ") }
        withStyle(SpanStyle(color = MaterialTheme.colorScheme.primary)) { append("Connection.") }
    }, modifier, fontSize = fontSize.sp, letterSpacing = 0.6.sp)
}

/** Анимированная заставка: знак прорисовывается, затем проявляются название и слоган. */
@Composable
fun AnimatedBrand(modifier: Modifier = Modifier, animate: Boolean = true, markSize: Dp = 128.dp, onDark: Boolean = true) {
    val draw = remember { Animatable(if (animate) 0f else 1f) }
    val text = remember { Animatable(if (animate) 0f else 1f) }
    LaunchedEffect(animate) {
        if (animate) {
            draw.animateTo(1f, tween(1100, easing = CubicBezierEasing(0.2f, 0.8f, 0.2f, 1f)))
            text.animateTo(1f, tween(450))
        }
    }
    Column(modifier, horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.Center) {
        PayvandMark(size = markSize, progress = draw.value, onDark = onDark)
        Spacer(Modifier.height(20.dp))
        Column(Modifier.graphicsLayer { alpha = text.value; translationY = (1f - text.value) * 24f }, horizontalAlignment = Alignment.CenterHorizontally) {
            Wordmark()
            Spacer(Modifier.height(6.dp))
            Slogan()
        }
    }
}
