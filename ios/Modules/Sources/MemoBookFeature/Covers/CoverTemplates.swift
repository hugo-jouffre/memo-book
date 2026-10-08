import MemoBookCore
import MemoBookDesign
import SwiftUI

/// **Les sept gabarits de couverture**, redessinés d'après les plats de Hugo
/// (`assets/covers`, 08/10/2026 : « recode-les pour qu'ils soient visibles et
/// éditables dans l'app »).
///
/// Chaque gabarit garde **la composition** de la maquette — où tombe le titre,
/// où va la photo, ce qui orne le papier — et y met **ce que le voyageur a
/// choisi** : son titre, sa signature, sa photo, son texte de quatrième, ses
/// chiffres. Rien de la maquette n'y reste écrit : ni « PHILIPPINES », ni la
/// photo des trois amis.
///
/// - **La signature** (`subtitle` du devant) se lit en deux temps, comme dans
///   les maquettes : sa première ligne est **qui** — « Maylis, Claire et
///   Augustin » —, sa dernière **quand** — « Août 2026 ». Chaque gabarit pose
///   l'une, l'autre ou les deux, là où la maquette les pose.
/// - **Ce qui ne se redessine pas** — la palme, la moto et le globe au trait,
///   les courbes tracées à la main — est découpé dans le plat de Hugo
///   (`ios/Tools/import-cover-ornaments.py`) et se pose sur l'aplat que l'app
///   dessine. Les aquarelles et les timbres de la maquette sont des images
///   **du voyage de la maquette** : ici, ce sont les photos du voyageur qui en
///   tiennent la place.
/// - Les mesures sont des **fractions de la largeur** du plat, comme
///   ``CoverPlate`` : le même dessin sert à 208 pt dans un carrousel et à
///   300 pt sur l'écran de choix. Et les tailles de texte ne suivent pas le
///   Dynamic Type — c'est l'image d'un objet imprimé (voir ``CoverPlate``).
///
/// ⚠️ **Ce n'est toujours pas le rendu d'impression** : la composition du PDF
/// qui lira ces choix reste à écrire (T223).
struct CoverTemplate: View {
    let family: CoverFamily
    let face: CoverFace
    let cover: BookCover
    /// Le plat d'en face, pour ce que le dos reprend du devant — qui, quand.
    let companion: BookCover?
    let photo: CoverPhoto?
    /// Les photos du voyage : les timbres de « Travel book », les images du
    /// récit au dos d'« Aquarelle ». La photo choisie passe toujours en tête.
    let gallery: [CoverPhoto]
    let stats: [CoverStat]
    let width: CGFloat

    var titleBadge: AnyView?
    var subtitleBadge: AnyView?
    var statsBadge: AnyView?

    private var height: CGFloat { width / CoverPlate.ratio }
    private func unit(_ fraction: CGFloat) -> CGFloat { width * fraction }

    var body: some View {
        Group {
            switch (family, face) {
            case (.default, .front): defaultFront
            case (.default, .back): defaultBack
            case (.watercolor, .front): watercolorFront
            case (.watercolor, .back): watercolorBack
            case (.assouline, .front): assoulineFront
            case (.assouline, .back): assoulineBack
            case (.drawing, .front): drawingFront
            case (.drawing, .back): drawingBack
            case (.photoDrawing, .front): photoDrawingFront
            case (.photoDrawing, .back): photoDrawingBack
            case (.travelBook, .front): travelBookFront
            case (.travelBook, .back): travelBookBack
            case (.elegant, .front): elegantFront
            case (.elegant, .back): elegantBack
            }
        }
        .frame(width: width, height: height)
    }

    // MARK: - Ce que les gabarits lisent

