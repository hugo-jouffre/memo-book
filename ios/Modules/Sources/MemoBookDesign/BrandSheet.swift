import SwiftUI

/// La feuille modale de MemoBook : elle monte du bas, tient la hauteur de son
/// contenu, et se referme au glissé comme n'importe quelle feuille iOS.
///
/// **Le geste est celui d'iOS, le dessin est le nôtre.** On s'appuie sur la
/// présentation modale du système — elle seule donne le glissé élastique, le
/// repli sur l'écran du dessous, le retour arrière de VoiceOver et le
/// redimensionnement au clavier ; les réécrire à la main donnerait une feuille
/// qui *ressemble* à une feuille sans se comporter comme telle. Tout ce qui se
/// voit, en revanche, est repris de la maquette : la poignée, le grand titre
/// Sora, le rond de fermeture, le crème de la marque et le rayon de 28.
///
/// **La hauteur suit le contenu.** iOS ne sait pas caler un cran de feuille sur
/// la hauteur naturelle de ce qu'elle porte : on la mesure, et on en fait un
/// cran sur mesure. Un contenu plus haut que l'écran est ramené par le système
/// à la hauteur maximale, et se met alors à défiler.
///
/// **Elle est posée au bas de l'écran, comme toute feuille iOS.** On a essayé
/// de la faire flotter, détachée des bords : c'était une erreur sur trois plans
/// à la fois. Le système dessine une ombre autour de son conteneur, qui débordait
/// de la carte en un liseré gris ; le conteneur n'étant plus celui qui porte la
/// forme, plus rien ne rognait le contenu, qui débordait des coins arrondis au
/// défilement ; et le bas décroché laissait voir une bande d'écran sous la
/// feuille. On laisse donc le système porter le fond
/// (`presentationBackground`) et la forme (`presentationCornerRadius`) : ses
/// coins du bas rejoignent alors ceux de la dalle, son ombre tombe derrière
/// elle, et le rognage vient gratuitement.
///
/// **Elle fait reculer l'app.** Le recul est déclenché par
/// ``SwiftUI/View/brandSheet(item:content:)``, qui présente la feuille **et**
/// l'annonce au compteur. Il faut passer par lui : le compteur doit basculer au
/// moment où la liaison change, c'est-à-dire quand la fermeture *commence*.
/// Branché sur l'apparition et la disparition de la feuille, il ne basculait
/// qu'une fois celle-ci entièrement descendue, et l'app se remettait à
/// l'échelle d'un coup sec après coup.
///
/// ```swift
/// .brandSheet(item: $sheet) { destination in
///     BrandSheet("Adresse postale", subtitle: "Ajoute l’adresse où tu souhaites recevoir ton carnet.") {
///         // les champs, puis le CTA
///     }
/// }
/// ```
public struct BrandSheet<Content: View>: View {
    private let title: String
    private let subtitle: String?
    private let content: Content

    public init(
        _ title: String,
        subtitle: String? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.content = content()
    }

    @Environment(\.dismiss) private var dismiss

    /// Hauteur naturelle de tout ce qui défile. C'est elle qui devient le cran
    /// de la feuille.
    @State private var bodyHeight: CGFloat = 0

    /// Hauteur du bandeau de la poignée : ses marges et son trait.
    private static var handleBlockHeight: CGFloat { MemoBookSpacing.xs * 2 + 5 }

    /// Tant que rien n'est mesuré, une feuille de départ plutôt qu'une feuille
    /// plate : le premier rendu ne doit pas laisser voir un ruban de 0 pt qui
    /// se déplie ensuite.
    private static var minimumHeight: CGFloat { 240 }

    /// La hauteur maximale d'une feuille : celle qui laisse voir, au-dessus
    /// d'elle, la bande d'app décrite par ``BrandSheetMetrics/appReveal``.
    @MainActor
    private static var ceilingHeight: CGFloat {
        DeviceScreen.height
            - DeviceScreen.topSafeInset
            - BrandSheetMetrics.recoilDrop
            - BrandSheetMetrics.appReveal
    }

    /// Le niveau d'empilement de cette feuille, et le compteur partagé qui dit
    /// combien de feuilles sont ouvertes. Ensemble, ils permettent à une feuille
    /// de savoir qu'une autre s'est ouverte par-dessus elle.
    @Environment(\.brandSheetDepth) private var depth
    @Environment(\.brandSheetPresentation) private var presentation
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// `true` quand une feuille est ouverte par-dessus celle-ci.
    private var isCoveredByAnotherSheet: Bool {
        (presentation?.count ?? 0) > depth + 1
    }

