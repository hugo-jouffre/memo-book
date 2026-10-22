package com.memobook.core

import kotlinx.serialization.KSerializer
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.descriptors.SerialDescriptor
import kotlinx.serialization.encoding.Decoder
import kotlinx.serialization.encoding.Encoder
import java.time.Instant

// L'aperçu du carnet : le PDF que la conversation a produit, page par page. Le
// jumeau de `MemoBookCore/BookPreview.swift`.
//
// **L'app ne redessine pas le carnet.** Les pages viennent du PDF composé par
// le back-end (OpenAI structure le récit, APITemplate le met en page) et
// s'affichent telles quelles. C'est la seule façon d'être sûr que l'aperçu
// montre ce qui sortira de l'imprimante — et c'est aussi la plus rapide : une
// page de PDF se rend en quelques millisecondes, là où rejouer la mise en page
// en Compose demanderait de réimplémenter le template et de le maintenir en
// double.
//
// Voir `docs/apitemplate.md` pour la composition, et `MemoBook Generator/templates/travel-journal/`
// pour le template lui-même.

/**
 * Où en est la composition du carnet.
 *
 * Elle voyage en **objet** (`{"status": "ready"}`, `{"status": "failed",
 * "message": …}`), comme le `Codable` écrit à la main de Swift.
 */
@Serializable(with = BookPreviewStatus.Serializer::class)
sealed interface BookPreviewStatus {
    /**
     * Le back-end compose. C'est l'écran « On compose ton Carnet » qui occupe
     * l'attente, et il n'attend pas passivement : il montre une page en train
     * de se monter.
     */
    data object Composing : BookPreviewStatus

    /** Le PDF est là, on peut le feuilleter. */
    data object Ready : BookPreviewStatus

    /**
     * La composition a échoué. Le message vient du serveur : lui seul sait si
     * c'est un souvenir illisible ou une panne de son côté.
     */
    data class Failed(val message: String) : BookPreviewStatus

    val isReady: Boolean get() = this == Ready

    @Serializable
    @SerialName("BookPreviewStatus")
    private class Surrogate(val status: String, val message: String? = null)

    object Serializer : KSerializer<BookPreviewStatus> {
        override val descriptor: SerialDescriptor = Surrogate.serializer().descriptor

        override fun deserialize(decoder: Decoder): BookPreviewStatus {
            val raw = decoder.decodeSerializableValue(Surrogate.serializer())
            return when (raw.status) {
                "ready" -> Ready
                "failed" -> Failed(raw.message ?: "La composition n’a pas abouti.")
                // Tout le reste — « queued », « running », un état ajouté demain —
                // est une attente. C'est le repli sûr : montrer la composition en
                // cours coûte quelques secondes, annoncer un échec à tort fait
                // fermer l'écran.
                else -> Composing
            }
        }

        override fun serialize(encoder: Encoder, value: BookPreviewStatus) {
            val surrogate = when (value) {
                Composing -> Surrogate("composing")
                Ready -> Surrogate("ready")
                is Failed -> Surrogate("failed", value.message)
            }
            encoder.encodeSerializableValue(Surrogate.serializer(), surrogate)
        }
    }
}

/**
 * Où en est **une** composition, telle que le serveur la mène
 * (`render.phase`, 06/10/2026).
 *
 * Plus fin que [BookPreviewStatus], qui ne dit que « ça compose » : une
 * composition attend son tour, met les souvenirs en pages — en attendant ceux
 * qui sont encore en rédaction —, puis fabrique le PDF. C'est ce que l'écran
 * de composition dit sous sa page, pour qu'une attente de plusieurs minutes
 * ne se lise pas comme un écran figé.
 */
@Serializable(with = BookRenderPhase.Serializer::class)
sealed interface BookRenderPhase {
    val rawValue: String

    /** En file, pas encore commencée. */
    data object Queued : BookRenderPhase { override val rawValue = "queued" }

    /**
     * Les textes se mettent en page — et la composition attend, jusqu'à trois
     * minutes, les souvenirs encore en rédaction.
     */
    data object Writing : BookRenderPhase { override val rawValue = "writing" }

