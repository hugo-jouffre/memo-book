import MemoBookCore
import MemoBookDesign
import SwiftUI

/// Les cinq feuilles des paramètres d'un voyage.
///
/// **Elles règlent sans quitter l'écran**, et c'est tout leur intérêt : on est
/// en plein voyage, on veut décaler une date ou couper une alerte, et on ne veut
/// pas traverser trois écrans pour ça. Chacune tient la hauteur de son contenu
/// (``BrandSheet``), fait reculer l'écran du dessous, et se referme au glissé.
///
/// **Elles enregistrent en se fermant, jamais avant.** Enfin, presque : c'est
/// vrai des quatre qui n'ont pas de bouton — dates, rythme, notifications,
/// co-voyageurs —, où chaque geste part seul, comme les lignes de réglages
/// partout ailleurs dans l'app. Le thème, lui, porte un « Valider » parce que la
/// maquette lui en donne un : on y **tape** un texte, et un champ qui
/// s'enregistre à chaque lettre enverrait dix requêtes par mot.

/// Ce que les paramètres d'un voyage ouvrent en feuille.
public enum TripSettingsSheet: String, Identifiable, Hashable, Sendable {
    case dates
    case pace
    case notifications
    case theme
    case companions
    /// Les limites de souvenirs, et le palier étendu.
    case memory

    public var id: String { rawValue }
}

// MARK: - Dates

/// « Dates » — les deux bornes du voyage, chacune ouvrant le sélecteur du
/// système par-dessus la feuille.
///
/// **Une date posée se change, elle ne s'efface plus** (Clara, 26/09/2026) :
/// pas de croix sur les deux lignes. On pouvait retirer le départ d'un voyage
/// déjà configuré, ce qui n'a pas de sens — c'est lui qui range le voyage dans
/// « à venir » ou « en cours ».
struct TripDatesSheet: View {
    let model: TripSettingsModel

    /// Les dates **de la feuille**, et non celles du modèle.
    ///
    /// Les deux se bornent l'une l'autre : poser une fin avant le début est
    /// refusé par le serveur, et par le sélecteur lui-même. On tient donc les
    /// deux ensemble ici, et on n'envoie qu'une fois la paire cohérente.
    @State private var start: Date?
    @State private var end: Date?

    init(model: TripSettingsModel) {
        self.model = model
        _start = State(initialValue: model.settings?.startDate)
        _end = State(initialValue: model.settings?.endDate)
    }

    var body: some View {
        BrandSheet(BookCopy.Dates.title) {
            VStack(spacing: MemoBookSpacing.snug) {
                BrandDateField(
                    BookCopy.Dates.start,
                    date: $start,
                    // Une fin déjà posée borne le début : l'inverse n'a pas de
                    // sens, et le serveur le refuserait.
                    in: ...(end ?? .distantFuture),
                    isClearable: false
                )

                BrandDateField(
                    BookCopy.Dates.end,
                    date: $end,
                    in: (start ?? .distantPast)...,
                    isClearable: false
                )
            }
            // Un seul envoi pour les deux, et **au changement** : la feuille n'a
            // pas de bouton, c'est le geste qui vaut validation.
            .onChange(of: start) { model.setDates(start: start, end: end) }
            .onChange(of: end) { model.setDates(start: start, end: end) }
        }
    }
}

// MARK: - Rythme du récit

/// « Rythme du récit » — cinq cadences, une seule choisie.
struct TripPaceSheet: View {
    let model: TripSettingsModel

    /// Ce qu'on vient de toucher, le temps que la feuille parte — la coche se
    /// pose sur **cette** valeur, pas sur celle du modèle, dont l'aller-retour
    /// ne doit pas la faire clignoter. Même mécanique que « Genre ».
    @State private var chosen: NarrationPace?

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        BrandSheet(BookCopy.Pace.title, subtitle: BookCopy.Pace.subtitle) {
            BrandOptionGroup {
                ForEach(NarrationPace.selectable, id: \.self) { pace in
                    BrandOptionRow(
                        pace.displayName,
                        subtitle: pace.detail,
                        isSelected: (chosen ?? model.settings?.narrationPace) == pace
                    ) {
                        select(pace)
                    }
                }
            }
        }
    }

    /// Coche, enregistre, puis referme — dans cet ordre. Choisir, c'est finir :
    /// la feuille n'a rien d'autre à proposer, et la garder ouverte obligerait
    /// à la refermer pour voir la valeur posée sur la ligne. Mais on voit la
    /// coche avant (Hugo, 18/09/2026). Un second toucher pendant l'attente ne
    /// fait rien : le premier est déjà parti.
    private func select(_ pace: NarrationPace) {
        guard chosen == nil else { return }
        withAnimation(.snappy(duration: 0.2)) { chosen = pace }
        model.setPace(pace)
        Task {
            try? await Task.sleep(for: BrandOptionRow.lingerBeforeDismiss)
            dismiss()
        }
    }
}

