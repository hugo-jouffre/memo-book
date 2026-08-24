# Contrat de mise en page — carnet `travel-journal`

Base de connaissance de l'agent qui produit le JSON envoyé au moteur PDF.

> **Règle de survie du dépôt.** Ce fichier décrit ce que `index.html` sait
> réellement afficher. Toute modification du template doit modifier ce fichier
> **dans le même commit**. C'est exactement ce qui avait dérivé : le KB
> documentait onze layouts dont un seul existait, et l'agent produisait des
> champs que personne ne lisait.

## Format

- Page **A5 : 420 × 595 pt** (1 unité Figma = 1 pt), sans fond perdu.
  Géométrie dans `print.json`, maquette Figma `geIpjYxG3WCkGrgJFpkuVC`.
- Marge de contenu : 30 pt. Les décors (tracé pointillé, stickers) débordent
  volontairement.
- Une page de carnet = un élément `.page`. Une entrée de `days[]` = une page.

## Structure du payload

| Champ | Type | Rôle |
|---|---|---|
| `book_title` | requis | Titre de couverture, sur la photo |
| `book_subtitle` | optionnel | Bandeau blanc incliné sous le titre |
| `authors`, `date_range` | optionnels | Signature en bas de couverture |
| `cover_photo` | optionnel | Photo pleine page de couverture |
| `render_profile` | `print` \| `preview` | **Fond du PDF, voir plus bas** |
| `brand_name`, `year` | optionnels | Colophon (défauts `MemoBook` / `2026`) |
| `intro_title`, `intro_text` | optionnels | Page d'introduction (`intro_text` en HTML) |
| `intro_photos[]` | 0 à 2 | Photos scotchées en haut de l'introduction |
| `days[]` | requis | **Une entrée = un bloc de récit, pas une page** — voir ci-dessous |
| `back_cover` | optionnel | Quatrième de couverture. **Sans `image`, variante typographique** — c'est le défaut souhaité |

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

## Champs d'une journée

| Champ | Type | Notes |
|---|---|---|
| `title` | requis | Titre manuscrit en tête du récit |
| `body_html` | requis | Récit. `<p>` par idée, `<ul>/<li>` pour les listes. Pas de `<h1>`/`<h2>` |
| `day_intro` | optionnel | Affiche le bandeau : `{ day_number, location, date, stay, host, weather_key }` |
| `stay`, `host` | optionnels | Nom du gîte, prénom des hôtes. **À préférer à la météo** |
| `weather_key` | optionnel, 5 valeurs | Icône mise en avant. Sans le champ, la rangée disparaît |
| `tag` | optionnel | Étiquette manuscrite (« Top départ »). **Trois mots max**, sinon elle déborde |
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
| `layout_chapter_map` | Carte de la région à droite, récit et carte info à gauche, photos en bas | Ouverture d'un chapitre — voir la table plus haut | 0–2 | sous S à M, **selon la carte info et les photos** |
| `layout_hero_top` | Grande photo en tête, récit dessous | Une photo iconique porte la journée | 1 | sous S, S |
| `layout_split_left` | Carte info à gauche, récit en colonne à droite, puis deux photos en bas | Un fait à mettre en avant et deux belles images | 2 | S, M — **S seulement avec un fun fact** |
| `layout_collage` | Récit pleine largeur puis 2 ou 3 photos inclinées en bas | Journée dense visuellement | 2–3 | S, M |
| `layout_photo_page` | **Page pleine de photos**, sans récit ni bandeau. `title` devient une légende manuscrite en bas | Étape très visuelle. En placer régulièrement : c'est la page que les lecteurs préfèrent | 3–5 | aucune — le récit n'est pas rendu |
| *(par défaut)* | Récit, puis carte info et photo flottantes en bas de page | Ouverture de journée, cas le plus courant | 0–1 | S, M |

Les tailles exactes, et le plafond mesuré de chaque configuration, sont en
§ « Longueur des textes ».

Le cas par défaut couvre aussi `layout_story_opener` et `layout_story_facts` :
le validateur exige au moins un drapeau, n'importe lequel de ces deux convient.

## Le tracé pointillé du voyage

Décor de bas de page, tiré au sort parmi quatre boucles. **Il ne passe que
derrière des photos, jamais derrière du texte**, qu'il rendrait illisible. Le
gabarit ne le dessine donc que si le bas de la page porte une bande d'images,
ce qui exclut :

- `layout_hero_top`, qui met la photo en haut et le récit en bas ;
- les étapes à moins de deux photos, qui n'ont pas de bande ;
- les étapes portant un `prompt` ou un `quiz`, qui occupent eux-mêmes le bas.

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

