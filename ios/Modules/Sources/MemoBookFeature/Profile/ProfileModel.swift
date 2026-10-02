import Foundation
import MemoBookCore
import MemoBookNetworking
import Observation

/// Ce que l'écran de profil sait faire : charger le profil, et enregistrer ce
/// qu'on y change.
///
/// Même construction que ``HomeModel`` : le modèle ne connaît pas l'API, il
/// reçoit **deux fonctions** — une qui lit, une qui écrit. L'app leur branche
/// `GET` et `PATCH /v1/profile` ; les aperçus n'en fournissent aucune et
/// travaillent alors en mémoire, sans serveur.
///
/// **Une correction part au serveur dès qu'elle est faite**, ligne par ligne,
/// et la réponse — le profil entier relu — remplace ce qui est à l'écran. Pas
/// de bouton « Enregistrer » : c'est le contrat des lignes des Réglages, et
/// c'est perdre le focus qui vaut validation. La ligne le dit ensuite avec une
/// coche, sans quoi rien ne distinguerait une correction partie d'une
/// correction oubliée.
@MainActor
@Observable
public final class ProfileModel {
    public private(set) var profile: TravellerProfile?
    public private(set) var errorMessage: String?

    /// Ce qui vient d'être enregistré, le temps que la ligne concernée
    /// l'annonce. Une seule à la fois : on ne corrige qu'une ligne à la fois.
    public private(set) var justSaved: SavedField?

    /// Les lignes qui peuvent accuser réception. Une énumération et non un
    /// booléen par ligne : c'est ce qui garantit qu'une seule coche s'allume.
    public enum SavedField: Sendable, Hashable {
        case fullName
        case phoneNumber
        case address
        case gender
        case newsletter
        case avatar
    }

    private let source: () async throws -> TravellerProfile
    private let persist: ((ProfileEdit) async throws -> TravellerProfile)?
    private let remove: (() async throws -> Void)?
    /// Envoie la photo de profil. `nil` en aperçu : la photo reste sur place.
    private let uploadAvatar: ((Data, String) async throws -> TravellerProfile)?
    /// Retire la photo de profil. `nil` en aperçu.
    private let deleteAvatar: (() async throws -> TravellerProfile)?

    /// Change le mot de passe, et envoie l'e-mail de « mot de passe oublié ».
    /// Les deux vont à la feuille « Modifier mon mot de passe » (Hugo,
    /// 29/09/2026) ; `nil` en aperçu, où la feuille joue la réussite.
    let changePassword: ((String, String) async throws -> Void)?
    let requestPasswordReset: ((String) async throws -> Void)?

    /// Ferme l'abonnement côté serveur. `nil` en aperçu.
    private let cancelSubscriptionRemotely:
        ((SubscriptionCancellationReason?) async throws -> TravellerProfile)?

    /// Demande le lien d'export des données. `nil` en aperçu : la feuille joue
    /// la réussite.
    private let exportData: (() async throws -> DataExportReceipt)?

    /// La photo est en route vers le serveur : l'avatar le montre.
    public private(set) var isUploadingAvatar = false

    /// Ce qui a raté en envoyant ou en retirant la photo, dit **sous le rond**.
    ///
    /// Pas dans ``errorMessage`` : celui-là s'affiche au pied de la page, sous
    /// les mentions légales, et on touche la photo tout en haut. « Supprimer la
    /// photo » échouait donc sans que rien ne bouge à l'écran (Hugo,
    /// 30/09/2026 — la route n'était pas encore déployée, l'API rendait 404).
    public private(set) var avatarErrorMessage: String?

    /// Ce qu'on avait sur le disque — voir ``ContentCache``. `nil` en aperçu.
    private let cached: CachedValue<TravellerProfile>?

    /// Ce que le dernier chargement a appris. C'est lui que la vue anime —
    /// voir ``SwiftUI/View/brandRefreshFlash(_:)``.
    public private(set) var freshness: ContentFreshness = .unknown

    /// L'envoi en cours. Le garder permet d'annuler celui d'avant quand deux
    /// corrections s'enchaînent : c'est la dernière qui compte, et la réponse
    /// d'une requête dépassée réécrirait l'écran avec une valeur périmée.
    private var pendingSave: Task<Void, Never>?

    /// L'effacement de la coche. Gardé pour la même raison : corriger deux fois
    /// de suite ne doit pas éteindre la seconde coche à l'heure de la première.
    private var confirmationReset: Task<Void, Never>?

