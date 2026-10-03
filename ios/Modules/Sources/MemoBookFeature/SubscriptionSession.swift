import MemoBookCore
import Observation
import SwiftUI

/// Ce que la session sait de l'abonnement du compte, d'un écran à l'autre.
///
/// **Depuis le crédit du jour (Hugo, 03/10/2026), l'abonnement n'ouvre plus
/// qu'une chose : l'illimité.** Tout le monde raconte, cinq minutes par jour et
/// par voyage ; l'abonné raconte sans compter. Il n'y a donc plus de palier à
/// porter, plus de verrou de micro : il reste deux faits, et cet objet les fait
/// circuler entre des écrans qui ont chacun leur modèle et leur appel.
///
/// 1. **Ce compte raconte-t-il sans limite ?** Le serveur le dit à l'accueil
///    (`traveller.isUnlimited`), au profil (`subscription`) et dans chaque
///    crédit du jour (`dailyCredit.isUnlimited`). Mais un achat ou une
///    résiliation doivent basculer l'interface **tout de suite**, sans attendre
///    la prochaine relecture : la barre d'enregistrement ne doit pas compter les
///    secondes d'un abonné qui vient de payer. Le geste a donc le dernier mot
///    sur ce que le serveur a dit avant lui — **et seulement jusqu'à ce que le
///    serveur dise la même chose** (03/10/2026) : il rend alors la main, et ce
///    que le serveur dira ensuite (l'échéance du mois payé, un remboursement)
///    fait foi.
/// 2. **Quelle version du paywall montrer ?** Quelqu'un qui a déjà été abonné
///    voit la version « retour » (deux écrans), partout — profil, conversation,
///    réglages du voyage, accueil — et plus seulement depuis le profil, le seul
///    écran qui le savait jusqu'ici.
///
/// ## L'API (stable : la conversation et les réglages du voyage s'en servent)
///
/// - ``isUnlimited`` — vrai pour un abonné (ou un résilié encore dans sa
///   période payée). Faux tant qu'on ne sait rien : le serveur tranche de toute
///   façon, l'app ne fait que prévenir.
/// - ``paywallVariant`` — `.returning` pour qui a déjà été abonné, sinon
///   `.firstTime`. À passer tel quel à
///   `PaywallView(subscription:variant:previewMemoId:onSubscribe:)`.
/// - ``record(isSubscribed:)`` — à appeler dans **chaque** `onSubscribe` du
///   paywall (`true`) et après une résiliation (`grantsAccess` du profil).
/// - ``learn(isUnlimited:hasSubscribedBefore:)``, et ses deux raccourcis
///   `learn(_: Traveller)` (accueil) et `learn(_: TravellerProfile)` (profil) —
///   ce qu'un écran vient de lire du serveur.
/// - ``applied(to:)`` — un ``DailyCredit`` servi avant le geste, relu avec lui :
///   illimité tout de suite après un achat.
/// - ``reset()`` — à chaque changement de compte : déconnexion, session
///   refusée, compte supprimé. Le geste et l'histoire d'un compte ne passent
///   pas au suivant.
///
/// Elle ne porte que les gestes **vrais** — souscrire, résilier. Le bac à sable,
/// lui, passe par ``SandboxPersona``, qui retouche les données au lieu de les
/// contredire ; le panneau de débogage efface donc le geste retenu avant de
/// faire jouer un personnage (``play(isUnlimited:)``).
@MainActor
@Observable
final class SubscriptionSession {
    /// Ce que le dernier geste de la session a décidé — acheter (`true`),
    /// résilier sans période payée devant soi (`false`) —, ou `nil` pour
    /// laisser parler le serveur.
    private(set) var override: Bool?

    /// Ce que le serveur a dit en dernier, tel que l'accueil ou le profil l'ont
    /// reçu. `nil` tant qu'aucun des deux n'a répondu.
    private(set) var known: Bool?

    /// Ce compte a déjà été abonné — en ce moment ou par le passé. C'est ce qui
    /// choisit la version du paywall.
    private(set) var hasSubscribedBefore = false

    init() {}

    /// Le compte raconte-t-il sans limite ? Le geste de la session d'abord,
    /// sinon ce que le serveur a dit ; faux tant qu'on ne sait rien.
    var isUnlimited: Bool { override ?? known ?? false }

