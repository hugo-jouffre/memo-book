# Photos : qualité, recadrage, scotch

Ce que le pipeline doit garantir avant qu'une photo arrive dans un carnet.
Les sections 1 à 4 sont une **spécification** : rien n'en est encore
implémenté. Les sections 0 et 0 bis, elles, tournent.

## 0. La photo de couverture d'un voyage — *implémentée*

⚠️ **De quelle couverture on parle.** Celle-ci est **la carte du voyage** — la
vignette de l'accueil et l'image en tête de l'écran du voyage. Elle est
**large**. La couverture *imprimée* du carnet est verticale, et ne suit **pas**
cette règle : elle a son parcours à elle, où l'on dépose ses photos exprès
(`routes/covers.ts`). Les deux ont porté le même mot et on s'y est repris à
deux fois le 15/10/2026 — d'où ce rappel en tête.

**La couverture d'un voyage est la plus récente de ses photos paysage.** Une
photo verticale posée sur une carte large s'y recadre en une bande prise au
milieu. Un voyage qui n'a aucune photo paysage garde donc le motif de la
marque — plutôt pas de photo qu'une photo coupée (Hugo, 15/10/2026).

| | |
|---|---|
| Paysage | largeur ≥ hauteur, **carré compris** |
| Le plus récent | `capturedAt`, puis `createdAt`, puis `id` — six photos d'un même message partagent leur date à la milliseconde, et sans ces deux derniers la couverture changeait d'une requête à l'autre |
| Toujours prioritaire | la couverture choisie à la main (`memos.coverPhotoUrl`) |
| Jamais couverture | une photo non mesurée (`photoIsLandscape` à `null`) |

⚠️ **Les pixels ne disent pas le sens.** Une photo prise à la verticale avec
un iPhone est stockée en pixels *horizontaux*, avec un drapeau EXIF qui dit de
la tourner à l'affichage. `jimp` applique ce drapeau au décodage, donc
`services/photoOrientation.ts` ne corrige rien par-dessus — mais c'est un
comportement implicite, qu'une montée de version peut retirer sans bruit : les
tests de ce service l'épinglent avec des JPEG dont ils écrivent l'EXIF à la
main.

**Où ça vit.** La mesure est écrite à l'arrivée de la photo
(`routes/chat.ts`, trois champs de `entries`) ; le choix est la requête
`tripInclude` de `routes/home.ts`, et non une fonction — l'accueil lit la
couverture de chaque voyage à chaque ouverture. Les photos d'avant la mesure se
rattrapent avec `npm run photos:mesurer`.

## 0 bis. Le format, et l'adresse — *implémentées* (11/11/2026)

**Deux pannes muettes suffisaient à sortir un carnet sans une seule photo.**
Hugo : « lors de la confection des PDF, les photos n'apparaissent pas. » Les
deux sont invisibles côté app : la photo s'y affiche partout, et ne manque
qu'au livre.

### Le HEIC ne se peint pas

Le carnet est composé par un **Chromium** — le nôtre en rendu local, celui
d'APITemplate en production —, et Chromium **ne décode pas le HEIC**. Pire, il
ne le dit pas : l'`<img>` se déclare `complete`, n'émet **aucun** évènement
`error`, et reste à `naturalWidth: 0`. La page se compose sans la photo, le
rendu se déclare prêt.

Or le HEIC arrivait : la photothèque d'un iPhone garde ses photos en « haute
efficacité », et l'app envoyait les octets du fichier **tels quels**, sous un
nom en `.jpg` et un `content-type: image/jpeg`. Le mensonge ne se voyait nulle
part, iOS décodant le HEIC sans broncher.

Trois endroits le corrigent, et il faut les trois :

| Où | Quoi |
|---|---|
| `ios/.../PhotoEncoding.swift`, `android/.../PhotoFlow.galleryJpeg` | la photo choisie part en JPEG, jamais dans le format de la photothèque. ⚠️ Par ImageIO côté iOS (`CGImageDestinationAddImageFromSource`) et non `UIImage.jpegData`, qui perd le drapeau EXIF et couche les photos verticales |
| `backend/src/services/photoFormat.ts` | **on ne croit pas le type déclaré, on lit les octets** : tout ce que Chromium ne peint pas est converti en JPEG à l'arrivée (conversation, souvenirs, couverture imprimée). Le décodeur est `heic-decode` (libheif en WebAssembly) : les binaires précompilés de `sharp` lisent l'AVIF mais **pas** le HEIC d'un iPhone, faute de `libde265`, et `jimp` ne connaît pas le conteneur |
| `backend/src/services/renderPhotos.ts` | les photos **déjà en stock** sont converties au premier carnet qui les demande, une fois. Le format se reconnaît sur seize octets (`storage.firstBytes`), pas en rapatriant le fichier. L'original est gardé (`originalStorageKey`) |

Une photo convertie redevient au passage candidate à la couverture du voyage :
`measurePhoto` ne sait pas lire un HEIC, et laissait `photoIsLandscape` à
`null`.

