package com.memobook.feature.tripcreation

import android.os.Build
import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.core.animateDpAsState
import androidx.compose.animation.core.snap
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
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.sizeIn
import androidx.compose.foundation.layout.statusBars
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.BlurredEdgeTreatment
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.blur
import androidx.compose.ui.graphics.ColorFilter
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.memobook.design.BrandBackdrop
import com.memobook.design.BrandButton
import com.memobook.design.BrandKeyboardDismissBar
import com.memobook.design.BrandSkeleton
import com.memobook.design.BrandText
import com.memobook.design.DeviceScreen
import com.memobook.design.ErrorBanner
import com.memobook.design.MemoBookColor
import com.memobook.design.MemoBookFont
import com.memobook.design.MemoBookShadow
import com.memobook.design.MemoBookSpacing
import com.memobook.design.PlainButtonIndication
import com.memobook.design.R
import com.memobook.design.SwiftMotion
import com.memobook.design.brandFooterScrim
import com.memobook.design.isReduceMotionEnabled
import com.memobook.design.scaled
import com.memobook.feature.HomeIntent
import com.memobook.feature.auth.onHorizontalSwipe
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import java.net.URI
import kotlin.math.abs

/**
 * Créer un voyage : six étapes, une par question, et rien d'autre à l'écran.
 * Jumeau de `TripCreation/TripCreationView.swift`.
 *
 * **Toutes les étapes ont la même charpente** — la flèche et « Passer » en
 * haut, l'illustration, la frise, le titre vert, ce qu'on remplit, et le
 * bouton en bas. Seul le milieu change. C'est ce qui rend la traversée
 * lisible : on ne réapprend pas l'écran à chaque question, on ne lit que ce qui
 * bouge.
 *
 * **L'écran ne navigue pas.** Il émet une [HomeIntent] à la fin, comme
 * l'accueil et la galerie : `RootView` décide que « Commencer ! » ouvre le
 * voyage qu'on vient de créer.
 *
 * @param inviteBase l'adresse de production, pour le lien d'invitation de la
 *   dernière étape — voir [TripAccessCode].
 * @param onBack refermer l'écran — le `dismiss()` d'iOS.
 */