    /** Le PDF se fabrique chez APITemplate. */
    data object Composing : BookRenderPhase { override val rawValue = "composing" }
    data object Ready : BookRenderPhase { override val rawValue = "ready" }
    data object Failed : BookRenderPhase { override val rawValue = "failed" }

    /**
     * Une phase ajoutée côté serveur après cette version : une attente, comme
     * tout ce qui n'est ni prêt ni en échec.
     */
    data class Unknown(override val rawValue: String) : BookRenderPhase

    companion object {
        fun from(raw: String): BookRenderPhase = when (raw) {
            "queued" -> Queued
            "writing" -> Writing
            "composing" -> Composing
            "ready" -> Ready
            "failed" -> Failed
            else -> Unknown(raw)
        }
    }

    object Serializer : RawValueSerializer<BookRenderPhase>(
        "com.memobook.core.BookRenderPhase", { it.rawValue }, ::from,
    )
}

/**
 * La **dernière** composition du carnet, quel que soit son état — le champ
 * `render` de `GET /v1/memos/:id/preview`.
 *
 * Elle distingue ce que [BookPreviewStatus] confond : « une composition
 * tourne » et « rien n'a jamais été lancé ». Le serveur répond `composing`
 * dans les deux cas ; seul ce champ, `null` dans le second, permet à l'écran de
 * ne pas attendre une composition qui ne viendra pas.
 *
 * @property phase `null` sur un serveur qui ne la sert pas encore : on lit alors
 *   une attente, comme pour une phase inconnue.
 */
@Serializable
data class BookRenderProgress(
    val id: String,
    val phase: BookRenderPhase? = null,
    val error: String? = null,
)

/**
 * Les deux lignes que porte la carte de partage : ce que le carnet raconte, en
 * deux phrases prises dedans.
 *
 * C'est du **contenu** : les phrases sortent du récit rédigé, pas d'un libellé
 * d'interface. Elles servent aussi de métadonnées Open Graph au lien de
 * prévisualisation, ce qui est la raison pour laquelle elles vivent dans le
 * modèle et non dans la vue.
 *
 * @property quote La phrase mise en avant, entre guillemets dans la carte.
 * @property detail Ce qui la prolonge, en une phrase.
 */
@Serializable
data class BookExcerpt(val quote: String, val detail: String? = null)

/**
 * Tout ce que l'aperçu du carnet a besoin de savoir.
 *
 * Les adresses restent du **texte**, comme dans le JSON : l'app ne fait que les
 * repasser au téléchargement ou au partage.
 *
 * @property memoId L'identifiant du carnet côté serveur. C'est lui qu'on repasse
 *   pour relancer une composition ou commander l'impression.
 * @property title Le titre du carnet — « Rome et la Dolce Vita ». Celui du
 *   **carnet**, qui peut différer du nom du voyage : le récit se donne un titre.
 * @property pdfUrl Le PDF composé. `null` tant que [status] n'est pas `Ready`.
 *   C'est un lien signé et de courte durée : il ne se met pas en cache sur le
 *   disque, seul le document déjà chargé reste en mémoire.
 * @property pageCount Combien de pages le carnet fait. Il vient du serveur et non
 *   du PDF : l'en-tête l'affiche (« 10 pages composées ») avant que le document
 *   soit téléchargé. Une fois le PDF là, c'est **lui** qui fait foi.
 * @property shareUrl Le lien de prévisualisation en ligne, à partager. `null` tant
 *   qu'il n'a pas été demandé — c'est un lien public, il ne se crée pas tout seul.
 *   **Seul le serveur le fabrique** (`POST /v1/memos/:id/share-link`) : une page
 *   publique `/c/<jeton>` servie par l'API, avec sa vignette Open Graph pour
 *   WhatsApp et iMessage. L'app ne compose jamais d'URL — celle qu'elle
 *   fabriquait, `memo-book.com/c/<identifiant>`, ne menait nulle part (06/10/2026).
 * @property coverPhotoUrl La couverture, pour la carte de partage.
 * @property tripDate La date du voyage, telle que la carte de partage l'affiche.
 *   `null` quand le voyage n'en a pas — la pastille disparaît alors plutôt que
 *   d'inventer aujourd'hui.
 * @property hasConfiguredCovers La première et la quatrième de couverture
 *   ont-elles été choisies. Faux, la page de couverture s'affiche voilée avec son
 *   invitation à la régler — c'est ce que dessine « Prévisualisation PDF - 2 ». Ce
 *   n'est pas un état d'erreur : un carnet est feuilletable sans couverture
 *   choisie, elle se met juste par défaut.
 * @property render La dernière composition — voir [BookRenderProgress]. `null`
 *   quand le carnet n'a jamais été composé, **et** sur un serveur d'avant le
 *   06/10/2026 qui ne la sert pas.
 * @property readyRenderId Le rendu derrière [pdfUrl] : celui qu'on commande.
 *   `null` tant qu'aucune composition n'a abouti.
 * @property isUpToDate [pdfUrl] montre-t-il le contenu actuel ? Faux quand il n'y
 *   a pas de PDF, ou que le récit a changé depuis — une composition va repartir.
 *   `null` sur un serveur qui ne le dit pas.
 * @property pendingMemoryCount Combien de souvenirs sont encore en rédaction : la
 *   composition les attend avant de mettre en page. `null` sur un serveur qui ne
 *   le dit pas.
 */
