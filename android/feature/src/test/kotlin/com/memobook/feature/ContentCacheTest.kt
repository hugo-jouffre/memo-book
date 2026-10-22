package com.memobook.feature

import com.memobook.core.Account
import kotlinx.coroutines.test.runTest
import java.nio.file.Files
import java.time.Instant
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotEquals
import kotlin.test.assertNull

class ContentCacheTest {
    private val directory = Files.createTempDirectory("contenu").toFile()
    private val cache = ContentCache(directory)
    private val account = Account(id = "compte-1", firstName = "Camille", createdAt = Instant.parse("2026-09-29T08:00:00Z"))

    @Test fun whatIsWrittenIsReadBack() = runTest {
        cache.write(ContentCache.Slot.Account, account)
        assertEquals(account, cache.read<Account>(ContentCache.Slot.Account))
    }

    @Test fun nothingWrittenReadsAsNothing() = runTest {
        assertNull(cache.read<Account>(ContentCache.Slot.Home))
    }

    /** Un fichier qui date d'un modèle qui a changé : rien à réparer, un appel à faire. */
    @Test fun anUnreadableFileReadsAsNothing() = runTest {
        directory.mkdirs()
        directory.resolve(ContentCache.Slot.Account.filename).writeText("{\"id\": 3}")
        assertNull(cache.read<Account>(ContentCache.Slot.Account))
    }

    @Test fun signingOutForgetsEverything() = runTest {
        cache.write(ContentCache.Slot.Account, account)
        cache.clearAll()
        assertNull(cache.read<Account>(ContentCache.Slot.Account))
    }

    /** L'identifiant du voyage n'est jamais écrit en clair, et son empreinte ne change pas d'un lancement à l'autre. */
    @Test fun aTripSlotHidesItsIdentifierBehindAStableDigest() {
        val id = "1CE0FEED-0000-4000-A000-000000000001"
        val name = ContentCache.Slot.Trip(id).filename
        assertEquals(name, ContentCache.Slot.Trip(id).filename)
        assert(!name.contains(id))
        assertNotEquals(name, ContentCache.Slot.TripSettings(id).filename)
    }

    /** La même somme que sur iOS (djb2 en base 36). */
    @Test fun theDigestIsDjb2InBase36() {
        assertEquals((5381uL * 33uL + 'a'.code.toULong()).toString(36), ContentCache.Slot.digest("a"))
    }
}