@Composable
fun TripCreationView(model: TripCreationModel, inviteBase: URI?, onIntent: (HomeIntent) -> Unit, onBack: () -> Unit) {
    val state by model.state.collectAsStateWithLifecycle(context = Dispatchers.Main.immediate)
    val scope = rememberCoroutineScope()
    val reduceMotion = isReduceMotionEnabled()

    var focus by remember { mutableStateOf<TripCreationField?>(null) }

    // La charpente n'est pas encore posée.
    //
    // C'est l'état de la première maquette de la série : le squelette de
    // l'étape, avant l'étape. Il ne couvre plus qu'un moment — la poussée
    // depuis l'accueil, pendant laquelle une illustration qui arrive à
    // mi-course saute. L'enregistrement du voyage, lui, n'attend plus le
    // réseau (Hugo, 01/10/2026) : il n'a plus de squelette.
    var hasSettled by remember { mutableStateOf(false) }

    // Le sens du dernier mouvement : en avant sur « Valider » et « Passer », en
    // arrière sur la flèche. C'est lui qui décide d'où l'illustration arrive et
    // par où elle repart.
    var direction by remember { mutableStateOf(Direction.Forward) }

    // Le squelette : le temps de la poussée, et rien d'autre. La dernière étape
    // se dessine entière dès la validation de la précédente, et seul son code
    // d'accès attend le serveur (Hugo, 29/09 puis 01/10/2026).
    val showsSkeleton = !hasSettled

    LaunchedEffect(Unit) {
        // Le temps de la poussée, pas une seconde de plus : le squelette tient
        // la place, il ne la garde pas.
        delay(350)
        hasSettled = true
    }
    // Les thèmes de la première étape viennent du serveur, et se lisent **en
    // même temps** que la charpente se pose — pas après.
    LaunchedEffect(model) { model.loadThemes() }
    // Le code d'accès, dès que le voyage est enregistré : tout de suite en
    // ligne, au retour du réseau sinon. Quitter l'écran annule l'attente, pas
    // l'envoi.
    LaunchedEffect(state.trip?.id) { model.awaitAccessCode() }

    fun validate() {
        focus = null
        direction = Direction.Forward
        scope.launch { model.validate() }
    }

    /**
     * La flèche du haut. Depuis la première étape il n'y a pas d'étape
     * précédente : elle referme l'écran, ce que le modèle ne peut pas faire à
     * sa place.
     */
    fun goBack() {
        focus = null
        direction = Direction.Backward
        if (!model.goBack()) onBack()
    }

    /**
     * « Commencer ! » : on ouvre le voyage qu'on vient de créer.
     *
     * **Sans `onBack()`.** Refermer l'écran et demander le voyage sont deux
     * changements de pile dans le même geste : lancés d'ici, ils se croisent.
     * C'est `RootView` qui remplace l'étape par le voyage, en une seule
     * écriture. La vue annonce, elle ne navigue pas.
     *
     * Le carnet, lui, existe déjà : il a été enregistré à la validation de
     * l'étape précédente — sur le téléphone, que le serveur l'ait reçu ou non.
     * Sans lui, ou refusé par le serveur, il ne reste qu'à refermer.
     */
    fun finish() {
        val trip = model.trip
        if (trip == null || model.wasRejected) onBack() else onIntent(HomeIntent.OpenTrip(trip.id))
    }

    // **Les étapes se feuillettent au doigt, dans les deux sens** (Hugo,
    // 17/09/2026) : un glissé vers la gauche vaut « Valider », un glissé vers
    // la droite vaut la flèche. Franchement horizontal, pour ne pas prendre le
    // défilement vertical de l'étape ; et jamais depuis la première vers
    // l'accueil — c'est la flèche qui referme.
    val swipe by rememberUpdatedState { dx: Float, dy: Float ->
        if (abs(dx) > 60 && abs(dx) > abs(dy) * 1.5f) {
            if (dx < 0) {
                if (model.state.value.canAdvance) validate()
            } else if (model.state.value.canGoBack) {
                goBack()
            }
        }
    }

    // L'illustration glisse de la largeur de l'écran, pour venir du bord et non
    // de sa propre boîte.
    val travel = with(LocalDensity.current) { DeviceScreen.width().roundToPx() }

    Box(Modifier.fillMaxSize()) {
        BrandBackdrop(Modifier.fillMaxSize())

        BrandKeyboardDismissBar(Modifier.fillMaxSize()) {
            Box(Modifier.fillMaxSize(), contentAlignment = Alignment.TopCenter) {
                Column(
                    Modifier
                        // Largeur du cadre de la maquette, comme sur l'écran de
                        // bienvenue : le contenu se centre au lieu de s'étaler
                        // sur une tablette.
                        .widthIn(max = CONTENT_WIDTH)
                        .fillMaxSize()
                        .windowInsetsPadding(WindowInsets.statusBars)
                        // Le clavier pousse le bouton au-dessus de lui, comme le
                        // `safeAreaInset` d'iOS.
                        .imePadding(),
                ) {
                    Header(
                        canBeSkipped = state.step.canBeSkipped,
                        isDisabled = showsSkeleton,
                        onBack = ::goBack,
                        onSkip = {
                            focus = null
                            direction = Direction.Forward
                            scope.launch { model.skip() }
                        },
                    )

                    if (showsSkeleton) {
                        TripCreationSkeleton(Modifier.weight(1f))
                    } else {
                        // **Tout défile, sauf le bouton.** Même parti pris que
                        // l'écran de bienvenue, et pour la même raison : en
                        // taille de texte accessible, le titre passe de deux
                        // lignes à quatre et l'étape ne tient plus dans
                        // l'écran. Le bouton, lui, reste ancré en bas : c'est la
                        // sortie de l'étape, elle ne se cherche pas.
                        Column(
                            Modifier
                                .weight(1f)
                                .fillMaxWidth()
                                .onHorizontalSwipe(minimumDistance = 30.dp) { dx, dy -> swipe(dx, dy) }
                                .verticalScroll(rememberScrollState()),
                            horizontalAlignment = Alignment.CenterHorizontally,
                        ) {
                            // **Un sticker**, pas une image posée : l'ombre
                            // portée le décolle de la page — Hugo, 14/09/2026.
                            // C'est l'une des deux ombres de la marque, il n'y en
                            // a pas de troisième.
                            //
                            // Et **il glisse** : celui de l'étape suivante arrive
                            // par la droite pendant que celui-ci sort par la
                            // gauche, comme des cartes qu'on fait défiler — le
                            // sens s'inverse sur la flèche de retour. Le reste de
                            // l'étape, lui, se fond : deux mouvements en même
                            // temps se lisent comme un écran qui change, un seul
                            // comme une question qui suit l'autre. En
                            // « Supprimer les animations », un fondu : un dessin
                            // qui traverse l'écran est exactement le genre de
                            // déplacement que ce réglage demande d'éteindre.
                            AnimatedContent(
                                targetState = state.step,
                                transitionSpec = {
                                    val fade = SwiftMotion.smooth<Float>(0.4f)
                                    if (reduceMotion) {
                                        fadeIn(fade) togetherWith fadeOut(fade)
                                    } else {
                                        val motion = SwiftMotion.smooth<IntOffset>(0.4f)
                                        val forward = direction == Direction.Forward
                                        (slideInHorizontally(motion) { if (forward) travel else -travel } + fadeIn(fade)) togetherWith
                                            (slideOutHorizontally(motion) { if (forward) -travel else travel } + fadeOut(fade))
                                    }
                                },
                                label = "illustration",
                            ) { step -> StickerIllustration(step) }

                            TripCreationProgress(
                                current = state.progress,
                                count = state.stepCount,
                                modifier = Modifier.padding(top = MemoBookSpacing.m),
                            )

                            // L'étape change, pas l'écran : la charpente reste
                            // immobile — la frise, le bouton — pendant que le
                            // titre et le contenu se remplacent en fondu.
                            AnimatedContent(
                                targetState = state.step,
                                transitionSpec = {
                                    val fade = if (reduceMotion) snap<Float>() else SwiftMotion.smooth(0.4f)
                                    fadeIn(fade) togetherWith fadeOut(fade)
                                },
                                label = "étape",
                            ) { step ->
                                Column(Modifier.fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally) {
                                    // Le titre prend les lignes qu'il lui faut
                                    // plutôt que de se faire rogner : c'est la
                                    // question de l'étape.
                                    BrandText(
                                        step.title,
                                        MemoBookFont.h1,
                                        Modifier
                                            .padding(top = MemoBookSpacing.s)
                                            .padding(horizontal = MemoBookSpacing.screenMargin)
                                            .semantics { heading() },
                                        color = MemoBookColor.action,
                                        textAlign = TextAlign.Center,
                                    )

                                    TripCreationStepContent(
                                        model = model,
                                        state = state,
                                        step = step,
                                        focus = focus,
                                        onFocusChange = { focus = it },
                                        inviteBase = inviteBase,
                                        modifier = Modifier
                                            .fillMaxWidth()
                                            .padding(horizontal = MemoBookSpacing.screenMargin)
                                            .padding(top = MemoBookSpacing.m, bottom = MemoBookSpacing.s),
                                        onAdvance = ::validate,
                                    )
                                }
                            }
                        }

                        Footer(
                            errorMessage = state.errorMessage,
                            title = state.step.callToAction,
                            isEnabled = state.canValidate && !state.isSaving,
                        ) {
                            if (state.step == TripCreationStep.Companions) finish() else validate()
                        }
                    }
                }
            }
        }
    }
}

