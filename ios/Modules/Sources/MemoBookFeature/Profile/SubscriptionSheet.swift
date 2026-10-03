import MemoBookCore
import MemoBookDesign
import StoreKit
import SwiftUI

/// L'abonnement, de bout en bout : ce qu'il rend, et les trois portes qu'il faut
/// pousser pour en sortir.
///
/// **Quatre feuilles, une seule présentation.** La ligne « Mon abonnement » du
/// profil n'ouvre qu'une feuille ; c'est son contenu qui change. Empiler quatre
/// `sheet` aurait fait reculer l'app quatre fois — ``BrandSheet`` recule d'un
/// cran à chaque feuille ouverte par-dessus — et une confirmation en trois temps
/// se serait lue comme un empilement de fenêtres au lieu d'un chemin.
///
/// Le chemin, justement :
///
/// ```
/// « Mon abonnement » ─→ .current  (« Mon Abonnement »)
///                          │ Résilier mon abonnement
///                          ▼
///                       .keepGoing (« Ton voyage continue »)
///                          │ Résilier
///                          ▼
///                       .reason    (« Pourquoi nous quittes-tu ? »)
///                          │ Confirmer ma résiliation
///                          ▼
///                       .done      (« C'est validé »)
/// ```
///
/// **Plus de feuille « Comment ça fonctionne ? »** (Hugo, 03/10/2026) : elle
/// précédait le paywall et racontait l'essai gratuit d'avant. « Découvrir
/// l'abonnement » ouvre désormais le paywall directement, et cette feuille
/// n'existe que pour qui est abonné — **ou l'a été et garde l'illimité jusqu'au
/// bout du mois payé** : ``Step/current`` le lui dit, avec la date, et lui
/// propose de se réinscrire.
///
/// À chaque étape, le bouton vert **garde** l'abonnement et le bouton rouge
/// avance vers la sortie : c'est la seule chose qu'on n'a pas eu à décider, la
/// maquette la répète trois fois.
///
/// **Un abonnement tenu par Apple se résilie chez Apple** (01/10/2026). Apple
/// ne laisse aucune app le faire à la place de son client : « Confirmer ma
/// résiliation » envoie la raison, puis ouvre la feuille de gestion des
/// abonnements d'iOS. C'est au retour de celle-ci, d'après ce que StoreKit dit
/// du renouvellement, qu'on passe à « C'est validé » — ou qu'on revient à
/// « Mon Abonnement » si la personne n'y a rien coupé.
struct SubscriptionSheet: View {
    let subscription: Subscription?
    let onActivate: () -> Void
    let onCancel: (SubscriptionCancellationReason?) -> Void

    /// La raison, seule, pour un abonnement tenu par Apple — la résiliation
    /// elle-même se fait dans la feuille d'iOS.
    var onRecordReason: (SubscriptionCancellationReason?) -> Void = { _ in }

    /// Ce que StoreKit dit du renouvellement au retour de la feuille d'iOS :
    /// `false`, il est coupé ; `true`, il court encore.
    var onAppStoreRenewal: (Bool) -> Void = { _ in }

    /// À qui la pastille s'adresse : « Abonnée » ou « Abonné » (T76). La forme
    /// non marquée quand on ne sait pas.
    var gender: Gender = .undisclosed

    /// Où on en est du chemin. `nil` tant qu'on n'a rien poussé : on part de
    /// « Mon Abonnement ». Dès qu'un bouton est touché, c'est cette valeur qui
    /// commande — sans quoi la dernière feuille disparaîtrait à l'instant même
    /// où la résiliation a lieu.
    @State private var step: Step?

    /// La raison choisie. Volontairement `nil` au départ : la maquette montre
    /// une carte sélectionnée, mais c'est l'état d'une carte qu'elle
    /// documente, pas une réponse cochée d'avance. En pré-cocher une
    /// fausserait le compteur qu'elle alimentera.
    @State private var reason: SubscriptionCancellationReason?

    /// La feuille de gestion des abonnements d'iOS, pour un abonnement tenu
    /// par Apple.
    @State private var managesAtApple = false

