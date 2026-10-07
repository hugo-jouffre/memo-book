# Paiements — Stripe, StoreKit, et ce qui va où

Ce que le dépôt encaisse, par quel rail, et comment le vérifier.

## La règle qui décide de tout

> 🚨 **Ce n'est pas un choix technique, c'est une contrainte de validation App Store.**
>
> | Ce qu'on vend | Rail | Pourquoi |
> |---|---|---|
> | Abonnement mensuel (récit illimité) | **StoreKit 2** | Service numérique → Apple impose l'achat intégré |
> | Carnet imprimé | **Stripe** | Bien physique → l'achat intégré est **interdit** |

**La cagnotte est retirée** (Hugo, 06/10/2026 — « on supprime la cagnotte ») :
plus de recharge, plus de déduction, plus de page de contribution. Une commande
se paie **entièrement par Stripe**. Ce qui en reste en base — `wallet_entries`,
`accounts.walletBalanceCents`, `print_orders.walletAppliedCents` — n'est plus
écrit que pour les commandes et les recharges d'avant (voir « L'héritage de la
cagnotte » plus bas), et part dans l'export des données des comptes qui l'ont
utilisée. Les colonnes seront retirées par une seconde migration, une fois
celle-ci déployée.

`PAYMENT_KIND` (`src/services/billing.ts`) ne porte que des valeurs physiques :
aucun crédit acheté par Stripe ne doit jamais déverrouiller une fonction
numérique, ce qui contournerait l'achat intégré.

## Le chemin d'encaissement

```
POST /memos/:id/orders
  └─ PaymentIntent (le total) → feuille → webhook ────────────→ submitted
       │
       ├─ « Payer » à nouveau → POST /orders/:id/payment (même intention)
       └─ abandonnée, annulée, 24 h sans paiement
            → intention annulée → cancelled (« paiement abandonné »)
                 └─ « Finaliser ma commande » → POST /orders/:id/payment
                      → rouverte en draft, intention neuve, même prix
```

**Une commande abandonnée se finalise** (T232, Hugo 06/10/2026). Le suivi des
commandes du profil (`GET /v1/profile` → `orders[]`) montre, à côté des
commandes en route (`status: "in_progress"`), **la dernière commande jamais
payée de chaque voyage** de moins de 30 jours (`status: "payment_abandoned"`) :
étiquette « Paiement abandonné, commande non finalisée », CTA « Finaliser ma
commande ». Ce CTA appelle la reprise, qui rouvre la commande fermée (de
nouveau `draft`, nouvelle intention, prix figé à la commande) au lieu de
répondre `409 order_expired` comme avant. Une commande payée puis remboursée
ne se rouvre pas (`409 order_refunded`). Le webhook ignore les événements de
l'ancienne intention, remplacée ; le ménage des 24 h compte depuis la
dernière écriture (`updatedAt`), pour ne pas refermer aussitôt une commande
ancienne qu'on vient de rouvrir.

Ce qui ferme une commande non payée (`services/orderPayments.ts`) :

| Ce qui ferme la commande | Qui |
|---|---|
| On change d'adresse, d'exemplaires ou de rapidité après une tentative | l'app, `POST /v1/orders/:id/cancel` |
| L'intention ne peut pas s'ouvrir chez Stripe | la route de commande, aussitôt |
| L'intention est annulée (tableau de bord, ménage) | le webhook `payment_intent.canceled` |
| Personne ne revient payer | la tâche horaire, au-delà de 24 h |
| Remboursement **total** avant l'impression | le webhook `charge.refunded` |

> ⚠️ **L'intention s'annule toujours avant que la commande se ferme.** Stripe
> refuse d'annuler une intention payée : c'est lui qui tranche la course entre
> le ménage et un paiement validé à la même seconde.

**Une commande naît toujours en `draft`** et n'en sort que sur confirmation du
webhook.

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
| Commander | `OrderModel.pay()` | `POST /orders` → `PlacedPrintOrder` — ou `POST /orders/:id/payment` si la commande existe déjà et que rien n'a changé |
| Régler | `PaymentPresenter.present` | la feuille, montée sur `clientSecret`, **avec les cartes du compte** |
| Conclure | `OrderModel.settled(_:)` | relit `GET /orders/:id` jusqu'à sortir de `draft` |