    /// La signature du devant, ligne par ligne.
    private var signatureLines: [String] {
        let source = face == .front ? cover.subtitle : companion?.subtitle ?? ""
        return source
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    /// Qui : la première ligne de la signature, quand elle en a deux.
    private var authors: String? {
        signatureLines.count > 1 ? signatureLines.first : nil
    }

    /// Quand : la dernière ligne — la seule, si la signature n'en a qu'une.
    private var when: String? { signatureLines.last }

    /// Le titre du devant, vu du dos.
    private var frontTitle: String {
        face == .front ? cover.title : companion?.title ?? ""
    }

    /// Le texte de quatrième, coupé en paragraphes.
    private var backParagraphs: [String] {
        cover.subtitle
            .components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    /// Les photos à poser, la choisie d'abord.
    private var photos: [CoverPhoto] {
        var ordered = gallery
        if let photo {
            ordered.removeAll { $0.id == photo.id }
            ordered.insert(photo, at: 0)
        }
        return ordered
    }

    // MARK: - Les polices

    /// Les capitales à empattements de « Par défaut » et d'« Élégant ».
    private func serif(_ size: CGFloat, _ weight: Font.Weight = .bold) -> Font {
        .system(size: unit(size), weight: weight, design: .serif)
    }

    /// Le grotesque épais d'« Aquarelle », d'« Assouline » et de « Travel book ».
    private func heavy(_ size: CGFloat) -> Font {
        .system(size: unit(size), weight: .black)
    }

    /// L'écriture à la main de « Dessin » et de « Photo-dessin ».
    private func hand(_ size: CGFloat) -> Font {
        .custom(BrandFonts.gloriaHallelujah, fixedSize: unit(size))
    }

    private func sans(_ size: CGFloat) -> Font {
        .custom(BrandFonts.generalSansRegular, fixedSize: unit(size))
    }

    // MARK: - Pièces communes

    private func picture(_ photo: CoverPhoto?) -> some View {
        CoverPhotoImage(photo: photo, seed: photo?.id ?? cover.styleId)
    }

    /// Le M de la marque, au pied du dos.
    private func logo(_ color: Color, opacity: Double = 1) -> some View {
        Image(brand: "LogoMemobookCreme")
            .resizable()
            .renderingMode(.template)
            .scaledToFit()
            .frame(height: unit(0.075))
            .foregroundStyle(color.opacity(opacity))
            .accessibilityHidden(true)
    }

    private func ornament(_ name: String, width fraction: CGFloat) -> some View {
        Image(brand: name)
            .resizable()
            .scaledToFit()
            .frame(width: unit(fraction))
            .accessibilityHidden(true)
    }

    /// Un texte qu'on peut ne pas avoir écrit : il tient sa place même vide,
    /// pour que son crayon ait où se poser.
    private func placeholderFrame(minHeight fraction: CGFloat) -> some View {
        Color.clear.frame(maxWidth: .infinity, minHeight: unit(fraction))
    }

    /// « Mon voyage en quelques chiffres », dans un cadre arrondi.
    private func statsBox(ink: Color, fill: Color?, border: Color) -> some View {
        VStack(spacing: unit(0.025)) {
            Text(BookCopy.Covers.Stats.heading)
                .font(serif(0.036, .semibold))
                .foregroundStyle(ink)
            HStack(alignment: .top, spacing: unit(0.025)) {
                ForEach(stats) { stat in
                    VStack(spacing: unit(0.008)) {
                        Text(stat.value)
                            .font(serif(0.075, .semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                        Text(stat.label)
                            .font(serif(0.028, .regular))
                            .multilineTextAlignment(.center)
                    }
                    .foregroundStyle(ink)
                    .frame(maxWidth: .infinity)
                }
            }
            .minimumScaleFactor(0.5)
        }
        .padding(unit(0.035))
        .background {
            RoundedRectangle(cornerRadius: unit(0.04))
                .fill(fill ?? .clear)
            RoundedRectangle(cornerRadius: unit(0.04))
                .strokeBorder(border, lineWidth: max(1, unit(0.004)))
        }
        .overlay(alignment: .topTrailing) { statsBadge }
    }

    // MARK: - Par défaut

    /// La photo pleine page ; le titre en grandes capitales à empattements en
    /// haut, la signature en bas, en blanc.
    private var defaultFront: some View {
        ZStack {
            picture(photo)
            // Le blanc se lit sur un ciel clair grâce à ce voile, qui laisse le
            // milieu de la photo intact.
            LinearGradient(
                colors: [.black.opacity(0.35), .clear, .clear, .black.opacity(0.4)],
                startPoint: .top,
                endPoint: .bottom
            )
            VStack(spacing: 0) {
                Text(cover.title)
                    .font(serif(0.14))
                    .foregroundStyle(MemoBookColor.paper)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.4)
                    .shadow(color: .black.opacity(0.25), radius: unit(0.01))
                    .frame(maxWidth: .infinity)
                    .overlay(alignment: .topTrailing) { titleBadge }
                Spacer(minLength: 0)
                Text(cover.subtitle)
                    .font(serif(0.05, .regular))
                    .foregroundStyle(MemoBookColor.paper)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .minimumScaleFactor(0.6)
                    .shadow(color: .black.opacity(0.3), radius: unit(0.008))
                    .frame(maxWidth: .infinity)
                    .overlay(alignment: .bottomTrailing) { subtitleBadge }
            }
            .padding(.horizontal, unit(0.06))
            .padding(.top, unit(0.07))
            .padding(.bottom, unit(0.08))
        }
    }

    /// Le papier, un filet en pointillés, le trajet, les chiffres, la marque.
    private var defaultBack: some View {
        ZStack {
            MemoBookColor.paper
            RoundedRectangle(cornerRadius: unit(0.01))
                .strokeBorder(
                    MemoBookColor.action.opacity(0.35),
                    style: StrokeStyle(lineWidth: max(0.5, unit(0.003)), dash: [unit(0.012), unit(0.008)])
                )
                .padding(unit(0.035))
            VStack(spacing: unit(0.05)) {
                CoverRouteSketch()
                    .stroke(MemoBookColor.action.opacity(0.7), style: StrokeStyle(lineWidth: max(1, unit(0.006)), lineCap: .round, dash: [unit(0.015), unit(0.012)]))
                    .overlay { CoverRouteStops(color: MemoBookColor.action, radius: unit(0.016)) }
                    .frame(width: unit(0.55), height: unit(0.62))
                    .accessibilityHidden(true)
                Spacer(minLength: 0)
                if !stats.isEmpty {
                    statsBox(ink: MemoBookColor.ink, fill: nil, border: MemoBookColor.action.opacity(0.6))
                }
                logo(MemoBookColor.action)
            }
            .padding(.horizontal, unit(0.1))
            .padding(.top, unit(0.12))
            .padding(.bottom, unit(0.08))
        }
    }

    // MARK: - Aquarelle

    /// Un bandeau crème et son titre noir en capitales épaisses ; dessous, la
    /// photo, comme une aquarelle qui se perd dans le papier en bas.
    private var watercolorFront: some View {
        VStack(spacing: 0) {
            Text(cover.title.uppercased())
                .font(heavy(0.115))
                .foregroundStyle(MemoBookColor.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.4)
                .frame(maxWidth: .infinity)
                .frame(height: height * 0.17)
                .padding(.horizontal, unit(0.05))
                .overlay(alignment: .topTrailing) { titleBadge }

            picture(photo)
                .saturation(1.15)
                .contrast(1.05)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
                // L'aquarelle de la maquette ne s'arrête pas net : elle se perd
                // dans le papier. La photo fait de même, en bas.
                .mask {
                    LinearGradient(
                        stops: [.init(color: .black, location: 0), .init(color: .black, location: 0.82), .init(color: .clear, location: 1)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }
                .overlay(alignment: .bottomTrailing) {
                    if let when {
                        Text(when)
                            .font(heavy(0.04))
                            .foregroundStyle(MemoBookColor.ink.opacity(0.8))
                            .padding(unit(0.05))
                    }
                }
                .overlay(alignment: .bottomTrailing) { subtitleBadge }
        }
        .background(MemoBookColor.coverCream)
    }

    /// De grandes taches sur le papier ; la date en titre ; le récit en trois
    /// temps, chacun avec une image, à gauche puis à droite.
    private var watercolorBack: some View {
        ZStack {
            MemoBookColor.coverCream
            CoverWashes()
                .fill(MemoBookColor.coverWash)
                .accessibilityHidden(true)
            VStack(spacing: unit(0.045)) {
                Text(when ?? frontTitle)
                    .font(heavy(0.055))
                    .foregroundStyle(MemoBookColor.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)

                VStack(spacing: unit(0.05)) {
                    let paragraphs = Array(backParagraphs.prefix(3))
                    if paragraphs.isEmpty {
                        placeholderFrame(minHeight: 0.3)
                    }
                    ForEach(Array(paragraphs.enumerated()), id: \.offset) { index, paragraph in
                        let image = photos.isEmpty ? nil : photos[index % photos.count]
                        HStack(alignment: .center, spacing: unit(0.04)) {
                            if index.isMultiple(of: 2) { vignette(image) }
                            Text(paragraph)
                                .font(sans(0.03))
                                .foregroundStyle(MemoBookColor.ink)
                                .lineSpacing(unit(0.004))
                                .minimumScaleFactor(0.6)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            if !index.isMultiple(of: 2) { vignette(image) }
                        }
                    }
                }
                .overlay(alignment: .topTrailing) { subtitleBadge }

                Spacer(minLength: 0)
                logo(MemoBookColor.separator, opacity: 0.8)
            }
            .padding(.horizontal, unit(0.08))
            .padding(.top, unit(0.08))
            .padding(.bottom, unit(0.06))
        }
    }

    /// Une image du récit, aux bords adoucis comme une aquarelle collée.
    private func vignette(_ photo: CoverPhoto?) -> some View {
        picture(photo)
            .frame(width: unit(0.22), height: unit(0.18))
            .clipShape(.rect(cornerRadius: unit(0.02)))
            .saturation(1.1)
            .opacity(0.95)
    }

    // MARK: - Assouline

    /// Le bleu de la marque, le titre en grandes capitales vertes, une palme
    /// au milieu, l'année en bas.
    private var assoulineFront: some View {
        ZStack {
            MemoBookColor.outline
            VStack(spacing: 0) {
                Text(cover.title.uppercased())
                    .font(heavy(0.12))
                    .foregroundStyle(MemoBookColor.action)
                    .lineLimit(2)
                    .minimumScaleFactor(0.4)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .overlay(alignment: .topTrailing) { titleBadge }
                Spacer(minLength: unit(0.03))
                ornament("CoverOrnamentPalm", width: 0.72)
                Spacer(minLength: unit(0.03))
                Text(when ?? "")
                    .font(heavy(0.06))
                    .foregroundStyle(MemoBookColor.action)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .frame(maxWidth: .infinity, minHeight: unit(0.07))
                    .overlay(alignment: .bottomTrailing) { subtitleBadge }
            }
            .padding(.horizontal, unit(0.05))
            .padding(.top, unit(0.1))
            .padding(.bottom, unit(0.06))
        }
    }

    /// Le même bleu : qui a voyagé, en capitales vertes ; le récit, centré ;
    /// les chiffres dans un cadre blanc.
    private var assoulineBack: some View {
        ZStack {
            MemoBookColor.outline
            VStack(spacing: unit(0.04)) {
                Text((authors ?? frontTitle).uppercased())
                    .font(heavy(0.055))
                    .foregroundStyle(MemoBookColor.action)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.5)

                Group {
                    if cover.subtitle.isEmpty {
                        placeholderFrame(minHeight: 0.3)
                    } else {
                        Text(cover.subtitle)
                            .font(serif(0.03, .regular))
                            .foregroundStyle(MemoBookColor.ink)
                            .multilineTextAlignment(.center)
                            .lineSpacing(unit(0.004))
                            .minimumScaleFactor(0.5)
                    }
                }
                .frame(maxWidth: .infinity)
                .overlay(alignment: .topTrailing) { subtitleBadge }

                Spacer(minLength: 0)
                if !stats.isEmpty {
                    statsBox(ink: MemoBookColor.ink, fill: MemoBookColor.paper, border: MemoBookColor.ink.opacity(0.2))
                }
            }
            .padding(.horizontal, unit(0.08))
            .padding(.top, unit(0.1))
            .padding(.bottom, unit(0.07))
        }
    }

    // MARK: - Dessin

    /// Le papier crème, des chemins en pointillés aux coins, la moto, le
    /// titre à la main, la route, le globe, et qui a voyagé.
    private var drawingFront: some View {
        ZStack {
            MemoBookColor.coverCream
            CoverDashedTrails()
                .stroke(MemoBookColor.ink, style: StrokeStyle(lineWidth: max(1, unit(0.005)), lineCap: .round, dash: [unit(0.018), unit(0.012)]))
                .accessibilityHidden(true)
            VStack(spacing: unit(0.04)) {
                drawn("CoverOrnamentMotorbike", width: 0.34)
                Text(cover.title)
                    .font(hand(0.085))
                    .foregroundStyle(MemoBookColor.ink)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .minimumScaleFactor(0.5)
                    .frame(maxWidth: .infinity)
                    .overlay(alignment: .topTrailing) { titleBadge }
                if let when {
                    Text(when)
                        .font(hand(0.045))
                        .foregroundStyle(MemoBookColor.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                }
                ornament("CoverOrnamentRoad", width: 0.5)
                drawn("CoverOrnamentGlobe", width: 0.2)
                Spacer(minLength: 0)
                Text(authors ?? "")
                    .font(hand(0.035))
                    .foregroundStyle(MemoBookColor.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .frame(maxWidth: .infinity, minHeight: unit(0.05))
                    .overlay(alignment: .bottomTrailing) { subtitleBadge }
            }
            .padding(.horizontal, unit(0.12))
            .padding(.top, unit(0.13))
            .padding(.bottom, unit(0.07))
        }
    }

    /// Un dessin au trait sur son disque bleu pâle, comme la maquette.
    private func drawn(_ name: String, width fraction: CGFloat) -> some View {
        ornament(name, width: fraction)
            .background {
                Circle()
                    .fill(MemoBookColor.outline.opacity(0.25))
                    .frame(width: unit(fraction * 0.8), height: unit(fraction * 0.8))
                    .offset(x: unit(fraction * 0.05))
            }
    }

    /// Un titre à la main souligné, le motard au milieu, et le texte de
    /// quatrième, à la main lui aussi.
    private var drawingBack: some View {
        ZStack {
            MemoBookColor.coverCream
            VStack(spacing: unit(0.05)) {
                VStack(alignment: .trailing, spacing: 0) {
                    Text(BookCopy.Covers.drawingBackHeading)
                        .font(hand(0.08))
                        .foregroundStyle(MemoBookColor.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                    Capsule()
                        .fill(MemoBookColor.ink)
                        .frame(width: unit(0.25), height: max(1.5, unit(0.008)))
                        .padding(.trailing, unit(0.1))
                }
                Spacer(minLength: 0)
                drawn("CoverOrnamentRider", width: 0.42)
                Spacer(minLength: 0)
                Group {
                    if cover.subtitle.isEmpty {
                        placeholderFrame(minHeight: 0.12)
                    } else {
                        Text(cover.subtitle)
                            .font(hand(0.032))
                            .foregroundStyle(MemoBookColor.ink)
                            .multilineTextAlignment(.center)
                            .minimumScaleFactor(0.5)
                    }
                }
                .frame(maxWidth: .infinity)
                .overlay(alignment: .topTrailing) { subtitleBadge }
            }
            .padding(.horizontal, unit(0.08))
            .padding(.top, unit(0.12))
            .padding(.bottom, unit(0.07))
        }
    }

    // MARK: - Photo-dessin

    /// La photo pleine page, des courbes de niveau tracées par-dessus, le
    /// titre à la main sur un arc ; qui en haut, l'année en bas à droite.
    private var photoDrawingFront: some View {
        ZStack {
            picture(photo)
            // Sous le titre, comme la maquette : le titre se pose au-dessus
            // des courbes, pas dedans.
            CoverContourLines()
                .stroke(MemoBookColor.coverMint.opacity(0.9), lineWidth: max(1, unit(0.008)))
                .frame(width: unit(0.9), height: unit(0.72))
                .offset(y: unit(0.26))
                .accessibilityHidden(true)
            VStack(spacing: 0) {
                Text((authors ?? "").uppercased())
                    .font(hand(0.05))
                    .foregroundStyle(MemoBookColor.coverMint)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .frame(maxWidth: .infinity, minHeight: unit(0.06))
                Spacer(minLength: 0)
                CoverArcText(
                    text: cover.title.uppercased(),
                    font: hand(0.17),
                    color: MemoBookColor.coverMint,
                    rise: unit(0.07),
                    width: unit(0.88)
                )
                .overlay(alignment: .topTrailing) { titleBadge }
                Spacer(minLength: 0)
                Spacer(minLength: 0)
                Spacer(minLength: 0)
                Text(when ?? "")
                    .font(hand(0.08))
                    .foregroundStyle(MemoBookColor.coverMint)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .frame(maxWidth: .infinity, minHeight: unit(0.08), alignment: .trailing)
                    .overlay(alignment: .bottomLeading) { subtitleBadge }
            }
            .shadow(color: .black.opacity(0.18), radius: unit(0.006))
            .padding(.horizontal, unit(0.06))
            .padding(.top, unit(0.04))
            .padding(.bottom, unit(0.04))
        }
    }

    /// L'aplat d'eau claire, les courbes en haut à gauche, un mot à la main au
    /// milieu, la marque en bas.
    private var photoDrawingBack: some View {
        ZStack(alignment: .topLeading) {
            MemoBookColor.coverMint
            ornament("CoverOrnamentContours", width: 0.62)
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                Group {
                    if cover.subtitle.isEmpty {
                        placeholderFrame(minHeight: 0.15)
                    } else {
                        Text(cover.subtitle.uppercased())
                            .font(hand(0.042))
                            .foregroundStyle(MemoBookColor.action)
                            .multilineTextAlignment(.center)
                            .lineSpacing(unit(0.01))
                            .minimumScaleFactor(0.5)
                    }
                }
                .frame(maxWidth: .infinity)
                .overlay(alignment: .topTrailing) { subtitleBadge }
                Spacer(minLength: 0)
                logo(MemoBookColor.action)
            }
            .padding(.horizontal, unit(0.1))
            // Sous les courbes du coin, jamais dessus.
            .padding(.top, unit(0.34))
            .padding(.bottom, unit(0.07))
        }
    }

    // MARK: - Travel book

    /// Le carnet de bord : le titre et la date en capitales vertes, un tampon,
    /// les photos du voyage en timbres, et qui a voyagé en bas.
    private var travelBookFront: some View {
        ZStack {
            MemoBookColor.coverCream
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top, spacing: unit(0.03)) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(cover.title.uppercased())
                            .font(heavy(0.07))
                            .lineLimit(2)
                            .minimumScaleFactor(0.5)
                            .overlay(alignment: .topTrailing) { titleBadge }
                        if let when {
                            Text(when.uppercased())
                                .font(heavy(0.07))
                                .lineLimit(1)
                                .minimumScaleFactor(0.5)
                        }
                    }
                    .foregroundStyle(MemoBookColor.action)
                    .frame(maxWidth: .infinity, alignment: .leading)

                    CoverPostmark(year: when ?? cover.title, side: unit(0.22))
                }
                Spacer(minLength: 0)
                stampCollage
                    .frame(maxWidth: .infinity)
                Spacer(minLength: 0)
                Text((authors ?? "").uppercased())
                    .font(heavy(0.055))
                    .foregroundStyle(MemoBookColor.action)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .frame(maxWidth: .infinity, minHeight: unit(0.06))
                    .overlay(alignment: .bottomTrailing) { subtitleBadge }
            }
            .padding(.horizontal, unit(0.1))
            .padding(.top, unit(0.1))
            .padding(.bottom, unit(0.06))
        }
    }

    /// Les timbres : jusqu'à quatre photos du voyage, de travers, bord
    /// dentelé, comme le collage de la maquette.
    private var stampCollage: some View {
        let shown = Array(photos.prefix(4))
        let placements: [(x: CGFloat, y: CGFloat, size: CGFloat, angle: Double)] = [
            (-0.17, -0.12, 0.34, -7),
            (0.14, -0.15, 0.36, 3),
            (-0.15, 0.17, 0.3, 4),
            (0.17, 0.13, 0.32, -5),
        ]
        return ZStack {
            if shown.isEmpty {
                CoverStamp(photo: nil, seed: cover.styleId, side: unit(0.4))
                    .rotationEffect(.degrees(-4))
            }
            ForEach(Array(shown.enumerated()), id: \.element.id) { index, photo in
                let place = placements[index]
                CoverStamp(photo: photo, seed: photo.id, side: unit(place.size))
                    .rotationEffect(.degrees(place.angle))
                    .offset(x: unit(place.x), y: unit(place.y))
            }
        }
        .frame(width: unit(0.8), height: unit(0.72))
    }

    /// La photo dans un cadre vert déchiré, la marque dessous.
    private var travelBookBack: some View {
        ZStack {
            MemoBookColor.coverCream
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                picture(photo)
                    .frame(width: unit(0.86), height: unit(0.96))
                    .clipped()
                    .overlay {
                        CoverRoughFrame()
                            .stroke(MemoBookColor.coverForest, lineWidth: max(2, unit(0.018)))
                    }
                Spacer(minLength: 0)
                logo(MemoBookColor.action)
            }
            .padding(.top, unit(0.12))
            .padding(.bottom, unit(0.08))
        }
    }

    // MARK: - Élégant

    /// Le titre en fines capitales à empattements, la photo comme un tirage,
    /// la date dessous.
    private var elegantFront: some View {
        ZStack {
            MemoBookColor.coverCream
            VStack(spacing: unit(0.05)) {
                Text(cover.title.uppercased())
                    .font(serif(0.1, .regular))
                    .tracking(unit(0.004))
                    .foregroundStyle(MemoBookColor.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.4)
                    .frame(maxWidth: .infinity)
                    .overlay(alignment: .topTrailing) { titleBadge }
                picture(photo)
                    .frame(width: unit(0.82), height: unit(0.68))
                    .clipped()
                Spacer(minLength: 0)
                Text((when ?? "").uppercased())
                    .font(serif(0.04, .regular))
                    .tracking(unit(0.003))
                    .foregroundStyle(MemoBookColor.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .frame(maxWidth: .infinity, minHeight: unit(0.05))
                    .overlay(alignment: .bottomTrailing) { subtitleBadge }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, unit(0.06))
            .padding(.top, unit(0.08))
            .padding(.bottom, unit(0.06))
        }
    }

    /// Un paysage en bandeau, quelques lignes à empattements, la marque
    /// effacée.
    private var elegantBack: some View {
        ZStack {
            MemoBookColor.coverCream
            VStack(spacing: unit(0.08)) {
                picture(photo)
                    .frame(width: unit(0.84), height: unit(0.26))
                    .clipped()
                Spacer(minLength: 0)
                Group {
                    if cover.subtitle.isEmpty {
                        placeholderFrame(minHeight: 0.2)
                    } else {
                        Text(cover.subtitle)
                            .font(serif(0.032, .regular))
                            .foregroundStyle(MemoBookColor.ink)
                            .multilineTextAlignment(.center)
                            .lineSpacing(unit(0.006))
                            .minimumScaleFactor(0.5)
                    }
                }
                .frame(maxWidth: .infinity)
                .overlay(alignment: .topTrailing) { subtitleBadge }
                Spacer(minLength: 0)
                logo(MemoBookColor.separator, opacity: 0.8)
            }
            .padding(.horizontal, unit(0.08))
            .padding(.top, unit(0.1))
            .padding(.bottom, unit(0.07))
        }
    }
}

// MARK: - La photo d'un plat

/// Une photo de couverture : son image, sinon la trame du voyage. Une image
/// qui ne charge plus redemande des liens neufs (T237).
struct CoverPhotoImage: View {
    let photo: CoverPhoto?
    let seed: String

    @Environment(\.refreshCoverPhotos) private var refreshCoverPhotos

    var body: some View {
        Color.clear
            .overlay {
                if let url = photo?.url {
                    AsyncImage(url: url) { phase in
                        if let image = phase.image {
                            image.resizable().scaledToFill()
                        } else if phase.error != nil {
                            TripCoverPlaceholder(seed: seed)
                                .task(id: url) { await refreshCoverPhotos?() }
                        } else {
                            TripCoverPlaceholder(seed: seed)
                        }
                    }
                } else {
                    TripCoverPlaceholder(seed: seed)
                }
            }
            .clipped()
            .accessibilityHidden(true)
    }
}

// MARK: - Les ornements dessinés

/// Un timbre : la photo sur une marge blanche, le bord dentelé.
private struct CoverStamp: View {
    let photo: CoverPhoto?
    let seed: String
    let side: CGFloat

    var body: some View {
        CoverPhotoImage(photo: photo, seed: seed)
            .frame(width: side * 0.84, height: side * 0.84)
            .padding(side * 0.08)
            .background(MemoBookColor.paper)
            // Les dents sont **retirées** du rectangle : remplissage
            // pair-impair.
            .clipShape(CoverPerforatedEdge(tooth: side * 0.035), style: FillStyle(eoFill: true))
            .shadow(color: .black.opacity(0.18), radius: side * 0.03, y: side * 0.015)
    }
}

/// Le bord d'un timbre : un rectangle aux dents rondes, découpées tout autour.
private struct CoverPerforatedEdge: Shape {
    let tooth: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path(rect)
        guard tooth > 0 else { return path }
        let step = tooth * 2.6
        var x = rect.minX + step / 2
        while x < rect.maxX {
            path.addEllipse(in: CGRect(x: x - tooth, y: rect.minY - tooth, width: tooth * 2, height: tooth * 2))
            path.addEllipse(in: CGRect(x: x - tooth, y: rect.maxY - tooth, width: tooth * 2, height: tooth * 2))
            x += step
        }
        var y = rect.minY + step / 2
        while y < rect.maxY {
            path.addEllipse(in: CGRect(x: rect.minX - tooth, y: y - tooth, width: tooth * 2, height: tooth * 2))
            path.addEllipse(in: CGRect(x: rect.maxX - tooth, y: y - tooth, width: tooth * 2, height: tooth * 2))
            y += step
        }
        return path
    }
}

/// Le tampon de « Travel book » : deux cercles, une couronne de points,
/// l'année au milieu, de travers.
private struct CoverPostmark: View {
    let year: String
    let side: CGFloat

