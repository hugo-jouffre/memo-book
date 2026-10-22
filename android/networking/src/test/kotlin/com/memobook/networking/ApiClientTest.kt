package com.memobook.networking

import com.memobook.core.BookCustomisationEdit
import com.memobook.core.BookFontCombo
import com.memobook.core.ChatTextTurn
import com.memobook.core.EntryKind
import com.memobook.core.MemoBookDate
import com.memobook.core.MemoBookJson
import com.memobook.core.NewTextEntry
import com.memobook.core.PushEnvironment
import com.memobook.core.PushTokenRegistration
import com.memobook.core.Status
import com.memobook.core.SupportMessage
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.cancelAndJoin
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.boolean
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import okhttp3.Call
import okhttp3.Interceptor
import okhttp3.OkHttpClient
import okhttp3.Protocol
import okhttp3.Request
import okhttp3.Response
import okhttp3.ResponseBody.Companion.toResponseBody
import okio.Buffer
import java.io.IOException
import java.net.ConnectException
import java.net.SocketTimeoutException
import java.net.URI
import java.net.UnknownHostException
import java.time.Instant
import java.time.ZoneId
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import kotlin.test.BeforeTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertIs
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue
import kotlin.test.fail

/**
 * Intercepte les requêtes pour tester le client sans serveur — le
 * `StubURLProtocol` d'iOS : un intercepteur d'application OkHttp qui garde la
 * dernière requête et son corps, et rend la réponse scriptée par [handler].
 */
class StubInterceptor : Interceptor {
    @Volatile var handler: ((Request) -> Pair<Int, String>)? = null
    @Volatile var lastRequest: Request? = null
    @Volatile var lastBody: ByteArray? = null

    override fun intercept(chain: Interceptor.Chain): Response {
        val request = chain.request()
        lastRequest = request
        // OkHttp pose un corps vide sur un POST qui n'en a pas ; iOS n'en pose
        // aucun. Les deux se lisent ici comme « pas de corps ».
        lastBody = request.body?.let { body ->
            Buffer().also(body::writeTo).readByteArray()
        }?.takeIf { it.isNotEmpty() }

        val handler = handler ?: throw IOException("badServerResponse")
        val (status, json) = handler(request)
        return Response.Builder()
            .request(request)
            .protocol(Protocol.HTTP_1_1)
            .code(status)
            .message("")
            .body(json.toResponseBody())
            .build()
    }
}

class ApiClientTest {
    private lateinit var stub: StubInterceptor
    private lateinit var httpClient: OkHttpClient
    private val baseUrl = URI("https://api.test")

    @BeforeTest
    fun setUp() {
        stub = StubInterceptor()
        httpClient = OkHttpClient.Builder().addInterceptor(stub).build()
    }

    /**
     * Un client identifié par une **session de compte** : c'est ce que
     * présentent toutes les routes qui touchent à quelque chose de quelqu'un.
     * Le jeton d'appareil ne sert plus qu'à l'enregistrement.
     */
    private fun makeClient(
        sessionToken: String? = "jeton-de-session",
        deviceToken: String? = "jeton-d-appareil",
    ) = MemoBookApiClient(
        configuration = ApiConfiguration(baseUrl),
        tokenStore = InMemoryTokenStore(deviceToken),
        sessionStore = InMemoryTokenStore(sessionToken),
        httpClient = httpClient,
    )

    private fun respond(status: Int, json: String) {
        stub.handler = { status to json }
    }

    private val lastRequest: Request get() = assertNotNull(stub.lastRequest)
    private val lastBodyText: String get() = stub.lastBody?.toString(Charsets.UTF_8).orEmpty()
    private fun lastBodyJson(): JsonObject = MemoBookJson.parseToJsonElement(lastBodyText).jsonObject
    private fun lastBodyStrings(): Map<String, String> = lastBodyJson().mapValues { it.value.jsonPrimitive.content }

    private suspend fun expectApiError(block: suspend () -> Unit): ApiError {
        try {
            block()
        } catch (error: ApiError) {
            return error
        }
        fail("L'appel devait échouer.")
    }

