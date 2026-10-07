# Contrat de mise en page — carnet `travel-journal`

Base de connaissance de l'agent qui produit le JSON envoyé au moteur PDF.

> **Règle de survie du dépôt.** Ce fichier décrit ce que `index.html` sait
> réellement afficher. Toute modification du template doit modifier ce fichier
> **dans le même commit**. C'est exactement ce qui avait dérivé : le KB
> documentait onze layouts dont un seul existait, et l'agent produisait des
> champs que personne ne lisait.

> **Qui lit ce fichier — et qui ne le lit pas.** Il est chargé tel quel dans le
> prompt de l'Agent Mise en page du back-end (`structuring.ts`) : une règle
> écrite ici s'applique aux carnets de l'app dès la fusion. **L'atelier
> (MemoBook Generator) ne le lit pas** : il n'a pas d'agent de mise en page, ses
> règles sont recopiées en code dans `MemoBook Generator/public/app.js`
> (`pagesDeRecit`, `repartirPhotos`, `placerPhotos`). Une règle ajoutée ici ne
> change donc rien aux PDF de l'atelier tant qu'elle n'y est pas portée — c'est
> ce qui s'est passé pour les trois règles de répartition, écrites le 05/10 et
> absentes du carnet généré le 06/10.

## Format

- Page **A5 : 420 × 595 pt** (1 unité Figma = 1 pt), sans fond perdu.
  Géométrie dans `print.json`, maquette Figma `geIpjYxG3WCkGrgJFpkuVC`.
  En millimètres — l'unité que demande le panneau d'APITemplate — c'est
  **148 × 210 mm** : l'A5 exact vaut 419,53 × 595,28 pt, soit un demi-point
  d'écart. Les deux écritures désignent la même feuille, et doivent rester
  d'accord (voir § « Pas de marges blanches »).
- Marge de contenu : 30 pt. Les décors (tracé pointillé, stickers) débordent
  volontairement.
- Une page de carnet = un élément `.page`. Une entrée de `days[]` = une page.
- **La page remplit la feuille, bord à bord.** Pas de marge d'impression, pas
  de conteneur centré, pas de `padding` autour des `.page` : la couleur du
  papier va jusqu'au bord coupé. Ce que ça impose est détaillé plus bas.

## Structure du payload

| Champ | Type | Rôle |
|---|---|---|
| `book_title` | requis | Titre de couverture, sur la photo |
| `book_subtitle` | optionnel | Bandeau blanc incliné sous le titre |
| `authors`, `date_range` | optionnels | Signature en bas de couverture |
| `cover_photo` | optionnel | Photo pleine page de couverture |
| `render_profile` | `print` \| `preview` | **Fond du PDF, voir plus bas** |
| `brand_name`, `year` | optionnels | Colophon (défauts `MemoBook` / `2026`) |
| `ai_illustrations` | optionnel, booléen | Ajoute « Illustrations par IA » au colophon. **Seulement si le carnet contient des illustrations générées** ; absent, la mention n'est pas imprimée |
| `intro_title`, `intro_text` | optionnels | Page d'introduction (`intro_text` en HTML) |
| `intro_photos[]` | 0 à 2 | Photos scotchées en haut de l'introduction |
| `days[]` | requis | **Une entrée = un bloc de récit, pas une page** — voir ci-dessous |
| `back_cover` | optionnel | Quatrième de couverture. **Sans `image`, variante typographique** — c'est le défaut souhaité. `closing_subtext` s'adresse au lecteur : jamais le nom d'un outil interne (« MemoBook Generator ») ni un compteur de l'atelier ; sans texte à y mettre, on l'omet |

Pages toujours produites, dans l'ordre : **couverture → colophon →
introduction (si `intro_text`) → étapes → quatrième de couverture**.

## Étapes, chapitres et sauts de page

Une entrée de `days[]` est une **étape**, pas une page. Une étape peut être une
journée, une semaine, un mois, un pays — ce que le récit découpe naturellement.

Deux règles :

- **Une nouvelle étape commence toujours une nouvelle page.** Jamais deux
  étapes sur la même feuille.
- **Une étape peut occuper plusieurs pages.** Le gabarit n'en produit qu'une
  aujourd'hui : quand une étape est trop dense, il faut la scinder en plusieurs
  entrées consécutives et ne remettre le bandeau `day_intro` que sur la
  première. Les suivantes ont un `title` **vide** et **pas de `day_intro`** —
  c'est à ça que le validateur les reconnaît comme la suite de la même étape, et
  c'est ce qui leur rend les 320 caractères que le bandeau occupait. Les tailles
  **L** et **XL** du barème sont faites pour ce couple de pages ; voir
  § « Longueur des textes ».

**Ouverture de chapitre.** Un chapitre commence par une page portant
`layout_chapter_map` : carte de la région à droite, récit et carte info à
gauche, photos en bas. Quand ouvrir un chapitre, et quelle carte montrer,
dépend de la forme du voyage :

| Forme du voyage | Chapitres | Carte à l'ouverture |
|---|---|---|
| Toujours la même ville (woofing, échange, stage) | Semaines / mois / années | Toujours la même carte de ville, enrichie de nouveaux points au fil du livre |
| Plusieurs villes, un seul pays | Semaines / mois / villes | Carte du pays au début du livre, puis une carte par sous-chapitre : par ville si ≥ 500 000 habitants, sinon par région traversée |
| 2 pays et plus (itinérant) | Semaines / mois / villes / pays | Carte du pays concerné à chaque ouverture de chapitre, puis cartes de villes pour certains sous-chapitres |
| 5 pays et plus (tour du monde) | Idem itinérant | Idem itinérant |
| Petits villages, à pied (randonnée) | Semaines / mois / villes | Zoom permanent sur le chemin, une carte à chaque chapitre **et** sous-chapitre |

### Chapitre ou journée ordinaire : comment l'ouverture est arbitrée

`layout_chapter_map` et le layout par défaut se disputent la même page — celle
qui ouvre un chapitre. Le départage se fait dans cet ordre, et il s'arrête au
premier « non ».

1. **Est-ce une ouverture de chapitre ?** La table ci-dessus le dit, selon la
   forme du voyage. Si non, layout par défaut, et la question ne se pose pas.
2. **Le récit nomme-t-il un lieu cartographiable ?** `layout_chapter_map` exige
   `map`, et `map` exige un code ISO et des coordonnées justes au dixième de
   degré. Un chapitre qui s'ouvre sur « quelque part dans les terres » n'a rien
   à cartographier : layout par défaut. Une carte sans point, ou pointée au
   hasard, se repère immédiatement quand on connaît le pays — c'est pire que
   pas de carte.
3. **Le récit tient-il dans ce que la carte laisse ?** C'est le point qu'on
   oublie. La carte occupe 176 pt à droite, et la colonne de récit tombe à ~24
   caractères par ligne. Les plafonds mesurés :

   | Ouverture de chapitre | Plafond |
   |---|---|
   | carte seule, pas de bande d'images | 560 |
   | carte + 2 photos | 320 |
   | carte + 2 photos + un `fun_facts` | 120 |

   Si le récit dépasse, **on allège la page avant de renoncer à la carte**,
   dans cet ordre : retirer le `fun_facts` (120 → 320), puis descendre sous
   deux photos (320 → 560). Une ouverture de chapitre vaut mieux sans encart
   que sans carte.
4. **Si le récit ne tient toujours pas**, layout par défaut, et le chapitre
   s'ouvre sans carte. On ne scinde pas une ouverture de chapitre en deux pages
   pour sauver la carte : le bandeau et la carte sur une page, la suite du
   récit sur une autre, ça ne se lit plus comme une ouverture.

En résumé : **la carte gagne sur l'encart et sur les photos, et perd sur le
récit.** Le texte du voyageur ne se raccourcit jamais pour faire entrer un
décor.

## Les cartes

L'agent **décrit** la carte, il ne la dessine pas :

```json
"map": {
  "regions": ["PH"],
  "points": [
    { "label": "Manille", "lat": 14.5995, "lon": 120.9842 },
    { "label": "Visayas", "lat": 10.3157, "lon": 123.8854 }
  ]
}
```

