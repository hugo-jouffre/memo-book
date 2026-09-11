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

    /// L'encaissement : `nil` tant que Stripe n'est pas branché.
    ///
    /// C'est **la** différence entre « recharger » et les autres actions de
    /// l'écran : partager et inviter marchent déjà, ajouter de l'argent non.
    /// L'écran le lit pour le dire plutôt que d'ouvrir un écran vide.
    private let topUp: ((String?, Decimal) async throws -> Wallet)?

    public init(
        tripId: String? = nil,
        source: @escaping (String?) async throws -> Wallet = { _ in .fixture },
        topUp: ((String?, Decimal) async throws -> Wallet)? = nil
    ) {
        self.tripId = tripId
        self.source = source
        self.topUp = topUp
    }

    /// `true` tant qu'on n'a pas de valeurs. L'écran se dessine quand même :
    /// son en-tête, sa carte, ses boutons et son explication appartiennent à
    /// l'app. Seuls le solde, la barre et l'historique portent une barre
    /// d'attente — voir ``BrandSkeleton``.
    public var isLoading: Bool { wallet == nil && errorMessage == nil }

    /// L'encaissement est branché. Faux aujourd'hui : « Ajouter » le dit au
    /// lieu d'ouvrir un écran qui n'existe pas.
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
    public func addFunds(_ amount: Decimal) async {
        guard let topUp else {
            errorMessage = BookCopy.Wallet.addUnavailable
            return
        }

        do {
            wallet = try await topUp(tripId, amount)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    #if DEBUG
        /// Pose une cagnotte garnie, sans serveur ni Stripe. Absent de l'app
        /// livrée — voir ``WalletDebugPanel``.
        func debugFill() {
            wallet = .fixture
            errorMessage = nil
        }

        /// La vide, pour revoir l'écran « Cagnotte Vide ».
        func debugEmpty() {
            wallet = .emptyFixture
            errorMessage = nil
        }

        /// Ajoute une contribution **par-dessus ce qui est là**, comme un
        /// virement qui arriverait pendant qu'on regarde l'écran.
        ///
        /// C'est le bouton qui sert le plus : il montre l'animation du solde,
        /// celle de la barre, et l'arrivée d'une ligne dans l'historique — les
        /// trois choses qu'on ne peut pas vérifier sur un jeu d'essai figé.
        func debugContribute(_ amount: Decimal, from name: String, kind: WalletEntryKind = .gift) {
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
    #endif
}
