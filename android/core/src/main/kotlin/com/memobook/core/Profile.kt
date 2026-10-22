package com.memobook.core

import kotlinx.serialization.KSerializer
import kotlinx.serialization.Required
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.SerializationException
import kotlinx.serialization.builtins.ListSerializer
import kotlinx.serialization.builtins.serializer
import kotlinx.serialization.descriptors.SerialDescriptor
import kotlinx.serialization.descriptors.buildClassSerialDescriptor
import kotlinx.serialization.encoding.Decoder
import kotlinx.serialization.encoding.Encoder
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonDecoder
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonEncoder
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonObjectBuilder
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.jsonObject
import java.math.BigDecimal
import java.time.Instant
import java.time.ZoneId
import java.net.URI

// Ce que l'écran de profil affiche, modélisé comme le back-end le renvoie. Le
// jumeau de `MemoBookCore/Profile.swift`.
//
// Même principe que `HomeFeed` : la vue ne sait rien du contenu, elle ne sait
// que le dessiner. L'écran lit un [TravellerProfile] fourni par une fonction —
// la route, ou le jeu d'essai.

/**
 * L'adresse où le carnet imprimé sera livré.
 *
 * @property country le pays, en code ISO 3166-1 alpha-2 — « FR ». C'est la forme
 *   que la commande exige (`ShippingAddress.country`) et que la base garde : le
 *   profil est l'amorce de l'étape de livraison, il parle la même langue. Il se
 *   choisit dans [TravellerProfile.shippingCountries], jamais en texte libre. Un
 *   profil enregistré avant cette liste peut porter ici ce que la personne avait
 *   tapé (« Monaco ») : le serveur le rend tel quel plutôt que d'inventer un
 *   code, et le menu invite alors à choisir.
 * @property countryName le nom du pays, pour la ligne du profil — « France ».
 *   **Dérivé** par le serveur de la liste de l'imprimeur, jamais saisi ; l'app le
 *   recopie depuis la même liste quand elle pose une adresse avant que le
 *   serveur ait répondu. Vide quand le pays l'est. Décodage tolérant : un
 *   serveur d'avant le 18/09/2026 ne l'envoie pas, et le code fait alors office
 *   de nom plutôt que de faire tomber tout le profil.
 */
@Serializable
data class PostalAddress(
    @Required val street: String = "",
    @Required val postalCode: String = "",
    @Required val city: String = "",
    @Required val country: String = "",
    val countryName: String = country,
) {
    /** Une adresse ne vaut que complète : un colis part avec les quatre lignes ou ne part pas. */
    val isComplete: Boolean get() = missingFields.isEmpty()

    /**
     * Ce qui manque encore, dans l'ordre des champs de la feuille. C'est ce que
     * « Valider » nomme quand on appuie dessus trop tôt.
     */
    val missingFields: List<Field> get() = Field.entries.filter { value(it).isBlank() }

    /** Les quatre lignes, dans l'ordre où la feuille les demande. */
    enum class Field {
        Street,
        PostalCode,
        City,
        Country,
        ;

        /** Le nom de la ligne dans une phrase — « il manque *le code postal* ». */
        val label: String
            get() = when (this) {
                Street -> "l’adresse"
                PostalCode -> "le code postal"
                City -> "la ville"
                Country -> "le pays"
            }
    }

    /**
     * Ce qui manque, en une phrase : « le code postal et la ville ». `null` quand
     * rien ne manque. C'est ce que « Valider » dit quand on appuie dessus trop
     * tôt, au lieu d'avaler le geste.
     */
    val missingFieldsDescription: String?
        get() {
            val labels = missingFields.map { it.label }
            return when (labels.size) {
                0 -> null
                1 -> labels[0]
                else -> labels.dropLast(1).joinToString(", ") + " et " + labels.last()
            }
        }

    private fun value(field: Field): String = when (field) {
        Field.Street -> street
        Field.PostalCode -> postalCode
        Field.City -> city
        Field.Country -> country
    }

    /**
     * L'adresse sur une ligne, pour la ligne du profil : « 7 Rue Simon Fryd,
     * Lyon, France ». Les champs vides sont sautés plutôt que de laisser des
     * virgules orphelines. Le pays y est écrit en toutes lettres, jamais en
     * code : « FR » en bout de ligne se lirait comme une coquille.
     */
    val singleLine: String
        get() = listOf(street, city, countryName).map { it.trim() }.filter { it.isNotEmpty() }.joinToString(", ")
}

/**
 * Une carte enregistrée. **Le numéro complet n'entre jamais dans ce modèle** :
 * l'app n'en garde que les quatre derniers chiffres, le reste appartient au
 * prestataire de paiement.
 *
 * @property label le nom que l'utilisateur donne à sa carte : « Carte perso ».
 */
@Serializable
data class PaymentCard(val id: String, val label: String, val last4: String) {
    /**
     * Le numéro masqué de la maquette. Les X sont ceux du dessin, pas des
     * puces : c'est un gabarit de carte, pas un mot de passe.
     */
    val maskedNumber: String get() = "XXXX XXXX XXXX $last4"

    companion object {
        /**
         * « MM/AA », composé au fil de la frappe.
         *
         * Le champ ne garde que des chiffres et pose la barre lui-même : on tape
         * quatre chiffres, on obtient une date. C'est ce qui permet un pavé
         * **numérique** — un clavier qui porterait la barre oblique porte aussi
         * tout le reste de la ponctuation, et laisse écrire « 1-2/3 ».
         *
         * **La barre s'efface avec le chiffre qui la précède** : elle n'est pas
         * saisie, elle est déduite des deux premiers chiffres. Effacer le
         * troisième chiffre la fait donc disparaître toute seule, plutôt que
         * d'obliger à un second retour arrière sur un caractère qu'on n'a jamais
         * tapé.
         *
         * Elle vit ici, et non dans la feuille qui l'affiche : c'est une règle,
         * elle se teste sans émulateur.
         */
        fun formattedExpiry(raw: String): String {
            val digits = raw.filter { it.isDigit() }.take(4)
            if (digits.length <= 2) return digits
            return "${digits.take(2)}/${digits.drop(2)}"
        }
    }
}

/**
 * Une application tierce que MemoBook peut interroger pour enrichir un carnet.
 *
 * @property promise ce que MemoBook fera de l'accès, en une phrase. C'est le
 *   consentement qui se lit, pas une description marketing.
 * @property logoAssetName nom de l'image embarquée qui porte le logo de la
 *   marque. Provisoire : le jour où l'API sert les connecteurs, elle enverra une
 *   URL et ce champ disparaîtra. En attendant, les six logos vivent dans le
 *   catalogue de marque — ce sont des marques tierces, elles ne se teintent pas
 *   et ne se remplacent pas par une icône MemoBook.
 */
