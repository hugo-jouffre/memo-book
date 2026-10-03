import MemoBookDesign
import SwiftUI

/// La confirmation avant de supprimer son compte — **une feuille de l'app**, pas
/// une alerte du système.
///
/// Deux modales dans Figma, une seule vue ici : `Modale – Supression de compte
/// (sans voyage)` (`3203:21809`) et `(avec voyage)` (`3206:21854`) ne diffèrent
/// que d'un paragraphe, celui qui propose de **clore le voyage en cours** plutôt
/// que de tout effacer. Hugo, 14/09/2026 (T23).
///
/// Le texte est celui de la maquette, à deux corrections près, signalées dans
/// la fiche écran : « sont supprimé » s'accorde, et « Co-voyageurs » prend la
/// minuscule que le mot a partout ailleurs dans l'app.
///
/// ⚠️ Le titre et les libellés des deux boutons n'ont pas pu être lus sur les
/// nœuds (quota MCP) : ce sont ceux qui suivent la logique de la feuille — le
/// bouton plein **garde** le compte, le rouge le supprime. À relire sur la
/// maquette.
struct DeleteAccountSheet: View {
    /// Un voyage est en cours : la feuille propose alors de le clore plutôt que
    /// de tout effacer.
    let hasOngoingTrip: Bool

    /// Un abonnement App Store va se renouveler : la feuille rappelle que
    /// supprimer le compte ne l'arrête pas. **À lui seul** (03/10/2026) — le
    /// dire à tout le monde demandait à un compte gratuit de couper un
    /// abonnement qu'il n'a pas.
    var mentionsSubscription = true

    /// La suppression est partie. Le bouton rouge tourne et plus rien ne se
    /// touche : la demande est définitive, elle ne part pas deux fois.
    let isDeleting: Bool

    let onKeep: () -> Void
    let onDelete: () -> Void

    var body: some View {
        BrandSheet(DeleteAccountCopy.title) {
            VStack(alignment: .leading, spacing: MemoBookSpacing.m) {
                Text(DeleteAccountCopy.body(hasOngoingTrip: hasOngoingTrip, mentionsSubscription: mentionsSubscription))
                    .font(MemoBookFont.body)
                    .foregroundStyle(MemoBookColor.ink)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)

                VStack(spacing: MemoBookSpacing.s) {
                    // Le bouton plein est celui qui **ne détruit rien** : sur
                    // une feuille dont l'autre issue est sans retour, l'action
                    // la plus visible doit être la plus sûre.
                    BrandButton(DeleteAccountCopy.keep, fillsWidth: true, action: onKeep)
                        .disabled(isDeleting)

                    BrandButton(
                        DeleteAccountCopy.delete,
                        style: .destructive,
                        isLoading: isDeleting,
                        fillsWidth: true,
                        action: onDelete
                    )
                }
            }
        }
        .interactiveDismissDisabled(isDeleting)
    }
}

/// Les mots de la feuille, tels que Figma les écrit — voir ``DeleteAccountSheet``.
enum DeleteAccountCopy {
    static let title = "Tu es sûr de vouloir supprimer ton compte MemoBook ?"

    static let erasure =
        "Tes voyages, tes souvenirs et tes carnets seront effacés, ainsi que tes commandes. Les voyages que tu partages restent à tes co-voyageurs, avec les souvenirs que tu y as racontés. Ta cagnotte est supprimée. C’est immédiat et sans retour."

    /// Pour qui a un abonnement App Store qui va se renouveler — voir
    /// ``DeleteAccountSheet/mentionsSubscription``.
    static let subscriptionWarning =
        "Ton abonnement, lui, se résilie chez Apple : supprimer ton compte ne l’arrête pas, pense à le couper dans les réglages de ton iPhone."

    /// La porte de sortie qui n'existe que s'il y a un voyage en cours à clore.
    static let closeTripInstead =
        "Tu veux seulement clore ton voyage en cours ? Termine-le : ton compte et tes carnets restent."

    /// Le paragraphe de la feuille : ce qui s'efface, l'abonnement à couper
    /// chez Apple s'il y en a un, et la porte de sortie s'il y a un voyage.
    static func body(hasOngoingTrip: Bool, mentionsSubscription: Bool) -> String {
        var sentences = [erasure]
        if mentionsSubscription { sentences.append(subscriptionWarning) }
        if hasOngoingTrip { sentences.append(closeTripInstead) }
        return sentences.joined(separator: " ")
    }

    static let keep = "Garder mon compte"
    static let delete = "Supprimer définitivement mon compte"
}

#Preview("Suppression — sans voyage") {
    Color.clear
        .brandSheet(isPresented: .constant(true)) {
            DeleteAccountSheet(
                hasOngoingTrip: false,
                mentionsSubscription: false,
                isDeleting: false,
                onKeep: {},
                onDelete: {}
            )
        }
}

#Preview("Suppression — avec voyage") {
    Color.clear
        .brandSheet(isPresented: .constant(true)) {
            DeleteAccountSheet(hasOngoingTrip: true, isDeleting: false, onKeep: {}, onDelete: {})
        }
}
