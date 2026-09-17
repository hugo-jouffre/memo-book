import Foundation
import MemoBookCore
import MemoBookNetworking
import Observation

/// Ce que l'écran des paramètres d'un voyage sait faire : les charger, et
/// enregistrer ce qu'on y change.
///
/// Même construction que ``ProfileModel`` : le modèle ne connaît pas l'API, il
/// reçoit **deux fonctions** — une qui lit, une qui écrit. L'app leur branche
/// `GET` et `PATCH /v1/trips/:id/settings` ; les aperçus n'en fournissent aucune
/// et travaillent alors en mémoire, sans serveur.
///
/// **Un réglage modifié part au serveur dès qu'il est touché**, un par un. Pas
/// de bouton « Enregistrer » : c'est le contrat des lignes des Réglages, ici
/// comme dans le profil. Et un seul réglage à la fois dans la requête
/// (``TripSettingsEdit``), pour ne pas écraser ce qu'un co-voyageur aurait
/// changé entre-temps.
@MainActor
@Observable
public final class TripSettingsModel {
    public private(set) var settings: TripSettings?
    public private(set) var errorMessage: String?

    /// Ce qu'on peut **faire** de l'erreur, sous sa phrase — voir
    /// `APIError.recoveryAdvice`. « Erreur interne du serveur » seul laissait
    /// chercher ce qu'on avait mal fait (Hugo, 15/09/2026).
    public private(set) var errorAdvice: String?

    private let tripId: String
    private let source: (String) async throws -> TripSettings
    private let persist: ((String, TripSettingsEdit) async throws -> TripSettings)?

    /// Ce qu'on avait sur le disque — voir ``ContentCache``. `nil` en aperçu.
    private let cached: CachedValue<TripSettings>?

    /// Ce que le dernier chargement a appris. C'est lui que la vue anime —
    /// voir ``SwiftUI/View/brandRefreshFlash(_:)``.
    public private(set) var freshness: ContentFreshness = .unknown

    /// Supprimer le voyage — **le propriétaire seul**, et le serveur le
    /// vérifie. `nil` en aperçu : on ne supprime pas un voyage depuis une
    /// maquette.
    private let remove: ((String) async throws -> Void)?

    /// Supprimer la conversation — tout le monde y a droit, contrairement au
    /// voyage : c'est le fil qu'on efface, pas le récit des autres. `nil` en
    /// aperçu, où la feuille se joue quand même.
    private let clearConversation: ((String) async throws -> Void)?

    /// L'inverse, pour le bac à sable — voir ``ConversationArchive/restore(tripId:)``.
    private let restoreConversation: ((String) -> Void)?

    /// Relève le palier de limites de souvenirs. `nil` en aperçu — la feuille
    /// travaille alors en mémoire et le parcours se déroule quand même.
    private let setPlan: ((String, MemoryPlan) async throws -> TripSettings)?

    /// `true` pendant le changement de palier. Le bouton de la feuille tourne,
    /// et ne part pas deux fois.
    public private(set) var isChangingMemoryPlan = false

    /// `true` pendant la suppression. L'écran verrouille alors la feuille : la
    /// demande est définitive, elle ne doit pas partir deux fois.
    public private(set) var isDeleting = false

    /// `true` pendant la suppression de la conversation. Même verrou que pour
    /// le voyage : la feuille ne repart pas deux fois.
    public private(set) var isClearingConversation = false

    /// L'envoi en cours. Le garder permet d'annuler celui d'avant quand deux
    /// bascules s'enchaînent : c'est la dernière qui compte, et la réponse
    /// d'une requête dépassée réécrirait l'écran avec une valeur périmée.
    private var pendingSave: Task<Void, Never>?

    /// Retirer un co-voyageur, et renvoyer son lien d'invitation. Deux gestes
    /// que le `PATCH` des réglages ne sait pas porter : ils touchent
    /// `memo_members`, pas `memos`.
    private let removeCompanion: ((String, String) async throws -> TripSettings)?
    private let resendInvitation: ((String, String) async throws -> Void)?

    /// Ce qu'on vient de faire, et qu'il faut dire. Un mot sous la liste de la
    /// feuille — « Invitation renvoyée » —, pas une alerte : l'action a réussi,
    /// il n'y a rien à confirmer.
    public private(set) var confirmation: String?

    /// Les thèmes de voyage, dans l'ordre du serveur — « Autre » en dernier.
    ///
    /// **La même source qu'à la création du voyage**, et c'est la note du nœud
    /// qui l'exige : « les thèmes doivent venir de la même base de données que
    /// lors de la création ». Un second jeu ici ferait dériver `memos.theme`,
    /// que l'agent de rédaction lit tel quel.
    public private(set) var themes: [TripTheme] = []

    private let readThemes: @Sendable () async throws -> [TripTheme]

