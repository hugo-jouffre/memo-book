import MemoBookCore
import MemoBookDesign
import SwiftUI

/// Les textes des couvertures : le titre et la signature du devant, le texte de
/// quatrième et les chiffres du dos.
///
/// **Le plat reste la pièce principale**, et les crayons se posent dessus : on
/// modifie ce qu'on regarde. C'est ce que dessine la maquette, et c'est ce qui
/// distingue cet écran d'un formulaire — un titre de couverture ne se juge pas
/// dans un champ, il se juge sur le plat.
///
/// ⚠️ **La maquette ne dessine pas l'état « en train d'écrire ».** Elle pose les
/// crayons et s'arrête là. Plutôt que d'inventer une feuille (R3), le crayon
/// **ouvre le champ sous le plat** et lui donne le focus : le plat se met à jour
/// à mesure qu'on tape, donc on ne perd jamais de vue ce qu'on compose, et le
/// clavier a de la place pour monter. Signalé (T89).
struct CoverTextsView: View {
    @Bindable var model: CoversModel

    /// Le champ ouvert, s'il y en a un.
    @FocusState private var focus: Field?

    /// Le focus du cadre de texte, qui ne connaît qu'un booléen. Tenu d'accord
    /// avec ``focus`` — voir ``fields``.
    @FocusState private var isWritingSubtitle: Bool

    private enum Field: Hashable { case title, subtitle }