    // region L'adresse de secours

    /** Compte les requêtes par hôte, depuis l'intercepteur. */
    private class HostTally {
        private val counts = ConcurrentHashMap<String, Int>()
        fun record(host: String?) {
            counts.merge(host ?: "?", 1, Int::plus)
        }
        fun count(host: String): Int = counts[host] ?: 0
    }

    private fun makeClientWithFallback() = MemoBookApiClient(
        configuration = ApiConfiguration(
            baseUrl = URI("http://localhost:3000"),
            fallbackBaseUrl = URI("https://api.production.test"),
        ),
        tokenStore = InMemoryTokenStore("jeton-d-appareil"),
        sessionStore = InMemoryTokenStore("jeton-de-session"),
        httpClient = httpClient,
    )

    private val accountJson =
        """{"account":{"id":"a1","email":"demo@memo-book.com","firstName":"Camille","lastName":null,"createdAt":"2026-09-01T10:00:00.000Z"}}"""

    /**
     * Rien n'écoute sur `localhost` : le client bascule sur le secours, rejoue
     * la requête, et **y reste** pour la suite de la session.
     */
    @Test
    fun fallsBackWhenLocalhostRefusesAndStaysThere() = runTest {
        val client = makeClientWithFallback()
        val tally = HostTally()

        stub.handler = { request ->
            val host = request.url.host
            tally.record(host)
            if (host == "localhost") throw ConnectException("Connection refused")
            200 to accountJson
        }

        val account = client.currentAccount()
        assertEquals("a1", account.id)
        assertEquals("api.production.test", lastRequest.url.host)
        assertEquals("/v1/auth/me", lastRequest.url.encodedPath)
        // Le jeton de session voyage avec la requête rejouée.
        assertEquals("Bearer jeton-de-session", lastRequest.header("Authorization"))

        client.currentAccount()
        assertEquals(1, tally.count("localhost"), "une seule tentative sur localhost par session")
        assertEquals(2, tally.count("api.production.test"))
    }

    /** Un délai dépassé n'est pas une porte close : on ne bascule pas. */
    @Test
    fun timeoutDoesNotFallBack() = runTest {
        val client = makeClientWithFallback()
        val tally = HostTally()

        stub.handler = { request ->
            tally.record(request.url.host)
            throw SocketTimeoutException("timeout")
        }

        val error = expectApiError { client.currentAccount() }
        assertTrue(error.isTransport)
        assertEquals(1, tally.count("localhost"))
        assertEquals(0, tally.count("api.production.test"))
    }

    /**
     * Sans secours configuré — un appareil, la production —, une porte close
     * reste une erreur de transport, comme avant.
     */
    @Test
    fun noFallbackWithoutFallbackAddress() = runTest {
        val client = makeClient()
        stub.handler = { throw ConnectException("Connection refused") }

        val error = expectApiError { client.currentAccount() }
        assertTrue(error.isTransport)
    }

    /** Un hôte introuvable est une porte close, comme une connexion refusée. */
    @Test
    fun unknownHostAlsoFallsBack() = runTest {
        val client = makeClientWithFallback()
        stub.handler = { request ->
            if (request.url.host == "localhost") throw UnknownHostException("localhost")
            200 to accountJson
        }

        assertEquals("a1", client.currentAccount().id)
        assertEquals("api.production.test", lastRequest.url.host)
        assertEquals("https", lastRequest.url.scheme)
        assertEquals(443, lastRequest.url.port)
    }

    /**
     * On ne bascule qu'une fois : un secours qui refuse aussi remonte son
     * erreur, et l'appel suivant y retourne tout droit, sans repasser par la
     * première adresse.
     */
    @Test
    fun aRefusingFallbackSurfacesItsErrorAndDoesNotSwitchBack() = runTest {
        val client = makeClientWithFallback()
        val tally = HostTally()
        stub.handler = { request ->
            tally.record(request.url.host)
            throw ConnectException("Connection refused")
        }

        val error = expectApiError { client.currentAccount() }
        assertTrue(error.isTransport)
        assertEquals(URI("https://api.production.test/v1/auth/me"), (error as ApiError.Transport).url)

        expectApiError { client.currentAccount() }
        assertEquals(1, tally.count("localhost"))
        assertEquals(2, tally.count("api.production.test"))
    }

