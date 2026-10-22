package com.memobook.feature.paywall

import android.accessibilityservice.AccessibilityServiceInfo
import android.view.accessibility.AccessibilityManager
import androidx.activity.compose.BackHandler
import androidx.annotation.DrawableRes
import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutVertically
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.ColorFilter
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.lifecycle.viewmodel.compose.viewModel
import com.memobook.core.Subscription
import com.memobook.core.offeredPrice
import com.memobook.design.BrandAlert
import com.memobook.design.BrandMarkBackdrop
import com.memobook.design.BrandSheetHost
import com.memobook.design.BrandText
import com.memobook.design.MemoBookColor
import com.memobook.design.MemoBookFont
import com.memobook.design.MemoBookSpacing
import com.memobook.design.PlainButtonIndication
import com.memobook.design.R
import com.memobook.design.SwiftMotion
import com.memobook.design.isReduceMotionEnabled
import com.memobook.feature.LegalRoute
import com.memobook.feature.PaywallVariant
import com.memobook.feature.bookpreview.BookPreviewSheet
import com.memobook.feature.legal.LegalDocumentEntry
import com.memobook.feature.profile.euros
import com.memobook.feature.support.LocalSupportModel
import com.memobook.feature.support.SupportModel
import com.memobook.feature.support.SupportView
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlin.math.max

/**
 * Le paywall : des écrans qui se suivent tout seuls, comme des stories. Jumeau
 * de `Paywall/PaywallView.swift`.
 *
 * **Il vend l'illimité, pas le droit de raconter** (Hugo, 03/10/2026). Tout le
 * monde raconte cinq minutes par jour et par voyage ; l'abonnement, 4,99 € par
 * mois, rend le récit illimité pour l'abonné. Le paywall s'ouvre donc sur une
 * envie — « Tu as tant de choses à raconter ! » —, jamais sur un mur : on peut
 * le refermer et continuer demain.
 *
 * **Deux versions, un seul mécanisme.** Celle qu'on voit la première fois
 * compte trois écrans et explique tout ; celle qu'on revoit quand on a déjà été
 * abonné en compte deux et ne réexplique rien. Le minuteur, les zones de
 * tapotis, la barre du haut et le comportement du dernier écran sont les mêmes :
 * c'est [PaywallVariant] qui dit lesquels, et rien d'autre ne change. Qui
 * l'ouvre la lit sur `SubscriptionSession.paywallVariant`.
 *
 * **Le temps passe tout seul, mais on peut le doubler.** La barre du haut se
 * remplit à vue d'œil et fait passer à la suite quand elle est pleine ; un
 * tapotis à droite avance, à gauche revient — le geste que tout le monde
 * connaît d'Instagram. **Un doigt posé arrête le temps** (Hugo, 02/10/2026) —
 * voir [PaywallStoryTouchZone]. Le dernier écran, lui, **ne se referme pas** :
 * c'est celui qui porte l'offre, il attend qu'on décide.
 *
 * **Rien ne bouge en Reduce Motion.** Les barres sont remplies d'avance, les
 * traits déjà tracés, et l'avancement se fait au doigt.
 *
 * **« Besoin d'aide ? » ouvre le support par-dessus l'offre**, et le paywall
 * reste monté derrière avec sa page (Hugo, 16/09/2026) : on va chercher de
 * l'aide **pour revenir décider**, et perdre sa place au milieu d'un tunnel
 * d'achat est exactement ce qu'il ne faut pas faire. Le minuteur s'arrête
 * pendant ce temps-là, comme devant l'aperçu.
 *
 * **Plein écran**, posé par-dessus l'écran qui l'ouvre : le retour du système
 * fait ce que fait la flèche — il recule d'un écran, et referme depuis le
 * premier.
 *
 * @param variant première visite, ou retour d'un ancien abonné.
 * @param previewMemoId le carnet que la feuille « Prévisualisation » montre.
 *   `null` — un compte sans voyage en cours — ouvre le jeu d'essai : la feuille
 *   est là pour montrer à quoi ça ressemble, et un aperçu vide ne vendrait rien.
 * @param onSubscribe payé : **c'est l'écran qui a présenté le paywall qui le
 *   referme** ; on revient là d'où l'on venait, l'accueil le plus souvent.
 * @param onDismiss la flèche (ou le retour) depuis le premier écran — le
 *   `dismiss()` d'iOS.
 * @param subscriptionPurchase **l'achat passe par le store, et par lui seul**
 *   (01/10/2026). `null` — un aperçu isolé — fait comme si l'achat avait réussi.
 */
