import SwiftUI

/// Le curseur de MemoBook : un rail, une poignée, et les crans nommés sous le
/// rail.
///
/// **Ce n'est pas le `Slider` du système**, et ce n'est pas un caprice de
/// dessin : la maquette pose une poignée crème cerclée avec un point bleu au
/// centre, un rail de 6 pt et — surtout — **les valeurs écrites sous les
/// crans**, celle du moment en gras. Rien de tout ça ne se règle sur le
/// `Slider` d'iOS, dont seul le `tint` est ouvert.
///
/// **Ce qu'on perd en le dessinant, on le rend à la main.** Un curseur du
/// système est « ajustable » pour VoiceOver : on le sélectionne, et on monte ou
/// descend d'un cran au balayage vertical. C'est exactement ce que fait
/// `accessibilityAdjustableAction` ici — donc le geste d'assistance est le même
/// que partout ailleurs sur iOS, à un dessin près.
///
/// ```swift
/// BrandSlider(
///     value: $ratio,
///     in: 0...100,
///     step: 25,
///     ticks: ["0%", "25%", "50%", "75%", "100%"],
///     leadingLabel: "Plus de texte",
///     trailingLabel: "Plus de photos"
/// )
/// ```
public struct BrandSlider: View {
    @Binding private var value: Int
    private let bounds: ClosedRange<Int>
    private let step: Int
    private let ticks: [String]
    private let leadingLabel: String?
    private let trailingLabel: String?
    private let voiceLabel: String
    private let voiceValue: (Int) -> String

    /// - Parameters:
    ///   - step: le pas, **et l'écart entre deux crans écrits**. Les deux sont
    ///     le même nombre : un curseur qui s'arrête ailleurs que sous une
    ///     étiquette ferait douter de ce qu'on vient de choisir.
    ///   - ticks: les valeurs écrites sous le rail, de la borne basse à la
    ///     haute. Autant d'entrées que de crans.
    ///   - leadingLabel: ce que dit la borne gauche — « Plus de texte ». `nil`
    ///     quand la ligne au-dessus du rail porte déjà une phrase entière, comme
    ///     sur « Décorations & stickers ».
    ///   - voiceValue: comment VoiceOver annonce la valeur. Par défaut le
    ///     nombre nu ; « 50 % » ou « 2 décorations » valent mieux.
    public init(
        value: Binding<Int>,
        in bounds: ClosedRange<Int>,
        step: Int,
        ticks: [String],
        leadingLabel: String? = nil,
        trailingLabel: String? = nil,
        voiceLabel: String,
        voiceValue: @escaping (Int) -> String = { "\($0)" }
    ) {
        _value = value
        self.bounds = bounds
        self.step = max(1, step)
        self.ticks = ticks
        self.leadingLabel = leadingLabel
        self.trailingLabel = trailingLabel
        self.voiceLabel = voiceLabel
        self.voiceValue = voiceValue
    }

    /// Diamètre de la poignée. **Fixe, hors Dynamic Type** : c'est une cible
    /// tactile et un dessin, pas du texte — et la faire grandir décalerait le
    /// rail sous les étiquettes, qui, elles, grandissent d'un autre facteur.
    private static let thumbSide: CGFloat = 24
    private static let trackHeight: CGFloat = 6
    /// Largeur réservée à chaque étiquette de cran. Celle de la maquette : elle
    /// tient « 100 % » sans pousser ses voisines.
    private static let tickWidth: CGFloat = 32

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public var body: some View {
        VStack(alignment: .leading, spacing: MemoBookSpacing.snug) {
            if leadingLabel != nil || trailingLabel != nil {
                HStack(spacing: MemoBookSpacing.xs) {
                    if let leadingLabel {
                        Text(leadingLabel)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    if let trailingLabel {
                        Text(trailingLabel)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                }
                .font(MemoBookFont.tagline)
                .foregroundStyle(MemoBookColor.inkMuted)
                .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: MemoBookSpacing.xs + 2) {
                track
                tickLabels
            }
        }
        // **Un seul élément pour VoiceOver**, et il est ajustable : le rail, la
        // poignée et les étiquettes sont un seul contrôle, pas cinq textes à
        // parcourir un par un.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(voiceLabel)
        .accessibilityValue(voiceValue(value))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: move(by: step)
            case .decrement: move(by: -step)
            @unknown default: break
            }
        }
    }

    // MARK: - Le rail

