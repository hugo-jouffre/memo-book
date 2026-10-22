package com.memobook.feature

import androidx.compose.runtime.Stable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.runtime.staticCompositionLocalOf
import com.memobook.core.DailyCredit
import com.memobook.core.Traveller
import com.memobook.core.TravellerProfile
import java.time.Instant

/**
 * La version du paywall à montrer, d'où qu'on l'ouvre. Jumeau de
 * `PaywallVariant` (`PaywallView.swift`) : quelqu'un qui a déjà été abonné voit
 * la version « retour » en deux écrans ; les autres, la découverte en trois.
 */
enum class PaywallVariant(val pageCount: Int) {
    FirstTime(3),
    Returning(2),
}

/**
 * Ce que la session sait de l'abonnement du compte, d'un écran à l'autre.
 * Jumeau de `SubscriptionSession.swift`.
 *
 * **L'abonnement n'ouvre plus qu'une chose : l'illimité** (Hugo, 03/10/2026).
 * Il reste deux faits, et cet objet les fait circuler entre des écrans qui ont
 * chacun leur modèle et leur appel :
 *
 * 1. **Ce compte raconte-t-il sans limite ?** Le serveur le dit à l'accueil, au
 *    profil et dans chaque crédit du jour. Mais un achat ou une résiliation
 *    basculent l'interface **tout de suite** : le geste a le dernier mot sur ce
 *    que le serveur a dit avant lui — **et seulement jusqu'à ce que le serveur
 *    dise la même chose**.
 * 2. **Quelle version du paywall montrer ?** [paywallVariant].
 *
 * Un `@Observable` sur iOS : ici des états Compose, que les vues lisent et que
 * les modèles d'écran interrogent. Elle vit dans `RootView` pour toute la vie
 * de l'app, et descend par [LocalSubscriptionSession].
 */
@Stable
class SubscriptionSession {
    /** Ce que le dernier geste de la session a décidé — acheter (`true`), résilier (`false`) —, ou `null`. */
    var override: Boolean? by mutableStateOf(null)
        private set

    /** Ce que le serveur a dit en dernier. `null` tant qu'aucun écran n'a répondu. */
    var known: Boolean? by mutableStateOf(null)
        private set

    /** Ce compte a déjà été abonné — en ce moment ou par le passé. */
    var hasSubscribedBefore: Boolean by mutableStateOf(false)
        private set

    /** La fin annoncée de l'illimité — un renouvellement coupé. `RootView` l'attend. */
    var endsAt: Instant? by mutableStateOf(null)
        private set

    /** La période s'est achevée sous nos yeux, et aucun serveur ne l'a encore redit. */
    var hasLapsed: Boolean by mutableStateOf(false)
        private set

    /** Monte à chaque fois que l'abonnement a pu changer **hors de l'écran qui le montre**. */
    var revision: Int by mutableIntStateOf(0)
        private set

    /** Le geste de la session d'abord, sinon ce que le serveur a dit ; faux tant qu'on ne sait rien. */
    val isUnlimited: Boolean get() = override ?: known ?: false

    val paywallVariant: PaywallVariant get() = if (hasSubscribedBefore) PaywallVariant.Returning else PaywallVariant.FirstTime

    /**
     * Un écran vient de lire le serveur. **Le geste rend la main dès que le
     * serveur le confirme** (03/10/2026). `hasSubscribedBefore` ne redescend
     * jamais dans une session ; seul [reset] l'efface.
     */
    fun learn(isUnlimited: Boolean, hasSubscribedBefore: Boolean, endsAt: Instant? = null) {
        if (override == isUnlimited) override = null
        known = isUnlimited
        if (hasSubscribedBefore || isUnlimited) this.hasSubscribedBefore = true
        this.endsAt = if (isUnlimited) endsAt else null
        if (isUnlimited) hasLapsed = false
    }

    /**
     * L'accueil vient de lire son contenu — **à l'heure qu'il est** : un
     * accueil gardé depuis la veille ne fait pas revivre un renouvellement
     * coupé dont la date est passée.
     */
    fun learn(traveller: Traveller, now: Instant = Instant.now()) {
        val until = traveller.unlimitedUntil
        val isUnlimited = traveller.isUnlimited && (until?.let { it > now } ?: true)
        learn(isUnlimited = isUnlimited, hasSubscribedBefore = traveller.hasSubscribedBefore, endsAt = until)
    }

    /** Le profil vient de se charger. */
    fun learn(profile: TravellerProfile) {
        learn(
            isUnlimited = profile.isSubscriber,
            hasSubscribedBefore = profile.subscription.hasEndedBefore,
            endsAt = profile.subscription.unlimitedUntil(),
        )
    }

    /** **L'échéance est passée** : l'illimité tombe partout, tout de suite. */
    fun expireIfDue(now: Instant = Instant.now()) {
        val end = endsAt ?: return
        if (end > now) return
        endsAt = null
        if (override == true) override = null
        if (known == true) known = false
        hasLapsed = true
        revision += 1
    }

    /** **Le store ne tient plus l'achat que le serveur n'a jamais confirmé** : le geste « acheté » rend la main. */
    fun withdrawUnconfirmedPurchase() {
        if (override != true || known == true) return
        override = null
        revision += 1
    }

    /** L'abonnement a pu changer ailleurs. Les écrans qui le montrent se relisent. */
    fun noteOutsideChange() {
        revision += 1
    }

    /**
     * Souscrire ou résilier : l'interface bascule tout de suite. Résilier passe
     * `grantsAccess` du profil, et non `false` : un mois entamé est un mois payé.
     *
     * @param until la fin de la période payée qu'une résiliation laisse ouverte.
     */
    fun record(isSubscribed: Boolean, until: Instant? = null) {
        override = isSubscribed
        hasSubscribedBefore = true
        endsAt = if (isSubscribed) until else null
        hasLapsed = false
    }

    /** Un crédit du jour servi **avant** le dernier geste, relu avec lui. */
    fun applied(credit: DailyCredit?): DailyCredit? {
        credit ?: return null
        val gesture = override
        return when {
            gesture != null -> credit.copy(isUnlimited = gesture)
            hasLapsed && known != true && credit.isUnlimited -> credit.copy(isUnlimited = false)
            else -> credit
        }
    }

    /** Oublie tout ce que la session savait — **à chaque changement de compte**. */
    fun reset() {
        override = null
        known = null
        hasSubscribedBefore = false
        endsAt = null
        hasLapsed = false
        revision += 1
    }

    /** Le bac à sable fait jouer l'abonnement à l'app entière. `null` rend la main aux données. Debug seulement. */
    fun play(isUnlimited: Boolean?) {
        override = isUnlimited
    }
}

/**
 * L'abonnement tel que la session le connaît. `null` dans un aperçu isolé, où
 * les écrans retombent sur [PaywallVariant.FirstTime] et sur le crédit du serveur.
 */
val LocalSubscriptionSession = staticCompositionLocalOf<SubscriptionSession?> { null }
