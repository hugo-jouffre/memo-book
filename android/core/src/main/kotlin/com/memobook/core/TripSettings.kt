package com.memobook.core

import kotlinx.serialization.ExperimentalSerializationApi
import kotlinx.serialization.KeepGeneratedSerializer
import kotlinx.serialization.Serializable
import java.net.URI
import java.time.Instant

// Les paramètres d'un voyage : tout ce qui se règle sur le carnet sans quitter
// le voyage. Le jumeau de `MemoBookCore/TripSettings.swift`.
//
// L'écran est fait à 90 % d'intitulés que l'app connaît déjà — « Dates du
// voyage », « Rythme du récit » — et de valeurs qui viennent du serveur. C'est
// exactement le partage que `BrandSkeleton` demande : la page se dessine tout
// de suite, et seules les valeurs portent une barre d'attente.
//
// Ce qui se règle vraiment ici est décrit dans `docs/reglages-utilisateur.md` ;
// cette structure n'en est que la lecture.

/**
 * À quel rythme MEMO découpe le récit en étapes.
 *
 * Fermée côté app, tolérante au décodage : un rythme ajouté côté serveur
 * s'affiche sous son nom brut plutôt que de vider la ligne.
 */
@Serializable(with = NarrationPace.Serializer::class)
sealed interface NarrationPace {
    val rawValue: String

    data object Daily : NarrationPace { override val rawValue = "daily" }
    data object EveryTwoDays : NarrationPace { override val rawValue = "every_two_days" }
    data object EveryThreeDays : NarrationPace { override val rawValue = "every_three_days" }
    data object Weekly : NarrationPace { override val rawValue = "weekly" }

    /**
     * Le voyageur règle ses propres alertes.
     *
     * ⚠️ **L'écran qui les règle n'est pas dessiné.** L'option existe parce que
     * la maquette la pose (`3443:9874`) et qu'on n'invente pas plus qu'elle ne
     * dit (R3) ; choisir « Personnalisé » enregistre donc le rythme et ne
     * demande rien d'autre. Signalé dans la fiche écran.
     */
    data object Custom : NarrationPace { override val rawValue = "custom" }

    /** L'ancien rythme « À chaque lieu », remplacé dans la maquette par
     *  « Tous les 3 jours ». Gardé pour **relire** les voyages déjà réglés
     *  dessus : il s'affiche, il ne se propose plus. */
    data object ByPlace : NarrationPace { override val rawValue = "by_place" }
    data class Unknown(override val rawValue: String) : NarrationPace

    /** Le nom du rythme, tel qu'on l'écrit au voyageur. */
    val displayName: String
        get() = when (this) {
            Daily -> "Tous les jours"
            EveryTwoDays -> "Tous les 2 jours"
            EveryThreeDays -> "Tous les 3 jours"
            Weekly -> "Une fois par semaine"
            Custom -> "Personnalisé"
            ByPlace -> "À chaque lieu"
            is Unknown -> rawValue
        }

    /** La ligne sous le nom, dans la feuille « Rythme du récit ». Elle dit ce
     *  que le rythme **fait**, pas ce qu'il est. */
    val detail: String?
        get() = when (this) {
            Daily -> "Une entrée chaque soir"
            EveryTwoDays -> "Le rythme recommandé pour souffler"
            EveryThreeDays -> "Idéal pour les longs séjours"
            Weekly -> "Pour un résumé global"
            Custom -> "Définis tes propres alertes"
            ByPlace, is Unknown -> null
        }

    companion object {
        /** Les cinq rythmes que la feuille propose, dans l'ordre de la maquette. */
        // Un getter, pas un champ : les objets du `sealed interface` peuvent être
        // chargés avant leur compagnon, et la liste y recevrait des `null`.
        val selectable: List<NarrationPace> get() = listOf(Daily, EveryTwoDays, EveryThreeDays, Weekly, Custom)

        /**
         * Le rythme, depuis ce que la base garde.
         *
         * **Les anciens libellés aussi.** Jusqu'au 17/09/2026, la création écrivait
         * le rythme dans les mots de l'écran — « Tous les jours », « Tous les 2
         * jours », « Toutes les semaines » — quand la feuille des réglages
         * écrivait déjà la clé. Dix voyages en portent encore un : la feuille les
         * lisait comme un rythme inconnu et ne cochait rien (Hugo, 18/09/2026).
         * Le serveur les réécrit désormais en clés à l'entrée et une migration a
         * corrigé les rangées existantes, mais une app qui parle à l'API d'avant
         * doit les relire de la même façon.
         */
        fun from(storedValue: String): NarrationPace = when (storedValue.trim().lowercase()) {
            "daily", "tous les jours" -> Daily
            "every_two_days", "tous les 2 jours", "tous les deux jours" -> EveryTwoDays
            "every_three_days", "tous les 3 jours", "tous les trois jours" -> EveryThreeDays
            "weekly", "toutes les semaines", "une fois par semaine" -> Weekly
            "custom", "personnalisé" -> Custom
            "by_place", "à chaque lieu" -> ByPlace
            else -> Unknown(storedValue)
        }
    }

