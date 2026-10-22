package com.memobook.core

import kotlinx.serialization.KSerializer
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.descriptors.SerialDescriptor
import kotlinx.serialization.encoding.Decoder
import kotlinx.serialization.encoding.Encoder
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.decodeFromJsonElement
import kotlinx.serialization.json.encodeToJsonElement
import java.math.BigDecimal
import java.math.RoundingMode
import java.time.Instant
import java.time.ZoneId
import java.time.temporal.ChronoUnit
import kotlin.reflect.KProperty1

// Les personnalisations du carnet : ce qui décide de sa mise en page. Le jumeau
// de `MemoBookCore/BookCustomisation.swift`.
//
// Elles vivent **sur le carnet** et non dans une table à part — il y en a
// exactement un jeu par voyage, elles se lisent toujours avec lui, et aucune
// requête ne les interroge seules. C'est déjà le parti pris de la base
// (`memos`, migration M4) ; cette structure n'en est que la lecture.
//
// ⚠️ **Règle de survie** (`docs/reglages-utilisateur.md`) : aucun réglage n'est
// exposé dans l'app avant d'exister dans `MemoBook Generator/templates/travel-journal/LAYOUT_KB.md`.
// Une option que le gabarit ignore ferait croire au voyageur qu'il a réglé
// quelque chose.

/**
 * Les personnalisations d'un carnet, d'un seul tenant.
 *
 * Les `var` de Swift sont ici des `val` : on change un réglage par `copy(…)`.
 *
 * @property photoTextRatio Part de photo dans la page, en pourcentage. 50 =
 *   l'équilibre de la maquette. Pilote le choix des gabarits et la fréquence des
 *   pages photo.
 * @property targetPageCount Nombre de pages visé. Pilote le niveau de détail de
 *   la rédaction et le regroupement des étapes.
 * @property rulesEnabled Les pointillés d'écriture, sur lesquels le récit se pose.
 * @property decorationQuota Combien de stickers par étape du carnet, de 0 à 4.
 *   Zéro laisse la page nue : ni sticker ni tracé pointillé.
 * @property fontTitle Les quatre familles du carnet (`fontTitle`, `fontDisplay`,
 *   `fontHand`, `fontFacts`). Ce sont des **noms de police**, pas des
 *   identifiants : c'est le gabarit qui les résout, et l'app ne fait que les
 *   afficher.
 * @property hasConfiguredCovers La première et la quatrième de couverture
 *   ont-elles été choisies. La ligne du haut mène à leur aperçu quoi qu'il
 *   arrive : elle dit « Aperçu et personnalisation », pas « À configurer ».
 */
@Serializable
data class BookCustomisation(
    // Mise en page
    val photoTextRatio: Int = 50,
    val targetPageCount: Int = 60,
    // Décors
    val funFactsEnabled: Boolean = true,
    val rulesEnabled: Boolean = true,
    val decorationQuota: Int = 2,
    // Typographies
    val fontTitle: String = "Hansley",
    val fontDisplay: String = "Playfair Display",
    val fontHand: String = "Gloria Hallelujah",
    val fontFacts: String = "Playfair Display",
    // Extras
    val quizEnabled: Boolean = true,
    val freeZonesEnabled: Boolean = true,
    val crosswordEnabled: Boolean = true,
    // Couvertures
    val hasConfiguredCovers: Boolean = false,
) {
    /** « 50/50 » — la part de photo face à celle du texte. */
    val photoTextLabel: String get() = "$photoTextRatio/${100 - photoTextRatio}"

    /** « 60 pages ». Accordé : un carnet d'une page arrive au premier souvenir. */
    val targetPageLabel: String
        get() = if (targetPageCount <= 1) "$targetPageCount page" else "$targetPageCount pages"

    /** « 2 / étape », ou « Aucune » quand le quota est nul. */
    val decorationLabel: String
        get() = if (decorationQuota == 0) "Aucune" else "$decorationQuota / étape"
}

/**
 * Ce qu'une personnalisation modifiée envoie au serveur.
 *
 * Un réglage à la fois, comme `TripSettingsEdit` et pour la même raison :
 * l'écran ne renvoie que ce qu'on a touché, ce qui évite d'écraser ce qu'un
 * co-voyageur aurait changé entre-temps. Seul [FontCombo] porte plusieurs
 * colonnes — les quatre polices et les pointillés.
 */
