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
> règles sont recopiées en code dans `MemoBook Generator/public/mise-en-page.js`
> (`pagesDeRecit`, `affecterPhotos`, `varierDoublesPages`, `placerPhotos`),
> testé par `backend/test/miseEnPageAtelier.test.ts`. Une règle ajoutée ici ne
> change donc rien aux PDF de l'atelier tant qu'elle n'y est pas portée — c'est
> ce qui s'est passé pour les trois règles de répartition, écrites le 05/10 et
> absentes du carnet généré le 06/10.

## Format

- Page **A5 : 420 × 595 pt** (1 unité Figma = 1 pt). L'aperçu sort sans fond
  perdu ; la **version imprimeur** ajoute **3 mm de fond perdu** sur les quatre
  bords — voir § « Fond perdu ».
  Géométrie dans `print.json`, maquette Figma `geIpjYxG3WCkGrgJFpkuVC`.
  En millimètres — l'unité que demande le panneau d'APITemplate — c'est
  **148 × 210 mm** : l'A5 exact vaut 419,53 × 595,28 pt, soit un demi-point
  d'écart. Les deux écritures désignent la même feuille, et doivent rester
  d'accord (voir § « Pas de marges blanches »).
- Marges de contenu : 30 pt en haut et en bas ; sur les côtés, **marges
  miroir** pour la reliure (Hugo, 12/10/2026) : **42,5 pt (15 mm) côté pli**,
  **28,3 pt (10 mm) à l'extérieur**. Le colophon est la page 1, une page de
  droite ; le gabarit pose `page--gauche` sur les pages paires (le pli à leur
  droite) et `page--droite` sur les autres (le pli à leur gauche). La colonne
  fait **349,2 pt** de large sur toutes les pages, seule sa place change. Les
  planches de photos gardent 14 pt au bord, plus l'écart des marges côté pli.
  Les décors (tracé pointillé, stickers) débordent volontairement.
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
| `sans_couvertures` | optionnel, booléen | Version imprimeur d'un relié : ni couverture ni quatrième, le livre s'ouvre sur le colophon. Voir § « Couverture imprimée (Pumbo) » |
| `page_blanche_finale` | optionnel, booléen | Une page blanche en fin de livre, pour un nombre de pages pair |
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
| Toujours la même ville, ou la même île (city trip, woofing, échange, stage) | À chaque étape qui emmène le voyageur dans de nouveaux lieux de la ville ; semaines / mois / années pour un long séjour | **La première carte montre le pays et y situe la ville. Les suivantes zooment sur la ville** : la même carte, enrichie au fil du livre, qui trace les déplacements — voir § « Les cartes », séjour en un seul lieu |
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
   | carte seule, pas de bande d'images | 500 |
   | carte + 2 photos | 300 |
   | carte + 2 photos + un `fun_facts` | 110 |

   Si le récit dépasse, **on allège la page avant de renoncer à la carte**,
   dans cet ordre : retirer le `fun_facts` (110 → 300), puis descendre sous
   deux photos (300 → 500). Une ouverture de chapitre vaut mieux sans encart
   que sans carte.
4. **Si le récit ne tient toujours pas**, layout par défaut, et le chapitre
   s'ouvre sans carte. On ne scinde pas une ouverture de chapitre en deux pages
   pour sauver la carte : le bandeau et la carte sur une page, la suite du
   récit sur une autre, ça ne se lit plus comme une ouverture.

En résumé : **la carte gagne sur l'encart et sur les photos, et perd sur le
récit.** Le texte du voyageur ne se raccourcit jamais pour faire entrer un
décor.

**Dans l'atelier** (`composerJours`, `mise-en-page.js`), pour un voyage dans un
seul pays fait de plusieurs lieux :

- **un chapitre s'ouvre** à la première étape, puis à chaque étape dont le lieu
  change (Paros → Naxos → Ios) ; la page d'ouverture est la première page de
  l'étape ;
- **le lieu doit être situé** par l'analyse d'étape (pays, coordonnées) ; sinon,
  page ordinaire ;
- **plafonds** : 500 signes avec la carte seule, 300 avec deux photos — dernier
  palier sans débordement au calibrage (marges de reliure, 12/10/2026). Une étape L ou XL se répartit déjà sur
  deux pages : son ouverture prend la carte et la suite du récit continue sur
  la page d'après, ce n'est pas « scinder pour sauver la carte » ;
- **une carte ne coûte jamais une photo**, ni une page de récit sans image à
  côté d'une planche : si l'ouverture de chapitre provoque l'un ou l'autre et
  que l'étape s'en passe sans carte, elle s'ouvre sans carte. Une étape d'une
  seule page avec une ou deux photos et plus de 300 signes garde donc ses
  photos plutôt que la carte ;
- **la carte** montre le lieu du chapitre avec son nom, et les lieux des
  chapitres précédents en petits points sans nom, reliés par le trajet ;
