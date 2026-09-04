#!/usr/bin/env python3
"""Importe le jeu d'icônes de marque dans le catalogue d'assets de l'app.

Source : ``assets/icons/brand-icons`` (voir son README pour les conventions).
Cible  : ``ios/Modules/Sources/MemoBookDesign/Resources/MemoBookAssets.xcassets``

Chaque SVG devient un ``.imageset`` en *Single Scale / Preserve Vector Data* :
l'icône reste vectorielle et ne pixellise pas quand le Dynamic Type l'agrandit.

    Printer.svg    → IconPrinter.imageset
    Printer 2.svg  → IconPrinterDuo.imageset

Le script est **idempotent** : il réécrit ce qui existe et ne touche à rien
d'autre dans le catalogue — les illustrations du Welcome et le motif de fond
sont laissés en place.

    python3 ios/Tools/import-brand-icons.py
"""

import json
import re
import shutil
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
SOURCE = REPO / "assets" / "icons" / "brand-icons"
CATALOG = (
    REPO
    / "ios/Modules/Sources/MemoBookDesign/Resources/MemoBookAssets.xcassets"
)


def asset_name(stem: str) -> str:
    """« Picture Frame 2 » → IconPictureFrameDuo."""
    duo = stem.endswith(" 2")
    base = stem[:-2].strip() if duo else stem

    words = [w for w in re.split(r"[\s\-]+", base) if w]
    # Un mot déjà tout en capitales (PDF, PC) garde sa casse.
    pascal = "".join(w if w.isupper() else w[0].upper() + w[1:] for w in words)

    return f"Icon{pascal}" + ("Duo" if duo else "")


def main() -> int:
    if not SOURCE.is_dir():
        print(f"Source introuvable : {SOURCE}", file=sys.stderr)
        return 1
    if not CATALOG.is_dir():
        print(f"Catalogue introuvable : {CATALOG}", file=sys.stderr)
        return 1

    svgs = sorted(SOURCE.glob("*.svg"))
    if not svgs:
        print(f"Aucun SVG dans {SOURCE}", file=sys.stderr)
        return 1

    for svg in svgs:
        # Un export Figma avec cet attribut se fait déformer par Xcode.
        if 'preserveAspectRatio="none"' in svg.read_text(errors="ignore"):
            print(f"⚠️  {svg.name} porte preserveAspectRatio=\"none\" — à retirer")

        name = asset_name(svg.stem)
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

    mono = sum(1 for s in svgs if not s.stem.endswith(" 2"))
    print(f"{len(svgs)} icônes importées ({mono} monochromes, {len(svgs) - mono} bichromes)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