    /** La bascule se lit dans la trace : une ligne « ↪︎ », qui nomme les deux hôtes. */
    @Test
    fun theFallbackIsTraced() = runTest {
        val lines = mutableListOf<String>()
        val sink = object : NetworkLog.Sink {
            override fun debug(line: String) { synchronized(lines) { lines += line } }
            override fun notice(line: String) { synchronized(lines) { lines += line } }
            override fun error(line: String) { synchronized(lines) { lines += line } }
        }
        val client = MemoBookApiClient(
            configuration = ApiConfiguration(URI("http://localhost:3000"), fallbackBaseUrl = URI("https://api.production.test")),
            tokenStore = InMemoryTokenStore("jeton-d-appareil"),
            sessionStore = InMemoryTokenStore("jeton-de-session"),
            httpClient = httpClient,
            networkLog = NetworkLog(sink),
        )
        stub.handler = { request ->
            if (request.url.host == "localhost") throw ConnectException("Connection refused")
            200 to accountJson
        }

        client.currentAccount()

        assertEquals("→ GET /v1/auth/me", lines[0])
        assertTrue(lines[1].startsWith("✗ GET /v1/auth/me ("), lines[1])
        assertTrue(lines[1].endsWith("— connexion refusée (rien n’écoute)"), lines[1])
        assertEquals("↪︎ rien n’écoute sur localhost : bascule sur api.production.test pour la suite de la session", lines[2])
        assertTrue(lines.last().startsWith("← 200 GET /v1/auth/me ("), lines.last())
    }

    // endregion

    @Test
    fun registerDeviceStoresToken() = runTest {
        val store = InMemoryTokenStore()
        val client = MemoBookApiClient(
            configuration = ApiConfiguration(baseUrl),
            tokenStore = store,
            sessionStore = InMemoryTokenStore(),
            httpClient = httpClient,
        )

        respond(201, """{"deviceId":"d1","token":"secret"}""")
        client.ensureDeviceRegistered()

        assertEquals("secret", store.read())
    }

    @Test
    fun registeredDeviceIsNotRegisteredTwice() = runTest {
        val client = makeClient(deviceToken = "déjà-là")
        stub.handler = { fail("Aucune requête ne devait partir : l'appareil a déjà un token.") }

        client.ensureDeviceRegistered()
        assertNull(stub.lastRequest)
    }

    /**
     * Les carnets appartiennent à un compte : c'est le jeton de session qui
     * part, jamais celui de l'appareil.
     */
    @Test
    fun authorizationHeaderCarriesTheSessionToken() = runTest {
        val client = makeClient(sessionToken = "ma-session", deviceToken = "mon-appareil")
        respond(200, """{"memos":[]}""")

        client.memos()

        assertEquals("Bearer ma-session", lastRequest.header("Authorization"))
    }

    @Test
    fun missingTokenFailsBeforeAnyRequest() = runTest {
        val client = makeClient(sessionToken = null)

        val error = expectApiError { client.memos() }
        assertIs<ApiError.NotAuthenticated>(error)
        assertNull(stub.lastRequest)
    }

    /**
     * Le back-end renvoie déjà un message en français : il doit arriver intact
     * jusqu'à l'écran, sans être remplacé par un code HTTP.
     */
    @Test
    fun serverMessageIsSurfacedToTheUser() = runTest {
        val client = makeClient()
        respond(400, """{"error":"empty_memo","message":"Ce carnet ne contient encore aucun souvenir."}""")

        val error = expectApiError { client.startRender("m1") }
        assertEquals("Ce carnet ne contient encore aucun souvenir.", error.errorDescription)
        assertFalse(error.isRetryable)
    }

