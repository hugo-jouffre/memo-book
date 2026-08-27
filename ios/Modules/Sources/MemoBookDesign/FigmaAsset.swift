import SwiftUI
import UIKit

/// Un visuel dessiné dans Figma : icône, logo, illustration.
///
/// R10 est claire — les assets viennent du nœud Figma, jamais d'ailleurs, et on
/// ne substitue pas un SF Symbol « équivalent » à une icône dessinée. Cette
/// énumération est donc la **liste des exports à faire**, avec pour chacun son
/// nœud d'origine et sa géométrie. Voir `docs/figma-assets.md`.
///
/// Tant qu'un fichier manque du catalogue, `FigmaImage` affiche une réserve
/// neutre à la bonne taille : la mise en page est juste, et l'absence se voit.
/// C'est volontaire — un placeholder qui ressemble à l'icône finale, personne
/// ne le remplace jamais.
public enum FigmaAsset: String, CaseIterable, Sendable {
    /// Le logotype, sur le Splash. Nœud `2699:14313`, 149.35 × 106.68.
    case companyLogo = "company-logo"

    /// Le cadenas des trois écrans de mot de passe. Nœud `2742:16770`,
    /// 30 × 38.8, posé dans une pastille de 66.
    case lock = "lock"

    /// Le crayon qui rend l'email modifiable. Nœud `2755:17745`, 44 × 44.
    case pencil = "pencil"

    /// L'icône de la carte « Assistant vocal & écrit ». Nœud `2743:17105`.
    case benefitVoice = "benefit-voice"

    /// L'icône de la carte 2 du *Welcome*. Nœud `2743:17113`.
    case benefitPhoto = "benefit-photo"

    /// L'icône de la carte « Carnet imprimé d'exception ». Nœud `2553:27484`.
    case benefitBook = "benefit-book"

    /// La flèche des cartes bénéfices — `keyboard_backspace` retournée
    /// (miroir vertical + 180°). Nœud `2552:27458`, 24.4 × 24.4.
    case cardArrow = "card-arrow"

    /// La flèche du CTA, `arrow_right_alt`, posée **à gauche** du libellé.
    /// Instance `Button` du *Welcome*, nœud `2552:27426`.
    case buttonArrow = "button-arrow"

    /// Le tracé décoratif du fond, sur *Splash*, *Welcome*, *Sign Up* et
    /// *Login*. Nœud `2788:11553`, 707.16 × 542.49, posé tourné de −90°.
    case backgroundRoute = "background-route"

    case appleLogo = "social-apple"
    case googleLogo = "social-google"
    case facebookLogo = "social-facebook"

    /// `true` quand le fichier est effectivement dans le catalogue.
    public var isExported: Bool {
        UIImage(named: rawValue, in: .module, with: nil) != nil
    }
}

/// Affiche un asset Figma, ou sa réserve tant qu'il n'est pas exporté.
///
/// La géométrie est celle de la maquette et ne dépend pas de la présence du
/// fichier : la vue occupe la même place dans les deux cas.
public struct FigmaImage: View {
    private let asset: FigmaAsset
    private let label: String?

    /// - Parameter label: ce que VoiceOver annonce. `nil` pour un élément
    ///   purement décoratif, qui est alors masqué (R7).
    public init(_ asset: FigmaAsset, label: String? = nil) {
        self.asset = asset
        self.label = label
    }

    public var body: some View {
        content
            .accessibilityLabel(label ?? "")
            .accessibilityHidden(label == nil)
    }

    @ViewBuilder
    private var content: some View {
        if let image = UIImage(named: asset.rawValue, in: .module, with: nil) {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
        } else {
            // Une réserve, pas un remplaçant : elle ne prétend rien dessiner.
            RoundedRectangle(cornerRadius: rem(0.25))
                .fill(MemoBookColor.inkSecondary.opacity(0.15))
        }
    }
}
