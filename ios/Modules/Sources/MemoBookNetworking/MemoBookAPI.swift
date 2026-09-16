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

    /// Demande l'e-mail qui permet de choisir un nouveau mot de passe.
    ///
    /// Sans session : c'est précisément parce qu'on ne peut pas entrer qu'on
    /// l'appelle. Le serveur répond **la même chose** que l'adresse existe ou
    /// non — on ne renseigne pas un inconnu sur qui a un compte —, si bien que
    /// la réussite ici veut dire « si cette adresse est la tienne, regarde ta
    /// boîte », jamais « ce compte existe ».
    func requestPasswordReset(email: String) async throws

    /// Le nouveau mot de passe, avec le secret reçu par e-mail. Répond comme
    /// ``signIn(email:password:)`` : la session est ouverte, l'app entre.
    func resetPassword(token: String, password: String) async throws -> AuthSession

    // MARK: - Les écrans
    //
    // Une réponse par écran, et non une par bloc : l'accueil et le profil
    // s'affichent d'un seul tenant, et les découper ferait apparaître leurs
    // morceaux les uns après les autres au lancement.

    /// Tout ce qu'il faut pour dessiner l'accueil : le voyageur, ses voyages et
    /// ceux où il est co-voyageur, la carte de découverte.
    func homeFeed() async throws -> HomeFeed

    /// Un voyage ouvert : sa couverture, la relance et ses étapes.
    func tripDetail(id: String) async throws -> TripDetail

    /// Crée un voyage à partir des six étapes de « Créer un voyage ». Rend le
    /// voyage **et son code d'accès**, que la dernière étape affiche.
    func createTrip(_ draft: TripDraft) async throws -> CreatedTrip

    /// Corrige un voyage avec les mêmes six champs. Sert à la flèche de retour
    /// de la création : revenir sur les dates après avoir vu le code d'accès ne
    /// doit pas créer un second voyage.
    func updateTrip(id: String, draft: TripDraft) async throws -> CreatedTrip

    /// Les thèmes de « Contexte de ton voyage », dans l'ordre du serveur —
    /// « Autre » en dernier. Une table de référence, pas une liste dans l'app.
    func tripThemes() async throws -> [TripTheme]

    /// La galerie des carnets de la communauté : ses catégories, les carnets
    /// publics, et le voyage que celui qui regarde peut reprendre.
    func gallery() async throws -> Gallery

    /// Les carnets mis en avant sur l'écran de bienvenue. Seul appel du
    /// contrat qui ne demande **aucune** identification : cet écran s'affiche
    /// avant l'entrée dans un compte.
    func welcomeShowcases() async throws -> [Showcase]

    func profile() async throws -> TravellerProfile

    /// Corrige le profil. Renvoie la version enregistrée par le serveur, qui
    /// fait ensuite autorité sur ce que l'écran affiche.
    func updateProfile(_ edit: ProfileEdit) async throws -> TravellerProfile

    /// Branche ou débranche un connecteur.
    func setConnector(key: String, isEnabled: Bool) async throws

    /// Rattache l'appareil courant au compte connecté. À appeler juste après
    /// une connexion.
    ///
    /// Il n'y a rien à transférer au passage : un carnet naît avec son
    /// propriétaire, et l'appareil n'en possède aucun. Ce lien dit seulement sur
    /// quelles installations le compte est ouvert.
    func linkCurrentDevice() async throws

    /// Supprime le compte et **tout** ce qui est à lui : ses carnets, leurs
    /// souvenirs et leurs médias, ses commandes, sa cagnotte, ses moyens de
    /// paiement, ses connecteurs et ses appareils.
    ///
    /// Définitif et sans retour. **Un voyage partagé, lui, n'est pas supprimé :
    /// il passe à son co-voyageur le plus ancien** — un récit écrit à plusieurs
    /// ne s'efface pas parce que l'un s'en va. Seuls partent les voyages dont
    /// personne d'autre ne fait partie. L'écran qui l'appelle doit avoir
    /// demandé confirmation.
    func deleteAccount() async throws

    // MARK: - Carnets

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

    /// Tout ce que le tunnel de commande a besoin de savoir pour s'ouvrir :
    /// la carte du voyage, la cagnotte, les prix, l'adresse proposée et les
    /// moyens de paiement.
    ///
    /// **Une réponse pour les sept étapes.** Le parcours est une seule
    /// destination, et le découper ferait apparaître une attente à chaque
    /// « Continuer ».
    func orderContext(memoId: String) async throws -> OrderContext

    /// Le récapitulatif de l'étape 5, compté **par le serveur**. L'app
    /// n'additionne aucun montant : deux calculs finissent par diverger, et
    /// c'est le client qui a tort devant la personne qui paie.
    func orderQuote(
        memoId: String,
        copies: Int,
        shippingSpeed: ShippingSpeed
    ) async throws -> OrderQuote

    /// La cagnotte du compte : son solde, son historique, et l'estimation du
    /// carnet qu'on finance.
    ///
    /// `tripId` ne dit pas *quelle* cagnotte — il n'y en a qu'une par compte —
    /// mais **quel carnet on finance**, pour l'estimation de pages et de coût.
    /// `nil` quand on arrive du profil.
    func wallet(tripId: String?) async throws -> Wallet

    /// Pose une écriture de cagnotte à la main. **Réservée au développement** :
    /// le serveur ferme la route en production.
    ///
    /// Elle existe parce que sans encaissement branché, il n'y a aucun chemin
    /// depuis l'app vers un solde non nul — donc aucun moyen de voir les
    /// déductions du tunnel de commande, que le serveur calcule.
    func addWalletSandboxEntry(
        amount: Decimal,
        kind: WalletEntryKind,
        label: String
    ) async throws -> Decimal

    /// Accepte — ou refuse — d'être prévenu par WhatsApp de l'acheminement.
    /// Le numéro remonte sur le compte quand celui-ci n'en a pas encore.
    func setOrderWhatsApp(
        orderId: String,
        phone: String?
    ) async throws -> PrintOrder

    /// Le lien public de prévisualisation du carnet, créé au premier appel et
    /// rendu tel quel ensuite.
    ///
    /// **Idempotente côté serveur** : repartager deux fois ne donne pas deux
    /// liens, et celui qu'on a envoyé hier marche encore aujourd'hui — un lien
    /// parti dans une conversation ne se rattrape pas.
    func bookShareLink(memoId: String) async throws -> URL

    /// Commande le carnet imprimé, sur un rendu déjà prévisualisé.
    ///
    /// **N'encaisse rien.** Elle enregistre la commande en brouillon et rend,
    /// à côté, de quoi la régler — voir ``PlacedPrintOrder``. Le passage en
    /// `submitted` viendra du webhook de Stripe, jamais de l'app : entre le
    /// moment où la feuille se ferme et celui où elle rappellerait le serveur,
    /// l'app peut être tuée, et le paiement n'en aurait pas moins eu lieu.
    func createPrintOrder(
        memoId: String,
        order: NewPrintOrderRequest
    ) async throws -> PlacedPrintOrder

    /// Relit une commande, pour savoir ce que le serveur en dit **maintenant**.
    ///
    /// C'est la lecture qui suit un paiement : la feuille qui rend
    /// `.succeeded` dit que Stripe a accepté, pas que notre serveur l'a appris.
    func printOrder(id: String) async throws -> PrintOrder

    func printOrders(memoId: String) async throws -> [PrintOrder]

    /// Ouvre une recharge de cagnotte.
    ///
    /// **Ne crédite rien.** Elle rend de quoi présenter une feuille de
    /// paiement ; le solde ne bougera qu'une fois l'argent encaissé, sur retour
    /// de Stripe au serveur. D'où le fait qu'elle rende un ticket et non une
    /// ``Wallet`` : l'appelant doit relire la cagnotte après le paiement.
    func startWalletTopUp(amountCents: Int) async throws -> PaymentIntentTicket

    // MARK: - Les réglages d'un voyage

    /// Les réglages d'un voyage : nom, dates, rythme, alertes, co-voyageurs,
    /// solde, code d'accès — **et les personnalisations du carnet**.
    ///
    /// Tout arrive en une réponse parce que l'écran les affiche ensemble : sept
    /// appels feraient apparaître ses lignes une à une. Les personnalisations
    /// voyagent avec, parce qu'il y en a un jeu par voyage et qu'aucune requête
    /// ne les interroge seules.
    func tripSettings(id: String) async throws -> TripSettings

    /// Change **un** réglage, et relit tout.
    ///
    /// Un à la fois, et non la structure entière : un co-voyageur peut régler le
    /// même voyage au même moment, et renvoyer l'objet complet écraserait ce
    /// qu'il vient de poser. La réponse est le voyage relu, ce que l'écran garde
    /// à l'affichage.
    func updateTripSettings(id: String, edit: TripSettingsEdit) async throws -> TripSettings

    /// Change une personnalisation du carnet. Même route, même règle.
    func updateBookCustomisation(
        tripId: String,
        edit: BookCustomisationEdit
    ) async throws -> TripSettings

    /// Retire un co-voyageur du voyage, et relit les réglages.
    ///
    /// **Le propriétaire ne se retire pas** : le serveur refuse, et l'app ne le
    /// propose pas. Les souvenirs de la personne retirée restent dans le
    /// carnet — ils appartiennent au récit.
    func removeCompanion(tripId: String, companionId: String) async throws -> TripSettings

    /// Renvoie son lien d'invitation à quelqu'un qui n'est jamais entré.
    func resendInvitation(tripId: String, companionId: String) async throws
}
