package com.memobook.feature.order

import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import androidx.activity.compose.BackHandler
import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInHorizontally
import androidx.compose.animation.slideOutHorizontally
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.IntOffset
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewModelScope
import com.memobook.core.BookCopy
import com.memobook.core.OrderContext
import com.memobook.core.OrderCopy
import com.memobook.core.OrderStep
import com.memobook.design.BrandBackdrop
import com.memobook.design.BrandButton
import com.memobook.design.BrandKeyboardDismissBar
import com.memobook.design.BrandScreenHeader
import com.memobook.design.MemoBookColor
import com.memobook.design.MemoBookSpacing
import com.memobook.design.SwiftMotion
import com.memobook.design.brandFooterScrim
import com.memobook.design.isAccessibilityTextSize
import com.memobook.design.isReduceMotionEnabled
import com.memobook.feature.OrderIntent
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch
import java.net.URI

/**
 * Commander mon carnet : sept étapes, une seule charpente. Jumeau de
 * `Order/OrderView.swift`.
 *
 * **Rien ne bouge autour de l'étape.** L'en-tête, sa flèche et le bouton du bas
 * sont à la même place du début à la fin ; seul le milieu glisse. C'est ce qui
 * rend la traversée lisible — on ne réapprend pas l'écran à chaque
 * « Continuer », on ne lit que ce qui change.
 *
 * **L'écran ne navigue pas.** Il annonce une [OrderIntent] — j'ai fini, je
 * veux de l'aide — et `RootView` décide de la destination, comme pour
 * l'accueil et la galerie. Le partage, lui, est la feuille du système, que
 * l'écran ouvre lui-même.
 *
 * @param onBack referme l'écran — la flèche depuis la première étape, ce que
 *   le modèle ne peut pas faire à sa place.
 */
