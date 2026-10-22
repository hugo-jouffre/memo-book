package com.memobook.networking

import com.memobook.core.Account
import com.memobook.core.AuthSession
import com.memobook.core.BookCoverEdit
import com.memobook.core.BookCovers
import com.memobook.core.BookCustomisationEdit
import com.memobook.core.BookFontRole
import com.memobook.core.BookPreview
import com.memobook.core.ChatPhotosTurn
import com.memobook.core.ChatTextTurn
import com.memobook.core.ChatThread
import com.memobook.core.ChatThreadUpdate
import com.memobook.core.ChatTurnReceipt
import com.memobook.core.ChatVoiceTurn
import com.memobook.core.CoverFace
import com.memobook.core.CoverPhoto
import com.memobook.core.CreatedTrip
import com.memobook.core.CustomerPaymentKey
import com.memobook.core.DailyCreditCopy
import com.memobook.core.DataExportReceipt
import com.memobook.core.DeviceRegistration
import com.memobook.core.Entry
import com.memobook.core.EntryEdit
import com.memobook.core.EntryValidation
import com.memobook.core.FaqVote
import com.memobook.core.Gallery
import com.memobook.core.HomeFeed
import com.memobook.core.Memo
import com.memobook.core.MemoBookDate
import com.memobook.core.MemoBookJson
import com.memobook.core.MemoDetail
import com.memobook.core.MemoSummary
import com.memobook.core.NewMemo
import com.memobook.core.NewPrintOrderRequest
import com.memobook.core.NewTextEntry
import com.memobook.core.OrderContext
import com.memobook.core.OrderQuote
import com.memobook.core.PlacedPrintOrder
import com.memobook.core.PrintOrder
import com.memobook.core.ProfileEdit
import com.memobook.core.PushTokenRegistration
import com.memobook.core.Render
import com.memobook.core.ResumedOrderPayment
import com.memobook.core.ShippingSpeed
import com.memobook.core.Showcase
import com.memobook.core.SubscriptionCancellationReason
import com.memobook.core.SupportMessage
import com.memobook.core.TravelStatistics
import com.memobook.core.TravellerProfile
import com.memobook.core.TripDetail
import com.memobook.core.TripDraft
import com.memobook.core.TripNotificationPreferences
import com.memobook.core.TripSettings
import com.memobook.core.TripSettingsEdit
import com.memobook.core.TripTheme
import com.memobook.core.TripThemes
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.serialization.DeserializationStrategy
import kotlinx.serialization.Serializable
import kotlinx.serialization.builtins.ListSerializer
import kotlinx.serialization.builtins.MapSerializer
import kotlinx.serialization.builtins.serializer
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import kotlinx.serialization.serializer
import okhttp3.Call
import okhttp3.Callback
import okhttp3.Headers
import okhttp3.HttpUrl
import okhttp3.HttpUrl.Companion.toHttpUrlOrNull
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import okhttp3.Response
import java.io.IOException
import java.net.ConnectException
import java.net.URI
import java.net.URISyntaxException
import java.net.UnknownHostException
import java.time.Instant
import java.time.ZoneId
import java.util.concurrent.TimeUnit
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException

/**
 * Implémentation HTTP du contrat [MemoBookApi]. Le jumeau de
 * `MemoBookNetworking/MemoBookAPIClient.swift`, sur OkHttp.
 *
 * **Un seul endroit construit une requête** — [makeRequest] — et un seul
 * l'exécute — [performRaw] : les en-têtes, l'identification, les erreurs et la
 * bascule sur le secours ne s'écrivent qu'une fois. Une vue ne construit
 * jamais de client, et ne fabrique jamais de requête.
 *
 * Ce client ne dépend pas d'Android : les jetons passent par [TokenStore]
 * (le magasin chiffré [KeystoreTokenStore] dans l'app, [InMemoryTokenStore]
 * en test), la trace par [NetworkLog].
 *
 * @param tokenStore le jeton de l'**appareil**, qui ne sert plus qu'à
 *   s'enregistrer et à se rattacher.
 * @param sessionStore le jeton de **session**, qui parle pour tout le reste.
 * @param httpClient le client OkHttp de l'app, auquel on pose les délais de
 *   [ApiConfiguration.timeoutSeconds]. Un test y glisse son intercepteur.
 * @param networkLog la trace réseau — le `#if DEBUG` d'iOS : l'app n'en donne
 *   une qu'en Debug, `null` ne trace rien.
 */
