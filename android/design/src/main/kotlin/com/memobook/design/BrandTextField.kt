package com.memobook.design

import androidx.annotation.DrawableRes
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.core.FiniteAnimationSpec
import androidx.compose.animation.core.snap
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutVertically
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.sizeIn
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.text.selection.LocalTextSelectionColors
import androidx.compose.foundation.text.selection.TextSelectionColors
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.Stable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.runtime.withFrameNanos
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.autofill.ContentType
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ColorFilter
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.contentType
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.input.VisualTransformation
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.launch

/**
 * Le champ de saisie de l'app. Un seul dessin pour tous les formulaires.
 * Jumeau de `BrandTextField.swift`.
 *
 * Deux états, comme dans la maquette :
 * - **au repos** : aplat blanc, pas de contour, l'intitulé sert de texte
 *   indicatif à l'intérieur ;
 * - **actif** (au focus, ou dès qu'il contient quelque chose) : le fond
 *   redevient transparent, un contour apparaît, et l'intitulé monte se poser à
 *   cheval sur ce contour. L'entaille n'est pas dessinée : l'étiquette porte
 *   une pastille de la couleur du fond, qui masque le trait derrière elle.
 *
 * **Dans une feuille, le fond n'est plus le crème** mais le papier de
 * [BrandSheet], qui le dit par [LocalBrandFieldBackdrop] : la pastille en prend
 * la couleur, et le contour se dessine dès le repos.
 *
 * **Le focus appartient à l'écran, pas au champ** : l'écran tient une énum, la
 * passe à chaque champ, et la touche « suivant » du clavier passe d'un champ à
 * l'autre en la changeant — le `@FocusState` d'iOS.
 *
 * ```kotlin
 * var focus by remember { mutableStateOf<Field?>(null) }
 * BrandTextField("E-mail", email, { email = it }, field = Field.Email, focus = focus, onFocusChange = { focus = it },
 *     keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Email, imeAction = ImeAction.Next),
 *     keyboardActions = KeyboardActions(onNext = { focus = Field.Password }), contentType = ContentType.EmailAddress)
 * ```
 *
 * @param placeholder l'exemple de valeur affiché tant que le champ est vide. En
 *   [LabelPlacement.Floating][BrandTextField.LabelPlacement.Floating], c'est un
 *   **repère de format** — « JJ/MM/AAAA » : il remplace l'intitulé au repos, puis
 *   **reste dans le cadre** tant qu'on n'a rien tapé, pendant que l'intitulé monte
 *   (les « Dernières questions », Hugo, 06/10/2026).
 * @param hint le texte d'aide sous le champ. Il ne disparaît pas quand on tape.
 * @param trailingIcon un pictogramme de marque au bout du champ — le crayon de
 *   « Mot de passe oublié », qui dit qu'une valeur **préremplie** se corrige.
 *   Ignoré sur un champ secret, dont le bout appartient à l'œil.
 * @param textAlign le `multilineTextAlignment` qu'iOS lit dans l'environnement :
 *   le texte indicatif le suit aussi, sans quoi « Dupont » restait à gauche d'un
 *   champ où l'on tape au centre (26/09/2026).
 * @param keyboardOptions le `keyboardType` et le `submitLabel` qu'iOS pose de l'extérieur.
 * @param keyboardActions le `onSubmit` : la touche « suivant » change le focus de l'écran.
 * @param contentType le `textContentType` : ce que le remplissage automatique y propose.
 */
