package com.memobook.feature

import com.memobook.core.Account
import com.memobook.networking.ApiError
import kotlinx.coroutines.test.runTest
import java.io.IOException
import java.time.Instant
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.time.Duration

/**
 * Ce que le lancement fait d'une session gardée : seul un 401 fait sortir. Du
 * 27 au 29/09/2026, un 500 sur `GET /v1/auth/me` sortait tout le monde.
 * Porté de `SessionRestoreTests.swift`, cas pour cas.
 */
class SessionRestoreTest {
    private val yesterday = Account(id = "compte-1", firstName = "Camille", createdAt = Instant.EPOCH)
    private val fresh = Account(id = "compte-1", firstName = "Camille-Rose", createdAt = Instant.EPOCH)

    private val serverDown = ApiError.Server(statusCode = 500, code = null, message = "Erreur interne du serveur.")
    private val offline = ApiError.Transport(IOException("hors ligne"), url = null)

    /** Rejoue `resolve` avec une suite d'issues pour `verify`, une par essai. */
    private suspend fun resolve(
        outcomes: List<Result<Account>>,
        stillStored: Boolean = true,
        remembered: Account? = null,
    ): Pair<SessionRestore, Int> {
        var attempts = 0
        val restore = SessionRestore.resolve(
            verify = {
                val outcome = outcomes[minOf(attempts, outcomes.lastIndex)]
                attempts += 1
                outcome.getOrThrow()
            },
            isStillStored = { stillStored },
            remembered = { remembered },
            retryDelays = listOf(Duration.ZERO, Duration.ZERO),
        )
        return restore to attempts
    }

    @Test fun theServerAnswerWinsOverTheRememberedAccount() = runTest {
        val (restore, _) = resolve(listOf(Result.success(fresh)), remembered = yesterday)
        assertEquals(SessionRestore.Verified(fresh), restore)
    }

    @Test fun aServerErrorEntersWithYesterdaysAccount() = runTest {
        val (restore, attempts) = resolve(listOf(Result.failure(serverDown)), remembered = yesterday)
        assertEquals(SessionRestore.Remembered(yesterday), restore)
        assertEquals(1, attempts, "Avec un compte gardé, on entre sans faire attendre.")
    }

    @Test fun noNetworkEntersWithYesterdaysAccount() = runTest {
        val (restore, _) = resolve(listOf(Result.failure(offline)), remembered = yesterday)
        assertEquals(SessionRestore.Remembered(yesterday), restore)
    }

    /** Le 401 : le client a effacé le jeton, et c'est ce qui décide. */
    @Test fun aRefusedSessionClosesEvenWithARememberedAccount() = runTest {
        val refused = ApiError.Server(statusCode = 401, code = null, message = "Session expirée.")
        val (restore, attempts) = resolve(listOf(Result.failure(refused)), stillStored = false, remembered = yesterday)
        assertEquals(SessionRestore.Closed, restore)
        assertEquals(1, attempts)
    }

    @Test fun withoutARememberedAccountAPassingOutageIsRetried() = runTest {
        val (restore, attempts) = resolve(listOf(Result.failure(serverDown), Result.success(fresh)))
        assertEquals(SessionRestore.Verified(fresh), restore)
        assertEquals(2, attempts)
    }

    @Test fun withoutARememberedAccountALastingOutageGivesUpAfterTheRetries() = runTest {
        val (restore, attempts) = resolve(listOf(Result.failure(serverDown)))
        assertEquals(SessionRestore.Unreachable, restore)
        assertEquals(3, attempts, "Un essai, puis un par attente.")
    }

    /** Une réponse qu'on ne sait pas lire ne se lira pas mieux dans trois secondes. */
    @Test fun anUnreadableAnswerIsNotRetried() = runTest {
        val unreadable = ApiError.Decoding(IOException("illisible"))
        val (restore, attempts) = resolve(listOf(Result.failure(unreadable)))
        assertEquals(SessionRestore.Unreachable, restore)
        assertEquals(1, attempts)
    }
}
