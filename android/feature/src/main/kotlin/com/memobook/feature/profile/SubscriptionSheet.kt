package com.memobook.feature.profile

import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.Uri
import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.SizeTransform
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.tooling.preview.Preview
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LifecycleEventEffect
import com.memobook.core.Gender
import com.memobook.core.Subscription
import com.memobook.core.SubscriptionCancellationReason
import com.memobook.core.TravellerProfile
import com.memobook.design.BrandButton
import com.memobook.design.BrandNotice
import com.memobook.design.BrandOptionGroup
import com.memobook.design.BrandOptionRow
import com.memobook.design.BrandSheet
import com.memobook.design.BrandSheetHost
import com.memobook.design.BrandText
import com.memobook.design.LocalBrandSheetDismiss
import com.memobook.design.MemoBookColor
import com.memobook.design.MemoBookFont
import com.memobook.design.MemoBookSpacing
import com.memobook.design.R
import com.memobook.feature.paywall.LocalSubscriptionPurchase
import com.memobook.payments.PlayCatalog
import kotlinx.coroutines.launch
import java.math.BigDecimal
import java.time.Duration
import java.time.Instant

/**
 * L'abonnement, de bout en bout : ce qu'il rend, et les trois portes qu'il faut
 * pousser pour en sortir. Jumeau de `Profile/SubscriptionSheet.swift`.
 *
 * **Quatre feuilles, une seule présentation.** La ligne « Mon abonnement » du
 * profil n'ouvre qu'une feuille ; c'est son contenu qui change. Empiler quatre
 * feuilles aurait fait reculer l'app quatre fois — [BrandSheet] recule d'un
 * cran à chaque feuille ouverte par-dessus — et une confirmation en trois temps
 * se serait lue comme un empilement de fenêtres au lieu d'un chemin.
 *
 * Le chemin, justement :
 *
 * ```
 * « Mon abonnement » ─→ Current   (« Mon abonnement »)
 *                          │ Résilier mon abonnement
 *                          ▼
 *                       KeepGoing (« Ton voyage continue »)
 *                          │ Résilier
 *                          ▼
 *                       Reason    (« Pourquoi nous quittes-tu ? »)
 *                          │ Confirmer ma résiliation
 *                          ▼
 *                       Done      (« C'est validé »)
 * ```
 *
 * **Plus de feuille « Comment ça fonctionne ? »** (Hugo, 03/10/2026) : elle
 * précédait le paywall et racontait l'essai gratuit d'avant. « Découvrir
 * l'abonnement » ouvre désormais le paywall directement, et cette feuille
 * n'existe que pour qui est abonné — **ou l'a été et garde l'illimité jusqu'au
 * bout du mois payé** : [SubscriptionSheet.Step.Current] le lui dit, avec la
 * date, et lui propose de se réinscrire.
 *
 * À chaque étape, le bouton vert **garde** l'abonnement et le bouton rouge
 * avance vers la sortie : c'est la seule chose qu'on n'a pas eu à décider, la
 * maquette la répète trois fois.
 *
 * **Un abonnement se résilie chez le store qui l'a vendu** (01/10/2026 sur
 * iOS). Aucun store ne laisse une app le faire à la place de son client :
 *
 * - **Google Play** ([SubscriptionSheet.Store.GooglePlay]) — « Confirmer ma
 *   résiliation » envoie la raison, puis ouvre la page d'abonnements du Play
 *   Store. C'est au retour dans l'app, d'après ce que Google Play dit du
 *   renouvellement, qu'on passe à « C'est validé » — ou qu'on revient à « Mon
 *   abonnement » si la personne n'y a rien coupé. C'est le chemin d'iOS, la
 *   page du Play Store à la place de la feuille d'Apple.
 * - **L'App Store** ([SubscriptionSheet.Store.AppStore]) — un abonnement pris
 *   sur un iPhone ne se gère que là : Android n'a aucune porte vers Apple. La
 *   raison part quand même, et la feuille dit où le couper, comme la feuille
 *   de suppression du compte le dit déjà.
 * - **Aucun** ([SubscriptionSheet.Store.App]) — l'abonnement que le serveur
 *   tient seul se résilie par la route (`onCancel`).
 *
 * @param onRecordReason la raison, seule, pour un abonnement tenu par un store
 *   — la résiliation elle-même se fait chez lui.
 * @param onAppStoreRenewal ce que le store dit du renouvellement au retour de
 *   sa page : `false`, il est coupé ; `true`, il court encore. Le nom est celui
 *   d'iOS.
 * @param gender à qui la pastille s'adresse : « Abonnée » ou « Abonné » (T76).
 *   La forme non marquée quand on ne sait pas.
 * @param isHeldByPlay **un achat que Google Play tient et que le serveur n'a
 *   pas encore reçu** — le `managedByAppStore` que l'écran d'iOS force sur un
 *   achat `awaitingServer` : il se résilie chez le store, pas par la route.
 * @param opensStorePage faux dans le bac à sable : la page du Play Store ne
 *   s'ouvre pas, et le double du store répond comme si l'on en revenait.
 */
