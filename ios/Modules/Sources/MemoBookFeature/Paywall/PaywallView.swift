import MemoBookCore
import MemoBookDesign
import MemoBookPayments
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
/// jamais subie. **Un doigt posé arrête le temps** (Hugo, 02/10/2026) : sur les
/// écrans qui tournent tout seuls, la barre se fige, la page ne tourne plus, et
/// tout repart quand il se lève — voir ``PaywallStoryTouch``. Le dernier écran,
/// lui, **ne se referme pas** : c'est celui qui porte l'offre, il attend qu'on
/// décide.
///
/// **Rien ne bouge en Reduce Motion.** Les barres sont remplies d'avance, les
/// traits déjà tracés, et l'avancement se fait au doigt : une page qui se
/// dérobe toute seule est exactement ce que ce réglage demande d'éteindre.
///
/// **« Besoin d'aide ? » ouvre le support par-dessus l'offre**, et le paywall
/// reste monté derrière avec sa page (Hugo, 16/09/2026). C'était l'inverse : il
/// se refermait, le support était poussé par l'écran d'en dessous, et la flèche
/// de retour ramenait donc au profil ou à l'accueil — jamais à l'étape qu'on
/// regardait. Or on va chercher de l'aide **pour revenir décider**, et perdre sa
/// place au milieu d'un tunnel d'achat est exactement ce qu'il ne faut pas
/// faire. Le minuteur s'arrête pendant ce temps-là, comme devant l'aperçu.
struct PaywallView: View {
    let subscription: Subscription?

    /// Première visite, ou retour d'un ancien abonné.
    var variant: PaywallVariant = .firstTime

    /// Le carnet que la feuille « Prévisualisation » montre. `nil` — un compte
    /// sans voyage en cours — ouvre le jeu d'essai : la feuille est là pour
    /// montrer à quoi ça ressemble, et un aperçu vide ne vendrait rien.
    var previewMemoId: String?
    let onSubscribe: () -> Void


    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var page = 0
    @State private var showsPreview = false

    /// La feuille « Estimation », ouverte par la pastille de la carte « Tes
    /// abonnements sont déduits ! » — en pause, voir
    /// ``PaywallCopy/deductedSubscriptions``.
    @State private var showsEstimation = false

    /// L'estimation du carnet qu'on finance, lue sur la cagnotte dès que
    /// l'offre s'ouvre — sur les chiffres de la maquette tant qu'elle n'est
    /// pas là (T127). Voir ``SwiftUI/EnvironmentValues/walletSource``.
    @State private var estimation: PaywallEstimation?
    @Environment(\.walletSource) private var walletSource

    /// **L'achat passe par Apple, et par Apple seul** (01/10/2026). Le bouton
    /// de l'offre ouvrait une feuille de cartes et d'Apple Pay — un paiement
    /// hors achat intégré pour un service numérique, ce qu'App Review rejette
    /// (règle 3.1.1). C'est désormais la feuille d'Apple qui s'ouvre, et le
    /// serveur qui ouvre l'abonnement — voir ``SubscriptionPurchase``.
    @Environment(\.subscriptionPurchase) private var subscriptionPurchase

    /// La feuille d'Apple est ouverte, ou le serveur n'a pas encore répondu :
    /// le bouton attend, et un second tapotis ne lance pas un second achat.
    @State private var isPurchasing = false

    /// « Restaurer mes achats » attend l'App Store — qui peut demander le mot
    /// de passe de l'identifiant Apple.
    @State private var isRestoring = false

    /// Ce qu'il faut dire quand l'achat n'a pas ouvert l'abonnement — refusé,
    /// en attente d'un parent, rien à restaurer.
    @State private var purchaseNotice: PurchaseNotice?

    /// Le prix tel qu'Apple le facture dans le pays du compte. **C'est lui qui
    /// s'affiche dès qu'il est là** : App Store Connect a le dernier mot sur le
    /// montant, et l'écran ne doit pas annoncer autre chose que ce que la
    /// feuille d'Apple demandera.
    @State private var applePrice: String?

