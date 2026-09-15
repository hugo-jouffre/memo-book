# Les e-mails MemoBook

> Un seul point de commande pour tout ce qui part par e-mail — vérification
> d'adresse, mot de passe oublié, export de données, suivi de commande,
> newsletters — pilotable par l'app aujourd'hui et par une équipe CRM demain,
> sans réécrire la chaîne le jour où elle arrive.

---

## 1. Le malentendu à lever d'abord

« Tout gérer depuis un seul endroit » ne veut pas dire « tout envoyer avec un
seul outil ». Les équipes qui mettent leurs mots de passe oubliés dans le même
tuyau que leurs campagnes le paient de la même façon : une newsletter mal
segmentée fait grimper le taux de plainte, la réputation du domaine tombe, et
c'est le lien de réinitialisation qui finit en spam. Le client, lui, ne peut
plus entrer dans son compte.

Le point unique n'est donc pas l'expéditeur. Ce sont **quatre choses**, et elles
seules :

| Ce qui est unique | Où ça vit | Pourquoi là |
|---|---|---|
| **L'événement** qui déclenche | L'API, un seul endroit par fait métier | Une commande expédiée est un fait, pas un e-mail. Qui en fait quoi se décide plus loin |
| **Le consentement et les suppressions** | Postgres, tables `email_consents` et `email_suppressions` | La vérité sur « a-t-on le droit d'écrire à cette personne » ne peut pas vivre chez un prestataire qu'on changera |
| **Le registre des envois** | Postgres, table `outbound_messages` | Une seule requête répond à « Clara a-t-elle reçu son suivi ? », quel que soit l'outil qui l'a envoyé |
| **Le gabarit** | `templates/emails/` et son miroir dans le CRM | Corriger le pied de page une fois, pas onze |

Ce qui se dédouble, en revanche : **le domaine d'envoi** et **l'outil**. C'est
volontaire, et c'est la seule protection réelle contre l'accident ci-dessus.

---

## 2. Les deux familles

| | **Service** (transactionnel) | **Relation** (marketing) |
|---|---|---|
| Déclenché par | Un changement d'état : compte créé, colis parti | Un segment et une date |
| Destinataire | Une personne, la concernée | Une liste |
| Délai acceptable | Quelques secondes | Quelques heures |
| Consentement | **Non requis** — la personne a droit à son mot de passe | **Requis**, explicite, horodaté |
| Désinscription | Non (proposer d'arrêter les mots de passe oubliés n'a pas de sens) | Obligatoire, plus l'en-tête `List-Unsubscribe` |
| Qui écrit le texte | Le produit | Le CRM |
| Sous-domaine | `tx.memo-book.com` | `news.memo-book.com` |

La ligne de partage n'est pas « utile / promotionnel » mais **« la personne
l'attend-elle maintenant, parce qu'elle vient de faire quelque chose ? »**. Un
« ton carnet est prêt » est un e-mail de service, même s'il donne envie de
commander. Un « voici les cinq plus beaux carnets du mois » est une campagne,
même s'il est envoyé à un seul client.

---

## 3. La chaîne, de bout en bout

```
   App iOS / API                    Postgres (Supabase)                 Envoi
   ─────────────                    ───────────────────                 ─────

   POST /v1/auth/…      ┌──►  outbound_messages   ──┐
   webhook Stripe       │     (le registre)         │
   webhook imprimeur  ──┤                           ├─► pg-boss          ┌─► ESP transactionnel
   job de rendu         │     email_consents        │   memobook.email   │   tx.memo-book.com
   suppression compte   │     email_suppressions    │                    │
                        │                           └────────────────────┤
                        │                                                └─► Outil CRM
   emitEmail(event) ────┘                                                    news.memo-book.com
                                                                             (campagnes, segments)
                              ▲                                                    │
                              └──────── webhooks retour : ouvert, cliqué, ─────────┘
                                        rebond dur, plainte, désinscription
```

**Trois règles tiennent l'ensemble.**

1. **L'API n'appelle jamais un prestataire d'e-mail.** Elle écrit une ligne dans
   `outbound_messages` et publie un job. Le prestataire est derrière une
   interface `EmailSender`, exactement comme `AssetPublisher` et `MediaStorage`
   le sont déjà : en changer coûte un fichier, et les tests n'envoient rien.

2. **Une clé d'idempotence par ligne.** `(template_key, dedupe_key)` en unique,
   où `dedupe_key` vaut par exemple `print_order:<id>:shipped`. Un webhook
   rejoué — l'imprimeur et Stripe les rejouent — échoue sur la contrainte au
   lieu d'envoyer deux fois. C'est la base de données qui garantit l'unicité,
   pas le code. Même discipline que `WalletEntry.stripeEventId`.

