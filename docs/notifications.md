# Notifications

Les notifications envoyées par APNs : ce qui part, à qui, quel jour, et
pourquoi. La source est la feuille Notion « Notifications » (Clara). Ce document
dit comment elle est appliquée, et ce qui reste à trancher.

**Le serveur décide de tout.** L'app ne programme aucune notification locale :
elle donne son autorisation, envoie son jeton, et ouvre le bon écran quand on
touche une notification. Les règles vivent dans un seul fichier pur,
`backend/src/services/notificationPlanner.ts`, testé règle par règle.

## 1. Ce qui part

| Notification | Famille | Quand | Qui | Le toucher ouvre |
|---|---|---|---|---|
| **Fin des 3 jours offerts** | Facturation | J+3 après le premier voyage créé, une fois | Pas abonné, compte avec quota d'étapes | L'offre (`memobook://paywall`) |
| **Fin du voyage** | Facturation | Le jour de la date de fin, une fois | Propriétaire et co-voyageurs, alerte « Rappel de fin de voyage » allumée | La cagnotte du voyage : ce qui est déjà versé, l'estimation du carnet |
| **Relance d'écriture** (le carnet est arrêté) | Rythme | Après *n* jours de silence, *n* étant le rythme du récit du voyage ; au plus 3 relances par silence ; à 19 h | Voyage en cours, alerte « Rappel d'écriture » allumée, rythme modéré ou soutenu | La conversation du voyage |
| **Carnet terminé, pas commandé** | Rythme | 3 jours puis 10 jours après la fin | Le propriétaire, carnet non vide, aucune commande partie, rythme soutenu | L'aperçu du carnet, qui porte « Commander ce carnet » |
| **Vacances scolaires** | Vacances | J-7, J-3 et le jour J de chaque période | Rythme soutenu, zone scolaire connue, aucun voyage déjà prévu sur ces dates | « Créer un voyage » |
| **Comportement appris** | Vacances | 14 jours avant la date anniversaire d'un voyage passé (un voyage suffit) | Rythme soutenu, aucun voyage déjà prévu sur cette période | « Créer un voyage » |
| **Anniversaire** | Vacances | 7 jours avant | Rythme soutenu, pas en voyage, pas de voyage prévu ce jour-là | « Créer un voyage » |

Les textes sont dans `backend/src/services/notificationCopy.ts`. **Aucun ne vient
d'une maquette** : la feuille donne l'objectif et le ton, pas les mots. Clara
doit les relire (T242).

Deux précisions sur la fin du voyage, parce que les deux cas sont réels :

- un abonnement **App Store** n'est jamais arrêté par le serveur : Apple ne
  laisse aucune app résilier à la place de son client. La notification ne dit
  donc pas « arrêté automatiquement » : elle invite à couper le renouvellement,
  que l'accueil propose en un geste (`subscriptionOutlivesTrip`) ;
- si un autre voyage est à venir ou en cours, l'abonnement continue : la
  notification n'en parle pas.

## 2. Le rythme du voyageur

La feuille pose une question en début de voyage : « À quelle fréquence
souhaitez-vous être relancé ? ». **Cette question existe déjà** : c'est l'étape
« Notifications » de la création d'un voyage, qui écrit le rythme du récit
(`memos.narrationPace`). Le serveur la relit, plutôt que de poser une seconde
question qui dirait la même chose.

`backend/src/services/notificationRhythm.ts` en tire un score de 0 à 1 :

- **déclaré** : tous les jours 1 · tous les 2 jours 0,8 · tous les 3 jours 0,65 ·
  une fois par semaine 0,4 · rarement 0,1 · question passée 0,25 ;
- **observé** : le taux d'ouverture des notifications, lu à partir de trois
  reçues sur 60 jours. Pondération **0,7 déclaré / 0,3 observé** ;
- **usage** : +0,1 si le voyageur a écrit à MEMO dans les 14 derniers jours. Un
  bonus et jamais une pénalité : celui qui se tait est justement celui que la
  relance doit aller chercher.

| Palier | Score | Reçoit |
|---|---|---|
| Soutenu | ≥ 0,6 | Tout |
| Modéré | ≥ 0,3 | Facturation et relances d'écriture |
| Léger | < 0,3 | Facturation seulement |

La relance d'écriture suit le rythme choisi (« tous les 2 jours » : après deux
jours sans rien raconter, T184). Elle part deux fois moins souvent quand moins
d'une notification sur quatre est ouverte.

## 3. Les règles anti-saturation

`selectNotifications`, dans le même fichier :

- **La facturation passe toujours.** Un jour où elle part, rien d'autre ne part.
- **Une seule autre notification par jour**, la plus pertinente : un voyage réel
  (carnet arrêté, carnet pas commandé) passe avant le comportement appris, qui
  passe avant l'anniversaire, qui passe avant les vacances scolaires.
- **Une seule notification de la famille Vacances sur 7 jours glissants**, quel
  que soit le rythme.