sealed interface BookCustomisationEdit {
    data class PhotoTextRatio(val value: Int) : BookCustomisationEdit
    data class TargetPageCount(val value: Int) : BookCustomisationEdit
    data class FunFacts(val value: Boolean) : BookCustomisationEdit
    data class Rules(val value: Boolean) : BookCustomisationEdit
    data class DecorationQuota(val value: Int) : BookCustomisationEdit

    /**
     * La typographie des **titres** du carnet, qui vit dans `fontDisplay` :
     * c'est le token `--mb-font-display` du gabarit. Voir la table de
     * `MemoBook Generator/templates/travel-journal/LAYOUT_KB.md`, et [BookFontRole] pour le
     * croisement des noms.
     */
    data class FontDisplay(val value: String) : BookCustomisationEdit

    /** Celle des **sous-titres** — `fontTitle`, token `--mb-font-title`. */
    data class FontTitle(val value: String) : BookCustomisationEdit

    /** Celle des **textes** — `fontHand`, la manuscrite du récit. */
    data class FontHand(val value: String) : BookCustomisationEdit

    /** Celle des **fun facts** — `fontFacts`. */
    data class FontFacts(val value: String) : BookCustomisationEdit

    /**
     * **Les quatre d'un coup**, parce qu'on ne les choisit plus séparément.
     *
     * Un seul aller-retour et non quatre : un assortiment est une décision, et
     * quatre `PATCH` successifs laisseraient le carnet dans trois états
     * intermédiaires qui n'ont jamais été choisis — dont un, si le réseau
     * coupe au milieu, resterait. Les quatre colonnes voyagent déjà ensemble
     * dans le corps de la requête, il n'y avait qu'à les y mettre.
     *
     * **Et les pointillés avec** (02/10/2026) : un assortiment décide aussi
     * d'eux — voir [BookRulesLock]. Les envoyer à part laisserait le serveur,
     * le temps d'un aller-retour ou pour de bon si le second échoue, avec un
     * *Manuscrit* aux pointillés allumés que l'écran ne montre pas.
     */
    data class FontCombo(val combo: BookFontCombo, val rulesEnabled: Boolean) : BookCustomisationEdit

    data class Quiz(val value: Boolean) : BookCustomisationEdit
    data class FreeZones(val value: Boolean) : BookCustomisationEdit
    data class Crossword(val value: Boolean) : BookCustomisationEdit
}

// MARK: - Les typographies proposées

/**
 * Une police proposée par une feuille de typographie.
 *
 * Un **nom de famille**, celui que `memos.font*` porte et que le gabarit
 * d'impression résout (`MemoBook Generator/templates/travel-journal/`) ; un **libellé**, celui
 * que la maquette écrit — « Playfair » pour Playfair Display — ; et une
 * phrase. L'app ne fait que montrer le libellé et renvoyer le nom.
 *
 * @property wordmark Le nom de la police **dessiné dans sa police**, quand Clara
 *   l'a fourni en vectoriel (`assets/logos/<Nom>.svg` → `Wordmark<Nom>`). `null` :
 *   l'écran écrit le libellé en General Sans.
 */
