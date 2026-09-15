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

    /// La feuille ouverte, s'il y en a une. Cinq des dix lignes de l'écran en
    /// ouvrent une désormais ; les autres remontent toujours une intention à
    /// ``RootView``, qui seul tient la pile.
    @State private var sheet: TripSettingsSheet?

    /// La feuille qui confirme la suppression du voyage — une feuille de
    /// l'app, comme celle du compte, et non une alerte : le paragraphe qui dit
    /// ce qui part mérite sa place.
    @State private var isConfirmingDeletion = false

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
                    // Le constat, le conseil, et les deux gestes : réessayer,
                    // ou nous écrire. Un 500 nu disait « Erreur interne du
                    // serveur » et rien d'autre (Hugo, 15/09/2026).
                    ErrorBanner(
                        message: message,
                        advice: model.errorAdvice,
                        retry: { Task { await model.load() } },
                        help: { onIntent(.openHelp) }
                    )
                }

                helpLink
                deleteLink

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
        .brandSheet(item: $sheet) { destination in
            switch destination {
            case .dates: TripDatesSheet(model: model)
            case .pace: TripPaceSheet(model: model)
            case .notifications: TripNotificationsSheet(model: model)
            case .theme: TripThemeSheet(model: model)
            case .companions: TripInviteSheet(model: model)
            }
        }
        .brandSheet(isPresented: $isConfirmingDeletion) {
            DeleteTripSheet(
                tripName: model.settings?.name ?? "",
                isDeleting: model.isDeleting,
                errorMessage: model.errorMessage,
                onKeep: { isConfirmingDeletion = false },
                onDelete: {
                    Task {
                        // Le voyage n'existe plus : l'app ne peut que revenir
                        // à l'accueil, et c'est `RootView` qui vide la pile.
                        if await model.delete() {
                            isConfirmingDeletion = false
                            onIntent(.tripDeleted)
                        }
                    }
                }
            )
        }
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
                    valueTone: .prominent,
                    isValueLoading: isLoading,
                    action: { onIntent(.renameTrip) }
                )
            }

            BrandRowGroup {
                BrandRow(
                    BookCopy.Settings.wallet,
                    value: settings?.walletBalance.euros,
                    valueTone: .prominent,
                    isValueLoading: isLoading,
                    action: { onIntent(.openWallet) }
                )
            }

            BrandRowGroup {
                BrandRow(
                    BookCopy.Settings.dates,
                    value: settings?.dateRangeLabel ?? BookCopy.Settings.noValue,
                    isValueLoading: isLoading,
                    action: { sheet = .dates }
                )
                BrandRow(
                    BookCopy.Settings.pace,
                    value: settings?.narrationPace?.displayName ?? BookCopy.Settings.noValue,
                    isValueLoading: isLoading,
                    action: { sheet = .pace }
                )
                BrandRow(BookCopy.Settings.notifications, isOn: notificationsBinding)
                BrandRow(BookCopy.Settings.manageNotifications) { sheet = .notifications }
                BrandRow(
                    BookCopy.Settings.companions,
                    value: settings?.companionsLabel ?? BookCopy.Settings.noValue,
                    isValueLoading: isLoading,
                    action: { sheet = .companions }
                )
            }
            // Le groupe attend **le temps de la lecture**, et pas plus : les
            // interrupteurs agissent, et les basculer sur des réglages pas
            // encore lus enverrait un état qu'on n'a pas. Mais une lecture qui a
            // échoué ne doit pas geler l'écran — les lignes rouvraient leurs
            // feuilles quand même, elles ne le pouvaient plus derrière un 500
            // (Hugo, 15/09/2026) ; une bascule sans réglages, elle, reste sans
            // effet (le modèle la refuse).
            .disabled(model.isLoading)

            BrandRowGroup {
                BrandRow(
                    BookCopy.Settings.theme,
                    value: settings?.theme ?? BookCopy.Settings.noValue,
                    isValueLoading: isLoading,
                    action: { sheet = .theme }
                )
                BrandRow(BookCopy.Settings.publicGallery, isOn: galleryBinding)
            }
            .disabled(model.isLoading)

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

            // « Commander le carnet » ouvre le tunnel de commande, toujours :
            // c'est lui qui sait dire s'il y a un carnet à imprimer, et une
            // ligne qui ne mène nulle part se lit comme une ligne cassée (Hugo,
            // 15/09/2026). Elle attendait un `isPrintable` que l'écran ne peut
            // pas lire quand les réglages ne chargent pas.
            BrandRowGroup {
                BrandRow(BookCopy.Settings.order) { onIntent(.orderBook) }
            }
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

    /// « Supprimer ce voyage », tout en bas — le même dessin que « Supprimer
    /// mon compte » sur le profil : une croix rouge et un mot, centrés, sans
    /// carte ni bouton plein. On ne met pas en avant la porte de sortie, mais
    /// elle existe (Hugo, 15/09/2026). La confirmation est dans la feuille ;
    /// après elle, il n'y a plus rien à annuler.
    private var deleteLink: some View {
        Button {
            isConfirmingDeletion = true
        } label: {
            HStack(spacing: MemoBookSpacing.xs) {
                Image(brand: "IconCross")
                    .resizable()
                    .renderingMode(.template)
                    .scaledToFit()
                    .frame(width: MemoBookSpacing.contentIcon, height: MemoBookSpacing.contentIcon)
                Text(BookCopy.Settings.delete)
                    .font(MemoBookFont.button)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(MemoBookColor.error)
            .frame(maxWidth: .infinity, minHeight: MemoBookSpacing.minimumTapTarget)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(model.isDeleting)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
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

/// Ce que les paramètres d'un voyage demandent à l'app d'**ouvrir ailleurs**.
///
/// L'écran ne pousse rien lui-même : ``RootView`` seul tient la pile de
/// navigation, comme pour l'accueil et le voyage.
///
/// Cinq intentions ont disparu de cette liste — dates, rythme, notifications,
/// co-voyageurs, thème — parce qu'elles ne mènent plus ailleurs : elles ouvrent
/// une feuille **sur** cet écran (``TripSettingsSheet``). Une intention qui
/// remonte pour redescendre aussitôt n'apprend rien à personne.
public enum TripSettingsIntent: Sendable, Hashable {
    case renameTrip
    case openWallet
    /// « Style du carnet » — les personnalisations de la mise en page.
    case openCustomisation
    case connectTricount
    case openBookPreview
    /// « Commander le carnet » — le tunnel de commande, en sept étapes.
    case orderBook
    case openHelp
    /// Le voyage vient d'être supprimé : il n'y a plus rien à afficher ici, et
    /// l'app revient à l'accueil.
    case tripDeleted
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

    /// Le logo de Tricount, tel que Tricount le dessine (`assets/logos/Tricount
    /// Icon.png`, importé par `import-brand-logos.py`). Il a longtemps été un
    /// « tt » dans le bleu de la marque, faute d'asset — Hugo l'a déposé le
    /// 15/09/2026, ce qui clôt T73. Jamais en `renderingMode(.template)` : c'est
    /// la marque d'un tiers, elle garde ses couleurs.
    private var mark: some View {
        Image(brand: "LogoTricount")
            .resizable()
            .scaledToFit()
            .frame(width: markSide, height: markSide)
            .clipShape(.rect(cornerRadius: MemoBookSpacing.xs))
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
