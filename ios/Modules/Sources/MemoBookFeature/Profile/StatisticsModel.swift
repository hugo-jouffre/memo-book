import Foundation
import MemoBookCore
import Observation

/// Ce que la feuille « Statistiques » sait faire : lire les chiffres, et les
/// **relire tant que l'agent en relève de nouveaux**.
///
/// Même construction que ``ProfileModel`` — une fonction qui lit, une case de
/// cache — avec une chose en plus : la veille. Le serveur dit combien de
/// souvenirs attendent encore leur relevé (`pendingDetections`) ; tant qu'il y
/// en a, le modèle relit la feuille toutes les quelques secondes, et un
/// chiffre qui vient d'être relevé apparaît sous les yeux. Dès que la file est
/// vide, la veille s'arrête : pas de requête à vide sur un voyage immobile.
///
/// **Aucune connexion ouverte, et c'est un choix.** Un flux serveur aurait
/// été plus « instantané » d'une seconde, et aurait demandé une seconde forme
/// de client d'API pour une feuille qu'on regarde trente secondes. La relance
/// s'arrête toute seule, elle ne coûte rien le reste du temps.
@MainActor
@Observable
public final class StatisticsModel {
    public private(set) var statistics: TravelStatistics?
    public private(set) var errorMessage: String?

    /// Ce que le dernier chargement a appris. **Comparé sur les chiffres, pas
    /// sur l'horodatage** : deux lectures à trois secondes d'écart sur un
    /// voyage immobile ne doivent pas faire clignoter la feuille.
    public private(set) var freshness: ContentFreshness = .unknown

    private let source: () async throws -> TravelStatistics
    private let cached: CachedValue<TravelStatistics>?

    /// La file des vocaux, pour savoir qu'un souvenir vient de partir.
    ///
    /// La feuille ne l'interroge pas : elle lit ``deliveries``, et relance sa
    /// veille quand le compteur bouge — c'est le même signal qui recharge
    /// l'accueil. `nil` en aperçu, où rien ne part.
    private let outbox: RecordingOutbox?

    /// Le temps entre deux relectures pendant qu'un relevé est en cours.
    ///
    /// Trois secondes : la rédaction d'un souvenir prend dix à trente secondes,
    /// et l'œil ne fait pas la différence entre un chiffre arrivé une seconde ou
    /// trois secondes après. En dessous, on frapperait le serveur pour rien.
    static let pollInterval: Duration = .seconds(3)

    /// Combien de relectures **sans changement** avant de lâcher la veille —
    /// deux minutes, à trois secondes l'une.
    ///
    /// Un souvenir peut rester « en attente » pour de mauvaises raisons : un
    /// worker tombé, un job perdu, un jeu d'essai qui n'a jamais enfilé sa
    /// rédaction. Sans borne, la feuille frapperait le serveur toutes les
    /// trois secondes tant qu'elle est ouverte. Passé ce cap, elle s'arrête ;
    /// un vocal livré ou une réouverture la relancent.
    static let maxUnchangedPolls = 40

    /// - Parameters:
    ///   - source: d'où viennent les chiffres. Par défaut, le jeu d'essai.
    ///   - cached: ce qu'on avait sur le disque — voir ``ContentCache``. `nil`
    ///     en aperçu.
    ///   - outbox: la file des vocaux de l'app, dont le compteur de livraisons
    ///     relance la veille. `nil` en aperçu.
    public init(
        source: @escaping () async throws -> TravelStatistics = { .fixture },
        cached: CachedValue<TravelStatistics>? = nil,
        outbox: RecordingOutbox? = nil
    ) {
        self.source = source
        self.cached = cached
        self.outbox = outbox
    }

    /// Combien de vocaux sont arrivés depuis le lancement. La feuille s'en
    /// sert comme **identifiant de sa veille** : à chaque changement, la tâche
    /// repart et relit tout de suite, sans attendre la prochaine relance.
    public var deliveries: Int { outbox?.deliveries ?? 0 }

    /// `true` tant qu'on n'a rien à montrer. La feuille se dessine quand même,
    /// avec des barres d'attente à la place des chiffres.
    public var isLoading: Bool { statistics == nil && errorMessage == nil }

    /// `true` tant que le serveur relit des souvenirs. La feuille le dit d'une
    /// ligne, et c'est ce qui tient la veille éveillée.
    public var isDetecting: Bool { statistics?.isDetecting ?? false }

    /// Une lecture, du disque puis du serveur.
    public func load() async {
        if statistics == nil, let stored = await cached?() {
            statistics = stored
            freshness = .restored
        }

        do {
            let loaded = try await source()
            freshness = freshness(of: loaded)
            statistics = loaded
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Lit, puis **veille** : relit à intervalle court tant que le serveur
    /// annonce des relevés en attente, et s'arrête dès qu'il n'y en a plus.
    ///
    /// À lancer depuis un `.task` de la vue : c'est lui qui l'annule quand la
    /// feuille se referme, et qui le relance quand un vocal vient de partir
    /// (`task(id:)` sur le compteur de livraisons de la file). Une panne réseau
    /// au milieu ne tue pas la veille tant qu'un relevé était attendu : la
    /// relance suivante réessaie, et le bandeau d'erreur dit pourquoi en
    /// attendant. Sans rien à attendre, on s'arrête — le bandeau a son bouton.
    public func watch() async {
        await load()

        var unchanged = 0
        while !Task.isCancelled, isDetecting, unchanged < Self.maxUnchangedPolls {
            try? await Task.sleep(for: Self.pollInterval)
            guard !Task.isCancelled else { return }
            await load()
            unchanged = freshness.isUpdated ? 0 : unchanged + 1
        }
    }

    private func freshness(of incoming: TravelStatistics) -> ContentFreshness {
        guard let shown = statistics else { return .unchanged }
        return shown.hasSameFigures(as: incoming) ? .unchanged : .updated
    }
}