    public var body: some View {
        VStack(spacing: 0) {
            handle
            scrollingBody
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .presentationDetents([.height(detentHeight)])
        // On dessine la nôtre : celle du système est posée par-dessus le
        // contenu et ne suit pas la palette de la marque.
        .presentationDragIndicator(.hidden)
        // Le fond **et** la forme appartiennent au système : c'est lui qui rogne
        // le contenu au bord de la feuille, et son ombre tombe alors derrière
        // elle au lieu de faire un liseré.
        .presentationBackground(MemoBookColor.surface)
        .presentationCornerRadius(MemoBookSpacing.sheetCornerRadius)
        // Le crème de la marque ne se retourne pas en sombre — voir
        // `MemoBookColor`.
        .environment(\.colorScheme, .light)
        // Une feuille présentée par cette feuille-ci sera d'un cran plus
        // profonde.
        .environment(\.brandSheetDepth, depth + 1)
        // Elle recule à son tour quand une autre s'ouvre par-dessus : le recul
        // ne s'arrête pas à l'app, il traverse la pile de feuilles.
        .scaleEffect(isCoveredByAnotherSheet ? 0.94 : 1, anchor: .top)
        .animation(
            reduceMotion ? .none : .smooth(duration: 0.35),
            value: isCoveredByAnotherSheet
        )
    }

    private var detentHeight: CGFloat {
        guard bodyHeight > 0 else { return Self.minimumHeight }
        // La feuille descend jusqu'au bord : c'est à elle de garder son dernier
        // élément au-dessus de l'indicateur d'accueil.
        let wanted =
            bodyHeight
            + Self.handleBlockHeight
            + MemoBookSpacing.s
            + DeviceScreen.bottomSafeInset

        // Un contenu trop haut ne pousse pas la feuille jusqu'en haut : il
        // défile. C'est le cas des six connecteurs.
        return min(wanted, Self.ceilingHeight)
    }

    private var handle: some View {
        Capsule()
            .fill(MemoBookColor.separator)
            .frame(width: 40, height: 5)
            .padding(.vertical, MemoBookSpacing.xs)
            .frame(maxWidth: .infinity)
            .accessibilityHidden(true)
    }

    private var scrollingBody: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: MemoBookSpacing.m) {
                header
                content
            }
            .padding(.horizontal, MemoBookSpacing.screenMargin)
            .padding(.bottom, MemoBookSpacing.s)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background { heightReader }
        }
        // Une feuille courte ne rebondit pas : le glissé appartient alors à la
        // feuille, qui doit pouvoir se refermer.
        .scrollBounceBehavior(.basedOnSize)
        .scrollIndicators(.hidden)
    }

    /// Mesure la hauteur naturelle du contenu.
    ///
    /// Un `GeometryReader` en fond plutôt qu'une `PreferenceKey` : la lecture
    /// reste sur l'acteur principal, là où `onPreferenceChange` demanderait une
    /// closure `Sendable` pour toucher à un `@State`.
    private var heightReader: some View {
        GeometryReader { proxy in
            Color.clear
                .onAppear { bodyHeight = proxy.size.height }
                .onChange(of: proxy.size.height) { _, height in bodyHeight = height }
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: MemoBookSpacing.s) {
            VStack(alignment: .leading, spacing: MemoBookSpacing.xs) {
                Text(title)
                    .font(MemoBookFont.h1)
                    .tracking(-0.41)
                    .foregroundStyle(MemoBookColor.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)

                if let subtitle {
                    Text(subtitle)
                        .font(MemoBookFont.body)
                        .foregroundStyle(MemoBookColor.inkMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 0)

            closeButton
        }
        .padding(.top, MemoBookSpacing.xs)
    }

    /// Le rond de fermeture. La feuille se referme aussi au glissé et au tapotis
    /// hors d'elle — ce bouton existe pour la main qui ne glisse pas, et pour
    /// VoiceOver, qui a besoin d'une cible nommée.
    private var closeButton: some View {
        Button { dismiss() } label: {
            Image(brand: "IconCross")
                .resizable()
                .renderingMode(.template)
                .scaledToFit()
                .frame(width: MemoBookSpacing.s + 4, height: MemoBookSpacing.s + 4)
                .foregroundStyle(MemoBookColor.ink)
                .padding(MemoBookSpacing.xs + 2)
                // Le noir de la marque à 10 %, pas le crème du fond : sur une
                // feuille déjà claire, le crème ne se détache pas assez pour
                // qu'on voie qu'il y a là un bouton.
                .background(MemoBookColor.hairline, in: .circle)
        }
        .frame(
            minWidth: MemoBookSpacing.minimumTapTarget,
            minHeight: MemoBookSpacing.minimumTapTarget
        )
        .contentShape(.circle)
        .accessibilityLabel("Fermer")
    }
}

// MARK: - Le recul de l'écran du dessous

/// Combien de feuilles de marque sont ouvertes, en ce moment, dans l'app.
///
/// L'information circule à l'envers de l'environnement — de la feuille vers
/// l'écran qui la présente — donc elle passe par un objet partagé plutôt que par
/// une valeur transmise. C'est ce qui rend le recul **automatique** : toute
/// ``BrandSheet`` s'y annonce en apparaissant, aucun écran n'a à y penser, et
/// aucune feuille ne peut oublier de le faire.
@MainActor
@Observable
public final class BrandSheetPresentation {
    public private(set) var count = 0

    public init() {}

    public var isPresenting: Bool { count > 0 }

    func open() { count += 1 }
    func close() { count = max(0, count - 1) }
}

extension EnvironmentValues {
    /// Le compteur de feuilles ouvertes. `nil` dans un aperçu isolé, où
    /// personne ne recule et où ce n'est pas un problème.
    @Entry public var brandSheetPresentation: BrandSheetPresentation?

    /// Le niveau d'empilement des feuilles à cet endroit de l'arbre.
    @Entry public var brandSheetDepth: Int = 0
}

extension View {
    /// L'écran recule pendant qu'une feuille est ouverte : il rapetisse, ses
    /// coins prennent ceux du téléphone, et du noir apparaît tout autour.
    ///
    /// C'est le geste d'iOS — celui de Réglages, de Mail, de l'App Store : la
    /// page en cours devient une carte posée derrière la feuille, et on comprend
    /// d'un coup d'œil qu'elle est toujours là et qu'on va y revenir.
    ///
    /// Il faut l'écrire à la main parce que le système ne le fait que pour la
    /// vue racine d'une fenêtre : une feuille présentée depuis un écran poussé
    /// dans une pile de navigation ne le déclenche pas.
    ///
    /// **À poser tout en haut**, sur la vue qui occupe vraiment l'écran entier :
    /// c'est elle qui porte le fond de l'app, et un recul appliqué plus bas
    /// couperait ce fond au ras de la barre d'état.
    public func brandSheetPresenter(isPresented: Bool) -> some View {
        modifier(BrandSheetPresenter(isPresented: isPresented))
    }
}

/// Les mesures que la feuille et l'écran qui recule doivent partager.
///
/// Elles sont ici, ensemble, parce qu'une feuille ne peut décider de sa hauteur
/// maximale qu'en sachant où le haut de la carte de l'app est allé se poser.
/// Séparées, elles dérivaient : la feuille arrivait pile sur le bord de la
/// carte, et il ne restait rien à voir de l'app au-dessus.
enum BrandSheetMetrics {
    /// Le rapport de réduction d'iOS : la carte perd de chaque côté à peu près
    /// la marge d'écran.
    static let recoilScale: CGFloat = 0.92

    /// Ce dont la carte redescend, pour que son haut se pose sous la barre
    /// d'état au lieu de flotter au milieu du noir.
    static let recoilDrop: CGFloat = 12

    /// Ce qu'on voit de la carte de l'app **au-dessus** de toute feuille, même
    /// quand son contenu déborde.
    ///
    /// C'est ce qui fait qu'une feuille reste une feuille : on voit le haut de
    /// l'écran qu'on a quitté, donc on sait qu'on va y revenir et qu'on peut la
    /// refermer. Une feuille qui monte jusqu'en haut n'est plus une feuille,
    /// c'est un écran — et personne ne pense à la faire glisser vers le bas.
    ///
    /// La bande est **la même sur tous les iPhone** : elle se compte depuis la
    /// carte, pas depuis le bord de la dalle, dont la barre d'état fait 20 pt
    /// sur un SE et 59 sur un modèle à Dynamic Island.
    static let appReveal: CGFloat = 44
}

/// Le recul de l'écran qui présente une feuille.
private struct BrandSheetPresenter: ViewModifier {
    let isPresented: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            // Le fond de l'app, posé en couche débordante : c'est lui qui
            // remplit les safe areas, que le cadre de la vue n'atteint pas.
            .background(MemoBookColor.background.ignoresSafeArea())
            // Un **masque** et non un `clipShape` : le découpage doit couvrir
            // tout l'écran, safe areas comprises, et le cadre de la vue s'arrête
            // à leur bord. Un `clipShape` posé ici rognait le fond au ras de la
            // barre d'état et laissait deux bandes noires, y compris quand
            // aucune feuille n'était ouverte. Le masque, lui, est une couche de
            // rendu : il déborde comme le fond.
            //
            // Et il vient **avant** la réduction, pas après : appliqué ensuite,
            // il arrondissait les coins de l'écran — que la carte réduite ne
            // touche plus — et celle-ci gardait des angles droits.
            .mask {
                RoundedRectangle(
                    cornerRadius: isPresented ? DeviceScreen.cornerRadius : 0,
                    style: .continuous
                )
                .ignoresSafeArea()
            }
            .scaleEffect(isPresented ? BrandSheetMetrics.recoilScale : 1, anchor: .top)
            .offset(y: isPresented ? BrandSheetMetrics.recoilDrop : 0)
            // `scaleEffect` est une transformation de rendu : elle ne touche pas
            // au cadre. Le noir posé ici reste donc à la taille de l'écran, et
            // c'est lui qu'on découvre autour de la carte.
            .background(Color.black.ignoresSafeArea())
            .animation(
                reduceMotion ? .none : .smooth(duration: 0.35),
                value: isPresented
            )
    }
}


