package com.memobook.core

import kotlinx.serialization.Required
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import java.math.BigDecimal

// Le tunnel de commande du carnet : ses sept étapes, ce qu'elles lisent, et ce
// qu'elles envoient. Le jumeau de `MemoBookCore/PrintOrderFlow.swift` — sauf
// `ShippingCountry`, qui a son fichier (`ShippingCountry.kt`).
//
// **Aucun montant ne se calcule ici.** Le récapitulatif arrive tout fait de
// `POST /v1/memos/:id/orders/quote` : un prix qui s'additionne des deux côtés
// finit par diverger, et c'est le client qui a tort au pire moment — devant la
// personne qui paie. Les `BigDecimal` de ce fichier ne servent qu'à mettre en
// page ce que le serveur a compté.

// MARK: - Les étapes

/**
 * Les sept étapes, dans l'ordre où on les traverse.
 *
 * L'ordre est celui du [rawValue] : c'est lui qui écrit « Étape 3/7 », et c'est
 * lui qui décide du sens de l'animation quand on avance ou qu'on revient. Une
 * `enum class` se compare déjà dans cet ordre, comme le `Comparable` d'iOS.
 */
enum class OrderStep {
    Start,
    Shipping,
    Copies,
    Speed,
    Summary,
    Payment,
    Confirmation,
    ;

    /** Le rang, à partir de 0 — le `rawValue` Swift. */
    val rawValue: Int get() = ordinal

    /** Le mot qui suit « Étape 3/7 — ». Celui de la maquette, au mot près. */
    val label: String
        get() = when (this) {
            Start -> "Démarrage"
            Shipping -> "Livraison"
            Copies -> "Exemplaires"
            Speed -> "Rapidité"
            Summary -> "Récapitulatif"
            Payment -> "Paiement"
            Confirmation -> "Confirmation"
        }

    /** « Étape 3/7 - Exemplaires ». */
    val progressLabel: String get() = "Étape ${rawValue + 1}/${entries.size} - $label"

    /**
     * La dernière étape ne se quitte pas par la flèche de retour : la commande
     * est passée, revenir sur le paiement n'a plus de sens.
     */
    val allowsGoingBack: Boolean get() = this != Confirmation && this != Start
}

// MARK: - L'acheminement

/** Le palier d'acheminement. Deux, parce que c'est ce que l'imprimeur vend. */
@Serializable
enum class ShippingSpeed(val rawValue: String) {
    @SerialName("standard") Standard("standard"),
    @SerialName("express") Express("express"),
    ;

    val title: String
        get() = when (this) {
            Standard -> "Standard"
            Express -> "Express"
        }
}

// MARK: - Les options d'un exemplaire

/**
 * Les quatre options d'**un** exemplaire — « 1er Carnet », « 2e Carnet ».
 *
 * Elles pendent de l'exemplaire et non de la commande parce que l'écran laisse
 * offrir le deuxième carnet dans une autre version que le premier.
 *
 * @property position le rang, à partir de 1.
 */
@Serializable
data class PrintedCopyOptions(
    val position: Int,
    @Required val decorationsEnabled: Boolean = true,
    @Required val quizEnabled: Boolean = true,
    @Required val freeZonesEnabled: Boolean = true,
    @Required val crosswordEnabled: Boolean = true,
) {
    val id: Int get() = position

    /**
     * Le même jeu d'options, porté par un autre rang. C'est ce que fait
     * « appliquer la même version que ton 1er carnet ».
     */
    fun moved(to: Int): PrintedCopyOptions = copy(position = to)

    /**
     * Les deux exemplaires portent-ils la même version ? C'est ce qui décide si
     * le deuxième carnet s'annonce « par défaut » ou comme un choix à part.
     */
    fun matches(other: PrintedCopyOptions): Boolean =
        decorationsEnabled == other.decorationsEnabled &&
            quizEnabled == other.quizEnabled &&
            freeZonesEnabled == other.freeZonesEnabled &&
            crosswordEnabled == other.crosswordEnabled

    /** « 1er Carnet », « 2e Carnet », « 3e Carnet ». */
    val title: String get() = if (position == 1) "1er carnet" else "${position}e carnet"
}

// MARK: - Ce que le tunnel reçoit pour s'ouvrir