// MARK: - Notifications

/// « Notifications » — les quatre alertes du voyage, une carte chacune.
struct TripNotificationsSheet: View {
    let model: TripSettingsModel

    private var settings: TripSettings? { model.settings }

    var body: some View {
        BrandSheet(
            BookCopy.Notifications.title,
            subtitle: BookCopy.Notifications.subtitle(trip: settings?.name ?? "")
        ) {
            VStack(alignment: .leading, spacing: MemoBookSpacing.snug) {
                // L'interrupteur maître est baissé : les quatre cartes restent
                // réglables — on prépare ce qu'on recevra —, mais l'écran dit
                // que rien ne partira d'ici là. Sans cette phrase, on croit à
                // quatre interrupteurs morts.
                if settings?.wantsNotifications == false {
                    BrandNotice(BookCopy.Notifications.mutedNotice)
                }

                BrandToggleCard(
                    title: BookCopy.Notifications.writingReminder,
                    detail: BookCopy.Notifications.writingReminderDetail,
                    isOn: binding(\.writingReminder) { $0.writingReminder = $1 }
                )
                BrandToggleCard(
                    title: BookCopy.Notifications.newStory,
                    detail: BookCopy.Notifications.newStoryDetail,
                    isOn: binding(\.newStory) { $0.newStory = $1 }
                )
                BrandToggleCard(
                    title: BookCopy.Notifications.weeklyDigest,
                    detail: BookCopy.Notifications.weeklyDigestDetail,
                    isOn: binding(\.weeklyDigest) { $0.weeklyDigest = $1 }
                )
                BrandToggleCard(
                    title: BookCopy.Notifications.tripEnd,
                    detail: BookCopy.Notifications.tripEndDetail,
                    isOn: binding(\.tripEndReminder) { $0.tripEndReminder = $1 }
                )
            }
            // Les quatre bascules **agissent** : les toucher avant que les
            // réglages soient là enverrait un état qu'on n'a pas lu.
            .disabled(settings == nil)
        }
    }

    /// La liaison d'une alerte : elle lit le modèle et lui repasse le bloc
    /// entier, parce que c'est le bloc entier que la route accepte.
    ///
    /// `@MainActor` sur la fermeture d'écriture : `Binding` veut du `Sendable`,
    /// et une méthode du modèle — isolée au menu principal — ne s'y glisse que
    /// si cette isolation est dite ici aussi.
    @MainActor
    private func binding(
        _ keyPath: KeyPath<TripNotificationPreferences, Bool>,
        _ set: @escaping (inout TripNotificationPreferences, Bool) -> Void
    ) -> Binding<Bool> {
        Binding(
            get: { model.settings?.notifications[keyPath: keyPath] ?? false },
            set: { isOn in
                guard var preferences = model.settings?.notifications else { return }
                set(&preferences, isOn)
                model.setNotificationPreferences(preferences)
            }
        )
    }
}

// MARK: - Thème de l'aventure

/// « Thème de l'aventure » — le même carrousel qu'à la création du voyage, et
/// le champ libre qu'il ouvre.
///
/// **Le carrousel est celui de la création**, à la lettre : c'est la note
/// « Logique » du nœud — « les thèmes doivent venir de la même base de données
/// que lors de la création du voyage ». Un second jeu de thèmes ici ferait
/// dériver `memos.theme`, que l'agent de rédaction lit tel quel.
struct TripThemeSheet: View {
    let model: TripSettingsModel

    /// Le seul champ de la feuille. ``BrandTextField`` veut une énumération de
    /// champs, parce que c'est l'écran qui tient le focus dans cette app — et
    /// une feuille à un champ n'échappe pas à la règle.
    private enum Field: Hashable { case theme }

    @Environment(\.dismiss) private var dismiss
    @FocusState private var focus: Field?

    /// Le thème choisi dans le carrousel, ou `nil` quand c'est un texte libre
    /// qui ne correspond à aucun.
    @State private var selection: TripTheme?
    /// Ce que le champ contient — **le nom d'un thème libre**, seulement
    /// derrière « Autre ». Un thème de la rangée n'a rien à taper : son nom
    /// est le thème (Hugo, 17/09/2026).
    @State private var text: String

