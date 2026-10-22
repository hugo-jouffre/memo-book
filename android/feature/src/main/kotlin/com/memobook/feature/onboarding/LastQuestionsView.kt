package com.memobook.feature.onboarding

import androidx.annotation.DrawableRes
import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.core.animateDpAsState
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInHorizontally
import androidx.compose.animation.slideOutHorizontally
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.navigationBars
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBars
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.autofill.ContentType
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.OffsetMapping
import androidx.compose.ui.text.input.TransformedText
import androidx.compose.ui.text.input.VisualTransformation
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.memobook.core.Account
import com.memobook.design.BrandButton
import com.memobook.design.BrandText
import com.memobook.design.BrandTextField
import com.memobook.design.DeviceScreen
import com.memobook.design.MemoBookColor
import com.memobook.design.MemoBookFont
import com.memobook.design.MemoBookSpacing
import com.memobook.design.PlainButtonIndication
import com.memobook.design.R
import com.memobook.design.SwiftMotion
import com.memobook.design.isAccessibilityTextSize
import com.memobook.design.isReduceMotionEnabled
import com.memobook.design.scaled
import com.memobook.feature.auth.FieldError
import com.memobook.feature.auth.onHorizontalSwipe
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import java.time.Instant
import kotlin.math.abs

/**
 * Les « Dernières questions » (`3533:14979`, `3533:15036`, `3533:15010`) :
 * trois écrans à la fin de l'onboarding, pour qui entre pour la première fois.
 * Jumeau de `LastQuestionsView.swift`.
 *
 * Chacun a le même dessin — la flèche et « Passer » en tête, l'illustration
 * de marque, les trois traits qui disent où l'on en est, le titre en vert,
 * le champ, et « Valider » en bas. Seuls l'illustration, le titre et le
 * champ changent : c'est **un** écran dont le contenu glisse, pas trois
 * destinations, et la flèche ramène à la question d'avant. Le premier écran
 * n'a pas de flèche (T192, Hugo, 06/10/2026) : il n'y a rien avant, sinon
 * l'entrée — et y revenir refermait la session qu'on venait d'ouvrir.
 *
 * **Les écrans se feuillettent au doigt**, comme les étapes de la création
 * d'un voyage (Hugo, 06/10/2026) : l'illustration glisse, le reste se fond.
 *
 * Ils remplacent la page de compléments après Apple ou Google (`2707:9456`),
 * qui ne s'ouvrait plus depuis que ces deux entrées vivent sur l'écran
 * d'entrée — le nom se vérifie désormais ici, pour tout le monde.
 */
