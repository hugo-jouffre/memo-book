import MemoBookCore
import MemoBookDesign
import SwiftUI

/// Les « Dernières questions » (`3533:14979`, `3533:15036`, `3533:15010`) :
/// trois écrans à la fin de l'onboarding, pour qui entre pour la première fois.
///
/// Chacun a le même dessin — la flèche et « Passer » en tête, l'illustration
/// de marque, les trois traits qui disent où l'on en est, le titre en vert,
/// le champ, et « Valider » en bas. Seuls l'illustration, le titre et le
/// champ changent : c'est **un** écran dont le contenu glisse, pas trois
/// destinations, et la flèche ramène à la question d'avant.
///
/// Ils remplacent la page de compléments après Apple ou Google (`2707:9456`),
/// qui ne s'ouvrait plus depuis que ces deux entrées vivent sur l'écran
/// d'entrée — le nom se vérifie désormais ici, pour tout le monde.
public struct LastQuestionsView: View {
    @State private var model: LastQuestionsModel
    private let onFinished: (Account) -> Void
    /// La flèche du premier écran : il n'y a rien avant, sinon l'entrée.
    private let onLeave: () -> Void

    @FocusState private var focus: Field?

    /// Ce que le champ de la date affiche, tel que tapé, avant nettoyage.
    ///
    /// ⚠️ **Le nettoyage se fait ici, pas seulement dans le modèle.** Un
    /// caractère refusé — une lettre d'un clavier physique, un collage —
    /// ramenait la valeur du modèle à ce qu'elle était déjà : pour SwiftUI rien
    /// n'avait changé, et le champ gardait le caractère affiché par-dessus le
    /// texte indicatif. Tenu ici, le texte change vraiment, et le champ suit.
    @State private var birthDateInput = ""

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize

    private enum Field: Hashable {
        case lastName, firstName, birthDate, phone
    }

    /// Largeur du cadre de la maquette : au-delà, la colonne se centre.
    private static let contentWidth: CGFloat = 390

    /// La largeur du titre : c'est elle qui le coupe en deux lignes comme la
    /// maquette — « Ton Nom / et Prénom ».
    private static let titleWidth: CGFloat = 220

    public init(
        model: LastQuestionsModel,
        onFinished: @escaping (Account) -> Void,
        onLeave: @escaping () -> Void
    ) {
        _model = State(initialValue: model)
        self.onFinished = onFinished
        self.onLeave = onLeave
    }

