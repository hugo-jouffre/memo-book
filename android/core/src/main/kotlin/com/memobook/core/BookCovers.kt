package com.memobook.core

import kotlinx.serialization.KSerializer
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.descriptors.SerialDescriptor
import kotlinx.serialization.encoding.Decoder
import kotlinx.serialization.encoding.Encoder
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonPrimitive

// Les deux plats du carnet : la première et la quatrième de couverture. Le
// jumeau de `MemoBookCore/BookCovers.swift`.
//
// **C'est la seule chose qu'on voit du Carnet avant de l'ouvrir**, et la seule
// qu'un autre verra sur une étagère. D'où un parcours à part plutôt qu'une ligne
// de réglage de plus : on choisit un style, une photo, puis on écrit les textes
// — trois gestes, dans cet ordre, sur les deux plats.
//
// ⚠️ **L'app dessine les plats, elle ne les importe pas.** La maquette pose des
// rendus de couvertures finies ; on en garde la composition — le cadrage, la
// place du titre, le rapport A5 — avec les moyens de l'app. Un rendu importé
// serait une image figée qui mentirait dès que le voyageur change sa photo ou
// son titre, alors que ces plats-là montrent **les siens**. Même parti pris que
// `CoverStack` sur l'écran des personnalisations (T83).

/** Lequel des deux plats. */
@Serializable
enum class CoverFace(val rawValue: String) {
    /** Le devant : photo, titre, année. */
    @SerialName("front") Front("front"),

    /** Le dos : le texte de quatrième, la carte du trajet et les chiffres du voyage. */
    @SerialName("back") Back("back");

    val id: String get() = rawValue

    /** Le plat d'en face. */
    val opposite: CoverFace get() = if (this == Front) Back else Front

    /**
     * « 1ère de couverture » et « 4e de couverture », les deux onglets.
     *
     * « 1ère » et non « 1re » : c'est l'abréviation que la maquette emploie
     * partout, et l'app la suit (Hugo, 17/09/2026, T91).
     */
    val title: String
        get() = when (this) {
            Front -> "1ère de couverture"
            Back -> "4e de couverture"
        }
}

/**
 * Comment un plat se dessine.
 *
 * Quatre familles, et non les sept styles de la maquette : ce sont les quatre
 * **compositions** que l'app sait rendre honnêtement avec la photo et les
 * textes du voyageur. Le jour où le gabarit rendra les couvertures pour de
 * vrai, c'est cette énumération qui disparaîtra, pas l'écran.
 */
@Serializable
enum class CoverTreatment(val rawValue: String) {
    /** La photo occupe tout le plat, le titre se pose dessus. */
    @SerialName("photo") Photo("photo"),

    /**
     * La photo est encadrée haut, sur un fond papier ; le texte respire
     * dessous. C'est la composition des quatrièmes de couverture.
     */
    @SerialName("framed") Framed("framed"),

    /** Pas de photo : un aplat, et le titre seul. */
    @SerialName("plain") Plain("plain"),

    /** Le papier kraft et l'écriture à la main. */
    @SerialName("kraft") Kraft("kraft");

    /**
     * Cette composition **porte-t-elle une photo** ?
     *
     * Deux des quatre n'en portent pas : un aplat et un kraft sont des fonds,
     * pas des cadres. Choisir une photo dessus ne changerait rien au plat —
     * et c'est exactement ce que faisait le carrousel des photos avant qu'on
     * le dise (Hugo, 16/09/2026).
     */
    val carriesPhoto: Boolean
        get() = when (this) {
            Photo, Framed -> true
            Plain, Kraft -> false
        }

    /**
     * Cette composition **porte-t-elle un texte**, sur ce plat-là ?
     *
     * La question ne se pose qu'au dos. Un devant a toujours son titre, quelle
     * que soit la composition — posé sur la photo, sur l'aplat ou à la main.
     * Au dos, en revanche, la photo pleine page **occupe tout le plat** : il
     * n'y a pas de place pour le texte de quatrième, et l'écran des textes n'a
     * donc rien à y écrire.
     */
    fun carriesText(on: CoverFace): Boolean = when (on) {
        CoverFace.Front -> true
        CoverFace.Back -> this != Photo
    }
}

/**
 * L'aplat d'un style. Un nom et non une couleur : `:core` ne connaît pas
 * Compose, et c'est au design system de dire à quoi ressemble « forêt ».
 */
