import MemoBookCore
import MemoBookDesign
import SwiftUI

/// Dire à l'app à qui elle parle — femme, homme, ou qu'on ne préfère pas
/// répondre.
///
/// Elle sert à **un accord grammatical**, et rien d'autre : « Abonnée » ou
/// « Abonné » sur la feuille d'abonnement. Le serveur devine sur le prénom tant
/// qu'on n'a rien dit ; cette feuille est là pour le corriger (Hugo,
/// 17/09/2026, T76). Le choix s'enregistre au toucher et la feuille se
/// referme : trois options, aucune saisie, un « Valider » de plus n'aurait rien
/// à valider.
///
/// **Elle se referme après s'être montrée cochée**, pas avant (Hugo,
/// 18/09/2026) : une feuille qui part à l'instant du toucher ne dit pas ce
/// qu'elle a retenu, et on rouvre pour vérifier. La coche se pose, on la voit
/// un tiers de seconde, la feuille descend.
///
/// ⚠️ **Aucune maquette** : écrite sur le motif des feuilles de choix du
/// profil (`PaymentMethodSheet`), et à dessiner dans Figma.
struct GenderSheet: View {
    let current: Gender
    let onSelect: (Gender) -> Void

    /// Ce qu'on vient de toucher, le temps que la feuille parte. La feuille
    /// coche **sa** valeur et non celle du modèle : celui-ci enregistre en
    /// arrière-plan, et sa réponse ne doit pas faire clignoter la coche.
    @State private var chosen: Gender?

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        BrandSheet(
            "Genre",
            subtitle: "Pour que MemoBook s’adresse à toi comme il faut."
        ) {
            BrandOptionGroup {
                ForEach(Gender.allCases, id: \.self) { gender in
                    BrandOptionRow(gender.label, isSelected: gender == (chosen ?? current)) {
                        select(gender)
                    }
                }
            }
        }
    }
}

extension GenderSheet {
    /// Coche, enregistre, puis referme — dans cet ordre. Un second toucher
    /// pendant l'attente ne fait rien : le premier est déjà parti.
    private func select(_ gender: Gender) {
        guard chosen == nil else { return }
        withAnimation(.snappy(duration: 0.2)) { chosen = gender }
        onSelect(gender)
        Task {
            try? await Task.sleep(for: BrandOptionRow.lingerBeforeDismiss)
            dismiss()
        }
    }
}

#Preview("Genre") {
    Color.clear
        .brandSheet(isPresented: .constant(true)) {
            GenderSheet(current: .female) { _ in }
        }
}
