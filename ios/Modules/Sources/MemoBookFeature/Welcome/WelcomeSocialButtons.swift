import AuthenticationServices
import MemoBookDesign
import SwiftUI

/// Les deux entrées par fournisseur tiers, telles que la maquette d'accueil les
/// dessine : deux pavés blancs de même gabarit, cerclés de beige, le logo à
/// gauche du libellé.
///
/// **Le bouton Apple est celui d'Apple** — `SignInWithAppleButton`, dessiné par
/// le système. Ni son libellé ni sa typographie ne nous appartiennent : Apple
/// impose son bouton, et le refuser vaut un refus en revue. Ce qu'on peut lui
/// imposer, on le lui impose : le style clair, la hauteur, le rayon.
///
/// ⚠️ Son contour est celui d'Apple — un filet à l'encre — là où la maquette
/// cercle de `Beige Darker`. Le style `.whiteOutline` ne se retouche pas :
/// écart signalé dans la fiche écran.
struct WelcomeSocialButtons: View {
    /// Appelée quand un fournisseur a donné son accord. Le jeton n'est encore
    /// une preuve de rien : seul le serveur peut le vérifier.
    let onCredential: (SocialCredential) -> Void

    /// Appelée quand l'échange a échoué. L'utilisateur qui referme la feuille
    /// Apple ne passe pas par là : renoncer n'est pas un incident.
    let onFailure: (any Error) -> Void

    let onGoogle: () -> Void

    /// La hauteur des deux boutons — 3.25 rem sur la maquette, contre 3 rem
    /// pour le CTA ordinaire de l'app. Elle suit le Dynamic Type côté Google ;
    /// Apple, lui, ne fait pas suivre son libellé (voir plus bas).
    @ScaledMetric(relativeTo: .body) private var height: CGFloat = 52

    /// Taille du logo Google, calée sur la pomme d'Apple. C'est le seul des deux
    /// qu'on peut régler : Apple dessine le sien à partir de la hauteur du
    /// bouton, et rien d'autre.
    @ScaledMetric(relativeTo: .body) private var markSide: CGFloat = 24

    /// Renouvelé à chaque appui : un nonce ne vaut que pour une tentative.
    @State private var nonce = SignInNonce()

    private var shape: RoundedRectangle {
        .rect(cornerRadius: MemoBookSpacing.controlCornerRadius)
    }

    var body: some View {
        VStack(spacing: MemoBookSpacing.s) {
            appleButton

            Button(action: onGoogle) {
                row(WelcomeCopy.google) {
                    // Le logo Google est quadrichrome : surtout pas de
                    // `renderingMode(.template)`, qui l'aplatirait en une seule
                    // couleur. Google interdit d'en modifier les teintes.
                    Image(brand: "IconGoogle")
                        .resizable()
                        .scaledToFit()
                }
                .background(MemoBookColor.surface, in: shape)
                .overlay { shape.strokeBorder(MemoBookColor.separator, lineWidth: 1.5) }
                .contentShape(shape)
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
        // Le pavé blanc de la maquette. `.whiteOutline` et non `.black` : la
        // carte d'accueil est crème, et un aplat noir y ferait un trou.
        .signInWithAppleButtonStyle(.whiteOutline)
        // Hauteur **non** mise à l'échelle, contrairement au bouton Google :
        // Apple ne fait pas suivre le Dynamic Type au libellé de son bouton. Le
        // faire grandir quand même ne donnerait qu'une dalle de 130 pt avec un
        // texte de 17 pt perdu au milieu.
        .frame(height: 52)
        .clipShape(shape)
    }

    private func row(_ title: String, @ViewBuilder mark: () -> some View) -> some View {
        HStack(spacing: MemoBookSpacing.xs + 2) {
            mark()
                .frame(width: markSide, height: markSide)
                .accessibilityHidden(true)
            Text(title)
                // General Sans Semibold, comme la maquette — et non la Sora des
                // boutons de l'app : ces deux-là empruntent le gabarit des
                // fournisseurs, pas la typographie des CTA.
                .font(MemoBookFont.bodySemibold)
                .foregroundStyle(MemoBookColor.ink)
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: height)
    }
}

/// Les échecs propres à l'entrée par fournisseur. Tout le reste remonte tel quel
/// du fournisseur ou du réseau.
enum SocialSignInError: LocalizedError {
    /// Apple a répondu, mais sans jeton d'identité exploitable. En pratique :
    /// jamais, sauf appareil mal configuré.
    case unusableAppleCredential

    var errorDescription: String? {
        switch self {
        case .unusableAppleCredential:
            "Apple n’a pas transmis d’identifiant utilisable. Réessaie."
        }
    }
}