    @Test
    fun unauthorizedClearsStoredToken() = runTest {
        val sessionStore = InMemoryTokenStore("périmé")
        val deviceStore = InMemoryTokenStore("appareil")
        val client = MemoBookApiClient(
            configuration = ApiConfiguration(baseUrl),
            tokenStore = deviceStore,
            sessionStore = sessionStore,
            httpClient = httpClient,
        )
        respond(401, """{"error":"unauthorized","message":"Token invalide."}""")

        runCatching { client.memos() }

        assertNull(sessionStore.read(), "Un token refusé doit être oublié.")
        assertNotNull(
            deviceStore.read(),
            "Seul le jeton présenté est effacé : celui de l'appareil n'a rien à voir avec un 401 de session.",
        )
    }

    /**
     * Supprimer son compte vide **les deux** magasins : le compte n'existe
     * plus, et son appareil a disparu avec lui côté serveur.
     */
    @Test
    fun deleteAccountClearsBothTokens() = runTest {
        val sessionStore = InMemoryTokenStore("ma-session")
        val deviceStore = InMemoryTokenStore("mon-appareil")
        val client = MemoBookApiClient(
            configuration = ApiConfiguration(baseUrl),
            tokenStore = deviceStore,
            sessionStore = sessionStore,
            httpClient = httpClient,
        )
        respond(204, "")

        client.deleteAccount()

        assertEquals("DELETE", lastRequest.method)
        assertEquals("/v1/accounts/me", lastRequest.url.encodedPath)
        assertNull(sessionStore.read())
        assertNull(deviceStore.read())
    }

    /**
     * « Exporter mes données » part avec la session, **sans corps** : la
     * requête ne porte aucune adresse, le serveur n'écrit qu'à celle du compte.
     * La réponse dit où le lien est parti, et jusqu'à quand.
     */
    @Test
    fun dataExportIsRequestedWithTheSessionAndNoAddress() = runTest {
        val client = makeClient()
        respond(
            202,
            """{"email":"hugo@memobook.app","requestedAt":"2026-10-01T16:02:00.000Z",""" +
                """"expiresAt":"2026-10-08T16:02:00.000Z","alreadyRequested":false}""",
        )

        val receipt = client.requestDataExport()

        assertEquals("POST", lastRequest.method)
        assertEquals("/v1/accounts/me/export", lastRequest.url.encodedPath)
        assertEquals("Bearer jeton-de-session", lastRequest.header("Authorization"))
        assertNull(stub.lastBody)
        assertEquals("hugo@memobook.app", receipt.email)
        assertEquals(MemoBookDate.parse("2026-10-08T16:02:00.000Z"), receipt.expiresAt)
        assertFalse(receipt.alreadyRequested)
    }

    /**
     * « Mot de passe oublié » part **sans** jeton : c'est parce qu'on ne peut
     * pas entrer qu'on l'appelle. Un client sans aucune session doit donc
     * pouvoir l'envoyer, et l'adresse voyage dans le corps.
     */
    @Test
    fun passwordResetRequestNeedsNoSession() = runTest {
        val client = makeClient(sessionToken = null, deviceToken = null)
        respond(202, "")

        client.requestPasswordReset("hugo@memobook.app")

        assertEquals("POST", lastRequest.method)
        assertEquals("/v1/auth/password/forgot", lastRequest.url.encodedPath)
        assertNull(lastRequest.header("Authorization"))
        assertEquals(mapOf("email" to "hugo@memobook.app"), lastBodyStrings())
    }

    /**
     * Le téléphone dit où le joindre : le jeton, son environnement, son fuseau
     * — au nom de la session, puisque le jeton part avec elle.
     */
    @Test
    fun pushTokenIsSentWithTheSession() = runTest {
        val client = makeClient()
        respond(204, "")

        client.registerPushToken(
            PushTokenRegistration(
                token = "00ab10ff",
                environment = PushEnvironment.Sandbox,
                timeZone = "Europe/Paris",
                appVersion = "0.1.0 (8)",
            ),
        )

        assertEquals("POST", lastRequest.method)
        assertEquals("/v1/push-tokens", lastRequest.url.encodedPath)
        assertEquals("Bearer jeton-de-session", lastRequest.header("Authorization"))
        assertEquals(
            mapOf("token" to "00ab10ff", "environment" to "sandbox", "timeZone" to "Europe/Paris", "appVersion" to "0.1.0 (8)"),
            lastBodyStrings(),
        )
    }

