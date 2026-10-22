package com.memobook.feature.bookpreview

import android.graphics.Bitmap
import android.graphics.Color
import android.graphics.pdf.PdfRenderer
import android.os.ParcelFileDescriptor
import android.util.LruCache
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.produceState
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.semantics.clearAndSetSemantics
import com.memobook.design.MemoBookColor
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import okhttp3.OkHttpClient
import okhttp3.Request
import java.io.File
import java.io.IOException
import java.util.UUID
import java.util.concurrent.atomic.AtomicBoolean

/**
 * Le PDF du carnet, et ses pages rendues à la demande. Jumeau de
 * `BookPreview/BookPageRenderer.swift`.
 *
 * **L'app ne redessine pas le carnet, elle affiche le PDF.** C'est le seul
 * moyen d'être sûr que l'aperçu montre ce qui sortira de l'imprimante, et c'est
 * aussi le plus rapide : rendre une page A5 à 250 dp de large coûte quelques
 * millisecondes à `PdfRenderer` — le PDFKit d'Android —, là où rejouer la mise
 * en page en Compose demanderait de réimplémenter le template, et de le
 * maintenir en double.
 *
 * Trois choses tiennent la fluidité de l'écran :
 *
 * 1. **Une page n'est rendue qu'une fois.** Les images vivent dans un
 *    [LruCache] **compté en octets** : le `NSCache` d'iOS rend ses images au
 *    système quand la mémoire manque, celui d'Android ne le sait pas. Une
 *    limite en nombre (24 sur iOS) laisserait vingt-quatre pages plein écran
 *    — neuf mégaoctets chacune — tuer l'app ; c'est donc le huitième de la
 *    mémoire de l'app, la recette d'Android pour un cache d'images.
 * 2. **La page voisine est préparée d'avance.** Tourner la page ne déclenche
 *    donc aucun rendu : il a eu lieu pendant qu'on lisait la précédente.
 * 3. **Le document n'est pas un cache.** Le lien est signé et de courte durée ;
 *    le garder ne servirait qu'à afficher un carnet périmé. `PdfRenderer` ne
 *    lit pourtant qu'un **fichier** — PDFKit, lui, ouvre des données en
 *    mémoire : il est écrit dans le cache de l'app (`book-pages/`), réécrit à
 *    chaque chargement, et effacé à la fermeture de l'écran ([close]). Jamais
 *    dans `ContentCache` : ce n'est pas du contenu à relire hors ligne.
 *
 * **Un seul fil** lit le document : `PdfRenderer` ne tient qu'une page ouverte à
 * la fois et ne se partage pas entre deux fils. Tout passe donc par
 * [documentThread], et aucun verrou n'est nécessaire.
 *
 * @param directory le dossier de travail — le cache de l'app.
 * @param download descend le PDF de l'adresse dans le fichier, et rend `false`
 *   sur une réponse HTTP hors des 2xx. Un double dans les tests.
 */