**Le moyen de paiement se choisit dans la feuille de Stripe** (01/10/2026).
L'app avait son propre formulaire de carte — numéro, échéance, cryptogramme —
qui ne gardait que quatre chiffres en mémoire et ne parlait à personne ; une
carte ajoutée là faisait répondre 404 à la commande (T225). Il n'existe plus :

- chaque billet de paiement porte le **client Stripe du compte et une clé
  éphémère** — la feuille montre les cartes enregistrées, propose
  « Enregistrer pour la prochaine fois », et en retire une ;
- « Cartes bancaires » dans le profil ouvre `CustomerSheet`, la feuille
  « Moyens de paiement » de Stripe (`POST /v1/payments/ephemeral-key` et
  `/setup-intent`).

> ⚠️ **Une clé éphémère, pas une session client.** Dans stripe-ios 24, les
> sessions client sont réservées à un accès bêta
> (`@_spi(CustomerSessionBetaAccess)`). La clé éphémère est le chemin stable, à
> une condition : être créée dans **la version d'API du SDK**, que l'app envoie
> (`stripeApiVersion`, `StripeSDK.apiVersion`, « 2020-08-27 »). Le jour où le
> SDK passe en 25, il faudra repasser aux sessions client.

> ⚠️ **Le retour d'un paiement qui sort de l'app** (3-D Secure, Klarna) revient
> par `memobook://stripe-redirect`, et `RootView.onOpenURL` le rend à Stripe
> (`StripeSDK.handle`). Sans ça, la feuille attendait indéfiniment.

`OrderPayment.settlement` tranche en un seul endroit ce que l'app doit faire :
`.card` (feuille) ou `.unavailable` (`.wallet`, rien à encaisser, ne peut plus
arriver : `paidFromWallet` est toujours faux depuis le 06/10/2026). Le second
n'est pas un cas d'usage mais **une panne de configuration** — l'API déployée
n'a pas ses clés Stripe — et il affiche un message au lieu d'une confirmation :
une commande non payée ne doit jamais ressembler à une commande passée.

> ⚠️ **Une feuille qui rend `.succeeded` ne veut pas dire « commande validée ».**
> Elle dit que Stripe a accepté, pas que notre serveur l'a appris. D'où la
> relecture de la commande, jusqu'à ce que le webhook l'ait passée.

> ⚠️ Annuler la feuille **n'est pas une erreur** : la commande reste en
> brouillon et « Payer » la reprend **sur la même intention**
> (`POST /v1/orders/:id/payment`) — pas de seconde commande. Jusqu'au
> 01/10/2026, chaque « Payer » en créait une neuve.

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
| `wallet_entries.idempotencyKey` unique | schéma | Rendre deux fois une réservation ; créditer deux fois une recharge vue par deux événements (`topup:<intention>`) |
| Montant reçu = montant de la commande | `stripeWebhook.ts` | Envoyer à l'impression un carnet payé à moitié |

Une erreur de traitement est **journalisée puis acquittée** (200) : un 500 ferait
rejouer, et un bug déterministe reviendrait toutes les heures pendant trois jours.
**Sauf une panne passagère** — base saturée, Stripe injoignable — qui répond
500 : l'acquitter perdait l'événement, et une commande payée restait en `draft`.

### Les remboursements

`charge.refunded` porte le **cumul** remboursé, inscrit dans
`print_orders.refundedCents` :

- **partiel** : inscrit, rien d'autre — un geste sur les frais de port n'annule
  pas un carnet ;
- **total, avant l'impression** : la commande est annulée (et une ancienne
  part de cagnotte revient) ;
- **total, une fois imprimée ou expédiée** : le statut ne bouge pas, et le log
  demande au support de trancher pour une ancienne part de cagnotte.

Un litige (`charge.dispute.created`) est journalisé en erreur et posé sur la
commande.

### L'héritage de la cagnotte

Retirée le 06/10/2026, elle laisse trois chemins **qui ne servent qu'aux
données d'avant** :

