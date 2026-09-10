# Pictogrammes Lucide

Ce dossier ne contient **pas** des icônes de marque : ce sont des remplaçants,
empruntés à une bibliothèque libre là où le jeu de
[`brand-icons`](../brand-icons/README.md) n'a rien à proposer.

Deux trous aujourd'hui, et rien d'autre :

| Emploi | Pictogrammes |
|---|---|
| Les catégories de la **galerie de la communauté** | `globe`, `footprints`, `car-front`, `building-2`, `palmtree`, `mountain-snow`, `users`, `bike`, `sailboat` (+ `backpack`, `heart`, `tent-tree`, `utensils` en réserve) |
| Le filtre **Transports** d'un voyage | `train-front` |
| Le repli d'une clé inconnue | `compass` |

> **Exception assumée à la règle R10** de `docs/ui-development.md` (« les assets
> viennent de Figma, jamais d'ailleurs »). Elle est nommée dans la fiche écran
> *Exemples de carnets*, et tombe le jour où Clara dessine la série.

## Source

[**Lucide**](https://lucide.dev) v1.43.0, sous licence **ISC** — libre d'usage
commercial, attribution conservée dans l'en-tête de chaque fichier.

Grille de 24 × 24, tracé de 2, bouts et jointures arrondis : la même grille que
le jeu de marque. Le style diffère (Lucide est *tracé*, la marque est *pleine*),
et c'est visible ; c'est le prix de ne pas les dessiner nous-mêmes.

## Deux retouches à l'import

1. `stroke="currentColor"` → `stroke="#2D231A"` (*Brand Colors/Black*). Xcode ne
   connaît pas `currentColor` : sans ça, l'icône est invisible. C'est
   `renderingMode(.template)` qui la reteinte à l'affichage — blanc sur une
   pastille verte, encre sur une pastille blanche.
2. L'attribut `class` est retiré, il ne sert à rien hors du web.

## Nommage dans l'app

| Source | Asset | Clé |
|---|---|---|
| `globe.svg` | `IconLucideGlobe` | `globe` |
| `mountain-snow.svg` | `IconLucideMountainSnow` | `mountain-snow` |

La **clé est le nom du fichier**, pas celui de ce à quoi il sert : deux
catégories peuvent partager un pictogramme, et renommer une catégorie ne doit
pas demander une migration. L'app la résout dans
`MemoBookDesign/LucideIcon.swift`, qui retombe sur `compass` pour une clé
inconnue — une catégorie ajoutée en base s'affiche donc, même avant la prochaine
version de l'app.

## Ajouter un pictogramme

```bash
curl -sSO https://cdn.jsdelivr.net/npm/lucide-static@1.43.0/icons/<nom>.svg
python3 ios/Tools/import-lucide-icons.py
```

Le script applique les deux retouches ci-dessus et recopie chaque SVG dans un
`.imageset` du catalogue, en *Single Scale / Preserve Vector Data*. Puis ajouter
la clé à `LucideIcon.known` — c'est la seule liste que Swift connaisse, et elle
est vérifiée par un test.