@Composable
fun OrderView(model: OrderModel, onIntent: (OrderIntent) -> Unit, onBack: () -> Unit, modifier: Modifier = Modifier) {
    // L'immédiat du fil principal : les champs de l'adresse relisent leur
    // valeur sans attendre l'image suivante, sans quoi le curseur saute.
    val state by model.state.collectAsStateWithLifecycle(context = Dispatchers.Main.immediate)
    val reduceMotion = isReduceMotionEnabled()
    val context = LocalContext.current
    val scope = rememberCoroutineScope()

    // Le focus appartient à l'écran, pas au champ : c'est ce qui permet à la
    // touche « suivant » du clavier d'enchaîner.
    var focus by remember { mutableStateOf<OrderField?>(null) }

    /**
     * La flèche du haut. Depuis la première étape il n'y a pas d'étape
     * précédente : elle referme l'écran, ce que le modèle ne peut pas faire à
     * sa place.
     */
    fun goBack() {
        focus = null
        if (!model.goBack()) onBack()
    }

    /**
     * « Partager le lien de prévisualisation ».
     *
     * La feuille est **celle du système** : elle seule connaît les apps
     * installées et les appareils à portée. Sans lien, rien ne s'ouvre — une
     * feuille de partage vide serait pire qu'un bouton qui n'a pas répondu, et
     * le bandeau du modèle dit pourquoi.
     */
    fun share() {
        scope.launch {
            val link = model.prepareShareLink() ?: return@launch
            val current = model.state.value
            context.shareOrderLink(
                title = current.context?.bookTitle.orEmpty(),
                pages = current.order?.pageCount ?: current.context?.pageCount ?: 0,
                link = link,
            )
        }
    }

    // Un champ qui quitte l'écran avec son étape rend le focus : sans ça, le
    // clavier ressortirait tout seul au retour sur l'adresse.
    LaunchedEffect(state.step) { focus = null }

    // Le retour du système recule d'une étape, comme la flèche ; il ne referme
    // l'écran que là où elle le referme. (Sur iOS, le glissé du bord ramène à
    // l'écran d'avant ; sur Android, le geste de retour est la flèche.)
    BackHandler(enabled = state.step.allowsGoingBack) { goBack() }

    BrandKeyboardDismissBar(modifier.fillMaxSize()) {
        Box(
            Modifier
                .fillMaxSize()
                .background(MemoBookColor.background),
        ) {
            BrandBackdrop(Modifier.matchParentSize())

            Column(
                Modifier
                    .fillMaxSize()
                    .statusBarsPadding()
                    // Le clavier pousse le bouton du bas au-dessus de lui, comme
                    // le `safeAreaInset` d'iOS.
                    .imePadding(),
            ) {
                // Le titre ne change pas d'une étape à l'autre : c'est le
                // sous-titre qui dit où on en est. La flèche, elle, recule d'une
                // étape — et ne referme l'écran que depuis la première.
                BrandScreenHeader(
                    title = OrderCopy.title,
                    onBack = ::goBack,
                    modifier = Modifier
                        .padding(horizontal = MemoBookSpacing.screenMargin)
                        .padding(top = MemoBookSpacing.xs),
                    subtitle = state.step.progressLabel,
                )

                // L'étape courante, qui glisse dans le sens où l'on va : elle
                // entre par le côté vers lequel on avance, et sort par l'autre.
                // Sous « Supprimer les animations », le glissé devient un simple
                // fondu : le déplacement est précisément ce que ce réglage
                // demande d'éviter.
                AnimatedContent(
                    targetState = state.step,
                    modifier = Modifier
                        .weight(1f)
                        .fillMaxWidth(),
                    transitionSpec = {
                        val fade = SwiftMotion.smooth<Float>(0.32f)
                        if (reduceMotion) {
                            fadeIn(fade) togetherWith fadeOut(fade)
                        } else {
                            val motion = SwiftMotion.smooth<IntOffset>(0.32f)
                            val forward = model.state.value.isAdvancing
                            (slideInHorizontally(motion) { if (forward) it else -it } + fadeIn(fade)) togetherWith
                                (slideOutHorizontally(motion) { if (forward) -it else it } + fadeOut(fade))
                        }
                    },
                    label = "étape",
                ) { step ->
                    when (step) {
                        OrderStep.Start -> OrderStartStep(state, model, onHelp = { onIntent(OrderIntent.OpenHelp) })
                        OrderStep.Shipping -> OrderShippingStep(state, model, focus, onFocusChange = { focus = it })
                        OrderStep.Copies -> OrderCopiesStep(state, model, onHelp = { onIntent(OrderIntent.OpenHelp) })
                        OrderStep.Speed -> OrderSpeedStep(state, model, onHelp = { onIntent(OrderIntent.OpenHelp) })
                        OrderStep.Summary -> OrderSummaryStep(state, model)
                        OrderStep.Payment -> OrderPaymentStep(state, onPay = { model.launch { pay() } })
                        OrderStep.Confirmation -> OrderConfirmationStep(
                            state,
                            model,
                            onShare = ::share,
                            onFinish = { onIntent(OrderIntent.Finish) },
                        )
                    }
                }
            }
        }
    }

    LaunchedEffect(model) { model.load() }
}

/**
 * Lance une action du modèle **dans sa portée à lui** — le `Task { await model.… }`
 * d'iOS, qui ne meurt pas avec la vue.
 *
 * Réservé à ce qui touche au serveur et à l'argent (payer, le suivi WhatsApp) :
 * une rotation recrée l'écran, et l'attente de la feuille de Stripe, la
 * relecture de la commande ou l'accord qui part ne doivent pas s'arrêter avec
 * lui. Le partage, qui finit par ouvrir une feuille du système depuis l'écran,
 * reste dans la portée de la composition.
 */
internal fun OrderModel.launch(action: suspend OrderModel.() -> Unit): Job {
    val model = this
    return viewModelScope.launch { model.action() }
}

/**
 * Ouvre la feuille de partage d'Android sur le message du carnet et son lien.
 *
 * Le message est celui d'iOS (`BookCopy.Share.invitation`), le sujet aussi
 * (`BookCopy.Share.subject`) pour un courrier ; le titre du voyage coiffe la
 * feuille, comme l'en-tête que `LPLinkMetadata` dessine sur iOS.
 */
private fun Context.shareOrderLink(title: String, pages: Int, link: URI) {
    val send = Intent(Intent.ACTION_SEND).apply {
        type = "text/plain"
        putExtra(Intent.EXTRA_TEXT, BookCopy.Share.invitation(title = title, pages = pages, link = link.toString()))
        putExtra(Intent.EXTRA_SUBJECT, BookCopy.Share.subject(title))
        putExtra(Intent.EXTRA_TITLE, title.ifEmpty { BookCopy.Share.title })
    }
    try {
        startActivity(Intent.createChooser(send, null))
    } catch (_: ActivityNotFoundException) {
        // Aucune app pour partager : il ne se passe rien, comme un partage
        // refermé.
    }
}

