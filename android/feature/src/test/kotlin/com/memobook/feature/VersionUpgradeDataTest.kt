package com.memobook.feature

import com.memobook.core.TripDraft
import com.memobook.recording.PendingRecordingStore
import com.memobook.recording.PendingTurn
import kotlin.test.assertNull
import kotlinx.coroutines.test.runTest
import java.io.File
import java.time.Instant
import java.util.UUID
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertTrue

/**
 * **Ce qu'une mise à jour de l'app ne doit pas emporter.** Jumeau de
 * `VersionUpgradeDataTests.swift`, cas pour cas (Hugo, 28/10/2026 —
 * « s'assurer que le passage d'une version à une autre, notamment d'une
 * version de test à une version publique, ne fasse pas perdre la donnée des
 * utilisateurs et ce qu'ils ont commencé à raconter »).
 *
 * Presque tout le récit vit sur le serveur, et une mise à jour n'y touche pas.
 * Deux choses n'existent **que** sur le téléphone : les tours de conversation
 * qui n'ont pas pu partir ([PendingRecordingStore]) et les voyages créés hors
 * ligne ([PendingTripStore]). Les deux sont relus d'un format écrit par la
 * version d'avant.
 */
class VersionUpgradeDataTest {
    private fun directory() = File(System.getProperty("java.io.tmpdir"), "Upgrade-${UUID.randomUUID()}")

    /** Pose une fiche et ses fichiers comme une version livrée les a écrits. */
    private fun plant(json: String, id: String, files: Int, directory: File) {
        directory.mkdirs()
        File(directory, "$id.json").writeText(json)
        repeat(files) { index ->
            File(directory, if (index == 0) "$id.audio" else "$id-$index.file").writeText("octets")
        }
    }

    // MARK: - Une version qui ne sait pas relire ne détruit pas

    /**
     * Une fiche écrite par une version suivante n'est pas comprise par
     * celle-ci. Elle ne doit pas disparaître avec son audio : un vocal qui
     * n'est pas parti n'existe nulle part ailleurs.
     */
    @Test
    fun `une fiche illisible est mise de cote au lieu d'etre supprimee`() = runTest {
        val directory = directory()
        val id = "F0000000-0000-0000-0000-00000000000A"
        plant("""{"id":"$id","format":"venu du futur"}""", id = id, files = 1, directory = directory)

        val visible = PendingRecordingStore(directory).all()
        assertEquals(0, visible.size, "Elle n'est pas lisible : elle ne se montre pas.")

        val quarantine = File(directory, "illisibles")
        assertTrue(File(quarantine, "$id.json").exists(), "La fiche illisible est mise de côté, pas supprimée.")
        assertEquals("octets", File(quarantine, "$id.audio").readText(), "L'audio part avec elle, intact.")
        assertFalse(
            File(directory, "$id.json").exists(),
            "Et il ne reste pas une copie dans la file, qu'on relirait à chaque lancement.",
        )
    }

    /** Une fiche illisible ne doit pas emporter les lisibles. */
    @Test
    fun `une fiche illisible ne bloque pas les autres`() = runTest {
        val directory = directory()
        val id = "A0000000-0000-0000-0000-00000000000C"
        plant(
            """
            {"id":"$id","tripId":"trip-1","kind":"voice","filenames":["memo.m4a"],
            "mimeTypes":["audio/m4a"],"levels":[],
            "recordedAt":"2026-11-12T08:00:00Z","queuedAt":"2026-11-12T08:00:00Z"}
            """.trimIndent(),
            id = id, files = 1, directory = directory,
        )
        File(directory, "F0000000-0000-0000-0000-00000000000B.json").writeText("""{"rien":"de lisible"}""")

        assertEquals(1, PendingRecordingStore(directory).all().size, "Le tour lisible arrive quand même.")
    }

    /**
     * Toute la file des voyages tient dans un seul fichier. Une entrée qu'on
     * ne comprend pas ne doit ni cacher les autres, ni être effacée par le
     * prochain enregistrement.
     */
    @Test
    fun `un voyage illisible survit a l'enregistrement suivant`() = runTest {
        val directory = directory()
        directory.mkdirs()
        val file = File(directory, "pending-trips.json")
        file.writeText("""[{"id":"venu-du-futur","nouveauChamp":42}]""")

        val store = PendingTripStore(directory)
        assertTrue(store.all().isEmpty(), "On ne sait pas le lire : il ne se montre pas.")

        store.save(PendingTrip(id = "trip-1", draft = TripDraft(title = "Rome"), accountId = "compte-1"))

        val written = file.readText()
        assertTrue(written.contains("trip-1"), "Le voyage de cette version est enregistré.")
        assertTrue(
            written.contains("venu-du-futur"),
            "Et celui qu'on n'a pas su lire n'a pas été écrasé : il repartira le jour où une version le comprendra.",
        )
    }