@Composable
internal fun SubscriptionSheet(
    subscription: Subscription?,
    onActivate: () -> Unit,
    onCancel: (SubscriptionCancellationReason?) -> Unit,
    onRecordReason: (SubscriptionCancellationReason?) -> Unit = {},
    onAppStoreRenewal: (Boolean) -> Unit = {},
    gender: Gender = Gender.Undisclosed,
    isHeldByPlay: Boolean = false,
    opensStorePage: Boolean = true,
) {
    val dismiss = LocalBrandSheetDismiss.current
    val subscriptionPurchase = LocalSubscriptionPurchase.current
    val context = LocalContext.current
    val scope = rememberCoroutineScope()

    // Où on en est du chemin. `null` tant qu'on n'a rien poussé : on part de
    // « Mon abonnement ». Dès qu'un bouton est touché, c'est cette valeur qui
    // commande — sans quoi la dernière feuille disparaîtrait à l'instant même
    // où la résiliation a lieu.
    var step by remember { mutableStateOf<SubscriptionSheet.Step?>(null) }

    // La raison choisie. Volontairement `null` au départ : la maquette montre
    // une carte sélectionnée, mais c'est l'état d'une carte qu'elle documente,
    // pas une réponse cochée d'avance. En pré-cocher une fausserait le
    // compteur qu'elle alimentera.
    var reason by remember { mutableStateOf<SubscriptionCancellationReason?>(null) }

    // La page d'abonnements du Play Store est ouverte : on attend le retour
    // dans l'app pour lire le renouvellement. Et la feuille d'où l'on est
    // parti : c'est là qu'on revient si la personne n'y a rien changé.
    var managesAtStore by remember { mutableStateOf(false) }
    var managementOrigin by remember { mutableStateOf<SubscriptionSheet.Step?>(null) }

    // Ce qu'Android ne peut pas faire pour un abonnement de l'App Store, dit
    // sous les boutons de l'étape où l'on a touché.
    var storeNotice by remember { mutableStateOf<String?>(null) }

    // Le prélèvement avait-il échoué **en entrant dans la feuille** — voir
    // `isBillingRetry`. Relevé une fois, et gardé : le retour du store pose
    // `cancelledAt` (`ProfileModel.acknowledgeAppStoreRenewal`), et « C'est
    // validé » redisait sinon « Ton mois est réglé » à qui n'avait rien payé.
    val enteredInBillingRetry = remember { SubscriptionSheet.isBillingRetry(subscription) }

    // Google Play tient-il cet abonnement ? Lu une fois, à l'ouverture : il
    // répond pour un abonnement qu'il connaît, `null` sinon.
    var playKnows by remember { mutableStateOf(false) }
    LaunchedEffect(subscriptionPurchase) { playKnows = subscriptionPurchase?.willAutoRenew() != null }

    val store = SubscriptionSheet.store(subscription, isHeldByPlay = isHeldByPlay, playKnows = playKnows)
    val holder = if (store == SubscriptionSheet.Store.GooglePlay) SubscriptionCopy.Holder.GooglePlay else SubscriptionCopy.Holder.Apple
    val currentStep = step ?: SubscriptionSheet.Step.Current

    val graceEnd = SubscriptionSheet.graceEnd(subscription)
    // Résilié, mais encore dans le mois payé : « Mon abonnement » le dit, et
    // propose de se réinscrire au lieu de résilier une seconde fois. Voir
    // `Subscription.isCancelled`.
    val isInGrace = subscription?.isCancelled == true && graceEnd != null
    // La période que l'abonné a payée : un ancien abonné à la semaine lit
    // « semaine » dans les phrases de la résiliation (03/10/2026).
    val paidInterval = subscription?.paidInterval ?: Subscription.Interval.Month
    val paidAhead = SubscriptionSheet.paidAhead(
        subscription,
        graceEnd = graceEnd,
        isBillingRetry = enteredInBillingRetry,
        isHeldByStore = store != SubscriptionSheet.Store.App,
    )

    fun go(next: SubscriptionSheet.Step) {
        storeNotice = null
        step = next
    }

    // On revient du Play Store : on lit sur l'appareil si le renouvellement
    // court encore, et on avance d'après ce que Google Play dit — pas d'après
    // le bouton qu'on a touché. `null` (le store ne sait pas) ne change rien :
    // mieux vaut rester sur place qu'annoncer une résiliation qui n'a pas eu
    // lieu.
    //
    // Renouvellement coupé : depuis la confirmation, c'est « C'est validé » ;
    // depuis une réinscription qui n'a pas eu lieu, on reste où l'on était.
    suspend fun settleStoreManagement() {
        val renews = subscriptionPurchase?.willAutoRenew() ?: return
        onAppStoreRenewal(renews)
        if (renews) {
            go(SubscriptionSheet.Step.Current)
        } else {
            go(if (managementOrigin == SubscriptionSheet.Step.Reason) SubscriptionSheet.Step.Done else managementOrigin ?: SubscriptionSheet.Step.Done)
        }
    }

    // Ouvre la page du Play Store, en retenant d'où l'on part. Dans le bac à
    // sable, elle ne s'ouvre pas : son double répond tout de suite, comme si
    // l'on en revenait (`StubSubscriptionStore.renewsAfterManagement`).
    fun manageAtPlay() {
        managementOrigin = currentStep
        if (!opensStorePage) {
            scope.launch { settleStoreManagement() }
            return
        }
        managesAtStore = true
        try {
            context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(SubscriptionSheet.playManageUrl(subscription))))
        } catch (_: ActivityNotFoundException) {
            managesAtStore = false
        }
    }

    LifecycleEventEffect(Lifecycle.Event.ON_RESUME) {
        if (!managesAtStore) return@LifecycleEventEffect
        managesAtStore = false
        scope.launch { settleStoreManagement() }
    }

    // Se réinscrire pendant le mois payé. Chez un store, c'est **réarmer** le
    // renouvellement — sur sa page.
    fun resubscribe() {
        when (store) {
            SubscriptionSheet.Store.GooglePlay -> manageAtPlay()
            SubscriptionSheet.Store.AppStore -> storeNotice = SubscriptionCopy.resubscribeAtApple
            SubscriptionSheet.Store.App -> {
                onActivate()
                go(SubscriptionSheet.Step.Current)
            }
        }
    }

    AnimatedContent(
        targetState = currentStep,
        transitionSpec = { fadeIn(tween(300)) togetherWith fadeOut(tween(300)) using SizeTransform(clip = false) },
        label = "étape",
    ) { shown ->
        when (shown) {
            // — « Mon abonnement »
            SubscriptionSheet.Step.Current -> BrandSheet(
                SubscriptionCopy.currentTitle,
                badge = SubscriptionCopy.currentBadge(gender),
                subtitle = if (isInGrace) SubscriptionCopy.graceSubtitle(until = graceEnd) else SubscriptionCopy.currentSubtitle,
            ) {
                Column(verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.m)) {
                    if (isInGrace) {
                        // Rien à rappeler : la résiliation est faite. Ce qui
                        // reste à proposer, c'est de revenir sur sa décision.
                        BrandButton(SubscriptionCopy.subscribeAgain, style = BrandButton.Style.Accent, fillsWidth = true, action = ::resubscribe)
                    } else {
                        SubscriptionCallout(
                            title = SubscriptionCopy.autoCancelTitle(destination = subscription?.tripDestination),
                            message = SubscriptionCopy.autoCancelBody(endsOn = subscription?.endsOn),
                        )

                        BrandButton(SubscriptionCopy.cancelSubscription, style = BrandButton.Style.Destructive, fillsWidth = true) {
                            go(SubscriptionSheet.Step.KeepGoing)
                        }
                    }
                    StoreNotice(storeNotice)
                }
            }

            // — Résiliation 1 : « Ton voyage continue »
            SubscriptionSheet.Step.KeepGoing -> BrandSheet(
                SubscriptionCopy.keepGoingTitle,
                paragraphs = SubscriptionCopy.keepGoingParagraphs(
                    tripTitle = subscription?.tripTitle,
                    graceEnd = graceEnd,
                    interval = paidInterval,
                    paidAhead = paidAhead,
                    holder = holder,
                ),
            ) {
                Column(verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.s)) {
                    BrandButton(SubscriptionCopy.waitForAutoCancel, fillsWidth = true, action = dismiss)

                    BrandButton(
                        SubscriptionCopy.cancel,
                        icon = painterResource(R.drawable.icon_arrow_forward),
                        iconPlacement = BrandButton.IconPlacement.Trailing,
                        style = BrandButton.Style.Destructive,
                        fillsWidth = true,
                    ) {
                        go(SubscriptionSheet.Step.Reason)
                    }
                }
            }

            // — Résiliation 2 : « Pourquoi nous quittes-tu ? »
            SubscriptionSheet.Step.Reason -> BrandSheet(
                SubscriptionCopy.reasonTitle,
                paragraphs = SubscriptionCopy.reasonParagraphs(graceEnd = graceEnd, interval = paidInterval, paidAhead = paidAhead, holder = holder),
            ) {
                Column(verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.m)) {
                    BrandOptionGroup {
                        SubscriptionCancellationReason.entries.forEach { candidate ->
                            BrandOptionRow(candidate.label, isSelected = reason == candidate) { reason = candidate }
                        }
                    }

                    Column(verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.s)) {
                        BrandButton(SubscriptionCopy.stayAWhile, fillsWidth = true, action = dismiss)

                        // La résiliation a lieu **ici**, pas sur la feuille
                        // suivante : celle-ci annonce ce qui vient d'arriver,
                        // elle ne le demande plus.
                        //
                        // Grisé tant qu'aucune raison n'est cochée — Hugo,
                        // 14/09/2026. La question est posée pour être répondue :
                        // confirmer sans raison passait à côté du seul retour
                        // que cette feuille rapporte.
                        BrandButton(
                            SubscriptionCopy.confirmCancellation,
                            icon = painterResource(R.drawable.icon_cross),
                            style = BrandButton.Style.Destructive,
                            fillsWidth = true,
                            enabled = reason != null,
                        ) {
                            when (store) {
                                SubscriptionSheet.Store.GooglePlay -> {
                                    onRecordReason(reason)
                                    manageAtPlay()
                                }
                                SubscriptionSheet.Store.AppStore -> {
                                    onRecordReason(reason)
                                    storeNotice = SubscriptionCopy.cancelAtApple
                                }
                                SubscriptionSheet.Store.App -> {
                                    onCancel(reason)
                                    go(SubscriptionSheet.Step.Done)
                                }
                            }
                        }
                    }
                    StoreNotice(storeNotice)
                }
            }

            // — Résiliation 3 : « C'est validé »
            SubscriptionSheet.Step.Done -> BrandSheet(
                SubscriptionCopy.doneTitle,
                paragraphs = SubscriptionCopy.doneParagraphs(graceEnd = graceEnd, interval = paidInterval, paidAhead = paidAhead, holder = holder),
            ) {
                Column(verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.s)) {
                    BrandButton(SubscriptionCopy.backHome, fillsWidth = true, action = dismiss)
                    BrandButton(SubscriptionCopy.subscribeAgain, style = BrandButton.Style.Accent, fillsWidth = true, action = ::resubscribe)
                    StoreNotice(storeNotice)
                }
            }
        }
    }
}