    var body: some View {
        ZStack {
            Circle().strokeBorder(MemoBookColor.coverPostmark, lineWidth: max(1, side * 0.035))
            Circle()
                .strokeBorder(
                    MemoBookColor.coverPostmark,
                    style: StrokeStyle(lineWidth: max(0.5, side * 0.015), dash: [side * 0.02, side * 0.03])
                )
                .padding(side * 0.12)
            Text(year.uppercased())
                .font(.system(size: side * 0.13, weight: .heavy, design: .serif))
                .foregroundStyle(MemoBookColor.coverPostmark)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.5)
                .padding(side * 0.22)
        }
        .frame(width: side, height: side)
        .rotationEffect(.degrees(-12))
        .opacity(0.85)
        .accessibilityHidden(true)
    }
}

/// Le cadre déchiré du dos de « Travel book » : un rectangle dont le bord
/// tremble, toujours de la même façon (un bruit fixe, pas un hasard).
private struct CoverRoughFrame: Shape {
    func path(in rect: CGRect) -> Path {
        let jitter = min(rect.width, rect.height) * 0.008
        let steps = 48
        func wobble(_ index: Int) -> CGFloat {
            let value = sin(Double(index) * 12.9898) * 43_758.5453
            return CGFloat(value - value.rounded(.down) - 0.5) * 2 * jitter
        }
        var path = Path()
        let corners = [
            CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.minY),
            CGPoint(x: rect.maxX, y: rect.maxY), CGPoint(x: rect.minX, y: rect.maxY),
        ]
        var index = 0
        for side in 0..<4 {
            let start = corners[side]
            let end = corners[(side + 1) % 4]
            for step in 0..<steps {
                let t = CGFloat(step) / CGFloat(steps)
                let point = CGPoint(
                    x: start.x + (end.x - start.x) * t + (side % 2 == 1 ? wobble(index) : 0),
                    y: start.y + (end.y - start.y) * t + (side % 2 == 0 ? wobble(index) : 0)
                )
                if side == 0, step == 0 { path.move(to: point) } else { path.addLine(to: point) }
                index += 1
            }
        }
        path.closeSubpath()
        return path
    }
}