- **le cadrage suit ce que racontent les récits, pas les frontières**
  (`cadreDuVoyage`). Un voyage aux Cyclades montrait le continent grec et la
  Crète, avec une épingle en pleine mer : la carte se cadrait sur le pays
  entier, et les contours de 110 m n'ont même pas les Cyclades. Désormais :
  - **les lieux du voyage** : le lieu de chaque étape, et ceux où son récit
    emmène le voyageur (une excursion, une île d'escale), que l'analyse
    d'étape relève et situe (`lieux`). Une ville seulement citée ne compte pas ;
  - **le cadre** les entoure tous, dans le pays du chapitre, avec 20 % de marge
    de chaque côté et **un degré de côté au moins** (~110 km) : en deçà, on ne
    sait plus où l'on est. Jamais plus grand que le pays : un tour de la Grèce
    retrouve la carte de la Grèce ;
  - **le même cadre** pour tous les chapitres d'un pays : d'une carte à
    l'autre, on voit le trajet avancer ;
  - **les contours** viennent de Natural Earth 10 m (`assets/maps/detail/`,
    un fichier par pays, `backend/scripts/build-map-detail.ts`) : tous les
    pays qui touchent le cadre, coupés au bord et effacés en fondu. Sans ces
    fichiers, la carte retombe sur le pays entier.

- **séjour en un seul lieu** (tous les lieux tiennent dans ~30 km) : la
  première ouverture de chapitre montre le pays et y situe la ville, puis
  chaque étape qui emmène le voyageur dans de nouveaux lieux de la ville ouvre
  un chapitre sur la carte de la ville et de son parcours (§ « Les cartes »).
  Le parcours avance aussi aux étapes sans carte : leurs lieux reviennent en
  petits points sur la carte suivante.

  Dessin : `MemoBook Generator/public/carte.js`, recopie de `mapSvg.ts` —
  cadrage et contours compris — gardée identique par
  `backend/test/carteAtelier.test.ts`. Seule différence : l'atelier connaît
  les lieux par l'analyse d'étape, l'app par les `points` que l'agent pose sur
  chaque carte (§ « Les cartes »).

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

- `regions` : codes **ISO 3166-1 alpha-2**. Le premier est le pays du
  chapitre ; les suivants ne servent plus qu'au repli (voir plus bas). 175 pays
  disponibles.
- `points` : 6 maximum. **Les lieux où les récits du chapitre emmènent le
  voyageur** — l'île où il arrive, le village visité, la plage d'excursion —
  pas ceux qui sont seulement cités (la ville de départ du vol). Les
  coordonnées doivent être justes au centième de degré : un point mal placé se
  voit immédiatement, et à l'échelle d'un archipel un dixième de degré, c'est
  une île voisine.

**Le cadrage suit ce que racontent les récits, pas les frontières.** La carte
ne montre pas le pays entier, mais la zone que le voyage y parcourt : un voyage
aux Cyclades se cadre sur les Cyclades, pas sur le continent grec avec les
épingles en pleine mer. Le back-end (`expandMaps`, `voyageFrame`) :

- réunit les `points` de **toutes** les cartes du carnet dans le même pays ;
- les entoure avec 20 % de marge de chaque côté et **un degré de côté au
  moins** (~110 km), sans dépasser le pays : un tour de la Grèce garde la
  carte de la Grèce ;
- garde **le même cadre** pour tous les chapitres du pays : d'une carte à
  l'autre, on voit le trajet avancer ;
- dessine les contours de Natural Earth 10 m (`assets/maps/detail/`, qui a les
  petites îles) de tous les pays qui touchent le cadre, coupés au bord et
  effacés en fondu.

C'est pourquoi les `points` comptent plus que `regions` : ce sont eux qui
disent où le voyage se passe. Sans contour détaillé pour le pays, la carte
retombe sur le pays entier, cadré sur le premier code de `regions`.

### Le trait des trajets : le moyen de transport

Chaque trajet se dessine selon la façon dont le voyageur l'a fait, telle que le
récit la raconte (`mode` sur le point d'arrivée) :

| Moyen | Trait |
|---|---|
| avion | **courbe en pointillés** — l'arc d'un vol, bombé vers le haut |
| bateau (ferry, navette) | **ligne droite en pointillés** |
| terre (voiture, bus, train, scooter, à pied) | **ligne droite pleine** |
| inconnu | ligne droite en pointillés ; terre sur une carte de ville |

On ne devine pas : si le récit ne dit pas comment on est passé d'une île à
l'autre, le mode reste inconnu. Dans l'app, l'agent le pose sur chaque point
(`mode`) ; dans l'atelier, il vient des `trajets` de l'analyse d'étape. Dessin :
`segmentsDuTrajet`, dans `carte.js` et `mapSvg.ts` (gardés identiques).

### Séjour en un seul lieu : le pays, puis la ville

Quand **tous les points du carnet dans un pays tiennent dans ~30 km** (0,3° de
côté) — un city trip, une île —, les cartes changent de rôle :

1. **La première carte du pays montre le pays entier et y situe la ville.**
   Elle porte un seul point, **la ville elle-même** (« Paris », pas « Louvre ») :
   c'est elle qui sera épinglée et nommée. Le pays, c'est son territoire
   principal et les terres proches (la Corse), pas l'outre-mer.
2. **Les suivantes zooment sur la ville** : le cadre entoure tous les lieux du
   séjour, avec **3 km de côté au moins**. Chacune porte, dans l'ordre du
   parcours, les lieux où le récit du chapitre emmène le voyageur — **3 au
   plus**, situés **au millième de degré** : à cette échelle, un centième de
   degré, c'est un kilomètre, la mauvaise rue. La carte :
   - nomme les lieux du chapitre (épingles) ;
   - garde ceux des chapitres précédents en petits points, nommés en petit ;
   - **trace le parcours** qui les relie, dans l'ordre ;
   - écrit le nom de la ville en tête et pose une barre d'échelle (« 1 km »).

**Ni rue ni fleuve** : les données mondiales disponibles hors ligne (Natural
Earth) sont trop grossières à cette échelle — la Seine y passait au nord de la
tour Eiffel. Une carte qui place un monument sur la mauvaise rive se voit plus
qu'une carte sobre. Seuls les points, exacts, s'y dessinent ; la côte reste
quand la ville en a une.

> ⚠️ **Non validé — à reprendre.** Le 08/10/2026, le fondateur juge ces cartes
> de ville insuffisantes sans rues ni fleuves (« ce point ne me convient pas,
> on va sûrement revenir dessus »). La piste : des données OpenStreetMap
> (rues, eau) à la génération, avec la mention « © OpenStreetMap » imprimée.

**Quand ouvrir un chapitre** dans un tel carnet : à chaque étape dont le récit
emmène le voyageur dans des lieux de la ville où il n'était pas encore allé,
quand le barème le permet (§ « Chapitre ou journée ordinaire »). Une journée
sans nouveau lieu reste une page ordinaire.

Le back-end projette les contours et les points avec **la même**
transformation (Mercator), puis insère le SVG dans `map_svg`. Ils ne peuvent
donc pas diverger. Voir `backend/src/services/mapSvg.ts` ; l'atelier en a une
recopie (`carte.js`), gardée identique par `backend/test/carteAtelier.test.ts`.

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
| Ratio photo / texte | 50 % | **Les cinq paliers**, voir § « Le ratio texte / photo » plus bas. C'est le nombre de pages et de photos qui s'adapte, jamais le texte | Rendu |
| Nombre de page cible | 60 | Niveau de détail des textes, regroupement des étapes | Rendu |
| Fun facts | ON | `fun_facts` — voir le dosage plus bas | Rendu |
| Quiz | ON | `quiz` | Rendu |
| Pointillés | ON | La **réglure** du papier, `.mb-note__rules` — `rules_enabled: false` la retire (`body.sans-reglure`), le rythme vertical ne bouge pas | Rendu |
| Décorations & stickers | 2 | Les **stickers** de la bibliothèque (2 par double page au plus, autant que le quota en permet) et le **tracé pointillé** — `decoration_quota: 0` retire les deux (`body.sans-decor`). Le scotch n'en dépend plus : l'habillage des photos est toujours complet | Rendu ; bibliothèque de 44 dessins importée de Notion (`assets/stickers/`) |
| Typographies (assortiment) | Carnet de voyage | Les quatre tokens ci-dessous d'un bloc | **À construire** — l'app n'expose plus quatre réglages mais **quatre assortiments** (`docs/reglages-utilisateur.md`) : Carnet de voyage, Éditorial, Moderne, Manuscrit. Le payload, lui, reste quatre champs |
| ↳ titres | Playfair | `--mb-font-display` | **À construire** |
| ↳ sous-titres | Hansley | `--mb-font-title` | **À construire** — `Hansley.otf` versionné mais pas inliné, repli sur la manuscrite |
| ↳ textes | Gloria Hallelujah | `--mb-font-hand` | **À construire** |
| ↳ fun facts | Playfair | Pas de token dédié : partage `--mb-font-display` | **À construire** — créer `--mb-font-facts` |
| Zones libres | ON | **Trois pages réglées** après la dernière étape, avant la quatrième — `pages_libres: 3` (`mb_page_libre`), 0 si coupé. La zone blanche en fin d'étape reste à construire | Rendu (pages de fin) |
| Mot fléché | ON | Grille générée à la commande, posée en fin de carnet | **À construire** |

**Deux « pointillés » à ne pas confondre.** Le réglage porte sur la **réglure**
— les lignes en pointillé sous le texte. Le **tracé pointillé du voyage** (voir
plus bas) est un décor de bas de page : il relève du quota de décorations, pas
de ce booléen.

**Les mêmes réglages, les deux PDF.** L'atelier (`reglagesDuCarnet`,
`app.js`) et l'app (`backend/src/services/bookSettings.ts`, appelé par
`jobs/structure.ts`) appliquent les mêmes, au même endroit du payload :
`rules_enabled`, `decoration_quota`, et le ratio texte / photo — par **le même
code**, `photoRatio.ts`, dont l'atelier reçoit une copie générée
(`public/ratio-photos.js`, `npm run ratio:build`). Les réglages
marqués « à construire » demandent un champ au schéma, une lecture par le gabarit, et cette
table mise à jour dans le même commit. Tant que ce n'est pas fait, l'agent ne
produit rien pour eux et l'app ne devrait pas les proposer.

## Le ratio texte / photo

Le voyageur règle la part de surface qu'occupent les photos : **0, 25, 50, 75 ou
100 %** (`photo_ratio` à la racine du payload). Le détail, les mesures et le
rapport des cas limites sont dans **`docs/ratio-texte-photo.md`** ; ici, le
contrat de mise en page.

> **La règle absolue.** Le texte validé par le voyageur ne bouge jamais : ni
> coupe, ni reformulation, ni troncature, ni corps réduit. C'est le **nombre de
> pages** et le **nombre de photos** qui s'adaptent au texte. Jamais l'inverse.

**Ce qui se mesure** : `ratio = surface photo / (surface photo + surface
texte)`, sur **l'ensemble des pages d'une étape**. Surface photo = les
emplacements `mb-photo` (le contour dessiné ne compte pas). Surface texte = ce que `mb-note` occupe
réellement. Les éléments fixes sont hors du calcul — bandeau, titre, étiquette,
météo, carte fun fact, carte de chapitre, décor. Tolérance ±5 points.