- `regions` : codes **ISO 3166-1 alpha-2**. Le premier cadre la vue, les
  suivants n'ajoutent que du contexte. 175 pays disponibles.
- `points` : 6 maximum. Les coordonnées doivent être justes au dixième de
  degré — un point mal placé se voit immédiatement quand on connaît le pays.

Le back-end projette le contour et les points avec **la même** transformation
(Mercator), puis insère le SVG dans `map_svg`. Ils ne peuvent donc pas diverger.
Voir `backend/src/services/mapSvg.ts`.

## Quand il manque des photos, ou du texte

Le carnet doit rester beau dans les deux cas extrêmes. Aucun champ visuel n'est
obligatoire :

- `intro_photos` est **optionnel** : sans photo adaptée, la page d'introduction
  n'affiche que le récit manuscrit.
- `cover_photo` est **optionnel**. *(À construire : une couverture sans photo,
  portée par la typographie et une illustration de la région visitée.)*
- Un récit très court doit déclencher un layout qui respire — la grande photo de
  `layout_hero_top`, la carte de `layout_chapter_map` — plutôt qu'une page aux
  trois quarts vide. Ce n'est plus une intention : sous le minimum de la taille
  S, le validateur refuse un layout de récit dès qu'une photo était disponible.
  Le barème et les deux messages destinés au voyageur sont en
  § « Longueur des textes ».

*(À construire : les variantes sans photo. Pour l'instant, l'agent choisit le
layout existant le plus proche.)*

## Les deux profils de sortie

`render_profile` décide du fond. Une seule template, deux rendus :

- **`print`** — fond blanc. Destiné à l'imprimeur, dont le papier est **déjà
  crème** : réimprimer le crème donnerait un carnet jauni.

  La règle vaut aussi pour les **aplats** : tout fond crème dont le rôle est de
  « faire papier » — ruban de journée, étiquettes `lieu` / `date`, étiquette de
  section — passe au blanc en profil imprimeur. Déposer du beige sur un papier
  déjà crème, c'est payer de l'encre pour assombrir une teinte qu'on a déjà ;
  la forme reste lisible par son contour, qui lui s'imprime. Tout élément à
  venir de la même famille doit utiliser les tokens `--mb-paper-fill` ou
  `--mb-label-solid`, jamais une couleur en dur.
- **`preview`** — fond crème granulé, réplique du rendu final. C'est celui de
  l'aperçu partageable dans l'app, en attendant la version imprimée.

Défaut : `preview`. Côté back-end, la variable `RENDER_PROFILE` fait foi.

## Les réglages du voyageur

Le voyageur règle une partie de ce que la page montre, depuis l'écran
*Personnalisations* de l'app. Le détail, les libellés et les défauts sont dans
**`docs/reglages-utilisateur.md`** ; ici, seulement ce que le gabarit sait en
faire aujourd'hui.

| Réglage | Défaut | Où ça agit | État |
|---|---|---|---|
| Ratio photo / texte | 50/50 | Choix des layouts par l'agent | Rendu |
| Nombre de page cible | 60 | Niveau de détail des textes, regroupement des étapes | Rendu |
| Fun facts | ON | `fun_facts` — voir le dosage plus bas | Rendu |
| Quiz | ON | `quiz` | Rendu |
| Pointillés | ON | La **réglure** du papier, `.mb-note__rules` | **À construire** |
| Décorations & stickers | 2 | Quota par paragraphe ou par image ; le scotch y est compté | **Partiel** : le scotch est rendu, les stickers non |
| Typographies (assortiment) | Carnet de voyage | Les quatre tokens ci-dessous d'un bloc | **À construire** — l'app n'expose plus quatre réglages mais **quatre assortiments** (`docs/reglages-utilisateur.md`) : Carnet de voyage, Éditorial, Moderne, Manuscrit. Le payload, lui, reste quatre champs |
| ↳ titres | Playfair | `--mb-font-display` | **À construire** |
| ↳ sous-titres | Hansley | `--mb-font-title` | **À construire** — `Hansley.otf` versionné mais pas inliné, repli sur la manuscrite |
| ↳ textes | Gloria Hallelujah | `--mb-font-hand` | **À construire** |
| ↳ fun facts | Playfair | Pas de token dédié : partage `--mb-font-display` | **À construire** — créer `--mb-font-facts` |
| Zones libres | ON | Zone blanche en fin d'étape + trois pages blanches en fin de carnet | **À construire** |
| Mot fléché | ON | Grille générée à la commande, posée en fin de carnet | **À construire** |

**Deux « pointillés » à ne pas confondre.** Le réglage porte sur la **réglure**
— les lignes en pointillé sous le texte. Le **tracé pointillé du voyage** (voir
plus bas) est un décor de bas de page : il relève du quota de décorations, pas
de ce booléen.

**Rien de tout cela n'est encore dans le payload.** Les réglages marqués « à
construire » demandent un champ au schéma, une lecture par le gabarit, et cette
table mise à jour dans le même commit. Tant que ce n'est pas fait, l'agent ne
produit rien pour eux et l'app ne devrait pas les proposer.

## Champs d'une journée

| Champ | Type | Notes |
|---|---|---|
| `title` | requis | Titre manuscrit en tête du récit |
| `body_html` | requis | Récit. `<p>` par idée, `<ul>/<li>` pour les listes. Pas de `<h1>`/`<h2>` |
| `day_intro` | optionnel | Affiche le bandeau : `{ day_number, location, date, stay, host, weather_key }` |
| `stay`, `host` | optionnels | Nom du gîte, prénom des hôtes. **À préférer à la météo** |
| `weather_key` | optionnel, 5 valeurs | Icône mise en avant. **Seulement si le vocal dit clairement le temps** ; sans le champ, la rangée disparaît |
| `tag` | optionnel | Étiquette manuscrite (« Top départ »). **Trois mots max**, sinon elle déborde. **Jamais le lieu** : il est déjà dans le bandeau. Sans humeur à y mettre, on l'omet |
| `fun_facts[]` | optionnel | **Seul le premier est affiché.** Dosage : voir plus bas |
| `fun_facts_title` | optionnel | Titre de la carte. Défaut « Fun fact » ; aussi « Infos », « Culture générale » |
| `photos[]` | optionnel | Nombre utilisé selon le layout, voir ci-dessous |
| `prompt` | optionnel | Champ à remplir à la main. **Un seul bloc interactif par page** |
| `quiz` | optionnel | Petit jeu, réponse imprimée à l'envers. Idem : un seul par page |
| `ai_note` | optionnel | Mention grise en bas de page dès qu'un élément vient de l'IA |

`highlights`, `sticker_groups`, `timeline_events`, `storyboard_cards`,
`global_stats` restent acceptés par le schéma mais **ne sont pas rendus** :
ne pas les produire tant qu'un layout ne les consomme pas.

## Catalogue des layouts

Un seul drapeau à `true` par journée. En cas de conflit, l'ordre ci-dessous
tranche : le premier actif l'emporte.

| Drapeau | Rendu | Quand le choisir | Photos | Tailles |
|---|---|---|---|---|
| `layout_chapter_map` | Carte de la région à droite, récit et carte info à gauche, photos en bas | Ouverture d'un chapitre, **quand un lieu est nommé dans le récit** — voir la table plus haut | 0–2 | sous S à M, **selon la carte info et les photos** |
| `layout_hero_top` | Grande photo en tête, récit dessous | Une photo iconique porte la journée | 1 | sous S, S |
| `layout_split_left` | Carte info à gauche, récit en colonne à droite, puis deux photos en bas | Un fait à mettre en avant et deux belles images | 2 | S, M — **S seulement avec un fun fact** |
| `layout_collage` | Récit pleine largeur puis 2 ou 3 photos inclinées en bas | Journée dense visuellement | 2–3 | S, M |
| `layout_photo_page` | **Page pleine de photos**, sans récit ni bandeau. `title` devient une légende manuscrite en bas | Étape très visuelle. En placer régulièrement — mais **jamais deux de suite**, voir § « La répartition sur une étape à plusieurs pages » | 3–5 | aucune — le récit n'est pas rendu |
| *(par défaut)* | Récit, puis carte info et photo flottantes en bas de page | Ouverture de journée, cas le plus courant | 0–1 | S, M |

