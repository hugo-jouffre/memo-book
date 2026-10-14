# Bibliothèque d'éléments MemoBook

Tout ce qui est **réutilisable d'un carnet à l'autre** vit ici : icônes au trait,
illustrations, textures. Les photos des voyageurs n'y sont pas — elles arrivent
par le pipeline et partent sur le CDN.

## La contrainte qui décide de tout

Le moteur PDF ne reçoit que **deux chaînes** : le HTML et le CSS. Aucun fichier
joint, aucun chemin relatif résolu. Un `<img src="assets/icons/sun.svg">` ne
s'affichera jamais dans un carnet.

D'où deux traitements, et un seul critère pour choisir :

| | Où ça vit | Comment ça arrive dans le PDF | Pour quoi |
|---|---|---|---|
| **Icônes** | `assets/icons/` | **Inlinées** dans `index.html` par `npm run icons:build` | Vocabulaire fixe, présent dans presque tous les carnets |
| **Illustrations** | `assets/illustrations/` | **URL publique** injectée dans le JSON au moment du rendu | Choisies par carnet, trop lourdes pour être toutes embarquées |

Une icône inlinée ne coûte rien au rendu et fonctionne hors ligne. Une
illustration inlinée ferait grossir le template pour tout le monde alors qu'un
carnet donné n'en utilise que trois.

## `assets/stickers/` — la bibliothèque de stickers dessinés

Les stickers illustrés du carnet : une **bibliothèque dessinée** (Hugo,
12/10/2026), pas une génération par IA. La source de dessin est la base Notion
**« Éléments graphiques »**
(<https://app.notion.com/p/37d401e7bdc1808da074d389128778f8>) ; le dépôt en
garde une copie préparée, que le carnet lit sans jamais appeler Notion.

| Fichier | Rôle |
|---|---|
| `source.json` | Le manifeste, **écrit à la main** : une entrée par image Notion (`notion` : id de la page, `nom`, `famille`, `style`), les **mots déclencheurs par famille** (`familles`) et les familles réservées (`reserves`) |
| `<famille>-<n>.png` | Les images, rognées de leurs marges transparentes, à leur définition d'origine |
| `stickers.json` | L'index que lit l'atelier, **généré** par `backend/scripts/preparer-stickers.ts` — ne pas le modifier à la main |

Une entrée de l'index :

```json
{ "fichier": "scooter-1.png", "nom": "Moto avec 2 passagers", "famille": "scooter",
  "style": "dessin", "mots": ["scooter", "moto", "vespa"],
  "largeur": 482, "hauteur": 415, "maxPt": 231, "notion": "387401e7…" }
```

- **`famille`** regroupe les variantes d'un même objet (huit sacs à dos, huit
  appareils photo, quatre boussoles). Jamais deux fois la même famille sur une
  double page, jamais le même dessin sur deux doubles pages qui se suivent ;
  la variante qui a le moins servi passe d'abord.
- **`style`** : `sticker` (découpé, contour blanc), `dessin` (illustration
  sans contour) ou `trait` (dessin au trait noir). Il ne règle que la taille —
  les trois se mêlent dans un carnet (Hugo, 12/10/2026).
- **`mots`** : sans accent, en minuscules, **mot entier** (pluriel en s ou x
  accepté) — « visa » ne prend pas « visage ». Jamais un mot que presque tout
  récit contient (« photo », « voyage », « ville ») : le sticker serait partout.
  Un mot du titre ou du lieu de l'étape l'emporte sur un mot du récit.
- **`maxPt`** : la largeur maximale à l'impression, à **150 dpi**. Les exports
  Notion font 300 px pour la plupart (140 à 280 px une fois rognés) : des
  stickers de 2 à 4 cm. Des exports de 600 px et plus permettraient de les
  agrandir.
- **`reserve: "voyageurs"`** : les personnages de dos (couple, femme brune,
  homme blond…). Importés, jamais tirés d'après le récit : il faudra les
  choisir d'après l'apparence des voyageurs.

**Ajouter ou remplacer un sticker** :

