#!/usr/bin/env python3
"""Importe les icônes **Lucide** de dépannage dans le catalogue d'assets de l'app.

Source : ``assets/icons/lucide`` (voir son README pour la liste et le pourquoi).
Cible  : ``ios/Modules/Sources/MemoBookDesign/Resources/MemoBookAssets.xcassets``

⚠️ **Ce sont des bouche-trous, pas des icônes de marque.** Le jeu de marque
(``assets/icons/brand-icons``, importé par ``import-brand-icons.py``) ne couvre
pas encore tout l'écran de chat : le haut-parleur, le presse-papiers, l'appareil
photo, le clavier, le calendrier, l'étincelle, la lecture et la pause manquent.
Elles sont donc empruntées à Lucide (licence ISC) en attendant les exports Figma
— chaque icône remplacée ici doit disparaître de ce dossier le jour où Clara la
dessine.

Le nom d'asset est préfixé ``IconLucide`` **exprès** : à la lecture d'une vue, on
voit immédiatement ce qui est de la marque et ce qui est provisoire.

    volume-2.svg  →  IconLucideSpeaker.imageset

Deux retouches sont appliquées au passage, sans quoi l'icône ne tombe pas juste
dans l'app :

1. ``currentColor`` est remplacé par l'encre de la marque. Les vues rendent ces
   images en ``.template``, donc seule la forme compte — mais un ``currentColor``
   que Xcode ne résout pas donnerait un SVG invisible dans l'aperçu du catalogue.
2. Les attributs ``width``/``height`` sont retirés : c'est la ``viewBox`` qui
   porte le cadrage, et la vue qui décide de la taille.

    python3 ios/Tools/import-lucide-icons.py
"""

import json
import re
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
SOURCE = REPO / "assets" / "icons" / "lucide"
CATALOG = REPO / "ios/Modules/Sources/MemoBookDesign/Resources/MemoBookAssets.xcassets"

#: L'encre de la marque — ``MemoBookColor.ink``. Voir la retouche 1 ci-dessus.
INK = "#2D231A"

#: Fichier Lucide → rôle dans l'app. Le rôle, et non le nom de Lucide : le jour
#: où l'icône de marque arrive, c'est le rôle qui reste.
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


def clean(svg: str, *, filled: bool) -> str:
    """Le SVG de Lucide, rendu utilisable par Xcode."""
    svg = svg.replace("currentColor", INK)
    svg = re.sub(r'\s+class="[^"]*"', "", svg)
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


def main() -> int:
    if not SOURCE.is_dir():
        print(f"Source introuvable : {SOURCE}", file=sys.stderr)
        return 1
    if not CATALOG.is_dir():
        print(f"Catalogue introuvable : {CATALOG}", file=sys.stderr)
        return 1

    missing = sorted(ROLES.keys() - {p.stem for p in SOURCE.glob("*.svg")})
    if missing:
        print(f"SVG manquants dans {SOURCE} : {', '.join(missing)}", file=sys.stderr)
        return 1

    for stem, role in sorted(ROLES.items()):
        name = f"IconLucide{role}"
        folder = CATALOG / f"{name}.imageset"
        folder.mkdir(exist_ok=True)

        (folder / f"{name}.svg").write_text(
            clean((SOURCE / f"{stem}.svg").read_text(), filled=stem in FILLED)
        )
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

    print(f"{len(ROLES)} icônes Lucide importées (bouche-trous — voir le module)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
