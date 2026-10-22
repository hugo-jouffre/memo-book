package com.memobook.feature.tripsettings

import android.content.Context
import androidx.compose.animation.Crossfade
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Image
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.size
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import coil3.SingletonImageLoader
import coil3.request.ErrorResult
import coil3.request.ImageRequest
import coil3.request.SuccessResult
import coil3.toBitmap
import com.memobook.design.SwiftMotion
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.isActive
import kotlinx.coroutines.withContext
import java.io.IOException
import java.net.URI
import kotlin.time.Duration
import kotlin.time.Duration.Companion.milliseconds

/**
 * L'aperçu de personnalisation, en tête de l'écran « Personnalisations » : la
 * page que donneraient les réglages qu'on est en train de toucher. Jumeau de
 * `TripSettings/BookCustomisationPreviewView.swift`.
 *
 * **Toujours lui, même quand un carnet a déjà été composé** (Hugo,
 * 02/10/2026) : c'est lui qui répond aux réglages, les vraies pages ne
 * changeraient qu'à la prochaine composition. Elles restent dans l'aperçu du
 * carnet.
 *
 * Les deux cents images ne sont pas dans l'app : elles sont publiées dans le
 * bucket public `memobook-public` (`BookCustomisationPreview.publicBaseURL`),
 * et seule leur correspondance est embarquée (`BookCustomisationPreviewManifest`,
 * dans `:core`) — comme sur iOS, qui ne les met pas non plus dans son catalogue.
 *
 * Trois règles tiennent la tête immobile :
 *
 * - **La place est réservée.** Le bloc a la taille des deux pages d'avant
 *   (`BookPagesPeek.headerSize`), qu'il y ait une image ou non : rien ne saute
 *   sous lui, ni au chargement, ni à l'échec.
 * - **Le papier nu tant que rien n'est arrivé**, puis un fondu. À l'échec, le
 *   papier reste, sans message : l'image est redemandée au réglage suivant, ou
 *   à la prochaine ouverture (Hugo, 02/10/2026). Le repli, lui, n'est pas un
 *   échec : c'est une image comme les autres.
 * - **L'image d'avant reste tant que la suivante n'est pas prête**, et un
 *   curseur qu'on fait glisser ne la change qu'une fois posé — voir
 *   [BookCustomisationPreviewLoader].
 *
 * Ce que l'image montre ne déclenche rien : les douze « composition trop
 * chargée » sont des aperçus comme les autres, le message vit dans l'image.
 *
 * @param url l'image à montrer, ou `null` tant que les réglages ne sont pas lus.
 */
@Composable
internal fun BookCustomisationPreviewView(url: URI?, modifier: Modifier = Modifier) {
    val context = LocalContext.current
    val loader = remember(context) { BookCustomisationPreviewLoader(fetch = BookCustomisationPreviewLoader.download(context)) }
    val shown by loader.shown.collectAsStateWithLifecycle()

    // L'adresse ne dépend que des cinq réglages qui pilotent l'image : le
    // nombre de pages, le quiz, les zones libres et le mot fléché ne la
    // changent pas, et la tâche ne repart pas.
    LaunchedEffect(url) { loader.show(url) }

    // Décor, comme les deux pages qu'il remplace : l'écran dessous dit ce qu'il
    // règle, et TalkBack n'a pas à s'arrêter sur une image.
    Box(modifier.size(BookPagesPeek.headerSize).clearAndSetSemantics {}) {
        // Une identité par image : l'ancienne s'efface pendant que la nouvelle
        // paraît, sans passer par le vide.
        Crossfade(shown, animationSpec = tween(250, easing = SwiftMotion.easeInOut), label = "aperçu") { current ->
            if (current != null) {
                Image(current.image, contentDescription = null, modifier = Modifier.fillMaxSize(), contentScale = ContentScale.Fit)
            } else {
                BookPagesPeek(pdfUrl = null, size = BookPagesPeek.headerSize)
            }
        }
    }
}

/**
 * Ce que la tête montre, et quand elle en change.
 *
 * À part de la vue pour se tester sans écran : la vue ne fait que dessiner
 * [image]. Générique sur l'image, pour que les tests sur la JVM lui donnent
 * des objets à eux — l'app lui donne des [ImageBitmap].
 *
 * @param settle combien de temps un réglage doit tenir avant que l'image le
 *   suive. Un curseur qu'on fait glisser change de valeur à chaque cran ; sans
 *   cette attente, la tête changerait d'image à chacun.
 * @param fetch télécharge et décode une image. Celle de l'app passe par le cache
 *   disque de Coil : les images publiées sont immuables, gardées un an.
 */
