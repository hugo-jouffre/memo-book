package com.memobook.feature

import com.memobook.core.MemoBookJson
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import kotlinx.serialization.KSerializer
import kotlinx.serialization.serializer
import java.io.File

/**
 * Ce que l'app garde du serveur sur l'appareil, pour rouvrir vite. Jumeau de
 * `ContentCache.swift`.
 *
 * **Deux usages pour une seule pièce** : relire hors ligne, et ouvrir vite —
 * un écran déjà vu se dessine avec ce qu'on avait pendant que la lecture réseau
 * continue derrière (Hugo, 16/09/2026).
 *
 * ### Ce qu'on garde, et ce qu'on ne garde pas
 *
 * **Une copie de ce que le serveur sait, et rien d'autre.** Ce qui n'existe
 * nulle part ailleurs — un vocal en attente — vit dans `filesDir` et n'est pas
 * là (voir `PendingRecordingStore`).
 *
 * | Gardé | Pourquoi |
 * |---|---|
 * | le compte ([Slot.Account]) | rouvrir l'app quand `GET /v1/auth/me` ne répond pas — voir [SessionRestore] |
 * | l'accueil ([Slot.Home]) | le premier écran, et le seul qui doit s'ouvrir sans réseau |
 * | le profil ([Slot.Profile]) | son abonnement et son adresse changent rarement |
 * | un voyage ([Slot.Trip]) | on y revient dix fois par jour pendant un voyage |
 * | ses réglages ([Slot.TripSettings]) | trente valeurs pour un écran qu'on ouvre pour en changer une |
 * | la galerie ([Slot.Gallery]) | des carnets publics, qui bougent à l'échelle de la semaine |
 * | les derniers messages d'un fil ([Slot.Chat]) | rouvrir la conversation sans réseau sur ce qu'on s'était dit |
 *
 * Ce qu'on **ne garde pas**, et c'est délibéré : les commandes — c'est de
 * l'argent, et un état périmé est pire qu'un état absent ; les rendus PDF ;
 * les photos, qui passent par le cache disque de Coil (256 Mo, comme le cache
 * d'URL d'iOS).
 *
 * ### Où ça vit
 *
 * Dans **`cacheDir`**, jamais ailleurs : c'est une copie, Android peut la
 * purger sous pression disque, et on la redemande. Et ça s'efface à la
 * déconnexion ([clearAll]).
 *
 * Un `actor` sur iOS ; ici un verrou et le répartiteur d'entrées-sorties.
 */
class ContentCache(private val directory: File) {
    /**
     * Ce qu'on range, et sous quel nom de fichier. Une énumération et non une
     * chaîne libre : deux écrans qui écriraient sous la même clé se
     * recouvriraient l'un l'autre, et le compilateur ne dirait rien.
     */
    sealed interface Slot {
        data object Account : Slot
        data object Home : Slot
        data object Profile : Slot
        data object Statistics : Slot
        data object Gallery : Slot
        data class Trip(val id: String) : Slot
        data class TripSettings(val id: String) : Slot
        data class Chat(val id: String) : Slot

        /**
         * Le nom du fichier. L'identifiant du voyage y entre **haché** plutôt
         * qu'en clair : on ne pose pas d'identifiants de ressources dans
         * l'arborescence d'un appareil.
         */
        val filename: String
            get() = when (this) {
                Account -> "account.json"
                Home -> "home.json"
                Profile -> "profile.json"
                Statistics -> "statistics.json"
                Gallery -> "gallery.json"
                is Trip -> "trip-${digest(id)}.json"
                is TripSettings -> "trip-settings-${digest(id)}.json"
                is Chat -> "chat-${digest(id)}.json"
            }

        companion object {
            /**
             * Une empreinte **stable** — la même que celle d'iOS (djb2, en base
             * 36) : un `hashCode` ferait aussi l'affaire, mais garder la même
             * somme ne coûte rien.
             */
            internal fun digest(value: String): String {
                var hash = 5381uL
                for (byte in value.encodeToByteArray()) hash = hash * 33uL + byte.toUByte().toULong()
                return hash.toString(36)
            }
        }
    }

    private val lock = Mutex()

    /**
     * Ce qu'on avait. `null` quand il n'y a rien, quand Android a fait le
     * ménage, ou quand le fichier date d'un modèle qui a changé depuis — dans
     * les trois cas, il n'y a rien à réparer, il y a un appel à faire.
     */
    suspend fun <T> read(slot: Slot, serializer: KSerializer<T>): T? = withContext(Dispatchers.IO) {
        lock.withLock {
            val file = File(directory, slot.filename)
            if (!file.exists()) return@withLock null
            runCatching { MemoBookJson.decodeFromString(serializer, file.readText()) }.getOrNull()
        }
    }

    suspend inline fun <reified T> read(slot: Slot): T? = read(slot, serializer<T>())

    /** Une écriture ratée n'est pas une erreur d'écran : au pire, il n'y aura rien à relire. */
    suspend fun <T> write(slot: Slot, value: T, serializer: KSerializer<T>) {
        withContext(Dispatchers.IO) {
            lock.withLock {
                runCatching {
                    directory.mkdirs()
                    val text = MemoBookJson.encodeToString(serializer, value)
                    // Écrit à côté, puis renommé : un fichier à moitié écrit ne
                    // se relit jamais (le `.atomic` d'iOS).
                    val temporary = File(directory, "${slot.filename}.tmp")
                    temporary.writeText(text)
                    if (!temporary.renameTo(File(directory, slot.filename))) temporary.delete()
                }
            }
        }
    }

    suspend inline fun <reified T> write(slot: Slot, value: T) = write(slot, value, serializer<T>())

    /** Efface tout. À la déconnexion, et à elle seule. */
    suspend fun clearAll() {
        withContext(Dispatchers.IO) { lock.withLock { directory.deleteRecursively() } }
    }
}
