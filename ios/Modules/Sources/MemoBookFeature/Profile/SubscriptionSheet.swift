import MemoBookCore
import MemoBookDesign
import SwiftUI

/// L'abonnement, de bout en bout : ce qu'il coûte, ce qu'il rend, et les trois
/// portes qu'il faut pousser pour en sortir.
///
/// **Cinq feuilles, une seule présentation.** La ligne « Mon abonnement » du
/// profil n'ouvre qu'une feuille ; c'est son contenu qui change. Empiler cinq
/// `sheet` aurait fait reculer l'app cinq fois — ``BrandSheet`` recule d'un cran
/// à chaque feuille ouverte par-dessus — et une confirmation en trois temps se
/// serait lue comme un empilement de fenêtres au lieu d'un chemin.
///
/// Le chemin, justement :
///
/// ```
///                    ┌─ pas abonné ─→ .pitch  (« Comment ça fonctionne ? »)
/// « Mon abonnement » ┤
///                    └─ abonné ─────→ .current (« Mon Abonnement »)
///                                        │ Résilier mon abonnement
///                                        ▼
///                                     .keepGoing (« Ton voyage continue »)
///                                        │ Résilier
///                                        ▼
///                                     .reason  (« Pourquoi nous quittes-tu ? »)
///                                        │ Confirmer ma résiliation
///                                        ▼
///                                     .done    (« C'est validé »)
/// ```
///
/// À chaque étape, le bouton vert **garde** l'abonnement et le bouton rouge
/// avance vers la sortie : c'est la seule chose qu'on n'a pas eu à décider, la
/// maquette la répète trois fois.
struct SubscriptionSheet: View {
    let subscription: Subscription?
    let onActivate: () -> Void
    let onCancel: (SubscriptionCancellationReason?) -> Void
    /// « En savoir plus » ouvre le paywall — trois écrans qui déroulent l'offre
    /// en entier, là où la feuille n'en donne que le principe.
    let onLearnMore: () -> Void

    /// Le carnet que l'aperçu montre. `nil` — un compte sans voyage en cours —
    /// ouvre le jeu d'essai : l'aperçu est là pour montrer à quoi ça ressemble.
    var previewMemoId: String?

    /// Où on en est du chemin. `nil` tant qu'on n'a rien poussé : l'étape de
    /// départ se **déduit** alors de l'abonnement, pour qu'elle suive le profil
    /// s'il arrive après l'ouverture de la feuille. Dès qu'un bouton est
    /// touché, c'est cette valeur qui commande — sans quoi la dernière feuille
    /// disparaîtrait à l'instant même où la résiliation a lieu.
    @State private var step: Step?

    /// La raison choisie. Volontairement `nil` au départ : la maquette montre
    /// une carte sélectionnée, mais c'est l'état d'une carte qu'elle
    /// documente, pas une réponse cochée d'avance. En pré-cocher une
    /// fausserait le compteur qu'elle alimentera.
    @State private var reason: SubscriptionCancellationReason?

    @Environment(\.dismiss) private var dismiss

    enum Step: Hashable {
        case pitch
        case current
        /// L'aperçu du carnet, ouvert par la pastille « Voir un aperçu ».
        ///
        /// **Une étape de la feuille, et non une feuille par-dessus.** C'est la
        /// règle du design system : une feuille ouverte sur une autre fait
        /// reculer celle du dessous, et deux reculs se lisent comme un
        /// empilement de fenêtres. Le contenu change, la feuille reste — comme
        /// pour les trois temps de la résiliation.
        case preview
        case keepGoing
        case reason
        case done
    }

    private var currentStep: Step {
        step ?? (subscription?.isActive == true ? .current : .pitch)
    }

    private var price: String { (subscription?.weeklyPrice ?? 0).euros }

    var body: some View {
        Group {
            switch currentStep {
            case .pitch: pitch
            case .current: current
            case .preview: preview
            case .keepGoing: keepGoing
            case .reason: reasons
            case .done: done
            }
        }
        .animation(.smooth(duration: 0.3), value: currentStep)
    }