    init(model: TripSettingsModel) {
        self.model = model
        _text = State(initialValue: model.settings?.theme ?? "")
    }

    /// Le champ n'existe que derrière « Autre » — et derrière un thème libre
    /// déjà enregistré, que la rangée ne connaît pas : sans champ, on ne
    /// pourrait ni le relire ni le corriger.
    private var showsField: Bool {
        selection?.isOther == true || (selection == nil && !model.themes.isEmpty)
    }

    /// Ce que « Valider » enregistre : le nom du thème choisi, ou le texte
    /// libre derrière « Autre ».
    private var chosenTheme: String {
        if let selection, !selection.isOther { return selection.name }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        BrandSheet(BookCopy.Theme.title, subtitle: BookCopy.Theme.subtitle) {
            VStack(spacing: MemoBookSpacing.s) {
                if model.themes.isEmpty {
                    TripThemePickerPlaceholder()
                } else {
                    TripThemePicker(themes: model.themes, selection: $selection) { theme in
                        // « Autre » ouvre la saisie libre, avec le clavier ;
                        // un thème de la rangée referme le champ — il n'y a
                        // plus que « Valider ».
                        if theme.isOther {
                            if model.themes.contains(where: { $0.name == text }) { text = "" }
                            focus = .theme
                        } else {
                            focus = nil
                        }
                    }
                }

                if showsField {
                    BrandTextField(
                        BookCopy.Theme.title,
                        text: $text,
                        field: Field.theme,
                        focus: $focus,
                        labelPlacement: .hidden,
                        placeholder: BookCopy.Theme.placeholder
                    )
                    .submitLabel(.done)
                    .onSubmit(validate)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }

                BrandButton(BookCopy.Theme.validate, fillsWidth: true, action: validate)
                    .disabled(chosenTheme.isEmpty)
            }
            .animation(.snappy(duration: 0.25), value: showsField)
        }
        // Les thèmes viennent du serveur, et la rangée montre sa barre
        // d'attente le temps qu'ils arrivent. Sans effet s'ils sont déjà là.
        .task {
            await model.loadThemes()
            // Le thème enregistré, s'il est dans la rangée ; sinon c'est un
            // thème libre, et « Autre » le porte.
            if let known = model.themes.first(where: { $0.name == text }) {
                selection = known
            } else if !text.isEmpty {
                selection = model.themes.first { $0.isOther }
            }
        }
    }

    private func validate() {
        focus = nil
        model.setTheme(chosenTheme)
        dismiss()
    }
}

// MARK: - Inviter un proche

/// « Inviter un proche » — qui raconte déjà, et de quoi faire venir les autres.
struct TripInviteSheet: View {
    let model: TripSettingsModel

    /// Le co-voyageur dont on a demandé le retrait. La confirmation est une
    /// alerte du système et non une feuille de plus : retirer quelqu'un est
    /// irréversible, et c'est exactement ce qu'une alerte sait dire.
    @State private var pendingRemoval: Companion?

    private var settings: TripSettings? { model.settings }

    var body: some View {
        BrandSheet(BookCopy.Invite.title, subtitle: BookCopy.Invite.subtitle) {
            VStack(alignment: .leading, spacing: MemoBookSpacing.s) {
                list

                if let code = settings?.accessCode {
                    TripAccessCode(
                        code: code,
                        tripTitle: settings?.name ?? "",
                        showsSystemShare: true
                    )
                } else if model.isLoading {
                    BrandSkeleton(height: MemoBookSpacing.controlHeight)
                }

                if let confirmation = model.confirmation {
                    Text(confirmation)
                        .font(MemoBookFont.caption)
                        .foregroundStyle(MemoBookColor.valid)
                        .frame(maxWidth: .infinity)
                        .transition(.opacity)
                }
            }
            .animation(.snappy(duration: 0.25), value: model.confirmation)
            .animation(.snappy(duration: 0.25), value: settings?.companions ?? [])
        }
        .alert(
            pendingRemoval.map(\.name).map(BookCopy.Invite.removeConfirmation) ?? "",
            isPresented: .init(
                get: { pendingRemoval != nil },
                set: { if !$0 { pendingRemoval = nil } }
            ),
            presenting: pendingRemoval
        ) { companion in
            Button(BookCopy.Invite.cancel, role: .cancel) { pendingRemoval = nil }
            Button(BookCopy.Invite.remove, role: .destructive) {
                model.remove(companion)
                pendingRemoval = nil
            }
        } message: { _ in
            Text(BookCopy.Invite.removeMessage)
        }
    }