@Composable
fun PaywallView(
    subscription: Subscription?,
    onSubscribe: () -> Unit,
    onDismiss: () -> Unit,
    modifier: Modifier = Modifier,
    variant: PaywallVariant = PaywallVariant.FirstTime,
    previewMemoId: String? = null,
    subscriptionPurchase: SubscriptionPurchase? = LocalSubscriptionPurchase.current,
) {
    val reduceMotion = isReduceMotionEnabled()
    val assistiveNavigation = rememberAssistiveNavigationIsOn()
    val scope = rememberCoroutineScope()
    val pageCount = variant.pageCount

    var page by rememberSaveable { mutableIntStateOf(0) }
    var showsPreview by rememberSaveable { mutableStateOf(false) }
    // Le support, ouvert **par-dessus** le paywall par « Besoin d'aide ? ».
    var showsHelp by rememberSaveable { mutableStateOf(false) }
    // Les conditions ou la politique de confidentialité, ouvertes depuis le pied
    // de l'offre — exigées à côté du bouton d'un abonnement.
    var legalDocument by rememberSaveable { mutableStateOf<LegalRoute?>(null) }

    // La feuille du store est ouverte, ou le serveur n'a pas encore répondu :
    // le bouton attend, et un second tapotis ne lance pas un second achat.
    var isPurchasing by remember { mutableStateOf(false) }
    // « Restaurer mes achats » attend le store.
    var isRestoring by remember { mutableStateOf(false) }
    // Ce qu'il faut dire quand l'achat n'a pas ouvert l'abonnement.
    var purchaseNotice by remember { mutableStateOf<PurchaseNotice?>(null) }

    // Le prix tel que le store le facture dans le pays du compte. **C'est lui
    // qui s'affiche dès qu'il est là** : le store a le dernier mot sur le
    // montant, et l'écran ne doit pas annoncer autre chose que ce que sa feuille
    // demandera. La période vient du même produit, pour la même raison.
    var storePrice by remember { mutableStateOf<String?>(null) }
    var storePeriod by remember { mutableStateOf<String?>(null) }

    // Où en est la barre de l'écran courant — voir `PaywallFill`. C'est elle
    // que le segment lit à chaque image ; le minuteur tourne la page sur la
    // même date de départ.
    var fill by remember { mutableStateOf<PaywallFill>(PaywallFill.Held(0.0)) }

    // Les zones où un doigt est posé. Un ensemble et non un booléen : un pouce
    // posé sur la bande basse et un tapotis sur une moitié, le tapotis levé ne
    // doit pas relancer le temps sous le pouce.
    var heldZones by remember { mutableStateOf(emptySet<HoldZone>()) }

    // Le temps ne passe que si l'on regarde l'écran : rien par-dessus, et pas
    // de doigt qui le tient.
    val isPaused = showsPreview || showsHelp || heldZones.isNotEmpty()

    // Le prix de l'offre — celui du store dès qu'il est là, sinon celui du
    // serveur s'il est mensuel, sinon 4,99 € (`Subscription.offer`).
    val price = storePrice ?: subscription.offeredPrice.euros
    val period = storePeriod ?: Subscription.offer.periodLabel

    fun turn(step: Int) {
        val next = page + step
        if (next < 0) {
            // Revenir en arrière depuis le premier écran, c'est sortir.
            onDismiss()
            return
        }
        if (next >= pageCount) return
        // **La barre qu'on quitte se finit, celle qu'on ouvre part de zéro** —
        // posée à zéro dans la même passe que la page, pour qu'aucune image ne
        // montre le nouvel écran avec l'avancement de l'ancien ; le minuteur
        // relancé la fait repartir aussitôt.
        fill = PaywallFill.Held(0.0)
        page = next
    }

    fun hold(zone: HoldZone, isDown: Boolean) {
        heldZones = if (isDown) heldZones + zone else heldZones - zone
    }

    // Achète l'abonnement. Sans achat possible — un aperçu isolé, sans
    // compte —, l'offre fait comme si c'était fait : un aperçu n'a rien à
    // encaisser.
    fun purchase() {
        if (isPurchasing || isRestoring) return
        val store = subscriptionPurchase ?: return onSubscribe()
        isPurchasing = true
        scope.launch {
            val outcome = store.purchase(previewMemoId)
            isPurchasing = false
            when (outcome) {
                PurchaseOutcome.Subscribed, PurchaseOutcome.AwaitingServer -> onSubscribe()
                PurchaseOutcome.Pending -> purchaseNotice = PurchaseNotice.Pending
                PurchaseOutcome.Cancelled -> Unit
                is PurchaseOutcome.Failed -> purchaseNotice = PurchaseNotice.Failed(outcome.message)
            }
        }
    }

    // « Restaurer mes achats » : un abonnement pris sur un autre téléphone, ou
    // avant une réinstallation, se retrouve ici. Retrouvé : l'abonnement
    // s'ouvre et l'offre se referme, comme après un achat. Rien de payé : on le
    // dit. La personne referme la demande du store : on ne dit rien, c'est un
    // choix. Un abonnement payé depuis un autre compte MemoBook : le message du
    // serveur le dit.
    fun restore() {
        if (isPurchasing || isRestoring) return
        val store = subscriptionPurchase ?: run {
            // Un aperçu isolé n'a pas de store à interroger.
            purchaseNotice = PurchaseNotice.NothingToRestore
            return
        }
        isRestoring = true
        scope.launch {
            try {
                when (store.restore()) {
                    RestoreOutcome.Restored -> onSubscribe()
                    RestoreOutcome.NothingToRestore -> purchaseNotice = PurchaseNotice.NothingToRestore
                    RestoreOutcome.Cancelled -> Unit
                }
            } catch (error: CancellationException) {
                throw error
            } catch (error: Exception) {
                purchaseNotice = PurchaseNotice.Failed(error.message.orEmpty())
            } finally {
                isRestoring = false
            }
        }
    }

    LaunchedEffect(subscriptionPurchase) {
        storePrice = subscriptionPurchase?.displayPrice()
        storePeriod = subscriptionPurchase?.displayPeriod()
    }

    // **Un seul minuteur, et il est structuré.** L'identité porte la page *et*
    // l'état de ce qui la recouvre : ouvrir l'aperçu annule la tâche en cours,
    // le refermer en démarre une neuve. Changer de page annule celle-ci, et
    // Compose en relance une pour la suivante — une tâche détachée qu'on
    // annulerait à la main enchaînait deux écrans d'un coup sur iOS.
    LaunchedEffect(page, isPaused, reduceMotion, assistiveNavigation) {
        val duration = PaywallMetrics.pageDurationMillis
        // Quelque chose recouvre la page, ou un doigt la tient : le temps
        // s'arrête, et la barre se **fige** là où elle en était.
        if (isPaused) {
            (fill as? PaywallFill.Running)?.let {
                fill = PaywallFill.Held(PaywallFill.fraction(it.sinceMillis, PaywallClock.now(), duration))
            }
            return@LaunchedEffect
        }
        // En Reduce Motion, aucune page ne tourne toute seule — on remplit la
        // barre pour dire où on en est, et c'est le doigt qui avance. Pareil
        // sous TalkBack ou Switch Access : on ne peut pas y poser le doigt pour
        // tenir la page (les zones sont cachées à l'accessibilité), et une page
        // qui tourne pendant la lecture coupe la phrase.
        if (reduceMotion || assistiveNavigation) {
            fill = PaywallFill.Held(1.0)
            return@LaunchedEffect
        }
        // **Une barre finie ne recommence pas** (Hugo, 19/09/2026).
        val held = fill as? PaywallFill.Held
        if (held != null && held.value >= 1) return@LaunchedEffect

        // La barre repart d'où elle s'était figée — un aperçu refermé, un doigt
        // levé reprennent le décompte, ils ne le recommencent pas.
        var since = PaywallClock.now()
        if (held != null && held.value > 0 && held.value < 1) since -= (held.value * duration).toLong()
        fill = PaywallFill.Running(since)

        delay(max(0L, duration - (PaywallClock.now() - since)))

        // Le dernier écran porte l'offre : il ne s'en va pas tout seul. Sa barre
        // se remplit **au même rythme que les deux autres** (Clara,
        // 17/09/2026) et reste pleine.
        if (page >= pageCount - 1) {
            fill = PaywallFill.Held(1.0)
        } else {
            turn(+1)
        }
    }

    // Le retour du système fait ce que fait la flèche.
    BackHandler(enabled = !showsHelp && legalDocument == null) { turn(-1) }

    Box(
        modifier
            .fillMaxSize()
            .background(MemoBookColor.background),
    ) {
        // Plus discret que sur l'accueil : ici le signe passe **derrière un
        // écran entier de texte**, et à l'opacité de repos il se lisait à
        // travers les titres. Le cadrage est celui du design system, **le même
        // partout** (T63, 17/09/2026).
        BrandMarkBackdrop(progress = 1f, opacity = PaywallMetrics.backdropOpacity)

        // **Les zones de tapotis sont sous le contenu**, et non par-dessus.
        // Posées au-dessus, elles avalaient tout contrôle qui ne tombait pas
        // dans la bande basse épargnée — la pastille « Voir un aperçu » tournait
        // la page au lieu d'ouvrir la feuille.
        //
        // **Un doigt posé arrête le temps partout**, bande basse comprise : elle
        // ne tourne rien, mais un doigt qui se pose à côté du bouton pour finir
        // sa lecture doit tenir la page comme ailleurs.
        Column(
            Modifier
                .fillMaxSize()
                .clearAndSetSemantics {},
        ) {
            Row(Modifier.weight(1f)) {
                PaywallStoryTouchZone(Modifier.weight(1f).fillMaxSize(), onTap = { turn(-1) }, onHold = { hold(HoldZone.Back, it) })
                PaywallStoryTouchZone(Modifier.weight(1f).fillMaxSize(), onTap = { turn(+1) }, onHold = { hold(HoldZone.Forward, it) })
            }
            PaywallStoryTouchZone(
                Modifier
                    .fillMaxWidth()
                    .height(PaywallMetrics.untappableFooter),
                onTap = null,
                onHold = { hold(HoldZone.Footer, it) },
            )
        }

        Column(
            Modifier
                .fillMaxSize()
                .statusBarsPadding()
                .padding(horizontal = PaywallMetrics.margin),
        ) {
            PaywallHeader(page = page, onBack = { turn(-1) }, onHelp = { showsHelp = true })
            PaywallStoriesBar(
                pageCount = pageCount,
                page = page,
                fill = fill,
                durationMillis = PaywallMetrics.pageDurationMillis,
                modifier = Modifier.padding(top = MemoBookSpacing.s),
            )

            // La transition est un fondu et non un glissé : les trois écrans
            // partagent leur décor, et faire glisser le contenu par-dessus un
            // fond immobile se lit comme un défaut. **Elle ne porte que le
            // contenu** : posée sur la page entière, elle emportait les barres
            // du haut, qui se remplissaient ensemble sur iOS.
            AnimatedContent(
                targetState = page,
                modifier = Modifier
                    .fillMaxWidth()
                    .weight(1f),
                transitionSpec = { fadeIn(SwiftMotion.smooth(0.25f)) togetherWith fadeOut(SwiftMotion.smooth(0.25f)) },
                label = "page",
            ) { shown ->
                Box(Modifier.fillMaxSize()) {
                    when {
                        variant == PaywallVariant.FirstTime && shown == 0 -> PaywallStoriesToTell { turn(+1) }
                        variant == PaywallVariant.FirstTime && shown == 1 -> PaywallFadingDetails(
                            onContinue = { turn(+1) },
                            onPreview = { showsPreview = true },
                        )
                        variant == PaywallVariant.Returning && shown == 0 -> PaywallReturning { turn(+1) }
                        else -> PaywallOffer(
                            price = price,
                            period = period,
                            title = variant.offerTitle,
                            isPurchasing = isPurchasing,
                            isRestoring = isRestoring,
                            onSubscribe = ::purchase,
                            onRestore = ::restore,
                            onShowLegal = { legalDocument = it },
                            onBack = { turn(-1) },
                        )
                    }
                }
            }
        }

        // **Le support, par-dessus l'offre.** Un écran, avec son en-tête et sa
        // flèche — et cette flèche ramène à l'étape du paywall qu'on regardait.
        // Sur le modèle de la session quand il y en a un, sur un modèle neuf
        // sinon : un aperçu doit pouvoir ouvrir l'écran, et la foire aux
        // questions est dans l'app.
        PaywallCover(isPresented = showsHelp, onDismiss = { showsHelp = false }) {
            val support = LocalSupportModel.current ?: viewModel(key = "paywall.previewSupport") { SupportModel() }
            SupportView(support, onBack = { showsHelp = false })
        }

        // Un écran, comme le support : son en-tête porte la flèche qui ramène à
        // l'offre. Sans « Besoin d'aide ? » : on vient de l'offre, qui l'a déjà.
        val shownDocument = remember { RetainedRoute() }
        legalDocument?.let { shownDocument.value = it }
        PaywallCover(isPresented = legalDocument != null, onDismiss = { legalDocument = null }) {
            shownDocument.value?.let { route ->
                LegalDocumentEntry(route.content, showsHelp = false, onIntent = {}, onBack = { legalDocument = null })
            }
        }
    }

    // La feuille se pose **par-dessus le paywall entier**, et non dans une page :
    // on doit pouvoir la refermer et retrouver l'offre exactement où on l'avait
    // laissée.
    BrandSheetHost(isPresented = showsPreview, onDismissRequest = { showsPreview = false }) {
        BookPreviewSheet(memoId = previewMemoId)
    }

    val notice = purchaseNotice
    BrandAlert(
        isPresented = notice != null,
        title = notice?.title.orEmpty(),
        message = notice?.message,
        actions = listOf(BrandAlert.Action(PaywallCopy.Purchase.ok, BrandAlert.Role.Cancel) { purchaseNotice = null }),
        onDismissRequest = { purchaseNotice = null },
    )
}