    /**
     * Un assortiment de typographies part avec les pointillés qu'il décide,
     * dans **le même** `PATCH` : le serveur ne passe jamais par un Manuscrit
     * aux pointillés allumés, et rien d'autre n'est réécrit.
     */
    @Test
    fun aFontComboCarriesItsRulesInTheSamePatch() = runTest {
        val client = makeClient()
        respond(500, """{"error":"Indisponible"}""")

        runCatching {
            client.updateBookCustomisation(
                tripId = "trip-1",
                edit = BookCustomisationEdit.FontCombo(BookFontCombo.handwritten, rulesEnabled = false),
            )
        }

        assertEquals("PATCH", lastRequest.method)
        assertEquals("/v1/trips/trip-1/settings", lastRequest.url.encodedPath)
        val body = lastBodyJson()
        assertEquals(setOf("rulesEnabled", "fontDisplay", "fontTitle", "fontHand", "fontFacts"), body.keys)
        assertEquals(false, body["rulesEnabled"]?.jsonPrimitive?.boolean)
        assertEquals("Hansley", body["fontDisplay"]?.jsonPrimitive?.content)
        assertEquals("Gloria Hallelujah", body["fontHand"]?.jsonPrimitive?.content)
    }

    /**
     * Le nouveau mot de passe répond comme une connexion : la session rendue
     * est **gardée**, pour que l'app entre sans rien retaper.
     */
    @Test
    fun resetPasswordStoresTheNewSession() = runTest {
        val sessionStore = InMemoryTokenStore(null)
        val client = MemoBookApiClient(
            configuration = ApiConfiguration(baseUrl),
            tokenStore = InMemoryTokenStore(null),
            sessionStore = sessionStore,
            httpClient = httpClient,
        )
        respond(
            200,
            """{"token":"session-neuve","expiresAt":"2027-01-01T00:00:00.000Z","account":{"id":"a1","email":"hugo@memobook.app","createdAt":"2026-01-01T00:00:00.000Z"}}""",
        )

        val opened = client.resetPassword(token = "secret", password = "nouveau2027")

        assertEquals("/v1/auth/password/reset", lastRequest.url.encodedPath)
        assertEquals(mapOf("token" to "secret", "password" to "nouveau2027"), lastBodyStrings())
        assertEquals("hugo@memobook.app", opened.account.email)
        assertEquals("session-neuve", sessionStore.read())
    }

    @Test
    fun serverErrorIsRetryable() = runTest {
        val client = makeClient()
        respond(503, """{"error":"unavailable","message":"Service indisponible."}""")

        val error = expectApiError { client.memos() }
        assertTrue(error.isRetryable)
    }

