import Foundation
import MemoBookCore

/// Le contrat que les écrans connaissent. Les modèles de vue en dépendent, pas
/// de l'implémentation : c'est ce qui permet de les piloter avec un double en
/// test et dans les aperçus SwiftUI.
public protocol MemoBookAPI: Sendable {
    /// Enregistre l'appareil si nécessaire et mémorise son token.
    func ensureDeviceRegistered() async throws

    // MARK: - Compte

    /// Une session est-elle déjà en trousseau ? Ne dit pas si elle est encore
    /// valide — seul le serveur le sait, via ``currentAccount()``.
    func hasStoredSession() async -> Bool

    func signUp(
        email: String,
        password: String,
        firstName: String?,
        lastName: String?
    ) async throws -> AuthSession

    func signIn(email: String, password: String) async throws -> AuthSession

    /// Échange un jeton d'identité Apple ou Google contre une session. Le
    /// serveur vérifie le jeton auprès du fournisseur avant de répondre.
    func signIn(with credential: SocialSignIn) async throws -> AuthSession

    /// Le compte de la session en cours. Sert aussi à savoir, au lancement, si
    /// la session gardée au trousseau vaut encore quelque chose.
    func currentAccount() async throws -> Account

    /// Ferme la session courante, et elle seule. Oublie le jeton local même si
    /// le serveur est injoignable : l'utilisateur a demandé à sortir.
    func signOut() async

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
