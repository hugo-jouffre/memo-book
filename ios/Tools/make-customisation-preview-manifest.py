#!/usr/bin/env python3
"""Écrit le manifeste des aperçus de personnalisation, d'après le dossier.

Sources : ``assets/illustrations/aperçu personnalisation`` (les exports Figma)
          ``assets/illustrations/apercus-personnalisation.manifest.json``
          (les images publiées, réécrit par ``npm run previews:publish``)
Cible   : ``ios/Modules/Sources/MemoBookCore/BookCustomisationPreviewManifest.swift``

    python3 ios/Tools/make-customisation-preview-manifest.py

L'app ne cherche pas un fichier pour voir s'il existe : elle consulte cette
liste. Et elle n'affiche pas les exports, trop lourds, mais l'image publiée de
chacun : le manifeste joint les deux, nom Figma → fichier en ligne. **Il est
embarqué** (Hugo, 02/10/2026) : un seul appel réseau, celui de l'image.

Après tout ajout, retrait ou renommage dans le dossier : ``npm run
previews:publish`` dans ``backend/``, puis ce script, puis une version de
l'app. Un aperçu absent du manifeste ne s'affichera jamais, il tombera sur le
repli. ``BookCustomisationPreviewTests`` compare le manifeste au dossier et le
dit quand on a oublié.

Le script **refuse** plutôt que de deviner :

- un nom en Unicode décomposé (NFD) : il s'écrit comme un nom NFC, mais une URL
  bâtie sur l'un ne trouve pas l'autre — c'est ce qui faisait répondre 404 à
  l'ancien repli « aperçu non existant » (``docs/apercu-personnalisation.md``) ;
- un nom qui ne suit pas la forme des cinq segments : la règle ne saurait
  jamais le composer, il n'existerait que pour encombrer le dossier ;
- l'absence de l'image de repli ;
- un dossier et un manifeste publié qui ne disent pas les mêmes noms : la
  chaîne de publication n'a pas été relancée.

Les segments ``Typos=`` ne sont pas vérifiés ici : leur table vit dans le code
Swift, et c'est un test qui s'assure que chaque fichier y correspond.
"""

import json
import re
import sys
import unicodedata
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
SOURCE = REPO / "assets" / "illustrations" / "aperçu personnalisation"
PUBLISHED = REPO / "assets" / "illustrations" / "apercus-personnalisation.manifest.json"
TARGET = REPO / "ios/Modules/Sources/MemoBookCore/BookCustomisationPreviewManifest.swift"

# Le même nom que `BookCustomisationPreview.fallbackFileName`. Sans cédille,
# voir plus haut.
FALLBACK = "apercu non existant.png"

# Ni guillemet ni barre oblique inverse dans `Typos=` : le nom est recopié tel
# quel dans un littéral Swift.
# Une image publiée : l'empreinte de sa source et de la recette.
PUBLISHED_FILE = re.compile(r"[0-9a-f]{8,64}\.webp")

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

    published, fallback_file = read_published(problems)
    if published is not None:
        for name in sorted(set(previews) - set(published)):
            problems.append(f"« {name} » n'est pas publié : relancer `npm run previews:publish`")
        for name in sorted(set(published) - set(previews)):
            problems.append(f"« {name} » est publié mais n'est plus dans le dossier")

    if problems:
        print("Manifeste non écrit :", file=sys.stderr)
        for problem in problems:
            print(f"  - {problem}", file=sys.stderr)
        return 1

    lines = [
        "// Généré par `ios/Tools/make-customisation-preview-manifest.py` depuis",
        "// `assets/illustrations/aperçu personnalisation/` et le manifeste publié",
        "// `assets/illustrations/apercus-personnalisation.manifest.json`. Ne pas éditer",
        "// à la main : relancer le script quand le dossier change.",
        "",
        "extension BookCustomisationPreview {",
        f"    /// Les {len(previews)} aperçus du dossier, image de repli exclue — chacun",
        "    /// écrit comme sur le disque.",
        "    public static let availableFileNames = Set(publishedFiles.keys)",
        "",
        "    /// L'image publiée de chaque aperçu, à résoudre contre",
        "    /// ``publicBaseURL``. Ce sont des empreintes : une image refaite change",
        "    /// de nom, l'ancienne reste en ligne.",
        "    static let publishedFiles: [String: String] = [",
        *(f'        "{name}": "{published[name]}",' for name in previews),
        "    ]",
        "",
        "    /// L'image publiée du repli.",
        f'    static let publishedFallback = "{fallback_file}"',
        "}",
        "",
    ]
    TARGET.write_text("\n".join(lines), encoding="utf-8")
    print(f"{len(previews)} aperçus → {TARGET.relative_to(REPO)}")
    return 0


def read_published(problems):
    """Le manifeste publié : nom Figma → image, et l'image du repli."""
    try:
        manifest = json.loads(PUBLISHED.read_text(encoding="utf-8"))
    except (OSError, ValueError) as error:
        problems.append(f"manifeste publié illisible ({PUBLISHED.name}) : {error}")
        return None, None

    if manifest.get("version") != 1:
        problems.append(f"manifeste publié en version {manifest.get('version')!r}, ce script lit la 1")
        return None, None

    fallback = manifest.get("fallback", {})
    if fallback.get("source") != FALLBACK:
        problems.append(f"le repli publié est « {fallback.get('source')} », pas « {FALLBACK} »")
    files = {}
    for entry in manifest.get("previews", []):
        source = entry.get("source")
        if source in files:
            problems.append(f"« {source} » est publié deux fois")
        files[source] = entry.get("file")
    for source, file in [*files.items(), (FALLBACK, fallback.get("file"))]:
        if not isinstance(file, str) or not PUBLISHED_FILE.fullmatch(file):
            problems.append(f"« {source} » est publié sous un nom inattendu : {file!r}")

    return files, fallback.get("file")


if __name__ == "__main__":
    sys.exit(main())
