#!/usr/bin/env python3
"""Importe les pictogrammes **Lucide** dans le catalogue d'assets de l'app.

Cible : ``ios/Modules/Sources/MemoBookDesign/Resources/MemoBookAssets.xcassets``

⚠️ **Ce sont des bouche-trous, pas des icônes de marque.** Le jeu de marque
(``assets/icons/brand-icons``, importé par ``import-brand-icons.py``) ne couvre
pas tout : ni les catégories de la galerie, ni la moitié des commandes de
l'écran de chat. Elles sont donc empruntées à Lucide (licence ISC) en attendant
les exports Figma — chaque icône remplacée ici doit disparaître de son dossier
le jour où Clara la dessine. C'est la seule exception à la règle « les assets
viennent de Figma », nommée dans ``docs/ui-development.md`` §13.

**Deux dossiers, deux façons de nommer**, et la différence est voulue :

``assets/icons/lucide-icons`` — les catégories de la galerie et les filtres.
    Le nom de l'asset suit celui de Lucide, parce que c'est la **base** qui
    nomme la catégorie : ajouter « tente » côté serveur ne doit pas demander de
    livrer une version. ``LucideIcon.swift`` résout la clé.

        globe.svg          → IconLucideGlobe.imageset
        mountain-snow.svg  → IconLucideMountainSnow.imageset

``assets/icons/lucide`` — les commandes du chat et de l'enregistrement.
    Le nom de l'asset suit le **rôle** dans l'app, pas celui de Lucide : le jour
    où l'icône de marque arrive, c'est le rôle qui reste, et aucune vue ne
    bouge. Ces icônes sont posées à la main dans le code, une par une.

        volume-2.svg  →  IconLucideSpeaker.imageset

Deux retouches sont appliquées aux deux dossiers, sans quoi l'icône ne tombe
pas juste dans l'app :

1. ``currentColor`` est remplacé par l'encre de la marque. Les vues rendent ces
   images en ``.template``, donc seule la forme compte — mais un ``currentColor``
   que Xcode ne résout pas donnerait un SVG invisible dans l'aperçu du
   catalogue.
2. L'attribut ``class`` est retiré : il ne sert à rien hors du web.

Les commandes en subissent une troisième : les attributs ``width``/``height``
sont retirés de la **balise racine**, parce qu'elles sont posées à des tailles
très différentes d'une barre à l'autre et que c'est la ``viewBox`` qui doit
porter le cadrage. Les pictogrammes de catégorie, eux, gardent leur 24 × 24 :
ils sont tous dessinés à cette taille, et rien ne gagnerait à les rouvrir.

Idempotent : il réécrit ce qui existe et ne touche à rien d'autre.

    python3 ios/Tools/import-lucide-icons.py
"""

import json
import re
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
CATALOG = REPO / "ios/Modules/Sources/MemoBookDesign/Resources/MemoBookAssets.xcassets"

#: Les pictogrammes nommés par la base — voir le docstring.
BY_NAME = REPO / "assets" / "icons" / "lucide-icons"

#: Les commandes nommées par leur rôle — voir le docstring.
BY_ROLE = REPO / "assets" / "icons" / "lucide"

#: *Brand Colors/Black*, la même encre que le jeu de marque —
#: ``MemoBookColor.ink``. Voir la retouche 1.
INK = "#2D231A"

#: Fichier Lucide → rôle dans l'app, pour le dossier ``lucide``.
ROLES = {
    "volume-2": "Speaker",
    "copy": "Copy",
    "camera": "Camera",
    "keyboard": "Keyboard",
    "calendar": "Calendar",
    "sparkles": "Sparkles",
    "play": "Play",
    "pause": "Pause",
    "square": "Stop",
    "arrow-down": "ArrowDown",
    "arrow-up": "ArrowUp",
    "send": "Send",
    "mic-off": "MicOff",
    "circle-pause": "PauseCircle",
    "check": "Check",
    "x": "Close",
}

#: Les icônes que la maquette montre **pleines** et non au trait : les commandes
#: d'un lecteur audio. Lucide les dessine en contour ; un triangle de lecture
#: creux ne se lit pas comme « joue ça » — c'est un acquis de toutes les apps de
#: lecture, on ne le réinvente pas.
FILLED = {"play", "pause", "square", "send"}


def asset_name(stem: str) -> str:
    """« mountain-snow » → IconLucideMountainSnow."""
    words = [w for w in re.split(r"[\s\-_]+", stem) if w]
    return "IconLucide" + "".join(w[0].upper() + w[1:] for w in words)


def normalise(svg: str) -> str:
    """Le SVG de Lucide, rendu utilisable par Xcode."""
    svg = svg.replace("currentColor", INK)
    return re.sub(r'\s*class="[^"]*"', "", svg)


def clean(svg: str, *, filled: bool = False) -> str:
    """La même chose, plus le décadrage des commandes."""
    svg = normalise(svg)
    # `width`/`height` ne sont retirés que de la balise racine : un `<rect>` en a
    # aussi, et les lui enlever le réduit à néant — la pause devenait un fichier
    # sans dessin.
    svg = re.sub(
        r"<svg\b[^>]*>",
        lambda m: re.sub(r'\s+(width|height)="[^"]*"', "", m.group(0)),
        svg,
        count=1,
    )
    if filled:
        svg = svg.replace('fill="none"', f'fill="{INK}"', 1)
    # Lucide livre le SVG sur plusieurs lignes avec un attribut par ligne ; Xcode
    # s'en moque, mais un fichier d'une ligne se relit mieux dans un diff.
    return re.sub(r"\s*\n\s*", " ", svg).strip() + "\n"


def write(name: str, svg: str) -> None:
    folder = CATALOG / f"{name}.imageset"
    folder.mkdir(exist_ok=True)

    (folder / f"{name}.svg").write_text(svg)
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


def main() -> int:
    if not CATALOG.is_dir():
        print(f"Catalogue introuvable : {CATALOG}", file=sys.stderr)
        return 1
    for source in (BY_NAME, BY_ROLE):
        if not source.is_dir():
            print(f"Source introuvable : {source}", file=sys.stderr)
            return 1

    svgs = sorted(BY_NAME.glob("*.svg"))
    if not svgs:
        print(f"Aucun SVG dans {BY_NAME}", file=sys.stderr)
        return 1

    for svg in svgs:
        write(asset_name(svg.stem), normalise(svg.read_text()))

    missing = sorted(ROLES.keys() - {p.stem for p in BY_ROLE.glob("*.svg")})
    if missing:
        print(f"SVG manquants dans {BY_ROLE} : {', '.join(missing)}", file=sys.stderr)
        return 1

    for stem, role in sorted(ROLES.items()):
        write(
            f"IconLucide{role}",
            clean((BY_ROLE / f"{stem}.svg").read_text(), filled=stem in FILLED),
        )

    keys = ", ".join(sorted(s.stem for s in svgs))
    print(f"{len(svgs)} pictogrammes importés : {keys}")
    print(f"{len(ROLES)} commandes importées (bouche-trous — voir le module)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
