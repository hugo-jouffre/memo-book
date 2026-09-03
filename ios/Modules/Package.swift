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
    // Le SDK Google doit être déclaré **ici** et non dans `project.yml` : un
    // package listé là-bas n'est visible que de la cible app, alors que
    // l'écran d'entrée vit dans `MemoBookFeature`. La cible app y accède quand
    // même, par transitivité.
    dependencies: [
        .package(url: "https://github.com/google/GoogleSignIn-iOS", from: "9.0.0"),
    ],
    targets: [
        // Modèles et types partagés. Aucune dépendance : c'est ce qui permet de
        // le tester sur n'importe quelle plateforme.
        .target(name: "MemoBookCore"),

        // Design tokens, composants transverses, et les ressources de la
        // marque (polices, icônes). Les ressources vivent ici plutôt que dans
        // la cible app pour que les aperçus Xcode du module les voient aussi.
        .target(
            name: "MemoBookDesign",
            dependencies: ["MemoBookCore"],
            resources: [.process("Resources")]
        ),

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
                // Seul `GoogleSignIn` est utile : `GoogleSignInSwift` n'apporte
                // que son bouton, et le nôtre est déjà dessiné.
                .product(name: "GoogleSignIn", package: "GoogleSignIn-iOS"),
            ]
        ),

        .testTarget(name: "MemoBookCoreTests", dependencies: ["MemoBookCore"]),
        .testTarget(
            name: "MemoBookNetworkingTests",
            dependencies: ["MemoBookNetworking", "MemoBookCore"]
        ),
    ]
)