    /// La feuille d'où l'on est parti chez Apple : c'est là qu'on revient si
    /// la personne n'y a rien changé.
    @State private var managementOrigin: Step?

    /// Le prélèvement avait-il échoué **en entrant dans la feuille** — voir
    /// ``isBillingRetry``. Relevé une fois, à l'apparition, et gardé : le
    /// retour de la feuille d'Apple pose `cancelledAt`
    /// (``ProfileModel/acknowledgeAppStoreRenewal(_:)``), et « C'est validé »
    /// redisait sinon « Ton mois est réglé » à qui n'avait rien payé.
    @State private var enteredInBillingRetry: Bool?

    @Environment(\.subscriptionPurchase) private var subscriptionPurchase

    @Environment(\.dismiss) private var dismiss

    private var isManagedByAppStore: Bool { subscription?.managedByAppStore == true }

    enum Step: Hashable {
        case current
        case keepGoing
        case reason
        case done
    }

    private var currentStep: Step { step ?? .current }

    /// Le dernier jour du mois déjà payé, quand il en reste un.
    ///
    /// **Relevé sur l'abonnement tel qu'il était en entrant dans la feuille**,
    /// et gardé : `onCancel` met `isActive` à `false`, et
    /// ``Subscription/graceEnd(on:)`` ne rend une date que sur un abonnement
    /// résilié — les deux feuilles doivent donc lire la même chose avant et
    /// après le geste, sans quoi le chapeau de l'avant-dernière changerait sous
    /// les yeux au moment où on confirme.
    private var graceEnd: Date? {
        guard let subscription else { return nil }
        return subscription.isWithinPaidPeriod() ? subscription.paidThrough : nil
    }

    /// Résilié, mais encore dans le mois payé : « Mon Abonnement » le dit, et
    /// propose de se réinscrire au lieu de résilier une seconde fois.
    ///
    /// **Résilié veut dire `cancelledAt`** (03/10/2026). Pendant le délai de
    /// grâce de facturation d'Apple (`past_due`), le serveur sert `isActive`
    /// faux et une période payée à venir, sans rien de résilié : la feuille
    /// disait « Tu as résilié ton abonnement » à quelqu'un dont Apple retentait
    /// le prélèvement, et lui retirait « Résilier ». Toute vraie résiliation
    /// pose sa date — le serveur, ``ProfileModel/cancelSubscription(reason:)``,
    /// ``ProfileModel/acknowledgeAppStoreRenewal(_:)`` —, et un `past_due` se
    /// lit comme un abonnement actif.
    private var isInGrace: Bool {
        subscription?.isActive == false && subscription?.cancelledAt != nil && graceEnd != nil
    }

    /// La période que l'abonné a payée : un ancien abonné à la semaine lit
    /// « semaine » dans les phrases de la résiliation (03/10/2026).
    private var paidInterval: Subscription.Interval { subscription?.paidInterval ?? .month }

    /// **Le délai de grâce de facturation d'Apple** (`past_due`) : ni actif ni
    /// résilié. Le serveur y met la fin du délai dans `paidThrough`
    /// (`gracePeriodEndsAt`), mais rien n'a été encaissé : les trois feuilles
    /// de la résiliation ne disent donc ni « mois déjà réglé » ni « Ton mois
    /// est réglé » (03/10/2026).
    private var isBillingRetry: Bool {
        enteredInBillingRetry ?? Self.isBillingRetry(subscription)
    }

    static func isBillingRetry(_ subscription: Subscription?) -> Bool {
        subscription?.isActive == false && subscription?.cancelledAt == nil
    }

    /// Ce qui reste payé devant soi — ce que les trois feuilles de la
    /// résiliation racontent, avec ``graceEnd``. Voir ``SubscriptionCopy/PaidAhead``.
    private var paidAhead: SubscriptionCopy.PaidAhead {
        Self.paidAhead(of: subscription, graceEnd: graceEnd, isBillingRetry: isBillingRetry)
    }

