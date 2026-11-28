import MemoBookCore
import MemoBookDesign
import SwiftUI

/// **Le petit livre qui dépasse du bord** — T297.
///
/// « Un petit livre dépasse du bord, en haut à droite, et sautille quand
/// l'aperçu se met à jour — la porte d'entrée du PDF, à la manière des stories
/// dans les messages d'Instagram » (Hugo, 28/11/2026).
///
/// **Il remplace la capsule « Ton carnet prend forme »** (choix de Hugo, le
/// même jour). Elle avait déjà été déplacée sous l'imprimante en octobre pour
/// cette raison : deux portes vers le même écran, à vingt points l'une de
/// l'autre, se lisent comme une seule. L'imprimante de l'en-tête reste — elle
/// est la commande du haut, alignée avec les réglages.
///
/// **Et il reste là.** La capsule allait et venait au défilement parce qu'elle
/// était large et bavarde ; un livre de soixante points qui ne montre que son
/// tiers n'a pas besoin de disparaître pour se faire oublier. Ce qui bougeait
/// avec elle — les seuils de remontée — ne sert plus qu'à la barre d'envoi
/// (T289), et porte désormais son nom.
///
/// **Deux âges**, et c'est le serveur qui tranche (``ChatBookPreview``) :
///
/// 1. **nu** — un plat crème, et l'étiquette qui décompte les étapes
///    illustrées qui le séparent de sa couverture ;
/// 2. **couvert** — la photo du voyage remplit le plat, l'étiquette s'efface,
///    et le livre **s'épaissit** : sa tranche gagne des feuillets à mesure que
///    les pages se composent.
struct ChatBookDoor: View {
    let preview: ChatBookPreview
    let onOpen: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Le livre suit la taille du texte : à 200 %, une porte de la taille d'un
    /// timbre ne se touche plus.
    @ScaledMetric(relativeTo: .subheadline) private var plateWidth: CGFloat = 60

    private var plateHeight: CGFloat { plateWidth * 1.41 }

    /// **Ce qui dépasse, et ce qui reste visible.** Le livre sort du bord
    /// droit du quart de son plat : assez pour qu'on voie qu'il continue,
    /// assez peu pour que **la part visible reste une cible honnête** — 45
    /// points de plat, plus la tranche, au-dessus des 44 de la marque. Au
    /// tiers, elle tombait à 35 et le livre se lisait comme un rectangle
    /// coupé.
    private var hidden: CGFloat { plateWidth / 4 }

    /// Les feuillets de la tranche : deux au début, cinq quand le carnet est
    /// épais. Le livre **grossit avec ce qui est composé**, pas avec ce qui
    /// est raconté — c'est le PDF qu'il ouvre.
    private var leaves: Int { min(5, 2 + preview.pageCount / 16) }

    var body: some View {
        Button(action: onOpen) {
            book
        }
        .buttonStyle(CardPressStyle())
        .accessibilityLabel(label)
        .accessibilityHint(ChatCopy.Voice.openPreview)
    }

    private var label: String {
        let state = preview.coverUrl == nil ? ChatCopy.BookDoor.bareBook : ChatCopy.previewTitle
        let counts = ChatCopy.previewSubtitle(memories: preview.memoryCount, pages: preview.pageCount)
        return "\(state). \(counts)"
    }

    /// **Les feuillets derrière le plat, et le plat devant** : c'est ce qui en
    /// fait un livre et non une carte. Le sautillement porte sur les deux — un
    /// livre dont seule la couverture bouge se déchirerait.
    ///
    /// Dessinés **derrière** et décalés vers le bas à gauche, et non en
    /// tranche sur le côté : à soixante points, trois filets d'un point et
    /// demi ne se voyaient pas, et le livre se lisait comme un rectangle
    /// blanc.
    private var book: some View {
        ZStack(alignment: .topTrailing) {
            ForEach(1..<leaves, id: \.self) { leaf in
                RoundedRectangle(cornerRadius: 4)
                    .fill(MemoBookColor.surface)
                    .overlay {
                        RoundedRectangle(cornerRadius: 4)
                            .strokeBorder(MemoBookColor.hairline, lineWidth: 0.5)
                    }
                    .frame(width: plateWidth, height: plateHeight)
                    .offset(x: -Double(leaf) * 2.5, y: Double(leaf) * 2.5)
            }
            plate
        }
        .brandShadow(.raised)
        .modifier(BookJiggle(trigger: preview.pageCount, isStill: reduceMotion))
        .offset(x: hidden)
    }

