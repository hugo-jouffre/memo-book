# Photos : qualité, recadrage, scotch

Ce que le pipeline doit garantir avant qu'une photo arrive dans un carnet.
Les sections 1 à 4 sont une **spécification** : rien n'en est encore
implémenté. La section 0, elle, tourne.

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