class BookFontOption(
    val name: String,
    label: String? = null,
    val detail: String,
    val wordmark: String? = null,
) {
    val label: String = label ?: name

    val id: String get() = name

    /**
     * Cette option est-elle celle qu'un carnet porte ? Le nom entier d'abord ;
     * le libellé aussi, parce que la base a longtemps reçu « Playfair » là où
     * le gabarit dit « Playfair Display ».
     */
    fun matches(stored: String): Boolean = stored == name || stored == label

    override fun equals(other: Any?): Boolean =
        other is BookFontOption && other.name == name && other.label == label &&
            other.detail == detail && other.wordmark == wordmark

    override fun hashCode(): Int = listOf(name, label, detail, wordmark).hashCode()

    override fun toString(): String =
        "BookFontOption(name=$name, label=$label, detail=$detail, wordmark=$wordmark)"

    companion object {
        /**
         * Deux noms désignent-ils la même famille ? Le nom entier, ou le libellé :
         * la base a longtemps reçu « Playfair » là où le gabarit dit « Playfair
         * Display », et les deux doivent se reconnaître.
         */
        fun matching(one: String, other: String): Boolean {
            if (one == other) return true
            val known = catalogue.firstOrNull { it.matches(one) } ?: return false
            return known.matches(other)
        }

        // Les cinq familles que le carnet sait porter.
        //
        // **Quatre d'entre elles se dessinent dans leur propre police**, par un
        // vectoriel du nom (Hugo, 17/09/2026, T118) : on n'embarque pas une
        // famille pour un bout de ligne. Alegreya a reçu le sien le 22/09/2026 ;
        // Montserrat s'écrit encore en General Sans, mais aucun assortiment ne la
        // propose plus.
        val playfair = BookFontOption(
            name = "Playfair Display",
            label = "Playfair",
            detail = "L’élégante, celle des titres",
            wordmark = "WordmarkPlayfair",
        )
        val alegreya = BookFontOption(
            name = "Alegreya", detail = "La serif chaleureuse du récit", wordmark = "WordmarkAlegreya",
        )
        val montserrat = BookFontOption(name = "Montserrat", detail = "La géométrique, nette et moderne")
        val hansley = BookFontOption(
            name = "Hansley", detail = "La manuscrite des titres", wordmark = "WordmarkHansley",
        )
        val gloria = BookFontOption(
            name = "Gloria Hallelujah",
            label = "Hallelujah",
            detail = "L’écriture à la main du récit",
            wordmark = "WordmarkGloriaHallelujah",
        )

        /** Le catalogue entier, pour résoudre un nom stocké en libellé. */
        val catalogue: List<BookFontOption> = listOf(playfair, alegreya, montserrat, hansley, gloria)
    }
}

/**
 * Les quatre typographies du carnet, dans l'ordre de l'écran.
 *
 * **On n'en choisit plus une par une** (Hugo, 16/09/2026) : l'écran ne propose
 * que des [BookFontCombo], trois assortiments dont on sait qu'ils tiennent
 * ensemble. Ce type reste, parce qu'il porte ce qu'un combo ne dit pas —
 * quelle colonne chaque rôle écrit, quelle édition il envoie, et sous quel nom
 * il se lit. C'est lui qui traduit un combo en quatre valeurs.
 *
 * ⚠️ **Le croisement des noms est volontaire.** « Typographie des titres »
 * écrit `fontDisplay` — le token `--mb-font-display` du gabarit —, et « des
 * sous-titres » écrit `fontTitle` (`--mb-font-title`). Voir la table de
 * `MemoBook Generator/templates/travel-journal/LAYOUT_KB.md`.
 */
enum class BookFontRole(val rawValue: String) {
    Titles("titles"),
    Subtitles("subtitles"),
    Texts("texts"),
    FunFacts("funFacts");

    val id: String get() = rawValue

    /**
     * La colonne du carnet que ce rôle lit. Le `WritableKeyPath` de Swift est
     * ici une propriété en lecture, et [writing] pour l'écriture : le carnet
     * est une `data class` immuable.
     */
    val keyPath: KProperty1<BookCustomisation, String>
        get() = when (this) {
            Titles -> BookCustomisation::fontDisplay
            Subtitles -> BookCustomisation::fontTitle
            Texts -> BookCustomisation::fontHand
            FunFacts -> BookCustomisation::fontFacts
        }

    /** Le carnet, la colonne de ce rôle portant `name` — l'écriture du `keyPath` Swift. */
    fun writing(name: String, into: BookCustomisation): BookCustomisation = when (this) {
        Titles -> into.copy(fontDisplay = name)
        Subtitles -> into.copy(fontTitle = name)
        Texts -> into.copy(fontHand = name)
        FunFacts -> into.copy(fontFacts = name)
    }

    /** L'édition qui porte ce nom au serveur. */
    fun edit(name: String): BookCustomisationEdit = when (this) {
        Titles -> BookCustomisationEdit.FontDisplay(name)
        Subtitles -> BookCustomisationEdit.FontTitle(name)
        Texts -> BookCustomisationEdit.FontHand(name)
        FunFacts -> BookCustomisationEdit.FontFacts(name)
    }

    /**
     * Ce que ce rôle habille, tel que la feuille des combos l'écrit en face du
     * nom de la police. C'est **la** chose qu'un assortiment doit rendre
     * évidente : on choisit une ligne, et on doit voir ce qu'elle décide.
     */
    val label: String
        get() = when (this) {
            Titles -> "Titres"
            Subtitles -> "Sous-titres"
            Texts -> "Textes"
            FunFacts -> "Fun facts & autres"
        }

