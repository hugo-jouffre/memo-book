package com.memobook.core

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

/**
 * Ce que `GET /v1/memos/:id/preview` dit d'une composition (contrat du
 * 06/10/2026) : la dernière composition, le rendu prêt qu'on commande, et ce
 * que l'écran de composition en raconte. Mêmes cas que `BookPreviewTests.swift`.
 */
class BookPreviewTest {
    private fun decode(json: String): BookPreview = MemoBookJson.decodeFromString(BookPreview.serializer(), json)

    /**
     * Une remise à jour qui tourne derrière un carnet déjà composé : le
     * statut dit « ça compose », mais il y a un rendu prêt — on le feuillette
     * et on le commande.
     */
    @Test
    fun aRecompositionKeepsTheReadyRender() {
        val preview = decode(
            """
            {"memoId":"m","title":"Rome","status":{"status":"composing"},
             "pdfUrl":"https://pdf.test/rome.pdf","pageCount":12,"shareUrl":null,
             "coverPhotoUrl":null,"tripDate":null,"excerpt":null,"hasConfiguredCovers":false,
             "render":{"id":"r2","status":"processing","phase":"writing",
                       "startedAt":"2026-10-06T10:00:00Z","updatedAt":"2026-10-06T10:01:00Z","error":null},
             "readyRenderId":"r1","isUpToDate":false,"pendingMemoryCount":2}
            """,
        )

        assertEquals(BookPreviewStatus.Composing, preview.status)
        assertTrue(preview.hasReadyRender)
        assertEquals("r1", preview.readyRenderId)
        assertEquals(BookRenderPhase.Writing, preview.render?.phase)
        assertEquals(2, preview.pendingMemoryCount)
        assertEquals(false, preview.isUpToDate)
    }

    /**
     * Jamais composé : `render` est nul, et rien n'est commandable. C'est ce
     * qui distingue « rien n'a été lancé » d'une composition qui tourne —
     * le statut dit `composing` dans les deux cas.
     */
    @Test
    fun aNeverComposedBookHasNoRender() {
        val preview = decode(
            """
            {"memoId":"m","title":"Rome","status":{"status":"composing"},"pdfUrl":null,
             "pageCount":0,"hasConfiguredCovers":false,"render":null,"readyRenderId":null,
             "isUpToDate":false,"pendingMemoryCount":0}
            """,
        )

        assertNull(preview.render)
        assertFalse(preview.hasReadyRender)
    }

    /**
     * Un serveur d'avant le contrat ne sert aucun des quatre champs : l'aperçu
     * se lit quand même.
     */
    @Test
    fun anOlderServerStillDecodes() {
        val preview = decode(
            """
            {"memoId":"m","title":"Rome","status":{"status":"ready"},"pdfUrl":null,
             "pageCount":10,"hasConfiguredCovers":true}
            """,
        )

        assertNull(preview.render)
        assertNull(preview.isUpToDate)
        assertTrue(preview.hasReadyRender)
    }

    /**
     * Une phase ajoutée côté serveur après cette version est une attente,
     * pas une erreur de décodage.
     */
    @Test
    fun anUnknownPhaseIsAWait() {
        val render = MemoBookJson.decodeFromString(BookRenderProgress.serializer(), """{"id":"r","phase":"proofreading"}""")
        assertEquals(BookRenderPhase.Unknown("proofreading"), render.phase)
    }

    /**
     * La ligne sous la page : la file, la rédaction attendue (accordée), la
     * mise en page, la fabrication du PDF.
     */
    @Test
    fun thePhaseLineFollowsTheComposition() {
        val copy = BookCopy.Composition
        assertEquals("Ton carnet attend son tour…", copy.phase(BookRenderPhase.Queued, pendingMemories = 0))
        assertEquals(
            "On attend la fin de la rédaction d’un souvenir…",
            copy.phase(BookRenderPhase.Writing, pendingMemories = 1),
        )
        assertEquals(
            "On attend la fin de la rédaction de 3 souvenirs…",
            copy.phase(BookRenderPhase.Writing, pendingMemories = 3),
        )
        assertEquals("On met tes souvenirs en pages…", copy.phase(BookRenderPhase.Writing, pendingMemories = 0))
        assertEquals("On fabrique le PDF de ton carnet…", copy.phase(BookRenderPhase.Composing, pendingMemories = 0))
        assertEquals("La composition de ton carnet est lancée…", copy.phase(null, pendingMemories = 0))
    }
}

/**
 * Le message de partage compte des pages, et le dit — il annonçait des
 * « étapes » en comptant les pages du carnet. Mêmes cas que
 * `ShareInvitationTests` (`BookPreviewTests.swift`).
 */
class ShareInvitationTest {
    private val link = "https://api.example.test/c/abc"

    @Test
    fun theMessageCountsPages() {
        val message = BookCopy.Share.invitation(title = "Rome", pages = 12, link = link)
        assertTrue(message.contains("Il compte déjà 12 pages !"))
        assertFalse(message.contains("étape"))
        assertFalse(message.contains("financer"))
        assertTrue(message.endsWith(link))
    }

    @Test
    fun onePageIsSingular() {
        assertTrue(BookCopy.Share.invitation(title = "Rome", pages = 1, link = link).contains("1 page !"))
    }

    @Test
    fun aNotYetComposedBookSaysNoCount() {
        val message = BookCopy.Share.invitation(title = "Rome", pages = 0, link = link)
        assertFalse(message.contains("page"))
        assertTrue(message.contains("« Rome »"))
    }
}
