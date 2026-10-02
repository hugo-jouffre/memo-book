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
| **Fin des 3 étapes offertes** | Facturation | Le lendemain de la validation de la dernière étape offerte, une fois (une semaine au plus après) | Pas abonné, étapes offertes épuisées | L'offre (`memobook://paywall`) |
| **Fin du voyage** | Facturation | Le jour de la date de fin, une fois | Propriétaire et co-voyageurs, alerte « Rappel de fin de voyage » allumée | La cagnotte du voyage : ce qui est déjà versé, l'estimation du carnet |
| **Relance d'écriture** (le carnet est arrêté) | Rythme | Après *n* jours de silence, *n* étant le rythme du récit du voyage ; au plus 3 relances par silence au rythme soutenu, **une** au rythme modéré ; à 19 h | Voyage en cours, alerte « Rappel d'écriture » allumée, rythme modéré ou soutenu | La conversation du voyage |
| **Nouveau récit** 💬 | Rythme | Dès qu'un co-voyageur a raconté un souvenir (texte, vocal, photos) et que MEMO lui a répondu ; une par nouveauté | Les **autres** membres du voyage, alerte « Nouveau récit » allumée, rythme soutenu | La conversation du voyage |
| **Le point de la semaine** 💬 | Rythme | Tous les 7 jours depuis le départ (fenêtre de 3 jours), à 18 h, si la semaine a capturé quelque chose | Propriétaire et co-voyageurs, voyage en cours, alerte « Résumé hebdomadaire » allumée, rythme modéré ou soutenu | La conversation du voyage |
| **Carnet terminé, pas commandé** | Rythme | 3 jours puis 10 jours après la fin | Le propriétaire, carnet non vide, aucune commande partie, rythme soutenu | L'aperçu du carnet, qui porte « Commander ce carnet » |
| **Vacances scolaires** | Vacances | J-7 et le jour J de chaque période | Rythme soutenu, aucun voyage déjà prévu sur ces dates. Zone du code postal ; sans code postal, les premières vacances de chaque période | « Créer un voyage » |
| **Comportement appris** | Vacances | 14 jours avant la date anniversaire d'un voyage passé (un voyage suffit) | Rythme soutenu, aucun voyage déjà prévu sur cette période | « Créer un voyage » |
| **Anniversaire** | Vacances | 7 jours avant | Rythme soutenu, pas en voyage, pas de voyage prévu ce jour-là | « Créer un voyage » |

Les textes sont dans `backend/src/services/notificationCopy.ts`. **Aucun ne vient
d'une maquette** : la feuille donne l'objectif et le ton, pas les mots. Clara
doit les relire (T242).

💬 **Les deux notifications marquées se prolongent dans le fil du voyage** : au
moment où elles partent, MEMO pose dans la conversation une bulle qui reprend
leurs mots — « Nouveau récit dans le carnet : Clara a ajouté 2 souvenirs. Qui
raconte la suite ? » —, pour qu'en touchant la notification on retrouve dans le
fil ce qu'on vient de lire. Le fil est **commun** aux co-voyageurs : la bulle ne
s'écrit qu'une fois, quel que soit le nombre de membres notifiés
(`payload.notification` porte sa clé) — une par jour au plus pour « Nouveau
récit », une par semaine pour le point —, et elle est tournée pour tous ceux
qui le lisent, l'auteur du récit compris. Elle attend que MEMO ait fini de répondre
(`findTurnInFlight`) pour ne pas tomber entre une question et sa réponse, et le
fil est remis à jour avant elle, comme à sa lecture — l'ouverture, les
souvenirs qui n'y étaient pas encore.

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
  personnalisé 0,5 · une fois par semaine 0,4 · question passée 0,25. Ce sont
  les réponses de l'app — la feuille « Rythme du récit » des réglages du
  voyage, plus fournie que l'étape de création ; le « rarement » de la feuille
  Notion n'y est pas ;
- **observé** : le taux d'ouverture des notifications, lu à partir de trois
  reçues sur 60 jours. Pondération **0,7 déclaré / 0,3 observé** ;
- **usage** : +0,1 si le voyageur a écrit à MEMO dans les 14 derniers jours. Un
  bonus et jamais une pénalité : celui qui se tait est justement celui que la
  relance doit aller chercher.

| Palier | Score | Reçoit |
|---|---|---|
| Soutenu | ≥ 0,6 | Tout |
| Modéré | ≥ 0,3 | Facturation, relances d'écriture (une par silence au lieu de trois) et le point de la semaine |
| Léger | < 0,3 | Facturation seulement |

La relance d'écriture suit le rythme choisi (« tous les 2 jours » : après deux
jours sans rien raconter, T184). Elle part deux fois moins souvent quand moins
d'une notification sur quatre est ouverte.

## 3. Les règles anti-saturation

`selectNotifications`, dans le même fichier :

