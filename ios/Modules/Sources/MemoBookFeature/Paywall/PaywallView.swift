import MemoBookCore
import MemoBookDesign
import SwiftUI

/// Le paywall : des écrans qui se suivent tout seuls, comme des stories.
///
/// **Deux versions, un seul mécanisme.** Celle qu'on voit la première fois
/// compte trois écrans et explique tout ; celle qu'on revoit en revenant pour un
/// nouveau voyage en compte deux et ne réexplique rien — « Tu connais déjà bien
/// le fonctionnement, on ne t'embête pas plus... ». Le minuteur, les zones de
/// tapotis, la barre du haut et le comportement du dernier écran sont les mêmes :
/// c'est ``PaywallVariant`` qui dit lesquels, et rien d'autre ne change.
///
/// **Le temps passe tout seul, mais on peut le doubler.** La barre du haut se
/// remplit à vue d'œil et fait passer à la suite quand elle est pleine ; un
/// tapotis à droite avance, à gauche revient — c'est le geste que tout le monde
/// connaît d'Instagram, et il faut qu'il marche pour que l'attente ne soit
/// jamais subie. Le dernier écran, lui, **ne se referme pas** : c'est celui qui
/// porte l'offre, il attend qu'on décide.
///
/// **Rien ne bouge en Reduce Motion.** Les barres sont remplies d'avance, les
/// traits déjà tracés, et l'avancement se fait au doigt : une page qui se
/// dérobe toute seule est exactement ce que ce réglage demande d'éteindre.
struct PaywallView: View {
    let subscription: Subscription?

    /// Première visite, ou retour d'un ancien abonné.
    var variant: PaywallVariant = .firstTime

    /// Le carnet que la feuille « Prévisualisation » montre. `nil` — un compte
    /// sans voyage en cours — ouvre le jeu d'essai : la feuille est là pour
    /// montrer à quoi ça ressemble, et un aperçu vide ne vendrait rien.
    var previewMemoId: String?
    let onSubscribe: () -> Void

    /// « Besoin d'aide ? ». Elle **referme le paywall** avant d'ouvrir le
    /// support, et c'est l'écran qui présente celui-ci qui s'en charge : le
    /// support est un écran poussé, pas une couche de plus au-dessus d'une
    /// offre. Quelqu'un qui va chercher de l'aide devant un prix ne revient pas
    /// à la story qu'il regardait.
    var onHelp: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var page = 0
    @State private var showsPreview = false

    /// La feuille « Estimation », ouverte par la pastille de la quatrième carte
    /// de l'offre.
    @State private var showsEstimation = false

    /// La feuille « Choisis ton mode de paiement », ouverte par le bouton de
    /// l'offre — et le modèle du profil qu'elle pilote, fabriqué à l'ouverture.
    @State private var showsPayment = false
    @State private var paymentModel: ProfileModel?

    /// Où en est la barre de l'écran courant — voir ``PaywallFill``. C'est elle
    /// que le segment lit à chaque image ; le minuteur de ``runPage()`` tourne
    /// la page sur la même date de départ.
    @State private var fill: PaywallFill = .held(0)

    /// Le profil, pour la feuille de paiement — posé par `RootView`, absent en
    /// aperçu, où le jeu d'essai le remplace.
    @Environment(\.profileModelFactory) private var makeProfileModel

    private var pageCount: Int { variant.pageCount }

    /// L'opacité du M derrière le paywall.
    private static let backdropOpacity: Double = 0.1

    /// Ce que dure un écran. Assez long pour lire trois lignes de Sora 32 sans
    /// se sentir bousculé, assez court pour qu'on n'attende pas la suite.
    private static let pageDuration: Duration = .seconds(6)

    private var price: String { (subscription?.weeklyPrice ?? 0).euros }

