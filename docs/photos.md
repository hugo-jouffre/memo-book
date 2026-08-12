# Photos : qualité, recadrage, scotch

Ce que le pipeline doit garantir avant qu'une photo arrive dans un carnet.
Rien de ce document n'est encore implémenté — c'est la spécification.

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

## 4. Où ça se branche

```
transcribe → structure → [enhance] → render
                            ↑
                  qualité, agrandissement,
                  visages, point de focus
```

Le job `enhance` n'existe pas encore. Il se déclarerait dans
`backend/src/jobs/queue.ts` à côté des trois autres, et lirait les seuils dans
`templates/travel-journal/print.json` — c'est le layout qui fixe l'exigence de
résolution, donc elle vit avec la géométrie.
