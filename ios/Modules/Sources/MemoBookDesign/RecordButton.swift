import SwiftUI

/// Le bouton d'enregistrement — l'élément central du cœur produit.
///
/// Deux états seulement : au repos il porte la couleur d'action, en
/// enregistrement il bascule sur l'orange et pulse. Aucun rendu 3D, aucune
/// illustration : des formes simples, comme dans Dictaphone.
public struct RecordButton: View {
    private let isRecording: Bool
    private let isBusy: Bool
    private let action: () -> Void

    @State private var pulse = false

    public init(isRecording: Bool, isBusy: Bool = false, action: @escaping () -> Void) {
        self.isRecording = isRecording
        self.isBusy = isBusy
        self.action = action
    }

    private var tint: Color {
        isRecording ? MemoBookColor.recording : MemoBookColor.action
    }

    public var body: some View {
        Button(action: action) {
            ZStack {
                if isRecording {
                    Circle()
                        .stroke(tint.opacity(0.35), lineWidth: 3)
                        .scaleEffect(pulse ? 1.35 : 1)
                        .opacity(pulse ? 0 : 1)
                }

                Circle()
                    .fill(tint)
                    .frame(width: 72, height: 72)
                    .shadow(color: tint.opacity(0.35), radius: 12, y: 6)

                if isBusy {
                    ProgressView()
                        .tint(.white)
                } else {
                    // Le carré signale « arrêter », comme dans toutes les apps
                    // d'enregistrement : c'est un acquis, on ne le réinvente pas.
                    Image(systemName: isRecording ? "stop.fill" : "mic.fill")
                        .font(.system(size: 28, weight: .medium))
                        .foregroundStyle(.white)
                }
            }
            .frame(width: 96, height: 96)
        }
        .buttonStyle(.plain)
        .disabled(isBusy)
        .accessibilityLabel(isRecording ? "Arrêter l'enregistrement" : "Enregistrer un souvenir")
        .accessibilityAddTraits(.isButton)
        .onChange(of: isRecording) { _, recording in
            guard recording else {
                pulse = false
                return
            }
            withAnimation(.easeOut(duration: 1.8).repeatForever(autoreverses: false)) {
                pulse = true
            }
        }
    }
}

#Preview("Repos") {
    RecordButton(isRecording: false) {}
}

#Preview("Enregistrement") {
    RecordButton(isRecording: true) {}
}
