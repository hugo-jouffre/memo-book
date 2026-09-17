import MemoBookCore
import MemoBookDesign
import SwiftUI

/// Le choix des chiffres qui s'impriment au dos du carnet.
///
/// Ouverte par le crayon posé sur le bandeau « Mon voyage en quelques chiffres »
/// de la quatrième de couverture — c'est le seul endroit de l'app qui y mène, et
/// c'est le bon : on règle un bloc en le regardant.
///
/// **C'est la version 2 de la maquette** : le chiffre en gros au-dessus de son
/// libellé, six cartes en grille. Elle reprend exactement la composition du
/// bandeau imprimé, là où la version 1 alignait des lignes de réglage — et
/// choisir ce qui va sur un plat en lisant une liste, c'est choisir à l'aveugle.
///
/// La sélection est bornée à trois ou quatre — voir ``BookCovers/statRange``.
/// La contrainte vient du gabarit : sous trois, le bandeau a des colonnes vides ;
/// au-delà de quatre, les chiffres ne sont plus lisibles à la taille imprimée.
struct CoverStatsSheet: View {
    let model: CoversModel

    /// Le brouillon. La feuille ne pose rien tant qu'on n'a pas validé : on doit
    /// pouvoir en décocher un pour en essayer un autre sans que le plat change
    /// trois fois derrière.
    @State private var selection: [String] = []

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        BrandSheet(BookCopy.Covers.Stats.title, subtitle: BookCopy.Covers.Stats.message) {
            VStack(spacing: MemoBookSpacing.m) {
                grid

                BrandButton(BookCopy.Covers.validate, fillsWidth: true) {
                    model.setStats(selection)
                    dismiss()
                }
                // En dessous de trois, le bandeau imprimé aurait des colonnes
                // vides : le bouton attend plutôt que d'accepter et de rogner.
                .disabled(!BookCovers.statRange.contains(selection.count))
            }
        }
        .onAppear { selection = model.covers?.back.statIds ?? [] }
    }

    private var stats: [CoverStat] { model.covers?.stats ?? [] }

    @Environment(\.dynamicTypeSize) private var typeSize

    /// Deux colonnes, comme la maquette — une seule en taille accessible, où
    /// « personnes rencontrées » sur une demi-largeur tiendrait en quatre
    /// lignes de deux syllabes.
    private var columns: [GridItem] {
        let count = typeSize.isAccessibilitySize ? 1 : 2
        return Array(repeating: GridItem(.flexible(), spacing: MemoBookSpacing.snug), count: count)
    }

    private var grid: some View {
        LazyVGrid(columns: columns, spacing: MemoBookSpacing.snug) {
            ForEach(stats) { stat in
                CoverStatCard(
                    stat: stat,
                    isSelected: selection.contains(stat.id),
                    isSelectable: selection.contains(stat.id)
                        || selection.count < BookCovers.statRange.upperBound
                ) {
                    toggle(stat)
                }
            }
        }
        .animation(.snappy(duration: 0.2), value: selection)
    }

    /// Coche ou décoche, en gardant **l'ordre de sélection**.
    ///
    /// C'est cet ordre-là qui s'imprime, de gauche à droite : quelqu'un qui
    /// choisit d'abord les kilomètres veut les voir en premier sur le plat.
    private func toggle(_ stat: CoverStat) {
        if let index = selection.firstIndex(of: stat.id) {
            selection.remove(at: index)
        } else if selection.count < BookCovers.statRange.upperBound {
            selection.append(stat.id)
        }
    }
}

/// Une carte de chiffre : la valeur, son libellé, et le rond qui dit si elle
/// part à l'impression.
private struct CoverStatCard: View {
    let stat: CoverStat
    let isSelected: Bool
    /// `false` quand quatre chiffres sont déjà retenus et que celui-ci n'en fait
    /// pas partie. La carte reste **lisible** et cesse d'être touchable : la
    /// masquer ferait disparaître la moitié de la grille à la quatrième coche.
    let isSelectable: Bool
    let action: () -> Void

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: MemoBookSpacing.snug)

        Button(action: action) {
            HStack(alignment: .top, spacing: MemoBookSpacing.xs) {
                VStack(alignment: .leading, spacing: MemoBookSpacing.xs) {
                    Text(stat.value)
                        .font(MemoBookFont.figure)
                        .foregroundStyle(MemoBookColor.ink)
                        // Un chiffre tient sur une ligne — « 2,3k » ne se
                        // coupe pas (Clara, 17/09/2026).
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)

                    Text(stat.label)
                        .font(MemoBookFont.taglineRegular)
                        .foregroundStyle(MemoBookColor.ink)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                RadioMark(isOn: isSelected)
            }
            .padding(MemoBookSpacing.snug)
            .frame(maxWidth: .infinity, minHeight: MemoBookSpacing.xl * 2, alignment: .topLeading)
            .background(
                isSelected ? MemoBookColor.listeningBackground.opacity(0.5) : MemoBookColor.surface,
                in: shape
            )
            .overlay {
                shape.strokeBorder(
                    isSelected ? MemoBookColor.outline : MemoBookColor.hairline,
                    lineWidth: 1
                )
            }
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .disabled(!isSelectable)
        // Une carte qu'on ne peut plus cocher reste lisible, mais se voit : sans
        // ce gris, on tape dessus sans comprendre pourquoi rien ne se passe.
        .opacity(isSelectable ? 1 : 0.45)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(stat.value) \(stat.label.replacingOccurrences(of: "\n", with: " "))")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

/// Le rond de sélection de la maquette.
///
/// Ce n'est pas un `Toggle` : ces cartes forment un choix **multiple borné**, et
/// un interrupteur dirait « active ceci » là où il faut lire « celui-ci part à
/// l'impression, et il y en a quatre au plus ».
private struct RadioMark: View {
    let isOn: Bool

    @ScaledMetric(relativeTo: .body) private var side: CGFloat = 20

    var body: some View {
        Circle()
            .strokeBorder(
                isOn ? MemoBookColor.blueText : MemoBookColor.disabledOutline,
                lineWidth: isOn ? 1.5 : 1
            )
            .frame(width: side, height: side)
            .overlay {
                if isOn {
                    Circle()
                        .fill(MemoBookColor.blueText)
                        .frame(width: side / 2, height: side / 2)
                }
            }
            .accessibilityHidden(true)
    }
}

#Preview("Choix des statistiques") {
    // Le modèle est chargé avant d'ouvrir la feuille : celle-ci lit les chiffres
    // à l'apparition, et la grille serait vide sans ça.
    @Previewable @State var model = CoversModel(tripId: "trip-rome")

    Color.clear
        .brandSheet(isPresented: .constant(true)) {
            CoverStatsSheet(model: model)
        }
        .environment(\.colorScheme, .light)
        .task { await model.load() }
}