@Composable
fun LastQuestionsView(model: LastQuestionsModel, onFinished: (Account) -> Unit) {
    val state by model.state.collectAsStateWithLifecycle(context = Dispatchers.Main.immediate)
    val scope = rememberCoroutineScope()
    val reduceMotion = isReduceMotionEnabled()

    var focus by remember { mutableStateOf<LastQuestionsField?>(null) }

    /**
     * Le sens du dernier mouvement : en avant sur « Valider », « Passer » et le
     * glissé vers la gauche, en arrière sur la flèche et le glissé vers la
     * droite. C'est lui qui décide d'où l'illustration arrive — même mécanique
     * que `TripCreationView`.
     */
    var direction by remember { mutableStateOf(Direction.Forward) }

    fun validate() {
        focus = null
        direction = Direction.Forward
        scope.launch { model.validate()?.let(onFinished) }
    }

    fun skip() {
        focus = null
        direction = Direction.Forward
        model.skip()?.let(onFinished)
    }

    fun swipeForward() {
        focus = null
        direction = Direction.Forward
        scope.launch { model.swipeForward()?.let(onFinished) }
    }

    fun back() {
        focus = null
        direction = Direction.Backward
        model.goBack()
    }

    // Un glissé vers la gauche avance, vers la droite revient — le geste de la
    // création d'un voyage, aux mêmes seuils : franchement horizontal, pour ne
    // pas prendre le défilement vertical.
    val swipe by rememberUpdatedState { dx: Float, dy: Float ->
        if (abs(dx) > 60 && abs(dx) > abs(dy) * 1.5f) {
            if (dx < 0) {
                swipeForward()
            } else if (model.state.value.canGoBack) {
                back()
            }
        }
    }

    // L'illustration glisse de la largeur de l'écran, pour venir du bord.
    val travel = with(LocalDensity.current) { DeviceScreen.width().roundToPx() }

    Column(
        Modifier
            .fillMaxSize()
            .background(MemoBookColor.background)
            // Le clavier pousse « Valider » au-dessus de lui, comme le
            // `safeAreaInset` d'iOS.
            .imePadding(),
    ) {
        TopBar(
            canGoBack = state.canGoBack,
            isSaving = state.isSaving,
            onBack = ::back,
            onSkip = ::skip,
        )

        Column(
            Modifier
                .weight(1f)
                .fillMaxWidth()
                .onHorizontalSwipe(minimumDistance = 30.dp) { dx, dy -> swipe(dx, dy) }
                .verticalScroll(rememberScrollState()),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Column(
                Modifier
                    .widthIn(max = CONTENT_WIDTH)
                    .fillMaxWidth()
                    .padding(horizontal = MemoBookSpacing.screenMargin)
                    .padding(top = MemoBookSpacing.m, bottom = MemoBookSpacing.l),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.l),
            ) {
                // L'illustration glisse — celle de l'écran suivant arrive par la
                // droite pendant que celle-ci sort par la gauche, et l'inverse en
                // revenant. Le reste se fond : deux mouvements à la fois se
                // liraient comme un autre écran.
                AnimatedContent(
                    targetState = state.step,
                    transitionSpec = {
                        val fade = SwiftMotion.snappy<Float>(0.35f)
                        if (reduceMotion) {
                            fadeIn(fade) togetherWith fadeOut(fade)
                        } else {
                            val motion = SwiftMotion.snappy<IntOffset>(0.35f)
                            val forward = direction == Direction.Forward
                            (slideInHorizontally(motion) { if (forward) travel else -travel } + fadeIn(fade)) togetherWith
                                (slideOutHorizontally(motion) { if (forward) -travel else travel } + fadeOut(fade))
                        }
                    },
                    label = "illustration",
                ) { step -> Illustration(step) }

                LastQuestionsProgress(current = state.step.ordinal, count = LastQuestionsModel.Step.entries.size)

                AnimatedContent(
                    targetState = state.step,
                    transitionSpec = { fadeIn(SwiftMotion.snappy(0.35f)) togetherWith fadeOut(SwiftMotion.snappy(0.35f)) },
                    label = "question",
                ) { step ->
                    Question(
                        step = step,
                        state = state,
                        model = model,
                        focus = focus,
                        onFocusChange = { focus = it },
                        onValidate = ::validate,
                    )
                }
            }
        }

        ValidateButton(isSaving = state.isSaving, canValidate = state.canValidate, onValidate = ::validate)
    }
}

private enum class Direction { Forward, Backward }

/** Dans l'ordre où le clavier les enchaîne : le prénom d'abord. */
private enum class LastQuestionsField { FirstName, LastName, BirthDate, Phone }

/** Largeur du cadre de la maquette : au-delà, la colonne se centre. */
private val CONTENT_WIDTH = 390.dp

/**
 * La largeur du titre : c'est elle qui le coupe en deux lignes comme la
 * maquette — « Ton nom / et prénom ».
 */
private val TITLE_WIDTH = 220.dp

// MARK: - La tête

@Composable
private fun TopBar(canGoBack: Boolean, isSaving: Boolean, onBack: () -> Unit, onSkip: () -> Unit) {
    Row(
        Modifier
            .fillMaxWidth()
            .windowInsetsPadding(WindowInsets.statusBars)
            .padding(horizontal = MemoBookSpacing.screenMargin)
            .padding(top = MemoBookSpacing.xs),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        // Pas de flèche sur le premier écran (T192) ; la place reste tenue,
        // pour que « Passer » ne bouge pas d'un écran à l'autre.
        Box(Modifier.size(MemoBookSpacing.minimumTapTarget)) {
            androidx.compose.animation.AnimatedVisibility(visible = canGoBack, enter = fadeIn(), exit = fadeOut()) {
                Box(
                    Modifier
                        .size(MemoBookSpacing.minimumTapTarget)
                        .clickable(interactionSource = null, indication = PlainButtonIndication, role = Role.Button, onClick = onBack)
                        .semantics { contentDescription = "Retour" },
                    contentAlignment = Alignment.Center,
                ) {
                    Image(
                        painter = painterResource(R.drawable.icon_arrow_duo),
                        contentDescription = null,
                        modifier = Modifier.size(MemoBookSpacing.navigationIcon),
                    )
                }
            }
        }

        Spacer(Modifier.weight(1f))

        Box(
            Modifier
                .heightIn(min = MemoBookSpacing.minimumTapTarget)
                .clickable(interactionSource = null, indication = PlainButtonIndication, enabled = !isSaving, role = Role.Button, onClick = onSkip),
            contentAlignment = Alignment.Center,
        ) {
            BrandText(LastQuestionsCopy.skip, MemoBookFont.bodySemibold, color = MemoBookColor.inkMuted)
        }
    }
}

// MARK: - L'illustration

