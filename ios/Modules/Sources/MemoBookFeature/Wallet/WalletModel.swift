import Foundation
import MemoBookCore
import Observation

/// Ce que l'écran de la cagnotte sait faire : la lire, et — en développement —
/// la remplir.
///
/// Comme ``ProfileModel``, il ne connaît pas l'API : il reçoit une
/// fonction-source. L'app lui branche `GET /v1/trips/:id/wallet` ; les aperçus
/// n'en fournissent aucune et travaillent sur le jeu d'essai.
///
/// **La cagnotte appartient au compte, pas au voyage** (voir ``Wallet``). Le
/// `tripId` ne sert donc qu'à une chose : savoir quel carnet on est en train de
/// financer, pour l'estimation de pages et de coût. La même somme s'affiche
/// depuis le profil, où il n'y a pas de voyage à nommer.
@MainActor
@Observable
public final class WalletModel {
    public private(set) var wallet: Wallet?
    public private(set) var errorMessage: String?

    /// Le voyage dont on regarde la cagnotte. `nil` quand on arrive du profil :
    /// l'écran parle alors du compte, pas d'un carnet.
    private let tripId: String?
    private let source: (String?) async throws -> Wallet

    /// L'encaissement. `nil` dans les previews Xcode, qui n'ont pas de serveur — et
    /// qui ne doivent pas pouvoir ouvrir Stripe.
    ///
    /// Rend la cagnotte relue une fois l'argent encaissé, ou **`nil` quand la
    /// personne a fermé la feuille**. Fermer n'est pas un échec : c'est un
    /// choix, et il ne mérite ni message d'erreur ni solde qui bouge.
    private let topUp: ((String?, Decimal) async throws -> Wallet?)?

    /// L'écriture de bac à sable, en développement seulement. `nil` dans les
    /// aperçus, qui n'ont pas de serveur à qui écrire.
    private let sandbox: ((Decimal, WalletEntryKind, String) async throws -> Decimal)?

    public init(
        tripId: String? = nil,
        source: @escaping (String?) async throws -> Wallet = { _ in .fixture },
        topUp: ((String?, Decimal) async throws -> Wallet?)? = nil,
        sandbox: ((Decimal, WalletEntryKind, String) async throws -> Decimal)? = nil
    ) {
        self.tripId = tripId
        self.source = source
        self.topUp = topUp
        self.sandbox = sandbox
    }

    /// `true` tant qu'on n'a pas de valeurs. L'écran se dessine quand même :
    /// son en-tête, sa carte, ses boutons et son explication appartiennent à
    /// l'app. Seuls le solde, la barre et l'historique portent une barre
    /// d'attente — voir ``BrandSkeleton``.
    public var isLoading: Bool { wallet == nil && errorMessage == nil }

    /// L'encaissement est branché. Vrai dans l'app, faux dans les previews Xcode.
    public var canTopUp: Bool { topUp != nil }

    public func load() async {
        do {
            wallet = try await source(tripId)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Recharge la cagnotte. Sans encaissement branché, dit pourquoi ce n'est
    /// pas possible plutôt que de ne rien faire.
    ///
    /// Une feuille fermée ne rapporte rien et n'affiche rien : `topUp` rend
    /// alors `nil`, et le solde reste celui qu'on lisait avant.
    public func addFunds(_ amount: Decimal) async {
        guard let topUp else {
            errorMessage = BookCopy.Wallet.addUnavailable
            return
        }

        do {
            if let credited = try await topUp(tripId, amount) {
                wallet = credited
            }
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    #if DEBUG
        /// Pose une cagnotte garnie **en mémoire**, sans serveur.
        ///
        /// ⚠️ Elle ne change que l'écran : le tunnel de commande demande ses
        /// déductions au serveur, qui n'en saura rien. Pour agir sur le prix
        /// d'une commande, c'est ``debugContribute(_:from:kind:)`` qu'il faut —
        /// elle écrit pour de vrai.
        func debugFill() {
            wallet = .filledFixture
            errorMessage = nil
        }

        /// La vide **à l'écran**, pour revoir « Cagnotte vide ». Même réserve
        /// que ci-dessus : le registre du serveur n'est pas touché.
        func debugEmpty() {
            wallet = .emptyFixture
            errorMessage = nil
        }

        /// Ajoute une contribution, **dans le registre du serveur**.
        ///
        /// C'est le bouton qui sert le plus, et il a changé de nature : il
        /// mutait un objet en mémoire, si bien que le solde montait à l'écran
        /// pendant que le serveur continuait d'ignorer la somme — et le
        /// récapitulatif de commande, qui lui demande au serveur, annonçait un
        /// total sans déduction. Il pose maintenant une vraie écriture, puis
        /// relit la cagnotte.
        ///
        /// Sans fonction d'écriture branchée — les aperçus SwiftUI —, il
        /// retombe sur une addition locale, qui suffit à voir l'animation.
        func debugContribute(
            _ amount: Decimal,
            from name: String,
            kind: WalletEntryKind = .gift
        ) async {
            guard let sandbox else {
                addLocally(amount, from: name, kind: kind)
                return
            }

            do {
                _ = try await sandbox(amount, kind, name)
                // On relit plutôt que d'additionner : le serveur fait autorité
                // sur le solde **et** sur l'ordre de l'historique.
                await load()
            } catch {
                errorMessage = error.localizedDescription
            }
        }

        private func addLocally(_ amount: Decimal, from name: String, kind: WalletEntryKind) {
            let current = wallet ?? .emptyFixture
            let entry = WalletEntry(
                id: UUID().uuidString,
                amount: amount,
                kind: kind,
                label: name,
                date: .now
            )

            wallet = Wallet(
                balance: current.balance + amount,
                // En tête de liste : l'historique va du plus récent au plus
                // ancien, et c'est le serveur qui ordonne en vrai.
                entries: [entry] + current.entries,
                tripTitle: current.tripTitle,
                estimate: current.estimate
            )
            errorMessage = nil
        }

        /// Le bac à sable écrit-il vraiment ? L'écran le dit, pour qu'on sache
        /// si ce qu'on ajoute comptera au moment de commander.
        var isSandboxLive: Bool { sandbox != nil }
    #endif
}
