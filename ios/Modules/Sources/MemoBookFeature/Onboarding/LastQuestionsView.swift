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
/// destinations, et la flèche ramène à la question d'avant. Le premier écran
/// n'a pas de flèche (T192, Hugo, 06/10/2026) : il n'y a rien avant, sinon
/// l'entrée — et y revenir refermait la session qu'on venait d'ouvrir.
///
/// **Les écrans se feuillettent au doigt**, comme les étapes de la création
/// d'un voyage (Hugo, 06/10/2026) : l'illustration glisse, le reste se fond.
///
/// Ils remplacent la page de compléments après Apple ou Google (`2707:9456`),
/// qui ne s'ouvrait plus depuis que ces deux entrées vivent sur l'écran
/// d'entrée — le nom se vérifie désormais ici, pour tout le monde.
public struct LastQuestionsView: View {
    @State private var model: LastQuestionsModel
    private let onFinished: (Account) -> Void

    @FocusState private var focus: Field?

    /// Ce que le champ de la date affiche, tel que tapé, avant nettoyage.
    ///
    /// ⚠️ **Le nettoyage se fait ici, pas seulement dans le modèle.** Un
    /// caractère refusé — une lettre d'un clavier physique, un collage —
    /// ramenait la valeur du modèle à ce qu'elle était déjà : pour SwiftUI rien
    /// n'avait changé, et le champ gardait le caractère affiché par-dessus le
    /// texte indicatif. Tenu ici, le texte change vraiment, et le champ suit.
    @State private var birthDateInput = ""

    /// Le sens du dernier mouvement : en avant sur « Valider », « Passer » et
    /// le glissé vers la gauche, en arrière sur la flèche et le glissé vers la
    /// droite. C'est lui qui décide d'où l'illustration arrive — même
    /// mécanique que ``TripCreationView``.
    @State private var direction: Direction = .forward

    private enum Direction { case forward, backward }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize

    /// Dans l'ordre où le clavier les enchaîne : le prénom d'abord.
    private enum Field: Hashable {
        case firstName, lastName, birthDate, phone
    }

    /// Largeur du cadre de la maquette : au-delà, la colonne se centre.
    private static let contentWidth: CGFloat = 390

    /// La largeur du titre : c'est elle qui le coupe en deux lignes comme la
    /// maquette — « Ton nom / et prénom ».
    private static let titleWidth: CGFloat = 220

    public init(
        model: LastQuestionsModel,
        onFinished: @escaping (Account) -> Void
    ) {
        _model = State(initialValue: model)
        self.onFinished = onFinished
    }