    /** Un fichier entièrement illisible est copié de côté avant réécriture. */
    @Test
    fun `un fichier de file abime est copie de cote`() = runTest {
        val directory = directory()
        directory.mkdirs()
        File(directory, "pending-trips.json").writeText("ceci n'est pas du JSON")

        PendingTripStore(directory).all()

        val kept = directory.listFiles()?.filter { it.name.contains("illisible") }.orEmpty()
        assertEquals(1, kept.size, "Le fichier abîmé est gardé à côté, daté.")
    }

    /** Un fichier vide n'est pas un fichier abîmé. */
    @Test
    fun `une file vide n'est pas un fichier abime`() = runTest {
        val directory = directory()
        directory.mkdirs()
        File(directory, "pending-trips.json").writeText("[]")

        PendingTripStore(directory).all()

        val kept = directory.listFiles()?.filter { it.name.contains("illisible") }.orEmpty()
        assertTrue(kept.isEmpty(), "Rien à sauver : la file était simplement vide.")
    }

    // MARK: - Le sens qui fait perdre des données

    /**
     * ⚠️ **Les cas ci-dessus tiennent le mauvais sens.** Ils prouvent qu'une
     * fiche illisible est mise de côté — ce qui protège *après* coup. Ce qui
     * fait perdre un souvenir, c'est l'inverse : une fiche écrite par la
     * version d'hier que celle d'aujourd'hui ne sait plus lire. Elle part en
     * quarantaine **en silence**, et rien ici ne serait rouge.
     *
     * Les cas qui suivent figent donc le format **octet pour octet**, tel
     * qu'une version livrée l'écrit sur le téléphone des gens. Un format figé
     * ici ne se corrige pas, il s'accompagne : on garde le cas tel quel et on
     * ajoute au décodage de quoi relire l'ancien.
     */

    @Test
    fun `un vocal ecrit par une version livree se relit`() = runTest {
        val directory = directory()
        val id = "11111111-1111-1111-1111-111111111111"
        plant(
            """
            {"id":"$id","tripId":"voyage-kyoto","kind":"voice",
            "filenames":["souvenir.m4a"],"mimeTypes":["audio/m4a"],
            "duration":42.5,"levels":[0.1,0.9,0.4],"placeLabel":"Kyoto",
            "recordedAt":"2026-11-12T08:30:00Z","queuedAt":"2026-11-12T08:31:00Z"}
            """.trimIndent(),
            id = id, files = 1, directory = directory,
        )

        val turn = PendingRecordingStore(directory).all().firstOrNull()
        assertNotNull(turn)
        assertEquals(id, turn.id)
        assertEquals("voyage-kyoto", turn.tripId)
        assertEquals(PendingTurn.Kind.Voice, turn.kind)
        assertEquals(listOf("souvenir.m4a"), turn.filenames)
        assertEquals(listOf("audio/m4a"), turn.mimeTypes)
        assertEquals(42.5, turn.duration)
        assertEquals(listOf(0.1, 0.9, 0.4), turn.levels)
        assertEquals("Kyoto", turn.placeLabel)
        assertFalse(turn.isOnHold(), "Rien ne le retient : il doit repartir au premier réseau.")
    }

    @Test
    fun `un texte ecrit par une version livree se relit`() = runTest {
        val directory = directory()
        val id = "22222222-2222-2222-2222-222222222222"
        plant(
            """
            {"id":"$id","tripId":"voyage-kyoto","kind":"text",
            "text":"On a mangé des nouilles sous la pluie.","suggestionId":"sugg-3",
            "filenames":[],"mimeTypes":[],"levels":[],
            "recordedAt":"2026-11-12T09:00:00Z","queuedAt":"2026-11-12T09:00:00Z"}
            """.trimIndent(),
            id = id, files = 0, directory = directory,
        )

        val turn = PendingRecordingStore(directory).all().firstOrNull()
        assertNotNull(turn)
        assertEquals(PendingTurn.Kind.Text, turn.kind)
        assertEquals("On a mangé des nouilles sous la pluie.", turn.text)
        assertEquals("sugg-3", turn.suggestionId)
    }

    @Test
    fun `deux photos ecrites par une version livree se relisent`() = runTest {
        val directory = directory()
        val id = "33333333-3333-3333-3333-333333333333"
        plant(
            """
            {"id":"$id","tripId":"voyage-kyoto","kind":"photos","entryId":"entry-7","stepId":"step-2",
            "filenames":["photo-0.jpg","photo-1.jpg"],"mimeTypes":["image/jpeg","image/jpeg"],
            "levels":[],"recordedAt":"2026-11-12T10:00:00Z","queuedAt":"2026-11-12T10:00:00Z"}
            """.trimIndent(),
            id = id, files = 2, directory = directory,
        )

        val turn = PendingRecordingStore(directory).all().firstOrNull()
        assertNotNull(turn)
        assertEquals(PendingTurn.Kind.Photos, turn.kind)
        assertEquals(2, turn.filenames.size)
        assertEquals("entry-7", turn.entryId)
        assertEquals("step-2", turn.stepId)
    }