    /**
     * Le nom de la police que ce rôle porte dans ce carnet, écrit comme la
     * marque l'écrit — « Playfair » là où le gabarit dit « Playfair Display ».
     * Une famille inconnue s'affiche telle quelle : une valeur posée par un
     * autre client ne doit pas disparaître de l'écran.
     */
    fun fontLabel(customisation: BookCustomisation): String {
        val stored = keyPath.get(customisation)
        return BookFontOption.catalogue.firstOrNull { it.matches(stored) }?.label ?: stored
    }
}

// MARK: - Les trois assortiments

/**
 * Un assortiment de quatre typographies qui vont ensemble.
 *
 * **On ne choisit plus police par police** (Hugo, 16/09/2026). L'écran posait
 * quatre lignes — titres, sous-titres, textes, fun facts — et laissait
 * composer librement : trois familles au choix sur chacune, soit des dizaines
 * de combinaisons dont la plupart sont laides. Un carnet imprimé ne se
 * rattrape pas, et personne ne veut découvrir à la livraison qu'il a marié une
 * géométrique et une manuscrite.
 *
 * Quatre assortiments, donc, chacun cohérent de bout en bout, et l'écran dit
 * **ce que chaque police habille** : c'est la seule façon de choisir en
 * connaissance de cause sans avoir à connaître la typographie.
 *
 * ⚠️ **Deux des cinq familles ne sont pas encore dans le gabarit.** `fonts.css`
 * n'inline que Playfair Display et Gloria Hallelujah ; Hansley est versionné
 * sans être inliné, Alegreya et Montserrat ne sont pas là du tout — voir
 * `MemoBook Generator/templates/travel-journal/LAYOUT_KB.md` § Polices. Rien n'échoue : la page
 * retombe sur une police système. C'était déjà vrai des quatre lignes que ces
 * combos remplacent ; ce n'est donc pas une régression, c'est une dette
 * nommée.
 *
 * @property name Le nom de l'assortiment — ce qu'on retient. « Carnet de voyage ».
 * @property detail Ce qu'il donne au carnet, en une phrase.
 * @property fonts Les quatre familles, **par rôle**. Une table et non quatre
 *   champs : c'est elle qui se parcourt pour écrire les quatre colonnes comme pour
 *   dessiner les quatre lignes de la feuille, sans que personne ait à réénumérer
 *   les rôles.
 */
