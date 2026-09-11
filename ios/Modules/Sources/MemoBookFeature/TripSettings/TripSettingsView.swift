import MemoBookCore
import MemoBookDesign
import SwiftUI

/// Les paramètres d'un voyage : tout ce qui se règle sur le carnet sans quitter
/// le voyage.
///
/// On y arrive par la roue crantée, posée au même endroit sur les deux écrans
/// du voyage — son accueil et la conversation. C'est voulu : les réglages
/// appartiennent au **voyage**, pas à l'écran depuis lequel on les ouvre.
///
/// **L'écran ne contient aucun contenu.** Nom, dates, rythme, co-voyageurs,
/// solde : tout vient du ``TripSettings`` que porte ``TripSettingsModel``. Ce
/// qui est écrit ici, ce sont les intitulés — et ils viennent tous de
/// ``BookCopy/Settings``.
///
/// **Il ne navigue pas.** Les lignes ouvrent des feuilles ou remontent une
/// intention à ``RootView``, qui seul tient la pile.
public struct TripSettingsView: View {
    private let onIntent: (TripSettingsIntent) -> Void

    @State private var model: TripSettingsModel

    @Environment(\.dismiss) private var dismiss

    public init(
        model: TripSettingsModel,
        onIntent: @escaping (TripSettingsIntent) -> Void
    ) {
        _model = State(initialValue: model)
        self.onIntent = onIntent
    }

    public var body: some View {
        ScrollView {
            // **L'écran se dessine tout de suite, entier.** Il n'attend rien de
            // tout ça : ses intitulés, ses groupes et ses lignes appartiennent à
            // l'app. Seules les valeurs viennent du réseau, et elles seules
            // portent une barre d'attente — voir ``BrandSkeleton``.
            VStack(alignment: .leading, spacing: MemoBookSpacing.m) {
                BrandScreenHeader(title: BookCopy.Settings.title)

                adventureSection
                quickAccessSection

                if let message = model.errorMessage {
                    ErrorBanner(message: message) {
                        Task { await model.load() }
                    }
                }

                helpLink

                #if DEBUG
                    TripSettingsDebugPanel(model: model)
                #endif
            }
            // Les valeurs se posent en douceur quand elles arrivent, au lieu de
            // remplacer les barres d'attente d'un coup sec.
            .animation(.snappy(duration: 0.25), value: model.settings == nil)
            .padding(.horizontal, MemoBookSpacing.screenMargin)
            .padding(.top, MemoBookSpacing.xs)
            .padding(.bottom, MemoBookSpacing.l)
        }
        .scrollIndicators(.hidden)
        .background(MemoBookColor.background.ignoresSafeArea())
        // L'écran dessine son propre en-tête, comme la maquette : la flèche et
        // le titre partagent une ligne, à la marge de la colonne.
        .brandHiddenNavigationBar()
        // Le crème de la marque ne se retourne pas en sombre — voir
        // `MemoBookColor`.
        .environment(\.colorScheme, .light)
        .task { await model.load() }
    }

    // MARK: - Gère ton aventure

