import Foundation
import MemoBookCore
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
        case newsletter
    }

    private let source: () async throws -> TravellerProfile
    private let persist: ((ProfileEdit) async throws -> TravellerProfile)?
    private let remove: (() async throws -> Void)?

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
        remove: (() async throws -> Void)? = nil
    ) {
        self.source = source
        self.persist = persist
        self.remove = remove
    }

    /// `true` tant qu'on n'a rien à montrer. L'écran se dessine quand même —
    /// il est fait pour l'essentiel de choses que l'app connaît déjà — et pose
    /// une barre d'attente à la place des valeurs. Voir ``BrandSkeleton``.
    public var isLoading: Bool { profile == nil && errorMessage == nil }

    public func load() async {
        do {
            let loaded = try await source()

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

    public func selectCard(id: String) {
        mutate { $0.selectedCardId = id }
    }

    public func save(address: PostalAddress) {
        guard address != profile?.address else { return }
        mutate { $0.address = address }
        save(ProfileEdit(address: address), confirming: .address)
    }

    /// Enregistre une carte à partir du formulaire.
    ///
    /// **Seuls les quatre derniers chiffres sont conservés** — voir
    /// ``PaymentCard``. Le numéro complet, la date et le cryptogramme ne sont ni
    /// gardés ni journalisés : le jour où le paiement existe, ils partiront
    /// directement au prestataire sans passer par nos modèles.
    public func addCard(number: String, label: String) {
        let digits = number.filter(\.isNumber)
        guard digits.count >= 4 else { return }

        mutate { profile in
            let card = PaymentCard(
                id: UUID().uuidString,
                label: label,
                last4: String(digits.suffix(4))
            )
            profile.cards.append(card)
            profile.selectedCardId = card.id
        }
    }

    /// Souscrire, et **cesser d'être un compte à quota dans le même geste**.
    ///
    /// Les deux ensemble parce que c'est ce que le serveur écrira le jour d'une
    /// vraie souscription : un abonné n'a plus d'étapes offertes à compter, et
    /// laisser la pastille se vider derrière lui serait un décompte sans objet.
    public func activateSubscription() {
        mutate { profile in
            profile.subscription.isActive = true
            profile.offeredSteps = nil
            profile.remainingSteps = nil
        }
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
                let saved = try await persist(edit)
                guard !Task.isCancelled else { return }
                guard let self else { return }

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