@Composable
fun <F : Any> BrandTextField(
    label: String,
    value: String,
    onValueChange: (String) -> Unit,
    field: F,
    focus: F?,
    onFocusChange: (F?) -> Unit,
    modifier: Modifier = Modifier,
    isSecure: Boolean = false,
    labelPlacement: BrandTextField.LabelPlacement = BrandTextField.LabelPlacement.Floating,
    placeholder: String? = null,
    hint: String? = null,
    @DrawableRes trailingIcon: Int? = null,
    textAlign: TextAlign = TextAlign.Start,
    keyboardOptions: KeyboardOptions = KeyboardOptions.Default,
    keyboardActions: KeyboardActions = KeyboardActions.Default,
    contentType: ContentType? = null,
) {
    // Le mot de passe se dévoile à la demande. Sans ça, corriger une faute de
    // frappe sur un clavier tactile relève du pari.
    var isRevealed by remember { mutableStateOf(false) }
    val backdrop = LocalBrandFieldBackdrop.current
    val height = scaled(MemoBookSpacing.fieldHeight)
    // La taille de l'étiquette flottante, suivie parce que le décalage qui la
    // pose sur le contour s'exprime en fraction de police.
    val labelSize = scaled(12.dp)
    // Le crayon suit le corps du texte : à 20 il pèse autant que l'œil.
    val trailingIconSide = scaled(20.dp)

    val isFocused = focus == field
    val isActive = isFocused || value.isNotEmpty()
    // L'aplat blanc du repos n'appartient qu'à l'étiquette flottante. **Sauf sur
    // le papier d'une feuille** (01/10/2026) : il est du même blanc, et un champ
    // au repos y disparaissait. Le contour gris prend alors le rôle de l'aplat.
    val isOutlined = labelPlacement != BrandTextField.LabelPlacement.Floating || isActive || backdrop != null
    val showsPlaceholder = when (labelPlacement) {
        // Un repère de format reste visible au focus, sous l'intitulé monté.
        BrandTextField.LabelPlacement.Floating -> !isActive || (placeholder != null && value.isEmpty())
        BrandTextField.LabelPlacement.Above, BrandTextField.LabelPlacement.Hidden -> value.isEmpty()
    }

    val currentFocus by rememberUpdatedState(focus)
    val binding = rememberFocusBinding(
        wanted = isFocused,
        released = focus == null,
        onFocusGained = { onFocusChange(field) },
        onFocusLost = { if (currentFocus == field) onFocusChange(null) },
    )

    val motion = fieldMotion<Color>()
    val borderColor by animateColorAsState(if (isFocused) MemoBookColor.action else MemoBookColor.separator, motion, label = "contour")
    val fill by animateColorAsState(
        if (isOutlined) MemoBookColor.surface.copy(alpha = 0f) else MemoBookColor.surface,
        motion,
        label = "aplat",
    )
    val labelColor by animateColorAsState(if (isFocused) MemoBookColor.action else MemoBookColor.inkMuted, motion, label = "intitulé")
    val shape = RoundedCornerShape(MemoBookSpacing.controlCornerRadius)

    CompositionLocalProvider(LocalTextSelectionColors provides BrandTextSelectionColors) {
        Column(modifier, verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.xs)) {
            if (labelPlacement == BrandTextField.LabelPlacement.Above) {
                // Le champ porte déjà ce mot pour TalkBack : il ne l'entend pas deux fois.
                BrandText(label, MemoBookFont.bodySemibold, Modifier.clearAndSetSemantics {})
            }

            Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                Box(
                    Modifier
                        .fillMaxWidth()
                        .height(height)
                        .background(fill, shape)
                        // Pas de trait de zéro au repos : zéro y vaut un trait d'un pixel.
                        // Et le contour **sous** le contenu : `Modifier.border` le
                        // dessine par-dessus, et l'intitulé monté ne le coupait plus —
                        // le trait le barrait (vu dans l'émulateur, 21/10/2026).
                        .then(if (isOutlined) Modifier.outlineBehind({ borderColor }, MemoBookSpacing.controlCornerRadius) else Modifier)
                        // Tout le cadre donne le focus, pas seulement la ligne de texte.
                        .pointerInput(Unit) { detectTapGestures { binding.requester.requestFocus() } },
                ) {
                    Row(
                        Modifier
                            .fillMaxSize()
                            .padding(horizontal = 20.dp),
                        horizontalArrangement = Arrangement.spacedBy(MemoBookSpacing.xs),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Box(Modifier.weight(1f), contentAlignment = placeholderAlignment(textAlign)) {
                            // Texte indicatif dessiné à la main, dans la typographie de la marque.
                            if (showsPlaceholder) {
                                BrandText(
                                    placeholder ?: label,
                                    MemoBookFont.bodySemibold,
                                    color = MemoBookColor.inkMuted,
                                    textAlign = textAlign,
                                    modifier = Modifier.clearAndSetSemantics {},
                                )
                            }
                            BasicTextField(
                                value = value,
                                onValueChange = onValueChange,
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .then(binding.modifier)
                                    .semantics {
                                        contentDescription = label
                                        if (contentType != null) this.contentType = contentType
                                    },
                                textStyle = MemoBookFont.body.copy(color = MemoBookColor.ink, textAlign = textAlign),
                                // Un mot de passe dévoilé reste un mot de passe : ni
                                // majuscule de début de phrase, ni correction du
                                // système — ce qu'on lit est ce qui sera envoyé. Le
                                // clavier ne change pas en se dévoilant : seul le
                                // masque tombe, et la saisie continue.
                                keyboardOptions = if (isSecure) {
                                    keyboardOptions.copy(
                                        keyboardType = KeyboardType.Password,
                                        capitalization = KeyboardCapitalization.None,
                                        autoCorrectEnabled = false,
                                    )
                                } else {
                                    keyboardOptions
                                },
                                keyboardActions = keyboardActions,
                                singleLine = true,
                                visualTransformation = if (isSecure && !isRevealed) PasswordVisualTransformation() else VisualTransformation.None,
                                cursorBrush = SolidColor(MemoBookColor.action),
                            )
                        }

                        if (isSecure) {
                            Box(
                                Modifier
                                    .sizeIn(minWidth = MemoBookSpacing.minimumTapTarget, minHeight = MemoBookSpacing.minimumTapTarget)
                                    .clickable(
                                        interactionSource = remember { MutableInteractionSource() },
                                        indication = null,
                                        role = Role.Button,
                                    ) {
                                        isRevealed = !isRevealed
                                        // Le focus reste au champ : on dévoile pour retaper.
                                        onFocusChange(field)
                                    }
                                    .semantics {
                                        contentDescription = if (isRevealed) "Masquer le mot de passe" else "Afficher le mot de passe"
                                    },
                                contentAlignment = Alignment.Center,
                            ) {
                                // `eye` / `eye.slash` d'iOS, redessinés au trait.
                                Image(
                                    painter = painterResource(if (isRevealed) R.drawable.system_eye_slash else R.drawable.system_eye),
                                    contentDescription = null,
                                    colorFilter = ColorFilter.tint(MemoBookColor.inkMuted),
                                    modifier = Modifier.size(trailingIconSide),
                                )
                            }
                        } else if (trailingIcon != null) {
                            Image(
                                painter = painterResource(trailingIcon),
                                contentDescription = null,
                                colorFilter = ColorFilter.tint(if (isFocused) MemoBookColor.action else MemoBookColor.inkMuted),
                                modifier = Modifier
                                    .size(trailingIconSide)
                                    .clearAndSetSemantics {},
                            )
                        }
                    }

                    FloatingLabel(
                        label = label,
                        visible = labelPlacement == BrandTextField.LabelPlacement.Floating && isActive,
                        color = labelColor,
                        backdrop = backdrop ?: MemoBookColor.background,
                        modifier = Modifier
                            .align(Alignment.TopStart)
                            .padding(start = 14.dp)
                            // Posée sur le contour : le milieu de ses capitales sur le trait.
                            .offset(y = -labelSize * GeneralSansMetrics.CAP_CENTER_FROM_TOP),
                    )
                }

                if (hint != null) {
                    BrandText(hint, MemoBookFont.caption, Modifier.padding(horizontal = 20.dp), color = MemoBookColor.inkMuted)
                }
            }
        }
    }
}

