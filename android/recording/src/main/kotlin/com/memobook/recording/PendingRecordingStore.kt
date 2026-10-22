package com.memobook.recording

import com.memobook.core.MemoBookDate
import com.memobook.core.MemoBookJson
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import kotlinx.serialization.KSerializer
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.descriptors.SerialDescriptor
import kotlinx.serialization.encoding.Decoder
import kotlinx.serialization.encoding.Encoder
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.contentOrNull
import java.io.File
import java.io.IOException
import java.nio.file.Files
import java.nio.file.StandardCopyOption
import java.time.Instant
import java.util.UUID

/**
 * Un tour de conversation qui n'a pas pu partir — un vocal, un texte, des
 * photos —, gardé sur l'appareil jusqu'à ce qu'il parte. Jumeau de
 * `PendingTurn` (`PendingRecordingStore.swift`).
 *
 * Ce qui est stocké, c'est **ce que le voyageur a dit**, jamais ce que le
 * serveur en fera : la transcription appartient au serveur, et un tour en
 * attente n'a encore rien produit.
 *
 * @property id l'identifiant **du message**, celui que le serveur reprendra :
 *   c'est ce qui fait qu'un tour parti deux fois — une panne de transport
 *   après un envoi qui avait abouti — ne se retrouve pas deux fois dans le fil.
 * @property tripId le carnet auquel il n'est **pas encore** arrivé. Un seul :
 *   un tour parle à une conversation.
 * @property text le texte d'un tour `text` ; [suggestionId] la puce qui l'a
 *   produit ; [entryId] le souvenir visé.
 * @property filenames les fichiers, dans l'ordre : un pour un vocal, un à
 *   quatre pour des photos, aucun pour un texte. Écrits à côté de la fiche.
 * @property duration la durée capturée d'un vocal, mesurée par l'app, en
 *   secondes. Elle dessine la bulle en attendant le serveur, qui relit la
 *   sienne dans le fichier — c'est celle-là qui décompte le crédit du jour
 *   (03/10/2026).
 * @property levels la forme d'onde relevée pendant l'enregistrement, pour la bulle.
 * @property recordedAt le moment où **on a parlé**, pas celui où le tour
 *   partira. C'est cette date que le carnet range : un souvenir raconté hier
 *   au fond d'une vallée ne se pose pas au jour de la reconnexion.
 * @property queuedAt depuis quand il attend. Sert à l'ordre d'envoi — le plus
 *   ancien d'abord — et à rien d'autre.
 * @property waitingForCreditUntil **il attend le crédit du jour**, jusqu'à
 *   cette heure (Hugo, 03/10/2026). Le serveur l'a refusé faute de crédit
 *   (`429 daily_credit_exhausted`) : ce n'est pas un refus définitif, le tour
 *   repartira tout seul quand le crédit se recharge — le `resetsAt` du
 *   serveur, à défaut le minuit local suivant. `null` : il n'attend que le
 *   réseau. Écrit sur la fiche pour qu'une app relancée ne le renvoie pas au
 *   serveur toutes les dix secondes jusqu'à minuit.
 * @property waitingForUnlimited **il attend l'illimité** (03/10/2026) : il coûte
 *   plus qu'une journée entière de crédit — un vocal de plus de 5:03, un texte
 *   de plus de 4 000 caractères —, et le serveur le refusera chaque jour, pot
 *   plein compris. Ni renvoyé, ni réveillé à minuit : il repart quand le
 *   compte passe en illimité (`RecordingOutbox.releaseCreditHolds`). Jamais
 *   jeté — ce serait perdre ce qu'on a raconté.
 */