    /// - Parameters:
    ///   - source: d'où vient le profil. Par défaut, le jeu d'essai.
    ///   - persist: où partent les corrections. `nil` — le cas des aperçus —
    ///     les garde en mémoire.
    ///   - remove: comment supprimer le compte. `nil` en aperçu : on ne
    ///     supprime pas un compte depuis une maquette.
    public init(
        source: @escaping () async throws -> TravellerProfile = { .fixture },
        persist: ((ProfileEdit) async throws -> TravellerProfile)? = nil,
        remove: (() async throws -> Void)? = nil,
        uploadAvatar: ((Data, String) async throws -> TravellerProfile)? = nil,
        deleteAvatar: (() async throws -> TravellerProfile)? = nil,
        changePassword: ((String, String) async throws -> Void)? = nil,
        requestPasswordReset: ((String) async throws -> Void)? = nil,
        cancelSubscription: (
            (SubscriptionCancellationReason?) async throws -> TravellerProfile
        )? = nil,
        exportData: (() async throws -> DataExportReceipt)? = nil,
        cached: CachedValue<TravellerProfile>? = nil
    ) {
        self.cached = cached
        self.source = source
        self.persist = persist
        self.remove = remove
        self.uploadAvatar = uploadAvatar
        self.deleteAvatar = deleteAvatar
        self.changePassword = changePassword
        self.requestPasswordReset = requestPasswordReset
        self.cancelSubscriptionRemotely = cancelSubscription
        self.exportData = exportData
    }

    /// `true` tant qu'on n'a rien à montrer. L'écran se dessine quand même —
    /// il est fait pour l'essentiel de choses que l'app connaît déjà — et pose
    /// une barre d'attente à la place des valeurs. Voir ``BrandSkeleton``.
    public var isLoading: Bool { profile == nil && errorMessage == nil }

