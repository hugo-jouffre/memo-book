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

                // Le crédit du jour : le neuf, les 30 dernières secondes,
                // l'épuisé et l'abonné. Le jeu d'essai n'en montre qu'un (un
                // voyage entamé, 3 min 20 devant soi) ; la jauge rouge et la
                // ligne « Illimité » ne se voient qu'ici.
                HStack(spacing: MemoBookSpacing.xs) {
                    Button("Crédit neuf") { model.debugPlayDailyCredit(.fresh) }
                    Button("30 s") { model.debugPlayDailyCredit(.lastSeconds) }
                    Button("Épuisé") { model.debugPlayDailyCredit(.exhausted) }
                    Button("Abonné") { model.debugPlayDailyCredit(.unlimited) }
                }
                .font(MemoBookFont.caption)
                .buttonStyle(.bordered)
                .tint(MemoBookColor.action)

                // De quoi remplir « Co-voyageur(s) » : le jeu d'essai en compte
                // deux, et le tiroir de retrait comme la relance d'invitation
                // demandent d'en avoir plusieurs, dont un en attente.
                HStack(spacing: MemoBookSpacing.xs) {
                    Button("+ Un co-voyageur", action: model.debugAddCompanion)
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
