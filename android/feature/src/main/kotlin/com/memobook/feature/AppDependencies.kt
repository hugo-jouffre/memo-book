package com.memobook.feature

import com.memobook.core.Account
import com.memobook.networking.ApiConfiguration
import com.memobook.networking.ApiError
import com.memobook.networking.Connectivity
import com.memobook.networking.MemoBookApi
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Deferred
import kotlinx.coroutines.async
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.serialization.KSerializer
import kotlinx.serialization.serializer
import java.io.File

/**
 * Les dépendances que les écrans partagent. Un seul point d'assemblage, comme
 * `AppDependencies.swift` : construit une fois par `MemoBookApplication`, puis
 * descendu aux écrans. Pas de singleton, pas de framework d'injection.
 *
 * **L'enregistrement de l'appareil n'est pas une condition de démarrage.** Il
 * est **paresseux** : il se déclenche au premier appel réseau qui en a besoin,
 * et son échec est l'erreur de cet appel-là, pas un mur devant l'app.
 *
 * ### Les modèles branchés sur l'API
 *
 * Chaque écran reçoit une **source**, une fonction qui rend son contenu. Sur
 * iOS, les fabriques (`homeModel()`, `tripModel(id:)`…) sont des méthodes de
 * cette classe ; ici ce sont des **fonctions d'extension**, chacune dans le
 * paquet de son écran (`home/HomeDependencies.kt`…) : un écran porté n'a pas à
 * rouvrir ce fichier. Elles lisent [api], [content] et [cachedSource], internes
 * au module.
 *
 * @param api le client d'API — le vrai, ou `PreviewApi` sous `previewSignedIn`.
 * @param apiConfiguration l'adresse que le client vise, pour la ligne de
 *   développeur de l'écran de lancement. `null` dans le bac à sable.
 * @param cacheDirectory où [ContentCache] écrit — `cacheDir` dans l'app.
 * @param filesDirectory où dorment ce qui n'existe nulle part ailleurs : les
 *   vocaux et les voyages en attente — `filesDir` dans l'app.
 * @param scope la portée de l'app entière : ce qui y est lancé survit aux
 *   écrans (la file des envois, l'enregistrement de l'appareil).
 */
class AppDependencies(
    val api: MemoBookApi,
    val apiConfiguration: ApiConfiguration?,
    val connectivity: Connectivity,
    val settings: AppSettings,
    val switches: LaunchSwitches,
    cacheDirectory: File,
    val filesDirectory: File,
    val scope: CoroutineScope,
) {
    /**
     * Ce que l'app garde du serveur sur l'appareil — voir [ContentCache].
     * **Deux usages pour une seule pièce** : relire hors ligne, et ouvrir vite.
     */
    internal val content = ContentCache(File(cacheDirectory, "memobook-content"))

    /** Le bac à sable : le jeu d'essai, aucun jeton, aucun appel qui aboutisse. */
    val isPreviewingSignedIn: Boolean get() = switches.previewSignedIn

    private val registrationLock = Mutex()
    private var registration: Deferred<Unit>? = null

    /**
     * Efface ce que l'app garde du compte qui s'en va. À appeler à la
     * déconnexion : les voyages de quelqu'un ne doivent pas apparaître, même
     * une demi-seconde, devant la personne suivante.
     *
     * **Les vocaux en attente, eux, restent** : si le même compte revient, ils
     * repartent ; si c'en est un autre, le serveur les refuse et la file le dit.
     */
    suspend fun forgetAccountContent() {
        content.clearAll()
        accountForgetters.forEach { it() }
    }

    /**
     * Ce que d'autres pièces doivent oublier avec le compte — le dernier crédit
     * du jour de chaque conversation, la file qui change de compte. Elles s'y
     * inscrivent en se construisant, au lieu que ce fichier les connaisse toutes.
     */
    private val accountForgetters = mutableListOf<suspend () -> Unit>()
    private val accountRememberers = mutableListOf<suspend (Account) -> Unit>()

    fun onForgetAccount(action: suspend () -> Unit) {
        accountForgetters += action
    }

    fun onRememberAccount(action: suspend (Account) -> Unit) {
        accountRememberers += action
    }

    /**
     * Relit la session gardée — voir [SessionRestore]. Une session refusée
     * emporte ce qu'on gardait du compte, comme une déconnexion.
     */
    suspend fun restoreSession(): SessionRestore {
        val restore = SessionRestore.resolve(
            verify = { api.currentAccount() },
            isStillStored = { api.hasStoredSession() },
            remembered = { content.read<Account>(ContentCache.Slot.Account) },
        )
        if (restore == SessionRestore.Closed) forgetAccountContent()
        return restore
    }

    /** Garde le compte de la session ouverte, pour rouvrir l'app le jour où le serveur ne répond pas. */
    suspend fun rememberAccount(account: Account) {
        content.write(ContentCache.Slot.Account, account)
        accountRememberers.forEach { it(account) }
    }

    /**
     * Garantit que l'appareil est enregistré avant un appel réseau. Idempotent,
     * et rejouable : après une panne réseau, l'appel suivant retente au lieu de
     * rester bloqué sur l'échec précédent.
     */
    suspend fun ensureRegistered() {
        val task = registrationLock.withLock {
            registration?.takeUnless { it.isCompleted && it.getCompletionExceptionOrNull() != null }
                ?: scope.async { api.ensureDeviceRegistered() }.also { registration = it }
        }
        task.await()
    }

    /**
     * Enveloppe une lecture réseau du cache : elle **recopie** ce qui arrive,
     * et **relit** ce qu'elle avait si le transport échoue.
     *
     * **On ne se replie que sur une panne de transport.** Un 500 ou un 404
     * sont des réponses : les cacher derrière un contenu périmé, c'est masquer
     * une panne du serveur.
     */
    internal fun <Value> cachedSource(
        slot: ContentCache.Slot,
        serializer: KSerializer<Value>,
        fetch: suspend () -> Value,
    ): suspend () -> Value = {
        try {
            fetch().also { content.write(slot, it, serializer) }
        } catch (error: CancellationException) {
            throw error
        } catch (error: Exception) {
            if ((error as? ApiError)?.isTransport != true) throw error
            content.read(slot, serializer) ?: throw error
        }
    }

    internal inline fun <reified Value> cachedSource(
        slot: ContentCache.Slot,
        noinline fetch: suspend () -> Value,
    ): suspend () -> Value = cachedSource(slot, serializer<Value>(), fetch)

    /** Ce qu'on avait pour [slot], pour le `cached` d'un modèle. */
    internal inline fun <reified Value> cached(slot: ContentCache.Slot): CachedValue<Value> = { content.read<Value>(slot) }
}