    /// Le prélèvement raté d'abord ; puis un abonnement tenu par Apple dont
    /// on ne connaît pas la fin de période — un achat que le serveur n'a pas
    /// encore reçu, le plus souvent : couper le renouvellement chez Apple ne
    /// coupe jamais la période en cours ; sinon, le cas ordinaire.
    static func paidAhead(
        of subscription: Subscription?,
        graceEnd: Date?,
        isBillingRetry: Bool
    ) -> SubscriptionCopy.PaidAhead {
        if isBillingRetry { return .billingRetry }
        if subscription?.managedByAppStore == true, graceEnd == nil { return .heldByApple }
        return .settled
    }

    var body: some View {
        Group {
            switch currentStep {
            case .current: current
            case .keepGoing: keepGoing
            case .reason: reasons
            case .done: done
            }
        }
        .animation(.smooth(duration: 0.3), value: currentStep)
        .onAppear {
            if enteredInBillingRetry == nil { enteredInBillingRetry = Self.isBillingRetry(subscription) }
        }
        .manageSubscriptionsSheet(isPresented: $managesAtApple)
        .onChange(of: managesAtApple) { _, isOpen in
            guard !isOpen else { return }
            Task { await settleAppStoreManagement() }
        }
    }

    /// Ouvre la feuille d'Apple, en retenant d'où l'on part.
    private func manageAtApple() {
        managementOrigin = currentStep
        managesAtApple = true
    }

    /// La feuille d'iOS vient de se refermer : on lit sur l'appareil si le
    /// renouvellement court encore, et on avance d'après ce qu'Apple dit — pas
    /// d'après le bouton qu'on a touché. `nil` (StoreKit ne sait pas) ne change
    /// rien : mieux vaut rester sur place qu'annoncer une résiliation qui n'a
    /// pas eu lieu.
    ///
    /// Renouvellement coupé : depuis la confirmation, c'est « C'est validé » ;
    /// depuis une réinscription qui n'a pas eu lieu, on reste où l'on était.
    private func settleAppStoreManagement() async {
        guard let renews = await subscriptionPurchase?.willAutoRenew() else { return }
        onAppStoreRenewal(renews)
        if renews {
            step = .current
        } else {
            step = managementOrigin == .reason ? .done : (managementOrigin ?? .done)
        }
    }

    // MARK: - « Mon Abonnement »

    private var current: some View {
        BrandSheet(
            SubscriptionCopy.currentTitle,
            badge: SubscriptionCopy.currentBadge(for: gender),
            subtitle: isInGrace
                ? SubscriptionCopy.graceSubtitle(until: graceEnd)
                : SubscriptionCopy.currentSubtitle
        ) {
            VStack(alignment: .leading, spacing: MemoBookSpacing.m) {
                if isInGrace {
                    // Rien à rappeler : la résiliation est faite. Ce qui reste à
                    // proposer, c'est de revenir sur sa décision.
                    BrandButton(SubscriptionCopy.subscribeAgain, style: .accent, fillsWidth: true) {
                        resubscribe()
                    }
                } else {
                    SubscriptionCallout(
                        title: SubscriptionCopy.autoCancelTitle(destination: subscription?.tripDestination),
                        message: SubscriptionCopy.autoCancelBody(endsOn: subscription?.endsOn)
                    )

                    BrandButton(SubscriptionCopy.cancelSubscription, style: .destructive, fillsWidth: true) {
                        step = .keepGoing
                    }
                }
            }
        }
    }

    /// Se réinscrire pendant le mois payé. Chez Apple, c'est **réarmer** le
    /// renouvellement — dans la même feuille d'iOS.
    private func resubscribe() {
        if isManagedByAppStore {
            manageAtApple()
        } else {
            onActivate()
            step = .current
        }
    }

    // MARK: - Résiliation 1 — « Ton voyage continue »

