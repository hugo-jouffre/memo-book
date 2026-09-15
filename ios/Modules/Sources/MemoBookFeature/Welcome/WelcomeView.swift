import AuthenticationServices
import MemoBookCore
import MemoBookDesign
import SwiftUI

/// L'écran d'entrée de MemoBook : ce que l'app fait, en trois mots, et les deux
/// façons d'entrer sans taper quoi que ce soit.
///
/// **C'est la seule porte de l'app**, et c'est ce qui a changé : Apple et Google
/// ne vivent plus dans le formulaire, ils vivent ici. Le formulaire — inscription
/// et connexion par e-mail — est devenu un écran poussé, qu'on atteint par
/// « S'inscrire avec un e-mail » et qu'on quitte par une flèche de retour.
///
/// **Une photo, puis une carte posée dessus.** L'image tient le haut de l'écran
/// et ne bouge pas ; la carte crème monte par-dessus, coins arrondis et ombre
/// portée vers le haut. Sur un grand écran elle se pose au bas de la dalle et
/// laisse voir la photo ; sur un iPhone SE le contenu dépasse et défile — la
/// carte glisse alors sur la photo au lieu de la pousser, ce qui garde le haut
/// de l'écran habité.
///
/// **Rien n'attend le réseau.** Aucun appel n'est fait ici : l'écran est
/// entièrement dessiné par l'app, et les deux boutons n'ouvrent leur feuille
/// qu'au doigt. C'est le premier écran, celui qu'on voit avant d'avoir un
/// compte : il doit apparaître à l'ouverture du binaire, pas après un
/// aller-retour.
public struct WelcomeView: View {
    /// Un fournisseur tiers a répondu, et le serveur a ouvert la session.
    private let onAuthenticated: (Account) -> Void
    /// « S'inscrire avec un e-mail » — l'écran poussé qui porte le formulaire.
    private let onEmail: () -> Void

    public init(
        onAuthenticated: @escaping (Account) -> Void,
        onEmail: @escaping () -> Void
    ) {
        self.onAuthenticated = onAuthenticated
        self.onEmail = onEmail
    }

    @Environment(AppDependencies.self) private var dependencies
    @Environment(\.dynamicTypeSize) private var typeSize

    @State private var model: AuthModel?

    /// Largeur du cadre de la maquette : au-delà, la colonne se centre au lieu
    /// de s'étirer — même règle que partout ailleurs dans l'app.
    private static let contentWidth: CGFloat = 390

    /// Hauteur de la photo, et part de l'écran qu'elle garde pour elle sous la
    /// carte. La maquette dessine 380 de photo dont 201 restent visibles
    /// (390 × 844) : les deux se suivent proportionnellement pour qu'un écran
    /// plus court ne réduise pas la photo à un bandeau.
    private static let heroHeight: CGFloat = 380
    private static let heroRevealRatio: CGFloat = 201 / 844

    public var body: some View {
        // Le modèle a besoin de l'API, qui arrive par l'environnement : il ne
        // peut pas naître dans un initialiseur de propriété.
        Group {
            if let model {
                content(model)
            } else {
                MemoBookColor.background
                    .ignoresSafeArea()
                    .onAppear { model = AuthModel(api: dependencies.api) }
            }
        }
        // Le crème de la marque ne se retourne pas en sombre — voir
        // `MemoBookColor`.
        .environment(\.colorScheme, .light)
    }

    private func content(_ model: AuthModel) -> some View {
        GeometryReader { proxy in
            ZStack(alignment: .top) {
                hero

                ScrollView {
                    VStack(spacing: 0) {
                        // Ce qu'on laisse voir de la photo. `Color` est gourmand :
                        // sur un grand écran il prend tout le reste et la carte se
                        // pose au bas de la dalle ; sur un petit il tombe à son
                        // minimum et la carte défile.
                        Color.clear
                            .frame(minHeight: proxy.size.height * Self.heroRevealRatio)
                            .accessibilityHidden(true)

                        card(model)
                    }
                    .frame(minHeight: proxy.size.height, alignment: .bottom)
                }
                .scrollIndicators(.hidden)
                .scrollBounceBehavior(.basedOnSize)
            }
        }
        .background(MemoBookColor.background.ignoresSafeArea())
        // Le retour de la feuille Google passe par une adresse au schéma de
        // l'app, déclarée dans `project.yml`.
        .onOpenURL { GoogleSignInService.handle($0) }
    }

    // MARK: - La photo