`settle()` rend désormais **les images que Chromium n'a pas peintes**, et
`npm run render:local` les affiche. `test/photosDuCarnet.test.ts` tient le
diagnostic : un vrai carnet composé, où le HEIC déguisé ne se peint pas et la
même photo convertie se peint.

### Une photo doit être joignable

Le payload portait l'URL rendue par `publisher.publish` — le CDN Webflow.
Sans `WEBFLOW_API_TOKEN`, c'est-à-dire sur **toute machine de développement**
et sur un déploiement où la variable manque, le publicateur est *simulé* : il
rendait une adresse `https://cdn.example.test/…` que rien ne sert. Le PDF se
composait, se déclarait prêt, et n'avait pas une photo.

Désormais, faute de CDN, la photo se sert **par l'API elle-même** —
`GET /v1/trip-photos/:file`, déjà publique, déjà utilisée par l'app
(`AssetPublisher.servesPublicUrls`). Un échec de publication retombe sur la
même adresse au lieu de faire échouer la composition.

⚠️ **Le service qui compose doit donc connaître son adresse publique.** Le
worker n'a pas de domaine, donc pas de `RAILWAY_PUBLIC_DOMAIN` ; il se rabat
alors sur `APP_LINK_BASE_URL`, qui vaut l'adresse de l'API aujourd'hui — mais
qui est faite pour les liens des e-mails et peut changer sans que personne ne
pense au carnet. Poser `API_PUBLIC_BASE_URL` sur le worker ferme la question
(voir `docs/deploiement.md`). Une adresse en boucle locale en production est
journalisée en `error`.

## 0 ter. Le sticker découpé dans la photo — *implémenté* (12/11/2026)

Hugo, 10/11/2026 : « stickers découpés depuis tes vraies photos de billets et
tampons ».

Un billet de train, un tampon de passeport, une étiquette de bagage : ce sont
des souvenirs **plats**. Ils font de mauvaises photos pleine page — on imprime
un bout de table — et d'excellents stickers. Le carnet y gagne deux fois.

**On découpe, on ne fait pas redessiner.** Un modèle d'images réinventerait le
texte du billet ; la décision et son prix sont dans
`docs/modeles-ia.md` § « Les stickers : le modèle choisit, il ne dessine pas ».

Trois pièces, une responsabilité chacune :

| Pièce | Ce qu'elle fait |
|---|---|
| `services/stickerVision.ts` | **l'œil** — un modèle de vision regarde les photos réduites à 512 px et rend, pour celles qui portent un souvenir plat, ses **quatre coins** et un libellé. Il refuse les visages, les papiers d'identité et les captures d'écran |
| `services/stickerEdges.ts` | **le mètre** — reprend l'indication du modèle et la resserre sur l'objet lui-même, par les pixels : couleur du fond aux quatre coins, masque, plus grande tache, rectangle le plus serré, de travers s'il le faut |
| `services/stickerCut.ts` | **les ciseaux** — `sharp` découpe le quadrilatère dans l'originale, pose une bordure blanche régulière et une ombre douce, et rend un PNG transparent. Aucun réseau, entièrement testé |
| `services/photoStickers.ts` | **la chaîne** — va chercher, montre, découpe, range le PNG et écrit la ligne |

Quatre coins et non une boîte : un billet posé sur une table est de travers,
et un rectangle droit autour de lui emporterait la nappe. On ne le redresse
pas pour autant — un sticker penché est un sticker collé.

**Le modèle reconnaît, les pixels cadrent** (12/11/2026). À la première vraie
photo essayée — une carte d'embarquement AirAsia sur une table grise — le
modèle a répondu « billet d'avion, score 90 », ce qui est juste, puis a rendu
`0,10 → 0,90` en x et `0,15 → 0,85` en y : une boîte ronde, centrée,
générique. Le sticker en est sorti avec de la table des deux côtés et les deux
bouts du billet coupés. Placer un bord au pixel près n'est pas un travail de
modèle de langue ; c'est une mesure, et `stickerEdges.ts` la fait. Chacune de
ses étapes peut renoncer : on garde alors les coins du modèle, approximatifs
valant mieux qu'absents.

⚠️ **`sharp` ne décode pas le HEIC**, le format par défaut d'un iPhone : il en
lit les métadonnées et échoue au décodage, faute de HEVC dans ses binaires. La
chaîne passe donc par `toRenderablePhoto` (§ 0 bis) avant les ciseaux, et le
découpage a lieu **après** la boucle de conversion de `jobs/structure.ts`.
Sans ça, la fonctionnalité ne marchait sur presque aucune vraie photo, en
silence — trouvé à la première photo essayée, pas en suite de tests.

Pour essayer la chaîne entière sur une photo, sans monter le back-end :

```bash
npx tsx scripts/essayer-un-sticker.ts <photo> [dossier de sortie]
```

**Une fois, et pas à chaque carnet.** La photo porte la date où on l'a
regardée (`entries.stickerCheckedAt`), le sticker reste (`photo_stickers`). Un
carnet en porte **quatre au plus**, et chacun se pose sur l'étape de sa photo,
jamais sur la page qui la montre déjà (`mise-en-page.js`, `famillesDe`).