/** Les trois zones qui tiennent la page sous le doigt. */
private enum class HoldZone { Back, Forward, Footer }

/** Le document qu'on referme, gardé le temps qu'il descende. */
private class RetainedRoute {
    var value: LegalRoute? = null
}

/**
 * La barre du haut : la flèche, et « Besoin d'aide ? ».
 *
 * La flèche **recule d'un écran**, comme le tapotis à gauche ; elle ne referme
 * le paywall que depuis le premier (Hugo, 16/09/2026). Elle refermait tout,
 * d'où qu'on soit : depuis l'offre, on retombait sur le profil au lieu de revoir
 * l'écran d'avant.
 */
@Composable
private fun PaywallHeader(page: Int, onBack: () -> Unit, onHelp: () -> Unit) {
    Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
        Box(
            Modifier
                .size(MemoBookSpacing.minimumTapTarget)
                .clickable(
                    interactionSource = remember { MutableInteractionSource() },
                    indication = PlainButtonIndication,
                    role = Role.Button,
                    onClick = onBack,
                )
                .semantics { contentDescription = if (page == 0) "Fermer" else "Retour" },
            contentAlignment = Alignment.Center,
        ) {
            // La même flèche, à la même taille, que sur tous les écrans poussés
            // — voir `MemoBookSpacing.navigationIcon`.
            Image(
                painterResource(R.drawable.icon_arrow),
                contentDescription = null,
                colorFilter = ColorFilter.tint(MemoBookColor.action),
                modifier = Modifier.size(MemoBookSpacing.navigationIcon),
            )
        }

        Spacer(Modifier.weight(1f))

        // La cible tactile déborde du texte jusqu'à 48 : « Besoin d'aide ? » à
        // 14 fait 15 de haut, et c'est le seul recours de quelqu'un qui bute ici.
        Box(
            Modifier
                .heightIn(min = MemoBookSpacing.minimumTapTarget)
                .clickable(
                    interactionSource = remember { MutableInteractionSource() },
                    indication = PlainButtonIndication,
                    role = Role.Button,
                    onClick = onHelp,
                ),
            contentAlignment = Alignment.Center,
        ) {
            BrandText(PaywallCopy.help, MemoBookFont.h3)
        }
    }
}