| Ratio | Corps de texte | Photos minimum | Layouts |
|---|---|---|---|
| **0 %** | intégral | 0 | `layout_story_full` (récit pleine page, réglure jusqu'en bas), `layout_chapter_map` aux ouvertures — une carte n'est pas une photo |
| **25 %** | intégral | 1 | Une photo par page de récit au plus |
| **50 %** | intégral | 2 | Le composeur choisit : collage, bande, trios, récit autour d'une grande photo, planches en fin d'étape |
| **75 %** | intégral | 3 | Idem, avec plus de photos — celles qui ne tiennent pas à côté du récit vont sur les planches de fin d'étape |
| **100 %** | **aucun** | selon les pages | `layout_photo_wall_intro` (bandeau, fun fact, 4 photos au plus) puis `layout_photo_page` |

**Qui compose (Hugo, 13/10/2026).** Le module de ratio dit **combien de photos**
chaque étape garde (`photosRequired`) ; le **composeur** (`mise-en-page.js`,
`composerJours`) met en page ces photos avec toutes ses règles — structure de
l'étape, pages paires, planches, carte de chapitre, décors, fun facts. Les
photos de trop s'écartent dans l'ordre habituel (floues ou sombres, doublons
d'une scène, moins bien notées). **L'atelier et l'app composent avec le même
code** : l'app charge le composeur de l'atelier (`backend/src/services/bookComposer.ts`).
Jusqu'au 13/10, le module de ratio recomposait lui-même chaque étape après le
composeur, et effaçait tout son travail ; la hauteur de bande (`band_scale`)
qu'il calculait n'est plus posée.

**À 100 %, aucun `mb-note` n'est émis.** La première page de l'étape
(`layout_photo_wall_intro`) garde le bandeau jour · lieu · date et la carte
`fun_facts` si le carnet les a allumés — une étape sans bandeau ne se lit plus
comme une étape. Les autres pages sont des planches. Le récit du voyageur
**sert de matière** au fun fact : il n'apparaît pas tel quel.

**Pas de légende**, ni de page ni par photo (Hugo, 12/10/2026) — y compris à
100 %, où la spécification du ratio en demandait. Les deux décisions ne peuvent
pas tenir ensemble ; celle du gabarit l'emporte. Voir
`docs/ratio-texte-photo.md` § « Ce qui reste à construire ».

**Les conflits, et comment ils sont tranchés.**

- **Texte très court à ratio bas** (quelques lignes à 25 %) : le minimum de
  photos gagne sur le ratio, et le dépassement est assumé. La page ne doit pas
  laisser de grande zone blanche : les photos s'agrandissent jusqu'au plafond que
  le texte leur laisse, et une bande à sa hauteur de conception ou au-dessus
  « porte la page » au sens de § « Les deux bornes basses ». L'inspecteur marque
  le cas « dépassement assumé », pas « erreur ».
- **Le nombre de photos ne change pas pour remplir**, pour rester cohérent avec
  le nombre annoncé dans le chat.
- **Le texte ne tombe jamais sur une page sans place prévue** : si `mb-note`
  déborde, on ajoute une page, on ne coupe pas.
- **Un palier ne demande jamais moins de photos que le palier d'en dessous** :
  le réglage doit se lire comme un curseur.

**Le nombre exact de photos** sort de `photosRequired`
(`backend/src/services/photoRatio.ts`), **la même fonction** qui alimente le
message du chat et la composition des deux PDF. Un écart entre le nombre annoncé
au voyageur et le nombre posé dans le carnet est un bug.

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
| `layout_chapter_map` | Carte de la région à droite, récit et carte info à gauche ; une photo au-dessus de la carte, ou deux en bas sous un récit court | Ouverture d'un chapitre, **quand un lieu est nommé dans le récit** — voir la table plus haut | 0–2 | sous S à M, **selon la carte info et les photos** |
| `layout_hero_top` | Grande photo en tête, récit dessous | Une photo iconique porte la journée | 1 | sous S, S |
| `layout_split_left` | Carte info à gauche, récit en colonne à droite, puis deux photos en bas | Un fait à mettre en avant et deux belles images | 2 | S, M — **S seulement avec un fun fact** |
| `layout_collage` | Récit pleine largeur puis 2 ou 3 photos inclinées en bas | Journée dense visuellement | 2–3 | S, M |
| `layout_trio_portrait` | **Page de suite seulement.** Récit court en tête, réglure prolongée jusqu'aux photos, puis trois photos en cascade : une portrait en haut, deux portraits en bas qui la chevauchent à peine, tracé pointillé derrière | Fin d'étape courte avec trois photos en portrait | 3 | sous S, S partiel — **410 en 2 paragraphes** |
| `layout_trio_landscape` | Le même, avec une **photo paysage en haut** (format 1,6) ; les deux du bas restent des portraits | Fin d'étape courte avec une paysage et deux portraits | 3 | idem |
| `layout_recit_photo` | **Maquette faite à la main (Banaue).** Quelques lignes pleine largeur, puis le récit en colonne à gauche d'une grande photo en hauteur qui flotte à droite, inclinée, avec son **étiquette de titre** (`label`). Un fun fact devient un **post-it « Infos »** en bas à gauche | Une page à une photo en portrait (format < 0,77) — bandeau ou suite | 1 | S, M ; 800 en page de suite avec le post-it |
| `layout_photo_page` | **Page de photos seules**, sans récit ni bandeau, **sans légende**. De 3 à 5, une planche bord à bord — à 5, en rangées ou en deux colonnes décalées (`planche_colonnes`), tour à tour ; 1 ou 2, une page d'album (tirages inclinés, tracé pointillé). Avec `pleine_page`, une seule photo bord à bord, sans cadre | **Toujours en fin d'étape**, après le récit — voir § « Structure d'une étape » | 1–5 | aucune — le récit n'est pas rendu |
| `layout_photo_wall_intro` | **La planche qui ouvre une étape** : bandeau en tête, photos sur le reste de la feuille, carte fun fact. Pas de légende non plus | Première page d'une étape à 100 % de photos | 1–4 | aucune — le récit n'est pas rendu |
| `layout_story_full` | Récit pleine page, réglure jusqu'en bas, **aucune photo** | Palier 0 % du ratio texte / photo | 0 | jusqu'à 1140 (bandeau) / 1640 (suite) |
| *(par défaut)* | Récit, puis carte info et photo flottantes en bas de page | Ouverture de journée, cas le plus courant | 0–1 | S, M |

Les tailles exactes, et le plafond mesuré de chaque configuration, sont en
§ « Longueur des textes ».

Le cas par défaut couvre aussi `layout_story_opener` et `layout_story_facts` :
le validateur exige au moins un drapeau, n'importe lequel de ces deux convient.

**Les trios** (maquettes du 08/10/2026) ne s'emploient **jamais sur la
première page d'une étape** : elle porte le bandeau jour · lieu · date, et les
trois photos n'auraient plus leur hauteur — le validateur le refuse. L'atelier
les choisit seul (`trioDe`, `mise-en-page.js`) : page de suite, trois photos,
410 signes en deux paragraphes au plus, pas de photo de groupe, et une variante
où **aucune des trois ne dépasse le plafond de rognage** — sinon la page reste
un collage. Entre les deux variantes, celle qui rogne le moins : la paysage va
en haut s'il y en a une. Pas de fun fact sur un trio : il n'y a pas de place
prévue.

**La condition du lieu sur `layout_chapter_map`.** Ce layout se choisit à
l'ouverture d'un chapitre, mais seulement **si le récit nomme un lieu** : c'est
ce lieu qui alimente `map.points`, et le layout exige `map`. Un chapitre qui
s'ouvre sans lieu identifiable n'a rien à cartographier — une carte sans point,
ou pointée au hasard, se repère immédiatement quand on connaît le pays. Dans ce
cas, ouvrir le chapitre avec un autre layout et garder `layout_chapter_map`
pour le premier chapitre où un lieu est nommé.

## Le tracé pointillé du voyage

**Un par double page au plus** (Hugo, 12/10/2026). L'atelier choisit la page —
une page qui a une bande de photos, de préférence celle de gauche — et la
variante, tour à tour (`day.trace` : `a`, `b`, `c` ou `aucun`,
`decorerDoublesPages`). Sans `trace` dans le payload, le gabarit ne le pose que
sur les pages de gauche, ce qui garde la même règle.

Décor en trois boucles. **Il ne passe que derrière des photos,
jamais derrière du texte**, qu'il rendrait illisible.

Pour le garantir, le tracé est dessiné **dans la bande de photos** (macro
`mb_trace`, appelée par `.mb-gallery`) et positionné par rapport à elle — pas
par rapport à la page. Où que la bande se trouve, il la suit, et il ne monte
jamais au-dessus de 112 pt quand la bande en fait au moins 160. Seuls les
layouts qui ont une bande en portent donc un : `layout_split_left`,
`layout_collage`, les deux trios (`.mb-trio`) et `layout_chapter_map` avec deux
photos ou plus. Le layout par
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
bandeau plus celle d'une page de suite, mesurées sur la colonne de 360 pt.
Les marges de reliure (12/10/2026) ont ramené ces deux pages à 540 et 860 ; le
barème, lui, n'a pas bougé : c'est une **cible de rédaction**, et l'étape prend
désormais autant de pages qu'il lui faut (six au plus). Ce sont les plafonds
par page, ci-dessous, qui décident des coupes.

### Ce que chaque page accepte réellement

Plafonds relevés par `backend/scripts/calibrate-lengths.ts`, qui rend chaque
layout à longueur croissante et note le point où la bande de photos se comprime
ou le texte passe sous la marge. **Ils ne se devinent pas** : les redériver, c'est
relancer le script.

| Configuration | Plafond | Tailles acceptées |
|---|---|---|
| `layout_photo_page` | 0 — aucun récit rendu | — |
| `layout_chapter_map` + fun fact + ≥ 2 photos | 110 | sous S |
| `layout_split_left` + fun fact | 230 | sous S, S partiel |
| `layout_chapter_map` + ≥ 2 photos, sans fun fact | 300 | sous S, S partiel |
| `layout_hero_top` | 380 (660 en page de suite) | sous S, S |
| `layout_recit_photo` | 560 (880 en page de suite) | S, M |
| `layout_recit_photo` avec le post-it « Infos », page de suite | 800 | S, M |
| `layout_trio_portrait`, `layout_trio_landscape` — page de suite seulement | 410, **2 paragraphes** | sous S, S partiel |
| `layout_chapter_map` sans photos, ou une photo au-dessus de la carte | 500 | S, M partiel |
| `layout_story_*`, `layout_collage`, `layout_split_left` sans fun fact | 540 | S, M |
| `layout_story_*` portant un `prompt` | 740 | S, M |
| **page de suite** (sans `day_intro`), tout layout de récit | 860 | complète L et XL |
| `layout_story_full` — palier 0 %, aucune photo | 1140 (bandeau) / 1640 (suite), **5 paragraphes** | le récit occupe la feuille entière |
| **corps serré** (`taille_texte: "serre"`), tout layout | plafond × 1,08 | — |

Recalibré le 12/10/2026 après les marges de reliure : la colonne passe de 360 à
349 pt, soit environ 3 % de signes en moins par ligne pleine largeur et 5 % dans
les colonnes étroites (carte, carte info). Le récit qui contourne une grande
photo n'y perd presque rien : il garde ses plafonds.

**Un couple, pas un nombre.** Ce n'est pas une longueur seule qui a été mesurée
mais un couple (caractères, paragraphes) : chaque `<p>` est suivi d'une ligne
vide, et celle de trop pousse le contenu sous la marge. 540 caractères tiennent
en **2** paragraphes et débordent en 3 ; 860 tiennent en **4** et débordent en 5.

### Corps ajusté d'un point

Hugo, 12/10/2026 : le corps et l'interligne sont **légèrement ajustables**
(±1 pt) pour remplir une page. Le composeur de l'atelier pose
`taille_texte` sur **toutes les pages de récit de l'étape** — un récit ne change
pas de corps en tournant la page :

| `taille_texte` | Corps | Quand |
|---|---|---|
| *(absent)* | 12 pt | Le cas courant |
| `serre` | 11 pt | Le récit dépasse de **8 % au plus** ce que ses pages tiennent : en 11 pt, il tient sur une page de moins, et l'étape reste paire avec moins de pages (`structurerEtape`). Le 11 pt tiendrait bien plus (+30 à +40 % mesurés) ; 8 % est la limite qu'on s'impose pour qu'il ne paraisse pas tassé |
| `ample` | 13 pt | Chaque page de récit de l'étape est remplie à **moins de 45 %**, sans photo, sans encart, sans carte pour combler (`corpsAmple`) |

L'interligne et la réglure suivent le corps : `.page--serre` et `.page--ample`
redéclarent `--mb-body-size` **et** `--mb-line` (une variable CSS se calcule là
où elle est déclarée). Le validateur accepte 8 % de plus sur une page serrée
(`SERRE_FACTOR`, `pageCapacity`).
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

- la première porte `day_intro` et le `title` — elle plafonne à 540 ;
- la seconde a un `title` **vide** et **pas de `day_intro`** : c'est ce qui lui
  rend les 320 caractères du bandeau, et la porte à 860.

C'est ce couple que le validateur reconnaît comme une étape unique : toute entrée
sans `day_intro` prolonge la précédente.

**Le récit se répartit à parts égales sur ses pages** (Hugo, 12/10/2026) :
chaque page reçoit une part à la mesure de ce qu'elle tient — la colonne
étroite d'une ouverture de chapitre en prend moins qu'une page de suite pleine
largeur. Un récit qui dépassait à peine d'une page ne laisse plus une page pleine
et une page presque vide (`repartirRecit`, atelier). La coupe se fait sur une
fin de phrase, même un peu plus loin qu'une virgule ; jamais au milieu d'un mot.

### Décisions de design du 12/10/2026

Les réponses de Hugo aux questions de design, à tenir partout (atelier, agent
de mise en page, gabarit) :

| Sujet | Décision |
|---|---|
| Pages par étape | **6 au plus** — sauf si le récit seul en demande davantage |
| Début d'étape | **Toujours sur une page de gauche** |
| Pages de photos en fin d'étape | **Une double page au plus** (2 pages, 10 photos) |
| Photos de trop | On écarte d'abord les **floues ou sombres**, puis les **doublons d'une scène** (on garde la mieux notée), puis les **moins bien notées** |
| Paragraphe sur deux pages | Oui, **coupé sur une fin de phrase** |
| Page de suite | **Rien** ne rappelle l'étape : le texte continue |
| Corps et interligne | **Légèrement ajustables** (±1 pt) pour remplir une page — § « Corps ajusté d'un point » |
| Étiquette de titre sur une photo | **Écrite par l'IA, une par double page au plus**, modifiable par le voyageur |
| Habillage des photos | **Toujours** contour dessiné, inclinaison et scotch (le cadre blanc est remplacé par un contour noir le 13/10/2026) |
| Légendes des pages de photos | **Jamais** |
| Photo en pleine page | **De temps en temps** : une par chapitre au plus |
| Stickers | **Bibliothèque dessinée**, liés au récit, selon le réglage « Décorations », 2 par double page au plus |
| Tracé pointillé | **Un par double page au plus**, derrière des photos |
| Fun fact | **Post-it « Infos » partout**, à peu près un toutes les trois pages (13/10/2026) — § « Les fun facts » |
| Rythme | Jamais deux fois le même design sur une double page |
| Carte de chapitre | À chaque nouveau lieu |
| Marges | **Plus large côté reliure** : 15 mm côté pli, 10 mm à l'extérieur — § « Format » |
| Fin du carnet | **3 pages libres réglées** pour écrire (réglage « Zones libres », `pages_libres`) |

### Retouches du 13/10/2026

Hugo a relu son PDF (175d5716). Ce qui change, et où :

| Sujet | Décision | Où |
|---|---|---|
| Page de garde | « …par une feuille blanche » descend dans le dernier tiers de la page, au-dessus des mentions | `.mb-colophon__closing` |
| Ruban « jour » | **Plus court** (70 pt visibles au lieu de 88) et **#F7E5E1**. L'encombrement du bandeau, lui, ne change pas : les capacités de récit en dépendent | `.mb-ribbon__shape`, `--mb-ribbon-fill` |
| Encarts lieu / date | Un **2ᵉ contour intérieur**, surlignage #FDE5D1 à 70 % | `.mb-field::after`, `--mb-field-highlight` |
| Aplats colorés en version imprimeur | Le ruban et le surlignage **gardent leur couleur** : ce sont des choix de couleur, pas des fonds qui imitent le papier (règle des aplats, `style.css`) | — |
| Cadre des photos | **Plus de passe-partout blanc** : un contour noir tracé à la main, tourné de 2° par rapport à la photo, qui déborde de 3,5 pt — § « L'habillage des photos » | `mb_cadre`, `.mb-photo__cadre` |
| Texte et réglure | Le récit **se pose sur la ligne** : la réglure remonte de 0,185 em (~0,5 pt sous la ligne de base), l'interligne et les capacités ne changent pas | `--mb-rule-lift` |
| Planche de cinq photos | Une **variante en deux colonnes décalées**, sans inclinaison, en alternance avec les rangées | `planche_colonnes` |
| Carte de chapitre | **Une photo au-dessus de la carte** quand la page en porte une ; deux photos restent dans la bande du bas, sous un récit court | `.mb-chapter__aside` |
| Pages de photos | Toujours **après** le récit de l'étape (déjà le cas depuis le 12/10) | § « Structure d'une étape » |

### Structure d'une étape

Consignes de Hugo, 12/10/2026, après une étape sortie en « page de texte, page
de photos, page de texte » sur trois pages :

1. **Le texte d'une étape n'est jamais séparé.** Ses pages de récit se suivent ;
   les pages de photos seules (`layout_photo_page`) viennent **toujours après le
   texte**, jamais entre deux de ses pages. Le validateur le refuse.
2. **Chaque étape a un nombre de pages pair** — une étape tient sur des doubles
   pages. Le validateur avertit d'une étape impaire ; l'atelier ne laisse une
   étape impaire que s'il n'a pas de quoi remplir une page de plus sans inventer
   (une seule phrase, aucune photo).
3. **Deux scénarios, en alternance** quand les deux donnent le même nombre de
   pages :
   - **A** — toutes les photos avec le texte, réparti à parts égales sur ses
     pages ; pas de page de photos ;
   - **B** — le texte avec une ou deux photos par page, puis une ou plusieurs
     pages de photos en fin d'étape (deux à la suite forment une double page de
     photos, ce qui est permis en fin d'étape).

   L'atelier alterne d'une étape à l'autre **dans la même situation** — récit
   tenant sur une page, nombre de pages naturel impair, ou pair —, en
   commençant par A (`structurerEtape`, `mise-en-page.js`).
4. **Étape courte** (le récit tient sur une page) : la première fois, le récit se
   partage sur **deux pages** (A) ; la fois suivante où la situation se
   reproduit, tout le texte sur une page avec une ou deux photos, puis une page
   « photos + stickers » (B) ; puis on alterne. Une étape courte sans photo
   n'a que A.

**Plafonds.** Une étape tient sur **six pages au plus**, dont **deux pages de
photos** (une double page) — à moins que le récit seul n'en demande
davantage. Quand ses photos n'y tiennent pas, l'atelier en écarte, la pire
d'abord (`trierPourEcarter`) : celles qui échouent au contrôle qualité (netteté
sous 40, luminance sous 45 ou au-dessus de 215, plus d'un quart de pixels
brûlés — les seuils de la couverture), puis, dans une même `scene`, toutes sauf
la mieux notée, puis par note `couverture` croissante. Le journal de l'atelier
le dit.

**Début d'étape à gauche.** Le colophon est la page 1, à droite : ce qui le
suit avant la première étape (introduction) doit faire un nombre pair de
pages. Sinon, une page libre réglée les complète (`pages_libres_avant: 1`). Avec
des étapes au nombre de pages pair, chacune commence alors à gauche. Le
validateur avertit d'une première étape à droite.

**Photo en pleine page**, une fois par chapitre (une suite d'étapes au même
lieu) au plus : sur une page de photos de fin d'étape qui n'en porte qu'une,
si la photo est notée 9 au moins, n'est pas une photo de groupe, se rogne de
moins d'un tiers au format de la page et tient 200 dpi sur 154 × 216 mm
(`pleine_page: true`). ⚠️ Elle s'arrête au bord de la page : à vérifier, le fond
perdu que Pumbo demande pour les pages intérieures.

**L'habillage des photos : toujours tout** (Hugo, 12/10/2026). Chaque photo a
son contour, son inclinaison et son scotch — les planches aussi, moins
inclinées (±1,2°), sauf la planche en colonnes, droite. L'atelier pose le coin
du scotch tour à tour (`habillerPhotos`). Seules exceptions : la photo réduite
sans être rognée (`contain`), sans scotch, dont le contour épouse l'image
(`tirage`), et la pleine page, sans rien.

**Le contour** (13/10/2026, d'après le carnet de Maylis) : pas de passe-partout
blanc, la photo remplit son emplacement ; un trait noir tracé à la main (trois
tracés, `#mb-cadre-a|b|c`, choisis d'après l'URL) l'entoure à 3,5 pt, tourné de
±2° par rapport à elle. Il ne prend aucune place : l'emplacement — et la
surface que compte le ratio photo / texte — est celui de la photo seule. Entre
deux photos d'une planche, 11 pt, et 14 pt dans une bande (où elles
tournent davantage), pour que deux contours ne se croisent pas.

**L'étiquette de titre : une par double page au plus**, sur la photo la mieux
notée qui en a une. Celle que le voyageur écrit sous la photo dans l'atelier
(30 signes) passe avant la `legende` de l'IA.

**Les stickers** viennent d'une **bibliothèque dessinée** : la base Notion
« Éléments graphiques », copiée et préparée dans `assets/stickers/` (44 dessins,
19 familles ; format et procédure d'ajout dans `assets/README.md`). Un sticker
est posé quand un de ses mots apparaît, en **mot entier**, dans le titre ou le
lieu de l'étape (lien fort), sinon dans son récit ou les scènes de ses photos
— deux par double page au plus, autant que le réglage « Décorations » en
permet, **jamais deux fois la même famille** dans le carnet (un seul sac à
dos, quelle que soit la variante). Trois styles se mêlent — sticker découpé,
dessin, trait —, qui ne règlent que la taille : 90 à 140 pt, jamais plus que
150 dpi ne le permet. Places : la page d'album, le bas de la colonne de
`layout_recit_photo` quand le récit laisse la place du post-it, la zone du bas
d'une page de récit ordinaire — tant qu'aucun post-it ne l'occupe — et jamais
dans le pli. Les **personnages de dos** sont réservés : ils se choisiront
d'après l'apparence des voyageurs, pas d'après le récit.

**La page « photos + stickers ».** `layout_photo_page` accepte désormais une ou
deux photos : une page d'album, les tirages inclinés et le tracé pointillé entre
eux, et un sticker dans le blanc que laissent les photos. De trois à cinq
photos, c'est la planche bord à bord habituelle.

**Ce qu'il faut éviter, par ordre de coût** : un nombre de pages impair ; une
page de plus que nécessaire ; une page de récit sans photo quand l'étape en a ;
une page de photos qui n'en porte qu'une (puis deux) ; un récit étiré d'une
page pour une étape qui en a déjà deux ou plus — ce n'est qu'un recours.

### Associer les photos au récit

Une photo va sur **la page du passage qu'elle illustre** : si le texte d'une
page raconte la sieste sur la plage, les photos de la plage sont sur cette page.
Et les photos **prises au même endroit** — même arrière-plan — restent
ensemble.

Ni l'un ni l'autre ne se devine de l'ordre des fichiers. Il faut regarder les
photos : c'est l'**analyse d'étape**, faite par le modèle avant la mise en page.
Pour chaque étape, il reçoit le récit découpé en paragraphes numérotés et une
vignette de chaque photo, et rend, sans rien réécrire :

| Champ | Usage |
|---|---|
| `lieu` (`nom`, `pays`, `lat`, `lon`) | La carte de chapitre. `null` s'il n'est pas sûr : pas de carte |
| `photos[].paragraphe` | Le passage que la photo illustre : elle vise la page qui porte ce paragraphe |
| `photos[].scene` | Le lieu de prise de vue, même libellé pour le même arrière-plan : ces photos restent ensemble |
| `photos[].personnes` | Trois visages ou plus : photo de groupe, jamais rognée |
| `photos[].legende` | L'étiquette de titre posée sur la photo de `layout_recit_photo` (« Rizières de Banaue »), 30 signes au plus ; à défaut, la `scene` si elle est assez courte |

La répartition, dans cet ordre (`affecterPhotos`) :

1. chaque groupe de scène vise la page que visent la majorité de ses photos,
   et ne se coupe que s'il dépasse ce qu'une page porte (deux ou trois photos) ;
2. le surplus d'une page va d'abord sur la page de récit la plus proche qui a
   de la place ;
3. ce qui reste va **en fin d'étape**, sur les pages de photos qui suivent le
   récit, à parts égales, cinq au plus par page — § « Structure d'une étape ».
   Aucune photo n'est perdue.

Sans analyse (pas de clé de modèle, ou un échec), chaque photo vise la page qui
correspond à son rang dans l'étape, et il n'y a pas de carte : le carnet se fait
quand même. L'analyse est gardée avec l'étape et refaite seulement si le lieu,
le récit ou les photos changent. Consigne : `consigneAnalyseEtape`
(`MemoBook Generator/public/partage.js`).

### Deux pages en vis-à-vis

**Deux pages qui se font face n'ont jamais la même composition** (« Consignes
IA », Notion). Les doubles pages sont celles du livre imprimé : le colophon est
la page 1, à droite, et la première page d'étape la page 2, à gauche.

Une **composition**, c'est ce qu'on voit d'un coup d'œil : texte seul, texte et
photo flottante, grande photo en tête, bande de deux photos, bande de trois,
carte de chapitre, planche, trio portrait, trio paysage. `layout_split_left` sans fun fact et
`layout_collage` à deux photos donnent la même page : ils comptent pour une.

Quand les deux côtés se ressemblent, on essaie, dans cet ordre
(`varierDoublesPages`) :

1. une page à une photo passe de la grande photo en tête à la photo
   flottante, ou l'inverse si la photo et le texte le permettent ;
2. deux pages de la même étape s'échangent une photo — de préférence celle qui
   illustre le passage de la page qui la reçoit, ou de la même scène que ses
   photos — pour que l'une en porte une de plus que l'autre ;
3. sinon on laisse : deux pages de texte sans photo n'ont pas d'autre
   composition. L'atelier le signale.

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

**Un post-it « Infos » partout** (Hugo, 12/10/2026) : papier, scotch, plus de
pince ni de bord pointillé, et toujours le titre « Infos ».

**La promesse (Hugo, 13/10/2026) : à peu près un fun fact toutes les trois
pages** quand le voyageur les allume. Avant, quatre règles cumulées — un par
étape, 7/10 au moins, une page de récit qui ait la place, trois pages d'écart —
plafonnaient un carnet chargé en photos à un encart toutes les cinq ou six
pages, voire moins.

> Retour le plus unanime du panel de lecteurs : **6 sur 7** en parlent, tous
> dans le même sens. Ce n'est pas un rejet — les fun facts sont aussi cités
> parmi les points forts — mais un problème de **quantité** et de **nature**.
> Un lecteur résume tout : « j'ai lu tous les fun facts, mais pas tout le
> contenu ». La carte gagnait la page contre le récit.

**Les encarts sont un réglage du voyageur, ON ou OFF.** À OFF, aucun `fun_facts`
n'est produit. Les règles ci-dessous valent à ON.

Quatre règles, à appliquer strictement :

1. **Fréquence : un encart toutes les trois pages**, deux au moins et quatre
   au plus d'un encart au suivant. Jamais un par page.
2. **Plusieurs par étape** quand l'étape est longue : autant que ses pages en
   demandent.
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

**Le réglage ON/OFF est appliqué au moment de composer le carnet**, pas à la
rédaction : la rédaction écrit l'encart de chaque étape quoi qu'il arrive, et
`jobs/structure.ts` ne le transmet que si `funFactsEnabled` est vrai. Un
voyageur qui rallume le réglage retrouve ses encarts sans tout relancer.

### Dans l'atelier

L'atelier n'a pas d'étape de rédaction : l'encart vient de l'**analyse d'étape**
(`consigneAnalyseEtape`, `partage.js`), le même appel que celui qui situe le
lieu et rattache les photos. Le modèle y reçoit le récit et propose **plusieurs
encarts** (`funFacts`, jusqu'à un pour 1 400 signes de récit, plus un), chacun
avec son registre, le paragraphe d'où il vient et une **note de pertinence sur
10**. Dans l'app, ce sont les fun facts de la rédaction, un par souvenir. La
mise en page (`placerEncarts`, `mise-en-page.js`), la même pour les deux PDF,
décide ensuite :

- **cadence** : on avance page par page ; la place visée est trois pages après
  le dernier encart (le premier, dans les trois premières pages), dans une
  fenêtre de deux à quatre pages. **La place passe avant la note** : une page
  d'écart coûte 2,5 points — un 9 à côté cède à un 7 pile à sa place ;
- **seuil** : 7/10 d'abord ; une place restée vide se contente d'un 5 ou d'un
  6 ; sous 5, jamais. Au-delà de 140 caractères, jamais ;
- **registre** : deux encarts du même registre à la suite, seulement quand il
  n'y a pas mieux ;
- **page hôte, dans la page** : récit avec 0 ou 1 photo, la zone flottante
  l'accueille sans rien coûter (540 signes sous un bandeau, 860 sur une page de
  suite), et une grande photo en tête repasse en photo flottante ; deux photos,
  230 signes au plus ; ouverture de chapitre avec deux photos, 110 ;
- **page hôte, sur les photos** (Hugo, 13/10/2026 : « les fun facts peuvent
  aussi aller sur les pages photos ») : un post-it posé dans un coin d'une
  planche (`mb-card--postit-planche`), sur le blanc d'une page d'album, ou sur
  la bande de photos d'une page de récit (`postit_bande`, collage, bande, trio,
  chapitre) — il mord sur une photo sans prendre une ligne au texte, côté
  extérieur de la page. Jamais sur la pleine page ;