class MemoBookApiClient(
    private val configuration: ApiConfiguration = ApiConfiguration.localDevelopment,
    private val tokenStore: TokenStore,
    private val sessionStore: TokenStore,
    httpClient: OkHttpClient = OkHttpClient(),
    private val networkLog: NetworkLog? = null,
) : MemoBookApi {

    /**
     * Le délai d'iOS (`URLRequest.timeoutInterval`) est un délai **sans
     * nouvelles** : il se pose ici sur la connexion, la lecture et l'écriture,
     * pas sur l'appel entier — l'upload d'un long vocal sur un réseau lent
     * peut durer plus d'une minute, tant qu'il avance.
     */
    private val client: OkHttpClient = httpClient.newBuilder()
        .connectTimeout(configuration.timeoutSeconds, TimeUnit.SECONDS)
        .readTimeout(configuration.timeoutSeconds, TimeUnit.SECONDS)
        .writeTimeout(configuration.timeoutSeconds, TimeUnit.SECONDS)
        .build()

    /**
     * Qui parle.
     *
     * **La session de compte, pour tout ce qui appartient à quelqu'un.** Le
     * jeton d'appareil n'ouvre plus rien : depuis qu'un carnet a toujours un
     * propriétaire, et que ce propriétaire est un compte, il ne sert qu'à
     * s'enregistrer et à se rattacher — et il voyage alors dans le corps de la
     * requête, pas dans son en-tête.
     */
    private enum class Credential { None, Session }

    /**
     * Enregistrement en cours, partagé : deux écrans qui démarrent en même
     * temps ne doivent pas créer deux appareils. Le second attend le premier,
     * puis trouve le jeton.
     */
    private val registration = Mutex()

    private val configuredBaseUrl: HttpUrl? = configuration.baseUrl.toString().toHttpUrlOrNull()
    private val fallbackBaseUrl: HttpUrl? = configuration.fallbackBaseUrl?.toString()?.toHttpUrlOrNull()

    /**
     * L'adresse à laquelle les requêtes partent **en ce moment** : la
     * configurée, jusqu'à ce qu'elle refuse la connexion et qu'un secours
     * existe — voir [rebasedOnFallback]. Une bascule tient pour toute la vie
     * du client.
     */
    @Volatile
    private var activeBaseUrl: HttpUrl? = configuredBaseUrl

    // region Identité

    override suspend fun ensureDeviceRegistered() {
        if (tokenStore.read() != null) return

        registration.withLock {
            if (tokenStore.read() != null) return
            val registered: DeviceRegistration = send(
                method = "POST",
                path = "/v1/devices",
                body = stringsBody(mapOf("platform" to "android")),
                credential = Credential.None,
            )
            tokenStore.write(registered.token)
        }
    }

    // endregion

    // region Compte

    override suspend fun hasStoredSession(): Boolean = sessionStore.read() != null

    override suspend fun signUp(
        email: String,
        password: String,
        firstName: String?,
        lastName: String?,
    ): AuthSession {
        val body = mutableMapOf("email" to email, "password" to password)
        // Champs facultatifs : les envoyer vides ferait échouer la validation
        // du serveur, qui exige au moins un caractère quand ils sont présents.
        if (!firstName.isNullOrEmpty()) body["firstName"] = firstName
        if (!lastName.isNullOrEmpty()) body["lastName"] = lastName
        return openSession("/v1/auth/signup", body)
    }

    override suspend fun signIn(email: String, password: String): AuthSession =
        openSession("/v1/auth/signin", mapOf("email" to email, "password" to password))

    override suspend fun signIn(with: SocialSignIn): AuthSession {
        val body = mutableMapOf("identityToken" to with.identityToken)
        with.nonce?.let { body["nonce"] = it }
        if (!with.firstName.isNullOrEmpty()) body["firstName"] = with.firstName
        if (!with.lastName.isNullOrEmpty()) body["lastName"] = with.lastName
        return openSession("/v1/auth/${with.provider.rawValue}", body)
    }

    override suspend fun currentAccount(): Account {
        val response: AccountResponse = send("GET", "/v1/auth/me", credential = Credential.Session)
        return response.account
    }

    override suspend fun signOut() {
        // Le jeton est oublié quoi qu'il arrive : quelqu'un qui se déconnecte
        // dans un train sans réseau ne doit pas rester connecté sur son écran.
        // La session côté serveur expirera d'elle-même.
        try {
            sendIgnoringResponse("POST", "/v1/auth/signout", credential = Credential.Session)
        } catch (_: ApiError) {
        } finally {
            sessionStore.clear()
        }
    }

    override suspend fun requestPasswordReset(email: String) {
        sendIgnoringResponse(
            method = "POST",
            path = "/v1/auth/password/forgot",
            body = stringsBody(mapOf("email" to email)),
            credential = Credential.None,
        )
    }

    override suspend fun resetPassword(token: String, password: String): AuthSession =
        openSession("/v1/auth/password/reset", mapOf("token" to token, "password" to password))

    private suspend fun openSession(path: String, body: Map<String, String>): AuthSession {
        val session: AuthSession = send("POST", path, stringsBody(body), Credential.None)
        sessionStore.write(session.token)
        return session
    }

    // endregion

    // region Les écrans

    override suspend fun homeFeed(): HomeFeed = send("GET", "/v1/home", credential = Credential.Session)

    override suspend fun tripDetail(id: String): TripDetail =
        send("GET", "/v1/trips/$id", credential = Credential.Session)

    override suspend fun validateStep(tripId: String, stepId: String): TripDetail =
        send("POST", "/v1/trips/$tripId/steps/$stepId/validate", credential = Credential.Session)

    override suspend fun createTrip(draft: TripDraft): CreatedTrip =
        send("POST", "/v1/trips", encoded(draft), Credential.Session)

    override suspend fun updateTrip(id: String, draft: TripDraft): CreatedTrip =
        send("PATCH", "/v1/trips/$id", encoded(draft), Credential.Session)

    override suspend fun joinTrip(code: String): CreatedTrip =
        send("POST", "/v1/trips/join", encoded(JoinBody(code)), Credential.Session)

    override suspend fun tripThemes(): List<TripTheme> {
        val response: TripThemes = send("GET", "/v1/trip-themes", credential = Credential.Session)
        return response.themes
    }

    override suspend fun gallery(): Gallery = send("GET", "/v1/gallery", credential = Credential.Session)

    override suspend fun welcomeShowcases(): List<Showcase> {
        val response: ShowcasesResponse = send("GET", "/v1/showcases/welcome", credential = Credential.None)
        return response.showcases
    }

    override suspend fun profile(): TravellerProfile = send("GET", "/v1/profile", credential = Credential.Session)

    override suspend fun travelStatistics(): TravelStatistics =
        send("GET", "/v1/profile/statistics", credential = Credential.Session)

    override suspend fun uploadAvatar(data: ByteArray, mimeType: String): TravellerProfile {
        val form = MultipartFormData()
        form.addFile(
            name = "file",
            filename = if (mimeType == "image/png") "avatar.png" else "avatar.jpg",
            mimeType = mimeType,
            data = data,
        )
        return postForm(form, "/v1/profile/avatar")
    }

    override suspend fun removeAvatar(): TravellerProfile =
        send("DELETE", "/v1/profile/avatar", credential = Credential.Session)

    override suspend fun changePassword(current: String, new: String) {
        sendIgnoringResponse(
            method = "POST",
            path = "/v1/profile/password",
            body = stringsBody(mapOf("currentPassword" to current, "newPassword" to new)),
            credential = Credential.Session,
        )
    }

    override suspend fun sendSupportMessage(message: SupportMessage) {
        send<IdReceipt>("POST", "/v1/support/messages", encoded(message), Credential.Session)
    }

    override suspend fun voteOnFaq(questionId: String, isHelpful: Boolean, appVersion: String?) {
        send<FaqVote>(
            method = "PUT",
            path = "/v1/support/faq-votes/$questionId",
            body = encoded(FaqVoteBody(isHelpful, appVersion)),
            credential = Credential.Session,
        )
    }

    override suspend fun faqVotes(): List<FaqVote> {
        val response: FaqVotesResponse = send("GET", "/v1/support/faq-votes")
        return response.votes
    }

    override suspend fun cancelSubscription(reason: SubscriptionCancellationReason?): TravellerProfile =
        send(
            method = "POST",
            path = "/v1/profile/subscription/cancel",
            body = encoded(CancellationBody(reason?.rawValue)),
            credential = Credential.Session,
        )

    override suspend fun syncAppStoreTransaction(signedTransaction: String, memoId: String?): TravellerProfile =
        send(
            method = "POST",
            path = "/v1/subscriptions/app-store",
            body = encoded(AppStoreTransactionBody(signedTransaction, memoId)),
            credential = Credential.Session,
        )

    override suspend fun syncGooglePlayPurchase(purchaseToken: String, productId: String, memoId: String?): TravellerProfile =
        send(
            method = "POST",
            path = "/v1/subscriptions/google-play",
            body = encoded(GooglePlayPurchaseBody(purchaseToken, productId, memoId)),
            credential = Credential.Session,
        )

    override suspend fun updateProfile(edit: ProfileEdit): TravellerProfile =
        send("PATCH", "/v1/profile", encoded(edit), Credential.Session)

    override suspend fun setConnector(key: String, isEnabled: Boolean) {
        send<ConnectorResponse>(
            method = "PUT",
            path = "/v1/profile/connectors/$key",
            body = encoded(ConnectorBody(isEnabled)),
            credential = Credential.Session,
        )
    }

    override suspend fun linkCurrentDevice() {
        // Les deux jetons dans la même requête, et c'est voulu : celui du
        // compte dans l'en-tête prouve qui reçoit, celui de l'appareil dans le
        // corps prouve ce qui est rattaché.
        ensureDeviceRegistered()
        val deviceToken = tokenStore.read() ?: throw ApiError.NotAuthenticated

        send<LinkedDeviceResponse>(
            method = "POST",
            path = "/v1/profile/link-device",
            body = encoded(LinkDeviceBody(deviceToken)),
            credential = Credential.Session,
        )
    }

    override suspend fun registerPushToken(registration: PushTokenRegistration) {
        sendIgnoringResponse(
            method = "POST",
            path = "/v1/push-tokens",
            body = stringsBody(registration.body),
            credential = Credential.Session,
        )
    }

    override suspend fun markNotificationOpened(id: String) {
        sendIgnoringResponse("POST", "/v1/notifications/$id/opened", credential = Credential.Session)
    }

    override suspend fun deleteAccount() {
        sendIgnoringResponse("DELETE", "/v1/accounts/me", credential = Credential.Session)

        // Les deux jetons partent, et pas seulement celui de la session : le
        // compte n'existe plus, et son appareil a disparu avec lui côté
        // serveur. Garder un jeton d'appareil périmé, ce serait rendre l'app
        // muette au prochain lancement, avec des 401 qu'elle ne saurait pas
        // expliquer.
        sessionStore.clear()
        tokenStore.clear()
    }

    override suspend fun requestDataExport(): DataExportReceipt =
        send("POST", "/v1/accounts/me/export", credential = Credential.Session)

    // endregion

    // region Carnets

    override suspend fun memos(): List<MemoSummary> {
        val response: MemosResponse = send("GET", "/v1/memos")
        return response.memos
    }

    override suspend fun createMemo(memo: NewMemo): Memo = send("POST", "/v1/memos", encoded(memo))

    override suspend fun memo(id: String): MemoDetail = send("GET", "/v1/memos/$id")

    override suspend fun deleteMemo(id: String) {
        sendIgnoringResponse("DELETE", "/v1/memos/$id")
    }

    override suspend fun deleteEntry(id: String) {
        sendIgnoringResponse("DELETE", "/v1/entries/$id")
    }

    // endregion

    // region Souvenirs

    override suspend fun addTextEntry(memoId: String, entry: NewTextEntry): Entry =
        send("POST", "/v1/memos/$memoId/entries", encoded(entry))

    override suspend fun uploadAudio(
        memoId: String,
        data: ByteArray,
        filename: String,
        mimeType: String,
        capturedAt: Instant,
        durationSeconds: Double?,
        placeLabel: String?,
    ): Entry = uploadMedia(memoId, data, filename, mimeType, capturedAt, durationSeconds, placeLabel)

    override suspend fun uploadPhoto(
        memoId: String,
        data: ByteArray,
        filename: String,
        mimeType: String,
        capturedAt: Instant,
        placeLabel: String?,
    ): Entry = uploadMedia(memoId, data, filename, mimeType, capturedAt, durationSeconds = null, placeLabel = placeLabel)

    private suspend fun uploadMedia(
        memoId: String,
        data: ByteArray,
        filename: String,
        mimeType: String,
        capturedAt: Instant,
        durationSeconds: Double? = null,
        placeLabel: String?,
    ): Entry {
        val form = MultipartFormData()
        form.addField("capturedAt", MemoBookDate.format(capturedAt))
        if (durationSeconds != null) {
            // Arrondie à la seconde : le serveur compte en minutes entamées, et
            // une décimale ne changerait rien qu'à la taille de la requête.
            form.addField("durationSeconds", Math.round(durationSeconds).toString())
        }
        if (placeLabel != null) {
            form.addField("placeLabel", placeLabel)
        }
        form.addFile(name = "file", filename = filename, mimeType = mimeType, data = data)
        return postForm(form, "/v1/memos/$memoId/entries")
    }

    override suspend fun entry(id: String): Entry = send("GET", "/v1/entries/$id")

    override suspend fun updateEntry(id: String, edit: EntryEdit): Entry =
        send("PATCH", "/v1/entries/$id", encoded(edit))

    override suspend fun retryRedaction(entryId: String): Entry = send("POST", "/v1/entries/$entryId/redaction")

    // endregion

    // region La conversation avec MEMO

    override suspend fun chatThread(tripId: String): ChatThread = send("GET", "/v1/trips/$tripId/chat")

    override suspend fun chatUpdates(tripId: String, since: Instant): ChatThreadUpdate =
        send("GET", "/v1/trips/$tripId/chat?since=${MemoBookDate.format(since)}")

    override suspend fun sendChatText(tripId: String, turn: ChatTextTurn): ChatTurnReceipt =
        send("POST", "/v1/trips/$tripId/chat", encoded(turn))

    override suspend fun sendChatVoice(tripId: String, turn: ChatVoiceTurn): ChatTurnReceipt {
        val form = MultipartFormData()
        form.addField("id", turn.id)
        form.addField("capturedAt", MemoBookDate.format(turn.capturedAt))
        // Arrondie à la seconde, et **pour mémoire** : depuis le crédit du jour
        // (03/10/2026), le serveur relit la durée dans le fichier et ne croit
        // plus celle-ci. Elle part quand même, inoffensive — un serveur d'avant
        // la lit encore.
        form.addField("durationSeconds", Math.round(turn.durationSeconds).toString())
        turn.placeLabel?.let { form.addField("placeLabel", it) }
        turn.stepId?.let { form.addField("stepId", it) }
        if (turn.levels.isNotEmpty()) {
            // La forme d'onde part avec le vocal : c'est elle que la bulle
            // redessine depuis un autre appareil. En `Float`, comme iOS ; un
            // niveau non fini ne s'écrit pas en JSON, et la bulle s'en passe.
            val levels = try {
                MemoBookJson.encodeToString(ListSerializer(Float.serializer()), turn.levels.map { it.toFloat() })
            } catch (_: IllegalArgumentException) {
                null
            }
            levels?.let { form.addField("levels", it) }
        }
        form.addFile(name = "file", filename = turn.filename, mimeType = turn.mimeType, data = turn.data)
        return postForm(form, "/v1/trips/$tripId/chat")
    }

    override suspend fun sendChatPhotos(tripId: String, turn: ChatPhotosTurn): ChatTurnReceipt {
        val form = MultipartFormData()
        form.addField("id", turn.id)
        form.addField("capturedAt", MemoBookDate.format(turn.capturedAt))
        turn.stepId?.let { form.addField("stepId", it) }
        for (photo in turn.photos) {
            form.addFile(name = "file", filename = photo.filename, mimeType = photo.mimeType, data = photo.data)
        }
        return postForm(form, "/v1/trips/$tripId/chat")
    }

    private suspend inline fun <reified R> postForm(form: MultipartFormData, path: String): R =
        send("POST", path, Body(form.finalized(), form.contentType), Credential.Session)

    override suspend fun validateEntry(id: String): EntryValidation = send("POST", "/v1/entries/$id/validate")

    override suspend fun clearChat(tripId: String) {
        sendIgnoringResponse("DELETE", "/v1/trips/$tripId/chat")
    }

    override suspend fun entryMedia(id: String): ByteArray =
        performRaw(makeRequest("GET", "/v1/entries/$id/media"), Credential.Session)

    override suspend fun chatMessageMedia(id: String): ByteArray =
        performRaw(makeRequest("GET", "/v1/chat-messages/$id/media"), Credential.Session)

    // endregion

    // region Génération

    override suspend fun startRender(memoId: String): Render = send("POST", "/v1/memos/$memoId/renders")

    override suspend fun render(id: String): Render = send("GET", "/v1/renders/$id")

    // endregion

    // region Impression

    override suspend fun orderContext(memoId: String): OrderContext = send("GET", "/v1/memos/$memoId/order-context")

    override suspend fun orderQuote(memoId: String, copies: Int, shippingSpeed: ShippingSpeed): OrderQuote =
        send("POST", "/v1/memos/$memoId/orders/quote", encoded(QuoteBody(copies, shippingSpeed)))

    override suspend fun setOrderWhatsApp(orderId: String, phone: String?): PrintOrder {
        // Le corps porte **l'accord et le numéro ensemble** : le serveur refuse
        // l'un sans l'autre, et les séparer côté client laisserait composer une
        // requête qu'il rejettera.
        val body = if (phone != null) {
            buildJsonObject {
                put("enabled", true)
                put("phone", phone)
            }
        } else {
            buildJsonObject { put("enabled", false) }
        }
        return send("POST", "/v1/orders/$orderId/whatsapp", jsonBody(body))
    }

    override suspend fun bookPreview(memoId: String): BookPreview = send("GET", "/v1/memos/$memoId/preview")

    override suspend fun bookShareLink(memoId: String): URI {
        val response: UrlResponse = send("POST", "/v1/memos/$memoId/share-link")
        return try {
            URI(response.url)
        } catch (error: URISyntaxException) {
            throw ApiError.Decoding(error)
        }
    }

    override suspend fun createPrintOrder(memoId: String, order: NewPrintOrderRequest): PlacedPrintOrder =
        send("POST", "/v1/memos/$memoId/orders", encoded(order))

    override suspend fun printOrder(id: String): PrintOrder = send("GET", "/v1/orders/$id")

    // endregion

    // region Les réglages d'un voyage

    override suspend fun tripSettings(id: String): TripSettings = send("GET", "/v1/trips/$id/settings")

    override suspend fun bookCovers(tripId: String): BookCovers = send("GET", "/v1/trips/$tripId/covers")

    override suspend fun updateBookCovers(tripId: String, edit: BookCoverEdit): BookCovers =
        send("PATCH", "/v1/trips/$tripId/covers", jsonBody(coverEditBody(edit)), Credential.Session)

    override suspend fun uploadCoverPhoto(tripId: String, data: ByteArray): CoverPhoto {
        val form = MultipartFormData()
        form.addFile(name = "file", filename = "cover.jpg", mimeType = "image/jpeg", data = data)
        val response: CoverPhotoResponse = postForm(form, "/v1/trips/$tripId/covers/photos")
        return response.photo
    }

    override suspend fun updateTripSettings(id: String, edit: TripSettingsEdit): TripSettings =
        send("PATCH", "/v1/trips/$id/settings", jsonBody(tripSettingsPatch(edit)))

    override suspend fun updateBookCustomisation(tripId: String, edit: BookCustomisationEdit): TripSettings =
        send("PATCH", "/v1/trips/$tripId/settings", jsonBody(tripSettingsPatch(edit)))

    override suspend fun rewritePageTarget(tripId: String): TripSettings =
        send("POST", "/v1/trips/$tripId/page-target/rewrite")

    override suspend fun removeCompanion(tripId: String, companionId: String): TripSettings =
        send("DELETE", "/v1/trips/$tripId/members/$companionId")

    override suspend fun resendInvitation(tripId: String, companionId: String) {
        sendIgnoringResponse("POST", "/v1/trips/$tripId/members/$companionId/invitation")
    }

    override suspend fun resumePrintOrderPayment(orderId: String, stripeApiVersion: String?): ResumedOrderPayment =
        send("POST", "/v1/orders/$orderId/payment", encoded(StripeVersionBody(stripeApiVersion)))

    override suspend fun cancelPrintOrder(orderId: String): PrintOrder = send("POST", "/v1/orders/$orderId/cancel")

    override suspend fun paymentMethodsKey(stripeApiVersion: String): CustomerPaymentKey =
        send("POST", "/v1/payments/ephemeral-key", encoded(StripeVersionBody(stripeApiVersion)))

    override suspend fun paymentMethodsSetupIntent(): String {
        val response: SetupIntentResponse = send("POST", "/v1/payments/setup-intent")
        return response.clientSecret
    }

    override suspend fun printOrders(memoId: String): List<PrintOrder> {
        val response: OrdersResponse = send("GET", "/v1/memos/$memoId/orders")
        return response.orders
    }

    // endregion

    // region Transport

    /** Un corps prêt à partir, et son type. */
    private class Body(val bytes: ByteArray, val contentType: String)

    private fun jsonBody(json: JsonObject): Body =
        Body(MemoBookJson.encodeToString(JsonObject.serializer(), json).toByteArray(Charsets.UTF_8), JSON)

    /** Le `[String: String]` d'iOS, écrit par `JSONSerialization`. */
    private fun stringsBody(body: Map<String, String>): Body =
        Body(
            MemoBookJson.encodeToString(MapSerializer(String.serializer(), String.serializer()), body)
                .toByteArray(Charsets.UTF_8),
            JSON,
        )

    /** Un modèle `@Serializable`, écrit par le JSON de l'app — le `JSONEncoder.memoBook` d'iOS. */
    private inline fun <reified B> encoded(body: B): Body =
        Body(MemoBookJson.encodeToString(serializer<B>(), body).toByteArray(Charsets.UTF_8), JSON)

    /** Le magasin qui porte un type de jeton donné, ou `null` pour un appel qui n'en présente aucun. */
    private fun store(credential: Credential): TokenStore? = when (credential) {
        Credential.None -> null
        Credential.Session -> sessionStore
    }

    private fun makeRequest(
        method: String,
        path: String,
        credential: Credential = Credential.Session,
        body: Body? = null,
    ): Request {
        val url = activeBaseUrl?.resolve(path)
            ?: throw ApiError.Server(statusCode = 0, code = null, message = "Chemin d’API invalide : $path")

        val headers = Headers.Builder()
            .add("Accept", "application/json")
            // **Le fuseau de l'appareil, sur chaque appel** (03/10/2026) : le
            // crédit du jour se recharge à minuit **chez celui qui raconte**, et
            // le voyageur change de fuseau avec son voyage. Le serveur met à
            // jour le compte quand il change — une écriture, pas une par
            // requête. Lu à chaque appel et non une fois pour toutes : l'avion
            // atterrit pendant que l'app est ouverte.
            .add(TIME_ZONE_HEADER, ZoneId.systemDefault().id)
            // **La plateforme, sur chaque appel** — l'en-tête du lot B5
            // (`docs/android.md`) : MEMO dira « les paramètres du téléphone »
            // et non « les Réglages de l'iPhone », et le serveur saura vers
            // quel store envoyer. Un serveur qui ne le lit pas encore l'ignore.
            .add(PLATFORM_HEADER, PLATFORM)

        store(credential)?.let { store ->
            val token = store.read() ?: throw ApiError.NotAuthenticated
            // Tel quel, comme `URLRequest` le pose : OkHttp refuserait — d'une
            // exception qui n'est pas une `ApiError` — un jeton qui ne serait
            // pas en ASCII.
            headers.addUnsafeNonAscii("Authorization", "Bearer $token")
        }

        val request = Request.Builder().url(url)

        if (body != null) {
            headers.add("Content-Type", body.contentType)
            request.method(method, body.bytes.toRequestBody(body.contentType.toMediaType()))
        } else {
            // OkHttp exige un corps pour ces trois méthodes ; iOS n'en envoie
            // aucun. Un corps vide, sans type, est ce qui s'en approche.
            request.method(method, if (method in METHODS_WITH_BODY) ByteArray(0).toRequestBody() else null)
        }

        return request.headers(headers.build()).build()
    }

    private suspend inline fun <reified R> send(
        method: String,
        path: String,
        body: Body? = null,
        credential: Credential = Credential.Session,
    ): R {
        val request = makeRequest(method, path, credential, body)
        return decode(serializer<R>(), performRaw(request, credential))
    }

    private suspend fun sendIgnoringResponse(
        method: String,
        path: String,
        body: Body? = null,
        credential: Credential = Credential.Session,
    ) {
        performRaw(makeRequest(method, path, credential, body), credential)
    }

    private fun <R> decode(deserializer: DeserializationStrategy<R>, data: ByteArray): R =
        try {
            MemoBookJson.decodeFromString(deserializer, data.toString(Charsets.UTF_8))
        } catch (error: Exception) {
            throw ApiError.Decoding(error)
        }

    /** Exécute la requête et traduit tout ce qui n'est pas un 2xx en [ApiError]. */
    private suspend fun performRaw(request: Request, credential: Credential): ByteArray {
        val log = networkLog
        val started = log?.start(request) ?: 0L

        val response = try {
            client.newCall(request).await()
        } catch (error: IOException) {
            log?.fail(request, error, started)
            // Porte close sur l'adresse configurée, et un secours : on y bascule
            // et on rejoue **la même** requête, une fois. Le secours qui échoue
            // à son tour remonte son erreur comme n'importe quelle autre.
            val retried = rebasedOnFallback(request, error)
            if (retried != null) {
                log?.fallback(request.url, retried.url)
                return performRaw(retried, credential)
            }
            throw ApiError.Transport(error, request.url.toUri())
        }

        log?.finish(request, response.statusCode, started)

        if (response.statusCode !in 200 until 300) {
            // Le JSON de l'app, et non un décodeur nu : le solde d'un refus de
            // crédit porte une date (`resetsAt`) en ISO 8601.
            val body = ApiErrorBody.parse(response.data)

            // Un jeton refusé ne vaudra pas mieux au prochain essai : on efface
            // celui qui a été présenté.
            if (response.statusCode == 401) {
                store(credential)?.clear()
            }

            // Le crédit du jour épuisé garde son solde jusqu'à la file — voir
            // `ApiError.DailyCreditExhausted`.
            if (body?.error == ApiError.DAILY_CREDIT_EXHAUSTED_CODE) {
                throw ApiError.DailyCreditExhausted(
                    message = body.message ?: DailyCreditCopy.exhaustedTitle,
                    credit = body.dailyCredit,
                )
            }

            throw ApiError.Server(
                statusCode = response.statusCode,
                code = body?.error,
                message = body?.message ?: "Le serveur a répondu ${response.statusCode}.",
            )
        }

        return response.data
    }

    /**
     * La même requête, réécrite sur l'adresse de secours — ou `null` quand il
     * n'y a pas lieu de basculer.
     *
     * **L'émulateur, et lui seul, a un secours** : c'est là que la
     * configuration vise le Mac avec la production derrière
     * ([ApiConfiguration.effective]). Le premier appel qui trouve porte close —
     * connexion refusée, hôte introuvable — bascule le client entier sur le
     * secours pour la durée de la session ; les suivants y vont tout droit.
     * « Testing mode » marche donc que le back-end du Mac tourne ou non (Hugo,
     * 16/09/2026).
     *
     * Un délai dépassé ne bascule pas : un serveur local qui rame n'est pas un
     * serveur absent, et changer d'avis au bout de soixante secondes serait
     * pire que l'erreur. Et on ne bascule qu'une fois : une adresse de secours
     * qui refuse aussi ne fait pas repartir vers la première.
     */
    private fun rebasedOnFallback(request: Request, error: IOException): Request? {
        val fallback = fallbackBaseUrl ?: return null
        if (error !is ConnectException && error !is UnknownHostException) return null
        synchronized(this) {
            if (activeBaseUrl != configuredBaseUrl) return null
            activeBaseUrl = fallback
        }
        val rebased = request.url.newBuilder()
            .scheme(fallback.scheme)
            .host(fallback.host)
            .port(fallback.port)
            .build()
        return request.newBuilder().url(rebased).build()
    }

    /** Ce que la réponse a rendu : le statut et le corps, déjà lu. */
    private class HttpResult(val statusCode: Int, val data: ByteArray)

    /**
     * L'appel OkHttp, suspendu et **annulable** : annuler la coroutine annule
     * l'appel en vol. Le corps est lu dans le rappel, sur le fil d'OkHttp — le
     * fil de l'appelant n'attend jamais une socket.
     */
    private suspend fun Call.await(): HttpResult = suspendCancellableCoroutine { continuation ->
        continuation.invokeOnCancellation { cancel() }
        enqueue(
            object : Callback {
                override fun onFailure(call: Call, e: IOException) {
                    continuation.resumeWithException(e)
                }

                override fun onResponse(call: Call, response: Response) {
                    val result = try {
                        response.use { HttpResult(it.code, it.body.bytes()) }
                    } catch (e: IOException) {
                        continuation.resumeWithException(e)
                        return
                    }
                    continuation.resume(result)
                }
            },
        )
    }

    /**
     * Le corps du `PATCH` des couvertures : le plat, et **un seul geste** —
     * c'est ce que [BookCoverEdit] porte, et le serveur ne touche à rien
     * d'autre.
     */
    private fun coverEditBody(edit: BookCoverEdit): JsonObject = buildJsonObject {
        when (edit) {
            is BookCoverEdit.Style -> {
                put("face", edit.face.rawValue)
                put("styleId", edit.styleId)
            }
            // « Retirer la photo » est un `null` explicite, que le JSON de
            // l'app aurait avalé : il s'écrit ici à la main, ce qui distingue
            // « pas touché » de « effacée ».
            is BookCoverEdit.Photo -> {
                put("face", edit.face.rawValue)
                put("photoId", edit.photoId?.let(::JsonPrimitive) ?: JsonNull)
            }
            is BookCoverEdit.Texts -> {
                put("face", edit.face.rawValue)
                put("title", edit.title)
                put("subtitle", edit.subtitle)
            }
            is BookCoverEdit.Stats -> {
                put("face", CoverFace.Back.rawValue)
                put("statIds", JsonArray(edit.statIds.map(::JsonPrimitive)))
            }
        }
    }

    /**
     * Le corps du `PATCH` des réglages : **un seul réglage à la fois** — un
     * champ, sauf l'assortiment de typographies, qui pose ses quatre polices et
     * les pointillés ensemble ([BookCustomisationEdit.FontCombo]).
     *
     * Seul le champ qui vaut quelque chose est écrit : le serveur ne touche
     * qu'aux champs présents, et n'efface que ceux posés explicitement à
     * `null`. C'est ce qui distingue « je n'ai pas parlé de la date de fin » de
     * « il n'y a plus de date de fin ».
     */
    private fun tripSettingsPatch(edit: TripSettingsEdit): JsonObject = buildJsonObject {
        when (edit) {
            is TripSettingsEdit.Name -> put("name", edit.value)
            // Les deux dates s'écrivent **ensemble**, `null` compris : effacer
            // une date de fin, c'est envoyer `endDate: null`.
            is TripSettingsEdit.Dates -> {
                put("startDate", edit.start?.let { JsonPrimitive(MemoBookDate.format(it)) } ?: JsonNull)
                put("endDate", edit.end?.let { JsonPrimitive(MemoBookDate.format(it)) } ?: JsonNull)
            }
            is TripSettingsEdit.NarrationPace -> put("narrationPace", edit.value.rawValue)
            is TripSettingsEdit.Notifications -> put("notificationsEnabled", edit.value)
            is TripSettingsEdit.NotificationPreferences ->
                put(
                    "notifications",
                    MemoBookJson.encodeToJsonElement(TripNotificationPreferences.serializer(), edit.value),
                )
            is TripSettingsEdit.Theme -> put("theme", edit.value)
            is TripSettingsEdit.PublicGallery -> put("isPublicGallery", edit.value)
        }
    }

    private fun tripSettingsPatch(edit: BookCustomisationEdit): JsonObject = buildJsonObject {
        when (edit) {
            is BookCustomisationEdit.PhotoTextRatio -> put("photoTextRatio", edit.value)
            is BookCustomisationEdit.TargetPageCount -> put("targetPageCount", edit.value)
            is BookCustomisationEdit.FunFacts -> put("funFactsEnabled", edit.value)
            is BookCustomisationEdit.Rules -> put("rulesEnabled", edit.value)
            is BookCustomisationEdit.DecorationQuota -> put("decorationQuota", edit.value)
            is BookCustomisationEdit.FontDisplay -> put("fontDisplay", edit.value)
            is BookCustomisationEdit.FontTitle -> put("fontTitle", edit.value)
            is BookCustomisationEdit.FontHand -> put("fontHand", edit.value)
            is BookCustomisationEdit.FontFacts -> put("fontFacts", edit.value)
            is BookCustomisationEdit.FontCombo -> {
                put("rulesEnabled", edit.rulesEnabled)
                put("fontDisplay", edit.combo.font(BookFontRole.Titles))
                put("fontTitle", edit.combo.font(BookFontRole.Subtitles))
                put("fontHand", edit.combo.font(BookFontRole.Texts))
                put("fontFacts", edit.combo.font(BookFontRole.FunFacts))
            }
            is BookCustomisationEdit.Quiz -> put("quizEnabled", edit.value)
            is BookCustomisationEdit.FreeZones -> put("freeZonesEnabled", edit.value)
            is BookCustomisationEdit.Crossword -> put("crosswordEnabled", edit.value)
        }
    }

    // endregion

    // region Les corps et les réponses d'une seule route

    @Serializable private class AccountResponse(val account: Account)
    @Serializable private class ShowcasesResponse(val showcases: List<Showcase>)
    @Serializable private class JoinBody(val code: String)
    @Serializable private class IdReceipt(val id: String)
    @Serializable private class FaqVoteBody(val isHelpful: Boolean, val appVersion: String?)
    @Serializable private class FaqVotesResponse(val votes: List<FaqVote>)
    @Serializable private class CancellationBody(val reason: String?)
    @Serializable private class AppStoreTransactionBody(val signedTransaction: String, val memoId: String?)
    @Serializable private class GooglePlayPurchaseBody(val purchaseToken: String, val productId: String, val memoId: String?)
    @Serializable private class ConnectorBody(val isEnabled: Boolean)
    @Serializable private class ConnectorResponse(val key: String)
    @Serializable private class LinkDeviceBody(val deviceToken: String)
    @Serializable private class LinkedDeviceResponse(val deviceId: String)
    @Serializable private class MemosResponse(val memos: List<MemoSummary>)
    @Serializable private class QuoteBody(val copies: Int, val shippingSpeed: ShippingSpeed)
    @Serializable private class UrlResponse(val url: String)
    @Serializable private class CoverPhotoResponse(val photo: CoverPhoto)
    @Serializable private class StripeVersionBody(val stripeApiVersion: String?)
    @Serializable private class SetupIntentResponse(val clientSecret: String)
    @Serializable private class OrdersResponse(val orders: List<PrintOrder>)

    // endregion

    companion object {
        /**
         * L'en-tête qui porte le fuseau de l'appareil (identifiant IANA), posé
         * sur chaque appel — voir [makeRequest].
         */
        const val TIME_ZONE_HEADER = "X-Time-Zone"
        const val PLATFORM_HEADER = "X-App-Platform"
        const val PLATFORM = "android"

        private const val JSON = "application/json"
        private val METHODS_WITH_BODY = setOf("POST", "PUT", "PATCH")
    }
}