    /// La version du paywall à montrer, d'où qu'on l'ouvre. Voir
    /// ``PaywallVariant``.
    var paywallVariant: PaywallVariant { hasSubscribedBefore ? .returning : .firstTime }

    /// Un écran vient de lire le serveur.
    ///
    /// **Le geste rend la main dès que le serveur le confirme** (03/10/2026).
    /// Il était gardé pour toute la session, et imposé à tout ce que le serveur
    /// disait ensuite : un résilié dont le mois payé venait de s'achever, ou un
    /// abonné remboursé par Apple, restait « illimité » dans la conversation
    /// pendant que le serveur refusait ses tours. Après un achat, la prochaine
    /// lecture qui dit `true` lève le geste ; après une résiliation dans le mois
    /// payé, le serveur dit `true` lui aussi, et dira `false` à l'échéance. Une
    /// réponse qui le contredit — servie avant lui, ou un serveur qui n'a pas
    /// encore vu l'achat — ne le lève pas.
    ///
    /// `hasSubscribedBefore` ne redescend jamais dans une session : avoir été
    /// abonné est un fait d'histoire, et un serveur plus ancien qui ne le sert
    /// pas encore ne doit pas faire revoir la découverte à qui vient d'acheter.
    /// Seul ``reset()`` l'efface, quand le compte change.
    func learn(isUnlimited: Bool, hasSubscribedBefore: Bool) {
        if override == isUnlimited { override = nil }
        known = isUnlimited
        if hasSubscribedBefore || isUnlimited { self.hasSubscribedBefore = true }
    }

    /// L'accueil vient de lire son contenu.
    func learn(_ traveller: Traveller) {
        learn(isUnlimited: traveller.isUnlimited, hasSubscribedBefore: traveller.hasSubscribedBefore)
    }

    /// Le profil vient de se charger.
    func learn(_ profile: TravellerProfile) {
        learn(
            isUnlimited: profile.isSubscriber,
            hasSubscribedBefore: profile.subscription.hasEndedBefore
        )
    }

    /// Souscrire ou résilier : l'interface bascule tout de suite.
    ///
    /// Résilier passe `grantsAccess` du profil, et non `false` : un mois
    /// entamé est un mois payé, l'illimité reste ouvert jusqu'à sa fin. Les
    /// deux gestes disent aussi qu'il y a eu un abonnement — le prochain paywall
    /// sera celui du retour.
    func record(isSubscribed: Bool) {
        override = isSubscribed
        hasSubscribedBefore = true
    }

    /// Un crédit du jour servi **avant** le dernier geste, relu avec lui.
    ///
    /// Le fil de la conversation, les réglages du voyage et l'accueil tiennent
    /// le crédit que le serveur leur a rendu ; juste après un achat, il dit
    /// encore « 1 min 20 restante ». Sans geste dans la session, le crédit du
    /// serveur fait foi tel quel.
    func applied(to credit: DailyCredit?) -> DailyCredit? {
        guard var credit, let override else { return credit }
        credit.isUnlimited = override
        return credit
    }

    /// Oublie tout ce que la session savait — **à chaque changement de compte**
    /// (03/10/2026) : déconnexion, session refusée par le serveur, compte
    /// supprimé.
    ///
    /// La session vit dans ``RootView`` pour toute la vie de l'app. Sans ça,
    /// l'achat de A restait imposé aux crédits de B, connecté ensuite sur le
    /// même iPhone : ni avertissement à 4:30, ni arrêt à 5:00, des tours
    /// refusés par le serveur — et le paywall « C’est reparti ? » d'un ancien
    /// abonné montré à quelqu'un qui n'a jamais souscrit. Remise à zéro sur
    /// place plutôt que remplacée : un écran encore monté garde sa référence.
    func reset() {
        override = nil
        known = nil
        hasSubscribedBefore = false
    }

    #if DEBUG
        /// Le bac à sable fait jouer l'abonnement à l'app entière — l'accueil
        /// tout de suite, le profil à sa prochaine ouverture. `nil` rend la main
        /// aux données.
        func play(isUnlimited: Bool?) {
            override = isUnlimited
        }
    #endif
}

extension EnvironmentValues {
    /// L'abonnement tel que la session le connaît. `nil` dans un aperçu isolé,
    /// où personne n'achète et où ce n'est pas un problème : les écrans
    /// retombent sur `.firstTime` et sur le crédit du serveur.
    @Entry var subscriptionSession: SubscriptionSession?
}
