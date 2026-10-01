# Paiements — Stripe, StoreKit, et ce qui va où

Ce que le dépôt encaisse, par quel rail, et comment le vérifier.

## La règle qui décide de tout

> 🚨 **Ce n'est pas un choix technique, c'est une contrainte de validation App Store.**
>
> | Ce qu'on vend | Rail | Pourquoi |
> |---|---|---|
> | Abonnement hebdomadaire | **StoreKit 2** | Service numérique → Apple impose l'achat intégré |
> | Carnet imprimé | **Stripe** | Bien physique → l'achat intégré est **interdit** |
> | Cagnotte | **Stripe** | Elle ne finance que du physique |

La cagnotte ne doit **jamais** pouvoir payer l'abonnement : du crédit acheté par
Stripe qui déverrouillerait une fonctionnalité numérique contournerait l'achat
intégré. C'est pour ça qu'il n'existe aucune branche « cagnotte » sur le chemin
d'abonnement, et que `PAYMENT_KIND` (`src/services/billing.ts`) ne porte que
deux valeurs, toutes deux physiques.

## Les trois chemins d'encaissement

```
POST /memos/:id/orders
  └─ la cagnotte couvre ce qu'elle peut → WalletEntry (débit), immédiate
       ├─ reste 0 € ─────────────────────────────────────────→ submitted
       └─ reste > 0 € → PaymentIntent → feuille → webhook ────→ submitted

POST /wallet/topup ──→ PaymentIntent ─→ feuille ─→ webhook ─→ WalletEntry + solde
```

> ⚠️ **La cagnotte n'est pas un mode de paiement qu'on choisit.** Il n'y a pas
> de drapeau `payWithWallet` : elle s'applique toujours, à hauteur de ce qu'elle
> contient, et l'intention Stripe ne porte que le reste. Trente euros sur un
> carnet à cent n'est donc pas un solde insuffisant — c'est un acompte, et la
> carte paie les soixante-dix restants.

**Une commande naît toujours en `draft`** et n'en sort que sur confirmation —
webhook pour une carte, écriture de registre quand la cagnotte a tout couvert.

> ⚠️ **Ne jamais faire passer une commande en `submitted` depuis le retour de
> l'app.** L'app peut être tuée entre le paiement et son rappel. Stripe, lui,
> rejoue son webhook jusqu'à obtenir un 2xx.

## Côté app

Un seul module touche à l'argent — `MemoBookPayments` — et une seule façade y
mène : `PaymentPresenter`. Les écrans ne voient jamais le SDK Stripe, et
`AppDependencies.preview()` y branche `StubPaymentPresenter` pour qu'un aperçu
SwiftUI ne puisse pas ouvrir une feuille, même par accident.

| Étape | Qui | Ce qui se passe |
|---|---|---|
| Commander | `OrderModel.pay()` | `POST /orders` → `PlacedPrintOrder` |
| Régler | `PaymentPresenter.present` | la feuille, montée sur `clientSecret` |
| Conclure | `OrderModel.settled(_:)` | relit `GET /orders/:id` jusqu'à sortir de `draft` |

`OrderPayment.settlement` tranche en un seul endroit ce que l'app doit faire :
`.wallet` (rien à encaisser), `.card` (feuille), ou `.unavailable`. Ce dernier
n'est pas un cas d'usage mais **une panne de configuration** — l'API déployée
n'a pas ses clés Stripe — et il affiche un message au lieu d'une confirmation :
une commande non payée ne doit jamais ressembler à une commande passée.

> ⚠️ **Une feuille qui rend `.succeeded` ne veut pas dire « commande validée ».**
> Elle dit que Stripe a accepté, pas que notre serveur l'a appris. D'où la
> relecture, côté commande comme côté cagnotte : le solde ne monte qu'une fois
> le webhook écrit au registre, une seconde ou deux plus tard.

> ⚠️ Annuler la feuille **n'est pas une erreur** : la commande reste en
> brouillon et « Payer » la reprend. La clé d'idempotence étant l'identifiant de
> la commande, Stripe rend la même intention — pas un second débit.