    @ViewBuilder
    private var list: some View {
        VStack(alignment: .leading, spacing: MemoBookSpacing.snug) {
            Text(BookCopy.Invite.listTitle)
                .font(MemoBookFont.overline)
                .foregroundStyle(MemoBookColor.inkMuted)
                .textCase(.uppercase)
                .accessibilityAddTraits(.isHeader)

            if let companions = settings?.companions, !companions.isEmpty {
                ForEach(companions) { companion in
                    CompanionRow(
                        companion: companion,
                        onRemove: { pendingRemoval = companion },
                        onResend: { model.resendInvitation(to: companion) }
                    )
                }

                if companions.contains(where: { !$0.isOwner }) {
                    Text(BookCopy.Invite.gestureHint)
                        .font(MemoBookFont.mention)
                        .foregroundStyle(MemoBookColor.inkMuted)
                }
            } else if model.isLoading {
                BrandSkeleton(height: 66)
                BrandSkeleton(height: 66)
            } else {
                Text(BookCopy.Invite.empty)
                    .font(MemoBookFont.caption)
                    .foregroundStyle(MemoBookColor.inkMuted)
            }
        }
    }
}

/// Une ligne de co-voyageur : son portrait, son nom, ce qu'il est pour toi — et,
/// au glissé comme à l'appui long, de quoi le retirer ou lui renvoyer son lien.
///
/// **Deux gestes pour les mêmes deux actions**, et c'est ce que demande la note
/// « Logique » de la maquette. Le glissé vers la gauche est celui des listes
/// d'iOS ; l'appui long ouvre le menu contextuel du système, qui est aussi ce
/// que VoiceOver et le Contrôle de sélection savent atteindre. Les deux
/// viennent de ``BrandSwipeDrawer``, que les cartes de l'accueil partagent
/// désormais.
private struct CompanionRow: View {
    let companion: Companion
    let onRemove: () -> Void
    let onResend: () -> Void

    @Environment(\.dynamicTypeSize) private var typeSize

    /// Le propriétaire ne se retire pas — première règle de la note.
    private var canRemove: Bool { !companion.isOwner }
    /// On ne renvoie un lien qu'à quelqu'un qui n'est jamais entré.
    private var canResend: Bool { companion.isPending }

    /// Renvoyer d'abord, retirer ensuite — le geste qui défait est le plus
    /// loin sous le doigt.
    private var actions: [BrandSwipeAction] {
        guard canRemove else { return [] }
        var actions: [BrandSwipeAction] = []
        if canResend {
            actions.append(
                BrandSwipeAction(
                    icon: "IconTeleverser",
                    tint: MemoBookColor.action,
                    label: BookCopy.Invite.resend,
                    action: onResend
                )
            )
        }
        actions.append(
            BrandSwipeAction(
                icon: "IconCross",
                tint: MemoBookColor.error,
                label: BookCopy.Invite.remove,
                action: onRemove
            )
        )
        return actions
    }

