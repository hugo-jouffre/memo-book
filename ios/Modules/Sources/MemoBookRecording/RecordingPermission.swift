import AVFoundation

/// Accès au micro.
///
/// iOS ne présente la demande qu'une fois : une fois refusée, le seul recours
/// est l'app Réglages, ce que l'interface doit dire explicitement plutôt que de
/// redemander en boucle.
public enum RecordingPermission {
    public enum State: Sendable {
        case granted
        case denied
        case undetermined
    }

    public static var current: State {
        switch AVAudioApplication.shared.recordPermission {
        case .granted: .granted
        case .denied: .denied
        case .undetermined: .undetermined
        @unknown default: .undetermined
        }
    }

    /// Demande l'accès si nécessaire. Retourne `true` si l'app peut enregistrer.
    public static func request() async -> Bool {
        switch current {
        case .granted: return true
        case .denied: return false
        case .undetermined:
            return await AVAudioApplication.requestRecordPermission()
        }
    }
}
