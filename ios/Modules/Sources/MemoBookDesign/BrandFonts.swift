import CoreText
import Foundation
import SwiftUI

/// Les polices de la marque sont des ressources du module, pas de la cible app.
///
/// `UIAppFonts` dans l'Info.plist ne sait charger que le bundle principal : il
/// ne verrait pas ces fichiers. On les enregistre donc auprès de CoreText au
/// premier usage — ce qui a l'avantage de les rendre disponibles aussi dans les
/// aperçus Xcode du module, sans lancer l'app.
///
/// Les deux familles sont livrées en variable dans le dépôt ; ce sont des
/// instances statiques figées à un poids précis qui sont embarquées ici. iOS
/// n'expose pas les instances nommées d'une police variable : sans cela,
/// demander un semi-gras donnerait un faux gras synthétique.
public enum BrandFonts {
    /// Sora SemiBold — titres.
    public static let soraSemiBold = "Sora-SemiBold"

    /// General Sans — corps de texte, dans les trois graisses de la maquette.
    public static let generalSansRegular = "GeneralSans-Regular"
    public static let generalSansMedium = "GeneralSans-Medium"
    public static let generalSansSemibold = "GeneralSans-Semibold"

    private static let register: Void = {
        let fonts =
            (Bundle.module.urls(forResourcesWithExtension: "ttf", subdirectory: "Fonts") ?? [])
            + (Bundle.module.urls(forResourcesWithExtension: "ttf", subdirectory: nil) ?? [])

        for url in Set(fonts) {
            var error: Unmanaged<CFError>?
            // `.process` : les polices restent privées à l'app, elles ne sont
            // pas offertes aux autres processus.
            guard !CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error) else { continue }

            // Un ré-enregistrement n'est pas une erreur : les aperçus Xcode
            // rechargent le bundle sans relancer le processus.
            let code = CFErrorGetCode(error?.takeUnretainedValue())
            if code != CTFontManagerError.alreadyRegistered.rawValue {
                assertionFailure("Police non enregistrée : \(url.lastPathComponent) (code \(code))")
            }
        }
    }()

    /// À appeler une fois au démarrage. Les appels suivants ne font rien.
    public static func registerIfNeeded() { _ = register }
}

/// Le catalogue d'images de la marque vit dans ce module. Ce helper évite
/// d'avoir à répéter `bundle: .module` sur chaque `Image`.
extension Image {
    public init(brand name: String) {
        self.init(name, bundle: .module)
    }
}
