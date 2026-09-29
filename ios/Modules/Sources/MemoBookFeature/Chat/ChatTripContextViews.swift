import MemoBookCore
import MemoBookDesign
import SwiftUI

/// La pastille « Contexte du voyage 2/5 », posée sous l'en-tête du fil tant
/// que MEMO recueille le contexte.
///
/// Elle dit **où on en est** sans rien demander : la question, c'est MEMO qui
/// la pose, une à la fois. Un appui ouvre la fiche — ce que MEMO a compris,
/// ligne à ligne, et ce qui manque encore.
///
/// Même dessin que la bannière de l'aperçu (``ChatPreviewBanner``) — capsule
/// bleue sur verre dépoli —, pour que les deux se lisent comme la même famille
/// d'objets : un état du carnet, pas un message.
struct ChatTripContextBanner: View {
    let context: ChatTripContext
    let onOpen: () -> Void

    @ScaledMetric(relativeTo: .subheadline) private var ringSide: CGFloat = 18
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        Button(action: onOpen) {
            content
                .foregroundStyle(MemoBookColor.ink)
                .padding(.horizontal, MemoBookSpacing.s)
                .padding(.vertical, MemoBookSpacing.xs + 2)
                .background(MemoBookColor.bubbleTraveller.opacity(0.75), in: shape)
                .background(.ultraThinMaterial, in: shape)
                .overlay { shape.strokeBorder(MemoBookColor.outline, lineWidth: 1) }
                .contentShape(shape)
                .animation(reduceMotion ? nil : .smooth(duration: 0.45), value: context.filledCount)
        }
        .buttonStyle(CardPressStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(ChatCopy.TripContext.accessibilityLabel(filled: context.filledCount, of: context.requiredCount))
        .accessibilityHint(ChatCopy.TripContext.accessibilityHint)
        .accessibilityAddTraits(.isButton)
    }

    /// Une ligne d'ordinaire ; aux tailles accessibles, la jauge et le compte
    /// au-dessus, le titre en entier dessous — sur une seule ligne, « Contexte »
    /// se coupait au milieu du mot.
    @ViewBuilder
    private var content: some View {
        if typeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: MemoBookSpacing.xs) {
                HStack(spacing: MemoBookSpacing.xs) {
                    ring
                    count
                    Spacer(minLength: 0)
                    chevron
                }
                title
            }
        } else {
            HStack(spacing: MemoBookSpacing.xs) {
                ring
                title
                count
                chevron
            }
        }
    }

    /// Une capsule, qui devient un rectangle arrondi quand elle s'empile : une
    /// capsule de trois lignes de haut se lirait comme une pilule.
    private var shape: RoundedRectangle {
        RoundedRectangle(
            cornerRadius: typeSize.isAccessibilitySize ? MemoBookSpacing.largeCornerRadius : 999,
            style: .continuous
        )
    }

    private var ring: some View {
        ZStack {
            Circle()
                .stroke(MemoBookColor.outline, lineWidth: 2.5)
            Circle()
                .trim(from: 0, to: context.progress)
                .stroke(MemoBookColor.action, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: ringSide, height: ringSide)
    }

    private var title: some View {
        Text(ChatCopy.TripContext.title)
            .font(MemoBookFont.label)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var count: some View {
        Text("\(context.filledCount)/\(context.requiredCount)")
            .font(MemoBookFont.tagline)
            .monospacedDigit()
            .contentTransition(reduceMotion ? .identity : .numericText(value: Double(context.filledCount)))
    }

    private var chevron: some View {
        Image(systemName: "chevron.right")
            .font(.caption.weight(.semibold))
    }
}

/// La fiche du contexte : ce que MEMO a compris, ligne à ligne.
///
/// Une lecture, pas un formulaire : on ne corrige pas ici, on le **dit** à
/// MEMO, qui fond la correction avec le reste. Deux endroits pour écrire la
/// même chose finiraient par ne plus dire la même chose.
struct ChatTripContextSheet: View {
    let context: ChatTripContext

    var body: some View {
        // Pas de pastille de compte dans l'en-tête : `badge:` est lime, et le
        // lime ne dit que l'abonnement. Les lignes « À raconter » le disent.
        BrandSheet(
            ChatCopy.TripContext.title,
            subtitle: context.isGathering ? ChatCopy.TripContext.gatheringSubtitle : ChatCopy.TripContext.doneSubtitle
        ) {
            VStack(alignment: .leading, spacing: MemoBookSpacing.s) {
                BrandRowGroup(rows(context.items.filter(\.isRequired)))

                let extras = context.items.filter { !$0.isRequired }
                if !extras.isEmpty {
                    Text(ChatCopy.TripContext.extrasTitle)
                        .font(MemoBookFont.overline)
                        .foregroundStyle(MemoBookColor.inkMuted)
                        .textCase(.uppercase)
                        .accessibilityAddTraits(.isHeader)
                    BrandRowGroup(rows(extras))
                }
            }
        }
    }

    private func rows(_ items: [ChatTripContext.Item]) -> [BrandRow] {
        items.map { item in
            BrandRow(
                item.label,
                value: item.value ?? ChatCopy.TripContext.missingValue,
                valuePlacement: .below,
                valueTone: item.isFilled ? .plain : .invitation,
                isConfirmed: item.isFilled
            )
        }
    }
}

#Preview("Contexte — pastille") {
    VStack(spacing: MemoBookSpacing.m) {
        ChatTripContextBanner(context: .fixture) {}
        ChatTripContextBanner(
            context: ChatTripContext(status: .gathering, filledCount: 0, requiredCount: 5, items: [])
        ) {}
    }
    .padding()
    .background(MemoBookColor.background)
}

#Preview("Contexte — fiche") {
    Color.clear
        .background(MemoBookColor.background)
        .sheet(isPresented: .constant(true)) {
            ChatTripContextSheet(context: .fixture)
        }
}