Les tailles exactes, et le plafond mesuré de chaque configuration, sont en
§ « Longueur des textes ».

Le cas par défaut couvre aussi `layout_story_opener` et `layout_story_facts` :
le validateur exige au moins un drapeau, n'importe lequel de ces deux convient.

**La condition du lieu sur `layout_chapter_map`.** Ce layout se choisit à
l'ouverture d'un chapitre, mais seulement **si le récit nomme un lieu** : c'est
ce lieu qui alimente `map.points`, et le layout exige `map`. Un chapitre qui
s'ouvre sans lieu identifiable n'a rien à cartographier — une carte sans point,
ou pointée au hasard, se repère immédiatement quand on connaît le pays. Dans ce
cas, ouvrir le chapitre avec un autre layout et garder `layout_chapter_map`
pour le premier chapitre où un lieu est nommé.

## Le tracé pointillé du voyage

Décor tiré au sort parmi quatre boucles. **Il ne passe que derrière des photos,
jamais derrière du texte**, qu'il rendrait illisible.

Pour le garantir, le tracé est dessiné **dans la bande de photos** (macro
`mb_trace`, appelée par `.mb-gallery`) et positionné par rapport à elle — pas
par rapport à la page. Où que la bande se trouve, il la suit, et il ne monte
jamais au-dessus de 112 pt quand la bande en fait au moins 160. Seuls les
layouts qui ont une bande en portent donc un : `layout_split_left`,
`layout_collage` et `layout_chapter_map` avec deux photos ou plus. Le layout par
défaut (photo flottante), `layout_hero_top` et les pages à `prompt` ou `quiz`
n'en ont pas.

> **Pourquoi il passait sous le texte (carnet du 06/10).** Le tracé était posé
> à hauteur fixe sur la page — 24, 48 ou 96 pt du bas — en supposant la bande
> de photos toujours collée en bas. Mais quand un récit dépassait ce que la
> page tient, la bande cédait la place (elle est faite pour se comprimer) ou
> sortait de la feuille, et c'est le texte qui occupait la hauteur où le tracé
> était dessiné. La condition du gabarit ne regardait que le nombre de photos,
> jamais où elles étaient réellement.

Rien à envoyer pour le piloter : c'est une règle du gabarit, pas un champ.

## Longueur des textes — le barème S / M / L / XL

> Ce barème existe parce que les deux agents ne comptaient pas la même chose.
> La mise en page raisonnait par layout, la rédaction écrivait librement, et une
> étape allait de 200 à 1260 caractères sans que personne ne sache laquelle
> tenait sur la page. **La taille se mesure désormais sur l'étape entière**, et
> le nombre de paragraphes s'en déduit — l'inverse laissait l'ambiguïté intacte.

**Ce qui se compte** : le texte brut de `body_html`, balises retirées, additionné
sur toutes les pages de l'étape. Ni le titre, ni le bandeau, ni l'encart, ni les
légendes — ils ont leurs propres limites.

| Taille | Fourchette | Cible | Paragraphes | Pages |
|---|---|---|---|---|
| **S** | 200 – 379 | 290 | 1 | 1 |
| **M** | 380 – 559 | 470 | 2 | 1 |
| **L** | 560 – 899 | 720 | 3 | 2 |
| **XL** | 900 – 1440 | 1150 | 4 | 2 |

Le nombre de paragraphes est une **cible de rédaction**. Ce qui se vérifie, c'est
ce que chaque *page* porte — voir ci-dessous, parce que c'est cela qui a été
mesuré.

Les fourchettes sont des **fourchettes d'acceptation**, pas des valeurs exactes :
le voyageur retouche son texte au clavier dans l'app, et une étape ne bascule pas
d'un cran parce qu'il a ajouté trois mots. Elles sont contiguës et couvrent
200 → 1440 sans trou.

**1440 n'est pas un chiffre rond**, c'est 560 + 880 : la capacité d'une page à
bandeau plus celle d'une page de suite. Les deux sont mesurées — 880 garde 20
caractères de marge sur les 900 relevés, parce que la dernière valeur qui passe
n'est pas la première qui casse. On arrondit vers le bas.

### Ce que chaque page accepte réellement

Plafonds relevés par `backend/scripts/calibrate-lengths.ts`, qui rend chaque
layout à longueur croissante et note le point où la bande de photos se comprime
ou le texte passe sous la marge. **Ils ne se devinent pas** : les redériver, c'est
relancer le script.

| Configuration | Plafond | Tailles acceptées |
|---|---|---|
| `layout_photo_page` | 0 — aucun récit rendu | — |
| `layout_chapter_map` + fun fact + ≥ 2 photos | 120 | sous S |
| `layout_split_left` + fun fact | 240 | sous S, S partiel |
| `layout_chapter_map` + ≥ 2 photos, sans fun fact | 320 | sous S, S partiel |
| `layout_hero_top` | 380 | sous S, S |
| `layout_story_*`, `layout_collage`, `layout_split_left` sans fun fact, `layout_chapter_map` sans photos | 560 | S, M |
| `layout_story_*` portant un `prompt` | 760 | S, M |
| **page de suite** (sans `day_intro`), tout layout de récit | 880 | complète L et XL |

**Un couple, pas un nombre.** Ce n'est pas une longueur seule qui a été mesurée
mais un couple (caractères, paragraphes) : chaque `<p>` est suivi d'une ligne
vide, et celle de trop pousse le contenu sous la marge. 560 caractères tiennent
en **2** paragraphes et débordent en 3 ; 880 tiennent en **4** et débordent en 5.
D'où deux plafonds fermes :

| Page | Paragraphes |
|---|---|
| page à bandeau (avec `day_intro`) | 2 |
| page de suite (sans `day_intro`) | 4 |

**La règle à retenir, c'est celle de la carte info.** Sur `layout_split_left` et
`layout_chapter_map`, l'encart occupe 173 pt de large : la colonne de récit tombe
de ~59 à ~24 caractères par ligne. **Un `fun_facts` sur ces deux layouts retire
une taille.** C'est le seul piège du barème, et il coûte plus de la moitié de la
page.

### Les deux bornes basses

Sous 200 caractères, la page reste aux trois quarts vide. Deux cas, deux
traitements :

- **une photo ou une carte est disponible** → le payload est **refusé**, et le
  message nomme le repli : `layout_hero_top` (la grande photo tient la hauteur)
  ou `layout_chapter_map` à une ouverture de chapitre. C'est le cas que le
  barème vise ;
- **ni photo ni carte** → simple **avertissement**. Aucun layout n'aurait fait
  mieux, et refuser un carnet entier pour un souvenir court demanderait au
  voyageur une correction qu'il ne peut pas faire. Une page trop aérée s'imprime ;
  une page qui déborde, non.

Au-dessus de 1440, refus : il faut **deux étapes**, pas une étape plus longue.

### Une étape sur plusieurs pages

L et XL ne tiennent pas sur une feuille. L'étape se scinde en **deux entrées
consécutives de `days[]`** :

- la première porte `day_intro` et le `title` — elle plafonne à 560 ;
- la seconde a un `title` **vide** et **pas de `day_intro`** : c'est ce qui lui
  rend les 320 caractères du bandeau, et la porte à 880.

C'est ce couple que le validateur reconnaît comme une étape unique : toute entrée
sans `day_intro` prolonge la précédente.

**On remplit la première page avant d'ouvrir la seconde.** Répartir 720
caractères en 360 + 360 laisse deux pages à moitié pleines et un blanc au milieu
de chacune ; 560 + 160 en laisse une pleine et une aérée, ce qui est le rythme
d'un carnet. La coupe se fait sur une fin de phrase, jamais au milieu d'une idée.