    /// Les conditions ou la politique de confidentialité, ouvertes depuis le
    /// pied de l'offre — exigées à côté du bouton d'un abonnement (règle 3.1.2).
    @State private var legalDocument: LegalRoute?

    /// Le support, ouvert **par-dessus** le paywall par « Besoin d'aide ? ».
    @State private var showsHelp = false

    /// Le support de la session — voir
    /// ``SwiftUI/EnvironmentValues/supportModel``.
    @Environment(\.supportModel) private var sessionSupport

    /// Celui qu'un aperçu fabrique faute de session.
    @State private var previewSupport: SupportModel?

    /// Où en est la barre de l'écran courant — voir ``PaywallFill``. C'est elle
    /// que le segment lit à chaque image ; le minuteur de ``runPage()`` tourne
    /// la page sur la même date de départ.
    @State private var fill: PaywallFill = .held(0)

    /// Un doigt est posé sur la page — voir ``PaywallStoryTouch``.
    @State private var isHeld = false

    /// Le temps ne passe que si l'on regarde l'écran : rien par-dessus, et pas
    /// de doigt qui le tient.
    private var isPaused: Bool { showsPreview || showsHelp || isHeld }

    private var pageCount: Int { variant.pageCount }

    /// L'opacité du M derrière le paywall.
    private static let backdropOpacity: Double = 0.1

    /// Ce que dure un écran. Assez long pour lire trois lignes de Sora 32 sans
    /// se sentir bousculé, assez court pour qu'on n'attende pas la suite.
    private static let pageDuration: Duration = .seconds(6)

    private var price: String { applePrice ?? subscription.displayedWeeklyPrice.euros }

