# La base MemoBook

Ce que la base porte, comment elle arrive dans Supabase, et pourquoi chaque table
est là. Ce fichier vit à côté de `schema.prisma` et des migrations : on ne peut
pas toucher au modèle sans le croiser.

**`schema.prisma` fait foi.** Ce document explique les arbitrages ; il ne les
remplace pas. Quand les deux divergent, c'est ce fichier qui a tort.

---

## 1. Comment la base est fabriquée

Supabase n'est **pas** utilisé comme BaaS. Le README racine tranche en faveur
d'un back-end Node/Fastify plutôt que Supabase ou Firebase, parce que le pipeline
enchaîne des tâches longues qui demandent une vraie file d'attente. Ce que
Supabase fournit ici, c'est deux choses et pas une de plus :

- le **Postgres managé** derrière `DATABASE_URL` ;
- un **bucket privé S3** pour les médias bruts (`S3_*` dans `.env`).

```
schema.prisma  ──migrate dev──▶  migrations/*.sql  ──migrate deploy──▶  Postgres (Supabase)
 source de vérité                 SQL versionné,                        schéma public
                                  relu en revue
```

Ce qui suit n'existe donc pas dans ce projet, et c'est délibéré :

| Pas utilisé | Ce qu'on fait à la place |
|---|---|
| Supabase Auth | `accounts`, `identities`, `sessions`, jetons opaques hachés en SHA-256 |
| Row Level Security | L'autorisation vit dans `src/plugins/auth.ts`, côté API |
| `supabase-js` | L'app iOS ne parle qu'à notre API, jamais à Supabase en direct |
| Supabase Realtime | L'app suit les statuts en interrogeant l'API |

**Un schéma de plus, hors Prisma.** La file d'attente pg-boss crée son propre
schéma `pgboss` au premier démarrage du worker (`job`, `archive`, `schedule`,
`version`). Il n'apparaît dans aucune migration : c'est la bibliothèque qui le
pose et le fait évoluer. Ne pas le gérer à la main.

### Appliquer une migration

```bash
npx prisma migrate dev      # en développement : génère le SQL et l'applique
npx prisma migrate deploy   # en CI et en production : applique ce qui manque
```

Le SQL généré se **relit et se complète à la main** quand la migration demande
une reprise de données. Deux précédents dans l'historique : M2 fait passer les
entrées photo en rédaction `ready`, M4 rattache les carnets existants à un
compte. Sans ces blocs, une migration correcte laisse la base dans un état que le
produit ne sait pas afficher.

---

## 2. L'historique des migrations

| | Date | Nom | Ce qu'elle pose |
|---|---|---|---|
| **M1** | 8 août 2026 | `init` | `devices`, `memos`, `entries`, `media_assets`, `renders` |
| **M2** | 15 août 2026 | `redaction_pass_and_print_orders` | `print_orders`, la passe de rédaction sur `entries`, le style et la fiche de cohérence sur `memos` |
| **M3** | 3 sept. 2026 | `comptes_identites_et_sessions` | `accounts`, `identities`, `sessions`, et `devices.accountId` |
| **M4** | 7 sept. 2026 | `voyages_partages_cagnotte_et_feedback` | Propriété par compte, participants, étapes, dépenses, cagnotte, paiements, mises en avant, demandes d'avis |

**21 tables**, 12 énumérations.

---

## 3. Les arbitrages de M4

Quatre décisions structurent cette migration. Elles se discutent, mais elles se
discutent **avant** d'écrire la suivante.

### Un participant est un compte, pas une fiche

Il n'y a pas de table `companions`. Un participant **est** un `Account`, et
`memo_members` est la table de liaison qui dit à quel titre.

```
accounts ──┬── memos.ownerAccountId          « le voyage que je possède »
           └── memo_members (role, status)   « les voyages où je participe »
```

