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
    public let audio: RecordedAudio

    /// Les niveaux relevés pendant l'enregistrement, de 0 à 1 : c'est la
    /// forme d'onde de la bulle. Sans eux, elle serait une ligne plate.
    public let levels: [Double]

    public init(audio: RecordedAudio, levels: [Double]) {
        self.audio = audio
        self.levels = levels
    }
}
