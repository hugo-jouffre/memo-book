package com.memobook.feature.trip

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.animateContentSize
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.layout.layout
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.memobook.core.Destination
import com.memobook.core.TripDetail
import com.memobook.core.TripStep
import com.memobook.design.BrandButton
import com.memobook.design.BrandRefreshFlash
import com.memobook.design.BrandSheetHost
import com.memobook.design.BrandSkeleton
import com.memobook.design.BrandText
import com.memobook.design.DeviceScreen
import com.memobook.design.ErrorBanner
import com.memobook.design.MemoBookColor
import com.memobook.design.MemoBookFont
import com.memobook.design.MemoBookSpacing
import com.memobook.design.R
import com.memobook.design.SwiftMotion
import com.memobook.feature.LocalTripsAwaitingServer
import com.memobook.feature.TripIntent
import com.memobook.feature.home.FixtureTripId
import com.memobook.networking.ApiError
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import java.io.IOException
import kotlin.math.min

/**
 * L'accueil d'un voyage : où on en est de celui-ci, et la relance de MemoBook
 * juste au-dessus du micro. Jumeau de `Trip/TripHomeView.swift`.
 *
 * **L'écran ne contient aucun contenu.** Titre, compteurs, co-voyageurs, pays,
 * relance, étapes : tout vient du `TripDetail` que porte [TripHomeModel]. Ce
 * qui est écrit ici, ce sont les seuls libellés qui appartiennent à
 * l'interface.
 *
 * **Deux couches, et une seule qui défile.** La photo occupe le haut de la
 * page et passe sous la barre d'état (`RootView` y coupe son voile) ; le
 * panneau crème remonte par-dessus elle, coins arrondis, et porte tout le
 * reste. Les deux défilent ensemble : c'est ce qui fait qu'on « entre » dans
 * le voyage plutôt que de consulter une fiche.
 *
 * @param onIntent ce que l'écran demande à l'app de faire. Il ne navigue pas
 *   lui-même — voir [TripIntent].
 * @param onBack la flèche de retour, le `dismiss()` d'iOS.
 */
