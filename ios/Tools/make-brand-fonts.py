#!/usr/bin/env python3
"""Fabrique les polices embarquées dans l'app à partir des sources du dépôt.

    python3 ios/Tools/make-brand-fonts.py     # depuis la racine du dépôt

Le dépôt versionne Sora et General Sans en **variable**. iOS n'expose pas les
instances nommées d'une police variable : demander un semi-gras à
`Font.custom` donnerait un faux gras synthétique, pas le vrai dessin 600. On
fige donc ici une instance statique par graisse utilisée dans la maquette.

Au passage, les métriques verticales sont alignées sur les interlignes du
fichier Figma. SwiftUI ne sait qu'**ajouter** de l'interligne — `lineSpacing`
ignore les valeurs négatives — donc un interligne plus serré que la police ne
peut pas se rattraper côté code : il se règle dans la police.

Relancer ce script après toute mise à jour des sources variables.
"""

from pathlib import Path

from fontTools.ttLib import TTFont
from fontTools.varLib import instancer

ROOT = Path(__file__).resolve().parents[2]
SOURCES = ROOT / "MemoBook Generator" / "public" / "fonts"
DESTINATION = ROOT / "ios" / "Modules" / "Sources" / "MemoBookDesign" / "Resources" / "Fonts"

# Interlignes des styles Figma, en multiple de la taille du corps.
#   Sora        — `App/h1` : 32 pt de corps pour 35 pt d'interligne.
#   General Sans — `App/body semibold` et consorts : 1.3.
LINE_HEIGHT = {"Sora": 35 / 32, "General Sans": 1.30}

# (fichier source, graisse, famille, style)
INSTANCES = [
    ("Sora-Variable.ttf", 600, "Sora", "SemiBold"),
    ("GeneralSans-Variable.ttf", 400, "General Sans", "Regular"),
    ("GeneralSans-Variable.ttf", 500, "General Sans", "Medium"),
    ("GeneralSans-Variable.ttf", 600, "General Sans", "Semibold"),
]


def retune_vertical_metrics(font: TTFont, ratio: float) -> None:
    """Cale la hauteur de ligne naturelle de la police sur `ratio` × corps.

    CoreText lit `hhea` ; on garde `OS/2` cohérent pour les autres moteurs. Les
    `usWin*` ne sont pas touchés : certains rasteriseurs s'en servent comme
    boîte de découpe, et les rétrécir rognerait les accents.
    """
    hhea, os2 = font["hhea"], font["OS/2"]
    upem = font["head"].unitsPerEm
    target = round(ratio * upem)

    # Le creux entre deux lignes se prend sur l'interligne tant qu'il y en a,
    # pour ne pas déplacer la ligne de base dans sa boîte.
    slack = min(hhea.lineGap, hhea.ascender - hhea.descender + hhea.lineGap - target)
    hhea.lineGap -= max(slack, 0)

    # S'il manque encore de la hauteur, on rogne ascendante et descendante au
    # prorata : le texte reste optiquement centré dans sa ligne.
    current = hhea.ascender - hhea.descender + hhea.lineGap
    if current > target:
        scale = (target - hhea.lineGap) / (hhea.ascender - hhea.descender)
        hhea.ascender = round(hhea.ascender * scale)
        hhea.descender = round(hhea.descender * scale)

    os2.sTypoAscender, os2.sTypoDescender = hhea.ascender, hhea.descender
    os2.sTypoLineGap = hhea.lineGap
    os2.fsSelection |= 1 << 7  # USE_TYPO_METRICS


def build(source: str, weight: int, family: str, style: str) -> None:
    font = instancer.instantiateVariableFont(
        TTFont(SOURCES / source), {"wght": weight}, inplace=False, updateFontNames=False
    )

    postscript = f"{family.replace(' ', '')}-{style}"
    names = font["name"]
    full = f"{family} {style}"
    for name_id, value in ((1, family), (2, style), (3, f"{full};memobook"), (4, full), (6, postscript)):
        names.setName(value, name_id, 3, 1, 0x409)  # Windows / Unicode BMP
        names.setName(value, name_id, 1, 0, 0)  # Macintosh / Roman
    for name_id in (16, 17, 21, 22):  # noms typographiques et WWS de la variable
        names.removeNames(nameID=name_id)

    font["OS/2"].usWeightClass = weight
    retune_vertical_metrics(font, LINE_HEIGHT[family])

    DESTINATION.mkdir(parents=True, exist_ok=True)
    font.save(DESTINATION / f"{postscript}.ttf")
    hhea = font["hhea"]
    height = (hhea.ascender - hhea.descender + hhea.lineGap) / font["head"].unitsPerEm
    print(f"{postscript}.ttf — graisse {weight}, interligne ×{height:.4f}")


if __name__ == "__main__":
    for instance in INSTANCES:
        build(*instance)
