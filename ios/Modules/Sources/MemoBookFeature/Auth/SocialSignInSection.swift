import AuthenticationServices
import MemoBookDesign
import SwiftUI

/// Les deux entrées par fournisseur tiers.
///
/// Le bouton Apple est celui d'Apple — `SignInWithAppleButton`, dessiné par le
/// système. Ni son libellé ni sa typographie ne nous appartiennent : Apple
/// impose son bouton, et le refuser vaut un refus en revue. Il ne partage donc
/// avec les deux autres appels à l'action que ce qu'on peut lui imposer, sa
/// hauteur et son rayon.
struct SocialSignInSection: View {
    /// Appelée quand un fournisseur a donné son accord. Le jeton n'est encore
    /// une preuve de rien : seul le serveur peut le vérifier.
    let onCredential: (SocialCredential) -> Void

    /// Appelée quand l'échange a échoué. L'utilisateur qui referme la feuille
    /// Apple ne passe pas par là : renoncer n'est pas un incident.
    let onFailure: (any Error) -> Void

    let onGoogle: () -> Void

    /// La hauteur commune à tous les CTA. Ces deux boutons ne passent pas par
    /// ``BrandButton`` — Apple et Google imposent chacun leur dessin — mais ils
    /// partagent son gabarit, sans quoi la pile se lirait de travers.
    @ScaledMetric(relativeTo: .body) private var height = MemoBookSpacing.controlHeight
    /// Taille du logo Google, calée sur la pomme d'Apple — 14,4 pt à la hauteur
    /// d'appel à l'action de l'app. C'est le seul des deux qu'on peut régler :
    /// Apple dessine le sien à partir de la hauteur du bouton, et rien d'autre.
    @ScaledMetric(relativeTo: .body) private var markSide: CGFloat = 15

    /// Renouvelé à chaque appui : un nonce ne vaut que pour une tentative.
    @State private var nonce = SignInNonce()

    var body: some View {
        VStack(spacing: 12) {
            Text("Ou continue avec")
                .font(MemoBookFont.taglineRegular)
                .foregroundStyle(MemoBookColor.action)
                .frame(maxWidth: .infinity)
                .padding(.bottom, MemoBookSpacing.xs)

            appleButton

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
            .buttonStyle(.plain)
        }
    }

    private var appleButton: some View {
        SignInWithAppleButton(.continue) { request in
            nonce = SignInNonce()
            // Apple ne les donne qu'à la toute première autorisation, et les
            // ignore poliment ensuite. Les demander coûte donc une seule fois.
            request.requestedScopes = [.fullName, .email]
            // Haché, jamais en clair : ce qui part chez Apple ne doit pas
            // suffire à rejouer la tentative.
            request.nonce = nonce.hashed
        } onCompletion: { result in
            switch result {
            case let .success(authorization):
                guard let credential = SocialCredential(authorization, nonce: nonce) else {
                    onFailure(SocialSignInError.unusableAppleCredential)
                    return
                }
                onCredential(credential)
            case let .failure(error):
                // Refermer la feuille n'est pas un échec : rien à signaler,
                // rien à afficher.
                guard (error as? ASAuthorizationError)?.code != .canceled else { return }
                onFailure(error)
            }
        }
        // `.black` plutôt que `.whiteOutline` : c'est le seul des trois styles
        // d'Apple qui tombe juste sur le crème de la marque.
        .signInWithAppleButtonStyle(.black)
        // Hauteur **non** mise à l'échelle, contrairement aux deux autres CTA :
        // Apple ne fait pas suivre le Dynamic Type au libellé de son bouton. Le
        // faire grandir quand même ne donnerait qu'une dalle noire de 130 pt
        // avec un texte de 17 pt perdu au milieu.
        .frame(height: MemoBookSpacing.controlHeight)
        .clipShape(.rect(cornerRadius: 16))
    }

    private func row(_ title: String, @ViewBuilder mark: () -> some View) -> some View {
        HStack(spacing: MemoBookSpacing.xs + 4) {
            mark()
                .frame(width: markSide, height: markSide)
                .accessibilityHidden(true)
            Text(title)
                // La police des boutons, comme « Continuer » : ces trois-là
                // sont le même appel à l'action, ils doivent se lire pareil.
                .font(MemoBookFont.button)
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: height)
    }
}

/// Les échecs propres à l'écran d'entrée. Tout le reste remonte tel quel du
/// fournisseur ou du réseau.
enum SocialSignInError: LocalizedError {
    /// Apple a répondu, mais sans jeton d'identité exploitable. En pratique :
    /// jamais, sauf appareil mal configuré.
    case unusableAppleCredential

    var errorDescription: String? {
        switch self {
        case .unusableAppleCredential:
            "Apple n'a pas transmis d'identifiant utilisable. Réessaie."
        }
    }
}