## Ce qui rend le rejeu inoffensif

Stripe rejoue, et il envoie plusieurs événements par paiement. **C'est le mode
de fonctionnement normal, pas un incident.** Quatre garde-fous, tous tenus par
la base de données plutôt que par du code applicatif :

| Garde-fou | Où | Ce qu'il empêche |
|---|---|---|
| `wallet_entries.stripeEventId` unique | schéma | Créditer deux fois une recharge |
| `print_orders.stripePaymentIntentId` unique | schéma | Deux intentions sur une commande |
| `updateMany where status: "draft"` | `stripeWebhook.ts` | Réécrire `submittedAt` au rejeu |
| `SELECT … FOR UPDATE` sur le compte | `walletLedger.ts` | Deux débits concurrents qui passeraient tous les deux |

Une erreur de traitement est **journalisée puis acquittée** (200) : un 500 ferait
rejouer, et un bug déterministe reviendrait toutes les heures pendant trois jours.

## Vérifier en local

Trois choses à lancer, dans cet ordre :

```bash
stripe listen --forward-to localhost:3000/v1/webhooks/stripe
```

Le `whsec_…` affiché va dans `STRIPE_WEBHOOK_SECRET`. **Il est propre à chaque
point de terminaison** : celui-ci n'est pas celui de Railway.

```bash
cd backend && npm run dev
```

```bash
cd backend && npm run stripe:e2e
```

Le dernier déroule tout le parcours avec le **vrai** Stripe en mode test :
compte, carnet, commande, paiement carte 4242, attente du webhook, contrôle
d'idempotence, recharge de cagnotte, puis une seconde commande où la cagnotte
paie une partie et la carte le reste. C'est le seul chemin qui exerce la vraie
signature de webhook — `test/payments.test.ts` passe par `FakePaymentGateway`
et ne peut pas la couvrir.

`stripe listen` marche sans `stripe login` : `--api-key "$STRIPE_SECRET_KEY"`
suffit, et évite d'appairer la machine à un compte pour lancer une vérification.

### Cartes de test

Date d'expiration : n'importe laquelle dans le futur. CVC : trois chiffres au
hasard. **Elles ne fonctionnent qu'en mode test.**

| Numéro | Comportement |
|---|---|
| `4242 4242 4242 4242` | ✅ Paiement accepté |
| `4000 0025 0000 3155` | ⚠️ Authentification 3D Secure demandée |
| `4000 0000 0000 0002` | ✗ Refus générique |
| `4000 0000 0000 9995` | ✗ Refus pour provision insuffisante |

La liste complète est sur <https://docs.stripe.com/testing>.

## Configuration

### Ce qui est dans le dépôt

| Variable | Où | Note |
|---|---|---|
| `STRIPE_SECRET_KEY` | `backend/.env` | **Secrète.** Ne sort jamais du serveur |
| `STRIPE_PUBLISHABLE_KEY` | `backend/.env` | Publique — elle part dans l'app, avec chaque réponse de paiement |
| `STRIPE_WEBHOOK_SECRET` | `backend/.env` | Propre à chaque point de terminaison |

### En production (Railway, service `api`)

Les trois mêmes variables, **en mode test** — le compte est le bac à sable
`MemoBook Test` (`acct_1UFioWBknFHnQoHL`). Le point de terminaison a été créé le
16 septembre 2026 :

| | |
|---|---|
| Identifiant | `we_1UG765BknFHnQoHL2aidvVgI` |
| URL | `https://api-production-9f35a.up.railway.app/v1/webhooks/stripe` |
| Événements | `payment_intent.succeeded`, `payment_intent.payment_failed`, `charge.refunded` |

Ce sont exactement les `HANDLED_EVENTS` de `services/payments.ts` : s'y abonner
plus largement ferait livrer des événements qu'on acquitte sans rien en faire.