data class BookFontCombo(
    val id: String,
    val name: String,
    val detail: String,
    val fonts: Map<BookFontRole, String>,
) {
    /**
     * La police de ce rôle dans cet assortiment, sous son nom de famille — ce
     * que la base stocke et que le gabarit résout.
     */
    fun font(role: BookFontRole): String =
        fonts[role] ?: travelJournal.fonts[role] ?: "Playfair Display"

    /** Le même, sous le nom qu'on écrit : « Playfair » et non « Playfair Display ». */
    fun fontLabel(role: BookFontRole): String {
        val name = font(role)
        return BookFontOption.catalogue.firstOrNull { it.matches(name) }?.label ?: name
    }

    /** Le vectoriel du nom de la police de ce rôle, s'il existe. */
    fun fontWordmark(role: BookFontRole): String? =
        BookFontOption.catalogue.firstOrNull { it.matches(font(role)) }?.wordmark

    /**
     * Ce carnet porte-t-il cet assortiment ? **Les quatre rôles, ou aucun** :
     * un carnet composé à la main avant cette feuille peut très bien avoir
     * trois polices sur quatre en commun avec un combo, et le cocher serait
     * mentir sur ce qui s'imprimera.
     */
    fun matches(customisation: BookCustomisation): Boolean =
        BookFontRole.entries.all { role ->
            BookFontOption.matching(font(role), role.keyPath.get(customisation))
        }

    /**
     * L'assortiment se choisit-il aujourd'hui ?
     *
     * **La V1 n'imprime que « Carnet de voyage »** (Hugo, 09/10/2026) : les
     * deux autres restent sur la feuille, pâlis et marqués « À venir », et ne
     * se touchent pas. Le modèle sait toujours les poser — un carnet déjà
     * réglé dessus garde ses polices, et le jour où le gabarit les imprime,
     * il suffit de rouvrir ici.
     */
    val isAvailable: Boolean get() = id == travelJournal.id

    companion object {
        // Les trois

        /**
         * Le défaut, et celui que portent déjà les carnets existants : Playfair,
         * Hansley, Gloria Hallelujah, Playfair. C'est **exactement** le jeu que la
         * base pose par défaut (voir les défauts de [BookCustomisation]), ce qui
         * fait qu'un carnet d'avant cette feuille s'y reconnaît sans rien changer.
         */
        val travelJournal = BookFontCombo(
            id = "travel-journal",
            name = "Carnet de voyage",
            // La phrase de la V3 (`3595:24014`), sa coquille corrigée : « La
            // recommandations » y est au pluriel (Hugo, 06/10/2026, T199).
            detail = "La recommandation de nos équipes",
            fonts = mapOf(
                BookFontRole.Titles to "Playfair Display",
                BookFontRole.Subtitles to "Hansley",
                BookFontRole.Texts to "Gloria Hallelujah",
                BookFontRole.FunFacts to "Playfair Display",
            ),
        )

        /**
         * **Playfair seule**, sur les quatre rôles : un vrai livre, celui qu'on
         * range dans une bibliothèque. C'est ce que la V3 propose (`3595:24024`),
         * et c'est tranché le 01/10/2026 — l'app y mariait Alegreya au récit.
         *
         * Un carnet réglé sur l'ancien assortiment garde ses polices et se lit
         * « Personnalisé », comme ceux de « Moderne ».
         */
        val editorial = BookFontCombo(
            id = "editorial",
            name = "Éditorial",
            detail = "La plus classique",
            fonts = mapOf(
                BookFontRole.Titles to "Playfair Display",
                BookFontRole.Subtitles to "Playfair Display",
                BookFontRole.Texts to "Playfair Display",
                BookFontRole.FunFacts to "Playfair Display",
            ),
        )

        /** Tout à la main : le carnet qu'on aurait écrit soi-même. */
        val handwritten = BookFontCombo(
            id = "handwritten",
            name = "Manuscrit",
            detail = "Pour des livres plus fun",
            fonts = mapOf(
                BookFontRole.Titles to "Hansley",
                BookFontRole.Subtitles to "Hansley",
                BookFontRole.Texts to "Gloria Hallelujah",
                BookFontRole.FunFacts to "Gloria Hallelujah",
            ),
        )

        /**
         * Les trois, dans l'ordre de la feuille — le défaut en tête.
         *
         * Il y en avait quatre : « Moderne » (titres Montserrat, récit Alegreya)
         * est retiré le 18/09/2026 (Hugo). Un carnet réglé dessus reste tel quel —
         * ses quatre polices sont en base, le gabarit les résout — et la feuille
         * l'écrit « Personnalisé », comme tout carnet composé hors de ces trois.
         * Dans l'ordre de la V3 : le défaut, le manuscrit, le classique.
         */
        val all: List<BookFontCombo> = listOf(travelJournal, handwritten, editorial)

        /**
         * L'assortiment d'un carnet, ou `null` s'il n'en porte aucun.
         *
         * `null` est un état réel et non un défaut manquant : un carnet composé
         * police par police avant cette feuille, ou par un autre client, peut
         * n'entrer dans aucune des trois cases. L'écran l'écrit alors
         * « Personnalisé » plutôt que de cocher de force.
         */
        fun matching(customisation: BookCustomisation): BookFontCombo? =
            all.firstOrNull { it.matches(customisation) }
    }
}

// MARK: - Le nombre de pages

/**
 * Le niveau de détail du carnet, tel que la feuille « Nombre de page » le
 * propose.
 *
 * **Les nombres ne sont pas écrits dans l'app.** La maquette annonce 30 / 60 /
 * 90 en précisant « Estimations pour un voyage de 2 mois » : ce sont des
 * projections, pas des valeurs. Elles se recalculent donc sur la durée du
 * voyage qu'on regarde — c'est la note « Logique » du nœud (`3443:10070`).
 */
enum class BookPageTarget(val rawValue: String) {
    Compact("compact"),
    Standard("standard"),
    Detailed("detailed"),

    /** Le voyageur pose lui-même son nombre de pages. */
    Custom("custom");

    val id: String get() = rawValue

