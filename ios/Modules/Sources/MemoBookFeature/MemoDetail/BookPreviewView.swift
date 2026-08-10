import QuickLook
import SwiftUI

/// Aperçu du carnet généré.
///
/// QuickLook ne sait pas afficher une URL distante : le PDF est d'abord
/// téléchargé dans un fichier temporaire, puis présenté depuis le disque.
struct BookPreviewView: View {
    let url: URL

    @Environment(\.dismiss) private var dismiss
    @State private var localURL: URL?
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Group {
                if let localURL {
                    QuickLookPreview(url: localURL)
                } else if let errorMessage {
                    ContentUnavailableView(
                        "Carnet indisponible",
                        systemImage: "exclamationmark.triangle",
                        description: Text(errorMessage)
                    )
                } else {
                    ProgressView("Téléchargement du carnet…")
                }
            }
            .navigationTitle("Mon carnet")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fermer") { dismiss() }
                }
            }
        }
        .task { await download() }
    }

    private func download() async {
        do {
            let (temporaryURL, _) = try await URLSession.shared.download(from: url)

            // Le fichier livré par URLSession porte un nom aléatoire sans
            // extension : QuickLook s'appuie dessus pour choisir son moteur de
            // rendu, il faut donc le renommer en .pdf.
            let destination = FileManager.default.temporaryDirectory
                .appendingPathComponent("memobook-\(UUID().uuidString).pdf")
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.moveItem(at: temporaryURL, to: destination)

            localURL = destination
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct QuickLookPreview: UIViewControllerRepresentable {
    let url: URL

    func makeCoordinator() -> Coordinator { Coordinator(url: url) }

    func makeUIViewController(context: Context) -> QLPreviewController {
        let controller = QLPreviewController()
        controller.dataSource = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: QLPreviewController, context: Context) {
        context.coordinator.url = url
        controller.reloadData()
    }

    final class Coordinator: NSObject, QLPreviewControllerDataSource {
        var url: URL

        init(url: URL) {
            self.url = url
        }

        func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }

        func previewController(
            _ controller: QLPreviewController,
            previewItemAt index: Int
        ) -> any QLPreviewItem {
            url as NSURL
        }
    }
}