/**
 * Les champs de l'étape 2. Le focus appartient à l'écran, pas au champ : c'est
 * ce qui permet à la touche « suivant » du clavier d'enchaîner.
 */
internal enum class OrderField {
    Name,
    Line1,
    Line2,
    PostalCode,
    City,
}

// MARK: - La charpente d'une étape

/**
 * Ce que toutes les étapes partagent : un contenu qui défile, et un bouton
 * ancré en bas.
 *
 * **Tout défile sauf le bouton.** Même parti pris que la création d'un voyage,
 * et pour la même raison : en taille de texte accessible le contenu déborde, et
 * un bouton qui partirait avec lui deviendrait introuvable.
 *
 * Le contenu s'arrête au-dessus du pied, et le fondu du voile déborde sur lui :
 * ce qui défile s'y dissout comme sur iOS, et ce qu'une étape amène sous les
 * yeux (`bringIntoView`) s'arrête au-dessus du bouton et non dessous. iOS fait
 * défiler un repère (`scrollTarget`) ; ici, l'élément le demande lui-même.
 *
 * @param help le « Besoin d'aide ? » de l'étape, quand elle en a un. Il est
 *   confié à la charpente plutôt que posé par chaque étape parce que **sa place
 *   change avec la taille du texte** : au-dessus du bouton aux tailles
 *   courantes, à la fin du contenu aux tailles accessibles, où la barre du bas
 *   mange déjà la moitié de l'écran et où une ligne de plus dedans ne
 *   laisserait presque rien à lire.
 */
@Composable
internal fun OrderStepLayout(
    help: (() -> Unit)? = null,
    content: @Composable ColumnScope.() -> Unit,
    actions: @Composable ColumnScope.() -> Unit,
) {
    val isAccessible = isAccessibilityTextSize()
    Column(Modifier.fillMaxSize()) {
        Column(
            Modifier
                .weight(1f)
                .fillMaxWidth()
                .verticalScroll(rememberScrollState())
                .padding(horizontal = MemoBookSpacing.screenMargin)
                .padding(top = MemoBookSpacing.s, bottom = MemoBookSpacing.m),
            verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.m),
        ) {
            content()

            if (help != null && isAccessible) OrderHelpLink(help)
        }

        // Le voile de la marque : un fondu au-dessus des commandes, et un aplat
        // **translucide** dessous — le même que sous tous les pieds d'écran de
        // l'app, voir `BrandFooterScrim`. Il descend sous la barre de
        // navigation, jusqu'au bord de la dalle. Il tient aussi en taille de
        // texte accessible, où la barre grandit de beaucoup : le contenu ne se
        // lit plus à travers le bouton, il se devine.
        Column(
            Modifier
                .fillMaxWidth()
                .brandFooterScrim()
                .navigationBarsPadding()
                .padding(horizontal = MemoBookSpacing.screenMargin)
                .padding(top = MemoBookSpacing.xs, bottom = MemoBookSpacing.s),
            verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.xs),
        ) {
            if (help != null && !isAccessible) OrderHelpLink(help)

            actions()
        }
    }
}

/** Le « Besoin d'aide ? » qui coiffe le bouton de plusieurs étapes. */
@Composable
internal fun OrderHelpLink(action: () -> Unit) {
    BrandButton(
        OrderCopy.help,
        style = BrandButton.Style.Link,
        isSubdued = true,
        fillsWidth = true,
        action = action,
    )
}

// MARK: - Aperçus

@Preview(locale = "fr-rFR", name = "Commander — démarrage", widthDp = 390, heightDp = 844)
@Composable
private fun OrderViewStartPreview() {
    OrderView(remember { OrderModel(memoId = "trip-rome", email = "clara@example.com") }, onIntent = {}, onBack = {})
}

@Preview(locale = "fr-rFR", name = "Commander — carnet pas encore composé", widthDp = 390, heightDp = 844)
@Composable
private fun OrderViewNotComposedPreview() {
    OrderView(
        remember { OrderModel(memoId = "trip-rome", context = { OrderContext.notComposedFixture }) },
        onIntent = {},
        onBack = {},
    )
}