@DrawableRes
private fun illustrationOf(step: LastQuestionsModel.Step): Int = when (step) {
    LastQuestionsModel.Step.Name -> R.drawable.illustration_carte_id
    LastQuestionsModel.Step.BirthDate -> R.drawable.illustration_calendrier
    LastQuestionsModel.Step.Phone -> R.drawable.illustration_phone
}

/**
 * 200 de haut sur la maquette ; elle rétrécit sur un petit écran et en taille
 * accessible, où c'est le champ qui doit rester visible.
 */
@Composable
private fun Illustration(step: LastQuestionsModel.Step) {
    val height = if (isAccessibilityTextSize()) 120.dp else minOf(scaled(200.dp), 200.dp)
    Image(
        painter = painterResource(illustrationOf(step)),
        contentDescription = null,
        contentScale = ContentScale.Fit,
        modifier = Modifier
            .fillMaxWidth()
            .height(height),
    )
}

// MARK: - La question

@Composable
private fun Question(
    step: LastQuestionsModel.Step,
    state: LastQuestionsModel.State,
    model: LastQuestionsModel,
    focus: LastQuestionsField?,
    onFocusChange: (LastQuestionsField?) -> Unit,
    onValidate: () -> Unit,
) {
    Column(
        Modifier.fillMaxWidth(),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.m),
    ) {
        BrandText(
            titleOf(step),
            MemoBookFont.h1,
            Modifier
                .widthIn(max = TITLE_WIDTH)
                .semantics { heading() },
            color = MemoBookColor.action,
            textAlign = TextAlign.Center,
        )

        // Le texte des champs part de la gauche (Hugo, 06/10/2026) : il était
        // centré comme sur la maquette, et l'intitulé qui monte sur le contour,
        // lui, se pose en haut à gauche.
        Column(verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.s)) {
            Fields(step, state, model, focus, onFocusChange, onValidate)

            // Sous le champ, aligné sur son texte — comme les erreurs de
            // l'inscription.
            FieldError(state.birthDateProblem ?: state.errorMessage)
        }
    }
}

private fun titleOf(step: LastQuestionsModel.Step): String = when (step) {
    LastQuestionsModel.Step.Name -> LastQuestionsCopy.nameTitle
    LastQuestionsModel.Step.BirthDate -> LastQuestionsCopy.birthDateTitle
    LastQuestionsModel.Step.Phone -> LastQuestionsCopy.phoneTitle
}

/**
 * Les champs de l'inscription, au comportement près (Hugo, 06/10/2026) : au
 * repos, le nom du champ en gris dans le cadre ; au focus, le contour vert et
 * le nom monté en haut à gauche. La date et le téléphone gardent un repère de
 * format au repos — « JJ/MM/AAAA » —, qui reste dans le cadre tant qu'on n'a
 * rien tapé (voir `BrandTextField`).
 */
@Composable
private fun Fields(
    step: LastQuestionsModel.Step,
    state: LastQuestionsModel.State,
    model: LastQuestionsModel,
    focus: LastQuestionsField?,
    onFocusChange: (LastQuestionsField?) -> Unit,
    onValidate: () -> Unit,
) {
    when (step) {
        LastQuestionsModel.Step.Name -> {
            BrandTextField(
                LastQuestionsCopy.firstNameLabel,
                state.firstName,
                { model.firstName = it },
                field = LastQuestionsField.FirstName,
                focus = focus,
                onFocusChange = onFocusChange,
                keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.Words, imeAction = ImeAction.Next),
                keyboardActions = KeyboardActions(onNext = { onFocusChange(LastQuestionsField.LastName) }),
                contentType = ContentType.PersonFirstName,
            )
            BrandTextField(
                LastQuestionsCopy.lastNameLabel,
                state.lastName,
                { model.lastName = it },
                field = LastQuestionsField.LastName,
                focus = focus,
                onFocusChange = onFocusChange,
                keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.Words, imeAction = ImeAction.Done),
                keyboardActions = KeyboardActions(onDone = { onValidate() }),
                contentType = ContentType.PersonLastName,
            )
        }

        // ⚠️ **Le champ ne tient que les chiffres**, et c'est
        // [BirthDateSlashes] qui y dessine les barres. iOS réécrit la valeur à
        // la frappe ; sur Android, réécrire « 120 » en « 12/0 » laissait le
        // curseur avant le « 0 » — le chiffre suivant s'insérait au mauvais
        // endroit. Le modèle garde, lui, la forme `JJ/MM/AAAA`. Le repère de
        // format est l'indice que VoiceOver entend sur iOS
        // (`LastQuestionsCopy.Voice.birthDateHint`) ; `BrandTextField` n'a pas
        // d'indice pour TalkBack, qui lit l'intitulé.
        LastQuestionsModel.Step.BirthDate -> BrandTextField(
            LastQuestionsCopy.birthDateLabel,
            state.birthDateText.filter { it.isDigit() },
            { model.birthDateText = it },
            field = LastQuestionsField.BirthDate,
            focus = focus,
            onFocusChange = onFocusChange,
            placeholder = LastQuestionsCopy.birthDatePlaceholder,
            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number, imeAction = ImeAction.Done),
            keyboardActions = KeyboardActions(onDone = { onValidate() }),
            contentType = ContentType.BirthDateFull,
            visualTransformation = BirthDateSlashes,
        )

        LastQuestionsModel.Step.Phone -> BrandTextField(
            LastQuestionsCopy.phoneLabel,
            state.phoneNumber,
            { model.phoneNumber = it },
            field = LastQuestionsField.Phone,
            focus = focus,
            onFocusChange = onFocusChange,
            placeholder = LastQuestionsCopy.phonePlaceholder,
            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Phone, imeAction = ImeAction.Done),
            keyboardActions = KeyboardActions(onDone = { onValidate() }),
            contentType = ContentType.PhoneNumber,
        )
    }
}

