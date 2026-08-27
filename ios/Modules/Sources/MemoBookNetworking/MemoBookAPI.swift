import Foundation
import MemoBookCore

/// Le contrat que les écrans connaissent. Les modèles de vue en dépendent, pas
/// de l'implémentation : c'est ce qui permet de les piloter avec un double en
/// test et dans les aperçus SwiftUI.
public protocol MemoBookAPI: Sendable {
    /// Enregistre l'appareil si nécessaire et mémorise son token.
    func ensureDeviceRegistered() async throws

    // MARK: - Compte

    /// Le compte de la session en cours. Lève `APIError.notAuthenticated`
    /// quand aucune session n'est ouverte, et un 401 quand elle a expiré :
    /// c'est ce que le *Splash* interroge pour choisir sa destination.
    func currentAccount() async throws -> Account

    func signUp(_ account: NewAccount) async throws -> AuthenticatedSession
    func signIn(email: String, password: String) async throws -> AuthenticatedSession

    /// Ferme la session côté serveur et oublie le jeton. Ne lève pas : se
    /// déconnecter doit toujours aboutir, réseau ou pas.
    func signOut() async

    /// Ouvre le flow d'un fournisseur tiers. Renvoie soit une session, soit le
    /// profil à confirmer sur *Complète tes informations*.
    func signIn(with provider: SocialProvider, credential: String) async throws
        -> SocialSignInOutcome

    func completeSocialProfile(_ profile: CompletedSocialProfile) async throws
        -> AuthenticatedSession

    /// Demande l'envoi du lien de réinitialisation.
    /// Lève un `APIError.server(statusCode: 404, code: "not_found", …)` quand
    /// aucun compte n'est associé à l'adresse — c'est ce qui fait basculer sur
    /// *Mdp oublié - compte inexistant*.
    func requestPasswordReset(email: String) async throws

    /// Pose le nouveau mot de passe à partir du jeton porté par le deep link.
    func resetPassword(token: String, newPassword: String) async throws

    func memos() async throws -> [MemoSummary]
    func createMemo(_ memo: NewMemo) async throws -> Memo
    func memo(id: String) async throws -> MemoDetail
    func deleteMemo(id: String) async throws

    func addTextEntry(memoId: String, entry: NewTextEntry) async throws -> Entry

    func uploadAudio(
        memoId: String,
        data: Data,
        filename: String,
        mimeType: String,
        capturedAt: Date,
        placeLabel: String?
    ) async throws -> Entry

    func uploadPhoto(
        memoId: String,
        data: Data,
        filename: String,
        mimeType: String,
        capturedAt: Date,
        placeLabel: String?
    ) async throws -> Entry

    func entry(id: String) async throws -> Entry

    /// Corrige un souvenir à la main. Le texte corrigé fait ensuite autorité :
    /// la mise en page le reprend au mot près.
    func updateEntry(id: String, edit: EntryEdit) async throws -> Entry

    /// Redemande une rédaction — après un échec, ou quand le texte proposé ne
    /// convient pas. Refusée si le souvenir a été corrigé à la main.
    func retryRedaction(entryId: String) async throws -> Entry

    /// Lance la génération du carnet. Le résultat arrive de façon asynchrone :
    /// suivre ensuite avec `render(id:)`.
    func startRender(memoId: String) async throws -> Render
    func render(id: String) async throws -> Render

    /// Commande le carnet imprimé, sur un rendu déjà prévisualisé.
    func createPrintOrder(memoId: String, order: NewPrintOrder) async throws -> PrintOrder
    func printOrders(memoId: String) async throws -> [PrintOrder]
}
