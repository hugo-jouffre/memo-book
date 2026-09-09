import SwiftUI

/// Le bouton d'enregistrement — l'élément central du cœur produit.
///
/// Un disque vert, le micro du jeu de marque, et un mot dessous. **Il ne change
/// pas de couleur en enregistrant** : le rouge de Dictaphone dit « attention,
/// ça tourne », alors que dans MemoBook enregistrer est l'état normal, celui
/// qu'on cherche. Ce qui change, c'est le mot — « Start » puis « Stop » — et le
/// fait que le disque se met à respirer.
///
/// **Le micro reste le micro**, même en enregistrement : le carré « arrêter »
/// des apps d'enregistrement ferait croire qu'on manipule un magnétophone. Ici
/// on parle à quelqu'un qui écoute.
///
/// Trois animations, et pas une de plus :
///
/// - **au toucher**, le disque s'enfonce et rebondit ; c'est le seul retour
///   tactile, il doit se sentir ;
/// - **en enregistrement**, il respire avec la voix — le niveau du micro le
///   fait grossir de quelques pour cent, jamais plus, sinon la page entière
///   bouge ;
/// - **un halo** part du bord et se dissout, en continu : c'est ce qui dit que
///   le micro est ouvert quand personne ne parle.
public struct RecordButton: View {
    private let isRecording: Bool
    private let isPaused: Bool
    private let isBusy: Bool
    private let level: Double
    private let action: () -> Void

    /// - Parameters:
    ///   - level: le niveau du micro, de 0 à 1. C'est lui qui fait respirer le
    ///     disque ; à 0 le bouton est simplement immobile.
    ///   - isPaused: la capture est suspendue. Le disque garde sa taille mais
    ///     cesse de respirer — c'est ça qui distingue « en pause » de « en
    ///     train d'écouter le silence ».
    public init(
        isRecording: Bool,
        isPaused: Bool = false,
        isBusy: Bool = false,
        level: Double = 0,
        action: @escaping () -> Void
    ) {
        self.isRecording = isRecording
        self.isPaused = isPaused
        self.isBusy = isBusy
        self.level = level
        self.action = action
    }

    @State private var halo = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Le disque de la maquette. Il suit le Dynamic Type comme le reste :
    /// c'est une cible tactile avant d'être un dessin.
    @ScaledMetric(relativeTo: .body) private var diameter: CGFloat = 128
    @ScaledMetric(relativeTo: .body) private var iconSide: CGFloat = 40

    /// Le micro capte vraiment : ni arrêté, ni en pause.
    private var isCapturing: Bool { isRecording && !isPaused }

    /// De 1 à 1,05 selon la voix. Volontairement minuscule : au-delà, le disque
    /// pompe et la page se met à trembler autour de lui.
    private var breath: CGFloat {
        guard isCapturing, !reduceMotion else { return 1 }
        return 1 + CGFloat(min(max(level, 0), 1)) * 0.05
    }

    private var label: String {
        if isPaused { return "Reprendre" }
        return isRecording ? "Stop" : "Start"
    }

    public var body: some View {
        Button(action: action) {
            ZStack {
                if isCapturing, !reduceMotion { haloRing }

                Circle()
                    .fill(MemoBookColor.action)
                    .frame(width: diameter, height: diameter)
                    .scaleEffect(breath)
                    // Le ressort, et pas une courbe douce : c'est lui qui donne
                    // le rebond quand la voix repart d'un coup.
                    .animation(.spring(response: 0.32, dampingFraction: 0.55), value: breath)

                content
            }
            // Le cadre ne bouge pas avec la respiration : le halo et le disque
            // débordent dedans, la mise en page autour reste fixe.
            .frame(width: diameter * 1.25, height: diameter * 1.25)
            .contentShape(.circle)
        }
        .buttonStyle(PressBounce())
        .disabled(isBusy)
        .accessibilityLabel(isRecording ? "Arrêter l’enregistrement" : "Enregistrer un souvenir")
        .accessibilityAddTraits(.isButton)
        .onChange(of: isCapturing) { _, capturing in
            guard capturing, !reduceMotion else {
                halo = false
                return
            }
            withAnimation(.easeOut(duration: 2).repeatForever(autoreverses: false)) {
                halo = true
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if isBusy {
            ProgressView().tint(MemoBookColor.onAction)
        } else {
            VStack(spacing: MemoBookSpacing.xs) {
                Image(brand: "IconMic")
                    .resizable()
                    .renderingMode(.template)
                    .scaledToFit()
                    .frame(width: iconSide, height: iconSide)
                    // Un rebond court à chaque changement d'état : le micro
                    // « prend » quand on démarre. `contentTransition` ne suffit
                    // pas ici, l'image ne change pas — c'est son échelle qui dit
                    // qu'il s'est passé quelque chose.
                    .scaleEffect(isCapturing ? 1.08 : 1)
                    .animation(.spring(response: 0.3, dampingFraction: 0.45), value: isCapturing)

                Text(label)
                    .font(MemoBookFont.label)
                    // Le mot change, pas sa place : un fondu croisé, pas un
                    // remplacement sec.
                    .contentTransition(.opacity)
                    .animation(.easeInOut(duration: 0.2), value: label)
            }
            .foregroundStyle(MemoBookColor.onAction)
        }
    }

    /// Le halo qui part du disque et se dissout. Il vit **derrière** le disque,
    /// donc on n'en voit que ce qui dépasse : un anneau qui s'éloigne.
    private var haloRing: some View {
        Circle()
            .fill(MemoBookColor.action.opacity(0.25))
            .frame(width: diameter, height: diameter)
            .scaleEffect(halo ? 1.25 : 1)
            .opacity(halo ? 0 : 1)
            .allowsHitTesting(false)
    }

    /// Le disque s'enfonce sous le doigt et **rebondit** en revenant. Un simple
    /// `scaleEffect` linéaire donnait un bouton mou ; le ressort lui donne sa
    /// matière.
    private struct PressBounce: ButtonStyle {
        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .scaleEffect(configuration.isPressed ? 0.94 : 1)
                .animation(
                    .spring(response: 0.25, dampingFraction: 0.5),
                    value: configuration.isPressed
                )
        }
    }
}

#Preview("Repos") {
    RecordButton(isRecording: false) {}
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(MemoBookColor.listeningBackground)
        .environment(\.colorScheme, .light)
}

#Preview("Enregistrement") {
    RecordButton(isRecording: true, level: 0.7) {}
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(MemoBookColor.listeningBackground)
        .environment(\.colorScheme, .light)
}

#Preview("En pause") {
    RecordButton(isRecording: true, isPaused: true) {}
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(MemoBookColor.listeningBackground)
        .environment(\.colorScheme, .light)
}