private enum class Direction { Forward, Backward }

/**
 * L'illustration de l'étape, en **sticker** : son ombre suit le détourage du
 * dessin, ce qui fait le sticker (le `.brandShadow(.raised)` d'iOS sur une
 * image). `dropShadow` ne sait suivre qu'une forme : l'ombre est donc le dessin
 * lui-même, teint et flouté sous l'original, à la mesure de l'ombre « Raised ».
 * Avant Android 12, le flou n'existe pas : l'ombre s'efface plutôt que de
 * doubler le dessin.
 */
@Composable
private fun StickerIllustration(step: TripCreationStep) {
    val painter = painterResource(step.illustration)
    val shadow = MemoBookShadow.Raised
    Box(
        Modifier
            .padding(top = MemoBookSpacing.m)
            .sizeIn(maxWidth = 180.dp, maxHeight = 150.dp)
            .clearAndSetSemantics {},
    ) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            Image(
                painter,
                contentDescription = null,
                contentScale = ContentScale.Fit,
                colorFilter = ColorFilter.tint(shadow.color),
                modifier = Modifier
                    .matchParentSize()
                    .offset(y = shadow.offsetY)
                    .blur(shadow.radius / 2, BlurredEdgeTreatment.Unbounded),
            )
        }
        Image(painter, contentDescription = null, contentScale = ContentScale.Fit)
    }
}