    /** Le nom du palier, sans son nombre — celui-ci dépend du voyage. */
    val title: String
        get() = when (this) {
            Compact -> "Compact"
            Standard -> "Par défaut"
            Detailed -> "Détaillé"
            Custom -> "Personnalisé"
        }

    val detail: String
        get() = when (this) {
            Compact -> "Très condensé, peut impliquer des pertes de détails"
            Standard -> "Parfait pour une aventure comme la tienne"
            Detailed -> "Les moindres détails de tes récits seront conservés"
            // Au tutoiement (R9) : la maquette vouvoie ici, seule de la feuille.
            Custom -> "Définis un nombre de pages cible"
        }

    /** « Compact (≈ 30 pages) » — le titre, et sa projection pour ce voyage-ci. */
    fun label(forTripDays: Int?, ratio: Int = 50): String {
        val pages = pageCount(forTripDays, ratio) ?: return title
        return "$title (≈ $pages pages)"
    }

    /**
     * Combien de pages ce palier vise pour un voyage de `forTripDays` jours, au
     * ratio photo / texte `ratio`.
     *
     * Une page par jour au palier « Par défaut » à 50 %, **pondérée par le
     * ratio** (Hugo, 18/10/2026 — [ratioFactor]), arrondie à la dizaine, bornée
     * entre un carnet minimal et ce qu'une reliure accepte. Les deux autres
     * paliers en sont les **deux tiers et les quatre tiers** (Hugo, 15/10/2026).
     * Sans date de fin, 40 / 60 / 80 à 50 %. `null` pour [Custom], qui ne
     * projette rien — c'est le voyageur qui pose le nombre.
     *
     * Le serveur fait le même calcul (`backend/src/services/pageTarget.ts`) :
     * c'est lui qui lit la densité du récit dans la cible.
     */
    fun pageCount(forTripDays: Int?, ratio: Int = 50): Int? {
        if (this == Custom) return null
        val standard = standardPageCount(forTripDays, ratio)
        return when (this) {
            Compact -> roundedToTen(standard.toDouble() * 2 / 3)
            Standard -> standard
            Detailed -> roundedToTen(standard.toDouble() * 4 / 3)
            Custom -> null
        }
    }

    companion object {
        /**
         * Le palier auquel un nombre de pages correspond, ou [Custom] s'il ne
         * tombe sur aucun.
         */
        fun matching(pageCount: Int, tripDays: Int?, ratio: Int = 50): BookPageTarget =
            listOf(Compact, Standard, Detailed)
                .firstOrNull { it.pageCount(tripDays, ratio) == pageCount } ?: Custom

        /**
         * **Les paliers suivent aussi le ratio** (Hugo, 18/10/2026) : un carnet
         * plus écrit vise moins de pages, un carnet plus photographique
         * davantage — c'est ce qu'il peut réellement atteindre. Recopie de
         * `RATIO_PAGE_FACTOR` (`backend/src/services/pageTarget.ts`).
         */
        fun ratioFactor(ratio: Int): Double = when {
            ratio < 13 -> 0.7
            ratio < 38 -> 0.85
            ratio < 63 -> 1.0
            ratio < 88 -> 1.15
            else -> 1.3
        }

        /**
         * Un carnet de moins de 30 pages ne vaut pas une reliure, et au-delà de 180
         * le dos ne tient plus. Sans durée connue, 60 pages à 50 %.
         */
        private fun standardPageCount(days: Int?, ratio: Int): Int {
            val factor = ratioFactor(ratio)
            if (days == null || days <= 0) return roundedToTen(60 * factor)
            return minOf(maxOf(roundedToTen(days.toDouble() * factor), 30), 180)
        }

        /** Le `.rounded()` de Swift : au plus proche, la moitié loin de zéro. */
        private fun roundedToTen(value: Double): Int =
            BigDecimal(value / 10).setScale(0, RoundingMode.HALF_UP).toInt() * 10
    }
}

// MARK: - Changer le nombre de pages cible