@Composable
fun TripHomeView(model: TripHomeModel, onIntent: (TripIntent) -> Unit, onBack: () -> Unit) {
    val state by model.state.collectAsStateWithLifecycle(context = Dispatchers.Main.immediate)
    val scope = rememberCoroutineScope()

    // Les voyages que le serveur n'a pas encore reçus — voir `TripAwaitingServer`.
    val tripsAwaitingServer = LocalTripsAwaitingServer.current

    // La boîte « Disponible dès ta reconnexion », le temps de la lire.
    var showsAwaitingServer by remember { mutableStateOf(false) }

    // L'étape dont la croix a été touchée : la feuille de confirmation est
    // ouverte sur elle (T235).
    var stepToDelete by remember { mutableStateOf<TripStep?>(null) }

    LaunchedEffect(model) { model.load() }

    /** Ouvre une porte du serveur, ou dit pourquoi elle est fermée. */
    fun open(intent: TripIntent, isAwaitingServer: Boolean) {
        if (isAwaitingServer) showsAwaitingServer = true else onIntent(intent)
    }

    Box(
        Modifier
            .fillMaxSize()
            .background(MemoBookColor.background),
    ) {
        // Sous les commandes de la photo, qu'elle ne doit pas recouvrir.
        AwaitingServerNotice(
            isPresented = showsAwaitingServer,
            onIsPresentedChange = { showsAwaitingServer = it },
            below = DeviceScreen.topSafeInset() + MemoBookSpacing.xs + MemoBookSpacing.minimumTapTarget,
        ) {
            Refreshable(onRefresh = { model.load() }) {
                // L'écran s'ouvre sur le voyage qu'on avait ; quand le serveur
                // en dit plus — une étape de plus, des pages composées —, ça
                // s'anime.
                BrandRefreshFlash(state.freshness.isUpdated) {
                    Column(
                        Modifier
                            .fillMaxSize()
                            .verticalScroll(rememberScrollState()),
                    ) {
                        // **L'en-tête est là dès la première image, chargé ou
                        // non.** Sans lui, l'écran s'ouvrait sur un aplat crème
                        // vide : pas de photo, pas de titre, et surtout pas de
                        // flèche de retour — on ne pouvait que subir l'attente.
                        // Le remplaçant a la même hauteur et porte la même
                        // flèche ; seules la photo et les mots arrivent après.
                        val detail = state.detail
                        if (detail != null) {
                            // Créé hors ligne et pas encore reçu : les trois
                            // portes du serveur pâlissent, et l'appui dit
                            // pourquoi (T239).
                            val isAwaitingServer = detail.trip.id in tripsAwaitingServer
                            TripHeader(
                                detail = detail,
                                onBack = onBack,
                                onPrint = { open(TripIntent.OpenBookPreview(detail.trip.id), isAwaitingServer) },
                                // L'identifiant vient du voyage **chargé** et
                                // non de celui passé à l'écran : c'est le même,
                                // et celui-là est déjà en portée. En garder une
                                // copie dans la vue aurait fait deux vérités
                                // pour la même valeur.
                                onSettings = { open(TripIntent.OpenSettings(detail.trip.id), isAwaitingServer) },
                                onInvite = { open(TripIntent.InviteCompanions(detail.trip.id), isAwaitingServer) },
                                isAwaitingServer = isAwaitingServer,
                            )
                        } else {
                            TripHeaderPlaceholder(onBack = onBack)
                        }

                        Canopy(
                            model = model,
                            state = state,
                            onIntent = onIntent,
                            onRetry = { scope.launch { model.load() } },
                            onDeleteStep = { stepToDelete = it },
                        )
                    }
                }
            }
        }
    }

    BrandSheetHost(
        item = stepToDelete,
        onDismissRequest = { stepToDelete = null },
        dismissDisabled = state.deletingStepId != null,
    ) { step ->
        DeleteStepSheet(
            step = step,
            isDeleting = state.deletingStepId == step.id,
            errorMessage = state.stepDeletionError,
            onKeep = { stepToDelete = null },
            onDelete = {
                scope.launch {
                    if (model.deleteMemories(step)) stepToDelete = null
                }
            },
        )
        // Le `.onDisappear` d'iOS : la feuille refermée oublie son erreur.
        DisposableEffect(step) { onDispose { model.dismissStepDeletionError() } }
    }
}

/** Le libellé du bouton vert. « Continuer à enregistrer » disait le micro ; le bouton ouvre la conversation — Hugo a changé d'avis le 15/09/2026. */
private const val CALL_TO_ACTION = "Accéder au chat"

/**
 * Le panneau crème qui recouvre le bas de la photo.
 *
 * Le panneau mord sur la photo : c'est ce chevauchement qui fait qu'il la
 * recouvre au lieu d'être posé en dessous.
 *
 * **Il mord d'exactement son rayon, pas moins.** À 24 pour un rayon de 40,
 * les 16 derniers points de l'arrondi tombaient sous le bas de la photo : la
 * courbe se posait alors sur le crème de la page, du crème sur du crème, et le
 * coin se lisait comme tranché à plat. Le lien entre les deux valeurs n'est
 * donc pas un réglage, c'est une contrainte — d'où la constante et non un
 * nombre. (Compose n'a pas de marge négative : la mise en page déclare une
 * hauteur réduite du rayon et pose le panneau d'autant plus haut.)
 */