    var body: some View {
        ZStack {
            MemoBookColor.background.ignoresSafeArea()
            // Plus discret que sur l'accueil : ici le signe passe **derrière un
            // écran entier de texte**, et à l'opacité de repos il se lisait
            // à travers les titres. Le cadrage est celui du design system,
            // **le même partout** — la maquette du paywall tournait le M d'un
            // quart de tour, et Hugo a tranché pour un seul cadrage (T63,
            // 17/09/2026).
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
                            isPurchasing: isPurchasing,
                            isRestoring: isRestoring,
                            onSubscribe: purchase,
                            onRestore: restore,
                            onShowLegal: { legalDocument = $0 },
                            onBack: { turn(-1) }
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
        .task(id: PageTimer(page: page, isPaused: isPaused)) { await runPage() }
        // **Le support, par-dessus l'offre.** Un `fullScreenCover` et non une
        // feuille : c'est un écran, avec son en-tête et sa flèche — et cette
        // flèche, qui appelle `dismiss()`, ramène donc à l'étape du paywall
        // qu'on regardait, sans qu'il y ait une ligne à écrire pour ça.
        .fullScreenCover(isPresented: $showsHelp) {
            if let support = sessionSupport ?? previewSupport {
                NavigationStack {
                    SupportView(model: support)
                }
                .tint(MemoBookColor.action)
            }
        }
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
                estimation: estimation ?? .example(weeklyPrice: subscription.displayedWeeklyPrice)
            )
        }
        .task(id: previewMemoId) {
            guard let walletSource, let wallet = try? await walletSource(previewMemoId) else { return }
            estimation = PaywallEstimation(wallet: wallet, weeklyPrice: subscription.displayedWeeklyPrice)
        }
        .task { applePrice = await subscriptionPurchase?.displayPrice() }
        // Un écran, comme le support : son en-tête porte la flèche qui ramène
        // à l'offre.
        .fullScreenCover(item: $legalDocument) { route in
            NavigationStack {
                LegalDocumentView(document: route.content, showsHelp: false)
            }
            .tint(MemoBookColor.action)
        }
        .alert(
            purchaseNotice?.title ?? "",
            isPresented: Binding(
                get: { purchaseNotice != nil },
                set: { if !$0 { purchaseNotice = nil } }
            ),
            presenting: purchaseNotice
        ) { _ in
            Button(PaywallCopy.Purchase.ok, role: .cancel) {}
        } message: { notice in
            Text(notice.message)
        }
    }

    /// Achète l'abonnement. **Payé, c'est l'écran qui a présenté le paywall qui
    /// le referme** : on revient là d'où l'on venait, l'accueil le plus souvent.
    ///
    /// Sans achat possible — un aperçu isolé, sans compte —, l'offre fait comme
    /// si c'était fait : c'est ce qu'elle faisait avant StoreKit, et un aperçu
    /// n'a rien à encaisser.
    private func purchase() {
        guard !isPurchasing, !isRestoring else { return }
        guard let subscriptionPurchase else {
            onSubscribe()
            return
        }

        isPurchasing = true
        Task {
            let outcome = await subscriptionPurchase.purchase(previewMemoId)
            isPurchasing = false

            switch outcome {
            case .subscribed, .awaitingServer:
                onSubscribe()
            case .pending:
                purchaseNotice = .pending
            case .cancelled:
                break
            case .failed(let message):
                purchaseNotice = .failed(message)
            }
        }
    }

    /// « Restaurer mes achats » : un abonnement pris sur un autre iPhone, ou
    /// avant une réinstallation, se retrouve ici.
    ///
    /// **Ce que demande Apple** : un geste explicite, qui resynchronise avec
    /// l'App Store (`AppStore.sync()`, qui peut demander le mot de passe), puis
    /// rend l'accès à ce qui est encore payé. Retrouvé : l'abonnement s'ouvre et
    /// l'offre se referme, comme après un achat. Rien de payé : on le dit. La
    /// personne referme la demande de mot de passe : on ne dit rien, c'est un
    /// choix. Un abonnement payé depuis un autre compte MemoBook : le message
    /// du serveur le dit.
    private func restore() {
        guard !isPurchasing, !isRestoring else { return }
        guard let subscriptionPurchase else {
            // Un aperçu isolé n'a pas d'App Store à interroger.
            purchaseNotice = .nothingToRestore
            return
        }

        isRestoring = true
        Task {
            defer { isRestoring = false }
            do {
                switch try await subscriptionPurchase.restore() {
                case .restored: onSubscribe()
                case .nothingToRestore: purchaseNotice = .nothingToRestore
                case .cancelled: break
                }
            } catch {
                purchaseNotice = .failed(error.localizedDescription)
            }
        }
    }

    /// Ce qui décide de relancer le minuteur : la page qu'on regarde, et le fait
    /// qu'une feuille soit ouverte par-dessus ou qu'un doigt la tienne.
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

            Button(action: openHelp) {
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
        }
    }

    /// Ouvre le support **sur** le paywall.
    ///
    /// Sur le modèle de la session quand il y en a un, sur un modèle neuf
    /// sinon : un aperçu doit pouvoir ouvrir l'écran, et le jeu d'essai de la
    /// foire aux questions est dans le binaire.
    private func openHelp() {
        if sessionSupport == nil, previewSupport == nil { previewSupport = SupportModel() }
        showsHelp = true
    }

    /// Deux moitiés d'écran, comme dans une story : à droite on avance, à
    /// gauche on revient. Elles ne couvrent pas le bas de l'écran, où vivent le
    /// bouton d'abonnement et les pastilles.
    ///
    /// **Un doigt posé arrête le temps partout**, bande basse comprise : elle
    /// ne tourne rien, mais un doigt qui se pose à côté du bouton pour finir sa
    /// lecture doit tenir la page comme ailleurs. Le bouton, lui, garde le
    /// doigt pour lui et avance comme avant.
    private var tapZones: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Color.clear.contentShape(.rect)
                    .paywallStoryTouch(onTap: { turn(-1) }, onHold: { isHeld = $0 })
                Color.clear.contentShape(.rect)
                    .paywallStoryTouch(onTap: { turn(+1) }, onHold: { isHeld = $0 })
            }

            Color.clear.contentShape(.rect)
                .paywallStoryTouch(onHold: { isHeld = $0 })
                .frame(height: PaywallMetrics.untappableFooter)
        }
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
        // Une feuille est ouverte par-dessus, ou un doigt tient la page : le
        // temps s'arrête, et la barre se **fige** là où elle en était. Une page
        // qui tourne derrière un aperçu fait retrouver un autre écran en le
        // refermant ; une page qui tourne sous le doigt, c'est ce qu'on
        // voulait éviter en le posant.
        //
        // Le support en fait partie : il n'était que dans l'identité de la
        // tâche, pas ici, et l'ouvrir faisait repartir la barre de zéro au lieu
        // de la figer.
        guard !isPaused else {
            if case .running(let since) = fill {
                fill = .held(
                    PaywallFill.fraction(since: since, at: .now, duration: Self.pageDuration.seconds)
                )
            }
            return
        }

        // En Reduce Motion, aucune page ne tourne toute seule — on remplit la
        // barre pour dire où on en est, et c'est le doigt qui avance.
        guard !reduceMotion else {
            fill = .held(1)
            return
        }

        // **Une barre finie ne recommence pas.** La dernière page s'arrête sur
        // une barre pleine ; ouvrir « Besoin d'aide ? » annule la tâche, et la
        // refermer en relançait une neuve qui repartait de zéro — l'écran
        // avait l'air de se recharger tout seul (Hugo, 19/09/2026).
        if case .held(let value) = fill, value >= 1 { return }

        // La barre repart d'où elle s'était figée — un aperçu refermé, un
        // doigt levé reprennent le décompte, ils ne le recommencent pas — et de
        // zéro partout ailleurs.
        let seconds = Self.pageDuration.seconds
        var since = Date.now
        if case .held(let value) = fill, value > 0, value < 1 {
            since = since.addingTimeInterval(-value * seconds)
        }
        fill = .running(since: since)

        let remaining = max(0, seconds - Date.now.timeIntervalSince(since))
        do { try await Task.sleep(for: .seconds(remaining)) } catch { return }
        guard !Task.isCancelled else { return }

        // Le dernier écran porte l'offre : il ne s'en va pas tout seul. Sa
        // barre se remplit **au même rythme que les deux autres** — elle
        // sautait à 1 d'un coup (Clara, 17/09/2026) — et reste pleine.
        guard page < pageCount - 1 else {
            fill = .held(1)
            return
        }

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
    /// il vend le carnet (« Ce carnet que tu relieras encore dans 30 ans »),
    /// au retour il rassure (« On a pas changé la recette ! »).
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

    /// Au-delà, un doigt posé ne tapote plus : il tient la page, et ne la
    /// tourne pas en se levant. Un tapotis dure un ou deux dixièmes de
    /// seconde ; un quart laisse passer les plus appuyés sans faire attendre
    /// qui veut lire. La barre, elle, se fige dès le contact.
    static let holdDelay: Double = 0.25
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
    /// **Sans « peut-être »** (01/10/2026) : le titre doit tenir sur trois
    /// lignes, et le mot l'emmenait sur une quatrième.
    static let offerTitleLead = "Ce carnet que tu relieras encore "
    static let offerTitleStrong = "dans 30 ans"
    static let estimationPill = "Voir une estimation →"
    /// ⚠️ **« /semaine » et non « /mois »** (Hugo, 17/09/2026). L’abonnement
    /// est hebdomadaire — la feuille d’abonnement l’écrit, l’estimation compte
    /// trois semaines —, et ce pied de page seul promettait un prélèvement
    /// mensuel : il annonçait donc un quart du prix réel.
    ///
    /// **La seconde ligne ne promet plus d'arrêt automatique** (01/10/2026).
    /// Apple ne laisse aucune app résilier à la place de son client : promettre
    /// « automatiquement à la fin du voyage » aurait fait payer des semaines
    /// qu'on croyait arrêtées. Elle dit ce qui est vrai — où l'on résilie, et
    /// le rappel qu'on reçoit au retour.
    static func offerFootnote(price: String) -> [String] {
        [
            "Renouvellement automatique pour \(price)/semaine",
            "résiliable à tout moment, rappel à la fin du voyage",
        ]
    }

    /// La première ligne du pied, en deux morceaux : **le prix se lit en
    /// gras** (Hugo, 19/09/2026). C'est le seul chiffre de l'écran, et il
    /// était écrit du même gris léger que la mention qui l'entoure.
    static func offerFootnotePrice(price: String) -> (lead: String, price: String) {
        ("Renouvellement automatique pour ", "\(price)/semaine")
    }
    /// Le bouton de l'offre nomme le geste — Hugo, 15/09/2026. « Choisis ton
    /// mode de paiement » ouvrait une feuille de cartes ; c'est désormais la
    /// feuille d'Apple qui s'ouvre, et l'on s'y abonne.
    static let offerCallToAction = "S’abonner"

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

    // — L'achat, par la feuille d'Apple
    enum Purchase {
        static let ok = "OK"
        static let restore = "Restaurer mes achats"
        static let terms = "Conditions d’utilisation"
        static let privacy = "Confidentialité"

        static let pendingTitle = "Achat en attente"
        static let pendingMessage =
            "Ton achat attend une validation — celle d’un parent, ou de ta banque. Ton abonnement s’ouvrira tout seul dès qu’elle arrivera."
        static let failedTitle = "Achat impossible"
        static let nothingTitle = "Rien à restaurer"
        static let nothingMessage =
            "Aucun abonnement MemoBook en cours sur cet identifiant Apple. S’il en existe un sur un autre identifiant, connecte-toi avec lui dans les réglages de l’App Store, puis réessaie."
    }

    struct Argument {
        let icon: String
        let title: String
        let detail: String
        let pill: String?
        /// L'inclinaison de la carte, en degrés. Elles alternent, comme des
        /// papiers posés à la main.
        let tilt: Double
    }

    /// Les cartes de l'offre, de haut en bas. **Trois depuis le 02/10/2026** :
    /// la quatrième, ``deductedSubscriptions``, est en pause.
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
            // **Pleine**, comme les trois autres (Hugo, 19/09/2026) : le tracé
            // au trait se lisait plus léger que le cadre photo, le cadenas et
            // le sac, et la pile de cartes perdait son unité.
            icon: "IconPrinterFilled",
            title: "Vite fait, bien fait !",
            detail: "Ton carnet est imprimé et livré chez toi quelques jours après ton retour !",
            pill: nil,
            tilt: 1.4
        ),
        Argument(
            icon: "IconLockerChecked",
            // **Un rappel, pas un arrêt** (01/10/2026) : Apple seul résilie,
            // à la demande de la personne. L'accueil le propose en un geste
            // dès que plus aucun voyage ne court.
            title: "On te rappelle de résilier",
            detail:
                "À la fin de ton voyage, tu coupes l’abonnement en un geste : pas besoin de nous entre deux voyages",
            pill: nil,
            tilt: -1
        ),
    ]

    /// « Tes abonnements sont déduits ! » — **en pause** (Hugo, 02/10/2026).
    ///
    /// Rien ne crédite encore la cagnotte des semaines payées chez Apple : la
    /// carte promettait une déduction que la commande ne fait pas. Elle sort de
    /// l'offre, et la feuille « Estimation » que sa pastille ouvrait n'a plus
    /// d'entrée. Les deux restent écrites et branchées : pour les rallumer,
    /// remettre cette carte au bout d'``arguments``.
    static let deductedSubscriptions = Argument(
        icon: "IconMoneyBag",
        title: "Tes abonnements sont déduits !",
        detail:
            "Le coût cumulé de tes semaines d’abonnement sera déduit du prix final de ton carnet",
        pill: estimationPill,
        tilt: 1
    )
}

/// Ce que l'offre dit quand l'achat n'a pas ouvert l'abonnement.
enum PurchaseNotice: Hashable {
    case pending
    case failed(String)
    case nothingToRestore

    var title: String {
        switch self {
        case .pending: PaywallCopy.Purchase.pendingTitle
        case .failed: PaywallCopy.Purchase.failedTitle
        case .nothingToRestore: PaywallCopy.Purchase.nothingTitle
        }
    }

    var message: String {
        switch self {
        case .pending: PaywallCopy.Purchase.pendingMessage
        case .failed(let message): message
        case .nothingToRestore: PaywallCopy.Purchase.nothingMessage
        }
    }
}

extension LegalRoute: Identifiable {
    var id: Self { self }
}