@Serializable(with = PendingTurn.Serializer::class)
data class PendingTurn(
    val id: String,
    val tripId: String,
    val kind: Kind,
    val text: String? = null,
    val suggestionId: String? = null,
    val entryId: String? = null,
    val stepId: String? = null,
    val filenames: List<String> = emptyList(),
    val mimeTypes: List<String> = emptyList(),
    val duration: Double? = null,
    val levels: List<Double> = emptyList(),
    val placeLabel: String? = null,
    val recordedAt: Instant,
    val queuedAt: Instant = Instant.now(),
    val waitingForCreditUntil: Instant? = null,
    val waitingForUnlimited: Boolean = false,
) {
    @Serializable
    enum class Kind {
        @SerialName("voice") Voice,
        @SerialName("text") Text,
        @SerialName("photos") Photos,
    }

    /** Le tour attend encore le crédit du jour à cet instant. */
    fun isWaitingForCredit(at: Instant = Instant.now()): Boolean {
        val until = waitingForCreditUntil ?: return false
        return until > at
    }

    /**
     * Le tour est **retenu** à cet instant — le crédit de demain, ou
     * l'illimité : un vidage ne le renvoie pas.
     */
    fun isOnHold(at: Instant = Instant.now()): Boolean = waitingForUnlimited || isWaitingForCredit(at)

    /**
     * La fiche telle qu'elle s'écrit. Décodage **tolérant**, comme sur iOS :
     * un champ absent prend sa valeur par défaut, et une date d'attente
     * illisible ne garde pas le tour en otage — il repart.
     *
     * La fiche d'avant le 22/09/2026 d'iOS (un vocal, plusieurs carnets, sous
     * `tripIds`) ne se relit pas ici : aucune version Android ne l'a écrite.
     */
    @Serializable
    private class Record(
        val id: String,
        val tripId: String,
        val kind: Kind = Kind.Voice,
        val text: String? = null,
        val suggestionId: String? = null,
        val entryId: String? = null,
        val stepId: String? = null,
        val filenames: List<String> = emptyList(),
        val mimeTypes: List<String> = emptyList(),
        val duration: Double? = null,
        val levels: List<Double> = emptyList(),
        val placeLabel: String? = null,
        val recordedAt: String,
        val queuedAt: String,
        val waitingForCreditUntil: JsonElement? = null,
        // Écrit seulement quand il est vrai : la fiche d'un tour ordinaire ne
        // change pas d'une ligne.
        val waitingForUnlimited: JsonElement? = null,
    )

    internal object Serializer : KSerializer<PendingTurn> {
        override val descriptor: SerialDescriptor = Record.serializer().descriptor

        override fun deserialize(decoder: Decoder): PendingTurn {
            val record = decoder.decodeSerializableValue(Record.serializer())
            return PendingTurn(
                id = record.id,
                tripId = record.tripId,
                kind = record.kind,
                text = record.text,
                suggestionId = record.suggestionId,
                entryId = record.entryId,
                stepId = record.stepId,
                filenames = record.filenames,
                mimeTypes = record.mimeTypes,
                duration = record.duration,
                levels = record.levels,
                placeLabel = record.placeLabel,
                recordedAt = MemoBookDate.parse(record.recordedAt)
                    ?: throw IOException("Un tour en attente sans date : ${record.recordedAt}"),
                queuedAt = MemoBookDate.parse(record.queuedAt)
                    ?: throw IOException("Un tour en attente sans date de file : ${record.queuedAt}"),
                waitingForCreditUntil = (record.waitingForCreditUntil as? JsonPrimitive)?.contentOrNull?.let(MemoBookDate::parse),
                waitingForUnlimited = (record.waitingForUnlimited as? JsonPrimitive)?.booleanOrNull ?: false,
            )
        }

        override fun serialize(encoder: Encoder, value: PendingTurn) {
            encoder.encodeSerializableValue(
                Record.serializer(),
                Record(
                    id = value.id,
                    tripId = value.tripId,
                    kind = value.kind,
                    text = value.text,
                    suggestionId = value.suggestionId,
                    entryId = value.entryId,
                    stepId = value.stepId,
                    filenames = value.filenames,
                    mimeTypes = value.mimeTypes,
                    duration = value.duration,
                    levels = value.levels,
                    placeLabel = value.placeLabel,
                    recordedAt = MemoBookDate.format(value.recordedAt),
                    queuedAt = MemoBookDate.format(value.queuedAt),
                    waitingForCreditUntil = value.waitingForCreditUntil?.let { JsonPrimitive(MemoBookDate.format(it)) },
                    waitingForUnlimited = if (value.waitingForUnlimited) JsonPrimitive(true) else null,
                ),
            )
        }
    }
}

/**
 * La file d'attente des tours, sur le disque de l'appareil. Jumeau de
 * `PendingRecordingStore.swift`.
 *
 * **Sur le disque et non en mémoire, parce que c'est tout l'intérêt** : un
 * vocal enregistré dans un train doit survivre à la fermeture de l'app, à la
 * batterie vide et au redémarrage. Une file en mémoire ne promettrait la même
 * chose qu'à l'écran.
 *
 * Elle vit dans `filesDir` et non dans `cacheDir` : Android vide le cache sous
 * pression disque, et ce qui est ici est le récit de quelqu'un, que rien ne
 * peut régénérer. (La sauvegarde de l'app, elle, est coupée pour tout — voir
 * le manifeste de `:app`.)
 *
 * Un verrou et un fil d'entrées-sorties, l'acteur d'iOS : les lectures et
 * écritures de fichiers ne bloquent jamais l'écran, et deux envois concurrents
 * ne peuvent pas se marcher dessus.
 *
 * @param dispatcher où tournent les entrées-sorties — `Dispatchers.IO` ; un
 *   test passe le sien, pour rester dans son temps virtuel.
 */