    object Serializer : RawValueSerializer<NarrationPace>(
        "com.memobook.core.NarrationPace",
        { it.rawValue },
        { from(storedValue = it) },
    )
}

/**
 * Les quatre alertes d'un voyage — la feuille « Notifications ».
 *
 * **Quatre drapeaux et non un seul.** L'interrupteur « Notifications » des
 * réglages coupe tout d'un coup ; ceux-ci disent *quoi* recevoir quand il est
 * levé. Les confondre revenait à proposer un réglage fin qui n'était pas
 * retenu — exactement ce que `docs/reglages-utilisateur.md` interdit.
 *
 * Décodage tolérant : un serveur qui ne les sert pas encore rend quatre
 * alertes actives, ce qui est le défaut de la base.
 */
@OptIn(ExperimentalSerializationApi::class)
@KeepGeneratedSerializer
@Serializable(with = TripNotificationPreferences.Serializer::class)
data class TripNotificationPreferences(
    /** « Rappel d'écriture » — la relance calée sur le rythme du récit. */
    var writingReminder: Boolean = true,
    /** « Nouveau récit » — un proche a alimenté le carnet. */
    var newStory: Boolean = true,
    /** « Résumé hebdomadaire » — un point sur les souvenirs capturés. */
    var weeklyDigest: Boolean = true,
    /** « Rappel de fin de voyage » — l'alerte qui dit qu'il est temps de
     *  valider l'impression. */
    var tripEndReminder: Boolean = true,
) {
    object Serializer : DecodeIfPresentSerializer<TripNotificationPreferences>(generatedSerializer())
}

