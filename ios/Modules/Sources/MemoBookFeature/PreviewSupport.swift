import Foundation
import MemoBookCore
import MemoBookNetworking
import MemoBookPayments
import os

extension AppDependencies {
    /// Le graphe **sans serveur et sans argent** : previews Xcode, tests
    /// d'interface, et le lancement `-previewSignedIn`.
    ///
    /// Une fabrique et non deux arguments à recopier : le jour où une dépendance
    /// de plus doit être neutralisée pour une preview Xcode, elle se neutralise ici, et
    /// aucun site d'appel ne peut l'oublier. C'est ``StubPaymentPresenter`` qui
    /// garantit qu'une preview Xcode n'ouvre jamais Stripe.
    @MainActor
    public static func preview() -> AppDependencies {
        AppDependencies(
            api: PreviewAPI(),
            payments: StubPaymentPresenter(),
            subscriptions: StubSubscriptionStore(),
            paymentMethods: StubPaymentMethodsPresenter()
        )
    }
}

/// Double de l'API pour les aperçus SwiftUI et les tests d'interface.
///
/// Il garde son état en mémoire : ajouter un souvenir dans un aperçu met
/// vraiment la liste à jour, ce qui rend les aperçus utilisables pour
/// travailler les écrans sans back-end lancé.
/// Le « Passer hors ligne » du bac à sable, tel que le double de l'API le
/// voit.
///
/// Sans lui, le bouton ne coupait que la file : l'accueil, le voyage et la
/// conversation continuaient de se lire comme en ligne, et le parcours hors
/// ligne d'un voyage créé dans l'avion ne se rejouait pas (01/10/2026). Le
/// double répond désormais comme un réseau absent — une panne de
/// **transport** — sur les lectures que ce parcours traverse, et sur la
/// création. Posé par ``RecordingOutbox/debugSetOffline(_:)``, qui n'existe
/// pas dans l'app livrée : là, il reste faux.
enum SandboxNetwork {
    static let isOffline = OSAllocatedUnfairLock(initialState: false)

    static func failIfOffline() throws {
        if isOffline.withLock({ $0 }) {
            throw APIError.transport(URLError(.notConnectedToInternet), url: nil)
        }
    }
}