    public var body: some View {
        VStack(spacing: 0) {
            topBar

            ScrollView {
                VStack(spacing: MemoBookSpacing.l) {
                    // L'illustration glisse — celle de l'écran suivant arrive
                    // par la droite pendant que celle-ci sort par la gauche, et
                    // l'inverse en revenant. Le reste se fond : deux
                    // mouvements à la fois se liraient comme un autre écran.
                    illustration
                        .id("illustration-\(model.step.rawValue)")
                        .transition(illustrationTransition)
                    LastQuestionsProgress(current: model.step.rawValue, count: LastQuestionsModel.Step.allCases.count)
                    question
                        .id("question-\(model.step.rawValue)")
                        .transition(.opacity)
                }
                .padding(.horizontal, MemoBookSpacing.screenMargin)
                .padding(.top, MemoBookSpacing.m)
                .padding(.bottom, MemoBookSpacing.l)
                .frame(maxWidth: Self.contentWidth)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
            .scrollIndicators(.hidden)
            // Un glissé vers la gauche avance, vers la droite revient — le
            // geste de la création d'un voyage, aux mêmes seuils : franchement
            // horizontal, pour ne pas prendre le défilement vertical.
            .simultaneousGesture(
                DragGesture(minimumDistance: 30)
                    .onEnded { value in
                        let dx = value.translation.width
                        guard abs(dx) > 60, abs(dx) > abs(value.translation.height) * 1.5 else { return }
                        if dx < 0 {
                            swipeForward()
                        } else if model.canGoBack {
                            back()
                        }
                    }
            )
        }
        .safeAreaInset(edge: .bottom) { validateButton }
        .background(MemoBookColor.background.ignoresSafeArea())
        .environment(\.colorScheme, .light)
        .animation(reduceMotion ? .none : .snappy(duration: 0.35), value: model.step)
        .animation(.snappy(duration: 0.2), value: model.errorMessage)
    }

    /// L'illustration glisse dans le sens où l'on va, de la largeur de
    /// l'écran pour venir du bord. En « Reduce Motion », un fondu.
    private var illustrationTransition: AnyTransition {
        guard !reduceMotion else { return .opacity }
        let travel = DeviceScreen.width
        let (enterFrom, exitTo): (CGFloat, CGFloat) =
            direction == .forward ? (travel, -travel) : (-travel, travel)
        return .asymmetric(
            insertion: .offset(x: enterFrom).combined(with: .opacity),
            removal: .offset(x: exitTo).combined(with: .opacity)
        )
    }

    // MARK: - La tête

    private var topBar: some View {
        HStack {
            // Pas de flèche sur le premier écran (T192) ; la place reste
            // tenue, pour que « Passer » ne bouge pas d'un écran à l'autre.
            if model.canGoBack {
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
                .transition(.opacity)
            } else {
                Color.clear
                    .frame(width: MemoBookSpacing.minimumTapTarget, height: MemoBookSpacing.minimumTapTarget)
                    .accessibilityHidden(true)
            }

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

                // Sous le champ, aligné sur son texte — comme les erreurs de
                // l'inscription.
                if let problem = model.birthDateProblem ?? model.errorMessage {
                    Text(problem)
                        .font(MemoBookFont.notification)
                        .foregroundStyle(MemoBookColor.error)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 20)
                        .fixedSize(horizontal: false, vertical: true)
                        .transition(.opacity)
                }
            }
            // Le texte des champs part de la gauche (Hugo, 06/10/2026) : il
            // était centré comme sur la maquette, et l'intitulé qui monte sur
            // le contour, lui, se pose en haut à gauche.
            .multilineTextAlignment(.leading)
        }
    }

    private var title: String {
        switch model.step {
        case .name: LastQuestionsCopy.nameTitle
        case .birthDate: LastQuestionsCopy.birthDateTitle
        case .phone: LastQuestionsCopy.phoneTitle
        }
    }

    /// Les champs de l'inscription, au comportement près (Hugo, 06/10/2026) :
    /// au repos, le nom du champ en gris dans le cadre ; au focus, le contour
    /// vert et le nom monté en haut à gauche. La date et le téléphone gardent
    /// un repère de format au repos — « JJ/MM/AAAA » —, qui reste dans le
    /// cadre tant qu'on n'a rien tapé (voir ``BrandTextField``).
    @ViewBuilder
    private var fields: some View {
        switch model.step {
        case .name:
            BrandTextField(
                LastQuestionsCopy.firstNameLabel,
                text: $model.firstName,
                field: Field.firstName,
                focus: $focus
            )
            .textContentType(.givenName)
            .textInputAutocapitalization(.words)
            .submitLabel(.next)
            .onSubmit { focus = .lastName }

            BrandTextField(
                LastQuestionsCopy.lastNameLabel,
                text: $model.lastName,
                field: Field.lastName,
                focus: $focus
            )
            .textContentType(.familyName)
            .textInputAutocapitalization(.words)
            .submitLabel(.done)
            .onSubmit(validate)

        case .birthDate:
            BrandTextField(
                LastQuestionsCopy.birthDateLabel,
                text: $birthDateInput,
                field: Field.birthDate,
                focus: $focus,
                placeholder: LastQuestionsCopy.birthDatePlaceholder
            )
            .accessibilityHint(LastQuestionsCopy.Voice.birthDateHint)
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
                LastQuestionsCopy.phoneLabel,
                text: $model.phoneNumber,
                field: Field.phone,
                focus: $focus,
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
        direction = .forward
        Task {
            if let account = await model.validate() { onFinished(account) }
        }
    }

    private func skip() {
        focus = nil
        direction = .forward
        if let account = model.skip() { onFinished(account) }
    }

    private func swipeForward() {
        focus = nil
        direction = .forward
        Task {
            if let account = await model.swipeForward() { onFinished(account) }
        }
    }

    private func back() {
        focus = nil
        direction = .backward
        model.goBack()
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
        onFinished: { _ in }
    )
}

#Preview("Dernières questions — AX3") {
    LastQuestionsView(
        model: LastQuestionsModel(account: Account(id: "preview", createdAt: .now)),
        onFinished: { _ in }
    )
    .environment(\.dynamicTypeSize, .accessibility3)
}
