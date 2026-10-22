@file:OptIn(ExperimentalCoroutinesApi::class)

package com.memobook.feature

import com.memobook.core.ChatTurnReceipt
import com.memobook.core.ChatTurnStatus
import com.memobook.core.CreatedTrip
import com.memobook.core.HomeFeed
import com.memobook.core.Traveller
import com.memobook.core.Trip
import com.memobook.core.TripDraft
import com.memobook.core.TripStage
import com.memobook.core.local
import com.memobook.feature.chat.OutgoingTurn
import com.memobook.feature.tripcreation.TripCreationModel
import com.memobook.feature.tripcreation.TripCreationStep
import com.memobook.networking.ApiError
import com.memobook.networking.Connectivity
import com.memobook.recording.PendingRecordingStore
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.async
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.test.setMain
import java.io.IOException
import java.time.Instant
import java.util.UUID
import kotlin.test.AfterTest
import kotlin.test.BeforeTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull
import kotlin.test.assertTrue

/**
 * « Créer un voyage doit être possible hors ligne de bout en bout, puis envoyé
 * au serveur au retour de la connexion. Pareil pour les vocaux et les textes »
 * (Hugo, 01/10/2026).
 *
 * Ce que ça promet, et que ces tests tiennent :
 * - la création va jusqu'au code d'accès **sans le serveur** — seul le code
 *   l'attend ;
 * - le voyage part au retour du réseau, sous l'identifiant que l'app a tiré ;
 * - ce qu'on y a raconté part **après** lui, jamais avant (le serveur
 *   refuserait un vocal pour un carnet qu'il ne connaît pas, et il serait
 *   perdu) ;
 * - la conversation s'ouvre sans réseau, et on peut y raconter.
 *
 * Porté de `OfflineTripCreationTests.swift`. Les cas de « Créer un voyage »
 * traversent `TripCreationModel`, branché sur la file comme l'app le branche —
 * `save` ([RecordingOutbox.saveTrip]) et `sync` ([RecordingOutbox.tripSync]).
 * Restent à porter avec leur écran : les deux cas de la conversation sans
 * réseau (`ChatModel`).
 */
class OfflineTripCreationTest {
    private val dispatcher = StandardTestDispatcher()

    @BeforeTest
    fun setUp() {
        Dispatchers.setMain(dispatcher)
    }

    @AfterTest
    fun tearDown() {
        Dispatchers.resetMain()
        // `debugSetOffline` coupe aussi le double d'API, pour tout le processus.
        SandboxNetwork.isOffline = false
    }

    // MARK: - La création

    @Test
    fun aTripCreatedOfflineReachesTheCodeStepWithoutTheServer() = runTest(dispatcher) {
        val server = FakeServer()
        val outbox = outbox(server)
        outbox.debugSetOffline(true)
        val model = creationModel(outbox)

        walkToTheCodeStep(model, title = "Lisbonne")

        assertEquals(TripCreationStep.Companions, model.step, "La création ne doit pas rester bloquée faute de réseau.")
        assertNull(model.errorMessage)
        assertEquals("Lisbonne", model.trip?.title, "« Commencer ! » doit avoir un voyage à ouvrir.")
        assertNull(model.accessCode, "Le code, lui, ne peut venir que du serveur.")
        assertTrue(server.log.isEmpty())
    }

    @Test
    fun theAccessCodeArrivesWhenTheConnectionComesBack() = runTest(dispatcher) {
        val server = FakeServer()
        val outbox = outbox(server)
        outbox.debugSetOffline(true)
        val model = creationModel(outbox)
        walkToTheCodeStep(model, title = "Lisbonne")

        val waiting = async { model.awaitAccessCode() }
        outbox.debugSetOffline(false)
        waiting.await()

        assertEquals("ABC123", model.accessCode)
        assertEquals(listOf("trip:${model.trip?.id ?: "?"}:Lisbonne"), server.log, "Le serveur reprend l'identifiant de l'app.")
        assertTrue(outbox.localTrips.value.isEmpty(), "Arrivé, le voyage ne se montre plus que depuis le serveur.")
    }

    /**
     * T238 : un voyage a toujours un départ. Ni « Valider » appelé quand même,
     * ni « Passer » ne franchissent l'étape des dates sans lui.
     */
    @Test
    fun noTripIsSavedWithoutADepartureDate() = runTest(dispatcher) {
        val model = creationModel(outbox(FakeServer()))
        model.draft = model.draft.copy(title = "Lisbonne")
        model.validate()
        assertEquals(TripCreationStep.Dates, model.step)

        model.validate()
        model.skip()
        assertEquals(TripCreationStep.Dates, model.step)
        assertNull(model.trip)

        model.draft = model.draft.copy(startDate = Instant.now())
        model.validate()
        assertEquals(TripCreationStep.Notifications, model.step)
    }

    @Test
    fun theIdentifierIsLowercasedLikeTheServerWritesIt() = runTest(dispatcher) {
        val model = creationModel(outbox(FakeServer()))
        walkToTheCodeStep(model, title = "Lisbonne")

        val id = model.trip?.id.orEmpty()
        UUID.fromString(id)
        assertEquals(id.lowercase(), id)
    }

