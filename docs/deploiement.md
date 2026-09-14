# Déployer l'API

Tant que l'API n'est pas en ligne, **un build TestFlight ne peut pas fonctionner,
sur aucun iPhone**. L'adresse est figée dans le binaire au moment du build
(`ios/Config/Release.xcconfig`, clé `MEMOBOOK_API_BASE_URL`) : un serveur lancé
sur le Mac, ou dans un conteneur de développement, n'est joignable par aucun
téléphone, même le sien.

C'est la seule raison de « Connexion impossible. Vérifie ton réseau et réessaie. »
sur un build TestFlight : l'app appelle `https://api.memo-book.com`, un nom de
domaine qui n'a aujourd'hui aucun enregistrement DNS.

Cible retenue : **Railway** pour l'API, le worker et Postgres, **Supabase
Storage** pour les médias.

## 1. Le projet Railway

Le dépôt contient déjà `railway.json` à sa racine : Railway construit
`backend/Dockerfile` **depuis la racine du dépôt**, ce dont le Dockerfile a
besoin (il copie `templates/`, `agents/` et `assets/`). Ne pas régler le
« Root Directory » du service sur `backend/`, l'image se construirait sans
broncher et tomberait au premier carnet.

1. New Project ▸ Deploy from GitHub repo ▸ `hugo-jouffre/memo-book`.
2. Le service détecte `railway.json` et construit l'image. Vérifier dans les
   logs de build qu'il utilise bien `backend/Dockerfile`.
3. Settings ▸ Networking ▸ Generate Domain. Railway donne une adresse du type
   `memo-book-production.up.railway.app`. **C'est déjà assez pour un TestFlight
   qui marche** : le domaine personnalisé peut attendre.

## 2. Postgres

New ▸ Database ▸ Add PostgreSQL, dans le même projet. Railway expose
`DATABASE_URL` par référence :

    DATABASE_URL = ${{Postgres.DATABASE_URL}}

Les migrations ne tournent pas au démarrage : l'image d'exécution est construite
avec `npm ci --omit=dev`, elle n'embarque donc pas le CLI Prisma. On les applique
depuis le Mac, contre la base de production :

    cd backend
    DATABASE_URL="<l'URL publique du Postgres Railway>" npm run db:deploy

À refaire **à chaque fois qu'une migration est ajoutée**, avant de déployer le
code qui en dépend.

## 3. Le worker

La transcription d'un vocal ne doit jamais tenir une requête HTTP. C'est un
second service, la même image, une autre commande :

1. New ▸ GitHub Repo ▸ le même dépôt, dans le même projet.
2. Settings ▸ Deploy ▸ Custom Start Command : `node dist/worker.js`.
3. Settings ▸ Networking : aucun domaine, il n'écoute rien.
4. Les mêmes variables d'environnement que l'API.

## 4. Supabase Storage

Storage ▸ New bucket ▸ `memobook-media`, **privé**. Puis Project Settings ▸
Storage ▸ S3 connection ▸ générer une clé d'accès.

    S3_ENDPOINT=https://<ref>.storage.supabase.co/storage/v1/s3
    S3_REGION=<la région du projet, ex. eu-west-3>
    S3_BUCKET=memobook-media
    S3_ACCESS_KEY_ID=<la clé générée>
    S3_SECRET_ACCESS_KEY=<le secret généré>
    S3_FORCE_PATH_STYLE=true

Le bucket reste privé : l'app ne parle jamais à Supabase en direct, elle passe
par l'API, qui délivre des URL signées à durée limitée.

⚠️ En `NODE_ENV=production`, l'absence de configuration S3 **empêche le
démarrage**, volontairement : mieux vaut un service qui refuse de partir qu'un
service qui perd les vocaux en silence.

## 5. Les variables d'environnement

Sur les deux services, API et worker. La liste commentée est dans
`backend/.env.example` ; voici le minimum pour que la connexion fonctionne :

| Variable | Valeur | Pourquoi |
| --- | --- | --- |
| `NODE_ENV` | `production` | |
| `PORT` | `3000` | Railway l'injecte aussi, la valeur explicite évite l'ambiguïté. |
| `DATABASE_URL` | `${{Postgres.DATABASE_URL}}` | |
| `S3_*` | voir ci-dessus | Sans elles, le serveur ne démarre pas en production. |
| `APPLE_BUNDLE_ID` | `com.memobook.app` | Sans elle, « Continuer avec Apple » échoue. |
| `GOOGLE_IOS_CLIENT_ID` | le client iOS, voir `ios/Config/Base.xcconfig` | Sans elle, « Continuer avec Google » échoue. |

