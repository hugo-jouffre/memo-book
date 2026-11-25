import MemoBookCore
import MemoBookDesign
import SwiftUI

/**
 **Où et quand, pour une photo qui ne le sait plus** (T315, Hugo, 08/11/2026).

 Une photo passée par une messagerie arrive sans date de prise de vue ni
 position — voir ``MemoBookCore/PhotoFilename``. La photothèque en garde une
 date, mais c'est celle de son **arrivée** sur le téléphone : le carnet range
 alors la photo d'il y a dix jours au jour où on l'a reçue.

 La feuille demande les deux champs, et **aucun n'est obligatoire** : ce qu'on
 laisse vide reste comme avant. Les photos partent dans les deux cas — elles
 sont déjà choisies, et une sélection qui disparaît parce qu'on n'a pas
 répondu à une question serait exactement ce que T295 reproche à la file.

 Elle ne concerne que les photos sans mémoire : celles du même envoi qui ont
 gardé la leur ne sont pas retouchées.
 */
struct PhotoOriginSheet: View {
    /// Combien de photos de cet envoi ont perdu leur mémoire.
    let count: Int

    /// Le lieu de l'étape en cours, proposé en exemple dans le champ — pas
    /// posé dedans : ce serait répondre à la place du voyageur, et la photo
    /// vient peut-être d'ailleurs.
    let suggestedPlace: String?

    let onConfirm: (Date?, String) -> Void
    let onSkip: () -> Void

    @State private var day: Date?
    @State private var place = ""
    @FocusState private var focus: Field?

    private enum Field: Hashable { case place }

    var body: some View {
        BrandSheet(
            ChatCopy.Photos.Origin.title,
            paragraphs: [ChatCopy.Photos.Origin.lead(count)]
        ) {
            VStack(spacing: MemoBookSpacing.s) {
                // Une photo ne se prend pas demain : la borne évite la faute
                // de frappe d'un doigt sur le calendrier.
                BrandDateField(ChatCopy.Photos.Origin.day, date: $day, in: ...Date.now)

                BrandTextField(
                    ChatCopy.Photos.Origin.place,
                    text: $place,
                    field: Field.place,
                    focus: $focus,
                    labelPlacement: .above,
                    placeholder: suggestedPlace ?? ChatCopy.Photos.Origin.placePlaceholder
                )

                BrandButton(
                    ChatCopy.Photos.Origin.confirm,
                    style: .primary,
                    fillsWidth: true
                ) {
                    onConfirm(day, place)
                }

                // Pas de bouton fermé tant qu'on n'a rien saisi : « Ranger et
                // envoyer » sans rien dedans fait ce que fait cette sortie, et
                // un bouton qui se refuse n'expliquerait rien de plus.
                BrandButton(ChatCopy.Photos.Origin.skip, style: .link, fillsWidth: true, action: onSkip)
            }
        }
    }
}

#Preview("Où et quand ?") {
    Color.clear.brandSheet(isPresented: .constant(true)) {
        PhotoOriginSheet(count: 3, suggestedPlace: "Trastevere", onConfirm: { _, _ in }, onSkip: {})
    }
}