class BookPageRenderer(
    private val directory: File,
    private val download: suspend (url: String, into: File) -> Boolean = ::downloadDocument,
) {
    /**
     * Ce que l'écran sait du document. Recopié dans l'état du modèle à chaque
     * chargement : l'écran le lit là, avec le reste.
     *
     * @property sheetCount combien de feuilles le PDF contient. Distinct de
     *   `BookPreview.pageCount`, qui vient du serveur : celui-ci est la vérité
     *   du document, et c'est lui que le compteur du plein écran affiche
     *   (« 1 sur 24 »).
     * @property didFail le chargement a échoué. Le carnet existe, c'est le
     *   téléchargement qui n'a pas abouti — d'où un message qui propose de
     *   réessayer, pas de recomposer.
     * @property aspectRatio le rapport largeur / hauteur de la première
     *   feuille. Il vient du **document** et non d'une constante : le template
     *   est en A5 aujourd'hui, il peut changer, et une page rendue dans le
     *   mauvais rapport se voit immédiatement. 1/√2 tant que rien n'est chargé
     *   — c'est l'A5, le format actuel du carnet.
     * @property generation monte à chaque document ouvert : les images déjà
     *   rendues d'un autre document ne valent plus rien, et les vues qui les
     *   montrent se redemandent la leur.
     */
    data class Document(
        val sheetCount: Int = 0,
        val didFail: Boolean = false,
        val aspectRatio: Float = 1f / 1.414f,
        val generation: Int = 0,
    )

    /** Le dernier état du document. */
    @Volatile
    var document: Document = Document()
        private set

    private val isLoading = AtomicBoolean(false)

    /**
     * Le fichier de ce rendu-ci. Un nom à lui, et non celui du carnet : la
     * feuille du paywall et l'écran de l'aperçu peuvent montrer le même carnet
     * en même temps, et l'un réécrirait le fichier que l'autre lit.
     */
    private val workFile: File by lazy { File(File(directory, "book-pages"), "${UUID.randomUUID()}.pdf") }

    /** Le document ouvert, et le descripteur qu'il lit. Touchés sur [documentThread] seulement. */
    private var renderer: PdfRenderer? = null
    private var descriptor: ParcelFileDescriptor? = null

    /**
     * Ce qui a été rendu. La clé porte la largeur : la même page en vignette et
     * en plein écran sont deux images, et la seconde ne doit pas remplacer la
     * première dans la bande de miniatures.
     *
     * Paresseux : un modèle de test n'ouvre jamais de document, et n'a pas à
     * construire un cache d'Android.
     */
    private val cache: LruCache<String, Bitmap> by lazy {
        val kilobytes = (Runtime.getRuntime().maxMemory() / 1024 / 8).toInt()
        object : LruCache<String, Bitmap>(kilobytes) {
            override fun sizeOf(key: String, value: Bitmap): Int = value.byteCount / 1024
        }
    }

    /**
     * Ouvre le PDF. Rejouable : réessayer après un échec passe par ici.
     *
     * Le document est descendu en entier avant d'être ouvert, comme sur iOS :
     * `PdfRenderer` ne sait pas lire un lien, et le faire attendre le réseau
     * bloquerait le fil qui rend les pages.
     */
    suspend fun load(url: String): Document {
        if (!isLoading.compareAndSet(false, true)) return document
        try {
            document = document.copy(didFail = false)
            val partial = File(workFile.parentFile, "${workFile.name}.part")
            val downloaded = try {
                withContext(Dispatchers.IO) {
                    workFile.parentFile?.mkdirs()
                    download(url, partial)
                }
            } catch (error: CancellationException) {
                throw error
            } catch (_: IOException) {
                false
            }
            if (!downloaded) {
                partial.delete()
                document = document.copy(didFail = true)
                return document
            }
            document = withContext(documentThread) { open(partial) }
            return document
        } finally {
            isLoading.set(false)
        }
    }

    /**
     * Remplace le document ouvert par celui qui vient d'arriver — **seulement
     * s'il s'ouvre** : un téléchargement qui rend autre chose qu'un PDF laisse
     * le carnet d'avant à l'écran, comme sur iOS. Sur [documentThread].
     */
    private fun open(partial: File): Document {
        val opened: ParcelFileDescriptor
        val pdf: PdfRenderer
        try {
            opened = ParcelFileDescriptor.open(partial, ParcelFileDescriptor.MODE_READ_ONLY)
            pdf = try {
                PdfRenderer(opened)
            } catch (error: Exception) {
                opened.close()
                throw error
            }
        } catch (_: IOException) {
            // Ce qui est arrivé n'est pas un PDF lisible.
            partial.delete()
            return document.copy(didFail = true)
        } catch (_: SecurityException) {
            // Un PDF protégé par mot de passe : `PdfRenderer` refuse de l'ouvrir.
            partial.delete()
            return document.copy(didFail = true)
        }

        closeDocument()
        // Le descripteur reste valable une fois le fichier renommé : le
        // document ouvert continue de le lire sous son nouveau nom.
        partial.renameTo(workFile)
        descriptor = opened
        renderer = pdf
        cache.evictAll()

        var ratio = document.aspectRatio
        if (pdf.pageCount > 0) {
            pdf.openPage(0).use { first -> if (first.height > 0) ratio = first.width.toFloat() / first.height }
        }
        return Document(sheetCount = pdf.pageCount, didFail = false, aspectRatio = ratio, generation = document.generation + 1)
    }

    /**
     * L'image d'une feuille si elle est déjà rendue — de quoi dessiner tout de
     * suite, sans attendre, dans la quasi-totalité des cas : voir [prepare],
     * qui a déjà fait le travail.
     */
    fun cachedImage(sheet: Int, width: Int): ImageBitmap? {
        if (document.sheetCount == 0 || width <= 0) return null
        return cache.get(key(sheet, width))?.asImageBitmap()
    }

    /**
     * L'image d'une feuille, rendue si besoin. Suspendue, et non synchrone
     * comme sur iOS : le rendu se fait sur le fil du document, jamais sur
     * celui de l'écran.
     */
    suspend fun image(sheet: Int, width: Int): ImageBitmap? {
        cachedImage(sheet, width)?.let { return it }
        return withContext(documentThread) { render(sheet, width) }?.asImageBitmap()
    }

    /** Le rendu lui-même. Sur [documentThread]. */
    private fun render(sheet: Int, width: Int): Bitmap? {
        val pdf = renderer ?: return null
        if (sheet < 0 || sheet >= pdf.pageCount || width <= 0) return null

        val key = key(sheet, width)
        cache.get(key)?.let { return it }

        return pdf.openPage(sheet).use { page ->
            if (page.width <= 0 || page.height <= 0) return@use null
            val height = (width.toLong() * page.height / page.width).toInt().coerceAtLeast(1)
            val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
            // Le blanc du papier sous la page : un PDF sans fond se rend
            // transparent, là où PDFKit pose le blanc de lui-même.
            bitmap.eraseColor(Color.WHITE)
            page.render(bitmap, null, null, PdfRenderer.Page.RENDER_MODE_FOR_DISPLAY)
            cache.put(key, bitmap)
            bitmap
        }
    }

    /**
     * Prépare la feuille demandée et ses voisines immédiates.
     *
     * C'est ce qui fait que tourner la page ne coûte rien : le rendu a eu lieu
     * pendant qu'on lisait la page d'avant. Trois feuilles et pas plus — au
     * delà, on rendrait un carnet entier pour un lecteur qui va s'arrêter à la
     * troisième page.
     */
    suspend fun prepare(around: Int, width: Int) {
        if (document.sheetCount == 0) return
        for (offset in listOf(0, 1, -1)) image(around + offset, width)
    }

    /**
     * Le PDF, tel quel, pour le partager. Le fichier et non le lien : le lien
     * du serveur est signé et expire. `null` quand rien n'est chargé.
     */
    val documentFile: File?
        get() = workFile.takeIf { document.sheetCount > 0 && it.isFile }

    /**
     * Ferme le document et efface son fichier — l'écran s'en va. Sur le fil du
     * document, après le rendu qui y tournerait encore : le modèle qui
     * l'appelle n'a plus de portée où l'attendre.
     */
    fun close() {
        closer.launch {
            closeDocument()
            workFile.delete()
        }
    }

    private fun closeDocument() {
        renderer?.close()
        renderer = null
        descriptor?.close()
        descriptor = null
    }

    /**
     * La largeur est arrondie au pixel par l'appelant : sans ça, deux rendus de
     * la même page à 251,7 et 251,9 seraient deux entrées de cache, et le
     * second recalculerait pour rien.
     */
    private fun key(sheet: Int, width: Int) = "$sheet@$width"

    companion object {
        /** Le fil unique du document — voir l'en-tête. */
        @OptIn(ExperimentalCoroutinesApi::class)
        private val documentThread = Dispatchers.IO.limitedParallelism(1)

        /** Où se ferment les documents des écrans partis. */
        private val closer = CoroutineScope(SupervisorJob() + documentThread)

        /**
         * Le client du téléchargement. **Pas celui de l'API** : le PDF vit sur
         * un stockage, derrière un lien déjà signé, et la session n'a rien à y
         * faire — c'est le `URLSession.shared` d'iOS.
         */
        private val client by lazy { OkHttpClient() }

        private fun downloadDocument(url: String, into: File): Boolean {
            val request = try {
                Request.Builder().url(url).build()
            } catch (_: IllegalArgumentException) {
                return false
            }
            client.newCall(request).execute().use { response ->
                if (!response.isSuccessful) return false
                into.outputStream().use { output -> response.body.byteStream().copyTo(output) }
            }
            return true
        }
    }
}

