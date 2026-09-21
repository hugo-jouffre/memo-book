import MemoBookCore
import MemoBookDesign
import PhotosUI
import SwiftUI

/// Les deux carrousels : celui des styles et celui des photos.
///
/// **Un seul écran pour les deux maquettes.** Elles ne diffèrent que par ce
/// qu'on fait défiler — sept plats dessinés d'un côté, cinq photos et une case
/// d'import de l'autre — et par le sous-titre. Tout le reste est identique :
/// l'en-tête, les onglets, la file au centre, la pastille cochée, le bouton du
/// bas. Deux écrans auraient eu à rester d'accord sur le rythme du défilement,
/// et le second aurait vieilli le premier.
///
/// **Ce qui est au centre est ce qui est choisi.** Pas de sélection au tapotis
/// séparée du défilement : la maquette agrandit le plat du milieu et le coiffe
/// d'une coche, ce qui dit exactement ça. Toucher un plat voisin l'amène au
/// centre, ce qui revient au même geste.
struct CoverCarouselView: View {
    enum Kind {
        case style
        case photo
    }

    let kind: Kind
    @Bindable var model: CoversModel

    /// Ce qui est au centre. Un identifiant et non un index : `scrollPosition`
    /// travaille par identité, et la liste des photos s'allonge quand on en
    /// importe une.
    @State private var centred: String?

    @State private var pickedItem: PhotosPickerItem?
    @State private var isPicking = false
    @State private var importProblem: String?

