import MemoBookDesign
import SwiftUI

/// **Ce qu'un voyage créé hors ligne ne peut pas encore faire** (T239, Hugo,
/// 06/10/2026).
///
/// Tant que le serveur ne l'a pas reçu, un voyage n'existe que sur le
/// téléphone : on y raconte (la file garde tout), mais ses réglages,
/// « Inviter un proche », l'aperçu du carnet et la commande sont des écrans
/// **du serveur** — ils s'ouvraient sur son erreur, un 404 ou une panne. Ces
/// portes-là **pâlissent** au lieu de mener à un écran cassé : elles restent
/// tapables, et l'appui dit pourquoi et quand elles s'ouvriront — la règle
/// « ce qu'on ne peut pas faire pâlit, ça ne se désactive pas »
/// (`ios/CLAUDE.md`).
///
/// L'ensemble des voyages en attente vient de la file
/// (``RecordingOutbox/localTrips``), posé une fois par `RootView` sur la pile
/// de navigation : l'accueil, l'écran du voyage et la conversation le lisent
/// sans connaître la file. Le voyage arrivé, il sort de l'ensemble et les
/// portes se rallument d'elles-mêmes.
enum TripAwaitingServer {
    /// L'opacité d'une commande qui attend le serveur — celle des autres
    /// contrôles pâlis de l'app (40–45 %).
    static let dimmedOpacity = 0.45

    /// La boîte posée à l'appui. La phrase de Hugo en tête, puis la cause.
    static let notice =
        "**Disponible dès ta reconnexion.** Ton voyage a été créé hors ligne : il n’est encore que sur ton téléphone."

    /// Ce que VoiceOver entend sur une commande pâlie, avant de la toucher.
    static let hint = "Disponible dès ta reconnexion"

    /// Combien de temps la boîte reste, si on ne la touche pas.
    static let noticeDuration: Duration = .seconds(4)
}

extension EnvironmentValues {
    /// Les voyages que le serveur n'a pas encore reçus — voir
    /// ``TripAwaitingServer``. Vide hors de la pile de l'app, donc dans les
    /// aperçus : tout y est ouvert.
    @Entry var tripsAwaitingServer: Set<String> = []
}

extension View {
    /// Pâlit une commande qui attend le serveur, et le dit à VoiceOver. Elle
    /// reste tapable : c'est à son action de poser la boîte.
    func dimmedWhileAwaitingServer(_ isAwaiting: Bool) -> some View {
        opacity(isAwaiting ? TripAwaitingServer.dimmedOpacity : 1)
            .accessibilityHint(isAwaiting ? TripAwaitingServer.hint : "")
    }

    /// La boîte « Disponible dès ta reconnexion », posée en haut de l'écran le
    /// temps de la lire.
    ///
    /// - Parameter below: le bas des commandes de l'en-tête, **en coordonnées
    ///   de l'écran** : la boîte se pose dessous, pour ne pas les recouvrir.
    ///   En coordonnées de l'écran parce que les deux écrans qui s'en servent
    ///   passent sous la barre d'état chacun à sa façon — même mesure que la
    ///   bannière de l'aperçu de la conversation.
    func awaitingServerNotice(isPresented: Binding<Bool>, below: CGFloat) -> some View {
        modifier(AwaitingServerNotice(isPresented: isPresented, below: below))
    }
}

private struct AwaitingServerNotice: ViewModifier {
    @Binding var isPresented: Bool
    let below: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .top) {
                if isPresented {
                    GeometryReader { proxy in
                        BrandNotice(TripAwaitingServer.notice, tone: .information) { EmptyView() }
                            // La boîte d'information a un aplat très clair :
                            // posée sur une photo, elle a besoin du papier
                            // dessous.
                            .background(
                                MemoBookColor.background,
                                in: .rect(cornerRadius: MemoBookSpacing.largeCornerRadius)
                            )
                            .brandShadow(.raised)
                            .padding(.horizontal, MemoBookSpacing.screenMargin)
                            .padding(.top, max(0, below - proxy.frame(in: .global).minY) + MemoBookSpacing.xs)
                            // Toucher la boîte la referme : elle a été lue.
                            .onTapGesture { isPresented = false }
                    }
                    .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
                    .task {
                        AccessibilityNotification.Announcement(TripAwaitingServer.hint).post()
                        try? await Task.sleep(for: TripAwaitingServer.noticeDuration)
                        guard !Task.isCancelled else { return }
                        isPresented = false
                    }
                }
            }
            .animation(reduceMotion ? nil : .snappy(duration: 0.25), value: isPresented)
    }
}
