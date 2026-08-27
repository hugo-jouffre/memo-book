import SwiftUI

/// Le flow d'entrée dans l'app, du *Splash* jusqu'à la liste des carnets.
///
/// Un seul écran à la fois, sans pile de navigation : aucune de ces étapes
/// n'a de bouton retour dans les maquettes, et *Mdp oublié - config* ne doit
/// même pas être atteignable autrement que par le lien reçu par email.
struct OnboardingFlowView: View {
    @Bindable var model: OnboardingModel
    let dependencies: AppDependencies

    var body: some View {
        content
            .transition(.opacity)
            .animation(.easeInOut(duration: 0.25), value: model.step)
            .task { await model.start() }
    }

    @ViewBuilder
    private var content: some View {
        switch model.step {
        case .splash, .home:
            // `.home` ne s'affiche jamais ici : `RootView` a déjà rendu la main
            // à la liste des carnets. Le splash tient la place le temps de la
            // bascule, plutôt qu'un écran vide d'une frame.
            SplashView()

        case .welcome:
            WelcomeView(onDiscover: model.discoverMemoBook)

        case .credentials(let tab):
            CredentialsView(
                model: CredentialsModel(
                    api: dependencies.api,
                    onboarding: model,
                    tab: tab,
                    social: dependencies.social
                ),
                failure: $model.signInFailure
            )
            // L'identité suit l'écran, pas l'onglet : basculer entre
            // « S'inscrire » et « Se connecter » ne doit pas effacer ce qui a
            // déjà été saisi. Passer par *Mot de passe oublié*, en revanche,
            // démonte bien l'écran — c'est `carriedEmail` qui rapporte alors
            // l'adresse au retour.
            .id("credentials")

        case .forgotPassword:
            ForgotPasswordView(
                model: ForgotPasswordModel(api: dependencies.api, onboarding: model)
            )

        case .forgotPasswordNoAccount(let email):
            ForgotPasswordNoAccountView(
                email: email,
                onCreateAccount: model.createAccountFromMissingAccount
            )

        case .resetPassword(let token):
            ResetPasswordView(
                model: ResetPasswordModel(
                    token: token,
                    api: dependencies.api,
                    onboarding: model
                )
            )

        case .completeProfile(let draft):
            CompleteProfileView(
                model: CompleteProfileModel(
                    draft: draft,
                    api: dependencies.api,
                    onboarding: model
                )
            )
        }
    }
}