- **mention** : la page porte `ai_note` « Fun fact rédigé par IA ».

Le journal de l'atelier donne la cadence obtenue (« 14 encarts, un toutes les
3,0 pages ») et, étape par étape, pourquoi un fun fact manque.

Le réglage « Insérer des Fun facts » se coche dans la fiche du carnet de
l'atelier, allumé par défaut comme dans l'app.

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
   photo entre entière dans son emplacement, et le contour l'épouse (`tirage`,
   la taille de l'image réduite en % de l'emplacement) : c'est un petit
   tirage, pas une image coupée. **Une photo de groupe n'est jamais
   rognée**, quel que soit le rognage : elle passe toujours en `contain`.
3. **Les visages restent dans le cadre.** Une photo plus haute que son
   emplacement est rognée en haut et en bas : on garde le haut (`focus`
   vertical à 30 %), là où sont les visages sur une photo prise à hauteur
   d'homme. Quand une détection de visages est disponible, ses boîtes priment :
   le cadre doit contenir au moins chaque visage entier, et une photo dont les
   visages ne tiennent pas dans le cadre passe en `contain`.

**Les formats des emplacements**, mesurés sur le rendu (l'image remplit son
emplacement, le contour déborde sans compter), dans l'ordre où le gabarit lit
`photos[]` — remesurés le 13/10/2026 :

