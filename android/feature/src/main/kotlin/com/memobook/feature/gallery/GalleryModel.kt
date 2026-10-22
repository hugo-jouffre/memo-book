package com.memobook.feature.gallery

import androidx.lifecycle.ViewModel
import com.memobook.core.Gallery
import com.memobook.core.GalleryCategory
import com.memobook.core.GalleryTrip
import com.memobook.feature.CachedValue
import com.memobook.feature.ContentFreshness
import com.memobook.feature.contentFreshness
import com.memobook.networking.ApiError
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update

/**
 * Ce que la galerie des carnets sait faire : charger son contenu, le filtrer
 * par catégorie, et le ranger en colonnes. Jumeau de `Gallery/GalleryModel.swift`.
 *
 * Même construction que `HomeModel` et `TripHomeModel` : le modèle ne connaît
 * pas l'API, il reçoit **une source**. L'app y branche `api.gallery()` (voir
 * `AppDependencies.galleryModel()`), les aperçus n'en fournissent aucune et
 * tombent sur le jeu d'essai.
 *
 * **Les colonnes sont calculées ici, pas dans la vue.** Une mosaïque se répartit
 * en mesurant ce qui est déjà posé ; le faire dans une recomposition, c'est le
 * refaire à chaque image d'animation — et la grille se réorganiserait sous les
 * doigts pendant qu'on fait défiler.
 *
 * @param cached ce qu'on avait sur le disque — voir `ContentCache`. `null` en
 *   aperçu.
 */
class GalleryModel(
    private val source: suspend () -> Gallery = { Gallery.fixture },
    private val cached: CachedValue<Gallery>? = null,
) : ViewModel() {
    /**
     * @property selectedCategoryId la catégorie cochée. `null` veut dire
     *   « Tout » : c'est l'état d'ouverture de l'écran.
     * @property columns les carnets déjà répartis en colonnes, prêts à être
     *   empilés tels quels.
     * @property freshness ce que le dernier chargement a appris. C'est lui que
     *   la vue anime — voir `BrandRefreshFlash`.
     */
    data class State(
        val gallery: Gallery? = null,
        val errorMessage: String? = null,
        val selectedCategoryId: String? = null,
        val columns: List<List<GalleryTrip>> = emptyList(),
        val freshness: ContentFreshness = ContentFreshness.Unknown,
    ) {
        /**
         * `true` tant qu'on n'a rien à montrer. L'écran pose alors des vignettes
         * vides plutôt qu'un trou : la grille garde sa forme, seules les images
         * et les mots arrivent après.
         */
        val isLoading: Boolean get() = gallery == null && errorMessage == null

        val categories: List<GalleryCategory> get() = gallery?.categories.orEmpty()

        /**
         * Le voyage qu'on propose de reprendre. C'est lui qui décide du bouton
         * du bas : « Continuer mon voyage » s'il existe, « Créer mon voyage »
         * sinon.
         */
        val resumableTripId: String? get() = gallery?.resumableTripId

        /**
         * La galerie est vide — soit qu'aucun carnet public n'existe encore,
         * soit que la catégorie cochée n'en range aucun. Les deux ne disent pas
         * la même chose, et l'écran ne les raconte pas pareil.
         */
        val isEmpty: Boolean get() = columns.all { it.isEmpty() }
    }

    private val _state = MutableStateFlow(State())
    val state: StateFlow<State> = _state.asStateFlow()

    /**
     * Le nombre de colonnes de la mosaïque.
     *
     * Il **vient de la vue** et non des données : il dépend de la taille de
     * texte de l'utilisateur, que seule la composition connaît. C'est la seule
     * chose que l'écran dise à son modèle, et il la dit une fois, à l'ouverture
     * et quand le réglage change — pas à chaque recomposition, où le rangement
     * se referait à chaque image d'animation.
     */
    private var columnCount = GalleryMetrics.columnCount

    suspend fun load() {
        // Des carnets publics, qui bougent à l'échelle de la semaine : les
        // rouvrir depuis le disque ne risque pas de montrer du périmé.
        if (_state.value.gallery == null) {
            cached?.invoke()?.let { stored ->
                _state.update { it.copy(gallery = stored, freshness = ContentFreshness.Restored) }
                // Rangée tout de suite. ⚠️ iOS ne range pas ce qu'il relit du
                // disque : ses colonnes restent vides le temps de l'aller-retour,
                // et l'écran dit « Les premiers carnets arrivent » au lieu de
                // montrer ce qu'il avait.
                layOut()
            }
        }

        try {
            val loaded = source()
            _state.update { state ->
                // Une catégorie qui a disparu du serveur ne doit pas laisser la
                // grille filtrée sur rien après un rechargement.
                val selected = state.selectedCategoryId?.takeIf { id -> loaded.categories.any { it.id == id } }
                state.copy(
                    freshness = contentFreshness(loaded, state.gallery),
                    gallery = loaded,
                    errorMessage = null,
                    selectedCategoryId = selected,
                )
            }
            layOut()
        } catch (error: CancellationException) {
            throw error
        } catch (error: Exception) {
            _state.update { it.copy(errorMessage = (error as? ApiError)?.errorDescription ?: error.localizedMessage ?: error.toString()) }
        }
    }

    /** Coche une catégorie, ou revient à « Tout » avec `null`. */
    fun select(categoryId: String?) {
        if (categoryId == _state.value.selectedCategoryId) return
        _state.update { it.copy(selectedCategoryId = categoryId) }
        layOut()
    }

    /** Dit au modèle sur combien de colonnes la vue peut ranger la mosaïque. */
    fun use(columnCount: Int) {
        if (columnCount == this.columnCount) return
        this.columnCount = columnCount
        layOut()
    }

    /**
     * Répartit les carnets visibles en colonnes. Le rangement se fait **une
     * fois par filtre**, pas à chaque recomposition.
     */
    private fun layOut() {
        _state.update { state ->
            val visible = state.gallery?.trips.orEmpty().filter { it.belongs(state.selectedCategoryId) }
            state.copy(columns = balanced(visible, columnCount))
        }
    }

    companion object {
        /**
         * La mosaïque : chaque carnet va dans la colonne **la plus courte**.
         *
         * On ne compare pas des hauteurs en dp mais des hauteurs *relatives* :
         * les colonnes ont la même largeur, donc une vignette de rapport 0,8 est
         * exactement 1/0,8 fois plus haute que large, quelle que soit la largeur
         * finale. Le rangement ne dépend donc pas de l'écran, et ne se refait pas
         * quand on tourne l'appareil.
         *
         * En alternant simplement gauche-droite, deux vignettes hautes de suite
         * dans la même colonne creusaient un vide de cent points en bas de
         * l'autre.
         */
        fun balanced(trips: List<GalleryTrip>, columns: Int): List<List<GalleryTrip>> {
            if (columns <= 0) return emptyList()

            val buckets = List(columns) { mutableListOf<GalleryTrip>() }
            val heights = DoubleArray(columns)

            for (trip in trips) {
                // À égalité, la colonne la plus à gauche — c'est là que se pose
                // la première vignette d'une grille.
                var shortest = 0
                for (index in heights.indices) if (heights[index] < heights[shortest]) shortest = index

                buckets[shortest].add(trip)
                heights[shortest] += 1.0 / GalleryMetrics.aspectRatio(trip.id)
            }

            return buckets
        }
    }
}