/** Ce qu'Android ne peut pas faire pour un abonnement de l'App Store — la sortie, nommée. */
@Composable
private fun StoreNotice(message: String?) {
    message ?: return
    BrandNotice(message, tone = BrandNotice.Tone.Information)
}

/**
 * L'encadré bleu de la feuille « Mon abonnement » : ce qui va se passer tout
 * seul, et pourquoi.
 */
@Composable
private fun SubscriptionCallout(title: String, message: String) {
    Column(
        Modifier
            .fillMaxWidth()
            .background(MemoBookColor.outline.copy(alpha = 0.5f), RoundedCornerShape(MemoBookSpacing.controlCornerRadius))
            .padding(horizontal = MemoBookSpacing.s, vertical = MemoBookSpacing.m)
            .semantics(mergeDescendants = true) {},
        verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.xs / 2),
    ) {
        // Le corps est à l'encre pleine et non en gris : ce n'est pas une
        // légende, c'est l'explication qu'on est venu chercher.
        BrandText(title, MemoBookFont.calloutTitle, Modifier.fillMaxWidth())
        BrandText(message, MemoBookFont.taglineRegular, Modifier.fillMaxWidth())
    }
}

/** Les axes de la feuille, sous son nom comme sur iOS (`SubscriptionSheet.Step`). */
internal object SubscriptionSheet {
    enum class Step {
        Current,
        KeepGoing,
        Reason,
        Done,
    }