- **La facturation passe toujours.** Un jour où elle part, rien d'autre ne part.
- **Une seule autre notification par jour**, la plus pertinente : un voyage réel
  (nouveau récit, carnet arrêté, point de la semaine, carnet pas commandé) passe
  avant le comportement appris, qui passe avant l'anniversaire, qui passe avant
  les vacances scolaires.
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
   caractères de la clé — ceux du nom du fichier, `AuthKey_<KEY_ID>.p8`),
   `APNS_TEAM_ID=HP2A94889S`, `APNS_PRIVATE_KEY` (le contenu **entier** du
   `.p8`, lignes `-----BEGIN/END PRIVATE KEY-----` comprises ; les retours à la
   ligne peuvent s'écrire `\n`). **Ces noms-là, exactement** : une clé posée
   sous `APPLE_PRIVATE_KEY` n'est lue par personne (vu le 02/10/2026).
4. **Vérifier** que la clé répond, sans rien envoyer à personne :

   ```bash
   cd backend && railway run --service worker --environment production -- npm run apns:check
   ```

   `BadDeviceToken — clé acceptée` sur les deux lignes, c'est bon : Apple a
   accepté la clé et refusé seulement le faux téléphone du test.
   `InvalidProviderToken`, c'est la clé : le Key ID n'est pas celui de ce
   `.p8`, ou la clé n'a pas le service APNs.
5. **Les migrations** `20261002090000_notifications_push` et
   `20261002130000_notifications_recit_et_resume` s'appliquent seules au
   déploiement (Pre-deploy Command, `docs/deploiement.md`).

Sans clé, rien ne casse : en développement les notifications sont journalisées
au lieu de partir, en production la passe ne fait rien et le dit dans les logs,
**sans rien marquer comme envoyé**.

Pour essayer dans le simulateur, sans serveur : glisser sur le simulateur un
fichier `.apns` qui contient `"Simulator Target Bundle": "com.memobook.app"`, un
`aps.alert` et une clé `link` (par exemple `memobook://paywall`). Le toucher
ouvre l'écran.

## 6. Les choix tranchés, et ce qui reste ouvert

**Tranché par Clara le 02/10/2026** — chaque choix est une constante :

| Point | Décision | Où |
|---|---|---|
| J-7, J-3, J *et* une seule notification Vacances par semaine | **J-7 et le jour J**, plus de J-3 | `SCHOOL_HOLIDAY_DAYS_BEFORE`, `notificationPlanner.ts` |
| « Fin des 3 jours offerts », alors que l'app offre trois étapes | On parle **d'étapes** : la notification part le lendemain de la dernière étape offerte | `TRIAL_END_DAYS_AFTER`, `trialEndText` |
| 2,99 €/semaine dans la feuille, 1,99 € dans le catalogue | **1,99 €/semaine** — le texte lit le catalogue | `subscriptionCatalog.ts` |
| Rythmes modéré et léger : « uniquement les essentielles » | Le modéré reçoit quand même ses relances d'écriture, **moins** : une par silence au lieu de trois | `MAX_REMINDERS_PER_SILENCE` |
| Source de la zone scolaire | Le code postal du profil ; **sans lui, les premières vacances** de chaque période (zones A, B, C), en attendant qu'il arrive | `schoolCalendarOf`, `earliestPeriods` (`schoolHolidays.ts`) |
| Pondération déclaré / observé | **0,7 / 0,3**, validé | `DECLARED_WEIGHT`, `notificationRhythm.ts` |
| « Arrêt au milieu du userflow : ?? » | Les deux cas couverts suffisent : carnet arrêté, carnet terminé pas commandé | `notificationPlanner.ts` |
| « Rarement », quatrième réponse de la feuille | On garde **les rythmes de l'app** — ceux des réglages du voyage, plus nombreux que ceux de la création ; `rarely` n'est plus lu | `DECLARED_SCORE`, `notificationRhythm.ts` |
| Nouveau récit, résumé hebdomadaire | **Créés**, et chacun doublé d'une bulle de MEMO dans le fil du voyage | `newStoryText`, `weeklyDigestText`, `postToThread` |
| Qui reçoit « Nouveau récit » | Le rythme soutenu seulement ; le modéré en a le point de la semaine (validé par Hugo le 02/10/2026) | `TIER_ALLOWS` |
| Le point de la semaine | Tous les 7 jours depuis le départ, à 18 h, si la semaine a capturé quelque chose ; aucun pour un voyage de moins d'une semaine, la fin du voyage fait ce point-là (validé le 02/10/2026) | `WEEKLY_DIGEST_EVERY_DAYS`, `notificationPlanner.ts` |
| Les mots de « Nouveau récit », du point de la semaine et de leurs bulles | Validés tels quels le 02/10/2026 | `newStoryText`, `weeklyDigestText` |
