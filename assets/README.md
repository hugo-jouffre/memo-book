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

Le script réécrit le bloc de sprite dans `templates/travel-journal/index.html`,
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

## `assets/textures/`

Grains de papier, scotch, papiers déchirés. Même logique que les illustrations.
Le grain du papier actuel n'est pas ici : il est généré en `feTurbulence` dans
`style.css`, pour ne dépendre d'aucun fichier.

## Ce qui ne va PAS ici

- **Les photos des voyageurs** — elles transitent par le pipeline
  (`backend/src/services/webflow.ts`) et ne sont jamais versionnées.
- **Les polices** — `templates/travel-journal/assets/fonts/`, parce qu'elles
  sont propres à un style de carnet et embarquées dans son CSS.
- **Les substituts de test** — `backend/test/fixtures/offline/`.
