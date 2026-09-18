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
/// ⚠️ **Aucune maquette** : écrite sur le motif des feuilles de choix du
/// profil (`PaymentMethodSheet`), et à dessiner dans Figma.
struct GenderSheet: View {
    let current: Gender
    let onSelect: (Gender) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        BrandSheet(
            "Genre",
            subtitle: "Pour que MemoBook s’adresse à toi comme il faut."
        ) {
            BrandOptionGroup {
                ForEach(Gender.allCases, id: \.self) { gender in
                    BrandOptionRow(gender.label, isSelected: gender == current) {
                        onSelect(gender)
                        dismiss()
                    }
                }
            }
        }
    }
}

#Preview("Genre") {
    Color.clear
        .brandSheet(isPresented: .constant(true)) {
            GenderSheet(current: .female) { _ in }
        }
}
