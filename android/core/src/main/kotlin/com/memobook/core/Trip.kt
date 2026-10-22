package com.memobook.core

import kotlinx.serialization.ExperimentalSerializationApi
import kotlinx.serialization.KeepGeneratedSerializer
import kotlinx.serialization.Serializable
import kotlinx.serialization.SerializationException
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import java.net.URI
import java.time.Instant

// Ce que la page d'accueil affiche, modélisé comme le back-end le renverra.
// Le jumeau de `MemoBookCore/Trip.swift`.
//
// Rien n'est en dur dans les vues : l'écran ne sait rien du contenu, il ne sait
// que le dessiner. Le jour où l'API existe, seule la source du [HomeFeed]
// change — voir `HomeModel`.

/** La personne qui voyage. Le prénom porte la salutation de l'accueil. */
@OptIn(ExperimentalSerializationApi::class)
@KeepGeneratedSerializer
@Serializable(with = Traveller.Serializer::class)
data class Traveller(
    val id: String,
    val firstName: String,
    @Serializable(with = UriSerializer::class) val avatarUrl: URI? = null,

    /**
     * Ce compte raconte sans limite : il est abonné, ou résilié mais encore
     * dans sa période payée (Hugo, 03/10/2026).
     *
     * **Explicite**, et plus déduit d'un quota absent comme sous l'ancien
     * essai gratuit : c'est ce que `SubscriptionSession` apprend de
     * l'accueil pour que la conversation et les réglages sachent, sans
     * relire le profil, s'il faut compter. Faux quand un serveur plus ancien
     * ne sert pas le champ — le serveur tranche de toute façon.
     */
    val isUnlimited: Boolean = false,

    /** Ce compte a déjà été abonné, en ce moment ou par le passé. Il choisit la
     *  version du paywall (découverte ou retour) partout où on l'ouvre, et plus
     *  seulement depuis le profil. */
    val hasSubscribedBefore: Boolean = false,

    /**
     * Le jour où la **période payée** du dernier abonnement s'est achevée,
     * quand c'est récent.
     *
     * C'est ce qui ouvre l'alerte système « Ton abonnement MemoBook s'est
     * arrêté » à l'ouverture de l'app (Hugo, 16/09/2026). Il ne sert qu'à ça :
     * l'abonnement lui-même se lit sur le profil, et l'accueil n'en a pas
     * besoin pour le reste.
     *
     * **Déduit et non stocké**, et **borné à quinze jours** côté serveur — une
     * alerte annonce une nouvelle, et quelqu'un qui revient au bout de trois
     * mois n'a pas de nouvelle à apprendre. `null` le reste du temps, ou quand
     * un serveur plus ancien ne sert pas le champ.
     */
    @Serializable(with = InstantSerializer::class) val subscriptionEndedOn: Instant? = null,

    /**
     * **Le rappel de fin de voyage** (01/10/2026) : l'abonnement va se
     * renouveler alors qu'aucun voyage ne court plus.
     *
     * C'est ce qui reste de « l'arrêt automatique » : le store ne laisse pas
     * l'app résilier à la place de la personne, alors l'accueil le lui propose,
     * en un geste. Faux quand un serveur plus ancien ne sert pas le champ.
     */
    val subscriptionOutlivesTrip: Boolean = false,

    /** **Où en est l'abonnement** — `traveller.subscriptionState` (contrat du
     *  06/10/2026, point 11). `null` d'un serveur plus ancien, **ou d'un état
     *  que l'app ne connaît pas** : il ne fait pas échouer tout l'accueil. */
    val subscriptionState: Subscription.State? = null,

    /** La fin de l'illimité d'un abonnement au renouvellement coupé
     *  ([Subscription.State.Ending]) : c'est là que la session le fait
     *  tomber, sans attendre une relecture. */
    @Serializable(with = InstantSerializer::class) val subscriptionEndsAt: Instant? = null,
) {
    /** La date où l'illimité s'arrête, quand le renouvellement est coupé et
     *  qu'elle est encore devant soi. `null` sinon. */
    val unlimitedUntil: Instant?
        get() = if (subscriptionState == Subscription.State.Ending) subscriptionEndsAt else null

    /**
     * Décodage tolérant sur les champs de l'abonnement : un serveur qui ne
     * les sert pas encore ne doit pas faire échouer tout l'accueil. Un
     * `subscriptionState` illisible est lu comme absent (le `try?` d'iOS).
     */
    object Serializer : DecodeIfPresentSerializer<Traveller>(generatedSerializer()) {
        override fun transformDeserialize(element: JsonElement): JsonElement {
            val tolerant = super.transformDeserialize(element)
            if (tolerant !is JsonObject) return tolerant
            val state = tolerant["subscriptionState"] ?: return tolerant
            val readable = try {
                MemoBookJson.decodeFromJsonElement(Subscription.State.serializer(), state)
                true
            } catch (_: SerializationException) {
                false
            } catch (_: IllegalArgumentException) {
                false
            }
            return if (readable) tolerant else JsonObject(tolerant - "subscriptionState")
        }
    }
}