@Serializable
data class Connector(
    val id: String,
    val name: String,
    val promise: String,
    @Required val isEnabled: Boolean = false,
    val logoAssetName: String? = null,
)

/**
 * L'abonnement, tel que les feuilles le présentent.
 *
 * **4,99 € par mois, et l'illimité pour l'abonné seul** (Hugo, 03/10/2026) :
 * sans abonnement, chaque voyage raconte cinq minutes par jour (voir
 * `DailyCredit`) ; abonné, on raconte sans compter. Il ne se coupe pas tout
 * seul — le store le renouvelle —, alors l'app propose de le résilier à la fin
 * du voyage, et c'est pour ça que ce modèle porte le voyage autant que le prix :
 * sans lui, « un rappel à la fin de ton voyage à Rome » n'a rien à écrire.
 *
 * **Une valeur, dont deux champs ont une conséquence.** Sur iOS, retoucher
 * `isActive` ou `paidThrough` sur place (`didSet`) oublie le verdict du serveur.
 * Ici, le constructeur et `copy` sont privés : on construit par
 * [Subscription.invoke] (les paramètres de l'`init` Swift), et on retouche par
 * [updating], qui tient la même règle.
 *
 * @property price ce que l'abonnement coûte par période. En euros, `BigDecimal` : de l'argent.
 * @property interval la période que [price] paie. Le mois, désormais ; la semaine
 *   reste lisible pour les abonnés de l'ancienne formule, honorés jusqu'à
 *   l'expiration de ce qu'ils ont payé — et pour un serveur plus ancien.
 * @property isActive un geste fait dans l'app — souscrire, résilier, le bac à
 *   sable — le retouche sur place : le verdict du serveur ([servedIsUnlimited]),
 *   qui datait d'avant, ne vaut plus, et l'app recompte (03/10/2026).
 * @property tripDestination le voyage qui porte l'abonnement, sous ses deux noms
 *   — les feuilles emploient les deux et ce ne sont pas les mêmes mots. La
 *   destination se glisse dans une phrase (« à la fin de ton voyage à
 *   **Rome** »), le titre ([tripTitle]) se cite entre guillemets (« ton voyage
 *   “**Rome entre amis**” »). Écrire l'un à la place de l'autre donnerait « à la
 *   fin de ton voyage à Rome entre amis ».
 * @property endsOn le dernier jour du voyage qui porte l'abonnement : c'est là
 *   que l'app propose de le résilier. C'est de lui que sort le « dans 3
 *   semaines » de la feuille — jamais d'un nombre écrit à la main quelque part
 *   dans une vue.
 * @property cancelledAt le jour où il a été résilié à la main, s'il l'a été.
 * @property paidThrough **jusqu'où la période payée porte.** La fin du mois déjà
 *   réglé — `subscriptions.renewsAt` côté serveur. C'est ce qui rend vraie la
 *   promesse de la résiliation : un mois commencé est un mois payé, et résilier
 *   au lendemain d'un prélèvement ne doit pas refermer l'illimité des semaines
 *   plus tôt que prévu (Hugo, 16/09/2026, règle tenue au passage au mois le
 *   03/10/2026). L'abonnement passe donc par un **sursis** : `isActive` tombe,
 *   `paidThrough` reste, et l'app comme le serveur laissent raconter sans
 *   compter jusqu'à cette date. `null` quand rien n'a été payé — un compte qui
 *   n'a jamais souscrit —, ou quand un serveur plus ancien ne sert pas le
 *   champ : on retombe alors sur l'arrêt le jour même.
 * @property hasEndedBefore ce compte a **déjà** été abonné, et ne l'est plus.
 *   C'est ce qui décide de la version du paywall : quelqu'un qui revient a déjà
 *   vu les trois écrans de découverte, et on lui en montre deux — voir
 *   `PaywallVariant`. Il se lit sur l'existence d'un abonnement terminé, pas sur
 *   une colonne de plus : le serveur garde l'historique des abonnements d'un
 *   compte (`subscriptions`). L'app propose de résilier à la fin de chaque
 *   voyage : ce drapeau est donc l'état normal de n'importe qui entre deux
 *   voyages, pas celui d'un mécontent.
 * @property managedByAppStore **Apple tient l'abonnement** (01/10/2026) : il a été
 *   acheté par StoreKit. Ça décide de la résiliation : Apple ne laisse aucune app
 *   la faire à la place de son client, donc la feuille enregistre la raison puis
 *   ouvre la gestion des abonnements d'iOS. Faux pour un compte qui n'a rien
 *   souscrit, ou quand un serveur plus ancien ne sert pas le champ. ⚠️ Nom du
 *   contrat iOS gardé tel quel : il deviendra « tenu par un store » (App Store
 *   ou Google Play) avec le paiement Android.
 * @property servedIsUnlimited **ce que le serveur a tranché** :
 *   `subscription.isUnlimited` de `GET /v1/profile`, calculé par
 *   `hasUnlimitedAccess` à l'instant près (`renewsAt > now`, délai de grâce du
 *   store compris). C'est lui que [isUnlimited] lit d'abord (03/10/2026). L'app
 *   recomptait au jour près, et se contredisait avec le serveur le dernier jour
 *   payé ou pendant un délai de grâce de facturation. `null` d'un serveur plus
 *   ancien, ou dès qu'un geste local a retouché [isActive] ou [paidThrough] : le
 *   recalcul local reprend alors la main.
 * @property servedState **où en est l'abonnement, tranché par le serveur** —
 *   `subscription.state` de `GET /v1/profile` (contrat du 06/10/2026, point 11,
 *   « Désabonnement »). C'est la réponse à la remarque de Hugo : « quand
 *   quelqu'un se désabonne, attention à ce que tous les endroits qui
 *   indiquaient “abonné” ne l'indiquent plus ». Jusqu'ici l'app devinait l'état
 *   en croisant `isActive`, `cancelledAt` et `paidThrough` — un renouvellement
 *   coupé chez Apple sans `cancelledAt` se lisait comme un prélèvement raté. Le
 *   serveur le dit désormais en un mot ; `null` d'un serveur plus ancien (ou
 *   d'une valeur inconnue), ou dès qu'un geste local a retouché [isActive] ou
 *   [paidThrough] : le recalcul d'avant reprend la main.
 * @property autoRenews le renouvellement est-il armé — `subscription.autoRenews`.
 *   `null` quand le serveur ne le dit pas.
 * @property renewsAt le prochain prélèvement, pour un abonnement [State.Active].
 * @property endsAt **la fin de l'illimité** d'un abonnement [State.Ending] — la
 *   fin de la période payée, après laquelle le compte retrouve le crédit du
 *   jour. C'est le « jusqu'au … » des écrans.
 */