/**
 * Un écran posé **par-dessus** le paywall, qui monte du bas — le
 * `fullScreenCover` d'iOS. Le retour du système le referme.
 */
@Composable
private fun PaywallCover(isPresented: Boolean, onDismiss: () -> Unit, content: @Composable () -> Unit) {
    val reduceMotion = isReduceMotionEnabled()
    AnimatedVisibility(
        visible = isPresented,
        enter = if (reduceMotion) fadeIn() else slideInVertically(SwiftMotion.smooth(0.35f)) { it },
        exit = if (reduceMotion) fadeOut() else slideOutVertically(SwiftMotion.smooth(0.3f)) { it },
    ) {
        Box(
            Modifier
                .fillMaxSize()
                .background(MemoBookColor.background),
        ) { content() }
    }
    BackHandler(enabled = isPresented, onBack = onDismiss)
}

/**
 * TalkBack ou Switch Access est allumé : on ne peut pas y poser le doigt pour
 * tenir la page. Relu quand l'un ou l'autre change.
 */
@Composable
private fun rememberAssistiveNavigationIsOn(): Boolean {
    val context = LocalContext.current
    val manager = remember(context) { context.getSystemService(AccessibilityManager::class.java) }
    var isOn by remember(manager) { mutableStateOf(manager.isAssistiveNavigationOn()) }
    DisposableEffect(manager) {
        if (manager == null) return@DisposableEffect onDispose {}
        val state = AccessibilityManager.AccessibilityStateChangeListener { isOn = manager.isAssistiveNavigationOn() }
        val touch = AccessibilityManager.TouchExplorationStateChangeListener { isOn = manager.isAssistiveNavigationOn() }
        manager.addAccessibilityStateChangeListener(state)
        manager.addTouchExplorationStateChangeListener(touch)
        onDispose {
            manager.removeAccessibilityStateChangeListener(state)
            manager.removeTouchExplorationStateChangeListener(touch)
        }
    }
    return isOn
}

