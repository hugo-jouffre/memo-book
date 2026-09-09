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