@ConsistentCopyVisibility
@Serializable(with = Subscription.Serializer::class)
data class Subscription private constructor(
    val price: BigDecimal,
    val interval: Interval,
    val isActive: Boolean,
    val tripDestination: String?,
    val tripTitle: String?,
    val endsOn: Instant?,
    val cancelledAt: Instant?,
    val paidThrough: Instant?,
    val hasEndedBefore: Boolean,
    val managedByAppStore: Boolean,
    val servedIsUnlimited: Boolean?,
    val servedState: State?,
    val autoRenews: Boolean?,
    val renewsAt: Instant?,
    val endsAt: Instant?,
) {
    /** Les cinq états du contrat. */
    @Serializable
    enum class State(val rawValue: String) {
        /** Jamais abonné. */
        @SerialName("none") None("none"),

        /** Abonné, renouvellement armé. */
        @SerialName("active") Active("active"),

        /** **Renouvellement coupé** (ou résilié) : toujours illimité jusqu'à [Subscription.endsAt], puis [Ended]. */
        @SerialName("ending") Ending("ending"),

        /** Le prélèvement a échoué ; le store garde l'accès le temps de réessayer. */
        @SerialName("grace") Grace("grace"),

        /** A été abonné, plus rien ne court. */
        @SerialName("ended") Ended("ended"),
    }

    /** La période qu'un prix paie. */
    @Serializable
    enum class Interval(val rawValue: String) {
        @SerialName("month") Month("month"),
        @SerialName("week") Week("week"),
        ;

        /** Le mot qui suit la barre oblique : le « mois » de « 4,99 €/mois ». */
        val label: String
            get() = when (this) {
                Month -> "mois"
                Week -> "semaine"
            }
    }

    /**
     * Retouche l'abonnement sur place — le `var` d'iOS.
     *
     * **Un geste local vient de retoucher l'abonnement** : si [isActive] ou
     * [paidThrough] changent, ce que le serveur avait tranché avant lui
     * ([servedIsUnlimited], [servedState]) ne vaut plus — le `didSet` d'iOS.
     * Reposer la même valeur ne l'oublie pas.
     */
    fun updating(
        isActive: Boolean = this.isActive,
        tripDestination: String? = this.tripDestination,
        tripTitle: String? = this.tripTitle,
        endsOn: Instant? = this.endsOn,
        cancelledAt: Instant? = this.cancelledAt,
        paidThrough: Instant? = this.paidThrough,
        hasEndedBefore: Boolean = this.hasEndedBefore,
        managedByAppStore: Boolean = this.managedByAppStore,
        autoRenews: Boolean? = this.autoRenews,
        renewsAt: Instant? = this.renewsAt,
        endsAt: Instant? = this.endsAt,
    ): Subscription {
        val forgets = isActive != this.isActive || paidThrough != this.paidThrough
        return copy(
            isActive = isActive,
            tripDestination = tripDestination,
            tripTitle = tripTitle,
            endsOn = endsOn,
            cancelledAt = cancelledAt,
            paidThrough = paidThrough,
            hasEndedBefore = hasEndedBefore,
            managedByAppStore = managedByAppStore,
            servedIsUnlimited = if (forgets) null else servedIsUnlimited,
            servedState = if (forgets) null else servedState,
            autoRenews = autoRenews,
            renewsAt = renewsAt,
            endsAt = endsAt,
        )
    }

    // MARK: Le sursis de la période payée

    /**
     * La période payée court-elle encore, à cette date ?
     *
     * **Strictement après**, et non « à partir de » : une période qui se termine
     * aujourd'hui se termine aujourd'hui. C'est le cas que Hugo a nommément
     * épargné — « si le dernier jour est aujourd'hui, le processus reste celui
     * d'avant » —, et c'est aussi le plus simple à tenir : il n'y a pas de sursis
     * à annoncer pour un jour qui est déjà là.
     */
    fun isWithinPaidPeriod(on: Instant = Instant.now()): Boolean {
        val paidThrough = paidThrough ?: return false
        val zone = ZoneId.systemDefault()
        return paidThrough.atZone(zone).toLocalDate() > on.atZone(zone).toLocalDate()
    }

    /**
     * Le compte raconte-t-il sans limite : abonné, **ou** résilié mais dans sa
     * période payée — **recalculé ici, au jour près**.
     *
     * C'est cette question-là que posent l'app et le serveur, jamais `isActive`
     * seul. Le serveur y répond à l'instant près (`hasUnlimitedAccess`,
     * `services/subscriptions.ts` : `renewsAt > now`) ; ce recalcul-ci compare
     * des jours, et ne sert qu'à défaut de sa réponse — voir [isUnlimited].
     * Passer à l'instant près est une règle à demander à Hugo, qui a voulu le
     * jour (16/09/2026).
     */
    fun grantsAccess(on: Instant = Instant.now()): Boolean = isActive || isWithinPaidPeriod(on)

    /**
     * Le compte raconte-t-il sans limite : **le verdict du serveur quand il l'a
     * servi** ([servedIsUnlimited]), sinon [grantsAccess].
     *
     * Le recalcul ne reprend la main que d'un serveur plus ancien, ou quand un
     * achat, une résiliation ou le bac à sable ont retouché [isActive] ou
     * [paidThrough] sur place : la réponse doit alors suivre le geste sans
     * attendre une relecture (03/10/2026).
     */
    val isUnlimited: Boolean get() = isUnlimited(at = Instant.now())

    /**
     * Le même, à un instant donné.
     *
     * **Un « oui » servi se périme avec la période qu'il couvrait**
     * (03/10/2026). Le verdict voyage dans le cache du profil : reçu le 1er pour
     * un mois résilié payé jusqu'au 5, il disait encore « illimité » le 7 dans
     * l'avion — pastille « Abonné(e) », « Résilier mon abonnement », et une
     * session qui l'apprenait. On ne le croit donc que tant qu'il tient avec la
     * date : abonnement vivant, ou fin de période encore à venir (`renewsAt >
     * now`, la règle du serveur, à l'instant près — le dernier jour payé reste
     * ouvert jusqu'à son heure). Sans date servie — le délai de grâce du store,
     * qui n'en annonce pas toujours —, il tient. Un « non » servi reste un non.
     */
    fun isUnlimited(at: Instant): Boolean {
        // **L'état du serveur d'abord** (contrat du 06/10/2026) : il dit en un
        // mot ce que les drapeaux laissaient deviner, et un « renouvellement
        // coupé » s'éteint de lui-même à sa date, même lu dans le cache.
        if (servedState != null) {
            return when (servedState) {
                // Le serveur borne lui-même ces deux-là (trois jours sans
                // nouvelles du store après l'échéance) : son verdict fait foi.
                State.Active, State.Grace -> servedIsUnlimited ?: true
                State.Ending -> (endsAt ?: paidThrough)?.let { it > at } ?: (servedIsUnlimited ?: true)
                State.None, State.Ended -> false
            }
        }
        val served = servedIsUnlimited ?: return grantsAccess(at)
        return served && (isActive || (paidThrough?.let { it > at } ?: true))
    }

    /**
     * **Le renouvellement est coupé, et l'illimité court encore** : la date où
     * il s'arrête, pour écrire « jusqu'au … ». `null` pour un abonnement qui se
     * renouvelle, pour un compte sans abonnement, une fois la date passée — ou
     * quand on ne la connaît pas.
     *
     * L'état du serveur quand il l'a dit ([State.Ending] et [endsAt]) ; sinon la
     * lecture d'avant : résilié (`cancelledAt`), plus actif, une période payée
     * devant soi.
     */
    fun unlimitedUntil(at: Instant = Instant.now()): Instant? {
        if (servedState != null) {
            val end = endsAt ?: paidThrough
            if (servedState != State.Ending || end == null || end <= at) return null
            return end
        }
        val paidThrough = paidThrough
        if (isActive || cancelledAt == null || paidThrough == null || paidThrough <= at) return null
        return paidThrough
    }

    /**
     * **Le dernier prélèvement n'est pas passé** et le store réessaie : ni actif
     * au sens du renouvellement réussi, ni résilié.
     *
     * L'état du serveur quand il l'a dit ([State.Grace]). Sinon la lecture
     * d'avant : plus actif, rien de résilié.
     */
    val isInBillingRetry: Boolean
        get() = if (servedState != null) servedState == State.Grace else !isActive && cancelledAt == null

    /**
     * **Résilié, ou renouvellement coupé** — la feuille « Mon Abonnement »
     * propose alors de se réabonner au lieu de résilier une seconde fois.
     */
    val isCancelled: Boolean
        get() = if (servedState != null) {
            servedState == State.Ending || servedState == State.Ended
        } else {
            !isActive && cancelledAt != null
        }

    /**
     * Le jour où le sursis s'arrête, quand il y en a un à annoncer. `null` quand
     * l'abonnement est encore actif, ou quand la période payée se termine
     * aujourd'hui ou est déjà passée.
     */
    fun graceEnd(on: Instant = Instant.now()): Instant? {
        if (isActive || !isWithinPaidPeriod(on)) return null
        return paidThrough
    }

    // MARK: Le prix à écrire

    /**
     * Le prix à **écrire**, qui n'est jamais zéro.
     *
     * ⚠️ Un abonnement à zéro euro n'existe pas : c'est la marque d'un serveur
     * qui n'a pas de ligne à lire — l'ancien comportement de `GET /v1/profile`.
     * L'app affichait alors « 0,00 € » sur la feuille d'offre (Hugo,
     * 16/09/2026). On retombe sur le tarif de l'offre, et sur sa période.
     */
    val displayedPrice: BigDecimal get() = if (price.signum() > 0) price else offer.price

    /** La période qui va avec [displayedPrice] : « mois », ou « semaine » pour un abonné de l'ancienne formule. */
    val periodLabel: String get() = paidInterval.label

    /**
     * La période que l'abonné a payée — celle des phrases de la résiliation et
     * de l'alerte de fin : un ancien abonné à la semaine n'a pas payé un mois
     * (03/10/2026). Le mois de l'offre quand il n'y a pas de prix à lire.
     */
    val paidInterval: Interval get() = if (price.signum() > 0) interval else offer.interval

    /**
     * Le prix de **ce que le paywall vend** — le mois —, quand le store ne l'a
     * pas encore dit.
     *
     * Distinct de [displayedPrice] : un ancien abonné à la semaine garde son
     * ancien tarif dans « Mon abonnement », mais l'offre qu'on lui présente est
     * la mensuelle. On ne lit donc le prix servi que s'il est mensuel.
     */
    val offeredPrice: BigDecimal
        get() = if (interval == Interval.Month && price.signum() > 0) price else offer.price

    companion object {
        /** Les paramètres de l'`init` d'iOS, avec ses valeurs par défaut. */
        operator fun invoke(
            price: BigDecimal,
            interval: Interval = Interval.Month,
            isActive: Boolean = false,
            tripDestination: String? = null,
            tripTitle: String? = null,
            endsOn: Instant? = null,
            cancelledAt: Instant? = null,
            paidThrough: Instant? = null,
            hasEndedBefore: Boolean = false,
            managedByAppStore: Boolean = false,
            servedIsUnlimited: Boolean? = null,
            servedState: State? = null,
            autoRenews: Boolean? = null,
            renewsAt: Instant? = null,
            endsAt: Instant? = null,
        ): Subscription = Subscription(
            price, interval, isActive, tripDestination, tripTitle, endsOn, cancelledAt, paidThrough,
            hasEndedBefore, managedByAppStore, servedIsUnlimited, servedState, autoRenews, renewsAt, endsAt,
        )

        /**
         * **L'offre**, telle que le paywall la présente quand le store n'a pas
         * encore rendu la sienne : 4,99 € par mois, le prix du catalogue serveur
         * (`SUBSCRIPTION_MONTHLY_CENTS`, `backend/src/services/subscriptionCatalog.ts`)
         * et du produit `com.memobook.app.subscription.monthly`.
         *
         * C'est le filet, pas la vérité : le paywall écrit le prix et la période
         * que le store déclare dès qu'il les a (règle 3.1.2 de l'App Store —
         * l'écran d'achat et la feuille du store ne doivent pas dire deux prix).
         */
        val offer: Subscription = invoke(price = BigDecimal("4.99"), interval = Interval.Month)
    }

    /**
     * Décodage tolérant : un serveur qui ne sert pas encore un drapeau fait voir
     * la version de découverte du paywall, jamais un écran vide.
     *
     * **Le prix** se lit sur `price`, sinon sur l'ancien `weeklyPrice` — et la
     * période avec lui : un serveur qui ne connaît que `weeklyPrice` ne vend que
     * la semaine. `weeklyPrice` est lu seulement : le serveur d'aujourd'hui le
     * remplit encore du même prix, pour les apps installées qui le décodent en
     * obligatoire.
     */
    object Serializer : KSerializer<Subscription> {
        override val descriptor: SerialDescriptor = buildClassSerialDescriptor("com.memobook.core.Subscription")

        override fun deserialize(decoder: Decoder): Subscription {
            val (json, fields) = decoder.jsonObject()
            val price = json.optional(fields, "price", BigDecimalSerializer)
            return Subscription(
                price = price ?: json.required(fields, "weeklyPrice", BigDecimalSerializer),
                interval = if (price != null) {
                    json.lenient(fields, "interval", Interval.serializer()) ?: Interval.Month
                } else {
                    Interval.Week
                },
                isActive = json.required(fields, "isActive", Boolean.serializer()),
                tripDestination = json.optional(fields, "tripDestination", String.serializer()),
                tripTitle = json.optional(fields, "tripTitle", String.serializer()),
                endsOn = json.optional(fields, "endsOn", InstantSerializer),
                cancelledAt = json.optional(fields, "cancelledAt", InstantSerializer),
                paidThrough = json.optional(fields, "paidThrough", InstantSerializer),
                hasEndedBefore = json.optional(fields, "hasEndedBefore", Boolean.serializer()) ?: false,
                managedByAppStore = json.optional(fields, "managedByAppStore", Boolean.serializer()) ?: false,
                servedIsUnlimited = json.optional(fields, "isUnlimited", Boolean.serializer()),
                // Une valeur que cette version ne connaît pas ne fait pas tomber
                // le profil : le recalcul d'avant répond à sa place.
                servedState = json.lenient(fields, "state", State.serializer()),
                autoRenews = json.optional(fields, "autoRenews", Boolean.serializer()),
                renewsAt = json.optional(fields, "renewsAt", InstantSerializer),
                endsAt = json.optional(fields, "endsAt", InstantSerializer),
            )
        }

        override fun serialize(encoder: Encoder, value: Subscription) {
            encoder.encodeJsonObject { json ->
                put(json, "price", value.price, BigDecimalSerializer)
                put(json, "interval", value.interval, Interval.serializer())
                put(json, "isActive", value.isActive, Boolean.serializer())
                put(json, "tripDestination", value.tripDestination, String.serializer())
                put(json, "tripTitle", value.tripTitle, String.serializer())
                put(json, "endsOn", value.endsOn, InstantSerializer)
                put(json, "cancelledAt", value.cancelledAt, InstantSerializer)
                put(json, "paidThrough", value.paidThrough, InstantSerializer)
                put(json, "hasEndedBefore", value.hasEndedBefore, Boolean.serializer())
                put(json, "managedByAppStore", value.managedByAppStore, Boolean.serializer())
                put(json, "isUnlimited", value.servedIsUnlimited, Boolean.serializer())
                put(json, "state", value.servedState, State.serializer())
                put(json, "autoRenews", value.autoRenews, Boolean.serializer())
                put(json, "renewsAt", value.renewsAt, InstantSerializer)
                put(json, "endsAt", value.endsAt, InstantSerializer)
            }
        }
    }
}

