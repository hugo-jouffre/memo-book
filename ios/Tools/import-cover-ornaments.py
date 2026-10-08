#!/usr/bin/env python3
"""Découpe les ornements des gabarits de couverture dans le catalogue d'assets.

Source : ``assets/covers`` — les quatorze plats de Hugo (08/10/2026), sept
paires « front cover_style … » / « back cover_style … ».
Cible  : ``ios/Modules/Sources/MemoBookDesign/Resources/MemoBookAssets.xcassets``

L'app **redessine** chaque gabarit avec la photo et les mots du voyageur
(``CoverTemplates.swift``). Ce qui ne se redessine pas — une palme, une moto
au trait, un globe, des courbes tracées à la main — est découpé ici dans le
plat de Hugo, et son fond (l'aplat du plat) rendu transparent : l'ornement se
pose ensuite sur l'aplat que l'app dessine.

    front cover_style dessin.png, moto du haut → CoverOrnamentMotorbike.imageset

Le script est **idempotent** : il réécrit ses propres imagesets et ne touche à
rien d'autre dans le catalogue.

    python3 ios/Tools/import-cover-ornaments.py
"""

import json
import sys
from pathlib import Path

from PIL import Image

REPO = Path(__file__).resolve().parents[2]
SOURCE = REPO / "assets" / "covers"
CATALOG = REPO / "ios/Modules/Sources/MemoBookDesign/Resources/MemoBookAssets.xcassets"

# (asset, fichier, cadre en fractions du plat (x0, y0, x1, y1), aplat à retirer)
ORNAMENTS = [
    ("CoverOrnamentPalm", "front covers/front cover_style assouline.png", (0.05, 0.19, 0.95, 0.88), (0xAF, 0xD2, 0xF0)),
    ("CoverOrnamentMotorbike", "front covers/front cover_style dessin.png", (0.33, 0.13, 0.68, 0.29), (0xF6, 0xEE, 0xE6)),
    ("CoverOrnamentRoad", "front covers/front cover_style dessin.png", (0.24, 0.58, 0.76, 0.66), (0xF6, 0xEE, 0xE6)),
    ("CoverOrnamentGlobe", "front covers/front cover_style dessin.png", (0.39, 0.69, 0.62, 0.86), (0xF6, 0xEE, 0xE6)),
    ("CoverOrnamentRider", "back covers/back cover_style dessin.png", (0.27, 0.32, 0.70, 0.64), (0xF6, 0xEE, 0xE6)),
    ("CoverOrnamentContours", "back covers/back cover_style photo-dessin.png", (0.0, 0.0, 0.62, 0.21), (0xCD, 0xF9, 0xF5)),
]

# En deçà de cette distance à l'aplat, le pixel est du fond ; au-delà de
# FULL, il est entièrement de l'ornement ; entre les deux, il s'adoucit — le
# papier des plats a du grain, et un seuil franc laisserait des confettis.
CLEAR = 18.0
FULL = 60.0


def key_out(image: Image.Image, background: tuple[int, int, int]) -> Image.Image:
    rgba = image.convert("RGBA")
    pixels = rgba.load()
    width, height = rgba.size
    for y in range(height):
        for x in range(width):
            r, g, b, _ = pixels[x, y]
            distance = ((r - background[0]) ** 2 + (g - background[1]) ** 2 + (b - background[2]) ** 2) ** 0.5
            if distance <= CLEAR:
                alpha = 0
            elif distance >= FULL:
                alpha = 255
            else:
                alpha = int(255 * (distance - CLEAR) / (FULL - CLEAR))
            pixels[x, y] = (r, g, b, alpha)
    return rgba


def main() -> int:
    if not SOURCE.is_dir() or not CATALOG.is_dir():
        print(f"Source ou catalogue introuvable : {SOURCE}, {CATALOG}", file=sys.stderr)
        return 1

    for name, filename, frame, background in ORNAMENTS:
        plate = Image.open(SOURCE / filename)
        width, height = plate.size
        box = tuple(int(round(f * size)) for f, size in zip(frame, (width, height, width, height)))
        ornament = key_out(plate.crop(box), background)
        # Rogné à ce qui reste visible : l'ornement se cale ensuite sur son
        # propre dessin, pas sur un cadre de fond transparent.
        bounds = ornament.getbbox()
        if bounds:
            ornament = ornament.crop(bounds)

        imageset = CATALOG / f"{name}.imageset"
        imageset.mkdir(exist_ok=True)
        for stale in imageset.glob("*.png"):
            stale.unlink()
        ornament.save(imageset / f"{name}.png")
        (imageset / "Contents.json").write_text(
            json.dumps(
                {
                    "images": [{"filename": f"{name}.png", "idiom": "universal"}],
                    "info": {"author": "xcode", "version": 1},
                },
                indent=2,
            )
            + "\n"
        )
        print(f"{name}: {ornament.size[0]}×{ornament.size[1]}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
