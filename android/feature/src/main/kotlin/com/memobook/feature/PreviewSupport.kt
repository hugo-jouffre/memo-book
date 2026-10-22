package com.memobook.feature

import com.memobook.core.Account
import com.memobook.core.AuthSession
import com.memobook.core.BookCoverEdit
import com.memobook.core.BookCovers
import com.memobook.core.BookCustomisation
import com.memobook.core.BookCustomisationEdit
import com.memobook.core.BookFontRole
import com.memobook.core.BookPreview
import com.memobook.core.BookPreviewStatus
import com.memobook.core.BookRenderPhase
import com.memobook.core.BookRenderProgress
import com.memobook.core.CalendarDay
import com.memobook.core.ChatPhotosTurn
import com.memobook.core.ChatTextTurn
import com.memobook.core.ChatThread
import com.memobook.core.ChatThreadUpdate
import com.memobook.core.ChatTurnReceipt
import com.memobook.core.ChatVoiceTurn
import com.memobook.core.CoverPhoto
import com.memobook.core.CreatedTrip
import com.memobook.core.CustomerPaymentKey
import com.memobook.core.DailyCredit
import com.memobook.core.DataExportReceipt
import com.memobook.core.Entry
import com.memobook.core.EntryEdit
import com.memobook.core.EntryKind
import com.memobook.core.EntryValidation
import com.memobook.core.FaqVote
import com.memobook.core.Gallery
import com.memobook.core.HomeFeed
import com.memobook.core.Memo
import com.memobook.core.MemoDetail
import com.memobook.core.MemoSummary
import com.memobook.core.NewMemo
import com.memobook.core.NewPrintOrderRequest
import com.memobook.core.NewTextEntry
import com.memobook.core.OrderContext
import com.memobook.core.OrderPayment
import com.memobook.core.OrderQuote
import com.memobook.core.PageTargetAllowance
import com.memobook.core.PlacedPrintOrder
import com.memobook.core.PrintOrder
import com.memobook.core.PrintOrderStatus
import com.memobook.core.ProfileEdit
import com.memobook.core.PushTokenRegistration
import com.memobook.core.Render
import com.memobook.core.ResumedOrderPayment
import com.memobook.core.ShippingSpeed
import com.memobook.core.Showcase
import com.memobook.core.Status
import com.memobook.core.SubscriptionCancellationReason
import com.memobook.core.SupportMessage
import com.memobook.core.TravelStatistics
import com.memobook.core.Traveller
import com.memobook.core.TravellerProfile
import com.memobook.core.Trip
import com.memobook.core.TripDetail
import com.memobook.core.TripDraft
import com.memobook.core.TripSettings
import com.memobook.core.TripSettingsEdit
import com.memobook.core.TripTheme
import com.memobook.feature.chat.PreviewChatBox
import com.memobook.feature.chat.sandboxChatThread
import com.memobook.feature.chat.sandboxChatUpdates
import com.memobook.feature.chat.sandboxClearChat
import com.memobook.feature.chat.sandboxSendChatPhotos
import com.memobook.feature.chat.sandboxSendChatText
import com.memobook.feature.chat.sandboxSendChatVoice
import com.memobook.feature.chat.sandboxValidateEntry
import com.memobook.feature.covers.fixture
import com.memobook.feature.gallery.fixture
import com.memobook.feature.home.fixture
import com.memobook.feature.order.fixture
import com.memobook.feature.order.previewRequest
import com.memobook.feature.profile.fixture
import com.memobook.feature.trip.fixture
import com.memobook.feature.tripcreation.fixture
import com.memobook.feature.tripsettings.fixture
import com.memobook.networking.ApiError
import com.memobook.networking.Connectivity
import com.memobook.networking.MemoBookApi
import com.memobook.networking.SocialSignIn
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import java.io.File
import java.net.NoRouteToHostException
import java.net.URI
import java.time.Duration
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.util.UUID

// Le bac à sable — le jumeau de `PreviewSupport.swift`.
//
// Ce fichier expose :
// - [PreviewSupport] : `api(switches)`, le double que `MemoBookApplication`
//   monte sous `previewSignedIn`, et `dependencies(…)`, le graphe sans serveur
//   et sans argent des aperçus et des tests (l'`AppDependencies.preview()` d'iOS) ;
// - au module `:feature` seulement : [PreviewApi], le double complet de
//   `MemoBookApi` ; [SandboxNetwork], le « Passer hors ligne » du bac à sable ;
// [SandboxCredit], le crédit du jour qu'il joue ; `Traveller.replacing(…)`.
//
// Le fil de la conversation du double est dans `chat/PreviewChat.kt`, comme
// `PreviewChat.swift` sur iOS.

/**
 * Le bac à sable vu de l'extérieur : ce que l'app et les aperçus en appellent.
 */
object PreviewSupport {
    /**
     * Le double de l'API pour le lancement `previewSignedIn` : le jeu d'essai,
     * aucun jeton, aucun appel qui aboutisse. `switches.composeBook` y joue la
     * composition du carnet en dix secondes — l'`OnboardingStorage.isComposingBook`
     * d'iOS, qu'Android lit sur l'intention.
     */
    fun api(switches: LaunchSwitches = LaunchSwitches.None): MemoBookApi =
        PreviewApi(isComposingBook = switches.composeBook)

    /**
     * Le graphe **sans serveur et sans argent** : aperçus, tests, et tout ce qui
     * a besoin d'un [AppDependencies] sans back-end. L'`AppDependencies.preview()`
     * d'iOS.
     *
     * Une fabrique et non des arguments à recopier : le jour où une dépendance de
     * plus doit être neutralisée pour un aperçu — les paiements, quand
     * `:payments` arrivera dans `AppDependencies` —, elle se neutralise ici, et
     * aucun site d'appel ne peut l'oublier.
     *
     * @param directory où le cache de contenu et les fichiers de l'aperçu
     *   s'écrivent — le dossier temporaire par défaut, le `cacheDir` de l'app
     *   sur Android.
     * @param scope la portée « de l'app » de ce graphe. Hors de `Dispatchers.Main`
     *   par défaut : un test JVM n'en a pas.
     */
    fun dependencies(
        api: MemoBookApi = PreviewApi(),
        directory: File = File(System.getProperty("java.io.tmpdir"), "memobook-preview"),
        scope: CoroutineScope = CoroutineScope(SupervisorJob() + Dispatchers.Default),
        switches: LaunchSwitches = LaunchSwitches.None,
    ): AppDependencies =
        AppDependencies(
            api = api,
            apiConfiguration = null,
            connectivity = Connectivity.online,
            settings = InMemoryAppSettings(),
            switches = switches,
            cacheDirectory = File(directory, "cache"),
            filesDirectory = File(directory, "files"),
            scope = scope,
        )
}

/**
 * Le « Passer hors ligne » du bac à sable, tel que le double de l'API le voit.
 *
 * Sans lui, le bouton ne coupait que la file : l'accueil, le voyage et la
 * conversation continuaient de se lire comme en ligne, et le parcours hors
 * ligne d'un voyage créé dans l'avion ne se rejouait pas (01/10/2026). Le
 * double répond désormais comme un réseau absent — une panne de **transport** —
 * sur les lectures que ce parcours traverse, et sur la création. Posé par
 * `RecordingOutbox.debugSetOffline(…)`, que seul le panneau de Debug appelle :
 * dans l'app livrée, il reste faux.
 */