3. **Les webhooks retour redescendent dans Postgres.** Un rebond dur ou une
   plainte écrit dans `email_suppressions`, et plus rien ne repart à cette
   adresse — campagne *comme* service. Une désinscription faite depuis un
   e-mail du CRM met à jour `email_consents`, pas seulement la liste du CRM.

---

## 4. Les trois niveaux de contrôle

C'est la réponse directe à « piloté par l'app quand il le faut, par le CRM quand
il existera ». Chaque e-mail est rangé dans un niveau, une fois, et ce niveau
dit qui peut le modifier sans demander à personne.

### Niveau 1 — au code, et seulement au code

Vérification d'adresse, mot de passe oublié, alerte de changement de mot de
passe, export de données, confirmation de suppression de compte, reçus.

Ces e-mails **transportent un secret** (un jeton à usage unique) ou **font foi**
(un reçu). Le gabarit vit dans `templates/emails/`, il passe en revue de code,
et le CRM ne peut pas l'éditer. Ce n'est pas de la défiance : un éditeur
visuel qui casse `{{ links.reset }}` verrouille tous les comptes de la journée,
et personne ne s'en aperçoit avant le support.

### Niveau 2 — déclenché par l'app, rédigé par le CRM

Suivi de commande, « ton carnet est prêt », invitation à un voyage, relances
d'onboarding, fin d'abonnement.

L'API émet l'événement avec ses données (`order.tracking`, `memo.title`…). Le
gabarit, lui, vit dans le CRM sous la même clé (`print_order.shipped`). Le CRM
récrit le texte, change l'image, teste un autre objet — **sans déploiement**. Le
contrat est la liste des variables, versionnée dans `templates/emails/README.md` :
tant qu'elle ne bouge pas, les deux côtés sont libres.

C'est le niveau qui grandit avec l'équipe. Aujourd'hui ces gabarits sont dans le
dépôt ; le jour où le CRM arrive, on bascule la clé côté routage et rien d'autre
ne change.

### Niveau 3 — au CRM, de bout en bout

Newsletters, campagnes saisonnières, réactivation, enquêtes de satisfaction.

L'API ne déclenche rien. Elle **alimente** le CRM : un job
`memobook.contact_sync` y pousse le contact et ses attributs à chaque
changement — prénom, langue, nombre de voyages, date du dernier voyage, a déjà
commandé, solde de cagnotte. Le CRM segmente là-dessus et envoie seul.

> **Le sens de la synchronisation ne s'inverse jamais.** Postgres est
> propriétaire de l'identité et du consentement ; le CRM en reçoit une copie.
> Un CRM qui redevient la source de vérité du consentement est un CRM qu'on ne
> peut plus quitter, et un RGPD qu'on ne peut plus prouver.

---

## 5. L'inventaire

État relevé le 15/09/2026 sur `backend/src/routes/`. La colonne « socle » dit ce
qui manque **côté serveur** — l'e-mail n'est jamais que le dernier mètre.

| E-mail | Clé | Déclencheur | Niveau | Socle |
|---|---|---|---|---|
| Vérification d'adresse | `account.verify_email` | `POST /v1/auth/signup` | 1 | **À construire** : jeton + `POST /v1/auth/email/verify` |
| Bienvenue | `account.welcome` | Adresse vérifiée | 2 | Prêt (`welcomeScreenSeenAt` existe) |
| Mot de passe oublié | `account.password_reset` | `POST /v1/auth/password/forgot` | 1 | **À construire** : la route n'existe pas |
| Mot de passe changé | `account.password_changed` | Après réinitialisation | 1 | Suit la précédente |
| Connexion sur un nouvel appareil | `account.new_device` | Création de `Session` | 1 | Prêt (`devices`) |
| Invitation à un voyage | `memo.invitation` | `MemoMember` en `invited` | 2 | Prêt |
| Carnet prêt à relire | `render.ready` | `Render` en `ready` | 2 | Prêt |
| Confirmation de commande | `print_order.confirmed` | `PrintOrder` en `submitted` | 2 | Arrive avec Stripe |
| En impression | `print_order.in_production` | Statut `in_production` | 2 | Webhook imprimeur |
| **Expédié** | `print_order.shipped` | `shippedAt` + `trackingUrl` | 2 | Webhook imprimeur — **gabarit fait** |
| Livré | `print_order.delivered` | `deliveredAt` | 2 | Webhook imprimeur |
| Reçu de paiement | `payment.receipt` | Webhook Stripe | 1 | Arrive avec Stripe |
| Cagnotte rechargée | `wallet.credited` | `WalletEntry` | 1 | Prêt |
| Export de données | `account.data_export` | Job d'export terminé | 1 | **À construire** : il n'y a que la suppression |
| Compte supprimé | `account.deleted` | `DELETE /v1/accounts/me` | 1 | Prêt |
| Abonnement : renouvellement, échec, fin | `subscription.*` | `Subscription` | 2 | Modèle prêt |
| Newsletter | `news.*` | Le CRM | 3 | Consentement à horodater |
| Réactivation, relances | `lifecycle.*` | Le CRM, sur segment | 3 | Dépend de `contact_sync` |
| Enquête de satisfaction | `feedback.campaign` | `FeedbackCampaign` | 3 | Modèle prêt |