    public func load() async {
        // Ce qu'on avait, tout de suite, et seulement au premier chargement.
        if profile == nil, let stored = await cached?() {
            profile = stored
            freshness = .restored
        }

        do {
            let loaded = try await source()
            freshness = contentFreshness(of: loaded, replacing: profile)

            #if DEBUG
                // Le bac à sable de l'accueil décide aussi de ce profil-ci :
                // basculer « abonné » là-bas doit se voir ici. Voir
                // ``SandboxPersona``. Absent de l'app livrée.
                profile = SandboxPersona.current?.applied(to: loaded) ?? loaded
            #else
                profile = loaded
            #endif

            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Sortir pour de bon

    /// `true` pendant la suppression du compte. L'écran verrouille alors le
    /// bouton : la demande est définitive, elle ne doit pas partir deux fois.
    public private(set) var isDeletingAccount = false

    /// Supprime le compte et tout ce qui est à lui. Renvoie `true` quand c'est
    /// fait — c'est le signal qui ramène l'app à l'écran d'entrée.
    ///
    /// L'écran a déjà demandé confirmation : ce n'est pas au modèle de la
    /// redemander, et il n'y a rien à annuler après.
    public func deleteAccount() async -> Bool {
        guard let remove else { return false }

        isDeletingAccount = true
        defer { isDeletingAccount = false }

        do {
            try await remove()
            errorMessage = nil
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    // MARK: - Exporter ses données

    /// Où en est « Exporter mes données » — voir ``DataExportSheet``.
    public enum DataExportState: Sendable, Equatable {
        /// Rien de demandé : la feuille propose.
        case idle
        /// La demande est partie, le bouton tourne.
        case requesting
        /// Le lien est parti — ou l'était déjà, voir
        /// ``DataExportReceipt/alreadyRequested``.
        case sent(DataExportReceipt)
        /// Rien n'est parti, et voici pourquoi.
        case failed(String)
    }

    public private(set) var dataExport: DataExportState = .idle

    /// Demande au serveur d'envoyer le lien d'export à l'adresse du compte.
    ///
    /// **Rien à confirmer avant** : la demande ne détruit rien, ne coûte rien,
    /// et le lien ne part qu'à l'adresse du compte. La feuille dit ce qui va se
    /// passer, et un seul bouton le fait.
    public func requestDataExport() async {
        if case .requesting = dataExport { return }

        guard let exportData else {
            dataExport = .sent(.fixture(email: profile?.email ?? "ton adresse e-mail"))
            return
        }

        dataExport = .requesting
        do {
            dataExport = .sent(try await exportData())
        } catch APIError.server(statusCode: 404, code: _, message: _) {
            // Le serveur en ligne ne connaît pas encore la route : il a
            // répondu par le 404 de Fastify, en anglais, qui ne parle à
            // personne.
            dataExport = .failed(DataExportCopy.notYetAvailable)
        } catch {
            dataExport = .failed(error.localizedDescription)
        }
    }

    /// La feuille se referme : la prochaine ouverture repart de la
    /// proposition, pas de la confirmation d'hier. Une demande en vol, elle,
    /// va à son terme.
    public func resetDataExport() {
        if case .requesting = dataExport { return }
        dataExport = .idle
    }

    // MARK: - Ce qu'on change depuis l'écran
    //
    // Des méthodes plutôt qu'un `profile` ouvert en écriture : une vue ne doit
    // pas pouvoir remplacer un profil entier par mégarde, et c'est ici que
    // viendront se brancher les appels réseau — un seul endroit à modifier.

    /// Les trois champs d'identité, corrigés depuis les lignes de l'écran.
    /// Un champ vidé redevient `nil` plutôt que de rester une chaîne vide :
    /// « pas de téléphone » et « un téléphone vide » ne sont pas la même chose.

    public func setFullName(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        // Le nom, lui, ne peut pas disparaître : c'est le titre de l'écran.
        guard !trimmed.isEmpty, trimmed != profile?.fullName else { return }
        mutate { $0.fullName = trimmed }

        // Le serveur tient un prénom et un nom, l'écran une seule ligne : la
        // coupure se fait ici, au premier espace. Le reste part en nom de
        // famille, particules et noms composés compris — « Jean de La
        // Fontaine » vaut mieux découpé comme ça que tronqué.
        let parts = trimmed.split(separator: " ", maxSplits: 1).map(String.init)
        save(
            ProfileEdit(
                firstName: .some(parts.first),
                lastName: .some(parts.count > 1 ? parts[1] : nil)
            ),
            confirming: .fullName
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

    public func setPhoneNumber(_ phoneNumber: String) {
        let value = phoneNumber.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        guard value != profile?.phoneNumber else { return }

        mutate { $0.phoneNumber = value }
        save(ProfileEdit(phoneNumber: .some(value)), confirming: .phoneNumber)
    }

    public func setNewsletter(_ isOn: Bool) {
        guard isOn != profile?.wantsNewsletter else { return }
        mutate { $0.wantsNewsletter = isOn }
        save(ProfileEdit(wantsNewsletter: isOn), confirming: .newsletter)
    }

    public func setConnector(id: String, isEnabled: Bool) {
        mutate { profile in
            guard let index = profile.connectors.firstIndex(where: { $0.id == id }) else { return }
            profile.connectors[index].isEnabled = isEnabled
        }
    }

    /// Enregistre l'adresse que la feuille a validée — la première comme une
    /// correction : c'est le même geste, sur les mêmes quatre lignes.
    ///
    /// Le pays se lit dans la liste servie avec le profil, pour que la ligne
    /// l'écrive **tout de suite** en toutes lettres et que le serveur reçoive
    /// le code : la feuille peut n'avoir qu'un nom — tapé à la main quand la
    /// liste n'était pas là — et le serveur ne répond qu'après. Ce que la
    /// liste ne connaît pas part tel quel : le serveur le reconnaîtra, ou le
    /// refusera en le disant.
    public func save(address: PostalAddress) {
        var address = address
        if let country = profile?.shippingCountry(code: address.country) {
            address.country = country.code
            address.countryName = country.name
        }
        guard address != profile?.address else { return }
        mutate { $0.address = address }
        save(ProfileEdit(address: address), confirming: .address)
    }

    /// Envoie la photo de profil choisie (Clara, 17/09/2026, T165).
    ///
    /// **Rien ne change à l'écran avant la réponse** : c'est le profil relu que
    /// le serveur renvoie qui porte la nouvelle adresse, et un échec laisse
    /// l'ancienne photo avec le reproche au-dessus — comme les lignes qui
    /// s'enregistrent. Le JPEG est déjà réduit par l'écran ; ici on envoie.
    public func setAvatar(_ data: Data, mimeType: String = "image/jpeg") async {
        guard let uploadAvatar else { return }

        isUploadingAvatar = true
        defer { isUploadingAvatar = false }

        avatarErrorMessage = nil
        do {
            let saved = try await uploadAvatar(data, mimeType)
            #if DEBUG
                profile = SandboxPersona.current?.applied(to: saved) ?? saved
            #else
                profile = saved
            #endif
            confirm(.avatar)
        } catch {
            avatarErrorMessage = error.localizedDescription
        }
    }

    /// Retire la photo de profil : le rond revient aux initiales (Hugo,
    /// 29/09/2026). Même contrat que l'envoi — c'est le profil relu qui fait
    /// foi, et un échec laisse la photo avec le reproche dessous.
    public func removeAvatar() async {
        guard let deleteAvatar else {
            // En aperçu : on retire sur place.
            profile?.avatarUrl = nil
            return
        }

        isUploadingAvatar = true
        defer { isUploadingAvatar = false }

        avatarErrorMessage = nil
        do {
            let saved = try await deleteAvatar()
            #if DEBUG
                profile = SandboxPersona.current?.applied(to: saved) ?? saved
            #else
                profile = saved
            #endif
            confirm(.avatar)
        } catch {
            avatarErrorMessage = error.localizedDescription
        }
    }

    /// Ce que la personne dit d'elle-même, à la place de ce que le serveur
    /// devinait sur son prénom. Voir ``Gender``.
    public func setGender(_ gender: Gender) {
        guard gender != profile?.gender else { return }
        mutate { $0.gender = gender }
        save(ProfileEdit(gender: gender), confirming: .gender)
    }

    /// Souscrire, ou re-souscrire après une résiliation — et **cesser d'être un
    /// compte à quota dans le même geste**.
    ///
    /// Les deux ensemble parce que c'est ce que le serveur écrira le jour d'une
    /// vraie souscription : un abonné n'a plus d'étapes offertes à compter, et
    /// laisser la pastille se vider derrière lui serait un décompte sans objet.
    ///
    /// ⚠️ **Aucun achat n'a lieu ici.** L'achat passe par le paywall et
    /// StoreKit (``SubscriptionPurchase``) ; ceci ne reste que pour un
    /// abonnement qui n'est pas tenu par Apple — un abonnement App Store se
    /// réarme dans la feuille d'iOS, voir ``acknowledgeAppStoreRenewal(_:)``.
    public func activateSubscription() {
        mutate { profile in
            profile.subscription.isActive = true
            profile.subscription.cancelledAt = nil
            profile.offeredSteps = nil
            profile.remainingSteps = nil
        }
    }

    /// Résilier, au bout des trois confirmations.
    ///
    /// **L'abonnement cesse de se renouveler ; la semaine déjà payée, elle, va
    /// à son terme** (Hugo, 16/09/2026). `isActive` tombe, `paidThrough` reste,
    /// et c'est ``Subscription/grantsAccess(on:)`` qui décide de ce qui est
    /// ouvert — pas `isActive` seul. Le serveur applique la même règle sur son
    /// verrou (`assertCanRecord`).
    ///
    /// Ça remplace « l'abonnement s'arrête aujourd'hui », qui n'était vrai que
    /// le dernier jour d'une période — et qui reste la phrase affichée dans ce
    /// cas-là, voir ``SubscriptionCopy/doneParagraphs(graceEnd:)``.
    ///
    /// **Et ça part au serveur** (Hugo, 19/09/2026). Ça ne partait pas : la
    /// méthode ne touchait que la copie locale, le prochain chargement relisait
    /// une ligne `subscriptions` toujours active, et on se retrouvait abonné
    /// après avoir confirmé trois fois. `POST /v1/profile/subscription/cancel`
    /// ferme la ligne et rend le profil relu.
    ///
    /// L'écran a **déjà** bougé quand la requête part — trois confirmations,
    /// on ne fait pas attendre le réseau pour la quatrième —, et un échec
    /// **remet ce que le serveur a vraiment** : une résiliation qu'on croit
    /// faite et qui ne l'est pas est pire qu'un message d'erreur.
    public func cancelSubscription(reason: SubscriptionCancellationReason?) {
        mutate {
            $0.subscription.isActive = false
            $0.subscription.cancelledAt = .now
        }

        guard let cancelSubscriptionRemotely else { return }

        pendingSave?.cancel()
        pendingSave = Task { [weak self] in
            do {
                let saved = try await cancelSubscriptionRemotely(reason)
                guard !Task.isCancelled, let self else { return }

                #if DEBUG
                    profile = SandboxPersona.current?.applied(to: saved) ?? saved
                #else
                    profile = saved
                #endif

                errorMessage = nil
            } catch {
                guard !Task.isCancelled, let self else { return }
                errorMessage = error.localizedDescription
                // Ce que le serveur a vraiment : l'abonnement est peut-être
                // encore ouvert, et l'écran doit le dire.
                await load()
            }
        }
    }

    /// Résilier un abonnement **tenu par Apple** (01/10/2026) : seule la raison
    /// part d'ici.
    ///
    /// Apple ne laisse aucune app résilier à la place de son client : c'est la
    /// feuille de gestion des abonnements d'iOS qui coupe le renouvellement, et
    /// la notification d'Apple qui ferme la ligne côté serveur. Fermer
    /// l'abonnement ici l'aurait fait croire arrêté pendant qu'Apple
    /// continuait de prélever. L'écran ne bouge donc qu'au retour de la
    /// feuille d'iOS — voir ``acknowledgeAppStoreRenewal(_:)``.
    public func recordCancellationReason(_ reason: SubscriptionCancellationReason?) {
        guard let cancelSubscriptionRemotely else { return }
        // Sans attendre, et sans message en cas d'échec : c'est une réponse de
        // sondage, pas un état du compte.
        Task { _ = try? await cancelSubscriptionRemotely(reason) }
    }

    /// Ce qu'Apple dit du renouvellement, lu **sur l'appareil** au retour de la
    /// feuille d'iOS. L'écran suit tout de suite ; le serveur l'apprend par la
    /// notification d'Apple, quelques secondes plus tard, et le prochain
    /// chargement le confirme. La semaine payée (`paidThrough`) ne bouge pas.
    public func acknowledgeAppStoreRenewal(_ renews: Bool) {
        mutate {
            $0.subscription.isActive = renews
            $0.subscription.cancelledAt = renews ? nil : .now
        }
    }

    /// L'abonnement laisse-t-il encore raconter — actif, ou dans sa semaine
    /// payée. C'est ce que la session doit retenir après une résiliation.
    public var subscriptionGrantsAccess: Bool {
        profile?.subscription.grantsAccess() ?? false
    }

    // MARK: - L'envoi

    /// Envoie une correction, et accuse réception quand le serveur a répondu.
    ///
    /// L'écran a **déjà** la nouvelle valeur : `mutate` l'a posée avant l'appel,
    /// pour qu'une ligne ne clignote pas le temps d'un aller-retour. Ce que la
    /// réponse apporte, c'est le profil relu — les champs que le serveur a pu
    /// normaliser, et le reste de la page inchangé.
    ///
    /// Un échec **ne défait rien** : ce qui a été tapé reste à l'écran, avec le
    /// reproche au-dessus. Effacer sous les doigts de quelqu'un ce qu'il vient
    /// d'écrire est la pire des réponses à une panne de réseau, et le prochain
    /// chargement de l'écran remettra de toute façon les pendules à l'heure.
    private func save(_ edit: ProfileEdit, confirming field: SavedField) {
        guard let persist else { return }

        pendingSave?.cancel()
        justSaved = nil

        pendingSave = Task { [weak self] in
            do {
                var saved = try await persist(edit)
                guard !Task.isCancelled else { return }
                guard let self else { return }

                // **Le genre envoyé fait foi.** L'API d'avant le 18/09/2026 ne
                // connaît pas le champ : elle répond sans, ce que le décodage
                // lit « ne préfère pas répondre » — et le choix qu'on venait de
                // faire s'effaçait sous les yeux, une seconde après. Le serveur
                // n'a rien à corriger sur un genre : il l'enregistre tel quel,
                // donc ce qu'on a envoyé est ce qu'il a — ou ce qu'il aura, une
                // fois déployé.
                if let gender = edit.gender { saved.gender = gender }

                #if DEBUG
                    profile = SandboxPersona.current?.applied(to: saved) ?? saved
                #else
                    profile = saved
                #endif

                errorMessage = nil
                confirm(field)
            } catch {
                guard !Task.isCancelled else { return }
                self?.errorMessage = error.localizedDescription
            }
        }
    }

    /// Allume la coche, et l'éteint quelques secondes plus tard.
    ///
    /// Assez longtemps pour qu'on la voie **en relevant les yeux du clavier** —
    /// quatre secondes, pas deux : la coche n'apparaît qu'une fois le serveur
    /// revenu, et on regarde encore le champ à ce moment-là. Assez court pour
    /// qu'elle ne devienne pas un élément permanent de la ligne : ce serait
    /// alors un état, et non un accusé de réception.
    private func confirm(_ field: SavedField) {
        justSaved = field
        confirmationReset?.cancel()

        confirmationReset = Task { [weak self] in
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            if self?.justSaved == field { self?.justSaved = nil }
        }
    }

    private func mutate(_ change: (inout TravellerProfile) -> Void) {
        guard var profile else { return }
        change(&profile)
        self.profile = profile
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
