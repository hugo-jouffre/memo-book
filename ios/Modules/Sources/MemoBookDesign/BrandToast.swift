import SwiftUI

/// **Le message qui passe** : une phrase qui s'affiche, se lit, et s'en va
/// toute seule (Hugo, 10/11/2026 — « un popup temporaire de 3 sec devrait
/// indiquer "Tu as rejoint le voyage de X" »).
///
/// C'est **le** composant de ce rôle, et il se distingue de ses voisins :
///
/// - ``BrandNotice`` reste tant que la cause reste — il explique un état, on y
///   revient ;
/// - `ErrorBanner` demande un geste — réessayer, écrire au support ;
/// - celui-ci **ne demande rien**. Il confirme ce qui vient d'arriver, puis il
///   libère l'écran. Rien ne doit en dépendre : ce qu'il dit est déjà vrai
///   ailleurs — le voyage est dans la liste, la page est ouverte.
///
/// Il se pose en haut, sous la barre d'état, parce que le bas de l'écran
/// appartient aux actions et que sa place doit être la même partout.
public struct BrandToast: View {
    private let message: String

    public init(_ message: String) {
        self.message = message
    }

    public var body: some View {
        Text(message)
            .font(MemoBookFont.bodySemibold)
            .foregroundStyle(MemoBookColor.ink)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, MemoBookSpacing.s)
            .padding(.vertical, MemoBookSpacing.snug)
            .background(
                MemoBookColor.surface,
                in: .rect(cornerRadius: MemoBookSpacing.largeCornerRadius)
            )
            .overlay {
                RoundedRectangle(cornerRadius: MemoBookSpacing.largeCornerRadius)
                    .strokeBorder(MemoBookColor.hairline, lineWidth: 1)
            }
            .brandShadow(.soft)
            .padding(.horizontal, MemoBookSpacing.screenMargin)
            // Une phrase qui s'en va toute seule doit être **lue** par
            // VoiceOver au moment où elle arrive : sans ça, elle n'existe pas
            // pour qui ne voit pas l'écran.
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isStaticText)
    }
}

/// Combien de temps un message reste sous les yeux. Trois secondes : le temps
/// de lire une phrase, et pas celui de s'y habituer (Hugo, 10/11/2026).
public let brandToastDuration: Duration = .seconds(3)

private struct BrandToastModifier: ViewModifier {
    @Binding var message: String?
    let duration: Duration

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .top) {
                if let message {
                    BrandToast(message)
                        .transition(
                            reduceMotion
                                ? .opacity
                                : .move(edge: .top).combined(with: .opacity)
                        )
                }
            }
            .animation(.smooth, value: message)
            // `.task(id:)` et non une minuterie : un second message qui arrive
            // avant la fin du premier **relance** l'attente au lieu de la
            // laisser emporter les deux.
            .task(id: message) {
                guard message != nil else { return }
                try? await Task.sleep(for: duration)
                guard !Task.isCancelled else { return }
                message = nil
            }
    }
}

extension View {
    /// Pose un message fugitif en haut de l'écran. Il s'efface seul au bout de
    /// ``brandToastDuration``, et remettre la valeur à `nil` l'efface tout de
    /// suite.
    public func brandToast(_ message: Binding<String?>, duration: Duration = brandToastDuration) -> some View {
        modifier(BrandToastModifier(message: message, duration: duration))
    }
}

#Preview("Message fugitif") {
    VStack {
        Spacer()
        Text("L'écran, derrière")
            .font(MemoBookFont.body)
            .foregroundStyle(MemoBookColor.inkMuted)
        Spacer()
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(MemoBookColor.background)
    .brandToast(.constant("Tu as rejoint le voyage de Fanny, il est ajouté à tes voyages."))
    .environment(\.colorScheme, .light)
}
