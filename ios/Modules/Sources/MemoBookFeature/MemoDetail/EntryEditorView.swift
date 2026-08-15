import MemoBookCore
import MemoBookDesign
import SwiftUI

/// L'écran de relecture d'un souvenir : le texte rédigé, modifiable au
/// clavier.
///
/// C'est le seul endroit du produit où l'utilisateur reprend la main sur ce
/// que l'IA a écrit, et c'est le point de non-retour du texte : une fois
/// corrigé, il part tel quel dans le carnet. L'écran doit donc rendre trois
/// choses évidentes — ce qui a été dit, ce qui a été écrit, et comment revenir
/// en arrière.
struct EntryEditorView: View {
    let entry: Entry
    let onSave: (String) -> Void
    let onRevert: () -> Void
    let onRetry: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var draft: String
    @State private var showsTranscript = false
    @State private var confirmsRevert = false

    init(
        entry: Entry,
        onSave: @escaping (String) -> Void,
        onRevert: @escaping () -> Void,
        onRetry: @escaping () -> Void
    ) {
        self.entry = entry
        self.onSave = onSave
        self.onRevert = onRevert
        self.onRetry = onRetry
        _draft = State(initialValue: entry.displayText ?? "")
    }

    private var hasChanges: Bool {
        draft.trimmingCharacters(in: .whitespacesAndNewlines) != (entry.displayText ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                if entry.redactionStatus == .failed {
                    Section {
                        RedactionFailureNotice(message: entry.redactionError) { onRetry() }
                    }
                }

                Section {
                    TextEditor(text: $draft)
                        .font(MemoBookFont.body)
                        .frame(minHeight: 220)
                        .accessibilityLabel("Texte du souvenir")
                } header: {
                    Text("Le texte du carnet")
                } footer: {
                    // Le compteur n'est pas décoratif : au-delà de 420
                    // caractères par paragraphe, la génération du PDF échoue.
                    // Mieux vaut le dire ici qu'après coup.
                    ParagraphLengthHint(text: draft)
                }

                if entry.isEdited {
                    Section {
                        Button("Revenir au texte proposé", role: .destructive) {
                            confirmsRevert = true
                        }
                    } footer: {
                        Text("Ta version sera remplacée par celle rédigée automatiquement.")
                    }
                } else if entry.redactedText != nil {
                    Section {
                        Button("Proposer un autre texte") { onRetry() }
                    } footer: {
                        Text("Le souvenir sera rédigé à nouveau à partir de ce que tu as raconté.")
                    }
                }

                if let transcript = entry.transcript, !transcript.isEmpty {
                    Section {
                        DisclosureGroup("Ce que tu as raconté", isExpanded: $showsTranscript) {
                            Text(transcript)
                                .font(MemoBookFont.caption)
                                .foregroundStyle(MemoBookColor.inkSecondary)
                                .textSelection(.enabled)
                        }
                    } footer: {
                        Text("La transcription brute est conservée : elle ne part pas dans le carnet.")
                    }
                }
            }
            .navigationTitle(entry.suggestedTitle ?? "Souvenir")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Enregistrer") {
                        onSave(draft)
                        dismiss()
                    }
                    .disabled(!hasChanges || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .confirmationDialog(
                "Revenir au texte proposé ?",
                isPresented: $confirmsRevert,
                titleVisibility: .visible
            ) {
                Button("Revenir au texte proposé", role: .destructive) {
                    onRevert()
                    dismiss()
                }
                Button("Garder ma version", role: .cancel) {}
            } message: {
                Text("Ta correction sera perdue.")
            }
        }
    }
}

/// Longueur du plus long paragraphe, rapportée à la limite du gabarit.
private struct ParagraphLengthHint: View {
    let text: String

    /// `LAYOUT_KB.md` § Contraintes de longueur — appliqué à la génération.
    private static let maxCharactersPerParagraph = 420

    private var longestParagraph: Int {
        text
            .components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).count }
            .max() ?? 0
    }

    private var isOverLimit: Bool { longestParagraph > Self.maxCharactersPerParagraph }

    var body: some View {
        Text(
            isOverLimit
                ? "Paragraphe trop long : \(longestParagraph) caractères sur \(Self.maxCharactersPerParagraph). Coupe-le en deux avec une ligne vide."
                : "\(longestParagraph)/\(Self.maxCharactersPerParagraph) caractères sur le plus long paragraphe."
        )
        .font(MemoBookFont.caption)
        .foregroundStyle(isOverLimit ? MemoBookColor.error : MemoBookColor.inkSecondary)
    }
}

private struct RedactionFailureNotice: View {
    let message: String?
    let onRetry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: MemoBookSpacing.xs) {
            Text("La rédaction n'a pas abouti")
                .font(MemoBookFont.body.weight(.semibold))
                .foregroundStyle(MemoBookColor.error)

            Text(message ?? "Le texte affiché est ta transcription brute. Tu peux la corriger à la main ou réessayer.")
                .font(MemoBookFont.caption)
                .foregroundStyle(MemoBookColor.inkSecondary)

            Button("Réessayer", action: onRetry)
                .buttonStyle(.bordered)
        }
        .padding(.vertical, MemoBookSpacing.xs / 2)
    }
}
