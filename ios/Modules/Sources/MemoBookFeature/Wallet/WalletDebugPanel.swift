#if DEBUG

    import MemoBookCore
    import MemoBookDesign
    import SwiftUI

    /// Le bac à sable de la cagnotte : de quoi la remplir sans Stripe.
    ///
    /// **Il n'existe pas dans l'app livrée.** Le fichier entier est sous
    /// `#if DEBUG`, comme celui de l'accueil.
    ///
    /// C'est le panneau qu'on a demandé explicitement, et pour une bonne
    /// raison : l'écran de la cagnotte **pleine** ne se voit pas autrement.
    /// L'encaissement n'existe pas encore, donc sans ces boutons il n'y a aucun
    /// chemin depuis l'app vers un solde non nul — et c'est justement l'écran
    /// qui a le plus de choses à montrer (le vert du solde, la barre qui monte,
    /// les deux natures de pastille, les totaux).
    ///
    /// « + 10 € » ajoute une contribution **par-dessus ce qui est là**, comme
    /// un virement qui arriverait pendant qu'on regarde : c'est le seul moyen de
    /// vérifier que le solde s'anime chiffre par chiffre et que la ligne glisse
    /// bien par le haut de l'historique.
    struct WalletDebugPanel: View {
        let model: WalletModel

        var body: some View {
            VStack(alignment: .leading, spacing: MemoBookSpacing.xs) {
                Text("Bac à sable — absent de l’app livrée")
                    .font(MemoBookFont.caption)
                    .foregroundStyle(MemoBookColor.inkMuted)

                Text(
                    model.isSandboxLive
                        ? "Les contributions écrivent dans le registre du serveur : le prix d’une commande en tient compte."
                        : "Aperçu sans serveur : les contributions restent à l’écran."
                )
                .font(MemoBookFont.caption)
                .foregroundStyle(MemoBookColor.inkMuted)
                .fixedSize(horizontal: false, vertical: true)

                FlowLayout(spacing: MemoBookSpacing.xs) {
                    action("+ 1,99 € · abonnement") {
                        await model.debugContribute(1.99, from: "Abonnement MB", kind: .topup)
                    }
                    action("+ 9,95 € · 5 semaines") {
                        await model.debugContribute(9.95, from: "Abonnement MB", kind: .topup)
                    }

                    action("+ 10 € · Marie D.") {
                        await model.debugContribute(10, from: "Marie D.")
                    }
                    action("+ 20 € · Bruno Dupont") {
                        await model.debugContribute(20, from: "Bruno Dupont")
                    }
                    action("+ 50 € · Un proche") {
                        await model.debugContribute(50, from: "Un proche")
                    }

                    // Un débit, pour revenir en arrière sans repartir du seed :
                    // le registre est en ajout seul, on annule par l'inverse.
                    action("− 10 € · correction") {
                        await model.debugContribute(-10, from: "Correction", kind: .adjustment)
                    }

                    action("Cagnotte garnie (écran)", model.debugFill)
                    action("Cagnotte vide (écran)", model.debugEmpty)
                    action("Recharger") { await model.load() }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(MemoBookSpacing.s)
            .brandDashedCard(color: MemoBookColor.separator)
        }

        /// Les écritures partent au serveur : les boutons sont donc
        /// asynchrones, et le panneau les enveloppe une fois pour toutes.
        private func action(
            _ title: String,
            _ perform: @escaping () async -> Void
        ) -> some View {
            Button(title) { Task { await perform() } }
                .font(MemoBookFont.caption)
                .buttonStyle(.bordered)
                .tint(MemoBookColor.action)
        }

        private func action(_ title: String, _ perform: @escaping () -> Void) -> some View {
            Button(title, action: perform)
                .font(MemoBookFont.caption)
                .buttonStyle(.bordered)
                .tint(MemoBookColor.action)
        }
    }

#endif
