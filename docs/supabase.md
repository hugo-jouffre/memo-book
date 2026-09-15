# Héberger MemoBook sur Supabase

Ce que Supabase porte, comment le configurer, et comment en partir le jour venu.

Supabase est ici un **hébergement provisoire assumé** : un Postgres managé et un
bucket S3, le temps d'avoir de vraies données dans l'app. Rien de ce qui suit ne
crée de dépendance à Supabase — c'est le sujet du § 6, et c'est ce qui rend le
déménagement vers Postgres et Backblaze plus tard une affaire de variables
d'environnement.

```
                    ┌──────────── Supabase ────────────┐
   API Fastify ────▶│  Postgres     schéma public      │
   Worker pg-boss   │               schéma pgboss      │
                    │  Storage      bucket privé S3    │
                    └──────────────────────────────────┘
```

---

## 1. Ce que tu dois faire à la main

Quatre étapes dans l'interface. Le reste est automatisé par
`npm run supabase:setup`.

### a. Créer le projet

**supabase.com ▸ New project**

| Réglage | Valeur | Pourquoi |
|---|---|---|
| Name | `memobook` | |
| Database password | à générer, **à copier tout de suite** | Il n'est plus jamais affiché. Il se réinitialise dans Settings ▸ Database |
| Region | `eu-central-1` (Francfort) ou `eu-west-3` (Paris) | La latence compte : le pipeline fait des centaines d'allers-retours par carnet. Et les données restent dans l'UE |
| Plan | Free | Voir § 5 pour ce que ça implique |

### b. Récupérer la bonne chaîne de connexion

