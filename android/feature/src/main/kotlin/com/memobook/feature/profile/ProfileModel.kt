package com.memobook.feature.profile

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.memobook.core.AccountNotificationPreferences
import com.memobook.core.DataExportReceipt
import com.memobook.core.Gender
import com.memobook.core.PostalAddress
import com.memobook.core.ProfileEdit
import com.memobook.core.Some
import com.memobook.core.SubscriptionCancellationReason
import com.memobook.core.TravellerProfile
import com.memobook.feature.CachedValue
import com.memobook.feature.ContentFreshness
import com.memobook.feature.SandboxPersona
import com.memobook.feature.SubscriptionSession
import com.memobook.feature.contentFreshness
import com.memobook.networking.ApiError
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import java.time.Instant
import kotlin.time.Duration
import kotlin.time.Duration.Companion.seconds

/**
 * Ce que l'écran de profil sait faire : charger le profil, et enregistrer ce
 * qu'on y change. Jumeau de `Profile/ProfileModel.swift`.
 *
 * Même construction que `HomeModel` : le modèle ne connaît pas l'API, il
 * reçoit **deux fonctions** — une qui lit, une qui écrit. L'app leur branche
 * `GET` et `PATCH /v1/profile` ; les aperçus n'en fournissent aucune et
 * travaillent alors en mémoire, sans serveur.
 *
 * **Une correction part au serveur dès qu'elle est faite**, ligne par ligne,
 * et la réponse — le profil entier relu — remplace ce qui est à l'écran. Pas
 * de bouton « Enregistrer » : c'est le contrat des lignes des Réglages, et
 * c'est perdre le focus qui vaut validation. La ligne le dit ensuite avec une
 * coche, sans quoi rien ne distinguerait une correction partie d'une
 * correction oubliée.
 *
 * @param source d'où vient le profil. Par défaut, le jeu d'essai.
 * @param persist où partent les corrections. `null` — le cas des aperçus —
 *   les garde en mémoire.
 * @param remove comment supprimer le compte. `null` en aperçu : on ne
 *   supprime pas un compte depuis une maquette.
 * @param uploadAvatar envoie la photo de profil. `null` en aperçu : la photo
 *   reste sur place.
 * @param deleteAvatar retire la photo de profil. `null` en aperçu.
 * @param changePassword change le mot de passe — pour la feuille « Modifier
 *   mon mot de passe » (Hugo, 29/09/2026) ; `null` en aperçu, où la feuille
 *   joue la réussite.
 * @param requestPasswordReset envoie l'e-mail de « mot de passe oublié », pour
 *   la même feuille.
 * @param cancelSubscription ferme l'abonnement côté serveur. `null` en aperçu.
 * @param exportData demande le lien d'export des données. `null` en aperçu :
 *   la feuille joue la réussite.
 * @param cached ce qu'on avait sur le disque — voir `ContentCache`. `null` en aperçu.
 * @param confirmationDelay combien de temps la coche reste allumée — voir
 *   [confirm]. Un test le raccourcit.
 */