@Composable
private fun Canopy(
    model: TripHomeModel,
    state: TripHomeModel.State,
    onIntent: (TripIntent) -> Unit,
    onRetry: () -> Unit,
    onDeleteStep: (TripStep) -> Unit,
) {
    val overlap = MemoBookSpacing.overlayCornerRadius
    val shape = RoundedCornerShape(topStart = overlap, topEnd = overlap)

    Column(
        Modifier
            .layout { measurable, constraints ->
                val shift = overlap.roundToPx()
                val placeable = measurable.measure(constraints)
                layout(placeable.width, placeable.height - shift) { placeable.place(0, -shift) }
            }
            .fillMaxWidth()
            .background(MemoBookColor.background, shape)
            .padding(top = MemoBookSpacing.l, bottom = MemoBookSpacing.xl)
            .animateContentSize(SwiftMotion.snappy(0.25f)),
        verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.m),
    ) {
        state.errorMessage?.let { message ->
            ErrorBanner(message, Modifier.padding(horizontal = MemoBookSpacing.screenMargin), retry = onRetry)
        }

        AnimatedVisibility(visible = state.confirmation != null, enter = fadeIn(), exit = fadeOut()) {
            BrandText(
                state.confirmation.orEmpty(),
                MemoBookFont.caption,
                Modifier
                    .fillMaxWidth()
                    .padding(horizontal = MemoBookSpacing.screenMargin),
                color = MemoBookColor.valid,
                textAlign = TextAlign.Center,
            )
        }

        val detail = state.detail
        if (detail != null) {
            Header(detail, Modifier.padding(horizontal = MemoBookSpacing.screenMargin)) {
                onIntent(TripIntent.TellMore(detail.trip.id))
            }

            TripStepsSection(
                model = model,
                state = state,
                onOpenStep = { step -> onIntent(TripIntent.OpenStep(detail.trip.id, step.id)) },
                onValidateStep = model::validateStep,
                onDeleteStep = onDeleteStep,
            )
        } else if (state.errorMessage == null) {
            LoadingHeader(Modifier.padding(horizontal = MemoBookSpacing.screenMargin))

            TripStepsPlaceholder()
        }
    }
}

/**
 * Le haut du panneau pendant l'attente : la place du pays, celle de la
 * relance, et **le vrai bouton**, désactivé.
 *
 * Le bouton n'est pas un squelette parce qu'il n'en est pas un : son libellé
 * n'a jamais dépendu du serveur. Le montrer tout de suite dit ce que l'écran
 * va proposer ; le remplacer par une barre grise ferait douter qu'il y en ait
 * un.
 */
@Composable
private fun LoadingHeader(modifier: Modifier = Modifier) {
    Column(
        modifier.fillMaxWidth(),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.s),
    ) {
        BrandSkeleton(width = 96.dp)

        // La relance est un titre : ses deux barres tiennent la hauteur qu'il
        // prendra, pour que le bouton ne saute pas en arrivant.
        Column(
            Modifier.height(MemoBookSpacing.xl + MemoBookSpacing.xs),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.xs, Alignment.CenterVertically),
        ) {
            BrandSkeleton(width = 260.dp)
            BrandSkeleton(width = 190.dp)
        }

        CappedAtFirstAccessibilitySize {
            BrandButton(
                CALL_TO_ACTION,
                Modifier.padding(top = MemoBookSpacing.xs),
                icon = painterResource(R.drawable.icon_bubble),
                iconPlacement = BrandButton.IconPlacement.Trailing,
                fillsWidth = true,
                enabled = false,
            ) {}
        }
    }
}

/**
 * Le pays, la relance, et le micro. Trois blocs qui se lisent d'un trait : où
 * l'on est, ce qu'on nous demande, et de quoi y répondre.
 */
