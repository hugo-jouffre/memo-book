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

                FlowLayout(spacing: MemoBookSpacing.xs) {
                    action("Cagnotte garnie", model.debugFill)
                    action("Cagnotte vide", model.debugEmpty)

                    action("+ 10 € · Marie D.") {
                        model.debugContribute(10, from: "Marie D.")
                    }
                    action("+ 20 € · Bruno Dupont") {
                        model.debugContribute(20, from: "Bruno Dupont")
                    }
                    action("+ 50 € · Anonyme") {
                        model.debugContribute(50, from: "Un proche")
                    }
                    action("+ 1,99 € · abonnement") {
                        model.debugContribute(1.99, from: "Abonnement MB", kind: .topup)
                    }

                    action("Recharger") { Task { await model.load() } }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(MemoBookSpacing.s)
            .brandDashedCard(color: MemoBookColor.separator)
        }

        private func action(_ title: String, _ perform: @escaping () -> Void) -> some View {
            Button(title, action: perform)
                .font(MemoBookFont.caption)
                .buttonStyle(.bordered)
                .tint(MemoBookColor.action)
        }
    }

#endif