/**
 * Combien de fois le nombre de pages cible peut encore changer — le bloc
 * `pageTarget` de `GET /v1/trips/:id/settings`.
 *
 * **Deux changements par voyage** (Hugo, 15/10/2026) : chacun peut faire
 * réécrire tout le carnet par l'IA, ce qui coûte. Un changement ne compte
 * qu'une fois une étape écrite ([changesCount]) : avant, il n'y a rien à
 * homogénéiser, et régler sa cible le premier soir n'en est pas un.
 *
 * Décodage tolérant, et défaut **libre** : une API déployée avant cette règle
 * ne la sert pas, et l'app ne doit alors ni compter ni bloquer — c'est le
 * serveur qui décide, et il ne décide encore rien.
 *
 * @property changesLeft Ce qui reste, de 0 à [changeLimit].
 * @property changeLimit Combien de changements un voyage a en tout — 2.
 * @property changesCount Une étape au moins est écrite : un changement compte, et
 *   l'app demande confirmation avant de le faire.
 * @property rewriteAvailable Le dernier changement ouvre encore le droit de
 *   réécrire les étapes déjà écrites à la nouvelle cible —
 *   `POST /v1/trips/:id/page-target/rewrite`.
 * @property reachableByRatio **Ce que le carnet peut atteindre**, pour chacun des
 *   cinq ratios (Hugo, 18/10/2026) — `reachableByRatio`. Vide d'un serveur plus
 *   ancien : l'app ne juge alors aucune cible.
 */
@Serializable(with = PageTargetAllowance.Serializer::class)
data class PageTargetAllowance(
    val changesLeft: Int = 2,
    val changeLimit: Int = 2,
    val changesCount: Boolean = false,
    val rewriteAvailable: Boolean = false,
    val reachableByRatio: Map<Int, PageRange> = emptyMap(),
) {
    /**
     * **La cible est-elle atteignable ?** `null` quand oui — ou quand le
     * serveur ne dit pas ce que le carnet peut atteindre. Sinon, ce que la
     * feuille [PageTargetReach] dit : la fourchette d'aujourd'hui, la cible
     * atteignable la plus proche, et le ratio qui ouvrirait la cible voulue.
     * Le carnet final tient à ± 5 pages de sa cible
     * (`PAGE_TARGET_TOLERANCE`) : une cible à 5 pages de la fourchette passe.
     */
    fun reach(of: Int, ratio: Int): PageTargetReach? {
        val target = of
        val range = reachableByRatio[ratio] ?: return null
        val tolerance = 5
        if (!(target < range.min - tolerance || target > range.max + tolerance)) return null
        val isTooLong = target > range.max
        // La cible atteignable la plus proche, dans les bornes de la feuille.
        val rounded = BigDecimal((if (isTooLong) range.max else range.min).toDouble() / 10)
            .setScale(0, RoundingMode.HALF_UP).toInt() * 10
        val closest = minOf(maxOf(rounded, 30), 180)
        val opening = if (isTooLong) {
            reachableByRatio.keys.sorted()
                .firstOrNull { it > ratio && (reachableByRatio[it]?.max ?: 0) + tolerance >= target }
        } else {
            null
        }
        return PageTargetReach(target, ratio, range, closestTarget = closest, ratioThatReaches = opening)
    }

    /**
     * Les deux changements sont faits, et ils comptaient : la cible ne
     * bouge plus. Les paliers pâlissent, et l'appui dit pourquoi.
     */
    val isExhausted: Boolean get() = changesCount && changesLeft <= 0

    companion object {
        /** Ce qu'on lit quand le serveur ne dit rien : rien n'est compté. */
        val unrestricted = PageTargetAllowance()
    }

    /** Ce que le JSON porte : tout est facultatif, la table a des clés textuelles. */
    @Serializable
    @SerialName("PageTargetAllowance")
    private class Surrogate(
        val changesLeft: Int? = null,
        val changeLimit: Int? = null,
        val changesCount: Boolean? = null,
        val rewriteAvailable: Boolean? = null,
        val reachableByRatio: JsonElement? = null,
    )

    /**
     * Le décodage tolérant de Swift : chaque champ absent retombe sur son défaut,
     * et une table illisible vaut une table vide (`try?`).
     */
    object Serializer : KSerializer<PageTargetAllowance> {
        override val descriptor: SerialDescriptor = Surrogate.serializer().descriptor

        override fun deserialize(decoder: Decoder): PageTargetAllowance {
            val raw = decoder.decodeSerializableValue(Surrogate.serializer())
            // Un objet JSON a des clés textuelles : « 0 » à « 100 ».
            val byKey: Map<String, PageRange> = (raw.reachableByRatio as? JsonObject)?.let { element ->
                try {
                    MemoBookJson.decodeFromJsonElement<Map<String, PageRange>>(element)
                } catch (_: IllegalArgumentException) {
                    null
                }
            } ?: emptyMap()
            return PageTargetAllowance(
                changesLeft = raw.changesLeft ?: 2,
                changeLimit = raw.changeLimit ?: 2,
                changesCount = raw.changesCount ?: false,
                rewriteAvailable = raw.rewriteAvailable ?: false,
                reachableByRatio = byKey.mapNotNull { (key, range) -> key.toIntOrNull()?.let { it to range } }.toMap(),
            )
        }

        override fun serialize(encoder: Encoder, value: PageTargetAllowance) {
            val table = value.reachableByRatio.mapKeys { it.key.toString() }
            encoder.encodeSerializableValue(
                Surrogate.serializer(),
                Surrogate(
                    changesLeft = value.changesLeft,
                    changeLimit = value.changeLimit,
                    changesCount = value.changesCount,
                    rewriteAvailable = value.rewriteAvailable,
                    reachableByRatio = MemoBookJson.encodeToJsonElement(table),
                ),
            )
        }
    }
}