private fun AccessibilityManager?.isAssistiveNavigationOn(): Boolean {
    if (this == null || !isEnabled) return false
    if (isTouchExplorationEnabled) return true
    return getEnabledAccessibilityServiceList(AccessibilityServiceInfo.FEEDBACK_ALL_MASK)
        .any { it.id.contains("switchaccess", ignoreCase = true) }
}

// MARK: - Les deux versions

/**
 * Le titre de l'écran d'offre. Il change avec la version : la première fois il
 * vend le carnet (« Ce carnet que tu relieras encore dans 30 ans »), au retour
 * il dit ce qu'on retrouve (« Raconte de nouveau sans compter »).
 *
 * **La version « retour » existe parce qu'on propose de résilier à la fin de
 * chaque voyage.** Quelqu'un qui repart et retrouve l'envie de raconter sans
 * compter se réabonne ; lui rejouer les trois écrans de découverte reviendrait
 * à lui réexpliquer ce qu'il nous a déjà acheté une fois. Elle se décide
 * **partout** sur `SubscriptionSession.paywallVariant` (Hugo, 03/10/2026).
 */
val PaywallVariant.offerTitle: Pair<String, String>
    get() = when (this) {
        PaywallVariant.FirstTime -> PaywallCopy.offerTitleLead to PaywallCopy.offerTitleStrong
        PaywallVariant.Returning -> PaywallCopy.returnOfferTitleLead to PaywallCopy.returnOfferTitleStrong
    }