/** L'intitulé monté sur le contour. Il arrive en fondu, de 6 plus bas. */
@Composable
private fun FloatingLabel(label: String, visible: Boolean, color: Color, backdrop: Color, modifier: Modifier) {
    val density = LocalDensity.current
    val rise = with(density) { 6.dp.roundToPx() }
    AnimatedVisibility(
        visible = visible,
        modifier = modifier,
        enter = fadeIn(fieldMotion()) + slideInVertically(fieldMotion()) { rise },
        exit = fadeOut(fieldMotion()) + slideOutVertically(fieldMotion()) { rise },
    ) {
        BrandText(
            label,
            MemoBookFont.caption,
            color = color,
            modifier = Modifier
                // La pastille prend la couleur du fond : c'est elle qui « coupe »
                // le contour. Dans une feuille, celle du papier — le crème y
                // faisait une bulle orangée.
                .background(backdrop)
                .padding(horizontal = 6.dp)
                .clearAndSetSemantics {},
        )
    }
}

/** Les mises en page du champ, sous le nom du composant comme sur iOS (`BrandTextField.LabelPlacement`). */
object BrandTextField {
    /** Où se pose l'intitulé du champ. Un seul champ, trois mises en page — pas trois composants. */
    enum class LabelPlacement {
        /**
         * L'intitulé **est** le texte indicatif, et monte sur le contour dès que
         * le champ sert. Le formulaire d'entrée dans l'app.
         */
        Floating,

