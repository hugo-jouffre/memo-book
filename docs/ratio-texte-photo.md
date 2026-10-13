# Ratio texte / photo

Le réglage « Ratio photo / texte » de la personnalisation : la part de surface
qu'occupent les photos dans le carnet. Cinq paliers — 0, 25, 50, 75, 100 %.

| Où | Quoi |
|---|---|
| `backend/src/services/photoRatio.ts` | **Source de vérité** : le calcul, la table des gabarits, la mesure |
| `MemoBook Generator/public/ratio-photos.js` | La même, **générée** pour l'atelier (`npm run ratio:build`) |
| `backend/src/services/photoBudget.ts` | Ce que le chat annonce au voyageur |
| `backend/src/services/bookSettings.ts` | Le réglage appliqué au payload de l'app |
| `MemoBook Generator/public/app.js` | Le même, appliqué au payload de l'atelier |
| `backend/test/ratioPhotos.test.ts` | Les quinze cas, **mesurés dans Chromium** |
| `backend/test/ratioPhotosAtelier.test.ts` | L'atelier et l'app calculent-ils la même chose ? |

## La règle absolue

**Le texte validé par le voyageur ne bouge jamais.** Pas de coupe, pas de
reformulation, pas de troncature, pas de corps de police réduit au-delà de ce
que le gabarit fait déjà.

C'est le **nombre de pages** et le **nombre de photos** qui s'adaptent au texte.
Jamais l'inverse. Un paragraphe peut passer d'une page à la suivante ; le récit
d'une étape, bout à bout, reste identique octet pour octet — c'est la première
chose que vérifie chacun des quinze cas de test.

## Ce que « ratio » mesure

```
ratio = surface photo / (surface photo + surface texte)
```

- **surface photo** : les cadres `mb-photo`, **bord blanc compris** ;
- **surface texte** : ce que `mb-note` occupe réellement — lignes × `--mb-line`
  × largeur de colonne ;
- **sur l'étape entière**, pas page par page : une étape de deux pages n'aurait
  sinon aucune marge de manœuvre ;
- **éléments fixes exclus** : bandeau, titre, étiquette, météo, carte fun fact,
  carte de chapitre, décor. Les compter ferait varier le ratio sans qu'aucun
  réglage du voyageur n'ait changé.

Tolérance : **±5 points**.

## Les layouts de chaque palier

Mesurés sur le gabarit (colonne 349 pt depuis les marges de reliure, hauteur utile 535 pt, `--mb-line` 15,6 pt) :

| Configuration | Surface photo | Ratio à texte plein |
|---|---|---|
| `layout_story_full` (sans photo) | 0 | **0 %** |
| `layout_story_opener` + photo flottante | 26 730 | **28 %** |
| `layout_collage` / `layout_split_left`, bande de 2–3 photos | 70 000–72 100 | **52 %** |
| `layout_trio_portrait` / `layout_trio_landscape` | ~75 000 | 60 % |
| `layout_hero_top` | 96 480 | **68 %** |
| `layout_photo_page` (planche pleine) | ~216 000 | **100 %** |

| Ratio | Minimum de photos | Layouts |
|---|---|---|
| **0 %** | 0 | `layout_story_full`, et `layout_chapter_map` aux ouvertures de chapitre — une carte n'est pas une photo. Le récit prend la feuille, la réglure descend jusqu'en bas : 1180 signes sur une page à bandeau, 1700 sur une page de suite |
| **25 %** | 1 | `layout_story_opener` / `layout_story_facts`, chaque page gardant sa photo flottante ; un `layout_collage` si le compte le demande encore |
| **50 %** | 2 | `layout_collage` (2–3 photos), `layout_split_left`, `layout_hero_top` sur un texte court, les trios sur une page de suite. C'est ce que le carnet faisait déjà |
| **75 %** | 3 | `layout_hero_top` en tête, `layout_collage` à bande haussée, les trios, et une planche pour absorber le reliquat |
| **100 %** | — (se déduit des pages) | `layout_photo_wall_intro` (la première page garde le bandeau), puis `layout_photo_page`. Aucun `mb-note`, des légendes sous environ une photo sur deux |

