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
        case .pending, .processing, .unknown: MemoBookColor.inkSecondary
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

/// Bouton d'action principal, pleine largeur — la convention iOS que la
/// critique design relève comme déjà bien réglée dans les maquettes.
public struct PrimaryButton: View {
    private let title: String
    private let isLoading: Bool
    private let action: () -> Void

    public init(_ title: String, isLoading: Bool = false, action: @escaping () -> Void) {
        self.title = title
        self.isLoading = isLoading
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: MemoBookSpacing.xs) {
                if isLoading { ProgressView().tint(.white) }
                Text(title).font(MemoBookFont.button)
            }
            .frame(maxWidth: .infinity, minHeight: MemoBookSpacing.controlHeight)
        }
        .buttonStyle(.borderedProminent)
        .tint(MemoBookColor.action)
        .disabled(isLoading)
    }
}

/// Message d'erreur avec possibilité de réessayer, plutôt qu'une alerte
/// modale : l'utilisateur garde le contexte de l'écran.
public struct ErrorBanner: View {
    private let message: String
    private let retry: (() -> Void)?

    public init(message: String, retry: (() -> Void)? = nil) {
        self.message = message
        self.retry = retry
    }

    public var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: MemoBookSpacing.xs) {
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(MemoBookColor.error)
            Text(message)
                .font(MemoBookFont.caption)
                .foregroundStyle(MemoBookColor.ink)
            Spacer(minLength: 0)
            if let retry {
                Button("Réessayer", action: retry)
                    .font(MemoBookFont.caption)
                    .tint(MemoBookColor.action)
            }
        }
        .padding(MemoBookSpacing.s)
        .background(MemoBookColor.errorSoft, in: .rect(cornerRadius: MemoBookSpacing.cornerRadius))
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
                .foregroundStyle(MemoBookColor.inkSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, MemoBookSpacing.xl)
    }
}
