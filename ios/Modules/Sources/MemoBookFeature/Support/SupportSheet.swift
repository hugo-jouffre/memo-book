import MemoBookCore
import MemoBookDesign
import SwiftUI

/// La feuille du support, en trois temps : une réponse, un formulaire, une
/// confirmation.
///
/// **Une seule feuille pour les trois**, et c'est une contrainte du design
/// system : on n'empile pas deux ``BrandSheet``. « J'ai encore une question »
/// devait pourtant mener au formulaire depuis une réponse — c'est donc une
/// **étape** de la même feuille, comme l'aperçu l'est de la feuille
/// d'abonnement (voir `BookPreviewSheet`).
///
/// L'avantage n'est pas que théorique : la feuille garde son identité d'un temps
/// à l'autre, donc sa hauteur s'anime au lieu de sauter, et le retour arrière de
/// VoiceOver reste celui d'une seule feuille.
struct SupportSheet: View {
    let model: SupportModel
    let route: SupportSheetRoute

    @State private var step: Step
    @State private var message = ""
    @FocusState private var isWriting: Bool

    init(model: SupportModel, route: SupportSheetRoute) {
        self.model = model
        self.route = route
        _step = State(initialValue: Step(route))
    }

    enum Step: Equatable {
        case answer(FaqEntry)
        case contact
        case sent
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        BrandSheet(title, paragraphs: paragraphs) {
            content
        }
        .animation(reduceMotion ? .none : .snappy(duration: 0.3), value: step)
        // Deux feuilles ouvertes l'une après l'autre ne partagent pas l'état
        // d'envoi de la première : sans ça, la seconde s'ouvrirait sur la
        // confirmation de la précédente.
        .onDisappear { model.resetSending() }
    }

    private var title: String {
        switch step {
        case .answer(let entry): entry.question
        case .contact: SupportCopy.Contact.title
        case .sent: SupportCopy.Contact.confirmation
        }
    }

    /// Le chapeau gris sous le titre. Seul le formulaire en a un : une réponse
    /// écrit son texte en pleine encre, plus bas.
    private var paragraphs: [String] {
        step == .contact ? [SupportCopy.Contact.message] : []
    }

    @ViewBuilder
    private var content: some View {
        switch step {
        case .answer(let entry): answer(entry)
        case .contact: form
        case .sent: confirmation
        }
    }

    // MARK: - Une réponse