    /**
     * **Le 👍 traverse la file** (T296) : un tour de réaction attend le réseau
     * comme les autres, et il doit repartir en sachant **quelle** bulle il
     * salue — sans quoi il se dessinerait comme une bulle « Ça me convient »
     * de plus, ce que le geste cherchait justement à éviter. Et la clé ne
     * coûte rien aux fiches qui n'en portent pas.
     */
    @Test
    fun `un pouce garde sa cible, et ne coute rien quand il n'y en a pas`() = runTest {
        val directory = directory()
        val store = PendingRecordingStore(directory)

        val ordinaire = PendingTurn(
            id = "cccccccc-0000-0000-0000-000000000000",
            tripId = "voyage",
            kind = PendingTurn.Kind.Text,
            text = "On a marché jusqu’au port.",
            recordedAt = Instant.parse("2026-11-28T09:00:00Z"),
        )
        store.enqueue(ordinaire, files = emptyList())
        val ecrit = File(directory, "${ordinaire.id}.json").readText()
        assertFalse(ecrit.contains("reactionTo"), "Rien à dire, rien à écrire : $ecrit")

        val pouce = PendingTurn(
            id = "dddddddd-0000-0000-0000-000000000000",
            tripId = "voyage",
            kind = PendingTurn.Kind.Text,
            text = "Ça me convient",
            suggestionId = "accept",
            entryId = "e1",
            reactionTo = "bulle-de-memo",
            recordedAt = Instant.parse("2026-11-28T09:05:00Z"),
        )
        store.enqueue(pouce, files = emptyList())

        val relus = PendingRecordingStore(directory).all()
        assertEquals("bulle-de-memo", relus.first { it.id == pouce.id }.reactionTo)
        assertNull(relus.first { it.id == ordinaire.id }.reactionTo)
    }

    /**
     * Un tour retenu jusqu'au crédit de demain garde sa retenue : relu sans
     * elle, il partirait tout de suite et se ferait refuser.
     */
    @Test
    fun `un tour retenu jusqu'a demain garde sa retenue`() = runTest {
        val directory = directory()
        val id = "44444444-4444-4444-4444-444444444444"
        val demain = Instant.now().plusSeconds(3600).toString()
        plant(
            """
            {"id":"$id","tripId":"voyage-kyoto","kind":"voice",
            "filenames":["souvenir.m4a"],"mimeTypes":["audio/m4a"],"levels":[],
            "recordedAt":"2026-11-12T11:00:00Z","queuedAt":"2026-11-12T11:00:00Z",
            "waitingForCreditUntil":"$demain"}
            """.trimIndent(),
            id = id, files = 1, directory = directory,
        )

        val turn = PendingRecordingStore(directory).all().firstOrNull()
        assertNotNull(turn)
        assertTrue(turn.isWaitingForCredit(), "Il attend le crédit de demain, et doit continuer d'attendre.")
    }

    /**
     * Un voyage créé hors ligne, écrit par une version livrée. Perdre
     * celui-ci, c'est perdre un voyage que le serveur n'a jamais vu.
     */
    @Test
    fun `un voyage ecrit par une version livree se relit`() = runTest {
        val directory = directory()
        directory.mkdirs()
        File(directory, "pending-trips.json").writeText(
            """
            [{"id":"66666666-6666-6666-6666-666666666666","accountId":"compte-1",
            "queuedAt":"2026-11-12T12:00:00Z",
            "draft":{"id":"66666666-6666-6666-6666-666666666666","title":"Rome","theme":"Gastronomie",
            "startDate":"2026-11-10T00:00:00Z","endDate":"2026-11-18T00:00:00Z",
            "narrationPace":"Tous les jours","photoTextRatio":70}}]
            """.trimIndent(),
        )

        val trip = PendingTripStore(directory).all().firstOrNull()
        assertNotNull(trip)
        assertEquals("66666666-6666-6666-6666-666666666666", trip.id)
        assertEquals("compte-1", trip.accountId)
        assertEquals("Rome", trip.draft.title)
        assertEquals("Gastronomie", trip.draft.theme)
        assertEquals("Tous les jours", trip.draft.narrationPace)
        assertEquals(70, trip.draft.photoTextRatio)
        assertNotNull(trip.draft.startDate)
        assertNotNull(trip.draft.endDate)
    }
}
