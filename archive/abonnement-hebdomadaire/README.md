# Archive — l'abonnement hebdomadaire, les étapes offertes et les limites de souvenirs

Retirés de l'app le **3 octobre 2026** (Hugo), remplacés par le **crédit du jour** :
5 minutes de récit par jour et par voyage, gratuites, et un abonnement à 4,99 €/mois
qui rend le récit illimité. Voir `docs/paiements.md` pour le modèle en vigueur.

> **Pourquoi c'est parti.** Les commissions d'Apple et de Stripe et la TVA sur
> chaque semaine d'abonnement empêchaient de déduire les abonnements du prix du
> carnet sans perte : un long voyage aurait cumulé des mois d'abonnement, donc de
> commissions, et se serait offert un carnet presque gratuit. L'abonnement ne sert
> plus qu'à lever la limite quotidienne.

**Rien ici n'est compilé.** Ce dossier est hors de `ios/Modules` et de `backend/` :
ni Xcode, ni `tsc`, ni la CI ne le voient. Ce sont des copies **telles qu'elles
étaient sur `main` au commit `0b34857`**, pour les relire sur GitHub sans changer de
branche.

## Retrouver l'app entière d'avant

La branche **`icebox/abonnement-hebdomadaire`** est `main` à `0b34857`, l'app
complète, qui compile et tourne. C'est le chemin le plus sûr pour ramener une
fonctionnalité : on y voit chaque fichier dans son contexte, avec ce qui
l'appelait.

```bash
git checkout icebox/abonnement-hebdomadaire -- <chemin du fichier>
```

## Ce qui est parti, et où c'était

| Fonctionnalité | Ce qu'elle faisait | Fichiers (copies ici) |
|---|---|---|
| **Les 3 étapes offertes** | Trois souvenirs gratuits, puis l'abonnement obligatoire pour continuer à raconter. Pastille « N étapes restantes » sur l'avatar de l'accueil et dans le profil, CTA lime verrouillé, micro du chat verrouillé, 403 `quota_exhausted` côté serveur | `ios/…/MemoBookCore/FreemiumStatus.swift`, `ios/…/MemoBookFeature/SubscriptionSession.swift`, `ios/…/MemoBookFeature/SandboxPersona.swift`, `backend/src/services/quota.ts`, `backend/test/quota.test.ts` |
| **L'abonnement hebdomadaire** | 1,99 €/semaine, produit App Store `com.memobook.app.subscription.weekly` (toujours **accepté** par le serveur et l'app pour un abonné en cours, plus vendu) | `ios/Config/MemoBook.storekit`, `backend/src/services/subscriptionCatalog.ts` |
| **« Tes abonnements sont déduits ! »** | 4ᵉ carte de l'offre du paywall (déjà en pause depuis le 02/10), et la feuille « Estimation » ouverte par sa pastille (cumul des semaines déduit du prix du carnet) | `ios/…/Paywall/PaywallView.swift` (`PaywallCopy.deductedSubscriptions`, `PaywallCopy.Estimation`), `ios/…/Paywall/PaywallSheets.swift` (`PaywallEstimationSheet`, `PaywallEstimation`) |
| **Le paywall « 3 premières étapes »** | Écran 1 « Bravo ! Tu as enregistré tes 3 premières étapes », écran 2 « Ton carnet comptera environ 40 pages » | `ios/…/Paywall/PaywallView.swift`, `ios/…/Paywall/PaywallPages.swift` |
| **La feuille « Comment ça fonctionne ? »** | L'étape `.pitch` de la feuille d'abonnement, ouverte par « Découvrir l'abonnement » avant le paywall : frise en 3 temps, « Comment résilier ? », « En savoir plus » | `ios/…/Profile/SubscriptionSheet.swift` |
| **Les limites de souvenirs** | Budget hebdomadaire en « souvenirs » (texte = 1, minute de vocal = 10), 2 000 compris, 8 000 étendus pour 3,99 €/semaine ; ligne et feuille dans les réglages du voyage ; 403 `memory_limit_reached` ; route `POST /v1/trips/:id/memory-plan` | `ios/…/MemoBookCore/MemoryAllowance.swift`, `ios/…/MemoBookCore/MemoryCopy.swift`, `ios/…/TripSettings/MemoryAllowanceSheet.swift`, `backend/src/services/memoryAllowance.ts`, tests |
| **L'arrêt automatique en fin de voyage** | La tâche quotidienne `memobook.end-subscriptions`, qui éteignait les abonnements non StoreKit (seul le jeu d'essai en créait) | `backend/src/jobs/endSubscriptions.ts`, `backend/src/services/subscriptions.ts` |
| **La notification « fin des 3 étapes offertes »** | `trial_end`, le lendemain de la dernière étape offerte validée, lien `memobook://paywall` ; et les phrases de déduction de `trip_end` | `backend/src/services/notificationCopy.ts`, `backend/src/services/notificationPlanner.ts` |
| **La documentation d'avant** | Le modèle hebdomadaire, les étapes offertes, les limites de souvenirs, les décisions de Clara sur `trial_end` | `docs/paiements.md`, `docs/conversation.md`, `docs/notifications.md`, `docs/reglages-utilisateur.md` |

## Ce que la base a perdu

En deux temps, pour que l'ancien code tourne encore pendant la bascule :

- **`20261003090000_credit_du_jour`** (ce lot) a retiré la valeur `trial_end` de
  `NotificationKind`, avec les lignes de `notification_deliveries` qui la
  portaient (le journal de ses envois) ;
- **`20261004090000_retire_les_colonnes_de_l_ancien_modele`** (la PR d'après)
  supprime les colonnes
  `accounts.offeredSteps`, `accounts.remainingSteps`, `accounts.memoryPlan`,
  `accounts.memoryUsed`, `accounts.memoryPeriodStart` et l'énumération
  `MemoryPlan`. Le schéma Prisma ne les connaît déjà plus.

Ramener une de ces fonctionnalités, c'est donc aussi une migration qui recrée la
colonne — le schéma d'avant est dans `backend/prisma/schema.prisma` de la branche
`icebox/abonnement-hebdomadaire`.
