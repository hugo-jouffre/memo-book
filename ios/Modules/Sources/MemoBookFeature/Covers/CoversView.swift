import MemoBookCore
import MemoBookDesign
import SwiftUI

/// Le choix des couvertures : le plat qu'on a, et les trois façons d'en changer.
///
/// **On y arrive de deux endroits**, et c'est voulu : par la ligne
/// « Couvertures (1re & 4e) » en tête des personnalisations, et par la pastille
/// « Défini maintenant ta 1ère et 4ème de couverture » posée sur la première et
/// la dernière page de l'aperçu PDF. Le second chemin est le plus important —
/// c'est en regardant son carnet qu'on se rend compte qu'il n'a pas de
/// couverture.
///
/// L'écran ne fait presque rien lui-même : il montre le plat en grand et ouvre
/// les trois écrans qui le changent. C'est son rôle — **voir avant de régler**.
public struct CoversView: View {
    @State private var model: CoversModel
    private let onIntent: (CoversIntent) -> Void

    /// L'explication posée par une ligne qui ne mène nulle part. `nil` le reste
    /// du temps — voir ``actions``.
    @State private var blockedMessage: String?

    public init(model: CoversModel, onIntent: @escaping (CoversIntent) -> Void) {
        _model = State(initialValue: model)
        self.onIntent = onIntent
    }

    public var body: some View {
        ScrollView {
            VStack(spacing: MemoBookSpacing.s) {
                BrandScreenHeader(title: BookCopy.Covers.title)
                    .frame(maxWidth: .infinity, alignment: .leading)

                CoverFaceTabs(face: $model.face)

                plate

                actions

                if let message = model.errorMessage {
                    ErrorBanner(message: message) {
                        Task { await model.reload() }
                    }
                }
            }
            .padding(.horizontal, MemoBookSpacing.screenMargin)
            .padding(.top, MemoBookSpacing.xs)
            .padding(.bottom, MemoBookSpacing.l)
        }
        .scrollIndicators(.hidden)
        .background(MemoBookColor.background.ignoresSafeArea())
        .brandHiddenNavigationBar()
        // Le crème de la marque ne se retourne pas en sombre — voir
        // `MemoBookColor`.
        .environment(\.colorScheme, .light)
        .task { await model.load() }
        // Changer de plat referme l'explication : elle parlait de l'autre.
        .onChange(of: model.face) { _, _ in blockedMessage = nil }
    }

    // MARK: - Le plat

    /// 300 de large sur la maquette. En fraction de l'écran plutôt qu'en points :
    /// sur un iPhone SE, 300 pt ne laissent que 37 pt de marge de chaque côté et
    /// le plat touche presque les bords.
    private var plate: some View {
        GeometryReader { proxy in
            let width = min(proxy.size.width, Self.plateWidth)

            Group {
                if let cover = model.cover {
                    CoverPlate(
                        cover: cover,
                        style: model.style(of: cover),
                        photo: model.photo(of: cover),
                        face: model.face,
                        stats: model.face == .back ? model.covers?.statSelection ?? [] : [],
                        width: width
                    )
                } else {
                    BrandSkeleton(
                        width: width,
                        height: width / CoverPlate.ratio,
                        cornerRadius: MemoBookSpacing.snug
                    )
                }
            }
            .frame(maxWidth: .infinity)
        }
        // La hauteur doit être connue avant le `GeometryReader`, qui prendrait
        // sinon toute la place que le `ScrollView` lui laisse.
        .frame(height: Self.plateWidth / CoverPlate.ratio)
        .animation(.snappy(duration: 0.25), value: model.face)
    }

    private static let plateWidth: CGFloat = 300

    // MARK: - Les trois façons d'en changer

    private var actions: some View {
        VStack(spacing: MemoBookSpacing.xs) {
            CoverActionRow(
                icon: "IconLayers",
                title: BookCopy.Covers.changeStyle
            ) {
                onIntent(.openStyle)
            }

            // **Les deux lignes suivantes pâlissent** quand le style du plat
            // qu'on regarde ne les porte pas : un aplat n'a pas de photo, une
            // photo pleine page au dos n'a pas de texte. Elles restent tapables
            // et posent l'explication — voir ``blockedMessage``.
            CoverActionRow(
                icon: "IconPictureFrame",
                title: BookCopy.Covers.changePhoto,
                isAvailable: acceptsPhoto
            ) {
                guard acceptsPhoto else {
                    block(BookCopy.Covers.noPhotoHere(model.face))
                    return
                }
                onIntent(.openPhoto)
            }

            CoverActionRow(
                icon: "IconPen",
                title: BookCopy.Covers.editTexts,
                isAvailable: acceptsText
            ) {
                guard acceptsText else {
                    block(BookCopy.Covers.noTextHere(model.face))
                    return
                }
                onIntent(.openTexts)
            }

            if let blockedMessage {
                BrandNotice(blockedMessage, tone: .information)
                    .transition(.opacity)
            }
        }
        .animation(.snappy(duration: 0.25), value: blockedMessage)
        .disabled(model.covers == nil)
    }

