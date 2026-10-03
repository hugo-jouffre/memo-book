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

        /// Ce qu'un achat ou une résiliation ont imposé à la session. Le panneau
        /// ne s'en sert que pour l'**effacer** : c'est ``SandboxPersona`` qui
        /// fait jouer l'abonnement aux écrans, et un geste resté dans la
        /// session prendrait le pas sur lui.
        @Environment(\.subscriptionSession) private var session

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

                    action("Devenir un abonné") { play(model.debugBecomeSubscriber) }
                    action("Sans abonnement") { play(model.debugBecomeFree) }
                    // La découverte en trois écrans : il faut oublier aussi
                    // que la session a déjà vu un abonné — elle ne l'oublie
                    // d'elle-même qu'en changeant de compte.
                    action("Jamais abonné") {
                        session?.reset()
                        model.debugBecomeNeverSubscribed()
                    }
                    // Le crédit du jour du voyage, servi par le double d'API au
                    // fil de la conversation, à ses reçus, aux réglages et à
                    // l'accueil — voir ``SandboxCredit``.
                    ForEach(SandboxCredit.Preset.allCases, id: \.self) { preset in
                        action(preset.label) { play { model.debugPlayCredit(preset) } }
                    }
                    action("Erreur", model.debugShowError)

                    // Le hors-ligne coupe **vraiment** le réseau de l'app, et le
                    // vocal mis en file part **vraiment** sur le disque : c'est
                    // le seul moyen de vérifier que la promesse écrite dans la
                    // boîte est tenue. Les deux derniers, eux, ne font que poser
                    // un état passager qu'on n'aurait sinon le temps de voir
                    // qu'avec un très mauvais réseau.
                    action(model.isOffline ? "Repasser en ligne" : "Passer hors ligne", model.debugToggleOffline)
                    action("+ vocal en attente") { Task { await model.debugQueueRecording() } }
                    action("Envoi en cours", model.debugShowSending)
                    action("Vocal envoyé", model.debugShowDelivered)

                    action("Jeu d’essai") {
                        session?.play(isUnlimited: nil)
                        model.debugReset()
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(MemoBookSpacing.s)
            .brandDashedCard(color: MemoBookColor.separator)
        }

        /// Fait jouer un personnage — et **efface d'abord ce que la session
        /// impose**. Sans ça, un achat ou une résiliation faits plus tôt
        /// primaient sur le personnage (voir ``SubscriptionSession/isUnlimited``),
        /// et les boutons du bac à sable n'avaient plus l'air de marcher.
        private func play(_ persona: () -> Void) {
            session?.play(isUnlimited: nil)
            persona()
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

#endif