    // MARK: - « Comment ça fonctionne ? » — pas encore abonné

    private var pitch: some View {
        BrandSheet(SubscriptionCopy.pitchTitle) {
            VStack(alignment: .leading, spacing: MemoBookSpacing.m) {
                VStack(alignment: .leading, spacing: MemoBookSpacing.l) {
                    SubscriptionTimeline()
                    offer
                    HowToCancelCard()
                }

                BrandButton(
                    SubscriptionCopy.learnMore,
                    icon: Image(brand: "IconArrowForward"),
                    iconPlacement: .trailing,
                    fillsWidth: true,
                    action: onLearnMore
                )
            }
        }
    }

    /// L'argument de vente : deux lignes vertes centrées, et la pastille qui
    /// promet un aperçu.
    private var offer: some View {
        VStack(spacing: MemoBookSpacing.s) {
            VStack(spacing: 0) {
                Text(SubscriptionCopy.offerHeadline(price: price))
                    .font(MemoBookFont.bodySemibold)
                Text(SubscriptionCopy.offerCadence)
                    .font(MemoBookFont.body)
            }
            .foregroundStyle(MemoBookColor.action)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityElement(children: .combine)

            // Elle garde son dessin de pastille, comme la maquette, mais elle
            // **ouvre** désormais l'aperçu : c'est une proposition posée dans
            // une phrase, pas l'appel à l'action de la feuille.
            Button { step = .preview } label: {
                BrandTagPill(
                    SubscriptionCopy.previewPill,
                    tone: .accentOutlined,
                    isUppercased: true
                )
            }
            .buttonStyle(.plain)
            // La cible tactile monte à 2.75 rem même si la pastille est plus
            // courte : le dessin est plus petit que le geste (R7).
            .frame(minHeight: MemoBookSpacing.minimumTapTarget)
            .contentShape(.rect)
            .accessibilityAddTraits(.isButton)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - L'aperçu du carnet

    /// Le carnet qu'on feuillette sans quitter l'offre.
    ///
    /// Le bouton du bas ramène au principe de l'abonnement : on est venu voir
    /// ce qu'on achète, on doit repartir d'où l'on venait.
    private var preview: some View {
        BookPreviewSheet(memoId: previewMemoId) { step = .pitch }
    }

    // MARK: - « Mon Abonnement » — déjà abonné

    private var current: some View {
        BrandSheet(
            SubscriptionCopy.currentTitle,
            badge: SubscriptionCopy.currentBadge,
            subtitle: SubscriptionCopy.currentSubtitle
        ) {
            VStack(alignment: .leading, spacing: MemoBookSpacing.m) {
                SubscriptionCallout(
                    title: SubscriptionCopy.autoCancelTitle(destination: subscription?.tripDestination),
                    message: SubscriptionCopy.autoCancelBody(endsOn: subscription?.endsOn)
                )

                VStack(spacing: MemoBookSpacing.s) {
                    // ⚠️ « Ma cagnotte » n'a pas d'écran dessiné derrière elle,
                    // pas plus ici que sur la ligne du profil qui porte le même
                    // nom — fiche écran.
                    BrandButton(SubscriptionCopy.seeWallet, style: .secondary, fillsWidth: true) {}

                    BrandButton(SubscriptionCopy.cancelSubscription, style: .destructive, fillsWidth: true) {
                        step = .keepGoing
                    }
                }
            }
        }
    }

    // MARK: - Résiliation 1 — « Ton voyage continue »

    private var keepGoing: some View {
        BrandSheet(
            SubscriptionCopy.keepGoingTitle,
            paragraphs: SubscriptionCopy.keepGoingParagraphs(tripTitle: subscription?.tripTitle)
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
            paragraphs: SubscriptionCopy.reasonParagraphs
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
                        onCancel(reason)
                        step = .done
                    }
                }
            }
        }
    }

    // MARK: - Résiliation 3 — « C'est validé »

    private var done: some View {
        BrandSheet(SubscriptionCopy.doneTitle, paragraphs: SubscriptionCopy.doneParagraphs) {
            VStack(spacing: MemoBookSpacing.s) {
                BrandButton(SubscriptionCopy.backHome, fillsWidth: true) { dismiss() }

                BrandButton(SubscriptionCopy.subscribeAgain, style: .accent, fillsWidth: true) {
                    onActivate()
                    step = .current
                }
            }
        }
    }
}