@Serializable
enum class CoverTint(val rawValue: String) {
    @SerialName("paper") Paper("paper"),
    @SerialName("sand") Sand("sand"),
    @SerialName("forest") Forest("forest"),
    @SerialName("slate") Slate("slate"),
    @SerialName("ink") Ink("ink"),
}

/**
 * **Les sept gabarits de couverture** de `assets/covers` (Hugo, 08/10/2026 :
 * « intégrer les visuels de cover en associant correctement la front cover et
 * la back cover »).
 *
 * Chaque famille a **sa** 1ère et **sa** 4e de couverture : les fichiers de
 * Hugo vont par paires, nommés pareil à la fin — « front cover_style dessin »
 * et « back cover_style dessin ». C'est la famille qui fait la paire, et donc
 * la pastille « Assortie à ta 1ère de couverture » ([CoverStyle.matches]).
 *
 * L'app **redessine** chaque gabarit avec la photo et les mots du voyageur
 * (`CoverTemplates.swift`) : ni le titre « PHILIPPINES » ni la photo de la
 * maquette n'y restent. Une famille inconnue — un serveur plus récent — se
 * décode en `null`, et le plat retombe sur sa composition ([CoverTreatment]).
 */
@Serializable
enum class CoverFamily(val rawValue: String) {
    /**
     * La photo pleine page, le titre en capitales à empattements dessus ; au
     * dos, le trajet et les chiffres.
     */
    @SerialName("default") Default("default"),

    /**
     * Un bandeau crème et son titre noir, la photo comme une aquarelle ; au
     * dos, le récit en trois temps, chacun avec son image.
     */
    @SerialName("watercolor") Watercolor("watercolor"),

    /**
     * Le bleu de la marque, le titre vert, une palme ; au dos, le récit et
     * les chiffres sur le même bleu.
     */
    @SerialName("assouline") Assouline("assouline"),

    /** Le papier crème, l'écriture à la main et des dessins au trait. */
    @SerialName("drawing") Drawing("drawing"),

    /**
     * La photo pleine page, des courbes de niveau tracées à la main par-dessus
     * et le titre manuscrit ; au dos, un aplat d'eau claire et un mot.
     */
    @SerialName("photo-drawing") PhotoDrawing("photo-drawing"),

    /**
     * Le carnet de bord : des timbres, un tampon, le vert de la marque ; au
     * dos, une photo dans un cadre déchiré.
     */
    @SerialName("travel-book") TravelBook("travel-book"),

    /**
     * Le titre fin à empattements, la photo comme un tirage ; au dos, un
     * paysage en bandeau et quelques lignes.
     */
    @SerialName("elegant") Elegant("elegant");

    /**
     * Ce plat de cette famille **porte-t-il une photo** — celle qu'on choisit
     * dans le carrousel des photos ?
     */
    fun carriesPhoto(on: CoverFace): Boolean = when (this) {
        Default -> on == CoverFace.Front
        Watercolor, TravelBook, Elegant -> true
        PhotoDrawing -> on == CoverFace.Front
        Assouline, Drawing -> false
    }

    /**
     * Ce plat porte-t-il **un texte qu'on écrit** — le titre et la signature
     * devant, le texte de quatrième au dos ?
     */
    fun carriesText(on: CoverFace): Boolean = when (on) {
        CoverFace.Front -> true
        CoverFace.Back -> when (this) {
            Default, TravelBook -> false
            Watercolor, Assouline, Drawing, PhotoDrawing, Elegant -> true
        }
    }

    /**
     * Ce plat imprime-t-il **les chiffres du voyage** ? Au dos seulement, et
     * pas sur tous : deux maquettes les posent.
     */
    fun carriesStats(on: CoverFace): Boolean =
        on == CoverFace.Back && (this == Default || this == Assouline)

    companion object {
        fun from(raw: String): CoverFamily? = entries.firstOrNull { it.rawValue == raw }
    }
}

/**
 * Une famille inconnue ne fait pas tomber le catalogue : le `try?` de Swift.
 * Tout ce qui n'est pas une famille connue — un nom ajouté demain, un type
 * inattendu — se lit `null`.
 */
internal object LenientCoverFamilySerializer : KSerializer<CoverFamily?> {
    override val descriptor: SerialDescriptor = JsonElement.serializer().descriptor