        /**
         * L'intitulé est écrit **au-dessus** du champ, en gras. Le dessin des
         * feuilles : le texte indicatif y montre un **exemple de valeur**
         * (« 7 rue Simon Fryd ») et non le nom du champ.
         */
        Above,

        /**
         * Aucun intitulé écrit : pour le champ **unique** d'une feuille dont le
         * titre et le sous-titre disent déjà ce qu'on attend — « Rejoindre ».
         * L'intitulé reste donné à TalkBack, qui n'a que lui.
         */
        Hidden,
    }
}

/**
 * L'aplat sur lequel les champs sont posés, **quand ce n'est pas le crème de
 * l'écran** : le papier d'une [BrandSheet], qui le pose ici. `null` sur un écran.
 */
val LocalBrandFieldBackdrop = staticCompositionLocalOf<Color?> { null }

/**
 * Métriques verticales de General Sans, lues dans ses tables `hhea` et `OS/2`
 * et ramenées à la taille de police : montante 1,010, interligne 0,050, hauteur
 * de capitale 0,718. Elles posent l'étiquette flottante sur le contour : on vise
 * le milieu des capitales, seul repère que l'œil voit.
 */
private object GeneralSansMetrics {
    const val ASCENDER = 1.010f
    const val CAP_HEIGHT = 0.718f

    /**
     * Du haut du cadre d'un texte au milieu de ses capitales. iOS réserve
     * l'interligne (0,050) au-dessus de la première ligne ; Android non.
     */
    const val CAP_CENTER_FROM_TOP = ASCENDER - CAP_HEIGHT / 2
}

/** Le `.snappy(duration: 0.22)` du champ, ou rien sous « Supprimer les animations ». */
@Composable
private fun <T> fieldMotion(): FiniteAnimationSpec<T> =
    if (isReduceMotionEnabled()) snap() else SwiftMotion.snappy(0.22f)

private fun placeholderAlignment(textAlign: TextAlign): Alignment = when (textAlign) {
    TextAlign.Center -> Alignment.Center
    TextAlign.End, TextAlign.Right -> Alignment.CenterEnd
    else -> Alignment.CenterStart
}

/** Le curseur et la sélection au vert d'action, le `.tint` d'iOS ; le fond de sélection à 40 %, comme celui du système. */
internal val BrandTextSelectionColors = TextSelectionColors(
    handleColor = MemoBookColor.action,
    backgroundColor = MemoBookColor.action.copy(alpha = 0.4f),
)

