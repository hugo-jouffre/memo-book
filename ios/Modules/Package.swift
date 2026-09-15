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
        .library(name: "MemoBookPayments", targets: ["MemoBookPayments"]),
        .library(name: "MemoBookRecording", targets: ["MemoBookRecording"]),
        .library(name: "MemoBookFeature", targets: ["MemoBookFeature"]),
    ],
    // Le SDK Google doit être déclaré **ici** et non dans `project.yml` : un
    // package listé là-bas n'est visible que de la cible app, alors que
    // l'écran d'entrée vit dans `MemoBookFeature`. La cible app y accède quand
    // même, par transitivité.
    dependencies: [
        .package(url: "https://github.com/google/GoogleSignIn-iOS", from: "9.0.0"),
        // Stripe, pour la feuille de paiement du carnet imprimé et de la
        // cagnotte. **Jamais pour l'abonnement** : Apple impose l'achat intégré
        // pour un service numérique, et l'encaisser ici ferait rejeter le
        // binaire. Voir `MemoBookPayments`.
        .package(url: "https://github.com/stripe/stripe-ios", from: "24.0.0"),
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

        // La feuille de paiement Stripe, isolée dans son module.
        //
        // À part, et pas dans `MemoBookFeature`, pour une raison précise : le
        // SDK Stripe est la seule dépendance de l'app qui touche à de l'argent.
        // L'isoler rend visible, à la lecture du graphe, **tout** ce qui peut
        // déclencher un paiement — et garantit qu'aucun écran ne l'appelle
        // sans passer par la façade qu'on contrôle.
        .target(
            name: "MemoBookPayments",
            dependencies: [
                "MemoBookCore",
                .product(name: "StripePaymentSheet", package: "stripe-ios"),
            ]
        ),

        // Capture audio (AVFoundation) et permissions.
        .target(name: "MemoBookRecording", dependencies: ["MemoBookCore"]),

        // Écrans SwiftUI et leurs modèles de vue.
        .target(
            name: "MemoBookFeature",
            dependencies: [
                "MemoBookCore",
                "MemoBookDesign",
                "MemoBookNetworking",
                "MemoBookPayments",
                "MemoBookRecording",
                // Seul `GoogleSignIn` est utile : `GoogleSignInSwift` n'apporte
                // que son bouton, et le nôtre est déjà dessiné.
                .product(name: "GoogleSignIn", package: "GoogleSignIn-iOS"),
            ]
        ),

        .testTarget(name: "MemoBookCoreTests", dependencies: ["MemoBookCore"]),
        // Ce que le design system décide **hors d'une vue** : aujourd'hui, la
        // résolution d'un pictogramme de catégorie vers son asset. Le catalogue
        // est une ressource de ce module, donc c'est ici qu'on peut vérifier
        // qu'une image existe vraiment.
        .testTarget(name: "MemoBookDesignTests", dependencies: ["MemoBookDesign"]),
        .testTarget(
            name: "MemoBookNetworkingTests",
            dependencies: ["MemoBookNetworking", "MemoBookCore"]
        ),
    ]
)
