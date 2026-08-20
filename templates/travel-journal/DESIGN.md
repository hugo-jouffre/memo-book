# Design du carnet — couleurs, papier, typographies

> Le design system du **carnet imprimé**. Il est **indépendant de celui de l'app** :
> [`agents/design.md`](../../agents/design.md) ne décrit que l'interface iOS et ne
> gouverne rien ici.
>
> Ce n'est pas une négligence, c'est le sujet : une app est une interface, un carnet est
> un **objet de papier**. L'un se lit au pouce sur un écran rétroéclairé, l'autre à la
> lumière du salon, imprimé en quadrichromie. Les deux n'ont ni les mêmes contraintes de
> contraste, ni les mêmes polices, ni la même unité de mesure.

Ce fichier vit à côté du template parce qu'il doit changer **dans le même commit que
lui** — même raison que [`LAYOUT_KB.md`](LAYOUT_KB.md).

## Où vit l'implémentation

| Sujet | Fichier |
|---|---|
| Toutes les variables ci-dessous | `style.css`, bloc `:root` |
| Chargement des polices (`@font-face` inlinés) | `fonts.css` |
| Couleurs de la carte illustrée | `backend/src/services/mapSvg.ts` |
| Catalogue des layouts et limites de longueur | [`LAYOUT_KB.md`](LAYOUT_KB.md) |
| Ambiances éditoriales | [`agents/carnet-styles/`](../../agents/carnet-styles/) |

## L'unité est le point, pas le rem

420 × 595 pt (A5), marge d'impression de **30 pt**. Le contenu ne sort jamais de cette
marge.

L'app mesure en rem parce qu'un texte doit pouvoir grossir à la demande de l'utilisateur.
**Un carnet imprimé n'a pas de Dynamic Type** : sa page a une taille physique définitive.
On y écrit donc des points, et `1 unité Figma = 1 pt` — toute valeur relevée dans la
maquette se reporte telle quelle, sans conversion.

## Couleurs

| Variable | Valeur | Rôle |
|---|---|---|
| `--mb-black` | `#2B231B` | Le texte. Un noir chaud, jamais `#000000` |
| `--mb-ink` | `#0033A0` | L'encre manuscrite bleue — titres de notes, passages soulignés |
| `--mb-carrot` | `#F86015` | L'accent. Une seule utilisation aujourd'hui : l'icône météo du jour, mise en évidence dans le bandeau |
| `--mb-mint` | `#AFDCD3` | Bandeau de titre des cartes d'information |
| `--mb-label-solid` | `#FDE5D1` | Pastilles « lieu » et « date » |
| `--mb-rule` | `#2B231B` à 26 % | Lignes réglées du papier |
| `--mb-card-bg` | blanc à 96 % | Fond des cartes posées sur le papier |

> **Sur les noms.** `--mb-carrot` et `--mb-black` portent des noms hérités de l'ancienne
> palette de marque, où Carrot `#F86015` était l'accent de l'app. Ce n'est plus le cas :
> l'app est passée à Green `#28654B`, et Carrot n'existe plus de son côté. **Ces valeurs
> restent celles du carnet** — elles sont désormais définies ici, et nulle part ailleurs.
> Renommer `--mb-carrot` en `--mb-accent` lèverait l'ambiguïté ; ça ne change aucun rendu,
> mais ça touche le template, donc ça se fait dans un commit dédié.

### Ombres

| Variable | Valeur |
|---|---|
| `--mb-card-shadow` | `6pt 6pt 2pt rgba(53, 84, 193, 0.1)` — bleutée, comme une ombre de papier sous une lumière froide |
| `--mb-photo-shadow` | `0 3pt 4pt rgba(0, 0, 0, 0.25)` |

## Le papier

Le crème **n'est pas une couleur de fond** : c'est une teinte orangée posée sur du blanc,
plus un grain.

| Variable | Valeur |
|---|---|
| `--mb-paper-base` | `#FFFFFF` |
| `--mb-paper-tint` | `rgba(212, 136, 59, 0.1)` |
| `--mb-grain-opacity` | `0.3` |

### Deux profils de rendu

Le champ `render_profile` du payload choisit lequel s'applique (voir `LAYOUT_KB.md`) :

- **`preview`** — fond crème granulé, pour l'aperçu partageable dans l'app. C'est le
  profil par défaut.
- **`print`** — `--mb-paper-tint: transparent` et `--mb-grain-opacity: 0`, donc **fond
  blanc**. Le papier de l'imprimeur est déjà crème : le rendre une seconde fois donnerait
  un carnet jauni.

## Typographies

| Variable | Famille | Emploi |
|---|---|---|
| `--mb-font-display` | **Playfair Display**, puis Times New Roman | Titres et texte éditorial. C'est la voix principale du carnet |
| `--mb-font-hand` | **Gloria Hallelujah**, puis Bradley Hand | Passages manuscrits, annotations |
| `--mb-font-title` | **Hansley**, puis Gloria Hallelujah | Titres de journée |

Corps de texte : `12pt`, interligne `1.3`. La grille verticale (`--mb-line`) en découle —
c'est elle qui aligne le texte sur les lignes réglées du papier.

> **Hansley est une police propriétaire.** Si le `.woff2` n'est pas déposé dans
> `assets/fonts/`, le repli est la manuscrite et non le serif : un titre de journée doit
> rester écrit à la main, même dégradé.

Ces trois familles n'ont **rien à voir avec Sora et General Sans**, qui sont les polices
de l'app. Ne pas les mélanger : voir un titre de carnet en Sora, c'est voir une barre de
navigation dans un livre.

## La carte illustrée

Générée en SVG par `backend/src/services/mapSvg.ts` :

| Rôle | Valeur |
|---|---|
| Tracé du parcours | `#19532B` |
| Remplissage | même vert à 5 % |
| Pin de localisation | `#F86015` |

Ces deux couleurs viennent elles aussi de l'ancienne palette de marque et ne figurent pas
dans la table ci-dessus. À rattacher aux tokens du carnet — soit en les y ajoutant, soit
en les remplaçant — la prochaine fois qu'on touche à la carte.

## Les styles de carnet

Les fichiers d'[`agents/carnet-styles/`](../../agents/carnet-styles/) décrivent des
**ambiances éditoriales** — journal manuscrit, scrapbook coloré, vintage voyage — chacune
avec sa propre palette et sa propre typographie. Ils se posent **par-dessus** ces tokens
et peuvent s'en écarter : c'est leur raison d'être.

Un carnet suit **un seul style** de bout en bout. L'Agent Mise en page respecte le style
choisi à la lettre, et ne mélange jamais.

## À faire évoluer

- Rattacher les couleurs de la carte aux tokens (voir ci-dessus)
- Renommer `--mb-carrot`, dont le nom ne renvoie plus à rien
- Documenter les textures de `assets/` (scotch, grain) quand elles se stabiliseront
