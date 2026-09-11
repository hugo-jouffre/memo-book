import MemoBookCore
import MemoBookDesign
import SwiftUI

/// L'aperçu **plein cadre** : la page occupe tout ce que l'écran peut lui
/// donner, et le reste se pose dessus.
///
/// Ce n'est pas un écran de plus mais un mode de l'aperçu — d'où le fait qu'il
/// n'ait pas sa propre entrée dans ``HomeRoute`` : la flèche de retour doit
/// ramener au voyage, pas à la version réduite. C'est le rond `normal_screen`,
/// en haut à gauche de la page, qui revient en arrière.
///
/// Trois choses le distinguent du mode réduit, et toutes les trois viennent de
/// la maquette :
///
/// 1. **La page déborde la marge d'écran.** C'est le seul endroit de l'app où
///    quelque chose sort de la colonne, et c'est ce qui fait le plein écran.
/// 2. **Les commandes flottent sur la page** au lieu d'être posées dessous.
/// 3. **La bande de miniatures** remplace l'indicateur : en plein écran on
///    saute d'une page à l'autre, on ne les tourne plus une par une.
struct BookFullScreenView: View {
    let model: BookPreviewModel
    let onShare: () -> Void

    @Environment(\.displayScale) private var displayScale

    var body: some View {
        VStack(spacing: MemoBookSpacing.xs) {
            header
            page
            filmstrip
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    // MARK: L'en-tête

    /// Le même en-tête que le mode réduit, au filet près : la maquette lui
    /// ajoute une ligne de séparation en bas, parce que la page qui suit monte
    /// jusqu'à lui.
    private var header: some View {
        BrandScreenHeader(
            title: BookCopy.Preview.title,
            subtitle: BookCopy.Preview.subtitle(
                title: model.preview?.title ?? "",
                pages: model.sheetCount
            )
        ) {
            BrandHeaderAction(
                icon: "IconTeleverser",
                label: BookCopy.Preview.Voice.share,
                action: onShare
            )
        }
        .padding(.horizontal, MemoBookSpacing.screenMargin)
        .padding(.top, MemoBookSpacing.xs)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(MemoBookColor.hairline)
                .frame(height: 1)
                .accessibilityHidden(true)
        }
    }

    // MARK: La page

    /// La page, et tout ce qui flotte dessus.
    ///
    /// Elle occupe la hauteur restante et déborde la marge d'écran des deux
    /// côtés — c'est ce que la maquette dessine (420 pt de large sur un écran
    /// de 390). Le débordement passe par une marge **négative** plutôt que par
    /// une largeur en dur : celle-ci aurait figé le dessin à un modèle
    /// d'iPhone.
    private var page: some View {
        ZStack {
            BookSheetImage(renderer: model.renderer, index: model.sheetIndex)
                .id(model.sheetIndex)
                .transition(.opacity)
                .animation(.easeInOut(duration: 0.18), value: model.sheetIndex)

            if model.isOnConfigurableCover {
                Color.black.opacity(0.4)
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, -MemoBookSpacing.snug)
        .clipped()
        .overlay(alignment: .top) { topControls }
        .overlay(alignment: .bottom) { pager }
        // Le glissé horizontal tourne les pages. C'est le geste qu'on essaie
        // d'abord sur une image plein écran, et le seul qui ne demande pas de
        // viser une commande.
        .gesture(pageSwipe)
        .task(id: model.sheetIndex) {
            model.renderer.prepare(around: model.sheetIndex, width: 420 * displayScale)
        }
        .animation(.easeInOut(duration: 0.2), value: model.isOnConfigurableCover)
    }

    /// Le retour au mode réduit, et le compteur de feuilles.
    private var topControls: some View {
        HStack {
            BookScreenModeButton(
                icon: "IconNormalScreen",
                label: BookCopy.Preview.Voice.exitFullScreen,
                action: { model.setFullScreen(false) }
            )

            Spacer(minLength: 0)

            Text(BookCopy.Preview.sheetIndicator(model.sheetIndex + 1, of: max(model.sheetCount, 1)))
                .font(MemoBookFont.bodySemibold)
                .foregroundStyle(MemoBookColor.inkSecondary)
                .monospacedDigit()
                .padding(.horizontal, MemoBookSpacing.xs)
                .padding(.vertical, MemoBookSpacing.xs / 2)
                // Le gris système et non le crème de la marque : la pastille
                // est posée sur une photo dont on ne choisit pas les couleurs,
                // et c'est le matériau qui la rend lisible partout. Relevé sur
                // la maquette (`Grays/Gray 6`).
                .background(.thinMaterial, in: .rect(cornerRadius: MemoBookSpacing.snug))
        }
        .padding(.horizontal, MemoBookSpacing.snug)
        .padding(.top, MemoBookSpacing.xs)
    }

    /// La barre de pagination posée en bas de la page : trois pastilles bleues
    /// sur un voile crème, comme la maquette.
    private var pager: some View {
        HStack {
            pagerArrow(.backward, isEnabled: model.canGoBack, action: model.goBack)
            Spacer(minLength: 0)

            Text(BookCopy.Preview.pageIndicator(model.sheetIndex + 1, of: max(model.sheetCount, 1)))
                .font(MemoBookFont.body)
                .foregroundStyle(MemoBookColor.ink)
                .monospacedDigit()
                .contentTransition(.numericText())
                .animation(.snappy(duration: 0.2), value: model.sheetIndex)
                .padding(.horizontal, MemoBookSpacing.snug)
                .padding(.vertical, MemoBookSpacing.xs)
                .background(MemoBookColor.outline, in: .capsule)

            Spacer(minLength: 0)
            pagerArrow(.forward, isEnabled: model.canGoForward, action: model.goForward)
        }
        .padding(.horizontal, MemoBookSpacing.s)
        .padding(.vertical, MemoBookSpacing.xs)
        // Le voile crème de la maquette : la barre doit rester lisible sur une
        // photo pleine page sans la masquer.
        .background(MemoBookColor.background.opacity(0.7))
    }

    private func pagerArrow(
        _ direction: BookPageArrow.Direction,
        isEnabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(brand: "IconChevron")
                .resizable()
                .renderingMode(.template)
                .scaledToFit()
                .rotationEffect(.degrees(direction == .backward ? 180 : 0))
                .frame(width: MemoBookSpacing.snug, height: MemoBookSpacing.snug)
                .foregroundStyle(MemoBookColor.ink)
                .padding(.horizontal, MemoBookSpacing.snug)
                .padding(.vertical, MemoBookSpacing.xs + 1)
                .background(MemoBookColor.outline.opacity(isEnabled ? 1 : 0.5), in: .capsule)
                .frame(minWidth: MemoBookSpacing.minimumTapTarget, minHeight: MemoBookSpacing.minimumTapTarget)
                .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .accessibilityLabel(
            direction == .backward
                ? BookCopy.Preview.Voice.previousPage
                : BookCopy.Preview.Voice.nextPage
        )
    }

    /// Tourner la page d'un glissé.
    ///
    /// Le seuil est franc — 50 pt — et le geste doit rester horizontal : sans
    /// ces deux conditions, remonter l'écran d'un doigt un peu de travers
    /// changerait de page.
    private var pageSwipe: some Gesture {
        DragGesture(minimumDistance: 20)
            .onEnded { drag in
                let horizontal = drag.translation.width
                guard abs(horizontal) > 50,
                    abs(horizontal) > abs(drag.translation.height) * 1.5
                else { return }

                withAnimation(.snappy(duration: 0.25)) {
                    if horizontal < 0 { model.goForward() } else { model.goBack() }
                }
            }
    }

    // MARK: La bande de miniatures

    /// Toutes les feuilles du carnet, en petit, pour sauter n'importe où.
    ///
    /// La feuille courante est **plus haute** que les autres — c'est ce que
    /// dessine la maquette (65 contre 59) — et c'est ce qui la désigne sans
    /// avoir besoin d'un cadre de sélection.
    ///
    /// `LazyHStack` : un carnet de soixante pages ne rend que les miniatures
    /// visibles, pas les soixante.
    private var filmstrip: some View {
        ScrollViewReader { scroller in
            ScrollView(.horizontal) {
                LazyHStack(spacing: MemoBookSpacing.xs / 2) {
                    ForEach(0..<max(model.sheetCount, 0), id: \.self) { index in
                        thumbnail(index)
                            .id(index)
                    }
                }
                .padding(.horizontal, MemoBookSpacing.screenMargin)
            }
            .scrollIndicators(.hidden)
            .frame(height: Self.currentThumbnailHeight)
            .onChange(of: model.sheetIndex) { _, index in
                // La bande suit la page : tourner avec les flèches doit amener
                // la miniature correspondante sous les yeux.
                withAnimation(.snappy(duration: 0.3)) {
                    scroller.scrollTo(index, anchor: .center)
                }
            }
        }
    }

    private static let currentThumbnailHeight: CGFloat = 66
    private static let thumbnailHeight: CGFloat = 60

    private func thumbnail(_ index: Int) -> some View {
        let isCurrent = index == model.sheetIndex
        let height = isCurrent ? Self.currentThumbnailHeight : Self.thumbnailHeight

        return Button {
            withAnimation(.snappy(duration: 0.25)) { model.show(sheet: index) }
        } label: {
            BookSheetImage(renderer: model.renderer, index: index)
                .aspectRatio(model.renderer.aspectRatio, contentMode: .fit)
                .frame(height: height)
                .clipShape(.rect(cornerRadius: 2))
                .overlay {
                    RoundedRectangle(cornerRadius: 2)
                        .strokeBorder(
                            isCurrent ? MemoBookColor.action : MemoBookColor.hairline,
                            lineWidth: isCurrent ? 1.5 : 1
                        )
                }
                // La cible tactile est plus large que la miniature : une page
                // de 42 pt de large ne se vise pas au doigt (R7).
                .frame(minWidth: MemoBookSpacing.minimumTapTarget)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(BookCopy.Preview.pageIndicator(index + 1, of: max(model.sheetCount, 1)))
        .accessibilityAddTraits(isCurrent ? [.isButton, .isSelected] : .isButton)
    }
}