**Trois flux sur cinq de ta liste n'ont pas encore de socle serveur.** La
vérification d'adresse, le mot de passe oublié et l'export de données n'existent
nulle part dans l'API : l'authentification est maison (`jose` + `scrypt`), donc
rien ne vient gratuitement — Supabase Auth, qui aurait fourni ces trois écrans
et leurs e-mails, n'est pas utilisé ici, et le back-end ne s'en sert que comme
Postgres et stockage. Ce sont des routes à écrire avant de parler de gabarit.

### Ce qu'un export de données demande, précisément

C'est le point le plus sous-estimé de la liste, et le plus réglementé — le RGPD
donne un mois pour répondre, dans un format lisible par machine.

1. Une route `POST /v1/accounts/me/export` qui publie un job, et rien d'autre :
   assembler les carnets, les souvenirs, les médias et les commandes de
   quelqu'un prend des minutes, pas des millisecondes.
2. Un job qui écrit un `.zip` dans S3 — JSON pour les données, les fichiers
   d'origine pour les médias.
3. Un lien **signé et périmable** (7 jours) dans l'e-mail. Jamais la pièce
   jointe : elle pèse des centaines de mégaoctets, et un e-mail se transfère.
4. L'e-mail part à l'adresse **vérifiée** du compte, et à elle seule.

---

## 6. Les tables

Trois tables, à ajouter au schéma Prisma. Rien de plus : le contact, lui, est
déjà `accounts`.

```prisma
/// Le registre de tout ce qui part. Une ligne par e-mail, transactionnel comme
/// campagne — c'est ce qui permet de répondre au support sans ouvrir trois
/// outils.
model OutboundMessage {
  id          String   @id @default(uuid())
  accountId   String?              // nul pour un invité qui n'a pas de compte
  toEmail     String
  templateKey String               // "print_order.shipped"
  class       EmailClass           // transactional | marketing
  locale      String   @default("fr")

  /// Ce qui rend un envoi unique. "print_order:<id>:shipped" — un webhook
  /// rejoué bute sur la contrainte plutôt que d'envoyer deux fois.
  dedupeKey   String

  payload     Json                 // les variables passées au gabarit
  status      EmailStatus          // queued | sent | delivered | bounced | complained | failed
  providerId  String?              // l'identifiant côté prestataire
  error       String?

  queuedAt    DateTime @default(now())
  sentAt      DateTime?
  openedAt    DateTime?
  clickedAt   DateTime?

  @@unique([templateKey, dedupeKey])
  @@index([toEmail, queuedAt])
  @@map("outbound_messages")
}

/// Le consentement marketing, avec sa preuve. `accounts.wantsNewsletter` reste
/// le drapeau que l'app lit ; cette table dit **quand** et **d'où** il a été
/// donné, ce qu'un booléen ne saura jamais dire à un régulateur.
model EmailConsent {
  id        String   @id @default(uuid())
  accountId String
  topic     String               // "newsletter", "product_updates"
  granted   Boolean
  source    String               // "signup", "settings", "crm_form"
  ip        String?
  at        DateTime @default(now())

  @@index([accountId, topic, at])
  @@map("email_consents")
}

/// Les adresses auxquelles on n'écrit plus, jamais, quel que soit le tuyau.
/// Réalimentée par les webhooks des deux prestataires.
model EmailSuppression {
  email     String   @id
  reason    String               // "hard_bounce" | "complaint" | "unsubscribe_all"
  source    String
  at        DateTime @default(now())

  @@map("email_suppressions")
}
```

**La règle d'envoi tient en deux lignes**, et c'est le seul endroit où elle est
écrite :

- *service* : on envoie si l'adresse n'est pas dans `email_suppressions` ;
- *campagne* : on envoie si, **en plus**, le dernier `EmailConsent` du sujet est
  `granted`.

---

## 7. Le domaine, et la réputation

C'est la partie qu'on ne peut pas rattraper après coup : une réputation abîmée
met des semaines à revenir, et pendant ce temps les mots de passe n'arrivent
plus.

