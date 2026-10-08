import Foundation
import MemoBookCore
import MemoBookNetworking
import Observation
import UIKit

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
    /// **Relu du serveur** à chaque compte (`GET /v1/support/faq-votes`,
    /// T226) : une question déjà votée garde son « Merci ! » d'une session à
    /// l'autre. Ceci ne sert qu'à remplacer les deux pouces par un merci une
    /// fois qu'on a voté : les laisser actifs invite à voter deux fois, et
    /// fausserait justement la mesure.
    ///
    /// **Le merci attend le serveur** : un vote n'entre ici qu'une fois reçu.
    public private(set) var votes: [String: Bool] = [:]

    /// Les votes partis, pas encore reçus : les pouces se figent le temps de
    /// la réponse.
    public private(set) var pendingVotes: Set<String> = []

    /// Le vote qui n'a pas pu partir, et pourquoi — sous ses pouces, rendus
    /// actifs pour réessayer.
    public private(set) var voteFailure: (questionId: String, message: String)?

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

    /// Ce qui relie le support au serveur — voir ``SupportBackend``. `nil`
    /// pour les aperçus : la feuille fait alors comme si, ce qui permet de
    /// dérouler les trois étapes sans réseau.
    private var backend: SupportBackend?

    /// - Parameter backend: les trois routes du support. `RootView` le pose
    ///   à chaque compte (``connect(_:)``) : le modèle vit toute la session de
    ///   l'app, l'API arrive avec le compte.
    public init(
        topics: [FaqCategory] = Faq.topics,
        contact: FaqCategory = Faq.contact,
        variables: FaqVariables = .current,
        backend: SupportBackend? = nil
    ) {
        self.topics = topics
        self.contact = contact
        self.variables = variables
        self.backend = backend
        visibleTopics = topics
        visibleContact = contact
    }

    /// Branche le support sur le compte qui vient d'entrer, et relit ses
    /// votes. **Les votes du compte d'avant s'effacent** : ce ne sont pas
    /// les siens.
    public func connect(_ backend: SupportBackend?) async {
        self.backend = backend
        votes = [:]
        pendingVotes = []
        voteFailure = nil
        sendState = .idle
        await loadVotes()
    }

    /// Relit les votes déjà donnés. Un échec ne dit rien : les pouces restent,
    /// et un vote de plus remplacera l'ancien côté serveur.
    public func loadVotes() async {
        guard let backend, let served = try? await backend.loadVotes() else { return }
        for vote in served where pendingVotes.contains(vote.questionId) == false {
            votes[vote.questionId] = vote.isHelpful
        }
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

    /// Vote « Est-ce utile ? » — et ne dit « Merci ! » qu'une fois le vote
    /// reçu (T226). Hors ligne, les pouces reviennent avec une ligne qui le
    /// dit : un merci pour un vote perdu fausserait la mesure qu'il sert.
    public func vote(_ isHelpful: Bool, on entry: FaqEntry) async {
        guard votes[entry.id] == nil, !pendingVotes.contains(entry.id) else { return }
        guard let backend else {
            votes[entry.id] = isHelpful
            return
        }

        pendingVotes.insert(entry.id)
        if voteFailure?.questionId == entry.id { voteFailure = nil }
        defer { pendingVotes.remove(entry.id) }
        do {
            try await backend.vote(entry.id, isHelpful)
            votes[entry.id] = isHelpful
        } catch {
            voteFailure = (entry.id, Self.isOffline(error) ? SupportCopy.Answer.voteOffline : SupportCopy.Answer.voteFailed)
        }
    }

    /// Envoie le message, et dit ce qu'il devient — **« envoyé » seulement
    /// une fois que le serveur l'a reçu** (Hugo, 06/10/2026, T226).
    ///
    /// Sans serveur — les aperçus —, la feuille marque une pause avant de
    /// confirmer plutôt que de sauter à l'étape suivante : une confirmation
    /// instantanée se lit comme un bouton qui n'a rien fait.
    ///
    /// - Parameters:
    ///   - source: le formulaire du support, ou « Partager mes retours ».
    ///   - topicId: la question de « Nous contacter » qui a ouvert le
    ///     formulaire.
    ///   - tripId: le voyage d'où l'on écrit.
    public func send(
        _ message: String,
        source: SupportMessage.Source = .support,
        topicId: String? = nil,
        tripId: String? = nil
    ) async {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, sendState != .sending else { return }

        sendState = .sending
        do {
            if let backend {
                try await backend.send(
                    SupportMessage(
                        source: source,
                        topicId: topicId,
                        message: trimmed,
                        tripId: tripId,
                        appVersion: SupportDevice.appVersion,
                        diagnostics: SupportDevice.diagnostics
                    )
                )
            } else {
                try await Task.sleep(for: .milliseconds(600))
            }
            sendState = .sent
        } catch {
            sendState = .failed(Self.sendFailure(for: error))
        }
    }

    /// Ce que le formulaire dit quand le message n'est pas parti : pas de
    /// réseau, trop de messages aujourd'hui, ou le reste.
    static func sendFailure(for error: any Error) -> String {
        if isOffline(error) { return SupportCopy.Contact.sendOffline }
        if (error as? APIError)?.code == "support_rate_limited" { return SupportCopy.Contact.sendRateLimited }
        return SupportCopy.Contact.sendFailed
    }

    private static func isOffline(_ error: any Error) -> Bool {
        if let api = error as? APIError { return api.isTransport }
        return error is URLError
    }

    /// Remet le formulaire à zéro — à la fermeture de la feuille, pour que la
    /// suivante ne s'ouvre pas sur la confirmation de la précédente.
    public func resetSending() {
        sendState = .idle
    }
}

