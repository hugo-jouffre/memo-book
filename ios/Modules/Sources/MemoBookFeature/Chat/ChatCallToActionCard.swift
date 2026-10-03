import Foundation
import MemoBookCore
import MemoBookDesign
import SwiftUI

/// **La carte d'une bulle de MEMO qui porte un bouton** — ``ChatCallToAction``
/// (maquettes `3653:17090` et, une fois touchée, `3653:17213` ; 03/10/2026).
///
/// C'est une bulle de MEMO comme les autres — ``BrandChatBubble``, sa queue,
/// son blanc —, avec trois choses de plus, de haut en bas :
///
/// 1. **l'en-tête manuscrit**, « ✦ » et l'``ChatCallToAction/eyebrow`` en
///    ``MemoBookFont/handwriting`` vert : MEMO annote sa propre bulle, comme on
///    écrit un mot dans la marge du carnet ;
/// 2. sous le texte et un filet, **la ligne d'action**, centrée, icône et
///    libellé en vert d'action ;
/// 3. sous un second filet, **« Ignorer »**, centré, en gris — si le bouton
///    se laisse ignorer.
///
/// **Touchée**, l'action s'exécute, la ligne passe au bleu du texte
/// (``MemoBookColor/blueText``) et « Ignorer » s'en va : on voit ce qu'on a
/// déjà ouvert, et on peut y retourner. **Ignorée**, l'en-tête, la ligne et
/// « Ignorer » s'en vont : la bulle redevient une bulle. L'état se retient sur
/// l'appareil, par bulle (``ChatCallToActionMemory``).
///
/// **Réutilisable tel quel** : elle ne sait rien de l'abonnement ni des
/// photos. Le bouton est décrit par ``ChatCallToAction`` ; ce qu'il ouvre, c'est
/// l'écran qui le décide (``ChatView``). Un ``ChatCallToAction/Kind/unknown(_:)``
/// ne montre pas de bouton, ni « s'abonner » à un abonné :
/// ``ChatModel/showsCallToAction(_:)`` le dit avant qu'on la pose.
struct ChatCallToActionCard: View {
    let text: String
    let callToAction: ChatCallToAction
    let state: ChatCallToActionState
    let onFollow: () -> Void
    let onDismiss: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .body) private var iconSide: CGFloat = 20

    var body: some View {
        BrandChatBubble(author: .memo) {
            VStack(alignment: .leading, spacing: MemoBookSpacing.xs) {
                if state != .dismissed, let eyebrow = callToAction.eyebrow, !eyebrow.isEmpty {
                    header(eyebrow)
                }

                Text(text)
                    .font(MemoBookFont.bubble)
                    .foregroundStyle(MemoBookColor.ink)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)

                if state != .dismissed {
                    VStack(spacing: 0) {
                        rule
                        actionRow
                        if callToAction.dismissible, state == .pending {
                            rule
                            dismissRow
                        }
                    }
                    .transition(.opacity)
                }
            }
        }
        .animation(reduceMotion ? nil : .smooth(duration: 0.25), value: state)
    }

    /// « ✦ Crédit du jour épuisé », à la main, en vert.
    private func header(_ eyebrow: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: MemoBookSpacing.xs / 2) {
            Text(ChatCopy.CallToAction.star)
                .font(MemoBookFont.label)
                .accessibilityHidden(true)
            Text(eyebrow)
                .font(MemoBookFont.handwriting)
        }
        .foregroundStyle(MemoBookColor.action)
        .accessibilityElement(children: .combine)
    }

    /// Le filet qui sépare le texte de ce qu'on peut en faire.
    private var rule: some View {
        Rectangle()
            .fill(MemoBookColor.hairline)
            .frame(height: 1)
            .accessibilityHidden(true)
    }

    /// La ligne d'action : verte tant qu'elle n'a pas servi, bleue ensuite.
    private var actionRow: some View {
        Button(action: onFollow) {
            HStack(spacing: MemoBookSpacing.xs) {
                Image(brand: Self.icon(for: callToAction.kind))
                    .resizable()
                    .renderingMode(.template)
                    .scaledToFit()
                    .frame(width: iconSide, height: iconSide)
                    .accessibilityHidden(true)
                Text(callToAction.label)
                    .font(MemoBookFont.bubbleAction)
                    .multilineTextAlignment(.center)
            }
            .foregroundStyle(state == .followed ? MemoBookColor.blueText : MemoBookColor.action)
            .frame(maxWidth: .infinity, minHeight: MemoBookSpacing.minimumTapTarget)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(callToAction.label)
        .accessibilityValue(state == .followed ? ChatCopy.CallToAction.followed : "")
        .accessibilityAddTraits(.isButton)
    }

    private var dismissRow: some View {
        Button(action: onDismiss) {
            Text(ChatCopy.CallToAction.dismiss)
                .font(MemoBookFont.bubble)
                .foregroundStyle(MemoBookColor.inkMuted)
                .frame(maxWidth: .infinity, minHeight: MemoBookSpacing.minimumTapTarget)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    /// L'icône de la ligne d'action, par genre de bouton. Celle de
    /// « Modifier l’autorisation » est celle de la maquette ; les autres
    /// reprennent l'icône que l'app montre déjà pour la même destination.
    static func icon(for kind: ChatCallToAction.Kind) -> String {
        switch kind {
        case .subscribe: "IconLucideSparkles"
        case .openTripSettings: "IconSettings"
        case .openPreview: "IconBook"
        case .importPhotos: "IconLucideCamera"
        case .openPhotoSettings: "IconPictureFrame"
        case .unknown: "IconArrowRight"
        }
    }
}

/// Ce qu'on a fait des boutons posés sous les bulles de MEMO, **retenu sur
/// l'appareil** — touché ou ignoré, par identifiant de bulle.
///
/// Sur l'appareil et non sur le serveur : c'est l'état d'un geste, pas un
/// fait du récit, et un co-voyageur qui ignore « Raconter sans limite » ne
/// l'ignore pas pour les autres. Seuls les gestes s'écrivent — une bulle
/// sans trace est en attente —, ce qui garde la liste à quelques lignes par
/// voyage.
@MainActor
public final class ChatCallToActionMemory {
    private let defaults: UserDefaults?
    private var states: [String: String]

    /// La clé dans les réglages de l'appareil.
    static let key = "memobook.chat.callToActionStates"

    /// Les réglages de l'appareil — l'app.
    public static let standard = ChatCallToActionMemory(defaults: .standard)

    /// Rien sur le disque — les aperçus et les tests.
    public static func inMemory() -> ChatCallToActionMemory {
        ChatCallToActionMemory(defaults: nil)
    }

    public init(defaults: UserDefaults?) {
        self.defaults = defaults
        states = defaults?.dictionary(forKey: Self.key) as? [String: String] ?? [:]
    }

    func state(for messageId: String) -> ChatCallToActionState {
        states[messageId].flatMap(ChatCallToActionState.init(rawValue:)) ?? .pending
    }

    func remember(_ state: ChatCallToActionState, for messageId: String) {
        states[messageId] = state.rawValue
        defaults?.set(states, forKey: Self.key)
    }
}

// MARK: - Aperçus

#Preview("Carte d’appel à l’action — ses trois états") {
    ScrollView {
        VStack(alignment: .leading, spacing: MemoBookSpacing.s) {
            ChatCallToActionCard(
                text: DailyCreditCopy.exhaustedMessage,
                callToAction: .dailyCreditSubscribe,
                state: .pending,
                onFollow: {},
                onDismiss: {}
            )
            ChatCallToActionCard(
                text: DailyCreditCopy.exhaustedMessage,
                callToAction: .dailyCreditSubscribe,
                state: .followed,
                onFollow: {},
                onDismiss: {}
            )
            ChatCallToActionCard(
                text: DailyCreditCopy.exhaustedMessage,
                callToAction: .dailyCreditSubscribe,
                state: .dismissed,
                onFollow: {},
                onDismiss: {}
            )
            ChatCallToActionCard(
                text: ChatFixtureCopy.limitedPhotosMessage,
                callToAction: ChatFixtureCopy.limitedPhotosCallToAction,
                state: .pending,
                onFollow: {},
                onDismiss: {}
            )
        }
        .padding(MemoBookSpacing.snug)
    }
    .background(MemoBookColor.background)
    .environment(\.colorScheme, .light)
}
