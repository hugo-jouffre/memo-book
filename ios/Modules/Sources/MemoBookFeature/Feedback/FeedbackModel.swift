import Foundation
import MemoBookCore
import MemoBookNetworking

/// **Ce que l'app fait d'une demande d'avis** (T273).
///
/// Il demande la campagne une fois, décide si elle se montre, retient les
/// réponses pendant qu'on écrit, et dit au serveur ce qu'on en a fait — qu'on
/// ait répondu ou fermé.
///
/// ⚠️ **Demander la campagne compte comme un affichage** côté serveur
/// (`displayCount`, que `maxDisplays` borne). Le modèle ne la demande donc
/// qu'une fois par lancement, et seulement là où la modale paraîtra vraiment.
@MainActor
@Observable
public final class FeedbackModel {
    /// La campagne à montrer. `nil` : il n'y en a pas, et c'est le cas le
    /// plus fréquent.
    public private(set) var campaign: FeedbackCampaign?

    /// Ce qui a été répondu, par identifiant de question.
    public private(set) var answers: [String: FeedbackAnswer] = [:]

    public private(set) var isSending = false

    private let load: @Sendable () async throws -> FeedbackCampaign?
    private let submit: @Sendable (String, FeedbackResponse) async throws -> Void
    private let appVersion: String?
    private var hasAsked = false

    public init(
        load: @escaping @Sendable () async throws -> FeedbackCampaign?,
        submit: @escaping @Sendable (String, FeedbackResponse) async throws -> Void,
        appVersion: String? = nil
    ) {
        self.load = load
        self.submit = submit
        self.appVersion = appVersion
    }

    /// Demande la campagne, **une seule fois par lancement**.
    ///
    /// Une campagne que cette version ne sait pas dessiner entière est
    /// écartée ici : elle a déjà compté comme un affichage côté serveur, et
    /// c'est tant pis — mieux vaut un affichage perdu qu'une modale à trous.
    /// Elle reparaîtra d'elle-même quand l'app saura la dessiner.
    public func askOnce() async {
        guard !hasAsked else { return }
        hasAsked = true
        // Un échec ne se dit pas : personne n'a demandé à voir cette modale,
        // et un bandeau d'erreur pour un avis qu'on n'a pas sollicité serait
        // du bruit sur l'accueil.
        guard let fetched = try? await load() else { return }
        guard fetched.isDrawable else { return }
        campaign = fetched
    }

    public func answer(_ question: FeedbackQuestion, text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        answers[question.id] =
            trimmed.isEmpty ? nil : FeedbackAnswer(questionId: question.id, text: trimmed)
    }

    public func answer(_ question: FeedbackQuestion, choice key: String) {
        answers[question.id] = FeedbackAnswer(questionId: question.id, choiceKey: key)
    }

    public func chosenKey(for question: FeedbackQuestion) -> String? {
        answers[question.id]?.choiceKey
    }

    /// Un curseur ou une note : la valeur retenue part dans `number`.
    public func answer(_ question: FeedbackQuestion, number: Int) {
        answers[question.id] = FeedbackAnswer(questionId: question.id, number: Double(number))
    }

    /// Ce qui a été réglé, ou `nil` — **et `nil` veut dire « pas répondu »**.
    ///
    /// C'est pour ça qu'un curseur ne part pas avec une valeur par défaut :
    /// une note de 3 sur 5 que personne n'a touchée serait un avis inventé.
    /// La vue montre une position de départ, le modèle n'en retient aucune
    /// tant que le doigt n'a rien bougé.
    public func number(for question: FeedbackQuestion) -> Int? {
        answers[question.id]?.number.map { Int($0.rounded()) }
    }

    /// Le bouton d'envoi est-il ouvert ? Toutes les questions **obligatoires**
    /// doivent avoir leur réponse — les autres peuvent rester vides, et c'est
    /// ce qui permet de n'écrire qu'un mot.
    public var canSubmit: Bool {
        guard let campaign else { return false }
        return campaign.questions.filter(\.isRequired).allSatisfy { answers[$0.id] != nil }
    }

    /// « Envoyer ». La modale se referme **tout de suite** : ce qu'on vient
    /// d'écrire est parti, et attendre le réseau pour fermer ferait douter.
    public func send() {
        guard let campaign, canSubmit, !isSending else { return }
        let response = FeedbackResponse(
            appVersion: appVersion,
            answers: campaign.questions.compactMap { answers[$0.id] }
        )
        deliver(response, of: campaign.id)
    }

    /// La croix, ou le geste qui referme la feuille. **Fermer est un
    /// résultat** : le serveur l'apprend, et ne repropose pas la campagne.
    public func dismiss() {
        guard let campaign else { return }
        deliver(FeedbackResponse(dismissed: true, appVersion: appVersion), of: campaign.id)
    }

    private func deliver(_ response: FeedbackResponse, of campaignId: String) {
        campaign = nil
        answers = [:]
        isSending = true
        Task { [submit] in
            // Un envoi qui échoue ne se dit pas non plus : la modale est
            // partie, et la redemander pour annoncer une panne d'avis serait
            // demander deux fois.
            try? await submit(campaignId, response)
            self.isSending = false
        }
    }
}
