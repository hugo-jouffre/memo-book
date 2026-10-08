import MemoBookCore
import MemoBookDesign
import SwiftUI

// Les blocs que la composition et l'aperçu partagent.
//
// Ils sont ici et non dans chaque écran pour une raison de dessin et non de
// rangement : les deux écrans doivent poser **exactement** les mêmes boutons au
// même endroit, sinon le passage de l'un à l'autre les fait sauter. Un composant
// commun est la seule façon d'en être sûr.

/// Les deux appels à l'action du carnet : le personnaliser, ou le commander.
///
/// Le secondaire au-dessus du primaire, comme la maquette : « Personnaliser »
/// est ce qu'on fait plusieurs fois, « Commander » est ce qu'on fait une fois.
/// Le geste répété se pose donc sous le pouce en premier.
struct BookActionsBlock: View {
    /// Le carnet est composé et peut partir à l'impression.
    ///
    /// **Il ne dit plus « le PDF est rasterisé ».** Les deux boutons étaient
    /// gris tant que `renderer.sheetCount` valait zéro — c'est-à-dire tant que
    /// l'app n'avait pas fini de dessiner les pages, et *pour toujours* quand
    /// le PDF ne se chargeait pas. On ne pouvait alors ni commander un carnet
    /// que le serveur déclarait prêt, ni même aller changer son style, ce qui
    /// ne demande rien du tout.
    let isComposed: Bool
    let onCustomise: () -> Void
    let onOrder: () -> Void

