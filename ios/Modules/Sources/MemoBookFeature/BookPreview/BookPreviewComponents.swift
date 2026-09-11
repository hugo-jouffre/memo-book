import MemoBookCore
import MemoBookDesign
import SwiftUI

// Les blocs que la composition et l'aperçu partagent.
//
// Ils sont ici et non dans chaque écran pour une raison de dessin et non de
// rangement : les deux écrans doivent poser **exactement** les mêmes boutons au
// même endroit, sinon le passage de l'un à l'autre les fait sauter. Un composant
// commun est la seule façon d'en être sûr.

/// Les deux appels à l'action du carnet : le personnaliser, ou le commander.
///
/// Le secondaire au-dessus du primaire, comme la maquette : « Personnaliser »
/// est ce qu'on fait plusieurs fois, « Commander » est ce qu'on fait une fois.
/// Le geste répété se pose donc sous le pouce en premier.
struct BookActionsBlock: View {
    /// Faux tant qu'il n'y a pas de carnet : les deux boutons gardent leur
    /// place et passent au gris. Les cacher ferait remonter la carte de
    /// cagnotte de 112 pt à l'arrivée de l'aperçu.
    let isEnabled: Bool
    let onCustomise: () -> Void
    let onOrder: () -> Void

    var body: some View {
        VStack(spacing: MemoBookSpacing.s) {
            BrandButton(
                BookCopy.Preview.customise,
                style: .secondary,
                fillsWidth: true,
                action: onCustomise
            )

            BrandButton(
                BookCopy.Preview.order,
                icon: Image(brand: "IconDeliver"),
                style: .primary,
                fillsWidth: true,
                action: onOrder
            )
        }
        .disabled(!isEnabled)
    }
}

/// « Fais-toi offrir ce carnet » : la carte bleue qui mène à la cagnotte.
///
/// Bleue et non verte, et ce n'est pas un caprice de maquette : le bleu de la
/// marque est l'aplat de ce qui **informe**, le vert celui de ce sur quoi on
/// appuie. Cette carte propose quelque chose qui n'est pas l'action de l'écran —
/// l'écran, c'est le carnet ; elle, c'est comment le payer.
struct BookOfferCard: View {
    let onShare: () -> Void
    let onSeeWallet: () -> Void

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: MemoBookSpacing.largeCornerRadius)

        return VStack(alignment: .leading, spacing: MemoBookSpacing.snug) {
            VStack(alignment: .leading, spacing: MemoBookSpacing.xs / 2) {
                Text(BookCopy.Preview.offerTitle)
                    .font(MemoBookFont.calloutTitle)
                    .foregroundStyle(MemoBookColor.ink)

                Text(BookCopy.Preview.offerMessage)
                    .font(MemoBookFont.caption)
                    .foregroundStyle(MemoBookColor.ink)
            }
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)

            actions
        }
        .padding(MemoBookSpacing.sectionGap)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MemoBookColor.bubbleTraveller.opacity(0.5), in: shape)
        .overlay { shape.strokeBorder(MemoBookColor.outline, lineWidth: 1) }
    }

    /// Les deux actions côte à côte **quand elles tiennent**, empilées sinon.
    ///
    /// `ViewThatFits` et non le test de taille accessible habituel : ces deux
    /// libellés-là sont longs (« Partager ma cagnotte » et « Voir ma
    /// cagnotte »), et ils débordaient **dès la taille par défaut** sur un
    /// iPhone 17 — donc bien avant l'accessibilité. Le seuil ne dépend pas que
    /// du corps du texte mais de la largeur de l'écran et de la longueur des
    /// mots ; c'est à la disposition de trancher, pas à une condition écrite à
    /// la main. Un libellé rogné n'est jamais acceptable : c'est justement le
    /// mot « cagnotte » qui disparaissait.
    private var actions: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: MemoBookSpacing.snug) {
                shareButton
                seeButton
                Spacer(minLength: 0)
            }

            VStack(spacing: MemoBookSpacing.xs) {
                shareButton.frame(maxWidth: .infinity)
                seeButton.frame(maxWidth: .infinity)
            }
        }
    }

    private var shareButton: some View {
        BrandButton(
            BookCopy.Preview.offerShare,
            style: .primary,
            size: .small,
            action: onShare
        )
    }

    private var seeButton: some View {
        BrandButton(
            BookCopy.Preview.offerSee,
            style: .tertiary,
            size: .small,
            action: onSeeWallet
        )
    }
}

/// Une flèche de page : un chevron dans un rond cerclé.
///
/// Elle **garde sa place quand elle ne sert à rien** — page 1 pour la
/// précédente, dernière page pour la suivante — au lieu de disparaître : les
/// trois éléments de l'indicateur sont centrés ensemble, et en retirer un
/// recentrerait les deux autres à chaque bout du carnet.
struct BookPageArrow: View {
    enum Direction { case backward, forward }

    let direction: Direction
    let label: String
    let isEnabled: Bool
    let action: () -> Void

    @ScaledMetric(relativeTo: .body) private var side: CGFloat = 31

    var body: some View {
        Button(action: action) {
            Image(brand: "IconChevron")
                .resizable()
                .renderingMode(.template)
                .scaledToFit()
                // Le chevron du design system pointe à droite ; celui de gauche
                // est le même retourné. Pas deux assets pour un miroir.
                .rotationEffect(.degrees(direction == .backward ? 180 : 0))
                .frame(width: side * 0.45, height: side * 0.45)
                .foregroundStyle(isEnabled ? MemoBookColor.ink : MemoBookColor.inkFaint)
                .frame(width: side, height: side)
                .overlay {
                    Circle().strokeBorder(
                        isEnabled ? MemoBookColor.hairline : MemoBookColor.hairline.opacity(0.5),
                        lineWidth: 1
                    )
                }
                // La cible reste à 2.75 rem même quand le rond fait 31 pt : le
                // dessin est plus petit que le geste (R7).
                .frame(
                    width: MemoBookSpacing.minimumTapTarget,
                    height: MemoBookSpacing.minimumTapTarget
                )
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .accessibilityLabel(label)
    }
}

/// La commande qui passe l'aperçu en plein écran, et celle qui en revient.
///
/// Un rond bleu clair posé sur la page, comme la maquette : la page est du
/// papier, la commande n'en fait pas partie et doit se voir comme ajoutée.
struct BookScreenModeButton: View {
    let icon: String
    let label: String
    let action: () -> Void

    @ScaledMetric(relativeTo: .body) private var side: CGFloat = 36

    var body: some View {
        Button(action: action) {
            Image(brand: icon)
                .resizable()
                .scaledToFit()
                .frame(width: min(side, 52), height: min(side, 52))
                .frame(
                    width: MemoBookSpacing.minimumTapTarget,
                    height: MemoBookSpacing.minimumTapTarget
                )
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}