/// Le trajet du dos « Par défaut » : une route en pointillés qui serpente du
/// haut vers le bas. La maquette dessine la carte du pays visité ; elle viendra
/// du gabarit d'impression, qui connaît les étapes (`carte.js`).
private struct CoverRouteSketch: Shape {
    static let stops: [CGPoint] = [
        CGPoint(x: 0.42, y: 0.05), CGPoint(x: 0.62, y: 0.28),
        CGPoint(x: 0.3, y: 0.5), CGPoint(x: 0.58, y: 0.72), CGPoint(x: 0.78, y: 0.94),
    ]

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let points = Self.stops.map { CGPoint(x: rect.minX + $0.x * rect.width, y: rect.minY + $0.y * rect.height) }
        guard let first = points.first else { return path }
        path.move(to: first)
        for (previous, next) in zip(points, points.dropFirst()) {
            let control = CGPoint(x: (previous.x + next.x) / 2 + rect.width * 0.12, y: (previous.y + next.y) / 2)
            path.addQuadCurve(to: next, control: control)
        }
        return path
    }
}

/// Les étapes posées sur le trajet : un rond plein, cerné de papier.
private struct CoverRouteStops: View {
    let color: Color
    let radius: CGFloat

    var body: some View {
        GeometryReader { proxy in
            ForEach(Array(CoverRouteSketch.stops.enumerated()), id: \.offset) { _, stop in
                Circle()
                    .fill(color)
                    .overlay { Circle().strokeBorder(MemoBookColor.paper, lineWidth: radius * 0.4) }
                    .frame(width: radius * 2, height: radius * 2)
                    .position(x: stop.x * proxy.size.width, y: stop.y * proxy.size.height)
            }
        }
    }
}

