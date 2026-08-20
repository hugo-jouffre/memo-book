# CLAUDE.md — mémoire du projet MemoBook

Ce fichier est lu au début de chaque session Claude Code. Il dit **où vit la vérité** et
**ce qu'on ne fait jamais**. Il ne recopie pas les valeurs qui vivent ailleurs : un chiffre
présent à deux endroits finit toujours par diverger.

## Le produit

MemoBook transforme des **souvenirs** racontés à la voix en un **carnet** mis en page,
partageable et imprimable. Le voyageur parle pendant sa journée ; l'app transcrit, un agent
rédige, un autre met en page, et le carnet part en PDF puis à l'impression.

### Vocabulaire, sans exception

- On dit **carnet**, jamais « livre ». **Souvenir**, jamais « note » ni « entrée ».
  **Voyageur**, **famille**.
- Les noms internes **Stories** et **News** n'apparaissent **jamais** dans l'interface.
- **On tutoie l'utilisateur. Partout.** Écrans, messages d'erreur, notifications, mails
  transactionnels, textes produits par les agents IA. « Vérifie ton adresse email », jamais
  « Veuillez vérifier votre adresse ». Le vouvoiement est réservé aux supports externes
  (decks investisseurs), pas au produit.
- Tout est en français, avec les apostrophes typographiques (`’`).

## Le dépôt

| Dossier | Rôle |
|---|---|
| `ios/` | L'app iOS (SwiftUI, iOS 17+, Swift 6 en concurrence stricte) |
| `backend/` | API Fastify + PostgreSQL, et le pipeline `transcrire → rédiger → relire → mettre en page → imprimer` |
| `templates/travel-journal/` | Le template PDF du carnet et ses schémas |
| `agents/` | Fiches de poste des agents IA, et le design system |
| `docs/` | Documentation transverse |
| `assets/` | Icônes, illustrations, textures |

### Où vit la vérité

Avant d'écrire du code, lire la source concernée. Ne jamais deviner, ne jamais recopier
une valeur d'un de ces fichiers dans un autre.