/**
 * Le prix de l'offre, pour les écrans qui n'ont pas d'abonnement sous la main —
 * le paywall ouvert depuis l'accueil ou la conversation.
 */
val Subscription?.offeredPrice: BigDecimal
    get() = this?.offeredPrice ?: Subscription.offer.price

/**
 * Pourquoi on s'en va. Les quatre raisons de la maquette, dans son ordre.
 *
 * Une énumération et non une chaîne libre : la réponse part vers un compteur
 * côté serveur, et un compteur ne sait rien faire de quatre orthographes de la
 * même raison.
 */
@Serializable
enum class SubscriptionCancellationReason(val rawValue: String) {
    @SerialName("unused") Unused("unused"),
    @SerialName("tooExpensive") TooExpensive("tooExpensive"),
    @SerialName("storiesFinished") StoriesFinished("storiesFinished"),
    @SerialName("wasTesting") WasTesting("wasTesting"),
    ;

    val id: String get() = rawValue

    /**
     * Figma les saisit avec l'apostrophe droite, alors que le reste de l'app
     * emploie la typographique ; elles sont corrigées ici comme le reste de la
     * copie de l'abonnement (D12, T66).
     */
    val label: String
        get() = when (this) {
            Unused -> "Je ne l’utilise plus"
            TooExpensive -> "C’est un peu cher"
            StoriesFinished -> "J’ai fini mes récits"
            WasTesting -> "C’était pour tester"
        }
}