    /** Qui tient l'abonnement — et donc où il se résilie. */
    enum class Store {
        /** Acheté sur un iPhone : seul l'App Store le coupe, et Android n'y a pas de porte. */
        AppStore,

        /** Acheté sur Android : la page d'abonnements du Play Store le coupe. */
        GooglePlay,

        /** Ni l'un ni l'autre : le serveur le tient seul, et la route le résilie. */
        App,
    }

    /**
     * La page d'abonnements de Google Play, ouverte sur celui de MemoBook —
     * la feuille de gestion d'iOS.
     */
    val playSubscriptionsUrl: String =
        "https://play.google.com/store/account/subscriptions?sku=${PlayCatalog.MONTHLY_SUBSCRIPTION}&package=com.memobook.app"

    /**
     * Qui tient l'abonnement. Un achat que Google Play tient et que le serveur
     * n'a pas reçu d'abord ; puis **ce que le serveur dit**
     * (`subscription.store`, lot B4) — y compris « aucun store » ; enfin, d'un
     * serveur ou d'un cache d'avant B4 qui ne le dit pas, la lecture d'avant :
     * Apple quand `managedByAppStore` le dit, Google Play quand il connaît un
     * abonnement sur ce téléphone, sinon le serveur seul.
     *
     * Le serveur passe avant Google Play : un abonnement que Google Play
     * connaît sur ce téléphone peut être celui d'un autre compte MemoBook.
     */
    fun store(subscription: Subscription?, isHeldByPlay: Boolean, playKnows: Boolean): Store {
        if (isHeldByPlay) return Store.GooglePlay
        subscription?.servedStore?.let { served ->
            return when (served.value) {
                Subscription.Store.AppStore -> Store.AppStore
                Subscription.Store.GooglePlay -> Store.GooglePlay
                null -> Store.App
            }
        }
        return when {
            subscription?.managedByAppStore == true -> Store.AppStore
            playKnows -> Store.GooglePlay
            else -> Store.App
        }
    }

    /**
     * La page du Play Store qu'ouvre « Gérer » : celle que le serveur sert
     * (`subscription.manageUrl`) pour un abonnement qu'il sait tenu par Google
     * Play, sinon la nôtre — un achat qu'il n'a pas encore reçu, un serveur
     * d'avant B4. Jamais la page d'Apple : Android n'y a pas de porte.
     */
    fun playManageUrl(subscription: Subscription?): String =
        subscription?.manageUrl?.takeIf { subscription?.servedStore?.value == Subscription.Store.GooglePlay }
            ?: playSubscriptionsUrl

