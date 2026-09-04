# Design — Tokens et variables MemoBook

> Miroir des **variables du fichier Figma** [MemoBook — Product](https://www.figma.com/design/kytPYFno7PvDciIKTxCujK/MemoBook---Product).
> Figma est la source de vérité : ce fichier la recopie, il ne l'interprète pas. À tenir à
> jour à chaque évolution des variables.
>
> Relevé le 20/08/2026 sur la page *Design System* et sur les écrans du lot 1.
> Pour la **méthode** d'implémentation (unités, fidélité, fiches écran), voir
> [`docs/ui-development.md`](../docs/ui-development.md).

## Scheme (usage sémantique dans l'app)

| Rôle | Variable Figma | Hex |
|---|---|---|
| Text | `Scheme/Text` | #2D231A |
| Accent | `Scheme/Accent` | #E2F32B *(Lime)* |
| Foreground | `Scheme/Foreground` | #FFFCF8 *(White)* |
| Background Light | `Scheme/Background Light` | #FCF2E9 *(Beige)* |
| Background Dark | `Scheme/Background Dark` | #2D231A *(Black)* |
| Borders | `Scheme/Borders` | #2B231B, 10 % d'opacité |

## Brand Colors

| Nom | Hex | Rôle observé sur les écrans |
|---|---|---|
| Green | #28654B | CTA primaire, bordure de la tagline |
| Lime | #E2F32B | Accent du scheme — pas encore employé sur le lot 1 |
| Blue | #AFD2F0 | Bordure des cartes, pastilles numérotées, fonds d'icônes (à 30 %) |
| Beige | #FCF2E9 | Fond d'écran |
| Beige Darker | #CFBBAA | — |
| Black | #2D231A | Texte principal |
| White | #FFFCF8 | Surfaces (cartes, champs) — un blanc chaud, jamais #FFFFFF |
| Grey | #C8C8C8 | Bordures neutres, champs au repos |
| **Grey Typo** | **#2B231B80** | **Texte secondaire de l'accueil** — le noir de la marque à 50 %, pas un gris neutre |
| **Green Lighter** | **#3D9A6F** | **Signaux discrets** — le point « en ce moment » de l'accueil |

> **Grey Typo et Green Lighter** ont été relevés le 04/09/2026 par
> `get_variable_defs` sur le nœud de l'accueil (`3116:30733`). Ils ne
> figuraient pas dans le relevé du 20/08 : ce miroir avait un train de retard.
>
> **Grey Typo n'est pas `Grays/Gray`.** Le gris système #8E8E93 est neutre et
> refroidit le crème ; Grey Typo est tiré du noir chaud de la marque et s'y
> pose. Les deux coexistent dans le code (`inkSecondary` et `inkMuted`) parce
> que les écrans du lot 1 emploient bien le gris système : à trancher avec
> Clara si l'un doit remplacer l'autre partout.

> **Carrot, Carrot Darker, Forest Green et Kiwi n'existent plus.** Blue et Lime les
> remplacent. Les fichiers qui les citent encore sont listés plus bas.

## Grays

| Nom | Hex | Usage |
|---|---|---|
| `Grays/Gray` | #8E8E93 | Texte secondaire, placeholders (gris système iOS) |

## Semantic

| Rôle | Hex | Variante douce |
|---|---|---|
| Info | #435AD8 | #D9DEF7 |
| Success | #27AE60 | #BEE7CF |
| Warning | #FFBC39 | #FFF2D7 |
| Danger | #EB5757 | #FBDDDD |

Les variantes *soft* servent de fond de bandeau ou de badge ; la couleur pleine porte le
texte et l'icône.

## Tailles et traits

| Variable | Valeur |
|---|---|
| `Size/small` | 8 |
| `Size/medium` | 16 |
| `Size/large` | 24 |
| `Size/xlarge` | 32 |
| `Stroke/Border Width` | 1 |

| `Text Sizes` | Valeur |
|---|---|
| Text Tiny | 12 |
| Text Small | 14 | 
| Text Regular | 16 |
| Text Medium | 18 |
| Text Large | 20 |
| Heading 6 | 20 |
| Heading 5 | 24 |
| Heading 4 | 32 |
| Heading 3 | 40 |
| Heading 2 | 48 |
| Heading 1 | 56 |

`Text Regular` = 16 est la **racine typographique** : c'est elle qui définit 1 rem dans
l'app (voir `docs/ui-development.md` §2).

## Typographies

Deux familles, relevées sur les écrans du lot 1 :

| Famille | Graisses employées | Emploi |
|---|---|---|
| **Sora** | Bold, SemiBold | Titres d'écran, chiffres des pastilles |
| **General Sans** | Semibold, Medium, Regular | Titres de blocs, corps de texte, libellés de boutons, taglines |

Styles observés :

| Style | Police | Taille | Interligne | Approche |
|---|---|---|---|---|
| Titre d'écran | Sora Bold | 32 | 35 | −0.408 |
| Titre de bloc | General Sans Semibold | 16 | 1.3 | +0.16 |
| Corps | General Sans Regular | 16 | 1.3 | +0.16 |
| Description | General Sans Regular | 12 | 1.3 | +0.12 |
| Libellé de bouton | General Sans Medium | 16 | 1.5 | 0 |
| Tagline | General Sans Medium | 14 | 22 | −0.408 |
| Chiffre de pastille | Sora SemiBold | 16 | 1.3 | +0.16 |

> ⚠️ Les variables `Heading/*` et `Text/*` du fichier Figma annoncent encore **Roboto** :
> ce sont les valeurs par défaut du template de départ, pas la typographie MemoBook. Les
> écrans, eux, utilisent bien Sora et General Sans. À corriger dans Figma.
>
> Le serif des **titres de carnet** (pages du livre, pas le chrome de l'app) reste une
> décision éditoriale à part, non couverte par ces variables.

## Règles d'usage

- Le texte principal utilise toujours **Black** (#2D231A), jamais un noir pur (#000000)
- Les surfaces utilisent **White** (#FFFCF8), jamais un blanc pur (#FFFFFF)
- **Green** (#28654B) porte l'action principale : boutons primaires et CTA
- **Lime** (#E2F32B) est l'accent du scheme. Très saturé : il sert à mettre en valeur
  ponctuellement (surlignage, sélection, badge), jamais à porter du texte sombre sur
  grande surface, et jamais comme fond de CTA sans contraste vérifié
- **Blue** (#AFD2F0) est l'accent illustratif de l'onboarding : bordures de cartes,
  pastilles numérotées, fonds d'icônes à 30 % d'opacité
- **Beige** (#FCF2E9) est le fond des écrans ; les blocs de contenu se détachent en White
- Les couleurs sémantiques ne servent qu'aux retours système (messages, statuts), jamais
  en décoration
- Les fonds de carnet suivent le style choisi (`carnet-styles/`), qui peut réutiliser tout
  ou partie de cette palette

## Modes de variables — piège à connaître

Les collections Figma portent plusieurs modes. La page *Design System* affiche encore le
mode par défaut du template acheté : `Scheme/Text` y vaut #212121, `Radius/Small` et
`Radius/Medium` valent 0, et la typographie est Roboto. **Les écrans de l'app résolvent
un autre mode** — ce sont ces valeurs-là qui sont recopiées ci-dessus, et elles seules
qui font foi.

À nettoyer dans Figma quand l'occasion se présente : la collection `Color Scheme 1/*`,
les `Color/Neutral*`, les `Radius/*` à 0 et les styles `Heading/*` / `Text/*` en Roboto —
tous hérités du template et jamais employés par l'app.

## Fichiers encore sur l'ancienne palette

La suppression de Carrot, Forest Green et Kiwi laisse ces références à traiter. Aucune
n'a été modifiée d'office : le remplacement est un choix de design, pas une substitution
mécanique.

| Fichier | Référence | Piste |
|---|---|---|
| `agents/carnet-styles/vintage-voyage.md` | Cadre et accents Carrot #F86015 | Quelle couleur d'accent pour ce style ? |
| `agents/carnet-styles/scrapbook-colore.md` | Accent dominant Carrot (3 occurrences) | Idem |
| `backend/src/services/mapSvg.ts` | Tracé Forest Green #19532B, pin Carrot #F86015 | Green #28654B pour le tracé ; pin à trancher |
| `ios/.../MemoBookDesign/Tokens.swift` | Commentaire « design.md dit Carrot » | La palette est désormais tranchée : les tokens peuvent être posés |
| `ios/README.md` | Avertissement « palette pas encore posée » | À lever une fois les tokens posés |

## Utilisé par

- **App iOS** : `MemoBookDesign/Tokens.swift` — cible de la migration ci-dessus
- **Agent Mise en page** : applique ces couleurs sur les pages du carnet, dans les limites
  du style choisi
- **Agent Sélection photo** : évite les retouches qui entreraient en conflit avec la
  palette de marque

## À faire évoluer

- Rayons : les variables `Radius/*` sont à 0 (héritage du template) alors que les écrans
  utilisent 20 (cartes), 16 (boutons) et 13 (fonds d'icônes). À poser en variables
- Ombres : une page *Shadows* existe dans Figma, aucune valeur n'est encore documentée ici
- Mode sombre : `Scheme/Background Dark` existe, mais aucun écran ne le décline encore