    private var adventureSection: some View {
        let settings = model.settings
        let isLoading = model.isLoading

        return VStack(alignment: .leading, spacing: MemoBookSpacing.snug) {
            sectionTitle(BookCopy.Settings.adventureSection)

            // Le nom et la cagnotte ont **chacun leur carte**, et ce n'est pas
            // un oubli de la maquette : ce sont les deux seules lignes de
            // l'écran qui portent une valeur qu'on vient chercher du regard.
            // Les fondre dans le groupe qui suit les aurait rangées parmi les
            // réglages, alors qu'elles n'en sont pas.
            BrandRowGroup {
                BrandRow(
                    BookCopy.Settings.name,
                    value: settings?.name,
                    isValueProminent: true,
                    isValueLoading: isLoading,
                    action: { onIntent(.renameTrip) }
                )
            }

            BrandRowGroup {
                BrandRow(
                    BookCopy.Settings.wallet,
                    value: settings?.walletBalance.euros,
                    isValueProminent: true,
                    isValueLoading: isLoading,
                    action: { onIntent(.openWallet) }
                )
            }

            BrandRowGroup {
                BrandRow(
                    BookCopy.Settings.dates,
                    value: settings?.dateRangeLabel ?? BookCopy.Settings.noValue,
                    isValueLoading: isLoading,
                    action: { onIntent(.editDates) }
                )
                BrandRow(
                    BookCopy.Settings.pace,
                    value: settings?.narrationPace?.displayName ?? BookCopy.Settings.noValue,
                    isValueLoading: isLoading,
                    action: { onIntent(.editPace) }
                )
                BrandRow(BookCopy.Settings.notifications, isOn: notificationsBinding)
                BrandRow(BookCopy.Settings.manageNotifications) { onIntent(.manageNotifications) }
                BrandRow(
                    BookCopy.Settings.companions,
                    value: settings?.companionsLabel ?? BookCopy.Settings.noValue,
                    isValueLoading: isLoading,
                    action: { onIntent(.editCompanions) }
                )
            }
            // Les interrupteurs sont les seuls contrôles du groupe qui
            // **agissent** avant que la valeur soit là : les basculer sur des
            // réglages pas encore lus enverrait un état qu'on n'a pas. Le
            // groupe entier attend, ce qui ne coûte rien — les autres lignes ne
            // font qu'ouvrir des feuilles.
            .disabled(settings == nil)

            BrandRowGroup {
                BrandRow(
                    BookCopy.Settings.theme,
                    value: settings?.theme ?? BookCopy.Settings.noValue,
                    isValueLoading: isLoading,
                    action: { onIntent(.editTheme) }
                )
                BrandRow(BookCopy.Settings.publicGallery, isOn: galleryBinding)
            }
            .disabled(settings == nil)

            BrandRowGroup {
                BrandRow(
                    BookCopy.Settings.style,
                    value: settings?.styleSummary ?? BookCopy.Settings.noValue,
                    isValueLoading: isLoading,
                    action: { onIntent(.openCustomisation) }
                )
            }

            TricountCallout(
                connected: settings?.tricountLabel,
                isLoading: isLoading,
                action: { onIntent(.connectTricount) }
            )
        }
    }

    // MARK: - Accès rapide

    private var quickAccessSection: some View {
        let settings = model.settings

        return VStack(alignment: .leading, spacing: MemoBookSpacing.snug) {
            sectionTitle(BookCopy.Settings.quickAccessSection)

            PdfPreviewRow(
                coverUrl: settings?.previewCoverUrl,
                isLoading: model.isLoading,
                action: { onIntent(.openBookPreview) }
            )

            BrandRowGroup {
                BrandRow(BookCopy.Settings.order) { onIntent(.orderBook) }
            }
            // Rien à imprimer tant que le carnet n'a pas été composé. La ligne
            // reste lisible — elle dit ce qui viendra — mais ne mène nulle part.
            .disabled(!(settings?.isPrintable ?? false))
        }
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(MemoBookFont.sectionOverline)
            .foregroundStyle(MemoBookColor.inkMuted)
            .textCase(.uppercase)
            .accessibilityAddTraits(.isHeader)
    }

    private var helpLink: some View {
        BrandButton(
            BookCopy.Settings.help,
            style: .link,
            isSubdued: true,
            fillsWidth: true
        ) {
            onIntent(.openHelp)
        }
    }

    // MARK: - Les deux interrupteurs

    /// Les liaisons passent par le modèle et non par `settings` : une vue ne
    /// doit pas pouvoir poser une valeur sans qu'elle partie au serveur.
    private var notificationsBinding: Binding<Bool> {
        Binding(
            get: { model.settings?.wantsNotifications ?? false },
            set: { model.setNotifications($0) }
        )
    }