/// Les trois routes du support (contrat du 06/10/2026, point 4), en
/// fonctions — le modèle ne connaît pas l'API.
public struct SupportBackend: Sendable {
    /// `POST /v1/support/messages`.
    public var send: @Sendable (SupportMessage) async throws -> Void
    /// `PUT /v1/support/faq-votes/:questionId`.
    public var vote: @Sendable (_ questionId: String, _ isHelpful: Bool) async throws -> Void
    /// `GET /v1/support/faq-votes`.
    public var loadVotes: @Sendable () async throws -> [FaqVote]

    public init(
        send: @escaping @Sendable (SupportMessage) async throws -> Void,
        vote: @escaping @Sendable (String, Bool) async throws -> Void,
        loadVotes: @escaping @Sendable () async throws -> [FaqVote]
    ) {
        self.send = send
        self.vote = vote
        self.loadVotes = loadVotes
    }

    /// Les trois routes, sur l'API du compte.
    public init(api: any MemoBookAPI) {
        self.init(
            send: { try await api.sendSupportMessage($0) },
            vote: { try await api.voteOnFaq(questionId: $0, isHelpful: $1, appVersion: SupportDevice.appVersion) },
            loadVotes: { try await api.faqVotes() }
        )
    }
}

/// Ce que le diagnostic dit de l'appareil — et rien d'autre.
enum SupportDevice {
    /// « 0.1.0 (21) ».
    static var appVersion: String? {
        let info = Bundle.main.infoDictionary
        guard let short = info?["CFBundleShortVersionString"] as? String else { return nil }
        guard let build = info?["CFBundleVersion"] as? String else { return short }
        return "\(short) (\(build))"
    }

    /// « iOS 26.0 », « iPhone17,1 », « fr_FR ».
    @MainActor static var diagnostics: SupportDiagnostics {
        var system = utsname()
        uname(&system)
        let model = withUnsafeBytes(of: &system.machine) { raw in
            String(decoding: raw.prefix { $0 != 0 }, as: UTF8.self)
        }
        return SupportDiagnostics(
            osVersion: "\(UIDevice.current.systemName) \(UIDevice.current.systemVersion)",
            deviceModel: model,
            locale: Locale.current.identifier
        )
    }
}