/** Les paramètres d'un voyage, d'un seul tenant. */
@Serializable
data class TripSettings(
    val tripId: String,

    // Gère ton aventure

    /** Le nom du voyage — « Rome 2026 ». */
    var name: String,

    /**
     * Le **crédit du jour** de ce voyage, lu par ce compte — voir
     * [DailyCredit].
     *
     * Il appartient au voyage (5 minutes par jour, partagées entre les
     * co-voyageurs non abonnés), et `isUnlimited` dit si **celui qui lit** est
     * abonné. Les réglages en portent la ligne « Crédit du jour » : c'est
     * désormais le levier de l'abonnement, toujours visible pour un
     * non-abonné (Hugo, 03/10/2026).
     *
     * **Une clé neuve**, et non l'ancienne `memory` remplie autrement : le
     * cache disque garde des réglages lus avant ce changement, et le
     * décodeur tolérant aurait relu ces limites de l'ancien modèle comme un
     * crédit plein inventé. Optionnel le temps qu'un serveur plus ancien le
     * serve : la ligne disparaît alors, au lieu d'annoncer un reste faux.
     */
    var dailyCredit: DailyCredit? = null,

    @Serializable(with = InstantSerializer::class) var startDate: Instant? = null,
    @Serializable(with = InstantSerializer::class) var endDate: Instant? = null,
    var narrationPace: NarrationPace? = null,

    /** Les notifications de ce voyage. C'est l'interrupteur du voyage, pas
     *  celui du système : couper ici n'enlève pas l'autorisation, ça arrête
     *  seulement les relances de ce carnet-là. */
    var wantsNotifications: Boolean = true,

    /** Le détail des quatre alertes, réglé par « Gérer mes notifications ». */
    var notifications: TripNotificationPreferences = TripNotificationPreferences(),

    /**
     * Ceux qui racontent le voyage avec toi — **le propriétaire compris**, en
     * tête de liste.
     *
     * Il y figure parce que la feuille « Inviter un proche » le montre : sa
     * ligne dit « Moi » et « Propriétaire du voyage », et c'est elle qui fait
     * comprendre que la liste est celle du voyage entier. Il en est retiré
     * **là où on compte les autres** — voir [guests].
     */
    var companions: List<com.memobook.core.Companion> = emptyList(),

    /** Le code d'accès du voyage — « JHKFDA ». C'est lui qu'on colle dans un
     *  message pour faire entrer quelqu'un. Nul tant que les réglages
     *  viennent d'un jeu d'essai sans code. */
    var accessCode: String? = null,

    // Le contenu du carnet

    /** Le thème du voyage — « City trip & découvertes ». Il oriente le ton du
     *  récit et les illustrations. */
    var theme: String? = null,

    /** Le carnet est visible dans la galerie de la communauté. */
    var isPublicGallery: Boolean = false,

    /** Le style de mise en page — « Pointillés, cadres, etc. ». Un résumé de ce
     *  que `docs/reglages-utilisateur.md` détaille. */
    var styleSummary: String? = null,

    // Accès rapide

    /** Le Tricount relié, s'il y en a un. Sa présence change le libellé de la
     *  ligne : « Connecte ton Tricount » devient le compte relié. */
    var tricountLabel: String? = null,

    /** L'aperçu du carnet, pour la vignette de la ligne « Prévisualisation PDF ».
     *  `null` quand rien n'a encore été composé. */
    @Serializable(with = UriSerializer::class) var previewCoverUrl: URI? = null,

    /**
     * Le PDF du dernier carnet composé.
     *
     * Il voyage **avec les réglages** parce qu'il s'y trouvait déjà : la route
     * lit le dernier rendu prêt pour en tirer la vignette de couverture, et le
     * document est dans la même ligne. C'est lui que les feuilles de
     * personnalisation feuillettent au-dessus d'elles — voir `BookPagesPeek`.
     *
     * `null` tant qu'aucun carnet n'a été composé : les feuilles s'ouvrent
     * alors seules, sans pages au-dessus. Montrer deux rectangles vides
     * donnerait l'impression d'un rendu qui a échoué.
     */
    @Serializable(with = UriSerializer::class) var bookPdfUrl: URI? = null,

    /** Le carnet peut partir à l'impression. Faux, la ligne « Commander le
     *  carnet » reste lisible mais ne mène nulle part — il n'y a rien à
     *  imprimer. */
    var isPrintable: Boolean = false,

    /**
     * Les personnalisations de la mise en page — l'écran « Style du carnet ».
     *
     * Elles voyagent **avec** les réglages et non sur une requête à elles : il
     * y en a un jeu par voyage, elles se lisent toujours avec lui, et
     * `styleSummary` en est le résumé d'une ligne. Optionnel le temps que la
     * route les serve à tous les carnets.
     */
    var customisation: BookCustomisation? = null,

    /** « Supprimer la conversation » est ouvert à ce compte — le propriétaire du
     *  voyage. `null` quand le serveur ne l'a pas dit (un jeu d'essai, une
     *  réponse mise en cache avant que la conversation vive sur le serveur) :
     *  on lit alors `true`, et c'est le serveur qui refuse. */
    var canClearConversation: Boolean? = null,

    /** « Supprimer le voyage » est ouvert à ce compte — le propriétaire
     *  (T233). Même lecture que [canClearConversation] : `null` vaut `true`,
     *  et c'est le serveur qui refuse. Un co-voyageur ne voit pas la ligne. */
    var canDelete: Boolean? = null,

    /** Combien de fois le nombre de pages cible peut encore changer — le bloc
     *  `pageTarget` de la route (Hugo, 15/10/2026). Optionnel parce que l'API
     *  de production peut être en retard sur l'app : on lit alors
     *  [pageTargetAllowance], qui ne compte rien et ne bloque rien. */
    var pageTarget: PageTargetAllowance? = null,
) {
    val id: String get() = tripId

    /** Ce que l'écran lit : ce que le serveur a servi, ou rien de compté. */
    val pageTargetAllowance: PageTargetAllowance get() = pageTarget ?: PageTargetAllowance.unrestricted

    /**
     * « @clara_prn, @ana.prn » — les co-voyageurs en bout de ligne.
     *
     * `null` quand on voyage seul : la maquette ne dessine pas ce cas, et une
     * ligne « Co-voyageur(s) » vide se lirait comme une valeur qui n'a pas
     * chargé. C'est un écart signalé dans la fiche écran.
     */
    val companionsLabel: String?
        get() = if (guests.isEmpty()) null else guests.joinToString(", ") { it.name }

    /**
     * Les co-voyageurs **sans le propriétaire**.
     *
     * C'est ce que compte la ligne « Co-voyageur(s) » des réglages : le
     * titulaire de l'écran n'est pas quelqu'un qu'il a invité, et se voir dans
     * sa propre liste ferait douter du nombre.
     */
    val guests: List<com.memobook.core.Companion>
        get() = companions.filter { !it.isOwner }
}

/**
 * Ce qu'un réglage modifié envoie au serveur.
 *
 * Une seule propriété à la fois, et non la structure entière : l'écran ne
 * renvoie que ce que l'utilisateur a touché, ce qui évite d'écraser un réglage
 * changé ailleurs entre-temps — par un co-voyageur, par exemple.
 */
sealed interface TripSettingsEdit {
    data class Name(val value: String) : TripSettingsEdit
    data class Dates(val start: Instant?, val end: Instant?) : TripSettingsEdit
    data class NarrationPace(val value: com.memobook.core.NarrationPace) : TripSettingsEdit
    data class Notifications(val value: Boolean) : TripSettingsEdit

    /** Les quatre alertes, d'un bloc. **Une exception à la règle du réglage
     *  unique**, et elle se justifie : les quatre vivent sur la même feuille,
     *  personne d'autre ne les touche, et les envoyer une par une ferait quatre
     *  requêtes pour quatre bascules qu'on enchaîne au doigt. */
    data class NotificationPreferences(val value: TripNotificationPreferences) : TripSettingsEdit
    data class Theme(val value: String) : TripSettingsEdit
    data class PublicGallery(val value: Boolean) : TripSettingsEdit
}
