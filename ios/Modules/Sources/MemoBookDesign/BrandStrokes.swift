import SwiftUI

// Les traits dessinés à la main de la marque, repris des vecteurs Figma du
// paywall (nœud `3297:20771`).
//
// **Ce sont des `Shape`, pas des images.** Un SVG posé dans un `Image` ne sait
// pas se tracer progressivement ; une `Shape`, si — `trim(from:to:)` suffit, et
// c'est exactement l'animation que Figma décrit sur ces nœuds (`path-trim`).
// Les coordonnées viennent telles quelles de l'export, rapportées au cadre reçu
// pour que le trait suive la largeur de l'écran.

/// Le grand trait bleu qui traverse le premier écran du paywall — il descend, fait sa boucle, et repart vers la droite.
public struct BrandSquiggleDown: Shape {
    /// Le cadre du tracé dans Figma : 442.362 × 93.6948.
    public static let size = CGSize(width: 442.362, height: 93.6948)
    /// L'épaisseur du trait, en fraction de la hauteur du tracé.
    public static let lineWidthRatio: CGFloat = 12 / 93.6948

    public init() {}

    public func path(in rect: CGRect) -> Path {
        let w = rect.width / Self.size.width
        let h = rect.height / Self.size.height
        var path = Path()
        path.move(to: CGPoint(x: 6.00008 * w, y: 40.7985 * h))
        path.addCurve(
            to: CGPoint(x: 111.911 * w, y: 12.824 * h),
            control1: CGPoint(x: 6.00008 * w, y: 40.7985 * h),
            control2: CGPoint(x: 66.538 * w, y: -12.4846 * h)
        )
        path.addCurve(
            to: CGPoint(x: 111.251 * w, y: 87.6885 * h),
            control1: CGPoint(x: 157.284 * w, y: 38.1326 * h),
            control2: CGPoint(x: 134.861 * w, y: 88.3373 * h)
        )
        path.addCurve(
            to: CGPoint(x: 109.456 * w, y: 32.0493 * h),
            control1: CGPoint(x: 87.6411 * w, y: 87.0396 * h),
            control2: CGPoint(x: 84.7476 * w, y: 46.3371 * h)
        )
        path.addCurve(
            to: CGPoint(x: 261.41 * w, y: 81.9699 * h),
            control1: CGPoint(x: 134.165 * w, y: 17.7614 * h),
            control2: CGPoint(x: 190.013 * w, y: 72.8536 * h)
        )
        path.addCurve(
            to: CGPoint(x: 436.362 * w, y: 80.2933 * h),
            control1: CGPoint(x: 332.806 * w, y: 91.0863 * h),
            control2: CGPoint(x: 405.296 * w, y: 76.8523 * h)
        )
        return path
    }
}

/// Le même geste sur le deuxième écran, retourné : la boucle se pose plus haut et le trait remonte.
public struct BrandSquiggleUp: Shape {
    /// Le cadre du tracé dans Figma : 430.875 × 139.984.
    public static let size = CGSize(width: 430.875, height: 139.984)
    /// L'épaisseur du trait, en fraction de la hauteur du tracé.
    public static let lineWidthRatio: CGFloat = 12 / 139.984

    public init() {}

    public func path(in rect: CGRect) -> Path {
        let w = rect.width / Self.size.width
        let h = rect.height / Self.size.height
        var path = Path()
        path.move(to: CGPoint(x: 6.00041 * w, y: 6.00041 * h))
        path.addCurve(
            to: CGPoint(x: 191.959 * w, y: 44.5408 * h),
            control1: CGPoint(x: 6.00041 * w, y: 6.00041 * h),
            control2: CGPoint(x: 146.586 * w, y: 19.2322 * h)
        )
        path.addCurve(
            to: CGPoint(x: 182.887 * w, y: 115.59 * h),
            control1: CGPoint(x: 237.332 * w, y: 69.8495 * h),
            control2: CGPoint(x: 208.558 * w, y: 120.11 * h)
        )
        path.addCurve(
            to: CGPoint(x: 179.731 * w, y: 63.2145 * h),
            control1: CGPoint(x: 157.216 * w, y: 111.07 * h),
            control2: CGPoint(x: 155.022 * w, y: 77.5024 * h)
        )
        path.addCurve(
            to: CGPoint(x: 276.074 * w, y: 60.3797 * h),
            control1: CGPoint(x: 204.439 * w, y: 48.9266 * h),
            control2: CGPoint(x: 240.232 * w, y: 47.015 * h)
        )
        path.addCurve(
            to: CGPoint(x: 424.873 * w, y: 133.983 * h),
            control1: CGPoint(x: 311.917 * w, y: 73.7444 * h),
            control2: CGPoint(x: 363.682 * w, y: 114.993 * h)
        )
        return path
    }
}

/// Le petit trait qui souligne les derniers mots d'un titre, tracé à la main.
public struct BrandUnderline: Shape {
    /// Le cadre du tracé dans Figma : 146.645 × 10.4222.
    public static let size = CGSize(width: 146.645, height: 10.4222)
    /// L'épaisseur du trait, en fraction de la hauteur du tracé.
    public static let lineWidthRatio: CGFloat = 4 / 10.4222

    public init() {}

    public func path(in rect: CGRect) -> Path {
        let w = rect.width / Self.size.width
        let h = rect.height / Self.size.height
        var path = Path()
        path.move(to: CGPoint(x: 2.00033 * w, y: 8.42184 * h))
        path.addCurve(
            to: CGPoint(x: 144.645 * w, y: 4.58676 * h),
            control1: CGPoint(x: 24.1735 * w, y: 4.59981 * h),
            control2: CGPoint(x: 83.745 * w, y: -1.51806 * h)
        )
        return path
    }
}
