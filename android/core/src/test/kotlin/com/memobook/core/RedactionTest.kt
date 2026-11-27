package com.memobook.core

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertTrue

/**
 * Le texte d'un souvenir existe en trois versions — brute, rédigée, corrigée.
 * Ces tests verrouillent la seule règle qui compte pour l'utilisateur : sa
 * correction gagne toujours, et elle ne se perd jamais en route. Le jumeau de
 * `RedactionTests.swift`.
 */
class RedactionTest {
    private fun entryJson(extraFields: String): String =
        """
        {
          "id": "e1", "memoId": "m1", "kind": "audio", "status": "ready",
          "transcript": "euh du coup on est arrivés",
          "capturedAt": "2026-08-08T09:00:00.000Z",
          "createdAt": "2026-08-08T09:00:01.000Z"
          $extraFields
        }
        """

    private fun decode(json: String): Entry = MemoBookJson.decodeFromString(Entry.serializer(), json)

    @Test
    fun decodesRedactionFields() {
        val entry = decode(
            entryJson(
                """
                , "redactionStatus": "ready",
                  "redactedText": "On est arrivés.",
                  "displayText": "On est arrivés.",
                  "suggestedTitle": "Premier jour",
                  "funFact": "Un fait vérifiable.",
                  "funFactTitle": "Fun fact",
                  "weatherKey": "rain"
                """,
            ),
        )

        assertEquals(Status.Ready, entry.redactionStatus)
        assertEquals("On est arrivés.", entry.displayText)
        assertEquals("Premier jour", entry.suggestedTitle)
        assertEquals("rain", entry.weatherKey)
        assertFalse(entry.isEdited)
        assertTrue(entry.isReadyForBook)
    }

    /**
     * Le serveur peut être plus ancien que l'app, ou un endpoint peut ne pas
     * renvoyer ces champs : le souvenir doit rester décodable.
     */
    @Test
    fun decodesWithoutRedactionFields() {
        val entry = decode(entryJson(""))

        assertEquals(Status.Pending, entry.redactionStatus)
        assertEquals("euh du coup on est arrivés", entry.displayText)
        assertTrue(entry.isProcessing, "Sans rédaction, le souvenir n'est pas prêt")
        assertFalse(entry.isReadyForBook)
    }

    @Test
    fun editedTextWinsOverRedactedText() {
        val entry = decode(
            entryJson(
                """
                , "redactionStatus": "ready",
                  "redactedText": "La version du modèle.",
                  "editedText": "Ma version.",
                  "editedAt": "2026-08-08T10:00:00.000Z",
                  "displayText": "Ma version."
                """,
            ),
        )

        assertEquals("Ma version.", entry.displayText)
        assertTrue(entry.isEdited)
        assertNotNull(entry.redactedText, "La version proposée reste consultable")
    }

    /**
     * Une photo n'a rien à rédiger : elle ne doit pas retenir la génération
     * du carnet en restant éternellement « en attente ».
     */
    @Test
    fun photoIsNeverBlockedByRedaction() {
        val json =
            """
            {
              "id": "e2", "memoId": "m1", "kind": "photo", "status": "ready",
              "redactionStatus": "pending",
              "capturedAt": "2026-08-08T09:00:00.000Z",
              "createdAt": "2026-08-08T09:00:01.000Z"
            }
            """

        val entry = decode(json)

        assertFalse(entry.isProcessing)
        assertTrue(entry.isReadyForBook)
    }

    @Test
    fun failedRedactionIsReadyForBook() {
        val entry = decode(
            entryJson(
                """
                , "redactionStatus": "failed",
                  "redactionError": "Le modèle a refusé de rédiger ce souvenir."
                """,
            ),
        )

        assertFalse(entry.isProcessing, "Un échec n'est pas une attente")
        assertTrue(entry.isReadyForBook, "Le carnet part avec la transcription brute")
        assertEquals("euh du coup on est arrivés", entry.displayText)
    }
}

/**
 * `EntryEdit` doit distinguer trois intentions. Une seule les confond, et
 * « revenir au texte proposé » devient « ne rien faire ».
 */
class EntryEditEncodingTest {
    private fun encoded(edit: EntryEdit): String = MemoBookJson.encodeToString(EntryEdit.serializer(), edit)

    @Test
    fun newTextIsSent() {
        val json = encoded(EntryEdit.text("Ma version."))

        assertTrue(json.contains("\"editedText\""))
        assertTrue(json.contains("Ma version."))
    }

    @Test
    fun revertSendsExplicitNull() {
        val json = encoded(EntryEdit.revertToRedaction)

        assertTrue(
            json.contains("\"editedText\":null"),
            "Un null explicite est ce qui distingue « revenir en arrière » de « ne pas toucher »",
        )
    }

    @Test
    fun untouchedFieldIsOmitted() {
        val json = encoded(EntryEdit(weatherKey = Some("rain")))

        assertFalse(json.contains("editedText"), "Un champ absent ne doit pas écraser le texte")
        assertTrue(json.contains("rain"))
    }

    /**
     * **Les jours fixés à la main** (T288) : le jumeau de
     * `EntryEditEncodingTests` côté iOS. Un jour part seul, et la fin part
     * **toujours** avec lui — corriger le départ sur une période que la
     * rédaction avait devinée doit l'effacer, sinon on lirait « du 12 au 15 »
     * sans que personne ne l'ait dit.
     */
    @Test
    fun aHandWrittenDaySendsItsDayAndClearsTheEnd() {
        val json = encoded(EntryEdit.livedDays(from = "2026-11-14", to = null))

        assertTrue(json.contains("\"livedFrom\":\"2026-11-14\""))
        assertTrue(json.contains("\"livedTo\":null"), "La fin part avec le départ, même nulle")
    }

    @Test
    fun aHandWrittenPeriodSendsBothDays() {
        val json = encoded(EntryEdit.livedDays(from = "2026-11-14", to = "2026-11-16"))

        assertTrue(json.contains("\"livedFrom\":\"2026-11-14\""))
        assertTrue(json.contains("\"livedTo\":\"2026-11-16\""))
    }

    /** « Revenir aux dates déduites » : deux nulls explicites. */
    @Test
    fun revertingTheDaysSendsExplicitNulls() {
        val json = encoded(EntryEdit.livedDays(from = null, to = "2026-11-16"))

        assertTrue(json.contains("\"livedFrom\":null"))
        assertTrue(json.contains("\"livedTo\":null"), "Une fin sans départ ne dit rien")
    }

    /** « Changer le nom du lieu », et « revenir au lieu deviné ». */
    @Test
    fun aHandWrittenPlaceIsSentAndCleared() {
        assertTrue(encoded(EntryEdit.place("Apollonas")).contains("\"placeName\":\"Apollonas\""))
        assertTrue(encoded(EntryEdit.place(null)).contains("\"placeName\":null"))
    }
}