    @Test
    fun goingBackAndRevalidatingCorrectsTheSameTrip() = runTest(dispatcher) {
        val server = FakeServer()
        val outbox = outbox(server)
        outbox.debugSetOffline(true)
        val model = creationModel(outbox)

        walkToTheCodeStep(model, title = "Lisbonne")
        val first = model.trip?.id

        model.goBack()
        model.goBack()
        model.goBack()
        model.draft = model.draft.copy(title = "Lisbonne et Porto")
        walkToTheCodeStep(model, title = null)

        assertEquals(first, model.trip?.id, "Revenir en arrière ne crée pas un second voyage.")
        assertEquals(listOf("Lisbonne et Porto"), outbox.localTrips.value.map { it.draft.title })

        outbox.debugSetOffline(false)
        until("le voyage part") { outbox.localTrips.value.isEmpty() }
        assertEquals(listOf("trip:${first ?: "?"}:Lisbonne et Porto"), server.log, "Une seule création, avec le dernier brouillon.")
    }

    @Test
    fun aRefusedTripSaysSoAndOpensNothing() = runTest(dispatcher) {
        val server = FakeServer()
        server.tripRefusal = "La date de fin précède la date de début."
        val model = creationModel(outbox(server))

        walkToTheCodeStep(model, title = "Lisbonne")
        model.awaitAccessCode()

        assertTrue(model.wasRejected)
        assertEquals(
            "Ton voyage « Lisbonne » n’a pas pu être créé. La date de fin précède la date de début.",
            model.errorMessage,
        )
    }

    // MARK: - Ce qu'on y raconte

    @Test
    fun whatIsToldInATripCreatedOfflineLeavesAfterTheTrip() = runTest(dispatcher) {
        val server = FakeServer()
        val outbox = outbox(server)
        outbox.debugSetOffline(true)

        val trip = outbox.saveTrip(TripDraft(title = "Lisbonne"))
        val outcome = outbox.submit(OutgoingTurn(body = OutgoingTurn.Body.Text("On est arrivés")), trip.id)
        assertEquals(RecordingOutbox.Delivery.Queued, outcome)

        outbox.debugSetOffline(false)
        until("tout est parti") { outbox.pending.value == 0 && outbox.localTrips.value.isEmpty() }

        assertEquals(listOf("trip:${trip.id}:Lisbonne", "turn:${trip.id}"), server.log, "Le voyage d'abord, ce qu'on y a dit ensuite.")
    }

    /**
     * « En ligne » ne veut pas dire « l'API répond » : si la création n'est pas
     * passée, le texte n'est pas envoyé à un carnet que le serveur ne connaît
     * pas — il serait refusé, et perdu.
     */
    @Test
    fun aTurnWaitsForItsTripEvenOnline() = runTest(dispatcher) {
        val server = FakeServer()
        server.unreachable = true
        val outbox = outbox(server)

        val trip = outbox.saveTrip(TripDraft(title = "Lisbonne"))
        until("la création a échoué au transport") { outbox.sending.value == 0 && server.attempts > 0 }
        val outcome = outbox.submit(OutgoingTurn(body = OutgoingTurn.Body.Text("On est arrivés")), trip.id)

        assertEquals(RecordingOutbox.Delivery.Queued, outcome)
        assertTrue(server.log.isEmpty())

        server.unreachable = false
        outbox.flush()
        assertEquals(listOf("trip:${trip.id}:Lisbonne", "turn:${trip.id}"), server.log)
    }

    /**
     * Un voyage que le serveur ne prend pas (une panne de son côté) ne retient
     * que ce qu'on y a dit : le vocal d'un carnet qu'il connaît part.
     */
    @Test
    fun aStuckTripDoesNotHoldBackOtherTrips() = runTest(dispatcher) {
        val server = FakeServer()
        server.tripsUnreachable = true
        val outbox = outbox(server)
        outbox.debugSetOffline(true)

        val stuck = outbox.saveTrip(TripDraft(title = "Lisbonne"))
        outbox.submit(OutgoingTurn(body = OutgoingTurn.Body.Text("Pour Lisbonne")), stuck.id)
        outbox.submit(OutgoingTurn(body = OutgoingTurn.Body.Text("Pour Rome")), "rome")

        outbox.debugSetOffline(false)
        until("le carnet connu a reçu son tour") { outbox.pending.value == 1 }

        assertEquals(listOf("turn:rome"), server.log)
        assertEquals(listOf(stuck.id), outbox.localTrips.value.map { it.id }, "Le voyage attend encore, avec son tour.")
    }

    /**
     * Un serveur qui n'a pas encore la création rejouable tire son propre
     * identifiant : ce qu'on a raconté part vers **son** carnet.
     */
    @Test
    fun turnsFollowTheServerIdentifierWhenItDiffers() = runTest(dispatcher) {
        val server = FakeServer()
        server.ignoresClientIdentifiers = true
        val outbox = outbox(server)
        outbox.debugSetOffline(true)

        val trip = outbox.saveTrip(TripDraft(title = "Lisbonne"))
        outbox.submit(OutgoingTurn(body = OutgoingTurn.Body.Text("On est arrivés")), trip.id)
        outbox.debugSetOffline(false)
        until("tout est parti") { outbox.pending.value == 0 && outbox.localTrips.value.isEmpty() }

        assertEquals(listOf("trip:serveur-1:Lisbonne", "turn:serveur-1"), server.log)
    }