/**
 * Une commande d'impression du compte : en cours d'acheminement, ou laissée au
 * moment de payer.
 *
 * Décodage tolérant : un serveur d'avant le 06/10/2026 ne dit ni l'état ni le
 * carnet — ses commandes sont alors toutes en route, comme il les montrait. Un
 * état inconnu d'un serveur plus récent aussi : mieux vaut une carte de
 * livraison qu'un profil qui ne s'affiche plus.
 *
 * @property minimumDays fourchette de livraison, en jours, avec [maximumDays].
 *   Deux bornes plutôt qu'une date : un imprimeur annonce un délai, pas un rendez-vous.
 * @property memoId le carnet commandé. `null` sur un serveur d'avant le 06/10/2026.
 * @property total le net à payer, figé à la commande. `null` sur une commande
 *   d'avant la tarification — « pas de montant à afficher », jamais zéro.
 */
@Serializable(with = OrderTracking.Serializer::class)
data class OrderTracking(
    val id: String,
    val status: Status = Status.InProgress,
    val minimumDays: Int,
    val maximumDays: Int,
    val copies: Int,
    val pageCount: Int,
    val coverImageUrl: URI? = null,
    val memoId: String? = null,
    val tripTitle: String? = null,
    val total: BigDecimal? = null,
    val createdAt: Instant? = null,
) {
    /**
     * Où en est la commande, pour la feuille « Suivi des commandes ».
     *
     * **Une commande au paiement abandonné n'est pas en route** (T232,
     * 06/10/2026) : la feuille la listait comme si elle allait partir. Elle
     * porte désormais son étiquette et de quoi la finaliser. Le serveur n'en
     * rend qu'une par voyage — la dernière —, et seulement pendant 30 jours.
     */
    @Serializable
    enum class Status(val rawValue: String) {
        /** Payée, en cours d'impression ou d'acheminement. */
        @SerialName("in_progress") InProgress("in_progress"),

        /** Jamais payée : brouillon, ou fermée par le ménage des 24 h. */
        @SerialName("payment_abandoned") PaymentAbandoned("payment_abandoned"),
    }

    /**
     * Le paiement a-t-il été laissé en route ? C'est ce qui remplace le délai
     * par l'étiquette et « Finaliser ma commande ».
     */
    val isPaymentAbandoned: Boolean get() = status == Status.PaymentAbandoned

    object Serializer : KSerializer<OrderTracking> {
        override val descriptor: SerialDescriptor = buildClassSerialDescriptor("com.memobook.core.OrderTracking")

        override fun deserialize(decoder: Decoder): OrderTracking {
            val (json, fields) = decoder.jsonObject()
            return OrderTracking(
                id = json.required(fields, "id", String.serializer()),
                status = json.lenient(fields, "status", Status.serializer()) ?: Status.InProgress,
                minimumDays = json.required(fields, "minimumDays", Int.serializer()),
                maximumDays = json.required(fields, "maximumDays", Int.serializer()),
                copies = json.required(fields, "copies", Int.serializer()),
                pageCount = json.required(fields, "pageCount", Int.serializer()),
                coverImageUrl = json.optional(fields, "coverImageUrl", UriSerializer),
                memoId = json.optional(fields, "memoId", String.serializer()),
                tripTitle = json.optional(fields, "tripTitle", String.serializer()),
                total = json.optional(fields, "total", BigDecimalSerializer),
                createdAt = json.lenient(fields, "createdAt", InstantSerializer),
            )
        }

        override fun serialize(encoder: Encoder, value: OrderTracking) {
            encoder.encodeJsonObject { json ->
                put(json, "id", value.id, String.serializer())
                put(json, "status", value.status, Status.serializer())
                put(json, "minimumDays", value.minimumDays, Int.serializer())
                put(json, "maximumDays", value.maximumDays, Int.serializer())
                put(json, "copies", value.copies, Int.serializer())
                put(json, "pageCount", value.pageCount, Int.serializer())
                put(json, "coverImageUrl", value.coverImageUrl, UriSerializer)
                put(json, "memoId", value.memoId, String.serializer())
                put(json, "tripTitle", value.tripTitle, String.serializer())
                put(json, "total", value.total, BigDecimalSerializer)
                put(json, "createdAt", value.createdAt, InstantSerializer)
            }
        }
    }
}