Aujourd'hui la valeur est
`1022603657545-ehn9lik23bgu7m9h28a01b271lft0u2h.apps.googleusercontent.com`.
Elle doit rester identique des deux côtés : le serveur compare le champ `aud` du
jeton d'identité à cette valeur, et un jeton émis pour une autre app ne doit pas
ouvrir de compte ici.

Les clés du pipeline (`OPENAI_API_KEY`, `ANTHROPIC_API_KEY`,
`APITEMPLATE_API_KEY`, `WEBFLOW_*`) ne sont pas nécessaires pour se connecter :
sans elles, `PIPELINE_MODE=auto` bascule sur les implémentations simulées. La
connexion, les comptes et les voyages fonctionnent ; seuls la transcription
réelle et le PDF sont simulés. À renseigner dès qu'on veut un vrai carnet.

## 6. Apple et Google

Ces deux-là échouent **même avec l'API en ligne** si le serveur n'est pas
configuré, et le message d'erreur ne le dit pas. C'est le point le plus
souvent raté.

### Ce que le serveur fait, et ne fait pas

`src/services/socialIdentity.ts` vérifie le jeton d'identité contre les clés
publiques du fournisseur : signature, émetteur (`iss`), audience (`aud`),
expiration. Pour Apple s'ajoute le nonce.

Conséquence pratique, et elle fait gagner une soirée : **le serveur n'a besoin
d'aucun secret, ni chez Apple, ni chez Google.** Pas de Services ID, pas de clé
`.p8`, pas de client secret. La plupart des tutoriels en font créer parce qu'ils
décrivent une connexion depuis un navigateur. Ici l'app native obtient le jeton
elle-même, le serveur ne fait que le vérifier.

Deux variables suffisent, et elles ne sont pas secrètes :

    APPLE_BUNDLE_ID=com.memobook.app
    GOOGLE_IOS_CLIENT_ID=1022603657545-ehn9lik23bgu7m9h28a01b271lft0u2h.apps.googleusercontent.com

Elles doivent correspondre **exactement** à ce qui part dans le binaire
(`PRODUCT_BUNDLE_IDENTIFIER` dans `ios/project.yml`, `GOOGLE_IOS_CLIENT_ID` dans
`ios/Config/Base.xcconfig`). C'est tout l'intérêt du contrôle : un jeton Apple
authentique, mais émis pour une autre app, ne doit pas ouvrir de compte ici.

Si `GOOGLE_IOS_CLIENT_ID` et `GOOGLE_WEB_CLIENT_ID` sont vides tous les deux,
`/v1/auth/google` lève une erreur 500 au lieu de refuser proprement : c'est une
erreur de configuration, pas une tentative de connexion invalide.

### Côté portail Apple Developer

La capability doit être active sur l'App ID `com.memobook.app` (Certificates,
Identifiers & Profiles ▸ Identifiers ▸ l'App ID ▸ Sign In with Apple). Elle est
déjà déclarée côté projet dans `ios/project.yml` ; si le portail ne suit pas, ce
n'est pas la connexion qui échoue, c'est la **signature** du build, avec
« profile doesn't include the com.apple.developer.applesignin entitlement ».

⚠️ **Apple ne donne le nom et l'adresse qu'à la toute première autorisation.**
Aux connexions suivantes, le jeton ne porte plus que le `sub`. Le code en tient
compte (`fillMissingProfile` ne réécrit jamais ce qui est déjà là), mais en test
c'est piégeux : effacer le compte en base ne fait pas repartir Apple à zéro, et
le compte recréé n'aura ni nom ni adresse. Pour repartir vraiment de zéro, il
faut retirer l'autorisation côté téléphone :

    Réglages ▸ [son nom] ▸ Connexion et sécurité ▸ Se connecter avec Apple
    ▸ MemoBook ▸ Ne plus utiliser

À prévoir plus tard, quand l'app enverra des emails : une adresse Apple peut
être un relais `@privaterelay.appleid.com`, et il faut alors déclarer le domaine
d'envoi chez Apple pour que le courrier arrive.

### Côté Google Cloud

Le client iOS existe déjà. Ce qui manque souvent, c'est l'**écran de
consentement** (APIs & Services ▸ OAuth consent screen). Tant qu'il est en
statut « Testing », **seuls les comptes listés en Test users peuvent se
connecter**. Un testeur TestFlight qui n'est pas dans la liste voit la feuille
Google s'ouvrir puis refuser, sans explication utile.

Deux sorties :

- ajouter chaque testeur en Test users, acceptable pour trois personnes ;
- passer l'écran « In production », ce qui l'ouvre à tout le monde.

