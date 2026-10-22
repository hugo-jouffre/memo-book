package com.memobook.feature

import com.memobook.core.InstantSerializer
import com.memobook.core.MemoBookJson
import com.memobook.core.Trip
import com.memobook.core.TripDraft
import com.memobook.core.local
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import kotlinx.serialization.Serializable
import kotlinx.serialization.builtins.ListSerializer
import java.io.File
import java.io.IOException
import java.nio.file.Files
import java.nio.file.StandardCopyOption
import java.time.Instant
import java.util.UUID

/**
 * Un voyage créé sur le téléphone, que le serveur n'a pas encore vu. Jumeau
 * de `PendingTrip` (`PendingTripStore.swift`).
 *
 * Il porte **son brouillon entier**, et non une liste de corrections : la
 * création se rejoue (`POST /v1/trips` reconnaît son identifiant), donc
 * revenir sur les dates hors ligne ne fait que remplacer le brouillon qui
 * attend.
 *
 * @property accountId le compte qui l'a créé. Un autre compte ouvert sur le
 *   même téléphone ne le voit pas et ne l'envoie pas : c'est le voyage de
 *   quelqu'un, et le créer sous un autre nom le lui prendrait. `null` dans le
 *   bac à sable, qui n'a pas de compte.
 */
@Serializable
data class PendingTrip(
    val id: String,
    val draft: TripDraft,
    val accountId: String?,
    @Serializable(with = InstantSerializer::class) val queuedAt: Instant = Instant.now(),
) {
    /** Le voyage tel qu'il se montre en attendant le serveur. */
    val trip: Trip get() = Trip.local(draft, id = id)
}

/**
 * Les voyages qui attendent le réseau, **sur le disque**. Jumeau de
 * `PendingTripStore.swift`.
 *
 * À côté des vocaux en attente (`PendingRecordingStore`), et pour la même
 * raison dans `filesDir` et non dans `cacheDir` : un voyage créé dans l'avion
 * n'existe nulle part ailleurs, et Android vide le cache sans prévenir. Un
 * seul fichier : ils se comptent sur les doigts d'une main.
 *
 * @param dispatcher où tournent les entrées-sorties — `Dispatchers.IO` ; un
 *   test passe le sien.
 */
class PendingTripStore(
    directory: File,
    private val dispatcher: CoroutineDispatcher = Dispatchers.IO,
) {
    private val file = File(directory, "pending-trips.json")
    private val lock = Mutex()
    private var trips: List<PendingTrip>? = null

    /** Les voyages en attente, le plus ancien d'abord — l'ordre où ils partent. */
    suspend fun all(): List<PendingTrip> = locked { loaded() }

    /**
     * Pose le voyage, ou remplace son brouillon s'il attendait déjà — sans
     * changer sa place dans la file.
     *
     * @throws IOException quand le disque refuse.
     */
    suspend fun save(trip: PendingTrip) = locked {
        val known = loaded().toMutableList()
        val index = known.indexOfFirst { it.id == trip.id }
        if (index >= 0) known[index] = known[index].copy(draft = trip.draft) else known += trip
        write(known)
        trips = known
    }

    suspend fun remove(id: String) = locked { removeLocked(id) }

    /**
     * Retire le voyage, **à condition** qu'il attende encore ce brouillon-là.
     * Une correction posée pendant l'envoi reste, et partira à son tour.
     */
    suspend fun remove(id: String, ifDraftIs: TripDraft) = locked {
        if (loaded().firstOrNull { it.id == id }?.draft == ifDraftIs) removeLocked(id)
    }

    suspend fun removeAll() = locked {
        file.delete()
        trips = emptyList()
    }

    private fun removeLocked(id: String) {
        val remaining = loaded().filter { it.id != id }
        runCatching { write(remaining) }
        trips = remaining
    }

    private suspend fun <T> locked(block: () -> T): T = lock.withLock { withContext(dispatcher) { block() } }

    private fun loaded(): List<PendingTrip> = trips ?: run {
        val read = runCatching { MemoBookJson.decodeFromString(serializer, file.readText()) }.getOrNull().orEmpty()
        read.sortedBy { it.queuedAt }.also { trips = it }
    }

    /** L'`.atomic` d'iOS : un fichier entier ou rien. */
    private fun write(trips: List<PendingTrip>) {
        val directory = file.parentFile ?: throw IOException("Pas de dossier pour les voyages en attente.")
        if (!directory.isDirectory && !directory.mkdirs()) throw IOException("Le dossier des voyages n’a pas pu être créé.")
        val partial = File(directory, "${file.name}.${UUID.randomUUID()}.partial")
        try {
            partial.writeText(MemoBookJson.encodeToString(serializer, trips))
            Files.move(partial.toPath(), file.toPath(), StandardCopyOption.REPLACE_EXISTING, StandardCopyOption.ATOMIC_MOVE)
        } finally {
            partial.delete()
        }
    }

    companion object {
        private val serializer = ListSerializer(PendingTrip.serializer())

        /** Les voyages de l'app : ceux qui survivent à tout — dans `filesDir`. */
        fun inLibrary(filesDirectory: File): PendingTripStore = PendingTripStore(File(filesDirectory, "PendingTrips"))

        fun temporary(dispatcher: CoroutineDispatcher = Dispatchers.IO): PendingTripStore =
            PendingTripStore(File(System.getProperty("java.io.tmpdir"), "PendingTrips-${UUID.randomUUID()}"), dispatcher)
    }
}