// MARK: - Les morceaux de la première feuille

/// Les trois temps de l'abonnement, le long d'un rail qui s'éteint.
///
/// **Le rail est un fond, pas une colonne d'icônes.** Il est posé derrière la
/// pile entière : il prend donc sa hauteur exacte sans que personne ait à la
/// mesurer, et les icônes tombent d'elles-mêmes en face de leur titre.
private struct SubscriptionTimeline: View {
    /// Le rail et ses icônes grandissent avec le texte, ensemble : un rail figé
    /// derrière des lignes deux fois plus hautes ne relierait plus rien.
    @ScaledMetric(relativeTo: .body) private var railWidth: CGFloat = 20
    @ScaledMetric(relativeTo: .body) private var iconSide: CGFloat = 16

    /// Où le vert s'arrête et où le lime commence à disparaître, en fraction de
    /// la hauteur du rail. Relevés sur le nœud : le vert couvre 207,7 des 255,5
    /// du rail, et le lime s'efface à partir de 69,5 % de sa propre hauteur.
    private static let greenShare: CGFloat = 0.813
    private static let limeSolidShare: CGFloat = 0.695

    var body: some View {
        VStack(alignment: .leading, spacing: MemoBookSpacing.sectionGap) {
            ForEach(SubscriptionCopy.timeline, id: \.title) { item in
                HStack(alignment: .top, spacing: MemoBookSpacing.s) {
                    // **L'icône se centre sur la ligne du titre**, pas sur le
                    // haut du bloc. Le gabarit est une ligne de texte invisible
                    // dans la police du titre : il en donne la hauteur exacte
                    // et la suit au Dynamic Type, ce qu'une constante ne
                    // saurait pas faire.
                    Text(verbatim: "A")
                        .font(MemoBookFont.bodySemibold)
                        .hidden()
                        .frame(width: railWidth)
                        .overlay {
                            Image(brand: item.icon)
                                .resizable()
                                .renderingMode(.template)
                                .scaledToFit()
                                .frame(width: iconSide, height: iconSide)
                                .foregroundStyle(MemoBookColor.onAction)
                        }
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: MemoBookSpacing.xs) {
                        Text(item.title)
                            .font(MemoBookFont.bodySemibold)
                            .foregroundStyle(MemoBookColor.ink)
                        Text(item.detail)
                            .font(MemoBookFont.taglineRegular)
                            .foregroundStyle(MemoBookColor.inkMuted)
                    }
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityElement(children: .combine)
                }
            }
        }
        .background(alignment: .topLeading) { rail }
    }

    /// Deux capsules superposées, comme la maquette les empile — et non un seul
    /// dégradé.
    ///
    /// **Le vert a son propre bout rond.** Peint en dégradé dans une capsule
    /// unique, la frontière vert → lime était un trait horizontal net : le vert
    /// se terminait au carré. C'est une capsule à part entière, posée par-dessus
    /// le lime, qui lui rend son extrémité arrondie.
    ///
    /// Le lime, lui, est plein jusqu'aux deux tiers puis s'efface sur le crème
    /// de la feuille.
    private var rail: some View {
        Capsule()
            .fill(
                LinearGradient(
                    stops: [
                        .init(color: MemoBookColor.accent, location: 0),
                        .init(color: MemoBookColor.accent, location: Self.limeSolidShare),
                        .init(color: MemoBookColor.accent.opacity(0), location: 1),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .overlay(alignment: .top) {
                // Le `GeometryReader` pose son contenu en haut à gauche : la
                // capsule verte part donc du sommet du rail et s'arrête à sa
                // part, bout rond compris.
                GeometryReader { proxy in
                    Capsule()
                        .fill(MemoBookColor.action)
                        .frame(height: proxy.size.height * Self.greenShare)
                }
            }
            .frame(width: railWidth)
            .accessibilityHidden(true)
    }
}

/// « Comment résilier ? » — la promesse, sur l'aplat bleu de la marque.
private struct HowToCancelCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: MemoBookSpacing.xs) {
            Text(SubscriptionCopy.howToCancelTitle)
                .font(MemoBookFont.cardTitle)
                .foregroundStyle(MemoBookColor.ink)

            ForEach(SubscriptionCopy.howToCancelParagraphs, id: \.self) { paragraph in
                Text(paragraph)
                    .font(MemoBookFont.taglineRegular)
                    .foregroundStyle(MemoBookColor.inkMuted)
            }
        }
        .multilineTextAlignment(.leading)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, MemoBookSpacing.snug)
        .padding(.vertical, MemoBookSpacing.s)
        .background(
            MemoBookColor.outline.opacity(0.5),
            in: .rect(cornerRadius: MemoBookSpacing.controlCornerRadius)
        )
        .accessibilityElement(children: .combine)
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