    private var galleryBinding: Binding<Bool> {
        Binding(
            get: { model.settings?.isPublicGallery ?? false },
            set: { model.setPublicGallery($0) }
        )
    }
}

/// Ce que les paramètres d'un voyage demandent à l'app d'ouvrir.
///
/// L'écran ne pousse rien lui-même : ``RootView`` seul tient la pile de
/// navigation, comme pour l'accueil et le voyage.
public enum TripSettingsIntent: Sendable, Hashable {
    case renameTrip
    case openWallet
    case editDates
    case editPace
    case manageNotifications
    case editCompanions
    case editTheme
    /// « Style du carnet » — les personnalisations de la mise en page.
    case openCustomisation
    case connectTricount
    case openBookPreview
    case orderBook
    case openHelp
}

// MARK: - Les blocs qui ne sont pas des lignes

/// L'invitation à relier son Tricount : une carte à trois étages — le
/// pictogramme, ce que ça apporte, et le chevron.
///
/// Ce n'est pas une ``BrandRow`` parce que son texte fait deux lignes et porte
/// une explication, pas une valeur. Une ligne de réglage qui explique n'est plus
/// une ligne de réglage.
private struct TricountCallout: View {
    let connected: String?
    let isLoading: Bool
    let action: () -> Void

    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .body) private var markSide: CGFloat = MemoBookSpacing.l

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: MemoBookSpacing.largeCornerRadius)

        return Button(action: action) {
            content
                .padding(MemoBookSpacing.s)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(MemoBookColor.surface, in: shape)
                .overlay { shape.strokeBorder(MemoBookColor.hairline, lineWidth: 1) }
                .contentShape(shape)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }

    /// En taille accessible, le pictogramme passe au-dessus du texte : lui
    /// garder une colonne ne laisserait au titre que deux mots de large.
    @ViewBuilder
    private var content: some View {
        if typeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: MemoBookSpacing.snug) {
                mark
                text
            }
        } else {
            HStack(spacing: MemoBookSpacing.snug) {
                mark
                text
                Spacer(minLength: MemoBookSpacing.xs)
                BrandChevron()
            }
        }
    }

    /// Le « tt » de Tricount n'est pas une icône de la marque et n'a pas à
    /// entrer dans son catalogue : c'est le logo d'un service tiers, dessiné
    /// par lui. En attendant l'asset officiel, ses deux lettres dans le bleu de
    /// MemoBook — écart signalé dans la fiche écran.
    private var mark: some View {
        Text("tt")
            .font(MemoBookFont.bodySemibold)
            .foregroundStyle(MemoBookColor.blueText)
            .frame(width: markSide, height: markSide)
            .background(MemoBookColor.outline.opacity(0.35), in: .rect(cornerRadius: MemoBookSpacing.xs))
            .accessibilityHidden(true)
    }

    private var text: some View {
        VStack(alignment: .leading, spacing: MemoBookSpacing.xs / 2) {
            Text(connected ?? BookCopy.Settings.tricountTitle)
                .font(MemoBookFont.bodySemibold)
                .foregroundStyle(MemoBookColor.ink)

            if isLoading {
                BrandSkeleton()
            } else {
                Text(BookCopy.Settings.tricountMessage)
                    .font(MemoBookFont.caption)
                    .foregroundStyle(MemoBookColor.inkMuted)
            }
        }
        .multilineTextAlignment(.leading)
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// La ligne « Prévisulation PDF » : l'intitulé, sa précision, et la couverture
/// du carnet en vignette.
private struct PdfPreviewRow: View {
    let coverUrl: URL?
    let isLoading: Bool
    let action: () -> Void

    /// La vignette garde le rapport d'une page A5 — c'est le format du carnet
    /// (voir `templates/travel-journal/print.json`). Fixe, hors Dynamic Type :
    /// une image n'est pas du texte.
    private static let thumbnailWidth: CGFloat = 56
    private static let thumbnailRatio: CGFloat = 1.414

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: MemoBookSpacing.largeCornerRadius)

        return Button(action: action) {
            HStack(spacing: MemoBookSpacing.snug) {
                VStack(alignment: .leading, spacing: MemoBookSpacing.xs / 2) {
                    Text(BookCopy.Settings.pdfPreview)
                        .font(MemoBookFont.body)
                        .foregroundStyle(MemoBookColor.ink)
                    Text(BookCopy.Settings.pdfPreviewDetail)
                        .font(MemoBookFont.caption)
                        .foregroundStyle(MemoBookColor.inkMuted)
                }
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: MemoBookSpacing.xs)

                thumbnail
                BrandChevron()
            }
            .padding(.horizontal, MemoBookSpacing.s)
            .padding(.vertical, MemoBookSpacing.snug)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(MemoBookColor.surface, in: shape)
            .overlay { shape.strokeBorder(MemoBookColor.hairline, lineWidth: 1) }
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel("\(BookCopy.Settings.pdfPreview). \(BookCopy.Settings.pdfPreviewDetail)")
    }

    private var thumbnail: some View {
        let height = Self.thumbnailWidth * Self.thumbnailRatio

        return Group {
            if isLoading {
                BrandSkeleton(
                    width: Self.thumbnailWidth,
                    height: height,
                    cornerRadius: MemoBookSpacing.pageCornerRadius
                )
            } else {
                AsyncImage(url: coverUrl) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFill()
                    } else {
                        // Rien de composé encore : le papier du carnet, vide.
                        // Pas un gris système — ce serait un champ désactivé.
                        MemoBookColor.paper
                            .overlay {
                                Image(brand: "IconBookSimple")
                                    .resizable()
                                    .renderingMode(.template)
                                    .scaledToFit()
                                    .frame(width: MemoBookSpacing.m)
                                    .foregroundStyle(MemoBookColor.inkFaint)
                            }
                    }
                }
                .frame(width: Self.thumbnailWidth, height: height)
                .clipShape(.rect(cornerRadius: MemoBookSpacing.pageCornerRadius))
                .overlay {
                    RoundedRectangle(cornerRadius: MemoBookSpacing.pageCornerRadius)
                        .strokeBorder(MemoBookColor.hairline, lineWidth: 1)
                }
            }
        }
        .accessibilityHidden(true)
    }
}

