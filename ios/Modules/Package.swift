// swift-tools-version: 6.0
import PackageDescription

/// Le code de l'app vit ici, pas dans la cible Xcode : les modules purs se
/// compilent et se testent avec `swift test`, sans simulateur ni Xcode.
let package = Package(
    name: "MemoBookKit",
    defaultLocalization: "fr",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "MemoBookCore", targets: ["MemoBookCore"]),
        .library(name: "MemoBookDesign", targets: ["MemoBookDesign"]),
        .library(name: "MemoBookNetworking", targets: ["MemoBookNetworking"]),
        .library(name: "MemoBookRecording", targets: ["MemoBookRecording"]),
        .library(name: "MemoBookFeature", targets: ["MemoBookFeature"]),
    ],
    targets: [
        // Modèles et types partagés. Aucune dépendance : c'est ce qui permet de
        // le tester sur n'importe quelle plateforme.
        .target(name: "MemoBookCore"),

        // Design tokens et composants transverses.
        .target(name: "MemoBookDesign", dependencies: ["MemoBookCore"]),

        // Client de l'API MemoBook.
        .target(name: "MemoBookNetworking", dependencies: ["MemoBookCore"]),

        // Capture audio (AVFoundation) et permissions.
        .target(name: "MemoBookRecording", dependencies: ["MemoBookCore"]),

        // Écrans SwiftUI et leurs modèles de vue.
        .target(
            name: "MemoBookFeature",
            dependencies: [
                "MemoBookCore",
                "MemoBookDesign",
                "MemoBookNetworking",
                "MemoBookRecording",
            ]
        ),

        .testTarget(name: "MemoBookCoreTests", dependencies: ["MemoBookCore"]),
        .testTarget(
            name: "MemoBookNetworkingTests",
            dependencies: ["MemoBookNetworking", "MemoBookCore"]
        ),
    ]
)