/**
 * Le voyage en cours, tel que la carte de chiffres du profil le montre : un
 * identifiant pour y aller, et ses bornes pour l'annoncer.
 *
 * **Il n'est pas stocké.** Le serveur le déduit des voyages du compte — voir
 * `serializeProfileStats`. C'est un résumé, pas une seconde vérité à tenir à
 * jour à côté de [Trip].
 */
@Serializable
data class CurrentTrip(
    val id: String,
    @Serializable(with = InstantSerializer::class) val startDate: Instant? = null,
    @Serializable(with = InstantSerializer::class) val endDate: Instant? = null,
)

/**
 * Le genre de la personne, tel que le profil le montre et que la feuille
 * d'abonnement l'accorde (« Abonnée » / « Abonné »).
 *
 * **Le serveur le devine sur le prénom** tant que la personne n'a rien dit, et
 * c'est la ligne « Genre » du profil qui permet de corriger — femme, homme, ou
 * « je ne préfère pas répondre » (Hugo, 17/09/2026, T76). Le troisième cas est
 * un choix, pas une absence : l'app accorde alors sur la forme non marquée,
 * comme elle le faisait pour tout le monde.
 */
@Serializable
enum class Gender(val rawValue: String) {
    @SerialName("female") Female("female"),
    @SerialName("male") Male("male"),
    @SerialName("undisclosed") Undisclosed("undisclosed"),
    ;

    /** Le libellé de la ligne et de la feuille — les trois options de la demande, mot pour mot. */
    val label: String
        get() = when (this) {
            Female -> "Femme"
            Male -> "Homme"
            Undisclosed -> "Je ne préfère pas répondre"
        }

    /** Accorde un participe en `-é` : « Abonné » ou « Abonnée ». La forme non marquée quand on ne sait pas. */
    fun agreed(masculine: String): String = if (this == Female) masculine + "e" else masculine
}

/**
 * Les notifications **du compte** — celles qui ne parlent d'aucun voyage —, la
 * feuille « Notifications » du profil (D13, Hugo, 19/10/2026).
 *
 * Celles d'un voyage sont dans `TripNotificationPreferences`, réglées voyage par
 * voyage et pour soi seul. Celles-ci n'avaient aucun interrupteur : seul le
 * réglage du téléphone les coupait, et lui coupe tout.
 *
 * Décodage tolérant, comme les alertes d'un voyage : un serveur qui ne les sert
 * pas encore rend tout allumé, ce qui est le défaut de la base.
 *
 * @property renewalReminder « Rappel de renouvellement » — trois jours avant que
 *   l'abonnement reparte, quand aucun voyage ne court.
 * @property schoolHolidays « Vacances scolaires » — une semaine avant, puis le jour même.
 * @property learnedPeriod « L’an dernier à la même époque » — la période d'un voyage passé revient.
 * @property birthday « Anniversaire » — une semaine avant.
 */
@Serializable
data class AccountNotificationPreferences(
    val renewalReminder: Boolean = true,
    val schoolHolidays: Boolean = true,
    val learnedPeriod: Boolean = true,
    val birthday: Boolean = true,
)