    private var keepGoing: some View {
        BrandSheet(
            SubscriptionCopy.keepGoingTitle,
            paragraphs: SubscriptionCopy.keepGoingParagraphs(
                tripTitle: subscription?.tripTitle,
                graceEnd: graceEnd,
                interval: paidInterval,
                paidAhead: paidAhead
            )
        ) {
            VStack(spacing: MemoBookSpacing.s) {
                BrandButton(SubscriptionCopy.waitForAutoCancel, fillsWidth: true) { dismiss() }

                BrandButton(
                    SubscriptionCopy.cancel,
                    icon: Image(brand: "IconArrowForward"),
                    iconPlacement: .trailing,
                    style: .destructive,
                    fillsWidth: true
                ) {
                    step = .reason
                }
            }
        }
    }

    // MARK: - Résiliation 2 — « Pourquoi nous quittes-tu ? »

    private var reasons: some View {
        BrandSheet(
            SubscriptionCopy.reasonTitle,
            paragraphs: SubscriptionCopy.reasonParagraphs(
                graceEnd: graceEnd,
                interval: paidInterval,
                paidAhead: paidAhead
            )
        ) {
            VStack(spacing: MemoBookSpacing.m) {
                BrandOptionGroup {
                    ForEach(SubscriptionCancellationReason.allCases) { candidate in
                        BrandOptionRow(candidate.label, isSelected: reason == candidate) {
                            reason = candidate
                        }
                    }
                }

                VStack(spacing: MemoBookSpacing.s) {
                    BrandButton(SubscriptionCopy.stayAWhile, fillsWidth: true) { dismiss() }

                    // La résiliation a lieu **ici**, pas sur la feuille
                    // suivante : celle-ci annonce ce qui vient d'arriver, elle
                    // ne le demande plus.
                    BrandButton(
                        SubscriptionCopy.confirmCancellation,
                        icon: Image(brand: "IconCross"),
                        style: .destructive,
                        fillsWidth: true
                    ) {
                        if isManagedByAppStore {
                            onRecordReason(reason)
                            manageAtApple()
                        } else {
                            onCancel(reason)
                            step = .done
                        }
                    }
                    // Grisé tant qu'aucune raison n'est cochée — Hugo,
                    // 14/09/2026. La question est posée pour être répondue :
                    // confirmer sans raison passait à côté du seul retour que
                    // cette feuille rapporte.
                    .disabled(reason == nil)
                }
            }
        }
    }

    // MARK: - Résiliation 3 — « C'est validé »

    private var done: some View {
        BrandSheet(
            SubscriptionCopy.doneTitle,
            paragraphs: SubscriptionCopy.doneParagraphs(
                graceEnd: graceEnd,
                interval: paidInterval,
                paidAhead: paidAhead
            )
        ) {
            VStack(spacing: MemoBookSpacing.s) {
                BrandButton(SubscriptionCopy.backHome, fillsWidth: true) { dismiss() }

                BrandButton(SubscriptionCopy.subscribeAgain, style: .accent, fillsWidth: true) {
                    resubscribe()
                }
            }
        }
    }
}

/// L'encadré bleu de la feuille « Mon Abonnement » : ce qui va se passer tout
/// seul, et pourquoi.
private struct SubscriptionCallout: View {
    let title: String
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: MemoBookSpacing.xs / 2) {
            Text(title)
                .font(MemoBookFont.calloutTitle)
            Text(message)
                .font(MemoBookFont.taglineRegular)
        }
        // Le corps est à l'encre pleine et non en gris : ce n'est pas une
        // légende, c'est l'explication qu'on est venu chercher.
        .foregroundStyle(MemoBookColor.ink)
        .multilineTextAlignment(.leading)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, MemoBookSpacing.s)
        .padding(.vertical, MemoBookSpacing.m)
        .background(
            MemoBookColor.outline.opacity(0.5),
            in: .rect(cornerRadius: MemoBookSpacing.controlCornerRadius)
        )
        .accessibilityElement(children: .combine)
    }
}

// MARK: - La copie

