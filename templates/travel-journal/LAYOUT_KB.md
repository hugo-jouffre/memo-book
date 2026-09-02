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
  première. Les suivantes le laissent vide et enchaînent le récit.

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
- Un récit très court doit déclencher un layout qui respire — carte, sticker,
  tracé pointillé — plutôt qu'une page aux trois quarts vide.

*(À construire : les variantes sans photo et les variantes « peu de texte ».
Pour l'instant, l'agent choisit le layout existant le plus proche.)*

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
| Typographie des titres | Playfair | `--mb-font-display` | **À construire** |
| Typographie des sous-titres | Hansley | `--mb-font-title` | **À construire** — `.woff2` non déposé, repli sur la manuscrite |
| Typographie des textes | Gloria Hallelujah | `--mb-font-hand` | **À construire** |
| Typographie des fun facts | Playfair | Pas de token dédié : partage `--mb-font-display` | **À construire** — créer `--mb-font-facts` |
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

| Drapeau | Rendu | Quand le choisir | Photos |
|---|---|---|---|
| `layout_chapter_map` | Carte de la région à droite, récit et carte info à gauche, photos en bas | Ouverture d'un chapitre — voir la table plus haut | 0–2 |
| `layout_hero_top` | Grande photo en tête, récit dessous | Une photo iconique porte la journée | 1 |
| `layout_split_left` | Carte info à gauche, récit en colonne à droite, puis deux photos en bas | Un fait à mettre en avant et deux belles images | 2 |
| `layout_collage` | Récit pleine largeur puis 2 ou 3 photos inclinées en bas | Journée dense visuellement | 2–3 |
| `layout_photo_page` | **Page pleine de photos**, sans récit ni bandeau. `title` devient une légende manuscrite en bas | Étape très visuelle. En placer régulièrement : c'est la page que les lecteurs préfèrent | 3–5 |
| *(par défaut)* | Récit, puis carte info et photo flottantes en bas de page | Ouverture de journée, cas le plus courant | 0–1 |

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

## Contraintes de longueur

Appliquées par `backend/src/services/payloadValidator.ts` — un dépassement est
une **erreur**, pas un avertissement :

| Champ | Maximum |
|---|---|
| `intro_text` | 700 caractères par paragraphe, 3 paragraphes |
| `body_html` | 420 caractères par paragraphe, 2–3 paragraphes |
| `fun_facts[]` | 140 caractères |
| `highlights[]` | 80 caractères |

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

**L'agent ne remplit pas ces deux champs à la main.** Ils sortent de
`backend/src/services/photoAnalysis.ts`, qui mesure la photo : coin le plus
calme pour le scotch, zone la plus détaillée pour le recadrage. Voir
`docs/photos.md`.

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

### Polices — déjà inlinées, ne rien ajouter

`fonts.css` porte les `@font-face` en **base64**, générés par
`npm run fonts:build` (`backend/scripts/build-font-css.ts`) depuis les `.woff2`
versionnés dans `templates/travel-journal/assets/fonts/`. C'est la forme
retenue en production : elle supprime la dépendance réseau au moment du rendu
et garantit le même tirage à chaque impression.

Deux familles sont réellement embarquées : **Playfair Display** (400/700/900)
et **Gloria Hallelujah** (400). Rien d'autre. `--mb-font-title` nomme encore
`Hansley`, dont aucun `.woff2` n'est versionné : le titre retombe donc
aujourd'hui sur Gloria Hallelujah — exemple exact du défaut silencieux décrit
plus haut. Déposer le fichier dans `templates/travel-journal/assets/fonts/`
et relancer `fonts:build` suffit à le corriger.

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
