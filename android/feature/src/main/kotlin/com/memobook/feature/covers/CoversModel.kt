package com.memobook.feature.covers

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.memobook.core.BookCover
import com.memobook.core.BookCoverEdit
import com.memobook.core.BookCovers
import com.memobook.core.CoverFace
import com.memobook.core.CoverPhoto
import com.memobook.core.CoverStyle
import com.memobook.networking.ApiError
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Job
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import java.time.Duration
import java.time.Instant

/**
 * Ce que le parcours des couvertures sait faire : lire les deux plats, et
 * enregistrer chaque geste. Jumeau de `Covers/CoversModel.swift`.
 *
 * Même construction que `BookCustomisationModel` : le modèle ne connaît pas
 * l'API, il reçoit deux fonctions. Les aperçus n'en fournissent aucune et
 * travaillent en mémoire.
 *
 * **Un modèle pour les quatre écrans**, et non un par écran : on passe du choix
 * au style puis à la photo puis aux textes sans jamais quitter les mêmes deux
 * plats, et l'onglet « 1re / 4e » suit d'un écran à l'autre. Quatre modèles
 * auraient demandé de recharger à chaque pas, et de se retransmettre l'onglet.
 * Il vit donc dans le magasin de la session (`LocalSessionViewModelStoreOwner`)
 * — voir `rememberSessionCoversModel`.
 *
 * @property tripId le voyage dont on règle les couvertures. Lisible parce que le
 *   modèle est tenu pour les quatre écrans, et qu'il faut savoir s'il parle
 *   encore du bon voyage.
 * @param upload envoie une photo importée. `null` en aperçu : la photo reste sur
 *   l'appareil.
 */