/// Tous les libellés des quatre feuilles, et des deux alertes de l'accueil, en
/// un seul endroit.
///
/// La maquette porte neuf fautes de français et deux formes d'apostrophe ; **Hugo
/// a tranché de toutes les corriger** (D12, T66) plutôt que de les recopier
/// comme R8 le veut par défaut. C'est donc l'un des rares endroits où le code
/// s'écarte volontairement de Figma, et la liste des écarts vit dans la fiche
/// écran pour que Clara les reprenne à la source.
///
/// L'apostrophe est **partout typographique** (’), y compris dans les trois
/// feuilles de résiliation et les quatre raisons, où Figma emploie la droite.
///
/// **Résilier ne ferme plus le micro** (Hugo, 03/10/2026) : sans abonnement, on
/// retrouve le crédit du jour — cinq minutes par jour et par voyage. Les
/// phrases qui annonçaient « tu ne pourras plus dicter tes souvenirs » disent
/// désormais ce qu'on retrouve, et la période payée est **celle de l'abonné** :
/// le mois, ou la semaine d'un abonné de l'ancienne formule, toujours honoré
/// (``Subscription/paidInterval``).
///
/// **Plus de « inclus » après la date** (03/10/2026) : ni l'app ni le serveur
/// ne tiennent le dernier jour en entier — le serveur coupe à l'heure exacte
/// où la période payée s'achève.
enum SubscriptionCopy {
    /// Ce qu'on retrouve sans abonnement — la même phrase dans les trois
    /// feuilles de résiliation, pour qu'elles ne se contredisent pas.
    static let dailyCreditBack = "tu retrouves le crédit du jour : 5 minutes par jour et par voyage"

    /// « mois » est masculin, « semaine » féminin : les phrases de la
    /// résiliation s'accordent sur la période payée plutôt que d'y glisser un
    /// mot — « Ton semaine est réglé » ne se lit pas.
    private static func thePaidPeriod(_ interval: Subscription.Interval) -> String {
        switch interval {
        case .month: "la fin du mois déjà réglé"
        case .week: "la fin de la semaine déjà réglée"
        }
    }

    private static func yourPeriodIsPaid(_ interval: Subscription.Interval, already: Bool = false) -> String {
        switch interval {
        case .month: already ? "Ton mois est déjà réglé" : "Ton mois est réglé"
        case .week: already ? "Ta semaine est déjà réglée" : "Ta semaine est réglée"
        }
    }

    /// Ce qui reste payé devant soi au moment de résilier (03/10/2026). Les
    /// trois feuilles le lisent avec la date de fin (`graceEnd`), et ne
    /// disent « réglé » que de ce qui l'est.
    enum PaidAhead: Sendable, Hashable {
        /// Le cas ordinaire : la période réglée court jusqu'à la date connue —
        /// ou, sans date, l'abonnement s'arrête aujourd'hui.
        case settled
        /// **Apple tient une période payée dont l'app ne connaît pas la fin** :
        /// un achat encaissé que le serveur n'a pas encore reçu
        /// (`awaitingServer`), ou un serveur qui ne sert pas la date. Couper le
        /// renouvellement chez Apple ne coupe jamais la période en cours :
        /// « L’abonnement s’arrête aujourd’hui » mentait.
        case heldByApple
        /// **Le dernier prélèvement n'est pas passé** (`past_due`, délai de
        /// grâce d'Apple) : rien n'est réglé, Apple réessaie et laisse
        /// raconter en attendant. « Ton mois est déjà réglé » mentait.
        case billingRetry
    }

    /// Le prélèvement raté, dit tel quel : Apple réessaie, et l'illimité tient
    /// en attendant — jusqu'à la fin du délai quand le serveur la connaît.
    private static func paymentFailed(until graceEnd: Date?) -> String {
        guard let graceEnd else {
            return "Ton dernier prélèvement n’est pas passé : Apple réessaie, et te laisse raconter sans limite en attendant."
        }
        return
            "Ton dernier prélèvement n’est pas passé : Apple réessaie, et te laisse raconter sans limite jusqu’au \(graceEnd.dayAndMonth)."
    }

    // — « Mon Abonnement »