internal object SandboxNetwork {
    @Volatile
    var isOffline: Boolean = false

    fun failIfOffline() {
        if (isOffline) throw ApiError.Transport(NoRouteToHostException("Bac à sable hors ligne"), url = null)
    }
}

/**
 * Double de l'API pour les aperçus, les tests, et le lancement `previewSignedIn`.
 *
 * Il garde son état en mémoire : ajouter un souvenir dans un aperçu met
 * vraiment la liste à jour, ce qui rend les aperçus utilisables pour travailler
 * les écrans sans back-end lancé.
 *
 * Un verrou et non un acteur : chaque section qui le tient est courte et ne
 * suspend jamais — le compilateur refuse une suspension dans `synchronized`.
 *
 * @param seeded `false` démarre sans le carnet d'essai (`preview-memo`).
 * @param isComposingBook la composition jouée en dix secondes — voir
 *   [PreviewSupport.api].
 */
internal class PreviewApi(
    seeded: Boolean = true,
    private val isComposingBook: Boolean = false,
) : MemoBookApi {
    private val lock = Any()

    private val memosById = mutableMapOf<String, MemoDetail>()
    private val rendersById = mutableMapOf<String, Render>()
    private val ordersByMemoId = mutableMapOf<String, MutableList<PrintOrder>>()

    /** Nul tant que rien n'a été corrigé : le profil est alors le jeu d'essai. */
    private var editedProfile: TravellerProfile? = null

    /** Les votes « Est-ce utile ? » du bac à sable, le temps de la session. */
    private val sandboxFaqVotes = mutableMapOf<String, Boolean>()

    /**
     * Les voyages créés dans le bac à sable, le plus récent d'abord : ils restent
     * sur l'accueil une fois « arrivés », comme sur le serveur.
     */
    private val createdTrips = mutableListOf<Trip>()

    /**
     * Les souvenirs effacés par la croix d'une étape : l'étape qui n'en a plus
     * disparaît du voyage, comme le serveur la retirera (T235).
     */
    private val deletedEntryIds = mutableSetOf<String>()

    /** Les fils de conversation du double, un par voyage — voir `chat/PreviewChat.kt`. */
    internal val chat = PreviewChatBox()

    init {
        if (seeded) {
            val seed = seedMemo()
            memosById[seed.id] = seed
        }
    }

    override suspend fun ensureDeviceRegistered() {}

    // region Compte
    //
    // L'aperçu accepte tout le monde : ce qu'on travaille dans un aperçu, c'est
    // l'écran, pas la validation du serveur. Les refus se vérifient en test.

    private var account: Account? = null

    override suspend fun hasStoredSession(): Boolean = synchronized(lock) { account != null }

    override suspend fun signUp(email: String, password: String, firstName: String?, lastName: String?): AuthSession =
        open(
            Account(
                id = "preview-account",
                email = email,
                firstName = firstName,
                lastName = lastName,
                createdAt = Instant.now(),
            ),
        )

    override suspend fun signIn(email: String, password: String): AuthSession = open(previewAccount)

    override suspend fun signIn(with: SocialSignIn): AuthSession =
        open(
            Account(
                id = "preview-account",
                email = previewAccount.email,
                firstName = with.firstName ?: previewAccount.firstName,
                lastName = with.lastName,
                createdAt = Instant.now(),
            ),
        )

    override suspend fun currentAccount(): Account = synchronized(lock) { account } ?: throw ApiError.NotAuthenticated

    override suspend fun signOut() {
        synchronized(lock) { account = null }
    }

    /** Rien à envoyer en aperçu : la feuille passe simplement à l'étape suivante. */
    override suspend fun requestPasswordReset(email: String) {}

    override suspend fun resetPassword(token: String, password: String): AuthSession = open(previewAccount)

    private fun open(account: Account): AuthSession {
        synchronized(lock) { this.account = account }
        return AuthSession(
            token = "preview-session",
            expiresAt = Instant.now().plus(Duration.ofDays(90)),
            account = account,
        )
    }

    // endregion

    // region Les écrans
    //
    // Les jeux d'essai déjà écrits pour les aperçus font l'affaire : le double
    // n'a pas à réinventer un contenu que `HomeFeed.fixture` porte déjà.

    /**
     * L'accueil du jeu d'essai, et ce que le serveur y ajoute depuis le crédit
     * du jour : le voyageur abonné ou non, et le crédit de chaque voyage en
     * cours — voir [SandboxCredit].
     */
    override suspend fun homeFeed(): HomeFeed {
        SandboxNetwork.failIfOffline()
        val fixture = HomeFeed.fixture
        val profileIsUnlimited = sandboxProfileIsUnlimited
        val isUnlimited = SandboxCredit.isUnlimited(profileIsUnlimited = profileIsUnlimited)
        val feed = HomeFeed(
            traveller = fixture.traveller.replacing(isUnlimited = isUnlimited),
            trips = synchronized(lock) { createdTrips.map { it.copy() } } + fixture.trips,
            showcase = fixture.showcase,
        )
        return SandboxCredit.applied(feed, profileIsUnlimited = profileIsUnlimited)
    }

    override suspend fun tripDetail(id: String): TripDetail {
        SandboxNetwork.failIfOffline()
        // Un voyage créé ici est lui-même, pas le voyage de Rome du jeu d'essai.
        val (created, deleted) = synchronized(lock) { createdTrips.firstOrNull { it.id == id } to deletedEntryIds.toSet() }
        if (created != null) return TripDetail(trip = created.copy())
        val detail = TripDetail.fixture(id = id)
        return TripDetail(
            trip = detail.trip,
            prompt = detail.prompt,
            steps = detail.steps.filter { step ->
                val ids = step.entryIds
                ids.isNullOrEmpty() || !ids.all { it in deleted }
            },
        )
    }

    override suspend fun validateStep(tripId: String, stepId: String): TripDetail {
        val detail = TripDetail.fixture(id = tripId)
        return TripDetail(
            trip = detail.trip,
            prompt = detail.prompt,
            steps = detail.steps.map { if (it.id == stepId) it.validated() else it },
        )
    }

    override suspend fun gallery(): Gallery = Gallery.fixture

    override suspend fun tripThemes(): List<TripTheme> = TripTheme.fixtures

    /**
     * La création rend un voyage qui ressemble au brouillon, et le code d'accès
     * de la maquette : de quoi traverser les six étapes sans serveur. Sous
     * **l'identifiant que l'app a tiré**, comme le serveur.
     */
    override suspend fun createTrip(draft: TripDraft): CreatedTrip {
        SandboxNetwork.failIfOffline()
        val created = CreatedTrip.fixture(draft, id = draft.id)
        synchronized(lock) {
            // Rejouée, la création corrige le voyage au lieu d'en ajouter un.
            createdTrips.removeAll { it.id == created.trip.id }
            createdTrips.add(0, created.trip)
        }
        chat.open(created.trip)
        return created
    }

    override suspend fun updateTrip(id: String, draft: TripDraft): CreatedTrip = CreatedTrip.fixture(draft, id = id)

    /**
     * Le code de la maquette ouvre le premier voyage du jeu d'essai ; tout autre
     * répond comme le serveur à un code inconnu — c'est ce qui montre l'alerte
     * « Oups, voyage introuvable » dans le bac à sable.
     */
    override suspend fun joinTrip(code: String): CreatedTrip {
        val trip = HomeFeed.fixture.ongoingTrips.firstOrNull()
        if (code != "JHKFDA" || trip == null) {
            throw ApiError.Server(
                statusCode = 404,
                code = "trip_not_found",
                message = "Aucun voyage n’est associé à ce code.",
            )
        }
        return CreatedTrip(trip = trip, accessCode = code)
    }

    override suspend fun welcomeShowcases(): List<Showcase> = listOfNotNull(HomeFeed.fixture.showcase)

    override suspend fun profile(): TravellerProfile = synchronized(lock) { editedProfile } ?: TravellerProfile.fixture

    override suspend fun travelStatistics(): TravelStatistics = TravelStatistics.fixture

    /**
     * Le bac à sable reçoit le message comme le serveur : un instant, puis
     * « envoyé ». Rien ne part.
     */
    override suspend fun sendSupportMessage(message: SupportMessage) {
        delay(400)
    }

    override suspend fun voteOnFaq(questionId: String, isHelpful: Boolean, appVersion: String?) {
        synchronized(lock) { sandboxFaqVotes[questionId] = isHelpful }
    }

    override suspend fun faqVotes(): List<FaqVote> =
        synchronized(lock) { sandboxFaqVotes.map { FaqVote(questionId = it.key, isHelpful = it.value) } }

    override suspend fun updateProfile(edit: ProfileEdit): TravellerProfile = editProfile { current ->
        // Le double garde ce qu'on lui écrit : un aperçu où l'on corrige son
        // prénom doit montrer le prénom corrigé, pas retomber sur le jeu d'essai
        // au rechargement suivant.
        var profile = current
        edit.phoneNumber?.let { profile = profile.copy(phoneNumber = it.value) }
        edit.birthDate?.let { profile = profile.copy(birthDate = it.value) }
        edit.wantsNewsletter?.let { profile = profile.copy(wantsNewsletter = it) }
        edit.notifications?.let { profile = profile.copy(notifications = it) }
        edit.address?.let { address ->
            // Comme le serveur : le nom du pays se dérive du code, il ne se
            // stocke pas.
            val countryName = profile.shippingCountry(code = address.country)?.name ?: address.country
            profile = profile.copy(address = address.copy(countryName = countryName))
        }
        edit.gender?.let { profile = profile.copy(gender = it) }
        profile
    }

    /**
     * L'abonnement se referme **dans le double**, comme le reste : rouvrir la
     * feuille doit montrer quelqu'un de résilié, pas l'abonné du jeu d'essai. Le
     * mois réglé (`paidThrough`) ne bouge pas — c'est lui qui donne son sursis
     * (« illimité jusqu'au … »), et c'est ce qu'on vient vérifier à l'écran.
     */
    override suspend fun cancelSubscription(reason: SubscriptionCancellationReason?): TravellerProfile =
        editProfile { profile ->
            profile.copy(subscription = profile.subscription.updating(isActive = false, cancelledAt = Instant.now()))
        }

    /**
     * L'achat ouvre l'abonnement **dans le double** : rouvrir le profil doit
     * montrer un abonné, tenu par le store — sans qu'aucune signature soit lue —,
     * et le crédit du jour passe à l'illimité, sur le fil comme sur l'accueil.
     */
    override suspend fun syncAppStoreTransaction(signedTransaction: String, memoId: String?): TravellerProfile {
        val profile = editProfile { profile ->
            profile.copy(
                subscription = profile.subscription.updating(
                    isActive = true,
                    cancelledAt = null,
                    managedByAppStore = true,
                ),
            )
        }
        SandboxCredit.setUnlimited(true)
        // Un personnage joué par le bac à sable (« Sans abonnement », « Jamais
        // abonné ») retoucherait l'accueil et le profil en non abonné au prochain
        // rechargement : l'achat en fait un abonné, comme le serveur le ferait
        // (03/10/2026).
        if (SandboxPersona.current != null) SandboxPersona.current = SandboxPersona.Subscriber
        return profile
    }

    /** Le jumeau Google Play : l'abonnement s'ouvre de même, tenu par le Play Store. */
    override suspend fun syncGooglePlayPurchase(purchaseToken: String, productId: String, memoId: String?): TravellerProfile {
        val profile = editProfile { profile ->
            profile.copy(
                subscription = profile.subscription.updating(isActive = true, cancelledAt = null, managedByAppStore = false),
            )
        }
        SandboxCredit.setUnlimited(true)
        if (SandboxPersona.current != null) SandboxPersona.current = SandboxPersona.Subscriber
        return profile
    }

    override suspend fun changePassword(current: String, new: String) {}

    override suspend fun removeAvatar(): TravellerProfile = editProfile { it.copy(avatarUrl = null) }

    /**
     * La photo reste sur le disque de l'aperçu, et le profil pointe dessus :
     * c'est ce qui permet de voir sa photo changer sans serveur.
     */
    override suspend fun uploadAvatar(data: ByteArray, mimeType: String): TravellerProfile {
        val file = File(previewFilesDirectory, "preview-avatar-${UUID.randomUUID().toString().uppercase()}.jpg")
        file.writeBytes(data)
        return editProfile { it.copy(avatarUrl = file.toURI()) }
    }

    override suspend fun setConnector(key: String, isEnabled: Boolean) {
        editProfile { profile ->
            profile.copy(connectors = profile.connectors.map { if (it.id == key) it.copy(isEnabled = isEnabled) else it })
        }
    }

    override suspend fun linkCurrentDevice() {}
    override suspend fun registerPushToken(registration: PushTokenRegistration) {}
    override suspend fun markNotificationOpened(id: String) {}
    override suspend fun deleteAccount() {}

    /**
     * Le lien « part » à l'adresse du profil du jeu d'essai : rien ne sort du
     * bac à sable, et la feuille montre sa confirmation.
     */
    override suspend fun requestDataExport(): DataExportReceipt =
        DataExportReceipt.fixture(email = profile().email ?: "ton adresse e-mail")

    /** Lit, retouche et garde le profil du double, d'un seul tenant. */
    private fun editProfile(change: (TravellerProfile) -> TravellerProfile): TravellerProfile = synchronized(lock) {
        change(editedProfile ?: TravellerProfile.fixture).also { editedProfile = it }
    }

    // endregion

    // region Carnets

    override suspend fun memos(): List<MemoSummary> = synchronized(lock) {
        memosById.values
            .sortedByDescending { it.createdAt }
            .map { memo ->
                MemoSummary(
                    id = memo.id,
                    title = memo.title,
                    subtitle = memo.subtitle,
                    theme = memo.theme,
                    coverPhotoUrl = memo.coverPhotoUrl,
                    createdAt = memo.createdAt,
                    entryCount = memo.entries.size,
                    latestRender = memo.renders.firstOrNull(),
                )
            }
    }

    override suspend fun createMemo(memo: NewMemo): Memo {
        val id = UUID.randomUUID().toString().uppercase()
        val now = Instant.now()

        synchronized(lock) {
            memosById[id] = MemoDetail(
                id = id,
                title = memo.title,
                subtitle = memo.subtitle,
                authors = memo.authors,
                theme = memo.theme,
                startDate = memo.startDate,
                endDate = memo.endDate,
                coverPhotoUrl = null,
                createdAt = now,
                updatedAt = now,
                entries = emptyList(),
                renders = emptyList(),
            )
        }

        return Memo(
            id = id,
            title = memo.title,
            subtitle = memo.subtitle,
            authors = memo.authors,
            theme = memo.theme,
            startDate = memo.startDate,
            endDate = memo.endDate,
            createdAt = now,
            updatedAt = now,
        )
    }

    override suspend fun memo(id: String): MemoDetail = synchronized(lock) { existingMemo(id) }

    override suspend fun deleteMemo(id: String) {
        synchronized(lock) { memosById.remove(id) }
    }

    override suspend fun deleteEntry(id: String) {
        SandboxNetwork.failIfOffline()
        synchronized(lock) { deletedEntryIds += id }
    }

    override suspend fun addTextEntry(memoId: String, entry: NewTextEntry): Entry =
        append(
            memoId = memoId,
            kind = EntryKind.Text,
            status = Status.Ready,
            redactionStatus = Status.Pending,
            transcript = entry.transcript,
            capturedAt = entry.capturedAt,
            placeLabel = entry.placeLabel,
        )

    override suspend fun uploadAudio(
        memoId: String,
        data: ByteArray,
        filename: String,
        mimeType: String,
        capturedAt: Instant,
        durationSeconds: Double?,
        placeLabel: String?,
    ): Entry =
        append(
            memoId = memoId,
            kind = EntryKind.Audio,
            status = Status.Pending,
            redactionStatus = Status.Pending,
            transcript = null,
            capturedAt = capturedAt,
            placeLabel = placeLabel,
        )

    override suspend fun uploadPhoto(
        memoId: String,
        data: ByteArray,
        filename: String,
        mimeType: String,
        capturedAt: Instant,
        placeLabel: String?,
    ): Entry =
        append(
            memoId = memoId,
            kind = EntryKind.Photo,
            status = Status.Ready,
            redactionStatus = Status.Ready,
            transcript = null,
            capturedAt = capturedAt,
            placeLabel = placeLabel,
        )

    /**
     * ⚠️ **Un souvenir déposé sur un carnet inconnu ouvre ce carnet**, au lieu de
     * rendre un 404.
     *
     * Le bac à sable ne sème qu'un seul carnet, alors que l'accueil en montre
     * quatre : un vocal enregistré depuis l'accueil retombait donc sur « Carnet
     * introuvable », et la bulle s'affichait « Non envoyé » dans une app où rien
     * n'avait échoué. Un bac à sable qui refuse ce que l'app permet n'apprend
     * rien — il fait chercher un bug là où il n'y en a pas.
     */
    private fun append(
        memoId: String,
        kind: EntryKind,
        status: Status,
        redactionStatus: Status,
        transcript: String?,
        capturedAt: Instant,
        placeLabel: String?,
    ): Entry = synchronized(lock) {
        val memo = memosById[memoId] ?: emptyMemo(memoId)

        val entry = Entry(
            id = UUID.randomUUID().toString().uppercase(),
            memoId = memoId,
            kind = kind,
            status = status,
            transcript = transcript,
            redactionStatus = redactionStatus,
            capturedAt = capturedAt,
            placeLabel = placeLabel,
            error = null,
            media = null,
            createdAt = Instant.now(),
        )

        memosById[memoId] = memo.appending(entry)
        entry
    }

    override suspend fun entry(id: String): Entry = synchronized(lock) { existingEntry(id) }

    /** À appeler sous [lock]. */
    private fun existingEntry(id: String): Entry {
        for (memo in memosById.values) {
            memo.entries.firstOrNull { it.id == id }?.let { return it }
        }
        throw ApiError.Server(statusCode = 404, code = "not_found", message = "Entrée introuvable.")
    }

    override suspend fun updateEntry(id: String, edit: EntryEdit): Entry = synchronized(lock) {
        val current = existingEntry(id)

        // `Some<String?>?` : `Some(null)` revient au texte proposé, `null` ne
        // touche à rien. Le double niveau est ce qui distingue les deux.
        val change = edit.editedText
        val editedText = if (change != null) change.value else current.editedText
        val updated = current.applying(editedText = editedText)

        replace(updated)
        updated
    }

    override suspend fun retryRedaction(entryId: String): Entry = synchronized(lock) {
        val current = existingEntry(entryId)

        if (current.editedText != null) {
            throw ApiError.Server(
                statusCode = 400,
                code = "manually_edited",
                message = "Ce souvenir a été corrigé à la main.",
            )
        }

        val queued = current.applying(redactionStatus = Status.Pending)
        replace(queued)
        queued
    }

    /** À appeler sous [lock]. */
    private fun replace(entry: Entry) {
        val memo = memosById[entry.memoId] ?: return
        memosById[entry.memoId] = memo.replacing(entry)
    }

    /**
     * Quand la composition du bac à sable a commencé — voir [isComposingBook].
     * Posée par la première lecture, remise à zéro par chaque lancement de
     * composition.
     */
    private var sandboxCompositionStart: Instant? = null

    override suspend fun startRender(memoId: String): Render = synchronized(lock) {
        // La composition du bac à sable repart de zéro à chaque ouverture de
        // l'aperçu — voir [isComposingBook].
        if (isComposingBook) {
            val now = Instant.now()
            sandboxCompositionStart = now
            return@synchronized Render(
                id = "render-sandbox",
                memoId = memoId,
                status = Status.Processing,
                createdAt = now,
                updatedAt = now,
            )
        }
        val memo = existingMemo(memoId)
        val now = Instant.now()

        val render = Render(
            id = UUID.randomUUID().toString().uppercase(),
            memoId = memoId,
            status = Status.Ready,
            pdfUrl = "https://pdf.example.test/preview.pdf",
            error = null,
            createdAt = now,
            updatedAt = now,
        )

        rendersById[render.id] = render
        memosById[memoId] = memo.prepending(render)
        render
    }

    override suspend fun render(id: String): Render = synchronized(lock) {
        rendersById[id] ?: throw ApiError.Server(
            statusCode = 404,
            code = "not_found",
            message = "Génération introuvable.",
        )
    }

    override suspend fun setOrderWhatsApp(orderId: String, phone: String?): PrintOrder = synchronized(lock) {
        for (orders in ordersByMemoId.values) {
            val position = orders.indexOfFirst { it.id == orderId }
            if (position < 0) continue
            val updated = orders[position].copy(
                notifyByWhatsApp = phone != null,
                whatsappPhone = phone,
                updatedAt = Instant.now(),
            )
            orders[position] = updated
            return@synchronized updated
        }

        throw ApiError.Server(statusCode = 404, code = "not_found", message = "Commande introuvable.")
    }

    override suspend fun bookPreview(memoId: String): BookPreview {
        if (isComposingBook) return composingSandboxPreview()
        return BookPreview.fixture
    }

    /**
     * Une composition jouée en dix secondes : la file, la mise en page, le PDF,
     * puis le carnet du jeu d'essai.
     */
    private fun composingSandboxPreview(): BookPreview {
        val start = synchronized(lock) { sandboxCompositionStart ?: Instant.now().also { sandboxCompositionStart = it } }
        val elapsed = Duration.between(start, Instant.now()).toMillis() / 1000.0

        val phase = when {
            elapsed < 2 -> BookRenderPhase.Queued
            elapsed < 6 -> BookRenderPhase.Writing
            elapsed < 10 -> BookRenderPhase.Composing
            else -> return BookPreview.fixture
        }

        val fixture = BookPreview.fixture
        return BookPreview(
            memoId = fixture.memoId,
            title = fixture.title,
            status = BookPreviewStatus.Composing,
            pageCount = 0,
            render = BookRenderProgress(id = "render-sandbox", phase = phase),
            pendingMemoryCount = if (phase == BookRenderPhase.Writing && elapsed < 4) 1 else 0,
        )
    }

    override suspend fun bookShareLink(memoId: String): URI {
        // Les voyages du jeu d'essai de l'accueil portent le carnet du même
        // identifiant, comme sur le serveur : leur partage doit marcher dans le
        // bac à sable aussi.
        val isFixtureTrip = HomeFeed.fixture.trips.any { it.id == memoId }
        if (!isFixtureTrip) synchronized(lock) { existingMemo(memoId) }
        // Un lien d'aperçu, stable d'un appel à l'autre comme le vrai, et de sa
        // forme — mais sur un domaine d'exemple : seul le serveur crée un jeton.
        return URI(BookPreview.sampleShareLink(memoId))
    }

    override suspend fun orderContext(memoId: String): OrderContext = OrderContext.fixture

    override suspend fun orderQuote(memoId: String, copies: Int, shippingSpeed: ShippingSpeed): OrderQuote =
        OrderQuote.fixture(copies = copies, speed = shippingSpeed)

    /**
     * Une commande déjà réglée, et une intention **factice**.
     *
     * Elle ne monte aucune feuille : les aperçus branchent ce double sans
     * paiement, qui n'appelle personne, et un lancement `previewSignedIn` passe
     * par le tunnel en mémoire de `RootView`. C'était la cagnotte qui couvrait
     * tout et évitait la feuille, jusqu'à ce qu'elle parte (T230).
     */
    override suspend fun createPrintOrder(memoId: String, order: NewPrintOrderRequest): PlacedPrintOrder {
        val now = Instant.now()
        val created = synchronized(lock) {
            existingMemo(memoId)

            PrintOrder(
                id = UUID.randomUUID().toString().uppercase(),
                memoId = memoId,
                renderId = order.renderId ?: "render-preview",
                status = PrintOrderStatus.Submitted,
                copies = order.copies,
                shipping = order.shipping,
                trackingUrl = null,
                error = null,
                createdAt = now,
                updatedAt = now,
            ).also { ordersByMemoId.getOrPut(memoId) { mutableListOf() }.add(0, it) }
        }
        return PlacedPrintOrder(
            order = created,
            payment = OrderPayment(
                amountCents = 0,
                currency = "eur",
                clientSecret = "pi_preview_secret_preview",
                publishableKey = "pk_test_preview",
            ),
        )
    }

    override suspend fun printOrders(memoId: String): List<PrintOrder> =
        synchronized(lock) { ordersByMemoId[memoId]?.toList() ?: emptyList() }

    override suspend fun printOrder(id: String): PrintOrder = synchronized(lock) {
        ordersByMemoId.values.flatten().firstOrNull { it.id == id }
            ?: throw ApiError.Server(statusCode = 404, code = "not_found", message = "Commande introuvable.")
    }

    /**
     * Le double n'a pas d'intention à reprendre : ses commandes naissent payées.
     * Il rend donc la commande, sans rien à régler — y compris la commande
     * abandonnée du profil d'essai, que « Finaliser ma commande » rouvre (T232).
     */
    override suspend fun resumePrintOrderPayment(orderId: String, stripeApiVersion: String?): ResumedOrderPayment {
        val order = try {
            printOrder(orderId)
        } catch (_: ApiError) {
            PrintOrder.fixture(memoId = "preview", request = NewPrintOrderRequest.previewRequest)
        }
        return ResumedOrderPayment(order = order, payment = null)
    }

    override suspend fun cancelPrintOrder(orderId: String): PrintOrder = printOrder(orderId)

    override suspend fun paymentMethodsKey(stripeApiVersion: String): CustomerPaymentKey =
        CustomerPaymentKey(
            customerId = "cus_preview",
            ephemeralKeySecret = "ek_test_preview",
            publishableKey = "pk_test_preview",
        )

    override suspend fun paymentMethodsSetupIntent(): String = "seti_preview_secret_preview"

    // endregion

    // region La conversation — `chat/PreviewChat.kt`

    override suspend fun chatThread(tripId: String): ChatThread = sandboxChatThread(tripId)

    override suspend fun chatUpdates(tripId: String, since: Instant): ChatThreadUpdate =
        sandboxChatUpdates(tripId, since)

    override suspend fun sendChatText(tripId: String, turn: ChatTextTurn): ChatTurnReceipt =
        sandboxSendChatText(tripId, turn)

    override suspend fun sendChatVoice(tripId: String, turn: ChatVoiceTurn): ChatTurnReceipt =
        sandboxSendChatVoice(tripId, turn)

    override suspend fun sendChatPhotos(tripId: String, turn: ChatPhotosTurn): ChatTurnReceipt =
        sandboxSendChatPhotos(tripId, turn)

    override suspend fun validateEntry(id: String): EntryValidation = sandboxValidateEntry(id)

    override suspend fun clearChat(tripId: String) = sandboxClearChat(tripId)

    override suspend fun entryMedia(id: String): ByteArray =
        throw ApiError.Server(statusCode = 404, code = "not_found", message = "Média introuvable.")

    override suspend fun chatMessageMedia(id: String): ByteArray =
        throw ApiError.Server(statusCode = 404, code = "not_found", message = "Média introuvable.")

    // endregion

    // region Les réglages d'un voyage

    override suspend fun bookCovers(tripId: String): BookCovers = BookCovers.fixture

    override suspend fun updateBookCovers(tripId: String, edit: BookCoverEdit): BookCovers {
        val covers = BookCovers.fixture
        return when (edit) {
            is BookCoverEdit.Style -> covers.with(edit.face, covers[edit.face].copy(styleId = edit.styleId))
            is BookCoverEdit.Photo -> covers.with(edit.face, covers[edit.face].copy(photoId = edit.photoId))
            is BookCoverEdit.Texts -> covers.with(
                edit.face,
                covers[edit.face].copy(title = edit.title, subtitle = edit.subtitle),
            )
            is BookCoverEdit.Stats -> covers.copy(back = covers.back.copy(statIds = edit.statIds))
        }
    }

    override suspend fun uploadCoverPhoto(tripId: String, data: ByteArray): CoverPhoto {
        val file = File(previewFilesDirectory, "preview-cover-${UUID.randomUUID().toString().uppercase()}.jpg")
        file.writeBytes(data)
        return CoverPhoto(id = "cover-${UUID.randomUUID().toString().uppercase()}", url = file.toURI().toString())
    }

    /**
     * Les réglages du jeu d'essai, **avec le crédit du jour de ce voyage** : la
     * ligne « Crédit du jour » lit le même reste que la barre de la
     * conversation — voir [SandboxCredit].
     */
    override suspend fun tripSettings(id: String): TripSettings =
        SettingsBox.read().copy(dailyCredit = sandboxCredit(tripId = id))

    override suspend fun updateTripSettings(id: String, edit: TripSettingsEdit): TripSettings =
        applyTripSettings(edit).copy(dailyCredit = sandboxCredit(tripId = id))

    private fun applyTripSettings(edit: TripSettingsEdit): TripSettings =
        SettingsBox.apply { settings ->
            when (edit) {
                is TripSettingsEdit.Name -> settings.copy(name = edit.value)
                is TripSettingsEdit.Dates -> settings.copy(startDate = edit.start, endDate = edit.end)
                is TripSettingsEdit.NarrationPace -> settings.copy(narrationPace = edit.value)
                is TripSettingsEdit.Notifications -> settings.copy(wantsNotifications = edit.value)
                is TripSettingsEdit.NotificationPreferences -> settings.copy(notifications = edit.value)
                is TripSettingsEdit.Theme -> settings.copy(theme = edit.value)
                is TripSettingsEdit.PublicGallery -> settings.copy(isPublicGallery = edit.value)
            }
        }

    override suspend fun updateBookCustomisation(tripId: String, edit: BookCustomisationEdit): TripSettings {
        // La règle des deux changements, comme le serveur : un changement qui
        // compte en consomme un, ouvre la réécriture, et le troisième est refusé
        // en 409.
        if (edit is BookCustomisationEdit.TargetPageCount) {
            val current = SettingsBox.read()
            val allowance = current.pageTargetAllowance
            if (allowance.changesCount && edit.value != current.customisation?.targetPageCount) {
                if (allowance.changesLeft <= 0) {
                    throw ApiError.Server(
                        statusCode = 409,
                        code = ApiError.PAGE_TARGET_LIMIT_REACHED_CODE,
                        message = "Tu as déjà changé deux fois le nombre de pages cible de ce voyage.",
                    )
                }
                SettingsBox.apply { settings ->
                    settings.copy(pageTarget = allowance.copy(changesLeft = allowance.changesLeft - 1, rewriteAvailable = true))
                }
            }
        }
        return SettingsBox.apply { settings ->
            val customisation = settings.customisation ?: BookCustomisation.fixture
            settings.copy(customisation = customisation.applying(edit))
        }
    }

    override suspend fun rewritePageTarget(tripId: String): TripSettings {
        if (!SettingsBox.read().pageTargetAllowance.rewriteAvailable) {
            throw ApiError.Server(
                statusCode = 409,
                code = ApiError.PAGE_TARGET_REWRITE_UNAVAILABLE_CODE,
                message = "Les étapes déjà écrites sont déjà réécrites pour ce changement.",
            )
        }
        return SettingsBox.apply { settings ->
            settings.copy(pageTarget = settings.pageTarget?.copy(rewriteAvailable = false))
        }
    }

    override suspend fun removeCompanion(tripId: String, companionId: String): TripSettings =
        SettingsBox.apply { settings ->
            settings.copy(companions = settings.companions.filterNot { it.id == companionId && !it.isOwner })
        }

    override suspend fun resendInvitation(tripId: String, companionId: String) {}

    // endregion

    // region Le crédit du jour, servi par le double

    /**
     * Le profil du double est-il abonné ? C'est ce que le crédit suit tant
     * qu'aucun personnage du bac à sable n'est joué.
     */
    internal val sandboxProfileIsUnlimited: Boolean
        get() = (synchronized(lock) { editedProfile } ?: TravellerProfile.fixture).isSubscriber

    /** Le crédit de ce voyage, tel que le double le sert. */
    internal fun sandboxCredit(tripId: String): DailyCredit =
        SandboxCredit.credit(tripId = tripId, profileIsUnlimited = sandboxProfileIsUnlimited)

    /** Décompte un vocal de cette durée, ou le refuse comme le serveur. */
    internal fun chargeSandboxVoice(seconds: Double, turnId: String, tripId: String): DailyCredit =
        SandboxCredit.charge(
            SandboxCredit.Cost.Voice(milliseconds = Math.round(seconds * 1000).toInt()),
            turnId = turnId,
            tripId = tripId,
            profileIsUnlimited = sandboxProfileIsUnlimited,
        )

    /**
     * Décompte un texte, ou le refuse. Une puce du catalogue (`suggestionId`) ne
     * coûte rien, comme sur le serveur.
     */
    internal fun chargeSandboxText(text: String, suggestionId: String?, turnId: String, tripId: String): DailyCredit =
        SandboxCredit.charge(
            if (suggestionId == null) SandboxCredit.Cost.Text(text) else SandboxCredit.Cost.Free,
            turnId = turnId,
            tripId = tripId,
            profileIsUnlimited = sandboxProfileIsUnlimited,
        )

    // endregion

    /** À appeler sous [lock]. */
    private fun existingMemo(id: String): MemoDetail =
        memosById[id] ?: throw ApiError.Server(statusCode = 404, code = "not_found", message = "Carnet introuvable.")

    private companion object {
        val previewAccount = Account(
            id = "preview-account",
            email = "hugo@memobook.app",
            firstName = "Hugo",
            createdAt = Instant.now(),
        )

        /**
         * Où le double pose les photos qu'on lui confie — le `cachesDirectory`
         * d'iOS. Le dossier temporaire de la JVM est le `cacheDir` de l'app sur
         * Android.
         */
        val previewFilesDirectory: File get() = File(requireNotNull(System.getProperty("java.io.tmpdir")))

        fun seedMemo(): MemoDetail {
            val memoId = "preview-memo"
            val now = Instant.now()

            val entries = listOf(
                Entry(
                    id = "entry-1",
                    memoId = memoId,
                    kind = EntryKind.Audio,
                    status = Status.Ready,
                    transcript = "euh du coup on arrive à Bogotá après un vol de nuit, et enfin la première claque c’est l’altitude quoi",
                    redactionStatus = Status.Ready,
                    redactedText = "On arrive à Bogotá après un vol de nuit. La première claque, c’est l’altitude.",
                    suggestedTitle = "Premier souffle à 2 600 mètres",
                    funFact = "Bogotá culmine à 2 640 m : la troisième capitale la plus haute d’Amérique du Sud.",
                    funFactTitle = "Fun fact",
                    weatherKey = "cloud",
                    capturedAt = now.minus(Duration.ofDays(2)),
                    placeLabel = "Bogotá, Colombie",
                    error = null,
                    media = null,
                    createdAt = now.minus(Duration.ofDays(2)),
                ),
                Entry(
                    id = "entry-2",
                    memoId = memoId,
                    kind = EntryKind.Audio,
                    status = Status.Ready,
                    transcript = "on est montés à Monserrate en funiculaire, la vue est dingue",
                    redactionStatus = Status.Processing,
                    capturedAt = now.minus(Duration.ofDays(1)),
                    placeLabel = "Monserrate",
                    error = null,
                    media = null,
                    createdAt = now.minus(Duration.ofDays(1)),
                ),
            )

            return MemoDetail(
                id = memoId,
                title = "Claire et Gus en Colombie",
                subtitle = "Un carnet de voyage raconté à l’oral",
                authors = "Claire et Augustin",
                theme = "voyage",
                startDate = null,
                endDate = null,
                coverPhotoUrl = null,
                createdAt = now,
                updatedAt = now,
                entries = entries,
                renders = emptyList(),
            )
        }

        /**
         * Un carnet vide, ouvert au vol pour accueillir un souvenir déposé sur un
         * identifiant que le bac à sable ne sème pas.
         */
        fun emptyMemo(id: String): MemoDetail {
            val now = Instant.now()
            return MemoDetail(
                id = id,
                title = "Carnet du bac à sable",
                subtitle = null,
                authors = null,
                theme = null,
                startDate = null,
                endDate = null,
                coverPhotoUrl = null,
                createdAt = now,
                updatedAt = now,
                entries = emptyList(),
                renders = emptyList(),
            )
        }
    }
}