    /// Le plat sur lequel on vient de taper alors qu'il ne porte pas de photo.
    @State private var blockedFace: CoverFace?

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        // Une `ScrollView` verticale, et non une simple pile : en taille de
        // texte accessible, l'en-tête sur quatre lignes et les deux boutons
        // pleine largeur dépassent l'écran. Une pile les faisait déborder par le
        // haut — le titre passait au-dessus de la barre d'état — au lieu de les
        // laisser défiler. La file des plats, elle, garde son défilement
        // horizontal : les deux ne se marchent pas dessus.
        ScrollView {
            VStack(spacing: MemoBookSpacing.s) {
                BrandScreenHeader(title: BookCopy.Covers.title, subtitle: subtitle)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, MemoBookSpacing.screenMargin)

                // **Le plat sans photo pâlit dans le rail** (Hugo,
                // 16/09/2026) : un aplat ou un kraft n'en porte aucune, et
                // choisir une image dessus ne changeait rien au plat sans que
                // rien ne le dise. Le segment reste tapable et pose
                // l'explication. Le carrousel des **styles**, lui, n'a rien à
                // fermer : on y va justement pour changer ce style.
                CoverFaceTabs(
                    face: $model.face,
                    isAvailable: { kind == .style || acceptsPhoto($0) },
                    onUnavailable: { blockedFace = $0 }
                )
                .padding(.horizontal, MemoBookSpacing.screenMargin)

                if let blockedFace {
                    BrandNotice(BookCopy.Covers.noPhotoHere(blockedFace), tone: .information)
                        .padding(.horizontal, MemoBookSpacing.screenMargin)
                        .transition(.opacity)
                }

                carousel

                if let importProblem {
                    ErrorBanner(message: importProblem)
                        .padding(.horizontal, MemoBookSpacing.screenMargin)
                }

                buttons
                    .padding(.horizontal, MemoBookSpacing.screenMargin)
            }
            .padding(.top, MemoBookSpacing.xs)
            .padding(.bottom, MemoBookSpacing.l)
        }
        .scrollIndicators(.hidden)
        .background(MemoBookColor.background.ignoresSafeArea())
        .brandHiddenNavigationBar()
        // Le crème de la marque ne se retourne pas en sombre — voir
        // `MemoBookColor`.
        .environment(\.colorScheme, .light)
        // Le carrousel s'ouvre **sur le plat en cours**, pas au début de la
        // file : arriver sur le premier style donnerait à croire qu'on vient
        // d'en changer.
        //
        // ⚠️ Et il se cale **après** le chargement, pas dans un `onAppear` :
        // à l'apparition, `covers` est encore nul, donc la file est vide et il
        // n'y a rien à viser. Posé trop tôt, le carrousel restait sur sa
        // première case et aucune n'était cochée.
        .task {
            await model.load()
            centred = currentId
        }
        .onChange(of: model.face) { _, _ in
            centred = currentId
            // L'explication parlait de l'autre plat.
            blockedFace = nil
        }
        .animation(.snappy(duration: 0.25), value: blockedFace)
        .onChange(of: centred) { _, id in select(id) }
        .photosPicker(isPresented: $isPicking, selection: $pickedItem, matching: .images)
        .onChange(of: pickedItem) { _, item in
            guard let item else { return }
            Task { await importPhoto(item) }
        }
    }

    private var subtitle: String {
        switch kind {
        case .style: BookCopy.Covers.styleSubtitle
        case .photo: BookCopy.Covers.photoSubtitle
        }
    }

    /// Ce plat porte-t-il une photo ? Ouvert par défaut : on ne ferme pas un
    /// geste parce qu'on n'a pas encore lu les couvertures.
    private func acceptsPhoto(_ face: CoverFace) -> Bool {
        model.covers?.acceptsPhoto(on: face) ?? true
    }

    // MARK: - La file

    /// Ce que la file propose. Les styles pour l'un, les photos plus la case
    /// d'import pour l'autre.
    private var items: [CoverCarouselItem] {
        guard let covers = model.covers else { return [] }

        switch kind {
        case .style:
            return covers.styles(for: model.face).map { .style($0) }
        case .photo:
            return covers.photos.map { CoverCarouselItem.photo($0) } + [.importSlot]
        }
    }

    /// L'identifiant de ce qui est choisi aujourd'hui sur le plat courant.
    private var currentId: String? {
        guard let cover = model.cover else { return nil }
        switch kind {
        case .style: return cover.styleId
        case .photo: return cover.photoId ?? CoverCarouselItem.importSlot.id
        }
    }

    private var carousel: some View {
        GeometryReader { proxy in
            // La marge qui amène le premier et le dernier plat **au centre** :
            // sans elle, on ne peut choisir ni l'un ni l'autre, puisqu'aucun des
            // deux ne peut atteindre le milieu de l'écran.
            let gutter = max(0, (proxy.size.width - Self.plateWidth) / 2)

            ScrollView(.horizontal) {
                LazyHStack(spacing: MemoBookSpacing.m) {
                    ForEach(items) { item in
                        cell(item)
                            .id(item.id)
                    }
                }
                .scrollTargetLayout()
                .frame(height: Self.rowHeight)
            }
            // ⚠️ `contentMargins` et non `padding` : une marge posée **dans** le
            // contenu compte comme du contenu, et `viewAligned` cale alors la
            // file sur son bord au lieu du plat — le plat choisi se retrouvait à
            // une demi-largeur du centre, à moitié hors de l'écran. Une marge de
            // contenu, elle, est connue du défilement : le calage la déduit.
            .contentMargins(.horizontal, gutter, for: .scrollContent)
            .scrollTargetBehavior(.viewAligned)
            .scrollPosition(id: $centred, anchor: .center)
            .scrollIndicators(.hidden)
            .accessibilityLabel(BookCopy.Covers.Voice.carousel)
        }
        .frame(height: Self.rowHeight)
    }

    @ViewBuilder
    private func cell(_ item: CoverCarouselItem) -> some View {
        let isSelected = item.id == centred

        Group {
            switch item {
            case .style(let style):
                plate(style: style, photo: model.cover.flatMap(model.photo(of:)))
                    .accessibilityLabel(BookCopy.Covers.Voice.style(style.name))
                    // « Assortie à ta 1ère de couverture » : sur le plat qui
                    // reprend le style **choisi** de l'autre côté — et c'est la
                    // seule chose que le carrousel dise avec des mots. Elle
                    // suit le devant quand on le change (Clara, 17/09/2026).
                    .overlay(alignment: .top) {
                        if isSelected, model.covers?.isMatched(style, on: model.face) == true {
                            MatchedStyleTag().offset(y: -MemoBookSpacing.snug)
                        }
                    }

            case .photo(let photo):
                plate(style: model.cover.flatMap(model.style(of:)), photo: photo)
                    .accessibilityLabel(BookCopy.Covers.Voice.photo)

            case .importSlot:
                CoverImportSlot(width: Self.plateWidth)
            }
        }
        .overlay(alignment: .topTrailing) {
            if isSelected {
                CoverSelectionBadge()
                    // Elle déborde du coin, comme la maquette.
                    .offset(x: MemoBookSpacing.snug, y: -MemoBookSpacing.snug)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        // Ce qui n'est pas au centre s'efface : c'est ce qui fait lire le
        // milieu comme le choix, et non comme un plat parmi six.
        .opacity(isSelected ? 1 : 0.55)
        // ⚠️ **L'agrandissement est une transformation de rendu, pas une
        // largeur.** Faire dépendre la largeur de la case du plat sélectionné
        // rendait la mise en page circulaire : le plat choisi grandissait, ce
        // qui décalait toute la file, ce qui changeait le plat au centre — et le
        // carrousel se calait une case à côté, sans jamais cocher personne.
        // Un `scaleEffect` ne touche pas au cadre : la file garde son pas, et
        // c'est bien le plat visé qui s'agrandit.
        .scaleEffect(isSelected ? Self.selectedScale : 1)
        .animation(.snappy(duration: 0.25), value: isSelected)
        .onTapGesture { centred = item.id }
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    private func plate(style: CoverStyle?, photo: CoverPhoto?) -> some View {
        CoverPlate(
            cover: model.cover ?? BookCover(styleId: ""),
            style: style,
            photo: photo,
            face: model.face,
            stats: model.face == .back ? model.covers?.statSelection ?? [] : [],
            width: Self.plateWidth
        )
    }

    // MARK: - Les boutons du bas

    @ViewBuilder
    private var buttons: some View {
        VStack(spacing: MemoBookSpacing.snug) {
            // « Choisir la photo » n'apparaît que sur la case d'import : posé en
            // permanence, il ferait concurrence à « Valider » sur les cinq
            // autres plats, où il n'y a rien à choisir.
            if kind == .photo, centred == CoverCarouselItem.importSlot.id {
                // `IconImport` — la flèche qui entre dans le plateau —, et non
                // `IconTeleverser` : celui-là est bleu, plein, hors de la grille
                // de 24 (T101), et se lisait comme un partage (Hugo,
                // 15/09/2026). Importer une photo, c'est ce mot-là, et la case
                // du carrousel dit déjà « Importer ma photo ».
                BrandButton(
                    BookCopy.Covers.choosePhoto,
                    icon: Image(brand: "IconImport"),
                    style: .secondary,
                    fillsWidth: true
                ) {
                    isPicking = true
                }
            }

            BrandButton(BookCopy.Covers.validate, fillsWidth: true) {
                switch kind {
                case .style: model.commitStyle()
                case .photo: model.commitPhoto()
                }
                dismiss()
            }
            .disabled(model.covers == nil || (kind == .photo && !acceptsPhoto(model.face)))
        }
        .animation(.snappy(duration: 0.25), value: centred)
    }

    // MARK: - Ce qu'on choisit

    /// Pose le plat du milieu sur la couverture, sans l'envoyer : c'est
    /// « Valider » qui écrit. Faire défiler sept styles ne doit pas écrire sept
    /// fois au serveur.
    private func select(_ id: String?) {
        guard let id else { return }

        switch kind {
        case .style:
            guard let style = model.styles.first(where: { $0.id == id }) else { return }
            model.preview(style: style)

        case .photo:
            // La case d'import ne **retire** pas la photo en cours : on la
            // regarde, on choisit, et c'est le choix qui remplace. Poser `nil`
            // ici aurait vidé le plat dès qu'on fait défiler jusqu'au bout.
            guard id != CoverCarouselItem.importSlot.id else { return }
            model.preview(photo: model.covers?.photo(id: id))
        }
    }

    /// Range la photo importée à côté des autres, et la choisit.
    ///
    /// Elle est enregistrée dans les **caches** comme les photos du chat : ce
    /// n'est que du transit tant que la route qui les envoie n'existe pas, et le
    /// système peut reprendre la place s'il en manque.
    private func importPhoto(_ item: PhotosPickerItem) async {
        defer { pickedItem = nil }

        do {
            guard let data = try await item.loadTransferable(type: Data.self) else { return }
            let id = "cover-\(UUID().uuidString)"
            let url = try CoverPhotoFile.save(data, id: id)
            let photo = CoverPhoto(id: id, url: url)
            model.add(photo)
            model.preview(photo: photo)
            centred = photo.id
            importProblem = nil
        } catch {
            importProblem = BookCopy.Covers.importFailed
        }
    }

    /// La largeur d'une case de la file : celle d'un plat **au repos**, 13 rem
    /// (208), comme la maquette. C'est le pas du carrousel, et il ne change
    /// jamais — voir la remarque sur le `scaleEffect` dans ``cell(_:)``.
    private static let plateWidth: CGFloat = 208

    /// De combien le plat choisi grandit. La maquette le dessine à 233 contre
    /// 208 : 14.5 rem contre 13, soit un neuvième de plus.
    private static let selectedScale: CGFloat = 232 / 208

    /// La hauteur réservée à la file. Celle du plat **agrandi**, plus l'air que
    /// la pastille cochée prend en débordant du coin haut : sans lui, elle
    /// serait rognée par le bord du défilement.
    ///
    /// Une gouttière **de chaque côté**, et non une pour les deux : la file
    /// centre le plat, donc la moitié seulement de l'air va au-dessus de lui —
    /// 12 pt, quand l'agrandissement en mange déjà 17 et que la pastille en
    /// déborde de 13. Le haut du rond coché était tranché (Hugo, 15/09/2026).
    private static var rowHeight: CGFloat {
        plateWidth / CoverPlate.ratio * selectedScale + 2 * MemoBookSpacing.m
    }
}

// MARK: - Ce que la file propose

/// Une case du carrousel.
enum CoverCarouselItem: Identifiable, Hashable {
    case style(CoverStyle)
    case photo(CoverPhoto)
    /// La dernière case du carrousel des photos : « Importer ma photo ».
    case importSlot

    var id: String {
        switch self {
        case .style(let style): style.id
        case .photo(let photo): photo.id
        case .importSlot: "cover.import"
        }
    }
}

/// « Assortie à ta 1ère de couverture », posée au-dessus du plat qui reprend
/// le style choisi de l'autre côté.
private struct MatchedStyleTag: View {
    var body: some View {
        Text(BookCopy.Covers.matchedStyle)
            .font(MemoBookFont.mention)
            .foregroundStyle(MemoBookColor.blueText)
            .padding(.horizontal, MemoBookSpacing.snug)
            .padding(.vertical, MemoBookSpacing.xs / 2)
            .background(MemoBookColor.surface, in: .capsule)
            .overlay { Capsule().strokeBorder(MemoBookColor.outline, lineWidth: 1) }
            .fixedSize()
    }
}

/// La case d'import : un aplat, un pictogramme, et le mot qui dit quoi faire.
private struct CoverImportSlot: View {
    let width: CGFloat

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: MemoBookSpacing.snug, style: .continuous)

        VStack(spacing: MemoBookSpacing.s) {
            Image(brand: "IconPictureFrame")
                .resizable()
                .renderingMode(.template)
                .scaledToFit()
                .frame(width: MemoBookSpacing.l, height: MemoBookSpacing.l)
                .foregroundStyle(MemoBookColor.ink)

            Text(BookCopy.Covers.importPhoto)
                .font(MemoBookFont.tagline)
                .foregroundStyle(MemoBookColor.ink)
                .padding(.horizontal, MemoBookSpacing.snug)
                .padding(.vertical, MemoBookSpacing.xs)
                .background(MemoBookColor.surface, in: .capsule)
        }
        .frame(width: width, height: width / CoverPlate.ratio)
        .background(MemoBookColor.separator.opacity(0.4), in: shape)
        .overlay { shape.strokeBorder(MemoBookColor.hairline, lineWidth: 1) }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(BookCopy.Covers.importPhoto)
    }
}

/// Où vit une photo de couverture importée, le temps qu'on la regarde.
///
/// Dans les caches et non dans les documents, comme ``ChatPhotoFile`` et pour la
/// même raison : tant que la route qui l'envoie n'existe pas, ce n'est que du
/// transit, et rien de tout cela n'a à partir dans iCloud.
enum CoverPhotoFile {
    private static var directory: URL {
        URL.cachesDirectory.appending(path: "CoverPhotos", directoryHint: .isDirectory)
    }

    static func save(_ data: Data, id: String) throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appending(path: "\(id).jpg")
        try data.write(to: url, options: .atomic)
        return url
    }
}

#Preview("Couvertures — styles") {
    NavigationStack {
        CoverCarouselView(kind: .style, model: CoversModel(tripId: "trip-rome"))
    }
}

#Preview("Couvertures — photos") {
    NavigationStack {
        CoverCarouselView(kind: .photo, model: CoversModel(tripId: "trip-rome"))
    }
}
