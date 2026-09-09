#!/usr/bin/env python3
"""Importe les pictogrammes Lucide dans le catalogue d'assets de l'app.

Source : ``assets/icons/lucide-icons`` (voir son README : licence ISC).
Cible  : ``ios/Modules/Sources/MemoBookDesign/Resources/MemoBookAssets.xcassets``

Même principe que ``import-brand-icons.py``, avec deux retouches en plus, que
la source ne peut pas porter :

- ``stroke="currentColor"`` devient l'encre de la marque. Xcode ne connaît pas
  ``currentColor`` : sans ça, l'icône est invisible. C'est
  ``renderingMode(.template)`` qui la reteinte à l'affichage.
- L'attribut ``class`` est retiré : il ne sert à rien hors du web.

    globe.svg          → IconLucideGlobe.imageset
    mountain-snow.svg  → IconLucideMountainSnow.imageset

Idempotent : il réécrit ce qui existe et ne touche à rien d'autre.

    python3 ios/Tools/import-lucide-icons.py
"""

import json
import re
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
SOURCE = REPO / "assets" / "icons" / "lucide-icons"
CATALOG = REPO / "ios/Modules/Sources/MemoBookDesign/Resources/MemoBookAssets.xcassets"

#: *Brand Colors/Black*, la même encre que le jeu de marque.
INK = "#2D231A"


def asset_name(stem: str) -> str:
    """« mountain-snow » → IconLucideMountainSnow."""
    words = [w for w in re.split(r"[\s\-_]+", stem) if w]
    return "IconLucide" + "".join(w[0].upper() + w[1:] for w in words)


def normalise(svg: str) -> str:
    svg = svg.replace('stroke="currentColor"', f'stroke="{INK}"')
    return re.sub(r'\s*class="[^"]*"', "", svg)


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
        name = asset_name(svg.stem)
        folder = CATALOG / f"{name}.imageset"
        folder.mkdir(exist_ok=True)

        (folder / f"{name}.svg").write_text(normalise(svg.read_text()))
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

    keys = ", ".join(sorted(s.stem for s in svgs))
    print(f"{len(svgs)} pictogrammes importés : {keys}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