    var body: some View {
        BrandSwipeDrawer(actions: actions) {
            card
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: La carte

    private var card: some View {
        let shape = RoundedRectangle(cornerRadius: MemoBookSpacing.snug)

        return HStack(spacing: MemoBookSpacing.snug) {
            BrandAvatar(url: companion.avatarUrl, initials: companion.initials, side: 42)

            VStack(alignment: .leading, spacing: 2) {
                Text(companion.name)
                    .font(MemoBookFont.tagline)
                    .foregroundStyle(MemoBookColor.ink)
                if let detail {
                    Text(detail)
                        .font(MemoBookFont.caption)
                        .foregroundStyle(MemoBookColor.inkMuted)
                }
            }
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)

            if companion.isOwner, !typeSize.isAccessibilitySize {
                Text(BookCopy.Invite.owner)
                    .font(MemoBookFont.caption)
                    .foregroundStyle(MemoBookColor.inkMuted)
                    .multilineTextAlignment(.trailing)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(MemoBookSpacing.snug)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MemoBookColor.surface, in: shape)
        .overlay { shape.strokeBorder(MemoBookColor.hairline, lineWidth: 1) }
        .contentShape(shape)
    }

    /// La seconde ligne : « Moi » pour soi, le rôle déduit pour les autres,
    /// « Invitation envoyée » tant que personne n'est entré.
    private var detail: String? {
        if companion.isOwner { return BookCopy.Invite.me }
        if companion.isPending { return BookCopy.Invite.pending }
        return companion.role
    }
}

// MARK: - Supprimer le voyage

/// La confirmation avant de supprimer un voyage — **une feuille de l'app**, sur
/// le modèle de ``DeleteAccountSheet`` : le bouton plein garde, le rouge
/// supprime, et le paragraphe dit ce qui part avant qu'on appuie.
///
/// Elle vit ici, avec les cinq autres feuilles des réglages, parce que c'est de
/// cet écran qu'on supprime : la porte de sortie d'un voyage est au bout de ses
/// réglages, comme celle d'un compte est au bout du profil (Hugo, 15/09/2026).
struct DeleteTripSheet: View {
    /// Le nom du voyage, s'il est arrivé : les réglages peuvent ne pas avoir
    /// chargé, et la feuille doit se lire quand même.
    let tripName: String?

    /// La suppression est partie. Le bouton rouge tourne et plus rien ne se
    /// touche : la demande est définitive, elle ne part pas deux fois.
    let isDeleting: Bool

    /// Ce que le serveur a répondu si la suppression a échoué — un co-voyageur
    /// qui essaie, par exemple : seul le propriétaire y a droit. Il se lit
    /// **dans** la feuille : la fermer pour lire pourquoi obligerait à la
    /// rouvrir.
    let errorMessage: String?

    let onKeep: () -> Void
    let onDelete: () -> Void

    var body: some View {
        BrandSheet(BookCopy.Settings.Delete.title) {
            VStack(alignment: .leading, spacing: MemoBookSpacing.m) {
                Text(BookCopy.Settings.Delete.body(trip: tripName))
                    .font(MemoBookFont.body)
                    .foregroundStyle(MemoBookColor.ink)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if let errorMessage {
                    ErrorBanner(message: errorMessage)
                }

                VStack(spacing: MemoBookSpacing.s) {
                    // Le bouton plein est celui qui **ne détruit rien** : sur
                    // une feuille dont l'autre issue est sans retour, l'action
                    // la plus visible doit être la plus sûre.
                    BrandButton(BookCopy.Settings.Delete.keep, fillsWidth: true, action: onKeep)
                        .disabled(isDeleting)

                    BrandButton(
                        BookCopy.Settings.Delete.confirm,
                        style: .destructive,
                        isLoading: isDeleting,
                        fillsWidth: true,
                        action: onDelete
                    )
                }
            }
        }
        .interactiveDismissDisabled(isDeleting)
    }
}

// MARK: - Supprimer la conversation

/// La confirmation avant d'effacer la conversation d'un voyage — le même
/// dessin que ``DeleteTripSheet`` : le bouton plein garde, le rouge efface, et
/// le paragraphe dit ce qui part **et ce qui reste** avant qu'on appuie. Ce qui
/// reste compte ici plus qu'ailleurs : le mot d'accueil de MEMO revient, et
/// les souvenirs du carnet ne sont pas la conversation.
struct ClearConversationSheet: View {
    let isClearing: Bool
    let errorMessage: String?
    let onKeep: () -> Void
    let onClear: () -> Void

    var body: some View {
        BrandSheet(BookCopy.Settings.ClearConversation.title) {
            VStack(alignment: .leading, spacing: MemoBookSpacing.m) {
                Text(BookCopy.Settings.ClearConversation.body)
                    .font(MemoBookFont.body)
                    .foregroundStyle(MemoBookColor.ink)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if let errorMessage {
                    ErrorBanner(message: errorMessage)
                }

                VStack(spacing: MemoBookSpacing.s) {
                    BrandButton(BookCopy.Settings.ClearConversation.keep, fillsWidth: true, action: onKeep)
                        .disabled(isClearing)

                    BrandButton(
                        BookCopy.Settings.ClearConversation.confirm,
                        style: .destructive,
                        isLoading: isClearing,
                        fillsWidth: true,
                        action: onClear
                    )
                }
            }
        }
        .interactiveDismissDisabled(isClearing)
    }
}

#Preview("Supprimer la conversation") {
    Color.clear
        .brandSheet(isPresented: .constant(true)) {
            ClearConversationSheet(isClearing: false, errorMessage: nil, onKeep: {}, onClear: {})
        }
}

#Preview("Supprimer le voyage") {
    Color.clear
        .brandSheet(isPresented: .constant(true)) {
            DeleteTripSheet(
                tripName: "Rome entre amis",
                isDeleting: false,
                errorMessage: nil,
                onKeep: {},
                onDelete: {}
            )
        }
}

#Preview("Feuilles des réglages") {
    @Previewable @State var sheet: TripSettingsSheet? = .companions
    let model = TripSettingsModel(tripId: "preview")

    return Color.clear
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
        .environment(\.colorScheme, .light)
}
