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
> activée et on encaisse du HT. Au 15 septembre 2026 : `tax/settings` est en
> `pending` (pas d'adresse de siège) et `tax/registrations` est **vide**.

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

Au 15 septembre 2026, la configuration « Default » du bac à sable a déjà
`apple_pay`, `card`, `link`, `klarna` et une douzaine d'autres.

## Le prix

Une seule formule, dans `src/lib/pricing.ts`, pour deux lecteurs : l'estimation
affichée sur la carte de cagnotte et le montant réellement débité. Un test
vérifie qu'ils sont égaux au centime.

> ⚠️ **Le prix est à trancher avec l'imprimeur.** 1,798 € la page, frais fixes
> et port compris — ce qui est faux dès qu'on s'éloigne de cinquante pages. Et
> `billablePageCount()` retombe sur `targetPageCount` parce que
> `Memo.pageCount` n'est jamais écrit par le back-end. Les deux sont signalés
> dans le code.

## Ce qui n'existe pas encore

- **L'abonnement StoreKit** — colonnes (`Subscription`), paywall et
  `FreemiumStatus` sont prêts ; la plomberie ne l'est pas.
- **L'imprimeur** — une commande payée reste en `submitted` jusqu'à ce qu'un
  humain la traite. `in_production` et `shipped` attendent un fournisseur.
- **La contribution d'un proche** — la page web derrière `shareSlug`.
- **La Tax Calculation** — voir ci-dessus.
