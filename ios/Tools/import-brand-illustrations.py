#!/usr/bin/env python3
"""Importe les illustrations de marque dans le catalogue d'assets de l'app.

Source : ``assets/illustrations/brand-illustrations``
Cible  : ``ios/Modules/Sources/MemoBookDesign/Resources/MemoBookAssets.xcassets``

Même principe que ``import-brand-icons.py`` — *Single Scale / Preserve Vector
Data*, pour que le dessin reste vectoriel quand le Dynamic Type l'agrandit — et
même nommage lisible depuis Swift :

    appareilphoto.svg → IllustrationAppareilPhoto.imageset

Le script est **idempotent** : il réécrit ce qu'il connaît et ne touche à rien
d'autre dans le catalogue.

    python3 ios/Tools/import-brand-illustrations.py
"""

import json
import shutil
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
SOURCE = REPO / "assets" / "illustrations" / "brand-illustrations"
CATALOG = REPO / "ios/Modules/Sources/MemoBookDesign/Resources/MemoBookAssets.xcassets"

# Les noms de fichiers sont d'un seul tenant et en français ; la table dit où
# couper les mots. Une illustration absente d'ici n'est pas importée : le
# catalogue ne se remplit pas de dessins que l'app n'affiche nulle part.
NAMES = {
    "appareilphoto": "AppareilPhoto",
    "carnet": "Carnet",
    "duo": "Duo",
    "horloge": "Horloge",
    "hublot": "Hublot",
    "lunettes": "Lunettes",
    "maps": "Maps",
    "passport": "Passport",
    "sapin": "Sapin",
    "tag": "Tag",
    "valise": "Valise",
}


def main() -> int:
    if not SOURCE.is_dir():
        print(f"Source introuvable : {SOURCE}", file=sys.stderr)
        return 1
    if not CATALOG.is_dir():
        print(f"Catalogue introuvable : {CATALOG}", file=sys.stderr)
        return 1

    count = 0
    for stem, suffix in sorted(NAMES.items()):
        svg = SOURCE / f"{stem}.svg"
        if not svg.is_file():
            print(f"⚠️  {svg.name} manquant — ignoré")
            continue

        # Un export Figma avec cet attribut se fait déformer par Xcode.
        if 'preserveAspectRatio="none"' in svg.read_text(errors="ignore"):
            print(f'⚠️  {svg.name} porte preserveAspectRatio="none" — à retirer')

        name = f"Illustration{suffix}"
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
        count += 1

    print(f"{count} illustrations importées")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
