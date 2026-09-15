import MemoBookCore
import SwiftUI

/// Pastille d'état, partagée par les souvenirs et les générations.
public struct StatusBadge: View {
    private let status: Status

    public init(_ status: Status) {
        self.status = status
    }

    private var label: String {
        switch status {
        case .pending: "En attente"
        case .processing: "En cours"
        case .ready: "Prêt"
        case .failed: "Échec"
        case .unknown: "En cours"
        }
    }

    private var tint: Color {
        switch status {
        case .ready: MemoBookColor.valid
        case .failed: MemoBookColor.error
        case .pending, .processing, .unknown: MemoBookColor.inkMuted
        }
    }

    public var body: some View {
        HStack(spacing: 6) {
            if status.isInProgress {
                ProgressView().controlSize(.mini)
            } else {
                Circle().fill(tint).frame(width: 7, height: 7)
            }
            Text(label)
                .font(MemoBookFont.caption)
                .foregroundStyle(tint)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Statut : \(label)")
    }
}

/// Message d'erreur avec possibilité de réessayer, plutôt qu'une alerte
/// modale : l'utilisateur garde le contexte de l'écran.
public struct ErrorBanner: View {
    private let message: String
    private let advice: String?
    private let retry: (() -> Void)?
    private let help: (() -> Void)?

    /// - Parameters:
    ///   - message: ce qui s'est passé, en une phrase.
    ///   - advice: ce qu'on peut **faire** — la phrase qui suit le constat.
    ///     « Erreur interne du serveur » laissait le voyageur chercher ce qu'il
    ///     avait mal fait ; dire à qui est la panne et quel geste tenter est ce
    ///     qui transforme un mur en message (Hugo, 15/09/2026). Voir
    ///     `APIError.recoveryAdvice`.
    ///   - retry: relance ce qui a échoué.
    ///   - help: ouvre le support — la porte de sortie quand réessayer ne
    ///     suffit pas.
    public init(
        message: String,
        advice: String? = nil,
        retry: (() -> Void)? = nil,
        help: (() -> Void)? = nil
    ) {
        self.message = message
        self.advice = advice
        self.retry = retry
        self.help = help
    }

    public var body: some View {
        Group {
            if advice == nil, help == nil {
                compact
            } else {
                detailed
            }
        }
        .padding(MemoBookSpacing.s)
        .background(MemoBookColor.error.opacity(0.1), in: .rect(cornerRadius: MemoBookSpacing.cornerRadius))
    }

    /// Une ligne : le constat, et « Réessayer » au bout. Le dessin d'origine,
    /// pour les écrans qui n'ont rien de plus à dire.
    private var compact: some View {
        HStack(alignment: .firstTextBaseline, spacing: MemoBookSpacing.xs) {
            mark
            Text(message)
                .font(MemoBookFont.notification)
                .foregroundStyle(MemoBookColor.ink)
            Spacer(minLength: 0)
            if let retry {
                link("Réessayer", action: retry)
            }
        }
    }

    /// Le constat, le conseil dessous, et les gestes possibles sur leur propre
    /// ligne : une phrase de conseil ne tient pas au bout d'une ligne.
    private var detailed: some View {
        VStack(alignment: .leading, spacing: MemoBookSpacing.xs) {
            HStack(alignment: .firstTextBaseline, spacing: MemoBookSpacing.xs) {
                mark
                Text(message)
                    .font(MemoBookFont.notification)
                    .foregroundStyle(MemoBookColor.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }

            if let advice {
                Text(advice)
                    .font(MemoBookFont.caption)
                    .foregroundStyle(MemoBookColor.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if retry != nil || help != nil {
                HStack(spacing: MemoBookSpacing.s) {
                    if let retry { link("Réessayer", action: retry) }
                    if let help { link("Besoin d’aide ?", action: help) }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var mark: some View {
        Image(systemName: "exclamationmark.triangle")
            .foregroundStyle(MemoBookColor.error)
    }

    private func link(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .font(MemoBookFont.notification)
            .tint(MemoBookColor.action)
    }
}

/// État vide : une phrase qui dit quoi faire, pas une illustration décorative.
public struct EmptyStateView: View {
    private let systemImage: String
    private let title: String
    private let message: String

    public init(systemImage: String, title: String, message: String) {
        self.systemImage = systemImage
        self.title = title
        self.message = message
    }

    public var body: some View {
        VStack(spacing: MemoBookSpacing.xs) {
            Image(systemName: systemImage)
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(MemoBookColor.action)
            Text(title).font(MemoBookFont.sectionTitle)
            Text(message)
                .font(MemoBookFont.caption)
                .foregroundStyle(MemoBookColor.inkMuted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, MemoBookSpacing.xl)
    }
}

extension View {
    /// Fait **fondre** une bande qui défile sur ses deux bords, au lieu de la
    /// trancher net.
    ///
    /// Une rangée de pastilles prend toute la largeur de l'écran pour que la
    /// dernière puisse sortir par le bord — c'est ce qui dit « ça continue ».
    /// Mais ce qui sort est coupé à la verticale, et une pastille **pleine**
    /// devient alors une dalle de couleur plaquée contre le bord de l'écran :
    /// on la lit comme un défaut de rendu, pas comme un débordement. Le fondu
    /// rend le geste lisible — la pastille s'efface en sortant.
    ///
    /// Le voile ne mord que sur les bords : posé sur une bande dont le contenu
    /// commence à la marge d'écran, il ne touche rien tant que rien n'a défilé.
    ///
    /// - Parameter width: la largeur du fondu, de chaque côté.
    public func brandHorizontalFade(_ width: CGFloat = MemoBookSpacing.s) -> some View {
        mask {
            HStack(spacing: 0) {
                LinearGradient(colors: [.clear, .black], startPoint: .leading, endPoint: .trailing)
                    .frame(width: width)
                Rectangle().fill(.black)
                LinearGradient(colors: [.black, .clear], startPoint: .leading, endPoint: .trailing)
                    .frame(width: width)
            }
        }
    }
}