// MARK: - Mesures et copie

object PaywallMetrics {
    /**
     * La marge de l'écran — **celle de l'app**. L'alias reste parce que les
     * pages le lisent pour déborder de la colonne.
     */
    val margin: Dp = MemoBookSpacing.screenMargin

    /**
     * La bande basse que les zones de tapotis laissent tranquille : le bouton
     * d'abonnement et les pastilles y vivent, et un tapotis qui tourne la page
     * à leur place serait un piège.
     */
    val untappableFooter: Dp = 160.dp

    /** Épaisseur d'un segment de la barre de stories. */
    val storyBarHeight: Dp = 4.dp

    /**
     * Au-delà, un doigt posé ne tapote plus : il tient la page, et ne la tourne
     * pas en se levant. Un tapotis dure un ou deux dixièmes de seconde ; un
     * quart laisse passer les plus appuyés sans faire attendre qui veut lire.
     */
    const val holdDelayMillis: Long = 250

    /**
     * Ce que dure un écran. Assez long pour lire trois lignes de Sora 32 sans se
     * sentir bousculé, assez court pour qu'on n'attende pas la suite.
     */
    const val pageDurationMillis: Long = 6_000

    /** L'opacité du M derrière le paywall. */
    const val backdropOpacity: Float = 0.1f

    /** La taille de police où le pied de l'offre s'arrête de grandir — le seuil des tailles accessibles. */
    internal const val footerFontScaleCap: Float = 1.5f
}

/**
 * Toute la copie du paywall, **au caractère près** (Hugo, 03/10/2026 — textes
 * décidés avec le crédit du jour : on vend l'illimité, on ne bloque personne).
 *
 * Ce qui nomme la plateforme — le compte qui paie, où l'on résilie, où l'on
 * restaure — parle de Google Play au lieu de l'App Store.
 */
object PaywallCopy {
    const val help = "Besoin d’aide ?"
    const val cont = "Continuer"

    // — Écran 1 : l'envie de raconter
    const val storiesEyebrow = "On adore t’écouter !"
    const val storiesTitleLead = "Tu as tant de "
    const val storiesTitleStrong = "choses à raconter !"
    const val storiesBodyLead =
        "Et c’est exactement ce qu’on espérait. Un voyage ne tient pas en 5 minutes par jour : chaque détail que tu racontes, c’est une page de plus "
    const val storiesBodyStrong = "dans ton carnet."

