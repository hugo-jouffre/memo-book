#!/usr/bin/env python3
"""Écrit le manifeste des aperçus de personnalisation, d'après le dossier.

Source : ``assets/illustrations/aperçu personnalisation``
Cible  : ``ios/Modules/Sources/MemoBookCore/BookCustomisationPreviewManifest.swift``

    python3 ios/Tools/make-customisation-preview-manifest.py

L'app ne cherche pas un fichier pour voir s'il existe : elle consulte cette
liste. Relancer le script après tout ajout, retrait ou renommage dans le
dossier — un aperçu absent du manifeste ne s'affichera jamais, il tombera sur
le repli. ``BookCustomisationPreviewTests`` compare le manifeste au dossier et
le dit quand on a oublié.

Le script **refuse** plutôt que de deviner :

- un nom en Unicode décomposé (NFD) : il s'écrit comme un nom NFC, mais une URL
  bâtie sur l'un ne trouve pas l'autre — c'est ce qui faisait répondre 404 à
  l'ancien repli « aperçu non existant » (``docs/apercu-personnalisation.md``) ;
- un nom qui ne suit pas la forme des cinq segments : la règle ne saurait
  jamais le composer, il n'existerait que pour encombrer le dossier ;
- l'absence de l'image de repli.

Les segments ``Typos=`` ne sont pas vérifiés ici : leur table vit dans le code
Swift, et c'est un test qui s'assure que chaque fichier y correspond.
"""

import re
import sys
import unicodedata
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
SOURCE = REPO / "assets" / "illustrations" / "aperçu personnalisation"
TARGET = REPO / "ios/Modules/Sources/MemoBookCore/BookCustomisationPreviewManifest.swift"

# Le même nom que `BookCustomisationPreview.fallbackFileName`. Sans cédille,
# voir plus haut.
FALLBACK = "apercu non existant.png"

# Ni guillemet ni barre oblique inverse dans `Typos=` : le nom est recopié tel
# quel dans un littéral Swift.
SHAPE = re.compile(
    r"Pointillés=(on|off), Ratio image=(0|25|50|75|100)%, Fun fact=(on|off), "
    r'Stickers=[0-4], Typos=[^,"\\\n]+\.png'
)


def main() -> int:
    if not SOURCE.is_dir():
        print(f"Source introuvable : {SOURCE}", file=sys.stderr)
        return 1

    names = sorted(path.name for path in SOURCE.iterdir() if not path.name.startswith("."))
    problems = []

    if FALLBACK not in names:
        problems.append(f"l'image de repli « {FALLBACK} » manque")

    previews = [name for name in names if name != FALLBACK]
    for name in previews:
        if not unicodedata.is_normalized("NFC", name):
            problems.append(f"« {name} » est en Unicode décomposé (NFD) : le renommer en NFC")
        elif not SHAPE.fullmatch(name):
            problems.append(f"« {name} » ne suit pas la forme des cinq segments")

    if problems:
        print("Manifeste non écrit :", file=sys.stderr)
        for problem in problems:
            print(f"  - {problem}", file=sys.stderr)
        return 1

    lines = [
        "// Généré par `ios/Tools/make-customisation-preview-manifest.py` depuis",
        "// `assets/illustrations/aperçu personnalisation/`. Ne pas éditer à la main :",
        "// relancer le script quand le dossier change.",
        "",
        "extension BookCustomisationPreview {",
        f"    /// Les {len(previews)} aperçus du dossier, image de repli exclue — chacun",
        "    /// écrit comme sur le disque.",
        "    public static let availableFileNames: Set<String> = [",
        *(f'        "{name}",' for name in previews),
        "    ]",
        "}",
        "",
    ]
    TARGET.write_text("\n".join(lines), encoding="utf-8")
    print(f"{len(previews)} aperçus → {TARGET.relative_to(REPO)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
