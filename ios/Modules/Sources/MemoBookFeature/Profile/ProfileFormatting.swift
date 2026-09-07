import Foundation

// Mise en forme des valeurs du profil. Les règles vivent ici, pas dans les
// vues : un montant s'écrit pareil dans la ligne « Ma cagnotte » et dans le
// libellé du bouton d'abonnement.

extension Decimal {
    /// Un montant en euros, écrit selon la région de l'utilisateur.
    ///
    /// La maquette écrit « 67,88€ », collé. On passe quand même par le
    /// formateur du système : c'est lui qui sait qu'un français attend une
    /// espace insécable avant le symbole, et qu'un lecteur d'une autre région
    /// attend autre chose. L'écart est signalé dans la fiche écran.
    var euros: String {
        formatted(.currency(code: "EUR").precision(.fractionLength(2)))
    }
}