    @Test
    fun audioUploadSendsMultipartWithFileAndCaptureDate() = runTest {
        val client = makeClient()
        respond(
            201,
            """
            {
              "id":"e1","memoId":"m1","kind":"audio","status":"pending",
              "transcript":null,"capturedAt":"2026-08-08T09:00:00.000Z",
              "placeLabel":"Kyoto","error":null,"media":null,
              "createdAt":"2026-08-08T09:00:01.000Z"
            }
            """.trimIndent(),
        )

        val capturedAt = assertNotNull(MemoBookDate.parse("2026-08-08T09:00:00.000Z"))
        val entry = client.uploadAudio(
            memoId = "m1",
            data = "son".toByteArray(),
            filename = "memo.m4a",
            mimeType = "audio/mp4",
            capturedAt = capturedAt,
            durationSeconds = 95.0,
            placeLabel = "Kyoto",
        )

        assertEquals(Status.Pending, entry.status)
        assertEquals(EntryKind.Audio, entry.kind)

        val contentType = lastRequest.header("Content-Type")
        assertEquals(true, contentType?.startsWith("multipart/form-data; boundary="))

        val body = lastBodyText
        assertTrue(body.contains("""name="file"; filename="memo.m4a""""))
        assertTrue(body.contains("2026-08-08T09:00:00.000Z"), "La date de capture doit être transmise")
        // La durée part avec le fichier : c'est elle qui décompte les limites
        // de souvenirs, et le serveur ne peut pas la déduire du poids, qui
        // dépend du codec. Arrondie à la seconde.
        assertTrue(body.contains("""name="durationSeconds""""), "La durée doit être transmise")
        assertTrue(body.contains("95"), "La durée doit être transmise arrondie à la seconde")
        assertTrue(body.contains("Kyoto"))
    }

    @Test
    fun textEntryIsSentAsJson() = runTest {
        val client = makeClient()
        respond(
            201,
            """
            {
              "id":"e2","memoId":"m1","kind":"text","status":"ready",
              "transcript":"Une note","capturedAt":"2026-08-08T09:00:00.000Z",
              "placeLabel":null,"error":null,"media":null,
              "createdAt":"2026-08-08T09:00:00.000Z"
            }
            """.trimIndent(),
        )

        val entry = client.addTextEntry(memoId = "m1", entry = NewTextEntry(transcript = "Une note"))

        assertEquals("Une note", entry.transcript)
        assertEquals("application/json", lastRequest.header("Content-Type"))
        assertTrue(lastBodyText.contains(""""kind":"text""""))
    }

    /** Quitter l'écran annule la coroutine, et la coroutine annule l'appel OkHttp en vol. */
    @Test
    fun cancellingTheCallerCancelsTheCall() = runBlocking {
        val started = CountDownLatch(1)
        val calls = mutableListOf<Call>()
        val blocking = OkHttpClient.Builder()
            .addInterceptor { chain ->
                synchronized(calls) { calls += chain.call() }
                started.countDown()
                // Attend jusqu'à l'annulation, qui coupe la requête.
                while (!chain.call().isCanceled()) Thread.sleep(5)
                throw IOException("Canceled")
            }
            .build()
        val client = MemoBookApiClient(
            configuration = ApiConfiguration(baseUrl),
            tokenStore = InMemoryTokenStore("jeton-d-appareil"),
            sessionStore = InMemoryTokenStore("jeton-de-session"),
            httpClient = blocking,
        )

        val job = launch(Dispatchers.IO) { client.memos() }
        assertTrue(started.await(5, TimeUnit.SECONDS))
        job.cancelAndJoin()

        assertTrue(job.isCancelled)
        assertTrue(synchronized(calls) { calls.single() }.isCanceled())
    }

    // region Le support (T226, 06/10/2026)

    @Test
    fun aSupportMessageIsPostedWithItsSource() = runTest {
        val client = makeClient()
        respond(201, """{"id":"s1","createdAt":"2026-10-07T10:00:00.000Z"}""")

        client.sendSupportMessage(
            SupportMessage(source = SupportMessage.Source.FoundersNote, message = "Super carnet", appVersion = "0.1.0 (21)"),
        )

        assertEquals("POST", lastRequest.method)
        assertEquals("/v1/support/messages", lastRequest.url.encodedPath)
        assertTrue(lastBodyText.contains(""""source":"founders_note""""))
        assertTrue(lastBodyText.contains(""""message":"Super carnet""""))
    }

    @Test
    fun aFaqVoteIsPutOnItsQuestion() = runTest {
        val client = makeClient()
        respond(200, """{"questionId":"faq.carnet.pages","isHelpful":false,"updatedAt":"2026-10-07T10:00:00.000Z"}""")

        client.voteOnFaq(questionId = "faq.carnet.pages", isHelpful = false, appVersion = null)

        assertEquals("PUT", lastRequest.method)
        assertEquals("/v1/support/faq-votes/faq.carnet.pages", lastRequest.url.encodedPath)
        assertTrue(lastBodyText.contains(""""isHelpful":false"""))
    }

    @Test
    fun theFaqVotesAreRead() = runTest {
        val client = makeClient()
        respond(
            200,
            """{"votes":[{"questionId":"faq.carnet.pages","isHelpful":true,"updatedAt":"2026-10-07T10:00:00.000Z"}]}""",
        )

        val votes = client.faqVotes()

        assertEquals(listOf("faq.carnet.pages"), votes.map { it.questionId })
        assertEquals(true, votes.firstOrNull()?.isHelpful)
    }

    // endregion

    // region Le crédit du jour (03/10/2026)

    /**
     * Le fuseau de l'appareil part sur **chaque** appel : le crédit du jour se
     * recharge à minuit chez celui qui raconte.
     */
    @Test
    fun everyRequestCarriesTheDeviceTimeZone() = runTest {
        val client = makeClient()
        respond(200, """{"memos":[]}""")

        client.memos()

        assertEquals(ZoneId.systemDefault().id, lastRequest.header(MemoBookApiClient.TIME_ZONE_HEADER))
        assertEquals("X-Time-Zone", MemoBookApiClient.TIME_ZONE_HEADER)
    }

    /** La plateforme part aussi sur chaque appel (lot B5) : MEMO parle du téléphone, pas de l'iPhone. */
    @Test
    fun everyRequestNamesThePlatform() = runTest {
        val client = makeClient()
        respond(200, """{"memos":[]}""")

        client.memos()

        assertEquals("android", lastRequest.header("X-App-Platform"))
    }

    /**
     * Le refus faute de crédit garde son code **et son solde** jusqu'à la
     * file : c'est `resetsAt` qui dit quand réessayer.
     */
    @Test
    fun aCreditRefusalKeepsItsCodeAndBalance() = runTest {
        val client = makeClient()
        respond(
            429,
            """
            { "error": "daily_credit_exhausted",
              "message": "Le crédit du jour de ce voyage est épuisé. Reviens demain pour continuer, ou passe en illimité.",
              "dailyCredit": { "isUnlimited": false, "limitMs": 300000, "usedMs": 300000, "remainingMs": 0,
                               "textMsPerCharacter": 75, "warningRemainingMs": 30000, "urgentRemainingMs": 5000,
                               "day": "2026-10-03", "resetsAt": "2026-10-03T22:00:00.000Z" } }
            """.trimIndent(),
        )

        val error = expectApiError { client.sendChatText("t1", ChatTextTurn(id = "x", text = "Encore un mot")) }
        assertTrue(error.isDailyCreditExhausted)
        assertEquals("daily_credit_exhausted", error.code)
        assertEquals(429, error.statusCode)
        assertEquals(true, error.dailyCredit?.isExhausted)
        assertEquals(Instant.parse("2026-10-03T22:00:00Z"), error.dailyCredit?.resetsAt)
        assertTrue(error.errorDescription.startsWith("Le crédit du jour"), "Le mot du serveur, tel quel.")
        assertFalse(error.isRetryable, "C'est la file qui repart, à la recharge.")
        assertNotNull(error.recoveryAdvice)
    }

    /**
     * Un solde illisible ne coûte pas le message : le refus reste un refus de
     * crédit, la file retombera sur le minuit suivant.
     */
    @Test
    fun aCreditRefusalWithoutABalanceIsStillACreditRefusal() = runTest {
        val client = makeClient()
        respond(429, """{"error":"daily_credit_exhausted","message":"Épuisé.","dailyCredit":"?"}""")

        val error = expectApiError { client.sendChatText("t1", ChatTextTurn(id = "x", text = "Un mot")) }
        assertTrue(error.isDailyCreditExhausted)
        assertNull(error.dailyCredit)
        assertEquals("Épuisé.", error.errorDescription)
    }

    /**
     * Les autres refus gardent leur forme : le plafond anti-abus reste un
     * `Server(429, "chat_daily_cap", …)`.
     */
    @Test
    fun otherRefusalsKeepTheirShape() = runTest {
        val client = makeClient()
        respond(429, """{"error":"chat_daily_cap","message":"MEMO a besoin d’une pause."}""")

        val error = expectApiError { client.sendChatText("t1", ChatTextTurn(id = "x", text = "Un mot")) }
        val server = assertIs<ApiError.Server>(error)
        assertEquals(429, server.statusCode)
        assertEquals("chat_daily_cap", server.code)
        assertFalse(error.isDailyCreditExhausted)
        assertFalse(error.isDailyCreditTooLong)
        assertEquals("chat_daily_cap", error.code)
    }

    /**
     * Un tour plus long qu'une journée de crédit garde son code jusqu'à la
     * file, quel que soit le statut : ce n'est ni « demain » — le refus de
     * crédit ordinaire —, ni un échec à réessayer, c'est l'illimité.
     */
    @Test
    fun aTurnLongerThanADayKeepsItsCode() = runTest {
        val client = makeClient()
        respond(
            422,
            """{"error":"daily_credit_too_long","message":"Ce vocal dépasse le crédit d’une journée entière.","dailyCredit":{"usedMs":0}}""",
        )

        val error = expectApiError { client.sendChatText("t1", ChatTextTurn(id = "x", text = "Un très long texte")) }
        assertTrue(error.isDailyCreditTooLong)
        assertFalse(error.isDailyCreditExhausted, "Pas « demain » : demain donnerait le même refus.")
        assertEquals(ApiError.DAILY_CREDIT_TOO_LONG_CODE, error.code)
        assertFalse(error.isRetryable)
        assertTrue(error.recoveryAdvice?.contains("illimité") == true)
    }

    // endregion

    // region Le partage et le suivi WhatsApp de la confirmation (T229)

    /**
     * Le lien partagé est **celui que le serveur rend** — page publique
     * `/c/<jeton>` sur l'hôte de l'API —, jamais une URL composée par l'app.
     */
    @Test
    fun theShareLinkIsTheOneTheServerReturns() = runTest {
        val client = makeClient()
        respond(200, """{"url":"https://api.test/c/Zx81kQp2"}""")

        val link = client.bookShareLink("memo-1")

        assertEquals(URI("https://api.test/c/Zx81kQp2"), link)
        assertEquals("POST", lastRequest.method)
        assertEquals("/v1/memos/memo-1/share-link", lastRequest.url.encodedPath)
    }

    /**
     * « Recevoir sur WhatsApp » part sur la commande, l'accord **et** le numéro
     * dans le même corps ; le refus ne porte que l'accord.
     */
    @Test
    fun whatsAppTrackingIsSavedOnTheOrder() = runTest {
        val client = makeClient()
        val order = """
            {"id":"o1","memoId":"memo-1","renderId":"r1","status":"submitted","copies":1,
            "shippingSpeed":"standard","shipping":{"name":"Hugo","line1":"1 rue de Rome",
            "postalCode":"75008","city":"Paris","country":"FR"},"copyOptions":[],
            "notifyByWhatsApp":true,"whatsappPhone":"+33612345678",
            "createdAt":"2026-10-07T10:00:00.000Z","updatedAt":"2026-10-07T10:00:00.000Z"}
        """.trimIndent()
        respond(200, order)

        val saved = client.setOrderWhatsApp(orderId = "o1", phone = "+33612345678")

        assertTrue(saved.notifyByWhatsApp)
        assertEquals("POST", lastRequest.method)
        assertEquals("/v1/orders/o1/whatsapp", lastRequest.url.encodedPath)
        val accepted = lastBodyJson()
        assertEquals(true, accepted["enabled"]?.jsonPrimitive?.boolean)
        assertEquals("+33612345678", (accepted["phone"] as? JsonPrimitive)?.content)

        client.setOrderWhatsApp(orderId = "o1", phone = null)
        val declined = lastBodyJson()
        assertEquals(false, declined["enabled"]?.jsonPrimitive?.boolean)
        assertNull(declined["phone"])
    }

    // endregion
}
