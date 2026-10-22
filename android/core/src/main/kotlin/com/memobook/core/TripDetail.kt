package com.memobook.core

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import java.net.URI
import java.time.Instant

// Ce qu'on voit en entrant dans un voyage : sa couverture, la relance de
// MemoBook, et les étapes déjà racontées. Le jumeau de `MemoBookCore/TripDetail.swift`.
//
// Même principe que [HomeFeed] : l'écran ne sait rien du contenu, il ne sait
// que le dessiner. Le jour où l'API existe, seule la source change.

/**
 * Comment on est allé d'une étape à la suivante.
 *
 * La liste est fermée côté app : un mode que l'app ne connaît pas est une
 * erreur de décodage, comme sur iOS.
 */
@Serializable
enum class TripTransport(val rawValue: String) {
    @SerialName("walk") Walk("walk"),
    @SerialName("bike") Bike("bike"),
    @SerialName("car") Car("car"),
    @SerialName("bus") Bus("bus"),
    @SerialName("train") Train("train"),
    @SerialName("boat") Boat("boat"),
    @SerialName("plane") Plane("plane"),
    ;

    /** Le nom du mode, tel qu'on l'écrit à l'utilisateur. */
    val displayName: String
        get() = when (this) {
            Walk -> "À pied"
            Bike -> "Vélo"
            Car -> "Voiture"
            Bus -> "Bus"
            Train -> "Train"
            Boat -> "Bateau"
            Plane -> "Avion"
        }
}

/** Une étape du voyage : un lieu, des dates, ceux qui y étaient. */
@Serializable
data class TripStep(
    val id: String,

    /** Son rang dans le voyage. C'est lui qui nomme l'étape tant qu'elle n'a
     *  pas de titre — le carnet, lui, en trouvera un. */
    val number: Int,

    /** Le lieu, tel qu'on le dirait : « Trastevere ». */
    val placeName: String? = null,

    /** Le pays, qui porte le drapeau de la vignette et le filtre « Pays ». */
    val destination: Destination? = null,

    @Serializable(with = InstantSerializer::class) val startDate: Instant? = null,
    @Serializable(with = InstantSerializer::class) val endDate: Instant? = null,
    val companions: List<com.memobook.core.Companion> = emptyList(),
    @Serializable(with = UriSerializer::class) val photoUrl: URI? = null,
    val transport: TripTransport? = null,

    /** « Valider cette étape » : le voyageur l'a confirmée. `null` tant que ce
     *  n'est pas fait. */
    @Serializable(with = InstantSerializer::class) val validatedAt: Instant? = null,

    /**
     * **Les souvenirs rattachés à cette étape** — ce que la croix de son
     * tiroir efface (T235, Hugo, 06/10/2026), un `DELETE /v1/entries/:id`
     * chacun.
     *
     * Une étape est un **lieu** ; elle peut porter plusieurs souvenirs — un
     * vocal, un texte, des photos (`entries.stepId`, plusieurs lignes pour
     * une étape). « Le souvenir de l'étape », c'est donc tout ce qu'on y a
     * raconté. `null` d'un serveur qui ne le sert pas encore : la croix ne
     * paraît pas, faute de savoir quoi effacer.
     */
    val entryIds: List<String>? = null,
) {
    /** La croix du tiroir s'offre : on sait quels souvenirs effacer. */
    val hasDeletableMemories: Boolean get() = !entryIds.isNullOrEmpty()

    /** Cette étape, validée. Sert la mise à jour optimiste de « Valider cette
     *  étape » côté app, et les jeux d'essai qui simulent la même réponse. */
    fun validated(at: Instant = Instant.now()): TripStep = copy(validatedAt = at)
}

/** Un voyage ouvert : tout ce qu'il faut pour dessiner son accueil. */
@Serializable
data class TripDetail(
    val trip: Trip,

    /**
     * La relance de MemoBook — « Comment ça se passe à Trastevere ? ».
     *
     * Elle vient du serveur et non de l'app : c'est une question posée à
     * partir de ce qui a déjà été raconté, pas un libellé d'interface. `null`
     * quand il n'y a encore rien à relancer.
     */
    val prompt: String? = null,

    val steps: List<TripStep> = emptyList(),
) {
    val id: String get() = trip.id

    /** Les pays traversés, sans doublon, dans l'ordre des étapes. C'est la
     *  liste du filtre « Pays ». */
    val countries: List<Destination>
        get() {
            val seen = mutableSetOf<String>()
            return steps.mapNotNull { it.destination }.filter { seen.add(it.name) }
        }

    /** Les modes de transport employés, sans doublon. */
    val transports: List<TripTransport>
        get() = steps.mapNotNull { it.transport }.distinct()
}
