import SwiftUI

/// L'en-tête d'un écran secondaire : par où l'on sort, de quoi on parle, et au
/// plus une action.
///
/// Quatre écrans le dessinaient à l'identique — les paramètres d'un voyage, la
/// composition du carnet, l'aperçu PDF et la cagnotte. C'est **le** motif de
/// l'écran poussé, et il vit ici pour une raison précise : la flèche de retour
/// est le même geste partout, elle doit donc tomber au même endroit et faire la
/// même taille d'un écran à l'autre. Elle valait déjà trois valeurs différentes
/// avant que ``MemoBookSpacing/navigationIcon`` existe.
///
/// ```swift
/// BrandScreenHeader(
///     title: BookCopy.Wallet.title,
///     subtitle: BookCopy.Wallet.subtitle(trip: "Rome")
/// )
/// ```
///
/// Il ne pose **pas** de barre de navigation : l'écran qui l'emploie masque la
/// sienne avec ``SwiftUI/View/brandHiddenNavigationBar()``, qui rend au passage
/// le glissé depuis le bord.
public struct BrandScreenHeader<Trailing: View>: View {
    private let title: String
    private let subtitle: String?
    private let isSubtitleLoading: Bool
    private let onBack: (() -> Void)?
    private let trailing: Trailing

    /// - Parameters:
    ///   - subtitle: la ligne sous le titre. `nil` quand l'écran n'en a pas —
    ///     l'en-tête se contente alors d'une ligne, il ne réserve pas la place.
    ///   - isSubtitleLoading: le sous-titre vient du serveur et n'est pas encore
    ///     là. Le **titre**, lui, s'affiche toujours tout de suite : il
    ///     appartient à l'app. Voir ``BrandSkeleton``.
    ///   - onBack: ce que fait la flèche. `nil` referme l'écran, ce qui est le
    ///     cas courant. Un **parcours en étapes** la détourne pour revenir à
    ///     l'étape précédente : la flèche reste alors le même geste au même
    ///     endroit, et c'est bien pour ça qu'elle vit ici et non dans chaque
    ///     écran.
    ///   - trailing: l'action de bout de ligne, au plus une. Deux commandes en
    ///     tête d'un écran poussé et on ne sait plus laquelle est la sortie.
    public init(
        title: String,
        subtitle: String? = nil,
        isSubtitleLoading: Bool = false,
        onBack: (() -> Void)? = nil,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.title = title
        self.subtitle = subtitle
        self.isSubtitleLoading = isSubtitleLoading
        self.onBack = onBack
        self.trailing = trailing()
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize

    /// La hauteur d'une ligne du titre (``MemoBookFont/heading``, Sora 20),
    /// pour poser la flèche **en face** de cette ligne — voir ``text``.
    @ScaledMetric(relativeTo: .title3) private var titleLineHeight: CGFloat = 26

    public var body: some View {
        HStack(alignment: .top, spacing: MemoBookSpacing.xs) {
            backButton

            text
                // Le texte prend la place qui reste et la garde : sans ça, un
                // titre court laissait l'action revenir se coller contre lui.
                .frame(maxWidth: .infinity, alignment: .leading)

            trailing
        }
        .padding(.bottom, MemoBookSpacing.xs)
    }

    /// La flèche de retour, bichrome comme sur toutes les maquettes d'écran
    /// poussé.
    ///
    /// Sa cible tactile est **alignée à gauche sur la marge de la colonne** et
    /// le dessin centré dedans : centrée sur l'icône, elle débordait de la
    /// colonne et la moitié gauche des touches tombait à côté.
    private var backButton: some View {
        Button { onBack?() ?? dismiss() } label: {
            Image(brand: "IconArrowDuo")
                .resizable()
                .scaledToFit()
                .frame(
                    width: MemoBookSpacing.navigationIcon,
                    height: MemoBookSpacing.navigationIcon
                )
                .frame(
                    width: MemoBookSpacing.minimumTapTarget,
                    height: MemoBookSpacing.minimumTapTarget
                )
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Retour")
    }

    private var text: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(MemoBookFont.heading)
                .foregroundStyle(MemoBookColor.ink)
                .accessibilityAddTraits(.isHeader)

            if isSubtitleLoading {
                BrandSkeleton(width: 180)
            } else if let subtitle {
                Text(subtitle)
                    .font(MemoBookFont.h3)
                    .foregroundStyle(MemoBookColor.ink)
                    // Le sous-titre d'un parcours en étapes change à chaque
                    // « Continuer » — « Étape 2/7 », « Étape 3/7 ». Il se
                    // remplace en fondu plutôt que d'un coup sec, sans quoi
                    // c'est la seule chose de l'en-tête qui saute.
                    .contentTransition(.numericText())
                    .animation(.smooth(duration: 0.25), value: subtitle)
            }
        }
        // Les deux lignes s'enroulent plutôt que de se faire rogner : en taille
        // accessible, « Rome et la Dolce Vita - 10 pages composées » tient sur
        // trois lignes, et l'en-tête grandit avec.
        .fixedSize(horizontal: false, vertical: true)
        .multilineTextAlignment(.leading)
        // La ligne du haut aligne la flèche sur le **titre** et non sur le bloc
        // entier : avec un sous-titre de trois lignes, un centrage vertical
        // faisait descendre la sortie au milieu du texte.
        //
        // Et **en face de sa première ligne**, pas de son bord haut : la flèche
        // est dessinée au centre d'une cible de 2.75 rem, le titre fait une
        // ligne de 26 — posés bord à bord, la flèche tombait 5 pt sous le
        // milieu du titre, ce qui se voyait sur les paramètres du voyage (Hugo,
        // 14/09/2026, T103). La marge du titre vaut donc la moitié de l'écart
        // entre les deux, et suit le corps du texte. En taille accessible le
        // titre dépasse la cible : plus rien à rattraper.
        .padding(.top, typeSize.isAccessibilitySize ? 0 : max(0, (MemoBookSpacing.minimumTapTarget - titleLineHeight) / 2))
    }
}