    /**
     * Le dernier jour du mois déjà payé, quand il en reste un.
     *
     * Le renouvellement coupé, dit par le serveur (`ending`, 06/10/2026) : sa
     * date de fin à lui. Sinon la période payée encore devant soi.
     */
    fun graceEnd(subscription: Subscription?): Instant? {
        subscription ?: return null
        if (subscription.servedState == Subscription.State.Ending) return subscription.unlimitedUntil()
        return if (subscription.isWithinPaidPeriod()) subscription.paidThrough else null
    }

    /**
     * **Le délai de grâce de facturation du store** (`past_due`) : ni actif ni
     * résilié. Le serveur y met la fin du délai dans `paidThrough`
     * (`gracePeriodEndsAt`), mais rien n'a été encaissé : les trois feuilles
     * de la résiliation ne disent donc ni « mois déjà réglé » ni « Ton mois
     * est réglé » (03/10/2026).
     */
    fun isBillingRetry(subscription: Subscription?): Boolean = subscription?.isInBillingRetry == true

    /**
     * Ce qui reste payé devant soi — ce que les trois feuilles de la
     * résiliation racontent, avec `graceEnd`. Voir [SubscriptionCopy.PaidAhead].
     *
     * Le prélèvement raté d'abord ; puis un abonnement tenu par un store dont
     * on ne connaît pas la fin de période — un achat que le serveur n'a pas
     * encore reçu, le plus souvent : couper le renouvellement chez le store ne
     * coupe jamais la période en cours ; sinon, le cas ordinaire.
     */
    fun paidAhead(
        subscription: Subscription?,
        graceEnd: Instant?,
        isBillingRetry: Boolean,
        isHeldByStore: Boolean = subscription?.heldBy != null,
    ): SubscriptionCopy.PaidAhead = when {
        isBillingRetry -> SubscriptionCopy.PaidAhead.BillingRetry
        isHeldByStore && graceEnd == null -> SubscriptionCopy.PaidAhead.HeldByApple
        else -> SubscriptionCopy.PaidAhead.Settled
    }
}

// MARK: - La copie

/**
 * Tous les libellés des quatre feuilles, et des deux alertes de l'accueil, en
 * un seul endroit.
 *
 * La maquette porte neuf fautes de français et deux formes d'apostrophe ; **Hugo
 * a tranché de toutes les corriger** (D12, T66) plutôt que de les recopier
 * comme R8 le veut par défaut. C'est donc l'un des rares endroits où le code
 * s'écarte volontairement de Figma, et la liste des écarts vit dans la fiche
 * écran pour que Clara les reprenne à la source.
 *
 * L'apostrophe est **partout typographique** (’), y compris dans les trois
 * feuilles de résiliation et les quatre raisons, où Figma emploie la droite.
 *
 * **Résilier ne ferme plus le micro** (Hugo, 03/10/2026) : sans abonnement, on
 * retrouve le crédit du jour — cinq minutes par jour et par voyage. Les
 * phrases qui annonçaient « tu ne pourras plus dicter tes souvenirs » disent
 * désormais ce qu'on retrouve, et la période payée est **celle de l'abonné** :
 * le mois, ou la semaine d'un abonné de l'ancienne formule, toujours honoré
 * (`Subscription.paidInterval`).
 *
 * **Plus de « inclus » après la date** (03/10/2026) : ni l'app ni le serveur
 * ne tiennent le dernier jour en entier — le serveur coupe à l'heure exacte
 * où la période payée s'achève.
 *
 * Elle est `internal` au module, et non à la feuille : l'accueil (ses deux
 * alertes) et les réglages d'un voyage (la pastille) la lisent aussi.
 */
internal object SubscriptionCopy {
    /**
     * Ce qu'on retrouve sans abonnement — la même phrase dans les trois
     * feuilles de résiliation, pour qu'elles ne se contredisent pas.
     */
    const val dailyCreditBack = "tu retrouves le crédit du jour : 5 minutes par jour et par voyage"

    /**
     * « mois » est masculin, « semaine » féminin : les phrases de la
     * résiliation s'accordent sur la période payée plutôt que d'y glisser un
     * mot — « Ton semaine est réglé » ne se lit pas.
     */
    private fun thePaidPeriod(interval: Subscription.Interval): String = when (interval) {
        Subscription.Interval.Month -> "la fin du mois déjà réglé"
        Subscription.Interval.Week -> "la fin de la semaine déjà réglée"
    }

    private fun yourPeriodIsPaid(interval: Subscription.Interval, already: Boolean = false): String = when (interval) {
        Subscription.Interval.Month -> if (already) "Ton mois est déjà réglé" else "Ton mois est réglé"
        Subscription.Interval.Week -> if (already) "Ta semaine est déjà réglée" else "Ta semaine est réglée"
    }

    /**
     * Ce qui reste payé devant soi au moment de résilier (03/10/2026). Les
     * trois feuilles le lisent avec la date de fin (`graceEnd`), et ne
     * disent « réglé » que de ce qui l'est.
     */
    enum class PaidAhead {
        /**
         * Le cas ordinaire : la période réglée court jusqu'à la date connue —
         * ou, sans date, l'abonnement s'arrête aujourd'hui.
         */
        Settled,

