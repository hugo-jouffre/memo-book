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
                    // Le compteur n'est pas décoratif : c'est là que le
                    // voyageur voit si son étape tiendra sur la page, pendant
                    // qu'il écrit plutôt qu'après coup.
                    StepLengthHint(text: draft)
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
/// Le barème S / M / L / XL, côté écriture.
///
/// Il se mesure sur **l'étape entière**, pas sur le plus long paragraphe :
/// c'est ce que compte le validateur du back-end, et c'est ce que compte la
/// mise en page. Les trois devaient compter la même chose — c'était tout le
/// problème.
///
/// Les valeurs et les deux messages viennent de
/// `backend/src/services/payloadValidator.ts` (`STEP_SIZES`, `LENGTH_HINTS`) :
/// les changer ici seulement ferait mentir l'app.
private struct StepLengthHint: View {
    let text: String

    private enum Size: String, CaseIterable {
        case s = "S", m = "M", l = "L", xl = "XL"

        var range: ClosedRange<Int> {
            switch self {
            case .s: return 200...379
            case .m: return 380...559
            case .l: return 560...899
            case .xl: return 900...1440
            }
        }
    }

    /// Texte brut de l'étape : c'est l'unité du barème.
    private var length: Int {
        text.trimmingCharacters(in: .whitespacesAndNewlines).count
    }

    private var size: Size? {
        Size.allCases.first { $0.range.contains(length) }
    }

    private var isTooShort: Bool { length < Size.s.range.lowerBound }
    private var isTooLong: Bool { length > Size.xl.range.upperBound }

    private var message: String {
        if isTooShort {
            return "Encore quelques lignes : sous \(Size.s.range.lowerBound) caractères, "
                + "l'étape laisse une page aux trois quarts vide. Raconte un détail de plus "
                + "— ce que tu as vu, mangé, entendu."
        }
        if isTooLong {
            return "Ce souvenir dépasse ce qu'une étape peut contenir : "
                + "\(Size.xl.range.upperBound) caractères, soit deux pages de carnet. "
                + "Coupe-le en deux étapes, chacune aura les siennes."
        }
        // Hors des deux bornes, le compteur informe sans alarmer : la taille
        // dit au voyageur la place que son texte prendra dans le carnet.
        return "\(length) caractères — taille \(size?.rawValue ?? "S")."
    }

    var body: some View {
        Text(message)
            .font(MemoBookFont.caption)
            .foregroundStyle(
                isTooShort || isTooLong ? MemoBookColor.error : MemoBookColor.inkSecondary
            )
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