/** Largeur du cadre de la maquette : au-delà, la colonne se centre. */
private val CONTENT_WIDTH = 390.dp

// MARK: - L'en-tête

/**
 * La flèche et « Passer ». Ils restent en place pendant le squelette, grisés :
 * l'écran qui se pose ne doit pas non plus faire clignoter son en-tête.
 */
@Composable
private fun Header(canBeSkipped: Boolean, isDisabled: Boolean, onBack: () -> Unit, onSkip: () -> Unit) {
    Row(
        Modifier
            .fillMaxWidth()
            .alpha(if (isDisabled) 0.4f else 1f)
            .padding(horizontal = MemoBookSpacing.screenMargin)
            .padding(top = MemoBookSpacing.xs),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        // La cible tactile est alignée à gauche sur la marge de la colonne, et
        // le dessin est posé dedans — comme sur le profil et la galerie.
        Box(
            Modifier
                .size(MemoBookSpacing.minimumTapTarget)
                .clickable(interactionSource = null, indication = PlainButtonIndication, enabled = !isDisabled, role = Role.Button, onClick = onBack)
                .semantics { contentDescription = "Revenir à l’étape précédente" },
            contentAlignment = Alignment.CenterStart,
        ) {
            Image(
                painterResource(R.drawable.icon_arrow_duo),
                contentDescription = null,
                modifier = Modifier.size(MemoBookSpacing.navigationIcon),
            )
        }

        Spacer(Modifier.weight(1f))

        // La dernière étape n'a rien à passer : le voyage est créé, le code
        // d'accès est là, il n'y a plus que « Commencer ! » — Hugo, 14/09/2026.
        // Un « Passer » à côté laissait croire qu'on pouvait encore éviter
        // quelque chose. Le nom non plus : la base l'exige, et un « Passer » qui
        // posait « Mon voyage » à sa place trompait sur ce qu'on venait de faire
        // (Hugo, 29/09/2026). Les dates non plus (01/10/2026) : « Valider »
        // reste gris tant que le départ n'est pas posé.
        if (canBeSkipped) {
            Box(
                Modifier
                    .heightIn(min = MemoBookSpacing.minimumTapTarget)
                    .clickable(interactionSource = null, indication = PlainButtonIndication, enabled = !isDisabled, role = Role.Button, onClick = onSkip),
                contentAlignment = Alignment.Center,
            ) {
                BrandText("Passer", MemoBookFont.body, color = MemoBookColor.inkMuted)
            }
        }
    }
}

// MARK: - Le pied

/**
 * Le bouton, et l'erreur au-dessus de lui. Le contenu défile sous le bouton :
 * le voile de la marque l'en décolle sans poser un bandeau opaque sur le motif
 * de fond, et descend jusqu'au bord de la dalle — voir `BrandFooterScrim`.
 */
@Composable
private fun Footer(errorMessage: String?, title: String, isEnabled: Boolean, onClick: () -> Unit) {
    Column(
        Modifier
            .fillMaxWidth()
            .brandFooterScrim()
            .windowInsetsPadding(WindowInsets.navigationBars)
            .padding(horizontal = MemoBookSpacing.screenMargin)
            .padding(top = MemoBookSpacing.xs, bottom = MemoBookSpacing.s),
        verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.xs),
    ) {
        errorMessage?.let { ErrorBanner(it) }
        BrandButton(title, fillsWidth = true, enabled = isEnabled, action = onClick)
    }
}

// MARK: - La frise

/**
 * Une barre par étape, la verte étant celle qu'on remplit.
 *
 * Elle reprend le dessin de `BrandWaveform` — des capsules fines et
 * espacées — et ce n'est pas un hasard de maquette : MemoBook se remplit à la
 * voix, et remplir un formulaire y ressemble à parler. La barre en cours est
 * plus haute, comme une syllabe qu'on prononce, et **ses deux voisines la
 * suivent d'un cran** : c'est le mouvement d'une barre à l'autre qu'on voit,
 * pas une position (Hugo, 14/09/2026). Aux deux bouts il n'y a qu'une voisine,
 * et c'est elle seule qui monte.
 *
 * Le passage d'une étape à l'autre est une **onde** : chaque barre se met à sa
 * hauteur avec un ressort, et un léger retard proportionnel à sa distance à la
 * barre verte — la vague part d'elle et se propage. En « Supprimer les
 * animations », les hauteurs se posent sans mouvement.
 *
 * @param count combien de barres : les étapes **traversées**, pas toutes celles
 *   que le code connaît.
 */