        /**
         * **Un store tient une période payée dont l'app ne connaît pas la
         * fin** : un achat encaissé que le serveur n'a pas encore reçu
         * (`AwaitingServer`), ou un serveur qui ne sert pas la date. Couper le
         * renouvellement chez le store ne coupe jamais la période en cours :
         * « L’abonnement s’arrête aujourd’hui » mentait. Le nom est celui
         * d'iOS, où le store est Apple.
         */
        HeldByApple,

        /**
         * **Le dernier prélèvement n'est pas passé** (`past_due`, délai de
         * grâce du store) : rien n'est réglé, le store réessaie et laisse
         * raconter en attendant. « Ton mois est déjà réglé » mentait.
         */
        BillingRetry,
    }

    /**
     * Qui réessaie un prélèvement raté — **le store qui a vendu
     * l'abonnement**. Sur iOS c'est toujours Apple ; sur Android, un
     * abonnement Google Play se dit avec son nom à lui.
     *
     * @property paymentSettings où l'on met à jour son moyen de paiement.
     */
    enum class Holder(val storeName: String, val paymentSettings: String) {
        Apple("Apple", "dans les réglages de ton compte Apple"),
        GooglePlay("Google Play", "dans ton compte Google Play"),
    }

    /**
     * Le prélèvement raté, dit tel quel : le store réessaie, et l'illimité
     * tient en attendant — jusqu'à la fin du délai quand le serveur la connaît.
     */
    private fun paymentFailed(until: Instant?, holder: Holder): String {
        val graceEnd = until
            ?: return "Ton dernier prélèvement n’est pas passé : ${holder.storeName} réessaie, et te laisse raconter sans limite en attendant."
        return "Ton dernier prélèvement n’est pas passé : ${holder.storeName} réessaie, et te laisse raconter sans limite jusqu’au ${graceEnd.dayAndMonth}."
    }

    // — « Mon abonnement »

    const val currentTitle = "Mon abonnement"

    /** La maquette écrit « Abonnée » ; l'app accorde sur ce que le profil sait de la personne (T76). */
    fun currentBadge(gender: Gender): String = gender.agreed("Abonné")

    const val currentSubtitle =
        "Tu as déjà souscrit à ton abonnement MemoBook : tu racontes sans limite, à l’oral comme à l’écrit."

    /**
     * La valeur de la ligne « Mon abonnement » du profil, renouvellement
     * coupé : « Jusqu’au 12 octobre ».
     */
    fun rowUntil(end: Instant): String = "Jusqu’au ${end.dayAndMonth}"

    /**
     * Résilié, mais le mois payé court encore : l'illimité reste ouvert, et
     * la phrase le date. Sans date — un serveur qui ne la sert pas —, on dit
     * seulement ce qui vient ensuite.
     */
    fun graceSubtitle(until: Instant?): String {
        val graceEnd = until ?: return "Tu as résilié ton abonnement : ensuite, $dailyCreditBack."
        return "Tu as résilié ton abonnement : tu racontes sans limite jusqu’au ${graceEnd.dayAndMonth}. Ensuite, $dailyCreditBack."
    }

    /**
     * ⚠️ **État non maquetté** : sans destination, la phrase s'arrête au
     * voyage — un abonnement acheté hors d'un voyage n'en porte pas.
     */
    fun autoCancelTitle(destination: String?): String {
        if (destination.isNullOrEmpty()) return "Un rappel à la fin de ton voyage."
        return "Un rappel à la fin de ton voyage à $destination."
    }

    /**
     * ⚠️ **État non maquetté** : sans date de fin, on promet la même chose sans
     * avancer de délai — plutôt qu'un « dans 0 jour ».
     */
    fun autoCancelBody(endsOn: Instant?): String {
        val opening =
            "Parce que l’on sait que tu n’as pas besoin de notre application en dehors de tes voyages, on te proposera de résilier ton abonnement"
        endsOn ?: return "$opening à la fin de ton voyage."
        return "$opening ${endsOn.relativeDelay}."
    }

    const val cancelSubscription = "Résilier mon abonnement"

    // — Résiliation 1 : « Ton voyage continue »

    const val keepGoingTitle = "Ton voyage continue"

    /**
     * ⚠️ **État non maquetté** : sans titre de voyage, la première phrase se
     * passe des guillemets.
     *
     * **La deuxième phrase dit *quand*** (Hugo, 19/09/2026) : la période déjà
     * réglée continue, et elle nomme le jour, comme les deux feuilles
     * suivantes. Sans période réglée, elle dit seulement ce qu'on retrouve.
     */
    fun keepGoingParagraphs(
        tripTitle: String?,
        graceEnd: Instant?,
        interval: Subscription.Interval = Subscription.Interval.Month,
        paidAhead: PaidAhead = PaidAhead.Settled,
        holder: Holder = Holder.Apple,
    ): List<String> {
        val opening = if (!tripTitle.isNullOrEmpty()) {
            "Il te reste encore quelques jours dans ton voyage “$tripTitle”."
        } else {
            "Il te reste encore quelques jours dans ton voyage."
        }
        val consequence = when {
            paidAhead == PaidAhead.BillingRetry ->
                "${paymentFailed(graceEnd, holder)} Si tu coupes maintenant, ${holder.storeName} cesse de réessayer, et $dailyCreditBack."
            paidAhead == PaidAhead.HeldByApple && graceEnd == null ->
                "Si tu coupes maintenant, tu racontes sans limite jusqu’à la fin de la période déjà réglée. Ensuite, $dailyCreditBack."
            graceEnd != null ->
                "Si tu coupes maintenant, tu racontes sans limite jusqu’à ${thePaidPeriod(interval)}, le ${graceEnd.dayAndMonth}. Ensuite, $dailyCreditBack."
            else -> "Si tu coupes maintenant, $dailyCreditBack."
        }
        return listOf(
            opening,
            consequence,
            "Pour rappel, on te proposera de le résilier à ton retour, en un geste.",
        )
    }