### La répartition sur une étape à plusieurs pages

Une étape qui couvre trois pages doit se lire comme **trois pages de carnet**,
pas comme une page de texte suivie d'un album photo. C'est exactement ce qui
arrivait : une étape à neuf photos sortait en une page de récit portant **une**
image, puis deux planches de photos muettes à la suite. Le lecteur y voit deux
objets différents collés l'un à l'autre, et le récit perd ses illustrations.

Trois règles, dans cet ordre de priorité.

**1. Jamais deux `layout_photo_page` consécutifs.** Deux planches à la suite,
c'est un album inséré au milieu du carnet : la respiration visuelle que ce
gabarit apporte vient de ce qu'il **surprend**, et deux fois de suite il ne
surprend plus. S'il reste assez de photos pour deux planches, c'est qu'elles
devaient être réparties sur les pages de récit, ou que l'étape en porte plus que
le carnet n'en demande — mieux vaut en laisser de côté qu'aligner les planches.

**2. Chaque page de récit prend ses photos avant qu'une planche s'ouvre.** Une
page de récit en pose une à trois selon son gabarit ; on sert d'abord toutes les
pages de récit de l'étape, et seule la **surabondance** va sur une planche. Garder
les images pour la fin, c'est se retrouver avec un récit nu puis une pile
d'images sans légende. Le cas à proscrire : **une page entièrement couverte de texte
suivie d'une planche entièrement couverte de photos**. Deux pages qui mêlent
chacune texte et images valent toujours mieux.

**3. Le texte se répartit pour qu'aucune page de l'étape ne soit maigre.** La
règle du « remplir la première d'abord » vaut tant qu'il reste de quoi tenir la
suivante au-dessus du minimum de S. Trois pages à 400 caractères valent mieux
que 560 + 560 + 80, où la dernière n'est qu'un reliquat.

**Le cas qui a motivé ces règles.** L'étape du 22, neuf photos et 756 caractères,
sortait ainsi :

| | Rendu avant |
|---|---|
| page 1 | layout par défaut — récit entier, **1 photo** |
| page 2 | `layout_photo_page` — 5 photos |
| page 3 | `layout_photo_page` — 3 photos |

Deux planches de suite, et huit photos sur neuf coupées du texte qu'elles
illustrent. Ce qu'il fallait : deux pages de récit se partageant le texte **et**
leurs photos, puis au plus une planche pour le surplus.

### Les autres champs

Appliqués par `backend/src/services/payloadValidator.ts` — un dépassement est une
**erreur**, pas un avertissement :

| Champ | Maximum |
|---|---|
| `intro_text` | 700 caractères par paragraphe, 3 paragraphes |
| `body_html`, par paragraphe | 380 — la taille S. Au-delà c'est un mur de texte quelle que soit la taille de l'étape |
| `fun_facts[]` | 140 caractères |
| `highlights[]` | 80 caractères |

### Ce que l'app dit au voyageur

Pendant qu'il écrit, l'app compte les caractères de l'étape et affiche sa taille.
Deux messages, aux deux bornes du barème, définis une seule fois dans
`payloadValidator.ts` (`LENGTH_HINTS`) et recopiés dans `EntryEditorView.swift` :

- **sous 200** — « Encore quelques lignes : sous 200 caractères, l'étape laisse
  une page aux trois quarts vide. Raconte un détail de plus — ce que tu as vu,
  mangé, entendu. »
- **au-dessus de 1440** — « Ce souvenir dépasse ce qu'une étape peut contenir :
  1440 caractères, soit deux pages de carnet. Coupe-le en deux étapes, chacune
  aura les siennes. »

## Les fun facts — dosage et matière

> Retour le plus unanime du panel de lecteurs : **6 sur 7** en parlent, tous
> dans le même sens. Ce n'est pas un rejet — les fun facts sont aussi cités
> parmi les points forts — mais un problème de **quantité** et de **nature**.
> Un lecteur résume tout : « j'ai lu tous les fun facts, mais pas tout le
> contenu ». La carte gagnait la page contre le récit.

**Les encarts sont un réglage du voyageur, ON ou OFF.** À OFF, aucun `fun_facts`
n'est produit. Les règles ci-dessous valent à ON.

Quatre règles, à appliquer strictement :

1. **Fréquence : un encart toutes les trois à quatre pages**, selon la
   pertinence des faits disponibles. Jamais un par page.
2. **Un seul « Le saviez-vous » par étape**, quelle que soit la longueur.
3. **La matière doit venir du récit.** Un fait drôle réellement vécu vaut mieux
   qu'une donnée encyclopédique. La culture générale reste possible, mais en
   minorité et seulement si elle éclaire ce qui est raconté.
4. **Score de pertinence.** En dessous du seuil, **ne rien mettre** : omettre
   `fun_facts` est toujours préférable à un encart de remplissage.

| Ce fait mérite-t-il un encart ? | Verdict |
|---|---|
| Un épisode cocasse du récit, raconté en une phrase | Oui, c'est le meilleur cas |
| Une info qui explique ce que le voyageur vient de vivre | Oui |
| Une donnée vraie mais sans lien avec la journée | Non — omettre |
| Un chiffre trouvé pour meubler une page vide | Non — utiliser `prompt` ou `quiz` |

## Occuper les blancs sans les décorer

Deux lecteurs reprochent aux illustrations et aux emoji de « ne servir qu'à
combler le vide ». La réponse n'est pas d'ajouter du décor, mais de rendre la
page **habitable** :

- `prompt` — un champ à remplir à la main, sur lignes réglées :
  « Ton état d'esprit ce jour-là ».
- `quiz` — une question liée au voyage, cases à cocher, **réponse imprimée à
  l'envers** sous la question, comme dans les pages de jeux.

**Un seul bloc interactif par page**, et il remplace la zone flottante du bas
(carte info + photo). Les empiler fait déborder la page.

Le `quiz` est **réglable par le voyageur**, ON par défaut : à OFF, aucun n'est
produit, et le blanc se remplit par un `prompt` ou reste blanc.

## La mention « généré par IA »

`ai_note` s'imprime en petit gris, en bas de page. À renseigner **dès qu'un
élément de la page vient de la machine** — c'est une demande explicite, pas une
option. Exemple : « Fun fact et illustration générés par IA ».

## La météo du jour

**La météo ne figure que si le voyageur la dit clairement dans son vocal.**
Sinon, pas de `weather_key` : la rangée disparaît, et c'est le cas normal.

C'est une décision, pas un réglage par défaut. Les lecteurs sont explicites : la
météo n'est pas importante, ils préfèrent la carte, le nom de l'hôtel et l'hôte
— et une rangée absente aère la page, autre demande du panel. Préférer
`day_intro.stay` et `day_intro.host`. Surtout, une météo supposée est une
**invention** : elle imprime dans le carnet un temps que personne n'a raconté.

| Le vocal dit… | `weather_key` |
|---|---|
| « il a plu toute la journée », « grand soleil », « tempête de neige », « ciel tout gris » | la valeur qui correspond |
| rien sur le temps | **aucune** — même en Grèce en août |
| « coucher de soleil », « on a bronzé », « à la plage » | **aucune** — ce sont des activités, pas une météo dite |
| un temps qui ne se range dans aucune valeur, ou deux temps sans dominante | **aucune** — dans le doute, on omet |

Quand la météo est dite, le bandeau affiche les cinq icônes ; celle qui
correspond passe en pastille carotte, les quatre autres restent estompées à
30 %. **Il n'y a rien d'autre à envoyer** — ni emoji, ni couleur, ni
température.

**Qui la relève.** L'Agent Transcription, à la rédaction de chaque étape : il
lit le vocal et rend `weatherKey`, `null` le plus souvent. La mise en page la
reprend telle quelle et n'en ajoute jamais — `structuring.ts` retire toute
`weather_key` que la rédaction n'a pas relevée. L'atelier (MemoBook Generator)
ne lit pas le récit : il n'en envoie jamais.