@Composable
private fun Header(detail: TripDetail, modifier: Modifier = Modifier, onTellMore: () -> Unit) {
    Column(
        modifier.fillMaxWidth(),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.s),
    ) {
        detail.trip.destination?.let { CountryLine(it) }

        detail.prompt?.let { prompt ->
            BrandText(
                prompt,
                MemoBookFont.h1,
                Modifier.semantics { heading() },
                color = MemoBookColor.ink,
                textAlign = TextAlign.Center,
            )
        }

        // **« Accéder au chat »**, avec la bulle de la marque en fin de
        // libellé — la flèche disait « plus loin », la bulle dit « la
        // conversation » (Hugo, 17/09/2026). Le bouton mène à la
        // conversation, il n'ouvre pas le micro — c'est là-bas qu'on
        // enregistre (Hugo, 15/09/2026). **Jamais verrouillé** (Hugo,
        // 03/10/2026) : il passait au lime et au cadenas une fois l'essai
        // gratuit d'avant épuisé ; avec le crédit du jour, la conversation
        // s'ouvre toujours — on y lit, on y envoie des photos, et c'est elle
        // qui dit ce qu'il reste à raconter.
        CappedAtFirstAccessibilitySize {
            BrandButton(
                CALL_TO_ACTION,
                Modifier.padding(top = MemoBookSpacing.xs),
                icon = painterResource(R.drawable.icon_bubble),
                iconPlacement = BrandButton.IconPlacement.Trailing,
                fillsWidth = true,
                action = onTellMore,
            )
        }
    }
}

/**
 * Le libellé suit la taille de police, mais s'arrête à la première taille
 * accessible : au-delà, « enregistrer » était plus large que le bouton entier
 * et se coupait en plein mot. TalkBack, lui, lit le libellé complet quelle que
 * soit la taille. Même limite, et même raison, que le CTA de l'accueil. (Le
 * `...accessibility1` d'iOS : ×1,5 ici, le seuil des tailles accessibles
 * d'Android, comme le pied du paywall.)
 */
@Composable
private fun CappedAtFirstAccessibilitySize(content: @Composable () -> Unit) {
    val density = LocalDensity.current
    CompositionLocalProvider(LocalDensity provides Density(density.density, fontScale = min(density.fontScale, 1.5f)), content = content)
}

@Composable
private fun CountryLine(destination: Destination) {
    Row(
        Modifier.clearAndSetSemantics { contentDescription = destination.name },
        horizontalArrangement = Arrangement.spacedBy(MemoBookSpacing.xs),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        destination.flag?.let { BrandText(it, MemoBookFont.body) }
        BrandText(
            destination.name.uppercase(),
            MemoBookFont.overline.copy(letterSpacing = MemoBookFont.tracking),
            color = MemoBookColor.ink,
        )
    }
}

// MARK: - Aperçus

@Preview(locale = "fr-rFR", name = "Voyage", widthDp = 390, heightDp = 1200)
@Composable
private fun TripHomeViewPreview() {
    val model = remember { TripHomeModel(tripId = FixtureTripId.rome) }
    TripHomeView(model, onIntent = {}, onBack = {})
}

@Preview(locale = "fr-rFR", name = "Voyage — plusieurs pays", widthDp = 390, heightDp = 1200)
@Composable
private fun TripHomeViewWorldPreview() {
    val model = remember { TripHomeModel(tripId = FixtureTripId.tourDuMonde) }
    TripHomeView(model, onIntent = {}, onBack = {})
}

@Preview(locale = "fr-rFR", name = "Voyage — erreur", widthDp = 390, heightDp = 844)
@Composable
private fun TripHomeViewErrorPreview() {
    val model = remember {
        TripHomeModel(tripId = FixtureTripId.rome, source = { throw ApiError.Transport(IOException("hors ligne"), url = null) })
    }
    TripHomeView(model, onIntent = {}, onBack = {})
}

@Preview(locale = "fr-rFR", name = "Voyage — AX3", widthDp = 390, heightDp = 1600, fontScale = 2f)
@Composable
private fun TripHomeViewAccessibilityPreview() {
    val model = remember { TripHomeModel(tripId = FixtureTripId.rome) }
    TripHomeView(model, onIntent = {}, onBack = {})
}