// MARK: - Le focus tenu par l'écran

/**
 * Le pont entre l'état de focus que tient l'écran et le focus de Compose, dans
 * les deux sens : l'écran demande (`wanted`) ou relâche (`released`) le focus,
 * le champ annonce qu'il l'a pris ou perdu.
 */
@Stable
internal class FocusBinding(private val onChange: (Boolean) -> Unit) {
    val requester = FocusRequester()

    var hasFocus by mutableStateOf(false)
        private set

    val modifier: Modifier = Modifier
        .focusRequester(requester)
        .onFocusChanged { state ->
            if (state.isFocused != hasFocus) {
                hasFocus = state.isFocused
                onChange(state.isFocused)
            }
        }
}

@Composable
internal fun rememberFocusBinding(
    wanted: Boolean,
    released: Boolean,
    onFocusGained: () -> Unit,
    onFocusLost: () -> Unit,
): FocusBinding {
    val focusManager = LocalFocusManager.current
    val scope = rememberCoroutineScope()
    val gained by rememberUpdatedState(onFocusGained)
    val lost by rememberUpdatedState(onFocusLost)
    val binding = remember {
        lateinit var created: FocusBinding
        created = FocusBinding { focused ->
            if (focused) {
                gained()
            } else {
                // Une image plus tard : si le focus est passé à un autre champ,
                // l'écran le sait déjà, et on ne lui remet pas `null` par-dessus.
                scope.launch {
                    withFrameNanos {}
                    if (!created.hasFocus) lost()
                }
            }
        }
        created
    }
    LaunchedEffect(wanted) {
        if (wanted && !binding.hasFocus) binding.requester.requestFocus()
    }
    LaunchedEffect(released) {
        if (released && binding.hasFocus) focusManager.clearFocus()
    }
    return binding
}

private enum class PreviewField { Email, Password, Street, Code }

@Preview(locale = "fr-rFR", name = "Champs", widthDp = 390, heightDp = 640)
@Composable
private fun BrandTextFieldPreview() {
    var focus by remember { mutableStateOf<PreviewField?>(null) }
    var email by remember { mutableStateOf("") }
    var password by remember { mutableStateOf("secret") }
    var street by remember { mutableStateOf("") }
    var code by remember { mutableStateOf("") }
    Column(
        Modifier
            .background(MemoBookColor.background)
            .padding(MemoBookSpacing.screenMargin),
        verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.m),
    ) {
        BrandTextField("E-mail", email, { email = it }, PreviewField.Email, focus, { focus = it })
        BrandTextField("Mot de passe", password, { password = it }, PreviewField.Password, focus, { focus = it }, isSecure = true)
        BrandTextField(
            "Adresse",
            street,
            { street = it },
            PreviewField.Street,
            focus,
            { focus = it },
            labelPlacement = BrandTextField.LabelPlacement.Above,
            placeholder = "7 rue Simon Fryd",
            hint = "Le numéro et la rue.",
            trailingIcon = R.drawable.icon_pen,
        )
        BrandTextField(
            "Code d’accès",
            code,
            { code = it },
            PreviewField.Code,
            focus,
            { focus = it },
            labelPlacement = BrandTextField.LabelPlacement.Hidden,
            placeholder = "ABC-123",
            textAlign = TextAlign.Center,
        )
    }
}

/** Un contour d'un trait, dessiné **derrière** le contenu, à l'intérieur du cadre comme `Modifier.border`. */
private fun Modifier.outlineBehind(color: () -> Color, cornerRadius: Dp): Modifier = drawBehind {
    val stroke = 1.dp.toPx()
    drawRoundRect(
        color = color(),
        topLeft = Offset(stroke / 2, stroke / 2),
        size = Size(size.width - stroke, size.height - stroke),
        cornerRadius = CornerRadius(cornerRadius.toPx() - stroke / 2),
        style = Stroke(stroke),
    )
}