/**
 * Tout ce dont les sept étapes ont besoin, en **une** réponse.
 *
 * Une seule et non une par étape : le parcours est une seule destination, et le
 * découper ferait apparaître une attente à chaque « Continuer ». Seul le
 * récapitulatif a sa propre route, parce que lui seul dépend de choix qui ne
 * sont pas encore faits.
 *
 * @property renderId le rendu qui partira à l'impression. `null` quand le carnet
 *   n'a jamais été composé — il n'y a alors rien à commander, et l'écran le dit.
 * @property bookTitle le titre du **récit** — « Rome et la Dolce Vita ».
 * @property trip la carte du voyage, celle de l'accueil. Même modèle, même composant.
 * @property unitPrice ce que coûte un exemplaire, et [expressPrice] le supplément
 *   de l'express. Les deux arrivent d'emblée pour que les étapes 3 et 4
 *   s'affichent sans attendre.
 * @property shipping l'adresse proposée, tirée du profil. Une **amorce**, pas
 *   l'adresse de la commande : celle-ci se fige au moment de commander.
 * @property phoneNumber le numéro qu'on proposera pour le suivi WhatsApp. `null`
 *   tant que le compte n'en a pas : l'écran le demande alors au lieu de le supposer.
 * @property options le style du carnet, que chaque exemplaire reprend par défaut.
 */
@Serializable
data class OrderContext(
    val memoId: String,
    @Required val renderId: String?,
    val bookTitle: String,
    val pageCount: Int,
    val trip: Trip,
    @Serializable(with = BigDecimalSerializer::class) val unitPrice: BigDecimal,
    @Serializable(with = BigDecimalSerializer::class) val expressPrice: BigDecimal,
    val standardDays: DayRange,
    val expressDays: DayRange,
    val shipping: ShippingAddress,
    val countries: List<ShippingCountry>,
    val cards: List<PaymentCard>,
    @Required val selectedCardId: String?,
    val phoneNumber: String? = null,
    val options: PrintedCopyOptions,
) {
    /** Le délai annoncé pour un palier : « 5 à 7 jours ouvrés ». */
    fun days(speed: ShippingSpeed): DayRange = when (speed) {
        ShippingSpeed.Standard -> standardDays
        ShippingSpeed.Express -> expressDays
    }

    /** Porte les jeux d'essai de `:feature` (`OrderContext.fixture`…), qui s'y écrivent en extensions. */
    companion object
}

/** Deux bornes plutôt qu'une date : un imprimeur annonce un délai, pas un rendez-vous. */
@Serializable
data class DayRange(val min: Int, val max: Int) {
    /**
     * « 5 à 7 jours ouvrés », ou « 3 jours ouvrés » quand les bornes se
     * rejoignent — « 3 à 3 jours » ne se dit pas.
     */
    val label: String get() = if (min == max) "$max jours ouvrés" else "$min à $max jours ouvrés"

    /** « Dans 5 à 7 jours », pour l'écran de confirmation. */
    val deliveryLabel: String get() = if (min == max) "Dans $max jours" else "Dans $min à $max jours"
}

// MARK: - Le récapitulatif

/**
 * Une ligne du récapitulatif : un libellé, parfois un détail, un montant.
 *
 * @property detail « x2 », posé entre le libellé et le montant. `null` la plupart du temps.
 */
@Serializable
data class OrderQuoteLine(
    val id: String,
    val label: String,
    val detail: String? = null,
    @Serializable(with = BigDecimalSerializer::class) val amount: BigDecimal,
)

/** Un groupe de lignes et son sous-total. La maquette en pose deux. */
@Serializable
data class OrderQuoteGroup(
    val lines: List<OrderQuoteLine>,
    @Serializable(with = BigDecimalSerializer::class) val subtotal: BigDecimal,
)

/**
 * Le récapitulatif complet, tel que le serveur l'a compté.
 *
 * @property book ce que coûte **un** carnet : une seule ligne, dont le prix ne
 *   dépend que du nombre de pages.
 * @property specifications ce que le carnet **est**, et qui ne se choisit pas :
 *   le papier, la couverture, la reliure. C'étaient trois lignes facturées dans
 *   le récapitulatif, ce qui laissait croire à trois options alors qu'on ne peut
 *   en changer aucune. Elles décrivent désormais le produit, sous son prix, et le
 *   serveur les sert plutôt que l'app ne les écrive — le jour où le papier
 *   change, l'app n'a pas à sortir une version.
 * @property fulfilment les exemplaires et l'acheminement.
 * @property total **plus de déductions** (Hugo, 06/10/2026, T230) : elles ne
 *   portaient que la cagnotte, partie avec elle. Le total est ce que la carte
 *   paie. Un serveur qui enverrait encore `deductions` n'empêche rien de
 *   décoder : la clé est ignorée.
 */
