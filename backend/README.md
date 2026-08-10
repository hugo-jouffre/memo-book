# Back-end MemoBook

L'API et le pipeline qui transforment des vocaux en carnet imprimable.

```
Entry (audio) ──transcribe──▶ transcript ──structure──▶ payload ──render──▶ PDF
                 OpenAI                    LLM + schémas      APITemplate.io
                                           du dépôt
```

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
npm test                      # 37 tests — nécessite Postgres
npm run smoke                 # le parcours complet, tout simulé
npm run smoke -- --live       # le même parcours contre OpenAI + APITemplate, affiche l'URL du PDF
```

Le test le plus important fait passer `templates/travel-journal/data.json` — le payload qui
alimente APITemplate aujourd'hui — dans le validateur. S'il cesse d'être accepté, c'est le
validateur qui a tort.

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
| `GET /v1/entries/:id` | Statut et transcription d'un souvenir |
| `DELETE /v1/entries/:id` | Supprime un souvenir |
| `POST /v1/memos/:id/renders` | Lance la génération du carnet (202, résultat asynchrone) |
| `GET /v1/renders/:id` | Suit la génération, renvoie l'URL du PDF |

> **Authentification** — le token d'appareil est un provisoire assumé, le temps que les
> comptes utilisateur arrivent. Tout est concentré dans `src/plugins/auth.ts` : c'est le
> seul fichier à remplacer, les routes ne connaissent que `request.deviceId`.

## Où regarder

| Fichier | Ce qu'il fait |
| --- | --- |
| `src/lib/templates.ts` | Charge `gpt_image_schema.yaml` et `LAYOUT_KB.md` depuis `templates/` |
| `src/services/payloadValidator.ts` | Valide le carnet — schéma **et** limites de longueur de LAYOUT_KB |
| `src/services/structuring.ts` | Transforme les transcriptions en payload (LLM, avec repli heuristique) |
| `src/services/transcription.ts` | Audio → texte |
| `src/services/apitemplate.ts` | Payload → PDF |
| `src/services/webflow.ts` | Publie les photos sur le CDN (APITemplate a besoin d'URLs publiques) |
| `src/jobs/` | Les trois étapes du pipeline, sur une file pg-boss adossée à Postgres |

### Pourquoi valider les longueurs côté serveur

`LAYOUT_KB.md` fixe des maximums par paragraphe (420 caractères pour `body_html`, 140 pour un
fun fact, 80 pour un highlight). Ce ne sont pas des préférences de style : au-delà, le texte
déborde de la page, et ça ne se voit qu'une fois le PDF imprimé. Le validateur les refuse
avant l'appel à APITemplate, et la structuration par LLM reçoit les erreurs pour se corriger.

## Production

Deux process : `npm start` (API) et `npm run worker` (pipeline). En développement, `npm run dev`
porte les deux pour n'avoir qu'une commande à lancer.