| Valeur | Icône | Quand la choisir |
|---|---|---|
| `sun` | soleil plein | Grand beau, ciel dégagé, forte chaleur |
| `sun-wind` | soleil et vent | Éclaircies, ciel voilé, brise, temps changeant |
| `cloud` | nuage | Couvert, gris, brume, sans pluie |
| `rain` | pluie | Averses, mousson, orage |
| `snow` | flocon | Neige, gel, froid marquant |

**Comment choisir la valeur**, une fois la météo dite : prendre le temps
*dominant* que raconte le voyageur, pas le plus spectaculaire — une éclaircie
de dix minutes dans une journée de pluie reste `rain`. Ne jamais se fier au lieu
ni à la saison pour combler un silence, et ne pas prendre `sun-wind` comme
repli : sans météo dite, on omet le champ. Un bandeau sans rangée météo n'a rien de
cassé — c'est la rangée elle-même qui disparaît, pas seulement l'icône active.

`weather_icon` (emoji) subsiste dans le schéma pour compatibilité mais n'est
plus rendu. Ne pas le produire.

## Réglure et rythme vertical

**Un bandeau seul garde une ligne de réglure sous le ruban.** Quand rien ne
s'affiche sous le bandeau — ni nuit, ni hôte, ni météo, ni étiquette —, le
titre de l'étape descend d'une ligne (`.mb-header--seul`) : sans elle, le récit
collait au ruban. Les rangées « nuit » ou « météo » font déjà cet écart quand
elles sont là, et le barème a été calibré avec une rangée « nuit » : la page
tient donc le même texte dans les deux cas.

La réglure du papier est générée, pas dessinée : elle se répète tous les
`--mb-line`. Elle n'est juste que si **tout ce qu'elle traverse occupe un
multiple entier de cette valeur** — le titre pèse exactement deux interlignes,
la marge d'un paragraphe exactement un. Un bloc d'une autre hauteur décale
toutes les lignes suivantes, et l'écart texte/ligne dérive le long de la page.

Chaque paragraphe est suivi d'**une ligne vide** : elle montre l'emplacement
resté libre dans le gabarit, comme sur un carnet où l'on n'a pas rempli la page.

La réglure est un **pointillé gris clair**, pas un trait plein : deux lecteurs
la trouvaient trop marquée. Elle doit se deviner sous le texte, jamais se lire
avant lui.

C'est elle que gouverne le réglage **« Pointillés »**, ON par défaut. À OFF, les
`<i>` de `.mb-note__rules` ne sont pas émis : la page reste blanche sous le
récit, **et le rythme vertical ne bouge pas** — les hauteurs restent des
multiples de `--mb-line`, sans quoi la page se décalerait selon un réglage
d'affichage.

**Le nombre de pages est la vraie contrainte d'un long voyage.** Un lecteur
fixe la limite : moins de 50 pages pour 3 mois, sinon l'objet devient trop
gros. La variable n'est pas le nombre de pages mais le taux de compression par
étape — c'est ce qui justifie de regrouper les étapes sur les voyages longs
(voir la table des chapitres plus haut).

## Règles d'images

> **L'image passe avant le texte.** C'est le retour le plus constant du panel,
> toutes vagues confondues : « trop de texte », « les photos doivent être plus
> grosses », « moins de texte, chiant à lire ». À contenu égal, préférer
> toujours le layout le plus visuel, et intercaler des `layout_photo_page`.

- **URL absolue et publique, ou donnée `data:` en base64.** Jamais de chemin
  relatif : le moteur PDF ne reçoit que du HTML et du CSS, sans aucun fichier
  joint. En beta, c'est le base64 qui est retenu — voir « Ce que le moteur de
  rendu reçoit » pour le détail et pour le seuil de bascule vers un CDN.
- **1750 px minimum** pour une photo pleine page (couverture, quatrième,
  `layout_photo_page`) : à 148 mm de large, il en faut autant pour tenir les
  300 ppi de l'imprimeur. 1200 px n'y suffisent pas — ça donne 205 ppi.
- 1200–1600 px suffisent pour une photo héro ou une photo de galerie, qui
  n'occupent qu'une fraction de la largeur.
- Les photos sont recadrées en `object-fit: cover` et pivotées de quelques
  degrés : ne pas envoyer une image dont un visage touche déjà le bord.
- **Le scotch entre dans le quota de décorations** réglé par le voyageur (0 à 4
  par paragraphe ou par image, 2 par défaut). À 0, aucun `tape_corner`. Le quota
  est un plafond : une photo qui n'a pas besoin de son scotch s'en passe.
- **Pas d'illustration qui occupe une page seule.** Une photo des voyageurs
  vaut mieux qu'un dessin de remplissage : deux lecteurs le disent séparément.

### Rognage des photos

Chaque emplacement a son format, et une photo qui n'a pas le même est rognée
(`object-fit: cover`). Deux PDF ont montré ce que ça donne quand rien ne le
borne : une photo de groupe paysage posée dans la colonne étroite d'une planche,
où il ne restait que deux personnes sur quatre ; trois photos paysage dans les
colonnes d'un collage, réduites à des lanières méconnaissables.

**On mesure le rognage comme la part de l'image perdue** :
`1 − min(format cadre / format photo, format photo / format cadre)`, les formats
étant largeur ÷ hauteur.

**Le plafond : un tiers.** On garde toujours au moins les deux tiers de l'image.
C'est le seuil qui laisse passer les cas qui se lisent bien et arrête ceux qui
ne se lisent plus :

| Photo (format) | Emplacement (format) | Rognage | |
|---|---|---|---|
| paysage 4:3 (1,33) | héro (1,35) | 1 % | ✅ |
| portrait 3:4 (0,75) | bande de 2 (0,90) | 17 % | ✅ |
| paysage 4:3 (1,33) | photo flottante (1,02) | 23 % | ✅ |
| paysage 4:3 (1,33) | bande de 2 (0,90) | 32 % | ✅ juste sous le plafond |
| portrait 3:4 (0,75) | héro (1,35) | 44 % | ❌ |
| paysage 4:3 (1,33) | bande de 3 (0,56) | 58 % | ❌ — le jour 5 du 06/10 |
| paysage 4:3 (1,33) | colonne de planche (0,45) | 66 % | ❌ — la photo de groupe du 06/10 |

Trois règles, appliquées dans cet ordre :

1. **Chaque photo va à l'emplacement qui la rogne le moins.** Sur une page qui
   en porte plusieurs, on essaie toutes les répartitions (120 au plus, pour
   cinq photos) et on garde celle dont le rognage total est le plus faible : la
   paysage dans l'emplacement large, la portrait dans la colonne.
2. **Au-delà d'un tiers, on réduit au lieu de rogner** — `fit: "contain"`. La
   photo entre entière dans son emplacement, et le cadre blanc l'épouse : c'est
   un petit tirage, pas une image coupée. **Une photo de groupe n'est jamais
   rognée**, quel que soit le rognage : elle passe toujours en `contain`.
3. **Les visages restent dans le cadre.** Une photo plus haute que son
   emplacement est rognée en haut et en bas : on garde le haut (`focus`
   vertical à 30 %), là où sont les visages sur une photo prise à hauteur
   d'homme. Quand une détection de visages est disponible, ses boîtes priment :
   le cadre doit contenir au moins chaque visage entier, et une photo dont les
   visages ne tiennent pas dans le cadre passe en `contain`.

**Les formats des emplacements**, mesurés sur le rendu (image seule, sans le
cadre blanc), dans l'ordre où le gabarit lit `photos[]` :

| Layout | Photos | Formats |
|---|---|---|
| par défaut (photo flottante) | 1 | 1,02 |
| `layout_hero_top` | 1 | 1,35 |
| `layout_split_left`, `layout_collage` | 2 | 0,90 · 0,90 |
| `layout_collage` | 3 | 0,56 · 0,56 · 0,56 |
| `layout_photo_page` | 3 | 0,73 · 0,45 · 1,65 |
| `layout_photo_page` | 4 | 0,73 · 0,45 · 0,62 · 0,99 |
| `layout_photo_page` | 5 | 1,76 · 1,44 · 0,90 · 0,90 · 1,44 |

