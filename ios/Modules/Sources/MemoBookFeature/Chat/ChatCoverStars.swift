import MemoBookCore
import MemoBookDesign
import SwiftUI

/// **Les deux étoiles d'une photo** (T270, Hugo, 05/11/2026) : la verte dit
/// qu'elle est la photo principale de son **étape**, la lime qu'elle est celle
/// du **voyage**. Une photo peut porter les deux, et elles se posent alors
/// côte à côte.
///
/// Rien quand la photo n'est ni l'une ni l'autre — le cas de presque toutes :
/// une pastille vide sur chaque vignette ferait une grille de décorations.
///
/// ⚠️ **Le lime, ici, n'est pas l'abonnement.** La règle de la marque veut que
/// le lime ne dise que l'abonnement (T7, `ios/CLAUDE.md` § Design system) ;
/// T270 le demande nommément pour cette étoile — « étoile lime à contour
/// vert ». C'est la première exception, et elle tient à ce que l'étoile n'est
/// pas un bouton : elle ne propose rien, elle marque.
struct ChatCoverStars: View {
    let photo: PhotoAttachment

    /// L'étoile suit le corps du texte : sur une vignette de 76 pt, elle doit
    /// rester lisible sans manger la photo.
    @ScaledMetric(relativeTo: .caption) private var side: CGFloat = 20

    var body: some View {
        if photo.isStepCover || photo.isTripCover {
            HStack(spacing: 3) {
                // L'étape : une pastille verte, l'étoile en crème dedans.
                if photo.isStepCover {
                    badge(disc: MemoBookColor.action, star: MemoBookColor.paper, ring: nil)
                }
                // Le voyage : la pastille lime, cerclée de vert, l'étoile à
                // l'encre — « étoile lime à contour vert » (T270).
                if photo.isTripCover {
                    badge(disc: MemoBookColor.accent, star: MemoBookColor.ink, ring: MemoBookColor.action)
                }
            }
            .accessibilityHidden(true)
        }
    }

    /// ⚠️ **Une pastille, et non l'étoile seule.** `Star.svg` est une étoile
    /// **de contour** : posée telle quelle sur une photo, son trait de 1 pt se
    /// perd dans n'importe quel feuillage. La couleur doit donc porter sur un
    /// aplat — c'est elle qui dit laquelle des deux étoiles on regarde, et
    /// elle doit se lire d'un coup d'œil sur une vignette de 76 pt.
    private func badge(disc: Color, star: Color, ring: Color?) -> some View {
        ZStack {
            Circle()
                .fill(disc)
                .overlay { if let ring { Circle().strokeBorder(ring, lineWidth: 1.5) } }
                .brandShadow(.soft)

            Image(brand: "IconStar")
                .resizable()
                .renderingMode(.template)
                .scaledToFit()
                .foregroundStyle(star)
                .padding(side * 0.18)
        }
        .frame(width: side, height: side)
    }

    /// Ce que VoiceOver dit d'une bulle de photos, en plus de son nombre.
    ///
    /// Sur la bulle entière et non par photo : la bulle est **un** élément
    /// pour VoiceOver (`children: .ignore`), et annoncer quatre étoiles l'une
    /// après l'autre dans une grille de quatre vignettes ne se suit pas.
    static func spokenValue(of photos: [PhotoAttachment]) -> String {
        let step = photos.contains(where: \.isStepCover)
        let trip = photos.contains(where: \.isTripCover)
        return switch (step, trip) {
        case (true, true): ChatCopy.Menu.spokenBothCovers
        case (true, false): ChatCopy.Menu.spokenStepCover
        case (false, true): ChatCopy.Menu.spokenTripCover
        case (false, false): ""
        }
    }
}