Un compte peut donc être propriétaire du sien et invité dans autant d'autres
qu'il veut. « Qui est sur ce voyage » est une requête, « tous les voyages où
j'apparais » aussi.

Trois points à connaître :

- **Le propriétaire a sa propre ligne**, avec `role = owner`. Sans elle,
  afficher l'équipage demanderait de lire deux endroits et de les recoller.
- **`memos.ownerAccountId` est dénormalisé exprès.** Toutes les routes vérifient
  la propriété à chaque requête ; une jointure de plus sur ce chemin ne se
  justifie pas.
- **`invitedEmail` existe pour l'invitation en attente.** Sans lui, on ne
  pourrait inviter que des gens déjà inscrits sur MemoBook. `accountId` reste
  nul jusqu'à ce que la personne crée son compte.

> **Invariant non gardé par la base** : un seul `role = owner` par carnet. Un
> index unique partiel l'imposerait, mais Prisma ne sait pas le décrire, et la
> migration suivante le supprimerait comme une dérive. C'est donc au code qui
> crée un carnet de le tenir.

### Les personnalisations vivent sur `memos`

**Oui, c'était la bonne idée.** Trois raisons, dans cet ordre :

1. Il y a **exactement un jeu de réglages par voyage**. Une table à part
   aurait modélisé un « zéro ou un » qui n'existe pas, et ajouté partout un cas
   « pas encore de réglages » à traiter.
2. Ils se lisent **toujours avec le carnet** : la rédaction, la mise en page et
   l'app les demandent en même temps que le titre. Une table séparée n'aurait
   ajouté qu'une jointure sur le chemin le plus fréquent.
3. Aucune requête ne les interroge seuls. Une table ne se justifie que si on
   veut la lire, la compter ou la joindre indépendamment ; ce n'est jamais le
   cas ici.

Le coût est que `memos` passe à une quarantaine de colonnes. Postgres n'en a
cure, et les commentaires du schéma les regroupent par rôle.

**Pourquoi pas une colonne `settings Json`** : parce qu'on perdrait les valeurs
par défaut, la vérification de type à la compilation et la possibilité de
demander « tous les carnets où les pointillés sont coupés ». Les treize réglages
sont connus et stables ; le JSON n'est gardé que là où la structure est encore
ouverte (`coverFront`, `coverBack`, `audience`, `config`).

**Règle de survie**, reprise de `docs/reglages-utilisateur.md` : aucun réglage
n'est exposé dans l'app avant d'exister dans `LAYOUT_KB.md`. Une colonne que le
gabarit ignore ferait croire à l'utilisateur qu'il a réglé quelque chose.

### L'analyse photo et le quiz vivent sur `entries`

L'analyse d'une photo (verdict qualité, netteté, exposition, coin du scotch,
point de focus) est portée par le **souvenir**, pas par le fichier.

Ce n'est pas qu'une question de commodité : `tapeCorner` et le point de focus
sont des décisions de mise en page prises pour *cette* photo dans *ce* carnet.
Le fichier, lui, ne connaît que sa clé, son type et son poids.

`media_assets` ne gagne donc qu'une colonne, `originalStorageKey`, parce que
c'est un fait sur l'objet stocké : l'original est conservé après un
agrandissement, pour qu'un agrandissement raté puisse être annulé.

Le quiz suit la même logique que le fun fact : c'est du texte que l'agent de
rédaction produit une fois. Le laisser dans le payload du rendu le ferait
réécrire à chaque aperçu.

> `entries.mediaId` et `media_assets` restent une table à part, alors que la
> relation est un pour un dans les faits. C'est ce qui laisse la porte ouverte à
> plusieurs photos dans un même souvenir sans casser l'existant. Si cette
> hypothèse tombe, fusionner les deux tables est une migration simple.

### La cagnotte est un registre, pas un compteur

```
wallet_entries  (registre en ajout seul, en centimes)
      │  somme
      ▼
accounts.walletBalanceCents  (cache, déplacé dans la même transaction)
```

