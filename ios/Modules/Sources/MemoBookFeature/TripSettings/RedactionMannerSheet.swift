import MemoBookCore
import MemoBookDesign
import SwiftUI

/// **« Manière d'être rédigé »** — T292.
///
/// Trois manières, les indications libres du voyageur, et « Tout faire
/// reprendre ». Les fiches qui pilotent vraiment le modèle sont dans
/// `agents/redaction-manieres/` ; ici on ne montre que ce qu'on choisit.
///
/// ⚠️ **La confirmation est un second temps de cette feuille**, et non une
/// feuille posée dessus : un enchaînement de feuilles ne s'empile pas
/// (`ios/CLAUDE.md`). C'est aussi là que le consentement est donné — le serveur
/// ne le redemande pas, il reprend le carnet dès que le réglage change.
///
/// ⚠️ **Fermé, le réglage pâlit, il ne se désactive pas** : les manières
/// restent tapables, et l'appui pose la notice qui nomme la cause et la sortie.
struct RedactionMannerSheet: View {
    let model: TripSettingsModel

    /// Ce que le second temps va faire si on confirme.
    private enum Pending: Equatable {
        /// Changer de manière.
        case manner(RedactionManner)
        /// Tout reprendre sans rien changer.
        case rewrite
    }

    @State private var pending: Pending?

    /// La manière cochée **tant que l'aller-retour n'a pas répondu** : la coche
    /// se pose tout de suite, comme sur la feuille « Rythme du récit ».
    @State private var chosen: RedactionManner?

    /// Les indications telles qu'on les tape. Elles ne partent qu'à la sortie
    /// du champ : un envoi par caractère ferait une requête par lettre, et
    /// chacune reprendrait le carnet.
    @State private var notes = ""
    @State private var notesLoaded = false
    @FocusState private var isWritingNotes: Bool

    /// La notice du réglage fermé, posée par un appui sur une manière.
    @State private var explainsPaywall = false

    @Environment(\.dismiss) private var dismiss

    private var redaction: RedactionSettings { model.settings?.redactionSettings ?? RedactionSettings() }
    private var isAvailable: Bool { redaction.isAvailable }
    private var selected: RedactionManner { chosen ?? redaction.manner }

    var body: some View {
        BrandSheet(
            pending == nil ? BookCopy.Settings.Redaction.title : BookCopy.Settings.Redaction.Confirm.title,
            subtitle: pending == nil
                ? BookCopy.Settings.Redaction.subtitle
                : BookCopy.Settings.Redaction.Confirm.body
        ) {
            if pending == nil { choice } else { confirmation }
        }
        .animation(.snappy(duration: 0.2), value: pending)
        .task(id: redaction.notes) {
            // Le champ se remplit **une fois** : relire à chaque réponse du
            // serveur écraserait ce qu'on est en train de taper.
            guard !notesLoaded else { return }
            notes = redaction.notes ?? ""
            notesLoaded = true
        }
    }

    // MARK: - Premier temps : le choix

    @ViewBuilder private var choice: some View {
        VStack(alignment: .leading, spacing: MemoBookSpacing.s) {
            BrandOptionGroup {
                ForEach(RedactionManner.allCases, id: \.self) { manner in
                    BrandOptionRow(
                        label(manner),
                        subtitle: detail(manner),
                        value: manner == .spoken && redaction.chosenManner == nil
                            ? BookCopy.Settings.Redaction.byDefault
                            : nil,
                        isSelected: selected == manner
                    ) {
                        ask(.manner(manner))
                    }
                }
            }
            .opacity(isAvailable ? 1 : 0.45)

            if explainsPaywall {
                BrandNotice(BookCopy.Settings.Redaction.needsUnlimited, tone: .information)
            }

            notesField

            if isAvailable {
                BrandRowGroup {
                    BrandRow(
                        BookCopy.Settings.Redaction.rewrite,
                        note: BookCopy.Settings.Redaction.rewriteDetail,
                        action: { ask(.rewrite) }
                    )
                }
                .disabled(model.isRewritingRedaction)
            }
        }
    }

    /// Les indications : un **texte**, donc ``BrandTextBox`` et non
    /// ``BrandTextField`` — la frontière entre les deux est une valeur contre
    /// un texte.
    @ViewBuilder private var notesField: some View {
        VStack(alignment: .leading, spacing: MemoBookSpacing.xs) {
            Text(BookCopy.Settings.Redaction.notesTitle)
                .font(MemoBookFont.label)
                .foregroundStyle(MemoBookColor.ink)

            BrandTextBox(
                BookCopy.Settings.Redaction.notesPlaceholder,
                text: $notes,
                focus: $isWritingNotes,
                lineSpan: 3...6,
                accessibilityLabel: BookCopy.Settings.Redaction.notesTitle
            )
            .opacity(isAvailable ? 1 : 0.45)
            .disabled(!isAvailable)
            .onChange(of: isWritingNotes) { _, writing in
                // À la sortie du champ, comme le nom du voyage : un envoi par
                // caractère ferait une requête par lettre, et chacune
                // reprendrait le carnet.
                guard !writing else { return }
                model.setRedactionNotes(notes)
            }
            .onChange(of: notes) { _, value in
                // La coupe se voit **avant** l'envoi : le serveur tronque en
                // silence, et laisser écrire pour couper après serait couper
                // dans le texte de quelqu'un sans le lui dire.
                if value.count > RedactionSettings.notesLimit {
                    notes = String(value.prefix(RedactionSettings.notesLimit))
                }
            }

            Text(BookCopy.Settings.Redaction.notesHelp)
                .font(MemoBookFont.caption)
                .foregroundStyle(MemoBookColor.inkMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Second temps : la confirmation

    @ViewBuilder private var confirmation: some View {
        VStack(spacing: MemoBookSpacing.xs) {
            BrandButton(BookCopy.Settings.Redaction.Confirm.go, style: .primary) {
                commit()
            }
            BrandButton(BookCopy.Settings.Redaction.Confirm.keep, style: .tertiary) {
                pending = nil
            }
        }
    }

    // MARK: - Les gestes

    /// Demande confirmation — ou pose la notice, si le réglage est fermé.
    private func ask(_ next: Pending) {
        guard isAvailable else {
            withAnimation(.snappy(duration: 0.2)) { explainsPaywall = true }
            return
        }
        // Choisir la manière déjà en place ne reprend rien : on ne demande même
        // pas, on referme.
        if case .manner(let manner) = next, manner == redaction.manner {
            dismiss()
            return
        }
        pending = next
    }

    private func commit() {
        guard let pending else { return }
        switch pending {
        case .manner(let manner):
            chosen = manner
            model.setRedactionManner(manner)
        case .rewrite:
            model.rewriteRedaction()
        }
        self.pending = nil
        Task {
            try? await Task.sleep(for: BrandOptionRow.lingerBeforeDismiss)
            dismiss()
        }
    }

    // MARK: - La copie des trois manières

    private func label(_ manner: RedactionManner) -> String {
        switch manner {
        case .spoken: BookCopy.Settings.Redaction.spoken
        case .literary: BookCopy.Settings.Redaction.literary
        case .factual: BookCopy.Settings.Redaction.factual
        }
    }

    private func detail(_ manner: RedactionManner) -> String {
        switch manner {
        case .spoken: BookCopy.Settings.Redaction.spokenDetail
        case .literary: BookCopy.Settings.Redaction.literaryDetail
        case .factual: BookCopy.Settings.Redaction.factualDetail
        }
    }
}