class PendingRecordingStore(
    private val directory: File,
    private val dispatcher: CoroutineDispatcher = Dispatchers.IO,
) {
    private val lock = Mutex()

    /**
     * L'état de la file, lu une fois du disque puis tenu à jour ici. `null`
     * tant qu'on n'a pas encore regardé.
     */
    private var records: List<PendingTurn>? = null

    /** Les tours en attente, le plus ancien d'abord — c'est l'ordre dans lequel ils repartiront. */
    suspend fun all(): List<PendingTurn> = locked { loaded() }

    suspend fun count(): Int = all().size

    /**
     * Met un tour de côté. Les fichiers sont écrits **avant** la fiche : une
     * écriture interrompue laisse alors des fichiers orphelins, que rien ne
     * lira, plutôt qu'une fiche qui promet un fichier absent.
     *
     * Un tour déjà en file sous le même identifiant n'est pas repris : c'est le
     * renvoi d'un même message, pas un second.
     *
     * @throws IOException quand le disque refuse.
     */
    suspend fun enqueue(turn: PendingTurn, files: List<ByteArray>): PendingTurn = locked {
        // La file est relue **avant** d'écrire quoi que ce soit. Après, une
        // première relecture verrait déjà la fiche qu'on vient de poser sur le
        // disque, et l'ajouter une seconde fois compterait deux tours en
        // attente pour un seul.
        val known = loaded()
        known.firstOrNull { it.id == turn.id }?.let { return@locked it }

        ensureDirectory()
        files.forEachIndexed { index, data -> writeAtomically(fileOf(turn.id, index), data) }
        write(turn)

        records = known + turn
        turn
    }

    /**
     * Les fichiers d'un tour, relus du disque au moment de l'envoyer et pas
     * avant : une file de dix souvenirs ne tient pas dix vocaux en mémoire.
     *
     * @throws IOException quand un fichier manque.
     */
    suspend fun files(turn: PendingTurn): List<ByteArray> = withContext(dispatcher) {
        turn.filenames.indices.map { index -> fileOf(turn.id, index).readBytes() }
    }

    /** Réécrit une fiche. @throws IOException quand le disque refuse. */
    suspend fun update(turn: PendingTurn) = locked {
        write(turn)
        records = loaded().map { if (it.id == turn.id) turn else it }
    }

    /**
     * Le tour est arrivé, ou plus rien ne peut le faire arriver : on le
     * retire, fiche et fichiers.
     */
    suspend fun remove(turn: PendingTurn) = locked { removeLocked(turn) }

    suspend fun removeAll() = locked { loaded().forEach { removeLocked(it) } }

    private fun removeLocked(turn: PendingTurn) {
        metadataOf(turn.id).delete()
        for (index in 0 until maxOf(turn.filenames.size, 1)) fileOf(turn.id, index).delete()
        records = loaded().filter { it.id != turn.id }
    }

    // MARK: - Le disque

    private suspend fun <T> locked(block: () -> T): T = lock.withLock { withContext(dispatcher) { block() } }

    private fun loaded(): List<PendingTurn> = records ?: readFromDisk().sortedBy { it.queuedAt }.also { records = it }

    private fun metadataOf(id: String) = File(directory, "$id.json")

    /**
     * Le premier fichier garde le nom d'iOS (`<id>.audio`) : une seule règle de
     * nommage pour les deux apps.
     */
    private fun fileOf(id: String, index: Int) =
        if (index == 0) File(directory, "$id.audio") else File(directory, "$id-$index.file")

    private fun ensureDirectory() {
        if (!directory.isDirectory && !directory.mkdirs()) throw IOException("Le dossier de la file n’a pas pu être créé.")
    }

    private fun write(turn: PendingTurn) {
        ensureDirectory()
        writeAtomically(metadataOf(turn.id), MemoBookJson.encodeToString(PendingTurn.serializer(), turn).toByteArray())
    }

    /** L'`.atomic` d'iOS : un fichier entier ou rien, jamais une moitié. */
    private fun writeAtomically(target: File, data: ByteArray) {
        val partial = File(directory, "${target.name}.${UUID.randomUUID()}.partial")
        try {
            partial.writeBytes(data)
            Files.move(partial.toPath(), target.toPath(), StandardCopyOption.REPLACE_EXISTING, StandardCopyOption.ATOMIC_MOVE)
        } finally {
            partial.delete()
        }
    }

    /**
     * Relit la file. Une fiche illisible — disque abîmé — est **jetée avec ses
     * fichiers** plutôt que de faire échouer la lecture entière : un souvenir
     * perdu ne doit pas en bloquer neuf autres. Une fiche qui promet un
     * fichier absent aussi.
     */
    private fun readFromDisk(): List<PendingTurn> {
        val files = directory.listFiles() ?: return emptyList()
        return files.filter { it.extension == "json" }.mapNotNull { file ->
            val turn = runCatching { MemoBookJson.decodeFromString(PendingTurn.serializer(), file.readText()) }.getOrNull()
            if (turn == null) {
                file.delete()
                return@mapNotNull null
            }
            val filesArePresent = turn.filenames.indices.all { index -> fileOf(turn.id, index).exists() }
            if (!filesArePresent) {
                file.delete()
                return@mapNotNull null
            }
            turn
        }
    }

    companion object {
        /** La file de l'app : celle qui survit à tout — dans `filesDir`. */
        fun inLibrary(filesDirectory: File): PendingRecordingStore =
            PendingRecordingStore(File(filesDirectory, "PendingRecordings"))

        /**
         * Une file jetable, dans le dossier temporaire : les aperçus et les
         * tests. Le code exercé est **le même** — c'est le dossier qui change.
         */
        fun temporary(dispatcher: CoroutineDispatcher = Dispatchers.IO): PendingRecordingStore =
            PendingRecordingStore(
                File(System.getProperty("java.io.tmpdir"), "PendingRecordings-${UUID.randomUUID()}"),
                dispatcher,
            )
    }
}
