import MemoBookDesign
import SwiftUI

/// Premier écran de l'app : ce que MemoBook fait, en trois étapes, et une seule
/// action pour entrer.
///
/// **Adaptation aux tailles d'écran.** La maquette est dessinée pour un cadre de
/// 390 × 844 (iPhone 15/16). Deux choses la rendent fragile telle quelle : sur
/// un iPhone SE (375 × 667) le contenu dépasse de près de 80 pt, et en Dynamic
/// Type accessible il double de hauteur. D'où deux écarts assumés :
///
/// - le contenu défile, et le bouton principal est ancré au bas de l'écran
///   plutôt que posé en fin de liste. Sur un écran de 844 pt il tombe au même
///   endroit que dans la maquette ; sur un SE il reste atteignable sans avoir à
///   deviner qu'il faut faire défiler ;
/// - les largeurs suivent l'écran mais **plafonnent** à celles de la maquette.
///   Laisser le texte s'étaler sur un 6,9″ ferait passer le titre de trois
///   lignes à deux : la colonne se centre au lieu de s'élargir.
///
/// En Dynamic Type accessible, les cartes passent d'elles-mêmes en pile
/// verticale (voir `WelcomeStepCard`).
public struct WelcomeView: View {
    /// Largeur du cadre de la maquette. Le contenu ne s'étire pas au-delà : sur
    /// un 6,9″ il se centre, ce qui garde les retours à la ligne dessinés
    /// plutôt que d'étaler le texte sur toute la largeur.
    private static let contentWidth: CGFloat = 390

    /// Largeur de la colonne du titre dans la maquette. La retenir évite que le
    /// titre passe de trois à deux lignes sur les grands écrans.
    private static let titleWidth: CGFloat = 332

    private let onContinue: () -> Void

    public init(onContinue: @escaping () -> Void) {
        self.onContinue = onContinue
    }

    public var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                tagline
                title
                subtitle
                steps
            }
            .padding(.top, MemoBookSpacing.m)
            .padding(.bottom, MemoBookSpacing.xs)
            .frame(maxWidth: Self.contentWidth)
            .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
        .overlay(alignment: .top) { statusBarScrim }
        .safeAreaInset(edge: .bottom, spacing: 0) { callToAction }
        .background(BrandBackdrop())
        // La palette de la marque est un papier crème : elle ne se retourne pas
        // en sombre. Voir le commentaire de `MemoBookColor`.
        .environment(\.colorScheme, .light)
    }

    /// Il n'y a pas de barre de navigation pour protéger l'heure et la batterie :
    /// sans cela le titre leur passe dessus dès qu'on fait défiler.
    private var statusBarScrim: some View {
        LinearGradient(
            colors: [MemoBookColor.background, MemoBookColor.background.opacity(0)],
            startPoint: .top,
            endPoint: .bottom
        )
        .frame(height: MemoBookSpacing.s)
        .ignoresSafeArea(edges: .top)
        .allowsHitTesting(false)
    }

    // MARK: - En-tête

    private var taglineShape: RoundedRectangle {
        .rect(cornerRadius: MemoBookSpacing.largeCornerRadius)
    }

    private var tagline: some View {
        Text("Bienvenue voyageur & voyageuse")
            .font(MemoBookFont.tagline)
            .tracking(MemoBookFont.tracking(14))
            .foregroundStyle(MemoBookColor.action)
            .multilineTextAlignment(.center)
            .padding(.horizontal, MemoBookSpacing.xs)
            .padding(.vertical, 2)
            // Rayon fixe plutôt qu'une `Capsule` : sur une seule ligne les deux
            // se confondent, mais quand le Dynamic Type fait passer l'accroche
            // à trois lignes, la capsule devient une ellipse. C'est le rayon de
            // 20 de la maquette, que SwiftUI ramène tout seul à un demi-cercle
            // tant que la pastille est basse.
            .background(MemoBookColor.surface, in: taglineShape)
            .overlay(taglineShape.strokeBorder(MemoBookColor.action, lineWidth: 1))
            .padding(.horizontal, MemoBookSpacing.screenMargin)
    }

    private var title: some View {
        Text("Chaque instant mérite d’être mémorisé")
            .font(MemoBookFont.h1)
            .tracking(-0.41)
            .foregroundStyle(MemoBookColor.ink)
            .multilineTextAlignment(.center)
            // L'interligne serré de la maquette (35 pt pour 32 pt de corps) est
            // porté par les métriques de la police elle-même : `lineSpacing`
            // ne sait qu'ajouter de l'air, jamais en retirer. Voir
            // `ios/Tools/make-brand-fonts.py`.
            .frame(maxWidth: Self.titleWidth)
            .padding(.horizontal, MemoBookSpacing.screenMargin)
    }

    private var subtitle: some View {
        VStack(alignment: .leading, spacing: MemoBookSpacing.xs) {
            Text("Garde tes moments de voyage\ntels qu’ils se vivent.")
            Text("Tu les racontes, MemoBook les met en page.")
        }
        .font(MemoBookFont.body)
        .tracking(MemoBookFont.tracking(16))
        .foregroundStyle(MemoBookColor.inkSecondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, MemoBookSpacing.screenMargin)
    }

    // MARK: - Les trois étapes

    private var steps: some View {
        VStack(spacing: 22) {
            WelcomeStepCard(
                number: 1,
                icon: .mic,
                title: "Assistant vocal & écrit",
                detail: "Parlez simplement durant la journée, Memo retranscrit vos anecdotes",
                tilt: -1
            )
            WelcomeStepCard(
                number: 2,
                icon: .photo,
                title: "Vos photos mises en page",
                detail: "Vos photos concernées sont ajoutées rapidement depuis la galerie ou Instagram",
                tilt: 1
            )
            WelcomeStepCard(
                number: 3,
                icon: .book,
                title: "Carnet imprimé d’exception",
                detail:
                    "Mise en page automatique élégante et livraison chez vous de votre véritable carnet papier",
                tilt: -1
            )
        }
        // Même marge latérale que le reste de l'écran : les cartes s'alignent
        // sur la colonne de texte au lieu de la déborder.
        .padding(.horizontal, MemoBookSpacing.screenMargin)
        // Les pastilles numérotées débordent en haut de la première carte.
        .padding(.top, 14)
    }

    // MARK: - Action

    private var callToAction: some View {
        BrandButton(
            "Découvre MemoBook",
            icon: Image(brand: "IconArrowRight"),
            fillsWidth: true,
            action: onContinue
        )
        .padding(.horizontal, MemoBookSpacing.screenMargin)
        .frame(maxWidth: Self.contentWidth)
        .frame(maxWidth: .infinity)
        .padding(.top, MemoBookSpacing.s)
        .padding(.bottom, MemoBookSpacing.xs)
        // Le contenu défile sous le bouton : ce dégradé le décolle du texte
        // sans poser un bandeau opaque sur le motif de fond.
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
}

#Preview("Accueil") {
    WelcomeView {}
}

#Preview("Accueil — Dynamic Type XXXL") {
    WelcomeView {}
        .environment(\.dynamicTypeSize, .accessibility3)
}
