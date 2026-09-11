import MemoBookDesign
import SwiftUI

// Les trois écrans du paywall, et la barre qui les compte.

/// La barre de stories : un segment par écran, celui du moment se remplit.
struct PaywallStoriesBar: View {
    let pageCount: Int
    let page: Int
    let progress: Double

    var body: some View {
        HStack(spacing: MemoBookSpacing.xs) {
            ForEach(0..<pageCount, id: \.self) { index in
                Capsule()
                    .fill(MemoBookColor.outline)
                    .overlay(alignment: .leading) {
                        GeometryReader { proxy in
                            Capsule()
                                .fill(MemoBookColor.action)
                                .frame(width: proxy.size.width * fill(of: index))
                        }
                    }
                    .frame(height: PaywallMetrics.storyBarHeight)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Écran \(page + 1) sur \(pageCount)")
    }

    /// Un écran déjà passé est plein, celui du moment se remplit, les suivants
    /// sont vides.
    private func fill(of index: Int) -> Double {
        if index < page { return 1 }
        if index > page { return 0 }
        return progress
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

// MARK: - Écran 3 — l'offre

struct PaywallOffer: View {
    let price: String
    let onSubscribe: () -> Void

    var body: some View {
        VStack(spacing: MemoBookSpacing.l) {
            Spacer(minLength: 0)

            VStack(spacing: MemoBookSpacing.s) {
                PaywallEyebrow(PaywallCopy.offerEyebrow)
                PaywallTitle(
                    lead: PaywallCopy.offerTitleLead,
                    strong: PaywallCopy.offerTitleStrong,
                    isUnderlined: true
                )
            }
            .paywallProse()

            // Les quatre cartes se chevauchent de 4 pt et penchent chacune de
            // son côté : c'est une pile de papiers posés à la main, pas une
            // liste.
            VStack(spacing: -4) {
                ForEach(Array(PaywallCopy.arguments.enumerated()), id: \.offset) { _, argument in
                    PaywallArgumentCard(argument: argument)
                }
            }
            // Les quatre cartes sont du décor, pastille « Voir une estimation »
            // comprise : elles ne portent aucune action. Sans ça, elles
            // avaleraient le tapotis de retour sur presque tout l'écran — c'est
            // la contrepartie d'avoir mis les zones de tapotis dessous.
            //
            // ⚠️ Le jour où la pastille mènera quelque part, elle devra sortir
            // de ce bloc, comme celle de l'écran 2.
            .paywallProse()

            Spacer(minLength: 0)

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
            }
        }
    }
}

/// Une des quatre promesses de l'offre : une pastille d'icône, deux lignes, et
/// parfois un lien.
struct PaywallArgumentCard: View {
    let argument: PaywallCopy.Argument

    @ScaledMetric(relativeTo: .body) private var badgeSide: CGFloat = 34
    @ScaledMetric(relativeTo: .body) private var iconSide: CGFloat = 24

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
                    // ⚠️ Inerte : la feuille « Estimation » du nœud n'est pas
                    // encore écrite — fiche écran.
                    BrandTagPill(pill, tone: .accentOutlined, isUppercased: true)
                        .padding(.top, MemoBookSpacing.xs / 2)
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
        .accessibilityElement(children: .combine)
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
