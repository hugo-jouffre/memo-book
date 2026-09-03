import Foundation

/// Les deux faces de l'écran d'entrée.
public enum AuthMode: String, CaseIterable, Identifiable, Sendable {
    case signUp
    case signIn

    public var id: Self { self }

    var segmentTitle: String {
        switch self {
        case .signUp: "Inscription"
        case .signIn: "Connexion"
        }
    }

    var title: String {
        switch self {
        case .signUp: "Crée ton compte"
        case .signIn: "Ravi de te revoir !"
        }
    }

    var subtitle: String {
        switch self {
        case .signUp: "pour commencer à raconter ton histoire"
        case .signIn: "connecte-toi"
        }
    }
}