private fun MemoDetail.appending(entry: Entry): MemoDetail =
    copy(updatedAt = Instant.now(), entries = (entries + entry).sortedBy { it.capturedAt })

private fun MemoDetail.replacing(entry: Entry): MemoDetail =
    copy(updatedAt = Instant.now(), entries = entries.map { if (it.id == entry.id) entry else it })

private fun MemoDetail.prepending(render: Render): MemoDetail =
    copy(updatedAt = Instant.now(), renders = listOf(render) + renders)

/**
 * Recopie l'entrée en changeant la correction manuelle. `displayText` est
 * recalculé, comme le ferait le serveur.
 */
private fun Entry.applying(editedText: String?): Entry =
    copied(editedText = editedText, editedAt = if (editedText == null) null else Instant.now(), redactionStatus = redactionStatus)

private fun Entry.applying(redactionStatus: Status): Entry =
    copied(editedText = editedText, editedAt = editedAt, redactionStatus = redactionStatus)

/**
 * Le `copy(editedText:editedAt:redactionStatus:)` d'iOS, champ pour champ : il
 * repart de l'initialiseur, qui recalcule `displayText`, et ne recopie ni la
 * validation ni le reste de correction gratuite.
 */
private fun Entry.copied(editedText: String?, editedAt: Instant?, redactionStatus: Status): Entry =
    Entry(
        id = id,
        memoId = memoId,
        kind = kind,
        status = status,
        transcript = transcript,
        redactionStatus = redactionStatus,
        redactedText = redactedText,
        redactionError = redactionError,
        editedText = editedText,
        editedAt = editedAt,
        suggestedTitle = suggestedTitle,
        funFact = funFact,
        funFactTitle = funFactTitle,
        weatherKey = weatherKey,
        capturedAt = capturedAt,
        placeLabel = placeLabel,
        error = error,
        media = media,
        createdAt = createdAt,
    )

