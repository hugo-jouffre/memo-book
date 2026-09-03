import SwiftUI

/// Sélecteur à segments aux couleurs de la marque.
///
/// La pastille verte ne se redessine pas d'un segment à l'autre : c'est la
/// **même** vue qui se déplace, via `matchedGeometryEffect`. C'est ce qui donne
/// le glissé continu d'un segment iOS natif plutôt qu'un fondu entre deux états.
///
/// Sur iOS 26, le rail prend un fond Liquid Glass ; avant, il garde l'aplat
/// crème cerclé de la maquette. La pastille, elle, reste un aplat vert dans les
/// deux cas : c'est une couleur de marque, la passer en verre la délaverait.
public struct BrandSegmentedPicker<Value: Hashable & Identifiable>: View {
    private let values: [Value]
    private let title: (Value) -> String
    @Binding private var selection: Value

    public init(
        _ values: [Value],
        selection: Binding<Value>,
        title: @escaping (Value) -> String
    ) {
        self.values = values
        self._selection = selection
        self.title = title
    }

    @Namespace private var pill
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Aux tailles de texte accessibles, deux libellés côte à côte ne tiennent
    /// plus : « Inscription » passe à la ligne et déborde de son rail. Les
    /// segments s'empilent alors, et la pastille glisse verticalement — le
    /// `matchedGeometryEffect` s'en charge sans rien changer d'autre.
    @Environment(\.dynamicTypeSize) private var typeSize

    @ScaledMetric(relativeTo: .body) private var segmentHeight: CGFloat = 50

    private var isStacked: Bool { typeSize.isAccessibilitySize }

    public var body: some View {
        layout
            .padding(4)
            .background { rail }
            .animation(reduceMotion ? .none : .snappy(duration: 0.35, extraBounce: 0.1), value: selection)
            // VoiceOver et Voice Control annoncent un sélecteur, pas deux
            // boutons sans lien l'un avec l'autre.
            .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var layout: some View {
        if isStacked {
            VStack(spacing: 4) { segments }
        } else {
            HStack(spacing: 0) { segments }
        }
    }

    private var segments: some View {
        ForEach(values) { value in
            Button {
                selection = value
            } label: {
                Text(title(value))
                    .font(MemoBookFont.button)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(value == selection ? MemoBookColor.onAction : MemoBookColor.ink)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: segmentHeight)
                    .padding(.horizontal, MemoBookSpacing.xs)
                    .contentShape(Self.pillShape)
            }
            .buttonStyle(.plain)
            .background {
                if value == selection {
                    Self.pillShape
                        .fill(MemoBookColor.action)
                        .matchedGeometryEffect(id: "pill", in: pill)
                }
            }
            .accessibilityAddTraits(value == selection ? [.isButton, .isSelected] : .isButton)
        }
    }

    /// Rayon fixe plutôt qu'une `Capsule` : sur un seul segment de 50 pt les
    /// deux se confondent, mais dès que le libellé passe à deux lignes la
    /// capsule devient une ellipse.
    private static var pillShape: RoundedRectangle {
        .rect(cornerRadius: 21, style: .continuous)
    }

    @ViewBuilder
    private var rail: some View {
        let shape = RoundedRectangle(cornerRadius: 25, style: .continuous)

        if #available(iOS 26.0, *) {
            shape
                .fill(.clear)
                .glassEffect(.regular, in: shape)
                .overlay { shape.strokeBorder(MemoBookColor.ink, lineWidth: 1) }
        } else {
            shape
                .fill(MemoBookColor.background)
                .overlay { shape.strokeBorder(MemoBookColor.ink, lineWidth: 1) }
        }
    }
}
