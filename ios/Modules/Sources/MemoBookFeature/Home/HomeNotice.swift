import Foundation

/// Ce que l'accueil a à dire sur la connexion et sur les vocaux en route.
///
/// **Une seule boîte, quatre états.** Elle est toujours au même endroit — sous
/// la salutation, avant les voyages — et ne dit jamais qu'une chose à la fois :
/// une bande d'état qui s'empile finit par ne plus être lue. L'ordre de
/// priorité est celui de ``HomeModel/notice``, et il suit ce qui est le plus
/// utile à savoir : ce qui part maintenant, puis ce qui attend, puis ce qui
/// vient d'arriver, puis l'absence de réseau.
///
/// Les messages sont ici et non dans la vue, pour la même raison que les
/// libellés du palier freemium sont dans ``FreemiumStatus`` : ils dépendent
/// d'un état, et un état se teste.
public enum HomeNotice: Equatable, Sendable {
    /// Pas de réseau, et rien en attente : on prévient que l'app continue de
    /// marcher, ce qui est l'information utile.
    case offline

    /// Des vocaux dorment sur le téléphone en attendant le réseau.
    case waitingForConnection(count: Int)

    /// Des vocaux sont en train de partir.
    case sending(count: Int)

    /// Des vocaux viennent d'arriver. Transitoire — voir
    /// ``RecordingOutbox/justDelivered``.
    case delivered(count: Int)

    /// Le message, avec la partie qui compte entre `**` — voir ``BrandNotice``.
    ///
    /// Le singulier n'est pas une coquetterie : « Tes 1 vocaux » est le genre
    /// de phrase qui fait douter de tout le reste de l'app.
    public var message: String {
        switch self {
        case .offline:
            "Tu sembles hors ligne. **Tu peux consulter tes récits et enregistrer des étapes**, qui seront retranscrites plus tard."

        case .waitingForConnection(let count) where count <= 1:
            "**Ton vocal enregistré hors ligne est bien conservé.** Il sera envoyé dès ta reconnexion."
        case .waitingForConnection:
            "**Tes vocaux enregistrés hors ligne sont bien conservés.** Ils seront envoyés dès ta reconnexion."

        case .sending(let count) where count <= 1:
            "**Ton vocal est en cours d’envoi.** Encore un instant."
        case .sending(let count):
            "**Tes \(count) vocaux sont en cours d’envoi.** Encore un instant."

        case .delivered(let count) where count <= 1:
            "**Ton vocal est bien arrivé.** Il sera retranscrit dans quelques instants."
        case .delivered(let count):
            "**Tes \(count) vocaux sont bien arrivés.** Ils seront retranscrits dans quelques instants."
        }
    }

    /// Le même message, débarrassé de son balisage : c'est ce que VoiceOver
    /// annonce quand la boîte change, et une annonce ne se lit pas deux fois.
    public var spokenMessage: String {
        message.replacingOccurrences(of: "**", with: "")
    }
}