/**
 * Où se passe le voyage. Le drapeau n'est **pas** une donnée : il se dérive du
 * code pays, pour qu'aucun back-end n'ait à stocker un emoji.
 */
@Serializable
data class Destination(
    /** Nom affiché, dans la langue de l'utilisateur. Ex. « Italie ». */
    val name: String,

    /** Code ISO 3166-1 alpha-2. Ex. « IT ». */
    val countryCode: String? = null,

    /**
     * La ville. Ex. « Rome ».
     *
     * Distincte du pays **et** du titre du carnet, parce que c'est la seule
     * des trois avec laquelle on peut s'adresser au voyageur : « Nouveau
     * voyage à Rome ! ». Le pays donnerait « à Italie », qui n'est pas du
     * français, et le titre (« Rome entre frère et sœur ») une phrase entière.
     *
     * `null` pour un voyage qui n'est pas situé dans une ville — un tour du
     * monde, une randonnée. La phrase se replie alors, voir `ChatCopy`.
     */
    val city: String? = null,
) {
    /** Le drapeau du pays, composé des deux indicateurs régionaux Unicode.
     *  `null` si le code est absent ou hors A–Z : mieux vaut pas de drapeau
     *  qu'un carré blanc. */
    val flag: String?
        get() {
            val code = countryCode ?: return null
            if (code.codePointCount(0, code.length) != 2) return null

            val flag = StringBuilder()
            for (scalar in code.uppercase().codePoints()) {
                if (scalar !in 'A'.code..'Z'.code) return null
                flag.appendCodePoint(scalar + 0x1F1E6 - 0x41)
            }
            return flag.toString()
        }
}

/**
 * Un **co-voyageur**, tel qu'il apparaît en pastille sur la couverture.
 *
 * Sur le voyage, il fait tout ce que fait le propriétaire : raconter, régler,
 * générer le carnet, le commander. Seule la suppression du voyage reste au
 * propriétaire. Ce qu'il ne partage pas non plus, c'est l'argent : chacun a son
 * abonnement.
 *
 * Le nom de type garde le mot du contrat d'API (`companions`), qui n'a pas
 * bougé — c'est le vocabulaire *produit* qui a changé.
 *
 * **Décodage tolérant sur les trois champs ajoutés avec la feuille « Inviter un
 * proche ».** Pas un champ obligatoire : la pastille de co-voyageur de
 * l'accueil est servie par trois routes différentes (`/v1/home`,
 * `/v1/trips/:id`, `/v1/trips/:id/settings`), et un serveur qui n'aurait pas
 * encore la dernière ferait échouer **tout l'écran**, pas seulement la ligne —
 * voir la règle du décodeur dans `ios/CLAUDE.md`.
 */
