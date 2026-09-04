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
/// dessine à l'intérieur une carte détachée de quelques points. Ses coins sont
/// alors **concentriques** à ceux de l'écran — rayon de la dalle moins le
/// retrait, voir ``DeviceScreen`` — si bien qu'elle suit la courbe du verre au
/// lieu de la couper.
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

    /// Ce qui sépare la carte du bord du téléphone, sur les trois côtés. Assez
    /// pour qu'on voie l'écran du dessous tout autour, assez peu pour que la
    /// feuille reste une feuille et non une boîte de dialogue.
    private static var inset: CGFloat { MemoBookSpacing.xs }

    /// Tant que rien n'est mesuré, une feuille de départ plutôt qu'une feuille
    /// plate : le premier rendu ne doit pas laisser voir un ruban de 0 pt qui
    /// se déplie ensuite.
    private static var minimumHeight: CGFloat { 240 }

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

#Preview("Feuille") {
    Color.clear
        .background(MemoBookColor.background)
        .sheet(isPresented: .constant(true)) {
            BrandSheet(
                "Adresse postale",
                subtitle: "Ajoute l’adresse où tu souhaites recevoir ton carnet."
            ) {
                VStack(spacing: MemoBookSpacing.s) {
                    ForEach(["Adresse", "Code postal", "Ville"], id: \.self) { label in
                        Text(label)
                            .frame(maxWidth: .infinity, minHeight: MemoBookSpacing.fieldHeight)
                            .background(MemoBookColor.background, in: .rect(cornerRadius: MemoBookSpacing.controlCornerRadius))
                    }
                    BrandButton("Valider", fillsWidth: true) {}
                }
            }
        }
}

// MARK: - L'écran qui présente

extension View {
    /// L'écran recule pendant qu'une feuille est ouverte : il rapetisse, ses
    /// coins s'arrondissent, et du noir apparaît tout autour.
    ///
    /// C'est le geste d'iOS — celui de Réglages, de Mail, de l'App Store : la
    /// page en cours devient une carte posée derrière la feuille, et on
    /// comprend d'un coup d'œil qu'elle est toujours là et qu'on va y revenir.
    ///
    /// Il faut l'écrire à la main parce que le système ne le fait que pour la
    /// vue racine d'une fenêtre : une feuille présentée depuis un écran poussé
    /// dans une pile de navigation, comme le profil, ne le déclenche pas.
    ///
    /// ```swift
    /// content
    ///     .brandSheetPresenter(isPresented: sheet != nil)
    ///     .sheet(item: $sheet) { … }
    /// ```
    public func brandSheetPresenter(isPresented: Bool) -> some View {
        modifier(BrandSheetPresenter(isPresented: isPresented))
    }
}

/// Le recul de l'écran qui présente une feuille.
private struct BrandSheetPresenter: ViewModifier {
    let isPresented: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Le rapport de réduction d'iOS : la carte perd de chaque côté à peu près
    /// la marge d'écran, ce qui donne ce huitième de point de recul.
    private static let scale: CGFloat = 0.92

    /// Ce dont la carte redescend, pour que son haut se pose sous la barre
    /// d'état au lieu de flotter au milieu du noir.
    private static let drop: CGFloat = 12

    func body(content: Content) -> some View {
        content
            // Les coins de l'écran, exactement : la carte est une réduction du
            // téléphone, pas un rectangle posé dessus.
            .clipShape(.rect(cornerRadius: isPresented ? DeviceScreen.cornerRadius : 0))
            .scaleEffect(isPresented ? Self.scale : 1, anchor: .top)
            .offset(y: isPresented ? Self.drop : 0)
            // `scaleEffect` est une transformation de rendu : elle ne touche pas
            // au cadre. Le noir posé ici reste donc à la taille de l'écran, et
            // c'est lui qu'on découvre autour de la carte.
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black.ignoresSafeArea())
            .animation(
                reduceMotion ? .none : .smooth(duration: 0.35),
                value: isPresented
            )
    }
}