    // — Écran 2 : les détails qui s'effacent
    const val detailsEyebrow = "Raconte tout, tout de suite"
    const val detailsTitleLead = "Les détails s’effacent "
    const val detailsTitleStrong = "en quelques jours"
    val detailsBody = listOf(
        "Le nom de ce petit resto, la phrase du guide qui t’a fait rire, l’odeur du marché le matin...",
        "En illimité, tu racontes tout au moment où tu le vis, sans regarder le chrono.",
    )
    const val previewPill = "Voir un aperçu →"

    /**
     * Les deux formules, côte à côte : ce qui reste gratuit, et ce que
     * l'abonnement ouvre. Le chiffre est celui du serveur
     * (`DAILY_CREDIT_LIMIT_MS`) ; s'il bougeait, ce texte bougerait avec.
     */
    val detailsFootnote = listOf(
        "Gratuit : 5 minutes par jour et par voyage, à l’oral comme à l’écrit.",
        "—",
        "Illimité : raconte autant que tu veux, sur tous tes voyages.",
    )

    // — La version « retour », premier écran
    const val returnEyebrow = "C’est reparti ?"
    const val returnTitleLead = "Tu as encore "
    const val returnTitleStrong = "plein de choses à raconter !"
    val returnBody = listOf(
        "Ravis de te retrouver !",
        "Tu connais déjà le principe, on ne t’embête pas plus...",
    )

    // — La version « retour », écran d'offre
    const val returnOfferTitleLead = "Raconte de nouveau "
    const val returnOfferTitleStrong = "sans compter"

    // — Écran 3 : l'offre
    const val offerEyebrow = "Passe en illimité"

    /**
     * **Sans « peut-être »** (01/10/2026) : le titre doit tenir sur trois
     * lignes, et le mot l'emmenait sur une quatrième.
     */
    const val offerTitleLead = "Ce carnet que tu relieras encore "
    const val offerTitleStrong = "dans 30 ans"

    /** Le pied de l'offre en trois morceaux : seul le prix et sa période se lisent en gras. */
    data class OfferFootnotePrice(val lead: String, val price: String, val trail: String)

    /**
     * Le pied de l'offre : le nom de l'abonnement, son prix et sa période en
     * gras — **le prix se lit en gras** (Hugo, 19/09/2026), c'est le seul
     * chiffre de l'écran —, puis en petit ce que le store veut lire sur
     * l'écran même : qui prélève, le renouvellement, la résiliation 24 h avant
     * la fin de la période, et où elle se fait (Hugo, 19/10/2026, D1).
     *
     * **La période vient du produit** (03/10/2026) : « mois » se lit sur le
     * store, et le mois de l'offre n'est que le repli. Un pied écrit à la main a
     * déjà annoncé une autre durée que la feuille du store (17/09/2026).
     *
     * **« 4,99 € par mois » ne se coupe pas** (recette du 03/10/2026) : on
     * lisait le prix sur une ligne et sa période sur la suivante. Espaces
     * insécables.
     */
    fun offerFootnotePrice(price: String, period: String): OfferFootnotePrice {
        val glued = "$price par $period".replace(" ", " ")
        return OfferFootnotePrice("MemoBook illimité pour ", glued, ".")
    }

    /**
     * **Pas d'arrêt automatique promis** (01/10/2026) : le store ne laisse
     * aucune app résilier à la place de son client. Le rappel part quand le
     * dernier voyage en cours se termine, pas à la fin de chacun (D4).
     */
    const val offerFootnoteDetail =
        "Payé par ton compte Google, renouvelé automatiquement chaque mois sauf résiliation au moins 24 h avant la fin de la période, dans le Play Store › Paiements et abonnements › Abonnements. On te rappelle de résilier quand ton dernier voyage en cours se termine."

    /**
     * La phrase des conditions, à la période du produit : « chaque mois » ne
     * vaut que pour un abonnement mensuel.
     */
    fun offerFootnoteDetail(period: String): String = offerFootnoteDetail.replace("chaque mois", "chaque $period")

    /**
     * Le bouton de l'offre nomme le geste — Hugo, 15/09/2026. C'est la feuille
     * du store qui s'ouvre, et l'on s'y abonne.
     */
    const val offerCallToAction = "S’abonner"

