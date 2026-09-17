import MemoBookDesign
import SwiftUI

// Les trois écrans du paywall, et la barre qui les compte.

/// Où en est la barre de l'écran courant.
///
/// **Une date de départ, pas une animation.** La barre se remplissait par un
/// `withAnimation(.linear(6 s))` posé sur un `progress` : une animation de six
/// secondes en vol, qu'un changement de page devait couper — et qui, sur
/// l'iPhone de Hugo, survivait et remplissait deux segments à la fois
/// (15/09/2026), malgré la transaction sans animation qui devait la remplacer.
/// Ici rien n'est en vol : à chaque image, le segment lit l'heure et calcule sa
/// part. Tourner la page ne coupe rien, il n'y a rien à couper.
enum PaywallFill: Equatable {
    /// Elle se remplit depuis cette date, sur la durée d'un écran.
    case running(since: Date)
    /// Elle est arrêtée à cette valeur — pleine sur le dernier écran, figée
    /// pendant qu'une feuille est ouverte, à zéro l'instant d'un changement de
    /// page.
    case held(Double)

    var isRunning: Bool {
        if case .running = self { true } else { false }
    }

    /// La part remplie, de 0 à 1, à cet instant.
    func value(at date: Date, duration: TimeInterval) -> Double {
        switch self {
        case .running(let since): Self.fraction(since: since, at: date, duration: duration)
        case .held(let value): value
        }
    }

    static func fraction(since: Date, at date: Date, duration: TimeInterval) -> Double {
        guard duration > 0 else { return 1 }
        return min(1, max(0, date.timeIntervalSince(since) / duration))
    }
}

/// La barre de stories : un segment par écran, celui du moment se remplit.
struct PaywallStoriesBar: View {
    let pageCount: Int
    let page: Int
    let fill: PaywallFill
    /// Ce que dure un écran — la même valeur que le minuteur qui tourne la page.
    let duration: TimeInterval

