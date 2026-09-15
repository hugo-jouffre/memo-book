import Foundation

/// Ce que les six étapes de « Créer un voyage » remplissent.
///
/// Un seul objet, et non six appels : les étapes se remplissent hors ligne, se
/// sautent, se reprennent en arrière, et rien n'a de sens tant que le titre
/// n'est pas là. Le voyage part donc **d'un coup**, à la fin.
///
/// C'est le contrat exact de `POST /v1/trips` — au nom près, comme le veut
/// `backend/src/routes/appSerializers.ts`.
public struct TripDraft: Codable, Sendable, Hashable {
    /// Le thème narratif : « Gastronomie », « Tour du monde », ou la phrase
    /// libre saisie derrière « Autre ». Du texte et non une clé — il part tel
    /// quel dans le contexte de l'agent de rédaction.
    public var theme: String?

    /// Le seul champ obligatoire : un carnet sans titre n'existe pas. Passer
    /// l'étape du nom ne laisse donc pas ce champ vide, elle y pose le titre de
    /// repli — voir ``TripDraft/untitled``.
    public var title: String

    public var startDate: Date?
    public var endDate: Date?

    /// Le rythme des relances, dans les mots de l'écran : « Tous les jours ».
    /// Même raison que ``theme`` — c'est une consigne lue par un agent.
    public var narrationPace: String?

    /// La part de photo dans la page, de 0 à 100. 50 est l'équilibre de la
    /// maquette, et la valeur par défaut de la base.
    public var photoTextRatio: Int

    /// Le titre de quelqu'un qui a sauté l'étape du nom. Il se corrige ensuite
    /// dans les réglages du voyage : mieux vaut un nom provisoire qu'une étape
    /// qu'on ne peut pas passer alors que la maquette le propose.
    public static let untitled = "Mon voyage"

    public init(
        theme: String? = nil,
        title: String = "",
        startDate: Date? = nil,
        endDate: Date? = nil,
        narrationPace: String? = nil,
        photoTextRatio: Int = 50
    ) {
        self.theme = theme
        self.title = title
        self.startDate = startDate
        self.endDate = endDate
        self.narrationPace = narrationPace
        self.photoTextRatio = photoTextRatio
    }
}

/// Ce que le serveur rend d'un voyage qu'on vient de créer.
///
/// Le **code d'accès** vient avec, et il ne vient qu'avec : c'est la seule
/// réponse de l'app qui l'expose, et elle l'expose à celui qui vient de créer
/// le carnet. La dernière étape de la création ne montre que lui.
public struct CreatedTrip: Codable, Sendable, Hashable {
    public let trip: Trip
    public let accessCode: String

    public init(trip: Trip, accessCode: String) {
        self.trip = trip
        self.accessCode = accessCode
    }
}

/// Un thème de « Contexte de ton voyage », la première étape de la création.
///
/// **Il vient de la base** (`GET /v1/trip-themes`, table `trip_themes`) et non
/// d'une liste dans l'app : en ajouter, en renommer ou en éteindre un ne
/// demande pas de livrer une version — Hugo, 14/09/2026. Au nom près de
/// `serializeTripTheme` côté serveur.
public struct TripTheme: Codable, Sendable, Hashable, Identifiable {
    public let id: String

    /// L'identifiant stable, celui qu'on écrit dans un script. `name` peut
    /// changer, `slug` non.
    public let slug: String

    /// L'émoji de la rangée, et le nom écrit dessous.
    public let emoji: String
    public let name: String

    /// « Autre » : le thème qui n'en est pas un et ouvre un champ libre. Le
    /// serveur le sert toujours en dernier — on préfère un thème précis.
    public let isOther: Bool

    public init(id: String, slug: String, emoji: String, name: String, isOther: Bool = false) {
        self.id = id
        self.slug = slug
        self.emoji = emoji
        self.name = name
        self.isOther = isOther
    }

    /// Le libellé, tel qu'il part dans ``TripDraft/theme`` et tel qu'il s'écrit
    /// sous la rangée.
    public var label: String { name }
}

extension TripTheme {
    /// La liste arrêtée par Hugo le 14/09/2026, telle que `prisma/tripThemes.ts`
    /// la pose. Pour les aperçus et les tests — l'app, elle, la demande au
    /// serveur.
    public static let fixtures: [TripTheme] = [
        TripTheme(id: "nature-aventure", slug: "nature-aventure", emoji: "🏔️", name: "Nature & aventure"),
        TripTheme(id: "grands-voyages", slug: "grands-voyages", emoji: "🌍", name: "Grands voyages / exploration"),
        TripTheme(id: "a-deux", slug: "a-deux", emoji: "❤️", name: "Voyages à deux"),
        TripTheme(id: "en-famille", slug: "en-famille", emoji: "👨‍👩‍👧‍👦", name: "Voyages en famille"),
        TripTheme(id: "entre-amis", slug: "entre-amis", emoji: "👯", name: "Voyages entre amis"),
        TripTheme(id: "city-trips", slug: "city-trips", emoji: "🏙️", name: "City trips & découverte"),
        TripTheme(id: "gastronomie", slug: "gastronomie", emoji: "🍷", name: "Gastronomie & art de vivre"),
        TripTheme(id: "vacances-detente", slug: "vacances-detente", emoji: "☀️", name: "Vacances & détente"),
        TripTheme(id: "evenementiels", slug: "evenementiels", emoji: "🎉", name: "Voyages événementiels"),
        TripTheme(id: "etudes-travail", slug: "etudes-travail", emoji: "💼", name: "Études / Travail"),
        TripTheme(id: "autre", slug: "autre", emoji: "💬", name: "Autre", isOther: true),
    ]
}

/// Ce que `GET /v1/trip-themes` rend : la liste, dans une enveloppe, comme la
/// galerie.
public struct TripThemes: Codable, Sendable, Hashable {
    public let themes: [TripTheme]

    public init(themes: [TripTheme]) {
        self.themes = themes
    }
}
