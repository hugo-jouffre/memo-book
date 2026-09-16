import Foundation
import MemoBookCore
import Observation

/// Ce que l'écran de support sait faire : servir la foire aux questions, retenir
/// si une réponse a aidé, et porter un message jusqu'à l'équipe.
///
/// Même construction que ``BookCustomisationModel`` : le modèle ne connaît pas
/// l'API, il reçoit des fonctions. Les aperçus n'en fournissent aucune et
/// travaillent en mémoire.
///
/// **La foire aux questions arrive elle aussi par une fonction**, alors qu'elle
/// est statique aujourd'hui. C'est voulu : la page Notion demande que le contenu
/// soit « servi depuis une source distante, pas figé dans le binaire, pour
/// corriger une réponse sans passer par une mise à jour App Store ». Le jour où
/// la route existe, c'est ce seul branchement qui change — ni l'écran, ni la
/// feuille.
@MainActor
@Observable
public final class SupportModel {
    /// Les neuf paquets de « sujets courants ».
    public private(set) var topics: [FaqCategory]

    /// Le paquet « Nous contacter », qui a sa propre section sur l'écran.
    public private(set) var contact: FaqCategory

    /// Les valeurs qui bougent — seuils, prix, délais —, résolues à
    /// l'affichage. Voir ``FaqVariables``.
    public private(set) var variables: FaqVariables

    /// Où en est l'envoi d'un message.
    public enum SendState: Equatable {
        case idle
        case sending
        case sent
        case failed(String)
    }

    public private(set) var sendState: SendState = .idle

    /// Ce que le lecteur a répondu à « Est-ce utile ? », par identifiant de
    /// question.
    ///
    /// **Gardé pour la session seulement.** La mesure, elle, part au serveur —
    /// c'est elle qui compte. Ceci ne sert qu'à remplacer les deux pouces par un
    /// merci une fois qu'on a voté : les laisser actifs invite à voter deux
    /// fois, et fausserait justement la mesure.
    public private(set) var votes: [String: Bool] = [:]

    /// Ce qu'on cherche. Vide, l'écran montre les dix paquets tels quels.
    ///
    /// **La recherche vit dans le modèle et non dans la vue**, comme les trois
    /// listes triées de l'accueil : filtrer quarante-cinq questions et leurs
    /// réponses à chaque passage dans un `body`, c'est le refaire à chaque
    /// image d'animation. Ici c'est refait à chaque frappe, et pas plus.
    public var search = "" {
        didSet {
            guard search != oldValue else { return }
            apply(FaqQuery(search))
        }
    }

    /// Les paquets qui répondent à ce qu'on cherche, déjà réduits à leurs
    /// questions retenues.
    public private(set) var visibleTopics: [FaqCategory] = []

    /// Le paquet « Nous contacter », filtré lui aussi. `nil` quand rien n'y
    /// répond : sa section disparaît alors, sauf la ligne « J'ai encore une
    /// question », qui reste — c'est la sortie de secours d'une recherche qui
    /// ne trouve rien.
    public private(set) var visibleContact: FaqCategory?

    /// On cherche quelque chose.
    public var isSearching: Bool { !FaqQuery(search).isEmpty }

    /// On cherche, et rien ne répond. L'écran le dit et propose d'écrire.
    public var hasNoResults: Bool {
        isSearching && visibleTopics.isEmpty && visibleContact == nil
    }

    /// Combien de questions la recherche a retenues, pour l'annoncer.
    public var resultCount: Int {
        visibleTopics.reduce(0) { $0 + $1.entries.count } + (visibleContact?.entries.count ?? 0)
    }

    private let submit: ((String) async throws -> Void)?
    private let record: ((String, Bool) async -> Void)?

    /// - Parameters:
    ///   - submit: envoie un message à l'équipe. `nil` pour les aperçus : la
    ///     feuille fait alors comme si, ce qui permet de dérouler les trois
    ///     étapes sans réseau.
    ///   - record: enregistre un vote « cette réponse t'a-t-elle aidé ». `nil`
    ///     quand rien n'écoute — le vote reste alors local.
    public init(
        topics: [FaqCategory] = Faq.topics,
        contact: FaqCategory = Faq.contact,
        variables: FaqVariables = .current,
        submit: ((String) async throws -> Void)? = nil,
        record: ((String, Bool) async -> Void)? = nil
    ) {
        self.topics = topics
        self.contact = contact
        self.variables = variables
        self.submit = submit
        self.record = record
        visibleTopics = topics
        visibleContact = contact
    }

    /// Range ce que la recherche retient. Appelé à chaque frappe, et là
    /// seulement.
    private func apply(_ query: FaqQuery) {
        visibleTopics = topics.compactMap { $0.filtered(by: query, variables: variables) }
        visibleContact = contact.filtered(by: query, variables: variables)
    }

    /// Efface la recherche — la croix du champ, et la fermeture de l'écran.
    public func clearSearch() {
        search = ""
    }

    /// La réponse d'une question, variables résolues.
    public func answer(for entry: FaqEntry) -> [String] {
        entry.answer(with: variables)
    }

    public func vote(_ isHelpful: Bool, on entry: FaqEntry) {
        guard votes[entry.id] == nil else { return }
        votes[entry.id] = isHelpful
        Task { await record?(entry.id, isHelpful) }
    }

    /// Envoie le message, et dit ce qu'il devient.
    ///
    /// Sans fonction d'envoi — les aperçus, et l'app tant que la route n'existe
    /// pas —, la feuille marque une pause avant de confirmer plutôt que de
    /// sauter à l'étape suivante : une confirmation instantanée se lit comme un
    /// bouton qui n'a rien fait.
    public func send(_ message: String) async {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        sendState = .sending
        do {
            if let submit {
                try await submit(trimmed)
            } else {
                try await Task.sleep(for: .milliseconds(600))
            }
            sendState = .sent
        } catch {
            sendState = .failed(SupportCopy.Contact.sendFailed)
        }
    }

    /// Remet le formulaire à zéro — à la fermeture de la feuille, pour que la
    /// suivante ne s'ouvre pas sur la confirmation de la précédente.
    public func resetSending() {
        sendState = .idle
    }
}
