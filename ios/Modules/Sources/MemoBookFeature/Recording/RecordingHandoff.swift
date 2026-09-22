import Foundation
import MemoBookRecording

/// Un vocal enregistré depuis l'accueil, **en route vers la conversation**.
///
/// « Commencer à enregistrer » ouvre la feuille bleue ; quand on s'arrête, on
/// doit **arriver dans la conversation du voyage, le message déjà posé** —
/// Hugo, 14/09/2026. Le vocal part au serveur par la file de l'accueil
/// (``RecordingOutbox``), comme avant ; ce paquet-ci ne fait que le porter
/// jusqu'au fil pour qu'il s'y affiche, avec la forme d'onde relevée pendant
/// qu'on parlait.
public struct RecordingHandoff: Sendable, Hashable {
    /// L'identifiant de la bulle, et **le même des deux côtés** : la
    /// conversation l'écrit sur son message, la file s'en sert pour dire où en
    /// est cet envoi-là. C'est ce qui permet à la bulle de ne pas se déclarer
    /// arrivée pendant que le vocal attend le réseau sur le disque. Voir
    /// ``RecordingOutbox/lastDelivery``.
    ///
    /// Un UUID, parce que c'est aussi l'identifiant du message côté serveur,
    /// qui n'en accepte pas d'autre forme.
    public let id: String

    public let audio: RecordedAudio

    /// Les niveaux relevés pendant l'enregistrement, de 0 à 1 : c'est la
    /// forme d'onde de la bulle. Sans eux, elle serait une ligne plate.
    public let levels: [Double]

    public init(id: String = UUID().uuidString.lowercased(), audio: RecordedAudio, levels: [Double]) {
        self.id = id
        self.audio = audio
        self.levels = levels
    }
}
