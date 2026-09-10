import AVFoundation
import MemoBookCore
import MemoBookDesign
import Photos
import PhotosUI
import SwiftUI
import UIKit

/// Où vivent les photos jointes, le temps qu'on les regarde.
///
/// Dans les **caches** et non dans les documents, pour la même raison que les
/// vocaux : une photo partie sur le serveur n'a plus à être gardée, et le
/// système peut reprendre la place s'il en manque. C'est aussi ce qui évite de
/// sauvegarder dans iCloud des fichiers qui ne sont que du transit.
enum ChatPhotoFile {
    private static var directory: URL {
        URL.cachesDirectory.appending(path: "ChatPhotos", directoryHint: .isDirectory)
    }

    static func save(_ data: Data, id: String) throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appending(path: "\(id).jpg")
        try data.write(to: url, options: .atomic)
        return url
    }

    static func removeAll() {
        try? FileManager.default.removeItem(at: directory)
    }
}

/// Comment on ajoute une photo à la conversation.
///
/// **Le geste suit iOS, pas MemoBook.** On demande d'abord l'accès à la
/// photothèque — c'est là qu'iOS propose « Tout » ou « Sélectionner des
/// photos… », et cette décision-là ne nous appartient pas —, puis on demande ce
/// qu'on veut faire : prendre une photo maintenant, ou en choisir une. Les deux
/// commandes système font le reste.
///
/// Un refus n'est pas une impasse silencieuse : iOS ne redemande jamais, donc
/// l'écran dit ce qui manque et mène aux Réglages.
@MainActor
@Observable
final class ChatPhotoFlow {
    /// La feuille de choix est ouverte.
    var isChoosing = false

    /// Le sélecteur de photothèque est ouvert.
    var isPickingFromLibrary = false

    /// L'appareil photo est ouvert.
    var isTakingPhoto = false

    /// Ce qui manque, dit à l'utilisateur. Affiché en bandeau par l'écran.
    private(set) var deniedMessage: String?

    /// L'appareil photo existe. Faux sur un simulateur, et sur un appareil qui
    /// n'en a pas : proposer « Prendre une photo » là-dessus ouvrirait un écran
    /// noir.
    var canTakePhoto: Bool {
        UIImagePickerController.isSourceTypeAvailable(.camera)
    }

    /// Le geste d'entrée : on demande l'accès, puis on demande quoi faire.
    func begin() {
        deniedMessage = nil

        switch PHPhotoLibrary.authorizationStatus(for: .readWrite) {
        case .authorized, .limited:
            isChoosing = true
        case .denied, .restricted:
            deniedMessage = ChatCopy.Photos.libraryDenied
        case .notDetermined:
            Task {
                // C'est **cette** demande qui affiche « Tout » ou
                // « Sélectionner des photos… ». On ne la reproduit pas : on la
                // laisse parler.
                let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
                switch status {
                case .authorized, .limited: isChoosing = true
                default: deniedMessage = ChatCopy.Photos.libraryDenied
                }
            }
        @unknown default:
            isChoosing = true
        }
    }

    func chooseLibrary() {
        isPickingFromLibrary = true
    }

    /// L'appareil photo a sa propre autorisation, distincte de la photothèque.
    func chooseCamera() {
        guard canTakePhoto else {
            deniedMessage = ChatCopy.Photos.cameraUnavailable
            return
        }

        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            isTakingPhoto = true
        case .denied, .restricted:
            deniedMessage = ChatCopy.Photos.cameraDenied
        case .notDetermined:
            Task {
                if await AVCaptureDevice.requestAccess(for: .video) {
                    isTakingPhoto = true
                } else {
                    deniedMessage = ChatCopy.Photos.cameraDenied
                }
            }
        @unknown default:
            isTakingPhoto = true
        }
    }

    func dismissDenial() {
        deniedMessage = nil
    }
}

extension View {
    /// Pose le parcours d'ajout de photos : la feuille de choix, la
    /// photothèque, et l'appareil photo.
    func chatPhotoFlow(
        _ flow: ChatPhotoFlow,
        onPicked: @escaping ([Data]) -> Void
    ) -> some View {
        modifier(ChatPhotoFlowModifier(flow: flow, onPicked: onPicked))
    }
}

private struct ChatPhotoFlowModifier: ViewModifier {
    @Bindable var flow: ChatPhotoFlow
    let onPicked: ([Data]) -> Void

    @State private var selection: [PhotosPickerItem] = []

    func body(content: Content) -> some View {
        content
            .confirmationDialog(
                ChatCopy.Photos.title,
                isPresented: $flow.isChoosing,
                titleVisibility: .visible
            ) {
                // L'ordre suit celui d'iOS : l'action qui crée quelque chose
                // d'abord, celle qui puise dans l'existant ensuite.
                if flow.canTakePhoto {
                    Button(ChatCopy.Photos.takeOne) { flow.chooseCamera() }
                }
                Button(ChatCopy.Photos.fromLibrary) { flow.chooseLibrary() }
                Button(ChatCopy.Photos.cancel, role: .cancel) {}
            }
            .photosPicker(
                isPresented: $flow.isPickingFromLibrary,
                selection: $selection,
                maxSelectionCount: ChatMetrics.visiblePhotoCount,
                matching: .images
            )
            .fullScreenCover(isPresented: $flow.isTakingPhoto) {
                ChatCameraPicker { data in
                    flow.isTakingPhoto = false
                    guard let data else { return }
                    onPicked([data])
                }
                .ignoresSafeArea()
            }
            .onChange(of: selection) { _, items in
                guard !items.isEmpty else { return }
                Task {
                    // Les images sont chargées **en série** : quatre transferts
                    // en parallèle depuis iCloud ont plus de chances d'échouer
                    // qu'un à la fois, et l'ordre du choix est celui du récit.
                    var images: [Data] = []
                    for item in items {
                        if let data = try? await item.loadTransferable(type: Data.self) {
                            images.append(data)
                        }
                    }
                    selection = []
                    onPicked(images)
                }
            }
    }
}

/// L'appareil photo du système.
///
/// `UIImagePickerController` et non `AVCaptureSession` : on veut la caméra
/// d'iOS, avec son déclencheur, sa mise au point et son « Utiliser la photo » —
/// pas un viseur à redessiner. Le contrôleur est déprécié pour la photothèque,
/// pas pour la prise de vue, où il reste la voie courte.
private struct ChatCameraPicker: UIViewControllerRepresentable {
    let onFinish: (Data?) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onFinish: onFinish)
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let controller = UIImagePickerController()
        controller.sourceType = .camera
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}

    /// Le délégué. Une classe, parce que `UIImagePickerControllerDelegate` est un
    /// protocole Objective-C — et `@MainActor`, parce que ses rappels arrivent
    /// tous sur l'acteur principal.
    @MainActor
    final class Coordinator: NSObject, UIImagePickerControllerDelegate,
        UINavigationControllerDelegate
    {
        private let onFinish: (Data?) -> Void

        init(onFinish: @escaping (Data?) -> Void) {
            self.onFinish = onFinish
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            let image = info[.editedImage] as? UIImage ?? info[.originalImage] as? UIImage
            // 0,85 : au-delà, le poids double sans que l'œil y gagne quoi que
            // ce soit à la taille d'une page de carnet.
            onFinish(image?.jpegData(compressionQuality: 0.85))
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            onFinish(nil)
        }
    }
}
