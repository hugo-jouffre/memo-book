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

    /// Le sens du dernier mouvement : en avant sur « Valider » et « Passer »,
    /// en arrière sur la flèche. C'est lui qui décide d'où l'illustration
    /// arrive et par où elle repart — voir ``illustrationTransition``.
    @State private var direction: Direction = .forward

    private enum Direction { case forward, backward }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
        // Les thèmes de la première étape viennent du serveur, et se lisent
        // **en même temps** que la charpente se pose — pas après.
        .task { await model.loadThemes() }
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

            // La dernière étape n'a rien à passer : le voyage est créé, le code
            // d'accès est là, il n'y a plus que « Commencer ! » — Hugo,
            // 14/09/2026. Un « Passer » à côté laissait croire qu'on pouvait
            // encore éviter quelque chose.
            if model.step.canBeSkipped {
                Button("Passer") {
                    direction = .forward
                    Task { await model.skip() }
                }
                    .font(MemoBookFont.body)
                    .foregroundStyle(MemoBookColor.inkMuted)
            }
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
                // **Un sticker**, pas une image posée : l'ombre portée le
                // décolle de la page — Hugo, 14/09/2026. L'ombre suit le
                // détourage du dessin, ce qui fait le sticker ; c'est l'une des
                // deux ombres de la marque, il n'y en a pas de troisième.
                //
                // Et **il glisse** : celui de l'étape suivante arrive par la
                // droite pendant que celui-ci sort par la gauche, comme des
                // cartes qu'on fait défiler — le sens s'inverse sur la flèche
                // de retour. Le reste de l'étape, lui, se fond : deux
                // mouvements en même temps se lisent comme un écran qui change,
                // un seul comme une question qui suit l'autre.
                Image(brand: model.step.illustration)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 180, maxHeight: 150)
                    .brandShadow(.raised)
                    .padding(.top, MemoBookSpacing.m)
                    .accessibilityHidden(true)
                    .id("illustration-\(model.step.rawValue)")
                    .transition(illustrationTransition)

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
                    .id("title-\(model.step.rawValue)")
                    .transition(.opacity)

                TripCreationStepContent(model: model, focus: $focus)
                    .padding(.horizontal, MemoBookSpacing.screenMargin)
                    .padding(.top, MemoBookSpacing.m)
                    .padding(.bottom, MemoBookSpacing.s)
                    .id("content-\(model.step.rawValue)")
                    .transition(.opacity)
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
            // Le contenu défile sous le bouton : le voile de la marque l'en
            // décolle sans poser un bandeau opaque sur le motif de fond, et
            // descend jusqu'au bord de la dalle — voir ``BrandFooterScrim``.
            .brandFooterScrim()
        }
        // L'étape change, pas l'écran : la charpente reste immobile — la
        // frise, le bouton — pendant que l'illustration glisse et que le titre
        // et le contenu se remplacent en fondu. Chaque morceau porte sa propre
        // identité pour avoir sa propre transition ; un seul `id` sur l'écran
        // entier ne saurait faire que du fondu.
        .animation(reduceMotion ? nil : .smooth(duration: 0.4), value: model.step)
    }

    private var callToAction: some View {
        BrandButton(model.step.callToAction, fillsWidth: true) {
            guard model.step != .companions else {
                finish()
                return
            }
            direction = .forward
            Task { await model.validate() }
        }
        .disabled(!model.canValidate)
    }

    /// D'où l'illustration arrive, par où elle repart — de la largeur de
    /// l'écran, pour venir du bord et non de sa propre boîte. En « Reduce
    /// Motion », un fondu : un dessin qui traverse l'écran est exactement le
    /// genre de déplacement que ce réglage demande d'éteindre.
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

    // MARK: - Les deux sorties

    /// La flèche du haut. Depuis la première étape il n'y a pas d'étape
    /// précédente : elle referme l'écran, ce que le modèle ne peut pas faire à
    /// sa place.
    private func goBack() {
        focus = nil
        direction = .backward
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
/// plus haute, comme une syllabe qu'on prononce, et **ses deux voisines la
/// suivent d'un cran** : c'est le mouvement d'une barre à l'autre qu'on voit,
/// pas une position (Hugo, 14/09/2026). Aux deux bouts il n'y a qu'une
/// voisine, et c'est elle seule qui monte.
///
/// Le passage d'une étape à l'autre est une **onde** : chaque barre se met à sa
/// hauteur avec un ressort, et un léger retard proportionnel à sa distance à la
/// barre verte — la vague part d'elle et se propage. En « Reduce Motion », les
/// hauteurs se posent sans mouvement.
struct TripCreationProgress: View {
    let current: Int

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @ScaledMetric(relativeTo: .caption) private var barWidth: CGFloat = 3
    @ScaledMetric(relativeTo: .caption) private var restingHeight: CGFloat = 12
    @ScaledMetric(relativeTo: .caption) private var neighbourHeight: CGFloat = 15
    @ScaledMetric(relativeTo: .caption) private var activeHeight: CGFloat = 18

    var body: some View {
        HStack(alignment: .center, spacing: 5) {
            ForEach(TripCreationStep.allCases, id: \.rawValue) { step in
                let distance = abs(step.rawValue - current)
                Capsule()
                    .fill(distance == 0 ? MemoBookColor.action : MemoBookColor.inkFaint)
                    .frame(width: barWidth, height: height(atDistance: distance))
                    .animation(
                        reduceMotion
                            ? nil
                            : .spring(duration: 0.55, bounce: 0.35).delay(Double(distance) * 0.05),
                        value: current
                    )
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Étape \(current + 1) sur \(TripCreationStep.allCases.count)")
    }

    private func height(atDistance distance: Int) -> CGFloat {
        switch distance {
        case 0: activeHeight
        case 1: neighbourHeight
        default: restingHeight
        }
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