    const val waitForAutoCancel = "Attendre la fin du voyage"
    const val cancel = "Résilier"

    // — Résiliation 2 : « Pourquoi nous quittes-tu ? »

    const val reasonTitle = "Pourquoi nous quittes-tu ?"

    /**
     * Le chapeau de l'avant-dernière feuille — **et c'est ici que se dit le
     * sursis** (Hugo, 16/09/2026).
     *
     * Ici, et pas sur la dernière : c'est la feuille où l'on est encore en
     * train de décider. Apprendre après coup qu'on gardait son mois est une
     * bonne nouvelle qui arrive trop tard — on a hésité pour rien.
     *
     * Sans mois restant — il se termine aujourd'hui, ou rien n'a été payé —,
     * la phrase ne s'écrit pas : promettre « jusqu'au 16 septembre » le 16
     * septembre ne promet rien.
     *
     * Un prélèvement raté n'a rien réglé : la feuille dit plutôt qu'un moyen
     * de paiement à jour suffit à garder l'abonnement — c'est peut-être tout
     * ce qui motivait le geste. Une période tenue par un store sans date
     * connue va à son terme, et la phrase le dit sans inventer de jour.
     */
    fun reasonParagraphs(
        graceEnd: Instant?,
        interval: Subscription.Interval = Subscription.Interval.Month,
        paidAhead: PaidAhead = PaidAhead.Settled,
        holder: Holder = Holder.Apple,
    ): List<String> {
        val paragraphs = mutableListOf(
            "Aide-nous à faire évoluer l’application.",
            "Choisis la raison principale.",
        )
        when {
            paidAhead == PaidAhead.BillingRetry -> {
                paragraphs += "Si c’est le prélèvement qui bloque, mets à jour ton moyen de paiement ${holder.paymentSettings} : l’abonnement repartira tout seul."
                return paragraphs
            }
            paidAhead == PaidAhead.HeldByApple && graceEnd == null -> {
                paragraphs += "La période déjà réglée va à son terme : tu continues de raconter sans limite jusqu’à sa fin."
                return paragraphs
            }
        }
        if (graceEnd != null) {
            paragraphs += "${yourPeriodIsPaid(interval, already = true)} : tu continues de raconter sans limite jusqu’au ${graceEnd.dayAndMonth}."
        }
        return paragraphs
    }

    const val stayAWhile = "Rester abonné encore quelques jours"
    const val confirmCancellation = "Confirmer ma résiliation"

    // — Résiliation 3 : « C'est validé »

    const val doneTitle = "C’est validé"

    /**
     * Ce que la dernière feuille annonce.
     *
     * **Deux versions.** Quand le mois payé se termine aujourd'hui — ou qu'il
     * n'y en a pas —, l'abonnement s'arrête aujourd'hui, et le crédit du jour
     * revient tout de suite. Quand il reste des jours réglés, la phrase les
     * nomme plutôt que de mentir d'un mois.
     *
     * **Et deux cas où l'on ne sait pas dire « réglé jusqu'au »**
     * (03/10/2026) : un prélèvement raté, où rien n'est réglé ; une période
     * tenue par un store dont on ne connaît pas la fin, qui ne s'arrête pas
     * aujourd'hui pour autant. Voir [PaidAhead].
     */
    fun doneParagraphs(
        graceEnd: Instant?,
        interval: Subscription.Interval = Subscription.Interval.Month,
        paidAhead: PaidAhead = PaidAhead.Settled,
        holder: Holder = Holder.Apple,
    ): List<String> {
        val keepsBook = "et tu gardes accès à ton carnet de bord pour le relire quand tu veux."
        when {
            paidAhead == PaidAhead.BillingRetry -> return listOf(
                "L’abonnement ne se renouvellera pas.",
                "Ton dernier prélèvement n’était pas passé : ${holder.storeName} ne le retentera pas.",
                "Ensuite, $dailyCreditBack, $keepsBook",
            )
            paidAhead == PaidAhead.HeldByApple && graceEnd == null -> return listOf(
                "L’abonnement ne se renouvellera pas.",
                "La période déjà réglée va à son terme : d’ici là, rien ne change — tu racontes sans limite, comme avant.",
                "Ensuite, $dailyCreditBack, $keepsBook",
            )
        }
        graceEnd ?: return listOf(
            "L’abonnement s’arrête aujourd’hui.",
            "Tu retrouves le crédit du jour : 5 minutes par jour et par voyage, $keepsBook",
        )
        return listOf(
            "L’abonnement ne se renouvellera pas.",
            "${yourPeriodIsPaid(interval)} jusqu’au ${graceEnd.dayAndMonth} : d’ici là, rien ne change — tu racontes sans limite, comme avant.",
            "Ensuite, $dailyCreditBack, $keepsBook",
        )
    }

