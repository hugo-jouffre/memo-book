import MemoBookCore
import MemoBookDesign
import SwiftUI

/// Le titre d'une section de l'accueil, avec ses deux décorations possibles :
/// le point vert qui signale « en ce moment », et la pastille lime qui compte
/// ce que la section contient.
struct HomeSectionHeading: View {
    let title: String
    var showsLiveDot = false
    var count: Int?

    /// Ouvrir un nouveau carnet. Fournie, elle pose un « + » au bout de la
    /// ligne — sur « Ton voyage », ou sur « Voyage à venir » quand rien n'est en
    /// cours (Hugo, 15/09/2026). C'était la seule chose qui manquait à quelqu'un
    /// qui a déjà un voyage ouvert : le CTA du bas parle alors du micro, et la
    /// carte pointillée qui ouvrait la feuille n'apparaît que sans voyage.
    var onAdd: (() -> Void)?

    @ScaledMetric(relativeTo: .title3) private var dotSide: CGFloat = 9

    var body: some View {
        // Espacement nul : c'est le décalage de la pastille qui la place, et
        // il la fait mordre sur la dernière lettre du titre.
        HStack(alignment: .top, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                if showsLiveDot {
                    Circle()
                        // Le vert clair, pas celui du CTA : c'est un voyant,
                        // pas une action. (`Green Lighter`, à confirmer sur le
                        // nœud Figma.)
                        .fill(MemoBookColor.actionLight)
                        .frame(width: dotSide, height: dotSide)
                        // Le point se cale sur la hauteur d'x du titre plutôt
                        // que sur sa ligne de base, où il flotterait.
                        .alignmentGuide(.firstTextBaseline) { $0[.bottom] + 1 }
                        .accessibilityHidden(true)
                }

                Text(title)
                    .font(MemoBookFont.heading)
                    .foregroundStyle(MemoBookColor.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let count, count > 0 {
                CountBadge(count: count)
                    // Elle est dessinée après le titre, donc au-dessus : elle
                    // chevauche la fin du mot au lieu de le suivre.
                    .offset(x: -11, y: -MemoBookSpacing.xs)
            }

            Spacer(minLength: 0)

            if let onAdd {
                HomeAddButton(action: onAdd)
                    // Le rond fait 2.75 rem de cible, le titre une ligne de 26 :
                    // la marge négative le centre sur la ligne sans que la
                    // section grandisse de sa moitié.
                    .padding(.vertical, -(MemoBookSpacing.minimumTapTarget - 26) / 2)
            }
        }
        // Avec un « + », la ligne garde ses deux éléments pour VoiceOver : le
        // titre en entête, et le bouton — les fondre l'aurait fait disparaître
        // du curseur.
        .accessibilityElement(children: onAdd == nil ? .combine : .contain)
        .accessibilityAddTraits(onAdd == nil ? .isHeader : [])
    }
}

/// Le « + » d'une section de voyages : ouvrir un nouveau carnet.
///
/// Le même rond que celui qui invite un co-voyageur en tête d'un voyage
/// (``CompanionStack``) — 34 de dessin, 2.75 rem de cible —, cerné de bleu ici
/// parce qu'il se pose sur le crème et non sur une photo : blanc sur crème sans
/// filet, il n'aurait pas l'air d'un bouton.
struct HomeAddButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(brand: "IconPlus")
                .resizable()
                .renderingMode(.template)
                .scaledToFit()
                // Le glyphe n'occupe que la moitié de sa boîte — voir
                // ``MemoBookSpacing/contentIcon`` : 22 de boîte font 12 d'encre.
                .frame(width: MemoBookSpacing.s + 6, height: MemoBookSpacing.s + 6)
                .foregroundStyle(MemoBookColor.ink)
                .frame(width: CompanionStack.diameter, height: CompanionStack.diameter)
                .background(MemoBookColor.surface, in: .circle)
                .overlay { Circle().strokeBorder(MemoBookColor.outline, lineWidth: 1.5) }
                .frame(
                    width: MemoBookSpacing.minimumTapTarget,
                    height: MemoBookSpacing.minimumTapTarget
                )
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Ouvrir un nouveau carnet")
    }
}