/// Le chevron de bout de ligne, à la taille et à la couleur des lignes de
/// réglages.
///
/// Il vit ici et non dans ``BrandRowGroup`` parce que trois blocs de cet écran
/// ne sont pas des lignes de réglage — la carte, l'aperçu PDF, le Tricount — et
/// doivent pourtant porter le même chevron qu'elles.
struct BrandChevron: View {
    @ScaledMetric(relativeTo: .body) private var side: CGFloat = 22

    var body: some View {
        Image(brand: "IconChevron")
            .resizable()
            .renderingMode(.template)
            .scaledToFit()
            .frame(width: side, height: side)
            .foregroundStyle(MemoBookColor.inkMuted)
            .accessibilityHidden(true)
    }
}

#Preview("Paramètres du voyage") {
    NavigationStack {
        TripSettingsView(model: TripSettingsModel(tripId: "preview")) { _ in }
    }
}

#Preview("Paramètres — valeurs en route") {
    NavigationStack {
        TripSettingsView(
            model: TripSettingsModel(
                tripId: "preview",
                // Une source qui ne répond jamais : c'est l'état de chargement,
                // celui que la maquette ne dessine pas et que R11 réclame.
                source: { _ in
                    try await Task.sleep(for: .seconds(3600))
                    return .fixture
                }
            )
        ) { _ in }
    }
}

#Preview("Paramètres — AX3") {
    NavigationStack {
        TripSettingsView(model: TripSettingsModel(tripId: "preview")) { _ in }
    }
    .environment(\.dynamicTypeSize, .accessibility3)
}
