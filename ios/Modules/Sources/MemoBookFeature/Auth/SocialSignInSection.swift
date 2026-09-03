import MemoBookDesign
import SwiftUI

/// Les deux entrées par fournisseur tiers.
///
/// > Important : ce sont pour l'instant des boutons de maquette. Quand
/// > l'authentification sera réellement branchée, « Continuer avec Apple »
/// > devra passer par `SignInWithAppleButton` (`AuthenticationServices`) :
/// > Apple impose son propre bouton, et le refus en revue est systématique
/// > sinon.
struct SocialSignInSection: View {
    let onApple: () -> Void
    let onGoogle: () -> Void

    @ScaledMetric(relativeTo: .body) private var height = MemoBookSpacing.fieldHeight
    @ScaledMetric(relativeTo: .body) private var markSide: CGFloat = 20

    var body: some View {
        VStack(spacing: 12) {
            Text("Ou continue avec")
                .font(MemoBookFont.tagline)
                .foregroundStyle(MemoBookColor.action)
                .frame(maxWidth: .infinity)
                .padding(.bottom, MemoBookSpacing.xs)

            Button(action: onApple) {
                row("Continuer avec Apple") {
                    // Le logo Apple est un symbole système : il suit la
                    // couleur du texte, comme le veut Apple.
                    Image(systemName: "apple.logo")
                        .font(.system(size: markSide))
                }
                .foregroundStyle(MemoBookColor.surface)
                .background(MemoBookColor.ink, in: .rect(cornerRadius: 16))
            }

            Button(action: onGoogle) {
                row("Continuer avec Google") {
                    // Le logo Google est quadrichrome : surtout pas de
                    // `renderingMode(.template)`, qui l'aplatirait en une
                    // seule couleur. Google interdit d'en modifier les teintes.
                    Image(brand: "IconGoogle")
                        .resizable()
                        .scaledToFit()
                        .frame(width: markSide, height: markSide)
                }
                .foregroundStyle(MemoBookColor.ink)
                .background(MemoBookColor.surface, in: .rect(cornerRadius: 16))
                .overlay {
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(MemoBookColor.separator, lineWidth: 1)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func row(_ title: String, @ViewBuilder mark: () -> some View) -> some View {
        HStack(spacing: MemoBookSpacing.xs + 4) {
            mark()
                .frame(width: markSide, height: markSide)
                .accessibilityHidden(true)
            Text(title)
                .font(MemoBookFont.bodySemibold)
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: height)
        .padding(.vertical, MemoBookSpacing.xs)
    }
}