    @State private var title = ""
    @State private var subtitle = ""
    @State private var isChoosingStats = false

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(spacing: MemoBookSpacing.s) {
                BrandScreenHeader(
                    title: BookCopy.Covers.title,
                    subtitle: BookCopy.Covers.textsSubtitle
                )
                .frame(maxWidth: .infinity, alignment: .leading)

                CoverFaceTabs(face: $model.face)

                plate

                fields

                BrandButton(BookCopy.Covers.validate, fillsWidth: true) {
                    commit()
                    dismiss()
                }
                .disabled(model.covers == nil)
            }
            .padding(.horizontal, MemoBookSpacing.screenMargin)
            .padding(.top, MemoBookSpacing.xs)
            .padding(.bottom, MemoBookSpacing.l)
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .background(MemoBookColor.background.ignoresSafeArea())
        .brandHiddenNavigationBar()
        // Le crème de la marque ne se retourne pas en sombre — voir
        // `MemoBookColor`.
        .environment(\.colorScheme, .light)
        .task { await model.load() }
        .onChange(of: model.cover?.title) { _, _ in readTexts() }
        .onChange(of: model.face) { _, _ in
            // Changer de plat ferme le champ ouvert : le titre du devant et le
            // texte du dos ne se corrigent pas dans le même champ.
            focus = nil
            readTexts()
        }
        .onAppear(perform: readTexts)
        .brandSheet(isPresented: $isChoosingStats) {
            CoverStatsSheet(model: model)
        }
    }

    // MARK: - Le plat, et ses crayons

    private var plate: some View {
        GeometryReader { proxy in
            let width = min(proxy.size.width, Self.plateWidth)

            Group {
                if let cover = model.cover {
                    CoverPlate(
                        // Le plat lit le **brouillon**, pas la valeur
                        // enregistrée : c'est ce qui fait qu'on voit son titre
                        // se composer pendant qu'on le tape.
                        cover: draft(of: cover),
                        style: model.style(of: cover),
                        photo: model.photo(of: cover),
                        face: model.face,
                        stats: model.face == .back ? model.covers?.statSelection ?? [] : [],
                        width: width,
                        titleBadge: model.face == .front
                            ? AnyView(pencil(BookCopy.Covers.Voice.editTitle) { focus = .title })
                            : nil,
                        // ⚠️ **Le texte de dos n'a pas de crayon**, et c'est la
                        // maquette : « 4 - cover textes verso » n'en pose qu'un,
                        // sur le bandeau des chiffres. On implémente ce qui est
                        // dessiné (R3) plutôt que d'en ajouter un — mais c'est
                        // signalé (T90) : la FAQ promet « titre, visuel et
                        // **texte de dos** », et rien ne permet aujourd'hui de
                        // réécrire celui-ci.
                        subtitleBadge: model.face == .front
                            ? AnyView(
                                pencil(BookCopy.Covers.Voice.editSubtitle) { focus = .subtitle }
                            )
                            : nil,
                        statsBadge: model.face == .back
                            ? AnyView(
                                pencil(BookCopy.Covers.Voice.editStats) { isChoosingStats = true }
                            )
                            : nil
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
        .frame(height: Self.plateWidth / CoverPlate.ratio)
    }

    private static let plateWidth: CGFloat = 260

    /// Le crayon posé sur une zone du plat.
    ///
    /// Il **déborde** du bloc qu'il commande, comme la maquette : posé dedans,
    /// il se serait confondu avec le dessin de la couverture.
    private func pencil(_ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(brand: "IconPen")
                .resizable()
                .renderingMode(.template)
                .scaledToFit()
                .frame(width: MemoBookSpacing.s, height: MemoBookSpacing.s)
                .foregroundStyle(MemoBookColor.action)
                .frame(width: Self.pencilSide, height: Self.pencilSide)
                .background(MemoBookColor.surface, in: .circle)
                .overlay { Circle().strokeBorder(MemoBookColor.outline, lineWidth: 1.5) }
                .brandShadow(.soft)
                // Le dessin fait 32, la cible 44 : R7.
                .frame(
                    width: MemoBookSpacing.minimumTapTarget,
                    height: MemoBookSpacing.minimumTapTarget
                )
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .offset(x: Self.pencilSide / 2, y: -Self.pencilSide / 4)
    }

    private static let pencilSide: CGFloat = 32

    // MARK: - Les champs

    /// Le champ ouvert par un crayon.
    ///
    /// Un seul à la fois, et seulement pendant qu'on écrit : deux champs posés
    /// en permanence auraient fait de cet écran un formulaire avec une vignette,
    /// alors que c'est une couverture avec des crayons.
    ///
    /// Le titre est une **valeur** — un mot, deux au plus — donc un
    /// ``BrandTextField``. Le sous-titre est un **texte** — la signature au
    /// devant, le paragraphe de quatrième au dos — donc un ``BrandTextBox``.
    @ViewBuilder
    private var fields: some View {
        VStack(spacing: MemoBookSpacing.snug) {
            switch focus {
            case .title:
                BrandTextField(
                    BookCopy.Covers.Voice.editTitle,
                    text: $title,
                    field: Field.title,
                    focus: $focus,
                    labelPlacement: .above
                )

            case .subtitle:
                BrandTextBox(
                    BookCopy.Covers.Voice.editSubtitle,
                    text: $subtitle,
                    focus: $isWritingSubtitle,
                    // La signature du devant tient en deux lignes, le texte de
                    // quatrième en dix : le cadre part de la bonne hauteur
                    // plutôt que d'en imposer une aux deux.
                    minimumHeight: model.face == .front ? 72 : 133,
                    lineSpan: model.face == .front ? 2...4 : 4...10
                )

            case nil:
                EmptyView()
            }
        }
        .animation(.snappy(duration: 0.25), value: focus)
        // Les deux focus sont tenus d'accord : `BrandTextBox` porte un booléen
        // là où le reste de l'écran travaille sur l'énumération des champs.
        // Refermer le clavier doit refermer le cadre, sinon il reste ouvert et
        // vide sous le plat.
        .onChange(of: isWritingSubtitle) { _, isWriting in
            if !isWriting, focus == .subtitle { focus = nil }
        }
        .onChange(of: focus) { _, field in
            isWritingSubtitle = field == .subtitle
        }
    }

    // MARK: - Le brouillon

    private func draft(of cover: BookCover) -> BookCover {
        var draft = cover
        draft.title = title
        draft.subtitle = subtitle
        return draft
    }

    private func readTexts() {
        guard let cover = model.cover else { return }
        title = cover.title
        subtitle = cover.subtitle
    }

    private func commit() {
        model.setTexts(title: title, subtitle: subtitle)
    }
}

#Preview("Couvertures — textes") {
    NavigationStack {
        CoverTextsView(model: CoversModel(tripId: "trip-rome"))
    }
}

#Preview("Couvertures — textes — AX3") {
    NavigationStack {
        CoverTextsView(model: CoversModel(tripId: "trip-rome"))
            .environment(\.dynamicTypeSize, .accessibility3)
    }
}