/// Les chemins en pointillés qui sortent des coins du devant « Dessin ».
private struct CoverDashedTrails: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width
        let h = rect.height
        var path = Path()
        // En haut, de gauche vers le milieu, qui remonte.
        path.move(to: CGPoint(x: 0, y: h * 0.03))
        path.addCurve(
            to: CGPoint(x: w * 0.58, y: 0),
            control1: CGPoint(x: w * 0.3, y: h * 0.0),
            control2: CGPoint(x: w * 0.55, y: h * 0.12)
        )
        // En haut à droite.
        path.move(to: CGPoint(x: w * 0.9, y: 0))
        path.addQuadCurve(to: CGPoint(x: w, y: h * 0.08), control: CGPoint(x: w * 0.95, y: h * 0.06))
        // À gauche, qui descend jusqu'en bas.
        path.move(to: CGPoint(x: 0, y: h * 0.61))
        path.addCurve(
            to: CGPoint(x: w * 0.15, y: h),
            control1: CGPoint(x: w * 0.12, y: h * 0.7),
            control2: CGPoint(x: w * 0.17, y: h * 0.85)
        )
        // À droite, qui remonte de bas en haut.
        path.move(to: CGPoint(x: w * 0.82, y: h))
        path.addCurve(
            to: CGPoint(x: w, y: h * 0.73),
            control1: CGPoint(x: w * 0.78, y: h * 0.86),
            control2: CGPoint(x: w * 0.92, y: h * 0.8)
        )
        return path
    }
}