### Une étape sur deux pages

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

Quatre règles, à appliquer strictement :

1. **Fréquence : environ 2 pour 3 pages.** Jamais un par page.
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

## La mention « généré par IA »

`ai_note` s'imprime en petit gris, en bas de page. À renseigner **dès qu'un
élément de la page vient de la machine** — c'est une demande explicite, pas une
option. Exemple : « Fun fact et illustration générés par IA ».

## La météo du jour

**Champ optionnel, et rarement utile.** Les lecteurs sont explicites : la météo
n'est pas importante, ils préfèrent la carte, le nom de l'hôtel et l'hôte.
Sans `weather_key`, la rangée disparaît — ce qui aère la page, autre demande du
panel. Préférer `day_intro.stay` et `day_intro.host`.

Quand la météo porte vraiment la journée (mousson, tempête, premier jour de
neige), le bandeau affiche les cinq icônes ; celle qui correspond passe en
pastille carotte, les quatre autres restent estompées à 30 %. **Il n'y a rien
d'autre à envoyer** — ni emoji, ni couleur, ni température.

| Valeur | Icône | Quand la choisir |
|---|---|---|
| `sun` | soleil plein | Grand beau, ciel dégagé, forte chaleur |
| `sun-wind` | soleil et vent | Éclaircies, ciel voilé, brise, temps changeant |
| `cloud` | nuage | Couvert, gris, brume, sans pluie |
| `rain` | pluie | Averses, mousson, orage |
| `snow` | flocon | Neige, gel, froid marquant |

**Comment décider.** Prendre le temps *dominant* de la journée racontée, pas le
plus spectaculaire : une éclaircie de dix minutes dans une journée de pluie
reste `rain`. Si le récit ne dit rien du temps, se fier au lieu et à la saison
plutôt que d'omettre le champ — un bandeau sans icône active a l'air cassé.
En cas d'hésitation entre deux valeurs, `sun-wind` est le repli neutre : c'est
la seule qui ne raconte pas un temps tranché.

`weather_icon` (emoji) subsiste dans le schéma pour compatibilité mais n'est
plus rendu. Ne pas le produire.

## Réglure et rythme vertical

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

- URLs absolues et publiques (CDN Webflow). Pas de chemin relatif : le moteur
  PDF ne reçoit que du HTML et du CSS, sans aucun fichier joint.
- **1750 px minimum** pour une photo pleine page (couverture, quatrième,
  `layout_photo_page`) : à 148 mm de large, il en faut autant pour tenir les
  300 ppi de l'imprimeur. 1200 px n'y suffisent pas — ça donne 205 ppi.
- 1200–1600 px suffisent pour une photo héro ou une photo de galerie, qui
  n'occupent qu'une fraction de la largeur.
- Les photos sont recadrées en `object-fit: cover` et pivotées de quelques
  degrés : ne pas envoyer une image dont un visage touche déjà le bord.
- **Le scotch reste l'exception.** Un lecteur ne l'aime pas du tout ; il garde
  sa valeur tant qu'il surprend. Une photo scotchée de temps en temps, pas une
  page entière.
- **Pas d'illustration qui occupe une page seule.** Une photo des voyageurs
  vaut mieux qu'un dessin de remplissage : deux lecteurs le disent séparément.

### Deux formes acceptées pour une photo

Une entrée de `photos[]` est soit une URL nue, soit un objet enrichi par
l'analyse d'image. Les deux formes cohabitent dans le même tableau.

```json
"photos": [
  "https://cdn.../plage.jpg",
  { "url": "https://cdn.../marche.jpg", "tape_corner": "bottom-left", "focus": "17% 50%" }
]
```

| Champ | Valeurs | Effet |
|---|---|---|
| `url` | URL absolue | La photo. Seul champ obligatoire de la forme objet |
| `tape_corner` | `top-left`, `top-right`, `bottom-left`, `bottom-right`, `top` | Pose un scotch dans ce coin. **Absent = pas de scotch** : mieux vaut aucun scotch qu'un scotch sur un visage |
| `focus` | deux pourcentages, ex. `17% 50%` | Point que le recadrage préserve. Absent = recadrage centré |

**L'agent ne remplit pas ces deux champs à la main.** Ils sortent de
`backend/src/services/photoAnalysis.ts`, qui mesure la photo : coin le plus
calme pour le scotch, zone la plus détaillée pour le recadrage. Voir
`docs/photos.md`.

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
        "date": "22-23 fev 2026",
        "weather_key": "sun"
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