@Composable
internal fun TripCreationProgress(current: Int, modifier: Modifier = Modifier, count: Int = TripCreationStep.active.size) {
    val reduceMotion = isReduceMotionEnabled()
    val barWidth = scaled(3.dp)
    val restingHeight = scaled(12.dp)
    val neighbourHeight = scaled(15.dp)
    val activeHeight = scaled(18.dp)

    Row(
        modifier
            .height(activeHeight)
            .clearAndSetSemantics { contentDescription = "Étape ${current + 1} sur $count" },
        horizontalArrangement = Arrangement.spacedBy(5.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        repeat(count) { index ->
            val distance = abs(index - current)
            val target = when (distance) {
                0 -> activeHeight
                1 -> neighbourHeight
                else -> restingHeight
            }
            // Le retard d'abord, le ressort ensuite : chaque barre part un
            // peu après sa voisine, et la vague se propage.
            val delayedTarget = rememberDelayed(target, delayMillis = distance * 50L, enabled = !reduceMotion)
            val height by animateDpAsState(
                delayedTarget,
                // Le `.spring(duration: 0.55, bounce: 0.35)` d'iOS.
                if (reduceMotion) snap() else SwiftMotion.spring(response = 0.55f, dampingFraction = 0.65f),
                label = "barre",
            )
            Box(
                Modifier
                    .width(barWidth)
                    .height(height)
                    .background(if (distance == 0) MemoBookColor.action else MemoBookColor.inkFaint, RoundedCornerShape(percent = 50)),
            )
        }
    }
}

/**
 * La hauteur visée par une barre, suivie avec un retard : Compose n'a pas le
 * `.delay(_:)` d'une animation SwiftUI, et c'est ce retard qui fait l'onde. Le
 * premier passage, lui, se pose tout de suite.
 */
@Composable
private fun rememberDelayed(value: Dp, delayMillis: Long, enabled: Boolean): Dp {
    var shown by remember { mutableStateOf(value) }
    LaunchedEffect(value) {
        if (enabled && delayMillis > 0) delay(delayMillis)
        shown = value
    }
    return shown
}

// MARK: - Le squelette

/**
 * La place de l'étape, avant l'étape — la première maquette de la série.
 *
 * Elle reprend la charpente au pixel près : l'illustration, la frise, les deux
 * lignes du titre, ce qu'on remplit, et le bouton. C'est la seule façon que
 * rien ne bouge quand le contenu arrive.
 */
@Composable
internal fun TripCreationSkeleton(modifier: Modifier = Modifier) {
    Column(
        modifier
            .fillMaxWidth()
            .clearAndSetSemantics { contentDescription = "Chargement" },
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        BrandSkeleton(Modifier.padding(top = MemoBookSpacing.m), width = 150.dp, height = 150.dp, cornerRadius = MemoBookSpacing.overlayCornerRadius)

        BrandSkeleton(Modifier.padding(top = MemoBookSpacing.m + 8.dp), width = 60.dp, height = 10.dp)

        Column(
            Modifier.padding(top = MemoBookSpacing.m),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.xs + 4.dp),
        ) {
            BrandSkeleton(width = 180.dp, height = 18.dp)
            BrandSkeleton(width = 240.dp, height = 18.dp)
        }

        BrandSkeleton(
            Modifier
                .padding(horizontal = MemoBookSpacing.screenMargin)
                .padding(top = MemoBookSpacing.l),
            height = MemoBookSpacing.fieldHeight,
            cornerRadius = MemoBookSpacing.largeCornerRadius,
        )

        Spacer(Modifier.weight(1f).heightIn(min = MemoBookSpacing.m))

        BrandSkeleton(
            Modifier
                .windowInsetsPadding(WindowInsets.navigationBars)
                .padding(horizontal = MemoBookSpacing.screenMargin)
                .padding(bottom = MemoBookSpacing.s),
            height = MemoBookSpacing.controlHeight,
            cornerRadius = MemoBookSpacing.controlCornerRadius,
        )
    }
}

@Preview(locale = "fr-rFR", name = "Créer un voyage", widthDp = 390, heightDp = 844)
@Composable
private fun TripCreationViewPreview() {
    val model = remember { TripCreationModel() }
    Box(Modifier.background(MemoBookColor.background)) {
        TripCreationView(model, inviteBase = null, onIntent = {}, onBack = {})
    }
}
