#if DEBUG

    import MemoBookCore
    import MemoBookDesign
    import SwiftUI

    /// Le bac à sable des paramètres du voyage : de quoi voir l'écran pendant
    /// que ses valeurs arrivent, sans mauvais réseau.
    ///
    /// **Il n'existe pas dans l'app livrée.** Le fichier entier est sous
    /// `#if DEBUG`, comme celui de l'accueil.
    ///
    /// Un seul bouton, et c'est normal : l'écran n'a qu'un état que les
    /// maquettes ne dessinent pas — celui où les barres d'attente tiennent la
    /// place des valeurs. Le reste se voit en jeu d'essai.
    struct TripSettingsDebugPanel: View {
        let model: TripSettingsModel

        var body: some View {
            VStack(alignment: .leading, spacing: MemoBookSpacing.xs) {
                Text("Bac à sable — absent de l’app livrée")
                    .font(MemoBookFont.caption)
                    .foregroundStyle(MemoBookColor.inkMuted)

                HStack(spacing: MemoBookSpacing.xs) {
                    Button("Barres d’attente", action: model.debugShowSkeleton)
                    Button("Recharger") { Task { await model.load() } }
                }
                .font(MemoBookFont.caption)
                .buttonStyle(.bordered)
                .tint(MemoBookColor.action)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(MemoBookSpacing.s)
            .brandDashedCard(color: MemoBookColor.separator)
        }
    }

#endif
