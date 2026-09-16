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

    /// Le champ **ouvert** par un crayon, s'il y en a un.
    ///
    /// ⚠️ **Distinct du focus, et c'est ce qui manquait.** Le crayon posait
    /// directement `focus = .title` ; or le champ n'existe à l'écran *que*
    /// lorsqu'il est ouvert. SwiftUI ne peut pas donner le focus à une vue qui
    /// n'est pas là : il remettait la valeur à `nil` dans la même passe, le
    /// champ n'apparaissait jamais, et aucun clavier ne montait — un crayon sur
    /// deux ne faisait rien (Hugo, 15/09/2026). On ouvre donc le champ d'abord,
    /// et c'est lui qui prend le focus en apparaissant.
    @State private var editing: Field?

    /// Le focus du champ du titre. Il suit ``editing``, il ne le décide pas.
    @FocusState private var focus: Field?

    /// Le focus du cadre de texte, qui ne connaît qu'un booléen. Tenu d'accord
    /// avec ``editing`` — voir ``fields``.
    @FocusState private var isWritingSubtitle: Bool

    private enum Field: Hashable { case title, subtitle }

    @State private var title = ""
    @State private var subtitle = ""
    @State private var isChoosingStats = false

    /// Le plat sur lequel on vient de taper alors qu'il n'a pas de texte.
    /// `nil` le reste du temps — voir ``CoverFaceTabs``.
    @State private var blockedFace: CoverFace?

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollViewReader { scroller in
            ScrollView {
                VStack(spacing: MemoBookSpacing.s) {
                    BrandScreenHeader(
                        title: BookCopy.Covers.title,
                        subtitle: BookCopy.Covers.textsSubtitle
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)

                    // **Le plat sans texte pâlit dans le rail** (Hugo,
                    // 16/09/2026) : une quatrième de couverture en photo pleine
                    // page n'a rien à écrire, et l'écran n'y proposait aucun
                    // crayon sans jamais dire pourquoi. Le segment reste
                    // tapable et pose l'explication.
                    CoverFaceTabs(
                        face: $model.face,
                        isAvailable: acceptsText,
                        onUnavailable: { blockedFace = $0 }
                    )

                    plate

                    if let blockedFace {
                        BrandNotice(BookCopy.Covers.noTextHere(blockedFace), tone: .information)
                            .transition(.opacity)
                    }

                    fields
                        .id(Self.fieldsAnchor)

                    BrandButton(BookCopy.Covers.validate, fillsWidth: true) {
                        commit()
                        dismiss()
                    }
                    .disabled(model.covers == nil || !acceptsText(model.face))
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
                // Changer de plat ferme le champ ouvert : le titre du devant et
                // le texte du dos ne se corrigent pas dans le même champ. Et
                // l'explication, qui parlait de l'autre plat.
                close()
                readTexts()
                blockedFace = nil
            }
            .animation(.snappy(duration: 0.25), value: blockedFace)
            .onAppear(perform: readTexts)
            .brandSheet(isPresented: $isChoosingStats) {
                CoverStatsSheet(model: model)
            }
            // **Ce qu'on tape ne passe jamais sous le clavier.** Le champ
            // s'ouvre sous le plat, tout en bas de l'écran : sans ça, le
            // clavier montait par-dessus et on écrivait à l'aveugle (Hugo,
            // 16/09/2026). Le défilement automatique du système ne suffit pas
            // ici, parce que le champ n'existe pas encore quand le focus le
            // cherche — il apparaît, puis le prend. On attend donc que le
            // clavier soit monté, et on amène le champ juste au-dessus de lui.
            .onChange(of: editing) { _, field in
                guard field != nil else { return }
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(350))
                    withAnimation(.snappy(duration: 0.3)) {
                        scroller.scrollTo(Self.fieldsAnchor, anchor: .bottom)
                    }
                }
            }
        }
    }

    /// L'identité du bloc des champs, pour l'amener au-dessus du clavier.
    private static let fieldsAnchor = "cover-texts-fields"

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
                            ? AnyView(pencil(BookCopy.Covers.Voice.editTitle) { open(.title) })
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
                                pencil(BookCopy.Covers.Voice.editSubtitle) { open(.subtitle) }
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
            switch editing {
            case .title:
                BrandTextField(
                    BookCopy.Covers.Voice.editTitle,
                    text: $title,
                    field: Field.title,
                    focus: $focus,
                    labelPlacement: .above
                )
                // Le clavier monte **une fois le champ à l'écran** — d'où le
                // passage par `editing`. Une image plus tard, pour que la vue
                // soit bien dans la hiérarchie quand le focus la cherche.
                .onAppear { focusSoon { focus = .title } }

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
                .onAppear { focusSoon { isWritingSubtitle = true } }

            case nil:
                EmptyView()
            }
        }
        .animation(.snappy(duration: 0.25), value: editing)
        // Refermer le clavier referme le champ, sinon il reste ouvert et vide
        // sous le plat. Chaque champ ne referme que **le sien** : quand on passe
        // du titre à la signature, le focus du premier retombe à `nil` pendant
        // que le second s'ouvre, et ce n'est pas une fermeture.
        .onChange(of: focus) { _, field in
            if field == nil, editing == .title { editing = nil }
        }
        .onChange(of: isWritingSubtitle) { _, isWriting in
            if !isWriting, editing == .subtitle { editing = nil }
        }
    }

    /// Ouvre le champ d'un crayon. Un second appui sur le même crayon rend le
    /// focus au champ déjà ouvert plutôt que de le refermer et le rouvrir.
    private func open(_ field: Field) {
        guard editing != field else {
            focusSoon {
                switch field {
                case .title: focus = .title
                case .subtitle: isWritingSubtitle = true
                }
            }
            return
        }
        editing = field
    }

    private func close() {
        focus = nil
        isWritingSubtitle = false
        editing = nil
    }

    /// Donne le focus **après** la passe de rendu en cours : une vue qui vient
    /// d'être insérée ne le prend pas dans la même passe.
    private func focusSoon(_ apply: @escaping @MainActor () -> Void) {
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(60))
            apply()
        }
    }

    /// Ce plat porte-t-il un texte ? Ouvert par défaut : on ne ferme pas un
    /// geste parce qu'on n'a pas encore lu les couvertures.
    private func acceptsText(_ face: CoverFace) -> Bool {
        model.covers?.acceptsText(on: face) ?? true
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