Un solde stocké seul est une donnée qu'on ne peut ni auditer ni réparer : quand
il est faux, rien ne dit depuis quand ni pourquoi. Un registre répond aux deux
questions.

Quatre règles, et elles ne sont pas négociables :

1. **Des centimes entiers.** Aucun montant en flottant, nulle part. `Decimal`
   n'apporte rien de plus ici et coûte des conversions.
2. **Rien ne se met à jour, rien ne se supprime.** Une erreur se corrige par une
   écriture inverse, comme dans un livre de comptes. C'est ce qui rend
   l'historique opposable.
3. **Une écriture par mouvement réellement encaissé.** Il n'y a pas d'état « en
   attente » : tant que Stripe n'a pas confirmé, rien n'est écrit. Les
   intentions de paiement vivent chez Stripe, pas ici.
4. **`stripeEventId` est unique.** Stripe rejoue ses webhooks — c'est documenté
   et normal. Un rejeu échoue alors sur la contrainte au lieu de créditer deux
   fois. **L'idempotence est garantie par la base, pas par le code applicatif** :
   c'est le seul endroit où deux requêtes concurrentes ne peuvent pas passer
   entre les gouttes.

`balanceAfterCents` est redondant avec la somme, et c'est exactement son
intérêt : une dérive entre le cache et le registre se voit sans rejouer tout
l'historique.

Le même verrou protège les commandes : `print_orders.stripePaymentIntentId` est
unique, donc une commande ne peut pas être payée deux fois.

**Ce qui n'est pas dans la cagnotte** : une devise. Elle est en euros, point.
Une cagnotte multidevise demande un taux de change, une date de conversion et
une politique d'arrondi — trois problèmes qu'on n'a pas et qu'il ne faut pas
s'inventer. `subscriptions` et `expenses`, eux, portent leur devise : un
abonnement se vend hors zone euro, et une dépense de voyage est souvent dans une
autre monnaie.

---

## 4. Les tables

### Comptes et identité

| Table | Rôle |
|---|---|
| `accounts` | Une personne. Profil, adresse par défaut, solde de cagnotte, client Stripe |
| `identities` | Le lien vers un fournisseur tiers. `unique(provider, subject)` |
| `sessions` | Une session ouverte. Le jeton est haché ; révoquer, c'est supprimer une ligne |
| `devices` | Identité provisoire, le temps que la propriété passe au compte |

L'email d'un compte est unique mais **facultatif** : une personne entrée par
Apple avec l'adresse masquée n'en a pas d'utilisable.

### Le carnet

| Table | Rôle |
|---|---|
| `memos` | Un voyage : son identité, son état, ses compteurs et ses personnalisations |
| `memo_members` | Qui participe, et à quel titre |
| `memo_steps` | Les étapes du voyage. Une étape **regroupe** des souvenirs, elle n'en est pas un |
| `entries` | Un souvenir : un vocal, une note ou une photo |
| `media_assets` | Le fichier stocké. Une clé S3 et une URL CDN, jamais le contenu |
| `expenses` | Les dépenses du voyage |

`memo_steps` remplace un regroupement qui se refaisait à chaque génération à
partir de `capturedAt` et disparaissait ensuite. Il devient une donnée que
l'utilisateur peut corriger. `entries.stepId` reste nul tant que les étapes ne
sont pas posées : le repli sur `capturedAt` continue de fonctionner.

Le texte d'un souvenir traverse trois états, et **les trois sont conservés** :

```
transcript  ──rédaction──▶  redactedText  ──clavier──▶  editedText
(ce qui a été dit)          (ce que l'agent            (ce que l'utilisateur
                             en a fait)                 a corrigé)
```

Dès que `editedText` existe, il fait autorité et la mise en page le reprend au
mot près.

### Impression et argent

