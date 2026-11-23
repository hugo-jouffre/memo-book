import Foundation

extension Array {
    /// Découpe en lots de `taille` au plus, dans l'ordre.
    ///
    /// Écrit ici, et pas dans l'écran qui s'en sert : c'est une règle, elle se
    /// teste sans simulateur. Son premier usage est l'envoi des photos, que la
    /// conversation ne coupe plus mais **découpe** — soixante photos partent
    /// en trois messages de vingt, chacun avec sa bulle et son sort (T265,
    /// `ChatModel.sendPhotos`).
    ///
    /// Une taille nulle ou négative rend un seul lot : mieux vaut tout envoyer
    /// d'un coup qu'une boucle infinie.
    public func chunked(into taille: Int) -> [[Element]] {
        guard taille > 0 else { return isEmpty ? [] : [self] }
        return stride(from: 0, to: count, by: taille).map { debut in
            Array(self[debut..<Swift.min(debut + taille, count)])
        }
    }
}
