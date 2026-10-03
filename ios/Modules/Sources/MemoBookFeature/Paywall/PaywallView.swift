import MemoBookCore
import MemoBookDesign
import MemoBookPayments
import SwiftUI

/// Le paywall : des écrans qui se suivent tout seuls, comme des stories.
///
/// **Il vend l'illimité, pas le droit de raconter** (Hugo, 03/10/2026). Tout le
/// monde raconte cinq minutes par jour et par voyage ; l'abonnement, 4,99 € par
/// mois, rend le récit illimité pour l'abonné. Le paywall s'ouvre donc sur une
/// envie — « Tu as tant de choses à raconter ! » —, jamais sur un mur : on peut
/// le refermer et continuer demain.
///
/// **Deux versions, un seul mécanisme.** Celle qu'on voit la première fois
/// compte trois écrans et explique tout ; celle qu'on revoit quand on a déjà été
/// abonné en compte deux et ne réexplique rien — « Tu connais déjà le principe,
/// on ne t'embête pas plus... ». Le minuteur, les zones de tapotis, la barre du
/// haut et le comportement du dernier écran sont les mêmes : c'est
/// ``PaywallVariant`` qui dit lesquels, et rien d'autre ne change. Qui l'ouvre la
/// lit sur ``SubscriptionSession/paywallVariant``.
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
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled
    @Environment(\.accessibilitySwitchControlEnabled) private var switchControlEnabled

    @State private var page = 0
    @State private var showsPreview = false

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

    /// La période que ce prix paie, lue sur le même produit — « mois ». Elle
    /// vient avec le prix pour la même raison : l'écran ne doit pas annoncer
    /// une autre durée que celle que la feuille d'Apple facturera.
    @State private var applePeriod: String?

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

    /// Les zones où un doigt est posé — voir ``PaywallStoryTouch``. Un
    /// ensemble et non un booléen : un pouce posé sur la bande basse et un
    /// tapotis sur une moitié, le tapotis levé ne doit pas relancer le temps
    /// sous le pouce.
    @State private var heldZones: Set<HoldZone> = []
    private var isHeld: Bool { !heldZones.isEmpty }

    /// Le temps ne passe que si l'on regarde l'écran : rien par-dessus, et pas
    /// de doigt qui le tient.
    private var isPaused: Bool { showsPreview || showsHelp || isHeld }

    private var pageCount: Int { variant.pageCount }

    /// L'opacité du M derrière le paywall.
    private static let backdropOpacity: Double = 0.1

    /// Ce que dure un écran. Assez long pour lire trois lignes de Sora 32 sans
    /// se sentir bousculé, assez court pour qu'on n'attende pas la suite.
    private static let pageDuration: Duration = .seconds(6)

    /// Le prix de l'offre — celui d'Apple dès qu'il est là, sinon celui du
    /// serveur s'il est mensuel, sinon 4,99 € (``Subscription/offer``).
    private var price: String { applePrice ?? subscription.offeredPrice.euros }

    /// Sa période — celle du produit, sinon le mois de l'offre.
    private var period: String { applePeriod ?? Subscription.offer.periodLabel }

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
                        PaywallStoriesToTell { turn(+1) }
                    case (.firstTime, 1):
                        PaywallFadingDetails(
                            onContinue: { turn(+1) },
                            onPreview: { showsPreview = true }
                        )
                    case (.returning, 0):
                        PaywallReturning { turn(+1) }
                    default:
                        PaywallOffer(
                            price: price,
                            period: period,
                            title: variant.offerTitle,
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
        .task {
            applePrice = await subscriptionPurchase?.displayPrice()
            applePeriod = await subscriptionPurchase?.displayPeriod()
        }
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
            // retombait sur le profil au lieu de revoir l'écran d'avant.
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
                    .paywallStoryTouch(onTap: { turn(-1) }, onHold: { hold(.back, $0) })
                Color.clear.contentShape(.rect)
                    .paywallStoryTouch(onTap: { turn(+1) }, onHold: { hold(.forward, $0) })
            }

            Color.clear.contentShape(.rect)
                .paywallStoryTouch(onHold: { hold(.footer, $0) })
                .frame(height: PaywallMetrics.untappableFooter)
        }
        .accessibilityHidden(true)
    }

    /// Les trois zones qui tiennent la page sous le doigt.
    private enum HoldZone { case back, forward, footer }

    private func hold(_ zone: HoldZone, _ isDown: Bool) {
        if isDown { heldZones.insert(zone) } else { heldZones.remove(zone) }
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
        // barre pour dire où on en est, et c'est le doigt qui avance. Pareil
        // sous VoiceOver ou Switch Control : on ne peut pas y poser le doigt
        // pour tenir la page (les zones sont cachées à l'accessibilité), et
        // une page qui tourne pendant la lecture coupe la phrase. « Continuer »
        // et la flèche avancent comme avant.
        guard !reduceMotion, !voiceOverEnabled, !switchControlEnabled else {
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
/// **La seconde existe parce qu'on propose de résilier à la fin de chaque
/// voyage.** Quelqu'un qui repart et retrouve l'envie de raconter sans compter
/// se réabonne ; lui rejouer les trois écrans de découverte reviendrait à lui
/// réexpliquer ce qu'il nous a déjà acheté une fois.
///
/// Elle se décide **partout** — profil, conversation, réglages du voyage,
/// accueil — sur ``SubscriptionSession/paywallVariant``, qui la lit sur
/// `hasSubscribedBefore` (accueil) et `hasEndedBefore` (profil) (Hugo,
/// 03/10/2026). Seul le profil la connaissait, et « Me réabonner » sur
/// l'accueil rejouait la découverte à un ancien abonné.
enum PaywallVariant: Sendable, Hashable {
    /// Trois écrans : l'envie de raconter, les détails qui s'effacent, l'offre.
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
    /// au retour il dit ce qu'on retrouve (« Raconte de nouveau sans compter »).
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

/// Toute la copie du paywall, **au caractère près** (Hugo, 03/10/2026 — textes
/// décidés avec le crédit du jour : on vend l'illimité, on ne bloque personne).
enum PaywallCopy {
    static let help = "Besoin d’aide ?"
    static let cont = "Continuer"

    // — Écran 1 : l'envie de raconter
    static let storiesEyebrow = "On adore t’écouter !"
    static let storiesTitleLead = "Tu as tant de "
    static let storiesTitleStrong = "choses à raconter !"
    static let storiesBodyLead =
        "Et c’est exactement ce qu’on espérait. Un voyage ne tient pas en 5 minutes par jour : chaque détail que tu racontes, c’est une page de plus "
    static let storiesBodyStrong = "dans ton carnet."

    // — Écran 2 : les détails qui s'effacent
    static let detailsEyebrow = "Raconte tout, tout de suite"
    static let detailsTitleLead = "Les détails s’effacent "
    static let detailsTitleStrong = "en quelques jours"
    static let detailsBody = [
        "Le nom de ce petit resto, la phrase du guide qui vous a fait rire, l’odeur du marché le matin...",
        "En illimité, tu racontes tout au moment où tu le vis, sans regarder le chrono.",
    ]
    static let previewPill = "Voir un aperçu →"
    /// Les deux formules, côte à côte : ce qui reste gratuit, et ce que
    /// l'abonnement ouvre. Le chiffre est celui du serveur
    /// (`DAILY_CREDIT_LIMIT_MS`) ; s'il bougeait, ce texte bougerait avec.
    static let detailsFootnote = [
        "Gratuit : 5 minutes par jour et par voyage, à l’oral comme à l’écrit.",
        "—",
        "Illimité : raconte autant que tu veux, aussi longtemps que ton voyage dure.",
    ]

    // — La version « retour », premier écran
    static let returnEyebrow = "C’est reparti ?"
    static let returnTitleLead = "Tu as encore "
    static let returnTitleStrong = "plein de choses à raconter !"
    static let returnBody = [
        "Ravis de te retrouver !",
        "Tu connais déjà le principe, on ne t’embête pas plus...",
    ]

    // — La version « retour », écran d'offre
    static let returnOfferTitleLead = "Raconte de nouveau "
    static let returnOfferTitleStrong = "sans compter"

    // — Écran 3 : l'offre
    static let offerEyebrow = "Passe en illimité"
    /// **Sans « peut-être »** (01/10/2026) : le titre doit tenir sur trois
    /// lignes, et le mot l'emmenait sur une quatrième.
    static let offerTitleLead = "Ce carnet que tu relieras encore "
    static let offerTitleStrong = "dans 30 ans"

    /// Le pied de l'offre, en deux lignes : la première en deux morceaux,
    /// parce que **le prix se lit en gras** (Hugo, 19/09/2026) — c'est le seul
    /// chiffre de l'écran.
    ///
    /// **La période vient du produit** (03/10/2026) : « /mois » se lit sur
    /// l'App Store (`subscriptionPeriod`), et le mois de l'offre n'est que le
    /// repli. L'abonnement a été hebdomadaire ; un pied écrit à la main a déjà
    /// annoncé une autre durée que la feuille d'Apple (17/09/2026).
    ///
    /// **La seconde ligne ne promet pas d'arrêt automatique** (01/10/2026).
    /// Apple ne laisse aucune app résilier à la place de son client : elle dit
    /// ce qui est vrai — on résilie quand on veut, et on reçoit un rappel au
    /// retour.
    ///
    /// **« 4,99 €/mois » ne se coupe pas** (recette du 03/10/2026) : la barre
    /// oblique laisse passer à la ligne après elle, et l'espace du prix aussi
    /// quand StoreKit ou le repli en mettent une ordinaire. On lisait
    /// « 4,99 €/ » puis « mois » sur la ligne suivante. Espaces insécables, et
    /// un gluon de mot (U+2060) de part et d'autre de la barre.
    static func offerFootnotePrice(price: String, period: String) -> (lead: String, price: String) {
        let glued = "\(price)\u{2060}/\u{2060}\(period)"
            .replacingOccurrences(of: " ", with: "\u{00A0}")
        return ("Renouvellement automatique pour ", glued)
    }

    static let offerFootnoteDetail = "résiliable à tout moment, rappel à la fin du voyage"

    /// Le bouton de l'offre nomme le geste — Hugo, 15/09/2026. « Choisis ton
    /// mode de paiement » ouvrait une feuille de cartes ; c'est désormais la
    /// feuille d'Apple qui s'ouvre, et l'on s'y abonne.
    static let offerCallToAction = "S’abonner"

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
        /// L'inclinaison de la carte, en degrés. Elles alternent, comme des
        /// papiers posés à la main.
        let tilt: Double
    }

    /// Les trois cartes de l'offre, de haut en bas (Hugo, 03/10/2026). La
    /// quatrième, « Tes abonnements sont déduits ! », est partie avec la
    /// déduction elle-même et la feuille « Estimation » qu'elle ouvrait.
    static let arguments: [Argument] = [
        Argument(
            icon: "IconPictureFrame",
            title: "Vocaux et textes illimités",
            detail:
                "Raconte autant que tu veux : tout est mis en page automatiquement, tout au long de ton voyage",
            tilt: -1
        ),
        Argument(
            // **Pleine**, comme les deux autres (Hugo, 19/09/2026) : le tracé
            // au trait se lisait plus léger que le cadre photo et le cadenas,
            // et la pile de cartes perdait son unité.
            icon: "IconPrinterFilled",
            title: "Vite fait, bien fait !",
            detail: "Ton carnet est imprimé et livré chez toi quelques jours après ton retour !",
            tilt: 1.4
        ),
        Argument(
            icon: "IconLockerChecked",
            // **Un rappel, pas un arrêt** (01/10/2026) : Apple seul résilie,
            // à la demande de la personne. L'accueil le propose en un geste
            // dès que plus aucun voyage ne court — et l'illimité reste ouvert
            // jusqu'au bout du mois payé.
            title: "On te rappelle de résilier",
            detail:
                "À la fin de ton voyage, tu coupes l’abonnement en un geste, et l’illimité reste ouvert jusqu’au bout du mois payé",
            tilt: -1
        ),
    ]
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
