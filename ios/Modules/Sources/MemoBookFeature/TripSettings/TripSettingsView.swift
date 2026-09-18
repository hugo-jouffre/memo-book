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

    /// La confirmation avant d'effacer la conversation. Une seconde feuille
    /// et non un second temps de la première : les deux gestes ne se suivent
    /// jamais, et chacun a sa porte.
    @State private var isConfirmingConversationClearing = false

    @Environment(\.dismiss) private var dismiss

    /// - Parameter opening: la feuille à ouvrir dès l'arrivée — celle des
    ///   co-voyageurs quand on vient du « + » de l'accueil du voyage. `nil`
    ///   depuis la roue crantée.
    public init(
        model: TripSettingsModel,
        opening: TripSettingsSheet? = nil,
        onIntent: @escaping (TripSettingsIntent) -> Void
    ) {
        _model = State(initialValue: model)
        _sheet = State(initialValue: opening)
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
                clearConversationLink
                deleteLink

                #if DEBUG
                    TripSettingsDebugPanel(model: model)
                #endif
            }
            // Les valeurs se posent en douceur quand elles arrivent, au lieu de
            // remplacer les barres d'attente d'un coup sec.
            .animation(.snappy(duration: 0.25), value: model.settings == nil)
            // **Et quand elles changent, ça se voit.** L'écran s'ouvre sur ce
            // qu'on avait en cache ; si le serveur dit autre chose, trente
            // valeurs bougent en silence sous les yeux de quelqu'un qui lisait.
            // Le balayage et la pastille le disent — voir `BrandRefreshFlash`.
            .brandRefreshFlash(model.freshness.isUpdated)
            // Les valeurs elles-mêmes se remplacent en fondu chiffré plutôt que
            // d'un coup : c'est ce qui rend le changement lisible au lieu de le
            // rendre surprenant.
            .animation(.smooth(duration: 0.35), value: model.settings)
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
            case .memory: MemoryAllowanceSheet(model: model)
            }
        }
        .brandSheet(isPresented: $isConfirmingConversationClearing) {
            ClearConversationSheet(
                isClearing: model.isClearingConversation,
                errorMessage: model.errorMessage,
                onKeep: { isConfirmingConversationClearing = false },
                onClear: {
                    Task {
                        // On reste sur les réglages : c'est le fil, en
                        // dessous dans la pile, qui se vide — et c'est lui
                        // qu'on retrouve en revenant.
                        if await model.clearConversation() {
                            isConfirmingConversationClearing = false
                        }
                    }
                }
            )
        }
        .brandSheet(isPresented: $isConfirmingDeletion) {
            DeleteTripSheet(
                tripName: model.settings?.name,
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
            // Le nom se corrige **sur la ligne**, comme le téléphone du profil :
            // toucher ouvre le clavier, sortir du champ enregistre, la coche
            // verte accuse réception (Hugo, 18/09/2026). Il menait avant à une
            // intention que personne ne routait — la ligne s'ouvrait sur rien.
            BrandRowGroup {
                BrandRow(
                    BookCopy.Settings.name,
                    text: nameBinding,
                    isValueLoading: isLoading,
                    isConfirmed: model.justSaved == .name
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

            // **Les limites de souvenirs, et cet écran seul** (Hugo,
            // 16/09/2026). Elles appartiennent au compte comme la cagnotte
            // juste au-dessus, et n'apparaissent nulle part ailleurs : c'est un
            // garde-fou, pas un décompte qu'on suit. Quelqu'un qui raconte
            // normalement ne doit jamais avoir à y penser — d'où la ligne
            // discrète, et la jauge seulement quand elle commence à compter.
            if let memory = settings?.memory {
                MemoryAllowanceRow(memory: memory) { sheet = .memory }
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

    /// « Supprimer la conversation », juste au-dessus du voyage — à l'encre et
    /// avec la bulle, sur le dessin de « Me déconnecter » : c'est un geste qui
    /// se rattrape moins qu'un réglage et plus qu'une suppression de voyage,
    /// et deux croix rouges l'une sur l'autre auraient dit deux fois la même
    /// chose (Hugo, 17/09/2026).
    private var clearConversationLink: some View {
        exitLink(
            icon: "IconBubble",
            title: BookCopy.Settings.clearConversation,
            tint: MemoBookColor.ink
        ) {
            isConfirmingConversationClearing = true
        }
        .disabled(model.isClearingConversation)
    }

    /// « Supprimer ce voyage », tout en bas — le même dessin que « Supprimer
    /// mon compte » sur le profil : une croix rouge et un mot, centrés, sans
    /// carte ni bouton plein. On ne met pas en avant la porte de sortie, mais
    /// elle existe (Hugo, 15/09/2026). La confirmation est dans la feuille ;
    /// après elle, il n'y a plus rien à annuler.
    private var deleteLink: some View {
        exitLink(icon: "IconCross", title: BookCopy.Settings.delete, tint: MemoBookColor.error) {
            isConfirmingDeletion = true
        }
        .disabled(model.isDeleting)
    }

    /// Le dessin commun des deux portes de sortie : une icône et un mot,
    /// centrés, sans carte ni bouton plein — celui des actions de sortie du
    /// profil.
    private func exitLink(icon: String, title: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: MemoBookSpacing.xs) {
                Image(brand: icon)
                    .resizable()
                    .renderingMode(.template)
                    .scaledToFit()
                    .frame(width: MemoBookSpacing.contentIcon, height: MemoBookSpacing.contentIcon)
                Text(title)
                    .font(MemoBookFont.button)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(tint)
            .frame(maxWidth: .infinity, minHeight: MemoBookSpacing.minimumTapTarget)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }

    // MARK: - Les deux interrupteurs

    /// Les liaisons passent par le modèle et non par `settings` : une vue ne
    /// doit pas pouvoir poser une valeur sans qu'elle partie au serveur.
    /// La ligne relit le nom du modèle, et lui rend ce qu'on a tapé en sortant
    /// du champ. Voir ``TripSettingsModel/setName(_:)``.
    private var nameBinding: Binding<String> {
        Binding(
            get: { model.settings?.name ?? "" },
            set: { model.setName($0) }
        )
    }

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

/// La ligne des **limites de souvenirs** : le solde, et la jauge quand elle
/// commence à compter.
///
/// **Elle se tait tant qu'il reste de la marge**, et c'est le point de tout le
/// réglage : ces limites sont un garde-fou contre l'usage qui coûterait plus
/// cher que l'abonnement, pas un levier commercial. Une jauge posée en
/// permanence à 4 % ferait compter des souvenirs à quelqu'un qui devrait
/// compter des jours de voyage. Elle n'apparaît qu'au seuil — voir
/// ``MemoryAllowance/isRunningLow``.
///
/// Ce n'est donc pas une ``BrandRow`` : celle-ci porte un intitulé et une
/// valeur, et n'a pas de place pour une barre qui pousse sous elle.
///
/// ⚠️ **Aucune maquette ne la dessine** (Hugo, 16/09/2026). Elle reprend le
/// dessin des lignes d'à côté — même coque, même filet, même chevron — et reste
/// à valider dans Figma.
private struct MemoryAllowanceRow: View {
    let memory: MemoryAllowance
    let action: () -> Void

    @ScaledMetric(relativeTo: .body) private var chevronSide: CGFloat = 14

    private var shape: RoundedRectangle {
        .rect(cornerRadius: MemoBookSpacing.largeCornerRadius)
    }

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: MemoBookSpacing.xs) {
                HStack(spacing: MemoBookSpacing.s) {
                    Text(MemoryCopy.rowTitle)
                        .font(MemoBookFont.body)
                        .foregroundStyle(MemoBookColor.ink)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Text(MemoryCopy.rowValue(used: memory.used, allowance: memory.allowance))
                        .font(MemoBookFont.label)
                        .foregroundStyle(
                            memory.isExhausted ? MemoBookColor.error : MemoBookColor.inkMuted
                        )
                        .monospacedDigit()
                        .fixedSize()

                    Image(brand: "IconChevron")
                        .resizable()
                        .renderingMode(.template)
                        .scaledToFit()
                        .frame(width: chevronSide, height: chevronSide)
                        .foregroundStyle(MemoBookColor.inkMuted)
                }

                // La barre n'apparaît qu'au seuil : voir l'en-tête.
                if memory.isRunningLow || memory.isExhausted {
                    BrandGauge(
                        fraction: memory.fraction,
                        isExhausted: memory.isExhausted,
                        accessibilityLabel: MemoryCopy.rowTitle
                    )
                }
            }
            .padding(.horizontal, MemoBookSpacing.s)
            .padding(.vertical, MemoBookSpacing.snug)
            .frame(minHeight: MemoBookSpacing.minimumTapTarget)
            .background(MemoBookColor.surface, in: shape)
            .overlay { shape.strokeBorder(MemoBookColor.hairline, lineWidth: 1) }
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(
            "\(MemoryCopy.rowTitle). \(MemoryCopy.remaining(memory.remaining, renewsOn: nil))"
        )
    }
}

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

/// La ligne « Prévisualisation PDF » : l'intitulé, sa précision, et la couverture
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