- une commande d'avant qui portait une part de cagnotte la **rend toujours, une
  seule fois**, quand elle se ferme sans être payée ou est remboursée en entier
  (`returnWalletShare`, clé `order-wallet-return:<commande>`) ;
- une recharge ouverte avant et payée après est **inscrite au registre**, et le
  journal la signale en erreur : elle est à rembourser à la main ;
- une recharge remboursée est reprise sur le registre, plafonnée au solde.

Les soldes restants (`accounts.walletBalanceCents <> 0`) ne s'affichent plus
nulle part : ils sont à rembourser par le support, puis à solder par une
écriture `adjustment`.

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

Et, sans serveur ni base, **ce que le simulé ne peut pas prouver** — que Stripe
accepte nos appels : client, clé éphémère dans la version du SDK iOS,
intention d'enregistrement, intention avec reçu et adresse, annulation, refus
d'annuler une intention payée.

```bash
cd backend && npm run stripe:gateway-check
```

Le dernier déroule tout le parcours avec le **vrai** Stripe en mode test :
compte, carnet, commande, paiement carte 4242, attente du webhook, contrôle
d'idempotence. C'est le seul chemin qui exerce la vraie
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
| Événements | `payment_intent.succeeded`, `payment_intent.payment_failed`, `payment_intent.canceled`, `charge.refunded`, `charge.dispute.created` |

> 🚨 **`payment_intent.canceled` et `charge.dispute.created` sont à ajouter au
> point de terminaison** (01/10/2026). Sans le premier, une intention annulée
> dans le tableau de bord ne rend pas sa réservation avant le ménage horaire :
>
> ```bash
> stripe webhook_endpoints update we_1UG765BknFHnQoHL2aidvVgI \
>   -d "enabled_events[]=payment_intent.succeeded" \
>   -d "enabled_events[]=payment_intent.payment_failed" \
>   -d "enabled_events[]=payment_intent.canceled" \
>   -d "enabled_events[]=charge.refunded" \
>   -d "enabled_events[]=charge.dispute.created"
> ```

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

**En production, l'API refuse de démarrer sans ses trois clés, et le worker sans
la clé secrète** (01/10/2026) : sans elles, le serveur passait sur l'encaissement
simulé, qui aurait accepté un webhook non signé. Le simulé, lui, ne croit plus
aucun webhook hors de la suite de tests.