    public init(
        tripId: String,
        source: @escaping (String) async throws -> TripSettings = { _ in .fixture },
        persist: ((String, TripSettingsEdit) async throws -> TripSettings)? = nil,
        removeCompanion: ((String, String) async throws -> TripSettings)? = nil,
        resendInvitation: ((String, String) async throws -> Void)? = nil,
        delete: ((String) async throws -> Void)? = nil,
        clearConversation: ((String) async throws -> Void)? = nil,
        restoreConversation: ((String) -> Void)? = nil,
        setMemoryPlan: ((String, MemoryPlan) async throws -> TripSettings)? = nil,
        cached: CachedValue<TripSettings>? = nil,
        themes: @escaping @Sendable () async throws -> [TripTheme] = { TripTheme.fixtures }
    ) {
        self.cached = cached
        self.tripId = tripId
        self.source = source
        self.persist = persist
        self.removeCompanion = removeCompanion
        self.resendInvitation = resendInvitation
        self.remove = delete
        self.clearConversation = clearConversation
        self.restoreConversation = restoreConversation
        self.setPlan = setMemoryPlan
        self.readThemes = themes
    }

    // MARK: - Les limites de souvenirs

    /// Où en est le compte. `nil` quand le serveur ne les sert pas encore : la
    /// ligne disparaît alors, plutôt que d'annoncer un budget inventé.
    public var memory: MemoryAllowance? { settings?.memory }

    #if DEBUG
        /// Rejoue un état des limites de souvenirs, **sans rien envoyer**.
        ///
        /// Les deux seuils que le jeu d'essai ne montre pas : celui où la jauge
        /// apparaît (80 %), et celui où tout est consommé. Ce sont les deux
        /// états dont le dessin n'existe nulle part ailleurs — le reste se voit
        /// en ouvrant l'écran. Absent de l'app livrée.
        public func debugPlayMemory(fraction: Double) {
            guard var current = settings, var memory = current.memory else { return }
            memory.used = Int(Double(memory.allowance) * fraction)
            current.memory = memory
            settings = current
        }
    #endif

    /// Passe au palier étendu, ou revient au palier compris.
    ///
    /// **Rien n'est posé à l'écran avant la réponse**, contrairement aux
    /// réglages d'à côté : ceux-là sont des préférences, celui-ci est un achat.
    /// Montrer « 12 000 souvenirs » avant que le serveur l'ait accordé serait
    /// annoncer une limite qu'on n'a pas.
    @discardableResult
    public func changeMemoryPlan(to plan: MemoryPlan) async -> Bool {
        guard let setPlan else { return false }

        isChangingMemoryPlan = true
        defer { isChangingMemoryPlan = false }

        do {
            settings = try await setPlan(tripId, plan)
            clearError()
            return true
        } catch {
            report(error)
            return false
        }
    }

    /// Les thèmes, chargés à l'ouverture de leur feuille et pas avant : c'est
    /// un appel de plus, et la plupart des visites de cet écran ne changent pas
    /// de thème. Un échec laisse la rangée vide et le champ libre ouvert — on
    /// peut toujours écrire son thème à la main.
    public func loadThemes() async {
        guard themes.isEmpty else { return }
        themes = (try? await readThemes()) ?? []
    }

    /// `true` tant qu'on n'a pas de valeurs. L'écran se dessine quand même :
    /// ses intitulés, ses groupes et ses lignes appartiennent à l'app, pas au
    /// serveur. Seules les valeurs portent une barre d'attente — voir
    /// ``BrandSkeleton``.
    public var isLoading: Bool { settings == nil && errorMessage == nil }

    public func load() async {
        // Trente valeurs pour un écran qu'on ouvre pour en changer une : c'est
        // celui qui gagne le plus à s'ouvrir sur ce qu'on avait.
        if settings == nil, let stored = await cached?() {
            settings = stored
            freshness = .restored
        }

        do {
            let loaded = try await source(tripId)
            freshness = contentFreshness(of: loaded, replacing: settings)
            settings = loaded
            clearError()
        } catch {
            report(error)
        }
    }

    // MARK: - Supprimer le voyage

    /// Supprime le voyage et tout ce qui est à lui. Renvoie `true` quand c'est
    /// fait — c'est le signal qui ramène l'app à l'accueil.
    ///
    /// L'écran a déjà demandé confirmation : ce n'est pas au modèle de la
    /// redemander, et il n'y a rien à annuler après. Un refus du serveur — un
    /// co-voyageur qui essaie, le propriétaire seul y a droit — reste à
    /// l'écran, dans la feuille.
    public func delete() async -> Bool {
        guard let remove else { return false }

        isDeleting = true
        defer { isDeleting = false }

        do {
            try await remove(tripId)
            clearError()
            return true
        } catch {
            report(error)
            return false
        }
    }

    // MARK: - Supprimer la conversation

    /// Efface le fil de la conversation — les messages, pas le mot d'accueil
    /// de MEMO, qui est là pour quiconque n'a rien dit encore. Renvoie `true`
    /// quand c'est fait : la feuille se ferme, et on reste sur les réglages.
    ///
    /// L'écran a déjà demandé confirmation, comme pour le voyage. Sans
    /// fonction — en aperçu —, la feuille se ferme comme si c'était fait.
    public func clearConversation() async -> Bool {
        guard let clearConversation else { return true }

        isClearingConversation = true
        defer { isClearingConversation = false }

        do {
            try await clearConversation(tripId)
            clearError()
            return true
        } catch {
            report(error)
            return false
        }
    }