/** Une personnalisation changée, comme le serveur l'écrit. */
private fun BookCustomisation.applying(edit: BookCustomisationEdit): BookCustomisation = when (edit) {
    is BookCustomisationEdit.PhotoTextRatio -> copy(photoTextRatio = edit.value)
    is BookCustomisationEdit.TargetPageCount -> copy(targetPageCount = edit.value)
    is BookCustomisationEdit.FunFacts -> copy(funFactsEnabled = edit.value)
    is BookCustomisationEdit.Rules -> copy(rulesEnabled = edit.value)
    is BookCustomisationEdit.DecorationQuota -> copy(decorationQuota = edit.value)
    is BookCustomisationEdit.FontDisplay -> copy(fontDisplay = edit.value)
    is BookCustomisationEdit.FontTitle -> copy(fontTitle = edit.value)
    is BookCustomisationEdit.FontHand -> copy(fontHand = edit.value)
    is BookCustomisationEdit.FontFacts -> copy(fontFacts = edit.value)
    is BookCustomisationEdit.FontCombo -> copy(
        rulesEnabled = edit.rulesEnabled,
        fontDisplay = edit.combo.font(BookFontRole.Titles),
        fontTitle = edit.combo.font(BookFontRole.Subtitles),
        fontHand = edit.combo.font(BookFontRole.Texts),
        fontFacts = edit.combo.font(BookFontRole.FunFacts),
    )
    is BookCustomisationEdit.Quiz -> copy(quizEnabled = edit.value)
    is BookCustomisationEdit.FreeZones -> copy(freeZonesEnabled = edit.value)
    is BookCustomisationEdit.Crossword -> copy(crosswordEnabled = edit.value)
}