| Table | Rôle |
|---|---|
| `renders` | Une génération de carnet. L'historique est gardé, avec son payload |
| `print_orders` | Une commande, passée sur un rendu **figé**, avec son suivi |
| `wallet_entries` | Le registre de la cagnotte |
| `payment_cards` | Les cartes enregistrées. Quatre chiffres et une référence Stripe |
| `subscriptions` | L'abonnement, Stripe ou StoreKit |

Le rendu commandé est figé : réimprimer après avoir ajouté une étape crée une
nouvelle commande sur un nouveau rendu, jamais une mise à jour de celle-ci. Sans
quoi le carnet livré ne serait pas celui qui a été prévisualisé et payé. C'est
pour ça que `print_orders.renderId` est en `RESTRICT` et non en `CASCADE`.

L'adresse est **copiée** sur la commande, pas référencée. Corriger son adresse
dans le profil ne doit pas réécrire celle d'un colis déjà parti.

### Piloté depuis la base, sans livrer d'app

| Table | Rôle |
|---|---|
| `showcases` | Les carnets mis en avant |
| `feedback_campaigns` | Une demande d'avis, avec sa fenêtre de diffusion |
| `feedback_questions` | Ses questions, dans l'ordre |
| `feedback_responses` | Ce qu'une personne en a fait : remplie, ou fermée |
| `feedback_answers` | Ses réponses, une ligne par question |
| `account_connectors` | Les applications tierces branchées sur un compte |

#### Les mises en avant

`showcases` porte **deux drapeaux et non un seul** :

- `isActive` — visible sur la carte de découverte, en bas de l'accueil ;
- `showOnWelcomeScreen` — montré sur l'écran de bienvenue, celui qui n'apparaît
  qu'une fois au premier lancement.

Un carnet peut mériter l'accueil sans être ce qu'on montre à quelqu'un qui
découvre l'app, et l'inverse aussi. Les deux se basculent depuis la base.

`accounts.welcomeScreenSeenAt` retient que l'écran a été montré. Côté serveur
plutôt que dans l'app, pour que ça survive à une réinstallation.

#### Les demandes d'avis

L'app connaît les **formes** de question et sait les dessiner ; tout le reste
vient de la base. Ajouter une campagne est une insertion, pas une release.

```
feedback_campaigns  ──▶  feedback_questions   (le contenu de la modale)
        │
        ▼
feedback_responses  ──▶  feedback_answers     (ce qu'on en a fait)
```

Quatre formes, et la colonne `config` porte ce que chacune demande en plus :

| `kind` | `config` |
|---|---|
| `text` | rien |
| `choice` | `{ "options": [{ "key": "a", "label": "Option 1", "hint": "…" }] }` |
| `slider` | `{ "min": 0, "max": 4, "step": 1, "minLabel": "…", "maxLabel": "…" }` |
| `rating` | `{ "max": 5 }` |

Du JSON ici parce que chaque forme a ses propres réglages : des colonnes
séparées seraient nulles pour toutes les questions sauf une. Les **réponses**,
elles, ont bien une colonne par type (`textValue`, `numberValue`, `choiceKey`) :
c'est ce qui permet de faire la moyenne d'un curseur ou de compter les choix en
SQL, sans rien désérialiser.

`feedback_responses` enregistre aussi les modales **fermées** (`dismissedAt`).
Savoir qu'on écarte une question est un résultat, pas un trou dans les données.
`displayCount` est ce que `maxDisplays` borne : à 1, une modale fermée ne revient
jamais.

Voici la campagne de la maquette, telle qu'elle s'insère :

