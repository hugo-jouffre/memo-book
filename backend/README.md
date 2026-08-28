# Back-end MemoBook

L'API et le pipeline qui transforment des vocaux en carnet imprimable.

```
Entry ──transcribe──▶ transcript ──redact──▶ texte ──structure──▶ payload ──render──▶ PDF
         OpenAI                    Claude      ▲       LLM + schémas     APITemplate.io
                                   + règles    │       du dépôt
                                   du dépôt    │
                                        correction au clavier
                                        dans l'app (PATCH)
```

**Deux passes de modèle, volontairement séparées.** `redact` écrit le texte d'une
étape, une étape à la fois, en suivant `agents/agent-transcription.md` — pendant que
l'utilisateur est là pour relire. `structure` met en page l'ensemble du carnet à la
prévisualisation, en suivant `templates/travel-journal/LAYOUT_KB.md`, et **ne réécrit
rien**. Les fusionner reviendrait à réécrire, à chaque aperçu PDF, un texte que
l'utilisateur a corrigé à la main.

Les deux prompts sont construits à partir des fichiers Markdown du dépôt : corriger
une règle de rédaction est une modification de Markdown, pas de TypeScript.

## Démarrer

```bash
docker compose up -d          # Postgres + MinIO
cp .env.example .env
npm ci
npx prisma migrate dev
npm run dev                   # API + workers sur http://localhost:3000
```

`GET /health` répond `200` avec l'état de la base, de la file et le mode du pipeline.

**Sans aucune clé d'API**, le back-end démarre quand même : `PIPELINE_MODE=auto` bascule
sur des implémentations simulées et déterministes de la transcription, de la structuration
et du rendu, et le stockage des médias passe en mémoire faute de configuration S3. Seule
`DATABASE_URL` est réellement indispensable.

Renseigne `OPENAI_API_KEY` et `APITEMPLATE_API_KEY` pour passer en réel, et les `S3_*` pour
que les vocaux survivent à un redémarrage. En production (`NODE_ENV=production`), l'absence
de configuration S3 empêche le démarrage plutôt que de perdre silencieusement des vocaux.

```bash
npm run db:seed               # un carnet de démonstration + un token à utiliser en curl
```

## Vérifier

```bash
npm run typecheck
npm run lint
npm test                      # 42 tests — nécessite Postgres
npm run smoke                 # le parcours complet, tout simulé
npm run smoke -- --live       # le même parcours contre OpenAI + APITemplate, affiche l'URL du PDF
```

Le test le plus important fait passer `templates/travel-journal/data.json` — le payload qui
alimente APITemplate aujourd'hui — dans le validateur. S'il cesse d'être accepté, c'est le
validateur qui a tort.

## Travailler sur la mise en page du carnet

Le template vit dans `templates/travel-journal/`. Pour l'itérer sans appeler APITemplate :

```bash
npm run template:lint                       # dialecte Jinja + invariants CSS
npm run render:local -- --offline --png     # PDF A5 + un PNG par page, ~2 s, sans réseau
npm run render:watch                        # re-rendu à chaque sauvegarde
npm run render:local -- --profile print     # fond blanc imprimeur (défaut : crème d'aperçu)
npm run test:visual                         # diff pixel contre les captures de référence
npm run test:visual:update                  # régénère les captures après un changement voulu
npm run fonts:build                         # régénère fonts.css depuis Google Fonts
npm run inspector                           # inspecteur HTML : nomme chaque élément au survol
npm run icons:build                         # embarque assets/icons/ dans index.html
npm run icons:check                         # échoue si le sprite est périmé
```

`npm run inspector` produit `.render-out/inspecteur.html`, une page autonome qui affiche le
carnet rendu et, au survol de n'importe quel élément, donne son nom, son sélecteur CSS, les
champs JSON qui l'alimentent et les variables CSS en jeu. Elle sert à formuler des demandes de
retouche précises plutôt que « le bloc avec la pince est trop haut ». Le dictionnaire des
composants vit dans `scripts/build-inspector.ts` : il se met à jour en même temps que le
template, et `templates/travel-journal/samples/showcase.json` est le payload qui exerce tous
les layouts d'un coup.

Les sorties atterrissent dans `.render-out/` (ignoré par Git).

**Pourquoi un rendu local alors qu'APITemplate existe.** Viser la fidélité aux maquettes Figma
demande des dizaines d'allers-retours ; à travers une API distante, chacun coûte un push, un
appel réseau et un téléchargement, et rien ne permet de comparer deux rendus. En local, le même
`index.html` + `style.css` — les artefacts exacts envoyés à APITemplate — rendent en deux
secondes et se comparent au pixel près.

**Pourquoi c'est fiable.** APITemplate rend du Jinja2, le harnais local du Nunjucks. Les deux
moteurs diffèrent sur trois points qui comptent (`[]` faux en Jinja et vrai en JS, `null`
imprimé « None », littéraux Python). `scripts/lint-template.ts` interdit ces constructions, et
`test/templateDialect.test.ts` exécute le **vrai Jinja2 Python** sur le même gabarit pour
vérifier que les deux sorties sont identiques.

Ce que le local ne garantit pas : la version de Chromium d'APITemplate et le réglage de papier
de son tableau de bord. Voir `docs/apitemplate.md`, section « Calibration ».

### Rendre un PDF depuis le pipeline complet