| Layout | Photos | Formats |
|---|---|---|
| par défaut (photo flottante) | 1 | 1,02 |
| `layout_hero_top` | 1 | 1,31 |
| `layout_split_left`, `layout_collage` | 2 | 0,86 · 0,86 |
| `layout_collage` | 3 | 0,55 · 0,55 · 0,55 |
| `layout_recit_photo` | 1 | 0,51 |
| `layout_chapter_map` | 1 | 0,69 — au-dessus de la carte |
| `layout_chapter_map` | 2 | 0,89 · 0,89 — en bande |
| `layout_photo_page` (page d'album) | 1 | 0,85 — 1,38 couchée pour une photo en largeur (`album_paysage`) |
| `layout_photo_page` (page d'album) | 2 | 0,96 · 0,96 |
| `layout_trio_portrait` | 3 | 0,60 (haut) · 0,68 · 0,64 |
| `layout_trio_landscape` | 3 | 1,52 (haut) · 0,64 · 0,64 |
| `layout_photo_page` | 3 | 0,71 · 0,44 · 1,59 |
| `layout_photo_page` | 4 | 0,71 · 0,44 · 0,60 · 0,95 |
| `layout_photo_page` | 5 | 1,72 · 1,38 · 0,87 · 0,87 · 1,38 |
| `layout_photo_page` + `planche_colonnes` | 5 | 0,77 · 0,77 (gauche) · 0,94 · 0,77 · 0,94 (droite) |

Ils sont recopiés dans `FORMATS_EMPLACEMENTS` (atelier, `mise-en-page.js`) : **à
remesurer si la géométrie d'un layout change**.

**La bande de photos ne s'écrase plus sous 160 pt** (206 pt en temps normal).
Elle cédait sans limite quand un récit débordait ; à 100 pt, trois photos ne
sont plus que des lanières. Un récit trop long se découpe en amont, selon le
barème — il ne se loge pas en écrasant les images.

**Qui l'applique.** L'atelier, dans `placerPhotos` (`mise-en-page.js`). Une
photo est de groupe si le voyageur coche « Photo de groupe, ne pas rogner », ou
si l'analyse d'étape y compte trois visages ou plus (§ « Associer les photos au
récit »). Dans l'app, le back-end ne
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
et la livre en aperçu PDF au format exact et en fichier InDesign.

**Les plats viennent de la fiche Pumbo, le dos du nombre de pages.** L'outil
de couverture de Pumbo produit, pour une commande donnée, un script InDesign
(`.jsx`) ; l'atelier le lit (*Réglages → Fiche couverture Pumbo*) pour les
plats, le fond perdu et les marges. Sans fiche importée, il prend celle-ci :

| Fiche du 07/10/2026 — relié 154 × 216 mm | mm |
|---|---|
| Fond perdu, sur les quatre bords | 3 |
| Plat verso et plat recto (chacun) | 178 × 260 |
| Zone de pliage : haut, bas et bord extérieur des plats | 19 |
| Mors (le pli d'ouverture), mesuré depuis le dos | 10 |

Les plats sont plus grands que la page (178 × 260 contre 154 × 216) : le carton
déborde du bloc et le papier se rabat dessus. Les 19 mm de la zone de pliage se
rabattent sur les chants et l'intérieur du carton : ils ne se voient pas.

**La face visible** d'un plat va donc de la zone de pliage **jusqu'au dos** —
159 × 222 mm ici. Le mors n'en est pas le bord : c'est seulement là que le
papier plie quand on ouvre le livre, il reste visible. Tout se **centre sur la
face visible** (`Couverture.facesVisibles`) et se tient à **12 mm** de ses
bords (`RETRAIT`) : sur la ligne de pliage, un trait passe sur l'arête du
carton et disparaît ; contre le dos, il tombe dans le mors. C'est ce que
vérifie l'outil de contrôle de Pumbo (repères « Zone de pliage » et « Mors »).

**Le dos suit le barème Pumbo** (08/10/2026, récapitulatif tenu dans le
tableur de l'équipe), d'après le nombre de **pages intérieures** du carnet —
colophon compris, arrondi au nombre pair qui part chez l'imprimeur :

| Pages | Dos |
|---|---|
| 16 à 56 | **8,0 mm** (le minimum) |
| au-delà | **3 mm + 0,09 mm par page**, arrondi au dixième, 8 mm au moins |
| exemples | 100 pages → 12,0 mm ; 200 pages → 21,0 mm |

La planche fait donc `2 × 178 + dos` mm de large, plus le fond perdu (370 × 266
pour 48 pages). L'atelier compte les pages de sa propre mise en page
(`Couverture.dosPumbo`, `ficheDuCarnet`) et le dit au voyageur ; sous 16 pages,
il prévient que Pumbo ne relie pas un carnet aussi mince. Le carnet change de
nombre de pages : la couverture se refait.

**Le style par défaut** (`assets/covers/… cover_style par défaut.png`), seul
développé pour l'instant. Rien du modèle n'est écrit en dur : ni la photo, ni
les textes, ni les chiffres, ni la carte.

- **Première** — la photo en pleine page, fond perdu compris ; en haut, le
  titre (la destination, reprise du carnet) en Playfair Display Bold, blanc,
  aussi grand que la largeur le permet (72 pt au plus) ; en bas, les voyageurs
  et le mois du voyage (« août – septembre 2026 »). Titre et signature
  **centrés sur la face visible** (entre le dos et la zone de pliage), à 12 mm
  de ses bords. Une ombre légère sous les textes, pour les ciels clairs.
- **Dos** — le **papier beige de la quatrième**, qui s'y prolonge, le texte à
  l'encre.
- **Quatrième** — sur le papier, dans un **cadre pointillé centré sur la face
  visible**, à 12 mm de la zone de pliage comme du dos ; la carte, les chiffres
  et le logo sont centrés sur l'axe du cadre :
  - **la carte des villes visitées, reliées dans l'ordre de visite** — pour un
    voyage d'île en île, les îles. Seulement les lieux de séjour, c'est-à-dire
    le lieu principal de chaque étape (`Voyage.lieuxDeSejour`) : ni les sites
    visités en chemin (une plage, un musée, un village d'excursion), ni les
    escales de transit, ni la maison. Chaque trajet au trait de son moyen de
    transport (§ « Les cartes ») ; les côtes en trait fin, les villes en
    anneaux verts, leurs noms placés là où ils ne chevauchent rien, au besoin
    au bout d'un filet. Le cadre entoure toutes ces villes (une marge, un degré
    au moins), quel que soit le nombre de pays ;
  - **« Mon voyage en quelques chiffres »** : les jours, les kilomètres
    parcourus, puis les pays s'il y en a plusieurs — sinon **les lieux de la
    carte, comptés comme elle les montre** : « 4 îles visitées » pour les
    Cyclades, « 3 villes visitées », « 5 lieux visités » quand la carte mêle
    villes et îles. Une île, c'est le `genre: "ile"` de l'analyse ; pour les
    analyses plus anciennes, un site posé sur une terre qui n'est pas la plus
    grande de son pays (`Couverture.estUneIle`) ;
  - le logo MemoBook. Pas de photo : le style par défaut n'en a pas en
    quatrième.

**Le dos, dans tous les styles.** Toujours les **voyageurs, le titre du
carnet et les dates du voyage**, à la française (**lisibles de bas en haut**) :
les voyageurs calés en pied, le titre au milieu du dos, les dates calées en
tête, à 10 mm des zones de pliage (`Couverture.elementsDos`, à réutiliser par
chaque style, seule la couleur change). Corps : 45 % de la largeur du dos,
11 pt au plus, réduit si les trois ne tiennent pas ; le titre quitte le milieu
s'il y heurterait un voisin. Pas de texte sous 6 mm de dos.

**Les chiffres du voyage** (`voyage.js`), tirés des récits par l'analyse
d'étape :

- **kilomètres** : la somme des **trajets racontés** (`trajets` : départ,
  arrivée, moyen de transport), aller et retour compris — à vol d'oiseau en
  avion et en bateau, **1,3 fois** par la route ou le rail. Aucun trajet
  raconté : pas de chiffre, plutôt qu'un chiffre inventé ;
- **pays visités** et **villes visitées**, distincts : une ville ou un village
  compte comme ville, une île, une plage ou un musée non (`genre`). La maison —
  le départ du premier trajet — n'est ni un lieu visité ni un pays visité.

**Les photos des plats.** L'atelier propose les **trois** photos les plus
adaptées à la première et **trois autres** pour la quatrième ; le voyageur
choisit parmi les six, ou en prend une autre. La note (`evaluerPhoto`) :

- **qualité** (45 %) — la résolution à la taille d'impression (300 dpi visés),
  la netteté (variance du laplacien sur une vignette de 512 px) et
  l'exposition, mesurées dans le navigateur ;
- **contenu** (55 %) — la note « couverture » de l'analyse d'étape : 8 et plus
  pour un paysage marquant ou une belle photo des voyageurs ;
- **jamais proposée** : une photo qui échoue au contrôle qualité, ou que le plat
  rognerait de plus d'un tiers (15 % pour une photo de groupe).

**Le contrôle qualité**, à chaque photo choisie — proposée ou non : alerte sous
**200 dpi**, sous une netteté de **40** (une photo nette mesure de 170 à 3 000,
floutée d'un pixel de 15 à 130), sous une luminance moyenne de 45 (trop sombre),
au-dessus de 215 ou avec plus de 25 % de pixels brûlés (surexposée), et quand le
plat rogne trop. La photo de la première est aussi celle de la couverture
intérieure du carnet.

**Les fichiers.** Bouton « Générer la couverture » → le panneau de la
couverture :

- **« Aperçu à imprimer (PDF) »** — un onglet avec la feuille et ses repères
  (coupe, plis du dos, faces visibles — à l'écran seulement) → *Imprimer* →
  *Enregistrer au format PDF*, marges *Aucune*, *Graphiques d'arrière-plan*
  coché. La taille de la feuille est imposée par la règle `@page` ;
- **« Fichier InDesign (.zip) »** — un dossier : `Couverture MemoBook.jsx`, le
  script InDesign qui construit le document, la photo en pleine résolution et
  le logo dans `Liens/`, et `LISEZMOI.txt`. Le script reprend **mot pour mot**
  la mise en place de la fiche Pumbo (trois pages verso, dos, recto sur une
  planche), puis pose chaque élément en objet InDesign modifiable : photo liée
  et calée sur son point focal, textes en Playfair Display, carte en tracés
  vectoriels, nuances en CMJN, trois calques (photo et fonds, carte, textes).
  Il se lance depuis le panneau Scripts d'InDesign, comme la fiche Pumbo.

L'aperçu et le script viennent de **la même maquette** (`maquette`, en
millimètres) : ils ne peuvent pas diverger.

### Les styles de couverture

Le panneau de l'atelier propose **les sept styles du catalogue de l'app**
(`coverCatalogue.ts`), avec leur première de référence (`assets/covers/`). Le
moteur reste `couverture.js` ; un style ne fait que poser ses éléments
(`couverture-styles.js`). Spécifications de Hugo du 09/10/2026 :

| Style | Disponible | Polices | Couleurs | Images | Textes |
|---|---|---|---|---|---|
| Par défaut | oui | Playfair Display | photo, papier, encre | la photo de la première | titre, voyageurs, dates (tirés du carnet) |
| Élégant | oui | Cormorant Garamond (titre), Cormorant Infant | fonds beige, noir typo, logo beige foncé | deux photos de paysage : grande sur la première, bande panoramique en tête de la quatrième | titre, date, texte de la quatrième — rédigés par l'IA |
| Dessin | oui | Hansley (titres) — **Gloria Hallelujah tant que sa licence n'est pas vérifiée** —, Gloria Hallelujah | fonds beige, noir typo, disques bleu pâle | trois dessins de la bibliothèque (`assets/stickers/`, au trait ou dessinés), appelés par les récits | phrase-titre et titre de la quatrième rédigés par l'IA ; années, voyageurs et texte de la quatrième tirés du carnet |
| Aquarelle, Assouline, Photo-dessin, Travel book | **à venir** | | | images générées | |

- **Les textes** sont rédigés par l'IA d'après les récits (« Rédiger avec
  l'IA », `consigneTextes`), puis **modifiables** dans le panneau ; ce que le
  voyageur écrit passe avant. Ils sont gardés dans le fichier d'avancement
  (`couvertureStyle`).
- **Le dos, pour tous les styles** : le fond de la quatrième, et ses textes
  (titre, voyageurs, dates) dans la police et la couleur du corps de texte de
  la quatrième — à défaut, de son titre.
- **Les polices** des styles (OFL) sont dans `public/fonts/couvertures/` ;
  l'aperçu les charge, le `LISEZMOI.txt` du dossier InDesign dit lesquelles
  installer.
- **Les styles à images générées** attendent un lot à part (génération
  d'images). Leur carte est grisée et marquée « À venir ».
- **Le PDF de l'app** n'imprime encore que le style par défaut : le style
  choisi dans l'app est enregistré, pas encore composé côté serveur.

**L'intérieur, version imprimeur.** Le PDF du carnet contient sa propre
couverture et sa quatrième (première et dernière pages) : pour un relié, elles
seraient imprimées une seconde fois à l'intérieur. La **version imprimeur**
(case dans les réglages de l'atelier) envoie `sans_couvertures: true` — le livre
s'ouvre sur le colophon — et `page_blanche_finale: true` quand le nombre de
pages est impair, un relié s'imprimant en feuillets. Après le rendu, l'atelier
affiche le nombre de pages intérieures : c'est celui à donner à l'outil de
couverture Pumbo pour obtenir la fiche, donc le dos.

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

### Fond perdu

Le standard d'imprimerie : **3 mm sur les quatre bords**. La version
imprimeur (Pumbo) sort sur une feuille de **154 × 216 mm** (437 × 612 pt) pour
une page finie de 148 × 210 mm. Le payload porte `fond_perdu: true`, qui pose
la classe `fond-perdu` sur le `body` et règle `--mb-bleed` à 8,504 pt.

| Va jusqu'au bord de la feuille, coupé au massicot | Se cale sur la page finie, décalé de `--mb-bleed` |
|---|---|
| La teinte et le grain du papier (`.page::before/::after`) | La colonne de texte et toutes les marges (`.page__content`, `inset: var(--mb-bleed)`) — capacités inchangées |
| La photo en pleine page (`.mb-pleine-page`) | Les décors (`.page__decor`) |
| Le ruban « jour », qui dépassait déjà du haut | Les planches et pages d'album (`.mb-photowall`) |
| Le tracé pointillé, qui déborde volontairement | Les stickers, la mention « généré par IA » |

Sans `fond_perdu`, `--mb-bleed` vaut 0 et rien ne bouge : l'aperçu reste en A5
exact. Le jeu (`--mb-page-slack`) passe à 1,5 pt en fond perdu, pour que la page
tienne dans la feuille de 154 × 216 mm qu'arrondit le Chromium d'APITemplate
(§ suivant).

**Un template APITemplate à part.** Le format de la feuille se règle dans le
panneau *Settings* du template, que la synchronisation ne touche pas (§
suivant) : un même template ne peut pas sortir l'aperçu en A5 et l'intérieur à
imprimer avec fond perdu. D'où un **template imprimeur**, copie du premier, à
mettre en place une fois :

1. dans APITemplate, **dupliquer** le template du carnet ;
2. dans le panneau *Settings* de la copie : Paper Size `Custom`, **154 mm ×
   216 mm**, `Portrait`, Print background `Yes`, marges `0 / 0 / 0 / 0` ;
3. copier son identifiant dans l'atelier, réglage **« Template imprimeur (fond
   perdu 3 mm) »** — la version imprimeur l'utilise et envoie `fond_perdu` ;
4. le poser aussi en secret GitHub `APITEMPLATE_TEMPLATE_ID_IMPRIMEUR` : le
   workflow de synchronisation (et le bouton de l'atelier) poussent alors le
   gabarit vers les deux templates.

Tant que le template imprimeur n'est pas renseigné, la version imprimeur sort
comme avant, sans fond perdu, et l'atelier le signale dans son journal.

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