/**
 * **Le crédit du jour du bac à sable** (03/10/2026) : ce que le double d'API
 * sert comme `dailyCredit` — sur le fil de la conversation, ses mises à jour, le
 * reçu d'un tour (qu'il décompte), les réglages du voyage et l'accueil.
 *
 * Les trois réglages du panneau de l'accueil y posent un reste de départ :
 * « Crédit neuf », « Plus que 30 s » (4:30 consommées : l'avertissement paraît
 * dès qu'on parle), « Crédit épuisé ». Ensuite, chaque tour envoyé le fait
 * descendre, et le double refuse comme le serveur (`429 daily_credit_exhausted`)
 * — de quoi rejouer l'avertissement, la pulsation, l'arrêt net et le « Partira
 * demain » de la file sans back-end.
 *
 * Un verrou, comme [SandboxNetwork] : le panneau (sur le fil principal) et
 * [PreviewApi] (sur n'importe quel fil) le lisent tous deux sans attendre.
 * Compilé dans l'app livrée parce que [PreviewApi] l'est (les aperçus) ; seul le
 * panneau, en Debug, le règle.
 */
internal object SandboxCredit {
    /** Les trois réglages du panneau. */
    enum class Preset(val rawValue: String) {
        Fresh("fresh"),
        LastThirtySeconds("lastThirtySeconds"),
        Exhausted("exhausted"),
        ;