// MARK: - Présenter une feuille

extension View {
    /// Présente une ``BrandSheet`` pilotée par une valeur optionnelle, et
    /// annonce son ouverture au compteur qui fait reculer l'app.
    ///
    /// **À employer partout à la place de `sheet(item:)`.** C'est le passage par
    /// ici qui garantit que le recul se relâche au bon moment : la liaison
    /// bascule quand la fermeture *commence*, si bien que l'app regrandit
    /// pendant que la feuille descend, d'un même mouvement.
    public func brandSheet<Item: Identifiable, SheetContent: View>(
        item: Binding<Item?>,
        @ViewBuilder content: @escaping (Item) -> SheetContent
    ) -> some View {
        sheet(item: item, content: content)
            .modifier(BrandSheetPresentationReporter(isShowing: item.wrappedValue != nil))
    }

    /// La même chose, pilotée par un booléen — pour une feuille qui n'a qu'un
    /// seul état, comme l'ajout d'une carte.
    public func brandSheet<SheetContent: View>(
        isPresented: Binding<Bool>,
        @ViewBuilder content: @escaping () -> SheetContent
    ) -> some View {
        sheet(isPresented: isPresented, content: content)
            .modifier(BrandSheetPresentationReporter(isShowing: isPresented.wrappedValue))
    }
}

/// Tient à jour le compteur de feuilles ouvertes.
///
/// Il ne peut pas être tenu par la feuille elle-même : `onAppear` et
/// `onDisappear` **encadrent** l'animation de présentation au lieu de
/// l'accompagner. La sortie n'arrivait donc qu'une fois la feuille entièrement
/// descendue, et l'app se remettait à l'échelle d'un coup sec après coup. Lu
/// depuis la liaison, l'état bascule à l'instant où la fermeture commence.
private struct BrandSheetPresentationReporter: ViewModifier {
    let isShowing: Bool

    @Environment(\.brandSheetPresentation) private var presentation

    /// Ce qu'on a effectivement annoncé. Sans ce garde-fou, quitter l'écran
    /// feuille ouverte laisserait l'app reculée pour toujours, et un rendu de
    /// plus compterait deux fois la même feuille.
    @State private var hasReported = false

    func body(content: Content) -> some View {
        content
            .onAppear { report(isShowing) }
            .onChange(of: isShowing) { _, showing in report(showing) }
            .onDisappear { report(false) }
    }

    private func report(_ showing: Bool) {
        guard showing != hasReported else { return }
        hasReported = showing
        if showing {
            presentation?.open()
        } else {
            presentation?.close()
        }
    }
}
