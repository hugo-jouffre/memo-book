import Foundation
import MemoBookCore

/// Implémentation HTTP du contrat `MemoBookAPI`.
public actor MemoBookAPIClient: MemoBookAPI {
    private let configuration: APIConfiguration
    private let session: URLSession
    private let tokenStore: any TokenStore
    private let sessionStore: any TokenStore
    private let decoder = JSONDecoder.memoBook
    private let encoder = JSONEncoder.memoBook

    /// Qui parle.
    ///
    /// **La session de compte, pour tout ce qui appartient à quelqu'un.** Le
    /// jeton d'appareil n'ouvre plus rien : depuis qu'un carnet a toujours un
    /// propriétaire, et que ce propriétaire est un compte, il ne sert qu'à
    /// s'enregistrer et à se rattacher — et il voyage alors dans le corps de la
    /// requête, pas dans son en-tête.
    private enum Credential {
        case none
        case session
    }

    /// Enregistrement en cours, partagé : deux écrans qui démarrent en même
    /// temps ne doivent pas créer deux appareils.
    private var registrationTask: Task<Void, any Error>?

    /// L'adresse à laquelle les requêtes partent **en ce moment** : la
    /// configurée, jusqu'à ce qu'elle refuse la connexion et qu'un secours
    /// existe — voir ``rebasedOnFallback(_:after:)``. Une bascule tient pour
    /// toute la session du client.
    private var activeBaseURL: URL

    public init(
        configuration: APIConfiguration = .localDevelopment,
        session: URLSession = .shared,
        tokenStore: any TokenStore = KeychainTokenStore(),
        sessionStore: any TokenStore = KeychainTokenStore(account: "session-token")
    ) {
        self.configuration = configuration
        self.session = session
        self.tokenStore = tokenStore
        self.sessionStore = sessionStore
        self.activeBaseURL = configuration.baseURL
    }

    // MARK: - Identité

    public func ensureDeviceRegistered() async throws {
        if tokenStore.read() != nil { return }

        if let registrationTask {
            return try await registrationTask.value
        }

        let task = Task<Void, any Error> { [tokenStore] in
            let registration: DeviceRegistration = try await self.send(
                method: "POST",
                path: "/v1/devices",
                body: ["platform": "ios"],
                credential: .none
            )
            tokenStore.write(registration.token)
        }

        registrationTask = task
        defer { registrationTask = nil }
        try await task.value
    }

    // MARK: - Compte

    public func hasStoredSession() -> Bool {
        sessionStore.read() != nil
    }

    public func signUp(
        email: String,
        password: String,
        firstName: String?,
        lastName: String?
    ) async throws -> AuthSession {
        var body = ["email": email, "password": password]
        // Champs facultatifs : les envoyer vides ferait échouer la validation
        // du serveur, qui exige au moins un caractère quand ils sont présents.
        if let firstName, !firstName.isEmpty { body["firstName"] = firstName }
        if let lastName, !lastName.isEmpty { body["lastName"] = lastName }
        return try await openSession(path: "/v1/auth/signup", body: body)
    }

    public func signIn(email: String, password: String) async throws -> AuthSession {
        try await openSession(
            path: "/v1/auth/signin",
            body: ["email": email, "password": password]
        )
    }

    public func signIn(with credential: SocialSignIn) async throws -> AuthSession {
        var body = ["identityToken": credential.identityToken]
        if let nonce = credential.nonce { body["nonce"] = nonce }
        if let firstName = credential.firstName, !firstName.isEmpty {
            body["firstName"] = firstName
        }
        if let lastName = credential.lastName, !lastName.isEmpty {
            body["lastName"] = lastName
        }
        return try await openSession(
            path: "/v1/auth/\(credential.provider.rawValue)",
            body: body
        )
    }

    public func currentAccount() async throws -> Account {
        struct Response: Decodable { let account: Account }
        let response: Response = try await send(
            method: "GET",
            path: "/v1/auth/me",
            credential: .session
        )
        return response.account
    }

    public func signOut() async {
        // Le trousseau est vidé quoi qu'il arrive : quelqu'un qui se déconnecte
        // dans un train sans réseau ne doit pas rester connecté sur son écran.
        // La session côté serveur expirera d'elle-même.
        defer { sessionStore.clear() }
        try? await sendIgnoringResponse(
            method: "POST",
            path: "/v1/auth/signout",
            credential: .session
        )
    }

    public func requestPasswordReset(email: String) async throws {
        try await sendIgnoringResponse(
            method: "POST",
            path: "/v1/auth/password/forgot",
            body: ["email": email],
            credential: .none
        )
    }

    public func resetPassword(token: String, password: String) async throws -> AuthSession {
        try await openSession(
            path: "/v1/auth/password/reset",
            body: ["token": token, "password": password]
        )
    }

    private func openSession(path: String, body: [String: String]) async throws -> AuthSession {
        let session: AuthSession = try await send(
            method: "POST",
            path: path,
            body: body,
            credential: .none
        )
        sessionStore.write(session.token)
        return session
    }

    // MARK: - Les écrans

    public func homeFeed() async throws -> HomeFeed {
        try await send(method: "GET", path: "/v1/home", credential: .session)
    }

    public func tripDetail(id: String) async throws -> TripDetail {
        try await send(method: "GET", path: "/v1/trips/\(id)", credential: .session)
    }

    public func createTrip(_ draft: TripDraft) async throws -> CreatedTrip {
        try await send(method: "POST", path: "/v1/trips", encodableBody: draft, credential: .session)
    }

    public func updateTrip(id: String, draft: TripDraft) async throws -> CreatedTrip {
        try await send(
            method: "PATCH",
            path: "/v1/trips/\(id)",
            encodableBody: draft,
            credential: .session
        )
    }

    public func tripThemes() async throws -> [TripTheme] {
        let response: TripThemes = try await send(method: "GET", path: "/v1/trip-themes", credential: .session)
        return response.themes
    }

    public func gallery() async throws -> Gallery {
        try await send(method: "GET", path: "/v1/gallery", credential: .session)
    }

    public func welcomeShowcases() async throws -> [Showcase] {
        struct Response: Decodable { let showcases: [Showcase] }
        let response: Response = try await send(
            method: "GET",
            path: "/v1/showcases/welcome",
            credential: .none
        )
        return response.showcases
    }

    public func profile() async throws -> TravellerProfile {
        try await send(method: "GET", path: "/v1/profile", credential: .session)
    }

    public func updateProfile(_ edit: ProfileEdit) async throws -> TravellerProfile {
        try await send(
            method: "PATCH",
            path: "/v1/profile",
            encodableBody: edit,
            credential: .session
        )
    }

    public func setConnector(key: String, isEnabled: Bool) async throws {
        struct Body: Encodable { let isEnabled: Bool }
        struct Response: Decodable { let key: String }
        let _: Response = try await send(
            method: "PUT",
            path: "/v1/profile/connectors/\(key)",
            encodableBody: Body(isEnabled: isEnabled),
            credential: .session
        )
    }

    public func linkCurrentDevice() async throws {
        // Les deux jetons dans la même requête, et c'est voulu : celui du
        // compte dans l'en-tête prouve qui reçoit, celui de l'appareil dans le
        // corps prouve ce qui est rattaché.
        try await ensureDeviceRegistered()
        guard let deviceToken = tokenStore.read() else { throw APIError.notAuthenticated }

        struct Body: Encodable { let deviceToken: String }
        struct Response: Decodable { let deviceId: String }

        let _: Response = try await send(
            method: "POST",
            path: "/v1/profile/link-device",
            encodableBody: Body(deviceToken: deviceToken),
            credential: .session
        )
    }

    public func deleteAccount() async throws {
        try await sendIgnoringResponse(
            method: "DELETE",
            path: "/v1/accounts/me",
            credential: .session
        )

        // Les deux jetons partent, et pas seulement celui de la session : le
        // compte n'existe plus, et son appareil a disparu avec lui côté
        // serveur. Garder un jeton d'appareil périmé, ce serait rendre l'app
        // muette au prochain lancement, avec des 401 qu'elle ne saurait pas
        // expliquer.
        sessionStore.clear()
        tokenStore.clear()
    }

    // MARK: - Carnets

    public func memos() async throws -> [MemoSummary] {
        struct Response: Decodable { let memos: [MemoSummary] }
        let response: Response = try await send(method: "GET", path: "/v1/memos")
        return response.memos
    }

    public func createMemo(_ memo: NewMemo) async throws -> Memo {
        try await send(method: "POST", path: "/v1/memos", encodableBody: memo)
    }

    public func memo(id: String) async throws -> MemoDetail {
        try await send(method: "GET", path: "/v1/memos/\(id)")
    }

    public func deleteMemo(id: String) async throws {
        try await sendIgnoringResponse(method: "DELETE", path: "/v1/memos/\(id)")
    }

    // MARK: - Souvenirs

    public func addTextEntry(memoId: String, entry: NewTextEntry) async throws -> Entry {
        try await send(
            method: "POST",
            path: "/v1/memos/\(memoId)/entries",
            encodableBody: entry
        )
    }

    public func uploadAudio(
        memoId: String,
        data: Data,
        filename: String,
        mimeType: String,
        capturedAt: Date,
        placeLabel: String?
    ) async throws -> Entry {
        try await uploadMedia(
            memoId: memoId,
            data: data,
            filename: filename,
            mimeType: mimeType,
            capturedAt: capturedAt,
            placeLabel: placeLabel
        )
    }

    public func uploadPhoto(
        memoId: String,
        data: Data,
        filename: String,
        mimeType: String,
        capturedAt: Date,
        placeLabel: String?
    ) async throws -> Entry {
        try await uploadMedia(
            memoId: memoId,
            data: data,
            filename: filename,
            mimeType: mimeType,
            capturedAt: capturedAt,
            placeLabel: placeLabel
        )
    }

    private func uploadMedia(
        memoId: String,
        data: Data,
        filename: String,
        mimeType: String,
        capturedAt: Date,
        placeLabel: String?
    ) async throws -> Entry {
        var form = MultipartFormData()
        form.addField(name: "capturedAt", value: ISO8601DateFormatter.memoBookString(from: capturedAt))
        if let placeLabel {
            form.addField(name: "placeLabel", value: placeLabel)
        }
        form.addFile(name: "file", filename: filename, mimeType: mimeType, data: data)

        let contentType = form.contentType
        var request = try makeRequest(method: "POST", path: "/v1/memos/\(memoId)/entries")
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        request.httpBody = form.finalized()

        return try await perform(request, credential: .session)
    }

    public func entry(id: String) async throws -> Entry {
        try await send(method: "GET", path: "/v1/entries/\(id)")
    }

    public func updateEntry(id: String, edit: EntryEdit) async throws -> Entry {
        try await send(method: "PATCH", path: "/v1/entries/\(id)", encodableBody: edit)
    }

    public func retryRedaction(entryId: String) async throws -> Entry {
        try await send(method: "POST", path: "/v1/entries/\(entryId)/redaction")
    }

    // MARK: - Génération

    public func startRender(memoId: String) async throws -> Render {
        try await send(method: "POST", path: "/v1/memos/\(memoId)/renders")
    }

    public func render(id: String) async throws -> Render {
        try await send(method: "GET", path: "/v1/renders/\(id)")
    }

    // MARK: - Impression

    public func orderContext(memoId: String) async throws -> OrderContext {
        try await send(method: "GET", path: "/v1/memos/\(memoId)/order-context")
    }

    public func orderQuote(
        memoId: String,
        copies: Int,
        shippingSpeed: ShippingSpeed
    ) async throws -> OrderQuote {
        struct Body: Encodable {
            let copies: Int
            let shippingSpeed: ShippingSpeed
        }
        return try await send(
            method: "POST",
            path: "/v1/memos/\(memoId)/orders/quote",
            encodableBody: Body(copies: copies, shippingSpeed: shippingSpeed)
        )
    }

    public func wallet(tripId: String?) async throws -> Wallet {
        let path = tripId.map { "/v1/wallet?tripId=\($0)" } ?? "/v1/wallet"
        return try await send(method: "GET", path: path)
    }

    public func addWalletSandboxEntry(
        amount: Decimal,
        kind: WalletEntryKind,
        label: String
    ) async throws -> Decimal {
        struct Body: Encodable {
            let amount: Decimal
            let kind: String
            let label: String
        }
        struct Response: Decodable { let balance: Decimal }

        let response: Response = try await send(
            method: "POST",
            path: "/v1/wallet/debug-entry",
            encodableBody: Body(amount: amount, kind: kind.rawValue, label: label)
        )
        return response.balance
    }

    public func setOrderWhatsApp(orderId: String, phone: String?) async throws -> PrintOrder {
        // Le corps porte **l'accord et le numéro ensemble** : le serveur refuse
        // l'un sans l'autre, et les séparer côté client laisserait composer une
        // requête qu'il rejettera.
        struct Enabled: Encodable {
            let enabled = true
            let phone: String
        }
        struct Disabled: Encodable {
            let enabled = false
        }

        if let phone {
            return try await send(
                method: "POST",
                path: "/v1/orders/\(orderId)/whatsapp",
                encodableBody: Enabled(phone: phone)
            )
        }
        return try await send(
            method: "POST",
            path: "/v1/orders/\(orderId)/whatsapp",
            encodableBody: Disabled()
        )
    }

    public func bookShareLink(memoId: String) async throws -> URL {
        struct Response: Decodable { let url: URL }
        let response: Response = try await send(
            method: "POST",
            path: "/v1/memos/\(memoId)/share-link"
        )
        return response.url
    }

    public func createPrintOrder(
        memoId: String,
        order: NewPrintOrderRequest
    ) async throws -> PlacedPrintOrder {
        try await send(
            method: "POST",
            path: "/v1/memos/\(memoId)/orders",
            encodableBody: order
        )
    }

    public func printOrder(id: String) async throws -> PrintOrder {
        try await send(method: "GET", path: "/v1/orders/\(id)")
    }



    // MARK: - Les réglages d'un voyage

    public func tripSettings(id: String) async throws -> TripSettings {
        try await send(method: "GET", path: "/v1/trips/\(id)/settings")
    }

    public func updateTripSettings(id: String, edit: TripSettingsEdit) async throws -> TripSettings {
        try await send(
            method: "PATCH",
            path: "/v1/trips/\(id)/settings",
            encodableBody: TripSettingsPatch(edit)
        )
    }

    public func updateBookCustomisation(
        tripId: String,
        edit: BookCustomisationEdit
    ) async throws -> TripSettings {
        try await send(
            method: "PATCH",
            path: "/v1/trips/\(tripId)/settings",
            encodableBody: TripSettingsPatch(edit)
        )
    }

    public func removeCompanion(tripId: String, companionId: String) async throws -> TripSettings {
        try await send(method: "DELETE", path: "/v1/trips/\(tripId)/members/\(companionId)")
    }

    public func resendInvitation(tripId: String, companionId: String) async throws {
        try await sendIgnoringResponse(
            method: "POST",
            path: "/v1/trips/\(tripId)/members/\(companionId)/invitation"
        )
    }

    /// Le corps du `PATCH` des réglages : **un seul champ rempli à la fois**.
    ///
    /// Tous optionnels, et l'encodeur ne pose que ceux qui valent quelque chose
    /// (`encodeIfPresent`) : le serveur ne touche qu'aux champs présents, et
    /// n'efface que ceux posés explicitement à `null`. C'est ce qui distingue
    /// « je n'ai pas parlé de la date de fin » de « il n'y a plus de date de
    /// fin » — et c'est pour ça que les dates portent, en plus, leur propre
    /// drapeau de présence.
    private struct TripSettingsPatch: Encodable {
        var name: String?
        var startDate: Date?
        var endDate: Date?
        var editsDates = false
        var narrationPace: String?
        var notificationsEnabled: Bool?
        var notifications: TripNotificationPreferences?
        var theme: String?
        var isPublicGallery: Bool?

        var photoTextRatio: Int?
        var targetPageCount: Int?
        var funFactsEnabled: Bool?
        var rulesEnabled: Bool?
        var decorationQuota: Int?
        var fontDisplay: String?
        var fontTitle: String?
        var fontHand: String?
        var fontFacts: String?
        var quizEnabled: Bool?
        var freeZonesEnabled: Bool?
        var crosswordEnabled: Bool?

        init(_ edit: TripSettingsEdit) {
            switch edit {
            case .name(let value): name = value
            case .dates(let start, let end):
                startDate = start
                endDate = end
                editsDates = true
            case .narrationPace(let pace): narrationPace = pace.rawValue
            case .notifications(let isOn): notificationsEnabled = isOn
            case .notificationPreferences(let preferences): notifications = preferences
            case .theme(let value): theme = value
            case .publicGallery(let isOn): isPublicGallery = isOn
            }
        }

        init(_ edit: BookCustomisationEdit) {
            switch edit {
            case .photoTextRatio(let value): photoTextRatio = value
            case .targetPageCount(let value): targetPageCount = value
            case .funFacts(let isOn): funFactsEnabled = isOn
            case .rules(let isOn): rulesEnabled = isOn
            case .decorationQuota(let value): decorationQuota = value
            case .fontDisplay(let value): fontDisplay = value
            case .fontTitle(let value): fontTitle = value
            case .fontHand(let value): fontHand = value
            case .fontFacts(let value): fontFacts = value
            case .quiz(let isOn): quizEnabled = isOn
            case .freeZones(let isOn): freeZonesEnabled = isOn
            case .crossword(let isOn): crosswordEnabled = isOn
            }
        }

        private enum CodingKeys: String, CodingKey {
            case name, startDate, endDate, narrationPace, notificationsEnabled, notifications
            case theme, isPublicGallery
            case photoTextRatio, targetPageCount, funFactsEnabled, rulesEnabled, decorationQuota
            case fontDisplay, fontTitle, fontHand, fontFacts
            case quizEnabled, freeZonesEnabled, crosswordEnabled
        }

        func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encodeIfPresent(name, forKey: .name)
            // Les deux dates s'écrivent **ensemble ou pas du tout**, `null`
            // compris : effacer une date de fin, c'est envoyer `endDate: null`,
            // et `encodeIfPresent` ne l'écrirait jamais.
            if editsDates {
                try container.encode(startDate, forKey: .startDate)
                try container.encode(endDate, forKey: .endDate)
            }
            try container.encodeIfPresent(narrationPace, forKey: .narrationPace)
            try container.encodeIfPresent(notificationsEnabled, forKey: .notificationsEnabled)
            try container.encodeIfPresent(notifications, forKey: .notifications)
            try container.encodeIfPresent(theme, forKey: .theme)
            try container.encodeIfPresent(isPublicGallery, forKey: .isPublicGallery)
            try container.encodeIfPresent(photoTextRatio, forKey: .photoTextRatio)
            try container.encodeIfPresent(targetPageCount, forKey: .targetPageCount)
            try container.encodeIfPresent(funFactsEnabled, forKey: .funFactsEnabled)
            try container.encodeIfPresent(rulesEnabled, forKey: .rulesEnabled)
            try container.encodeIfPresent(decorationQuota, forKey: .decorationQuota)
            try container.encodeIfPresent(fontDisplay, forKey: .fontDisplay)
            try container.encodeIfPresent(fontTitle, forKey: .fontTitle)
            try container.encodeIfPresent(fontHand, forKey: .fontHand)
            try container.encodeIfPresent(fontFacts, forKey: .fontFacts)
            try container.encodeIfPresent(quizEnabled, forKey: .quizEnabled)
            try container.encodeIfPresent(freeZonesEnabled, forKey: .freeZonesEnabled)
            try container.encodeIfPresent(crosswordEnabled, forKey: .crosswordEnabled)
        }
    }

    /// Le corps de la recharge. Une structure locale plutôt qu'un dictionnaire :
    /// `send(method:path:body:)` ne prend que des `String`, et un montant est un
    /// entier de centimes — le passer en texte le rendrait arrondissable.
    private struct TopUpBody: Encodable {
        let amountCents: Int
    }

    public func startWalletTopUp(amountCents: Int) async throws -> PaymentIntentTicket {
        try await send(
            method: "POST",
            path: "/v1/wallet/topup",
            encodableBody: TopUpBody(amountCents: amountCents)
        )
    }

    public func printOrders(memoId: String) async throws -> [PrintOrder] {
        struct Response: Decodable { let orders: [PrintOrder] }
        let response: Response = try await send(method: "GET", path: "/v1/memos/\(memoId)/orders")
        return response.orders
    }

    // MARK: - Transport

    /// Le magasin qui porte un type de jeton donné, ou `nil` pour un appel qui
    /// n'en présente aucun.
    private func store(for credential: Credential) -> (any TokenStore)? {
        switch credential {
        case .none: nil
        case .session: sessionStore
        }
    }

    private func makeRequest(
        method: String,
        path: String,
        credential: Credential = .session
    ) throws -> URLRequest {
        guard let url = URL(string: path, relativeTo: activeBaseURL) else {
            throw APIError.server(statusCode: 0, code: nil, message: "Chemin d'API invalide : \(path)")
        }

        var request = URLRequest(url: url, timeoutInterval: configuration.timeout)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        if let store = store(for: credential) {
            guard let token = store.read() else { throw APIError.notAuthenticated }
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        return request
    }

    private func send<Response: Decodable>(
        method: String,
        path: String,
        body: [String: String]? = nil,
        credential: Credential = .session
    ) async throws -> Response {
        var request = try makeRequest(method: method, path: path, credential: credential)

        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }

        return try await perform(request, credential: credential)
    }

    private func send<Body: Encodable, Response: Decodable>(
        method: String,
        path: String,
        encodableBody: Body,
        credential: Credential = .session
    ) async throws -> Response {
        var request = try makeRequest(method: method, path: path, credential: credential)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(encodableBody)
        return try await perform(request, credential: credential)
    }

    private func sendIgnoringResponse(
        method: String,
        path: String,
        body: [String: String]? = nil,
        credential: Credential = .session
    ) async throws {
        var request = try makeRequest(method: method, path: path, credential: credential)

        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }

        _ = try await performRaw(request, credential: credential)
    }

    private func perform<Response: Decodable>(
        _ request: URLRequest,
        credential: Credential
    ) async throws -> Response {
        let data = try await performRaw(request, credential: credential)
        do {
            return try decoder.decode(Response.self, from: data)
        } catch {
            throw APIError.decoding(error)
        }
    }

    /// Exécute la requête et traduit tout ce qui n'est pas un 2xx en `APIError`.
    private func performRaw(
        _ request: URLRequest,
        credential: Credential
    ) async throws -> Data {
        let data: Data
        let response: URLResponse

        #if DEBUG
            let started = NetworkLog.start(request)
        #endif

        do {
            (data, response) = try await session.data(for: request)
        } catch {
            #if DEBUG
                NetworkLog.fail(request, error: error, since: started)
            #endif
            // Porte close sur l'adresse configurée, et un secours : on y
            // bascule et on rejoue **la même** requête, une fois. Le secours
            // qui échoue à son tour remonte son erreur comme n'importe quelle
            // autre.
            if let retried = rebasedOnFallback(request, after: error) {
                #if DEBUG
                    NetworkLog.fallback(from: request.url, to: retried.url)
                #endif
                return try await performRaw(retried, credential: credential)
            }
            throw APIError.transport(error, url: request.url)
        }

        guard let http = response as? HTTPURLResponse else {
            throw APIError.server(statusCode: 0, code: nil, message: "Réponse non HTTP.")
        }

        #if DEBUG
            NetworkLog.finish(request, statusCode: http.statusCode, since: started)
        #endif

        guard (200..<300).contains(http.statusCode) else {
            let body = try? JSONDecoder().decode(APIErrorBody.self, from: data)

            // Un jeton refusé ne vaudra pas mieux au prochain essai : on efface
            // celui qui a été présenté.
            if http.statusCode == 401 {
                store(for: credential)?.clear()
            }

            throw APIError.server(
                statusCode: http.statusCode,
                code: body?.error,
                message: body?.message ?? "Le serveur a répondu \(http.statusCode)."
            )
        }

        return data
    }

    /// La même requête, réécrite sur l'adresse de secours — ou `nil` quand il
    /// n'y a pas lieu de basculer.
    ///
    /// **Le simulateur, et lui seul, a un secours** : c'est là que la
    /// configuration vise `localhost` avec la production derrière
    /// (``APIConfiguration/effective(configured:productionFallback:runsInSimulator:)``).
    /// Le premier appel qui trouve porte close — connexion refusée, hôte
    /// introuvable — bascule le client entier sur le secours pour la durée de
    /// la session ; les suivants y vont tout droit. « Testing mode » marche
    /// donc que le back-end du Mac tourne ou non (Hugo, 16/09/2026).
    ///
    /// Un délai dépassé ne bascule pas : un serveur local qui rame n'est pas un
    /// serveur absent, et changer d'avis au bout de soixante secondes serait
    /// pire que l'erreur. Et on ne bascule qu'une fois : une adresse de secours
    /// qui refuse aussi ne fait pas repartir vers la première.
    private func rebasedOnFallback(_ request: URLRequest, after error: any Error) -> URLRequest? {
        guard
            let fallback = configuration.fallbackBaseURL,
            activeBaseURL == configuration.baseURL,
            let code = (error as? URLError)?.code,
            code == .cannotConnectToHost || code == .cannotFindHost,
            let url = request.url,
            var components = URLComponents(url: url, resolvingAgainstBaseURL: true),
            let target = URLComponents(url: fallback, resolvingAgainstBaseURL: true)
        else { return nil }

        components.scheme = target.scheme
        components.host = target.host
        components.port = target.port
        guard let rebased = components.url else { return nil }

        activeBaseURL = fallback
        var retried = request
        retried.url = rebased
        return retried
    }
}
