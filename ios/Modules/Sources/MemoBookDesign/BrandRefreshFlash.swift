import SwiftUI

/// L'animation qui dit **« ça vient de changer »**.
///
/// Elle sert un cas et un seul : un écran s'est ouvert sur ce qu'on avait en
/// cache, le serveur a répondu autre chose, et la page s'est mise à jour sous
/// les yeux de quelqu'un qui la regardait déjà. Sans elle, la différence entre
/// « rien ne s'est passé » et « trois valeurs viennent de bouger » est
/// invisible — et c'est précisément ce que le cache introduit comme risque.
///
/// **Un geste, et pas deux.** Un voile clair qui traverse le bloc de gauche à
/// droite — la lumière qu'on passe sur une page qu'on vient de réécrire — et,
/// pour qui ne voit pas, l'annonce « Mis à jour » de VoiceOver. Ni rebond, ni
/// changement de couleur, ni son : ce n'est pas une réussite qu'on célèbre,
/// c'est une information qu'on signale.
///
/// La **pastille** « Mis à jour » qui descendait du haut n'est plus posée par
/// défaut (Hugo, 17/09/2026) : elle prenait trop de place sur le contenu, et
/// le clignotement des chiffres qui changent suffit. Elle reste disponible
/// (`showsBadge:`) pour le jour où un changement le mérite — l'aperçu PDF qui
/// se recompose, par exemple.
///
/// **Rien ne bouge en Reduce Motion** : le balayage s'éteint, et l'annonce
/// VoiceOver reste. C'est l'information qui compte ; le balayage n'en est que
/// l'emballage, et c'est exactement ce que ce réglage demande d'éteindre.
///
/// ```swift
/// VStack { … }
///     .brandRefreshFlash(model.freshness.isUpdated)
/// ```
public extension View {
    /// - Parameters:
    ///   - isUpdated: passe à `true` quand le contenu vient de changer. Le
    ///     modificateur se charge de le remettre à `false` tout seul : il ne
    ///     demande pas à l'appelant de gérer une durée.
    ///   - showsBadge: pose aussi la pastille « Mis à jour » en haut du bloc.
    ///     Éteinte partout aujourd'hui — voir l'en-tête.
    func brandRefreshFlash(_ isUpdated: Bool, showsBadge: Bool = false) -> some View {
        modifier(BrandRefreshFlash(isUpdated: isUpdated, badgeEnabled: showsBadge))
    }
}

private struct BrandRefreshFlash: ViewModifier {
    let isUpdated: Bool
    let badgeEnabled: Bool

    /// Où en est le balayage, de -1 (hors cadre à gauche) à 1 (hors cadre à
    /// droite).
    @State private var sweep: CGFloat = -1
    @State private var showsBadge = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Le temps que la pastille reste. Assez pour être lue en levant les yeux,
    /// assez court pour ne pas devenir un élément de l'écran.
    private static let badgeDuration: Duration = .seconds(1.8)

    func body(content: Content) -> some View {
        content
            .overlay { if !reduceMotion { sweepLayer } }
            .overlay(alignment: .top) { badge }
            .onChange(of: isUpdated) { _, updated in
                guard updated else { return }
                play()
            }
    }

    /// Le voile qui traverse. Il ne teinte rien : c'est du blanc à 35 %, dont
    /// les deux bords sont transparents — sur le crème de la marque il se lit
    /// comme un reflet, pas comme une couleur.
    private var sweepLayer: some View {
        GeometryReader { proxy in
            LinearGradient(
                stops: [
                    .init(color: .white.opacity(0), location: 0),
                    .init(color: .white.opacity(0.35), location: 0.5),
                    .init(color: .white.opacity(0), location: 1),
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(width: proxy.size.width * 0.6)
            .offset(x: sweep * proxy.size.width)
        }
        // Il traverse, il ne se touche pas : sans ça il avalerait les gestes du
        // bloc qu'il recouvre pendant toute sa durée.
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .clipped()
    }

    @ViewBuilder
    private var badge: some View {
        if showsBadge {
            Text("Mis à jour")
                .font(MemoBookFont.overline)
                .foregroundStyle(MemoBookColor.onAction)
                .padding(.horizontal, MemoBookSpacing.s)
                .padding(.vertical, MemoBookSpacing.xs / 2)
                .background(MemoBookColor.action, in: .capsule)
                .brandShadow(.soft)
                .transition(
                    reduceMotion
                        ? .opacity
                        : .move(edge: .top).combined(with: .opacity)
                )
                // VoiceOver l'annonce sans interrompre la lecture en cours : on
                // ne coupe pas quelqu'un au milieu d'un paragraphe pour lui
                // dire qu'une date a bougé.
                .accessibilityAddTraits(.updatesFrequently)
        }
    }

    private func play() {
        if !reduceMotion {
            sweep = -1
            withAnimation(.easeInOut(duration: 0.9)) { sweep = 1 }
        }

        // Sans pastille, c'est l'annonce qui dit à VoiceOver que la page a
        // bougé — sans interrompre la lecture en cours.
        AccessibilityNotification.Announcement("Mis à jour").post()

        guard badgeEnabled else { return }
        withAnimation(.snappy(duration: 0.3)) { showsBadge = true }

        Task { @MainActor in
            try? await Task.sleep(for: Self.badgeDuration)
            withAnimation(.snappy(duration: 0.3)) { showsBadge = false }
        }
    }
}

#Preview("Mise à jour en direct") {
    struct Harness: View {
        @State private var isUpdated = false
        @State private var days = 12

        var body: some View {
            VStack(spacing: MemoBookSpacing.m) {
                VStack(alignment: .leading, spacing: MemoBookSpacing.xs) {
                    Text("Rome et la Dolce Vita")
                        .font(MemoBookFont.cardTitle)
                    Text("\(days) jours de voyage")
                        .font(MemoBookFont.body)
                        .contentTransition(.numericText())
                }
                .padding(MemoBookSpacing.s)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    MemoBookColor.surface,
                    in: .rect(cornerRadius: MemoBookSpacing.largeCornerRadius)
                )
                .brandRefreshFlash(isUpdated)

                Button("Le serveur répond autre chose") {
                    withAnimation { days += 1 }
                    isUpdated = true
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(100))
                        isUpdated = false
                    }
                }
                .buttonStyle(.bordered)
                .tint(MemoBookColor.action)
            }
            .padding(MemoBookSpacing.screenMargin)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(MemoBookColor.background)
            .environment(\.colorScheme, .light)
        }
    }

    return Harness()
}