    override fun deserialize(decoder: Decoder): CoverFamily? {
        val element = decoder.decodeSerializableValue(JsonElement.serializer())
        val primitive = element as? JsonPrimitive ?: return null
        return if (primitive.isString) CoverFamily.from(primitive.content) else null
    }

    override fun serialize(encoder: Encoder, value: CoverFamily?) {
        encoder.encodeSerializableValue(
            JsonElement.serializer(),
            value?.let { JsonPrimitive(it.rawValue) } ?: kotlinx.serialization.json.JsonNull,
        )
    }
}

/**
 * Un style graphique de couverture.
 *
 * @property name Le nom du style, pour TalkBack. Il n'est écrit nulle part sur
 *   l'écran : la maquette ne montre que les vignettes, et on choisit une
 *   couverture en la regardant, pas en lisant son nom.
 * @property family Le gabarit — voir [CoverFamily]. `null` pour un style d'avant
 *   le 08/10/2026, ou d'une famille que cette app ne connaît pas encore : le plat
 *   se dessine alors d'après [treatment] et [tint], que le serveur sert toujours
 *   pour les apps installées.
 */
@Serializable
data class CoverStyle(
    val id: String,
    val name: String,
    val treatment: CoverTreatment,
    val tint: CoverTint,
    // Une famille inconnue ne fait pas tomber le catalogue : le plat
    // retombe sur sa composition.
    @Serializable(with = LenientCoverFamilySerializer::class)
    val family: CoverFamily? = null,
) {
    /**
     * Ce style **s'accorde** à un autre. C'est ce que la pastille « Assortie
     * à ta 1ère de couverture » veut dire, et elle se calcule sur le plat
     * d'en face **tel qu'il est choisi** — un drapeau figé dans le catalogue
     * ne suivait pas le devant quand on le changeait (Clara, 17/09/2026).
     *
     * **La même famille** depuis le 08/10/2026 : la 4e « dessin » va avec la
     * 1ère « dessin », comme les fichiers de Hugo. Sans famille des deux
     * côtés, même composition et même aplat, comme avant.
     */
    fun matches(other: CoverStyle): Boolean {
        if (family != null && other.family != null) return family == other.family
        return treatment == other.treatment && tint == other.tint
    }

    /** Porte les jeux d'essai de `:feature` (`CoverStyle.fixture`…), qui s'y écrivent en extensions. */
    companion object
}

/** Une photo candidate à la couverture. L'adresse reste du texte, comme dans le JSON. */
@Serializable
data class CoverPhoto(val id: String, val url: String? = null)

/**
 * Un chiffre du voyage, tel qu'il s'imprimera au dos.
 *
 * @property value « 13 », « 22k », « 3 ». Une chaîne et non un nombre : c'est le
 *   serveur qui décide d'abréger 22 000 en 22k, et lui seul sait à partir de quand.
 * @property label « jours de voyage ». S'imprime sur deux lignes dans le carnet,
 *   donc le texte porte son retour à la ligne.
 */
@Serializable
data class CoverStat(val id: String, val value: String, val label: String)

/**
 * Ce qu'on a choisi pour un plat.
 *
 * @property photoId La photo retenue. `null` sur un style qui n'en porte pas, et
 *   sur un plat qu'on n'a pas encore réglé.
 * @property title Le grand titre — le nom du pays sur la maquette.
 * @property subtitle La ligne sous le titre : les prénoms et la date sur la
 *   première, le texte de quatrième sur l'autre.
 * @property statIds Les chiffres choisis pour le dos. Vide sur la première de
 *   couverture.
 */
@Serializable
data class BookCover(
    val styleId: String,
    val photoId: String? = null,
    val title: String = "",
    val subtitle: String = "",
    val statIds: List<String> = emptyList(),
)

/**
 * Les deux plats et tout ce qui sert à les composer.
 *
 * @property frontStyles Les styles proposés, par plat : le catalogue de la
 *   première n'est pas celui de la quatrième.
 * @property photos Les photos du voyage, dans l'ordre où le carrousel les propose.
 * @property stats Tous les chiffres que le voyage sait produire. Le voyageur en
 *   retient trois ou quatre — voir [statSelection].
 */