/// La pastille qui compte les carnets d'une section.
///
/// **Bleue à contour**, et non lime : la maquette montrait les deux, et Hugo a
/// tranché (14/09/2026, T36) — le lime ne parle que de l'abonnement, un compte
/// de voyages n'en parle pas. Elle compte les voyages **de la liste** qu'elle
/// coiffe, dont toutes les cartes sont visibles ; le « ×8 » d'une maquette à
/// carte unique était une erreur (T15).
struct CountBadge: View {
    let count: Int

    var body: some View {
        BrandTagPill("×\(count)", tone: .info)
            .accessibilityLabel("\(count) au total")
    }
}

/// La carte de découverte : un carnet d'exemple, pour comprendre où tout ça
/// mène avant d'avoir enregistré quoi que ce soit.
///
/// Le pointillé la distingue des cartes de contenu : ce n'est pas un de tes
/// voyages, c'est une porte vers autre chose. L'image, elle, va **jusqu'au bord
/// droit** — elle n'est pas une vignette posée dans la carte, elle en est le
/// flanc.
struct ShowcaseCard: View {
    let showcase: Showcase
    let onOpen: () -> Void

    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .body) private var minimumHeight: CGFloat = 104

    private var shape: RoundedRectangle {
        .rect(cornerRadius: MemoBookSpacing.largeCornerRadius)
    }

    var body: some View {
        Button(action: onOpen) {
            content
                .frame(minHeight: minimumHeight)
                .homeCardHitArea()
        }
        .buttonStyle(CardPressStyle())
        .background(MemoBookColor.outline.opacity(0.22), in: shape)
        // L'image touche les bords : c'est la carte qui la rogne.
        .clipShape(shape)
        .brandDashedCard(color: MemoBookColor.outline)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }

    @ViewBuilder
    private var content: some View {
        // En taille accessible le texte a besoin de toute la largeur : l'image
        // passe dessous plutôt que de lui voler la moitié de la carte.
        if typeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: MemoBookSpacing.s) {
                text.padding([.top, .horizontal], MemoBookSpacing.s)
                artwork
                    .frame(height: minimumHeight)
                    .overlay(alignment: .bottomTrailing) { arrow.padding(MemoBookSpacing.xs + 4) }
            }
        } else {
            HStack(spacing: 0) {
                text.padding(MemoBookSpacing.s)
                Spacer(minLength: MemoBookSpacing.xs)
                artwork
                    // Assez étroit pour que le titre tienne sur une ligne à la
                    // largeur de référence, assez large pour qu'on distingue
                    // les carnets sur la photo.
                    .frame(width: 124)
                    .overlay(alignment: .bottomTrailing) { arrow.padding(MemoBookSpacing.xs + 4) }
            }
        }
    }

    private var text: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(showcase.title)
                .font(MemoBookFont.bodySemibold)
                .foregroundStyle(MemoBookColor.blueText)
            Text(showcase.subtitle)
                .font(MemoBookFont.label)
                // Le même bleu que le titre, un cran plus petit et plus léger :
                // la hiérarchie se fait au corps et à la graisse, pas avec un
                // second bleu — il n'y en a que trois dans la palette (T12).
                .foregroundStyle(MemoBookColor.blueText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .multilineTextAlignment(.leading)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Le flanc illustré : les carnets terminés.
    ///
    /// L'illustration est **livrée avec l'app** tant que le serveur n'en fournit
    /// pas : c'est une image de marque, pas un contenu qui change avec les
    /// données. Le jour où une campagne veut la sienne, `Showcase.imageUrl` la
    /// remplace sans toucher à la vue.
    private var artwork: some View {
        AsyncImage(url: showcase.imageUrl) { phase in
            if let image = phase.image {
                image.resizable().scaledToFill()
            } else {
                Image(brand: "ShowcaseCarnets")
                    .resizable()
                    .scaledToFill()
            }
        }
        .frame(maxHeight: .infinity)
        .clipped()
        .accessibilityHidden(true)
    }

    /// Rond blanc cerclé de bleu, posé à cheval sur l'image.
    ///
    /// `IconArrowRight` et non `IconArrow` : celle du jeu de marque pointe à
    /// **gauche**, c'est une flèche de retour.
    private var arrow: some View {
        Image(brand: "IconArrowRight")
            .resizable()
            .renderingMode(.template)
            .scaledToFit()
            .frame(width: MemoBookSpacing.contentIcon, height: MemoBookSpacing.contentIcon)
            .foregroundStyle(MemoBookColor.blueText)
            // Le rond garde ses 40 pt : c'est le dessin qui grandit dedans, pas
            // le rond — voir ``MemoBookSpacing/contentIcon``.
            .padding(MemoBookSpacing.xs / 2)
            .background(MemoBookColor.surface, in: .circle)
            .overlay { Circle().strokeBorder(MemoBookColor.blueText, lineWidth: 1.5) }
            .accessibilityHidden(true)
    }
}

