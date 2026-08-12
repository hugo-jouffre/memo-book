# APITemplate.io — notes d'intégration MemoBook

Ce que le dépôt utilise de l'API, et pourquoi.

> ⚠️ **Statut de vérification.** Les sessions Claude Code sur ce dépôt ont
> `apitemplate.io` bloqué par le proxy réseau : la documentation officielle
> n'a pas pu être lue directement. Ce qui suit vient de
> `templates/travel-journal/gpt_image_schema.yaml`, du workflow de
> synchronisation et du code du back-end. Les points marqués **À VÉRIFIER**
> doivent être confirmés sur <https://apitemplate.io/apiv2/> depuis un poste
> non filtré, puis corrigés ici.

## Compte et région

| Élément | Valeur |
|---|---|
| Région | **DE** — `https://rest-de.apitemplate.io/v2` |
| Template id | `7a177b23210099d6` |
| En-tête d'authentification | `X-API-KEY: <clé>` |

**La région n'est pas cosmétique** : appeler `rest.apitemplate.io` avec une clé
d'un compte DE renvoie une erreur d'authentification, pas une redirection. Le
dépôt pointait sur la mauvaise région ; c'est corrigé dans `env.ts`
(`APITEMPLATE_BASE_URL`) et dans `.github/workflows/sync-apitemplate.yml`.

Autres régions connues : `rest.apitemplate.io` (défaut / US),
`rest-sg.apitemplate.io` (Singapour). **À VÉRIFIER** : liste complète.

## Secrets

Jamais dans le dépôt ni dans l'app. Deux emplacements :

- **GitHub** — *Settings → Secrets and variables → Actions* :
  `APITEMPLATE_API_KEY`, `APITEMPLATE_TEMPLATE_ID`. Le job de synchronisation
  tourne à chaque `push` sur `main` touchant le template ; tant que le secret
  est absent, une étape de garde le fait passer sans rien envoyer, en laissant
  une notice dans le run. Il s'activera donc de lui-même dès le secret posé.

  > ⚠️ Cette garde vit dans une **étape**, pas dans le `if:` du job. Le contexte
  > `secrets` n'existe pas au niveau job : GitHub refuse d'évaluer l'expression
  > et le run échoue instantanément, sans exécuter le moindre job. C'était le
  > cas de ce workflow jusqu'au 11 août 2026.
- **Back-end** — `.env`, voir `backend/.env.example`.

> 🔐 Toute clé ayant transité par un chat, un ticket ou un commit est à
> considérer comme compromise : la régénérer depuis le tableau de bord
> APITemplate avant de la poser en secret.

## Les deux appels utilisés

### `POST /v2/create-pdf?template_id=<id>`

Génère le PDF. Corps = le payload JSON du carnet, tel quel.
Implémenté par `ApiTemplateRenderer` dans
`backend/src/services/apitemplate.ts`.

```bash
curl -X POST "https://rest-de.apitemplate.io/v2/create-pdf?template_id=7a177b23210099d6" \
  -H "Content-Type: application/json" \
  -H "X-API-KEY: $APITEMPLATE_API_KEY" \
  -d @templates/travel-journal/data.json
```

Réponse attendue :

```json
{
  "status": "success",
  "download_url": "https://...pdf",
  "transaction_ref": "..."
}
```

Le back-end exige `status === "success"` **et** un `download_url` : un 200 sans
URL est traité comme un échec, parce qu'un rendu silencieusement vide serait
pire qu'une erreur.

**À VÉRIFIER** : l'objet `settings` (taille de papier, marges, orientation,
`print_background`) et les options `async`, `webhook_url`, `expiration`,
`cloud_storage`, `filename`. Le template définit déjà sa géométrie par une
règle `@page` (420 × 595 pt) ; reste à confirmer que le réglage du tableau de
bord ne la surcharge pas — voir « Calibration » plus bas.

### `POST /v2/update-template`

Pousse le template. Appelé par `.github/workflows/sync-apitemplate.yml` sur
chaque `push` vers `main` touchant le template.

```json
{ "template_id": "...", "body": "<html>…", "css": "<style>…" }
```

**Le champ `css` est la concaténation de `fonts.css` puis `style.css`**, dans
cet ordre. C'est exactement ce que fait `loadTemplateCss()` côté back-end.
Envoyer `style.css` seul ferait perdre toutes les polices en production sans
aucune erreur : le texte retomberait sur une police système.

## Contraintes qui pilotent la conception du template

APITemplate ne reçoit que **deux chaînes** : `body` et `css`. Aucun fichier
joint, aucun chemin relatif résolu. D'où trois choix du dépôt :

1. **Polices inlinées en base64** dans `fonts.css`
   (`backend/scripts/build-font-css.ts`). Un CDN marcherait aussi, mais rendrait
   le rendu dépendant du réseau et intestable hors ligne.
2. **Formes dessinées en SVG inline** (ruban, pince, icônes météo, tracé
   pointillé) plutôt qu'en images distantes.
3. **Grain du papier en `feTurbulence` inline** plutôt qu'en AVIF hébergé.

`style.css` doit rester un **fragment HTML** : un `<meta name="viewport">` puis
exactement une paire `<style>…</style>`. APITemplate injecte le champ verbatim
dans le document. `backend/scripts/lint-template.ts` vérifie cet invariant.

## Moteur de gabarit

APITemplate rend du **Jinja2**. Le rendu local utilise **Nunjucks**, très
proche mais pas identique. Trois écarts réels, tous clôturés par le lint et le
test-oracle (`backend/test/templateDialect.test.ts`, qui exécute le vrai Jinja2
Python et compare les deux sorties) :

| Écart | Jinja2 | Nunjucks |
|---|---|---|
| `[]` dans un `{% if %}` | **faux** | **vrai** |
| `null` interpolé | imprime `None` | chaîne vide |
| `True` / `False` / `None` | littéraux valides | erreur |

## Calibration de la géométrie — à faire une fois

Le format de page peut aussi être réglé dans le tableau de bord APITemplate,
en dehors de ce dépôt. Tant que ce n'est pas vérifié, il existe deux sources de
vérité, ce qui finira par produire des pages décalées.

Procédure, dès que la clé est posée :

1. Lancer un `create-pdf` réel sur `data.json`.
2. `pdfinfo` sur le résultat : il doit annoncer `420 x 595 pts (A5)`.
3. Si l'écart dépasse un point, aligner le tableau de bord sur la règle
   `@page` du template — pas l'inverse : la géométrie doit vivre dans
   l'artefact que les deux moteurs consomment.
4. Passer `apitemplate.calibrated` à `true` dans
   `templates/travel-journal/print.json`.

## Ce que le rendu local ne garantit pas

Le harnais local certifie *le template*, pas *la sortie d'APITemplate*. Restent
hors de portée :

- la version de Chromium employée par APITemplate, inconnue et mouvante ;
- le réglage de papier du tableau de bord (voir ci-dessus) ;
- la police d'emoji du service, si le payload en contient.

La seule mesure réelle de l'écart est un diff pixel entre le PDF local et le
PDF d'APITemplate, à faire après la calibration.

## Codes d'erreur

**À VÉRIFIER** : la liste officielle et les limites de débit. Observé côté
back-end : `401` clé invalide, `403` clé valide mais droits insuffisants,
`400` payload refusé. Le renderer remonte le champ `message` de la réponse.
