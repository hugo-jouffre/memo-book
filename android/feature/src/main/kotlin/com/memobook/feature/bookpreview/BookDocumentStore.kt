package com.memobook.feature.bookpreview

import com.memobook.core.MemoBookJson
import com.memobook.feature.ContentCache
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import kotlinx.serialization.Serializable
import java.io.File

/**
 * **Le dernier carnet composé, gardé sur l'appareil** (T299, Hugo, 08/11/2026
 * — « la dernière version est gardée sur le téléphone, donc lisible sans
 * réseau »). Porté de `BookDocumentStore.swift`.
 *
 * L'aperçu redescendait son PDF à chaque ouverture. La composition, elle, ne se
 * relançait plus pour rien depuis T224 — l'empreinte du carnet dit si quelque
 * chose a changé —, mais le transfert restait : plusieurs mégaoctets avant la
 * première page, à chaque fois, et rien du tout sans réseau.
 *
 * ### Un seul carnet par voyage, et c'est ce qui le borne
 *
 * Un voyage n'a qu'un carnet. Le fichier porte donc le voyage, et une
 * composition nouvelle remplace la précédente : le dossier ne grandit pas avec
 * le temps, il grandit avec le nombre de voyages qu'on a ouverts.
 *
 * À côté du PDF, une fiche dit **quel rendu** il montre ([Kept.renderId]) et
 * **quand** on l'a reçu. Le premier sert à ne pas redescendre ce qu'on a déjà —
 * c'est l'économie —, le second à le dire à l'écran quand c'est tout ce qu'on a.
 *
 * ### Où ça vit, et pourquoi là
 *
 * Dans le **cache** de l'app, comme [ContentCache] et pour la même raison :
 * c'est une copie de ce que le serveur sait, Android peut la purger, et on la
 * redemande. Et ça s'efface à la déconnexion ([clearAll]) : ce sont les voyages
 * de quelqu'un.
 *
 * ⚠️ **Le fichier et non les octets**, là où iOS garde des `Data` :
 * `PdfRenderer` ne lit qu'un fichier — voir [BookPageRenderer]. Le magasin rend
 * donc un `File`, et l'appelant ne le lit jamais en mémoire.
 */
class BookDocumentStore(private val directory: File) {
    /** Le carnet qu'on avait, et ce qu'on sait de lui. */
    data class Kept(
        val file: File,
        /**
         * Le rendu derrière ce PDF. C'est lui qu'on compare au
         * `readyRenderId` du serveur : égaux, il n'y a rien à redescendre.
         */
        val renderId: String,
        /** Quand ce PDF est arrivé sur l'appareil, en millisecondes. */
        val keptAt: Long,
    )

    /** La fiche posée à côté du PDF. */
    @Serializable
    private data class Card(val renderId: String, val keptAt: Long)

    private val lock = Mutex()

    /**
     * Le carnet gardé pour ce voyage. `null` quand il n'y en a pas, quand
     * Android a fait le ménage, ou quand le PDF et sa fiche se sont
     * désolidarisés — dans les trois cas il n'y a rien à réparer, il y a un
     * appel à faire.
     */
    suspend fun kept(memoId: String): Kept? = withContext(Dispatchers.IO) {
        lock.withLock {
            val document = documentFile(memoId)
            if (!document.isFile || document.length() == 0L) return@withLock null
            val card = cardFile(memoId)
            if (!card.isFile) return@withLock null
            val decoded = runCatching {
                MemoBookJson.decodeFromString(Card.serializer(), card.readText())
            }.getOrNull() ?: return@withLock null
            Kept(file = document, renderId = decoded.renderId, keptAt = decoded.keptAt)
        }
    }

    /**
     * Garde ce PDF comme le carnet de ce voyage, en remplaçant le précédent.
     *
     * **Le PDF d'abord, la fiche ensuite** : interrompue entre les deux,
     * l'écriture laisse un PDF sans fiche, que [kept] refuse — on
     * redescendra. L'ordre inverse laisserait une fiche qui promet un fichier
     * absent.
     */
    suspend fun keep(source: File, renderId: String, memoId: String, at: Long = System.currentTimeMillis()) {
        withContext(Dispatchers.IO) {
            lock.withLock {
                runCatching {
                    if (!source.isFile || source.length() == 0L) return@runCatching
                    directory.mkdirs()
                    // Recopié à côté puis renommé : un fichier à moitié écrit
                    // ne se relit jamais (le `.atomic` d'iOS).
                    val temporary = File(directory, "${documentFile(memoId).name}.tmp")
                    source.copyTo(temporary, overwrite = true)
                    if (!temporary.renameTo(documentFile(memoId))) {
                        temporary.delete()
                        return@runCatching
                    }
                    cardFile(memoId).writeText(
                        MemoBookJson.encodeToString(Card.serializer(), Card(renderId, at)),
                    )
                }
            }
        }
    }

    /** Efface tout. À la déconnexion, et à elle seule. */
    suspend fun clearAll() {
        withContext(Dispatchers.IO) { lock.withLock { directory.deleteRecursively() } }
    }

    private fun documentFile(memoId: String) =
        File(directory, "book-${ContentCache.Slot.digest(memoId)}.pdf")

    private fun cardFile(memoId: String) =
        File(directory, "book-${ContentCache.Slot.digest(memoId)}.json")
}
