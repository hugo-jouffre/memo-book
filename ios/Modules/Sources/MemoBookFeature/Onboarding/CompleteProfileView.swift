import MemoBookCore
import MemoBookDesign
import MemoBookNetworking
import SwiftUI

/// *Complète tes informations* — après une connexion tierce sur un compte
/// encore inconnu.
///
/// Le compte n'est jamais créé en silence : ce qui vient du fournisseur est
/// pré-rempli et reste modifiable. Nœud Figma `2707:9456`.
struct CompleteProfileView: View {
    @State private var model: CompleteProfileModel
    @FocusState private var focus: CompleteProfileModel.Field?

    init(model: CompleteProfileModel) {
        self._model = State(initialValue: model)
    }

    var body: some View {
        ZStack {
            MemoBookColor.background.ignoresSafeArea()

            ScrollView {
                VStack(spacing: MemoBookSpacing.l) {
                    heading
                    fields

                    MemoBookButton(
                        "Continuer",
                        isEnabled: model.canSubmit,
                        isLoading: model.isSubmitting
                    ) {
                        Task { await model.submit() }
                    }
                }
                .padding(.horizontal, MemoBookSpacing.screenMargin)
                .padding(.top, rem(2))
                .padding(.bottom, MemoBookSpacing.l)
            }
            .scrollDismissesKeyboard(.interactively)
        }
    }

    private var heading: some View {
        VStack(alignment: .leading, spacing: MemoBookSpacing.xs) {
            Text("Complète tes informations")
                .font(MemoBookFont.screenTitle)
                .foregroundStyle(MemoBookColor.ink)
                .tracking(MemoBookTracking.tight)
                .fixedSize(horizontal: false, vertical: true)

            Text("nous avons récupéré les informations suivantes, vérifie leur validité")
                .font(MemoBookFont.body)
                .foregroundStyle(MemoBookColor.inkSecondary)
                .tracking(MemoBookTracking.body)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var fields: some View {
        VStack(alignment: .leading, spacing: MemoBookSpacing.s) {
            HStack(spacing: MemoBookSpacing.s) {
                MemoBookTextField(
                    "Prénom",
                    text: $model.firstName,
                    field: .firstName,
                    focus: $focus,
                    kind: .givenName,
                    error: model.fieldErrors[.firstName]
                ) { focus = .lastName }

                MemoBookTextField(
                    "Nom",
                    text: $model.lastName,
                    field: .lastName,
                    focus: $focus,
                    kind: .familyName,
                    error: model.fieldErrors[.lastName]
                ) { focus = .email }
            }

            MemoBookTextField(
                "Email",
                text: $model.email,
                field: .email,
                focus: $focus,
                kind: .email,
                submitLabel: .go,
                error: model.fieldErrors[.email]
            ) { Task { await model.submit() } }

            if model.draft.usesAppleRelayEmail {
                // L'adresse relais est acceptée telle quelle : Apple fait
                // suivre le courrier tant que l'accès n'est pas révoqué. On ne
                // réclame pas une adresse personnelle à quelqu'un qui a
                // justement choisi de la masquer.
                Text(
                    "Cette adresse relais Apple fonctionne : tes emails MemoBook arriveront bien dans ta boîte."
                )
                .font(MemoBookFont.caption)
                .foregroundStyle(MemoBookColor.inkSecondary)
                .padding(.leading, MemoBookSpacing.m)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

#Preview("Complète tes informations") {
    let api = PreviewAPI()
    let onboarding = OnboardingModel(api: api, sessions: InMemorySessionStore())
    return CompleteProfileView(
        model: CompleteProfileModel(
            draft: SocialProfileDraft(
                socialToken: "apple:001.abcdef",
                provider: .apple,
                firstName: "Cla",
                lastName: "Thioll",
                email: "xk29fj@privaterelay.appleid.com"
            ),
            api: api,
            onboarding: onboarding
        )
    )
}
