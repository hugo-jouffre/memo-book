# La base de données

MemoBook tourne sur **PostgreSQL 16 managé chez Scaleway, région `fr-par`
(Paris)**. Une seule instance porte tout : les données métier (appareils,
carnets, souvenirs, transcriptions, rendus, commandes) *et* la file d'attente du
pipeline, que pg-boss stocke dans son propre schéma.

## Pourquoi ce choix

**Managé plutôt qu'auto-hébergé.** La file d'attente est déjà dans Postgres —
c'est ce qui évite d'opérer un Redis. Opérer en plus le Postgres lui-même
(sauvegardes, montées de version mineures, bascule sur panne) reviendrait à
reprendre d'une main ce qu'on a écarté de l'autre.

**Paris, pas Amsterdam ni Varsovie.** Les vocaux sont des données personnelles
au sens du RGPD, et la base en porte les transcriptions, le texte rédigé et les
métadonnées. Les garder en France simplifie le registre des traitements et la
future revue RGPD. Les sauvegardes automatiques restent dans la même région
(`backup-same-region=true` à la création).

**PostgreSQL 16.** La même version qu'en local (`docker-compose.yml`) et qu'en
CI (`.github/workflows/ci-backend.yml`) : la base de développement et celle de
production ne doivent pas diverger sur un `ORDER BY` ou un type.

## Créer l'instance

Une seule commande, idempotente — relancée, elle ne recrée rien :

```bash
./scripts/provision-db-scaleway.sh --allow <IP-de-sortie-des-serveurs>/32
```

Prérequis : `scw` (CLI Scaleway) authentifié — `scw init` une fois, ou les
variables `SCW_ACCESS_KEY`, `SCW_SECRET_KEY`, `SCW_DEFAULT_PROJECT_ID` — plus
`jq`, `openssl` et `curl`.

Ce que le script fait, dans l'ordre :

1. **L'instance** `memobook-prod` : `PostgreSQL-16`, `fr-par`, nœud `DB-DEV-S`,
   volume `sbs_5k` de 10 Go, chiffrement au repos activé, sauvegardes
   automatiques conservées dans la région.
2. **La base** `memobook` et les droits `all` pour l'utilisateur `memobook` :
   Prisma y crée les tables des migrations, pg-boss son propre schéma — un droit
   `readwrite` ne suffirait pas.
3. **Le filtrage IP** de l'endpoint public. Sans règle d'ACL, *personne* ne se
   connecte : c'est le comportement voulu, il faut déclarer les IP de sortie des
   machines API et worker. Sans `--allow`, le script autorise l'IP publique de
   la machine courante, ce qui convient pour un premier test depuis un poste.
4. **Le certificat TLS** de l'instance, écrit dans `./secrets/` (ignoré par Git).
5. **Le `DATABASE_URL`** à coller dans les secrets du déploiement.