/// Les courbes de niveau tracées sur la photo de « Photo-dessin » : quatre
/// contours emboîtés, d'une même forme qui se rétrécit.
private struct CoverContourLines: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        for ring in 0..<4 {
            let inset = CGFloat(ring) * 0.11
            let frame = rect.insetBy(dx: rect.width * inset / 2, dy: rect.height * inset / 2)
            path.addPath(blob(in: frame))
        }
        return path
    }

    private func blob(in rect: CGRect) -> Path {
        let w = rect.width
        let h = rect.height
        let x = rect.minX
        let y = rect.minY
        var path = Path()
        path.move(to: CGPoint(x: x + w * 0.08, y: y + h * 0.35))
        path.addCurve(
            to: CGPoint(x: x + w * 0.62, y: y + h * 0.02),
            control1: CGPoint(x: x + w * 0.1, y: y + h * 0.05),
            control2: CGPoint(x: x + w * 0.4, y: y)
        )
        path.addCurve(
            to: CGPoint(x: x + w, y: y + h * 0.5),
            control1: CGPoint(x: x + w * 0.85, y: y + h * 0.05),
            control2: CGPoint(x: x + w, y: y + h * 0.25)
        )
        path.addCurve(
            to: CGPoint(x: x + w * 0.4, y: y + h),
            control1: CGPoint(x: x + w, y: y + h * 0.8),
            control2: CGPoint(x: x + w * 0.7, y: y + h)
        )
        path.addCurve(
            to: CGPoint(x: x + w * 0.08, y: y + h * 0.35),
            control1: CGPoint(x: x + w * 0.1, y: y + h),
            control2: CGPoint(x: x, y: y + h * 0.6)
        )
        return path
    }
}