1. le dessiner dans Notion (PNG transparent, 600 px de large ou plus) ;
2. télécharger les images de la base dans un dossier de travail, chacune
   nommée `<id de la page Notion>.png` ;
3. compléter `source.json` (l'image, et les mots de sa famille si elle est
   nouvelle) ;
4. `cd backend && npx tsx scripts/preparer-stickers.ts --brut <dossier>` ;
5. `npx vitest run test/stickers.test.ts` vérifie l'index.

**Dosage et places** (`decorerDoublesPages`, `mise-en-page.js`) : autant de
stickers par double page que le réglage « Décorations & stickers » (1 à 4,
aucun à 0), deux par page au plus, complétés par les familles de voyage quand
le récit n'en appelle pas assez. Les places, jamais par-dessus le récit ni
dans le pli : `LAYOUT_KB.md`, § « Les stickers ».

**Arrivée dans le PDF** : par URL publique (`raw.githubusercontent.com`,
branche `main`), comme les illustrations — une bibliothèque n'apparaît dans le
carnet qu'une fois fusionnée.

## `assets/icons/` — la librairie Figma

Icônes **monochromes au trait**, exportées en SVG depuis Figma.

```
assets/icons/
  weather/     sun.svg, sun-wind.svg, cloud.svg, rain.svg, snow.svg
  travel/      plane.svg, scooter.svg, ferry.svg, passport.svg, pin.svg
  ui/          clip.svg, arrow.svg, star.svg
```

**Règles d'export**, à respecter sinon l'icône ne prendra pas la couleur du
contexte et arrivera noire sur un fond carotte :

1. Export **SVG**, `viewBox="0 0 24 24"`, sans `width`/`height` fixes.
2. **Aucune couleur en dur** : remplacer chaque `stroke="#…"` / `fill="#…"` par
   `currentColor`. C'est ce qui permet à une icône de passer en blanc quand elle
   est active, ou en gris quand elle ne l'est pas.
3. Nom de fichier en minuscules avec tirets — il devient l'identifiant
   (`weather/sun.svg` → `#mb-i-weather-sun`).
4. Tracés aplatis, pas de masque ni de calque de texte.

Puis :

```bash
cd backend && npm run icons:build
```

Le script réécrit le bloc de sprite dans `MemoBook Generator/templates/travel-journal/index.html`,
entre les marqueurs `mb:icons:start` / `mb:icons:end`. Le template reste un
fichier unique, prêt à partir chez APITemplate.

## `assets/illustrations/` — les visuels couleur

```
assets/illustrations/
  stickers/    illustrations générées ou dessinées (avion, scooter, valise…)
  stamps/      tampons de passeport par pays
  maps/        cartes illustrées
```

Ces fichiers sont la **référence versionnée**. Pour qu'un carnet les utilise, il
faut une URL publique : `manifest.json` fait le lien entre le nom logique et
l'URL CDN.

```json
{
  "stickers/plane": {
    "file": "stickers/plane.png",
    "url": "https://cdn.prod.website-files.com/…/plane.png",
    "tags": ["transport", "avion", "départ"]
  }
}
```

Le fichier reste ici pour qu'on sache ce qui existe et qu'on puisse le
régénérer ; l'`url` est ce que l'agent met dans le JSON du carnet.

## `assets/illustrations/aperçu personnalisation/` — l'aperçu de l'écran « Personnalisations »

200 exports Figma et une image de repli, ~800 Ko pièce. **Ce sont les sources,
pas ce que l'app affiche.** Quelle image pour quels réglages :
`docs/apercu-personnalisation.md`. Ici, comment elles arrivent sur le
téléphone.

```bash
cd backend
npm run previews:build     # prépare dans .previews-out/, ne publie rien
npm run previews:publish   # publie ce qui manque, puis le manifeste en ligne,
                           # et seulement alors réécrit le manifeste versionné
```

