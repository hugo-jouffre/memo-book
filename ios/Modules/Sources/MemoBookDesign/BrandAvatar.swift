import SwiftUI

/// Le portrait de quelqu'un : sa photo, ou ses initiales tant qu'il n'y en a
/// pas.
///
/// **Les initiales ne sont pas un pis-aller décoratif.** Une invitation partie
/// par lien n'a pas de compte derrière elle, donc pas de photo — et c'est l'état
/// le plus fréquent de la liste des co-voyageurs le jour où on l'ouvre. Le rond
/// gris de remplacement dit « cette personne existe, elle n'a pas encore posé sa
/// tête » ; un rond vide dirait « il manque quelque chose ».
public struct BrandAvatar: View {
    private let url: URL?
    private let initials: String
    private let side: CGFloat

    /// - Parameter side: le diamètre, **fixe** : un portrait n'est pas du texte,
    ///   et une liste dont les ronds grandissent avec le corps de texte se
    ///   transforme en colonne de pastilles.
    public init(url: URL?, initials: String, side: CGFloat = MemoBookSpacing.avatarSide) {
        self.url = url
        self.initials = initials
        self.side = side
    }

    public var body: some View {
        AsyncImage(url: url) { phase in
            if let image = phase.image {
                image.resizable().scaledToFill()
            } else {
                placeholder
            }
        }
        .frame(width: side, height: side)
        .clipShape(.circle)
        .overlay { Circle().strokeBorder(MemoBookColor.hairline, lineWidth: 1) }
        // Le nom est dit par la ligne qui porte ce rond : l'annoncer deux fois
        // ferait lire « Tom John, Tom John » à VoiceOver.
        .accessibilityHidden(true)
    }

    private var placeholder: some View {
        MemoBookColor.outline.opacity(0.35)
            .overlay {
                Text(initials)
                    .font(MemoBookFont.overline)
                    .foregroundStyle(MemoBookColor.action)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                    .padding(2)
            }
    }
}

#Preview("Portraits") {
    HStack(spacing: MemoBookSpacing.s) {
        BrandAvatar(url: nil, initials: "MD")
        BrandAvatar(url: nil, initials: "TJ", side: 42)
        BrandAvatar(url: nil, initials: "C", side: 64)
    }
    .padding(MemoBookSpacing.screenMargin)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(MemoBookColor.surface)
    .environment(\.colorScheme, .light)
}