class ProfileModel(
    private val source: suspend () -> TravellerProfile = { TravellerProfile.fixture },
    private val persist: (suspend (ProfileEdit) -> TravellerProfile)? = null,
    private val remove: (suspend () -> Unit)? = null,
    private val uploadAvatar: (suspend (ByteArray, String) -> TravellerProfile)? = null,
    private val deleteAvatar: (suspend () -> TravellerProfile)? = null,
    val changePassword: (suspend (String, String) -> Unit)? = null,
    val requestPasswordReset: (suspend (String) -> Unit)? = null,
    cancelSubscription: (suspend (SubscriptionCancellationReason?) -> TravellerProfile)? = null,
    private val exportData: (suspend () -> DataExportReceipt)? = null,
    private val cached: CachedValue<TravellerProfile>? = null,
    private val confirmationDelay: Duration = 4.seconds,
) : ViewModel() {

    /**
     * Les lignes qui peuvent accuser réception. Une énumération et non un
     * booléen par ligne : c'est ce qui garantit qu'une seule coche s'allume.
     */
    enum class SavedField {
        FullName,
        PhoneNumber,
        Address,
        Gender,
        Newsletter,
        Notifications,
        Avatar,
    }

    /** Où en est « Exporter mes données » — voir [DataExportSheet]. */
    sealed interface DataExportState {
        /** Rien de demandé : la feuille propose. */
        data object Idle : DataExportState

        /** La demande est partie, le bouton tourne. */
        data object Requesting : DataExportState

        /** Le lien est parti — ou l'était déjà, voir [DataExportReceipt.alreadyRequested]. */
        data class Sent(val receipt: DataExportReceipt) : DataExportState

        /** Rien n'est parti, et voici pourquoi. */
        data class Failed(val message: String) : DataExportState
    }

    /**
     * Ce que l'écran et ses feuilles lisent.
     *
     * @property justSaved ce qui vient d'être enregistré, le temps que la ligne
     *   concernée l'annonce. Une seule à la fois : on ne corrige qu'une ligne à
     *   la fois.
     * @property isUploadingAvatar la photo est en route vers le serveur : l'avatar le montre.
     * @property avatarErrorMessage ce qui a raté en envoyant ou en retirant la
     *   photo, dit **sous le rond**. Pas dans [errorMessage] : celui-là
     *   s'affiche au pied de la page, sous les mentions légales, et on touche
     *   la photo tout en haut. « Supprimer la photo » échouait donc sans que
     *   rien ne bouge à l'écran (Hugo, 30/09/2026 — la route n'était pas encore
     *   déployée, l'API rendait 404).
     * @property freshness ce que le dernier chargement a appris. C'est lui que
     *   la vue anime — voir `BrandRefreshFlash`.
     * @property isDeletingAccount `true` pendant la suppression du compte.
     *   L'écran verrouille alors le bouton : la demande est définitive, elle ne
     *   doit pas partir deux fois.
     */
    data class State(
        val profile: TravellerProfile? = null,
        val errorMessage: String? = null,
        val justSaved: SavedField? = null,
        val isUploadingAvatar: Boolean = false,
        val avatarErrorMessage: String? = null,
        val freshness: ContentFreshness = ContentFreshness.Unknown,
        val isDeletingAccount: Boolean = false,
        val dataExport: DataExportState = DataExportState.Idle,
    ) {
        /**
         * `true` tant qu'on n'a rien à montrer. L'écran se dessine quand même —
         * il est fait pour l'essentiel de choses que l'app connaît déjà — et
         * pose une barre d'attente à la place des valeurs. Voir `BrandSkeleton`.
         */
        val isLoading: Boolean get() = profile == null && errorMessage == null
    }

    private val _state = MutableStateFlow(State())
    val state: StateFlow<State> = _state.asStateFlow()

    val profile: TravellerProfile? get() = _state.value.profile
    val errorMessage: String? get() = _state.value.errorMessage
    val justSaved: SavedField? get() = _state.value.justSaved
    val avatarErrorMessage: String? get() = _state.value.avatarErrorMessage
    val dataExport: DataExportState get() = _state.value.dataExport

    /** Ferme l'abonnement côté serveur. `null` en aperçu. */
    private val cancelSubscriptionRemotely = cancelSubscription

    /**
     * L'envoi en cours. Le garder permet d'annuler celui d'avant quand deux
     * corrections s'enchaînent : c'est la dernière qui compte, et la réponse
     * d'une requête dépassée réécrirait l'écran avec une valeur périmée.
     */
    private var pendingSave: Job? = null

    /**
     * L'effacement de la coche. Gardé pour la même raison : corriger deux fois
     * de suite ne doit pas éteindre la seconde coche à l'heure de la première.
     */
    private var confirmationReset: Job? = null

    suspend fun load() {
        // Ce qu'on avait, tout de suite, et seulement au premier chargement.
        if (_state.value.profile == null) {
            cached?.invoke()?.let { stored ->
                // Le personnage du bac à sable vaut aussi pour la copie du
                // disque : sans lui, le profil gardé — abonné — repassait à la
                // session « a déjà été abonné » à l'ouverture, et « Jamais
                // abonné » ne montrait jamais le paywall de découverte
                // (recette du 03/10/2026).
                _state.update { it.copy(profile = played(stored), freshness = ContentFreshness.Restored) }
            }
        }

        try {
            val loaded = source()
            // Le bac à sable de l'accueil décide aussi de ce profil-ci :
            // basculer « abonné » là-bas doit se voir ici. Voir
            // `SandboxPersona` — `null` dans l'app livrée.
            _state.update {
                it.copy(
                    freshness = contentFreshness(loaded, it.profile),
                    profile = played(loaded),
                    errorMessage = null,
                )
            }
        } catch (error: CancellationException) {
            throw error
        } catch (error: Exception) {
            _state.update { it.copy(errorMessage = error.localizedDescription) }
        }
    }

    // MARK: - Sortir pour de bon

    /**
     * Supprime le compte et tout ce qui est à lui. Renvoie `true` quand c'est
     * fait — c'est le signal qui ramène l'app à l'écran d'entrée.
     *
     * L'écran a déjà demandé confirmation : ce n'est pas au modèle de la
     * redemander, et il n'y a rien à annuler après.
     */
    suspend fun deleteAccount(): Boolean {
        val remove = remove ?: return false

        _state.update { it.copy(isDeletingAccount = true) }
        return try {
            remove()
            _state.update { it.copy(errorMessage = null) }
            true
        } catch (error: CancellationException) {
            throw error
        } catch (error: Exception) {
            _state.update { it.copy(errorMessage = error.localizedDescription) }
            false
        } finally {
            _state.update { it.copy(isDeletingAccount = false) }
        }
    }

    // MARK: - Exporter ses données

    /**
     * Demande au serveur d'envoyer le lien d'export à l'adresse du compte.
     *
     * **Rien à confirmer avant** : la demande ne détruit rien, ne coûte rien,
     * et le lien ne part qu'à l'adresse du compte. La feuille dit ce qui va se
     * passer, et un seul bouton le fait.
     */
    suspend fun requestDataExport() {
        if (_state.value.dataExport == DataExportState.Requesting) return

        val exportData = exportData
        if (exportData == null) {
            val email = _state.value.profile?.email ?: "ton adresse e-mail"
            _state.update { it.copy(dataExport = DataExportState.Sent(DataExportReceipt.fixture(email))) }
            return
        }

        _state.update { it.copy(dataExport = DataExportState.Requesting) }
        val outcome = try {
            DataExportState.Sent(exportData())
        } catch (error: CancellationException) {
            throw error
        } catch (error: ApiError.Server) {
            // Le serveur en ligne ne connaît pas encore la route : il a
            // répondu par le 404 de Fastify, en anglais, qui ne parle à
            // personne.
            DataExportState.Failed(if (error.statusCode == 404) DataExportCopy.notYetAvailable else error.localizedDescription)
        } catch (error: Exception) {
            DataExportState.Failed(error.localizedDescription)
        }
        _state.update { it.copy(dataExport = outcome) }
    }

    /**
     * La feuille se referme : la prochaine ouverture repart de la
     * proposition, pas de la confirmation d'hier. Une demande en vol, elle,
     * va à son terme.
     */
    fun resetDataExport() {
        if (_state.value.dataExport == DataExportState.Requesting) return
        _state.update { it.copy(dataExport = DataExportState.Idle) }
    }

    // MARK: - Ce qu'on change depuis l'écran
    //
    // Des méthodes plutôt qu'un `profile` ouvert en écriture : une vue ne doit
    // pas pouvoir remplacer un profil entier par mégarde, et c'est ici que
    // viennent se brancher les appels réseau — un seul endroit à modifier.

    /**
     * Les trois champs d'identité, corrigés depuis les lignes de l'écran.
     * Un champ vidé redevient `null` plutôt que de rester une chaîne vide :
     * « pas de téléphone » et « un téléphone vide » ne sont pas la même chose.
     */
    fun setFullName(name: String) {
        val trimmed = name.trim()
        // Le nom, lui, ne peut pas disparaître : c'est le titre de l'écran.
        if (trimmed.isEmpty() || trimmed == profile?.fullName) return
        mutate { it.copy(fullName = trimmed) }

        // Le serveur tient un prénom et un nom, l'écran une seule ligne : la
        // coupure se fait ici, au premier espace. Le reste part en nom de
        // famille, particules et noms composés compris — « Jean de La
        // Fontaine » vaut mieux découpé comme ça que tronqué.
        val parts = trimmed.split(' ', limit = 2)
        save(
            ProfileEdit(firstName = Some(parts.first()), lastName = Some(parts.getOrNull(1))),
            confirming = SavedField.FullName,
        )
    }

    // **L'adresse email ne se corrige plus depuis le profil**, et il n'y a donc
    // plus de `setEmail` du tout.
    //
    // Elle n'était pas qu'un champ de plus : c'est l'identifiant de connexion.
    // La changer ici demande de vérifier la nouvelle adresse, de refuser celles
    // déjà prises, et de décider ce qu'il advient de la session ouverte avec
    // l'ancienne — trois choses que `PATCH /v1/profile` ne fait pas, et qu'une
    // ligne qui s'enregistre toute seule ne peut pas faire correctement. En
    // attendant cet écran-là, la ligne se lit.

    fun setPhoneNumber(phoneNumber: String) {
        val value = phoneNumber.trim().ifEmpty { null }
        if (value == profile?.phoneNumber) return

        mutate { it.copy(phoneNumber = value) }
        save(ProfileEdit(phoneNumber = Some(value)), confirming = SavedField.PhoneNumber)
    }

    fun setNewsletter(isOn: Boolean) {
        if (isOn == profile?.wantsNewsletter) return
        mutate { it.copy(wantsNewsletter = isOn) }
        save(ProfileEdit(wantsNewsletter = isOn), confirming = SavedField.Newsletter)
    }

    /**
     * Les notifications du compte, depuis la feuille « Notifications » du
     * profil (D13, 19/10/2026). Le bloc entier part : c'est ce que la route
     * accepte, comme les alertes d'un voyage.
     */
    fun setNotifications(preferences: AccountNotificationPreferences) {
        if (preferences == profile?.notifications) return
        mutate { it.copy(notifications = preferences) }
        save(ProfileEdit(notifications = preferences), confirming = SavedField.Notifications)
    }

    fun setConnector(id: String, isEnabled: Boolean) {
        mutate { profile ->
            if (profile.connectors.none { it.id == id }) return@mutate profile
            profile.copy(connectors = profile.connectors.map { if (it.id == id) it.copy(isEnabled = isEnabled) else it })
        }
    }

    /**
     * Enregistre l'adresse que la feuille a validée — la première comme une
     * correction : c'est le même geste, sur les mêmes quatre lignes.
     *
     * Le pays se lit dans la liste servie avec le profil, pour que la ligne
     * l'écrive **tout de suite** en toutes lettres et que le serveur reçoive
     * le code : la feuille peut n'avoir qu'un nom — tapé à la main quand la
     * liste n'était pas là — et le serveur ne répond qu'après. Ce que la
     * liste ne connaît pas part tel quel : le serveur le reconnaîtra, ou le
     * refusera en le disant.
     */
    fun save(address: PostalAddress) {
        var settled = address
        profile?.shippingCountry(address.country)?.let { country ->
            settled = settled.copy(country = country.code, countryName = country.name)
        }
        if (settled == profile?.address) return
        mutate { it.copy(address = settled) }
        save(ProfileEdit(address = settled), confirming = SavedField.Address)
    }

    /**
     * Envoie la photo de profil choisie (Clara, 17/09/2026, T165).
     *
     * **Rien ne change à l'écran avant la réponse** : c'est le profil relu que
     * le serveur renvoie qui porte la nouvelle adresse, et un échec laisse
     * l'ancienne photo avec le reproche au-dessus — comme les lignes qui
     * s'enregistrent. Le JPEG est déjà réduit par l'écran ; ici on envoie.
     */
    suspend fun setAvatar(data: ByteArray, mimeType: String = "image/jpeg") {
        val uploadAvatar = uploadAvatar ?: return
        replaceAvatar { uploadAvatar(data, mimeType) }
    }

    /**
     * Retire la photo de profil : le rond revient aux initiales (Hugo,
     * 29/09/2026). Même contrat que l'envoi — c'est le profil relu qui fait
     * foi, et un échec laisse la photo avec le reproche dessous.
     */
    suspend fun removeAvatar() {
        val deleteAvatar = deleteAvatar
        if (deleteAvatar == null) {
            // En aperçu : on retire sur place.
            mutate { it.copy(avatarUrl = null) }
            return
        }
        replaceAvatar { deleteAvatar() }
    }

    private suspend fun replaceAvatar(call: suspend () -> TravellerProfile) {
        _state.update { it.copy(isUploadingAvatar = true, avatarErrorMessage = null) }
        try {
            val saved = call()
            _state.update { it.copy(profile = played(saved)) }
            confirm(SavedField.Avatar)
        } catch (error: CancellationException) {
            throw error
        } catch (error: Exception) {
            _state.update { it.copy(avatarErrorMessage = error.localizedDescription) }
        } finally {
            _state.update { it.copy(isUploadingAvatar = false) }
        }
    }

    /**
     * Ce que la personne dit d'elle-même, à la place de ce que le serveur
     * devinait sur son prénom. Voir [Gender].
     */
    fun setGender(gender: Gender) {
        if (gender == profile?.gender) return
        mutate { it.copy(gender = gender) }
        save(ProfileEdit(gender = gender), confirming = SavedField.Gender)
    }

    /**
     * Souscrire, ou re-souscrire après une résiliation : l'écran passe à
     * l'illimité tout de suite, sans attendre que le serveur relise l'achat.
     *
     * ⚠️ **Aucun achat n'a lieu ici.** L'achat passe par le paywall et le store
     * (`SubscriptionPurchase`) ; ceci ne reste que pour un abonnement qui n'est
     * pas tenu par un store — un abonnement App Store se réarme sur l'iPhone,
     * un abonnement Google Play dans la page d'abonnements du Play Store.
     */
    fun activateSubscription() {
        mutate { it.copy(subscription = it.subscription.updating(isActive = true, cancelledAt = null)) }
    }

    /**
     * Résilier, au bout des trois confirmations.
     *
     * **L'abonnement cesse de se renouveler ; le mois déjà payé, lui, va à son
     * terme** (Hugo, 16/09/2026, règle tenue au passage au mois le
     * 03/10/2026). `isActive` tombe, `paidThrough` reste, et c'est
     * `Subscription.grantsAccess` qui décide si l'on raconte encore sans
     * limite — pas `isActive` seul. Le serveur applique la même règle
     * (`hasUnlimitedAccess`).
     *
     * Ça remplace « l'abonnement s'arrête aujourd'hui », qui n'était vrai que
     * le dernier jour d'une période — et qui reste la phrase affichée dans ce
     * cas-là, voir [SubscriptionCopy.doneParagraphs].
     *
     * **Et ça part au serveur** (Hugo, 19/09/2026). Ça ne partait pas : la
     * méthode ne touchait que la copie locale, le prochain chargement relisait
     * une ligne `subscriptions` toujours active, et on se retrouvait abonné
     * après avoir confirmé trois fois. `POST /v1/profile/subscription/cancel`
     * ferme la ligne et rend le profil relu.
     *
     * L'écran a **déjà** bougé quand la requête part — trois confirmations,
     * on ne fait pas attendre le réseau pour la quatrième —, et un échec
     * **remet ce que le serveur a vraiment** : une résiliation qu'on croit
     * faite et qui ne l'est pas est pire qu'un message d'erreur.
     */
    fun cancelSubscription(reason: SubscriptionCancellationReason?) {
        mutate { it.copy(subscription = it.subscription.updating(isActive = false, cancelledAt = Instant.now())) }

        val cancelSubscriptionRemotely = cancelSubscriptionRemotely ?: return

        pendingSave?.cancel()
        pendingSave = viewModelScope.launch {
            try {
                val saved = cancelSubscriptionRemotely(reason)
                if (!isActive) return@launch
                _state.update { it.copy(profile = played(saved), errorMessage = null) }
            } catch (error: CancellationException) {
                throw error
            } catch (error: Exception) {
                _state.update { it.copy(errorMessage = error.localizedDescription) }
                // Ce que le serveur a vraiment : l'abonnement est peut-être
                // encore ouvert, et l'écran doit le dire.
                load()
            }
        }
    }

    /**
     * Résilier un abonnement **tenu par Apple** (01/10/2026) : seule la raison
     * part d'ici.
     *
     * Apple ne laisse aucune app résilier à la place de son client : c'est la
     * gestion des abonnements de l'iPhone qui coupe le renouvellement, et la
     * notification d'Apple qui ferme la ligne côté serveur. Fermer
     * l'abonnement ici l'aurait fait croire arrêté pendant qu'Apple
     * continuait de prélever. Google Play suit la même règle pour un
     * abonnement Play : sa page d'abonnements coupe, son retour se lit sur le
     * store — voir [acknowledgeAppStoreRenewal].
     */
    fun recordCancellationReason(reason: SubscriptionCancellationReason?) {
        val cancelSubscriptionRemotely = cancelSubscriptionRemotely ?: return
        // Sans attendre, et sans message en cas d'échec : c'est une réponse de
        // sondage, pas un état du compte.
        viewModelScope.launch {
            try {
                cancelSubscriptionRemotely(reason)
            } catch (error: CancellationException) {
                throw error
            } catch (_: Exception) {
            }
        }
    }

    /**
     * Ce que le store dit du renouvellement, lu **sur l'appareil** au retour
     * de sa page de gestion. L'écran suit tout de suite ; le serveur l'apprend
     * par la notification du store, quelques secondes plus tard, et le
     * prochain chargement le confirme. Le mois payé (`paidThrough`) ne bouge
     * pas.
     */
    fun acknowledgeAppStoreRenewal(renews: Boolean) {
        mutate {
            it.copy(subscription = it.subscription.updating(isActive = renews, cancelledAt = if (renews) null else Instant.now()))
        }
    }

    /**
     * Le retour de la page du store, pour l'écran **et** pour la session —
     * d'après ce que le store dit du renouvellement.
     *
     * **Un achat que le store tient et que le serveur n'a pas encore reçu**
     * ([isHeldByAppleOnly]) ne se retouche pas sur la ligne du serveur
     * (03/10/2026) : elle n'a ni abonnement ni période payée. Renouvellement
     * coupé, on y enregistrait `false` — « L’abonnement s’arrête
     * aujourd’hui », l'offre reproposée —, alors que le store honore le mois
     * payé ; renouvellement armé, on y posait `isActive`, et l'écho du profil
     * levait le geste de la session sans que le serveur ait rien confirmé.
     * La session garde donc l'illimité — le store tient la période dans les
     * deux cas —, et l'écran remet la transaction puis relit : le serveur
     * tranchera.
     *
     * @return `true` dans ce cas-là, où il reste à remettre et relire.
     */
    fun settleAppStoreRenewal(renews: Boolean, session: SubscriptionSession?): Boolean {
        if (isHeldByAppleOnly(session)) {
            session?.record(isSubscribed = true)
            return true
        }
        acknowledgeAppStoreRenewal(renews)
        // Le mois payé garde l'illimité, même renouvellement coupé : la
        // session retient l'accès réel, pas le geste.
        session?.record(isSubscribed = subscriptionGrantsAccess, until = subscriptionUnlimitedUntil)
        return false
    }

    /**
     * La session dit « acheté », et le profil du serveur ne connaît pas
     * d'abonnement qui laisse raconter : un achat encaissé par le store que
     * l'API n'a pas encore pris (`AwaitingServer`). Faux tant que le profil
     * n'est pas là. Le nom est celui d'iOS ; sur Android, c'est Google Play
     * qui tient l'achat.
     */
    fun isHeldByAppleOnly(session: SubscriptionSession?): Boolean {
        val profile = profile ?: return false
        return session?.override == true && !profile.subscription.isUnlimited
    }

    /**
     * L'abonnement laisse-t-il encore raconter sans limite — actif, ou dans
     * son mois payé. C'est ce que la session doit retenir après une
     * résiliation : le geste vient de retoucher l'abonnement, donc c'est le
     * recalcul local qui répond (`Subscription.isUnlimited`).
     */
    val subscriptionGrantsAccess: Boolean
        get() = profile?.subscription?.isUnlimited ?: false

    /**
     * Jusqu'où l'illimité court encore après une résiliation — la date à
     * laquelle la session le fera tomber partout. `null` s'il se renouvelle.
     */
    val subscriptionUnlimitedUntil: Instant?
        get() = profile?.subscription?.unlimitedUntil()

    // MARK: - L'envoi

    /**
     * Envoie une correction, et accuse réception quand le serveur a répondu.
     *
     * L'écran a **déjà** la nouvelle valeur : [mutate] l'a posée avant l'appel,
     * pour qu'une ligne ne clignote pas le temps d'un aller-retour. Ce que la
     * réponse apporte, c'est le profil relu — les champs que le serveur a pu
     * normaliser, et le reste de la page inchangé.
     *
     * Un échec **ne défait rien** : ce qui a été tapé reste à l'écran, avec le
     * reproche au-dessus. Effacer sous les doigts de quelqu'un ce qu'il vient
     * d'écrire est la pire des réponses à une panne de réseau, et le prochain
     * chargement de l'écran remettra de toute façon les pendules à l'heure.
     */
    private fun save(edit: ProfileEdit, confirming: SavedField) {
        val persist = persist ?: return

        pendingSave?.cancel()
        _state.update { it.copy(justSaved = null) }

        pendingSave = viewModelScope.launch {
            try {
                var saved = persist(edit)
                if (!isActive) return@launch

                // **Le genre envoyé fait foi.** L'API d'avant le 18/09/2026 ne
                // connaît pas le champ : elle répond sans, ce que le décodage
                // lit « ne préfère pas répondre » — et le choix qu'on venait de
                // faire s'effaçait sous les yeux, une seconde après. Le serveur
                // n'a rien à corriger sur un genre : il l'enregistre tel quel,
                // donc ce qu'on a envoyé est ce qu'il a — ou ce qu'il aura, une
                // fois déployé.
                edit.gender?.let { saved = saved.copy(gender = it) }

                _state.update { it.copy(profile = played(saved), errorMessage = null) }
                confirm(confirming)
            } catch (error: CancellationException) {
                throw error
            } catch (error: Exception) {
                _state.update { it.copy(errorMessage = error.localizedDescription) }
            }
        }
    }

    /**
     * Allume la coche, et l'éteint quelques secondes plus tard.
     *
     * Assez longtemps pour qu'on la voie **en relevant les yeux du clavier** —
     * quatre secondes, pas deux : la coche n'apparaît qu'une fois le serveur
     * revenu, et on regarde encore le champ à ce moment-là. Assez court pour
     * qu'elle ne devienne pas un élément permanent de la ligne : ce serait
     * alors un état, et non un accusé de réception.
     */
    private fun confirm(field: SavedField) {
        _state.update { it.copy(justSaved = field) }
        confirmationReset?.cancel()

        confirmationReset = viewModelScope.launch {
            delay(confirmationDelay)
            _state.update { if (it.justSaved == field) it.copy(justSaved = null) else it }
        }
    }

    private fun mutate(change: (TravellerProfile) -> TravellerProfile) {
        _state.update { state -> state.profile?.let { state.copy(profile = change(it)) } ?: state }
    }

    /** Le profil tel que le bac à sable le fait jouer — tel quel hors de lui. */
    private fun played(profile: TravellerProfile): TravellerProfile = SandboxPersona.current?.applied(profile) ?: profile
}

/** Le `localizedDescription` d'iOS : la phrase de l'API, déjà en français. */
internal val Throwable.localizedDescription: String
    get() = (this as? ApiError)?.errorDescription ?: localizedMessage ?: toString()
