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
enum TripSettingsSheet: String, Identifiable, Hashable {
    case dates
    case pace
    case notifications
    case theme
    case companions
    /// Les limites de souvenirs, et le palier étendu.
    case memory

    var id: String { rawValue }
}

// MARK: - Dates

/// « Dates » — les deux bornes du voyage, chacune ouvrant le sélecteur du
/// système par-dessus la feuille.
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
                    in: ...(end ?? .distantFuture)
                )

                BrandDateField(
                    BookCopy.Dates.end,
                    date: $end,
                    in: (start ?? .distantPast)...
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

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        BrandSheet(BookCopy.Pace.title, subtitle: BookCopy.Pace.subtitle) {
            BrandOptionGroup {
                ForEach(NarrationPace.selectable, id: \.self) { pace in
                    BrandOptionRow(
                        pace.displayName,
                        subtitle: pace.detail,
                        isSelected: model.settings?.narrationPace == pace
                    ) {
                        model.setPace(pace)
                        // Choisir, c'est finir : la feuille n'a rien d'autre à
                        // proposer, et la garder ouverte obligerait à la
                        // refermer pour voir la valeur posée sur la ligne.
                        dismiss()
                    }
                }
            }
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
    /// Ce que le champ contient. Il porte le thème quel qu'il soit : choisir
    /// une pastille l'écrit dedans, et on peut ensuite le retoucher.
    @State private var text: String

    init(model: TripSettingsModel) {
        self.model = model
        _text = State(initialValue: model.settings?.theme ?? "")
    }

    var body: some View {
        BrandSheet(BookCopy.Theme.title, subtitle: BookCopy.Theme.subtitle) {
            VStack(spacing: MemoBookSpacing.s) {
                if model.themes.isEmpty {
                    TripThemePickerPlaceholder()
                } else {
                    TripThemePicker(themes: model.themes, selection: $selection) { theme in
                        // Le carrousel **écrit dans le champ** au lieu de le
                        // remplacer : « Autre » ouvre la saisie libre, les
                        // autres posent leur nom, et on garde la main dessus.
                        text = theme.isOther ? "" : theme.name
                        focus = theme.isOther ? .theme : nil
                    }
                }

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

                BrandButton(BookCopy.Theme.validate, fillsWidth: true, action: validate)
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        // Les thèmes viennent du serveur, et la rangée montre sa barre
        // d'attente le temps qu'ils arrivent. Sans effet s'ils sont déjà là.
        .task {
            await model.loadThemes()
            selection = model.themes.first { $0.name == text }
        }
    }

    private func validate() {
        focus = nil
        model.setTheme(text)
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
/// que VoiceOver et le Contrôle de sélection savent atteindre. On ne peut pas
/// se contenter du glissé : un geste continu n'existe pas pour ces deux-là.
private struct CompanionRow: View {
    let companion: Companion
    let onRemove: () -> Void
    let onResend: () -> Void

    /// De combien la carte est décalée vers la gauche. `0` au repos, la largeur
    /// des actions quand elles sont ouvertes.
    @State private var offset: CGFloat = 0
    @GestureState private var drag: CGFloat = 0

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize

    /// Largeur du tiroir : deux cibles tactiles et leur gouttière.
    private var drawerWidth: CGFloat {
        canRemove
            ? MemoBookSpacing.minimumTapTarget * (canResend ? 2 : 1)
                + MemoBookSpacing.xs * (canResend ? 3 : 2)
            : 0
    }

    /// Le propriétaire ne se retire pas — première règle de la note.
    private var canRemove: Bool { !companion.isOwner }
    /// On ne renvoie un lien qu'à quelqu'un qui n'est jamais entré.
    private var canResend: Bool { companion.isPending }

    private var translation: CGFloat {
        (offset + drag).clampedToDrawer(drawerWidth)
    }

    var body: some View {
        ZStack(alignment: .trailing) {
            if canRemove { actions }

            card
                .offset(x: translation)
                .gesture(swipe)
        }
        // La carte est **rognée sur sa propre place**. Sans ça, elle glissait
        // par-dessus la marge de la feuille et jusque sous le bord de l'écran :
        // le portrait sortait du cadre et le coin arrondi se retrouvait coupé
        // net. Rognée, elle disparaît sous la colonne comme une ligne de liste
        // disparaît sous le bord d'un tableau — et le coin reste rond.
        .clipShape(.rect(cornerRadius: MemoBookSpacing.snug))
        // L'appui long : le même couple d'actions, par le menu du système.
        .contextMenu {
            if canResend {
                Button(BookCopy.Invite.resend, systemImage: "paperplane") { onResend() }
            }
            if canRemove {
                Button(BookCopy.Invite.remove, systemImage: "person.badge.minus", role: .destructive) {
                    onRemove()
                }
            }
        }
        // Et pour VoiceOver, où ni l'un ni l'autre n'existe : le rotor
        // d'actions, qui est la façon dont iOS rend un balayage de liste.
        .accessibilityElement(children: .combine)
        .accessibilityActions {
            if canResend { Button(BookCopy.Invite.resend, action: onResend) }
            if canRemove { Button(BookCopy.Invite.remove, action: onRemove) }
        }
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

    // MARK: Le tiroir

    private var actions: some View {
        HStack(spacing: MemoBookSpacing.xs) {
            if canResend {
                actionButton(
                    icon: "IconTeleverser",
                    tint: MemoBookColor.action,
                    label: BookCopy.Invite.resend
                ) {
                    close()
                    onResend()
                }
            }

            actionButton(
                icon: "IconCross",
                tint: MemoBookColor.error,
                label: BookCopy.Invite.remove
            ) {
                close()
                onRemove()
            }
        }
        .padding(.trailing, MemoBookSpacing.xs)
        // Elles n'existent que lorsqu'on les a fait apparaître : posées en
        // permanence sous la carte, elles resteraient tapables à travers elle.
        .opacity(translation < -MemoBookSpacing.xs ? 1 : 0)
        .allowsHitTesting(translation < -MemoBookSpacing.xs)
        .accessibilityHidden(true)
    }

    private func actionButton(
        icon: String,
        tint: Color,
        label: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(brand: icon)
                .resizable()
                .renderingMode(.template)
                .scaledToFit()
                .frame(width: MemoBookSpacing.snug, height: MemoBookSpacing.snug)
                .foregroundStyle(tint)
                .frame(
                    width: MemoBookSpacing.minimumTapTarget,
                    height: MemoBookSpacing.minimumTapTarget
                )
                .overlay { Circle().strokeBorder(tint, lineWidth: 1) }
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    // MARK: Le geste

    /// Vers la gauche seulement, et franchement horizontal : la feuille défile
    /// verticalement sous ce geste, et un glissé un peu de travers ne doit pas
    /// ouvrir un tiroir au milieu d'une lecture.
    private var swipe: some Gesture {
        DragGesture(minimumDistance: 12)
            .updating($drag) { value, state, _ in
                guard canRemove, abs(value.translation.width) > abs(value.translation.height) else {
                    return
                }
                state = value.translation.width
            }
            .onEnded { value in
                guard canRemove, abs(value.translation.width) > abs(value.translation.height) else {
                    return
                }
                let settled = (offset + value.translation.width).clampedToDrawer(drawerWidth)
                withAnimation(reduceMotion ? .none : .snappy(duration: 0.25)) {
                    offset = settled < -drawerWidth / 2 ? -drawerWidth : 0
                }
            }
    }

    private func close() {
        withAnimation(reduceMotion ? .none : .snappy(duration: 0.25)) { offset = 0 }
    }
}

private extension CGFloat {
    /// Le tiroir ne s'ouvre que vers la gauche, et pas au-delà de sa largeur.
    func clampedToDrawer(_ width: CGFloat) -> CGFloat {
        // `Swift.min` / `Swift.max` explicitement : dans une extension de
        // `CGFloat`, `min` et `max` désignent d'abord les bornes du type.
        Swift.min(0, Swift.max(-width, self))
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
