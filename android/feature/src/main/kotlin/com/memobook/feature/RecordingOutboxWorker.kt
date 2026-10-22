package com.memobook.feature

import android.content.Context
import androidx.work.BackoffPolicy
import androidx.work.Constraints
import androidx.work.CoroutineWorker
import androidx.work.ExistingWorkPolicy
import androidx.work.NetworkType
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.WorkerParameters
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.time.Duration
import java.time.Instant
import java.util.concurrent.TimeUnit

/**
 * **La file se vide aussi en arrière-plan** — ce qu'Android a et que l'iPhone
 * n'a pas (`docs/android.md`, « File des envois »). Sans jumeau iOS : là-bas,
 * ce qui n'avait pas eu le temps de partir attendait le retour dans l'app.
 *
 * Un travail de WorkManager sous la contrainte « réseau connecté » : planifié
 * dès qu'un tour ou un voyage se met à attendre ([schedule], appelé par
 * `RecordingOutbox.onPending`), il tourne quand le téléphone retrouve le
 * réseau — app au premier plan, en arrière-plan ou fermée — et appelle
 * `RecordingOutbox.flush()`. Ce qui attend encore le réseau après lui le fait
 * repasser ([Result.retry], avec un délai qui s'allonge) ; ce qui attend le
 * crédit du jour se planifie à l'heure de la recharge (`schedule(context, at)`).
 *
 * Il trouve la file par l'`Application` ([AppDependenciesHost]) : WorkManager
 * construit le travail lui-même, sans rien lui passer.
 */
class RecordingOutboxWorker(context: Context, parameters: WorkerParameters) : CoroutineWorker(context, parameters) {
    override suspend fun doWork(): Result {
        // La file vit sur le fil principal, comme dans l'app — et les
        // dépendances s'y assemblent, une seule fois. Ce qui attend le crédit
        // du jour s'y planifie de lui-même, à sa recharge (`onPending`).
        val stillWaiting = withContext(Dispatchers.Main) {
            (applicationContext as? AppDependenciesHost)?.dependencies?.flushOutboxInBackground()
        } ?: return Result.retry()
        return if (stillWaiting) Result.retry() else Result.success()
    }

    companion object {
        /** Le travail du réseau retrouvé — un seul à la fois. */
        private const val WORK_NAME = "memobook.recording-outbox"

        /**
         * Ceux des recharges du crédit du jour, un par heure de recharge : un
         * nom par heure, et non un seul qu'on remplacerait — le travail qui
         * tourne à minuit replanifie la recharge suivante, et se serait annulé
         * lui-même.
         */
        private const val CREDIT_WORK_PREFIX = "memobook.recording-outbox.credit."

        /** La marge du réveil, comme celle de la file : arriver une seconde trop tôt coûterait une nuit. */
        private const val CREDIT_MARGIN_SECONDS = 5L

        private val constraints = Constraints.Builder().setRequiredNetworkType(NetworkType.CONNECTED).build()

        /**
         * Planifie le vidage au retour du réseau. Sans effet s'il l'est déjà :
         * le travail en attente videra aussi ce qui vient d'arriver.
         */
        fun schedule(context: Context) {
            val request = OneTimeWorkRequestBuilder<RecordingOutboxWorker>()
                .setConstraints(constraints)
                .setBackoffCriteria(BackoffPolicy.EXPONENTIAL, 30, TimeUnit.SECONDS)
                .build()
            WorkManager.getInstance(context).enqueueUniqueWork(WORK_NAME, ExistingWorkPolicy.KEEP, request)
        }

        /**
         * Ce que `RecordingOutbox.onPending` appelle : le retour du réseau
         * quand rien n'est dit (`null`), l'heure de la recharge sinon.
         * `MemoBookApplication` le passe à [AppDependencies].
         */
        fun scheduler(context: Context): (Instant?) -> Unit {
            val application = context.applicationContext
            return { until -> if (until == null) schedule(application) else schedule(application, at = until) }
        }

        /** Planifie le vidage à l'heure où le crédit du jour se recharge. Sans effet s'il l'est déjà pour cette heure-là. */
        fun schedule(context: Context, at: Instant) {
            val delay = Duration.between(Instant.now(), at).seconds.coerceAtLeast(0) + CREDIT_MARGIN_SECONDS
            val request = OneTimeWorkRequestBuilder<RecordingOutboxWorker>()
                .setConstraints(constraints)
                .setInitialDelay(delay, TimeUnit.SECONDS)
                .build()
            WorkManager.getInstance(context)
                .enqueueUniqueWork(CREDIT_WORK_PREFIX + at.epochSecond, ExistingWorkPolicy.KEEP, request)
        }
    }
}