/**
 * Tout ce que l'écran de profil montre, d'un seul tenant.
 *
 * Décodage tolérant sur les champs ajoutés au fil des versions — le
 * fournisseur, la date de naissance, le genre, la liste des pays, les chiffres.
 * Même raison que `Entry` : une app déjà installée ne doit pas cesser d'afficher
 * un profil parce qu'un serveur plus ancien ne connaît pas encore `tripCount`.
 * Le reste garde la synthèse.
 *
 * @property signInProvider par quel fournisseur la session a été ouverte, quand
 *   ce n'est pas par mot de passe. Il décide d'une chose et d'une seule :
 *   **l'adresse ne se corrige pas**. Elle appartient au compte Apple ou Google,
 *   et la changer ici ne ferait que la désaccorder de celle avec laquelle on se
 *   reconnecte.
 * @property hasPassword le compte a un mot de passe à lui — entré par e-mail, ou
 *   l'ayant posé depuis. C'est ce qui décide si la ligne « Mot de passe » du
 *   profil existe : un compte Apple ou Google seul n'a rien à changer ici (Hugo,
 *   29/09/2026). Vrai par défaut ; un serveur qui ne le dit pas encore le laisse
 *   déduire du fournisseur.
 * @property birthDate la date de naissance, demandée à la fin de l'onboarding.
 *   Un jour, pas un instant — voir [CalendarDay].
 * @property gender voir [Gender] : deviné par le serveur, corrigé depuis le profil.
 * @property shippingCountries les pays où l'imprimeur livre, servis avec le
 *   profil pour que la feuille « Adresse postale » y choisisse le sien sans
 *   second appel. La même liste que celle du tunnel de commande ([OrderContext.countries]).
 * @property notifications les notifications du compte — la ligne « Notifications » du profil.
 * @property tripCount combien de voyages en tout. La carte de chiffres
 *   l'affiche, et c'est tout ce qu'elle en fait.
 * @property currentTrip le voyage du moment, s'il y en a un.
 */
@Serializable(with = TravellerProfile.Serializer::class)
data class TravellerProfile(
    val fullName: String,
    val email: String? = null,
    val signInProvider: AuthProvider? = null,
    val hasPassword: Boolean = true,
    val phoneNumber: String? = null,
    val birthDate: CalendarDay? = null,
    val gender: Gender = Gender.Undisclosed,
    val avatarUrl: URI? = null,
    val address: PostalAddress = PostalAddress(),
    val shippingCountries: List<ShippingCountry> = emptyList(),
    val wantsNewsletter: Boolean = false,
    val notifications: AccountNotificationPreferences = AccountNotificationPreferences(),
    val cards: List<PaymentCard> = emptyList(),
    val selectedCardId: String? = null,
    val connectors: List<Connector> = emptyList(),
    val subscription: Subscription = Subscription(price = BigDecimal.ZERO),
    val orders: List<OrderTracking> = emptyList(),
    val tripCount: Int = 0,
    val currentTrip: CurrentTrip? = null,
) {
    /**
     * La carte affichée sur la ligne « Carte bancaire enregistrée ». Celle qui
     * est sélectionnée, ou la première à défaut : la ligne ne reste pas vide
     * parce qu'aucun choix n'a encore été fait.
     */
    val selectedCard: PaymentCard? get() = cards.firstOrNull { it.id == selectedCardId } ?: cards.firstOrNull()

    /** `true` quand l'adresse e-mail vient d'un fournisseur tiers et ne peut donc pas être corrigée depuis l'app. */
    val isEmailManagedByProvider: Boolean get() = signInProvider != null

    /** Le pays livrable que désigne ce code — ou ce nom, pour une adresse d'avant la liste —, s'il est dans la liste. */
    fun shippingCountry(code: String): ShippingCountry? = shippingCountries.matching(code)

    /**
     * **La** question qui départage les deux profils de la maquette : celui qui
     * raconte sans compter, et celui qui raconte dans le crédit du jour.
     *
     * **La période payée compte.** Quelqu'un qui vient de résilier garde l'écran
     * d'un abonné jusqu'au bout de ce qu'il a réglé : lui remontrer l'offre le
     * jour du geste, alors qu'il a encore des semaines ouvertes, reviendrait à
     * lui vendre ce qu'il possède déjà.
     *
     * **Le serveur tranche quand il l'a dit** ([Subscription.isUnlimited]) : le
     * dernier jour payé, ou pendant le délai de grâce du store, le profil ne
     * contredit plus la conversation (03/10/2026).
     */
    val isSubscriber: Boolean get() = subscription.isUnlimited

    /** Une ou deux initiales, quand la photo manque. Même règle que `Companion`. */
    val initials: String
        get() = fullName.split(' ').filter { it.isNotEmpty() }.take(2)
            .map { it.first().toString() }.joinToString("").uppercase()

    object Serializer : KSerializer<TravellerProfile> {
        override val descriptor: SerialDescriptor = buildClassSerialDescriptor("com.memobook.core.TravellerProfile")

        override fun deserialize(decoder: Decoder): TravellerProfile {
            val (json, fields) = decoder.jsonObject()
            val signInProvider = json.optional(fields, "signInProvider", AuthProvider.serializer())
            return TravellerProfile(
                fullName = json.required(fields, "fullName", String.serializer()),
                email = json.optional(fields, "email", String.serializer()),
                signInProvider = signInProvider,
                // Un serveur d'avant ne le dit pas : un compte sans fournisseur
                // est alors entré par mot de passe.
                hasPassword = json.optional(fields, "hasPassword", Boolean.serializer()) ?: (signInProvider == null),
                phoneNumber = json.optional(fields, "phoneNumber", String.serializer()),
                // Un serveur d'avant la date de naissance ne la rend pas, et une
                // valeur illisible ne doit pas emporter le profil entier.
                birthDate = json.lenient(fields, "birthDate", CalendarDay.serializer()),
                // Un serveur d'avant le genre ne le rend pas : on n'accorde alors rien.
                gender = json.optional(fields, "gender", Gender.serializer()) ?: Gender.Undisclosed,
                avatarUrl = json.optional(fields, "avatarUrl", UriSerializer),
                address = json.required(fields, "address", PostalAddress.serializer()),
                // Absente d'un serveur plus ancien : la feuille n'a alors pas de
                // menu, pas le profil entier qui disparaît.
                shippingCountries = json.optional(fields, "shippingCountries", ListSerializer(ShippingCountry.serializer()))
                    ?: emptyList(),
                wantsNewsletter = json.required(fields, "wantsNewsletter", Boolean.serializer()),
                // Absentes d'un serveur d'avant D13 : tout allumé, comme la base.
                notifications = json.optional(fields, "notifications", AccountNotificationPreferences.serializer())
                    ?: AccountNotificationPreferences(),
                cards = json.required(fields, "cards", ListSerializer(PaymentCard.serializer())),
                selectedCardId = json.optional(fields, "selectedCardId", String.serializer()),
                connectors = json.required(fields, "connectors", ListSerializer(Connector.serializer())),
                subscription = json.required(fields, "subscription", Subscription.serializer()),
                orders = json.required(fields, "orders", ListSerializer(OrderTracking.serializer())),
                tripCount = json.optional(fields, "tripCount", Int.serializer()) ?: 0,
                currentTrip = json.optional(fields, "currentTrip", CurrentTrip.serializer()),
            )
        }

        override fun serialize(encoder: Encoder, value: TravellerProfile) {
            encoder.encodeJsonObject { json ->
                put(json, "fullName", value.fullName, String.serializer())
                put(json, "email", value.email, String.serializer())
                put(json, "signInProvider", value.signInProvider, AuthProvider.serializer())
                put(json, "hasPassword", value.hasPassword, Boolean.serializer())
                put(json, "phoneNumber", value.phoneNumber, String.serializer())
                put(json, "birthDate", value.birthDate, CalendarDay.serializer())
                put(json, "gender", value.gender, Gender.serializer())
                put(json, "avatarUrl", value.avatarUrl, UriSerializer)
                put(json, "address", value.address, PostalAddress.serializer())
                put(json, "shippingCountries", value.shippingCountries, ListSerializer(ShippingCountry.serializer()))
                put(json, "wantsNewsletter", value.wantsNewsletter, Boolean.serializer())
                put(json, "notifications", value.notifications, AccountNotificationPreferences.serializer())
                put(json, "cards", value.cards, ListSerializer(PaymentCard.serializer()))
                put(json, "selectedCardId", value.selectedCardId, String.serializer())
                put(json, "connectors", value.connectors, ListSerializer(Connector.serializer()))
                put(json, "subscription", value.subscription, Subscription.serializer())
                put(json, "orders", value.orders, ListSerializer(OrderTracking.serializer()))
                put(json, "tripCount", value.tripCount, Int.serializer())
                put(json, "currentTrip", value.currentTrip, CurrentTrip.serializer())
            }
        }
    }
}

