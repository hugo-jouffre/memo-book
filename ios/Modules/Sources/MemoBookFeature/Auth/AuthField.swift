import Foundation

/// Les champs de l'écran d'entrée, dans l'ordre où le clavier les enchaîne.
enum AuthField: Hashable {
    case firstName
    case lastName
    case email
    case password
    case passwordConfirmation
}