    var body: some View {
        ZStack {
            MemoBookColor.background.ignoresSafeArea()
            // Plus discret que sur l'accueil : ici le signe passe **derrière un
            // écran entier de texte**, et à l'opacité de repos il se lisait
            // à travers les titres. ⚠️ Le cadrage reste celui du design
            // system ; la maquette du paywall, elle, tourne le M d'un quart de
            // tour — signalé (T63).
            BrandMarkBackdrop(progress: 1, opacity: Self.backdropOpacity)
                .ignoresSafeArea()

            // **Les zones de tapotis sont sous le contenu**, et non par-dessus.
            // Posées au-dessus, elles avalaient tout contrôle qui ne tombait
            // pas dans la bande basse épargnée — c'est exactement ce qui est
            // arrivé à la pastille « Voir un aperçu » : le tapotis tournait la
            // page au lieu d'ouvrir la feuille.
            //
            // Dessous, les boutons et les pastilles reçoivent le doigt les
            // premiers, et le texte des pages — qui ne fait rien du sien — le
            // laisse traverser (voir `PaywallProse`).
            tapZones

            VStack(spacing: 0) {
                header
                PaywallStoriesBar(
                    pageCount: pageCount,
                    page: page,
                    fill: fill,
                    duration: Self.pageDuration.seconds
                )
                .padding(.top, MemoBookSpacing.s)

                Group {
                    switch (variant, page) {
                    case (.firstTime, 0):
                        PaywallCongratulations { turn(+1) }
                    case (.firstTime, 1):
                        PaywallEstimate(
                            onContinue: { turn(+1) },
                            onPreview: { showsPreview = true }
                        )
                    case (.returning, 0):
                        PaywallReturning { turn(+1) }
                    default:
                        PaywallOffer(
                            price: price,
                            title: variant.offerTitle,
                            onEstimate: { showsEstimation = true },
                            onSubscribe: openPayment
                        )
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                // La transition est un fondu et non un glissé : les trois
                // écrans partagent leur décor, et faire glisser le contenu
                // par-dessus un fond immobile se lit comme un défaut.
                .transition(.opacity)
                .id(page)
                // **L'animation du changement de page vit ici, et nulle part
                // ailleurs.** Elle était portée par un `withAnimation` autour de
                // `page`, qui emportait aussi les barres du haut : à chaque
                // tour, la barre qu'on venait de finir et celle qui commençait
                // se remplissaient **ensemble** sur 0,25 s, et on ne lisait plus
                // les trois écrans comme une suite. Posée ici, elle ne concerne
                // que ce qu'elle doit concerner : le contenu.
                .animation(.smooth(duration: 0.25), value: page)
            }
            .padding(.horizontal, PaywallMetrics.margin)
            .padding(.bottom, MemoBookSpacing.l)

        }
        .background(MemoBookColor.background)
        .environment(\.colorScheme, .light)
        // **Un seul minuteur, et il est structuré.** L'identité porte la page
        // *et* l'état de la feuille : ouvrir l'aperçu annule la tâche en cours,
        // le refermer en démarre une neuve. Un `onChange` qui relançait
        // `runPage()` à la fermeture a été essayé — il faisait cohabiter deux
        // minuteurs, et les écrans défilaient deux fois plus vite.
        .task(id: PageTimer(page: page, isPaused: showsPreview)) { await runPage() }
        // La feuille se pose **par-dessus le paywall entier**, et non dans une
        // page : on doit pouvoir la refermer et retrouver l'offre exactement où
        // on l'avait laissée.
        .brandSheet(isPresented: $showsPreview) {
            BookPreviewSheet(memoId: previewMemoId)
        }
        // Les deux feuilles de l'offre, par-dessus le paywall entier elles
        // aussi : on les referme et on retrouve l'offre.
        .brandSheet(isPresented: $showsEstimation) {
            PaywallEstimationSheet(
                estimation: .example(weeklyPrice: subscription?.weeklyPrice ?? 0)
            )
        }
        .brandSheet(isPresented: $showsPayment) {
            if let paymentModel {
                PaywallPaymentSheet(model: paymentModel, price: price) {
                    // Payé : la feuille se referme, l'abonnement est posé, et
                    // c'est l'écran qui a présenté le paywall qui le referme —
                    // on revient là d'où l'on venait, l'accueil le plus souvent.
                    showsPayment = false
                    onSubscribe()
                }
            }
        }
    }

    /// Ouvre la feuille de paiement, sur un modèle du profil fabriqué par l'app
    /// — ou sur le jeu d'essai, en aperçu.
    private func openPayment() {
        if paymentModel == nil {
            paymentModel = makeProfileModel?() ?? ProfileModel()
        }
        showsPayment = true
    }

    /// Ce qui décide de relancer le minuteur : la page qu'on regarde, et le fait
    /// qu'une feuille soit ouverte par-dessus.
    ///
    /// Les deux ensemble, dans une seule identité, parce que `task(id:)` n'en
    /// accepte qu'une — et parce que c'est exactement la règle : le temps ne
    /// passe que si l'on regarde l'offre.
    private struct PageTimer: Equatable {
        let page: Int
        let isPaused: Bool
    }

    // MARK: - Chrome

    private var header: some View {
        HStack(spacing: 0) {
            // La flèche **recule d'un écran**, comme le tapotis à gauche ; elle
            // ne referme le paywall que depuis le premier (Hugo, 16/09/2026).
            // Elle refermait tout, d'où qu'on soit : depuis l'offre, on
            // retombait sur le profil au lieu de revoir l'estimation.
            Button { turn(-1) } label: {
                Image(brand: "IconArrow")
                    .resizable()
                    .renderingMode(.template)
                    .scaledToFit()
                    // La même flèche, à la même taille, que sur tous les écrans
                    // poussés — voir ``MemoBookSpacing/navigationIcon``.
                    .frame(width: MemoBookSpacing.navigationIcon, height: MemoBookSpacing.navigationIcon)
                    .foregroundStyle(MemoBookColor.action)
                    .frame(
                        width: MemoBookSpacing.minimumTapTarget,
                        height: MemoBookSpacing.minimumTapTarget
                    )
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(page == 0 ? "Fermer" : "Retour")

            Spacer(minLength: 0)

            Button {
                onHelp?()
            } label: {
                Text(PaywallCopy.help)
                    .font(MemoBookFont.h3)
                    .foregroundStyle(MemoBookColor.ink)
                    // La cible tactile déborde du texte jusqu'au seuil de R7 :
                    // « Besoin d'aide ? » à 14 pt fait 15 pt de haut, et c'est
                    // le seul recours de quelqu'un qui bute ici.
                    .frame(minHeight: MemoBookSpacing.minimumTapTarget)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .disabled(onHelp == nil)
        }
    }

    /// Deux moitiés d'écran, comme dans une story : à droite on avance, à
    /// gauche on revient. Elles ne couvrent pas le bas de l'écran, où vivent le
    /// bouton d'abonnement et les pastilles.
    private var tapZones: some View {
        HStack(spacing: 0) {
            Color.clear.contentShape(.rect).onTapGesture { turn(-1) }
            Color.clear.contentShape(.rect).onTapGesture { turn(+1) }
        }
        .padding(.bottom, PaywallMetrics.untappableFooter)
        .accessibilityHidden(true)
    }

    // MARK: - Le temps qui passe

    /// Lance le remplissage de la barre de l'écran courant, puis tourne la page.
    ///
    /// **Tout tient dans le `task(id:)`.** L'attente est structurée : changer de
    /// page annule cette tâche-ci, et SwiftUI en relance une pour la suivante.
    /// Une tâche détachée qu'on garderait pour l'annuler à la main a été
    /// essayée — elle enchaînait deux écrans d'un coup, parce que le minuteur
    /// qu'on annulait n'était déjà plus celui qui courait.
    ///
    /// **La barre et le minuteur lisent la même date de départ**, et rien
    /// d'autre : la barre calcule sa part à chaque image (``PaywallFill``), le
    /// minuteur dort le temps qui reste. Il n'y a plus d'animation de six
    /// secondes en vol à couper au changement de page — c'était elle qui,
    /// coupée trop tard, remplissait deux barres à la fois.
    private func runPage() async {
        // Une feuille est ouverte par-dessus : le temps s'arrête, et la barre
        // se **fige** là où elle en était. Une page qui tourne derrière un
        // aperçu fait retrouver un autre écran en le refermant.
        guard !showsPreview else {
            if case .running(let since) = fill {
                fill = .held(
                    PaywallFill.fraction(since: since, at: .now, duration: Self.pageDuration.seconds)
                )
            }
            return
        }

        // Le dernier écran porte l'offre : il ne s'en va pas tout seul, et sa
        // barre reste donc pleine plutôt que de se remplir dans le vide. En
        // Reduce Motion, aucune page ne tourne toute seule — on remplit la
        // barre pour dire où on en est, et c'est le doigt qui avance.
        guard page < pageCount - 1, !reduceMotion else {
            fill = .held(1)
            return
        }

        // La barre repart d'où elle s'était figée — un aperçu refermé reprend
        // le décompte, il ne le recommence pas — et de zéro partout ailleurs.
        let seconds = Self.pageDuration.seconds
        var since = Date.now
        if case .held(let value) = fill, value > 0, value < 1 {
            since = since.addingTimeInterval(-value * seconds)
        }
        fill = .running(since: since)

        let remaining = max(0, seconds - Date.now.timeIntervalSince(since))
        do { try await Task.sleep(for: .seconds(remaining)) } catch { return }
        guard !Task.isCancelled else { return }

        turn(+1)
    }

    private func turn(_ step: Int) {
        let next = page + step
        guard next >= 0, next < pageCount else {
            // Revenir en arrière depuis le premier écran, c'est sortir.
            if next < 0 { dismiss() }
            return
        }

        // **La barre qu'on quitte se finit, celle qu'on ouvre part de zéro** —
        // et c'est le segment qui s'en charge, pas une transaction posée ici :
        // chaque barre lit sa part dans l'état, et anime elle-même le saut à 1
        // (en avançant) ou à 0 (en revenant). La barre courante est posée à
        // zéro dans la même passe que la page, pour qu'aucune image ne montre
        // le nouvel écran avec l'avancement de l'ancien ; le minuteur relancé
        // par `task(id:)` la fait repartir aussitôt.
        fill = .held(0)
        page = next
    }
}

// MARK: - Les deux versions

/// Qui regarde l'offre : quelqu'un qui découvre, ou quelqu'un qui revient.
///
/// **La seconde existe parce que l'abonnement s'arrête tout seul.** Il s'éteint
/// à la fin du voyage — c'est ce que promet le troisième argument de l'offre,
/// « Parce que tu n'as pas besoin de notre application en dehors de tes
/// voyages ». Quelqu'un qui repart doit donc se réabonner, et lui rejouer les
/// trois écrans de découverte reviendrait à lui réexpliquer ce qu'il nous a déjà
/// acheté une fois.
enum PaywallVariant: Sendable, Hashable {
    /// Trois écrans : les trois étapes franchies, l'estimation, l'offre.
    case firstTime
    /// Deux écrans : le mot de retour, puis l'offre.
    case returning

    var pageCount: Int {
        switch self {
        case .firstTime: 3
        case .returning: 2
        }
    }

    /// Le titre de l'écran d'offre. Il change avec la version : la première fois
    /// il vend le carnet (« Ce carnet que tu relieras peut-être encore dans
    /// 30 ans »), au retour il rassure (« On a pas changé la recette ! »).
    var offerTitle: (lead: String, strong: String) {
        switch self {
        case .firstTime:
            (PaywallCopy.offerTitleLead, PaywallCopy.offerTitleStrong)
        case .returning:
            (PaywallCopy.returnOfferTitleLead, PaywallCopy.returnOfferTitleStrong)
        }
    }
}

// MARK: - Mesures et copie

enum PaywallMetrics {
    /// La marge de l'écran — **celle de l'app**. Le paywall s'en était donné
    /// une à lui (16, celle de sa maquette) quand le reste marchait à 24 ; la
    /// marge commune est passée à 1 rem le 14/09/2026 (T11, D2), et l'écart
    /// avec lui (T62) s'est refermé tout seul. L'alias reste parce que les
    /// pages le lisent en négatif pour déborder de la colonne.
    static let margin: CGFloat = MemoBookSpacing.screenMargin

    /// La bande basse que les zones de tapotis laissent tranquille : le bouton
    /// d'abonnement et les pastilles y vivent, et un tapotis qui tourne la page
    /// à leur place serait un piège.
    static let untappableFooter: CGFloat = 160

    /// Épaisseur d'un segment de la barre de stories.
    static let storyBarHeight: CGFloat = 4
}

enum PaywallCopy {
    static let help = "Besoin d’aide ?"
    static let cont = "Continuer"

    // — Écran 1
    static let bravoEyebrow = "Bravo !"
    static let bravoTitleLead = "Tu as enregistré tes "
    static let bravoTitleStrong = "3 premières étapes !"
    static let bravoBodyLead =
        "Tu as passé le plus dur, prendre le rythme et commencer à conserver des souvenirs précis, "
    static let bravoBodyStrong = "à vie !"

    // — Écran 2
    static let estimateEyebrow = "Selon nos calculs..."
    static let estimateTitleLead = "Ton carnet comptera environ "
    static let estimateTitleStrong = "40 pages !"
    static let estimateBody = [
        "Nous avons hâte de te montrer le résultat final !",
        "Notre outil de mise à page automatique est déjà au boulot...",
    ]
    static let previewPill = "Voir un aperçu →"
    static let estimateFootnote = [
        "Projection par rapport à tes 3 étapes d’enregistrements.",
        "—",
        "Ce nombre de pages est à titre indicatif. Il peut varier en fonction de la quantité de récit que tu enregistreras.",
    ]

    // — La version « retour », premier écran
    static let returnEyebrow = "C’est reparti ?"
    static let returnTitleLead = "Tu reviens pour un "
    static let returnTitleStrong = "nouveau voyage !"
    static let returnBody = [
        "Nous sommes ravi que tu aies apprécié MemoBook !",
        "Tu connais déjà bien le fonctionnement, on ne t’embête pas plus...",
    ]

    // — La version « retour », écran d'offre
    static let returnOfferTitleLead = "On a pas changé "
    static let returnOfferTitleStrong = "la recette !"

    // — Écran 3
    static let offerEyebrow = "Abonne toi pour continuer"
    static let offerTitleLead = "Ce carnet que tu relieras peut-être encore "
    static let offerTitleStrong = "dans 30 ans"
    static let estimationPill = "Voir une estimation →"
    static func offerFootnote(price: String) -> [String] {
        [
            "Renouvellement automatique pour \(price)/mois",
            "résilie à tout moment ou automatiquement à la fin du voyage",
        ]
    }
    /// Le bouton de l'offre ouvre la feuille de paiement, et le dit — Hugo,
    /// 15/09/2026. « Envoyer des vocaux en illimité » promettait le résultat
    /// sans nommer le geste.
    static let offerCallToAction = "Choisis ton mode de paiement"

    // — La feuille « Estimation » (`3469:14105`)
    enum Estimation {
        static let title = "Estimation"
        static func duration(weeks: Int) -> String {
            weeks == 1 ? "1 semaine de voyage" : "\(weeks) semaines de voyage"
        }
        static let bookPrice = "Prix final du carnet estimé"
        static func pages(_ count: Int) -> String { "Environ \(count) pages" }
        static let subscriptions = "Cumul de tes abonnements"
        static func subscriptionDetail(weeks: Int, weeklyPrice: String) -> String {
            "\(weeks) x \(weeklyPrice)"
        }
        static let total = "Montant final à payer lors de la commande du carnet"
        static let extraCopiesLead = "-20%"
        static let extraCopies = "pour chaque carnet supplémentaire"
        static func perCopy(_ price: String) -> String { "\(price)/carnet" }
    }

    // — La feuille de paiement, ouverte par le bouton de l'offre
    enum Payment {
        static func pay(_ price: String) -> String { "Payer \(price)" }
    }

    struct Argument {
        let icon: String
        let title: String
        let detail: String
        let pill: String?
        /// L'inclinaison de la carte, en degrés. Les quatre alternent, comme des
        /// papiers posés à la main.
        let tilt: Double
    }

    static let arguments: [Argument] = [
        Argument(
            icon: "IconPictureFrame",
            title: "Mise en page automatique",
            detail:
                "Tes audios, tes récits, tes photos sont mis en page automatiquement tout au long de ton voyage",
            pill: nil,
            tilt: -1
        ),
        Argument(
            icon: "IconPrinter",
            title: "Vite fait, bien fait !",
            detail: "Ton carnet est imprimé et livré chez toi quelques jours après ton retour !",
            pill: nil,
            tilt: 1.4
        ),
        Argument(
            icon: "IconLockerChecked",
            title: "Arrêt automatique de l’abonnement",
            detail: "Parce que tu n’as pas besoin de notre application en dehors de tes voyages",
            pill: nil,
            tilt: -1
        ),
        Argument(
            icon: "IconMoneyBag",
            title: "Tes abonnements sont déduits !",
            detail:
                "Le coût cumulé de tes semaines d’abonnement sera déduit du prix final de ton carnet",
            pill: estimationPill,
            tilt: 1
        ),
    ]
}