- Rien avant 10 h (19 h pour la relance d'écriture), rien après 21 h, **dans le
  fuseau du téléphone** (`accounts.timeZone`, envoyé avec le jeton ; Paris par
  défaut).
- Chaque notification a une clé unique (`notification_deliveries.dedupeKey`) :
  la passe horaire peut repasser, rien ne part deux fois.

## 4. Comment ça tourne

| Pièce | Où |
|---|---|
| Jetons des téléphones | `push_tokens`, rattachés **à la session** : se déconnecter les supprime |
| Journal des envois | `notification_deliveries` : les clés uniques, les plafonds, `openedAt` |
| Calendrier scolaire | `school_holidays`, recopié chaque jour depuis data.education.gouv.fr (`fr-en-calendrier-scolaire`, Licence Ouverte), qui publie déjà l'année suivante |
| Passe d'envoi | tâche pg-boss `memobook.send-notifications`, à la 35e minute de chaque heure (`services/notifications.ts`) |
| Recopie du calendrier | tâche `memobook.sync-school-holidays`, à 5 h 40 UTC. Une panne du site garde le calendrier de la veille |
| Envoi APNs | `services/apns.ts` : HTTP/2 et JWT ES256, sans dépendance. Un jeton qu'Apple ne connaît plus est supprimé ; une panne passagère libère la clé pour que la passe suivante réessaie |

Côté app (`ios/Modules/Sources/MemoBookFeature/Notifications/`) :

- **L'autorisation est demandée à l'étape « Notifications » de la création d'un
  voyage**, quand on choisit un rythme : c'est le « bon moment » de
  l'onboarding. Passer l'étape ne demande rien. Allumer une alerte dans
  « Gérer mes notifications » la demande aussi, si elle n'a jamais été posée.
- Le jeton part à chaque entrée dans l'app (`POST /v1/push-tokens`), avec le
  fuseau et l'environnement (sandbox pour un build Xcode, production pour
  TestFlight et l'App Store).
- Le toucher ouvre l'écran du lien (`NotificationLink`) sur une pile neuve,
  posée sur le voyage. Il prévient aussi le serveur
  (`POST /v1/notifications/:id/opened`), qui en tient compte dans le rythme.
- Si tout est coupé dans les Réglages d'iOS, la feuille « Notifications » le dit
  et propose d'y aller (T245).

## 5. Configuration (Hugo)

À faire une fois, dans cet ordre :

1. **Apple Developer ▸ Identifiers ▸ `com.memobook.app`** : cocher **Push
   Notifications**. Sans ça, la signature automatique échoue sur
   `aps-environment` (déclaré dans `ios/project.yml`).
2. **Apple Developer ▸ Keys ▸ +** : cocher « Apple Push Notifications service
   (APNs) », télécharger le `.p8`. **Il ne se télécharge qu'une fois.**
3. **Railway, services `api` et `worker`** : poser `APNS_KEY_ID` (les 10
   caractères de la clé), `APNS_TEAM_ID=HP2A94889S`, `APNS_PRIVATE_KEY` (le
   contenu du `.p8`, les retours à la ligne peuvent s'écrire `\n`).
4. **Migration** `20261002090000_notifications_push` à appliquer en production,
   comme les autres (`docs/deploiement.md`).

Sans clé, rien ne casse : en développement les notifications sont journalisées
au lieu de partir, en production la passe ne fait rien et le dit dans les logs,
**sans rien marquer comme envoyé**.

Pour essayer dans le simulateur, sans serveur : glisser sur le simulateur un
fichier `.apns` qui contient `"Simulator Target Bundle": "com.memobook.app"`, un
`aps.alert` et une clé `link` (par exemple `memobook://paywall`). Le toucher
ouvre l'écran.

## 6. Points ouverts

Les trois points de la feuille, et ce que la spec ne permet pas d'appliquer
telle quelle. **Chaque choix fait est une constante, facile à changer.**

| Point | Choix fait | Où le changer |
|---|---|---|
| **Source de la zone scolaire** (feuille, § 5) | Le code postal de l'adresse du profil, puis le département et l'académie. Qui n'a pas donné d'adresse (on la demande à la commande) ne reçoit pas les vacances scolaires. Demander la zone ailleurs reste à décider (T243) | `schoolZoneOf`, `services/schoolHolidays.ts` |
| **Seuil d'historique** du comportement appris | Un voyage, comme tranché | `notificationPlanner.ts` |
| **Pondération déclaré / observé** (feuille, § 5) | 0,7 / 0,3 | `DECLARED_WEIGHT`, `notificationRhythm.ts` |
| **J-7, J-3, J *et* une seule notification Vacances par semaine** : impossible d'avoir les deux, J-3 tombe 4 jours après J-7 | Le plafond l'emporte : **J-7 puis le jour J**. J-3 ne part que si J-7 n'est pas parti (voyageur arrivé entre les deux, passe manquée) | `HOLIDAY_COOLDOWN_DAYS`, `notificationPlanner.ts` |
| **« Fin des 3 jours offerts »** : l'app offre aujourd'hui trois **étapes**, pas trois jours | J+3 du premier voyage, comme la feuille le demande. Le texte reste vrai dans les deux modèles : il ne dit pas « ton essai est fini » | `trialEndText`, `notificationCopy.ts` |
| **2,99 €/semaine** dans la feuille, **1,99 €** dans le catalogue | Le texte lit le catalogue (`SUBSCRIPTION_WEEKLY_CENTS`) : il dira toujours le prix réel | `subscriptionCatalog.ts` |
| **Rythmes modéré et léger : « uniquement les essentielles »** | Le modéré reçoit aussi les relances d'écriture **qu'il a demandées** en choisissant « Une fois par semaine ». Ne lui en envoyer aucune contredirait l'étape « Notifications » | `TIER_ALLOWS`, `notificationPlanner.ts` |
| **« Rarement »**, quatrième réponse de la feuille | Comprise par le serveur (`rarely`), absente de l'étape de création tant que la maquette ne la dessine pas (R3, T244) | `TripCreationStepContent.paces` |
| **« Arrêt au milieu du userflow : ?? »** | Deux cas couverts : carnet arrêté (relance d'écriture), carnet terminé mais pas commandé | `notificationPlanner.ts` |
| **Nouveau récit, résumé hebdomadaire** (deux des quatre alertes de la feuille du voyage) | Pas dans la spec, rien ne les envoie encore | — |