`RENDERER` est un axe distinct de `PIPELINE_MODE` : le premier choisit le moteur PDF, le second
la transcription et la structuration. La combinaison utile en développement est « transcription
simulée, vrai PDF » :

```bash
PIPELINE_MODE=fake RENDERER=local npm run dev
```

Les PDF sont servis sur `/v1/local-renders/:file`, une route qui n'existe que dans ce mode —
l'app iOS télécharge `pdfUrl` en HTTP simple, un chemin `file://` ne lui servirait à rien.

## L'API

Toutes les routes `/v1` attendent un `Authorization: Bearer <token>` d'appareil, sauf
`POST /v1/devices` qui le délivre.

| Route | Rôle |
| --- | --- |
| `POST /v1/devices` | Enregistre l'appareil, renvoie son token (une seule fois, en clair) |
| `GET /v1/memos` | Les carnets de l'appareil |
| `POST /v1/memos` | Crée un carnet |
| `GET /v1/memos/:id` | Un carnet, ses souvenirs et ses générations |
| `DELETE /v1/memos/:id` | Supprime un carnet |
| `POST /v1/memos/:id/entries` | Ajoute un souvenir — JSON pour une note, multipart pour un vocal ou une photo |
| `GET /v1/entries/:id` | Statut, transcription et texte rédigé d'un souvenir |
| `PATCH /v1/entries/:id` | Corrige le texte à la main. `editedText: null` revient à la version proposée |
| `POST /v1/entries/:id/redaction` | Redemande une rédaction (refusé si le texte a été corrigé) |
| `DELETE /v1/entries/:id` | Supprime un souvenir |
| `POST /v1/memos/:id/renders` | Lance la génération du carnet (202, résultat asynchrone) |
| `GET /v1/renders/:id` | Suit la génération, renvoie l'URL du PDF |
| `POST /v1/memos/:id/orders` | Commande le carnet imprimé, sur un rendu déjà généré |
| `GET /v1/memos/:id/orders` | Les commandes d'un carnet |
| `GET /v1/orders/:id` | Suit une commande |

> **Authentification** — le token d'appareil est un provisoire assumé, le temps que les
> comptes utilisateur arrivent. Tout est concentré dans `src/plugins/auth.ts` : c'est le
> seul fichier à remplacer, les routes ne connaissent que `request.deviceId`.

## Où regarder

| Fichier | Ce qu'il fait |
| --- | --- |
| `src/lib/templates.ts` | Charge `gpt_image_schema.yaml` et `LAYOUT_KB.md` depuis `templates/`, et les règles de rédaction depuis `agents/` |
| `src/services/payloadValidator.ts` | Valide le carnet — schéma **et** limites de longueur de LAYOUT_KB |
| `src/services/redaction.ts` | Transcription → texte de carnet (Claude, piloté par `agents/agent-transcription.md`) |
| `src/services/structuring.ts` | Textes validés → payload de mise en page (LLM, avec repli heuristique) |
| `src/services/transcription.ts` | Audio → texte |
| `src/services/apitemplate.ts` | Payload → PDF via APITemplate, et choix du moteur de rendu |
| `src/services/bookPdf.ts` | Payload → PDF en local (Nunjucks + Chromium) |
| `src/services/localRenderer.ts` | Le moteur local branché sur le pipeline (`RENDERER=local`) |
| `scripts/render-local.ts` | La commande d'itération sur la mise en page |
| `scripts/lint-template.ts` | Empêche le gabarit de diverger entre Jinja2 et Nunjucks |
| `scripts/build-icons.ts` | Embarque `assets/icons/` dans le gabarit — voir `assets/README.md` |
| `scripts/build-inspector.ts` | L'inspecteur de mise en page, et le dictionnaire des composants |
| `src/services/webflow.ts` | Publie les photos sur le CDN (APITemplate a besoin d'URLs publiques) |
| `src/jobs/` | Les quatre étapes du pipeline, sur une file pg-boss adossée à Postgres |
| `src/lib/pgConnection.ts` | Traduit le `DATABASE_URL` (dialecte Prisma) pour node-postgres — le TLS de la base managée |

### Pourquoi valider les longueurs côté serveur

`LAYOUT_KB.md` fixe des maximums par paragraphe (420 caractères pour `body_html`, 140 pour un
fun fact, 80 pour un highlight). Ce ne sont pas des préférences de style : au-delà, le texte
déborde de la page, et ça ne se voit qu'une fois le PDF imprimé. Le validateur les refuse
avant l'appel à APITemplate, et la structuration par LLM reçoit les erreurs pour se corriger.

## Production

Deux process : `npm start` (API) et `npm run worker` (pipeline). En développement, `npm run dev`
porte les deux pour n'avoir qu'une commande à lancer.

La base est un **PostgreSQL 16 managé Scaleway, région `fr-par`** : création de l'instance,
`DATABASE_URL`, TLS, migrations et sauvegardes sont dans [`docs/database.md`](../docs/database.md).
Deux points à connaître avant de toucher à la configuration :

- les paramètres TLS du `DATABASE_URL` sont écrits dans le dialecte **Prisma**, le seul que
  `prisma migrate deploy` sache lire ; `src/lib/pgConnection.ts` les traduit pour pg-boss, qui
  passe par node-postgres et interpréterait `sslcert` comme un certificat *client* ;
- en production, un `DATABASE_URL` sans `sslmode` empêche le démarrage. La base est jointe par
  l'internet public : une connexion en clair y ferait passer des transcriptions de vocaux.
