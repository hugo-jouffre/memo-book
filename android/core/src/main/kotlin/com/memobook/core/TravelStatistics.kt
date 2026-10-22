package com.memobook.core

import kotlinx.serialization.KSerializer
import kotlinx.serialization.Required
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.builtins.ListSerializer
import kotlinx.serialization.descriptors.SerialDescriptor
import kotlinx.serialization.encoding.Decoder
import kotlinx.serialization.encoding.Encoder
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonDecoder
import java.time.Instant

// Ce que la feuille « Statistiques » du profil affiche, modélisé comme
// `GET /v1/profile/statistics` le rend. Le jumeau de
// `MemoBookCore/TravelStatistics.swift`.
//
// **Rien ici n'est calculé par l'app.** Chaque souvenir rédigé porte le relevé
// de l'agent de rédaction — pays, régions, villes, rencontres, kilomètres,
// transports, et l'endroit où le voyageur se trouve — et c'est le serveur qui
// les additionne à la lecture (`services/travelStatistics.ts`). L'app dessine
// ces chiffres, les accorde, et les relit tant que le serveur dit qu'un
// souvenir attend encore son relevé.

/**
 * Les cinq chiffres qui se lisent au global comme sur le voyage en cours.
 *
 * @property encounters combien de personnes rencontrées — les compagnons de voyage n'y sont pas.
 * @property distanceKilometres arrondis au kilomètre par le serveur ; l'app
 *   choisit seulement comment les écrire.
 */
@Serializable
data class TravelFigures(
    @Required val countries: Int = 0,
    @Required val regions: Int = 0,
    @Required val cities: Int = 0,
    @Required val encounters: Int = 0,
    @Required val distanceKilometres: Int = 0,
) {
    companion object {
        val empty = TravelFigures()
    }
}

/**
 * Un moyen de transport employé sur le voyage en cours.
 *
 * **Le nombre est facultatif, et c'est le sens de la ligne** : « 2 trains » se
 * compte, « scooter » se constate — la maquette écrit les deux sur la même
 * ligne. Le relevé ne pose un nombre que quand le récit l'a donné.
 */
@Serializable
data class TransportUsage(val kind: Kind, val count: Int? = null) {
    /**
     * Les moyens que l'agent sait nommer. Fermée : c'est l'app qui en écrit le
     * libellé et l'accord, et un moyen inconnu ne se lirait pas.
     */
    @Serializable
    enum class Kind(val rawValue: String) {
        @SerialName("plane") Plane("plane"),
        @SerialName("train") Train("train"),
        @SerialName("bus") Bus("bus"),
        @SerialName("car") Car("car"),
        @SerialName("boat") Boat("boat"),
        @SerialName("bike") Bike("bike"),
        @SerialName("walk") Walk("walk"),
        @SerialName("scooter") Scooter("scooter"),
        @SerialName("motorbike") Motorbike("motorbike"),
        @SerialName("metro") Metro("metro"),
        @SerialName("taxi") Taxi("taxi"),
        ;

        /**
         * Le mot au singulier et son pluriel — « avion », « avions ». Les deux
         * écrits, plutôt qu'un « s » collé : « bateau » fait « bateaux », et
         * « à pied » ne se compte pas.
         */
        val words: Pair<String, String>
            get() = when (this) {
                Plane -> "avion" to "avions"
                Train -> "train" to "trains"
                Bus -> "bus" to "bus"
                Car -> "voiture" to "voitures"
                Boat -> "bateau" to "bateaux"
                Bike -> "vélo" to "vélos"
                Walk -> "à pied" to "à pied"
                Scooter -> "scooter" to "scooters"
                Motorbike -> "moto" to "motos"
                Metro -> "métro" to "métros"
                Taxi -> "taxi" to "taxis"
            }
    }

    val id: Kind get() = kind

    /**
     * « 1 avion », « 2 trains », « scooter ». Le nombre ne s'écrit que s'il a
     * été relevé ; la marche ne se compte jamais.
     */
    val label: String
        get() {
            val (singular, plural) = kind.words
            if (count == null || kind == Kind.Walk) return singular
            return if (count == 1) "$count $singular" else "$count $plural"
        }
}