    private var track: some View {
        GeometryReader { proxy in
            // La poignée reste **entière dans le cadre** : elle va de son rayon
            // au bord opposé moins son rayon. Sans ça, elle sortirait d'une
            // demi-poignée à chaque bout et se ferait rogner par la feuille.
            let travel = max(0, proxy.size.width - Self.thumbSide)
            let center = Self.thumbSide / 2 + travel * fraction

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(MemoBookColor.hairline)
                    .frame(height: Self.trackHeight)

                Capsule()
                    .fill(MemoBookColor.outline)
                    .frame(width: center, height: Self.trackHeight)

                thumb.offset(x: center - Self.thumbSide / 2)
            }
            .frame(height: Self.thumbSide)
            .contentShape(.rect)
            // Le doigt se pose **n'importe où sur le rail** et la poignée vient
            // à lui : viser une pastille de 24 pt au bout d'un rail de 342 est
            // un jeu d'adresse, pas un réglage.
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        guard travel > 0 else { return }
                        let ratio = (drag.location.x - Self.thumbSide / 2) / travel
                        set(fraction: ratio)
                    }
            )
        }
        .frame(height: Self.thumbSide)
    }

    private var thumb: some View {
        Circle()
            .fill(MemoBookColor.surface)
            .overlay { Circle().strokeBorder(MemoBookColor.hairline, lineWidth: 1) }
            .overlay {
                Circle()
                    .fill(MemoBookColor.outline)
                    .frame(width: MemoBookSpacing.xs, height: MemoBookSpacing.xs)
            }
            .frame(width: Self.thumbSide, height: Self.thumbSide)
            .brandShadow(.soft)
            // Elle saute d'un cran à l'autre, elle ne glisse pas sous le doigt :
            // c'est le pas qui commande, et le petit ressort dit qu'on vient
            // d'en franchir un.
            .animation(reduceMotion ? .none : .snappy(duration: 0.18), value: value)
    }

    // MARK: - Les crans écrits

    private var tickLabels: some View {
        HStack(spacing: 0) {
            ForEach(Array(ticks.enumerated()), id: \.offset) { index, tick in
                Text(tick)
                    // Celui du moment est en gras : c'est **là** qu'on lit la
                    // valeur choisie, la poignée ne fait que la montrer.
                    .font(index == selectedTick ? MemoBookFont.tagline : MemoBookFont.caption)
                    .foregroundStyle(
                        index == selectedTick ? MemoBookColor.ink : MemoBookColor.inkMuted
                    )
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .frame(width: Self.tickWidth)

                if index < ticks.count - 1 { Spacer(minLength: 0) }
            }
        }
        .animation(reduceMotion ? .none : .snappy(duration: 0.18), value: selectedTick)
    }

    // MARK: - Les valeurs

    private var span: Double { Double(bounds.upperBound - bounds.lowerBound) }

    private var fraction: CGFloat {
        guard span > 0 else { return 0 }
        return CGFloat((Double(value) - Double(bounds.lowerBound)) / span)
    }

    /// L'étiquette sous laquelle la poignée se trouve. `nil` si les crans ne
    /// correspondent pas aux pas — l'appelant s'est trompé, mais l'écran ne doit
    /// pas s'en trouver mal.
    private var selectedTick: Int? {
        let index = (value - bounds.lowerBound) / step
        return ticks.indices.contains(index) ? index : nil
    }

    private func set(fraction ratio: CGFloat) {
        let raw = Double(bounds.lowerBound) + Double(ratio.clamped(to: 0...1)) * span
        let stepped = (raw / Double(step)).rounded() * Double(step)
        let next = Int(stepped).clamped(to: bounds)
        guard next != value else { return }
        value = next
    }

    private func move(by delta: Int) {
        let next = (value + delta).clamped(to: bounds)
        guard next != value else { return }
        value = next
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}

#Preview("Curseur") {
    @Previewable @State var ratio = 50
    @Previewable @State var decorations = 2

    return VStack(spacing: MemoBookSpacing.xl) {
        BrandSlider(
            value: $ratio,
            in: 0...100,
            step: 25,
            ticks: ["0%", "25%", "50%", "75%", "100%"],
            leadingLabel: "Plus de texte",
            trailingLabel: "Plus de photos",
            voiceLabel: "Ratio média",
            voiceValue: { "\($0) pour cent de photos" }
        )

        BrandSlider(
            value: $decorations,
            in: 0...4,
            step: 1,
            ticks: ["0", "1", "2", "3", "4"],
            leadingLabel: "Quantité de décorations par paragraphe ou image",
            voiceLabel: "Quantité de décorations"
        )
    }
    .padding(MemoBookSpacing.screenMargin)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(MemoBookColor.surface)
    .environment(\.colorScheme, .light)
}
