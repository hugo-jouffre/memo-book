import SwiftUI

/// La vignette d'un sujet : un pictogramme de marque dans un disque du bleu
/// `outline`, le seul aplat qui dise « information » sans tirer vers l'action.
///
/// Elle ouvre les écrans et les feuilles qui parlent d'**une** chose avant
/// qu'on la lise — le cadenas de « Mot de passe oublié », sur la feuille comme
/// sur la page du nouveau mot de passe. Le glyphe se dessine à `contentIcon`
/// (32 pt), comme toute icône de contenu de la marque ; le disque lui laisse un
/// anneau de 12 pt.
public struct BrandIconBadge: View {
    private let name: String

    public init(_ name: String) {
        self.name = name
    }

    public var body: some View {
        Image(brand: name)
            .resizable()
            .renderingMode(.template)
            .scaledToFit()
            .frame(width: MemoBookSpacing.contentIcon, height: MemoBookSpacing.contentIcon)
            .foregroundStyle(MemoBookColor.ink)
            .padding(MemoBookSpacing.snug)
            .background(MemoBookColor.outline, in: .circle)
            .accessibilityHidden(true)
    }
}
