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

    /// La dalle de la scène affichée, et non `UIScreen.main` — dépréciée, et
    /// fausse dès qu'une app tourne dans plusieurs fenêtres.
    @MainActor
    private static var screenSize: CGSize {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let scene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
        return scene?.screen.bounds.size ?? .zero
    }
}
