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

    /// La suppression est partie. Le bouton rouge tourne et plus rien ne se
    /// touche : la demande est définitive, elle ne part pas deux fois.
    let isDeleting: Bool

    let onKeep: () -> Void
    let onDelete: () -> Void

    var body: some View {
        BrandSheet(DeleteAccountCopy.title) {
            VStack(alignment: .leading, spacing: MemoBookSpacing.m) {
                Text(hasOngoingTrip ? DeleteAccountCopy.bodyWithTrip : DeleteAccountCopy.body)
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

    static let body =
        "Tes voyages, tes souvenirs et tes carnets seront effacés, ainsi que tes commandes. Les voyages que tu partages restent à tes co-voyageurs, avec les souvenirs que tu y as racontés. Ta cagnotte et tes abonnements sont supprimés. C’est immédiat et sans retour."

    /// La même phrase, et la porte de sortie qui n'existe que s'il y a un
    /// voyage en cours à clore.
    static let bodyWithTrip =
        body + " Tu veux seulement clore ton voyage en cours ? Termine-le : ton compte et tes carnets restent."

    static let keep = "Garder mon compte"
    static let delete = "Supprimer définitivement mon compte"
}

#Preview("Suppression — sans voyage") {
    Color.clear
        .brandSheet(isPresented: .constant(true)) {
            DeleteAccountSheet(hasOngoingTrip: false, isDeleting: false, onKeep: {}, onDelete: {})
        }
}

#Preview("Suppression — avec voyage") {
    Color.clear
        .brandSheet(isPresented: .constant(true)) {
            DeleteAccountSheet(hasOngoingTrip: true, isDeleting: false, onKeep: {}, onDelete: {})
        }
}
