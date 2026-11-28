import Foundation

/// **La manière d'être rédigé** du carnet — T292.
///
/// Elle règle la façon d'**écrire** le récit, et non le dessin du livre : le
/// style visuel, lui, est dans ``BookCustomisation``. Les fiches de chaque
/// manière vivent dans `agents/redaction-manieres/`, et c'est le serveur qui
/// les charge — l'app n'en connaît que la clé et le libellé.
public enum RedactionManner: String, Codable, Sendable, CaseIterable, Hashable {
    /// Le défaut : le carnet garde sa façon de raconter. **N'ajoute rien au
    /// prompt**, côté serveur — un carnet qui n'a jamais touché au réglage est
    /// rédigé exactement comme avant T292.
    case spoken
    /// Des phrases plus amples, l'oral qui s'efface davantage.
    case literary
    /// Court, chronologique, sans effets.
    case factual
}

/// Pourquoi le réglage est ouvert, ou ne l'est pas — `mannerAccess` côté
/// serveur (`backend/src/services/redactionMannerAccess.ts`).
///
/// L'app ne refait pas le calcul : elle lit ce que le serveur a tranché. C'est
/// ce qui évite deux règles à tenir d'accord, et un réglage ouvert dans l'app
/// que le serveur refuserait.
public enum RedactionMannerReason: String, Codable, Sendable, Hashable {
    /// Abonné illimité : ouvert, et la reprise peut être longue.
    case unlimited
    /// Carnet d'une seule étape : ouvert, la reprise ne coûte qu'un appel.
    case singleStep = "single_step"
    /// Ni l'un ni l'autre : le réglage se montre **pâli** et mène au paywall.
    case needsUnlimited = "needs_unlimited"
}

/// Le bloc `redaction` de `GET /v1/trips/:id/settings`.
public struct RedactionSettings: Codable, Sendable, Hashable {
    /// La manière **choisie**, ou `nil` si personne n'a choisi.
    ///
    /// ⚠️ La distinction ne vit que dans l'app, pour la pastille « par
    /// défaut » : le serveur traite `nil` et ``RedactionManner/spoken`` de la
    /// même façon (`mannerOf`).
    public var chosenManner: RedactionManner?

    /// Ce que l'écran coche : la manière choisie, ou celle par défaut.
    public var manner: RedactionManner { chosenManner ?? .spoken }

    /// Les indications libres du voyageur. `nil` quand il n'en a donné aucune.
    public var notes: String?

    /// Le réglage est ouvert. Faux, il se montre pâli et mène au paywall —
    /// **jamais désactivé** (voir `ios/CLAUDE.md`, « Ce qu'on ne peut pas faire
    /// pâlit »).
    public var isAvailable: Bool

    /// Pourquoi, pour que l'écran dise la cause et la sortie.
    public var reason: RedactionMannerReason

    public init(
        chosenManner: RedactionManner? = nil,
        notes: String? = nil,
        isAvailable: Bool = false,
        reason: RedactionMannerReason = .needsUnlimited
    ) {
        self.chosenManner = chosenManner
        self.notes = notes
        self.isAvailable = isAvailable
        self.reason = reason
    }

    private enum CodingKeys: String, CodingKey {
        case manner
        case notes
        case isAvailable
        case reason
    }

    /// ⚠️ **Décodage indulgent, et c'est la règle de l'app** : une manière ou
    /// une raison ajoutées par une version plus récente du serveur ne doivent
    /// pas faire échouer **tout l'écran** des réglages — seulement cette ligne.
    /// Une clé inconnue retombe donc sur le défaut, comme `mannerOf` le fait
    /// côté serveur.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let rawManner = try container.decodeIfPresent(String.self, forKey: .manner)
        chosenManner = rawManner.flatMap(RedactionManner.init(rawValue:))
        notes = try container.decodeIfPresent(String.self, forKey: .notes)
        isAvailable = try container.decodeIfPresent(Bool.self, forKey: .isAvailable) ?? false
        let rawReason = try container.decodeIfPresent(String.self, forKey: .reason)
        reason = rawReason.flatMap(RedactionMannerReason.init(rawValue:)) ?? .needsUnlimited
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(chosenManner?.rawValue, forKey: .manner)
        try container.encodeIfPresent(notes, forKey: .notes)
        try container.encode(isAvailable, forKey: .isAvailable)
        try container.encode(reason.rawValue, forKey: .reason)
    }

    /// La longueur maximale des indications — `REDACTION_NOTES_MAX` côté
    /// serveur, qui coupe silencieusement au-delà. L'app compte avant d'envoyer
    /// plutôt que de laisser le serveur trancher dans le texte de quelqu'un.
    public static let notesLimit = 600
}
