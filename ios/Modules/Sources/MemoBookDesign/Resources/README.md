# Les visuels de l'app

Ce catalogue reçoit les icônes, logos et illustrations **exportés du fichier
Figma** — et rien d'autre (règle R10 de `docs/ui-development.md`). On ne
substitue pas un SF Symbol à une icône dessinée.

La liste de ce qui est attendu, avec pour chacun son nœud d'origine, est dans
`FigmaAsset.swift` et dans [`docs/figma-assets.md`](../../../../../docs/figma-assets.md).

Tant qu'un fichier manque, `FigmaImage` affiche une réserve neutre à la bonne
taille : la mise en page reste juste et le trou se voit. Un placeholder qui
ressemblerait à l'icône finale, personne ne le remplacerait jamais.

## Ajouter un export

1. `download_assets` sur le nœud, en **SVG**.
2. Nouvel *Image Set* dans `Media.xcassets`, nommé exactement comme le
   `rawValue` du cas de `FigmaAsset` (`lock`, `company-logo`…).
3. **Single Scale** + **Preserve Vector Data** : le tracé reste net à toutes les
   tailles et suit Dynamic Type.
4. Rien d'autre à toucher — `FigmaImage` prend le relais tout seul.