@OptIn(ExperimentalSerializationApi::class)
@KeepGeneratedSerializer
@Serializable(with = Companion.Serializer::class)
data class Companion(
    val id: String,
    val name: String,
    @Serializable(with = UriSerializer::class) val avatarUrl: URI? = null,

    /**
     * Ce que cette personne est pour le voyageur — « Ton pote d’enfance ».
     *
     * **Personne ne le saisit.** Il est déduit par l'agent de rédaction au bout
     * de quelques récits, comme `prompt` et `gallerySummary` le sont déjà —
     * c'est la note « Logique IA 🤖 » de la maquette. Nul tant qu'il n'y a pas
     * eu assez de récit pour le deviner : la ligne se contente alors du nom,
     * et c'est ce que dessine la première des deux variantes de la feuille.
     */
    val role: String? = null,

    /** Le propriétaire du voyage. Il n'a pas de ligne dans `memo_members` — il
     *  est ajouté en tête de la liste par le sérialiseur — et **il ne se
     *  supprime pas** : c'est la seconde phrase de la note « Logique » de la
     *  maquette. */
    val isOwner: Boolean = false,

    /**
     * L'invitation est partie, la personne n'est pas encore entrée.
     *
     * C'est ce qui distingue les deux actions au balayage : on **renvoie** un
     * lien à quelqu'un qui n'est jamais venu, on ne le renvoie pas à quelqu'un
     * qui raconte déjà.
     */
    val isPending: Boolean = false,

    /** **La ligne de celui qui lit** (Hugo, 18/10/2026) : c'est sous elle que
     *  la feuille écrit « Moi », propriétaire ou non. Faux d'un serveur plus
     *  ancien, qui ne le sert pas. */
    val isViewer: Boolean = false,
) {
    /** Repli quand la photo manque : une ou deux initiales, jamais plus. */
    val initials: String
        get() = name.split(' ')
            .filter { it.isNotEmpty() }
            .take(2)
            .joinToString("") { String(Character.toChars(it.codePointAt(0))) }
            .uppercase()

    object Serializer : DecodeIfPresentSerializer<com.memobook.core.Companion>(generatedSerializer())
}

/**
 * Les compteurs affichés sous le titre d'un voyage. Chacun est optionnel :
 * un voyage tout juste commencé n'a ni distance ni photo, et la ligne se
 * contente alors de ce qu'elle a.
 */
@Serializable
data class TripStats(
    val dayCount: Int? = null,
    /** En kilomètres. L'unité affichée suit les réglages de l'utilisateur. */
    val distanceKilometres: Double? = null,
    val photoCount: Int? = null,
) {
    val isEmpty: Boolean
        get() = dayCount == null && distanceKilometres == null && photoCount == null
}

/**
 * Où en est le voyage. C'est cette valeur, et non l'ordre de la liste, qui
 * range un voyage dans « en cours » ou dans « précédents ».
 *
 * Comme [Status], le cas [Unknown] existe pour qu'un état ajouté côté
 * serveur ne fasse pas planter une app déjà installée. Un état inconnu est
 * traité comme « en cours » : mieux vaut un voyage visible en haut de l'écran
 * qu'un voyage qui disparaît.
 */
@Serializable(with = TripStage.Serializer::class)
sealed interface TripStage {
    val rawValue: String

    /** Prévu, pas encore commencé. Il n'a rien à raconter : il se planifie. */
    data object Upcoming : TripStage { override val rawValue = "upcoming" }
    data object Ongoing : TripStage { override val rawValue = "ongoing" }
    data object Past : TripStage { override val rawValue = "past" }
    data class Unknown(override val rawValue: String) : TripStage

    /** Un état inconnu du serveur est traité comme « en cours » : mieux vaut un
     *  voyage visible en haut de l'écran qu'un voyage qui disparaît. */
    val isOngoing: Boolean
        get() = when (this) {
            Ongoing, is Unknown -> true
            Upcoming, Past -> false
        }

    companion object {
        fun from(raw: String): TripStage = when (raw) {
            "upcoming" -> Upcoming
            "ongoing" -> Ongoing
            "past" -> Past
            else -> Unknown(raw)
        }
    }

    object Serializer : RawValueSerializer<TripStage>("com.memobook.core.TripStage", { it.rawValue }, ::from)
}

/**
 * Où en est le carnet : ce qui a été raconté, et ce que ça remplit.
 *
 * Deux compteurs et une cible, pas un pourcentage : « 2/80 pages » se lit,
 * « 2,5 % » ne dit rien. La fraction n'en est que la traduction pour la barre.
 */
@Serializable
data class TripProgress(
    val memoryCount: Int,
    val pageCount: Int,

    /** Le nombre de pages visé pour ce carnet — réglable par le voyageur, voir
     *  `docs/reglages-utilisateur.md`. */
    val targetPageCount: Int,
) {
    /** De 0 à 1. Bornée des deux côtés : un carnet qui dépasse sa cible ne fait
     *  pas déborder sa barre. */
    val fraction: Double
        get() {
            if (targetPageCount <= 0) return 0.0
            return (pageCount.toDouble() / targetPageCount.toDouble()).coerceIn(0.0, 1.0)
        }
}

