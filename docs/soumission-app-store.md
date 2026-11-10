# Soumettre l'app à App Review

Mis à jour le 05/11/2026 pour la version **0.2.0 (build 30)**.

La **0.1.0 est approuvée** : le rejet 5.1.2(i) du 15/09 a été levé en
décochant « Used for Tracking » (voir plus bas), et l'app est publiée. Le
dernier build reçu par Apple est le **25**, du 28/10. Les builds 28, 29 et un
premier 30 ont été archivés sans jamais être envoyés — l'Organizer les montre
à « – ».

## Ce qui est prêt dans le binaire

| Point | État |
|---|---|
| Adresse de l'API embarquée | ✅ `https://api-production-9f35a.up.railway.app` |
| Compile en **Release** pour iPhone | ✅ vérifié le 05/11 par `xcodebuild archive` (la CI ne compile qu'en Debug) |
| Numéro de version | ✅ `CFBundleShortVersionString` 0.2.0, dans `ios/project.yml` |
| Numéro de build | ✅ `CFBundleVersion` 30, dans `ios/project.yml` |
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

À coller dans *App Review Information ▸ Notes* — en français, le bloc
s'appelle **« Informations utiles à la vérification de l'app »** et le champ
**« Remarques »**, tout en bas de la page d'une **version** (pas de l'app). En
anglais : c'est la langue que lit l'équipe.

⚠️ **Le champ ne rend pas le Markdown.** Les `**` du bloc ci-dessous sont là
pour la lecture de ce document ; ce qui est dans App Store Connect est en texte
brut, et doit le rester — collés tels quels, les astérisques s'affichent.

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
> **Subscription**: free accounts get 2 minutes of storytelling per day per
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
>
> **Legal (Guideline 3.1.2)**: the subscription screen shows the subscription
> name, its length (1 month), its price from the App Store, a Restore Purchases
> button, and links to the Terms of Use and the Privacy Policy. The Terms of Use
> (Apple standard EULA) link is at the end of the App Description, and the
> Privacy Policy URL is set in App Privacy. The subscription is submitted
> together with this build.

⚠️ **Le dernier paragraphe ne vient pas d'ici** : il a été écrit directement
dans App Store Connect pendant les échanges avec App Review, et ce document
l'ignorait jusqu'au 10/11/2026 — relevé en comparant le champ réel à ce
fichier. C'est lui qui répond à la guideline 3.1.2 (ce qu'un écran
d'abonnement doit montrer), et la 0.1.0 a été approuvée avec. **Ne jamais
remplacer le champ par un copier-coller partiel** : on reprend le texte
existant et on n'y change que ce qui doit changer.

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

## Les deux numéros, et le piège de celui qu'on oublie

Les deux vivent dans `ios/project.yml`, et nulle part ailleurs : les régler
dans Xcode les perdrait au prochain `make project`.

- `CFBundleVersion` — **à monter avant chaque envoi**. App Store Connect
  refuse deux fois le même numéro. Prochain envoi : **build 31**.
- `CFBundleShortVersionString` — **à monter dès que la version courante est
  approuvée**. Une version publiée ferme son train : tout build qui s'y
  présente est refusé en *« Invalid Pre-Release Train »*, quel que soit son
  numéro de build. C'est ce qui a bloqué l'envoi du 05/11, parti en 0.1.0
  alors que cette version venait d'être approuvée — d'où le passage en 0.2.0.

Changer l'un des deux impose un `make project`, puis une **nouvelle archive** :
celle qui est déjà dans l'Organizer porte les anciens numéros.

## Il n'y a pas d'envoi automatique

La CI iOS (`.github/workflows/ci-ios.yml`) compile en Debug et lance les
tests ; elle n'archive pas et n'envoie rien. Il n'y a pas de fastlane. La
chaîne est manuelle de bout en bout : `main` à jour → monter les numéros →
`make project` → **Product ▸ Archive** → **Distribute App**. Côté Android,
`play-internal.yml` fait ce travail tout seul ; l'iOS n'a pas d'équivalent.