/// Les grandes taches du dos « Aquarelle ».
private struct CoverWashes: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width
        let h = rect.height
        var path = Path()
        path.addEllipse(in: CGRect(x: -w * 0.25, y: h * 0.18, width: w * 0.8, height: h * 0.32))
        path.addEllipse(in: CGRect(x: w * 0.45, y: h * 0.42, width: w * 0.85, height: h * 0.28))
        path.addEllipse(in: CGRect(x: -w * 0.1, y: h * 0.72, width: w * 0.7, height: h * 0.25))
        return path
    }
}

/// Un titre posé **sur un arc**, comme « PHILIPPINES » sur la photo de
/// « Photo-dessin » : chaque lettre monte puis redescend, et penche avec la
/// courbe.
private struct CoverArcText: View {
    let text: String
    let font: Font
    let color: Color
    /// De combien le milieu du mot monte au-dessus de ses extrémités.
    let rise: CGFloat
    let width: CGFloat

    var body: some View {
        let letters = Array(text)
        let count = max(letters.count - 1, 1)
        HStack(spacing: 0) {
            ForEach(Array(letters.enumerated()), id: \.offset) { index, letter in
                // De -1 (première lettre) à 1 (dernière) : la parabole d'un arc.
                let position = CGFloat(index) / CGFloat(count) * 2 - 1
                Text(String(letter))
                    .font(font)
                    .foregroundStyle(color)
                    .offset(y: -rise * (1 - position * position))
                    .rotationEffect(.degrees(Double(position) * 14))
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.3)
        .frame(width: width)
        .padding(.top, rise)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text)
    }
}
