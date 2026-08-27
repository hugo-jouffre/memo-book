import MemoBookDesign
import SwiftUI

/// Une des trois cartes bénéfices du *Welcome*.
///
/// Les dimensions sont uniformisées (décision D4) — Figma donne trois largeurs
/// différentes parce que les cadres épousent leur texte — mais l'inclinaison,
/// elle, se garde au degré près.
struct BenefitCard: View {
    let benefit: Benefit

    @ScaledMetric(relativeTo: .body) private var unit: CGFloat = MemoBookMetric.unit

    var body: some View {
        HStack(spacing: rem(0.75)) {
            icon

            VStack(alignment: .leading, spacing: rem(0.25)) {
                Text(benefit.title)
                    .font(MemoBookFont.sectionTitle)
                    .tracking(MemoBookTracking.body)

                Text(benefit.description)
                    .font(MemoBookFont.description)
                    .tracking(MemoBookTracking.description)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(MemoBookColor.ink)
            .frame(maxWidth: .infinity, alignment: .leading)

            FigmaImage(.cardArrow)
                .frame(width: unit * 1.5, height: unit * 1.5)
        }
        .padding(.horizontal, MemoBookSpacing.s)
        .padding(.vertical, rem(1.25))
        // Jamais de hauteur figée : le texte doit pouvoir s'étendre en
        // Dynamic Type. 5.75 rem est un plancher, pas une taille.
        .frame(minHeight: unit * 5.75)
        .background(
            MemoBookColor.surface,
            in: .rect(cornerRadius: MemoBookSpacing.cardCornerRadius)
        )
        .overlay {
            RoundedRectangle(cornerRadius: MemoBookSpacing.cardCornerRadius)
                .stroke(MemoBookColor.illustration, lineWidth: MemoBookStroke.border)
        }
        // La pastille déborde du cadre de la moitié de sa hauteur : le débord
        // est le dessin, on ne le rentre pas.
        .overlay(alignment: .topTrailing) {
            NumberBadge(benefit.number)
                .padding(.trailing, MemoBookSpacing.m)
                .offset(y: rem(-0.8125))
        }
        .rotationEffect(.degrees(benefit.tilt))
        // Les 2 pt retirés de la largeur absorbent le débord de la rotation :
        // un cadre incliné de 1° reste dans la marge d'écran.
        .padding(.horizontal, rem(0.0625))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "Étape \(benefit.number) sur 3. \(benefit.title). \(benefit.description)"
        )
    }

    /// Le fond d'icône : 2.75 × 2.5 rem, Blue à 30 %, rayon 0.75 rem.
    /// L'icône garde son ratio d'origine — jamais déformée.
    private var icon: some View {
        FigmaImage(benefit.icon)
            .frame(height: unit * 1.25)
            .frame(width: unit * 2.75, height: unit * 2.5)
            .background(
                MemoBookColor.illustrationSoft,
                in: .rect(cornerRadius: MemoBookSpacing.iconCornerRadius)
            )
    }
}

#Preview("Carte bénéfice") {
    VStack(spacing: MemoBookSpacing.m) {
        ForEach(WelcomeCopy.benefits) { BenefitCard(benefit: $0) }
    }
    .padding(MemoBookSpacing.screenMargin)
    .background(MemoBookColor.background)
}