        val label: String
            get() = when (this) {
                Fresh -> "Crédit neuf"
                LastThirtySeconds -> "Plus que 30 s"
                Exhausted -> "Crédit épuisé"
            }

        /** Ce que le voyage a déjà raconté aujourd'hui. */
        val usedMs: Int
            get() = when (this) {
                Fresh -> 0
                LastThirtySeconds -> DailyCredit.Catalog.limitMs - DailyCredit.Catalog.warningRemainingMs
                Exhausted -> DailyCredit.Catalog.limitMs
            }
    }

    /**
     * Le refus du serveur, au mot près (`DAILY_CREDIT_EXHAUSTED_MESSAGE` est la
     * bulle ; ceci est le corps du 429).
     */
    const val refusal =
        "Le crédit du jour de ce voyage est épuisé. Reviens demain pour continuer, ou passe en illimité."

    /** La marge d'un dernier vocal, comme `VOICE_TOLERANCE_MS` côté serveur. */
    const val voiceToleranceMs = 3_000

    private data class State(
        /**
         * Le réglage joué, `null` tant que le panneau n'a rien touché : le double
         * sert alors un crédit neuf qui descend, et l'accueil d'un vrai serveur
         * n'est jamais retouché.
         */
        val preset: Preset? = null,
        /** Ce que chaque voyage a consommé, depuis le réglage ou le jour. */
        val usedMsByTrip: Map<String, Int> = emptyMap(),
        /**
         * Le jour de ces chiffres : passé minuit, tout repart à zéro, comme sur
         * le serveur — sans quoi un tour « parti demain » serait refusé une
         * seconde fois.
         */
        val day: String = today(),
        /**
         * Abonné (`true`), sans abonnement (`false`), ou `null` pour suivre le
         * profil du double.
         */
        val isUnlimited: Boolean? = null,
        /**
         * Les tours déjà décomptés : un rejeu de la file (même identifiant) ne
         * compte pas deux fois — l'idempotence du serveur.
         */
        val chargedTurnIds: Set<String> = emptySet(),
    )