    var body: some View {
        VStack(spacing: MemoBookSpacing.s) {
            // **Toujours actif.** Personnaliser son carnet ne demande ni rendu,
            // ni PDF, ni réseau : c'est un écran de réglages, et c'est souvent
            // en attendant la composition qu'on a envie d'y aller.
            BrandButton(
                BookCopy.Preview.customise,
                style: .secondary,
                fillsWidth: true,
                action: onCustomise
            )

            // ⚠️ Il y avait ici « Configurer mes couvertures », en lien sous le
            // bouton de personnalisation. Retiré (Hugo, 19/09/2026) : les
            // couvertures se choisissent **sur la page**, en touchant le voile
            // de la première ou de la dernière — voir `CoverInvitation` —, et
            // ce lien disait une seconde fois ce que la page proposait déjà.

            // Commander demande, lui, un carnet composé : on ne fait pas
            // imprimer ce qui n'existe pas encore.
            BrandButton(
                BookCopy.Preview.order,
                icon: Image(brand: "IconDeliver"),
                style: .primary,
                fillsWidth: true,
                action: onOrder
            )
            .disabled(!isComposed)

            // **La porte de service**, et seulement quand le bouton du dessus
            // est fermé : elle ouvre quand même le tunnel de commande.
            //
            // Elle est **dans la version livrée** et non sous `#if DEBUG`
            // (Hugo, 16/09/2026) : le tunnel se teste sur un TestFlight, qui
            // est un build Release — une porte compilée en debug seulement ne
            // s'ouvre nulle part où l'on en a besoin. Son dessin la range à sa
            // place : un lien souligné, sans fond ni contour. On ne peut pas
            // la confondre avec l'appel à l'action juste au-dessus.
            //
            // **À l'encre, et un cran plus grande** (Hugo, 06/10/2026, T219) :
            // en beige au corps d'une légende, elle était presque invisible
            // pendant la composition — c'est-à-dire justement quand elle sert.
            // 14 au lieu de 12, la graisse courante.
            if !isComposed {
                Button(action: onOrder) {
                    Text(BookCopy.Preview.orderAnyway)
                        .font(MemoBookFont.taglineRegular)
                        .foregroundStyle(MemoBookColor.ink)
                        .underline()
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        // Le dessin fait une ligne, la cible 2.75 rem : R7.
                        .frame(maxWidth: .infinity, minHeight: MemoBookSpacing.minimumTapTarget)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
        }
        .animation(.snappy(duration: 0.25), value: isComposed)
    }
}

/// Une feuille du carnet : la page du PDF, ou **le plat choisi** quand c'est
/// la première ou la dernière et que les couvertures sont réglées.
///
/// **Les couvertures se voient dans l'aperçu** (Hugo, 06/10/2026, T223) : le
/// PDF n'imprime pas encore les plats choisis — la génération ignore les
/// couvertures, et c'est assumé tant que cette partie n'est pas écrite —, et
/// l'aperçu montrait donc une couverture par défaut juste après qu'on avait
/// réglé la sienne. Le plat est celui des écrans des couvertures
/// (``CoverPlate``), au même rapport A5 que la page : c'est la même image qui
/// sortira du gabarit le jour où il les rendra.
///
/// Elle sert l'aperçu, le plein écran et sa bande de miniatures : une même
/// feuille doit y montrer la même chose.
struct BookSheetFace: View {
    let model: BookPreviewModel
    let index: Int

    var body: some View {
        if let face = model.coverFace(at: index), let covers = model.covers {
            BookCoverSheet(covers: covers, face: face)
        } else {
            BookSheetImage(renderer: model.renderer, index: index)
        }
    }
}

/// Un plat de couverture qui occupe la place d'une page, centré.
struct BookCoverSheet: View {
    let covers: BookCovers
    let face: CoverFace

    var body: some View {
        GeometryReader { proxy in
            // La plus grande largeur qui tienne dans la boîte : le plat garde
            // son rapport A5, comme la page qu'il remplace.
            let width = min(proxy.size.width, proxy.size.height * CoverPlate.ratio)
            let cover = covers[face]

            CoverPlate(
                cover: cover,
                style: covers.style(id: cover.styleId),
                photo: covers.photo(id: cover.photoId),
                face: face,
                stats: face == .back ? covers.statSelection : [],
                companion: covers[face.opposite],
                gallery: covers.photos,
                width: width
            )
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        // Une image de couverture : VoiceOver lit le titre de l'écran et le
        // bouton « Configurer », pas un plat qu'il ne saurait décrire.
        .accessibilityHidden(true)
    }
}

/// Une flèche de page : un chevron dans un rond cerclé.
///
/// Elle **garde sa place quand elle ne sert à rien** — page 1 pour la
/// précédente, dernière page pour la suivante — au lieu de disparaître : les
/// trois éléments de l'indicateur sont centrés ensemble, et en retirer un
/// recentrerait les deux autres à chaque bout du carnet.
struct BookPageArrow: View {
    enum Direction { case backward, forward }

    let direction: Direction
    let label: String
    let isEnabled: Bool
    let action: () -> Void

    @ScaledMetric(relativeTo: .body) private var side: CGFloat = 31

    var body: some View {
        Button(action: action) {
            Image(brand: "IconChevron")
                .resizable()
                .renderingMode(.template)
                .scaledToFit()
                // Le chevron du design system pointe à droite ; celui de gauche
                // est le même retourné. Pas deux assets pour un miroir.
                .rotationEffect(.degrees(direction == .backward ? 180 : 0))
                .frame(width: side * 0.45, height: side * 0.45)
                .foregroundStyle(isEnabled ? MemoBookColor.ink : MemoBookColor.inkFaint)
                .frame(width: side, height: side)
                .overlay {
                    Circle().strokeBorder(
                        isEnabled ? MemoBookColor.hairline : MemoBookColor.hairline.opacity(0.5),
                        lineWidth: 1
                    )
                }
                // La cible reste à 2.75 rem même quand le rond fait 31 pt : le
                // dessin est plus petit que le geste (R7).
                .frame(
                    width: MemoBookSpacing.minimumTapTarget,
                    height: MemoBookSpacing.minimumTapTarget
                )
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .accessibilityLabel(label)
    }
}

/// La commande qui passe l'aperçu en plein écran, et celle qui en revient.
///
/// Un rond bleu clair posé sur la page, comme la maquette : la page est du
/// papier, la commande n'en fait pas partie et doit se voir comme ajoutée.
struct BookScreenModeButton: View {
    let icon: String
    let label: String
    let action: () -> Void

    @ScaledMetric(relativeTo: .body) private var side: CGFloat = 36

    var body: some View {
        Button(action: action) {
            Image(brand: icon)
                .resizable()
                .scaledToFit()
                .frame(width: min(side, 52), height: min(side, 52))
                .frame(
                    width: MemoBookSpacing.minimumTapTarget,
                    height: MemoBookSpacing.minimumTapTarget
                )
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}