/**
 * Une feuille du carnet, rendue depuis le PDF.
 *
 * Elle mesure d'abord, rend ensuite : la largeur de rendu est celle que la vue
 * occupe vraiment, en pixels. Une page rendue à 252 dp puis étirée à 390 serait
 * floue, et une page rendue à 1 170 px pour une vignette de 42 dp serait du
 * gâchis.
 *
 * @param showsPlaceholder le repli affiché tant que le document n'est pas là :
 *   le papier du carnet, vide. **Pas un gris système** — ce serait un champ
 *   désactivé.
 */
@Composable
internal fun BookSheetImage(
    renderer: BookPageRenderer,
    document: BookPageRenderer.Document,
    index: Int,
    modifier: Modifier = Modifier,
    showsPlaceholder: Boolean = true,
) {
    BoxWithConstraints(modifier.clearAndSetSemantics {}) {
        val width = constraints.maxWidth.takeIf { constraints.hasBoundedWidth } ?: 0
        val image by produceState(renderer.cachedImage(index, width), index, width, document.generation) {
            value = renderer.cachedImage(index, width) ?: renderer.image(index, width)
        }
        val shown = image
        if (shown != null) {
            Image(shown, contentDescription = null, modifier = Modifier.fillMaxSize(), contentScale = ContentScale.Crop)
        } else if (showsPlaceholder) {
            Box(Modifier.fillMaxSize().background(MemoBookColor.paper))
        }
    }
}