class CoversModel(
    val tripId: String,
    private val source: suspend (String) -> BookCovers = { BookCovers.fixture },
    private val persist: (suspend (String, BookCoverEdit) -> BookCovers)? = null,
    private val upload: (suspend (String, ByteArray) -> CoverPhoto)? = null,
) : ViewModel() {

    /**
     * Ce que les quatre écrans lisent.
     *
     * @property face le plat qu'on regarde. **Partagé par les quatre écrans** :
     *   passer de la quatrième de couverture au choix de sa photo ne doit pas
     *   ramener à la première.
     * @property isUploadingPhoto une photo est en route : le carrousel le montre
     *   sur sa case d'import.
     */
    data class State(
        val covers: BookCovers? = null,
        val errorMessage: String? = null,
        val face: CoverFace = CoverFace.Front,
        val isUploadingPhoto: Boolean = false,
    ) {
        val isLoading: Boolean get() = covers == null && errorMessage == null

        /** Le plat courant. */
        val cover: BookCover? get() = covers?.get(face)

        /** Les styles proposés pour le plat courant. */
        val styles: List<CoverStyle> get() = covers?.styles(face) ?: emptyList()

        fun style(of: BookCover): CoverStyle? = covers?.style(of.styleId)

        fun photo(of: BookCover): CoverPhoto? = covers?.photo(of.photoId)
    }

    private val _state = MutableStateFlow(State())
    val state: StateFlow<State> = _state.asStateFlow()

    // Ce que les écrans lisent, sous les noms d'iOS — les tests s'en servent.
    val covers: BookCovers? get() = _state.value.covers
    val cover: BookCover? get() = _state.value.cover
    val styles: List<CoverStyle> get() = _state.value.styles
    val face: CoverFace get() = _state.value.face

    private var pendingSave: Job? = null

    /**
     * Quand les adresses des photos ont été lues. Elles sont **signées pour une
     * heure** par le serveur (T237) : passé ce délai, elles ne chargent plus —
     * voir [refreshPhotoLinks].
     */
    private var photoLinksReadAt: Instant? = null

    /**
     * La dernière relecture faite pour une image qui n'a pas chargé. Une photo
     * vraiment cassée ne doit pas faire rappeler le serveur en boucle.
     */
    private var lastPhotoRefresh: Instant? = null

    /** L'horloge, pour les tests. */
    internal var now: () -> Instant = { Instant.now() }

    /** L'app envoie les photos importées : sinon, elles ne vivent que dans les caches de l'appareil. */
    val canUploadPhotos: Boolean get() = upload != null

    /** Le plat qu'on regarde — l'onglet « 1re / 4e », partagé par les quatre écrans. */
    fun setFace(face: CoverFace) {
        _state.update { it.copy(face = face) }
    }

    /**
     * Envoie une photo importée, la range à côté des autres et rend ce que le
     * serveur en a fait — son identifiant, son adresse durable (T88). Sans
     * serveur, la photo garde l'identifiant et l'adresse locale qu'on lui donne.
     */
    suspend fun importPhoto(data: ByteArray, fallback: CoverPhoto): CoverPhoto {
        val upload = upload
        if (upload == null) {
            add(fallback)
            return fallback
        }
        _state.update { it.copy(isUploadingPhoto = true) }
        try {
            val photo = upload(tripId, data)
            add(photo)
            return photo
        } finally {
            _state.update { it.copy(isUploadingPhoto = false) }
        }
    }

    /**
     * Lit les deux plats, **une fois pour le parcours entier**.
     *
     * Les quatre écrans l'appellent à l'apparition, parce qu'aucun ne peut
     * supposer qu'il vient après un autre. Mais il n'y a qu'un modèle pour les
     * quatre : relire à chaque pas remplacerait le plat qu'on est en train de
     * composer par celui du serveur — pousser le carrousel des photos depuis
     * celui des styles effaçait le style qu'on venait d'y choisir sans valider.
     */
    suspend fun load() {
        if (_state.value.covers != null) {
            // On revient sur un écran du parcours longtemps après l'avoir
            // ouvert : les photos ont des liens périmés, on les renouvelle sans
            // toucher au plat qu'on compose.
            val read = photoLinksReadAt
            if (read != null && Duration.between(read, now()) > photoLinkLifetime) {
                refreshPhotoLinks(force = true)
            }
            return
        }
        reload()
    }

    /**
     * Relit depuis la source, quoi qu'on ait déjà. C'est ce qu'appelle le
     * « Réessayer » d'un bandeau d'erreur, et ce que fait un enregistrement raté
     * pour revenir à ce que le serveur sait.
     */
    suspend fun reload() {
        try {
            val covers = source(tripId)
            photoLinksReadAt = now()
            _state.update { it.copy(covers = covers, errorMessage = null) }
        } catch (error: CancellationException) {
            throw error
        } catch (error: Exception) {
            _state.update { it.copy(errorMessage = describe(error)) }
        }
    }

    /**
     * Renouvelle les adresses des photos **et rien d'autre** (T237).
     *
     * Les photos de la conversation passent par un lien signé d'une heure : un
     * écran resté ouvert plus longtemps montrait des images cassées. Une image
     * qui ne charge pas appelle ceci (voir `CoverPhotoImage`) ; le serveur rend
     * des liens neufs, qu'on pose sur les photos du même identifiant. Le style,
     * la photo et les textes en cours de choix restent ceux qu'on regarde —
     * relire tout le plat les aurait remplacés par ceux du serveur.
     */
    suspend fun refreshPhotoLinks(force: Boolean = false) {
        if (_state.value.covers == null) return
        val last = lastPhotoRefresh
        if (!force && last != null && Duration.between(last, now()) < photoRefreshCooldown) return
        lastPhotoRefresh = now()

        val fresh = try {
            source(tripId)
        } catch (error: CancellationException) {
            throw error
        } catch (_: Exception) {
            return
        }
        val current = _state.value.covers ?: return
        // Le premier l'emporte, comme `uniquingKeysWith: { first, _ in first }` :
        // `associateBy` garde le dernier, d'où la liste retournée.
        val freshById = fresh.photos.asReversed().associateBy { it.id }
        val known = current.photos.map { it.id }.toSet()
        // Une photo importée sur l'appareil et pas encore connue du serveur
        // garde son adresse locale.
        val photos = current.photos.map { freshById[it.id] ?: it } + fresh.photos.filter { it.id !in known }
        _state.update { state -> state.covers?.let { state.copy(covers = it.copy(photos = photos)) } ?: state }
        photoLinksReadAt = now()
    }

    // MARK: - Ce qu'on regarde

    fun style(of: BookCover): CoverStyle? = _state.value.style(of)

    fun photo(of: BookCover): CoverPhoto? = _state.value.photo(of)

    // MARK: - Ce qu'on change

    /**
     * Le style se pose **sans partir** : on le regarde d'abord, on valide
     * ensuite. C'est le bouton « Valider » de la maquette qui envoie, et c'est la
     * seule différence avec les lignes de réglage de l'app — ici le choix est
     * visuel, et on veut pouvoir faire défiler sept plats sans écrire sept fois
     * au serveur.
     */
    fun preview(style: CoverStyle) {
        _state.update { state ->
            val covers = state.covers ?: return@update state
            state.copy(covers = covers.with(state.face, covers[state.face].copy(styleId = style.id)))
        }
    }

    fun preview(photo: CoverPhoto?) {
        _state.update { state ->
            val covers = state.covers ?: return@update state
            state.copy(covers = covers.with(state.face, covers[state.face].copy(photoId = photo?.id)))
        }
    }

    /**
     * Range une photo importée à côté de celles du voyage.
     *
     * **Juste avant la case d'import**, et non en fin de liste : la case est
     * toujours la dernière du carrousel, et une photo posée après elle serait
     * hors de portée du geste qui vient de l'ajouter.
     *
     * Elle part au serveur par [importPhoto] (T88, 29/09/2026) ; ici on ne fait
     * que la ranger.
     */
    fun add(photo: CoverPhoto) {
        _state.update { state ->
            val covers = state.covers ?: return@update state
            if (covers.photos.any { it.id == photo.id }) return@update state
            state.copy(covers = covers.copy(photos = covers.photos + photo))
        }
    }

    fun commitStyle() {
        val state = _state.value
        val cover = state.cover ?: return
        save(BookCoverEdit.Style(state.face, cover.styleId))
    }

    fun commitPhoto() {
        val state = _state.value
        val cover = state.cover ?: return
        save(BookCoverEdit.Photo(state.face, cover.photoId))
    }

    fun setTexts(title: String, subtitle: String) {
        val state = _state.value
        val covers = state.covers ?: return
        _state.update { it.copy(covers = covers.with(state.face, covers[state.face].copy(title = title, subtitle = subtitle))) }
        save(BookCoverEdit.Texts(state.face, title = title, subtitle = subtitle))
    }

    /**
     * Les chiffres du dos. La feuille garde la main sur les bornes — voir
     * `BookCovers.statRange` — et n'appelle ceci qu'à « Valider ».
     */
    fun setStats(ids: List<String>) {
        val covers = _state.value.covers ?: return
        _state.update { it.copy(covers = covers.copy(back = covers.back.copy(statIds = ids))) }
        save(BookCoverEdit.Stats(ids))
    }

    private fun save(edit: BookCoverEdit) {
        val persist = persist ?: return

        pendingSave?.cancel()
        pendingSave = viewModelScope.launch {
            try {
                val updated = persist(tripId, edit)
                if (!currentCoroutineContext().isActive) return@launch
                _state.update { it.copy(covers = updated, errorMessage = null) }
            } catch (error: CancellationException) {
                throw error
            } catch (error: Exception) {
                _state.update { it.copy(errorMessage = describe(error)) }
                reload()
            }
        }
    }

    companion object {
        /** Un lien signé vaut une heure ; on le renouvelle un peu avant. */
        val photoLinkLifetime: Duration = Duration.ofMinutes(45)
        val photoRefreshCooldown: Duration = Duration.ofSeconds(30)

        /** La phrase d'une erreur — le `localizedDescription` d'iOS. */
        private fun describe(error: Throwable): String =
            (error as? ApiError)?.errorDescription ?: error.localizedMessage ?: error.toString()
    }
}