> 🚨 **Son `whsec_` n'est pas celui de `stripe listen`.** Un secret de webhook
> appartient à un point de terminaison, pas à un compte. Recopier celui du local
> dans Railway fait échouer *toutes* les signatures — et les commandes restent
> en `draft` sans que rien ne le signale côté app.

Vérifier que le déployé encaisse, sans toucher à sa base :

```bash
curl -s -X POST https://api-production-9f35a.up.railway.app/v1/webhooks/stripe \
  -H 'stripe-signature: t=1,v1=deadbeef' -d '{}'
```

Une réponse qui parle de signature invalide veut dire que le secret est posé.
Si elle dit « `STRIPE_WEBHOOK_SECRET` est vide », c'est que la variable manque —
et à ce moment-là **aucune commande ne peut sortir de `draft` en production**.

Le serveur **refuse de démarrer** si les deux clés ne sont pas du même mode
(`sk_live_` avec `pk_test_`, ou l'inverse) : le mélange fait échouer le paiement
*après* que l'utilisateur a validé Face ID.

### Ce qui reste à faire à la main

| Sujet | Où | Effet tant que ce n'est pas fait |
|---|---|---|
| **Adresse du siège** | Tableau de bord → Tax → Settings | `status: pending` — **aucune taxe n'est calculée** |
| **Immatriculation TVA** | Tax → Registrations | Stripe ne collecte rien, **et ne lève aucune erreur** |
| **Identifiant marchand Apple Pay** | Portail Apple + Stripe | La feuille montre les cartes seules |
| Clé restreinte (`rk_`) | Développeurs → Clés API | — (bonne pratique avant la production) |

> 🚨 **Le piège de Stripe Tax.** Sans immatriculation active, Stripe ne
> calcule ni ne collecte rien **et ne signale pas d'erreur**. On croit la TVA
> activée et on encaisse du HT. Revérifié le 16 septembre 2026 :
> `tax/settings` est en `pending`, `status_details.pending.missing_fields` ne
> contient que `head_office`, et `tax/registrations` renvoie **zéro** ligne.
>
> Se relit en deux commandes, sans passer par le tableau de bord :
> `stripe get /v1/tax/settings` et `stripe get /v1/tax/registrations`.

> ⚠️ **`automatic_tax` ne s'applique pas à un PaymentIntent.** Il n'existe que
> sur les Subscriptions, Invoices et Checkout Sessions. Notre flux est un
> PaymentIntent — obligatoire pour une feuille de paiement native. Il faudra
> donc passer par l'**API Tax Calculation** : calculer depuis l'adresse de
> livraison et le code fiscal produit, puis créer l'intention sur le total.

## Moyens de paiement

Le serveur ne liste **jamais** les moyens acceptés : il passe
`automatic_payment_methods: { enabled: true }`, et c'est le tableau de bord qui
décide. Activer un moyen devient une case à cocher, pas une livraison.

> ⚠️ Ne jamais ajouter `payment_method_types` à un appel Stripe. C'est une règle
> explicite de Stripe : ce paramètre coupe la sélection dynamique et fait
> chuter la conversion. Pour restreindre, utiliser `payment_method_configurations`
> ou `excluded_payment_method_types`.

Au 16 septembre 2026, la configuration « Default » du bac à sable (celle par
défaut) compte **quinze** moyens actifs, dont `card`, `link`, `klarna`,
`amazon_pay` et `apple_pay`. À relire avec
`stripe get /v1/payment_method_configurations`.

> ⚠️ **`apple_pay` est actif chez Stripe et n'apparaîtra pourtant pas.** Ce
> n'est pas le tableau de bord qui bloque, c'est l'app : sans identifiant
> marchand Apple, `StripePaymentSheetPresenter` reçoit `applePayMerchantId:
> nil` et ne configure pas `configuration.applePay` — la feuille montre alors
> les cartes seules. Le manque est du côté du portail Apple, pas de Stripe.

## Le prix

Une seule formule, dans `src/lib/pricing.ts`, pour deux lecteurs : l'estimation
affichée sur la carte de cagnotte et le montant réellement débité. Un test
vérifie qu'ils sont égaux au centime.

> ⚠️ **Le prix est à trancher avec l'imprimeur.** 1,798 € la page, frais fixes
> et port compris — ce qui est faux dès qu'on s'éloigne de cinquante pages. Et
> `billablePageCount()` retombe sur `targetPageCount` parce que
> `Memo.pageCount` n'est jamais écrit par le back-end. Les deux sont signalés
> dans le code.

## L'abonnement, et les limites de souvenirs

Deux choses à vendre, un seul tarif chacune, **écrites une fois** dans
`src/services/subscriptionCatalog.ts` :

| | Prix | Clé Stripe |
|---|---|---|
| Abonnement | **1,99 €/semaine** | `memobook_subscription_weekly` |
| Limites de souvenirs étendues | **3,99 €/semaine** | `memobook_memory_upgrade_weekly` |

**Le tarif est servi même à qui n'a rien souscrit** (16/09/2026). Il ne l'était
pas : `GET /v1/profile` rendait `weeklyPrice: 0` faute de ligne `subscriptions`
à lire, et l'app écrivait donc « 0,00 €/semaine » sur la feuille d'offre, sur le
paywall et « 3 × 0,00 € » sur l'estimation. Un prix ne dépend pas de ce que la
personne a déjà acheté : c'est un tarif, il vit dans un catalogue. Côté app,
`Subscription.displayedWeeklyPrice` est le second filet — il ne rend jamais zéro.

⚠️ **L'abonnement s'encaisse par StoreKit, l'extension pas encore** (01/10/2026).
Apple impose l'achat intégré pour un service numérique : `PAYMENT_KIND` ne
porte donc aucune valeur d'abonnement (voir `billing.ts`), et c'est la section
[L'abonnement App Store](#labonnement-app-store-storekit) qui dit comment il
s'achète. Les références Stripe existent pour le jour où l'offre se vend aussi
hors de l'app — le web —, et pour que le back-end sache de quel prix il parle.

**Les deux prix vivent sous le même produit Stripe**, « Abonnement MemoBook »
(`prod_VGyIuAiG0DcXLa`) : l'extension n'est pas une seconde offre, c'est une
option de l'abonnement (Hugo, 17/09/2026).

État du sandbox Stripe (`acct_1UFioWBknFHnQoHL`, *MemoBook Test*) :

| Prix | | `lookup_key` | |
|---|---|---|---|
| `price_1UGQMe…` | 1,99 €/semaine | `memobook_subscription_weekly` | actif |
| `price_1UGRnH…` | 3,99 €/semaine | `memobook_memory_upgrade_weekly` | actif |
| `price_1UGRhK…` | 3,99 €/**mois** | `memobook_memory_upgrade_monthly` | **désactivé** |

⚠️ **L'intervalle d'un prix Stripe ne se modifie pas.** Le mensuel avait été créé
par erreur ; on ne le corrige pas, on en crée un neuf à la bonne cadence et on
désactive l'ancien — un prix ne se supprime jamais, il se désactive.

Une **`lookup_key` et non un identifiant de prix** : celui-ci change entre le
sandbox et la production, celle-là non. C'est ce qui permet de poser la même
valeur dans les deux comptes sans variable d'environnement de plus.

### La semaine payée va à son terme

Une semaine commencée est une semaine réglée : résilier le lundi ne rend pas les
six jours suivants, donc ça ne ferme pas le micro non plus (Hugo, 16/09/2026).

`subscriptions.renewsAt` est la fin de la période payée. Elle sort dans
`subscription.paidThrough`, et **deux verrous la lisent** : `assertCanRecord`
côté serveur, qui accepte un abonnement `cancelled` ou `expired` dont la période
court encore ; et `Subscription.grantsAccess()` côté app, que lisent
`freemiumStatus` et `isSubscriber` — jamais `isActive` seul.

Le dernier jour, rien ne change : la résiliation garde sa phrase d'avant,
« l'abonnement s'arrête aujourd'hui ». Il n'y a pas de sursis à annoncer pour un
jour qui est déjà là.

## L'abonnement App Store (StoreKit)

1,99 €/semaine, produit **`com.memobook.app.subscription.weekly`**, groupe
d'abonnements « MemoBook ». L'identifiant est écrit trois fois et doit rester
le même partout : `APP_STORE_PRODUCT_IDS` (`subscriptionCatalog.ts`),
`StoreKitCatalog` (`MemoBookPayments`) et `ios/Config/MemoBook.storekit`.
Apple ne le laisse ni modifier ni réutiliser.

```
App ─ Product.purchase(appAccountToken: id du compte)
  └─ feuille d'Apple ─ Face ID ─→ transaction signée (JWS)
       └─ POST /v1/subscriptions/app-store ─→ vérifiée ─→ subscriptions + registre
            └─ 2xx ─→ transaction.finish()           (sinon : rejouée au lancement)

Apple ─ POST /v1/webhooks/app-store (notifications v2)
  └─ renouvellement, renouvellement coupé, délai de grâce, expiration, remboursement
```

**Deux portes, la même écriture** (`services/appStoreSubscriptions.ts`) : l'app
ouvre le micro dans la seconde qui suit l'achat, Apple dit tout le reste — y
compris ce qui se passe app fermée. Une ligne `subscriptions` par
`originalTransactionId` (rouverte quand on se réabonne au voyage suivant), une
ligne `subscription_transactions` par semaine payée.

| Chez Apple | `subscriptions.status` | Accès |
|---|---|---|
| actif, renouvellement armé | `active` | oui |
| actif, renouvellement coupé dans iOS | `cancelled` | jusqu'à `renewsAt` |
| délai de grâce | `past_due` | oui, Apple l'accorde |
| nouvelle tentative de prélèvement | `expired` | non |
| expiré | `expired` | non |
| remboursé, révoqué | `expired` | non, dès la révocation |

### Ce qui rend le rejeu inoffensif, ici aussi

| Garde-fou | Où | Ce qu'il empêche |
|---|---|---|
| `subscriptions.providerSubscriptionId` unique | schéma | Deux abonnements pour un paiement |
| `subscription_transactions.transactionId` unique | schéma | Inscrire deux fois une semaine |
| `providerUpdatedAt` | `appStoreSubscriptions.ts` | Un événement en retard qui rouvrirait un abonnement coupé |
| `finish()` après le 2xx seulement | `SubscriptionStore.swift` | Perdre un achat fait dans un tunnel |

### 🚨 Apple seul résilie

**Aucune app ne peut résilier à la place de son client.** C'est pourquoi la
promesse « arrêt automatique à la fin du voyage » est devenue un **rappel**
(Hugo, 01/10/2026) :

- la passe de fin de voyage (`sweepEndedSubscriptions`) **ignore** les lignes
  StoreKit — les fermer pendant qu'Apple prélève, c'était faire payer
  quelqu'un dont le micro est fermé ;
- `GET /v1/home` rend `traveller.subscriptionOutlivesTrip` quand l'abonnement va
  se renouveler sans voyage en cours, et l'accueil propose de résilier — une
  fois par jour au plus ;
- `POST /v1/profile/subscription/cancel` n'enregistre que la **raison** d'un
  abonnement StoreKit ; l'app ouvre ensuite la feuille de gestion des
  abonnements d'iOS, et c'est `AUTO_RENEW_DISABLED` qui ferme la ligne.

### Trois pièges

> 🚨 **App Review achète en sandbox, contre le serveur de production.** Le
> serveur garde un vérificateur par environnement ; un serveur qui ne
> connaîtrait que la production refuserait l'achat du testeur, et Apple
> rejetterait l'app pour « achat qui ne marche pas ».

> 🚨 **Une transaction Xcode n'est signée par personne.** La bibliothèque d'Apple
> saute la vérification pour `Xcode` et `LocalTesting`. Ces environnements ne
> passent qu'avec `APP_STORE_ALLOW_XCODE=true`, et le serveur **refuse de
> démarrer** avec cette valeur en production.

> ⚠️ **Sans contrat *Paid Apps* actif, aucun produit ne revient.**
> `Product.products(for:)` rend une liste vide, même en sandbox, et le paywall
> dit « L'abonnement n'est pas disponible pour le moment ». Ce n'est pas le code.

### Configuration

| Variable | Où | Note |
|---|---|---|
| `APPLE_BUNDLE_ID` | Railway, `.env` | Déjà posée pour « Continuer avec Apple » : la même |
| `APP_STORE_APP_APPLE_ID` | Railway | *App Store Connect ▸ App Information ▸ Apple ID*. Vide : seuls les achats sandbox passent |
| `APP_STORE_ALLOW_XCODE` | `.env` local seulement | Jamais en production |

Aucun secret : vérifier une signature ne demande que le certificat racine
d'Apple, rangé dans `backend/certs/apple/` et copié dans l'image Docker.

Vérifier que le déployé reçoit, sans rien écrire :

```bash
curl -s -X POST https://api-production-9f35a.up.railway.app/v1/webhooks/app-store \
  -H 'content-type: application/json' -d '{"signedPayload":"x.e30.y"}'
```

`invalid_signature` : la route est là et refuse ce qu'Apple n'a pas signé.

### Ce qui se fait dans App Store Connect

Dans cet ordre — les deux premiers prennent des jours :

1. **Business ▸ Agreements** : contrat *Paid Apps*, compte bancaire, formulaires
   fiscaux. Attendre le statut *Active*.
2. **Small Business Program** (developer.apple.com) : 15 % de commission au lieu
   de 30 %.
3. **Monetization ▸ Subscriptions** : groupe « MemoBook », abonnement
   `com.memobook.app.subscription.weekly`, 1 semaine, France 1,99 €,
   localisation française, capture du paywall pour la revue, partage familial
   désactivé.
4. **App Information ▸ App Store Server Notifications** : la même URL en
   production et en sandbox, **version 2** —
   `https://api-production-9f35a.up.railway.app/v1/webhooks/app-store`. Puis
   *Request a Test Notification* : le log `Notification App Store de test
   reçue.` le confirme.
5. **Users and Access ▸ Sandbox** : un compte de test à une adresse jamais
   utilisée chez Apple.
6. **À la soumission** : l'abonnement se joint à une **nouvelle version** de
   l'app (section *In-App Purchases and Subscriptions*), et la description de
   l'App Store porte un lien vers les conditions d'utilisation.

Côté Xcode, **rien à cocher** : l'achat intégré n'a pas d'entitlement.

### Vérifier, dans l'ordre

1. **Simulateur, ⌘R** : le schéma charge `ios/Config/MemoBook.storekit` — on
   achète sans App Store Connect. Le serveur de production refuse ces achats
   (non signés) : l'app l'affiche. Pour aller jusqu'au serveur, back-end local
   avec `APP_STORE_ALLOW_XCODE=true`. *Debug ▸ StoreKit ▸ Manage Transactions*
   rembourse ou expire à la main.
2. **iPhone, compte sandbox** (*Réglages ▸ Développeur ▸ Compte sandbox*), schéma
   sans fichier StoreKit : **une semaine dure 3 minutes**, on voit arriver les
   renouvellements, la coupure et l'expiration dans les logs de Railway.
3. **TestFlight** : le même sandbox, sur le binaire de production.

## Ce qui n'existe pas encore

- **L'extension des limites de souvenirs** — `POST /v1/trips/:id/memory-plan`
  pose le palier et laisse dérouler le parcours de bout en bout, mais
  n'encaisse rien. C'est le reçu StoreKit qui l'appellera.
- **L'imprimeur** — une commande payée reste en `submitted` jusqu'à ce qu'un
  humain la traite. `in_production` et `shipped` attendent un fournisseur.
- **La contribution d'un proche** — la page web derrière `shareSlug`.
- **La Tax Calculation** — voir ci-dessus.