Ils sont recopiés dans `FORMATS_EMPLACEMENTS` (atelier, `app.js`) : **à
remesurer si la géométrie d'un layout change**.

**La bande de photos ne s'écrase plus sous 160 pt** (206 pt en temps normal).
Elle cédait sans limite quand un récit débordait ; à 100 pt, trois photos ne
sont plus que des lanières. Un récit trop long se découpe en amont, selon le
barème — il ne se loge pas en écrasant les images.

**Qui l'applique.** L'atelier, dans `placerPhotos` (`app.js`), avec une case
« Photo de groupe, ne pas rogner » sur chaque photo : il ne sait pas compter
les visages, c'est donc le voyageur qui le dit. Dans l'app, le back-end ne
l'applique pas encore : il lui faut la détection de visages prévue dans
`docs/photos.md` (Vision côté iOS), qui dira aussi qu'une photo est de groupe —
trois visages ou plus.

### Deux formes acceptées pour une photo

Une entrée de `photos[]` est soit une source nue (URL ou `data:`), soit un
objet enrichi par l'analyse d'image. Les deux formes cohabitent dans le même
tableau.

```json
"photos": [
  "https://cdn.../plage.jpg",
  { "url": "https://cdn.../marche.jpg", "tape_corner": "bottom-left", "focus": "17% 50%" }
]
```

| Champ | Valeurs | Effet |
|---|---|---|
| `url` | URL absolue, ou `data:image/…;base64,…` | La photo. Seul champ obligatoire de la forme objet |
| `tape_corner` | `top-left`, `top-right`, `bottom-left`, `bottom-right`, `top` | Pose un scotch dans ce coin. **Absent = pas de scotch** : mieux vaut aucun scotch qu'un scotch sur un visage |
| `focus` | deux pourcentages, ex. `17% 50%` | Point que le recadrage préserve. Absent = recadrage centré |
| `fit` | `cover` (défaut), `contain` | `contain` : photo réduite, jamais rognée, cadre ajusté à l'image — photo de groupe, ou rognage au-delà d'un tiers. Pas de scotch sur une photo `contain` |

**L'agent ne remplit pas ces champs à la main.** Ils sortent de
`backend/src/services/photoAnalysis.ts`, qui mesure la photo : coin le plus
calme pour le scotch, zone la plus détaillée pour le recadrage. Voir
`docs/photos.md`.

## Couverture imprimée (Pumbo)

Le carnet se commande en **livre relié 154 × 216 mm** chez Pumbo. La
couverture d'un relié n'est pas une page du carnet : c'est une seule feuille —
plat verso, dos, plat recto — imprimée à part, sur un autre papier, et dont la
largeur dépend du nombre de pages. Elle ne passe donc pas par ce gabarit ni par
APITemplate : l'atelier la compose (`MemoBook Generator/public/couverture.js`)
et le navigateur l'enregistre en PDF au format exact.

**Les dimensions viennent de la fiche Pumbo, jamais d'un calcul.** L'outil de
couverture de Pumbo produit, pour une commande donnée, un script InDesign
(`.jsx`) qui donne tout ; l'atelier le lit (*Réglages → Fiche couverture
Pumbo*). Pumbo ne publie pas de barème : la largeur du dos dépend du nombre de
pages **et** du papier, et la seule valeur connue est celle-ci :

| Fiche du 07/10/2026 — relié 154 × 216 mm, 48 pages | mm |
|---|---|
| Feuille complète, fond perdu compris | 370 × 266 |
| Fond perdu, sur les quatre bords | 3 |
| Plat verso et plat recto (chacun) | 178 × 260 |
| Dos | 8 |
| Zone sûre : marge haut, bas et bord extérieur des plats | 19 |
| Côté dos (charnière) : marge imposée par MemoBook, pas par la fiche | 12 |

Les plats sont plus grands que la page (178 × 260 contre 154 × 216) : le carton
déborde du bloc et le papier se rabat dessus. D'où la zone sûre de 19 mm, qui
couvre ce rabat. Sans fiche importée, l'atelier part de celle-ci **et le dit** :
un dos de 8 mm sur un carnet de 80 pages serait faux. Une fiche par commande.

**Un seul style : celui de la couverture intérieure.**

- **Recto** — la photo de couverture en pleine page, fond perdu compris ; le
  titre du carnet en Playfair Display Black, blanc, en haut de la zone sûre ;
  le sous-titre sur un bandeau blanc incliné ; les voyageurs et les dates en
  bas. Un voile sombre sur le haut seulement, pour que le titre reste lisible
  sur un ciel clair.
- **Dos** — aplat encre, titre et voyageurs en blanc, **lisibles de bas en
  haut** (à la française). Pas de texte sous 6 mm de dos : il ne tiendrait pas
  lisible. Corps : 45 % de la largeur du dos, 11 pt au plus.
- **Verso** — le papier crème et « À suivre. », comme la quatrième intérieure,
  avec le logo et l'adresse en bas.

**La photo de couverture.** Celle que le voyageur désigne (étoile sur la
photo), sinon la plus adaptée au recto, qui est un portrait (format 0,68) :
jamais une photo de groupe (elle serait rognée), d'abord une photo qui tient
sous le plafond de rognage d'un tiers — une portrait, en pratique —, puis celle
qui atteint 300 dpi sur le recto, puis la mieux résolue. C'est **la même** que
la photo de couverture intérieure du carnet. L'atelier prévient sous 200 dpi,
et quand une photo de groupe désignée serait rognée.