| Sujet | Source unique |
|---|---|
| Couleurs et typographies de **l'app** | [`agents/design.md`](agents/design.md) — miroir des variables Figma |
| Couleurs, papier et typographies du **carnet** | [`templates/travel-journal/DESIGN.md`](templates/travel-journal/DESIGN.md) — système séparé, voir ci-dessous |
| Règles d'implémentation des écrans | [`docs/ui-development.md`](docs/ui-development.md) — unités, fidélité, fiches écran |
| Tokens dans le code iOS | `ios/Modules/Sources/MemoBookDesign/Tokens.swift` et `Rem.swift` |
| Layouts du carnet, limites de longueur | `templates/travel-journal/LAYOUT_KB.md` |
| Schéma du payload de mise en page | `templates/travel-journal/gpt_image_schema.yaml` |
| Prompt système de la rédaction | `agents/agent-transcription.md` — chargé tel quel |
| Modèle de données | `backend/prisma/schema.prisma` |
| Structure du projet Xcode | `ios/project.yml` (le `.xcodeproj` n'est pas versionné) |

### Deux design systems, pas un

L'app et le carnet sont **deux systèmes séparés**, et c'est délibéré : une app est une
interface, un carnet est un objet de papier. Ils n'ont ni les mêmes polices, ni les mêmes
contraintes, ni la même unité de mesure.

| | App | Carnet |
|---|---|---|
| Fichier | `agents/design.md` | `templates/travel-journal/DESIGN.md` |
| Unité | le **rem** (1 rem = 16 pt), pour suivre le Dynamic Type | le **point** (1 unité Figma = 1 pt) — une page imprimée a une taille définitive |
| Polices | Sora, General Sans | Playfair Display, Gloria Hallelujah, Hansley |
| Accent | Green `#28654B` | `#F86015` |

Ne jamais appliquer les couleurs de l'un à l'autre, et ne jamais « harmoniser » les deux :
qu'ils diffèrent est le sujet, pas un oubli.

## Commandes

```bash
# Back-end (Node 22+)
cd backend
npm run dev            # API en local sur :3000
npm run typecheck      # les trois que la CI fait tourner
npm run lint
npm test
npm run render:offline # rend un carnet en PDF + PNG, sans clé d'API

# App iOS (macOS, Xcode)
cd ios
make project           # régénère MemoBook.xcodeproj depuis project.yml
make build
make test
```

L'app parle à `http://localhost:3000` par défaut : lancer le back-end avant.

## Architecture iOS

Le code ne vit pas dans la cible Xcode mais dans un paquet SwiftPM local, `MemoBookKit`
(`ios/Modules/`) : les modules purs se compilent et se testent sans simulateur.

```
App/                   Point d'entrée : @main, Info.plist, assets. Volontairement mince.
Modules/Sources/
├── MemoBookCore       Modèles et décodage. Aucune dépendance.
├── MemoBookDesign     Tokens (Rem, couleurs, typographies) et composants partagés.
├── MemoBookNetworking Client d'API, stockage du token, multipart.
├── MemoBookRecording  Capture audio (AVFoundation) et permissions.
└── MemoBookFeature    Écrans SwiftUI et modèles de vue.
```

SwiftUI, **MVVM avec `@Observable`**, Swift Concurrency (async/await). Les modèles de vue
dépendent du protocole `MemoBookAPI`, pas du client HTTP : `PreviewAPI` en fournit une
implémentation en mémoire, ce qui permet de travailler et tester les écrans sans back-end.

### Règles d'UI

Le détail est dans `docs/ui-development.md` — à lire **en entier** avant de toucher à un
écran. L'essentiel :

- **Toute dimension s'exprime en rem** (1 rem = 16 pt). `Rem.swift` est le seul fichier de
  l'app où un point apparaît. Aucune valeur numérique nue dans une vue.
- Marge d'écran unique : **1 rem**. Bouton et champ : 3 rem. Cible tactile : 2.75 rem mini.
- Les tailles de police se déclarent avec `relativeTo:` — jamais de taille figée, ça casse
  le Dynamic Type.
- Les traits restent en points (`Rem.hairline`) : un filet ne grossit pas avec le texte.
- **Figma est la source de vérité et ne s'améliore pas de sa propre initiative.** Une
  incohérence entre deux écrans se signale, elle ne s'harmonise pas en douce.
- Chaque écran gère quatre états : vide, chargement, erreur, nominal. Ce qui n'est pas
  maquetté se signale, ne s'invente pas.

## Back-end

Node/TypeScript (Fastify) + PostgreSQL, ORM Prisma, file d'attente pg-boss adossée à
Postgres — pas un BaaS : le pipeline enchaîne des tâches longues qui demandent une reprise
sur échec. Les routes existantes sont dans `backend/src/routes/` : `devices`, `memos`,
`entries`, `renders`, `orders`, `health`.

`PIPELINE_MODE=fake` court-circuite OpenAI et APITemplate avec des implémentations
déterministes : c'est ce qui permet de tester le pipeline sans clé ni réseau.

## Conventions

- **Une branche par ticket, PR obligatoire.** `main` est protégée.
- **Messages de commit en français, à l'impératif, sans préfixe** `feat:` / `chore:` /
  `docs:`. Le sujet dit ce que le commit change pour le produit, pas ce qu'il touche dans
  le code. Le corps explique pourquoi, quand ce n'est pas évident.
- La CI back-end (typecheck, lint, tests) doit être verte. Il n'y a **pas encore** de CI
  iOS : lancer `make build` et `make test` soi-même.
- Une PR d'écran contient une capture de l'écran implémenté à côté de la maquette Figma.

## À ne jamais faire

- Mettre un secret dans le code ou dans le dépôt. Les clés OpenAI, Anthropic et APITemplate
  vivent **uniquement** côté serveur.
- Coder une couleur ou une dimension en dur dans une vue au lieu d'un token.
- Vouvoyer l'utilisateur.
- Inventer un endpoint côté app en supposant qu'il existe : vérifier `backend/src/routes/`.
- Réécrire le texte d'un souvenir corrigé par le voyageur — même maladroit, il est
  intouchable (voir `agents/agent-layout.md`).
- Émettre `null` dans un payload de mise en page : Jinja2 imprime « None » dans le carnet.
  Omettre la clé.
- Faire un `force unwrap` dans du code de production.
- Livrer un écran sans label VoiceOver en français sur les éléments interactifs.

## Ce qui n'existe pas encore

Pas d'authentification (l'app s'enregistre comme un appareil anonyme via
`POST /v1/devices`), pas d'onboarding, pas de paywall, pas de réglages. Le chemin critique,
lui, tourne de bout en bout : enregistrer → transcrire → rédiger → mettre en page → PDF.

Les arbitrages ouverts sont listés dans
[`docs/ui-development.md` §7.2](docs/ui-development.md#72-ce-qui-reste-ouvert) — le plus
bloquant étant le modèle d'authentification.
