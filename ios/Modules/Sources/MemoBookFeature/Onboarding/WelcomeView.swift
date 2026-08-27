import MemoBookDesign
import SwiftUI

/// La promesse produit en trois bénéfices, puis *Sign Up*.
///
/// Écran **statique** : ce n'est pas un carrousel, et il n'a qu'une sortie.
/// Nœud Figma `2552:27407`.
struct WelcomeView: View {
    let onDiscover: () -> Void

    var body: some View {
        ZStack {
            MemoBookColor.background.ignoresSafeArea()
            BackgroundRoute()

            ScrollView {
                VStack(spacing: MemoBookSpacing.m) {
                    Tagline(WelcomeCopy.tagline)

                    Text(WelcomeCopy.title)
                        .font(MemoBookFont.screenTitle)
                        .foregroundStyle(MemoBookColor.ink)
                        .tracking(MemoBookTracking.tight)
                        .multilineTextAlignment(.center)
                        // 20.75 rem : c'est cette largeur qui fixe les retours
                        // à la ligne du titre. Elle ne dépasse jamais le
                        // contenu disponible sur un petit écran.
                        .frame(maxWidth: rem(20.75))

                    Text(WelcomeCopy.subtitle)
                        .font(MemoBookFont.body)
                        .foregroundStyle(MemoBookColor.inkSecondary)
                        .tracking(MemoBookTracking.body)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    ForEach(WelcomeCopy.benefits) { benefit in
                        BenefitCard(benefit: benefit)
                    }

                    MemoBookButton(
                        WelcomeCopy.callToAction,
                        leading: .asset(.buttonArrow),
                        action: onDiscover
                    )
                }
                .padding(.horizontal, MemoBookSpacing.screenMargin)
                .padding(.vertical, MemoBookSpacing.m)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
    }
}

/// La copie du *Welcome*, recopiée du nœud Figma **au caractère près** (R8),
/// apostrophes typographiques comprises.
///
/// ⚠️ Deux remontées pour Clara, signalées et non corrigées :
///
///   1. **Les cartes 1 et 2 vouvoient** (« Parlez simplement », « Vos photos
///      concernées sont ajoutées ») alors que l'app tutoie partout ailleurs
///      (R9). C'est le point T8, toujours ouvert.
///   2. **« Vos photos misent en page »** — « misent » pour « mises ». Une
///      faute ne se corrige pas sans retour de Clara (R8), elle se signale.
///
/// Le détail fonctionnel Notion nomme la carte 2 « Photos et stickers
/// instantanés », ce que Figma disait dans une version précédente. La maquette
/// courante dit autre chose : c'est elle qui fait foi (R3), et l'écart est
/// remonté.
enum WelcomeCopy {
    static let tagline = "Bienvenue voyageur & voyageuse"
    static let title = "Chaque instant mérite d’être mémorisé"
    static let subtitle =
        "Garde tes moments de voyage tels qu’ils se vivent. Tu les racontes, MemoBook les met en page."
    static let callToAction = "Découvre MemoBook"

    static let benefits: [Benefit] = [
        Benefit(
            number: 1,
            icon: .benefitVoice,
            title: "Assistant vocal & écrit",
            description: "Parlez simplement durant la journée, Memo retranscrit vos anecdotes",
            tilt: -1
        ),
        Benefit(
            number: 2,
            icon: .benefitPhoto,
            title: "Vos photos misent en page",
            description:
                "Vos photos concernées sont ajoutées rapidement depuis la galerie ou Instagram",
            tilt: 1
        ),
        Benefit(
            number: 3,
            icon: .benefitBook,
            title: "Carnet imprimé d’exception",
            description:
                "Mise en page automatique élégante et livraison chez vous de votre véritable carnet papier",
            tilt: -1
        ),
    ]
}

struct Benefit: Identifiable {
    let number: Int
    let icon: FigmaAsset
    let title: String
    let description: String
    /// L'inclinaison de la carte, en degrés. Elle est **intentionnelle** et se
    /// garde au degré près (décision D4) : −1°, +1°, −1°.
    let tilt: Double

    var id: Int { number }
}

#Preview("Welcome") {
    WelcomeView(onDiscover: {})
}

#Preview("Welcome — AX3") {
    WelcomeView(onDiscover: {})
        .environment(\.dynamicTypeSize, .accessibility3)
}