    static let currentTitle = "Mon Abonnement"
    /// La maquette écrit « Abonnée » ; l'app accorde sur ce que le profil sait
    /// de la personne (T76).
    static func currentBadge(for gender: Gender) -> String { gender.agreed("Abonné") }
    static let currentSubtitle =
        "Tu as déjà souscrit à ton abonnement MemoBook : tu racontes sans limite, à l’oral comme à l’écrit."

    /// Résilié, mais le mois payé court encore : l'illimité reste ouvert, et
    /// la phrase le date. Sans date — un serveur qui ne la sert pas —, on dit
    /// seulement ce qui vient ensuite.
    static func graceSubtitle(until graceEnd: Date?) -> String {
        guard let graceEnd else {
            return "Tu as résilié ton abonnement : ensuite, \(dailyCreditBack)."
        }
        return
            "Tu as résilié ton abonnement : tu racontes sans limite jusqu’au \(graceEnd.dayAndMonth). Ensuite, \(dailyCreditBack)."
    }

    /// ⚠️ **État non maquetté** : sans destination, la phrase s'arrête au
    /// voyage — un abonnement acheté hors d'un voyage n'en porte pas.
    static func autoCancelTitle(destination: String?) -> String {
        guard let destination, !destination.isEmpty else {
            return "Un rappel à la fin de ton voyage."
        }
        return "Un rappel à la fin de ton voyage à \(destination)."
    }

    /// ⚠️ **État non maquetté** : sans date de fin, on promet la même chose sans
    /// avancer de délai — plutôt qu'un « dans 0 jour ».
    static func autoCancelBody(endsOn: Date?) -> String {
        let opening =
            "Parce que l’on sait que tu n’as pas besoin de notre application en dehors de tes voyages, on te proposera de résilier ton abonnement"
        guard let endsOn else { return "\(opening) à la fin de ton voyage." }
        return "\(opening) \(endsOn.relativeDelay)."
    }

    static let cancelSubscription = "Résilier mon abonnement"

    // — Résiliation 1 : « Ton voyage continue »

    static let keepGoingTitle = "Ton voyage continue"

    /// ⚠️ **État non maquetté** : sans titre de voyage, la première phrase se
    /// passe des guillemets.
    ///
    /// **La deuxième phrase dit *quand*** (Hugo, 19/09/2026) : la période déjà
    /// réglée continue, et elle nomme le jour, comme les deux feuilles
    /// suivantes. Sans période réglée, elle dit seulement ce qu'on retrouve.
    static func keepGoingParagraphs(
        tripTitle: String?,
        graceEnd: Date?,
        interval: Subscription.Interval = .month,
        paidAhead: PaidAhead = .settled
    ) -> [String] {
        let opening =
            if let tripTitle, !tripTitle.isEmpty {
                "Il te reste encore quelques jours dans ton voyage “\(tripTitle)”."
            } else {
                "Il te reste encore quelques jours dans ton voyage."
            }
        let consequence =
            switch paidAhead {
            case .billingRetry:
                "\(paymentFailed(until: graceEnd)) Si tu coupes maintenant, Apple cesse de réessayer, et \(dailyCreditBack)."
            case .heldByApple where graceEnd == nil:
                "Si tu coupes maintenant, tu racontes sans limite jusqu’à la fin de la période déjà réglée. Ensuite, \(dailyCreditBack)."
            case .settled, .heldByApple:
                if let graceEnd {
                    "Si tu coupes maintenant, tu racontes sans limite jusqu’à \(thePaidPeriod(interval)), le \(graceEnd.dayAndMonth). Ensuite, \(dailyCreditBack)."
                } else {
                    "Si tu coupes maintenant, \(dailyCreditBack)."
                }
            }
        return [
            opening,
            consequence,
            "Pour rappel, on te proposera de le résilier à ton retour, en un geste.",
        ]
    }

    static let waitForAutoCancel = "Attendre la fin du voyage"
    static let cancel = "Résilier"

    // — Résiliation 2 : « Pourquoi nous quittes-tu ? »

