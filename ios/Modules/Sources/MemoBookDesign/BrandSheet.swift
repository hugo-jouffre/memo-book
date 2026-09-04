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
/// **La feuille flotte.** Elle ne touche jamais le bord du téléphone : le fond
/// que le système lui donne est effacé (`presentationBackground(.clear)`) et on
/// dessine à l'intérieur une carte détachée de quelques points, en bas comme sur
/// les côtés. Ses coins valent le rayon de la dalle **moins ce retrait** — voir
/// ``DeviceScreen`` — donc ils sont concentriques à ceux du téléphone et suivent
/// la courbe du verre au lieu de la couper.
///
/// **Elle fait reculer l'app.** Toute feuille de MemoBook demande à l'écran du
/// dessous de rapetisser — voir ``SwiftUI/View/brandSheetPresenter(isPresented:)``.
/// C'est la feuille elle-même qui le déclenche, par
/// ``SwiftUI/EnvironmentValues/brandSheetDepth`` : aucune ne peut l'oublier, et
/// une feuille ouverte par-dessus une autre les fait reculer toutes les deux.
///
/// ```swift
/// .sheet(isPresented: $isEditingAddress) {
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

    /// Ce qui sépare la carte du bord du téléphone, sur ses trois côtés. Assez
    /// pour qu'on voie l'écran du dessous tout autour, assez peu pour que la
    /// feuille reste une feuille et non une boîte de dialogue.
    private static var inset: CGFloat { MemoBookSpacing.xs }

    /// Tant que rien n'est mesuré, une feuille de départ plutôt qu'une feuille
    /// plate : le premier rendu ne doit pas laisser voir un ruban de 0 pt qui
    /// se déplie ensuite.
    private static var minimumHeight: CGFloat { 240 }

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
        // La carte occupe tout le cran, moins le retrait : c'est ce qui met son
        // bas exactement à la même distance du bord que ses côtés.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(MemoBookColor.surface, in: .rect(cornerRadius: cardCornerRadius))
        .padding(.horizontal, Self.inset)
        .padding(.bottom, Self.inset)
        .presentationDetents([.height(detentHeight)])
        // On dessine la nôtre : celle du système est posée par-dessus le
        // contenu et ne suit pas la palette de la marque.
        .presentationDragIndicator(.hidden)
        // Le fond du système est effacé : c'est la carte ci-dessus qui porte la
        // couleur et la forme, et c'est ce qui lui permet de flotter.
        .presentationBackground(.clear)
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
        // S'annoncer au compteur : c'est ce qui fait reculer l'app **quelle que
        // soit** la feuille, sans qu'aucun écran ait à y penser.
        .onAppear { presentation?.open() }
        .onDisappear { presentation?.close() }
    }

    /// Concentrique aux coins du téléphone : le rayon de la dalle, moins le
    /// retrait. Sur un écran à angles droits (SE), on retombe sur le rayon de
    /// feuille de la marque plutôt que sur zéro.
    private var cardCornerRadius: CGFloat {
        max(DeviceScreen.cornerRadius - Self.inset, MemoBookSpacing.sheetCornerRadius)
    }

    private var detentHeight: CGFloat {
        guard bodyHeight > 0 else { return Self.minimumHeight }
        // Le retrait décolle la carte du bord ; la marge qui s'y ajoute passe le
        // dernier élément au-dessus de l'indicateur d'accueil, dont la feuille
        // ne connaît pas la hauteur d'avance.
        return bodyHeight + Self.handleBlockHeight + MemoBookSpacing.s + Self.inset
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

/// Le recul de l'écran qui présente une feuille.
private struct BrandSheetPresenter: ViewModifier {
    let isPresented: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Le rapport de réduction d'iOS : la carte perd de chaque côté à peu près
    /// la marge d'écran.
    private static let scale: CGFloat = 0.92

    /// Ce dont la carte redescend, pour que son haut se pose sous la barre
    /// d'état au lieu de flotter au milieu du noir.
    private static let drop: CGFloat = 12

    func body(content: Content) -> some View {
        content
            // Le fond de l'app, posé en couche débordante : c'est lui qui
            // remplit les safe areas, que le cadre de la vue n'atteint pas.
            .background(MemoBookColor.background.ignoresSafeArea())
            .scaleEffect(isPresented ? Self.scale : 1, anchor: .top)
            .offset(y: isPresented ? Self.drop : 0)
            // Un **masque** et non un `clipShape` : le découpage doit couvrir
            // tout l'écran, safe areas comprises, et le cadre de la vue s'arrête
            // à leur bord. Un `clipShape` posé ici rognait le fond au ras de la
            // barre d'état et laissait deux bandes noires, y compris quand
            // aucune feuille n'était ouverte. Le masque, lui, est une couche de
            // rendu : il déborde comme le fond.
            .mask {
                RoundedRectangle(
                    cornerRadius: isPresented ? DeviceScreen.cornerRadius : 0,
                    style: .continuous
                )
                .ignoresSafeArea()
            }
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
