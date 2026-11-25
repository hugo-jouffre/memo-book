import CoreText
import Foundation
import SwiftUI
import UIKit

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
    /// Sora — titres. Deux graisses : le paywall écrit ses titres en **deux
    /// temps**, la moitié courante en Regular et la chute en SemiBold.
    public static let soraRegular = "Sora-Regular"
    public static let soraSemiBold = "Sora-SemiBold"

    /// General Sans — corps de texte, dans les trois graisses de la maquette.
    public static let generalSansRegular = "GeneralSans-Regular"
    public static let generalSansMedium = "GeneralSans-Medium"
    public static let generalSansSemibold = "GeneralSans-Semibold"

    /// Gloria Hallelujah — **l'écriture à la main du carnet**, et rien d'autre
    /// dans l'app.
    ///
    /// C'est déjà la police manuscrite du template d'impression
    /// (`memos.fontHand`), livrée en `woff2` dans
    /// `MemoBook Generator/templates/travel-journal/assets/fonts/`. CoreText ne sait pas lire le
    /// woff2 : le fichier embarqué ici est le **même** dessin converti en TTF,
    /// pas une seconde police.
    ///
    /// Le nom est celui du PostScript, sans tiret — c'est celui que
    /// `Font.custom` attend, et il diffère du nom de fichier.
    public static let gloriaHallelujah = "GloriaHallelujah"

    // MARK: - Les polices des couvertures

    /// **Les typographies des sept plats**, celles de l'atelier d'impression
    /// (`MemoBook Generator/public/couverture-styles.js`, § `POLICES`).
    ///
    /// Elles ne servent **qu'aux plats** : l'app n'écrit rien d'autre avec.
    /// Jusqu'au 25/11/2026 elle les approchait par les polices du système — un
    /// empattement pour « Par défaut » et « Élégant », le grotesque le plus
    /// lourd pour les trois autres —, si bien qu'un même plat sortait en trois
    /// typographies selon qu'on le regardait à l'écran, dans le PDF du carnet
    /// ou sur le livre imprimé. On choisit une couverture en la regardant
    /// (T256, Hugo).
    ///
    /// Toutes sont sous licence libre (OFL), livrées avec l'atelier et
    /// converties par `ios/Tools/make-brand-fonts.py` — **le même dessin**, pas
    /// une seconde police. ⚠️ Au sous-ensemble latin : une lettre d'Europe
    /// centrale dans un titre tomberait sur la police du système.
    public enum Cover {
        /// « Par défaut » : le titre en capitales. Et « Assouline » pour tout
        /// ce qui n'est pas son titre.
        public static let playfairBlack = "PlayfairDisplay-Black"
        public static let playfairRegular = "PlayfairDisplay-Regular"

        /// « Élégant » : le titre, puis le reste dans la variante Infant.
        public static let cormorantGaramond = "CormorantGaramond-Regular"
        public static let cormorantInfant = "CormorantInfant-Medium"

        /// « Assouline » : le titre, large et noir.
        public static let archivoBlack = "ArchivoBlack-Regular"

        /// « Aquarelle » : le titre, puis le reste en Manrope.
        public static let poppinsBlack = "Poppins-Black"
        public static let manrope = "Manrope-Regular"

        /// « Travel book » : une seule police pour tout le plat.
        public static let lilitaOne = "LilitaOne"

        /// « Photo-dessin » : le pinceau. « Dessin », lui, garde
        /// ``BrandFonts/gloriaHallelujah`` — c'est la police que l'atelier lui
        /// donne aussi.
        public static let caveatBrush = "CaveatBrush-Regular"
    }

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

extension UIImage {
    /// La même image du catalogue de la marque, pour ce qui ne parle qu'UIKit
    /// — les gestes de la feuille de partage du système.
    public static func brand(_ name: String) -> UIImage? {
        UIImage(named: name, in: .module, compatibleWith: nil)
    }
}
