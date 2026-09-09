import MemoBookCore
import MemoBookDesign
import SwiftUI

/// Créer un voyage : six étapes, une par question, et rien d'autre à l'écran.
///
/// **Toutes les étapes ont la même charpente** — la flèche et « Passer » en
/// haut, l'illustration, la frise, le titre vert, ce qu'on remplit, et le
/// bouton en bas. Seul le milieu change. C'est ce qui rend la traversée lisible :
/// on ne réapprend pas l'écran à chaque question, on ne lit que ce qui bouge.
///
/// **L'écran ne navigue pas.** Il émet une ``HomeIntent`` à la fin, comme
/// l'accueil et la galerie : `RootView` décide que « Commencer ! » ouvre le
/// voyage qu'on vient de créer.
public struct TripCreationView: View {
    @State private var model: TripCreationModel
    private let onIntent: (HomeIntent) -> Void

    public init(model: TripCreationModel, onIntent: @escaping (HomeIntent) -> Void) {
        _model = State(initialValue: model)
        self.onIntent = onIntent
    }

    /// Largeur du cadre de la maquette, comme sur l'écran de bienvenue : le
    /// contenu se centre au lieu de s'étaler sur un 6,9″.
    private static let contentWidth: CGFloat = 390

    @Environment(\.dismiss) private var dismiss
    @FocusState private var focus: TripCreationField?

    /// La charpente n'est pas encore posée.
    ///
    /// C'est l'état de la première maquette de la série : le squelette de
    /// l'étape, avant l'étape. Il couvre les deux seuls moments où l'écran n'a
    /// rien de vrai à montrer — la poussée depuis l'accueil, pendant laquelle
    /// une illustration qui arrive à mi-course saute, et l'aller-retour réseau
    /// qui crée le voyage entre l'avant-dernière étape et la dernière.
    @State private var hasSettled = false

    private var showsSkeleton: Bool { !hasSettled || model.isSaving }

    public var body: some View {
        VStack(spacing: 0) {
            header
            content
        }
        .frame(maxWidth: Self.contentWidth)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(BrandBackdrop())
        .brandHiddenNavigationBar()
        .brandKeyboardDismissBar()
        // La palette de la marque est un papier crème : elle ne se retourne
        // pas en sombre. Voir le commentaire de `MemoBookColor`.
        .environment(\.colorScheme, .light)
        .task {
            // Le temps de la poussée, pas une seconde de plus : le squelette
            // tient la place, il ne la garde pas.
            try? await Task.sleep(for: .milliseconds(350))
            withAnimation(.smooth(duration: 0.3)) { hasSettled = true }
        }
    }

    // MARK: - L'en-tête

    /// La flèche et « Passer ». Ils restent en place pendant le squelette,
    /// grisés : l'écran qui se pose ne doit pas non plus faire clignoter son
    /// en-tête.
    private var header: some View {
        HStack {
            Button(action: goBack) {
                Image(brand: "IconArrowDuo")
                    .resizable()
                    .scaledToFit()
                    .frame(
                        width: MemoBookSpacing.navigationIcon,
                        height: MemoBookSpacing.navigationIcon
                    )
                    // La cible tactile est alignée à gauche sur la marge de la
                    // colonne, et le dessin est centré dedans — comme sur le
                    // profil et la galerie.
                    .frame(
                        width: MemoBookSpacing.minimumTapTarget,
                        height: MemoBookSpacing.minimumTapTarget,
                        alignment: .leading
                    )
                    .contentShape(.rect)
            }
            .accessibilityLabel("Revenir à l’étape précédente")

            Spacer()

            Button("Passer") { Task { await model.skip() } }
                .font(MemoBookFont.body)
                .foregroundStyle(MemoBookColor.inkSecondary)
        }
        .buttonStyle(.plain)
        .disabled(showsSkeleton)
        .opacity(showsSkeleton ? 0.4 : 1)
        .padding(.horizontal, MemoBookSpacing.screenMargin)
        .padding(.top, MemoBookSpacing.xs)
    }

    // MARK: - Le corps

    @ViewBuilder
    private var content: some View {
        if showsSkeleton {
            TripCreationSkeleton()
        } else {
            step
        }
    }