**Le fichier.** Bouton « Générer la couverture » → un onglet avec la feuille et
ses repères (coupe, plis du dos, zone sûre — à l'écran seulement) → *Imprimer*
→ *Enregistrer au format PDF*, marges *Aucune*, *Graphiques d'arrière-plan*
coché. La taille de la feuille est imposée par la règle `@page`, au dixième de
millimètre (mesuré : 370,08 × 266,02 mm pour 370 × 266).

> **À trancher avant la première commande.** Le PDF intérieur rendu par
> APITemplate contient sa propre couverture et sa quatrième (première et
> dernière pages). Pour un relié, ces deux pages seraient imprimées *à
> l'intérieur*, en plus de la couverture. Il faudra un rendu « imprimeur » sans
> elles.

## Ce que le moteur de rendu reçoit

Le PDF sort d'un navigateur headless nourri de **deux chaînes** : le HTML du
gabarit et le CSS. Pas de build, pas de serveur de fichiers statiques, aucun
fichier joint à la requête. Ce dépôt est la seule source de vérité du template,
et ce qui n'entre pas dans ces deux chaînes n'existe pas au moment du rendu.

D'où la règle dont tout le reste découle — **le payload doit être
auto-portant** — et la raison de la tenir : une ressource non résolue
**n'échoue pas**. La police retombe sur une police système, l'image laisse un
cadre vide, l'API répond `success`. Ça ne se voit qu'à l'impression.

### CSS — aucune feuille externe

Tout le CSS voyage dans une balise `<style>` du document, ou en attribut
`style` sur l'élément. Ces deux lignes ne seront jamais résolues :

```html
<link rel="stylesheet" href="./carnet.css">
<link rel="stylesheet" href="/assets/print.css">
```

Ce que le moteur doit recevoir :

```html
<style>
  @page { size: 420pt 595pt; margin: 0; }
  .page { break-after: page; }
</style>
```

Le CSS reste **découpé en deux fichiers dans le dépôt**, pour rester éditable :
`fonts.css` (généré) puis `style.css` (écrit à la main). C'est
`loadTemplateCss()` qui les concatène dans cet ordre, et les deux consommateurs
— rendu local et appel à APITemplate — font exactement la même concaténation.
Envoyer `style.css` seul ferait perdre toutes les polices sans une seule
erreur.

Conséquence sur `style.css` : ce n'est pas du CSS nu mais un **fragment HTML**
— un `<meta name="viewport">` puis exactement une paire `<style>…</style>`, le
tout injecté verbatim. `npm run template:lint` refuse toute autre forme.

### Pas de marges blanches : les deux moitiés du réglage

Le carnet doit sortir **bord à bord**. Une bande blanche sur une feuille, c'est
un carnet bon à jeter chez l'imprimeur, et ça ne se voit qu'une fois le PDF
ouvert — l'API répond `success` dans tous les cas.

Le réglage vit à **deux endroits qui ne se parlent pas**, et les deux doivent
dire la même chose.

#### 1. Le panneau *Settings* du template hébergé — **jamais synchronisé**

`.github/workflows/sync-apitemplate.yml` pousse exactement trois champs :
`template_id`, `body` et `css`. **La géométrie de page n'en fait pas partie.**
Elle n'existe que dans l'interface d'APITemplate, onglet *Settings*, et elle
survit à toutes les synchros — y compris à celle qui vient de corriger le CSS.

À régler à la main, une fois, et **à revérifier après toute duplication de
template** (un template dupliqué repart des réglages par défaut) :

| Réglage | Valeur | Pourquoi |
|---|---|---|
| Paper Size | `Custom` | Aucun format prédéfini ne tombe sur la feuille voulue |
| Custom Paper Size | **148mm** × **210mm** | L'A5 de `print.json`, dans l'unité du panneau. Le champ accepte aussi `px`, mais un `px` y vaut 1/96ᵉ de pouce : `839px` donnerait 222 mm de large |
| Orientation | `Portrait` | La largeur est inférieure à la hauteur. Le panneau le rappelle : largeur > hauteur impose `Landscape` |
| Print background | `Yes` | Sans ça, aplats crème, ruban, étiquettes et grain **disparaissent** — la page sort blanche et les formes ne tiennent plus que par leur contour |
| Margin | `0` / `0` / `0` / `0` | **La cause n°1 des marges blanches.** Cette marge s'ajoute par-dessus le `@page` du CSS ; le contenu est alors réduit et recentré sur la feuille |

Ces valeurs sont le miroir exact de `print.json` (`widthPt` 420, `heightPt` 595,
`marginPt` tout à zéro, `printBackground` true). Si l'un des deux bouge, l'autre
doit bouger dans le même commit — c'est la même règle que pour le reste du
contrat.

#### 2. Les invariants CSS qui font qu'une page remplit sa feuille

Côté `style.css`, quatre règles portent tout le reste. Elles sont mesurées, pas
supposées : les valeurs ci-dessous sortent d'une mesure de la boîte `.page` en
média `print`, où la feuille vaut 560 × 793,3 px CSS.

```css
@page { size: 420pt 595pt; margin: 0; }          /* la feuille, et aucune marge */
html, body { margin: 0; padding: 0; }            /* rien autour des pages */
body { background: var(--mb-sheet); }            /* la feuille a la couleur du papier */
.page {                                          /* FIXE, et un point sous la feuille */
  width:  calc(420pt - 1pt);                     /*   dans les DEUX sens */
  height: calc(595pt - 1pt);
}
.page__content {                                 /* le point rendu à la marge : */
  padding: 30pt 29pt 29pt 30pt;                  /*   la colonne reste 360 × 535 pt */
}
```

| Ce qu'on écrit | Résultat chez APITemplate (feuille 419,04 × 594,96 pt) |
|---|---|
| page 419 × 594 pt | Correct : la page tient dans sa feuille dans les deux sens |
| page 420 × 595 pt | **Une feuille blanche derrière chaque page** — 29 feuilles pour 15 pages |
| `height: 100%` | **Le carnet s'effondre** : la page mesure 0 px |
| `padding` sur le conteneur | **Bande blanche en haut de chaque feuille** (64 px mesurés) |

**Pourquoi la page doit tenir dans sa feuille, dans les deux sens.** APITemplate
rend avec un **Chromium 97**, qui arrondit la feuille de 148 × 210 mm à
**419,04 × 594,96 pt**. Une page de 420 pt y est trop large de 0,96 pt. Ce vieux
moteur réagit en **réduisant tout le contenu** pour le faire tenir (−0,3 %,
mesuré : la page de 595 pt ne descend plus qu'à 593,3 pt sur la feuille), et sur
ce chemin il **intercale une feuille blanche derrière chaque page** qui force un
saut — toutes sauf la dernière, qui n'en force pas.

La preuve tient en deux PDF du même moteur, même gabarit, même CSS ; seule la
feuille change :

| Feuille | La page y tient ? | Feuilles produites |
|---|---|---|
| A4 (595 × 842 pt) | oui, dans les deux sens | **8 pour 8 pages** |
| A5 (419,04 × 594,96 pt) | non : 0,96 pt trop large | **29 pour 15 pages** |

**Le bug est invisible en local.** Notre Chromium, plus récent, ne fait ni cet
arrondi ni cette réduction : même en lui imposant la feuille exacte d'APITemplate,
il ne reproduit rien. Seul un PDF d'APITemplate peut valider un réglage de
géométrie — voir « Vérifier » ci-dessous.

> **Erreur corrigée.** Une première version de ce correctif (PR #95) ne retirait
> le point qu'à la hauteur, sur l'idée que la page dépassait de 0,04 pt vers le
> bas. Ce n'était pas la cause : avec la réduction, la page tenait déjà en
> hauteur, et les feuilles blanches sont restées. C'est la largeur qui dépassait.

**Le jeu ne doit pas se voir.** Il laisse apparaître la feuille, donc la feuille
porte la couleur du papier : `--mb-sheet`, la couleur *moyenne* de la page
mesurée sur le rendu (#f5ede6 en `preview`, grain compris ; blanc en `print`).
Mesurés à 600 dpi, le bas et le bord droit des pages sont uniformes. Le seul
endroit où ces 0,35 mm se lisent : à droite et sous une image **pleine page**
(couverture, quatrième avec photo), qui s'arrête un point avant le bord. C'est
le prix du correctif, sans commune mesure avec quatorze feuilles blanches.

**Le jeu appartient à la marge, pas au texte.** `.page__content` rend le point à
sa marge droite et basse : la colonne garde exactement ses 360 × 535 pt, à la
même place sur la feuille. Sans cette compensation, un point de colonne en moins
renvoyait des mots à la ligne — 13 lignes sur 317 dans les jeux de référence.
Avec elle, vérifié mot par mot sur les deux jeux de référence et sur le carnet
de Paros : **aucune ligne ne change**, et aucune des 925 boîtes de la colonne ne
bouge de plus d'un dixième de pixel par rapport à la CSS d'avant tout correctif.
Seuls bougent, d'un point, les éléments calés sur le bord de la page elle-même :
décor, mur de photos, couverture.

**`100vw` / `100vh`** sembleraient plus élégants qu'une taille fixe moins un
point. Ils ne le sont pas : leur valeur à l'impression varie selon les moteurs,
et ils ont la réputation de produire exactement ce bug-là.

**Pourquoi `height: 100%` ne marche pas ici**, alors qu'il a l'air plus souple :
un pourcentage se résout contre la hauteur du parent, et `html` / `body` n'en
déclarent aucune — le pourcentage retombe donc sur `auto`. Or tous les enfants
de `.page` sont en `position: absolute` (`.page__content`, `.page__decor`) :
il ne reste **aucun contenu en flux** pour donner une hauteur au bloc, qui
tombe à zéro. Une hauteur de page doit être une longueur absolue, comme la
feuille qu'elle représente.

De la même famille, à ne jamais introduire autour des pages :

- un **conteneur flex** avec `padding`, `gap` ou `align-items: center` : chaque
  valeur devient une bande blanche ou un décalage ;
- une **largeur en `px`** sur `.page` : la feuille est décrite en points, un
  mélange d'unités fait dériver la page d'un format à l'autre ;
- une **`box-shadow`** sur `.page` : inutile sur du papier, et un flou est de
  toute façon interdit ici (§ Règles d'images — il sort en aplat gris chez
  certains lecteurs PDF) ;
- une **`background-image`** sur `.page` pour « faire le papier » : elle est
  rastérisée entre 63 et 148 dpi. Le papier se fait avec un aplat, une teinte
  et le grain SVG inline, déjà en place dans `.page::before` / `.page::after`.

#### Vérifier

```bash
cd backend
npm run render:local -- --offline --png    # puis regarder les PNG
```

**Le rendu local ne suffit pas à valider la géométrie d'APITemplate** : ce n'est
pas le même moteur, et il ne fait pas les mêmes arrondis. Sur un PDF sorti
d'APITemplate, deux mesures tranchent :

```bash
pdfinfo carnet.pdf | grep -E "Pages|Page size"
```

- `Page size` doit être proche de **420 × 595 pt** — sinon c'est le panneau
  *Settings* ;
- `Pages` doit être égal au nombre de pages du carnet — s'il est presque double,
  la page ne tient plus dans sa feuille, en largeur ou en hauteur.

Et avant de conclure quoi que ce soit d'un PDF, **vérifier qu'il a été rendu avec
le gabarit qu'on croit**. La synchro lit le gabarit sur GitHub, qui sert
l'ancienne version d'un fichier jusqu'à cinq minutes après une fusion : un PDF
rendu dans la foulée sort avec l'ancienne CSS. Le 6 octobre, deux PDF rendus à
une heure d'écart, avant et après une correction, étaient identiques au pixel
près.

Le script compare la géométrie du PDF à `print.json` et échoue si elle s'en
écarte de plus d'un point. Une page qui sort à autre chose que 420 × 595 pt,
ou un PNG qui montre une bande claire sur un bord, se règle **toujours** par
l'une des deux moitiés ci-dessus.

### Polices — déjà inlinées, ne rien ajouter

`fonts.css` porte les `@font-face` en **base64**, générés par
`npm run fonts:build` (`backend/scripts/build-font-css.ts`) depuis les `.woff2`
versionnés dans `MemoBook Generator/templates/travel-journal/assets/fonts/`. C'est la forme
retenue en production : elle supprime la dépendance réseau au moment du rendu
et garantit le même tirage à chaque impression.

Deux familles sont réellement embarquées : **Playfair Display** (400/700/900)
et **Gloria Hallelujah** (400). Rien d'autre — et c'est là qu'est le piège.

`--mb-font-title` nomme `Hansley`, et `assets/fonts/Hansley.otf` est désormais
versionné. **Le titre retombe pourtant toujours sur Gloria Hallelujah** :
déposer le fichier ne suffit pas. `build-font-css.ts` part d'une liste de deux
familles Google, télécharge leurs sous-ensembles et ne lit que des `.woff2` —
un `.otf` posé à côté n'est jamais regardé. Exemple exact du défaut silencieux
décrit plus haut : rien n'échoue, la police est simplement absente du PDF.

Pour la brancher : déclarer Hansley comme face **locale** dans le générateur
(sans sous-ensemble ni `unicode-range`, puisqu'elle ne vient pas de Google),
la convertir en `.woff2` — l'`.otf` s'inline aussi, en `format("opentype")`,
au prix de quelques dizaines de kilo-octets — puis relancer `fonts:build`.

⚠️ **Deux familles de plus sont désormais proposées par l'app** et ne sont pas
ici : **Alegreya** et **Montserrat**, qu'emploient les assortiments « Éditorial »
et « Moderne ». Comme Hansley, elles retombent sur une police système tant
qu'elles ne sont pas inlinées — rien n'échoue, mais le carnet ne rend pas ce que
l'écran promet. Les ajouter à la liste de `build-font-css.ts`, en `.woff2`, puis
relancer `npm run fonts:build`.

Un `@import` Google Fonts fonctionne aussi :

```css
@import url('https://fonts.googleapis.com/css2?family=Playfair+Display:wght@400;700;900&family=Gloria+Hallelujah&display=swap');
```

mais il est réservé à un essai jetable : il rend le rendu dépendant du réseau,
intestable hors ligne, et ne doit pas être committé. Un chemin relatif vers un
`.woff2` du dépôt, lui, ne marche dans aucun cas.

### Images — URL publique ou base64

Chaque `src` est soit une URL absolue et publique, soit une donnée `data:` :

```html
<img src="https://…/souvenir-01.jpg">
<img src="data:image/jpeg;base64,/9j/4AAQSkZJRg…">
```

Pas de chemin local, pas de fichier joint, **pas d'URL signée à durée de vie
courte** : le moteur télécharge l'image quand il rend la page, parfois bien
après l'appel, et une signature expirée donne une page trouée sans message
d'erreur.

En beta, la voie retenue est le **base64** : elle évite d'ouvrir un bucket
public et d'en gérer les droits pour quelques carnets. Le JSON produit par
l'atelier porte alors directement les images encodées.

Deux limites à garder en tête avant la production :

- Le base64 gonfle la charge d'environ **un tiers**. Avec la règle des 1750 px
  (voir « Règles d'images »), une photo pèse ~0,6 à 1,2 Mo, donc ~0,8 à 1,6 Mo
  encodée : une trentaine de photos suffisent à porter le corps de requête à
  plusieurs dizaines de mégaoctets.
- **À VÉRIFIER** : la taille maximale de corps acceptée par APITemplate n'a
  jamais été mesurée. Tant qu'elle est inconnue, un carnet dense reste un pari.

Au delà d'une trentaine de photos, basculer sur des URLs publiques et durables
— Supabase Storage, ou le CDN Webflow que `WebflowAssetPublisher`
(`backend/src/services/webflow.ts`) alimente déjà.

### La bascule vers `create-pdf-from-html` — pas encore faite

La cible est d'envoyer le HTML brut à `POST /v2/create-pdf-from-html`, sans
template hébergé : une seule source de vérité, ce dépôt.

Ce n'est pas ce que fait le code aujourd'hui. `ApiTemplateRenderer`
(`backend/src/services/apitemplate.ts`) appelle
`POST /v2/create-pdf?template_id=…`, et `.github/workflows/sync-apitemplate.yml`
pousse le couple `body` / `css` par `POST /v2/update-template` à chaque `push`
sur `main`. Tant que les deux coexistent, le template vit à deux endroits — et
un rendu peut sortir d'une version que personne n'a relue.

**À faire** : porter le renderer sur `create-pdf-from-html`, retirer le
workflow de synchronisation, mettre `docs/apitemplate.md` d'accord. Aucune des
règles ci-dessus ne change au passage : elles valent déjà pour les deux
appels.

## Pièges à connaître

- **Jamais `null`.** Jinja2 imprime la chaîne littérale « None » dans le
  carnet. Omettre la clé plutôt que de l'envoyer vide.
- **Tableaux vides.** `[]` et l'absence du champ donnent le même rendu ; c'est
  volontaire, mais ça veut dire qu'une carte info vide n'apparaît pas du tout.
- **`body_html` est injecté tel quel** (`| safe`). Aucun script, aucun style
  en ligne, aucune balise autre que `<p>`, `<br>`, `<b>`, `<i>`, `<ul>`, `<li>`.

## Exemple minimal

```json
{
  "render_profile": "preview",
  "book_title": "Philippines",
  "authors": "Maÿlis, Claire et Augustin",
  "date_range": "février 2026",
  "cover_photo": "https://cdn.../cover.jpg",
  "intro_text": "<p>Il y a des voyages qu'on prépare pendant des mois…</p>",
  "days": [
    {
      "title": "36 heures plus tard, me voilà aux Philippines",
      "day_intro": {
        "day_number": "01",
        "location": "De Barcelone à Cebu",
        "date": "22-23 fev 2026"
      },
      "tag": "Top départ",
      "layout_story_opener": true,
      "body_html": "<p>Départ de Barcelone, sac sur le dos…</p>",
      "fun_facts": ["Les Philippines comptent plus de 7000 îles. Oui oui."],
      "photos": ["https://cdn.../jour01.jpg"]
    }
  ]
}
```

## Vérifier son rendu

```bash
cd backend
npm run template:lint                      # dialecte Jinja + invariants CSS
npm run render:local -- --offline --png    # PDF + un PNG par page
npm run render:local -- --data mon.json --validate --png
```
