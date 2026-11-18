#!/usr/bin/env python3
"""Importe les cinq icônes météo dans le catalogue d'assets de l'app.

Source : ``assets/icons/manifest.json`` — **le même fichier que le carnet**.
Cible  : ``ios/Modules/Sources/MemoBookDesign/Resources/MemoBookAssets.xcassets``

C'est tout l'intérêt de passer par le manifeste plutôt que de nommer cinq
fichiers ici : ``npm run icons:build`` embarque ces mêmes SVG dans le gabarit
(``mb-i-weather-…``), et ce script les embarque dans l'app. Le jour où l'un des
cinq change de dessin, les deux suivent ensemble. Un temps qu'il fait ne doit
pas se dessiner d'une façon dans l'app et d'une autre dans le livre.

Le nom d'asset se déduit de la clé, qui est celle que la rédaction relève
(``entries.weatherKey``) et que le serveur sert telle quelle :

    weather-sun       → IconWeatherSun
    weather-sun-wind  → IconWeatherSunWind

Côté Swift, ``WeatherIcon`` refait ce calcul : il n'y a pas de table à tenir.

Le script est **idempotent** : il réécrit ce qui existe et ne touche à rien
d'autre dans le catalogue.

    python3 ios/Tools/import-weather-icons.py
"""

import json
import shutil
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
MANIFEST = REPO / "assets" / "icons" / "manifest.json"
ICONS = REPO / "assets" / "icons"
CATALOG = REPO / "ios/Modules/Sources/MemoBookDesign/Resources/MemoBookAssets.xcassets"

PREFIX = "weather-"


def asset_name(role: str) -> str:
    """« weather-sun-wind » → IconWeatherSunWind."""
    return "Icon" + "".join(word.capitalize() for word in role.split("-"))


def main() -> int:
    if not MANIFEST.is_file():
        print(f"Manifeste introuvable : {MANIFEST}", file=sys.stderr)
        return 1
    if not CATALOG.is_dir():
        print(f"Catalogue introuvable : {CATALOG}", file=sys.stderr)
        return 1

    roles = {
        role: path
        for role, path in json.loads(MANIFEST.read_text())["icons"].items()
        if role.startswith(PREFIX)
    }
    if not roles:
        print(f"Aucune icône « {PREFIX}… » dans le manifeste", file=sys.stderr)
        return 1

    for role, relative in sorted(roles.items()):
        svg = ICONS / relative
        if not svg.is_file():
            print(f"Source introuvable : {svg}", file=sys.stderr)
            return 1

        # Un export Figma avec cet attribut se fait déformer par Xcode.
        if 'preserveAspectRatio="none"' in svg.read_text(errors="ignore"):
            print(f'⚠️  {svg.name} porte preserveAspectRatio="none" — à retirer')

        name = asset_name(role)
        folder = CATALOG / f"{name}.imageset"
        folder.mkdir(exist_ok=True)

        shutil.copyfile(svg, folder / f"{name}.svg")
        (folder / "Contents.json").write_text(
            json.dumps(
                {
                    "images": [{"filename": f"{name}.svg", "idiom": "universal"}],
                    "info": {"author": "xcode", "version": 1},
                    "properties": {"preserves-vector-representation": True},
                },
                indent=2,
            )
            + "\n"
        )
        print(f"  {role:18} {relative:32} → {name}")

    print(f"{len(roles)} icônes météo importées")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
