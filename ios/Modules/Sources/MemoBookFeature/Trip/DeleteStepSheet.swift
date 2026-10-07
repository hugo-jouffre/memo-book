import MemoBookCore
import MemoBookDesign
import SwiftUI

/// La confirmation avant d'effacer ce qu'on a raconté d'une étape — la croix
/// de son tiroir (T235, Hugo, 06/10/2026 : « même comportement que les cartes
/// de voyage dans l'accueil général »).
///
/// **Le dessin de « Supprimer ce voyage »** (``DeleteTripSheet``) : le bouton
/// plein garde, le rouge efface, et le paragraphe dit ce qui part avant qu'on
/// appuie. Une étape peut porter plusieurs souvenirs — un vocal, un texte,
/// des photos : la phrase le dit au pluriel quand c'est le cas, pour qu'on ne
/// croie pas n'effacer que la vignette.
struct DeleteStepSheet: View {
    let step: TripStep

    /// L'effacement est parti : le bouton rouge tourne et plus rien ne se
    /// touche — la demande est définitive, elle ne part pas deux fois.
    let isDeleting: Bool

    /// Ce que le serveur a répondu si l'effacement a échoué. Il se lit
    /// **dans** la feuille, comme pour un voyage.
    let errorMessage: String?

    let onKeep: () -> Void
    let onDelete: () -> Void

    private var count: Int { step.entryIds?.count ?? 0 }

    var body: some View {
        BrandSheet(DeleteStepCopy.title(count: count)) {
            VStack(alignment: .leading, spacing: MemoBookSpacing.m) {
                Text(DeleteStepCopy.body(step: step.title, count: count))
                    .font(MemoBookFont.body)
                    .foregroundStyle(MemoBookColor.ink)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if let errorMessage {
                    ErrorBanner(message: errorMessage)
                }

                VStack(spacing: MemoBookSpacing.s) {
                    BrandButton(DeleteStepCopy.keep(count: count), fillsWidth: true, action: onKeep)
                        .disabled(isDeleting)

                    BrandButton(
                        DeleteStepCopy.confirm,
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

/// Les mots de la feuille. Pas de maquette : ils suivent ceux de « Supprimer
/// ce voyage » (``BookCopy/Settings/Delete``), au tutoiement.
enum DeleteStepCopy {
    static func title(count: Int) -> String {
        count > 1
            ? "Tu es sûr de vouloir supprimer les souvenirs de cette étape ?"
            : "Tu es sûr de vouloir supprimer ce souvenir ?"
    }

    static func body(step: String, count: Int) -> String {
        let what = count > 1
            ? "Tout ce qui a été raconté pour « \(step) » — vocaux, textes et photos —"
            : "Le souvenir de « \(step) »"
        return "\(what) sera effacé du carnet, pour toi comme pour tes co-voyageurs. C’est immédiat et sans retour."
    }

    static func keep(count: Int) -> String {
        count > 1 ? "Garder ces souvenirs" : "Garder ce souvenir"
    }

    static let confirm = "Supprimer définitivement"

    /// Le libellé de la croix, pour VoiceOver et le menu de l'appui long.
    static func action(step: String) -> String { "Supprimer les souvenirs de « \(step) »" }

    /// Le mot qui s'efface tout seul, une fois fait.
    static func done(count: Int) -> String {
        count > 1 ? "Souvenirs supprimés." : "Souvenir supprimé."
    }
}
