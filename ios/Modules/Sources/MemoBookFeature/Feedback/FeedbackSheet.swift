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
/// Les quatre formes sont dessinées : la **liste d'options**, le **champ
/// libre**, le **curseur** (``BrandSlider``, celui du ratio photo/texte) et
/// la **note en étoiles**. Une campagne mal posée — une liste sans option,
/// une échelle dont les bornes sont à l'envers — n'est pas montrée du tout
/// plutôt qu'à trous (``FeedbackQuestion/isDrawable``).
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

            case .slider:
                if let scale = question.scale {
                    FeedbackSliderQuestion(question: question, scale: scale, model: model)
                }

            case .rating:
                if let scale = question.scale {
                    FeedbackRatingQuestion(question: question, scale: scale, model: model)
                }

            // Une forme que cette version ne dessine pas n'arrive jamais ici :
            // la campagne entière est écartée avant d'être montrée. Le cas
            // reste écrit pour que le compilateur le rappelle le jour où une
            // forme s'ajoute.
            case .unknown:
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

/// **Le curseur d'une campagne**, qui est celui du ratio photo/texte
/// (``BrandSlider``) : même rail, même poignée, mêmes crans écrits dessous, et
/// le même geste d'assistance — VoiceOver le règle au balayage vertical.
///
/// ⚠️ **Il part sans réponse.** La poignée se pose au milieu de l'échelle pour
/// qu'on voie ce qu'on règle, mais le modèle ne retient rien tant que le doigt
/// n'a pas bougé : une note que personne n'a touchée serait un avis inventé.
/// C'est aussi ce qui tient le bouton d'envoi fermé sur une question
/// obligatoire.
private struct FeedbackSliderQuestion: View {
    let question: FeedbackQuestion
    let scale: FeedbackQuestion.Scale
    let model: FeedbackModel

    /// La position montrée, qui n'est pas la réponse : celle-ci vit dans le
    /// modèle, et reste nulle jusqu'au premier geste.
    @State private var position: Int

    init(question: FeedbackQuestion, scale: FeedbackQuestion.Scale, model: FeedbackModel) {
        self.question = question
        self.scale = scale
        self.model = model
        let crans = scale.steps
        _position = State(initialValue: crans[crans.count / 2])
    }

    var body: some View {
        BrandSlider(
            value: Binding(
                get: { model.number(for: question) ?? position },
                set: { value in
                    position = value
                    model.answer(question, number: value)
                }
            ),
            in: scale.min...scale.max,
            step: scale.step,
            ticks: scale.ticks.isEmpty ? scale.steps.map(String.init) : scale.ticks,
            leadingLabel: scale.minLabel,
            trailingLabel: scale.maxLabel,
            voiceLabel: question.prompt ?? "",
            voiceValue: { value in
                let crans = scale.steps
                guard !scale.ticks.isEmpty, let rang = crans.firstIndex(of: value), rang < scale.ticks.count else {
                    return "\(value)"
                }
                return scale.ticks[rang]
            }
        )
        // **Pâle tant qu'on n'y a pas touché** — la règle de la marque, et
        // ici elle dit quelque chose de précis : la poignée est posée au
        // milieu pour qu'on voie l'échelle, mais rien n'est encore répondu.
        // Sans ça, « Bien » en gras se lirait comme un choix déjà fait.
        .opacity(model.number(for: question) == nil ? 0.5 : 1)
    }
}

/// **La note en étoiles.**
///
/// Une note part de 1 : zéro étoile serait une absence de réponse, pas un
/// avis, et c'est le modèle qui porte l'absence. Les étoiles non choisies sont
/// **pâlies, pas vides** — la règle de la marque, et un contour creux se
/// lirait comme un bouton désactivé.
///
/// VoiceOver y trouve **un seul élément réglable**, comme sur le curseur :
/// cinq boutons à la file feraient cinq arrêts pour une seule réponse.
private struct FeedbackRatingQuestion: View {
    let question: FeedbackQuestion
    let scale: FeedbackQuestion.Scale
    let model: FeedbackModel

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var chosen: Int? { model.number(for: question) }

    var body: some View {
        HStack(spacing: MemoBookSpacing.xs) {
            ForEach(scale.steps, id: \.self) { rang in
                Button {
                    model.answer(question, number: rang)
                } label: {
                    // **Pleine ou au trait**, et pas seulement vert ou pâle :
                    // une note se lit d'un coup d'œil, et cinq contours de la
                    // même forme ne disent pas où elle s'arrête. Les deux
                    // étoiles sont celles de la marque — rien de dessiné ici.
                    Image(brand: rang <= (chosen ?? 0) ? "IconStarDuo" : "IconStar")
                        .resizable()
                        .renderingMode(.template)
                        .scaledToFit()
                        .frame(width: 32, height: 32)
                        .foregroundStyle(rang <= (chosen ?? 0) ? MemoBookColor.action : MemoBookColor.inkFaint)
                        .scaleEffect(rang == chosen ? 1.08 : 1)
                }
                .buttonStyle(.plain)
                .frame(minWidth: MemoBookSpacing.minimumTapTarget, minHeight: MemoBookSpacing.minimumTapTarget)
            }
            Spacer(minLength: 0)
        }
        .animation(reduceMotion ? nil : .snappy(duration: 0.18), value: chosen)
        // Un seul élément pour l'assistance, réglable au balayage : la note
        // est une valeur, pas cinq boutons.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(question.prompt ?? FeedbackCopy.ratingLabel)
        .accessibilityValue(FeedbackCopy.ratingValue(chosen, max: scale.max))
        .accessibilityAdjustableAction { direction in
            let courant = chosen ?? 0
            switch direction {
            case .increment: model.answer(question, number: min(courant + 1, scale.max))
            case .decrement: model.answer(question, number: max(courant - 1, scale.min))
            @unknown default: break
            }
        }
    }
}

/// Ce que l'assistance dit d'une note.
enum FeedbackCopy {
    static let ratingLabel = "Note"

    static func ratingValue(_ chosen: Int?, max: Int) -> String {
        guard let chosen else { return "Pas encore noté" }
        return chosen == 1 ? "1 étoile sur \(max)" : "\(chosen) étoiles sur \(max)"
    }
}
