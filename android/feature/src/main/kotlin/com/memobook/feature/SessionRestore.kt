package com.memobook.feature

import com.memobook.core.Account
import com.memobook.networking.ApiError
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.delay
import kotlin.time.Duration
import kotlin.time.Duration.Companion.seconds

/**
 * Ce que le lancement fait d'une session gardée. Jumeau de `SessionRestore.swift`.
 *
 * **Seul un refus du serveur ferme une session, et il le dit par un 401.** Le
 * client efface alors le jeton qu'il avait présenté : tant que le jeton est
 * gardé, la session n'a pas été refusée, quoi qu'il soit arrivé à l'appel.
 *
 * Tout le reste est une panne — un 500, un délai dépassé, un réseau coupé. Du
 * 27 au 29/09/2026, `GET /v1/auth/me` a rendu 500 : chaque lancement à froid
 * sortait les testeurs de leur compte. Sur une panne, on rentre donc avec **le
 * compte d'hier** ([ContentCache.Slot.Account]).
 */
sealed interface SessionRestore {
    /** Le serveur a relu le compte. */
    data class Verified(val account: Account) : SessionRestore

    /** Le serveur n'a pas répondu, ou mal, mais n'a pas refusé la session. */
    data class Remembered(val account: Account) : SessionRestore

    /** Plus de session : le serveur l'a refusée, ou il n'y en avait pas. */
    data object Closed : SessionRestore

    /** La session tient peut-être, mais le serveur ne répond pas et aucun compte n'est gardé. */
    data object Unreachable : SessionRestore

    companion object {
        /**
         * Décide, à partir des trois questions à poser. Une fonction et non une
         * méthode du client : ce qu'elle décide ne dépend que de ces trois
         * réponses, et c'est ce qui la rend vérifiable sans serveur.
         *
         * @param verify relit le compte auprès du serveur.
         * @param isStillStored le jeton est-il encore gardé, **après** l'appel ?
         * @param remembered le compte gardé la dernière fois, s'il y en a un.
         * @param retryDelays les attentes entre deux essais, quand aucun compte
         *   n'est gardé et que la panne vaut qu'on réessaie.
         */
        suspend fun resolve(
            verify: suspend () -> Account,
            isStillStored: suspend () -> Boolean,
            remembered: suspend () -> Account?,
            retryDelays: List<Duration> = listOf(1.seconds, 3.seconds),
        ): SessionRestore {
            val delays = ArrayDeque(retryDelays)
            while (true) {
                val failure: Throwable = try {
                    return Verified(verify())
                } catch (error: CancellationException) {
                    throw error
                } catch (error: Exception) {
                    error
                }

                if (!isStillStored()) return Closed
                remembered()?.let { return Remembered(it) }

                if ((failure as? ApiError)?.isRetryable != true || delays.isEmpty()) return Unreachable
                delay(delays.removeFirst())
            }
        }
    }
}