public actor PreviewAPI: MemoBookAPI {
    private var memosById: [String: MemoDetail] = [:]
    private var rendersById: [String: Render] = [:]
    private var ordersByMemoId: [String: [PrintOrder]] = [:]

    /// Nul tant que rien n'a été corrigé : le profil est alors le jeu d'essai.
    private var editedProfile: TravellerProfile?

    /// Les votes « Est-ce utile ? » du bac à sable, le temps de la session.
    private var sandboxFaqVotes: [String: Bool] = [:]

    /// Les voyages créés dans le bac à sable, le plus récent d'abord : ils
    /// restent sur l'accueil une fois « arrivés », comme sur le serveur.
    private var createdTrips: [Trip] = []

    /// Les souvenirs effacés par la croix d'une étape : l'étape qui n'en a
    /// plus disparaît du voyage, comme le serveur la retirera (T235).
    private var deletedEntryIds: Set<String> = []

    /// Les fils de conversation du double, un par voyage — voir `PreviewChat.swift`.
    let chat = PreviewChatBox()

    public init(seeded: Bool = true) {
        // Le jeu d'essai est construit hors de l'acteur puis affecté : un `init`
        // synchrone d'acteur ne peut pas appeler ses propres méthodes isolées.
        if seeded {
            let seed = Self.seedMemo()
            memosById[seed.id] = seed
        }
    }

    private static func seedMemo() -> MemoDetail {
        let memoId = "preview-memo"
        let now = Date.now

        let entries = [
            Entry(
                id: "entry-1",
                memoId: memoId,
                kind: .audio,
                status: .ready,
                transcript:
                    "euh du coup on arrive à Bogotá après un vol de nuit, et enfin la première claque c’est l’altitude quoi",
                redactionStatus: .ready,
                redactedText:
                    "On arrive à Bogotá après un vol de nuit. La première claque, c’est l’altitude.",
                suggestedTitle: "Premier souffle à 2 600 mètres",
                funFact: "Bogotá culmine à 2 640 m : la troisième capitale la plus haute d’Amérique du Sud.",
                funFactTitle: "Fun fact",
                weatherKey: "cloud",
                capturedAt: now.addingTimeInterval(-86_400 * 2),
                placeLabel: "Bogotá, Colombie",
                error: nil,
                media: nil,
                createdAt: now.addingTimeInterval(-86_400 * 2)
            ),
            Entry(
                id: "entry-2",
                memoId: memoId,
                kind: .audio,
                status: .ready,
                transcript: "on est montés à Monserrate en funiculaire, la vue est dingue",
                redactionStatus: .processing,
                capturedAt: now.addingTimeInterval(-86_400),
                placeLabel: "Monserrate",
                error: nil,
                media: nil,
                createdAt: now.addingTimeInterval(-86_400)
            ),
        ]

        return MemoDetail(
            id: memoId,
            title: "Claire et Gus en Colombie",
            subtitle: "Un carnet de voyage raconté à l’oral",
            authors: "Claire et Augustin",
            theme: "voyage",
            startDate: nil,
            endDate: nil,
            coverPhotoUrl: nil,
            createdAt: now,
            updatedAt: now,
            entries: entries,
            renders: []
        )
    }

    public func ensureDeviceRegistered() async throws {}

    // MARK: - Compte
    //
    // L'aperçu accepte tout le monde : ce qu'on travaille dans un aperçu, c'est
    // l'écran, pas la validation du serveur. Les refus se vérifient en test.

    private var account: Account?

    private static let previewAccount = Account(
        id: "preview-account",
        email: "hugo@memobook.app",
        firstName: "Hugo",
        createdAt: .now
    )

    public func hasStoredSession() async -> Bool { account != nil }

    public func signUp(
        email: String,
        password: String,
        firstName: String?,
        lastName: String?
    ) async throws -> AuthSession {
        open(
            Account(
                id: "preview-account",
                email: email,
                firstName: firstName,
                lastName: lastName,
                createdAt: .now
            )
        )
    }

    public func signIn(email: String, password: String) async throws -> AuthSession {
        open(Self.previewAccount)
    }

    public func signIn(with credential: SocialSignIn) async throws -> AuthSession {
        open(
            Account(
                id: "preview-account",
                email: Self.previewAccount.email,
                firstName: credential.firstName ?? Self.previewAccount.firstName,
                lastName: credential.lastName,
                createdAt: .now
            )
        )
    }

    public func currentAccount() async throws -> Account {
        guard let account else { throw APIError.notAuthenticated }
        return account
    }

    public func signOut() async { account = nil }

    /// Rien à envoyer en aperçu : la feuille passe simplement à l'étape suivante.
    public func requestPasswordReset(email: String) async throws {}

    public func resetPassword(token: String, password: String) async throws -> AuthSession {
        open(Self.previewAccount)
    }

    private func open(_ account: Account) -> AuthSession {
        self.account = account
        return AuthSession(
            token: "preview-session",
            expiresAt: .now.addingTimeInterval(90 * 86_400),
            account: account
        )
    }

    // MARK: - Les écrans
    //
    // Les jeux d'essai déjà écrits pour les aperçus font l'affaire : le double
    // n'a pas à réinventer un contenu que `HomeFeed.fixture` porte déjà.

    /// L'accueil du jeu d'essai, et ce que le serveur y ajoute depuis le
    /// crédit du jour : le voyageur abonné ou non, et le crédit de chaque voyage
    /// en cours — voir ``SandboxCredit``.
    public func homeFeed() async throws -> HomeFeed {
        try SandboxNetwork.failIfOffline()
        let fixture = HomeFeed.fixture
        let isUnlimited = SandboxCredit.isUnlimited(profileIsUnlimited: sandboxProfileIsUnlimited)
        let feed = HomeFeed(
            traveller: fixture.traveller.replacing(isUnlimited: isUnlimited),
            trips: createdTrips + fixture.trips,
            showcase: fixture.showcase
        )
        return SandboxCredit.applied(to: feed, profileIsUnlimited: sandboxProfileIsUnlimited)
    }

    public func tripDetail(id: String) async throws -> TripDetail {
        try SandboxNetwork.failIfOffline()
        // Un voyage créé ici est lui-même, pas le voyage de Rome du jeu d'essai.
        if let created = createdTrips.first(where: { $0.id == id }) { return TripDetail(trip: created) }
        let detail = TripDetail.fixture(id: id)
        return TripDetail(
            trip: detail.trip,
            prompt: detail.prompt,
            steps: detail.steps.filter { step in
                guard let ids = step.entryIds, !ids.isEmpty else { return true }
                return !ids.allSatisfy(deletedEntryIds.contains)
            }
        )
    }

    public func validateStep(tripId: String, stepId: String) async throws -> TripDetail {
        let detail = TripDetail.fixture(id: tripId)
        return TripDetail(
            trip: detail.trip,
            prompt: detail.prompt,
            steps: detail.steps.map { $0.id == stepId ? $0.validated() : $0 }
        )
    }

    public func gallery() async throws -> Gallery { .fixture }

    public func tripThemes() async throws -> [TripTheme] { TripTheme.fixtures }

    /// La création rend un voyage qui ressemble au brouillon, et le code
    /// d'accès de la maquette : de quoi traverser les six étapes sans serveur.
    /// Sous **l'identifiant que l'app a tiré**, comme le serveur.
    public func createTrip(_ draft: TripDraft) async throws -> CreatedTrip {
        try SandboxNetwork.failIfOffline()
        let created = CreatedTrip.fixture(draft, id: draft.id)
        // Rejouée, la création corrige le voyage au lieu d'en ajouter un.
        createdTrips.removeAll { $0.id == created.trip.id }
        createdTrips.insert(created.trip, at: 0)
        await chat.open(created.trip)
        return created
    }

    public func updateTrip(id: String, draft: TripDraft) async throws -> CreatedTrip {
        .fixture(draft, id: id)
    }

    /// Le code de la maquette ouvre le premier voyage du jeu d'essai ; tout
    /// autre répond comme le serveur à un code inconnu — c'est ce qui montre
    /// l'alerte « Oups, voyage introuvable » dans le bac à sable.
    public func joinTrip(code: String) async throws -> CreatedTrip {
        guard code == "JHKFDA", let trip = HomeFeed.fixture.ongoingTrips.first else {
            throw APIError.server(
                statusCode: 404,
                code: "trip_not_found",
                message: "Aucun voyage n’est associé à ce code."
            )
        }
        return CreatedTrip(trip: trip, accessCode: code)
    }

    public func welcomeShowcases() async throws -> [Showcase] {
        HomeFeed.fixture.showcase.map { [$0] } ?? []
    }

    public func profile() async throws -> TravellerProfile { editedProfile ?? .fixture }

    public func travelStatistics() async throws -> TravelStatistics { .fixture }

    /// Le bac à sable reçoit le message comme le serveur : un instant, puis
    /// « envoyé ». Rien ne part.
    public func sendSupportMessage(_ message: SupportMessage) async throws {
        try await Task.sleep(for: .milliseconds(400))
    }

    public func voteOnFaq(questionId: String, isHelpful: Bool, appVersion: String?) async throws {
        sandboxFaqVotes[questionId] = isHelpful
    }

    public func faqVotes() async throws -> [FaqVote] {
        sandboxFaqVotes.map { FaqVote(questionId: $0.key, isHelpful: $0.value) }
    }

    public func updateProfile(_ edit: ProfileEdit) async throws -> TravellerProfile {
        // Le double garde ce qu'on lui écrit : un aperçu où l'on corrige son
        // prénom doit montrer le prénom corrigé, pas retomber sur le jeu
        // d'essai au rechargement suivant.
        var profile = editedProfile ?? .fixture
        if case .some(let value) = edit.phoneNumber { profile.phoneNumber = value }
        if case .some(let value) = edit.birthDate { profile.birthDate = value }
        if let wantsNewsletter = edit.wantsNewsletter { profile.wantsNewsletter = wantsNewsletter }
        if var address = edit.address {
            // Comme le serveur : le nom du pays se dérive du code, il ne se
            // stocke pas.
            address.countryName = profile.shippingCountry(code: address.country)?.name ?? address.country
            profile.address = address
        }
        if let gender = edit.gender { profile.gender = gender }
        editedProfile = profile
        return profile
    }

    /// L'abonnement se referme **dans le double**, comme le reste : rouvrir la
    /// feuille doit montrer quelqu'un de résilié, pas l'abonné du jeu d'essai.
    /// Le mois réglé (`paidThrough`) ne bouge pas — c'est lui qui donne son
    /// sursis (« illimité jusqu'au … »), et c'est ce qu'on vient vérifier à
    /// l'écran.
    public func cancelSubscription(
        reason: SubscriptionCancellationReason?
    ) async throws -> TravellerProfile {
        _ = reason
        var profile = editedProfile ?? .fixture
        profile.subscription.isActive = false
        profile.subscription.cancelledAt = .now
        editedProfile = profile
        return profile
    }

    /// L'achat ouvre l'abonnement **dans le double** : rouvrir le profil doit
    /// montrer un abonné, tenu par Apple — sans qu'aucune signature soit lue —,
    /// et le crédit du jour passe à l'illimité, sur le fil comme sur l'accueil.
    public func syncAppStoreTransaction(
        signedTransaction: String,
        memoId: String?
    ) async throws -> TravellerProfile {
        _ = (signedTransaction, memoId)
        var profile = editedProfile ?? .fixture
        profile.subscription.isActive = true
        profile.subscription.cancelledAt = nil
        profile.subscription.managedByAppStore = true
        editedProfile = profile
        SandboxCredit.setUnlimited(true)
        #if DEBUG
            // Un personnage joué par le bac à sable (« Sans abonnement »,
            // « Jamais abonné ») retoucherait l'accueil et le profil en non
            // abonné au prochain rechargement : l'achat en fait un abonné,
            // comme le serveur le ferait (03/10/2026).
            await MainActor.run {
                if SandboxPersona.current != nil { SandboxPersona.current = .subscriber }
            }
        #endif
        return profile
    }

    /// La photo reste sur le disque de l'aperçu, et le profil pointe dessus :
    /// c'est ce qui permet de voir sa photo changer sans serveur.
    public func changePassword(current: String, new: String) async throws {}

    public func removeAvatar() async throws -> TravellerProfile {
        var profile = editedProfile ?? .fixture
        profile.avatarUrl = nil
        editedProfile = profile
        return profile
    }

    public func uploadAvatar(data: Data, mimeType: String) async throws -> TravellerProfile {
        var profile = editedProfile ?? .fixture
        let url = URL.cachesDirectory.appending(path: "preview-avatar-\(UUID().uuidString).jpg")
        try data.write(to: url, options: .atomic)
        profile.avatarUrl = url
        editedProfile = profile
        return profile
    }

    public func setConnector(key: String, isEnabled: Bool) async throws {
        var profile = editedProfile ?? .fixture
        profile.connectors = profile.connectors.map { connector in
            guard connector.id == key else { return connector }
            var updated = connector
            updated.isEnabled = isEnabled
            return updated
        }
        editedProfile = profile
    }

    public func linkCurrentDevice() async throws {}
    public func registerPushToken(_ registration: PushTokenRegistration) async throws {}
    public func markNotificationOpened(id: String) async throws {}
    public func deleteAccount() async throws {}

    /// Le lien « part » à l'adresse du profil du jeu d'essai : rien ne sort du
    /// bac à sable, et la feuille montre sa confirmation.
    public func requestDataExport() async throws -> DataExportReceipt {
        .fixture(email: (editedProfile ?? .fixture).email ?? "ton adresse e-mail")
    }

    // MARK: - Carnets

    public func memos() async throws -> [MemoSummary] {
        memosById.values
            .sorted { $0.createdAt > $1.createdAt }
            .map { memo in
                MemoSummary(
                    id: memo.id,
                    title: memo.title,
                    subtitle: memo.subtitle,
                    theme: memo.theme,
                    coverPhotoUrl: memo.coverPhotoUrl,
                    createdAt: memo.createdAt,
                    entryCount: memo.entries.count,
                    latestRender: memo.renders.first
                )
            }
    }

    public func createMemo(_ memo: NewMemo) async throws -> Memo {
        let id = UUID().uuidString
        let now = Date.now

        memosById[id] = MemoDetail(
            id: id,
            title: memo.title,
            subtitle: memo.subtitle,
            authors: memo.authors,
            theme: memo.theme,
            startDate: memo.startDate,
            endDate: memo.endDate,
            coverPhotoUrl: nil,
            createdAt: now,
            updatedAt: now,
            entries: [],
            renders: []
        )

        return Memo(
            id: id,
            title: memo.title,
            subtitle: memo.subtitle,
            authors: memo.authors,
            theme: memo.theme,
            startDate: memo.startDate,
            endDate: memo.endDate,
            createdAt: now,
            updatedAt: now
        )
    }

    public func memo(id: String) async throws -> MemoDetail {
        guard let memo = memosById[id] else {
            throw APIError.server(statusCode: 404, code: "not_found", message: "Carnet introuvable.")
        }
        return memo
    }

    public func deleteMemo(id: String) async throws {
        memosById[id] = nil
    }

    public func deleteEntry(id: String) async throws {
        try SandboxNetwork.failIfOffline()
        deletedEntryIds.insert(id)
    }

    public func addTextEntry(memoId: String, entry: NewTextEntry) async throws -> Entry {
        try append(
            to: memoId,
            kind: .text,
            status: .ready,
            redactionStatus: .pending,
            transcript: entry.transcript,
            capturedAt: entry.capturedAt,
            placeLabel: entry.placeLabel
        )
    }

    public func uploadAudio(
        memoId: String,
        data: Data,
        filename: String,
        mimeType: String,
        capturedAt: Date,
        durationSeconds: TimeInterval?,
        placeLabel: String?
    ) async throws -> Entry {
        try append(
            to: memoId,
            kind: .audio,
            status: .pending,
            redactionStatus: .pending,
            transcript: nil,
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
        try append(
            to: memoId,
            kind: .photo,
            status: .ready,
            redactionStatus: .ready,
            transcript: nil,
            capturedAt: capturedAt,
            placeLabel: placeLabel
        )
    }

    /// ⚠️ **Un souvenir déposé sur un carnet inconnu ouvre ce carnet**, au lieu
    /// de rendre un 404.
    ///
    /// Le bac à sable ne sème qu'un seul carnet, alors que l'accueil en montre
    /// quatre : un vocal enregistré depuis l'accueil retombait donc sur
    /// « Carnet introuvable », et la bulle s'affichait « Non envoyé » dans une
    /// app où rien n'avait échoué. Un bac à sable qui refuse ce que l'app
    /// permet n'apprend rien — il fait chercher un bug là où il n'y en a pas.
    private func append(
        to memoId: String,
        kind: EntryKind,
        status: Status,
        redactionStatus: Status,
        transcript: String?,
        capturedAt: Date,
        placeLabel: String?
    ) throws -> Entry {
        let memo = memosById[memoId] ?? Self.emptyMemo(id: memoId)

        let entry = Entry(
            id: UUID().uuidString,
            memoId: memoId,
            kind: kind,
            status: status,
            transcript: transcript,
            redactionStatus: redactionStatus,
            capturedAt: capturedAt,
            placeLabel: placeLabel,
            error: nil,
            media: nil,
            createdAt: .now
        )

        memosById[memoId] = memo.appending(entry: entry)
        return entry
    }

    public func entry(id: String) async throws -> Entry {
        for memo in memosById.values {
            if let entry = memo.entries.first(where: { $0.id == id }) { return entry }
        }
        throw APIError.server(statusCode: 404, code: "not_found", message: "Entrée introuvable.")
    }

    public func updateEntry(id: String, edit: EntryEdit) async throws -> Entry {
        let current = try await entry(id: id)

        // `String??` : `.some(nil)` revient au texte proposé, `nil` ne touche
        // à rien. Le double niveau est ce qui distingue les deux.
        let editedText: String? = edit.editedText ?? current.editedText
        let updated = current.applying(editedText: editedText)

        replace(entry: updated)
        return updated
    }

    public func retryRedaction(entryId: String) async throws -> Entry {
        let current = try await entry(id: entryId)

        guard current.editedText == nil else {
            throw APIError.server(
                statusCode: 400,
                code: "manually_edited",
                message: "Ce souvenir a été corrigé à la main."
            )
        }

        let queued = current.applying(redactionStatus: .pending)
        replace(entry: queued)
        return queued
    }

    private func replace(entry: Entry) {
        guard let memo = memosById[entry.memoId] else { return }
        memosById[entry.memoId] = memo.replacing(entry: entry)
    }

    public func startRender(memoId: String) async throws -> Render {
        #if DEBUG
            // La composition du bac à sable repart de zéro à chaque ouverture
            // de l'aperçu — voir ``OnboardingStorage/composeBookArgument``.
            if OnboardingStorage.isComposingBook {
                sandboxCompositionStart = .now
                return Render(id: "render-sandbox", memoId: memoId, status: .processing, createdAt: .now, updatedAt: .now)
            }
        #endif
        let memo = try existingMemo(memoId)

        let render = Render(
            id: UUID().uuidString,
            memoId: memoId,
            status: .ready,
            pdfUrl: "https://pdf.example.test/preview.pdf",
            error: nil,
            createdAt: .now,
            updatedAt: .now
        )

        rendersById[render.id] = render
        memosById[memoId] = memo.prepending(render: render)
        return render
    }

    public func render(id: String) async throws -> Render {
        guard let render = rendersById[id] else {
            throw APIError.server(
                statusCode: 404,
                code: "not_found",
                message: "Génération introuvable."
            )
        }
        return render
    }

    public func setOrderWhatsApp(orderId: String, phone: String?) async throws -> PrintOrder {
        for (memoId, orders) in ordersByMemoId {
            guard let position = orders.firstIndex(where: { $0.id == orderId }) else { continue }
            let order = orders[position]
            let updated = PrintOrder(
                id: order.id,
                memoId: order.memoId,
                renderId: order.renderId,
                status: order.status,
                copies: order.copies,
                shippingSpeed: order.shippingSpeed,
                shipping: order.shipping,
                pageCount: order.pageCount,
                coverImageUrl: order.coverImageUrl,
                estimatedMinDays: order.estimatedMinDays,
                estimatedMaxDays: order.estimatedMaxDays,
                total: order.total,
                copyOptions: order.copyOptions,
                notifyByWhatsApp: phone != nil,
                whatsappPhone: phone,
                trackingUrl: order.trackingUrl,
                error: order.error,
                createdAt: order.createdAt,
                updatedAt: .now
            )
            ordersByMemoId[memoId]?[position] = updated
            return updated
        }

        throw APIError.server(statusCode: 404, code: "not_found", message: "Commande introuvable.")
    }

    public func bookPreview(memoId: String) async throws -> BookPreview {
        #if DEBUG
            if OnboardingStorage.isComposingBook { return composingSandboxPreview() }
        #endif
        return .fixture
    }

    /// Quand la composition du bac à sable a commencé — voir
    /// ``OnboardingStorage/composeBookArgument``. Posée par la première
    /// lecture, remise à zéro par chaque lancement de composition.
    private var sandboxCompositionStart: Date?

    /// Une composition jouée en dix secondes : la file, la mise en page, le
    /// PDF, puis le carnet du jeu d'essai.
    private func composingSandboxPreview() -> BookPreview {
        let start = sandboxCompositionStart ?? .now
        sandboxCompositionStart = start
        let elapsed = Date.now.timeIntervalSince(start)

        let phase: BookRenderPhase
        switch elapsed {
        case ..<2: phase = .queued
        case ..<6: phase = .writing
        case ..<10: phase = .composing
        default: return .fixture
        }

        let fixture = BookPreview.fixture
        return BookPreview(
            memoId: fixture.memoId,
            title: fixture.title,
            status: .composing,
            pageCount: 0,
            render: BookRenderProgress(id: "render-sandbox", phase: phase),
            pendingMemoryCount: phase == .writing && elapsed < 4 ? 1 : 0
        )
    }

    public func bookShareLink(memoId: String) async throws -> URL {
        // Les voyages du jeu d'essai de l'accueil portent le carnet du même
        // identifiant, comme sur le serveur : leur partage doit marcher dans
        // le bac à sable aussi.
        let isFixtureTrip = HomeFeed.fixture.trips.contains { $0.id == memoId }
        if !isFixtureTrip { _ = try existingMemo(memoId) }
        // Un lien d'aperçu, stable d'un appel à l'autre comme le vrai, et de
        // sa forme — mais sur un domaine d'exemple : seul le serveur crée un
        // jeton.
        return BookPreview.sampleShareLink(memoId: memoId)
    }

    public func orderContext(memoId: String) async throws -> OrderContext {
        .fixture
    }

    public func orderQuote(
        memoId: String,
        copies: Int,
        shippingSpeed: ShippingSpeed
    ) async throws -> OrderQuote {
        .fixture(copies: copies, speed: shippingSpeed)
    }

    /// Une commande déjà réglée, et une intention **factice**.
    ///
    /// Elle ne monte aucune feuille : les aperçus branchent ce double avec
    /// ``StubPaymentPresenter``, qui n'appelle personne, et un lancement
    /// `-previewSignedIn` passe par le tunnel en mémoire de `RootView`. C'était
    /// la cagnotte qui couvrait tout et évitait la feuille, jusqu'à ce qu'elle
    /// parte (T230).
    public func createPrintOrder(
        memoId: String,
        order: NewPrintOrderRequest
    ) async throws -> PlacedPrintOrder {
        _ = try existingMemo(memoId)

        let created = PrintOrder(
            id: UUID().uuidString,
            memoId: memoId,
            renderId: order.renderId ?? "render-preview",
            status: .submitted,
            copies: order.copies,
            shipping: order.shipping,
            trackingUrl: nil,
            error: nil,
            createdAt: .now,
            updatedAt: .now
        )

        ordersByMemoId[memoId, default: []].insert(created, at: 0)
        return PlacedPrintOrder(
            order: created,
            payment: OrderPayment(
                amountCents: 0,
                currency: "eur",
                clientSecret: "pi_preview_secret_preview",
                publishableKey: "pk_test_preview"
            )
        )
    }

    public func printOrders(memoId: String) async throws -> [PrintOrder] {
        ordersByMemoId[memoId] ?? []
    }

    public func printOrder(id: String) async throws -> PrintOrder {
        guard let found = ordersByMemoId.values.flatMap({ $0 }).first(where: { $0.id == id }) else {
            throw APIError.server(
                statusCode: 404,
                code: "not_found",
                message: "Commande introuvable."
            )
        }
        return found
    }

    /// Le double n'a pas d'intention à reprendre : ses commandes naissent
    /// payées. Il rend donc la commande, sans rien à régler — y compris la
    /// commande abandonnée du profil d'essai, que « Finaliser ma commande »
    /// rouvre (T232).
    public func resumePrintOrderPayment(
        orderId: String,
        stripeApiVersion: String?
    ) async throws -> ResumedOrderPayment {
        _ = stripeApiVersion
        let order = (try? await printOrder(id: orderId)) ?? .fixture(memoId: "preview", request: .previewRequest)
        return ResumedOrderPayment(order: order, payment: nil)
    }

    public func cancelPrintOrder(orderId: String) async throws -> PrintOrder {
        try await printOrder(id: orderId)
    }

    public func paymentMethodsKey(stripeApiVersion: String) async throws -> CustomerPaymentKey {
        _ = stripeApiVersion
        return CustomerPaymentKey(
            customerId: "cus_preview",
            ephemeralKeySecret: "ek_test_preview",
            publishableKey: "pk_test_preview"
        )
    }

    public func paymentMethodsSetupIntent() async throws -> String {
        "seti_preview_secret_preview"
    }

    // MARK: - Les réglages d'un voyage

    /// Les réglages **tenus en mémoire** le temps de l'aperçu.
    ///
    /// Un aperçu doit pouvoir pousser un curseur et voir la valeur rester : une
    /// source qui rendrait le jeu d'essai à chaque lecture annulerait le geste
    /// à la première relecture, et on croirait l'écran cassé. C'est la même
    /// mécanique que `memosById` pour les carnets.
    private static let settingsBox = SettingsBox()

    public func bookCovers(tripId: String) async throws -> BookCovers { .fixture }

    public func updateBookCovers(tripId: String, edit: BookCoverEdit) async throws -> BookCovers {
        var covers = BookCovers.fixture
        switch edit {
        case .style(let face, let styleId): covers[face].styleId = styleId
        case .photo(let face, let photoId): covers[face].photoId = photoId
        case .texts(let face, let title, let subtitle):
            covers[face].title = title
            covers[face].subtitle = subtitle
        case .stats(let ids): covers.back.statIds = ids
        }
        return covers
    }

    public func uploadCoverPhoto(tripId: String, data: Data) async throws -> CoverPhoto {
        let url = URL.cachesDirectory.appending(path: "preview-cover-\(UUID().uuidString).jpg")
        try data.write(to: url, options: .atomic)
        return CoverPhoto(id: "cover-\(UUID().uuidString)", url: url)
    }

    /// Les réglages du jeu d'essai, **avec le crédit du jour de ce voyage** :
    /// la ligne « Crédit du jour » lit le même reste que la barre de la
    /// conversation — voir ``SandboxCredit``.
    public func tripSettings(id: String) async throws -> TripSettings {
        var settings = await Self.settingsBox.read()
        settings.dailyCredit = sandboxCredit(tripId: id)
        return settings
    }

    public func updateTripSettings(id: String, edit: TripSettingsEdit) async throws -> TripSettings {
        var settings = try await applyTripSettings(edit)
        settings.dailyCredit = sandboxCredit(tripId: id)
        return settings
    }

    private func applyTripSettings(_ edit: TripSettingsEdit) async throws -> TripSettings {
        await Self.settingsBox.apply { settings in
            switch edit {
            case .name(let value): settings.name = value
            case .dates(let start, let end):
                settings.startDate = start
                settings.endDate = end
            case .narrationPace(let pace): settings.narrationPace = pace
            case .notifications(let isOn): settings.wantsNotifications = isOn
            case .notificationPreferences(let preferences): settings.notifications = preferences
            case .theme(let value): settings.theme = value
            case .publicGallery(let isOn): settings.isPublicGallery = isOn
            }
        }
    }

    public func updateBookCustomisation(
        tripId: String,
        edit: BookCustomisationEdit
    ) async throws -> TripSettings {
        await Self.settingsBox.apply { settings in
            var customisation = settings.customisation ?? .fixture
            switch edit {
            case .photoTextRatio(let value): customisation.photoTextRatio = value
            case .targetPageCount(let value): customisation.targetPageCount = value
            case .funFacts(let isOn): customisation.funFactsEnabled = isOn
            case .rules(let isOn): customisation.rulesEnabled = isOn
            case .decorationQuota(let value): customisation.decorationQuota = value
            case .fontDisplay(let value): customisation.fontDisplay = value
            case .fontTitle(let value): customisation.fontTitle = value
            case .fontHand(let value): customisation.fontHand = value
            case .fontFacts(let value): customisation.fontFacts = value
            case .fontCombo(let combo, let rules):
                customisation.rulesEnabled = rules
                customisation.fontDisplay = combo.font(.titles)
                customisation.fontTitle = combo.font(.subtitles)
                customisation.fontHand = combo.font(.texts)
                customisation.fontFacts = combo.font(.funFacts)
            case .quiz(let isOn): customisation.quizEnabled = isOn
            case .freeZones(let isOn): customisation.freeZonesEnabled = isOn
            case .crossword(let isOn): customisation.crosswordEnabled = isOn
            }
            settings.customisation = customisation
        }
    }

    public func removeCompanion(tripId: String, companionId: String) async throws -> TripSettings {
        await Self.settingsBox.apply { settings in
            settings.companions.removeAll { $0.id == companionId && !$0.isOwner }
        }
    }

    public func resendInvitation(tripId: String, companionId: String) async throws {}

    /// Un carnet vide, ouvert au vol pour accueillir un souvenir déposé sur un
    /// identifiant que le bac à sable ne sème pas.
    private static func emptyMemo(id: String) -> MemoDetail {
        MemoDetail(
            id: id,
            title: "Carnet du bac à sable",
            subtitle: nil,
            authors: nil,
            theme: nil,
            startDate: nil,
            endDate: nil,
            coverPhotoUrl: nil,
            createdAt: .now,
            updatedAt: .now,
            entries: [],
            renders: []
        )
    }

    private func existingMemo(_ id: String) throws -> MemoDetail {
        guard let memo = memosById[id] else {
            throw APIError.server(statusCode: 404, code: "not_found", message: "Carnet introuvable.")
        }
        return memo
    }
}

extension MemoDetail {
    fileprivate func appending(entry: Entry) -> MemoDetail {
        MemoDetail(
            id: id,
            title: title,
            subtitle: subtitle,
            authors: authors,
            theme: theme,
            startDate: startDate,
            endDate: endDate,
            coverPhotoUrl: coverPhotoUrl,
            createdAt: createdAt,
            updatedAt: .now,
            entries: (entries + [entry]).sorted { $0.capturedAt < $1.capturedAt },
            renders: renders
        )
    }

    fileprivate func replacing(entry: Entry) -> MemoDetail {
        MemoDetail(
            id: id,
            title: title,
            subtitle: subtitle,
            authors: authors,
            theme: theme,
            startDate: startDate,
            endDate: endDate,
            coverPhotoUrl: coverPhotoUrl,
            createdAt: createdAt,
            updatedAt: .now,
            entries: entries.map { $0.id == entry.id ? entry : $0 },
            renders: renders
        )
    }

    fileprivate func prepending(render: Render) -> MemoDetail {
        MemoDetail(
            id: id,
            title: title,
            subtitle: subtitle,
            authors: authors,
            theme: theme,
            startDate: startDate,
            endDate: endDate,
            coverPhotoUrl: coverPhotoUrl,
            createdAt: createdAt,
            updatedAt: .now,
            entries: entries,
            renders: [render] + renders
        )
    }
}

extension Entry {
    /// Recopie l'entrée en changeant la correction manuelle. `displayText` est
    /// recalculé par l'initialiseur, comme le ferait le serveur.
    fileprivate func applying(editedText newValue: String?) -> Entry {
        copy(editedText: newValue, editedAt: newValue == nil ? nil : .now, redactionStatus: redactionStatus)
    }

    fileprivate func applying(redactionStatus newValue: Status) -> Entry {
        copy(editedText: editedText, editedAt: editedAt, redactionStatus: newValue)
    }

    private func copy(editedText: String?, editedAt: Date?, redactionStatus: Status) -> Entry {
        Entry(
            id: id,
            memoId: memoId,
            kind: kind,
            status: status,
            transcript: transcript,
            redactionStatus: redactionStatus,
            redactedText: redactedText,
            redactionError: redactionError,
            editedText: editedText,
            editedAt: editedAt,
            displayText: nil,
            suggestedTitle: suggestedTitle,
            funFact: funFact,
            funFactTitle: funFactTitle,
            weatherKey: weatherKey,
            capturedAt: capturedAt,
            placeLabel: placeLabel,
            error: error,
            media: media,
            createdAt: createdAt
        )
    }
}


/// **Le crédit du jour du bac à sable** (03/10/2026) : ce que le double d'API
/// sert comme `dailyCredit` — sur le fil de la conversation, ses mises à jour,
/// le reçu d'un tour (qu'il décompte), les réglages du voyage et l'accueil.
///
/// Les trois réglages du panneau de l'accueil y posent un reste de départ :
/// « Crédit neuf », « Plus que 30 s » (4:30 consommées : l'avertissement
/// paraît dès qu'on parle), « Crédit épuisé ». Ensuite, chaque tour envoyé le
/// fait descendre, et le double refuse comme le serveur
/// (`429 daily_credit_exhausted`) — de quoi rejouer l'avertissement, la
/// pulsation, l'arrêt net et le « Partira demain » de la file sans back-end.
///
/// Un verrou et non un acteur, comme ``SandboxNetwork`` : le panneau (sur le
/// fil principal) et `PreviewAPI` (son propre acteur) le lisent tous deux sans
/// attendre. Compilé dans l'app livrée parce que `PreviewAPI` l'est (les
/// aperçus) ; seul le panneau, sous `#if DEBUG`, le règle.
public enum SandboxCredit {
    /// Les trois réglages du panneau.
    public enum Preset: String, CaseIterable, Sendable {
        case fresh
        case lastThirtySeconds
        case exhausted

        public var label: String {
            switch self {
            case .fresh: "Crédit neuf"
            case .lastThirtySeconds: "Plus que 30 s"
            case .exhausted: "Crédit épuisé"
            }
        }

        /// Ce que le voyage a déjà raconté aujourd'hui.
        public var usedMs: Int {
            switch self {
            case .fresh: 0
            case .lastThirtySeconds: DailyCredit.Catalog.limitMs - DailyCredit.Catalog.warningRemainingMs
            case .exhausted: DailyCredit.Catalog.limitMs
            }
        }
    }

    /// Le refus du serveur, au mot près (`DAILY_CREDIT_EXHAUSTED_MESSAGE` est
    /// la bulle ; ceci est le corps du 429).
    static let refusal =
        "Le crédit du jour de ce voyage est épuisé. Reviens demain pour continuer, ou passe en illimité."

    /// La marge d'un dernier vocal, comme `VOICE_TOLERANCE_MS` côté serveur.
    static let voiceToleranceMs = 3_000

    private struct State: Sendable {
        /// Le réglage joué, `nil` tant que le panneau n'a rien touché : le
        /// double sert alors un crédit neuf qui descend, et l'accueil d'un vrai
        /// serveur n'est jamais retouché.
        var preset: Preset?
        /// Ce que chaque voyage a consommé, depuis le réglage ou le jour.
        var usedMsByTrip: [String: Int] = [:]
        /// Le jour de ces chiffres : passé minuit, tout repart à zéro, comme
        /// sur le serveur — sans quoi un tour « parti demain » serait refusé
        /// une seconde fois.
        var day = SandboxCredit.today()
        /// Abonné (`true`), sans abonnement (`false`), ou `nil` pour suivre le
        /// profil du double.
        var isUnlimited: Bool?
        /// Les tours déjà décomptés : un rejeu de la file (même identifiant)
        /// ne compte pas deux fois — l'idempotence du serveur.
        var chargedTurnIds: Set<String> = []
    }

    private static let state = OSAllocatedUnfairLock(initialState: State())

    // MARK: Le panneau

    /// Pose un réglage : chaque voyage repart de ce reste.
    public static func play(_ preset: Preset) {
        state.withLock {
            $0.preset = preset
            $0.usedMsByTrip = [:]
            $0.day = today()
        }
    }

    /// Abonné ou non, d'après le personnage du bac à sable. `nil` rend la main
    /// au profil du double.
    public static func setUnlimited(_ isUnlimited: Bool?) {
        state.withLock { $0.isUnlimited = isUnlimited }
    }

    /// Le jeu d'essai : plus de réglage, plus de personnage.
    public static func reset() {
        state.withLock { $0 = State() }
    }

    /// Un réglage est-il joué ? C'est seulement alors que l'accueil d'un vrai
    /// serveur se laisse retoucher.
    public static var isPlaying: Bool { state.withLock { $0.preset != nil } }

    /// Abonné ou non : le personnage s'il y en a un, sinon le profil.
    public static func isUnlimited(profileIsUnlimited: Bool) -> Bool {
        state.withLock { $0.isUnlimited } ?? profileIsUnlimited
    }

    // MARK: Le double

    /// Le crédit de ce voyage, aujourd'hui. `profileIsUnlimited` dit ce que
    /// le profil du double sait quand aucun personnage n'est joué.
    public static func credit(for tripId: String, profileIsUnlimited: Bool = false) -> DailyCredit {
        state.withLock { state in
            rollOver(&state)
            return make(state, tripId: tripId, profileIsUnlimited: profileIsUnlimited)
        }
    }

    /// Ce que coûte un tour.
    enum Cost: Sendable {
        case voice(milliseconds: Int)
        case text(String)
        case free
    }

    /// Décompte un tour, **ou le refuse comme le serveur** : un vocal quand il
    /// ne reste rien, ou qu'il dépasse le reste de plus de 3 s ; un texte plus
    /// long que le reste. Un abonné ne consomme rien.
    static func charge(
        _ cost: Cost,
        turnId: String,
        tripId: String,
        profileIsUnlimited: Bool
    ) throws -> DailyCredit {
        // Le refus se lève **hors** du verrou : on n'y garde que des valeurs.
        let (credit, isRefused): (DailyCredit, Bool) = state.withLock { state in
            rollOver(&state)
            let credit = make(state, tripId: tripId, profileIsUnlimited: profileIsUnlimited)
            guard !credit.isUnlimited, !state.chargedTurnIds.contains(turnId) else {
                return (credit, false)
            }

            let milliseconds: Int
            switch cost {
            case .free:
                return (credit, false)
            case .voice(let duration):
                guard credit.remainingMs > 0, duration <= credit.remainingMs + voiceToleranceMs else {
                    return (credit, true)
                }
                milliseconds = duration
            case .text(let text):
                let price = credit.cost(ofText: text)
                guard price <= credit.remainingMs else { return (credit, true) }
                milliseconds = price
            }

            let charged = credit.consuming(milliseconds)
            state.usedMsByTrip[tripId] = charged.usedMs
            state.chargedTurnIds.insert(turnId)
            return (charged, false)
        }
        if isRefused { throw APIError.dailyCreditExhausted(message: refusal, credit: credit) }
        return credit
    }

    /// Le flux d'accueil, ses voyages en cours garnis de leur crédit.
    public static func applied(to feed: HomeFeed, profileIsUnlimited: Bool = false) -> HomeFeed {
        let trips = feed.trips.map { trip in
            guard trip.stage.isOngoing else { return trip }
            var trip = trip
            trip.dailyCredit = credit(for: trip.id, profileIsUnlimited: profileIsUnlimited)
            return trip
        }
        return HomeFeed(traveller: feed.traveller, trips: trips, showcase: feed.showcase)
    }

    // MARK: -

    private static func make(_ state: State, tripId: String, profileIsUnlimited: Bool) -> DailyCredit {
        DailyCredit(
            isUnlimited: state.isUnlimited ?? profileIsUnlimited,
            usedMs: state.usedMsByTrip[tripId] ?? state.preset?.usedMs ?? 0,
            day: state.day,
            resetsAt: Calendar.current.date(
                byAdding: .day,
                value: 1,
                to: Calendar.current.startOfDay(for: .now)
            )
        )
    }

    private static func rollOver(_ state: inout State) {
        let now = today()
        guard state.day != now else { return }
        state.day = now
        state.usedMsByTrip = [:]
        state.preset = state.preset.map { _ in .fresh }
    }

    /// Le jour **de l'appareil** : celui dont ``make(_:tripId:profileIsUnlimited:)``
    /// annonce la recharge à minuit, et où l'app recharge le crédit
    /// (``DailyCredit/refreshed(now:calendar:)``).
    ///
    /// Pas le jour UTC (03/10/2026) : `ISO8601FormatStyle` écrit en UTC par
    /// défaut, et le double changeait de jour à minuit UTC. Entre les deux
    /// minuits — de 0 h à 2 h à Paris l'été —, l'app repartait de 5:00 pendant
    /// que le double gardait l'usage de la veille et refusait un vocal d'une
    /// minute, « Partira demain » à tort.
    static func today(now: Date = .now, calendar: Calendar = .current) -> String {
        CalendarDay(now, calendar: calendar).iso
    }
}

// MARK: - Le crédit du jour, servi par le double

extension PreviewAPI {
    /// Le profil du double est-il abonné ? C'est ce que le crédit suit tant
    /// qu'aucun personnage du bac à sable n'est joué.
    var sandboxProfileIsUnlimited: Bool { (editedProfile ?? .fixture).isSubscriber }

    /// Le crédit de ce voyage, tel que le double le sert.
    func sandboxCredit(tripId: String) -> DailyCredit {
        SandboxCredit.credit(for: tripId, profileIsUnlimited: sandboxProfileIsUnlimited)
    }

    /// Décompte un vocal de cette durée, ou le refuse comme le serveur.
    func chargeSandboxVoice(seconds: TimeInterval, turnId: String, tripId: String) throws -> DailyCredit {
        try SandboxCredit.charge(
            .voice(milliseconds: Int((seconds * 1000).rounded())),
            turnId: turnId,
            tripId: tripId,
            profileIsUnlimited: sandboxProfileIsUnlimited
        )
    }

    /// Décompte un texte, ou le refuse. Une puce du catalogue (`suggestionId`)
    /// ne coûte rien, comme sur le serveur.
    func chargeSandboxText(
        _ text: String,
        suggestionId: String?,
        turnId: String,
        tripId: String
    ) throws -> DailyCredit {
        try SandboxCredit.charge(
            suggestionId == nil ? .text(text) : .free,
            turnId: turnId,
            tripId: tripId,
            profileIsUnlimited: sandboxProfileIsUnlimited
        )
    }
}

extension Traveller {
    /// Le même voyageur, abonné ou non — pour le double et le bac à sable, qui
    /// retouchent l'abonnement sans perdre le reste (les deux alertes de
    /// l'accueil comprises).
    func replacing(isUnlimited: Bool, hasSubscribedBefore: Bool? = nil) -> Traveller {
        Traveller(
            id: id,
            firstName: firstName,
            avatarUrl: avatarUrl,
            isUnlimited: isUnlimited,
            hasSubscribedBefore: hasSubscribedBefore ?? self.hasSubscribedBefore,
            subscriptionEndedOn: subscriptionEndedOn,
            subscriptionOutlivesTrip: subscriptionOutlivesTrip
        )
    }
}

/// Les réglages d'un voyage, gardés le temps d'un aperçu.
///
/// Un acteur et non une variable statique : `PreviewAPI` est `Sendable`, et une
/// boîte mutable partagée entre deux aperçus ne peut l'être qu'isolée.
private actor SettingsBox {
    private var settings: TripSettings = .fixture

    func read() -> TripSettings { settings }

    func apply(_ change: (inout TripSettings) -> Void) -> TripSettings {
        change(&settings)
        return settings
    }
}