/**
 * Ce qu'on corrige depuis l'écran de profil, envoyé en `PATCH`.
 *
 * Même construction que `EntryEdit`, et pour la même raison : le double
 * optionnel d'iOS (`String??`) distingue trois cas que le serveur traite
 * différemment. Il s'écrit ici `Some<T?>?` ([Some]) : une valeur remplace,
 * `Some(null)` efface (la clé vaut `null`), et `null` ne touche à rien (la clé
 * est absente). « Pas de téléphone » et « un téléphone vide »
 * ne sont pas la même chose.
 *
 * @property gender un simple optionnel : le genre ne s'efface pas, il se choisit.
 * @property notifications les quatre notifications du compte, d'un bloc — c'est
 *   le bloc entier que la route accepte, comme les alertes d'un voyage.
 */
@Serializable(with = ProfileEdit.Serializer::class)
data class ProfileEdit(
    val firstName: Some<String?>? = null,
    val lastName: Some<String?>? = null,
    val phoneNumber: Some<String?>? = null,
    val birthDate: Some<CalendarDay?>? = null,
    val gender: Gender? = null,
    val wantsNewsletter: Boolean? = null,
    val notifications: AccountNotificationPreferences? = null,
    val address: PostalAddress? = null,
) {
    /** Écrit seulement — le `Encodable` d'iOS. */
    object Serializer : KSerializer<ProfileEdit> {
        override val descriptor: SerialDescriptor = buildClassSerialDescriptor("com.memobook.core.ProfileEdit")

        override fun deserialize(decoder: Decoder): ProfileEdit =
            throw SerializationException("ProfileEdit ne se lit pas : il ne fait que partir au serveur.")

        override fun serialize(encoder: Encoder, value: ProfileEdit) {
            encoder.encodeJsonObject { json ->
                patch(json, "firstName", value.firstName, String.serializer())
                patch(json, "lastName", value.lastName, String.serializer())
                patch(json, "phoneNumber", value.phoneNumber, String.serializer())
                patch(json, "birthDate", value.birthDate, CalendarDay.serializer())
                put(json, "gender", value.gender, Gender.serializer())
                put(json, "wantsNewsletter", value.wantsNewsletter, Boolean.serializer())
                put(json, "notifications", value.notifications, AccountNotificationPreferences.serializer())
                put(json, "address", value.address, PostalAddress.serializer())
            }
        }
    }
}

// MARK: - Le JSON écrit à la main
//
// Les `init(from:)` d'iOS qui tolèrent un champ absent, une valeur inconnue ou
// un champ illisible se portent champ par champ : ces quelques fonctions sont
// les `decode`, `decodeIfPresent` et `try?` de `KeyedDecodingContainer`.

private fun Decoder.jsonObject(): Pair<Json, JsonObject> {
    val json = this as? JsonDecoder ?: throw SerializationException("Le profil ne se lit qu'en JSON")
    return json.json to json.decodeJsonElement().jsonObject
}

private fun JsonObject.present(key: String): JsonElement? = this[key]?.takeUnless { it is JsonNull }

/** `decode` : le champ doit être là, et lisible. */
private fun <T> Json.required(fields: JsonObject, key: String, serializer: KSerializer<T>): T =
    decodeFromJsonElement(serializer, fields[key] ?: throw SerializationException("Champ manquant : $key"))

/** `decodeIfPresent` : absent ou `null` donne `null`, illisible échoue. */
private fun <T> Json.optional(fields: JsonObject, key: String, serializer: KSerializer<T>): T? =
    fields.present(key)?.let { decodeFromJsonElement(serializer, it) }

/** `try? decodeIfPresent` : tout ce qui ne se lit pas donne `null`. */
private fun <T> Json.lenient(fields: JsonObject, key: String, serializer: KSerializer<T>): T? =
    runCatching { optional(fields, key, serializer) }.getOrNull()

private fun Encoder.encodeJsonObject(build: JsonObjectBuilder.(Json) -> Unit) {
    val json = this as? JsonEncoder ?: throw SerializationException("Le profil ne s'écrit qu'en JSON")
    json.encodeJsonElement(buildJsonObject { build(json.json) })
}

/** `encodeIfPresent` : une valeur nulle n'écrit pas sa clé. */
private fun <T : Any> JsonObjectBuilder.put(json: Json, key: String, value: T?, serializer: KSerializer<T>) {
    if (value != null) put(key, json.encodeToJsonElement(serializer, value))
}

/** Le double optionnel : absent ne s'écrit pas, vide s'écrit `null`. */
private fun <T : Any> JsonObjectBuilder.patch(json: Json, key: String, value: Some<T?>?, serializer: KSerializer<T>) {
    if (value == null) return
    put(key, value.value?.let { json.encodeToJsonElement(serializer, it) } ?: JsonNull)
}