    var body: some View {
        // La barre se redessine à chaque image **tant qu'elle se remplit**, et
        // plus du tout ensuite : figée ou pleine, elle ne coûte rien.
        TimelineView(.animation(minimumInterval: 1 / 30, paused: !fill.isRunning)) { context in
            HStack(spacing: MemoBookSpacing.xs) {
                ForEach(0..<pageCount, id: \.self) { index in
                    PaywallStorySegment(share: share(of: index, at: context.date))
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Écran \(page + 1) sur \(pageCount)")
    }

    /// Un écran déjà passé est plein, celui du moment se remplit, les suivants
    /// sont vides.
    private func share(of index: Int, at date: Date) -> Double {
        if index < page { return 1 }
        if index > page { return 0 }
        return fill.value(at: date, duration: duration)
    }
}

/// Un segment de la barre.
///
/// **Rien ne s'anime ici.** Le remplissage continu est piloté image par image
/// par la barre, et les sauts — la barre qu'on quitte passe à 1, celle qu'on
/// rouvre retombe à 0 — sont **instantanés** (Clara, 17/09/2026) : le tiers de
/// seconde qui les lissait se lisait encore comme la barre d'avant qui se
/// remplit, et deux barres qui bougent ensemble ne se lisent plus comme une
/// suite d'écrans.
private struct PaywallStorySegment: View {
    let share: Double

    var body: some View {
        Capsule()
            .fill(MemoBookColor.outline)
            .overlay(alignment: .leading) {
                GeometryReader { proxy in
                    Capsule()
                        .fill(MemoBookColor.action)
                        .frame(width: proxy.size.width * share)
                }
            }
            .frame(height: PaywallMetrics.storyBarHeight)
            .animation(nil, value: share)
    }
}

/// Le trait bleu qui se trace à l'arrivée de l'écran.
///
/// C'est l'animation que Figma décrit sur ces nœuds (`path-trim`) : le trait
/// n'apparaît pas, il **s'écrit** — un peu moins d'une seconde, en ralentissant
/// à la fin. Rien ne bouge en Reduce Motion : le trait est là, entier, tout de
/// suite.
struct PaywallSquiggle<S: Shape>: View {
    let shape: S
    let lineWidthRatio: CGFloat
    let aspectRatio: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var drawn: CGFloat = 0

    /// Relevé sur les images-clés Figma : 0,117 s d'attente, puis 0,79 s de
    /// tracé qui ralentit.
    private static var delay: Duration { .milliseconds(117) }
    private static var duration: Double { 0.79 }

    /// De combien le trait dépasse **de chaque côté**, en part de sa largeur.
    ///
    /// Un trait qui s'arrête pile au bord de l'écran montre ses deux bouts
    /// arrondis, et se lit alors comme un objet posé là plutôt que comme un
    /// geste qui traverse la page. Douze pour cent de chaque côté suffisent à
    /// les sortir du cadre sur tous les formats, y compris le SE.
    private static var bleed: CGFloat { 0.12 }

    var body: some View {
        GeometryReader { proxy in
            BleedingShape(base: shape, bleed: Self.bleed)
                .trim(from: 0, to: drawn)
                .stroke(
                    MemoBookColor.outline,
                    style: StrokeStyle(
                        lineWidth: proxy.size.height * lineWidthRatio,
                        lineCap: .round
                    )
                )
        }
        .aspectRatio(aspectRatio, contentMode: .fit)
        .accessibilityHidden(true)
        .task {
            guard !reduceMotion else {
                drawn = 1
                return
            }
            try? await Task.sleep(for: Self.delay)
            withAnimation(.easeOut(duration: Self.duration)) { drawn = 1 }
        }
    }
}

/// Un tracé dessiné **plus large que la place qu'on lui donne**, pour que ses
/// deux bouts tombent hors de l'écran.
///
/// Le débordement se fait dans le **chemin** et non par un `scaleEffect` : la
/// mise à l'échelle non uniforme d'un trait déjà tracé en écrase l'épaisseur
/// d'un côté et ovalise ses bouts ronds. Ici le chemin est construit dans un
/// cadre élargi, puis tracé normalement — l'épaisseur reste constante d'un bout
/// à l'autre.
///
/// La vue, elle, ne change pas de taille : c'est du dessin qui sort de son
/// cadre, pas une vue plus grande. Le `trim` de l'animation porte donc sur le
/// tracé entier, ce qui fait entrer le trait **par le hors-champ** — le geste
/// commence avant le bord de l'écran, exactement comme un trait à la main.
private struct BleedingShape<Base: Shape>: Shape {
    let base: Base
    /// Part de la largeur ajoutée de chaque côté.
    let bleed: CGFloat

    func path(in rect: CGRect) -> Path {
        base.path(in: rect.insetBy(dx: -rect.width * bleed, dy: 0))
    }
}

/// Ce qui, dans une page de paywall, **ne prend pas le doigt**.
///
/// Un `Text` de SwiftUI est touchable par défaut, même quand il n'a aucune
/// action : posé au-dessus des zones de tapotis, il les empêche de recevoir le
/// geste, et la story ne défile plus là où il y a du texte — c'est-à-dire
/// partout. Ce modificateur dit en un mot que ce bloc est du décor.
///
/// Les **contrôles** ne le portent jamais : ce sont eux qui doivent gagner.
extension View {
    func paywallProse() -> some View { allowsHitTesting(false) }
}

// MARK: - Écran 1 — « Bravo ! »

struct PaywallCongratulations: View {
    let onContinue: () -> Void

    var body: some View {
        VStack(spacing: MemoBookSpacing.l) {
            Spacer(minLength: 0)

            VStack(spacing: MemoBookSpacing.s) {
                PaywallEyebrow(PaywallCopy.bravoEyebrow)
                PaywallTitle(lead: PaywallCopy.bravoTitleLead, strong: PaywallCopy.bravoTitleStrong)

                (Text(PaywallCopy.bravoBodyLead) + Text(PaywallCopy.bravoBodyStrong).font(MemoBookFont.tagline))
                    .font(MemoBookFont.taglineRegular)
                    .foregroundStyle(MemoBookColor.ink)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .paywallProse()

            PaywallSquiggle(
                shape: BrandSquiggleDown(),
                lineWidthRatio: BrandSquiggleDown.lineWidthRatio,
                aspectRatio: BrandSquiggleDown.size.width / BrandSquiggleDown.size.height
            )
            .padding(.horizontal, -PaywallMetrics.margin)
            .paywallProse()

            Spacer(minLength: 0)

            BrandButton(PaywallCopy.cont, style: .blue, fillsWidth: true, action: onContinue)
        }
    }
}

// MARK: - Écran 2 — « Selon nos calculs... »

struct PaywallEstimate: View {
    let onContinue: () -> Void
    /// Ouvre la feuille « Prévisualisation ». L'écran ne la présente pas
    /// lui-même : elle doit se poser **par-dessus le paywall entier**, et c'est
    /// ``PaywallView`` qui l'occupe.
    let onPreview: () -> Void

    var body: some View {
        VStack(spacing: MemoBookSpacing.l) {
            Spacer(minLength: 0)

            VStack(spacing: MemoBookSpacing.s) {
                Group {
                    PaywallEyebrow(PaywallCopy.estimateEyebrow)
                    PaywallTitle(
                        lead: PaywallCopy.estimateTitleLead,
                        strong: PaywallCopy.estimateTitleStrong,
                        isUnderlined: true
                    )
                }
                .paywallProse()

                VStack(spacing: MemoBookSpacing.xs) {
                    ForEach(PaywallCopy.estimateBody, id: \.self) { line in
                        Text(line)
                            .font(MemoBookFont.taglineRegular)
                            .foregroundStyle(MemoBookColor.ink)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                            .paywallProse()
                    }

                    // La pastille **ouvre** désormais la feuille du nœud
                    // « Modale - Paywall Previsualisation ». Elle garde son
                    // dessin de pastille, comme la maquette : c'est une
                    // proposition posée dans une phrase, pas l'appel à l'action
                    // de l'écran — celui-là est le bouton bleu du bas.
                    Button(action: onPreview) {
                        BrandTagPill(
                            PaywallCopy.previewPill,
                            tone: .accentOutlined,
                            isUppercased: true
                        )
                    }
                    .buttonStyle(.plain)
                    // La cible tactile monte à 2.75 rem même si la pastille est
                    // plus courte : le dessin est plus petit que le geste (R7).
                    .frame(minHeight: MemoBookSpacing.minimumTapTarget)
                    .contentShape(.rect)
                    .accessibilityAddTraits(.isButton)
                }
            }

            PaywallSquiggle(
                shape: BrandSquiggleUp(),
                lineWidthRatio: BrandSquiggleUp.lineWidthRatio,
                aspectRatio: BrandSquiggleUp.size.width / BrandSquiggleUp.size.height
            )
            .padding(.horizontal, -PaywallMetrics.margin)
            .paywallProse()

            Spacer(minLength: 0)

            VStack(spacing: MemoBookSpacing.s) {
                VStack(spacing: MemoBookSpacing.xs / 2) {
                    ForEach(PaywallCopy.estimateFootnote, id: \.self) { line in
                        Text(line)
                            .font(MemoBookFont.taglineRegular)
                            .foregroundStyle(MemoBookColor.inkMuted)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .paywallProse()

                BrandButton(PaywallCopy.cont, style: .blue, fillsWidth: true, action: onContinue)
            }
        }
    }
}

// MARK: - Le mot de retour

/// L'écran qui ouvre le paywall d'un ancien abonné.
///
/// **Il remplace deux écrans à lui seul.** La version de découverte félicite
/// (« Tu as enregistré tes 3 premières étapes ! ») puis projette un nombre de
/// pages ; celui-ci ne fait ni l'un ni l'autre, et le dit : « on ne t'embête pas
/// plus ». C'est le seul écran de l'app dont la raison d'être est d'en économiser
/// un autre.
struct PaywallReturning: View {
    let onContinue: () -> Void

    var body: some View {
        VStack(spacing: MemoBookSpacing.l) {
            Spacer(minLength: 0)

            VStack(spacing: MemoBookSpacing.s) {
                Group {
                    PaywallEyebrow(PaywallCopy.returnEyebrow)
                    PaywallTitle(
                        lead: PaywallCopy.returnTitleLead,
                        strong: PaywallCopy.returnTitleStrong,
                        isUnderlined: true
                    )
                }
                .paywallProse()

                VStack(spacing: MemoBookSpacing.xs / 2) {
                    ForEach(PaywallCopy.returnBody, id: \.self) { line in
                        Text(line)
                            .font(MemoBookFont.taglineRegular)
                            .foregroundStyle(MemoBookColor.ink)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .paywallProse()
            }

            PaywallSquiggle(
                shape: BrandSquiggleDown(),
                lineWidthRatio: BrandSquiggleDown.lineWidthRatio,
                aspectRatio: BrandSquiggleDown.size.width / BrandSquiggleDown.size.height
            )
            .padding(.horizontal, -PaywallMetrics.margin)
            .paywallProse()

            Spacer(minLength: 0)

            BrandButton(PaywallCopy.cont, style: .blue, fillsWidth: true, action: onContinue)
        }
    }
}

// MARK: - Écran 3 — l'offre

struct PaywallOffer: View {
    let price: String
    /// Le titre, qui change avec la version — voir ``PaywallVariant/offerTitle``.
    /// Le surtitre, les quatre arguments et le bouton, eux, sont les mêmes :
    /// c'est la **même offre**, pas une seconde.
    var title: (lead: String, strong: String) = (
        PaywallCopy.offerTitleLead, PaywallCopy.offerTitleStrong
    )
    /// « Voir une estimation → », sur la quatrième carte : la feuille qui
    /// détaille le calcul. L'écran ne la présente pas lui-même — elle se pose
    /// **par-dessus le paywall entier**, comme l'aperçu.
    let onEstimate: () -> Void
    /// « Choisis ton mode de paiement » : la feuille de paiement, présentée par
    /// le paywall pour la même raison.
    let onSubscribe: () -> Void

    /// Le tapotis sur la moitié gauche : **reculer d'un écran**, comme sur les
    /// deux premiers (T132, T135). La `ScrollView` prend le doigt avant les
    /// zones que le paywall pose sous lui ; la zone vit donc **dans** son
    /// contenu, derrière les cartes, qui laissent passer le tapotis partout
    /// sauf sur leur pastille.
    var onBack: () -> Void = {}

    /// La hauteur du pied, mesurée : c'est elle qu'il faut retirer de la page
    /// pour centrer le contenu dans ce qu'on **voit**. Le `GeometryReader`
    /// mesure la page entière, pied compris ; centré sur cette hauteur-là, le
    /// contenu laissait un vide en haut et cachait sa dernière carte sous le
    /// pied.
    @State private var footerHeight: CGFloat = 0

    var body: some View {
        // **Une `ScrollView`, et non une pile qui répartit l'espace.** Quatre
        // cartes, un titre de deux lignes et le pied ne tiennent pas sur un
        // iPhone SE — ni sur un grand écran en taille de texte agrandie —, et
        // la pile faisait remonter le tout **sous** la barre de stories, jusque
        // sur « Besoin d'aide ? » (Hugo, 15/09/2026). Le pied — la mention et le
        // bouton — reste posé en bas sur le voile de la marque, et les cartes
        // défilent dessous.
        GeometryReader { proxy in
            ScrollView {
                VStack(spacing: MemoBookSpacing.l) {
                    Spacer(minLength: 0)

                    VStack(spacing: MemoBookSpacing.s) {
                        PaywallEyebrow(PaywallCopy.offerEyebrow)
                        PaywallTitle(lead: title.lead, strong: title.strong, isUnderlined: true)
                    }
                    .paywallProse()

                    // Les quatre cartes se chevauchent de 4 pt et penchent
                    // chacune de son côté : c'est une pile de papiers posés à la
                    // main, pas une liste. La quatrième porte la seule action du
                    // bloc, la pastille « Voir une estimation ».
                    VStack(spacing: -4) {
                        ForEach(Array(PaywallCopy.arguments.enumerated()), id: \.offset) { _, argument in
                            PaywallArgumentCard(
                                argument: argument,
                                onPill: argument.pill == nil ? nil : onEstimate
                            )
                            // Une carte de décor laisse passer le tapotis
                            // jusqu'à la zone de retour ; celle qui porte la
                            // pastille garde le doigt pour elle.
                            .allowsHitTesting(argument.pill != nil)
                        }
                    }

                    Spacer(minLength: 0)
                }
                .padding(.horizontal, PaywallMetrics.margin)
                .padding(.top, MemoBookSpacing.s)
                .frame(maxWidth: .infinity)
                // Assez haut pour que les deux ressorts centrent le contenu
                // dans la zone visible quand il y tient ; au-delà, il défile.
                .frame(minHeight: max(0, proxy.size.height - footerHeight))
                // La moitié gauche recule d'un écran ; la droite ne fait rien,
                // c'est le dernier. Derrière le contenu, pour que la pastille
                // et le bouton gagnent toujours.
                .background {
                    HStack(spacing: 0) {
                        Color.clear.contentShape(.rect).onTapGesture(perform: onBack)
                        Color.clear
                    }
                    .accessibilityHidden(true)
                }
            }
            .scrollIndicators(.hidden)
            .scrollBounceBehavior(.basedOnSize)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                footer
                    .onGeometryChange(for: CGFloat.self, of: \.size.height) { footerHeight = $0 }
            }
            // Le voile du haut : ce qui remonte sous la barre de stories s'y
            // **dissout** au lieu d'être tranché net au ras de la barre — le
            // même geste que la galerie sous sa barre de filtres. Court, pour
            // ne toucher que ce qui défile, jamais le surtitre au repos.
            .overlay(alignment: .top) {
                LinearGradient(
                    colors: [MemoBookColor.background, MemoBookColor.background.opacity(0)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: MemoBookSpacing.s)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
        }
        // La page sort des marges de l'écran, pour que le voile du pied aille
        // d'un bord à l'autre et jusqu'au bas de la dalle ; elle remet la marge
        // sur son propre contenu. Et elle laisse un souffle sous la barre de
        // stories, que le contenu ne vient pas toucher.
        .padding(.top, MemoBookSpacing.xs)
        .padding(.horizontal, -PaywallMetrics.margin)
        .padding(.bottom, -MemoBookSpacing.l)
    }

    /// La mention de renouvellement et le bouton, sur le voile — voir
    /// ``BrandFooterScrim`` : ce qui défile dessous s'y dissout, et les deux
    /// restent lisibles.
    private var footer: some View {
        VStack(spacing: MemoBookSpacing.s) {
            VStack(spacing: MemoBookSpacing.xs / 2) {
                ForEach(PaywallCopy.offerFootnote(price: price), id: \.self) { line in
                    Text(line)
                        .font(MemoBookFont.taglineRegular)
                        .foregroundStyle(MemoBookColor.ink)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            BrandButton(
                PaywallCopy.offerCallToAction,
                icon: Image(brand: "IconArrowForward"),
                iconPlacement: .trailing,
                fillsWidth: true,
                action: onSubscribe
            )
            // Même limite que les CTA de l'accueil et du voyage : au-delà
            // d'AX1, une barre ancrée en bas prend la moitié de l'écran.
            .dynamicTypeSize(...DynamicTypeSize.accessibility1)
        }
        .padding(.horizontal, PaywallMetrics.margin)
        .padding(.top, MemoBookSpacing.s)
        .padding(.bottom, MemoBookSpacing.xs)
        .brandFooterScrim()
    }
}

/// Une des quatre promesses de l'offre : une pastille d'icône, deux lignes, et
/// parfois un lien.
struct PaywallArgumentCard: View {
    let argument: PaywallCopy.Argument

    /// Ce que la pastille ouvre, quand la carte en porte une. `nil` la laisse
    /// muette — une carte de décor.
    var onPill: (() -> Void)? = nil

    @ScaledMetric(relativeTo: .body) private var badgeSide: CGFloat = 34
    /// Presque la plaque entière : le glyphe du jeu de marque n'occupe qu'une
    /// part de sa boîte — voir ``MemoBookSpacing/contentIcon``.
    @ScaledMetric(relativeTo: .body) private var iconSide: CGFloat = 28

    private var shape: RoundedRectangle {
        .rect(cornerRadius: MemoBookSpacing.largeCornerRadius)
    }

    var body: some View {
        HStack(spacing: MemoBookSpacing.snug) {
            Image(brand: argument.icon)
                .resizable()
                .renderingMode(.template)
                .scaledToFit()
                .frame(width: iconSide, height: iconSide)
                .foregroundStyle(MemoBookColor.ink)
                .frame(width: badgeSide, height: badgeSide)
                .background(
                    MemoBookColor.outline.opacity(0.3),
                    in: .rect(cornerRadius: MemoBookSpacing.snug + 1)
                )
                // La pastille se redresse : la carte penche, pas son icône.
                .rotationEffect(.degrees(-argument.tilt))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: MemoBookSpacing.xs) {
                Text(argument.title)
                    .font(MemoBookFont.tagline)
                Text(argument.detail)
                    .font(MemoBookFont.caption)

                if let pill = argument.pill {
                    if let onPill {
                        // La pastille **ouvre** la feuille « Estimation »
                        // (`3469:14105`). Elle garde son dessin de pastille,
                        // comme celle de l'écran 2 : une proposition posée
                        // dans une phrase, pas l'appel à l'action de l'écran.
                        Button(action: onPill) {
                            BrandTagPill(pill, tone: .accentOutlined, isUppercased: true)
                        }
                        .buttonStyle(.plain)
                        // La cible monte au seuil de R7 sans que la carte
                        // grandisse : la marge négative rend à la mise en page
                        // ce que le cadre a pris.
                        .frame(minHeight: MemoBookSpacing.minimumTapTarget)
                        .padding(.vertical, -(MemoBookSpacing.minimumTapTarget - 24) / 2)
                        .contentShape(.rect)
                        .accessibilityAddTraits(.isButton)
                        .padding(.top, MemoBookSpacing.xs / 2)
                    } else {
                        BrandTagPill(pill, tone: .accentOutlined, isUppercased: true)
                            .padding(.top, MemoBookSpacing.xs / 2)
                    }
                }
            }
            .foregroundStyle(MemoBookColor.ink)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, MemoBookSpacing.xs)
        .padding(.vertical, 14)
        .background(MemoBookColor.background, in: shape)
        .overlay { shape.strokeBorder(MemoBookColor.outline, lineWidth: 1) }
        .rotationEffect(.degrees(argument.tilt))
        // Une carte qui porte un bouton garde ses enfants pour VoiceOver : les
        // fondre avalerait la pastille.
        .accessibilityElement(children: onPill == nil ? .combine : .contain)
    }
}

// MARK: - Morceaux communs

/// Le surtitre : une ligne de Sora, au-dessus du titre.
struct PaywallEyebrow: View {
    private let title: String
    init(_ title: String) { self.title = title }

    var body: some View {
        Text(title)
            .font(MemoBookFont.eyebrow)
            .foregroundStyle(MemoBookColor.ink)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// Le titre des trois écrans : une phrase où **la fin pèse**, et se souligne
/// parfois d'un trait tracé à la main.
struct PaywallTitle: View {
    let lead: String
    let strong: String
    var isUnderlined = false

    var body: some View {
        (Text(lead).font(MemoBookFont.h1Light) + Text(strong).font(MemoBookFont.h1))
            .foregroundStyle(MemoBookColor.ink)
            .tracking(-0.41)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .overlay(alignment: .bottomTrailing) {
                if isUnderlined {
                    PaywallSquiggle(
                        shape: BrandUnderline(),
                        lineWidthRatio: BrandUnderline.lineWidthRatio,
                        aspectRatio: BrandUnderline.size.width / BrandUnderline.size.height
                    )
                    // Le trait souligne les derniers mots : il tient la moitié
                    // de la colonne et s'aligne sur leur fin.
                    .frame(width: 143)
                    .offset(y: MemoBookSpacing.xs / 2)
                }
            }
    }
}