    #if DEBUG
        /// Fait revenir la conversation supprimée. Bac à sable seulement.
        public func debugRestoreConversation() {
            restoreConversation?(tripId)
        }
    #endif

    /// Pose l'erreur **et son conseil** : la phrase dit ce qui s'est passé, le
    /// conseil ce qu'on peut faire.
    private func report(_ error: any Error) {
        errorMessage = error.localizedDescription
        errorAdvice = (error as? APIError)?.recoveryAdvice
    }

    private func clearError() {
        errorMessage = nil
        errorAdvice = nil
    }

    // MARK: - Ce qu'on change depuis l'écran
    //
    // Des méthodes plutôt qu'un `settings` ouvert en écriture : une vue ne doit
    // pas pouvoir poser une valeur sans qu'elle partie au serveur.

    public func setNotifications(_ isOn: Bool) {
        guard var current = settings else { return }
        current.wantsNotifications = isOn
        settings = current
        save(.notifications(isOn))
    }

    public func setPublicGallery(_ isOn: Bool) {
        guard var current = settings else { return }
        current.isPublicGallery = isOn
        settings = current
        save(.publicGallery(isOn))
    }

    /// Les deux dates d'un coup : elles se bornent l'une l'autre, et les
    /// envoyer séparément ferait refuser l'intermédiaire par le serveur.
    public func setDates(start: Date?, end: Date?) {
        guard var current = settings else { return }
        current.startDate = start
        current.endDate = end
        settings = current
        save(.dates(start: start, end: end))
    }

    public func setPace(_ pace: NarrationPace) {
        guard var current = settings else { return }
        current.narrationPace = pace
        settings = current
        save(.narrationPace(pace))
    }

    public func setTheme(_ theme: String) {
        let trimmed = theme.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var current = settings, !trimmed.isEmpty, trimmed != current.theme else { return }
        current.theme = trimmed
        settings = current
        save(.theme(trimmed))
    }

    public func setNotificationPreferences(_ preferences: TripNotificationPreferences) {
        guard var current = settings else { return }
        current.notifications = preferences
        settings = current
        save(.notificationPreferences(preferences))
    }

    // MARK: - Les co-voyageurs

    /// Retire quelqu'un du voyage.
    ///
    /// **Le propriétaire ne se retire pas** — c'est la note « Logique » de la
    /// maquette, et c'est aussi ce que le serveur refuserait. Le garde-fou est
    /// ici pour que l'action ne soit pas *proposée*, pas pour rattraper un
    /// appel.
    public func remove(_ companion: Companion) {
        guard let removeCompanion, !companion.isOwner, var current = settings else { return }

        // L'écran a déjà bougé : une ligne qui reste en place le temps d'un
        // aller-retour donne l'impression que le geste n'a pas pris.
        current.companions.removeAll { $0.id == companion.id }
        settings = current

        pendingSave?.cancel()
        pendingSave = Task {
            do {
                let updated = try await removeCompanion(tripId, companion.id)
                guard !Task.isCancelled else { return }
                settings = updated
                errorMessage = nil
            } catch {
                guard !Task.isCancelled else { return }
                report(error)
                await load()
            }
        }
    }

    /// Renvoie le lien d'invitation à quelqu'un qui n'est jamais entré.
    public func resendInvitation(to companion: Companion) {
        guard let resendInvitation, companion.isPending else { return }

        Task {
            do {
                try await resendInvitation(tripId, companion.id)
                confirm(BookCopy.Invite.resent(companion.name))
            } catch {
                report(error)
            }
        }
    }

    /// Un mot qui s'efface tout seul. Il ne demande rien, il **accuse
    /// réception** — le laisser à l'écran obligerait à le refermer.
    private func confirm(_ message: String) {
        confirmation = message
        Task {
            try? await Task.sleep(for: .seconds(4))
            guard confirmation == message else { return }
            confirmation = nil
        }
    }

    /// Envoie un réglage, et remplace l'écran par ce que le serveur relit.
    ///
    /// **L'écran a déjà bougé** quand on arrive ici : un interrupteur qui
    /// attend un aller-retour réseau pour basculer se lit comme cassé. La
    /// réponse ne fait que confirmer — ou, en cas d'échec, remettre les
    /// valeurs du serveur, ce qui annule visiblement la bascule.
    private func save(_ edit: TripSettingsEdit) {
        guard let persist else { return }

        pendingSave?.cancel()
        pendingSave = Task {
            do {
                let updated = try await persist(tripId, edit)
                guard !Task.isCancelled else { return }
                settings = updated
                clearError()
            } catch {
                guard !Task.isCancelled else { return }
                report(error)
                // Remettre ce que le serveur a vraiment : sans ça,
                // l'interrupteur resterait sur une valeur que personne n'a
                // enregistrée.
                await load()
            }
        }
    }

    #if DEBUG
        /// Vide les valeurs pour rejouer l'état de chargement. Absent de l'app
        /// livrée.
        func debugShowSkeleton() {
            settings = nil
            clearError()
        }
    #endif
}
