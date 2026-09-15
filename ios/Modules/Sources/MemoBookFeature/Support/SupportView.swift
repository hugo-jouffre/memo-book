import MemoBookCore
import MemoBookDesign
import SwiftUI

/// Le support : qui nous sommes, ce qu'on nous demande le plus souvent, et
/// comment nous écrire.
///
/// **On y arrive de partout où l'app écrit « Besoin d'aide ? »** — le bas de
/// l'accueil, le bas du profil, la barre du paywall, la dernière ligne des
/// paramètres d'un voyage et celle de la cagnotte. C'est la raison d'être de
/// l'écran : cinq liens qui ne menaient nulle part mènent maintenant au même
/// endroit.
///
/// L'écran ne fait que **lister** : chaque question ouvre une feuille, et c'est
/// la feuille qui porte la réponse, le vote et le passage au formulaire. Une
/// réponse dépliée dans la liste aurait fait sauter tout ce qui est en dessous à
/// chaque touche.
///
/// La photo et les deux paragraphes du haut ne sont pas de la décoration : la
/// page de support est l'endroit où quelqu'un arrive **contrarié**, et deux
/// visages avant une liste de liens changent le ton de ce qui suit.
public struct SupportView: View {
    @State private var model: SupportModel

    /// La question dont la feuille est ouverte, ou le formulaire seul.
    @State private var sheet: SupportSheetRoute?

    public init(model: SupportModel) {
        _model = State(initialValue: model)
    }

    @Environment(\.travellerFirstName) private var firstName

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: MemoBookSpacing.l) {
                // La photo se rapproche du titre : un écart de section entre
                // les deux les faisait lire comme deux blocs, alors que le
                // bonjour **suit** le titre (Hugo, 15/09/2026).
                VStack(alignment: .leading, spacing: MemoBookSpacing.s) {
                    BrandScreenHeader(title: SupportCopy.title)
                    greeting
                }

                topics
                contact
                legal
            }
            .padding(.horizontal, MemoBookSpacing.screenMargin)
            .padding(.top, MemoBookSpacing.xs)
            .padding(.bottom, MemoBookSpacing.l)
        }
        .scrollIndicators(.hidden)
        .background(MemoBookColor.background.ignoresSafeArea())
        .brandHiddenNavigationBar()
        // Le crème de la marque ne se retourne pas en sombre — voir
        // `MemoBookColor`.
        .environment(\.colorScheme, .light)
        .brandSheet(item: $sheet) { route in
            SupportSheet(model: model, route: route)
        }
    }

    // MARK: - Les deux visages, et le bonjour

    private var greeting: some View {
        VStack(spacing: MemoBookSpacing.s) {
            Image(brand: "PhotoFounders")
                .resizable()
                .scaledToFill()
                .frame(width: Self.portraitSide, height: Self.portraitSide)
                .clipShape(.circle)
                .overlay { Circle().strokeBorder(MemoBookColor.surface, lineWidth: 2) }
                // Les deux visages ne disent rien que la signature ne dise : la
                // photo est décorative, et VoiceOver passe au texte.
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: MemoBookSpacing.xs) {
                Text(SupportCopy.hello(firstName))

                ForEach(SupportCopy.intro, id: \.self) { paragraph in
                    Text(paragraph)
                }
            }
            // Le corps de texte, et non l'accroche de 14 : ce sont deux
            // paragraphes qu'on lit, pas une légende (Hugo, 15/09/2026).
            .font(MemoBookFont.body)
            .foregroundStyle(MemoBookColor.ink)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity)
    }

    /// La photo des fondateurs, ronde. 112 sur la maquette — 7 rem.
    private static let portraitSide: CGFloat = 112

    // MARK: - Les sujets courants

    /// Les neuf paquets de la foire aux questions, chacun dans son groupe.
    ///
    /// Un groupe par thème et non une seule liste de quarante-cinq lignes : on
    /// ne cherche pas une réponse en lisant tout, on cherche d'abord le rayon.
    private var topics: some View {
        VStack(alignment: .leading, spacing: MemoBookSpacing.m) {
            SupportSectionTitle(SupportCopy.topicsSection)

            ForEach(model.topics) { category in
                VStack(alignment: .leading, spacing: MemoBookSpacing.xs) {
                    Text(category.title)
                        .font(MemoBookFont.label)
                        .foregroundStyle(MemoBookColor.ink)
                        .accessibilityAddTraits(.isHeader)

                    BrandRowGroup {
                        for entry in category.entries {
                            BrandRow(entry.question) { sheet = .answer(entry) }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Nous contacter

    /// Les deux questions qui mènent à nous écrire, et la ligne qui y mène
    /// directement.
    ///
    /// La ligne directe est en dernier, et c'est l'ordre qui compte : on propose
    /// d'abord les deux réponses qui évitent d'écrire, on ouvre le formulaire
    /// ensuite.
    private var contact: some View {
        VStack(alignment: .leading, spacing: MemoBookSpacing.snug) {
            SupportSectionTitle(SupportCopy.contactSection)

            BrandRowGroup {
                for entry in model.contact.entries {
                    BrandRow(entry.question) { sheet = .answer(entry) }
                }
                BrandRow(SupportCopy.writeToUs) { sheet = .contact }
            }
        }
    }

    // MARK: - Le pied de page

    private var legal: some View {
        Text(SupportCopy.legal(version: Self.appVersion))
            .font(MemoBookFont.caption)
            .foregroundStyle(MemoBookColor.disabledOutline)
            .frame(maxWidth: .infinity, alignment: .center)
    }

    /// La version affichée en pied de page.
    ///
    /// Lue dans le bundle et non écrite dans la copie : une version en dur reste
    /// celle du jour où on l'a tapée, et ce pied de page sert précisément à
    /// savoir quelle version quelqu'un a sous les yeux quand il nous écrit.
    private static var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }
}

/// Le chapeau d'une des deux sections de l'écran.
private struct SupportSectionTitle: View {
    let title: String

    init(_ title: String) { self.title = title }

    var body: some View {
        Text(title)
            .font(MemoBookFont.sectionOverline)
            .foregroundStyle(MemoBookColor.inkMuted)
            // La maquette écrit le titre en minuscules et le dessine en
            // capitales : c'est une casse d'affichage. VoiceOver lit donc
            // « sujets courants » au lieu de l'épeler.
            .textCase(.uppercase)
            .accessibilityAddTraits(.isHeader)
    }
}

/// Ce que la feuille de support peut porter.
///
/// Une seule feuille pour les deux, et non deux feuilles empilées : le design
/// system l'interdit, et « J'ai encore une question » doit pouvoir mener au
/// formulaire depuis une réponse.
enum SupportSheetRoute: Identifiable, Hashable {
    case answer(FaqEntry)
    case contact

    var id: String {
        switch self {
        case .answer(let entry): entry.id
        case .contact: "faq.contact"
        }
    }
}

#Preview("Support et retours") {
    NavigationStack {
        SupportView(model: SupportModel())
            .environment(\.travellerFirstName, "Margaux")
    }
}

#Preview("Support et retours — AX3") {
    NavigationStack {
        SupportView(model: SupportModel())
            .environment(\.travellerFirstName, "Margaux")
            .environment(\.dynamicTypeSize, .accessibility3)
    }
}