@Serializable
data class OrderQuote(
    val bookTitle: String,
    val pageCount: Int,
    val copies: Int,
    val shippingSpeed: ShippingSpeed,
    @Serializable(with = BigDecimalSerializer::class) val unitPrice: BigDecimal,
    val book: OrderQuoteGroup,
    @Required val specifications: List<String> = emptyList(),
    val fulfilment: OrderQuoteGroup,
    @Serializable(with = BigDecimalSerializer::class) val total: BigDecimal,
    val estimatedMinDays: Int,
    val estimatedMaxDays: Int,
) {
    val estimatedDays: DayRange get() = DayRange(min = estimatedMinDays, max = estimatedMaxDays)

    /** Porte les jeux d'essai de `:feature` (`OrderQuote.fixture`…), qui s'y écrivent en extensions. */
    companion object
}

// MARK: - Ce qu'on envoie

/**
 * Ce que les six premières étapes remplissent.
 *
 * Un brouillon **local** : rien ne part avant « Payer ». C'est ce qui permet de
 * revenir sur ses choix sans écrire six fois dans la base.
 *
 * Une valeur, comme la `struct` d'iOS : ses fonctions `mutating` rendent ici le
 * brouillon modifié au lieu de le changer sur place.
 *
 * **Pas de moyen de paiement ici** (01/10/2026). Le brouillon portait une carte
 * et un « Apple Pay », que l'app fabriquait elle-même et que le serveur ne
 * connaissait pas (T225). La carte se choisit dans la feuille de Stripe, qui
 * tient celles du compte.
 *
 * @property copyOptions un jeu d'options par exemplaire, dans l'ordre des rangs.
 */
data class PrintOrderDraft(
    val copies: Int = 1,
    val shippingSpeed: ShippingSpeed = ShippingSpeed.Standard,
    val shipping: ShippingAddress,
    val copyOptions: List<PrintedCopyOptions> = emptyList(),
) {
    /**
     * L'adresse est-elle complète ? C'est ce qui allume « Continuer » à
     * l'étape 2. La deuxième ligne est facultative — beaucoup d'adresses n'en
     * ont pas, et en exiger une bloquerait tout le monde.
     */
    val hasCompleteAddress: Boolean
        get() = shipping.name.isNotBlank() &&
            shipping.line1.isNotBlank() &&
            shipping.postalCode.isNotBlank() &&
            shipping.city.isNotBlank() &&
            shipping.country.isNotBlank()

    /**
     * Ramène la liste d'options à [copies] entrées, en recopiant celles du
     * premier exemplaire pour tout rang qui vient d'apparaître.
     *
     * C'est la promesse de l'écran — « Par défaut, nous appliquons la même
     * version que ton 1er carnet » — tenue par le modèle plutôt que par la vue.
     */
    fun alignCopyOptions(defaults: PrintedCopyOptions): PrintOrderDraft {
        val first = copyOptions.firstOrNull() ?: defaults
        return copy(
            copyOptions = (1..maxOf(copies, 1)).map { position ->
                copyOptions.firstOrNull { it.position == position } ?: first.moved(to = position)
            },
        )
    }

    /**
     * Change une option d'un exemplaire.
     *
     * Toucher au **premier** carnet emmène avec lui tous ceux qui portaient
     * encore sa version : c'est ce que « par défaut, la même version que ton 1er
     * carnet » veut dire, et ne pas le faire laisserait le 2e carnet figé sur un
     * réglage qu'on vient d'abandonner.
     *
     * Les exemplaires **déjà détachés** ne bougent pas : quelqu'un qui a choisi
     * une version différente ne doit pas la voir se faire écraser.
     */
    fun setOption(option: PrintedCopyOption, isOn: Boolean, forCopyAt: Int): PrintOrderDraft {
        val index = copyOptions.indexOfFirst { it.position == forCopyAt }
        if (index < 0) return this

        val before = copyOptions[index]
        val after = option.applied(isOn, before)
        val options = copyOptions.toMutableList()
        options[index] = after

        if (forCopyAt == 1) {
            for (other in options.indices) {
                if (other != index && options[other].matches(before)) {
                    options[other] = after.moved(to = options[other].position)
                }
            }
        }
        return copy(copyOptions = options)
    }

    /**
     * L'exemplaire suit-il encore la version du premier ?
     *
     * Le premier se suit lui-même : c'est la référence, la question n'a pas de
     * sens pour lui et `true` est la réponse qui n'affiche pas de bouton de
     * détachement sur la référence elle-même.
     */
    fun followsFirstCopy(position: Int): Boolean {
        if (position == 1) return true
        val first = copyOptions.firstOrNull() ?: return true
        val copy = copyOptions.firstOrNull { it.position == position } ?: return true
        return copy.matches(first)
    }

    /** « Choisir une version différente du 1er carnet », et son retour. */
    fun setFollowsFirstCopy(follows: Boolean, forCopyAt: Int): PrintOrderDraft {
        val first = copyOptions.firstOrNull() ?: return this
        val index = copyOptions.indexOfFirst { it.position == forCopyAt }
        if (index < 0 || forCopyAt == 1) return this

        val options = copyOptions.toMutableList()
        if (follows) {
            options[index] = first.moved(to = forCopyAt)
        } else if (options[index].matches(first)) {
            // Détacher sans rien changer laisserait deux carnets identiques et
            // un écran qui prétend le contraire. On ouvre donc sur une
            // différence lisible : le carnet offert se passe des quiz.
            options[index] = options[index].copy(quizEnabled = !options[index].quizEnabled)
        }
        return copy(copyOptions = options)
    }
}