**Connect** (en haut de l'écran) ▸ onglet **ORMs** ou **Connection string**.

> **C'est ici qu'on se trompe, et ça coûte une soirée.** Supabase propose
> plusieurs chaînes. Prends **Session pooler** (port **5432**).
>
> **Pas** le *Transaction pooler* (port 6543) : il rend chaque requête à une
> session différente. Trois choses cassent alors, et aucune ne se voit tout de
> suite — les migrations Prisma, qui posent un verrou le temps de s'appliquer ;
> pg-boss, qui s'appuie sur des verrous de session pour ne pas traiter un job
> deux fois ; et les requêtes préparées. Le symptôme arrive plus tard, sous la
> forme d'un vocal transcrit deux fois.
>
> `npm run supabase:check` refuse de continuer s'il détecte le mauvais port.

La chaîne ressemble à ceci, avec `[PASSWORD]` à remplacer :

```
postgresql://postgres.abcdefgh:[PASSWORD]@aws-0-eu-central-1.pooler.supabase.com:5432/postgres
```

### c. Créer la clé d'accès S3

**Storage ▸ S3 Connection ▸ New access key**

Note les deux valeurs, la région affichée juste au-dessus, et l'URL du point
d'accès. Le secret n'est montré qu'une fois.

Le bucket, lui, est créé par le script. Si tu préfères le faire à la main :
**Storage ▸ New bucket**, nom `memobook-media`, et **laisse-le privé**. L'app ne
parle jamais à Supabase en direct : elle passe par l'API, qui délivre des URL
signées à durée limitée.

### d. Remplir le `.env`

```bash
cd backend
cp .env.example .env
```

Puis les six lignes qui comptent :

```bash
DATABASE_URL=postgresql://postgres.<ref>:<mot-de-passe>@aws-0-<region>.pooler.supabase.com:5432/postgres

S3_ENDPOINT=https://<ref>.storage.supabase.co/storage/v1/s3
S3_REGION=<la région du projet>
S3_BUCKET=memobook-media
S3_ACCESS_KEY_ID=<la clé>
S3_SECRET_ACCESS_KEY=<le secret>
S3_FORCE_PATH_STYLE=true
```

`.env` est dans `.gitignore`. Il ne doit jamais en sortir.

---

## 2. Ce que le script fait pour toi

```bash
npm run supabase:setup
```

Il est **idempotent** et ne supprime jamais rien. Le relancer sur un projet déjà
prêt se contente de le confirmer.

1. **La connexion.** Vérifie qu'elle répond, refuse le pooler en mode
   transaction, et confirme par une sonde que les verrous survivent d'une
   requête à l'autre.
2. **Les migrations.** Applique celles qui manquent.
3. **Le schéma.** Confirme qu'il n'y a pas de dérive entre `schema.prisma` et la
   base — une dérive veut dire que quelque chose a été modifié à la main dans
   l'éditeur SQL, et la prochaine migration partirait d'un état qu'elle ne
   connaît pas.
4. **Le stockage.** Crée le bucket s'il manque, puis fait un aller-retour
   complet : écriture, lecture, URL signée, suppression. Vérifier que les clés
   existent ne dit rien ; les quatre opérations que le produit utilise
   réellement, si.
5. **Les limites.** Mesure ce qui est consommé face au plan gratuit.

Pour vérifier sans rien changer :

```bash
npm run supabase:check
```

---

## 3. Mettre de vraies données, et brancher l'app

```bash
npm run db:seed
npm run dev
```

Le seed pose un compte de démonstration et de quoi remplir les trois écrans :

| | |
|---|---|
| Adresse | `demo@memobook.app` |
| Mot de passe | `memobook2026` |

Trois voyages — un en cours avec ses trois étapes et ses souvenirs, un terminé
et imprimable avec une commande en production, un à venir — une cagnotte
alimentée par son registre, un abonnement actif, les mises en avant de l'écran
de bienvenue et la modale d'avis.

Vérifie côté serveur avant de lancer Xcode :

```bash
TOKEN=$(curl -s localhost:3000/v1/auth/signin -H 'content-type: application/json' \
  -d '{"email":"demo@memobook.app","password":"memobook2026"}' | jq -r .token)

curl -H "Authorization: Bearer $TOKEN" localhost:3000/v1/home | jq
curl -H "Authorization: Bearer $TOKEN" localhost:3000/v1/profile | jq
curl localhost:3000/v1/showcases/welcome | jq
```

### Basculer les écrans du jeu d'essai vers l'API

Chaque écran reçoit une **source**, une fonction qui rend son contenu. Par
défaut c'est le jeu d'essai, ce qui laisse les aperçus SwiftUI fonctionner sans
serveur. `AppDependencies` porte les trois fabriques branchées sur le réseau, et
la bascule tient dans `RootView` :

```swift
// avant
HomeView(onIntent: handle)
ProfileView(onSignOut: signOut)
TripHomeView(tripId: id)

// après
HomeView(model: dependencies.homeModel(), onIntent: handle)
ProfileView(model: dependencies.profileModel(), onSignOut: signOut)
TripHomeView(tripId: id, model: dependencies.tripModel(id: id))
```

Rien d'autre ne bouge : ni les vues, ni les modèles, ni les aperçus.

**Sur un appareil réel**, `APIConfiguration.localDevelopment` pointe sur
`localhost` — inatteignable depuis un iPhone. Vise l'IP de ton Mac sur le
réseau local, ou passe par un tunnel.

### Après la connexion, rattacher l'appareil

Un carnet créé avant l'inscription appartient à l'appareil, pas au compte : il
n'apparaîtrait donc pas sur l'accueil. Appelle `linkCurrentDevice()` juste après
une connexion réussie, ce qui transfère les carnets orphelins de cet appareil au
compte.

Il ne prend que les carnets **sans propriétaire** : un téléphone prêté ne
transfère pas les carnets de son porteur précédent.

---

## 4. Ce qui marche, et ce qui attend encore

| Écran | Route | État |
|---|---|---|
| Accueil | `GET /v1/home` | Réelle |
| Un voyage | `GET /v1/trips/:id` | Réelle |
| Profil | `GET`/`PATCH /v1/profile` | Réelle, sauf les cartes |
| Connecteurs | `PUT /v1/profile/connectors/:key` | Enregistre l'intention, ne va rien chercher |
| Écran de bienvenue | `GET /v1/showcases/welcome` | Réelle |
| Carnets et souvenirs | `/v1/memos`, `/v1/entries` | Réelles depuis le début |

Ce qui manque encore, et pourquoi :

- **Les cartes bancaires.** La table existe, mais enregistrer une carte demande
  Stripe : la clé, le webhook, et un `SetupIntent`. Rien ne doit être écrit dans
  `payment_cards` avant que Stripe ait confirmé.
- **Les modales d'avis.** Le schéma et le seed sont là ; il manque
  `GET /v1/feedback/current` et `POST /v1/feedback/:key/responses`, et l'écran.
- **Les compteurs de voyage** (`memoryCount`, `pageCount`, `photoCount`) sont
  entretenus par le seed, pas encore par le pipeline.
- **La cagnotte** ne bouge que par le seed : la brancher demande le webhook
  Stripe, et l'écriture doit rester le seul chemin qui déplace un solde.

---

## 5. Les limites du plan gratuit

| Ressource | Limite | Ce que ça représente ici |
|---|---|---|
| Base | 500 Mo | Le texte ne pèse rien : des dizaines de milliers de souvenirs |
| Stockage | 1 Go | ~ 200 vocaux de 5 Mo, ou ~ 300 photos. **C'est ça qui saturera en premier** |
| Fichier | 50 Mo | Le back-end plafonne à 25 Mo, on est sous la limite |
| Transfert | 5 Go / mois | Chaque relecture d'un vocal et chaque PDF téléchargé comptent |

`npm run supabase:check` affiche la consommation et alerte à 80 %.

**Le projet se met en pause après 7 jours sans requête.** Ce n'est pas une perte
de données, mais le réveil prend quelques minutes : à savoir avant une
démonstration. Une requête par jour suffit à l'éviter.

Trois habitudes qui repoussent l'échéance, et qui sont de toute façon justes :

- **Les PDF ne vont pas dans le bucket.** Ils sont chez APITemplate, ou rendus
  en local. Un carnet de 60 pages pèse plusieurs mégaoctets.
- **Les photos publiées partent sur le CDN Webflow**, qui n'est pas décompté ici.
  Le bucket ne garde que l'original.
- **Rien de binaire en base.** `media_assets` ne stocke qu'une clé et une URL.

---

## 6. En partir

C'est la contrainte qui a guidé tous les choix, et elle se vérifie : rien de
propre à Supabase n'est utilisé.

| Pas utilisé | Ce qu'on fait à la place |
|---|---|
| Supabase Auth | `accounts`, `identities`, `sessions`, jetons opaques hachés |
| Row Level Security | L'autorisation vit dans `src/plugins/auth.ts` |
| `supabase-js` | L'app ne parle qu'à notre API |
| Realtime, Edge Functions | Fastify et pg-boss |
| Extensions Postgres | Aucune, hors `pgcrypto` que Supabase installe par défaut |

### La base

```bash
pg_dump "$SUPABASE_URL" --no-owner --no-privileges > memobook.sql
psql "$NOUVELLE_URL" < memobook.sql
```

Le schéma `pgboss` se recrée tout seul au démarrage du worker : inutile de le
transporter, et mieux vaut ne pas le faire — il porte des jobs en cours qui
n'ont plus de sens ailleurs. Une seule variable change ensuite,
`DATABASE_URL`.

Vérifie l'arrivée avec `npm run supabase:check`, qui n'a de Supabase que le nom
et fonctionne contre n'importe quel Postgres.

### Le stockage

Backblaze B2, Cloudflare R2 et Scaleway parlent tous le protocole S3. Le code ne
connaît que l'interface `MediaStorage` :

```bash
rclone sync supabase:memobook-media b2:memobook-media
```

Puis les quatre variables `S3_*`. Rien d'autre à toucher.

### Ce qu'il faudra quand même refaire

Deux choses ne se déménagent pas, parce qu'elles n'existent pas encore et qu'il
faut le savoir avant de les écrire :

- **Le chiffrement de `account_connectors.accessToken`.** Cette colonne ouvrira
  le compte de quelqu'un chez un tiers. Elle doit être chiffrée au repos par
  l'application, avec une clé qui n'est pas dans la base — donc de la même façon
  partout, et jamais avec un mécanisme fourni par l'hébergeur.
- **Les sauvegardes.** Le plan gratuit n'en fait aucune que tu contrôles. Un
  `pg_dump` quotidien vers un stockage à toi est le minimum dès qu'il y a un
  vrai utilisateur.

## Le budget de connexions — 15, et ils sont partagés

> ⚠️ **Le pooler Supabase en mode session n'accorde que 15 clients**, et ce
> plafond est celui du **projet**, pas d'une machine. Dépassé, il ne dégrade
> rien progressivement : il refuse, et **toutes** les routes répondent alors
> « Erreur interne du serveur ». Le message utile
> (`FATAL: (EMAXCONNSESSION) max clients reached in session mode`) n'apparaît
> que dans les journaux du serveur, jamais dans la réponse.

### Qui consomme ces 15

Trois consommateurs, et le piège est qu'ils ne sont pas sur la même machine —
`docs/deploiement.md` §2 le dit : **`DATABASE_URL` reçoit la même chaîne
Supabase sur les deux services Railway et dans le `.env` local.**

| Consommateur | Pool | Réglé par |
|---|---|---|
| API Railway | Prisma | `connection_limit` dans l'URL, **variable Railway** |
| Worker Railway | Prisma + pg-boss | idem, plus `max` dans `PgBossQueue` |
| Dev local | Prisma + pg-boss | `connection_limit` dans `backend/.env` |
| Tests (`npm test`) | Prisma | `TEST_DATABASE_URL` |
| Scripts de vérification | Prisma | leur propre URL |

**Prisma ouvre `cœurs × 2 + 1` connexions par défaut** — une vingtaine sur une
machine moderne, pour un seul processus. **pg-boss en ouvre 10 de plus, et il
ignore le `connection_limit` de l'URL** : c'est une autre bibliothèque, avec son
propre pool. Un seul service non plafonné mange donc tout le budget des autres.

### Le symptôme, vu d'en bas

Le développement local cesse de fonctionner **sans que rien n'ait changé en
local** : c'est un déploiement Railway qui a pris les créneaux. Le signe qui ne
trompe pas — compter les connexions réellement ouvertes depuis la machine :

```bash
lsof -nP -iTCP -sTCP:ESTABLISHED | grep -c pooler
```

Trois ou quatre en local et la base qui refuse quand même : les autres sont
ailleurs, et c'est Railway.

### Le réglage

Plafonner **partout**, y compris sur Railway. Sur les deux services, ajouter à
la variable `DATABASE_URL` :

```
?connection_limit=2&pool_timeout=20
```

(ou `&` si l'URL porte déjà un `?`). Puis redéployer — une variable
d'environnement seule ne relance pas le service.

Répartition qui tient dans 15 :

| Qui | Prisma | pg-boss | Total |
|---|---|---|---|
| API Railway | 2 | — | 2 |
| Worker Railway | 2 | 4 | 6 |
| Dev local | 4 | 4 | 8 *(ne pas faire tourner en même temps que les tests)* |
| Tests | 2 | — | 2 |

### Ce qui est déjà en place dans le dépôt

- `backend/.env` — `connection_limit` sur `DATABASE_URL` et `TEST_DATABASE_URL`
- `backend/src/jobs/queue.ts` — `max: 4` sur pg-boss, qui se déploie avec le code
- `backend/scripts/stripe-e2e.ts` — une seule connexion, explicitement

**Ce qui reste à faire à la main : les variables Railway.** Elles ne sont pas
dans le dépôt, donc aucun commit ne les corrigera.