    private val lock = Any()
    private var state = State()

    // region Le panneau

    /** Pose un réglage : chaque voyage repart de ce reste. */
    fun play(preset: Preset) {
        synchronized(lock) { state = state.copy(preset = preset, usedMsByTrip = emptyMap(), day = today()) }
    }

    /** Abonné ou non, d'après le personnage du bac à sable. `null` rend la main au profil du double. */
    fun setUnlimited(isUnlimited: Boolean?) {
        synchronized(lock) { state = state.copy(isUnlimited = isUnlimited) }
    }

    /** Le jeu d'essai : plus de réglage, plus de personnage. */
    fun reset() {
        synchronized(lock) { state = State() }
    }

    /**
     * Un réglage est-il joué ? C'est seulement alors que l'accueil d'un vrai
     * serveur se laisse retoucher.
     */
    val isPlaying: Boolean get() = synchronized(lock) { state.preset != null }

    /** Abonné ou non : le personnage s'il y en a un, sinon le profil. */
    fun isUnlimited(profileIsUnlimited: Boolean): Boolean =
        synchronized(lock) { state.isUnlimited } ?: profileIsUnlimited

    // endregion

    // region Le double

    /**
     * Le crédit de ce voyage, aujourd'hui. `profileIsUnlimited` dit ce que le
     * profil du double sait quand aucun personnage n'est joué.
     */
    fun credit(tripId: String, profileIsUnlimited: Boolean = false): DailyCredit = synchronized(lock) {
        rollOver()
        make(state, tripId = tripId, profileIsUnlimited = profileIsUnlimited)
    }

