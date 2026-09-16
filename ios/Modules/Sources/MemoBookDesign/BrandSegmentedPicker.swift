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
    /// Les deux tailles du rail.
    public enum Size {
        /// Le rail pleine page : deux libellés en typographie de bouton, 50 pt
        /// de haut. Celui de l'écran d'entrée.
        case regular

        /// Le rail posé **dans** un écran, au-dessus de ce qu'il commande : les
        /// deux plats de couverture. Plus bas, plus léger, cerclé du filet
        /// discret plutôt que de l'encre — il range le contenu, il ne l'annonce
        /// pas. C'est ce que dessine la maquette des couvertures.
        case compact
    }

    private let values: [Value]
    private let title: (Value) -> String
    private let size: Size
    private let isAvailable: (Value) -> Bool
    private let onUnavailable: ((Value) -> Void)?
    @Binding private var selection: Value

    /// - Parameters:
    ///   - isAvailable: ce segment mène-t-il quelque part. Un segment
    ///     indisponible reste **lisible et tapable** : il pâlit, il n'est pas
    ///     retiré, et son appui appelle `onUnavailable` au lieu de changer la
    ///     sélection. C'est la seule façon d'expliquer *pourquoi* on ne peut
    ///     pas y aller — un `disabled` du système avale le geste et ne dit
    ///     rien (Hugo, 16/09/2026).
    ///   - onUnavailable: ce qu'on fait de cet appui. Poser un message,
    ///     toujours : un segment qui ne répond pas se lit comme une panne.
    public init(
        _ values: [Value],
        selection: Binding<Value>,
        size: Size = .regular,
        isAvailable: @escaping (Value) -> Bool = { _ in true },
        onUnavailable: ((Value) -> Void)? = nil,
        title: @escaping (Value) -> String
    ) {
        self.values = values
        self._selection = selection
        self.size = size
        self.isAvailable = isAvailable
        self.onUnavailable = onUnavailable
        self.title = title
    }

    @Namespace private var pill
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Aux tailles de texte accessibles, deux libellés côte à côte ne tiennent
    /// plus : « Inscription » passe à la ligne et déborde de son rail. Les
    /// segments s'empilent alors, et la pastille glisse verticalement — le
    /// `matchedGeometryEffect` s'en charge sans rien changer d'autre.
    @Environment(\.dynamicTypeSize) private var typeSize

    @ScaledMetric(relativeTo: .body) private var regularHeight: CGFloat = 50
    @ScaledMetric(relativeTo: .body) private var compactHeight: CGFloat = 34

    private var segmentHeight: CGFloat {
        switch size {
        case .regular: regularHeight
        case .compact: compactHeight
        }
    }

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
            let available = isAvailable(value)

            Button {
                // Un segment fermé **ne change pas la sélection** : il explique.
                guard available else {
                    onUnavailable?(value)
                    return
                }
                selection = value
            } label: {
                Text(title(value))
                    .font(size == .regular ? MemoBookFont.button : MemoBookFont.tagline)
                    .multilineTextAlignment(.center)
                    // Un libellé trop long **passe à la ligne**, il ne se coupe
                    // pas : en taille accessible, « 1re de couverture » se
                    // rendait « 1re de couvert… », et deux segments tronqués au
                    // même endroit ne se distinguent plus l'un de l'autre.
                    .fixedSize(horizontal: false, vertical: true)
                    .foregroundStyle(value == selection ? MemoBookColor.onAction : MemoBookColor.ink)
                    // Pâli, pas effacé : il faut encore pouvoir le lire pour
                    // comprendre le message qu'il pose.
                    .opacity(available ? 1 : 0.4)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: segmentHeight)
                    .padding(.horizontal, MemoBookSpacing.xs)
                    .contentShape(pillShape)
            }
            .buttonStyle(.plain)
            .background {
                if value == selection {
                    pillShape
                        .fill(MemoBookColor.action)
                        .matchedGeometryEffect(id: "pill", in: pill)
                }
            }
            .accessibilityAddTraits(value == selection ? [.isButton, .isSelected] : .isButton)
            // VoiceOver doit l'entendre avant de taper, pas après : « non
            // disponible » suit le libellé.
            .accessibilityValue(available ? "" : "Non disponible")
        }
    }

    /// Rayon fixe plutôt qu'une `Capsule` : sur un seul segment de 50 pt les
    /// deux se confondent, mais dès que le libellé passe à deux lignes la
    /// capsule devient une ellipse.
    private var pillShape: RoundedRectangle {
        .rect(cornerRadius: size == .regular ? 21 : 17, style: .continuous)
    }

    @ViewBuilder
    private var rail: some View {
        let shape = RoundedRectangle(cornerRadius: size == .regular ? 25 : 21, style: .continuous)

        // Le rail compact garde son aplat blanc dans tous les cas : posé au
        // milieu d'un écran plutôt qu'au-dessus de lui, le verre n'aurait rien
        // à laisser transparaître.
        if #available(iOS 26.0, *), size == .regular {
            shape
                .fill(.clear)
                .glassEffect(.regular, in: shape)
                .overlay { shape.strokeBorder(MemoBookColor.ink, lineWidth: 1) }
        } else {
            shape
                .fill(size == .regular ? MemoBookColor.background : MemoBookColor.surface)
                .overlay { shape.strokeBorder(railBorder, lineWidth: 1) }
        }
    }

    /// Le filet du rail : l'encre pleine sur le rail d'entrée, le filet discret
    /// sur le rail compact — c'est ce que dessine la maquette des couvertures,
    /// et une bordure à l'encre y ferait un cadre.
    private var railBorder: Color {
        size == .regular ? MemoBookColor.ink : MemoBookColor.hairline
    }
}