Publier ne déclenche **pas** de revue Google ici : MemoBook ne demande que
`openid`, `email` et `profile`, qui sont des scopes non sensibles. La revue n'est
exigée que pour les scopes sensibles (Gmail, Drive, Calendar).

Vérifier aussi que le client utilisé est bien le client **iOS** et pas le client
web : un client web refuse les schémas d'URL personnalisés, et Google répond
« Custom scheme URIs are not allowed for WEB client type ». Le client iOS se
reconnaît à son type, à son Bundle ID, et à son absence de client secret.

## 7. Vérifier avant de toucher à l'app iOS

    curl https://<le-domaine>/health

Attendu : `{"status":"ok","checks":{"database":"ok","queue":"ok"},...}`.
Si `database` n'est pas `ok`, les migrations n'ont pas été appliquées (étape 2).

## 8. Pointer l'app sur l'API, et **refaire un build**

Une seule ligne, dans `ios/Config/Release.xcconfig` :

    MEMOBOOK_API_BASE_URL = https:/$()/<le-domaine>

⚠️ Les deux barres obliques ouvrent un commentaire dans un `.xcconfig`, y compris
au milieu d'une URL. Le `$()` les sépare et vaut la chaîne vide à l'évaluation.
C'est le piège numéro un du format, et il ne se voit qu'à l'exécution.

Puis un nouveau build, une nouvelle version, un nouvel envoi TestFlight. **Le
build déjà installé ne se réparera jamais** : il porte l'ancienne adresse dans
son Info.plist. Incrémenter `CFBundleVersion` dans `ios/project.yml`, App Store
Connect refuse deux fois le même numéro.

## Domaine personnalisé, plus tard

Railway ▸ Settings ▸ Networking ▸ Custom Domain ▸ `api.memo-book.com`, puis le
`CNAME` que Railway indique chez le registrar de `memo-book.com`. Une fois le
certificat émis, remettre `https://api.memo-book.com` dans `Release.xcconfig` et
refaire un build. Faire ce changement **avant** d'avoir des utilisateurs évite
d'avoir à le faire après.

## Tester sur son propre iPhone sans rien déployer

Utile pour vérifier une correction tout de suite. Ça ne concerne qu'un build
lancé depuis Xcode sur un iPhone branché au Mac, **pas un build TestFlight**, et
les deux doivent être sur le même wifi.

    cp ios/Config/Secrets.example.xcconfig ios/Config/Secrets.xcconfig

Y mettre l'IP du Mac sur le réseau local (Réglages ▸ Wi-Fi ▸ le réseau ▸
Adresse IP) :

    MEMOBOOK_API_BASE_URL = http:/$()/192.168.1.20:3000

`Secrets.xcconfig` est ignoré par Git. Le back-end doit tourner sur le Mac
(`cd backend && npm run dev`), et le HTTP en clair passe grâce à
`NSAllowsLocalNetworking`, déjà dans l'Info.plist.

## Changer de stockage plus tard (Backblaze B2, R2, autre)

Le code ne connaît que l'interface `MediaStorage` et les variables `S3_*`.
Changer de fournisseur, c'est changer cinq variables et redémarrer :

    S3_ENDPOINT=https://s3.<region>.backblazeb2.com
    S3_REGION=<la région du bucket, ex. eu-central-003>
    S3_BUCKET=memobook-media
    S3_ACCESS_KEY_ID=<le keyID Backblaze>
    S3_SECRET_ACCESS_KEY=<l'applicationKey Backblaze>
    S3_FORCE_PATH_STYLE=true

Les clés d'objets (`audio/<uuid>.m4a`) ne contiennent ni le nom du bucket ni
celui du fournisseur : la base n'a rien à migrer, seuls les fichiers se
recopient, par exemple avec `rclone copy`. Prévoir une fenêtre où les deux
stockages coexistent, l'ancien en lecture, le temps de la copie.

⚠️ **Le piège qui coûte une demi-journée, et il est déjà désamorcé.** Depuis sa
version 3.729, le SDK AWS pose de lui-même un en-tête `x-amz-checksum-crc32` sur
chaque écriture. Le vrai S3 le comprend ; plusieurs fournisseurs compatibles le
rejettent, Backblaze B2 en tête, avec une erreur qui n'explique rien. C'est
pour ça que `createMediaStorage` fixe `requestChecksumCalculation` et
`responseChecksumValidation` à `WHEN_REQUIRED` : le SDK retrouve son
comportement d'avant, et n'envoie la somme de contrôle que là où le protocole
l'exige. Aucune garantie perdue, SigV4 signe déjà l'empreinte du corps.

Pour le vérifier sur un fournisseur donné, un serveur HTTP local qui journalise
les en-têtes reçus suffit : c'est ce qui a servi à constater le problème.