@Serializable
data class BookCovers(
    val front: BookCover,
    val back: BookCover,
    val frontStyles: List<CoverStyle>,
    val backStyles: List<CoverStyle>,
    val photos: List<CoverPhoto>,
    val stats: List<CoverStat>,
) {
    /** Le plat demandé — le `subscript(face:)` de Swift, en lecture. */
    operator fun get(face: CoverFace): BookCover = when (face) {
        CoverFace.Front -> front
        CoverFace.Back -> back
    }

    /** Les deux plats, `face` remplacé — le `subscript(face:)` de Swift, en écriture. */
    fun with(face: CoverFace, cover: BookCover): BookCovers = when (face) {
        CoverFace.Front -> copy(front = cover)
        CoverFace.Back -> copy(back = cover)
    }

    fun styles(face: CoverFace): List<CoverStyle> = when (face) {
        CoverFace.Front -> frontStyles
        CoverFace.Back -> backStyles
    }

    fun style(id: String): CoverStyle? = (frontStyles + backStyles).firstOrNull { it.id == id }

    fun photo(id: String?): CoverPhoto? {
        if (id == null) return null
        return photos.firstOrNull { it.id == id }
    }

    // Ce qu'un plat accepte, vu du style qu'il porte

    /**
     * La composition que ce plat porte en ce moment. `null` si le style n'est
     * pas dans le catalogue — un plat servi par un serveur plus récent.
     */
    fun treatment(of: CoverFace): CoverTreatment? = style(this[of].styleId)?.treatment

    /** Le gabarit que ce plat porte en ce moment, s'il en a un. */
    fun family(of: CoverFace): CoverFamily? = style(this[of].styleId)?.family

    /**
     * Ce plat accepte-t-il une photo ? **Oui par défaut** quand le style est
     * inconnu : on n'interdit pas un geste parce qu'on n'a pas su lire.
     */
    fun acceptsPhoto(on: CoverFace): Boolean {
        family(on)?.let { return it.carriesPhoto(on) }
        return treatment(on)?.carriesPhoto ?: true
    }

    /** Ce plat accepte-t-il un texte ? Même règle de prudence. */
    fun acceptsText(on: CoverFace): Boolean {
        family(on)?.let { return it.carriesText(on) }
        return treatment(on)?.carriesText(on) ?: true
    }

    /**
     * Ce plat imprime-t-il les chiffres du voyage ? Le dos seulement ; tous
     * les dos d'avant les gabarits les portaient.
     */
    fun acceptsStats(on: CoverFace): Boolean {
        if (on != CoverFace.Back) return false
        return family(on)?.carriesStats(on) ?: true
    }

    /** Les chiffres retenus pour le dos, dans l'ordre du catalogue. */
    val statSelection: List<CoverStat>
        get() = back.statIds.mapNotNull { id -> stats.firstOrNull { it.id == id } }

    /**
     * Ce style, proposé pour `on`, reprend-il le style **choisi** sur
     * l'autre plat ? C'est lui que le carrousel coiffe de la pastille
     * « Assortie à ta 1ère de couverture ».
     *
     * **Au dos seulement** (Hugo, 12/10/2026) : la pastille dit quelle 4e va
     * avec la 1ère qu'on a choisie. Sur les styles de la 1ère, elle n'a rien
     * à dire — c'est elle qu'on choisit d'abord, et « assortie à ta 1ère »
     * s'y lisait comme une contradiction.
     */
    fun isMatched(style: CoverStyle, on: CoverFace): Boolean {
        if (on != CoverFace.Back) return false
        val chosen = style(front.styleId) ?: return false
        return style.matches(chosen)
    }

    companion object {
        /**
         * Combien de chiffres le dos accepte. « Choisis-en 3 ou 4 », dit la
         * feuille, et la contrainte vient du gabarit : sous trois, le bandeau a des
         * colonnes vides ; au-delà de quatre, les chiffres ne sont plus lisibles à
         * la taille imprimée.
         */
        val statRange: IntRange = 3..4
    }
}

/**
 * Ce qu'un plat modifié envoie au serveur.
 *
 * Un geste à la fois, comme [BookCustomisationEdit] : l'écran ne renvoie que
 * ce qu'on vient de valider.
 */
sealed interface BookCoverEdit {
    data class Style(val face: CoverFace, val styleId: String) : BookCoverEdit
    data class Photo(val face: CoverFace, val photoId: String?) : BookCoverEdit
    data class Texts(val face: CoverFace, val title: String, val subtitle: String) : BookCoverEdit
    data class Stats(val statIds: List<String>) : BookCoverEdit
}