    /// Une étape : l'illustration, la frise, le titre, ce qu'on remplit.
    ///
    /// **Tout défile, sauf le bouton.** Même parti pris que l'écran de
    /// bienvenue, et pour la même raison : en taille de texte accessible, le
    /// titre passe de deux lignes à quatre et l'étape ne tient plus dans
    /// l'écran. Laisser l'illustration et le titre hors du défilement les
    /// faisait rogner — « Contexte de ton voy… » — au lieu de les faire
    /// descendre. Le bouton, lui, reste ancré en bas : c'est la sortie de
    /// l'étape, elle ne se cherche pas.
    private var step: some View {
        ScrollView {
            VStack(spacing: 0) {
                Image(brand: model.step.illustration)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 180, maxHeight: 150)
                    .padding(.top, MemoBookSpacing.m)
                    .accessibilityHidden(true)

                TripCreationProgress(current: model.progress)
                    .padding(.top, MemoBookSpacing.m)

                Text(model.step.title)
                    .font(MemoBookFont.h1)
                    .foregroundStyle(MemoBookColor.action)
                    .multilineTextAlignment(.center)
                    // Le titre prend les lignes qu'il lui faut plutôt que de se
                    // faire rogner : c'est la question de l'étape.
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, MemoBookSpacing.s)
                    .padding(.horizontal, MemoBookSpacing.screenMargin)

                TripCreationStepContent(model: model, focus: $focus)
                    .padding(.horizontal, MemoBookSpacing.screenMargin)
                    .padding(.top, MemoBookSpacing.m)
                    .padding(.bottom, MemoBookSpacing.s)
            }
        }
        .scrollBounceBehavior(.basedOnSize)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: MemoBookSpacing.xs) {
                if let errorMessage = model.errorMessage {
                    ErrorBanner(message: errorMessage)
                }
                callToAction
            }
            .padding(.horizontal, MemoBookSpacing.screenMargin)
            .padding(.top, MemoBookSpacing.xs)
            .padding(.bottom, MemoBookSpacing.s)
            // Le contenu défile sous le bouton : ce dégradé l'en décolle sans
            // poser un bandeau opaque sur le motif de fond.
            .background {
                LinearGradient(
                    colors: [MemoBookColor.background.opacity(0), MemoBookColor.background],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .padding(.top, -MemoBookSpacing.l)
                .allowsHitTesting(false)
            }
        }
        // L'étape change, pas l'écran : une transition croisée, pour que la
        // charpente reste immobile pendant que son contenu se remplace.
        .id(model.step)
        .transition(.opacity)
        .animation(.smooth(duration: 0.28), value: model.step)
    }

    private var callToAction: some View {
        BrandButton(model.step.callToAction, fillsWidth: true) {
            guard model.step != .companions else {
                finish()
                return
            }
            Task { await model.validate() }
        }
        .disabled(!model.canValidate)
    }

    // MARK: - Les deux sorties

    /// La flèche du haut. Depuis la première étape il n'y a pas d'étape
    /// précédente : elle referme l'écran, ce que le modèle ne peut pas faire à
    /// sa place.
    private func goBack() {
        focus = nil
        if !model.goBack() { dismiss() }
    }

    /// « Commencer ! » : on ouvre le voyage qu'on vient de créer.
    ///
    /// **Sans `dismiss()`.** Refermer l'écran et demander le voyage sont deux
    /// changements de pile dans le même geste : lancés d'ici, ils se croisent et
    /// laissent une page blanche. C'est `RootView` qui remplace l'étape par le
    /// voyage, en une seule écriture. La vue annonce, elle ne navigue pas.
    ///
    /// Le carnet, lui, existe déjà : il a été créé à la validation de l'étape
    /// précédente. Sans lui — un « Commencer ! » qui n'aurait rien à ouvrir —
    /// il ne reste qu'à refermer.
    private func finish() {
        guard let created = model.created else {
            dismiss()
            return
        }
        onIntent(.openTrip(id: created.trip.id))
    }
}

// MARK: - La frise

/// Une barre par étape, la verte étant celle qu'on remplit.
///
/// Elle reprend le dessin de ``BrandWaveform`` — des capsules fines et
/// espacées — et ce n'est pas un hasard de maquette : MemoBook se remplit à la
/// voix, et remplir un formulaire y ressemble à parler. La barre en cours est
/// plus haute, comme une syllabe qu'on prononce.
struct TripCreationProgress: View {
    let current: Int

    @ScaledMetric(relativeTo: .caption) private var barWidth: CGFloat = 3
    @ScaledMetric(relativeTo: .caption) private var restingHeight: CGFloat = 12
    @ScaledMetric(relativeTo: .caption) private var activeHeight: CGFloat = 18

    var body: some View {
        HStack(alignment: .center, spacing: 5) {
            ForEach(TripCreationStep.allCases, id: \.rawValue) { step in
                let isCurrent = step.rawValue == current
                Capsule()
                    .fill(isCurrent ? MemoBookColor.action : MemoBookColor.inkFaint)
                    .frame(width: barWidth, height: isCurrent ? activeHeight : restingHeight)
            }
        }
        .animation(.smooth(duration: 0.28), value: current)
        .accessibilityElement()
        .accessibilityLabel("Étape \(current + 1) sur \(TripCreationStep.allCases.count)")
    }
}

// MARK: - Le squelette

/// La place de l'étape, avant l'étape — la première maquette de la série.
///
/// Elle reprend la charpente au pixel près : l'illustration, la frise, les deux
/// lignes du titre, ce qu'on remplit, et le bouton. C'est la seule façon que
/// rien ne bouge quand le contenu arrive.
struct TripCreationSkeleton: View {
    var body: some View {
        VStack(spacing: 0) {
            BrandSkeleton(width: 150, height: 150, cornerRadius: MemoBookSpacing.overlayCornerRadius)
                .padding(.top, MemoBookSpacing.m)

            BrandSkeleton(width: 60, height: 10)
                .padding(.top, MemoBookSpacing.m + 8)

            VStack(spacing: MemoBookSpacing.xs + 4) {
                BrandSkeleton(width: 180, height: 18)
                BrandSkeleton(width: 240, height: 18)
            }
            .padding(.top, MemoBookSpacing.m)

            BrandSkeleton(height: MemoBookSpacing.fieldHeight, cornerRadius: MemoBookSpacing.largeCornerRadius)
                .padding(.horizontal, MemoBookSpacing.screenMargin)
                .padding(.top, MemoBookSpacing.l)

            Spacer(minLength: MemoBookSpacing.m)

            BrandSkeleton(
                height: MemoBookSpacing.controlHeight,
                cornerRadius: MemoBookSpacing.controlCornerRadius
            )
            .padding(.horizontal, MemoBookSpacing.screenMargin)
            .padding(.bottom, MemoBookSpacing.s)
        }
        .accessibilityElement()
        .accessibilityLabel("Chargement")
    }
}

#Preview("Créer un voyage") {
    NavigationStack {
        TripCreationView(model: TripCreationModel()) { _ in }
    }
}
