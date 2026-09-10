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

extension Date {
    /// Le temps qui nous sépare de cette date, écrit comme on le dit :
    /// « dans 3 semaines ».
    ///
    /// **La préposition fait partie de la chaîne** — c'est le formateur du
    /// système qui la choisit, et elle change avec la langue de l'appareil. La
    /// phrase de la feuille se termine donc par le délai, elle ne l'encadre pas.
    ///
    /// Le formateur choisit aussi l'unité : trois semaines s'écrivent
    /// « dans 3 semaines », trois jours « dans 3 jours ». La maquette ne montre
    /// que le premier cas ; le second sort tout seul, sans rien à écrire ici.
    var relativeDelay: String {
        formatted(.relative(presentation: .numeric))
    }
}