/** Un voyage : le carnet vu du dessus, avant d'entrer dedans. */
@Serializable
data class Trip(
    val id: String,
    val title: String,
    val destination: Destination? = null,
    val stage: TripStage,

    /** Bornes du séjour. Ouvertes des deux côtés : un voyage en cours n'a pas
     *  encore de fin, un carnet importé peut n'avoir aucune date. */
    @Serializable(with = InstantSerializer::class) val startDate: Instant? = null,
    @Serializable(with = InstantSerializer::class) val endDate: Instant? = null,

    @Serializable(with = UriSerializer::class) val coverPhotoUrl: URI? = null,
    val stats: TripStats = TripStats(),
    val companions: List<com.memobook.core.Companion> = emptyList(),

    /** Où en est le carnet. `null` pour un voyage à venir, qui n'a rien à
     *  remplir encore. */
    val progress: TripProgress? = null,

    /** Le carnet est généré et peut partir à l'impression — c'est ce qui
     *  allume le bouton imprimante sur les voyages passés. */
    val isPrintable: Boolean = false,

    /**
     * **Le crédit du jour de ce voyage** (Hugo, 03/10/2026), servi sur chaque
     * voyage **en cours** de l'accueil : c'est celui que vise le vocal de
     * l'accueil, et la feuille d'enregistrement s'en sert pour prévenir à
     * 4:30 et couper à 5:00 comme la barre de la conversation.
     *
     * `null` pour un voyage à venir ou passé, et quand un serveur plus ancien
     * ne le sert pas — on enregistre alors sans compter, et le serveur
     * tranche. Une variable, pour que l'app le décompte entre deux lectures.
     */
    var dailyCredit: DailyCredit? = null,

    /**
     * **Ce compte peut supprimer ce voyage** — il en est le propriétaire
     * (T233, Hugo, 06/10/2026). Un co-voyageur raconte, règle, commande,
     * mais ne détruit pas le récit de tout le monde : « Supprimer le voyage »
     * ne lui est même pas montré.
     *
     * `null` quand le serveur ne l'a pas dit — un serveur d'avant le
     * 06/10, un accueil gardé avant, et **un voyage créé hors ligne**, qui
     * appartient à son créateur : on lit alors `true` ([isDeletable]), et
     * c'est le serveur qui refuse.
     */
    val canDelete: Boolean? = null,
) {
    /** Voir [canDelete] : faute de réponse, la porte reste montrée. */
    val isDeletable: Boolean get() = canDelete ?: true

    /** Porte `Trip.local(…)` (`TripCreation.kt`). */
    companion object
}

/** La carte de découverte en bas de l'accueil. Son contenu vient du serveur
 *  pour qu'une campagne se change sans mise à jour de l'app. */
@Serializable
data class Showcase(
    val title: String,
    val subtitle: String,
    @Serializable(with = UriSerializer::class) val imageUrl: URI? = null,
    @Serializable(with = UriSerializer::class) val destinationUrl: URI? = null,
)

/**
 * Tout ce qu'il faut pour dessiner l'accueil, en une seule réponse.
 *
 * Les voyages arrivent dans **une** liste : c'est [TripStage] qui les range,
 * pas deux tableaux que le serveur devrait tenir cohérents.
 */
@Serializable
data class HomeFeed(
    val traveller: Traveller,
    val trips: List<Trip>,
    val showcase: Showcase? = null,
) {
    /** Les voyages en cours, les plus récemment commencés d'abord. */
    val ongoingTrips: List<Trip>
        get() = trips.filter { it.stage.isOngoing }.sortedByDescending { it.startDate ?: Instant.MIN }

    /** Les voyages prévus, le plus proche d'abord. */
    val upcomingTrips: List<Trip>
        get() = trips.filter { it.stage == TripStage.Upcoming }.sortedBy { it.startDate ?: Instant.MAX }

    /**
     * Les voyages terminés, du plus récent au plus ancien.
     *
     * `== Past`, et non « tout ce qui n'est pas en cours » : depuis qu'un
     * voyage peut être **à venir**, la négation le rangeait parmi les carnets
     * terminés — un voyage qui n'a pas commencé affiché comme fini.
     */
    val pastTrips: List<Trip>
        get() = trips.filter { it.stage == TripStage.Past }
            .sortedByDescending { it.endDate ?: it.startDate ?: Instant.MIN }
}