/** Une fourchette de pages : ce que le carnet peut atteindre. */
@Serializable
data class PageRange(val min: Int, val max: Int)

/**
 * **Une cible personnalisée hors d'atteinte** (Hugo, 18/10/2026) : ce que la
 * feuille dit au voyageur — ce que le carnet peut faire avec ses réglages, et
 * comment aller chercher la cible qu'il veut.
 *
 * @property closestTarget La cible atteignable la plus proche, à la dizaine.
 * @property ratioThatReaches Le plus petit ratio au-dessus de l'actuel qui
 *   ouvrirait la cible ; `null` quand aucun ne suffit, ou quand la cible est trop
 *   courte.
 */
data class PageTargetReach(
    val target: Int,
    val ratio: Int,
    val range: PageRange,
    val closestTarget: Int,
    val ratioThatReaches: Int? = null,
) {
    val id: String get() = "$target-$ratio"

    /** Trop longue — sinon trop courte : le récit seul dépasse déjà la cible. */
    val isTooLong: Boolean get() = target > range.max
}

/**
 * Où en est le voyage quand la cible change — c'est ce qui décide de
 * proposer, ou non, de réécrire les étapes déjà écrites.
 *
 * Au début ou au milieu, la suite du carnet pèse plus que ce qui est écrit :
 * on change la cible des prochaines étapes et on ne touche à rien. Vers la
 * fin, presque tout est déjà écrit à l'ancienne densité — le carnet serait
 * coupé en deux —, et l'app propose d'étoffer ou de condenser ce qui l'est.
 */
enum class PageTargetTripStage {
    BeginningOrMiddle,
    End;

    companion object {
        /**
         * La part du voyage écoulée à partir de laquelle on est « vers la fin » :
         * les deux tiers. Au-delà, il reste trop peu d'étapes à venir pour que
         * le carnet devienne homogène tout seul.
         */
        const val endThreshold: Double = 2.0 / 3.0

        /**
         * Le stade d'après les dates, ou `null` quand il faut le demander — sans
         * date de fin, on ne sait pas quelle part du voyage est passée.
         *
         * Le voyage dure ses jours bornes comprises, comme ailleurs dans l'app ;
         * sont écoulés les jours **entiers** avant aujourd'hui — celui qu'on vit
         * n'est pas encore raconté. Un voyage terminé est à la fin.
         *
         * Le `Calendar` de Swift est ici son fuseau, `zone`.
         */
        fun from(
            startDate: Instant?,
            endDate: Instant?,
            today: Instant = Instant.now(),
            zone: ZoneId = ZoneId.systemDefault(),
        ): PageTargetTripStage? {
            if (endDate == null) return null
            val todayStart = today.atZone(zone).toLocalDate()
            val end = endDate.atZone(zone).toLocalDate()
            if (todayStart > end) return End
            if (startDate == null) return null
            val start = startDate.atZone(zone).toLocalDate()
            if (todayStart < start) return BeginningOrMiddle
            val total = ChronoUnit.DAYS.between(start, end).toInt() + 1
            val elapsed = ChronoUnit.DAYS.between(start, todayStart).toInt()
            return if (elapsed.toDouble() / maxOf(total, 1).toDouble() >= endThreshold) End else BeginningOrMiddle
        }
    }
}