/// Tous les libellés des cinq feuilles, en un seul endroit.
///
/// La maquette porte neuf fautes de français et deux formes d'apostrophe ; **Hugo
/// a tranché de toutes les corriger** (D12, T66) plutôt que de les recopier
/// comme R8 le veut par défaut. C'est donc l'un des rares endroits où le code
/// s'écarte volontairement de Figma, et la liste des écarts vit dans la fiche
/// écran pour que Clara les reprenne à la source.
///
/// L'apostrophe est **partout typographique** (’), y compris dans les trois
/// feuilles de résiliation et les quatre raisons, où Figma emploie la droite.
enum SubscriptionCopy {
    struct TimelineItem {
        let icon: String
        let title: String
        let detail: String
    }

    // — Feuille 1 : « Comment ça fonctionne ? »

    static let pitchTitle = "Comment ça fonctionne ?"

    static let timeline: [TimelineItem] = [
        TimelineItem(
            icon: "IconPlus",
            title: "Création du voyage",
            detail: "Configure ton voyage et attends le jour du départ pour commencer"
        ),
        TimelineItem(
            icon: "IconBubble",
            title: "Raconte tes 3 premières étapes",
            detail:
                "Une étape c’est une journée, une semaine, un lot d’ajouts à ton voyage (vocaux + photos)"
        ),
        TimelineItem(
            icon: "IconLockerOutlined",
            title: "Tu atteins la limite gratuite",
            detail:
                "Préparer ton carnet demande de l’énergie, l’abonnement fait donc vivre notre application"
        ),
    ]

    /// Le prix est **écrit une seule fois**, et il vient de l'abonnement. La
    /// maquette le colle au symbole (« 1,99€/semaine ») ; on passe par le
    /// formateur du système comme partout ailleurs — même écart qu'à la ligne
    /// « Ma cagnotte », signalé (T20).
    static func offerHeadline(price: String) -> String {
        "Envoi illimité d’étapes et mise en page illimitée de tes souvenirs pour \(price)/semaine"
    }

    static let offerCadence = "Résiliation automatique à la fin du voyage"
    static let previewPill = "Voir un aperçu de ton carnet →"

    static let howToCancelTitle = "Comment résilier ?"
    static let howToCancelParagraphs = [
        "L’abonnement est sans engagement. Tu l’annules quand tu veux sans perdre tes créations.",
        "Surtout, il s’arrête tout seul à la fin de ton voyage !",
    ]

    static let learnMore = "En savoir plus"