/**
 * Les barres de `JJ/MM/AAAA`, dessinées sur les chiffres tapés — la même règle
 * que [LastQuestionsModel.maskedBirthDate], qui écrit le texte affiché. Le
 * curseur saute la barre : derrière le deuxième chiffre, il est avant elle.
 */
private object BirthDateSlashes : VisualTransformation {
    override fun filter(text: AnnotatedString): TransformedText {
        val digits = text.text
        val masked = LastQuestionsModel.maskedBirthDate(digits)
        val mapping = object : OffsetMapping {
            override fun originalToTransformed(offset: Int): Int = when {
                offset <= 2 -> offset
                offset <= 4 -> offset + 1
                else -> offset + 2
            }.coerceAtMost(masked.length)

            override fun transformedToOriginal(offset: Int): Int = when {
                offset <= 2 -> offset
                offset <= 5 -> offset - 1
                else -> offset - 2
            }.coerceIn(0, digits.length)
        }
        return TransformedText(AnnotatedString(masked), mapping)
    }
}

// MARK: - Valider

@Composable
private fun ValidateButton(isSaving: Boolean, canValidate: Boolean, onValidate: () -> Unit) {
    Box(
        Modifier
            .fillMaxWidth()
            .background(MemoBookColor.background)
            .windowInsetsPadding(WindowInsets.navigationBars),
        contentAlignment = Alignment.TopCenter,
    ) {
        BrandButton(
            LastQuestionsCopy.validate,
            modifier = Modifier
                .widthIn(max = CONTENT_WIDTH)
                .padding(horizontal = MemoBookSpacing.screenMargin, vertical = MemoBookSpacing.snug),
            isLoading = isSaving,
            fillsWidth = true,
            enabled = canValidate,
            action = onValidate,
        )
    }
}

/**
 * Les trois traits qui disent où l'on en est (`3533:14203`) : le trait de la
 * question en cours est le plus haut et le seul en vert, les autres
 * raccourcissent en s'éloignant.
 */
@Composable
internal fun LastQuestionsProgress(current: Int, count: Int) {
    Row(
        Modifier
            .height(PROGRESS_HEIGHTS[0])
            .clearAndSetSemantics { contentDescription = LastQuestionsCopy.Voice.progress(current + 1, count) },
        horizontalArrangement = Arrangement.spacedBy(6.dp),
        verticalAlignment = Alignment.Bottom,
    ) {
        repeat(count) { index ->
            val distance = minOf(abs(index - current), PROGRESS_HEIGHTS.lastIndex)
            val height by animateDpAsState(PROGRESS_HEIGHTS[distance], SwiftMotion.snappy(0.25f), label = "trait")
            Box(
                Modifier
                    .width(2.5.dp)
                    .height(height)
                    .background(if (index == current) MemoBookColor.action else MemoBookColor.inkFaint, RoundedCornerShape(50)),
            )
        }
    }
}

/** Les hauteurs de la maquette, selon la distance à la question en cours. */
private val PROGRESS_HEIGHTS = listOf(20.dp, 16.dp, 13.dp)

@Preview(locale = "fr-rFR", name = "Dernières questions — le nom", widthDp = 390, heightDp = 844)
@Composable
private fun LastQuestionsViewPreview() {
    val model = remember { LastQuestionsModel(Account(id = "preview", firstName = "Camille", createdAt = Instant.now())) }
    LastQuestionsView(model, onFinished = {})
}

@Preview(locale = "fr-rFR", name = "Dernières questions — AX3", widthDp = 390, heightDp = 844, fontScale = 2f)
@Composable
private fun LastQuestionsViewAccessibilityPreview() {
    val model = remember { LastQuestionsModel(Account(id = "preview", createdAt = Instant.now())) }
    LastQuestionsView(model, onFinished = {})
}