Le réglage continu, c'est la **hauteur de bande** (`band_scale` sur la page,
`--mb-band` dans le CSS) : entre le plancher du CSS — `mb-gallery` jamais sous
160 pt — et le plafond que le texte de la page laisse libre. Une bande ne vole
jamais une ligne au récit.

## L'algorithme

1. mesurer la surface texte **T** de l'étape ;
2. calculer la surface photo cible **P = T × r / (1 − r)** ;
3. le nombre de pages : le maximum entre ce que le texte impose (réparti en
   remplissant chaque page avant d'ouvrir la suivante) et ce que T + P +
   éléments fixes imposent. Chaque hypothèse de pagination est **composée**, et
   on garde celle qui approche le mieux la cible ;
4. le layout de chaque page, dans l'ordre de préférence du palier ;
5. **N** = max(minimum du palier, ce que les layouts retenus portent, et jamais
   moins que le palier d'en dessous) ;
6. la hauteur des bandes, par dichotomie, chacune bornée par son texte ;
7. le résidu : la carte fun fact, puis les photos agrandies.

Tout est déclaré dans `GABARITS` et `PREFERENCES` : **ajouter un gabarit, c'est
ajouter une ligne à la table**, pas relire l'algorithme.

## Ce que le chat annonce

> Illustre ce souvenir avec 3 photos : c'est ce qu'il faut pour remplir sa page.

Le chiffre suit la longueur du récit **et** le réglage. À 0 %, le chat ne
demande aucune photo. Le PDF porte exactement ce nombre : c'est la même fonction
(`photosRequired`) qui répond aux deux, et un écart est un bug — c'est ce que
garde `ratioPhotosAtelier.test.ts`.

| Cas | Ce qui se passe |
|---|---|
| Le voyageur envoie **moins** de photos que demandé | La page se compose avec ce qui est là, et le layout se replie sur celui que le nombre réel sait tenir. Aucune photo n'est inventée |
| Il en envoie **plus** | Les N premières sont posées — l'ordre vient de l'analyse de détail existante |
| Il **change le ratio** après coup | L'étape est recalculée, le texte reste identique, le chat peut redemander des photos |

## Les cas où la tolérance n'a pas pu être tenue

Relevés **sur le rendu**, par `npm test -- test/ratioPhotos.test.ts`, au
13/10/2026 — après les marges de reliure, qui retirent 3 % de signes à chaque
page. Trois longueurs de récit × cinq paliers.

| Récit | Cible | Mesuré | Écart | Photos | Pages | État |
|---|---|---|---|---|---|---|
| court, 181 signes | 0 % | 0 % | 0 | 0 | 1 | dans la tolérance |
| court, 181 signes | 25 % | 84,2 % | **59,2** | 1 | 1 | dépassement assumé |
| court, 181 signes | 50 % | 82,4 % | **32,4** | 2 | 1 | dépassement assumé |
| court, 181 signes | 75 % | 81,9 % | **6,9** | 3 | 1 | remplissage forcé |
| court, 181 signes | 100 % | 100 % | 0 | 4 | 1 | dans la tolérance |
| moyen, 542 signes | 0 % | 0 % | 0 | 0 | 1 | dans la tolérance |
| moyen, 542 signes | 25 % | 29,0 % | 4,0 | 1 | 2 | dans la tolérance |
| moyen, 542 signes | 50 % | 52,7 % | 2,7 | 2 | 2 | dans la tolérance |
| moyen, 542 signes | 75 % | 75,0 % | 0 | 3 | 2 | dans la tolérance |
| moyen, 542 signes | 100 % | 100 % | 0 | 4 | 1 | dans la tolérance |
| long, 1354 signes | 0 % | 0 % | 0 | 0 | 2 | dans la tolérance |
| long, 1354 signes | 25 % | 26,7 % | 1,7 | 2 | 3 | dans la tolérance |
| long, 1354 signes | 50 % | 51,2 % | 1,2 | 4 | 3 | dans la tolérance |
| long, 1354 signes | 75 % | 74,0 % | 1,0 | 4 | 4 | dans la tolérance |
| long, 1354 signes | 100 % | 100 % | 0 | 9 | 2 | dans la tolérance |

**Douze cas sur quinze dans la tolérance. Les trois autres sont le même cas**, et
il était prévu : un récit de 181 signes, soit **sous le minimum de la taille S du
barème** (200). À cette longueur :

- le **minimum de photos** du palier gagne sur le ratio (1 photo à 25 %, 2 à
  50 %, 3 à 75 %). Une seule photo pèse déjà plus que quatre lignes de texte :
  26 730 pt² contre 22 464, soit 54 % à elle seule. Atteindre 25 % demanderait
  une photo de 5 616 pt² — un timbre de 75 × 75 pt ;
- la page **ne doit pas laisser de grande zone blanche**. Ni les fun facts ni le
  décor ne peuvent la remplir ici (voir plus bas), donc les photos s'agrandissent
  jusqu'au plafond que le texte leur laisse. C'est ce qui fait passer 75 % à
  81,9 % : le gabarit a délibérément haussé la bande pour occuper le blanc ;
- l'inspecteur marque ces cas **« dépassement assumé »** ou **« remplissage
  forcé »**, en ambre, et non comme une erreur rouge.

Il n'y a pas de correction à apporter : c'est une incompatibilité arithmétique
entre « au moins une photo » et « 25 % de surface » sur quatre lignes de texte.
La seule issue serait de descendre sous la taille S côté rédaction, ce que le
barème refuse déjà pour une autre raison — une page aux trois quarts vide.

### Deux écarts assumés avec la spécification

1. **Le décor n'absorbe pas le blanc d'une page.** La spécification demande
   d'absorber le résidu « par le décor (tracé, stickers), si l'option est
   activée », avant d'agrandir les photos. Dans ce gabarit, le tracé pointillé
   est dessiné **à l'intérieur** de la bande de photos (`mb_trace`, appelé par
   `.mb-gallery`) et le scotch tient aux coins des images : ni l'un ni l'autre ne
   descend dans le blanc. Le compter comme absorbeur laissait un quart de feuille
   vide sous un récit de trois lignes. Il ne compte donc pas.
2. **La carte fun fact n'absorbe que si le layout lui a prévu une place.**
   `layout_collage` et les trios n'ont pas d'encart (`encart: false` dans la
   table des gabarits). Une carte « allumée » dans les réglages ne remplit donc
   rien sur ces pages, et le résidu passe directement aux photos.

### Ce qui reste à construire

- **Les légendes des planches à 100 % ne sont pas rendues.** La spécification
  du chantier les demandait — « des légendes `mb-photo__caption` sous certaines
  photos, environ une sur deux, jamais toutes ». Mais le gabarit a tranché
  l'inverse entre-temps : « Pas de légende sur les pages de photos » (Hugo,
  12/10/2026), et la légende de page a été retirée dans le même mouvement. Les
  deux ne peuvent pas tenir ensemble. Le code a donc été retiré plutôt que
  laissé à moitié construit — pas de champ `caption` au schéma, pas de macro
  orpheline dans le gabarit. **À trancher** : si les légendes reviennent pour
  le palier 100 %, il faut dire en quoi elles diffèrent de celles qu'on vient
  d'enlever.
  À 100 %, la planche porte donc aujourd'hui le bandeau d'étape et la carte fun
  fact, et rien d'écrit d'autre.
- **Le `photo_ratio` par étape** est lu (`getPhotoRatio`) mais aucune interface
  ne le pose : la surcharge par étape est prête, elle n'est pas exposée.
- **Le format** est un paramètre de `photosRequired` (`FORMATS`), mais A5 est le
  seul décrit. Un second format demande une ligne dans la table, pas une refonte.
- **`layout_recit_photo`** (le récit qui contourne une grande photo, maquette de
  Banaue) n'est pas un gabarit candidat : le ratio ne le choisit jamais et
  recompose la page sur un gabarit qu'il connaît. L'ajouter demande une ligne
  dans `GABARITS` et son nom dans `PREFERENCES`.
- **`taille_texte`** (corps à 11 ou 13 pt) n'entre pas dans le calcul du ratio :
  les capacités employées sont celles du corps à 12 pt.