    // — Un abonnement de l'App Store, lu sur Android

    /**
     * « Confirmer ma résiliation » d'un abonnement pris sur un iPhone : la
     * raison est partie, mais seul Apple coupe le renouvellement. ⚠️ **Phrase
     * propre à Android**, sur le modèle de celle de la suppression du compte
     * (`DeleteAccountCopy.subscriptionWarning(AppStore)`) — à relire par Clara.
     */
    const val cancelAtApple =
        "Ton abonnement a été pris sur un iPhone : il se résilie chez Apple, dans les réglages de ton iPhone. MemoBook ne peut pas le couper depuis ce téléphone."

    /** « S’inscrire à nouveau », même cas. ⚠️ **Phrase propre à Android**, à relire par Clara. */
    const val resubscribeAtApple =
        "Ton abonnement a été pris sur un iPhone : il se réactive chez Apple, dans les réglages de ton iPhone. MemoBook ne peut pas le relancer depuis ce téléphone."

    // — L'alerte du système, quand le sursis s'achève

    /**
     * Le titre de l'alerte qui s'ouvre le jour où le mois payé s'achève.
     *
     * **Une alerte et non une feuille de la marque**, et c'est voulu : elle
     * n'arrive pas au bout d'un geste qu'on vient de faire, elle tombe à
     * l'ouverture de l'app, des jours plus tard. Une feuille qui monte toute
     * seule se lit comme un écran de l'app ; une alerte se lit comme une
     * nouvelle. C'est la même raison qui fait qu'iOS annonce lui-même la fin
     * d'un abonnement.
     */
    const val endedTitle = "Ton abonnement MemoBook s’est arrêté"

    /**
     * On ne perd rien : on retrouve le crédit du jour, et l'illimité est à un
     * geste (Hugo, 03/10/2026).
     *
     * **La période sans la nommer** (03/10/2026) : l'accueil, qui ouvre
     * l'alerte, ne sait pas si l'abonné payait le mois ou la semaine de
     * l'ancienne formule — « Ton mois réglé est terminé » mentait à ce
     * dernier.
     */
    fun endedMessage(tripTitle: String?): String {
        val opening = if (!tripTitle.isNullOrEmpty()) {
            "La période que tu avais réglée est terminée, et l’abonnement de « $tripTitle » ne s’est pas renouvelé."
        } else {
            "La période que tu avais réglée est terminée, et l’abonnement ne s’est pas renouvelé."
        }
        return "$opening Tu retrouves 5 minutes par jour et par voyage. Pour raconter sans compter, réabonne-toi."
    }

    const val endedDismiss = "D’accord"

    // — Le rappel de fin de voyage, sur l'accueil
    const val tripEndTitle = "Ton voyage est terminé"
    const val tripEndMessage =
        "Ton abonnement MemoBook va se renouveler, alors que tu n’en as pas besoin entre deux voyages. Tu peux le résilier maintenant, tes carnets restent à toi."
    const val tripEndCancel = "Résilier mon abonnement"
    const val tripEndKeep = "Le garder"
    const val endedResubscribe = "Me réabonner"
    const val backHome = "Revenir à l’accueil"
    const val subscribeAgain = "S’inscrire à nouveau"
}

// MARK: - Aperçus

/** Résilié il y a deux jours, le mois payé court encore trois semaines. */
private val cancelledInGrace = Subscription(
    price = BigDecimal("4.99"),
    isActive = false,
    cancelledAt = Instant.now().minus(Duration.ofDays(2)),
    paidThrough = Instant.now().plus(Duration.ofDays(21)),
    managedByAppStore = true,
)

@Preview(locale = "fr-rFR", name = "Mon abonnement — abonné", heightDp = 700)
@Composable
private fun SubscriptionSheetPreview() {
    BrandSheetHost(isPresented = true, onDismissRequest = {}) {
        SubscriptionSheet(subscription = TravellerProfile.fixture.subscription, onActivate = {}, onCancel = {})
    }
}

@Preview(locale = "fr-rFR", name = "Mon abonnement — résilié, mois payé", heightDp = 700)
@Composable
private fun SubscriptionSheetGracePreview() {
    BrandSheetHost(isPresented = true, onDismissRequest = {}) {
        SubscriptionSheet(subscription = cancelledInGrace, onActivate = {}, onCancel = {})
    }
}

@Preview(locale = "fr-rFR", name = "Abonné — AX3", heightDp = 900, fontScale = 2f)
@Composable
private fun SubscriptionSheetLargePreview() {
    BrandSheetHost(isPresented = true, onDismissRequest = {}) {
        SubscriptionSheet(subscription = TravellerProfile.fixture.subscription, onActivate = {}, onCancel = {})
    }
}
