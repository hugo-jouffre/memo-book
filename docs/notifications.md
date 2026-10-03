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
| **Fin du voyage** | Facturation | Le jour de la date de fin, une fois | Propriétaire et co-voyageurs, alerte « Rappel de fin de voyage » allumée | La cagnotte du voyage et l'estimation du carnet |
| **Avant le renouvellement** | Facturation | 3 jours avant le renouvellement de l'abonnement (2 si la passe l'a manqué, jamais la veille), une fois par période | Abonnement App Store au renouvellement armé, aucun voyage en cours ni prévu d'ici le renouvellement, pas de « Fin du voyage » ces 3 derniers jours, pas dans les jours de l'e-mail de fin de voyage (de la fin à J+3), pas d'autre rappel ces 25 derniers jours | La feuille de l'abonnement (`memobook://subscription`), où il se coupe en un geste |
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

Trois précisions sur la fin du voyage et l'abonnement, qui est **mensuel**
depuis le 03/10/2026 (4,99 €/mois, l'illimité pour l'abonné seul) :

- **plus aucun abonnement ne s'arrête seul**, et le serveur ne peut pas en
  arrêter un : Apple ne laisse aucune app résilier à la place de son client. La
  notification **invite doucement** à couper le renouvellement, que l'accueil
  propose en un geste (`subscriptionOutlivesTrip`) — « Ton abonnement ne te sert
  plus d’ici ton prochain voyage ? Coupe-le en un geste depuis l’accueil, tu
  gardes l’illimité jusqu’au 1er novembre. » —, puis donne l'estimation du
  carnet. La date est celle du renouvellement (`subscriptions.renewsAt`) : résilié,
  l'illimité court jusqu'au bout de la période payée ;
- si un autre voyage est à venir ou en cours, l'abonnement sert encore : la
  notification n'en parle pas ;
- la fin du voyage tombe n'importe où dans le mois payé : d'où **le rappel
  avant le renouvellement**, trois jours avant qu'Apple ne prélève, quand plus
  aucun voyage ne court. Jamais la veille : Apple demande de résilier au moins
  vingt-quatre heures avant. Il se tait quand la fin du voyage vient de le
  dire — la notification de fin ces trois derniers jours, **ou l'e-mail de fin
  de voyage**, de la date de fin à J+3 : l'e-mail n'est pas dans l'historique
  que relit le planificateur, la règle se lit donc sur la date de fin, et elle
  tient même quand « Rappel de fin de voyage » est coupé. Et jamais deux rappels
  à moins de 25 jours : l'ancien abonnement à la semaine, encore honoré, n'en
  reçoit qu'un toutes les quatre semaines au lieu d'un chaque semaine
  (03/10/2026).

### L'e-mail de fin de voyage

Le **lendemain** de la fin d'un voyage (jusqu'à J+3 si la passe l'a manqué),
entre 10 h et 21 h chez le voyageur, un e-mail redit le rappel à qui a un
abonnement App Store au renouvellement armé et plus aucun voyage en cours ou
prévu : « Ton voyage est fini : pense à ton abonnement », le chemin dans les
Réglages de l'iPhone (Réglages ▸ ton nom ▸ Abonnements), la date jusqu'à laquelle
l'illimité reste ouvert, et le carnet qui attend sa commande.

Il part **aussi aux comptes sans téléphone enregistré** — c'est tout son
intérêt — et ne dépend ni des alertes du voyage ni du rythme : c'est la promesse
du paywall, « On te rappelle de résilier », pas une relance. Une fois par voyage :
il est journalisé dans `notification_deliveries` (kind `trip_end_email`, clé
`<compte>:trip_end_email:<voyage>`), mais le planificateur ne le relit pas — il
ne compte ni dans le taux d'ouverture, ni dans « une notification par jour ».
La règle est `planTripEndEmail`, l'envoi `sendTripEndEmails`, le texte
`renderSubscriptionReminderMail` et le gabarit Resend `subscription-reminder`
(voir `docs/emails.md`).

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
| Modéré | ≥ 0,3 | Facturation (fin du voyage, rappel avant le renouvellement), relances d'écriture (une par silence au lieu de trois) et le point de la semaine |
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
| Passe d'envoi | tâche pg-boss `memobook.send-notifications`, à la 35e minute de chaque heure (`services/notifications.ts`). Elle envoie aussi l'e-mail de fin de voyage (`sendTripEndEmails`), indépendamment d'APNs |
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
5. **Les migrations** `20261002090000_notifications_push`,
   `20261002130000_notifications_recit_et_resume` et
   `20261003090000_credit_du_jour` (qui retire `trial_end` et ajoute
   `renewal_reminder` et `trip_end_email`) s'appliquent seules au déploiement
   (Pre-deploy Command, `docs/deploiement.md`).