Le serveur **refuse de démarrer** si les deux clés ne sont pas du même mode
(`sk_live_` avec `pk_test_`, ou l'inverse) : le mélange fait échouer le paiement
*après* que l'utilisateur a validé Face ID.

### Ce qui reste à faire à la main

| Sujet | Où | Effet tant que ce n'est pas fait |
|---|---|---|
| **Adresse du siège** | Tableau de bord → Tax → Settings | `status: pending` — **aucune taxe n'est calculée** |
| **Immatriculation TVA** | Tax → Registrations | Stripe ne collecte rien, **et ne lève aucune erreur** |
| **Certificat Apple Pay, puis `APPLE_PAY_MERCHANT_ID`** | Stripe + portail Apple + Railway (voir *Apple Pay*) | La feuille montre les cartes seules |
| **Événements du webhook** | Développeurs ▸ Webhooks (commande ci-dessus) | Une intention annulée à la main ne rend sa réservation qu'au ménage horaire |
| **Reçus par e-mail** | Paramètres ▸ E-mails clients ▸ Paiements réussis | Les intentions portent `receipt_email`, mais Stripe n'envoie rien tant que la case n'est pas cochée — et jamais en mode test |
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

### Apple Pay

**C'est le serveur qui l'allume** (05/10/2026) : chaque paiement de commande
rend `applePayMerchantId`, lu dans la variable
`APPLE_PAY_MERCHANT_ID` du service `api`. L'app ne propose Apple Pay que si
elle le reçoit ; vide, la feuille montre les cartes seules. Allumer ou couper
Apple Pay est donc une variable Railway, pas une livraison.

L'identifiant marchand existe depuis le 02/10/2026 (`merchant.com.tonapp.memobook`),
et l'app le porte : capability Apple Pay déclarée dans `ios/project.yml`. Dans
cet ordre, **pour chaque compte Stripe** (le sandbox et la production ont
chacun le leur) :

1. Tableau de bord Stripe ▸ *Paramètres ▸ Moyens de paiement ▸ Apple Pay* ▸
   *Ajouter une nouvelle application* : télécharger la demande de certificat
   (CSR).
2. Portail Apple ▸ *Identifiers ▸ Merchant IDs* ▸ `merchant.com.tonapp.memobook`
   ▸ *Apple Pay Payment Processing Certificate* ▸ *Create* : déposer la CSR,
   télécharger le `.cer`, le rendre à Stripe.
3. Railway ▸ `api` ▸ `APPLE_PAY_MERCHANT_ID=merchant.com.tonapp.memobook`.

Dans l'autre ordre, le bouton paraît et le paiement échoue après Face ID.

## Le prix

Une seule formule, dans `src/services/printPricing.ts`, pour deux lecteurs :
l'estimation de la notification de fin de voyage et le montant réellement
débité.

> ⚠️ **Le prix est à trancher avec l'imprimeur.** 1,798 € la page, frais fixes
> et port compris — ce qui est faux dès qu'on s'éloigne de cinquante pages. Et
> `billablePageCount()` retombe sur `targetPageCount` parce que
> `Memo.pageCount` n'est jamais écrit par le back-end. Les deux sont signalés
> dans le code.

## L'abonnement, et le crédit du jour

**Depuis le 03/10/2026 (Hugo), une seule chose se vend en numérique : le récit
illimité.** Tout le monde raconte gratuitement, dans la limite du **crédit du
jour** de chaque voyage ; l'abonnement mensuel lève cette limite pour celui qui
s'abonne. Plus d'étapes offertes, plus de limites de souvenirs ni d'extension,
plus d'abonnement à la semaine, plus de déduction des abonnements du prix du
carnet. L'ancien modèle est archivé sur la branche `icebox/abonnement-hebdomadaire`
(= `main` à `0b34857`) et dans `archive/`.

Le tarif est **écrit une fois** dans `src/services/subscriptionCatalog.ts` :

| | Prix | Produit App Store | Clé Stripe |
|---|---|---|---|
| Abonnement | **4,99 €/mois** (`SUBSCRIPTION_MONTHLY_CENTS = 499`) | `com.memobook.app.subscription.monthly` | `memobook_subscription_monthly` |

**Le tarif est servi même à qui n'a rien souscrit** (16/09/2026) : un prix ne
dépend pas de ce que la personne a déjà acheté, c'est un tarif, il vit dans un
catalogue. `GET /v1/profile` rend `subscription.price` (euros) et
`subscription.interval` (`"month"`, `"week"` pour un ancien abonné
hebdomadaire), et garde `weeklyPrice` **rempli avec le même prix** : les apps
installées le décodent en obligatoire. Côté app, le paywall affiche le prix et
la période de StoreKit (`displayPrice`, `subscriptionPeriod`), avec `4,99 €` /
`mois` en repli.

⚠️ **L'abonnement s'encaisse par StoreKit, et par lui seul.** Apple impose
l'achat intégré pour un service numérique : `PAYMENT_KIND` ne porte aucune
valeur d'abonnement (voir `billing.ts`), et c'est la section
[L'abonnement App Store](#labonnement-app-store-storekit) qui dit comment il
s'achète. La clé Stripe n'existe que pour que le back-end sache de quel prix il
parle, et pour le jour où l'offre se vendrait hors de l'app : **aucun
encaissement Stripe de l'abonnement**.

État du sandbox Stripe (`acct_1UFioWBknFHnQoHL`, *MemoBook Test*), produit
« Abonnement MemoBook » (`prod_VGyIuAiG0DcXLa`) :

| Prix | | `lookup_key` | |
|---|---|---|---|
| `price_1UMIML…` | 4,99 €/**mois** | `memobook_subscription_monthly` | actif (créé le 03/10/2026) |
| `price_1UGQMe…` | 1,99 €/semaine | `memobook_subscription_weekly` | à désactiver à la main |
| `price_1UGRnH…` | 3,99 €/semaine | `memobook_memory_upgrade_weekly` | à désactiver à la main (extension abandonnée) |
| `price_1UGRhK…` | 3,99 €/mois | `memobook_memory_upgrade_monthly` | désactivé |

⚠️ **L'intervalle d'un prix Stripe ne se modifie pas, et un prix ne se supprime
jamais : il se désactive.** Le sandbox refuse les `update` à l'outil (voir la
mémoire « Stripe : sandbox MemoBook Test ») : les désactivations se font dans
le tableau de bord, ou par Hugo en ligne de commande :

```bash
stripe prices update price_1UGQMeBknFHnQoHLYno3hvG4 --active=false
stripe prices update price_1UGRnHBknFHnQoHLM4oVaJkV --active=false
stripe products update prod_VGyIuAiG0DcXLa -d "description=Vocaux et textes illimités, 4,99 € par mois."
```

Une **`lookup_key` et non un identifiant de prix** : celui-ci change entre le
sandbox et la production, celle-là non. C'est ce qui permet de poser la même
valeur dans les deux comptes sans variable d'environnement de plus.

### Le crédit du jour (sans abonnement)

Chaque voyage peut raconter **5 minutes par jour**, partagées entre ses
co-voyageurs **non abonnés**. Un seul crédit pour l'oral et l'écrit : un vocal
consomme sa **durée mesurée par le serveur**, un texte **75 ms par caractère**
(800 caractères = 1 min). Les photos ne consomment rien. Les constantes vivent
dans `src/services/dailyCredit.ts` et **voyagent avec le solde** jusqu'à l'app
(objet `dailyCredit`) : il n'y a qu'une vérité.

| Constante | Valeur | Ce qu'elle fait |
|---|---|---|
| `DAILY_CREDIT_LIMIT_MS` | 300 000 | 5 minutes par voyage et par jour |
| `TEXT_MS_PER_CHARACTER` | 75 | Le coût d'un caractère écrit |
| `WARNING_REMAINING_MS` | 30 000 | L'app prévient au-dessus de la barre d'enregistrement (4:30) |
| `URGENT_REMAINING_MS` | 5 000 | L'avertissement pulse (4:55) |
| `VOICE_TOLERANCE_MS` | 3 000 | Un dernier vocal peut dépasser le reste de 3 s au plus |

**Les garde-fous**, côté serveur — l'app prévient, elle ne décide jamais :

- **Le jour** est celui de celui qui raconte (`accounts.timeZone`, mis à jour
  par l'en-tête `X-Time-Zone` que l'app envoie sur chaque appel), et **ne
  recule jamais** : changer de fuseau ne rouvre pas une journée.
- **Le décompte est atomique**, dans la transaction qui écrit la bulle du
  voyageur, sous le verrou du voyage (`memos … FOR UPDATE`) : deux envois
  simultanés ne passent pas tous les deux. Un échec plus loin annule le
  décompte.
- **La durée d'un vocal est mesurée** dans le conteneur MPEG-4
  (`src/lib/mp4Duration.ts`) : le `durationSeconds` déclaré par le client n'est
  plus cru. **Et les en-têtes ne sont pas crus seuls** : un client peut les
  réécrire en quatre octets, alors que le transcripteur décode tous les paquets.
  Le fichier doit avoir une seule piste, audio, en AAC-LC, non fragmentée ; le
  nombre de paquets de `stts` doit égaler celui de `stsz` ; l'échelle de `mdhd`
  doit égaler la fréquence de l'`AudioSpecificConfig` ; la durée retenue est la
  plus longue de Σ`stts` et de `paquets × 1024 ÷ fréquence`, et un débit de plus
  de 40 Ko/s est refusé. Tout écart : `400 unreadable_audio`.
- **Un filet après la transcription** : si le texte rendu pèse plus du double de
  la durée mesurée (75 ms par caractère) et l'écart plus de 15 s, l'écart est
  décompté du crédit du voyage — sans refuser le tour — et journalisé.
- **Au-delà du reste**, `429 daily_credit_exhausted`, avec le crédit dans le
  corps ; le message dit « épuisé » seulement si le pot est vide, sinon « ce
  tour dépasse le crédit qui reste aujourd'hui ». L'app garde le vocal dans sa
  file hors ligne et le renvoie après `resetsAt` ; un texte trop long est
  empêché avant l'envoi.
- **Plus long qu'une journée** (vocal de plus de 5 min 03, texte de plus de
  4 000 caractères) : `429 daily_credit_too_long`. Il ne passera jamais sans
  abonnement : l'app le garde en « attend l'illimité » et le libère à
  l'abonnement.
- **Gratuit** : une puce envoyée telle quelle, une commande silencieuse, les
  photos. Le contexte du voyage et les précisions comptent comme le reste.
- **La bulle « reviens demain »** : quand le crédit tombe à zéro, MEMO pose une
  fois par voyage et par jour une bulle écrite par le code, avec l'appel à
  l'action « Raconter sans limite » vers le paywall. Un abonné ne la voit pas.
- **Le plafond anti-abus** `CHAT_DAILY_TURN_CAP` (tours par carnet et par jour)
  reste, pour tout le monde, abonnés compris.

Le crédit est servi avec le fil (`GET /v1/trips/:id/chat`), chaque reçu de tour,
les réglages du voyage (`GET|PATCH /v1/trips/:id/settings`) et chaque voyage en
cours de l'accueil (`GET /v1/home`). L'app le montre dans la barre
d'enregistrement (4:30 / 4:55 / 5:00) et dans la ligne « Crédit du jour » des
réglages du voyage, d'où « Passer en illimité » ouvre le paywall.

### L'illimité est personnel, et la période payée va à son terme

**L'abonnement n'ouvre l'illimité qu'à l'abonné** : ses tours ne consomment pas
le pot commun du voyage, et ses co-voyageurs non abonnés continuent de le
partager. Il n'ouvre rien d'autre — les statistiques du voyage sont à tout le
monde.

Un mois commencé est un mois réglé : résilier ne coupe pas l'illimité avant la
fin de la période payée. `subscriptions.renewsAt` en est la fin ; elle sort dans
`subscription.paidThrough`. **Une seule source dit l'accès** :
`hasUnlimitedAccess` (`src/services/subscriptions.ts`) — statut vivant
(`active`, `trialing`, `past_due`), ou `cancelled` / `expired` avec `renewsAt`
encore à venir. Côté app, `Subscription.grantsAccess()` lit la même règle.

## L'abonnement App Store (StoreKit)

4,99 €/mois, produit **`com.memobook.app.subscription.monthly`**, groupe
d'abonnements « MemoBook ». L'identifiant est écrit trois fois et doit rester
le même partout : `APP_STORE_PRODUCT_IDS` (`subscriptionCatalog.ts`),
`StoreKitCatalog` (`MemoBookPayments`) et `ios/Config/MemoBook.storekit`.
Apple ne le laisse ni modifier ni réutiliser.

**L'ancien produit hebdomadaire `com.memobook.app.subscription.weekly` reste
accepté** (Hugo, 03/10/2026) : un abonné éventuel est honoré jusqu'à
l'expiration de sa période, et ses renouvellements comme ses notifications
passent toujours. Il n'est plus vendu nulle part dans l'app ; à retirer de la
vente dans App Store Connect.

```
App ─ Product.purchase(appAccountToken: id du compte)
  └─ feuille d'Apple ─ Face ID ─→ transaction signée (JWS)
       └─ POST /v1/subscriptions/app-store ─→ vérifiée ─→ subscriptions + registre
            └─ 2xx ─→ transaction.finish()           (sinon : rejouée au lancement)

Apple ─ POST /v1/webhooks/app-store (notifications v2)
  └─ renouvellement, renouvellement coupé, délai de grâce, expiration, remboursement
```

**Deux portes, la même écriture** (`services/appStoreSubscriptions.ts`) : l'app
rend l'illimité dans la seconde qui suit l'achat, Apple dit tout le reste — y
compris ce qui se passe app fermée. Une ligne `subscriptions` par
`originalTransactionId` (rouverte quand on se réabonne au voyage suivant), une
ligne `subscription_transactions` par période payée (un mois ; une semaine pour
l'ancien produit).

| Chez Apple | `subscriptions.status` | Accès |
|---|---|---|
| actif, renouvellement armé | `active` | oui |
| actif, renouvellement coupé dans iOS | `cancelled` | jusqu'à `renewsAt` |
| délai de grâce | `past_due` | oui, Apple l'accorde |
| nouvelle tentative de prélèvement | `expired` | non |
| expiré | `expired` | non |
| remboursé, révoqué | `expired` | non, dès la révocation |

### Ce que l'app en dit : un état, en un mot (07/10/2026)

Hugo, 06/10/2026 : « quand quelqu'un se désabonne, tous les endroits qui
indiquaient « abonné » ne doivent plus l'indiquer ». Le statut en base ne
suffisait pas — chaque écran le relisait à sa façon, et une ligne restée
`active` après un `EXPIRED` perdu disait « abonné » pour toujours.
`subscriptionStateOf` / `accountSubscriptionOf` (`services/subscriptions.ts`)
en tirent **un** état, d'où tout le reste dérive :

| État | Ce que c'est | Illimité | « Abonné » (`isActive`) |
|---|---|---|---|
| `active` | renouvellement armé | oui | oui |
| `grace` | prélèvement en échec, délai de grâce d'Apple | oui | oui |
| `ending` | renouvellement coupé : la période payée court encore | jusqu'à `endsAt` | non |
| `ended` | expiré, remboursé, révoqué — ou sans nouvelles d'Apple 3 jours après l'échéance | non | non |
| `none` | jamais abonné | non | non |

Il sort dans `GET /v1/profile` → `subscription.state`, `autoRenews`,
`renewsAt` (prochain prélèvement, `active` seulement), `endsAt` ; et dans
`GET /v1/home` → `traveller.subscriptionState`, `subscriptionEndsAt` (pour
`ending`). `subscriptionOutlivesTrip`, `subscriptionEndedOn`,
`hasEndedBefore` et les notifications (`armedAppleRenewal`) le lisent aussi :
plus rien n'invite à couper un abonnement qui ne se renouvellera pas.

### Ce qui rend le rejeu inoffensif, ici aussi

| Garde-fou | Où | Ce qu'il empêche |
|---|---|---|
| `subscriptions.providerSubscriptionId` unique | schéma | Deux abonnements pour un paiement |
| `subscription_transactions.transactionId` unique | schéma | Inscrire deux fois une période |
| `providerUpdatedAt` | `appStoreSubscriptions.ts` | Un événement en retard qui rouvrirait un abonnement coupé |
| `finish()` après le 2xx seulement | `SubscriptionStore.swift` | Perdre un achat fait dans un tunnel |

### 🚨 Apple seul résilie

**Aucune app ne peut résilier à la place de son client.** C'est pourquoi la
promesse « arrêt automatique à la fin du voyage » est devenue un **rappel**
(Hugo, 01/10/2026) :

- la passe de fin de voyage (`sweepEndedSubscriptions`) **ignore** les lignes
  StoreKit — les fermer pendant qu'Apple prélève, c'était faire payer
  quelqu'un qui n'a plus l'illimité ;
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
   `com.memobook.app.subscription.monthly`, 1 mois, France 4,99 €,
   localisation française, capture du paywall pour la revue, partage familial
   désactivé. L'hebdomadaire `com.memobook.app.subscription.weekly` se retire
   de la vente (*Remove from Sale*) sans être supprimé : ses abonnés vont au
   bout de leur période.
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
   sans fichier StoreKit : **un mois dure 5 minutes**, on voit arriver les
   renouvellements, la coupure et l'expiration dans les logs de Railway.
3. **TestFlight** : le même sandbox, sur le binaire de production.

## Ce qui n'existe pas encore

- **L'imprimeur** — une commande payée reste en `submitted` jusqu'à ce qu'un
  humain la traite. `in_production` et `shipped` attendent un fournisseur.
- **La contribution d'un proche** — la page web derrière `shareSlug`.
- **La Tax Calculation** — voir ci-dessus.
