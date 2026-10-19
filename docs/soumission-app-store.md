# Soumettre l'app à App Review

Préparé le 19/10/2026 pour la version **0.1.0 (build 9)**, après le lot 13.
Le dernier envoi était le build 8, du 14/09/2026, rejeté le 15/09 en
**5.1.2(i)** (voir plus bas).

## Ce qui est prêt dans le binaire

| Point | État |
|---|---|
| Compile en **Release** pour iPhone | ✅ vérifié le 19/10 (la CI ne compile qu'en Debug) |
| Adresse de l'API embarquée | ✅ `https://api-production-9f35a.up.railway.app` |
| Numéro de build | ✅ `CFBundleVersion` 9, dans `ios/project.yml` |
| Manifeste de confidentialité | ✅ `ios/App/PrivacyInfo.xcprivacy` (nouveau) : aucun suivi, données liées au compte pour le fonctionnement de l'app, UserDefaults (CA92.1) |
| Chiffrement | ✅ `ITSAppUsesNonExemptEncryption: false` |
| Textes des autorisations | ✅ micro, photothèque, appareil photo, dictée |
| Sign in with Apple | ✅ à côté de Google |
| Suppression du compte dans l'app | ✅ Profil ▸ Supprimer mon compte |
| Paywall : prix, conditions, confidentialité, restaurer | ✅ |
| Comptes de test en production | ✅ connexion vérifiée le 19/10 |

## À faire avant l'archive

1. **Attendre le déploiement du lot 13** sur Railway (services `api` et
   `worker`). Railway attend la fin de la CI iOS de `main`. Vérifier :
   ```bash
   curl -s https://api-production-9f35a.up.railway.app/.well-known/apple-app-site-association
   ```
   Le fichier doit répondre en JSON avec `HP2A94889S.com.memobook.app`.
2. **Portail Apple Developer ▸ Identifiers ▸ `com.memobook.app`** : cocher
   **Associated Domains** (le lien d'invitation `/j/<code>`). La signature
   automatique le fait seule si le compte en a le droit ; sinon l'archive
   échoue sur l'entitlement.
3. **Xcode** : `make project`, puis schéma *MemoBook*, destination
   *Any iOS Device*, **Product ▸ Archive**, puis *Distribute App ▸ App Store
   Connect ▸ Upload*.

## À faire dans App Store Connect

1. **Étiquettes de confidentialité (App Privacy)** : décocher **« Used for
   Tracking »** partout, sur Nom et Adresse e-mail notamment. C'était la cause
   du rejet 5.1.2(i) du 15/09 : l'app ne suit personne, sans SDK publicitaire
   ni d'analytique. Les données déclarées doivent correspondre au manifeste :
   nom, e-mail, téléphone, adresse postale, audio, photos, autre contenu,
   historique d'achat, identifiant, autres données (date de naissance, genre).
   Toutes sont liées au compte et servent au fonctionnement de l'app.
2. **Accords ▸ Paid Apps** : statut *Active* (sans lui, le paywall ne trouve
   aucun produit).
3. **Abonnement** `com.memobook.app.subscription.monthly` : prêt à soumettre,
   avec sa capture du paywall, et **joint à la version** dans *In-App Purchases
   and Subscriptions*.
4. **Description** : un lien vers les conditions d'utilisation (EULA).
5. **App Review Information** : le compte et les notes ci-dessous.

## Notes pour l'équipe App Review

À coller dans *App Review Information ▸ Notes*, en anglais : c'est la langue
que lit l'équipe.

> **Sign-in**: use the email option with the demo account below. It already has
> ten trips with recorded memories, photos and a composed book, so every screen
> has content.
>
> **What the app does**: MemoBook turns a trip into a printed travel journal.
> The traveller records voice notes or writes during the trip; an assistant
> (MEMO, in the trip chat) turns each memory into a written page and asks for
> photos; the app composes a PDF book that can be previewed and ordered as a
> printed book.
>
> **The app is in French only.**
>
> **Subscription**: free accounts get 5 minutes of storytelling per day per
> trip. The monthly subscription (4,99 €/month) removes this limit. To see the
> offer: Profile ▸ "Découvrir l'abonnement", or Trip ▸ settings (gear) ▸
> "Crédit du jour" ▸ "Passer en illimité". Purchases work with a Sandbox
> account. Cancelling is done from Profile ▸ "Mon abonnement" ▸ "Résilier",
> which opens Apple's subscription management.
>
> **Printed book orders** are a physical good paid by card (Stripe), not a
> digital purchase.
>
> **Account deletion**: Profile ▸ "Supprimer mon compte".
>
> **Tracking**: the app does not track users and contains no advertising or
> analytics SDK.

Le compte, dans *Sign-In Information* : **`demo@memo-book.com`**, avec le
mot de passe des comptes de test (`TEST_PASSWORD`, `backend/prisma/seed.ts`).
C'est le compte gratuit : l'équipe y voit le crédit du jour et le paywall, et
peut acheter en sandbox. Le compte abonné, `demo@memobook.app`, ne montre pas
l'offre.

## Après l'envoi

- Le build passe en *Processing* puis arrive dans TestFlight : l'installer sur
  un iPhone avant de soumettre, et refaire le parcours des notes.
- Un rejet sur l'achat : vérifier que `APP_STORE_APP_APPLE_ID` est posée sur
  `api` et que le serveur accepte le sandbox (`docs/paiements.md` § Trois pièges).
- Prochain envoi : **build 10**. App Store Connect refuse deux fois le même
  numéro.