/**
 * Les quatre options d'un exemplaire, en tant que **champ qu'on désigne**.
 *
 * Une énumération plutôt qu'une propriété exposée : la vue nomme une option,
 * elle n'écrit pas dans la structure.
 */
enum class PrintedCopyOption(val rawValue: String) {
    Decorations("decorations"),
    Quiz("quiz"),
    FreeZones("freeZones"),
    Crossword("crossword"),
    ;

    val id: String get() = rawValue

    val title: String
        get() = when (this) {
            Decorations -> OrderCopy.Copies.decorations
            Quiz -> OrderCopy.Copies.quiz
            FreeZones -> OrderCopy.Copies.freeZones
            Crossword -> OrderCopy.Copies.crossword
        }

    fun value(options: PrintedCopyOptions): Boolean = when (this) {
        Decorations -> options.decorationsEnabled
        Quiz -> options.quizEnabled
        FreeZones -> options.freeZonesEnabled
        Crossword -> options.crosswordEnabled
    }

    internal fun applied(isOn: Boolean, options: PrintedCopyOptions): PrintedCopyOptions = when (this) {
        Decorations -> options.copy(decorationsEnabled = isOn)
        Quiz -> options.copy(quizEnabled = isOn)
        FreeZones -> options.copy(freeZonesEnabled = isOn)
        Crossword -> options.copy(crosswordEnabled = isOn)
    }
}

/**
 * Paramètres d'une commande d'impression, tels qu'ils partent au serveur.
 *
 * @property renderId le rendu à imprimer — celui que le tunnel a lu à
 *   l'ouverture. `null` quand il n'y en avait pas : le serveur prend alors **le
 *   dernier rendu prêt** du voyage (06/10/2026), ce qui laisse passer une
 *   commande dont la composition a abouti pendant qu'on remplissait son adresse,
 *   et répond `409 no_render` s'il n'y en a toujours aucun. Absent du corps
 *   quand il est nul.
 * @property stripeApiVersion la version d'API du SDK Stripe de l'app : c'est
 *   elle qui permet au serveur de rendre une clé éphémère lisible par la
 *   feuille, et donc les cartes du compte. Posée par `AppDependencies` — ce
 *   module ne connaît pas Stripe.
 */
@Serializable
data class NewPrintOrderRequest(
    val renderId: String?,
    val copies: Int,
    val shippingSpeed: ShippingSpeed,
    val shipping: ShippingAddress,
    val copyOptions: List<PrintedCopyOptions>,
    val stripeApiVersion: String? = null,
) {
    constructor(renderId: String?, draft: PrintOrderDraft) : this(
        renderId = renderId,
        copies = draft.copies,
        shippingSpeed = draft.shippingSpeed,
        shipping = draft.shipping,
        copyOptions = draft.copyOptions,
    )

    /** Porte les jeux d'essai de `:feature` (`NewPrintOrderRequest.previewRequest`), qui s'y écrivent en extensions. */
    companion object
}