@Serializable
data class BookPreview(
    val memoId: String,
    val title: String,
    val status: BookPreviewStatus = BookPreviewStatus.Composing,
    val pdfUrl: String? = null,
    val pageCount: Int = 0,
    val shareUrl: String? = null,
    val coverPhotoUrl: String? = null,
    @Serializable(with = InstantSerializer::class)
    val tripDate: Instant? = null,
    val excerpt: BookExcerpt? = null,
    val hasConfiguredCovers: Boolean = false,
    val render: BookRenderProgress? = null,
    val readyRenderId: String? = null,
    val isUpToDate: Boolean? = null,
    val pendingMemoryCount: Int? = null,
) {
    /**
     * Les pages qui se **configurent** : la première et la dernière.
     *
     * Une seule quand le carnet n'a qu'une page, et aucune quand il n'en a
     * pas : sans ce garde-fou, un carnet vide aurait proposé de configurer une
     * page inexistante.
     */
    fun isConfigurableCover(page: Int, total: Int): Boolean {
        if (hasConfiguredCovers || total <= 0) return false
        return page == 0 || page == total - 1
    }

    /**
     * Le PDF est ouvert et feuilletable.
     *
     * Distinct de [status] : le serveur peut avoir fini de composer alors que
     * le fichier n'est pas encore descendu. C'est cette question-là que
     * l'écran doit poser avant de poser quoi que ce soit **sur** une page —
     * une invitation à choisir sa couverture posée sur un aplat vide promet
     * une page qui n'existe pas encore.
     */
    val hasDocument: Boolean get() = status.isReady && pdfUrl != null

    /**
     * Une composition a déjà abouti : il y a un carnet à feuilleter et à
     * commander, **même si une autre tourne** pour le remettre à jour.
     *
     * Le PDF est celui du dernier rendu **prêt** (`pdfUrl` ne s'efface pas
     * pendant une recomposition), d'où le fait qu'il suffise. Le statut prêt
     * seul compte aussi : c'est le cas du jeu d'essai, qui n'a pas de PDF.
     */
    val hasReadyRender: Boolean
        get() = readyRenderId != null || pdfUrl != null || status.isReady

    companion object {
        /**
         * Le lien des jeux d'essai — bac à sable, aperçus —, à la forme de
         * celui du serveur (`<hôte de l'API>/c/<jeton>`) mais sur un domaine
         * réservé aux exemples : il ne mène nulle part, et ne fait pas croire le
         * contraire. Un vrai jeton ne vient que de `POST /v1/memos/:id/share-link`.
         */
        fun sampleShareLink(memoId: String): String = "https://api.memobook.example/c/essai-$memoId"
    }
}