    /// Elle déborde sous la barre d'état et monte jusqu'au bord de la dalle :
    /// c'est une photo de couverture, pas une illustration posée dans une page.
    private var hero: some View {
        // ⚠️ **La photo est posée en `overlay` d'un cadre vide**, et non
        // dimensionnée elle-même. `scaledToFill` ne se laisse pas contraindre en
        // largeur : une `Image` ainsi cadrée rend une taille de mise en page de
        // 620 pt de large sur un cadre de 380 de haut, la `ZStack` prend cette
        // largeur, et **tout l'écran déborde vers la droite** — le titre sortait
        // par le bord. Un cadre vide, lui, accepte la largeur proposée ; la
        // photo le remplit et `clipped()` coupe ce qui dépasse.
        Color.clear
            .frame(maxWidth: .infinity)
            .frame(height: Self.heroHeight)
            .overlay {
                Image(brand: "PhotoWelcomeHero")
                    .resizable()
                    .scaledToFill()
            }
            // Le voile de la maquette : la photo passe sous du texte blanc en
            // haut, et sous la carte en bas.
            .overlay(MemoBookColor.ink.opacity(0.4))
            // Et le dégradé qui protège l'heure et la batterie, sans poser un
            // bandeau opaque sur l'image.
            .overlay(alignment: .top) {
                LinearGradient(
                    colors: [MemoBookColor.ink.opacity(0.25), MemoBookColor.ink.opacity(0)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: MemoBookSpacing.l + MemoBookSpacing.m)
            }
            .clipped()
            .frame(maxWidth: .infinity, alignment: .top)
            .ignoresSafeArea(edges: .top)
            .accessibilityLabel(WelcomeCopy.Voice.hero)
    }

    // MARK: - La carte

    private func card(_ model: AuthModel) -> some View {
        VStack(alignment: .leading, spacing: MemoBookSpacing.l) {
            titleBlock
            featuresBlock
            authBlock(model)
        }
        .padding(.horizontal, MemoBookSpacing.screenMargin)
        .padding(.top, MemoBookSpacing.m)
        .padding(.bottom, MemoBookSpacing.l)
        .frame(maxWidth: Self.contentWidth)
        .frame(maxWidth: .infinity)
        .background {
            // Le crème remonte sous la carte et **déborde vers le bas** : sur un
            // grand écran, la carte s'arrête à la zone sûre et la bande
            // d'indicateur d'accueil doit rester crème, pas montrer la photo.
            UnevenRoundedRectangle(
                topLeadingRadius: MemoBookSpacing.largeCornerRadius + MemoBookSpacing.s,
                topTrailingRadius: MemoBookSpacing.largeCornerRadius + MemoBookSpacing.s
            )
            .fill(MemoBookColor.background)
            .ignoresSafeArea(edges: .bottom)
            // L'ombre de la maquette monte : c'est la carte qui est posée sur
            // la photo, pas l'inverse.
            .shadow(color: .black.opacity(0.25), radius: 2, y: -4)
        }
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: MemoBookSpacing.xs) {
            (Text(WelcomeCopy.titleLead).font(MemoBookFont.h1Light)
                + Text(WelcomeCopy.titleStrong)
                .font(MemoBookFont.h1)
                .foregroundColor(MemoBookColor.action))
                .foregroundStyle(MemoBookColor.ink)
                .tracking(-0.41)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)

            Text(WelcomeCopy.subtitle)
                .font(MemoBookFont.taglineRegular)
                .foregroundStyle(MemoBookColor.inkMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Les trois temps, et la note

    private var featuresBlock: some View {
        VStack(spacing: MemoBookSpacing.s) {
            features
            socialProof
        }
    }

    /// En taille accessible les trois colonnes deviennent trois lignes : à
    /// 118 pt de large, « 1. Raconte » se coupe au milieu.
    @ViewBuilder
    private var features: some View {
        if typeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: MemoBookSpacing.snug) {
                ForEach(WelcomeCopy.features) { feature in
                    HStack(spacing: MemoBookSpacing.snug) {
                        featureIcon(feature)
                        Text(feature.label)
                            .font(MemoBookFont.overline)
                            .foregroundStyle(MemoBookColor.ink)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            HStack(alignment: .top, spacing: MemoBookSpacing.xs) {
                ForEach(WelcomeCopy.features) { feature in
                    VStack(spacing: MemoBookSpacing.xs) {
                        featureIcon(feature)
                        Text(feature.label)
                            .font(MemoBookFont.overline)
                            .foregroundStyle(MemoBookColor.ink)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }

    @ScaledMetric(relativeTo: .body) private var featureIconSide: CGFloat = MemoBookSpacing.xl

    private func featureIcon(_ feature: WelcomeCopy.Feature) -> some View {
        Image(brand: feature.icon)
            .resizable()
            .renderingMode(.template)
            .scaledToFit()
            .frame(width: featureIconSide, height: featureIconSide)
            .foregroundStyle(MemoBookColor.ink)
            .accessibilityHidden(true)
    }

    private var socialProof: some View {
        let shape = RoundedRectangle(cornerRadius: MemoBookSpacing.snug)

        return HStack(spacing: MemoBookSpacing.xs) {
            Text(WelcomeCopy.rating)
                .font(MemoBookFont.tagline)
                .foregroundStyle(MemoBookColor.action)

            Circle()
                .fill(MemoBookColor.inkMuted)
                .frame(width: MemoBookSpacing.xs / 2, height: MemoBookSpacing.xs / 2)

            Text(WelcomeCopy.community)
                .font(MemoBookFont.caption)
                .foregroundStyle(MemoBookColor.ink)
        }
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
        .padding(MemoBookSpacing.xs + 2)
        .frame(maxWidth: .infinity)
        .overlay { shape.strokeBorder(MemoBookColor.hairline, lineWidth: 1) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(WelcomeCopy.Voice.rating)
    }

    // MARK: Entrer

    private func authBlock(_ model: AuthModel) -> some View {
        VStack(alignment: .leading, spacing: MemoBookSpacing.s) {
            VStack(alignment: .leading, spacing: MemoBookSpacing.xs / 2) {
                Text(WelcomeCopy.hello)
                    .font(MemoBookFont.calloutTitle)
                    .foregroundStyle(MemoBookColor.ink)
                Text(WelcomeCopy.helloDetail)
                    .font(MemoBookFont.taglineRegular)
                    .foregroundStyle(MemoBookColor.inkMuted)
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)

            WelcomeSocialButtons(
                onCredential: { accept($0, model) },
                onFailure: model.report,
                onGoogle: { signInWithGoogle(model) }
            )
            .disabled(model.isWorking)

            if let errorMessage = model.errorMessage {
                Text(errorMessage)
                    .font(MemoBookFont.notification)
                    .foregroundStyle(MemoBookColor.error)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .transition(.opacity)
            }

            footer(model)
        }
        .animation(.snappy(duration: 0.2), value: model.errorMessage)
    }

    private func footer(_ model: AuthModel) -> some View {
        VStack(spacing: MemoBookSpacing.xs) {
            Button(action: onEmail) {
                Text(WelcomeCopy.email)
                    .font(MemoBookFont.tagline)
                    .foregroundStyle(MemoBookColor.action)
                    .underline()
                    .frame(maxWidth: .infinity, minHeight: MemoBookSpacing.minimumTapTarget)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .disabled(model.isWorking)

            Text(WelcomeCopy.legal)
                .font(MemoBookFont.mention)
                .foregroundStyle(MemoBookColor.inkMuted)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            #if DEBUG
                // ⚠️ PROVISOIRE — l'entrée de chantier, par le compte que le
                // seed pose. Absente de la version livrée : `#if DEBUG` ne
                // compile pas en release.
                Button {
                    Task {
                        guard let account = await model.signInAsTestAccount() else { return }
                        onAuthenticated(account)
                    }
                } label: {
                    Text("Testing mode →")
                        .font(MemoBookFont.caption)
                        .foregroundStyle(MemoBookColor.inkMuted)
                        .frame(maxWidth: .infinity, minHeight: MemoBookSpacing.minimumTapTarget)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
            #endif
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Actions

    private func accept(_ credential: SocialCredential, _ model: AuthModel) {
        Task {
            guard let account = await model.accept(credential) else { return }
            onAuthenticated(account)
        }
    }

    private func signInWithGoogle(_ model: AuthModel) {
        Task {
            do {
                // `nil` : l'utilisateur a refermé la feuille. Rien à dire.
                guard let credential = try await GoogleSignInService.signIn() else { return }
                accept(credential, model)
            } catch {
                model.report(error)
            }
        }
    }
}

#Preview("Accueil — 1ère connexion") {
    WelcomeView(onAuthenticated: { _ in }, onEmail: {})
        .environment(AppDependencies(api: PreviewAPI()))
}

#Preview("Accueil — AX3") {
    WelcomeView(onAuthenticated: { _ in }, onEmail: {})
        .environment(AppDependencies(api: PreviewAPI()))
        .environment(\.dynamicTypeSize, .accessibility3)
}