    private func answer(_ entry: FaqEntry) -> some View {
        VStack(alignment: .leading, spacing: MemoBookSpacing.m) {
            VStack(alignment: .leading, spacing: MemoBookSpacing.xs) {
                ForEach(model.answer(for: entry), id: \.self) { paragraph in
                    Text(paragraph)
                        .font(MemoBookFont.body)
                        .foregroundStyle(MemoBookColor.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            HelpfulVote(entry: entry, model: model)

            VStack(spacing: MemoBookSpacing.s) {
                BrandButton(
                    SupportCopy.Answer.stillStuck,
                    style: .secondary,
                    fillsWidth: true
                ) {
                    step = .contact
                }

                BrandButton(SupportCopy.Answer.understood, fillsWidth: true) {
                    dismiss()
                }
            }
        }
    }

    // MARK: - Le formulaire

    private var form: some View {
        VStack(alignment: .leading, spacing: MemoBookSpacing.m) {
            BrandTextBox(SupportCopy.Contact.placeholder, text: $message, focus: $isWriting)

            if case .failed(let problem) = model.sendState {
                Text(problem)
                    .font(MemoBookFont.caption)
                    .foregroundStyle(MemoBookColor.error)
                    .fixedSize(horizontal: false, vertical: true)
            }

            BrandButton(
                SupportCopy.Contact.send,
                isLoading: model.sendState == .sending,
                fillsWidth: true
            ) {
                isWriting = false
                Task {
                    await model.send(message)
                    if model.sendState == .sent { step = .sent }
                }
            }
            // Un formulaire vide n'a rien à envoyer, et le bouton le dit en
            // passant au gris plutôt qu'en échouant après coup.
            .disabled(message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    // MARK: - La confirmation

    /// Le rond bleu et sa coche. Rien d'autre : la feuille a déjà dit ce qu'il
    /// fallait dire dans son titre.
    ///
    /// La maquette le dessine en lime ; il est bleu parce que le lime ne parle
    /// que de l'abonnement (Hugo, 14/09/2026, T7) et qu'un message envoyé au
    /// support n'en parle pas. Le bleu est l'accent de tout le reste.
    private var confirmation: some View {
        Image(brand: "IconLucideCheck")
            .resizable()
            .renderingMode(.template)
            .scaledToFit()
            .frame(width: Self.checkSide, height: Self.checkSide)
            .foregroundStyle(MemoBookColor.ink)
            .frame(width: Self.confirmationSide, height: Self.confirmationSide)
            // À moitié, comme la maquette : à pleine intensité, le rond
            // crierait plus fort que le message qu'il confirme.
            .background(MemoBookColor.outline.opacity(0.5), in: .circle)
            .frame(maxWidth: .infinity)
            .accessibilityLabel(SupportCopy.Contact.confirmationVoice)
    }

    /// 66 sur la maquette — 4 rem, plus un quart.
    private static let confirmationSide: CGFloat = 66
    private static let checkSide: CGFloat = 28
}

private extension SupportSheet.Step {
    init(_ route: SupportSheetRoute) {
        switch route {
        case .answer(let entry): self = .answer(entry)
        case .contact: self = .contact
        }
    }
}

// MARK: - « Est-ce utile ? »

/// Les deux pouces sous une réponse.
///
/// C'est **la mesure** que demande la page Notion : « Consultations et clics
/// *cette réponse t'a-t-elle aidé* par identifiant, pour repérer les questions
/// mal formulées et les frictions produit. » Elle porte donc l'identifiant de la
/// question, jamais son texte — c'est l'identifiant qui survit à une réécriture.
///
/// Une fois le vote passé, les pouces laissent place à un merci : les laisser
/// actifs invite à voter deux fois, et fausserait la mesure qu'ils servent.
private struct HelpfulVote: View {
    let entry: FaqEntry
    let model: SupportModel

    var body: some View {
        HStack(spacing: MemoBookSpacing.s) {
            Text(SupportCopy.Answer.helpful)
                .font(MemoBookFont.label)
                .foregroundStyle(MemoBookColor.inkMuted)

            if model.votes[entry.id] == nil {
                thumb(icon: "IconThumbUp", label: SupportCopy.Answer.helpfulYes, isHelpful: true)
                thumb(icon: "IconThumbDown", label: SupportCopy.Answer.helpfulNo, isHelpful: false)
            } else {
                Text(SupportCopy.Answer.thanks)
                    .font(MemoBookFont.label)
                    .foregroundStyle(MemoBookColor.action)
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func thumb(icon: String, label: String, isHelpful: Bool) -> some View {
        Button {
            model.vote(isHelpful, on: entry)
        } label: {
            Image(brand: icon)
                .resizable()
                .renderingMode(.template)
                .scaledToFit()
                .frame(width: thumbSide, height: thumbSide)
                .foregroundStyle(MemoBookColor.inkMuted)
                // Le dessin fait 16, la cible en fait 44 : c'est R7, et deux
                // pouces à 16 pt côte à côte seraient intouchables.
                .frame(
                    width: MemoBookSpacing.minimumTapTarget,
                    height: MemoBookSpacing.minimumTapTarget
                )
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    @ScaledMetric(relativeTo: .body) private var thumbSide: CGFloat = 16
}

#Preview("Réponse") {
    Color.clear
        .brandSheet(isPresented: .constant(true)) {
            SupportSheet(
                model: SupportModel(),
                route: .answer(Faq.entry(id: "faq.carnet.pages") ?? Faq.discover.entries[0])
            )
        }
        .environment(\.colorScheme, .light)
}

#Preview("Nous contacter") {
    Color.clear
        .brandSheet(isPresented: .constant(true)) {
            SupportSheet(model: SupportModel(), route: .contact)
        }
        .environment(\.colorScheme, .light)
}

#Preview("Réponse — AX3") {
    Color.clear
        .brandSheet(isPresented: .constant(true)) {
            SupportSheet(
                model: SupportModel(),
                route: .answer(Faq.entry(id: "faq.raconter.comment") ?? Faq.tell.entries[0])
            )
            .environment(\.dynamicTypeSize, .accessibility3)
        }
        .environment(\.colorScheme, .light)
}
