import SwiftUI

/// **Le temps qu'il faisait**, dessiné : l'icône, et la température à côté
/// quand on l'a (T263, Hugo — « chaque étape devrait porter sa date et sa
/// température, avec une petite icône météo »).
///
/// ⚠️ **Les cinq glyphes sont ceux du carnet.** Ils viennent du même manifeste
/// (`assets/icons/manifest.json`), embarqués dans le gabarit par
/// `npm run icons:build` et dans l'app par
/// `python3 ios/Tools/import-weather-icons.py`. Un temps qu'il fait ne se
/// dessine pas d'une façon à l'écran et d'une autre à l'impression ; le jour
/// où l'un des cinq change, les deux suivent ensemble.
///
/// Le nom d'asset se **calcule** depuis la clé plutôt que de vivre dans une
/// table : `sun-wind` → `IconWeatherSunWind`, comme côté script. Une table de
/// cinq lignes serait une seconde vérité à tenir d'accord.
public struct WeatherIcon: View {
    private let asset: String?
    private let temperatureC: Int?

    /// **Initialiseur faillible, et c'est voulu** : rien à dire, rien à
    /// dessiner. Sans icône *et* sans température, la vue n'existe pas — elle
    /// ne laisse donc ni place vide ni écart dans la pile qui la porte. Une
    /// étape sans météo ne doit pas faire de trou dans sa carte.
    ///
    /// L'un des deux suffit : une température sans icône s'affiche seule, et
    /// une icône sans température aussi.
    public init?(weatherKey: String?, temperatureC: Int?) {
        let asset = WeatherIcon.assetName(for: weatherKey)
        guard asset != nil || temperatureC != nil else { return nil }
        self.asset = asset
        self.temperatureC = temperatureC
    }

    /// Les cinq clés que la rédaction relève et que le gabarit sait dessiner.
    /// Une clé inconnue — un temps ajouté côté serveur, une app pas encore à
    /// jour — rend `nil` : on n'affiche rien plutôt qu'un carré vide.
    static func assetName(for key: String?) -> String? {
        guard let key, !key.isEmpty else { return nil }
        let known = ["sun", "sun-wind", "cloud", "rain", "snow"]
        guard known.contains(key) else { return nil }
        return "IconWeather" + key.split(separator: "-").map { $0.capitalized }.joined()
    }

    public var body: some View {
        HStack(spacing: MemoBookSpacing.xs / 2) {
            if let asset {
                Image(brand: asset)
                    .resizable()
                    .renderingMode(.template)
                    .scaledToFit()
                    .frame(width: side, height: side)
            }
            if let temperatureC {
                Text("\(temperatureC) °C")
            }
        }
        .font(MemoBookFont.label)
        .foregroundStyle(MemoBookColor.inkMuted)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(spoken)
    }

    /// L'icône suit la taille du texte à côté d'elle : à AX5, une image figée
    /// à 14 pt se perdrait sous une température de 30.
    @ScaledMetric(relativeTo: .caption) private var side: CGFloat = 14

    /// Dit, pas seulement montré. « Soleil, 28 degrés » plutôt qu'une image
    /// muette suivie d'un « 28 °C » que rien ne rattache à elle.
    private var spoken: String {
        let temps: String?
        switch asset {
        case "IconWeatherSun": temps = "Soleil"
        case "IconWeatherSunWind": temps = "Soleil et vent"
        case "IconWeatherCloud": temps = "Nuageux"
        case "IconWeatherRain": temps = "Pluie"
        case "IconWeatherSnow": temps = "Neige"
        default: temps = nil
        }
        let degres = temperatureC.map { "\($0) degrés" }
        return [temps, degres].compactMap { $0 }.joined(separator: ", ")
    }
}