    // — L'achat, par la feuille du store
    object Purchase {
        const val ok = "OK"
        const val restore = "Restaurer mes achats"
        const val terms = "Conditions d’utilisation"
        const val privacy = "Confidentialité"

        const val pendingTitle = "Achat en attente"
        const val pendingMessage =
            "Ton achat attend une validation — celle d’un parent, ou de ta banque. Ton abonnement s’ouvrira tout seul dès qu’elle arrivera."
        const val failedTitle = "Achat impossible"
        const val nothingTitle = "Rien à restaurer"
        const val nothingMessage =
            "Aucun abonnement MemoBook en cours sur ce compte Google. S’il en existe un sur un autre compte, connecte-toi avec lui dans le Play Store, puis réessaie."
    }

    /**
     * Une carte de l'offre.
     *
     * @property tilt l'inclinaison de la carte, en degrés. Elles alternent,
     *   comme des papiers posés à la main.
     */
    data class Argument(@param:DrawableRes val icon: Int, val title: String, val detail: String, val tilt: Float)

    /**
     * Les trois cartes de l'offre, de haut en bas (Hugo, 03/10/2026). La
     * quatrième, « Tes abonnements sont déduits ! », est partie avec la
     * déduction elle-même.
     */
    val arguments: List<Argument> = listOf(
        Argument(
            icon = R.drawable.icon_picture_frame,
            title = "Vocaux et textes illimités",
            detail = "Raconte autant que tu veux : tout est mis en page automatiquement, sur tous tes voyages",
            tilt = -1f,
        ),
        Argument(
            // **Pleine**, comme les deux autres (Hugo, 19/09/2026) : le tracé au
            // trait se lisait plus léger que le cadre photo et le cadenas.
            icon = R.drawable.icon_printer_filled,
            title = "Vite fait, bien fait !",
            // **L'impression se paie à part** (Hugo, 19/10/2026, D2) : posée
            // entre les deux avantages de l'abonnement, l'ancienne phrase
            // laissait croire le carnet compris dedans.
            detail = "Quand tu veux, ton carnet s’imprime et arrive chez toi — il se commande à part de l’abonnement.",
            tilt = 1.4f,
        ),
        Argument(
            icon = R.drawable.icon_locker_checked,
            // **Un rappel, pas un arrêt** (01/10/2026) : seul le store résilie,
            // à la demande de la personne. L'accueil le propose en un geste dès
            // que plus aucun voyage ne court — et l'illimité reste ouvert
            // jusqu'au bout du mois payé.
            title = "On te rappelle de résilier",
            detail = "Quand ton dernier voyage en cours se termine, tu coupes l’abonnement en un geste, et l’illimité reste ouvert jusqu’au bout du mois payé",
            tilt = -1f,
        ),
    )
}

/** Ce que l'offre dit quand l'achat n'a pas ouvert l'abonnement. */
sealed interface PurchaseNotice {
    data object Pending : PurchaseNotice
    data class Failed(val reason: String) : PurchaseNotice
    data object NothingToRestore : PurchaseNotice

    val title: String
        get() = when (this) {
            Pending -> PaywallCopy.Purchase.pendingTitle
            is Failed -> PaywallCopy.Purchase.failedTitle
            NothingToRestore -> PaywallCopy.Purchase.nothingTitle
        }

    val message: String
        get() = when (this) {
            Pending -> PaywallCopy.Purchase.pendingMessage
            is Failed -> reason
            NothingToRestore -> PaywallCopy.Purchase.nothingMessage
        }
}

@Preview(locale = "fr-rFR", name = "Paywall — première fois", widthDp = 390, heightDp = 844)
@Composable
private fun PaywallFirstTimePreview() {
    PaywallView(subscription = Subscription.offer, onSubscribe = {}, onDismiss = {}, subscriptionPurchase = null)
}

@Preview(locale = "fr-rFR", name = "Paywall — retour", widthDp = 390, heightDp = 844)
@Composable
private fun PaywallReturningPreview() {
    PaywallView(
        subscription = Subscription.offer,
        onSubscribe = {},
        onDismiss = {},
        variant = PaywallVariant.Returning,
        subscriptionPurchase = null,
    )
}

@Preview(locale = "fr-rFR", name = "Paywall — l'offre", widthDp = 390, heightDp = 844)
@Composable
private fun PaywallOfferPreview() {
    Box(Modifier.background(MemoBookColor.background).padding(horizontal = PaywallMetrics.margin)) {
        PaywallOffer(price = "4,99 €", period = "mois", onSubscribe = {})
    }
}