    private var plate: some View {
        ZStack {
            MemoBookColor.surface
            if let url = preview.coverUrl {
                RemoteImage(url: url) { Color.clear }
                    .scaledToFill()
            } else {
                // Le plat nu porte le signe de la marque, en très pâle : un
                // rectangle crème seul se lit comme une image qui n'a pas
                // chargé.
                BrandMarkDrawing(progress: 1, color: MemoBookColor.outline)
                    .frame(width: plateWidth * 0.42)
                    .opacity(0.6)
            }
        }
        .frame(width: plateWidth, height: plateHeight)
        .clipShape(.rect(cornerRadius: 4))
        .overlay {
            RoundedRectangle(cornerRadius: 4)
                .strokeBorder(MemoBookColor.outline, lineWidth: 1)
        }
    }
}

/// **Le sautillement** (T297) : le livre tressaute quand une page de plus est
/// composée, et pas une fois de plus.
///
/// Déclenché par le nombre de pages et non par chaque réponse du serveur : le
/// fil se relit toutes les trois secondes, et un livre qui sautille à chaque
/// sondage deviendrait un clignotant. En Reduce Motion, il ne bouge pas du
/// tout — c'est un signe, pas une information : les chiffres sont dans
/// l'aperçu.
private struct BookJiggle: ViewModifier {
    let trigger: Int
    let isStill: Bool

    func body(content: Content) -> some View {
        if isStill {
            content
        } else {
            content.keyframeAnimator(initialValue: Jiggle(), trigger: trigger) { view, jiggle in
                view
                    .rotationEffect(.degrees(jiggle.angle), anchor: .bottom)
                    .offset(y: jiggle.lift)
            } keyframes: { _ in
                KeyframeTrack(\Jiggle.angle) {
                    CubicKeyframe(-6, duration: 0.12)
                    CubicKeyframe(4, duration: 0.12)
                    CubicKeyframe(-2, duration: 0.1)
                    CubicKeyframe(0, duration: 0.14)
                }
                KeyframeTrack(\Jiggle.lift) {
                    CubicKeyframe(-5, duration: 0.14)
                    CubicKeyframe(0, duration: 0.24)
                }
            }
        }
    }

    private struct Jiggle {
        var angle: Double = 0
        var lift: CGFloat = 0
    }
}

/// L'étiquette posée sous le livre, tant qu'il n'a pas de couverture.
///
/// Elle **décompte** — « après 2 étapes avec photos » —, et elle disparaît
/// d'elle-même quand la photo arrive : c'est ce qui en fait une étiquette et
/// non une consigne. Le serveur décide du nombre (``ChatBookPreview``) ;
/// l'app l'écrit.
struct ChatBookDoorCaption: View {
    let steps: Int

    var body: some View {
        Text(ChatCopy.BookDoor.coverAfter(steps: steps))
            .font(MemoBookFont.caption)
            .foregroundStyle(MemoBookColor.inkMuted)
            .multilineTextAlignment(.trailing)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: 150, alignment: .trailing)
            .padding(.horizontal, MemoBookSpacing.xs)
            .padding(.vertical, 5)
            // **Opaque, et cernée** : elle flotte au-dessus du fil comme le
            // livre, et un verre translucide posé sur une fiche se lisait
            // comme une tache sur elle, pas comme une étiquette.
            .background(MemoBookColor.surface, in: .rect(cornerRadius: 10))
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(MemoBookColor.hairline, lineWidth: 1)
            }
            .brandShadow(.raised)
            .accessibilityHidden(true)
    }
}
