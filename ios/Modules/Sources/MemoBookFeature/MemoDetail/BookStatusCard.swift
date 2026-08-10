import MemoBookCore
import MemoBookDesign
import SwiftUI

/// L'aboutissement du parcours : générer le carnet, suivre sa fabrication,
/// puis l'ouvrir.
///
/// Fond papier — c'est une surface « carnet », la seule de l'écran à porter la
/// couleur crème de la marque.
struct BookStatusCard: View {
    let render: Render?
    let canGenerate: Bool
    let onGenerate: () -> Void

    @State private var isPreviewing = false

    var body: some View {
        VStack(alignment: .leading, spacing: MemoBookSpacing.s) {
            HStack {
                Text("Mon carnet")
                    .font(MemoBookFont.bookTitle(20))
                    .foregroundStyle(MemoBookColor.ink)
                Spacer()
                if let render {
                    StatusBadge(render.status)
                }
            }

            switch render?.status {
            case .ready:
                if let urlString = render?.pdfUrl, let url = URL(string: urlString) {
                    VStack(spacing: MemoBookSpacing.xs) {
                        PrimaryButton("Ouvrir mon carnet") { isPreviewing = true }
                        ShareLink(item: url) {
                            Text("Partager le PDF").font(MemoBookFont.caption)
                        }
                        .tint(MemoBookColor.action)
                    }
                    .sheet(isPresented: $isPreviewing) {
                        BookPreviewView(url: url)
                    }
                }

            case .pending, .processing, .unknown:
                HStack(spacing: MemoBookSpacing.xs) {
                    ProgressView()
                    Text("Ton carnet est en train de s'écrire…")
                        .font(MemoBookFont.caption)
                        .foregroundStyle(MemoBookColor.inkSecondary)
                }

            case .failed:
                VStack(alignment: .leading, spacing: MemoBookSpacing.xs) {
                    Text(render?.error ?? "La génération a échoué.")
                        .font(MemoBookFont.caption)
                        .foregroundStyle(MemoBookColor.error)
                    PrimaryButton("Réessayer", action: onGenerate)
                }

            case .none:
                VStack(alignment: .leading, spacing: MemoBookSpacing.xs) {
                    Text("Quand tu as raconté assez de souvenirs, génère ton carnet.")
                        .font(MemoBookFont.caption)
                        .foregroundStyle(MemoBookColor.inkSecondary)
                    PrimaryButton("Générer mon carnet", action: onGenerate)
                        .disabled(!canGenerate)
                        .opacity(canGenerate ? 1 : 0.5)
                }
            }
        }
        .padding(MemoBookSpacing.s)
        .background(MemoBookColor.paper, in: .rect(cornerRadius: MemoBookSpacing.cornerRadius))
        .padding(.horizontal, MemoBookSpacing.screenMargin - MemoBookSpacing.s)
    }
}