| Enregistrement | Valeur | Pourquoi |
|---|---|---|
| **SPF** | `v=spf1 include:<esp> -all`, sur chaque sous-domaine | Dit quels serveurs ont le droit d'écrire en notre nom |
| **DKIM** | La clé du prestataire, par sous-domaine | Signe le message ; sans elle, Gmail classe d'office |
| **DMARC** | `p=none` d'abord, avec `rua=`, puis `p=quarantine` | `none` collecte les rapports sans rien casser. Passer à `quarantine` avant de les avoir lus coupe le courrier |
| **BIMI** | Plus tard, après `p=quarantine` | Affiche le logo MemoBook dans la boîte. Joli, mais il exige un DMARC déjà solide |

**Trois sous-domaines, un domaine racine intouché.**

- `tx.memo-book.com` — le service. Volume régulier, taux de plainte nul.
- `news.memo-book.com` — les campagnes. C'est lui qui prend les coups.
- `memo-book.com` — **on n'envoie rien depuis la racine.** Elle porte le site et
  les adresses humaines ; une campagne ratée ne doit pas pouvoir brûler
  l'adresse à laquelle les clients répondent.

Le reste du dossier : `Reply-To` sur une vraie boîte lue (le pied de page promet
qu'on lit, il faut tenir), chauffe progressive du domaine avant la première
grosse campagne, et pour les campagnes l'en-tête `List-Unsubscribe` avec
`List-Unsubscribe-Post` — Gmail et Yahoo l'exigent des expéditeurs de masse
depuis 2024, avec un taux de plainte tenu sous 0,3 %.

---

## 8. Le prestataire

L'arbitrage n'est pas « quel est le meilleur outil » mais « combien de systèmes
une équipe de trois personnes peut-elle opérer ». Réponse : un, aujourd'hui.

**Aujourd'hui — un prestataire qui fait les deux.** Brevo tient les deux
familles, héberge en Europe, facture au volume plutôt qu'au contact, et offre
au futur CRM une interface où il n'aura pas à réimporter la base. On garde les
sous-domaines séparés dès le premier jour : c'est gratuit à faire tout de suite,
et cher à faire après.

**Plus tard — le jour où le CRM veut un vrai outil de cycle de vie.** Le
transactionnel bascule sur Postmark ou Resend (réputation dédiée, meilleures
statistiques de remise), le marketing part chez Klaviyo, Customer.io ou HubSpot.
Comme l'API n'a jamais connu que `EmailSender`, ça reste un fichier à écrire —
et `outbound_messages` garde l'historique des deux périodes.

**Ce qu'on ne fait pas :** envoyer en SMTP direct depuis Railway. L'IP est
partagée, la réputation ne nous appartient pas, et il n'y a aucun webhook de
rebond — donc aucun moyen d'alimenter `email_suppressions`.

---

## 9. Les gabarits

Ils vivent dans **`templates/emails/`**, à la racine du dépôt, pour la même
raison que `templates/travel-journal/` : le back-end les lit, il ne les duplique
pas, et corriger un texte n'est pas une modification de TypeScript.

- `layout.njk` — l'en-tête, le pied, la palette, les parades de compatibilité.
  Le pied de page y distingue seul le service de la campagne.
- `<clé>.njk` — un fichier par e-mail, qui n'écrit que son contenu.
- `README.md` — le contrat de variables, celui que le CRM lira.

Nunjucks est déjà une dépendance du back-end : rien à installer.

**Le rendu suit ce que fait déjà `templates/travel-journal/`** — mêmes tokens
que `agents/design.md`, et des tests visuels sur le modèle de
`backend/test/visual/` : chaque gabarit rendu avec ses données d'exemple,
capturé, comparé. C'est ce qui empêche un bouton de disparaître chez Outlook
sans que personne ne le voie.

---

## 10. L'ordre de construction

L'ordre compte : chaque étape rend la suivante vérifiable.

1. **Le domaine et les enregistrements DNS.** Trois jours de propagation et de
   chauffe qu'on ne rattrape pas. À faire avant d'écrire une ligne de code.
2. **`EmailSender`, `outbound_messages` et le job `memobook.email`.** Le socle,
   avec un `FakeSender` qui écrit dans les journaux — comme `FakeRedactor`.
3. **Les routes manquantes** : vérification d'adresse, mot de passe oublié,
   export de données. C'est du travail d'API, pas d'e-mail, et c'est le plus
   long des trois.
4. **Les gabarits de niveau 1**, et leurs tests visuels.
5. **Les consentements et les suppressions**, avant la première campagne — pas
   après.
6. **`contact_sync` et le CRM**, le jour où quelqu'un est là pour s'en servir.

---

## À lire à côté

- [`templates/emails/README.md`](../templates/emails/README.md) — le contrat de
  variables et les règles de compatibilité des clients.
- [`agents/design.md`](../agents/design.md) — la palette et les typographies
  reprises par le gabarit.
- [`docs/deploiement.md`](deploiement.md) — les variables d'environnement et le
  worker qui fera tourner le job d'envoi.
