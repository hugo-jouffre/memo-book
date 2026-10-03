import MemoBookCore
import MemoBookDesign
import SwiftUI

/// Ce que le bandeau du crédit du jour dit, au-dessus d'une barre
/// d'enregistrement — celle du chat comme la feuille bleue de l'accueil
/// (Hugo, 03/10/2026).
///
/// Trois états, et rien pour un abonné :
///
/// | État | Quand | Ce qu'on voit |
/// |---|---|---|
/// | ``warning(remainingMs:)`` | moins de 30 s pendant qu'on parle | le compte à rebours |
/// | ``urgent(remainingMs:)`` | moins de 5 s | le même, qui pulse |
/// | ``exhausted`` | plus rien | « Crédit du jour épuisé », qui mène à l'offre |
///
/// Les seuils voyagent avec le solde (``DailyCredit/warningRemainingMs``,
/// ``DailyCredit/urgentRemainingMs``) : l'app n'en écrit aucun.
public enum DailyCreditBanner: Sendable, Hashable {
    case warning(remainingMs: Int)
    case urgent(remainingMs: Int)
    case exhausted

    /// Le bandeau pendant qu'on parle : le reste du jour, moins ce que le
    /// fichier contient déjà. `nil` tant qu'il reste plus de trente secondes.
    public static func whileRecording(credit: DailyCredit, elapsedMs: Int) -> DailyCreditBanner? {
        let remaining = credit.remainingMs(whileRecording: elapsedMs)
        switch credit.phase(remainingMs: remaining) {
        case .calm: return nil
        case .warning: return .warning(remainingMs: remaining)
        case .urgent: return .urgent(remainingMs: remaining)
        // L'instant entre zéro et l'arrêt net : le bandeau dit déjà la suite.
        case .exhausted: return .exhausted
        }
    }

    /// Le bandeau se touche : seul « épuisé » mène quelque part — à l'offre.
    public var opensOffer: Bool { self == .exhausted }
}

/// Le bandeau du crédit du jour, dessiné — ``BrandLimitBanner`` habillé des
/// phrases de ``DailyCreditCopy``.
///
/// **Empilé dans le pied, jamais en calque** : c'est la condition pour que
/// « épuisé » se touche. Il prend la place du rail de suggestions pendant
/// l'enregistrement — voir ``ChatComposer``.
struct DailyCreditBannerView: View {
    let banner: DailyCreditBanner

    /// Ce que fait le toucher sur « épuisé » : ouvrir l'offre. Ignoré pour le
    /// compte à rebours, qui se lit seulement.
    let onSubscribe: () -> Void

    var body: some View {
        switch banner {
        case .warning(let remainingMs):
            BrandLimitBanner(DailyCreditCopy.warning(remainingMs: remainingMs))
        case .urgent(let remainingMs):
            BrandLimitBanner(DailyCreditCopy.warning(remainingMs: remainingMs), isPulsing: true)
        case .exhausted:
            BrandLimitBanner(
                DailyCreditCopy.exhaustedTitle,
                detail: DailyCreditCopy.exhaustedDetail,
                systemImage: "moon.zzz",
                accessibilityHint: ChatCopy.Credit.exhaustedHint,
                action: onSubscribe
            )
        }
    }
}

/// La boîte d'information au-dessus du champ, quand le crédit du jour pèse
/// sur ce qu'on écrit — voir ``ChatModel/creditTextNotice``.
public enum ChatCreditTextNotice: Sendable, Hashable {
    /// Le brouillon dépasse le reste du jour : l'envoi a pâli, voici pourquoi.
    case tooLong(String)
    /// Moins d'une minute de crédit : combien de caractères cela laisse.
    case reminder(String)

    public var message: String {
        switch self {
        case .tooLong(let message), .reminder(let message): message
        }
    }
}

// MARK: - Aperçus

#Preview("Bandeau du crédit — avertissement, pulsation, épuisé") {
    VStack(spacing: MemoBookSpacing.s) {
        DailyCreditBannerView(banner: .warning(remainingMs: 24_000), onSubscribe: {})
        DailyCreditBannerView(banner: .urgent(remainingMs: 3_000), onSubscribe: {})
        DailyCreditBannerView(banner: .exhausted, onSubscribe: {})
    }
    .padding(MemoBookSpacing.screenMargin)
    .background(MemoBookColor.background)
    .environment(\.colorScheme, .light)
}
