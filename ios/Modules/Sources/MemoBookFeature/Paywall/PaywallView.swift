import MemoBookCore
import MemoBookDesign
import SwiftUI

/// Le paywall : trois écrans qui se suivent tout seuls, comme des stories.
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
    /// Le carnet que la feuille « Prévisualisation » montre. `nil` — un compte
    /// sans voyage en cours — ouvre le jeu d'essai : la feuille est là pour
    /// montrer à quoi ça ressemble, et un aperçu vide ne vendrait rien.
    var previewMemoId: String?
    let onSubscribe: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var page = 0
    @State private var showsPreview = false
    /// Part de l'écran courant déjà écoulée, de 0 à 1. C'est **elle** qui remplit
    /// la barre, et c'est son arrivée à 1 qui tourne la page.
    @State private var progress: Double = 0
    private static let pageCount = 3

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
                PaywallStoriesBar(pageCount: Self.pageCount, page: page, progress: progress)
                    .padding(.top, MemoBookSpacing.s)

                Group {
                    switch page {
                    case 0: PaywallCongratulations { turn(+1) }
                    case 1:
                        PaywallEstimate(
                            onContinue: { turn(+1) },
                            onPreview: { showsPreview = true }
                        )
                    default: PaywallOffer(price: price, onSubscribe: onSubscribe)
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
            Button { dismiss() } label: {
                Image(brand: "IconArrow")
                    .resizable()
                    .renderingMode(.template)
                    .scaledToFit()
                    .frame(width: MemoBookSpacing.m, height: MemoBookSpacing.m)
                    .foregroundStyle(MemoBookColor.action)
                    .frame(
                        width: MemoBookSpacing.minimumTapTarget,
                        height: MemoBookSpacing.minimumTapTarget
                    )
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Fermer")

            Spacer(minLength: 0)

            // ⚠️ Aucune destination n'est dessinée derrière « Besoin d'aide ? ».
            Text(PaywallCopy.help)
                .font(MemoBookFont.h3)
                .foregroundStyle(MemoBookColor.ink)
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

    /// Remplit la barre de l'écran courant, puis tourne la page.
    ///
    /// **Tout tient dans le `task(id:)`.** L'attente est structurée : changer de
    /// page annule cette tâche-ci, et SwiftUI en relance une pour la suivante.
    /// Une tâche détachée qu'on garderait pour l'annuler à la main a été
    /// essayée — elle enchaînait deux écrans d'un coup, parce que le minuteur
    /// qu'on annulait n'était déjà plus celui qui courait.
    private func runPage() async {
        // Une feuille est ouverte par-dessus : le temps s'arrête, et la barre
        // reste où elle en était. Une page qui tourne derrière un aperçu fait
        // retrouver un autre écran en le refermant.
        guard !showsPreview else { return }

        // Le dernier écran porte l'offre : il ne s'en va pas tout seul, et sa
        // barre reste donc pleine plutôt que de se remplir dans le vide. En
        // Reduce Motion, aucune page ne tourne toute seule — on remplit la
        // barre pour dire où on en est, et c'est le doigt qui avance.
        guard page < Self.pageCount - 1, !reduceMotion else {
            progress = 1
            return
        }

        // **Deux temps, et deux images.** Remettre la barre à zéro puis lancer
        // son remplissage dans la même passe ne donne qu'une seule écriture à
        // SwiftUI : il interpole alors depuis la valeur déjà à l'écran — 1,
        // laissée par l'écran précédent — vers 1, c'est-à-dire rien. La barre
        // se posait pleine d'un coup au lieu de se remplir.
        //
        // La remise à zéro est donc explicitement **sans animation**, et on
        // rend la main le temps d'une image avant de lancer le remplissage.
        var reset = Transaction()
        reset.disablesAnimations = true
        withTransaction(reset) { progress = 0 }

        await Task.yield()
        guard !Task.isCancelled else { return }

        withAnimation(.linear(duration: Self.pageDuration.seconds)) { progress = 1 }

        do { try await Task.sleep(for: Self.pageDuration) } catch { return }
        guard !Task.isCancelled else { return }

        turn(+1)
    }

    private func turn(_ step: Int) {
        let next = page + step
        guard next >= 0, next < Self.pageCount else {
            // Revenir en arrière depuis le premier écran, c'est sortir.
            if next < 0 { dismiss() }
            return
        }

        // **Le remplissage en cours est coupé net, et la page change avec.**
        //
        // Les deux dans la *même* transaction, et cette transaction sans
        // animation : c'est ce qui manquait. Le remplissage est une animation
        // linéaire de six secondes posée sur `progress` ; appuyer sur
        // « Continuer » au bout de deux la laissait courir. La barre qu'on
        // ouvrait héritait alors des quatre secondes restantes et se remplissait
        // **en même temps** que celle qu'on venait de quitter finissait la
        // sienne — exactement les deux traits qui avancent ensemble.
        //
        // Remettre `progress` à zéro sans animation remplace l'animation en vol
        // au lieu de l'attendre ; la faire dans la même passe que `page` évite
        // l'image intermédiaire où la nouvelle barre montrerait l'avancement de
        // l'ancienne.
        var immediate = Transaction()
        immediate.disablesAnimations = true
        withTransaction(immediate) {
            progress = 0
            page = next
        }
    }
}

// MARK: - Mesures et copie

enum PaywallMetrics {
    /// ⚠️ La maquette du paywall marge à 16, là où le reste de l'app marge à
    /// `screenMargin` (24) — voir T11 et T62. Suivi tel quel (R3).
    static let margin: CGFloat = MemoBookSpacing.s

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
    static let offerCallToAction = "Envoyer des vocaux en illimité"

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
