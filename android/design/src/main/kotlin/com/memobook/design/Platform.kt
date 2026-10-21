package com.memobook.design

import android.provider.Settings
import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.text.BasicText
import androidx.compose.foundation.text.TextAutoSize
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.dropShadow
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.rotate
import androidx.compose.ui.graphics.shadow.Shadow
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.DpOffset
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

// Ce que SwiftUI donne d'office et que Compose Foundation n'a pas, écrit une
// fois ici pour que les composants `Brand…` se portent ligne à ligne :
// `Text`, `@ScaledMetric`, `isAccessibilitySize`, `accessibilityReduceMotion`,
// `ProgressView`, `.shadow`. Rien ici n'a de jumeau dans `MemoBookDesign` — ce
// sont les pièces du système, pas de la marque.

/**
 * Le texte de l'app. L'équivalent du `Text` de SwiftUI : Compose Foundation
 * n'a que `BasicText`, et Material, qu'on n'emploie pas, porte le sien.
 *
 * @param minimumScaleFactor le `minimumScaleFactor` de SwiftUI : sous 1, le
 *   texte rétrécit jusqu'à cette part de sa taille plutôt que d'être rogné.
 */
@Composable
fun BrandText(
    text: String,
    style: TextStyle,
    modifier: Modifier = Modifier,
    color: Color = MemoBookColor.ink,
    textAlign: TextAlign? = null,
    maxLines: Int = Int.MAX_VALUE,
    minimumScaleFactor: Float = 1f,
) {
    val resolved = style.copy(color = color, textAlign = textAlign ?: style.textAlign)
    BasicText(
        text = text,
        modifier = modifier,
        style = resolved,
        maxLines = maxLines,
        overflow = TextOverflow.Ellipsis,
        autoSize = if (minimumScaleFactor < 1f && style.fontSize.isSp) {
            TextAutoSize.StepBased(
                minFontSize = (style.fontSize.value * minimumScaleFactor).sp,
                maxFontSize = style.fontSize,
                stepSize = 0.5.sp,
            )
        } else {
            null
        },
    )
}

/**
 * `@ScaledMetric` : une mesure qui grandit avec la taille de police du
 * téléphone, comme le texte. Elle suit la même courbe que les `sp` — non
 * linéaire depuis Android 14, qui grossit moins les grands corps.
 */
@Composable
fun scaled(value: Dp): Dp = with(LocalDensity.current) { value.value.sp.toDp() }

/**
 * `dynamicTypeSize.isAccessibilitySize` : les tailles de police où ce qui est
 * côte à côte doit s'empiler. Les tailles accessibles d'iOS commencent un
 * cran au-dessus de la plus grande taille ordinaire (≈ ×1,35) ; côté Android,
 * c'est à partir de ×1,5.
 */
@Composable
fun isAccessibilityTextSize(): Boolean = LocalDensity.current.fontScale >= 1.5f

/**
 * `accessibilityReduceMotion` : vrai quand « Supprimer les animations » est
 * activé — Android le dit par une échelle d'animation à zéro.
 */
@Composable
fun isReduceMotionEnabled(): Boolean {
    val resolver = LocalContext.current.contentResolver
    return remember(resolver) {
        Settings.Global.getFloat(resolver, Settings.Global.ANIMATOR_DURATION_SCALE, 1f) == 0f
    }
}

/** `brandShadow(_:)` : pose l'une des deux ombres nommées de la marque. */
fun Modifier.brandShadow(shadow: MemoBookShadow, shape: Shape): Modifier = dropShadow(
    shape = shape,
    shadow = Shadow(radius = shadow.radius, color = shadow.color, offset = DpOffset(0.dp, shadow.offsetY)),
)

/**
 * Le `ProgressView` du système : un arc qui tourne. Material en a un, qu'on
 * n'emploie pas ; celui-ci prend la couleur de ce qui le porte.
 */
@Composable
fun ActivitySpinner(color: Color, modifier: Modifier = Modifier, size: Dp = 18.dp) {
    val transition = rememberInfiniteTransition(label = "spinner")
    val angle by transition.animateFloat(
        initialValue = 0f,
        targetValue = 360f,
        animationSpec = infiniteRepeatable(tween(900, easing = LinearEasing), RepeatMode.Restart),
        label = "angle",
    )
    Canvas(modifier.size(size)) {
        val stroke = this.size.minDimension * 0.12f
        rotate(angle) {
            drawArc(
                color = color,
                startAngle = 0f,
                sweepAngle = 270f,
                useCenter = false,
                topLeft = Offset(stroke / 2, stroke / 2),
                size = androidx.compose.ui.geometry.Size(this.size.width - stroke, this.size.height - stroke),
                style = Stroke(width = stroke, cap = StrokeCap.Round),
            )
        }
    }
}