    // — Feuille 2 : « Mon Abonnement »

    static let currentTitle = "Mon Abonnement"
    static let currentBadge = "Abonnée"
    static let currentSubtitle =
        "Tu as déjà souscrit à ton abonnement MemoBook, tu peux mettre en page tes récits de manière illimitée."

    /// ⚠️ **État non maquetté** : sans destination, la phrase s'arrête au
    /// voyage. Le back-end ne rattache encore aucun voyage à un abonnement —
    /// fiche écran.
    static func autoCancelTitle(destination: String?) -> String {
        guard let destination, !destination.isEmpty else {
            return "Résiliation automatique à la fin de ton voyage."
        }
        return "Résiliation automatique à la fin de ton voyage à \(destination)."
    }

    /// ⚠️ **État non maquetté** : sans date de fin, on promet la même chose sans
    /// avancer de délai — plutôt qu'un « dans 0 jour ».
    static func autoCancelBody(endsOn: Date?) -> String {
        let opening =
            "Parce que l’on sait que tu n’as pas besoin de notre application en dehors de tes voyages, ton abonnement sera résilié automatiquement"
        guard let endsOn else { return "\(opening) à la fin de ton voyage." }
        return "\(opening) \(endsOn.relativeDelay)."
    }

    static let seeWallet = "Voir ma cagnotte"
    static let cancelSubscription = "Résilier mon abonnement"

    // — Feuille 3 : « Ton voyage continue »

    static let keepGoingTitle = "Ton voyage continue"

    /// ⚠️ **État non maquetté** : sans titre de voyage, la première phrase se
    /// passe des guillemets.
    static func keepGoingParagraphs(tripTitle: String?) -> [String] {
        let opening =
            if let tripTitle, !tripTitle.isEmpty {
                "Il te reste encore quelques jours dans ton voyage “\(tripTitle)”."
            } else {
                "Il te reste encore quelques jours dans ton voyage."
            }
        return [
            opening,
            "Si tu coupes maintenant, tu ne pourras plus dicter tes derniers souvenirs.",
            "Pour rappel, ton abonnement sera résilié automatiquement à ton retour.",
        ]
    }

    static let waitForAutoCancel = "Attendre la résiliation automatique"
    static let cancel = "Résilier"

    // — Feuille 4 : « Pourquoi nous quittes-tu ? »

    static let reasonTitle = "Pourquoi nous quittes-tu ?"
    static let reasonParagraphs = [
        "Aide-nous à faire évoluer l’application.",
        "Choisis la raison principale.",
    ]
    static let stayAWhile = "Rester abonné encore quelques jours"
    static let confirmCancellation = "Confirmer ma résiliation"

    // — Feuille 5 : « C'est validé »

    static let doneTitle = "C’est validé"
    static let doneParagraphs = [
        "L’abonnement s’arrête aujourd’hui.",
        "Tu ne pourras plus dicter tes souvenirs, mais tu gardes accès à ton carnet de bord pour le relire quand tu veux.",
    ]
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
                SubscriptionSheet(subscription: subscription, onActivate: {}, onCancel: { _ in }, onLearnMore: {})
                    .environment(\.dynamicTypeSize, typeSize)
            }
    }
}

#Preview("Comment ça fonctionne ? — pas abonné") {
    SubscriptionSheetPreview(subscription: Subscription(weeklyPrice: 1.99))
}

#Preview("Mon Abonnement — abonné") {
    SubscriptionSheetPreview(subscription: TravellerProfile.fixture.subscription)
}

#Preview("Pas abonné — Dynamic Type AX3") {
    SubscriptionSheetPreview(
        subscription: Subscription(weeklyPrice: 1.99),
        typeSize: .accessibility3
    )
}

#Preview("Abonné — Dynamic Type AX3") {
    SubscriptionSheetPreview(
        subscription: TravellerProfile.fixture.subscription,
        typeSize: .accessibility3
    )
}