    private var acceptsPhoto: Bool { model.covers?.acceptsPhoto(on: model.face) ?? true }
    private var acceptsText: Bool { model.covers?.acceptsText(on: model.face) ?? true }

    /// Pose l'explication, et l'efface quand on change de plat — sans quoi elle
    /// resterait à parler d'une couverture qu'on ne regarde plus.
    private func block(_ message: String) {
        blockedMessage = message
    }
}

// MARK: - Les deux onglets

/// « 1re de couverture » / « 4e de couverture ».
///
/// Partagé par les quatre écrans du parcours : c'est le même rail, au même
/// endroit, et c'est ce qui fait qu'on ne perd pas le plat qu'on regardait en
/// passant du style à la photo.
///
/// **Un plat que l'écran ne sait pas régler pâlit au lieu de disparaître**
/// (Hugo, 16/09/2026) : sur l'écran des textes, une quatrième de couverture en
/// photo pleine page n'a pas de texte à écrire ; sur celui des photos, un plat
/// en aplat n'a pas de photo à choisir. Le segment reste lisible et **tapable**,
/// et son appui pose l'explication — la retirer ou la désactiver laisserait
/// chercher pourquoi.
struct CoverFaceTabs: View {
    @Binding var face: CoverFace

    /// Ce plat se règle-t-il sur cet écran. Tout est ouvert par défaut : les
    /// écrans du choix et du style n'ont rien à fermer.
    var isAvailable: (CoverFace) -> Bool = { _ in true }

    /// Ce qu'on fait de l'appui sur un plat fermé. `nil` sur les écrans où
    /// aucun ne l'est.
    var onUnavailable: ((CoverFace) -> Void)?

    var body: some View {
        BrandSegmentedPicker(
            CoverFace.allCases,
            selection: $face,
            size: .compact,
            isAvailable: isAvailable,
            onUnavailable: onUnavailable
        ) { $0.title }
    }
}

// MARK: - Une ligne d'action

/// Une carte qui mène ailleurs : un pictogramme, un libellé, un chevron.
///
/// Ce n'est pas une ``BrandRow`` : celles-ci vivent **groupées** dans une coque
/// commune, séparées par un filet, et portent une valeur à droite. Ces
/// trois-ci sont trois cartes distinctes, espacées, avec un pictogramme à
/// gauche et rien à droite — c'est ce que dessine la maquette, et les deux
/// motifs ne se confondent pas.
private struct CoverActionRow: View {
    let icon: String
    let title: String
    /// La ligne mène-t-elle quelque part. **Pâlie et non désactivée** quand
    /// elle ne le fait pas : elle doit rester tapable pour pouvoir expliquer.
    var isAvailable: Bool = true
    let action: () -> Void

    @ScaledMetric(relativeTo: .body) private var iconSide: CGFloat = MemoBookSpacing.contentIcon
    @ScaledMetric(relativeTo: .body) private var chevronSide: CGFloat = 14

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: MemoBookSpacing.cornerRadius)

        Button(action: action) {
            HStack(spacing: MemoBookSpacing.snug) {
                Image(brand: icon)
                    .resizable()
                    .renderingMode(.template)
                    .scaledToFit()
                    .frame(width: iconSide, height: iconSide)
                    .foregroundStyle(MemoBookColor.ink)

                Text(title)
                    .font(MemoBookFont.tagline)
                    .foregroundStyle(MemoBookColor.ink)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Image(brand: "IconChevron")
                    .resizable()
                    .renderingMode(.template)
                    .scaledToFit()
                    .frame(width: chevronSide, height: chevronSide)
                    .foregroundStyle(MemoBookColor.inkMuted)
                    // Le chevron dit « ça mène quelque part » : il part quand
                    // ce n'est pas le cas, plutôt que de pâlir en promettant.
                    .opacity(isAvailable ? 1 : 0)
            }
            .opacity(isAvailable ? 1 : 0.45)
            .padding(MemoBookSpacing.snug)
            .frame(minHeight: MemoBookSpacing.minimumTapTarget)
            // Figma dessine #E6DAD0 ; `hairline` est l'encre à 10 %, qui tombe
            // à #E6DFD8 sur le crème — trois points d'écart sur un canal. Même
            // arbitrage que les cartes d'extras.
            .background(MemoBookColor.surface, in: shape)
            .overlay { shape.strokeBorder(MemoBookColor.hairline, lineWidth: 1) }
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(.isButton)
        .accessibilityValue(isAvailable ? "" : "Non disponible")
    }
}

#Preview("Choix des couvertures") {
    NavigationStack {
        CoversView(model: CoversModel(tripId: "trip-rome"), onIntent: { _ in })
    }
}

#Preview("Choix des couvertures — AX3") {
    NavigationStack {
        CoversView(model: CoversModel(tripId: "trip-rome"), onIntent: { _ in })
            .environment(\.dynamicTypeSize, .accessibility3)
    }
}