Sans clé, rien ne casse : en développement les notifications sont journalisées
au lieu de partir, en production la passe ne fait rien et le dit dans les logs,
**sans rien marquer comme envoyé**.

Pour essayer dans le simulateur, sans serveur : glisser sur le simulateur un
fichier `.apns` qui contient `"Simulator Target Bundle": "com.memobook.app"`, un
`aps.alert` et une clé `link` (par exemple `memobook://subscription`). Le
toucher ouvre l'écran.

## 6. Les choix tranchés, et ce qui reste ouvert

**Tranché par Clara le 02/10/2026** — chaque choix est une constante :

| Point | Décision | Où |
|---|---|---|
| J-7, J-3, J *et* une seule notification Vacances par semaine | **J-7 et le jour J**, plus de J-3 | `SCHOOL_HOLIDAY_DAYS_BEFORE`, `notificationPlanner.ts` |
| Rythmes modéré et léger : « uniquement les essentielles » | Le modéré reçoit quand même ses relances d'écriture, **moins** : une par silence au lieu de trois | `MAX_REMINDERS_PER_SILENCE` |
| Source de la zone scolaire | Le code postal du profil ; **sans lui, les premières vacances** de chaque période (zones A, B, C), en attendant qu'il arrive | `schoolCalendarOf`, `earliestPeriods` (`schoolHolidays.ts`) |
| Pondération déclaré / observé | **0,7 / 0,3**, validé | `DECLARED_WEIGHT`, `notificationRhythm.ts` |
| « Arrêt au milieu du userflow : ?? » | Les deux cas couverts suffisent : carnet arrêté, carnet terminé pas commandé | `notificationPlanner.ts` |
| « Rarement », quatrième réponse de la feuille | On garde **les rythmes de l'app** — ceux des réglages du voyage, plus nombreux que ceux de la création ; `rarely` n'est plus lu | `DECLARED_SCORE`, `notificationRhythm.ts` |
| Nouveau récit, résumé hebdomadaire | **Créés**, et chacun doublé d'une bulle de MEMO dans le fil du voyage | `newStoryText`, `weeklyDigestText`, `postToThread` |
| Qui reçoit « Nouveau récit » | Le rythme soutenu seulement ; le modéré en a le point de la semaine (validé par Hugo le 02/10/2026) | `TIER_ALLOWS` |
| Le point de la semaine | Tous les 7 jours depuis le départ, à 18 h, si la semaine a capturé quelque chose ; aucun pour un voyage de moins d'une semaine, la fin du voyage fait ce point-là (validé le 02/10/2026) | `WEEKLY_DIGEST_EVERY_DAYS`, `notificationPlanner.ts` |
| Les mots de « Nouveau récit », du point de la semaine et de leurs bulles | Validés tels quels le 02/10/2026 | `newStoryText`, `weeklyDigestText` |

**Tranché par Hugo le 03/10/2026** — le crédit du jour remplace les étapes
offertes, l'abonnement devient mensuel (le code d'avant est sur la branche
`icebox/abonnement-hebdomadaire`) :

| Point | Décision | Où |
|---|---|---|
| « Fin des 3 étapes offertes » (`trial_end`) | **Retirée** : il n'y a plus d'étapes offertes. Ses envois journalisés partent avec la valeur de l'énumération | migration `20261003090000_credit_du_jour` |
| « Ton abonnement s’arrête automatiquement » | **Retiré** : plus aucun abonnement ne s'arrête seul. La fin du voyage n'invite à couper que l'abonnement App Store au renouvellement armé | `tripEndText`, `ArmedRenewal` |
| La déduction des semaines payées du prix du carnet | **Retirée**, avec ses phrases et le calcul de ce qui était versé | `notificationCopy.ts` |
| Le texte de la fin du voyage | Invite doucement à couper l'abonnement en un geste depuis l'accueil, et dit jusqu'à quand l'illimité reste ouvert | `tripEndText` |
| Un rappel avant le renouvellement | **Créé** (`renewal_reminder`) : J-3, ou J-2 en rattrapage, une fois par période et jamais deux à moins de 25 jours, vers `memobook://subscription` ; muet les jours de l'e-mail de fin de voyage | `RENEWAL_REMINDER_DAYS_BEFORE`, `RENEWAL_REMINDER_MIN_GAP_DAYS`, `tripEndEmailWindow`, `renewalReminderText` |
| Le même rappel par e-mail | **Créé** (`trip_end_email`) : le lendemain de la fin du voyage, aussi sans téléphone enregistré | `planTripEndEmail`, `sendTripEndEmails` |