    public var body: some View {
        VStack(spacing: 0) {
            topBar

            ScrollView {
                VStack(spacing: MemoBookSpacing.l) {
                    illustration
                    LastQuestionsProgress(current: model.step.rawValue, count: LastQuestionsModel.Step.allCases.count)
                    question
                }
                .id(model.step)
                .transition(stepTransition)
                .padding(.horizontal, MemoBookSpacing.screenMargin)
                .padding(.top, MemoBookSpacing.m)
                .padding(.bottom, MemoBookSpacing.l)
                .frame(maxWidth: Self.contentWidth)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
            .scrollIndicators(.hidden)
        }
        .safeAreaInset(edge: .bottom) { validateButton }
        .background(MemoBookColor.background.ignoresSafeArea())
        .environment(\.colorScheme, .light)
        .animation(reduceMotion ? .none : .snappy(duration: 0.35), value: model.step)
        .animation(.snappy(duration: 0.2), value: model.errorMessage)
    }

    /// Les écrans glissent dans le sens où l'on va.
    private var stepTransition: AnyTransition {
        reduceMotion ? .opacity : .asymmetric(
            insertion: .move(edge: .trailing).combined(with: .opacity),
            removal: .move(edge: .leading).combined(with: .opacity)
        )
    }

    // MARK: - La tête

    private var topBar: some View {
        HStack {
            Button(action: back) {
                Image(brand: "IconArrowDuo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: MemoBookSpacing.navigationIcon, height: MemoBookSpacing.navigationIcon)
                    .frame(width: MemoBookSpacing.minimumTapTarget, height: MemoBookSpacing.minimumTapTarget)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Retour")

            Spacer()

            Button(action: skip) {
                Text(LastQuestionsCopy.skip)
                    .font(MemoBookFont.bodySemibold)
                    .foregroundStyle(MemoBookColor.inkMuted)
                    .frame(minHeight: MemoBookSpacing.minimumTapTarget)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .disabled(model.isSaving)
        }
        .padding(.horizontal, MemoBookSpacing.screenMargin)
        .padding(.top, MemoBookSpacing.xs)
    }

    // MARK: - L'illustration

    private var illustrationName: String {
        switch model.step {
        case .name: "IllustrationCarteID"
        case .birthDate: "IllustrationCalendrier"
        case .phone: "IllustrationPhone"
        }
    }

    /// 200 pt de haut sur la maquette ; elle rétrécit sur un petit écran et en
    /// taille accessible, où c'est le champ qui doit rester visible.
    @ScaledMetric(relativeTo: .body) private var illustrationHeight: CGFloat = 200

    private var illustration: some View {
        Image(brand: illustrationName)
            .resizable()
            .scaledToFit()
            .frame(height: typeSize.isAccessibilitySize ? 120 : min(illustrationHeight, 200))
            .frame(maxWidth: .infinity)
            .accessibilityHidden(true)
    }

    // MARK: - La question

    @ViewBuilder
    private var question: some View {
        VStack(spacing: MemoBookSpacing.m) {
            Text(title)
                .font(MemoBookFont.h1)
                .foregroundStyle(MemoBookColor.action)
                .multilineTextAlignment(.center)
                .frame(maxWidth: Self.titleWidth)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)

            VStack(spacing: MemoBookSpacing.s) {
                fields

                if let problem = model.birthDateProblem ?? model.errorMessage {
                    Text(problem)
                        .font(MemoBookFont.notification)
                        .foregroundStyle(MemoBookColor.error)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .transition(.opacity)
                }
            }
            // Le texte des champs est centré, comme sur la maquette.
            .multilineTextAlignment(.center)
        }
    }

    private var title: String {
        switch model.step {
        case .name: LastQuestionsCopy.nameTitle
        case .birthDate: LastQuestionsCopy.birthDateTitle
        case .phone: LastQuestionsCopy.phoneTitle
        }
    }

    @ViewBuilder
    private var fields: some View {
        switch model.step {
        case .name:
            BrandTextField(
                LastQuestionsCopy.Voice.lastName,
                text: $model.lastName,
                field: Field.lastName,
                focus: $focus,
                labelPlacement: .hidden,
                placeholder: LastQuestionsCopy.lastNamePlaceholder
            )
            .textContentType(.familyName)
            .textInputAutocapitalization(.words)
            .submitLabel(.next)
            .onSubmit { focus = .firstName }

            BrandTextField(
                LastQuestionsCopy.Voice.firstName,
                text: $model.firstName,
                field: Field.firstName,
                focus: $focus,
                labelPlacement: .hidden,
                placeholder: LastQuestionsCopy.firstNamePlaceholder
            )
            .textContentType(.givenName)
            .textInputAutocapitalization(.words)
            .submitLabel(.done)
            .onSubmit(validate)

        case .birthDate:
            BrandTextField(
                LastQuestionsCopy.Voice.birthDate,
                text: $birthDateInput,
                field: Field.birthDate,
                focus: $focus,
                labelPlacement: .hidden,
                placeholder: LastQuestionsCopy.birthDatePlaceholder
            )
            .keyboardType(.numberPad)
            .textContentType(.birthdate)
            .onAppear { birthDateInput = model.birthDateText }
            .onChange(of: birthDateInput) { _, typed in
                let masked = LastQuestionsModel.maskedBirthDate(typed)
                if masked != typed { birthDateInput = masked }
                model.birthDateText = masked
            }

        case .phone:
            BrandTextField(
                LastQuestionsCopy.Voice.phone,
                text: $model.phoneNumber,
                field: Field.phone,
                focus: $focus,
                labelPlacement: .hidden,
                placeholder: LastQuestionsCopy.phonePlaceholder
            )
            .keyboardType(.phonePad)
            .textContentType(.telephoneNumber)
        }
    }

    // MARK: - Valider

    private var validateButton: some View {
        BrandButton(
            LastQuestionsCopy.validate,
            isLoading: model.isSaving,
            fillsWidth: true,
            action: validate
        )
        .disabled(!model.canValidate)
        .padding(.horizontal, MemoBookSpacing.screenMargin)
        .padding(.vertical, MemoBookSpacing.snug)
        .frame(maxWidth: Self.contentWidth)
        .frame(maxWidth: .infinity)
        .background(MemoBookColor.background)
    }

    private func validate() {
        focus = nil
        Task {
            if let account = await model.validate() { onFinished(account) }
        }
    }

    private func skip() {
        focus = nil
        if let account = model.skip() { onFinished(account) }
    }

    private func back() {
        focus = nil
        if !model.goBack() { onLeave() }
    }
}

/// Les trois traits qui disent où l'on en est (`3533:14203`) : le trait de la
/// question en cours est le plus haut et le seul en vert, les autres
/// raccourcissent en s'éloignant.
struct LastQuestionsProgress: View {
    let current: Int
    let count: Int

    /// Les hauteurs de la maquette, selon la distance à la question en cours.
    private static let heights: [CGFloat] = [20, 16, 13]

    var body: some View {
        HStack(alignment: .bottom, spacing: 6) {
            ForEach(0..<count, id: \.self) { index in
                let distance = min(abs(index - current), Self.heights.count - 1)
                Capsule()
                    .fill(index == current ? MemoBookColor.action : MemoBookColor.inkFaint)
                    .frame(width: 2.5, height: Self.heights[distance])
            }
        }
        .frame(height: Self.heights[0], alignment: .bottom)
        .animation(.snappy(duration: 0.25), value: current)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(LastQuestionsCopy.Voice.progress(step: current + 1, of: count))
    }
}

#Preview("Dernières questions — le nom") {
    LastQuestionsView(
        model: LastQuestionsModel(account: Account(id: "preview", firstName: "Camille", createdAt: .now)),
        onFinished: { _ in },
        onLeave: {}
    )
}

#Preview("Dernières questions — AX3") {
    LastQuestionsView(
        model: LastQuestionsModel(account: Account(id: "preview", createdAt: .now)),
        onFinished: { _ in },
        onLeave: {}
    )
    .environment(\.dynamicTypeSize, .accessibility3)
}