**Rien de tout ça n'a le droit de faire échouer un carnet** : c'est de la
décoration. Modèle en panne, photo illisible, stockage qui refuse — on
journalise et la composition continue avec les stickers de la bibliothèque.

Le PNG se sert par `GET /v1/trip-stickers/:file`, comme les photos de la
conversation (§ 0 bis), et s'efface avec le voyage, le compte ou la photo
(`services/deletion.ts`).

## 1. Contrôle de qualité

Une photo de carnet est imprimée en A5. Une image de 800 px de large étalée sur
une demi-page rend **73 dpi** : c'est visible à l'œil nu sur le papier, et c'est
irrattrapable une fois le livre imprimé. Le contrôle doit donc arriver **avant**
la mise en page, pas après.

Trois mesures, dans cet ordre :

| Mesure | Seuil | Pourquoi |
|---|---|---|
| **Résolution effective** | ≥ 200 dpi à la taille d'affichage prévue | En dessous, l'impression pixellise |
| **Netteté** (variance du laplacien) | seuil à calibrer sur un lot réel | Écarte les photos floues ou bougées |
| **Exposition** (histogramme) | < 60 % des pixels dans les 5 % extrêmes | Écarte les photos cramées ou noires |

La résolution effective se calcule à partir du layout : une photo de galerie
occupe 160 pt de haut, soit 2,2 pouces — il lui faut 445 px de haut pour tenir
les 200 dpi. **C'est le layout qui fixe l'exigence**, pas une valeur absolue.

Verdict en trois états, jamais un simple rejet :

- **`ok`** — utilisable telle quelle.
- **`upscale`** — nette et bien exposée, mais trop petite. Candidate à
  l'agrandissement.
- **`downgrade`** — utilisable seulement dans un emplacement plus petit. L'agent
  de mise en page la déplace vers une vignette plutôt que de l'écarter.
- **`reject`** — floue ou inexploitable. L'utilisateur est prévenu, la photo
  n'est jamais supprimée.

## 2. Agrandissement

À déclencher **uniquement** sur le verdict `upscale`, et jamais en aveugle : un
agrandissement sur une photo floue amplifie le flou.

Deux voies, à arbitrer :

- **Local** (Real-ESRGAN ou équivalent) : pas de coût par image, pas de données
  qui sortent, mais un modèle à héberger et du GPU.
- **API** : simple à brancher, coût par image, et les photos des utilisateurs
  transitent chez un tiers — à valider côté RGPD avant tout engagement.

Dans les deux cas, l'agrandissement se place **après** la sélection photo et
**avant** la publication sur le CDN, dans un nouveau job de la file
(`memobook.enhance`), entre `structure` et `render`. L'original est conservé :
un agrandissement raté doit pouvoir être annulé.

## 3. Scotch et recadrage : ne pas masquer l'essentiel

Le scotch se pose sur un coin ou sur le bord supérieur de la photo. Posé au
hasard, il finit un jour sur un visage.

La règle est de **détecter les zones à préserver, puis choisir le coin le plus
vide** :

1. Détection de visages (Vision côté iOS, ou une passe serveur) → boîtes à
   préserver.
2. À défaut de visage, carte de saillance grossière : découper l'image en une
   grille 3 × 3 et retenir la case de plus faible variance.
3. Le scotch se pose sur le coin dont la case est la plus vide, et le recadrage
   `object-fit: cover` est décalé (`object-position`) pour garder les boîtes à
   préserver dans le cadre.

Le résultat est un champ par photo dans le payload, calculé par le back-end et
non par l'agent :

```json
{ "url": "…", "tape_corner": "top-left", "focus": { "x": 0.42, "y": 0.31 } }
```

`focus` alimente `object-position`, `tape_corner` choisit la variante de scotch.
Sans ces champs, le gabarit retombe sur un centrage neutre et un scotch en haut
à gauche — jamais une erreur, seulement un rendu moins fin.

### Le plafond de rognage et les photos de groupe

Le recadrage `cover` est borné (`LAYOUT_KB.md`, § « Rognage des photos ») :

- **jamais plus d'un tiers de l'image perdu** — au-delà, la photo passe en
  `fit: "contain"` : réduite, entière, le contour dessiné ajusté à elle ;
- **une photo de groupe n'est jamais rognée** — trois visages ou plus, ou la
  case « Photo de groupe » cochée dans l'atelier ;
- **chaque visage reste entier dans le cadre** — sinon `contain`.

La détection de visages est ce qui permettra d'appliquer les deux dernières
règles sans demander au voyageur : nombre de visages (groupe ou pas) et boîtes
à garder dans le cadre. D'ici là, l'atelier se fie à la case cochée et garde le
haut des photos rognées verticalement (`focus` à 30 %).

## 4. Où ça se branche

```
transcribe → structure → [enhance] → render
                            ↑
                  qualité, agrandissement,
                  visages, point de focus
```

Le job `enhance` n'existe pas encore. Il se déclarerait dans
`backend/src/jobs/queue.ts` à côté des trois autres, et lirait les seuils dans
`MemoBook Generator/templates/travel-journal/print.json` — c'est le layout qui fixe l'exigence de
résolution, donc elle vit avec la géométrie.
