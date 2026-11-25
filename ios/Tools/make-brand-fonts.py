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

L'app Android embarque **les mêmes fichiers** : chacun est recopié dans
`android/design/src/main/res/font`, sous le nom qu'Android exige (minuscules,
sans tiret). Les deux apps dessinent ainsi le même texte au même interligne.

Relancer ce script après toute mise à jour des sources variables.
"""

import shutil
from pathlib import Path

from fontTools.ttLib import TTFont
from fontTools.varLib import instancer

ROOT = Path(__file__).resolve().parents[2]
SOURCES = ROOT / "MemoBook Generator" / "public" / "fonts"

# La police manuscrite du carnet n'est pas variable : elle est livrée en woff2
# avec le template d'impression. CoreText ne sait pas lire le woff2, d'où la
# conversion — c'est le **même** dessin, pas une seconde police.
WOFF2_SOURCES = ROOT / "MemoBook Generator" / "templates" / "travel-journal" / "assets" / "fonts"

# Les polices **des couvertures**, celles de l'atelier d'impression
# (`couverture-styles.js`, § POLICES). Même raison d'être ici : l'app dessine
# les sept plats, et elle les dessinait en polices système — le même plat
# sortait donc en trois typographies selon qu'on le regardait à l'écran, dans
# le PDF du carnet ou sur le livre imprimé (T256, Hugo, 25/11/2026).
COVER_SOURCES = ROOT / "MemoBook Generator" / "public" / "fonts" / "couvertures"

DESTINATION = ROOT / "ios" / "Modules" / "Sources" / "MemoBookDesign" / "Resources" / "Fonts"
ANDROID_DESTINATION = ROOT / "android" / "design" / "src" / "main" / "res" / "font"

# Interlignes des styles Figma, en multiple de la taille du corps.
#   Sora        — `App/h1` : 32 pt de corps pour 35 pt d'interligne.
#   General Sans — `App/body semibold` et consorts : 1.3.
LINE_HEIGHT = {"Sora": 35 / 32, "General Sans": 1.30}

# (fichier source, graisse, famille, style)
INSTANCES = [
    ("Sora-Variable.ttf", 400, "Sora", "Regular"),
    ("Sora-Variable.ttf", 600, "Sora", "SemiBold"),
    ("GeneralSans-Variable.ttf", 400, "General Sans", "Regular"),
    ("GeneralSans-Variable.ttf", 500, "General Sans", "Medium"),
    ("GeneralSans-Variable.ttf", 600, "General Sans", "Semibold"),
]

# (fichier woff2 source, nom PostScript de sortie)
#
# Ces polices-là sont recopiées telles quelles : pas d'instanciation à faire, et
# **pas de recalage d'interligne** — une écriture à la main n'a pas de style
# Figma qui lui impose une hauteur de ligne, et lui en imposer une casserait
# justement ce qui la rend manuscrite.
STATIC_WOFF2 = [
    ("gloria-hallelujah-400-latin.woff2", "GloriaHallelujah"),
]

# ⚠️ **Le sous-ensemble `-latin` seulement**, pour toutes les polices de
# couverture. Il couvre le français en entier — accents, `œ`, l'apostrophe
# typographique —, et c'est ce que l'app écrit. Le `-latin-ext` qui
# l'accompagne n'ajoute que l'Europe centrale (`ł`, `ğ`) : un titre qui en
# contiendrait verrait **ces lettres-là seulement** tomber sur la police du
# système. Les réunir n'est pas possible pour les familles variables —
# `fontTools.merge` ne sait pas fusionner deux `VarStore` — et on ne garde pas
# deux chemins pour une même étagère. L'imprimé, lui, charge les deux par
# `unicode-range` : il n'a pas cette limite.
#
# (fichier woff2 source, nom PostScript de sortie) — déjà statiques, et leur
# nom PostScript est déjà celui qu'on veut : rien à renommer.
COVER_STATIC = [
    ("archivo-black-latin.woff2", "ArchivoBlack-Regular"),
    ("poppins-black-latin.woff2", "Poppins-Black"),
    ("lilita-one-latin.woff2", "LilitaOne"),
    ("caveat-brush-latin.woff2", "CaveatBrush-Regular"),
]

# Les polices de couverture livrées en **variable**, à figer comme Sora et
# General Sans. (dossier source, fichier woff2, graisse, famille, style)
#
# Playfair Display est livrée avec le gabarit du carnet et non avec les
# couvertures, et ses deux fichiers — `-400-` et `-900-` — portent **le même**
# axe 400–900 et le même nom PostScript : c'est deux fois la même variable. On
# n'en lit donc qu'une, et on en tire les deux graisses ; les convertir toutes
# les deux telles quelles donnerait deux polices du même nom, que CoreText ne
# saurait pas départager.
COVER_INSTANCES = [
    ("playfair", "playfair-display-400-latin.woff2", 900, "Playfair Display", "Black"),
    ("playfair", "playfair-display-400-latin.woff2", 400, "Playfair Display", "Regular"),
    ("couverture", "cormorant-garamond-latin.woff2", 400, "Cormorant Garamond", "Regular"),
    ("couverture", "cormorant-infant-latin.woff2", 500, "Cormorant Infant", "Medium"),
    ("couverture", "manrope-latin.woff2", 400, "Manrope", "Regular"),
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


def copy_for_android(postscript: str) -> None:
    """Recopie la police iOS telle quelle dans `res/font` : `Sora-SemiBold` → `sora_semibold.ttf`."""
    ANDROID_DESTINATION.mkdir(parents=True, exist_ok=True)
    name = postscript.lower().replace("-", "_")
    shutil.copyfile(DESTINATION / f"{postscript}.ttf", ANDROID_DESTINATION / f"{name}.ttf")


def rename(font: TTFont, family: str, style: str) -> str:
    """Donne à l'instance figée son nom à elle, et rend son nom PostScript.

    Une variable porte le nom de son instance par défaut — « Cormorant Garamond
    Light », « Manrope ExtraLight ». Figée à une autre graisse, elle mentirait
    sous ce nom-là ; et deux instances de la même variable porteraient le même,
    que CoreText ne saurait pas départager.
    """
    postscript = f"{family.replace(' ', '')}-{style}"
    names = font["name"]
    full = f"{family} {style}"
    for name_id, value in ((1, family), (2, style), (3, f"{full};memobook"), (4, full), (6, postscript)):
        names.setName(value, name_id, 3, 1, 0x409)  # Windows / Unicode BMP
        names.setName(value, name_id, 1, 0, 0)  # Macintosh / Roman
    for name_id in (16, 17, 21, 22):  # noms typographiques et WWS de la variable
        names.removeNames(nameID=name_id)
    return postscript


def save(font: TTFont, postscript: str, note: str) -> None:
    font.flavor = None  # woff2 → sfnt brut, pour les sources compressées
    DESTINATION.mkdir(parents=True, exist_ok=True)
    font.save(DESTINATION / f"{postscript}.ttf")
    copy_for_android(postscript)
    print(f"{postscript}.ttf — {note}")


def build(source: str, weight: int, family: str, style: str) -> None:
    font = instancer.instantiateVariableFont(
        TTFont(SOURCES / source), {"wght": weight}, inplace=False, updateFontNames=False
    )
    postscript = rename(font, family, style)
    font["OS/2"].usWeightClass = weight
    retune_vertical_metrics(font, LINE_HEIGHT[family])

    hhea = font["hhea"]
    height = (hhea.ascender - hhea.descender + hhea.lineGap) / font["head"].unitsPerEm
    save(font, postscript, f"graisse {weight}, interligne ×{height:.4f}")


def convert(source: str, postscript: str, folder: Path = WOFF2_SOURCES) -> None:
    """Dé-compresse un woff2 en TTF, sans rien changer d'autre."""
    font = TTFont(folder / source)
    save(font, postscript, f"{font['name'].getDebugName(1)}, converti depuis woff2")


def build_cover(folder: str, source: str, weight: int, family: str, style: str) -> None:
    """Fige une graisse d'une police de couverture, **sans toucher l'interligne**.

    Pas de recalage ici : ces polices-là ne servent pas à un écran de l'app mais
    au dessin d'un objet imprimé, dont la maquette est celle de l'atelier. Leur
    interligne naturel est celui que l'imprimé emploie — le changer ferait
    diverger l'écran du livre, ce que T256 cherche justement à finir.
    """
    sources = WOFF2_SOURCES if folder == "playfair" else COVER_SOURCES
    font = instancer.instantiateVariableFont(
        TTFont(sources / source), {"wght": weight}, inplace=False, updateFontNames=False
    )
    postscript = rename(font, family, style)
    font["OS/2"].usWeightClass = weight
    save(font, postscript, f"couverture, graisse {weight}")


if __name__ == "__main__":
    for instance in INSTANCES:
        build(*instance)
    for conversion in STATIC_WOFF2:
        convert(*conversion)
    for conversion in COVER_STATIC:
        convert(*conversion, folder=COVER_SOURCES)
    for instance in COVER_INSTANCES:
        build_cover(*instance)
