# Les visuels à exporter de Figma

> Règle R10 de [`ui-development.md`](ui-development.md) : les icônes et
> illustrations viennent du nœud Figma, jamais d'ailleurs. On ne substitue pas
> un SF Symbol à une icône dessinée.

Le lot 1 est implémenté ; **ses visuels ne le sont pas encore**. Ils n'ont pas
pu être exportés lors de la session de développement (limite d'appels du plan
Figma atteinte, et le réseau de la session ne joint pas `figma.com` pour aller
chercher les fichiers directement).

En attendant, `FigmaImage` affiche une **réserve neutre à la bonne taille** :
la mise en page est juste, et le trou se voit. C'est délibéré — un placeholder
qui ressemblerait à l'icône finale, personne ne le remplacerait jamais.

Fichier Figma :
[MemoBook — Product](https://www.figma.com/design/kytPYFno7PvDciIKTxCujK/MemoBook---Product).

## La liste

| Identifiant (`FigmaAsset`) | Nœud | Taille maquette | Où il sert |
|---|---|---|---|
| `company-logo` | `2699:14313` | 149.35 × 106.68 | Splash |
| `background-route` | `2788:11553` | 707.16 × 542.49, posé à −90° | Splash, Welcome, Sign Up, Login |
| `benefit-voice` | `2743:17105` | 15.68 × 21.06 | Carte 1 du Welcome |
| `benefit-photo` | `2743:17113` | 26.26 × 20.86 | Carte 2 du Welcome |
| `benefit-book` | `2553:27484` | 23.76 × 18.92 | Carte 3 du Welcome |
| `card-arrow` | `2552:27458` | 24.4 × 24.4 | Flèche des cartes bénéfices — `keyboard_backspace` **retournée** (miroir vertical + 180°) |
| `button-arrow` | instance `Button`, `2552:27426` | 24 × 24 | `arrow_right_alt`, à **gauche** du libellé du CTA |
| `lock` | `2742:16770` | 30 × 38.8, dans une pastille de 66 | Les trois écrans de mot de passe |
| `pencil` | `2755:17745` | 44 × 44 | *Mot de passe oublié*, rend l'adresse modifiable |
| `social-apple` | `image 697`, `2712:14866` | 48 × 44.57 | Sign Up, Login |
| `social-google` | `image 698`, `2712:14868` | 41.13 × 44.4 | Sign Up, Login |
| `social-facebook` | `image 701`, `2712:14867` | 45.79 × 48.5 | Sign Up, Login |

> ⚠️ **Les trois logos sociaux sont à identifier au moment de l'export.** Figma
> les nomme `image 697`, `image 698` et `image 701` et les découpe dans un même
> visuel source : lequel est Apple, lequel est Google, lequel est Facebook se
> lit à l'œil sur le nœud, pas dans les métadonnées. L'affectation ci-dessus est
> une hypothèse à vérifier avant de committer les fichiers.
>
> Ce sont des **marques déposées** : elles s'exportent telles quelles, ne se
> redessinent pas et ne se recolorent pas.

## La procédure

1. `download_assets` sur le nœud, en **SVG**.
2. Nouvel *Image Set* dans
   `ios/Modules/Sources/MemoBookDesign/Resources/Media.xcassets`, nommé
   exactement comme l'identifiant de la colonne 1.
3. **Single Scale** + **Preserve Vector Data**.
4. Rien d'autre à toucher : `FigmaImage` prend le relais tout seul, et
   `FigmaAsset.isExported` passe à `true`.

## Les polices

**Sora** (titres, chiffres) et **General Sans** (le reste) ne sont pas encore
embarquées non plus. Tant qu'elles manquent, `Font.custom` retombe sur la
police système : les écrans restent lisibles et bien proportionnés.

Le jour où les fichiers entrent dans `ios/App/Fonts/`, les déclarer dans
`UIAppFonts` — le bloc est déjà écrit en commentaire dans
[`ios/project.yml`](../ios/project.yml). Aucun code à changer : les noms de
familles sont dans `MemoBookFontFamily`.
