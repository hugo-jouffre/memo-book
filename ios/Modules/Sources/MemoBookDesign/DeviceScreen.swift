import SwiftUI
import UIKit

/// Ce que l'app doit savoir de la dalle sur laquelle elle est posée.
///
/// Une seule chose pour l'instant : **le rayon des coins de l'écran**. Il n'est
/// exposé par aucune API publique — `UIScreen` ne le donne pas — et la seule
/// façon de le lire est une clé privée, qu'on ne veut pas expédier à l'App
/// Store. On le déduit donc du format de la dalle, qui est public et stable.
///
/// C'est ce rayon qui permet à une feuille modale d'être **concentrique** au
/// téléphone : ses coins suivent la courbe du verre au lieu de la couper.
public enum DeviceScreen {
    /// Rayon des coins de l'écran, en points.
    ///
    /// | Format | Rayon | Appareils |
    /// |---|---|---|
    /// | bouton d'accueil | 0 | SE, 8 et antérieurs : la dalle est un rectangle |
    /// | 360 × 780 | 44 | 12 et 13 mini |
    /// | 375 × 812 · 390 × 844 | 47,33 | encoche, du X au 14 |
    /// | le reste | 55 | Dynamic Island, du 14 Pro à aujourd'hui |
    ///
    /// Un format inconnu tombe sur 55, le rayon des appareils récents : mieux
    /// vaut une feuille très légèrement arrondie qu'une feuille aux angles
    /// droits sur un téléphone qui n'en a pas.
    @MainActor
    public static var cornerRadius: CGFloat {
        let size = screenSize
        let height = max(size.width, size.height)
        let width = min(size.width, size.height)

        return switch (width, height) {
        case (_, ..<800): 0
        case (..<365, _): 44
        case (_, ..<850): 47.33
        default: 55
        }
    }

    /// Hauteur de la dalle, en points. Sert à borner une feuille modale pour
    /// qu'elle ne monte jamais jusqu'en haut.
    @MainActor
    public static var height: CGFloat {
        let size = screenSize
        return max(size.width, size.height)
    }

    /// Ce que la barre d'état et l'encoche prennent en haut de l'écran.
    ///
    /// C'est la seule mesure qui change vraiment d'un iPhone à l'autre — 20 pt
    /// sur un SE, 59 sur un modèle à Dynamic Island. Tout ce qui doit se poser
    /// « juste sous le haut » s'y réfère, sans quoi le même code donne deux
    /// écrans différents selon le téléphone.
    @MainActor
    public static var topSafeInset: CGFloat {
        keyWindow?.safeAreaInsets.top ?? 0
    }

    @MainActor
    private static var keyWindow: UIWindow? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow }
    }

    /// La dalle de la scène affichée, et non `UIScreen.main` — dépréciée, et
    /// fausse dès qu'une app tourne dans plusieurs fenêtres.
    @MainActor
    private static var screenSize: CGSize {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let scene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
        return scene?.screen.bounds.size ?? .zero
    }
}
