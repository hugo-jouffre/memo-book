#if DEBUG

    import MemoBookCore
    import MemoBookDesign
    import SwiftUI

    /// Le bac à sable de l'accueil : de quoi voir chacun de ses états sans
    /// back-end ni compte.
    ///
    /// **Il n'existe pas dans l'app livrée.** Le fichier entier est sous
    /// `#if DEBUG` : il ne compile pas en release, et rien de ce qu'il appelle
    /// non plus — voir le bac à sable de ``HomeModel``.
    ///
    /// Il est posé tout en bas de l'accueil, après le contenu réel, et se
    /// présente comme ce qu'il est : un panneau d'atelier, pas un morceau de
    /// l'app. D'où le pointillé et le libellé qui le nomme.
    struct HomeDebugPanel: View {
        let model: HomeModel

        var body: some View {
            VStack(alignment: .leading, spacing: MemoBookSpacing.xs) {
                Text("Bac à sable — absent de l’app livrée")
                    .font(MemoBookFont.caption)
                    .foregroundStyle(MemoBookColor.inkMuted)

                // Les boutons s'écoulent sur plusieurs lignes : ils sont
                // nombreux, de largeurs très différentes, et une bande qui
                // défile cacherait les derniers.
                FlowLayout(spacing: MemoBookSpacing.xs) {
                    action("Tout effacer", model.debugRemoveAllTrips)
                    action("+ voyage en cours") { model.debugAddTrip(stage: .ongoing) }
                    action("+ voyage à venir") { model.debugAddTrip(stage: .upcoming) }
                    action("+ voyage passé") { model.debugAddTrip(stage: .past) }
                    action("Devenir un abonné", model.debugBecomeSubscriber)
                    action("Première connexion", model.debugFirstConnection)
                    action("Limite atteinte", model.debugReachFreeLimit)
                    action("Erreur", model.debugShowError)
                    action("Jeu d’essai", model.debugReset)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(MemoBookSpacing.s)
            .brandDashedCard(color: MemoBookColor.separator)
        }

        private func action(_ title: String, _ perform: @escaping () -> Void) -> some View {
            Button(title, action: perform)
                .font(MemoBookFont.caption)
                .foregroundStyle(MemoBookColor.action)
                .padding(.horizontal, MemoBookSpacing.xs)
                .padding(.vertical, 6)
                .background(MemoBookColor.surface, in: .capsule)
                .overlay { Capsule().strokeBorder(MemoBookColor.separator, lineWidth: 1) }
        }
    }

    /// Une rangée qui passe à la ligne quand elle déborde.
    ///
    /// `Layout` plutôt qu'une grille : le nombre de boutons par ligne dépend de
    /// la longueur de leurs libellés, qu'une grille à colonnes fixes ne connaît
    /// pas. Vingt lignes ici évitent de découper la liste à la main à chaque
    /// bouton ajouté.
    private struct FlowLayout: Layout {
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