    // MARK: - Où le voyage se montre

    /** L'accueil du jeu d'essai (`HomeFeed.fixture`) arrive avec le bac à sable : un voyage connu suffit ici. */
    @Test
    fun theHomeShowsATripCreatedOfflineFirst() = runTest(dispatcher) {
        val outbox = outbox(FakeServer())
        outbox.debugSetOffline(true)
        val trip = outbox.saveTrip(TripDraft(title = "Lisbonne"))
        val served = HomeFeed(
            traveller = Traveller(id = "t", firstName = "Camille"),
            trips = listOf(Trip(id = "rome", title = "Rome", stage = TripStage.Past)),
        )

        val feed = outbox.mergingLocalTrips(served)

        assertEquals(trip.id, feed.trips.first().id)
        assertEquals(served.trips.size + 1, feed.trips.size)
        assertTrue(feed.ongoingTrips.any { it.id == trip.id }, "Sans date, il commence maintenant.")
    }

    @Test
    fun anotherAccountNeitherSeesNorSendsTheTrip() = runTest(dispatcher) {
        val server = FakeServer()
        val outbox = outbox(server)
        outbox.debugSetOffline(true)
        outbox.setAccount("compte-a")
        outbox.saveTrip(TripDraft(title = "Lisbonne"))

        outbox.setAccount("compte-b")
        outbox.debugSetOffline(false)
        outbox.flush()

        assertTrue(outbox.localTrips.value.isEmpty())
        assertTrue(server.log.isEmpty(), "Le voyage de quelqu'un ne se crée pas sous le nom d'un autre.")

        outbox.setAccount("compte-a")
        assertEquals(listOf("Lisbonne"), outbox.localTrips.value.map { it.draft.title })
    }

    @Test
    fun deletingATripTheServerNeverSawForgetsItsTurnsToo() = runTest(dispatcher) {
        val outbox = outbox(FakeServer())
        outbox.debugSetOffline(true)
        val trip = outbox.saveTrip(TripDraft(title = "Lisbonne"))
        outbox.submit(OutgoingTurn(body = OutgoingTurn.Body.Text("On est arrivés")), trip.id)

        val discarded = outbox.discardLocalTrip(trip.id)

        assertTrue(discarded)
        assertTrue(outbox.localTrips.value.isEmpty())
        assertEquals(0, outbox.pending.value)
    }

    // MARK: - Outils

    private fun creationModel(outbox: RecordingOutbox): TripCreationModel = TripCreationModel(
        save = { draft -> outbox.saveTrip(draft) },
        sync = { id -> outbox.tripSync(id) },
    )

    /**
     * Le nom, le départ — les dates n'ont plus de « Passer » —, puis « Passer »
     * sur les notifications : la validation de la troisième enregistre le
     * voyage.
     */
    private suspend fun walkToTheCodeStep(model: TripCreationModel, title: String?) {
        if (title != null) model.draft = model.draft.copy(title = title)
        model.validate()
        model.draft = model.draft.copy(startDate = Instant.now())
        model.validate()
        model.skip()
    }

    private fun TestScope.outbox(server: FakeServer): RecordingOutbox = RecordingOutbox(
        store = PendingRecordingStore.temporary(Dispatchers.Unconfined),
        trips = PendingTripStore.temporary(Dispatchers.Unconfined),
        connectivity = Connectivity.online,
        send = { _, tripId -> server.send(tripId) },
        createTrip = { draft -> server.createTrip(draft) },
        scope = backgroundScope,
    )
}

/** Le serveur, vu de la file : il note ce qu'il reçoit, **dans l'ordre**. */
private class FakeServer {
    val log = mutableListOf<String>()
    var attempts = 0
    var unreachable = false
    var tripsUnreachable = false
    var tripRefusal: String? = null
    var ignoresClientIdentifiers = false

    fun createTrip(draft: TripDraft): CreatedTrip {
        attempts += 1
        if (unreachable) throw ApiError.Transport(IOException("hors ligne"), url = null)
        if (tripsUnreachable) throw ApiError.Server(statusCode = 503, code = null, message = "Saturé.")
        tripRefusal?.let { throw ApiError.Server(statusCode = 400, code = "bad_request", message = it) }
        val id = if (ignoresClientIdentifiers) "serveur-${log.size + 1}" else (draft.id ?: "sans-identifiant")
        log += "trip:$id:${draft.title}"
        return CreatedTrip(trip = Trip.local(draft, id = id), accessCode = "ABC123")
    }

    fun send(tripId: String): ChatTurnReceipt {
        if (unreachable) throw ApiError.Transport(IOException("hors ligne"), url = null)
        log += "turn:$tripId"
        return ChatTurnReceipt(messages = emptyList(), turn = ChatTurnStatus.Idle, now = java.time.Instant.now())
    }
}