/// L'invitation à préparer le prochain voyage, quand il n'y en a aucun en
/// cours.
///
/// Un **pointillé** et non une carte pleine : ce cadre n'est pas un contenu,
/// c'est une place qui attend d'être remplie. C'est la même grammaire que le
/// bloc des voyages passés vides, et elle ne sert qu'à ça dans l'app.
struct UpcomingTripInvite: View {
    let onOpen: () -> Void

    /// La seconde ligne : ce que le doigt déclenche. Elle change avec l'endroit
    /// où la carte est posée — ouvrir un carnet depuis l'accueil, voir les
    /// carnets de la communauté depuis la feuille des commandes.
    var subtitle = "Clique ici pour ouvrir ton prochain carnet"

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: MemoBookSpacing.s) {
                artwork

                VStack(alignment: .leading, spacing: 4) {
                    Text("Commence à planifier ton prochain voyage")
                        .font(MemoBookFont.bodySemibold)
                        .foregroundStyle(MemoBookColor.ink)

                    // La phrase suit la destination : elle dit ce que le doigt
                    // déclenche, et rien d'autre. Sur l'accueil, la carte
                    // menait aux carnets de la communauté et ouvre désormais la
                    // feuille « Nouveau carnet » — à reprendre dans Figma.
                    Text(subtitle)
                        .font(MemoBookFont.label)
                        .foregroundStyle(MemoBookColor.inkMuted)
                }
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(MemoBookSpacing.s)
            .homeCardHitArea()
        }
        .buttonStyle(CardPressStyle())
        .brandDashedCard(color: MemoBookColor.action)
        .overlay(alignment: .topTrailing) { tape }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }

    /// Le carnet MemoBook fini, posé sur sa plaque beige.
    ///
    /// La plaque est **plus étroite que la carte** et l'illustration la remplit
    /// jusqu'aux bords : c'est ce qui la fait lire comme une photo posée dans
    /// le cadre, et non comme un fond de carte de plus. Le beige, lui, ne sert
    /// qu'à ça — voir ``MemoBookColor/beige``.
    private var artwork: some View {
        Image(brand: "EmptyTripIllustration")
            .resizable()
            .scaledToFit()
            .frame(maxWidth: .infinity)
            .padding(.horizontal, MemoBookSpacing.xs)
            // De l'air au-dessus, rien en dessous : le carnet **pose** sur le
            // bas de la plaque au lieu de flotter au milieu. La plaque se règle
            // donc sur la hauteur de l'illustration, elle ne la centre pas.
            .padding(.top, MemoBookSpacing.s)
            .frame(maxWidth: .infinity)
            .background(
                MemoBookColor.beige,
                in: .rect(cornerRadius: MemoBookSpacing.cornerRadius)
            )
            .accessibilityHidden(true)
    }

    /// Le bout de scotch qui déborde en haut du cadre.
    ///
    /// Même grammaire que celui de ``FeaturedTripCard`` : par-dessus la carte,
    /// translucide — on voit le pointillé au travers — et de travers. C'est ce
    /// débordement qui rattache le cadre à la page au lieu de le laisser flotter
    /// dedans.
    private var tape: some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(MemoBookColor.action.opacity(0.18))
            .frame(width: 72, height: 26)
            .rotationEffect(.degrees(-4))
            // Une moitié sur la carte, une moitié dans le vide, et à distance du
            // coin arrondi — posé dessus, il se lirait comme une étiquette.
            .offset(y: -11)
            .padding(.trailing, MemoBookSpacing.l)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

/// La place que prendront les carnets terminés.
struct PastTripsPlaceholder: View {
    var body: some View {
        Text("Tes voyages passés s’afficheront ici")
            .font(MemoBookFont.body)
            .foregroundStyle(MemoBookColor.inkMuted)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(MemoBookSpacing.s)
            .padding(.vertical, MemoBookSpacing.s)
            .brandDashedCard()
    }
}
