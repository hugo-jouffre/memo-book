import Foundation

/// Une source d'écran qui peut répondre **deux fois** : ce qu'on avait, puis ce
/// qui arrive.
///
/// **C'est la seule pièce que le cache ajoute aux modèles d'écran.** Ils
/// recevaient une fonction `() async throws -> Value` ; ils reçoivent en plus
/// une fonction qui rend ce qui est sur le disque, tout de suite et sans
/// pouvoir échouer. Le modèle s'en sert dans cet ordre, et c'est tout ce qu'il
/// a à savoir :
///
/// ```swift
/// public func load() async {
///     if value == nil, let stored = cached?() { apply(stored, isFresh: false) }
///     do { apply(try await source(), isFresh: true) } catch { … }
/// }
/// ```
///
/// **Pourquoi pas un flux.** Un `AsyncStream` aurait été la forme savante, et
/// elle aurait demandé de réécrire les cinq modèles, leurs aperçus et leurs
/// tests pour un gain nul : il y a exactement deux valeurs, la première est
/// synchrone, et la seconde est celle qu'on a toujours attendue.
///
/// **Le cache n'est jamais la réponse finale.** Un écran servi par le disque
/// reste « en chargement » du point de vue de l'utilisateur — la lecture réseau
/// continue derrière —, et un échec de celle-ci laisse le contenu du disque en
/// place avec son bandeau. C'est ce que fait déjà l'accueil hors ligne.
public typealias CachedValue<Value> = @Sendable () async -> Value?

/// Ce qu'un écran vient d'apprendre, et s'il faut l'animer.
///
/// **L'animation ne se joue que sur un vrai changement**, jamais à la première
/// arrivée ni sur une réponse identique. C'est toute la règle : un écran qui
/// clignote à chaque ouverture apprend à ne plus être regardé, alors qu'un
/// écran qui s'anime *seulement* quand une valeur a bougé apprend à l'être.
public enum ContentFreshness: Equatable, Sendable {
    /// Rien n'est encore arrivé.
    case unknown
    /// Ce qui est à l'écran vient du disque : on attend le serveur.
    case restored
    /// Le serveur a répondu, et disait la même chose. Rien à signaler.
    case unchanged
    /// Le serveur a répondu, et **ce n'est plus la même chose**. C'est le seul
    /// cas qui s'anime.
    case updated

    /// Faut-il jouer l'animation de mise à jour ?
    public var isUpdated: Bool { self == .updated }
}

/// Décide de la fraîcheur d'une valeur qui arrive.
///
/// Une fonction libre plutôt qu'une méthode : les cinq modèles font exactement
/// le même raisonnement, et le seul moyen de garantir qu'ils le font pareil est
/// qu'il n'existe qu'une fois.
///
/// **L'origine de ce qui était affiché ne compte pas.** Que la valeur d'avant
/// vienne du disque ou d'un chargement précédent, la question est la même : le
/// serveur dit-il autre chose ? Un « tirer pour rafraîchir » qui rapporte une
/// étape de plus mérite la même animation qu'une réouverture d'app.
///
/// - Parameters:
///   - incoming: ce que le serveur vient de rendre.
///   - shown: ce qui est à l'écran, s'il y a quelque chose.
public func contentFreshness<Value: Equatable>(
    of incoming: Value,
    replacing shown: Value?
) -> ContentFreshness {
    // Rien n'était affiché : c'est une première arrivée, pas une mise à jour.
    // L'écran qui se dessine est déjà l'animation.
    guard let shown else { return .unchanged }
    // Le serveur confirme ce qu'on montrait. On anime ce qui change, pas ce qui
    // se confirme — sans quoi l'animation ne voudrait plus rien dire.
    return shown == incoming ? .unchanged : .updated
}
