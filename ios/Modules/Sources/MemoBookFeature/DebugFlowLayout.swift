#if DEBUG

    import SwiftUI

    // La disposition des boutons des bacs à sable. Elle vivait dans le panneau
    // de l'accueil ; celui de la cagnotte en a eu besoin aussi, et une
    // disposition n'appartient à aucun des deux écrans.
    //
    // **Absente de l'app livrée**, comme les panneaux qu'elle sert.

    /// Une rangée qui passe à la ligne quand elle déborde.
    ///
    /// `Layout` plutôt qu'une grille : le nombre de boutons par ligne dépend de
    /// la longueur de leurs libellés, qu'une grille à colonnes fixes ne connaît
    /// pas. Vingt lignes ici évitent de découper la liste à la main à chaque
    /// bouton ajouté.
    struct FlowLayout: Layout {
        var spacing: CGFloat

        func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
            let width = proposal.width ?? .infinity
            let rows = rows(for: subviews, width: width)
            let height = rows.reduce(0) { $0 + $1.height } + spacing * CGFloat(max(rows.count - 1, 0))
            return CGSize(width: width == .infinity ? rows.map(\.width).max() ?? 0 : width, height: height)
        }

        func placeSubviews(
            in bounds: CGRect,
            proposal: ProposedViewSize,
            subviews: Subviews,
            cache: inout ()
        ) {
            var y = bounds.minY

            for row in rows(for: subviews, width: bounds.width) {
                var x = bounds.minX
                for index in row.indices {
                    let size = subviews[index].sizeThatFits(.unspecified)
                    subviews[index].place(
                        at: CGPoint(x: x, y: y),
                        anchor: .topLeading,
                        proposal: ProposedViewSize(size)
                    )
                    x += size.width + spacing
                }
                y += row.height + spacing
            }
        }

        private struct Row {
            var indices: [Int] = []
            var width: CGFloat = 0
            var height: CGFloat = 0
        }

        private func rows(for subviews: Subviews, width: CGFloat) -> [Row] {
            var rows: [Row] = []
            var current = Row()

            for index in subviews.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                let needed = current.indices.isEmpty ? size.width : current.width + spacing + size.width

                if needed > width, !current.indices.isEmpty {
                    rows.append(current)
                    current = Row()
                }

                current.indices.append(index)
                current.width = current.indices.count == 1 ? size.width : current.width + spacing + size.width
                current.height = max(current.height, size.height)
            }

            if !current.indices.isEmpty { rows.append(current) }
            return rows
        }
    }

#endif