/**
 * Le voyage en cours, tel que la moitié basse de la feuille le montre.
 *
 * Décodage tolérant : un transport que cette version de l'app ne connaît pas
 * est **sauté**, pas fatal. L'agent peut apprendre un mot avant que l'app ne
 * soit mise à jour, et une ligne de moins vaut mieux qu'une feuille qui ne
 * s'ouvre plus. Les autres champs absents tombent sur leur zéro.
 *
 * @property currentPlace « Rome » — la dernière ville où un souvenir situe le voyageur.
 * @property dayCount le nombre de jours du voyage, pour « 2 jours validés sur 21 ».
 * @property validatedDays les journées qui ont au moins un souvenir rédigé.
 * @property recordings les vocaux enregistrés sur ce voyage.
 */
@Serializable
data class CurrentTripStatistics(
    val id: String,
    @Serializable(with = InstantSerializer::class) val startDate: Instant? = null,
    @Serializable(with = InstantSerializer::class) val endDate: Instant? = null,
    val currentPlace: String? = null,
    val dayCount: Int = 0,
    val validatedDays: Int = 0,
    val figures: TravelFigures = TravelFigures.empty,
    val recordings: Int = 0,
    @Serializable(with = LenientTransportsSerializer::class) val transports: List<TransportUsage> = emptyList(),
) {
    /**
     * La part du voyage déjà racontée, entre 0 et 1 : les jours validés sur les
     * jours du voyage. Zéro tant qu'on ne sait pas combien il dure — un
     * pourcentage d'une durée inconnue ne veut rien dire.
     */
    val writtenFraction: Double
        get() {
            if (dayCount <= 0) return 0.0
            return minOf(1.0, maxOf(0.0, validatedDays.toDouble() / dayCount.toDouble()))
        }
}

/**
 * Tout ce que la feuille « Statistiques » montre, d'un seul tenant.
 *
 * Même raison que [TravellerProfile] : un serveur plus ancien, ou un champ
 * ajouté plus tard, ne doit pas vider la feuille — chaque champ absent tombe sur
 * sa valeur par défaut.
 *
 * @property overall tous les voyages du compte, additionnés.
 * @property pendingDetections combien de souvenirs attendent encore leur relevé.
 *   Tant qu'il y en a, la feuille se relit à intervalle court : c'est ce qui fait
 *   bouger un chiffre sous les yeux, sans connexion ouverte avec le serveur.
 */
@Serializable
data class TravelStatistics(
    val tripCount: Int = 0,
    val overall: TravelFigures = TravelFigures.empty,
    val currentTrip: CurrentTripStatistics? = null,
    val pendingDetections: Int = 0,
    @Serializable(with = InstantSerializer::class) val updatedAt: Instant? = null,
) {
    /** `true` tant que l'agent a encore des souvenirs à relire — la feuille le dit, et se relit. */
    val isDetecting: Boolean get() = pendingDetections > 0

    /**
     * Ce qui **compte** pour dire que la feuille a changé : les chiffres, pas
     * l'horodatage. Deux lectures à trois secondes d'écart sur un voyage
     * immobile ne doivent pas faire clignoter l'écran.
     */
    fun hasSameFigures(other: TravelStatistics): Boolean =
        tripCount == other.tripCount &&
            overall == other.overall &&
            currentTrip == other.currentTrip &&
            pendingDetections == other.pendingDetections

    /** Porte les jeux d'essai de `:feature` (`TravelStatistics.fixture`…), qui s'y écrivent en extensions. */
    companion object
}

/**
 * Décode chaque transport **ou rien**, au lieu de faire échouer la liste qui
 * le porte — le `Lenient` d'iOS. C'est ce qui permet à une liste de transports
 * de survivre à un mot que l'app ne connaît pas encore.
 */
private object LenientTransportsSerializer : KSerializer<List<TransportUsage>> {
    private val strict = ListSerializer(TransportUsage.serializer())
    override val descriptor: SerialDescriptor = strict.descriptor

    override fun deserialize(decoder: Decoder): List<TransportUsage> {
        if (decoder !is JsonDecoder) return strict.deserialize(decoder)
        val array = decoder.decodeJsonElement() as? JsonArray ?: return emptyList()
        return array.mapNotNull { element ->
            runCatching { decoder.json.decodeFromJsonElement(TransportUsage.serializer(), element) }.getOrNull()
        }
    }

    override fun serialize(encoder: Encoder, value: List<TransportUsage>) = strict.serialize(encoder, value)
}