    /** Ce que coûte un tour. */
    sealed interface Cost {
        data class Voice(val milliseconds: Int) : Cost
        data class Text(val text: String) : Cost
        data object Free : Cost
    }

    /**
     * Décompte un tour, **ou le refuse comme le serveur** : un vocal quand il ne
     * reste rien, ou qu'il dépasse le reste de plus de 3 s ; un texte plus long
     * que le reste. Un abonné ne consomme rien.
     */
    fun charge(cost: Cost, turnId: String, tripId: String, profileIsUnlimited: Boolean): DailyCredit {
        // Le refus se lève **hors** du verrou : on n'y garde que des valeurs.
        val (credit, isRefused) = synchronized(lock) {
            rollOver()
            val credit = make(state, tripId = tripId, profileIsUnlimited = profileIsUnlimited)
            if (credit.isUnlimited || turnId in state.chargedTurnIds) return@synchronized credit to false

            val milliseconds = when (cost) {
                Cost.Free -> return@synchronized credit to false
                is Cost.Voice -> {
                    if (credit.remainingMs <= 0 || cost.milliseconds > credit.remainingMs + voiceToleranceMs) {
                        return@synchronized credit to true
                    }
                    cost.milliseconds
                }
                is Cost.Text -> {
                    val price = credit.cost(ofText = cost.text)
                    if (price > credit.remainingMs) return@synchronized credit to true
                    price
                }
            }

            val charged = credit.consuming(milliseconds)
            state = state.copy(
                usedMsByTrip = state.usedMsByTrip + (tripId to charged.usedMs),
                chargedTurnIds = state.chargedTurnIds + turnId,
            )
            charged to false
        }
        if (isRefused) throw ApiError.DailyCreditExhausted(message = refusal, credit = credit)
        return credit
    }

    /** Le flux d'accueil, ses voyages en cours garnis de leur crédit. */
    fun applied(feed: HomeFeed, profileIsUnlimited: Boolean = false): HomeFeed {
        val trips = feed.trips.map { trip ->
            if (!trip.stage.isOngoing) return@map trip
            trip.copy(dailyCredit = credit(tripId = trip.id, profileIsUnlimited = profileIsUnlimited))
        }
        return HomeFeed(traveller = feed.traveller, trips = trips, showcase = feed.showcase)
    }

    // endregion

    private fun make(state: State, tripId: String, profileIsUnlimited: Boolean): DailyCredit {
        val zone = ZoneId.systemDefault()
        return DailyCredit(
            isUnlimited = state.isUnlimited ?: profileIsUnlimited,
            usedMs = state.usedMsByTrip[tripId] ?: state.preset?.usedMs ?: 0,
            day = state.day,
            resetsAt = LocalDate.now(zone).plusDays(1).atStartOfDay(zone).toInstant(),
        )
    }

    /** À appeler sous [lock]. */
    private fun rollOver() {
        val now = today()
        if (state.day == now) return
        state = state.copy(day = now, usedMsByTrip = emptyMap(), preset = state.preset?.let { Preset.Fresh })
    }

    /**
     * Le jour **de l'appareil** : celui dont [make] annonce la recharge à minuit,
     * et où l'app recharge le crédit (`DailyCredit.refreshed(now, zone)`).
     *
     * Pas le jour UTC (03/10/2026) : sur iOS, `ISO8601FormatStyle` écrit en UTC
     * par défaut, et le double changeait de jour à minuit UTC. Entre les deux
     * minuits — de 0 h à 2 h à Paris l'été —, l'app repartait de 5:00 pendant
     * que le double gardait l'usage de la veille et refusait un vocal d'une
     * minute, « Partira demain » à tort.
     */
    fun today(now: Instant = Instant.now(), zone: ZoneId = ZoneId.systemDefault()): String =
        CalendarDay(now, zone).iso
}

/**
 * Le même voyageur, abonné ou non — pour le double et le bac à sable, qui
 * retouchent l'abonnement sans perdre le reste (les deux alertes de l'accueil
 * comprises). L'état d'abonnement servi (`subscriptionState`,
 * `subscriptionEndsAt`) ne suit pas, comme sur iOS : il dirait l'inverse de ce
 * qu'on joue.
 */
internal fun Traveller.replacing(isUnlimited: Boolean, hasSubscribedBefore: Boolean? = null): Traveller =
    Traveller(
        id = id,
        firstName = firstName,
        avatarUrl = avatarUrl,
        isUnlimited = isUnlimited,
        hasSubscribedBefore = hasSubscribedBefore ?: this.hasSubscribedBefore,
        subscriptionEndedOn = subscriptionEndedOn,
        subscriptionOutlivesTrip = subscriptionOutlivesTrip,
    )

/**
 * Les réglages d'un voyage, gardés le temps d'un aperçu — **communs à tous les
 * doubles**, comme le `static let settingsBox` d'iOS.
 *
 * Un aperçu doit pouvoir pousser un curseur et voir la valeur rester : une
 * source qui rendrait le jeu d'essai à chaque lecture annulerait le geste à la
 * première relecture, et on croirait l'écran cassé. C'est la même mécanique que
 * `memosById` pour les carnets.
 */
private object SettingsBox {
    /**
     * Le jeu d'essai, avec **une** étape écrite et un seul changement de cible
     * restant : c'est ce qui fait voir, au premier palier touché,
     * l'avertissement, puis — le voyage étant fini — l'offre de réécrire ; au
     * second, l'orange de la limite. Sans date de fin (« Dates du voyage »), la
     * feuille demande où l'on en est.
     */
    private var settings: TripSettings =
        TripSettings.fixture.copy(pageTarget = PageTargetAllowance(changesLeft = 1, changesCount = true))

    // Des copies, à l'entrée comme à la sortie : `TripSettings` a des `var`, et
    // le modèle qui en retoucherait une sur place retoucherait la boîte — la
    // structure d'iOS, elle, se recopie d'elle-même.
    fun read(): TripSettings = synchronized(this) { settings.copy() }

    fun apply(change: (TripSettings) -> TripSettings): TripSettings = synchronized(this) {
        change(settings.copy()).also { settings = it }.copy()
    }
}