extension BrandScreenHeader where Trailing == EmptyView {
    /// L'en-tête sans action de bout de ligne — le cas courant.
    public init(
        title: String,
        subtitle: String? = nil,
        isSubtitleLoading: Bool = false,
        onBack: (() -> Void)? = nil
    ) {
        self.init(
            title: title,
            subtitle: subtitle,
            isSubtitleLoading: isSubtitleLoading,
            onBack: onBack,
            trailing: { EmptyView() }
        )
    }
}

/// Une commande carrée en bout d'en-tête : une icône cerclée d'un filet
/// d'encre, à la cible tactile de l'app.
///
/// Le cerne la distingue de la flèche de retour, qui n'en a pas : la sortie est
/// un geste qu'on connaît, l'action de l'écran est un bouton qu'on découvre.
public struct BrandHeaderAction: View {
    private let icon: String
    private let label: String
    private let action: () -> Void

    public init(icon: String, label: String, action: @escaping () -> Void) {
        self.icon = icon
        self.label = label
        self.action = action
    }

    /// L'icône suit le texte, la cible non : une commande qui grandit à
    /// l'infini pousserait le titre hors de sa ligne.
    /// 24 et non 28 (Hugo, 19/09/2026) : le tracé du partage remplit sa boîte
    /// bien plus que le crayon ou l'engrenage, et à 28 il pesait plus lourd
    /// que le titre qu'il accompagne. C'est la taille d'une icône de barre,
    /// pas celle d'une icône de contenu.
    @ScaledMetric(relativeTo: .body) private var iconSide: CGFloat = 24

    public var body: some View {
        let shape = RoundedRectangle(cornerRadius: MemoBookSpacing.snug)

        return Button(action: action) {
            Image(brand: icon)
                .resizable()
                .renderingMode(.template)
                .scaledToFit()
                .frame(width: min(iconSide, MemoBookSpacing.l), height: min(iconSide, MemoBookSpacing.l))
                .foregroundStyle(MemoBookColor.ink)
                .frame(
                    width: MemoBookSpacing.minimumTapTarget,
                    height: MemoBookSpacing.minimumTapTarget
                )
                // Figma dessine un filet de 0,75 pt. R1 garde les traits en
                // points, et 1 pt est l'épaisseur unique de l'app
                // (`Stroke/Border Width`) : un second filet plus fin ne se
                // verrait pas, il ne ferait que se distinguer à l'export.
                .overlay { shape.strokeBorder(MemoBookColor.ink, lineWidth: 1) }
                .contentShape(shape)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

#Preview("En-têtes d’écran") {
    VStack(alignment: .leading, spacing: MemoBookSpacing.l) {
        BrandScreenHeader(title: "Paramètres du voyage")

        BrandScreenHeader(
            title: "Ma Cagnotte",
            subtitle: "Finance ton carnet de Rome"
        )

        BrandScreenHeader(
            title: "Aperçu PDF",
            subtitle: "Rome et la Dolce Vita - 10 pages composées"
        ) {
            BrandHeaderAction(icon: "IconShareSystem", label: "Partager mon carnet") {}
        }

        BrandScreenHeader(title: "Aperçu PDF", subtitle: nil, isSubtitleLoading: true)
    }
    .padding(.horizontal, MemoBookSpacing.screenMargin)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    .background(MemoBookColor.background)
    .environment(\.colorScheme, .light)
}