La chaîne (`backend/scripts/customisation-previews.ts`) recale chaque export
sur le centre de ses pages, le réduit à **900×840** (~300 pt de large à
l'écran, en @3x) et l'encode en **WebP** avec sa transparence : ~110 Ko au
lieu de 800. Toutes les images ont la même
taille et les pages au même endroit, au demi-pixel près : l'aperçu ne saute
pas quand un curseur bouge.

Le manifeste en ligne :
`https://pjmetjdnajskijoljulc.supabase.co/storage/v1/object/public/memobook-public/apercus/manifest.json`.
**L'app ne le lit pas** : elle embarque la même correspondance, écrite par
`ios/Tools/make-customisation-preview-manifest.py` depuis le manifeste versionné,
et ne télécharge que l'image (décision du 02/10/2026, Hugo).

Elles partent dans le bucket Supabase **public** `memobook-public`, sous
`apercus/`, à côté des images d'e-mail, derrière le CDN de Supabase. Jamais
dans `memobook-media`, qui est privé et porte les médias des voyageurs.

| Objet | Nom | Cache |
|---|---|---|
| Une image | empreinte de sa source et de la recette, `<hash>.webp` | un an, immuable |
| Le manifeste | `apercus/manifest.json` | cinq minutes |

Le nom d'une image ne change que si sa source ou la recette change, et un nom
déjà en ligne n'est pas renvoyé : **relancer la chaîne sur des sources
inchangées ne publie rien.** Rien n'est jamais supprimé du bucket.

**`assets/illustrations/apercus-personnalisation.manifest.json` est le
contrat entre la chaîne et l'app**, publié tel quel en ligne. Il vit à côté du
dossier et non dedans : le dossier ne contient que des aperçus. Une entrée par
aperçu : ses réglages dans les noms de `BookCustomisation` (`rulesEnabled`,
`photoTextRatio`, `funFactsEnabled`, `decorationQuota`) et l'identifiant de
`BookFontCombo` (`fontCombo`), le fichier publié (`file`, à résoudre contre
l'adresse du manifeste) et le nom Figma de la source (`source`) ; une
combinaison absente prend `fallback`.

L'app, elle, ne lit **que** `source` et `file` : son sélecteur rend le nom
Figma — faute « Hellelujah » comprise —, et
`ios/Tools/make-customisation-preview-manifest.py` en tire la copie embarquée
« nom Figma → fichier publié ». Elle ne réserve pas la place d'après `width` et
`height`, mais d'après la tête de l'écran (`BookPagesPeek.headerSize`).

**Ajouter un aperçu** : déposer le PNG, nommé comme les autres, lancer
`npm run previews:publish`, puis `python3 ios/Tools/make-customisation-preview-manifest.py`,
et commiter les deux manifestes. Il ne paraît dans l'app qu'avec la version
suivante. Aucun autre code à toucher, sauf pour un assortiment typographique
nouveau (`FONT_COMBOS` dans le script, et la table des segments de
`BookCustomisationPreview`). Un PNG déposé sans relancer la chaîne fait échouer
`npm run previews:check` et `test/customisationPreviews.test.ts` côté back-end,
et `BookCustomisationPreviewTests` côté iOS. ⚠️ En CI, seulement si la PR
touche aussi `backend/` ou `ios/` : les deux workflows ne surveillent pas
encore `assets/illustrations/` — le correctif attend un jeton qui puisse
modifier `.github/workflows/`.

Le dossier est exclu de l'image Docker du serveur (`.dockerignore`) : le
back-end ne le lit pas.

## `assets/textures/`

Grains de papier, scotch, papiers déchirés. Même logique que les illustrations.
Le grain du papier actuel n'est pas ici : il est généré en `feTurbulence` dans
`style.css`, pour ne dépendre d'aucun fichier.

## Ce qui ne va PAS ici

- **Les photos des voyageurs** — elles transitent par le pipeline
  (`backend/src/services/webflow.ts`) et ne sont jamais versionnées.
- **Les polices** — `MemoBook Generator/templates/travel-journal/assets/fonts/`, parce qu'elles
  sont propres à un style de carnet et embarquées dans son CSS.
- **Les substituts de test** — `backend/test/fixtures/offline/`.