    static let reasonTitle = "Pourquoi nous quittes-tu ?"

    /// Le chapeau de l'avant-dernière feuille — **et c'est ici que se dit le
    /// sursis** (Hugo, 16/09/2026).
    ///
    /// Ici, et pas sur la dernière : c'est la feuille où l'on est encore en
    /// train de décider. Apprendre après coup qu'on gardait son mois est une
    /// bonne nouvelle qui arrive trop tard — on a hésité pour rien.
    ///
    /// Sans mois restant — il se termine aujourd'hui, ou rien n'a été payé —,
    /// la phrase ne s'écrit pas : promettre « jusqu'au 16 septembre » le 16
    /// septembre ne promet rien.
    ///
    /// Un prélèvement raté n'a rien réglé : la feuille dit plutôt qu'un moyen
    /// de paiement à jour suffit à garder l'abonnement — c'est peut-être tout
    /// ce qui motivait le geste. Une période tenue par Apple sans date connue
    /// va à son terme, et la phrase le dit sans inventer de jour.
    static func reasonParagraphs(
        graceEnd: Date?,
        interval: Subscription.Interval = .month,
        paidAhead: PaidAhead = .settled
    ) -> [String] {
        var paragraphs = [
            "Aide-nous à faire évoluer l’application.",
            "Choisis la raison principale.",
        ]
        switch paidAhead {
        case .billingRetry:
            paragraphs.append(
                "Si c’est le prélèvement qui bloque, mets à jour ton moyen de paiement dans les réglages de ton compte Apple : l’abonnement repartira tout seul."
            )
            return paragraphs
        case .heldByApple where graceEnd == nil:
            paragraphs.append(
                "La période déjà réglée va à son terme : tu continues de raconter sans limite jusqu’à sa fin."
            )
            return paragraphs
        case .settled, .heldByApple:
            break
        }
        if let graceEnd {
            paragraphs.append(
                "\(yourPeriodIsPaid(interval, already: true)) : tu continues de raconter sans limite jusqu’au \(graceEnd.dayAndMonth)."
            )
        }
        return paragraphs
    }

    static let stayAWhile = "Rester abonné encore quelques jours"
    static let confirmCancellation = "Confirmer ma résiliation"

    // — Résiliation 3 : « C'est validé »

    static let doneTitle = "C’est validé"

    /// Ce que la dernière feuille annonce.
    ///
    /// **Deux versions.** Quand le mois payé se termine aujourd'hui — ou qu'il
    /// n'y en a pas —, l'abonnement s'arrête aujourd'hui, et le crédit du jour
    /// revient tout de suite. Quand il reste des jours réglés, la phrase les
    /// nomme plutôt que de mentir d'un mois.
    ///
    /// **Et deux cas où l'on ne sait pas dire « réglé jusqu'au »**
    /// (03/10/2026) : un prélèvement raté, où rien n'est réglé ; une période
    /// tenue par Apple dont on ne connaît pas la fin, qui ne s'arrête pas
    /// aujourd'hui pour autant. Voir ``PaidAhead``.
    static func doneParagraphs(
        graceEnd: Date?,
        interval: Subscription.Interval = .month,
        paidAhead: PaidAhead = .settled
    ) -> [String] {
        let keepsBook = "et tu gardes accès à ton carnet de bord pour le relire quand tu veux."
        switch paidAhead {
        case .billingRetry:
            return [
                "L’abonnement ne se renouvellera pas.",
                "Ton dernier prélèvement n’était pas passé : Apple ne le retentera pas.",
                "Ensuite, \(dailyCreditBack), \(keepsBook)",
            ]
        case .heldByApple where graceEnd == nil:
            return [
                "L’abonnement ne se renouvellera pas.",
                "La période déjà réglée va à son terme : d’ici là, rien ne change — tu racontes sans limite, comme avant.",
                "Ensuite, \(dailyCreditBack), \(keepsBook)",
            ]
        case .settled, .heldByApple:
            break
        }
        guard let graceEnd else {
            return [
                "L’abonnement s’arrête aujourd’hui.",
                "Tu retrouves le crédit du jour : 5 minutes par jour et par voyage, \(keepsBook)",
            ]
        }
        return [
            "L’abonnement ne se renouvellera pas.",
            "\(yourPeriodIsPaid(interval)) jusqu’au \(graceEnd.dayAndMonth) : d’ici là, rien ne change — tu racontes sans limite, comme avant.",
            "Ensuite, \(dailyCreditBack), \(keepsBook)",
        ]
    }

