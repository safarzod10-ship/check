package tj.payvand.app.ui.components

import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.CubicBezierEasing
import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Image
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.BlendMode
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import tj.payvand.app.R
import tj.payvand.app.ui.theme.Brand

/** Логотип Payvan (золотая «P» с флагом и горами). [shimmer] — бегущий блик по золоту. */
@Composable
fun PayvandMark(modifier: Modifier = Modifier, size: Dp = 96.dp, shimmer: Boolean = false) {
    val shape = RoundedCornerShape(size * 0.22f)
    val sweep = if (shimmer && LocalAnimatedBackground.current) {
        val t = rememberInfiniteTransition(label = "shimmer")
        val v by t.animateFloat(-0.6f, 1.6f, infiniteRepeatable(tween(3200, easing = LinearEasing), RepeatMode.Restart), label = "sweep")
        v
    } else null
    Image(
        painterResource(R.drawable.logo), contentDescription = "Payvan",
        modifier = modifier.size(size).clip(shape).border(1.dp, Brand.Gold.copy(alpha = 0.55f), shape).drawWithContent {
            drawContent()
            if (sweep != null) {
                val x = this.size.width * sweep
                drawRect(
                    Brush.linearGradient(listOf(Color.Transparent, Color.White.copy(alpha = 0.34f), Color.Transparent),
                        start = Offset(x - this.size.width * 0.25f, 0f), end = Offset(x + this.size.width * 0.25f, this.size.height)),
                    blendMode = BlendMode.Plus,
                )
            }
        },
    )
}

@Composable
fun Wordmark(modifier: Modifier = Modifier, fontSize: Int = 38) {
    Text("Payvan", modifier, style = TextStyle(brush = Brand.GoldText, fontSize = fontSize.sp, fontWeight = FontWeight.Black, fontStyle = FontStyle.Italic, letterSpacing = 0.5.sp))
}

@Composable
fun Slogan(modifier: Modifier = Modifier, fontSize: Int = 14) {
    Text(buildAnnotatedString {
        withStyle(SpanStyle(color = MaterialTheme.colorScheme.onBackground.copy(alpha = 0.85f))) { append("One World. One ") }
        withStyle(SpanStyle(color = MaterialTheme.colorScheme.primary)) { append("Connection.") }
    }, modifier, fontSize = fontSize.sp, letterSpacing = 0.6.sp)
}

/** Заставка: логотип «проявляется» из золотого свечения, по нему бежит блик, затем появляются название и слоган. */
@Composable
fun AnimatedBrand(modifier: Modifier = Modifier, animate: Boolean = true, markSize: Dp = 168.dp) {
    val appear = remember { Animatable(if (animate) 0f else 1f) }
    val text = remember { Animatable(if (animate) 0f else 1f) }
    LaunchedEffect(animate) {
        if (animate) {
            appear.animateTo(1f, tween(900, easing = CubicBezierEasing(0.2f, 0.9f, 0.2f, 1f)))
            text.animateTo(1f, tween(450))
        }
    }
    val pulse = if (LocalAnimatedBackground.current) {
        val t = rememberInfiniteTransition(label = "halo")
        val v by t.animateFloat(0.75f, 1f, infiniteRepeatable(tween(1800), RepeatMode.Reverse), label = "pulse")
        v
    } else 0.9f
    Column(modifier, horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.Center) {
        Box(contentAlignment = Alignment.Center, modifier = Modifier.drawBehind {
            val r = size.minDimension * 0.95f * pulse
            drawCircle(Brush.radialGradient(listOf(Brand.Gold.copy(alpha = 0.42f * appear.value), Color.Transparent), center, r), r)
        }) {
            PayvandMark(Modifier.graphicsLayer { alpha = appear.value; val s = 0.72f + 0.28f * appear.value; scaleX = s; scaleY = s }, size = markSize, shimmer = true)
        }
        Spacer(Modifier.height(22.dp))
        Column(Modifier.graphicsLayer { alpha = text.value; translationY = (1f - text.value) * 28f }, horizontalAlignment = Alignment.CenterHorizontally) {
            Wordmark()
            Spacer(Modifier.height(4.dp))
            Slogan()
        }
    }
}
