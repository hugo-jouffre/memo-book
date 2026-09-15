import AuthenticationServices
import MemoBookDesign
import SwiftUI

/// Les deux entrées par fournisseur tiers, telles que la maquette d'accueil les
/// dessine : deux pavés de même gabarit, cerclés de beige, le logo à gauche du
/// libellé.
///
/// **Les deux portent le même habillage, et il n'est écrit qu'une fois** —
/// ``providerChrome(shape:)``. C'est ce qui empêche les deux boutons de
/// diverger : même rayon, même filet, même aplat, et un seul endroit à changer.
///
/// **Le bouton Apple est celui d'Apple** — `SignInWithAppleButton`, dessiné par
/// le système. Ni son libellé ni sa typographie ne nous appartiennent : Apple
/// impose son bouton, et le refuser vaut un refus en revue. Ce qu'on peut lui
/// imposer, on le lui impose, et c'est là que le filet beige se pose.
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
            googleButton
        }
    }

    // MARK: - Google

    private var googleButton: some View {
        Button(action: onGoogle) {
            HStack(spacing: MemoBookSpacing.xs + 2) {
                // Le logo de la marque, dessiné à la main et cerné de bleu
                // comme les trois icônes du dessus — surtout pas de
                // `renderingMode(.template)`, qui l'aplatirait en une couleur.
                Image(brand: "LogoGoogle")
                    .resizable()
                    .scaledToFit()
                    .frame(width: markSide, height: markSide)
                    .accessibilityHidden(true)

                Text(WelcomeCopy.google)
                    // General Sans Semibold, comme la maquette — et non la Sora
                    // des boutons de l'app : ces deux-là empruntent le gabarit
                    // des fournisseurs, pas la typographie des CTA.
                    .font(MemoBookFont.bodySemibold)
                    .foregroundStyle(MemoBookColor.ink)
            }
            // De l'air avant le filet : en taille accessible le libellé passe à
            // la ligne et vient occuper toute la largeur offerte — sans cette
            // réserve, « avec Google » butait contre le bord du bouton.
            .padding(.horizontal, MemoBookSpacing.s)
            .frame(maxWidth: .infinity)
            .frame(minHeight: height)
            .providerChrome(shape: shape)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Apple

    /// ⚠️ **Le filet est le nôtre, posé par-dessus.**
    ///
    /// Le style `.whiteOutline` en dessine un — à l'encre, et selon *son* rayon,
    /// pas celui de nos contrôles : le trait coupait les angles en travers de
    /// l'arrondi. Il ne se retouche pas, alors on ne le prend pas. `.white`
    /// donne le même pavé clair **sans contour**, on le découpe à notre forme,
    /// et le beige se pose dessus comme sur le bouton Google.
    ///
    /// L'aplat, lui, est le blanc pur d'Apple là où l'app pose son blanc crème.
    /// `colorMultiply` rattrape l'écart sans toucher au dessin : le blanc du
    /// fond devient `surface`, et le noir de la pomme et du libellé reste noir
    /// — multiplier par 0 ne donne rien d'autre que 0.
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
        .signInWithAppleButtonStyle(.white)
        .colorMultiply(MemoBookColor.surface)
        // Hauteur **non** mise à l'échelle, contrairement au bouton Google :
        // Apple ne fait pas suivre le Dynamic Type au libellé de son bouton. Le
        // faire grandir quand même ne donnerait qu'une dalle de 130 pt avec un
        // texte de 17 pt perdu au milieu.
        .frame(height: 52)
        .providerChrome(shape: shape)
    }

}

private extension View {
    /// L'habillage des deux boutons de fournisseur : l'aplat, le filet beige, et
    /// la découpe qui les fait suivre le même arrondi.
    ///
    /// `clipShape` **avant** le filet, et non l'inverse : le bouton d'Apple
    /// dessine son propre fond selon son propre rayon, et sans découpe il
    /// déborderait du trait dans les angles.
    func providerChrome(shape: RoundedRectangle) -> some View {
        background(MemoBookColor.surface, in: shape)
            .clipShape(shape)
            .overlay { shape.strokeBorder(MemoBookColor.separator, lineWidth: 1.5) }
            .contentShape(shape)
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