internal class BookCustomisationPreviewLoader<Picture : Any>(
    private val settle: Duration = 300.milliseconds,
    private val fetch: suspend (URI) -> Picture,
) {
    /** Une image à l'écran, et son adresse. */
    data class Shown<Picture : Any>(val image: Picture, val url: URI)

    private val _shown = MutableStateFlow<Shown<Picture>?>(null)

    /** Ce que la tête montre. `null` tant qu'aucune image n'est arrivée : le papier nu. */
    val shown: StateFlow<Shown<Picture>?> = _shown.asStateFlow()

    /** L'image à l'écran. `null` tant qu'aucune n'est arrivée : le papier nu. */
    val image: Picture? get() = _shown.value?.image

    /** L'adresse de [image]. */
    val shownURL: URI? get() = _shown.value?.url

    /**
     * Une première adresse a été demandée. Seule celle-là part sans attendre :
     * la regarder plutôt que [image] évite qu'un glissé sur le papier nu — une
     * ouverture lente, ou ratée — ne charge chaque cran.
     */
    private var hasRequested = false

    /**
     * Les dernières images décodées, pour qu'un aller-retour entre deux
     * réglages ne retélécharge rien. Huit, pas deux cents : une image décodée
     * pèse trois mégaoctets. L'ordre d'accès fait le tri, comme le `NSCache`
     * d'iOS à huit entrées.
     */
    private val decoded = object : LinkedHashMap<URI, Picture>(8, 0.75f, true) {
        override fun removeEldestEntry(eldest: MutableMap.MutableEntry<URI, Picture>?): Boolean = size > 8
    }

    /**
     * Montre l'image de cette adresse.
     *
     * Appelée par `LaunchedEffect(url)` : une nouvelle adresse **annule** l'appel
     * en cours, et c'est ce qui fait l'attente du curseur — tant qu'il bouge,
     * chaque appel est annulé avant la fin de son attente, et seul le dernier
     * arrive au bout.
     */
    suspend fun show(url: URI?) {
        if (url == null || url == shownURL) return

        // La première image arrive tout de suite : à l'ouverture, il n'y a pas
        // de geste à attendre. Les suivantes attendent qu'il se pose.
        val isFirst = !hasRequested
        hasRequested = true
        if (!isFirst) {
            try {
                delay(settle)
            } catch (_: CancellationException) {
                return
            }
        }
        // L'attente a pu finir à l'instant où un autre réglage l'annulait :
        // l'image en cache serait alors celle d'un réglage déjà quitté.
        if (!currentCoroutineContext().isActive) return

        decoded[url]?.let { cached ->
            present(cached, url)
            return
        }
        // L'échec ne change rien à l'écran : l'image d'avant, ou le papier nu.
        val loaded = try {
            fetch(url)
        } catch (_: CancellationException) {
            return
        } catch (_: Exception) {
            return
        }
        decoded[url] = loaded
        // Arrivée trop tard, pendant qu'un autre réglage était déjà demandé :
        // gardée pour plus tard, pas montrée.
        if (!currentCoroutineContext().isActive) return
        present(loaded, url)
    }

    private fun present(image: Picture, url: URI) {
        _shown.value = Shown(image, url)
    }

    companion object {
        /**
         * Le téléchargement de l'app : une réponse qui est une image, décodée
         * hors du fil principal, par le chargeur d'images de l'app — son cache
         * disque est le cache HTTP du système d'iOS.
         */
        fun download(context: Context): suspend (URI) -> ImageBitmap {
            val appContext = context.applicationContext
            return { url ->
                val request = ImageRequest.Builder(appContext).data(url.toString()).build()
                when (val result = SingletonImageLoader.get(appContext).execute(request)) {
                    is SuccessResult -> withContext(Dispatchers.Default) {
                        result.image.toBitmap().asImageBitmap().also { it.prepareToDraw() }
                    }
                    is ErrorResult -> throw IOException("Aperçu illisible : $url", result.throwable)
                }
            }
        }
    }
}