Options utiles : `--ha` (second nœud en veille), `--node-type` (montée en
gamme), `--name memobook-staging` (une seconde instance), `--dry-run` (affiche
les commandes sans rien créer). `scw rdb node-type list region=fr-par` donne la
liste des nœuds disponibles et la
[grille tarifaire Scaleway](https://www.scaleway.com/fr/tarifs/managed-database/)
leur prix.

> **Le mot de passe n'est affiché qu'une fois.** Scaleway ne le restitue jamais.
> Range-le immédiatement dans le gestionnaire de secrets du déploiement. Perdu,
> il se réinitialise : `scw rdb user update instance-id=<id> name=memobook
> password=<nouveau> region=fr-par`.

## Se connecter

Le `DATABASE_URL` de production ressemble à ceci :

```
postgresql://memobook:<mot-de-passe>@rw-<id>.rdb.fr-par.scw.cloud:<port>/memobook?sslmode=require&sslcert=/etc/memobook/scaleway-rdb.pem&sslaccept=strict&connection_limit=10
```

Trois détails qui ne s'improvisent pas :

**Le nom DNS, pas l'IP.** `rw-<id>.rdb.fr-par.scw.cloud` est le nom pour lequel
le certificat est émis. Une connexion par IP interdit `sslmode=verify-full`, et
l'IP de l'endpoint peut changer.

**Les paramètres TLS sont écrits dans le dialecte Prisma** (`sslmode`,
`sslcert`, `sslaccept`), parce que c'est le seul que `prisma migrate deploy` sait
lire : la CLI prend la variable d'environnement telle quelle, aucun code du
back-end ne peut s'interposer. pg-boss, lui, passe par node-postgres, qui attend
`sslrootcert` et traiterait `sslcert` comme un certificat *client*.
`src/lib/pgConnection.ts` fait la traduction, et c'est ce que ses tests
vérifient. Ne rien « simplifier » là sans les relire.

**`sslmode=require` avec un certificat = vérification de la chaîne, pas du nom
d'hôte** — la sémantique de libpq. Pour aller jusqu'à la vérification du nom
d'hôte, passer `sslmode=verify-full` : c'est supporté par Scaleway pour tout
certificat créé ou renouvelé depuis février 2023, à condition de se connecter par
le nom DNS ci-dessus.

Le certificat doit exister à ce chemin sur **chaque** machine qui se connecte —
API et worker. En production, une URL sans `sslmode` empêche le démarrage
(`src/env.ts`) : la base est jointe par l'internet public, une connexion en clair
y ferait passer des transcriptions de vocaux.

Vérifier une connexion à la main :

```bash
PGSSLROOTCERT=./secrets/scaleway-rdb-memobook-prod.pem \
  psql "host=rw-<id>.rdb.fr-par.scw.cloud port=<port> user=memobook dbname=memobook sslmode=verify-full"
```

## Appliquer le schéma

```bash
cd backend
DATABASE_URL="…" npx prisma migrate deploy
```

`migrate deploy` n'applique que les migrations déjà versionnées dans
`prisma/migrations/` — il ne génère rien et ne demande rien. `prisma migrate dev`
reste réservé au développement local : lancé sur la production, il proposerait de
réinitialiser la base.

pg-boss crée son schéma tout seul au premier démarrage du worker.

## Budget de connexions

Deux process (API et worker), chacun avec son pool Prisma et, pour le worker,
celui de pg-boss. Un nœud `DB-DEV-S` n'offre que quelques dizaines de connexions.
D'où `connection_limit=10` dans l'URL : Prisma dimensionnerait sinon son pool sur
le nombre de cœurs de la machine, ce qui sature une petite instance dès qu'on
ajoute un worker. Si `too many connections` apparaît dans les logs, c'est ce
paramètre — ou le type de nœud — qu'il faut revoir, pas le code.

## Sauvegardes et restauration

Les sauvegardes automatiques sont actives à la création et restent en `fr-par`.

```bash
scw rdb backup list instance-id=<id> region=fr-par        # ce qui existe
scw rdb backup create instance-id=<id> database-name=memobook name=avant-migration region=fr-par
scw rdb backup restore <backup-id> instance-id=<id> database-name=memobook region=fr-par
```

Une sauvegarde manuelle avant une migration qui touche des données existantes
coûte trente secondes et évite une soirée.

**Ce qui n'est pas encore fait** : personne n'a encore restauré une sauvegarde
pour de vrai. Une sauvegarde jamais restaurée n'est pas une sauvegarde — la
première restauration de test est à faire avant le lancement.

## Renouveler le certificat

Le certificat de l'instance a une date de fin. Pour le renouveler puis
redéployer le PEM sur les machines :

```bash
scw rdb instance renew-certificate <id> region=fr-par
./scripts/provision-db-scaleway.sh          # récupère le nouveau certificat
```

## Aller plus loin

Ce qui reste ouvert, volontairement :

- **Réseau privé.** L'instance est aujourd'hui jointe par son endpoint public,
  protégé par le filtrage IP et TLS. Le jour où l'API tournera sur des Instances
  Scaleway, un Private Network supprimerait l'exposition publique.
- **Utilisateur applicatif restreint.** Un seul utilisateur, propriétaire de la
  base, sert aux migrations et à l'exécution. Séparer les deux se fait avec
  `scw rdb user create` puis `scw rdb privilege set`.
- **Réplica de lecture.** Inutile tant que la charge tient sur un nœud ; c'est
  `scw rdb read-replica create` le jour venu.