```sql
INSERT INTO feedback_campaigns (id, key, title, subtitle, "isActive")
VALUES (gen_random_uuid()::text, 'avis-v1',
        'Peux-tu nous donner ton avis ?',
        'MemoBook est en plein développement et ton avis compte beaucoup pour nous aider à améliorer l''app',
        true);

INSERT INTO feedback_questions (id, "campaignId", position, kind, placeholder, config)
SELECT gen_random_uuid()::text, id, 1, 'text', 'Ton commentaire...', NULL
FROM feedback_campaigns WHERE key = 'avis-v1';

INSERT INTO feedback_questions (id, "campaignId", position, kind, config)
SELECT gen_random_uuid()::text, id, 2, 'choice',
       '{"options":[{"key":"a","label":"Option 1","hint":"Lorem Ipsum"},
                    {"key":"b","label":"Option 2","hint":"Lorem Ipsum"},
                    {"key":"c","label":"Option 3","hint":"Lorem Ipsum"}]}'::jsonb
FROM feedback_campaigns WHERE key = 'avis-v1';

INSERT INTO feedback_questions (id, "campaignId", position, kind, prompt, config)
SELECT gen_random_uuid()::text, id, 3, 'slider', 'Questions avec un slider',
       '{"min":0,"max":4,"step":1}'::jsonb
FROM feedback_campaigns WHERE key = 'avis-v1';
```

#### Les connecteurs

`account_connectors.accessToken` est **la colonne la plus sensible du schéma** :
elle ouvre le compte de quelqu'un chez un tiers. Elle doit être chiffrée au
repos, ne jamais descendre jusqu'à l'app, et ne sortir de la base que vers
l'appel qui l'utilise. Le chiffrement n'est pas encore en place : le brancher
est un prérequis au premier connecteur réel, pas une amélioration.

---

## 5. Ce que le schéma attend encore du code

M4 pose les colonnes. Elle ne branche rien : aucune route, aucun job n'a changé.
Ce qui reste, par ordre de dépendance :

1. **Rattacher les carnets orphelins.** La reprise de données a rempli
   `ownerAccountId` pour les appareils déjà connectés. Les autres restent nuls.
   Tant qu'il en reste, `ownerAccountId` ne peut pas devenir obligatoire — et
   c'est cette contrainte qui rendra la propriété par compte réelle.

   ```sql
   SELECT count(*) FROM memos WHERE "ownerAccountId" IS NULL;
   ```

2. **Faire écrire la ligne `owner`** à la création d'un carnet, et vérifier
   l'appartenance par `memo_members` plutôt que par `deviceId` dans
   `src/plugins/auth.ts`.

3. **Entretenir les compteurs** de `memos` (`memoryCount`, `photoCount`,
   `pageCount`, `isPrintable`) à l'écriture. Ils sont entretenus et non calculés
   parce que l'accueil les demande tous d'un coup, pour tous les voyages.

4. **Brancher Stripe**, et n'écrire dans `wallet_entries` que depuis le webhook,
   dans une transaction qui déplace aussi `walletBalanceCents`.

5. **Lire les personnalisations** dans la structuration, puis les faire
   descendre dans le payload et dans `gpt_image_schema.yaml`. Tant que le
   gabarit les ignore, ne pas les exposer dans l'app.

6. **Le job `memobook.enhance`** (`docs/photos.md`), qui remplit l'analyse photo
   entre `structure` et `render`.

**Attention aux textes déjà relus.** Changer un réglage qui touche l'écriture
relance la rédaction. Or le texte corrigé au clavier fait autorité et ne se
réécrit jamais : il faut exclure les étapes déjà validées, ou prévenir
explicitement avant de régénérer.

---

## 6. Vérifier une migration sans Supabase

Un Postgres jetable suffit, et c'est ce que fait la CI. En local :

```bash
docker compose up -d postgres
DATABASE_URL=postgresql://memobook:memobook@localhost:5432/memobook \
  npx prisma migrate deploy
```

Puis, pour confirmer que le schéma et la base disent la même chose :

```bash
npx prisma migrate diff \
  --from-schema-datasource prisma/schema.prisma \
  --to-schema-datamodel  prisma/schema.prisma \
  --exit-code
```

`No difference detected.` est la seule réponse acceptable avant de pousser.