    // — L'alerte du système, quand le sursis s'achève

    /// Le titre de l'alerte native qui s'ouvre le jour où le mois payé
    /// s'achève.
    ///
    /// **Une alerte du système et non une feuille de la marque**, et c'est
    /// voulu : elle n'arrive pas au bout d'un geste qu'on vient de faire, elle
    /// tombe à l'ouverture de l'app, des jours plus tard. Une feuille qui monte
    /// toute seule se lit comme un écran de l'app ; une alerte se lit comme une
    /// nouvelle. C'est la même raison qui fait qu'iOS annonce lui-même la fin
    /// d'un abonnement.
    static let endedTitle = "Ton abonnement MemoBook s’est arrêté"

    /// On ne perd rien : on retrouve le crédit du jour, et l'illimité est à un
    /// geste (Hugo, 03/10/2026).
    ///
    /// **La période sans la nommer** (03/10/2026) : l'accueil, qui ouvre
    /// l'alerte, ne sait pas si l'abonné payait le mois ou la semaine de
    /// l'ancienne formule — « Ton mois réglé est terminé » mentait à ce
    /// dernier.
    static func endedMessage(tripTitle: String?) -> String {
        let opening =
            if let tripTitle, !tripTitle.isEmpty {
                "La période que tu avais réglée est terminée, et l’abonnement de « \(tripTitle) » ne s’est pas renouvelé."
            } else {
                "La période que tu avais réglée est terminée, et l’abonnement ne s’est pas renouvelé."
            }
        return
            "\(opening) Tu retrouves 5 minutes par jour et par voyage. Pour raconter sans compter, réabonne-toi."
    }

    static let endedDismiss = "D’accord"

    // — Le rappel de fin de voyage, sur l'accueil
    static let tripEndTitle = "Ton voyage est terminé"
    static let tripEndMessage =
        "Ton abonnement MemoBook va se renouveler, alors que tu n’en as pas besoin entre deux voyages. Tu peux le résilier maintenant, tes carnets restent à toi."
    static let tripEndCancel = "Résilier mon abonnement"
    static let tripEndKeep = "Le garder"
    static let endedResubscribe = "Me réabonner"
    static let backHome = "Revenir à l’accueil"
    static let subscribeAgain = "S’inscrire à nouveau"
}

// MARK: - Aperçus

private struct SubscriptionSheetPreview: View {
    let subscription: Subscription?
    var typeSize: DynamicTypeSize = .large

    var body: some View {
        Color.clear
            .background(MemoBookColor.background)
            .sheet(isPresented: .constant(true)) {
                SubscriptionSheet(subscription: subscription, onActivate: {}, onCancel: { _ in })
                    .environment(\.dynamicTypeSize, typeSize)
            }
    }
}

/// Résilié il y a deux jours, le mois payé court encore trois semaines.
private let cancelledInGrace = Subscription(
    price: 4.99,
    isActive: false,
    cancelledAt: .now.addingTimeInterval(-2 * 86_400),
    paidThrough: .now.addingTimeInterval(21 * 86_400),
    managedByAppStore: true
)

#Preview("Mon Abonnement — abonné") {
    SubscriptionSheetPreview(subscription: TravellerProfile.fixture.subscription)
}

#Preview("Mon Abonnement — résilié, mois payé") {
    SubscriptionSheetPreview(subscription: cancelledInGrace)
}

#Preview("Abonné — Dynamic Type AX3") {
    SubscriptionSheetPreview(
        subscription: TravellerProfile.fixture.subscription,
        typeSize: .accessibility3
    )
}
