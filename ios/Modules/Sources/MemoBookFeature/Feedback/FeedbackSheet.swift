import MemoBookCore
import MemoBookDesign
import SwiftUI

/// **La modale d'avis** (T273) — dessinée ici, écrite en base.
///
/// Son titre, son sous-titre, ses questions et le libellé de son bouton
/// viennent du serveur : l'app ne connaît que les **formes** de question. Une
/// campagne de plus est une insertion, pas une livraison — c'est la réponse à
/// « peut-on envoyer des popups sans faire retélécharger l'app ».
///
/// Deux formes sont dessinées : la **liste d'options** et le **champ libre**.
/// Le curseur et les étoiles attendent leur dessin (la marque n'a pas de
/// curseur, et `BrandGauge` se lit sans se régler) ; une campagne qui les
/// emploie n'est pas montrée du tout plutôt qu'à trous
/// (``FeedbackCampaign/isDrawable``).
///
/// ⚠️ **Aucune note sur l'App Store ici.** Hugo l'a écarté pour le moment :
/// on demande un avis, pas une étoile.
struct FeedbackSheet: View {
    let campaign: FeedbackCampaign
    let model: FeedbackModel

    var body: some View {
        BrandSheet(campaign.title, subtitle: campaign.subtitle) {
            VStack(alignment: .leading, spacing: MemoBookSpacing.m) {
                ForEach(campaign.questions) { question in
                    field(for: question)
                }

                BrandButton(campaign.submitLabel, fillsWidth: true) {
                    model.send()
                }
                .disabled(!model.canSubmit)
                // Pâlir plutôt que désactiver : la règle de la marque veut
                // qu'on puisse toucher et comprendre. Ici, ce qui manque se
                // voit au-dessus — une question obligatoire sans réponse —,
                // et le bouton n'a rien à expliquer de plus.
                .opacity(model.canSubmit ? 1 : 0.45)
            }
        }
    }

    @ViewBuilder
    private func field(for question: FeedbackQuestion) -> some View {
        VStack(alignment: .leading, spacing: MemoBookSpacing.xs) {
            if let prompt = question.prompt, !prompt.isEmpty {
                Text(prompt)
                    .font(MemoBookFont.bodySemibold)
                    .foregroundStyle(MemoBookColor.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }

            switch question.kind {
            case .choice:
                BrandOptionGroup {
                    ForEach(question.options) { option in
                        BrandOptionRow(
                            option.label,
                            subtitle: option.hint,
                            isSelected: model.chosenKey(for: question) == option.key
                        ) {
                            model.answer(question, choice: option.key)
                        }
                    }
                }

            case .text:
                FeedbackTextQuestion(question: question, model: model)

            // Une forme que cette version ne dessine pas n'arrive jamais ici :
            // la campagne entière est écartée avant d'être montrée. Le cas
            // reste écrit pour que le compilateur le rappelle le jour où une
            // forme s'ajoute.
            case .slider, .rating, .unknown:
                EmptyView()
            }
        }
    }
}

/// Un champ libre d'une campagne.
///
/// **Une vue à part, et c'est le `@FocusState` qui l'impose** : il ne se met
/// pas dans un dictionnaire, et une campagne peut poser deux champs. Chaque
/// champ porte donc le sien, comme chaque champ porte sa frappe — le modèle,
/// lui, ne reçoit que la réponse.
private struct FeedbackTextQuestion: View {
    let question: FeedbackQuestion
    let model: FeedbackModel

    @State private var draft = ""
    @FocusState private var isWriting: Bool

    var body: some View {
        BrandTextBox(
            question.placeholder ?? "",
            text: Binding(
                get: { draft },
                set: { value in
                    draft = value
                    model.answer(question, text: value)
                }
            ),
            focus: $isWriting,
            accessibilityLabel: question.prompt
        )
    }
}
