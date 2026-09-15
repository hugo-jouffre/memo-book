#!/usr/bin/env python3
"""Importe les logos de marque dans le catalogue d'assets de l'app.

Source : ``assets/logos``
Cible  : ``ios/Modules/Sources/MemoBookDesign/Resources/MemoBookAssets.xcassets``

Même principe que ``import-brand-icons.py`` — le catalogue ne se remplit jamais
à la main, et le script est idempotent. La table ``NAMES`` dit quels fichiers
sont importés : un logo qui n'y figure pas reste dans ``assets/`` sans entrer
dans le binaire.

    Apple Icon.svg → LogoApple.imageset
    Apple Pay.svg  → LogoApplePay.imageset

⚠️ **Deux formes de SVG cohabitent dans ce dossier**, et elles ne s'importent
pas pareil :

- Un **vrai vectoriel** (tracés, dégradés) est recopié tel quel, en *Preserve
  Vector Data* : il ne pixellise pas quand le Dynamic Type l'agrandit.
- Un **export d'image** — Figma pose alors le bitmap en base64 dans un
  ``<pattern>``, et n'en montre qu'une découpe via la matrice d'un ``<use>``.
  Xcode ne sait pas rendre ça : son moteur SVG dessine des formes, pas des
  images incorporées. Et l'incorporer voudrait dire embarquer **toute la
  planche** (160 ko de base64 pour une icône de 24 pt, la planche entière
  recopiée dans chacune des deux). On décode donc le bitmap, on en extrait la
  découpe, et on écrit un PNG à sa résolution native.

    python3 ios/Tools/import-brand-logos.py
"""

import base64
import io
import json
import re
import shutil
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
SOURCE = REPO / "assets" / "logos"
CATALOG = REPO / "ios/Modules/Sources/MemoBookDesign/Resources/MemoBookAssets.xcassets"

# Les noms de fichiers viennent de Figma et ne sont pas des identifiants ; la
# table dit comment ils s'appellent côté Swift. Les connecteurs
# (`assets/logos/connectors`) ont les leurs et ne passent pas par ici.
NAMES = {
    "Apple Icon": "LogoApple",
    "Google Icon": "LogoGoogle",
    "Apple Pay": "LogoApplePay",
    "Memobook Creme": "LogoMemobookCreme",
}

DATA_URI = re.compile(r'xlink:href="data:image/png;base64,([^"]+)"')
USE_MATRIX = re.compile(r'<use[^>]*transform="matrix\(([-\d.eE ]+)\)"')


def crop_of(svg: str) -> tuple[bytes, tuple[int, int, int, int]] | None:
    """La découpe que montre un export d'image Figma, ou ``None`` si vectoriel.

    Figma écrit la planche entière en base64 et la place par une matrice
    ``(sx 0 0 sy tx ty)`` en unités de la boîte englobante : le pixel *x* de
    l'image tombe en ``sx·x + tx``. Ce qui se voit est donc ce qui retombe dans
    ``[0, 1]``, soit ``x ∈ [-tx/sx, (1-tx)/sx]``.
    """
    data = DATA_URI.search(svg)
    matrix = USE_MATRIX.search(svg)
    if not data or not matrix:
        return None

    sx, _, _, sy, tx, ty = (float(v) for v in matrix.group(1).split())
    raw = base64.b64decode(data.group(1))

    from PIL import Image  # importé ici : un logo vectoriel n'en a pas besoin

    with Image.open(io.BytesIO(raw)) as sheet:
        width, height = sheet.size

    box = (
        max(0, round(-tx / sx)),
        max(0, round(-ty / sy)),
        min(width, round((1 - tx) / sx)),
        min(height, round((1 - ty) / sy)),
    )
    return raw, box


def write_contents(folder: Path, filename: str, *, vector: bool) -> None:
    contents: dict[str, object] = {
        "images": [{"filename": filename, "idiom": "universal"}],
        "info": {"author": "xcode", "version": 1},
    }
    if vector:
        contents["properties"] = {"preserves-vector-representation": True}
    (folder / "Contents.json").write_text(json.dumps(contents, indent=2) + "\n")


def main() -> int:
    if not SOURCE.is_dir():
        print(f"Source introuvable : {SOURCE}", file=sys.stderr)
        return 1
    if not CATALOG.is_dir():
        print(f"Catalogue introuvable : {CATALOG}", file=sys.stderr)
        return 1

    vectors = rasters = 0

    for stem, name in sorted(NAMES.items()):
        svg = SOURCE / f"{stem}.svg"
        if not svg.is_file():
            print(f"⚠️  {svg.name} manquant — ignoré")
            continue

        folder = CATALOG / f"{name}.imageset"
        folder.mkdir(exist_ok=True)
        # Un logo qui passe du vectoriel au bitmap (ou l'inverse) laisserait
        # l'ancien fichier derrière lui, et le catalogue en montrerait deux.
        for stale in folder.glob("*"):
            stale.unlink()

        cropped = crop_of(svg.read_text(errors="ignore"))

        if cropped is None:
            if 'preserveAspectRatio="none"' in svg.read_text(errors="ignore"):
                print(f'⚠️  {svg.name} porte preserveAspectRatio="none" — à retirer')
            shutil.copyfile(svg, folder / f"{name}.svg")
            write_contents(folder, f"{name}.svg", vector=True)
            vectors += 1
            continue

        from PIL import Image

        raw, box = cropped
        with Image.open(io.BytesIO(raw)) as sheet:
            # *Single Scale*, à la résolution native de la découpe : on ne
            # choisit pas de taille en points, donc pas d'arrondi qui écrase le
            # dessin. L'icône se pose de toute façon dans un cadre explicite,
            # et iOS sous-échantillonne proprement.
            sheet.convert("RGBA").crop(box).save(folder / f"{name}.png", optimize=True)

        write_contents(folder, f"{name}.png", vector=False)
        rasters += 1
        print(f"{svg.name} → {name} ({box[2] - box[0]}×{box[3] - box[1]} px)")

    print(f"{vectors + rasters} logos importés ({vectors} vectoriels, {rasters} bitmaps)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
