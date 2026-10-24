# MemoBook sur Android — portage et parité

L'app Android fait **tout ce que fait l'app iOS**, sur le même serveur, la même
base, les mêmes comptes. Un voyageur passe de l'un à l'autre sans rien perdre :
ses voyages, ses vocaux, son abonnement le suivent, puisqu'ils sont au serveur.

Référence : iOS 0.1.0 (build 10), `main` à `5d46279`, le 21/10/2026. Les
conventions du code Android sont dans [`android/CLAUDE.md`](../android/CLAUDE.md).

## Ce qui reste, ce qui change

Natif, en Kotlin et Jetpack Compose, construit comme l'app iOS : mêmes modules,
même sens de dépendance, mêmes noms de fichiers. Compose reprend presque mot
pour mot les règles SwiftUI et MVVM du code iOS ; une base commune aux deux
plateformes demanderait de réécrire une app iOS déjà livrée.

| Sujet | iOS | Android | Serveur |
|---|---|---|---|
| API, comptes, base | Fastify sur Railway, jeton de session de 90 jours | la même ; `POST /v1/devices` accepte déjà `platform: "android"` | rien |
| Écrans | SwiftUI, `@Observable`, `RootView` | Compose, `ViewModel` + `StateFlow`, `RootView` | rien |
| Stockage local | Trousseau, Application Support, Caches, UserDefaults | jeton chiffré par le Keystore, `filesDir`, `cacheDir`, DataStore | rien |
| File des envois | `RecordingOutbox`, vidée au retour dans l'app | la même, vidée par WorkManager — elle survit aussi à l'arrière-plan | rien |
| Vocal | AAC 44,1 kHz mono, `.m4a`, `audio/mp4` | le même fichier, par `MediaRecorder` | rien |
| Transcription en direct, lecture à voix haute | `SFSpeechRecognizer`, `AVSpeechSynthesizer`, `fr-FR` | `SpeechRecognizer` sur l'appareil, `TextToSpeech`, `fr-FR` | rien |
| Connexion | Apple natif, SDK Google, e-mail | Google par Credential Manager, e-mail — pas d'Apple (22/10/2026) | B1 |
| Abonnement | StoreKit 2, `com.memobook.app.subscription.monthly`, 4,99 € | Google Play Billing, **même identifiant**, vérifié par le serveur | B4 |
| Carnet imprimé | Stripe PaymentSheet, Apple Pay | Stripe PaymentSheet Android, Google Pay | B5 |
| Notifications | APNs | Firebase Cloud Messaging, mêmes types et mêmes liens | B3 |
| Liens | `memobook://`, liens universels `/j/*` | `memobook://`, App Links `/j/*` (`assetlinks.json`) | B1 |
| Test et publication | TestFlight, App Store Connect | piste de test interne, Play Console, Play App Signing | — |
| CI | `ci-ios.yml`, macOS, Debug | `ci-android.yml`, Linux, Debug **et** Release | — |

**L'illimité pend du compte, pas du store** (`hasUnlimitedAccess`) : un abonné
de l'App Store est abonné sur Android, et inversement. Android ne propose pas
« S'abonner » à un compte illimité, et « Gérer » l'envoie au store qui a vendu
l'abonnement.

## Les phases

Dix semaines estimées jusqu'à la piste de test interne, en deux couloirs : les
phases de l'app (A) et les lots du serveur (B). L'app iOS et son serveur ont
mis douze semaines du premier commit (27/07) au build 10 ; le portage part
d'un produit, d'un serveur et d'un code déjà tranchés.

| Phase | Semaines | Contenu | Fini quand | Attend |
|---|---|---|---|---|
| **A0** Comptes et clés | 1–2 | Play Console ; client OAuth Android (SHA-1 debug, upload, signature Play) ; Firebase ; compte de service Play ; clé d'upload hors du dépôt ; téléphones de test ; `api.memo-book.com` tranché | chaque clé existe et est rangée avec celles d'iOS | Hugo |
| **A1** Socle | 1 | projet Gradle aux modules d'iOS, tokens, polices, adresse du serveur, CI | CI verte, l'app s'ouvre dans l'émulateur | — |
| **A2** Design system | 1–3 | les 36 composants `Brand…`, import des 178 images, tests de capture | un écran-catalogue montre chaque composant | — |
| **A3** Cœur, client, bac à sable | 2–3 | modèles, client des 72 routes, erreurs, jeton, connectivité, cache, `PreviewApi` et interrupteurs de debug | les tests Core et Networking portés passent | — |
| **A4** Comptes et entrée | 3–4 | lancement, accueil d'entrée, e-mail, Google, mot de passe oublié, dernières questions, déconnexion, suppression | les deux comptes de test entrent sur un Pixel ; l'e-mail de réinitialisation ouvre l'app | B1 |
| **A5** Le récit | 4–6 | accueil, nouveau carnet, rejoindre, création de voyage hors ligne, écran du voyage, conversation avec MEMO, enregistrement et crédit du jour, file des envois, cache | un vocal enregistré hors ligne sur Android arrive une fois dans le fil iPhone du même voyage | — |
| **A6** Le carnet | 6–7 | réglages du voyage, personnalisation, couvertures, composition, lecteur PDF, partage, galerie | un voyage donne le même PDF sur les deux | — |
| **A7** L'argent | 7–8 | paywall, abonnement Play, feuille d'abonnement, tunnel de commande Stripe et Google Pay, cartes, suivi | un achat de test sur Android rend illimité le même compte sur iPhone | B4, B5 |
| **A8** Profil, aide, notifications | 8–9 | profil et ses neuf feuilles, statistiques, export, aide, textes légaux, FCM | chacun des neuf types de notification ouvre son écran | B3 |
| **A9** Recette et Play | 9–10 | la recette iOS rejouée sur Android, fiche Play et sécurité des données (`fiche-play-store.md`), URL de suppression, test interne → fermé → production | Clara et Paul installent l'app depuis la piste interne | B6, A0 |

Le compte développeur Play est un compte **organisation**, créé le 21/10/2026 :
il est dispensé du test fermé (12 testeurs pendant 14 jours) qu'un compte
personnel neuf doit passer avant la production. Reste l'examen de Google à
chaque version.

## Les lots du serveur

Tous additifs : chaque build iOS en circulation continue de marcher. La base de
développement est celle de production — chaque migration part dans sa propre
PR, appliquée à la production par la Pre-deploy Command et à `memobook_test` à
la main.

| Lot | Ce qui change | Fichiers | Migration |
|---|---|---|---|
| **B1** Liens et Google — ✅ PR #143 ; `GOOGLE_WEB_CLIENT_ID` posé sur Railway et dans `gradle.properties` le 22/10 (client « MemoBook Backend ») ; le client Android (`com.memobook.app` + SHA-1 de debug) est créé, ceux des clés d'upload et de Play viennent avec la Play Console | `GOOGLE_WEB_CLIENT_ID` posé sur Railway (l'audience des jetons Android) ; `/.well-known/assetlinks.json` ; `/j/:code` et `/password/reset` savent mener au Play Store ou dans l'app, sans dire « iPhone » | `env.ts`, `invitePage.ts`, `passwordResetPage.ts` | non |
| ~~B2~~ Apple par le web — **abandonné** (Hugo, 22/10/2026) : pas d'entrée Apple sur Android. Le travail est gardé sur la branche `android-serveur-b2` | — | — | non |
| **B3** FCM — 🔶 branche `android-serveur-b3` (migration `20261022140000_jetons_fcm` dans son propre commit) ; reste le projet Firebase (A0) et ses variables | `push_tokens.provider` (apns ou fcm) ; `/v1/push-tokens` accepte un jeton FCM (`provider: "fcm"` ou `platform: "android"`) sans le passer en minuscules ; un expéditeur FCM HTTP v1 (compte de service, JWT RS256, sans SDK) derrière `PushSender`, qui choisit APNs ou FCM par jeton ; `UNREGISTERED` oublie le jeton ; `FCM_SERVICE_ACCOUNT_JSON`, `FCM_PROJECT_ID`, `npm run fcm:check`. Côté app : `FirebasePush.kt` et `MemoBookMessagingService`, sans `google-services` | `schema.prisma`, `routes/notifications.ts`, `services/apns.ts`, `services/fcm.ts` | oui |
| **B4** Google Play Billing — 🔶 branche `android-serveur-b4` (migration `20261022150000_abonnement_google_play` dans son propre commit) : `POST /v1/subscriptions/google-play`, `POST /v1/webhooks/google-play`, `subscription.store` et `manageUrl` au profil ; reste le compte de service Play et Pub/Sub (A0) | le fournisseur `google_play` ; la route d'achat qui vérifie et **acquitte** le jeton ; le webhook des notifications temps réel ; résiliation, sérialiseurs et rappels selon le store | `schema.prisma`, `services/googlePlay.ts`, `routes/profile.ts`, `appSerializers.ts`, `subscriptionCatalog.ts` | oui |
| **B5** Google Pay et plateforme — 🔶 branche `android-serveur-b5` : `X-App-Platform` retenu sur le tour (`payload.platform`), `GOOGLE_PAY_ENABLED` → `googlePayEnabled` du ticket ; le rappel d'abonnement parle du Play Store à un abonné Play (B4) | Google Pay dans le ticket de paiement Stripe ; un en-tête `X-App-Platform` lu comme `X-Time-Zone` ; « Réglages de l'iPhone » dans le prompt de MEMO et ses appels à l'action, le lien App Store de l'e-mail de rappel | `billing.ts`, `app.ts`, `callsToAction.ts`, `conversationAnthropic.ts`, `mailer.ts` | non |
| **B6** Page de suppression — 🔶 PR #143 : `/account/delete` | une page publique pour demander la suppression d'un compte par e-mail, que Google Play exige de toute app qui crée des comptes | à côté de `dataExportPage.ts` | non |

Côté app, B4 rend aussi indépendant du store ce qui ne connaît qu'Apple :
`Subscription.managedByAppStore` (dire quel store tient l'abonnement), les états
`Grace` et `isInBillingRetry` (calqués sur le réessai d'Apple), et
`applePayMerchantId` dans `PaymentIntentTicket` et `OrderPayment` (B5). Les CGU
(chapitre 5), la politique de confidentialité (2.4 et 3) et trois réponses de
la FAQ parlaient de l'App Store et de l'iPhone : leur version Google Play est
écrite côté Android (A8b, 23/10/2026), à relire par Clara.

`POST /v1/profile/subscription/cancel` ne coupe plus localement un abonnement
Google Play (B4) : il note la raison, comme pour StoreKit, et la résiliation se
fait dans le Play Store (`subscription.manageUrl`).

## La liste de parité

Écran par écran, dans l'ordre des phases. ✅ fait · 🔄 en cours · ⏳ à faire.
Les noms sont ceux du code iOS (`ios/Modules/Sources/MemoBookFeature`) ; le
fichier Kotlin porte le même.

### Socle (A1)

| iOS | Android | État |
|---|---|---|
| `APIConfiguration` et ses tests | `ApiConfiguration` — l'émulateur vise `10.0.2.2`, un téléphone retombe sur la production | ✅ |
| `NotificationLink`, `InviteLink`, `PasswordResetLink` | les trois lecteurs de liens, dans `:core`, et leurs tests | ✅ |
| `Tokens.swift`, `BrandFonts` | `Tokens.kt`, `BrandFonts.kt`, les six polices | ✅ |
| `StoreKitCatalog` | `PlayCatalog` — le même identifiant de produit | ✅ |
| Format du vocal (`AudioRecorder`) | `VoiceNoteFormat` | ✅ |
| `Onboarding/LaunchView` | le M s'écrit sur la courbe de la marque (`BrandMarkBackdrop`), vérifié dans l'émulateur | ✅ |
| Icône `AppIcon.icon` | icône adaptative, M crème sur vert, monochrome pour Android 13+ | ✅ |
| `ci-ios.yml` | `ci-android.yml` | ✅ |

### Design system (A2)

44 des 45 fichiers de `MemoBookDesign` — tous sauf `BrandNavigation` —, chacun sous le même nom dans
`android/design`. L'écran-catalogue (`make run ARGS="--ez designCatalogue true"`)
les montre tous, et chaque preview est une capture de référence que la CI compare.

| iOS | Android | État |
|---|---|---|
| `Tokens.swift`, `BrandFonts` | `Tokens.kt`, `BrandFonts.kt` ; l'interlettrage posé là où iOS le pose, pas partout | ✅ |
| Le catalogue d'images (178) | `make assets` : VectorDrawables et images depuis `MemoBookAssets.xcassets` ; deux tests les chargent toutes | ✅ |
| `BrandButton`, `ErrorBanner`, `BrandTagPill` (et la jauge, la carte en pointillés), `BrandSkeleton`, `BrandIconBadge`, `BrandFooterScrim`, `LucideIcon` | portés | ✅ |
| `BrandRowGroup`, `BrandOptionGroup`, `BrandDisclosureCard`, `BrandToggleCard`, `BrandSegmentedPicker`, `BrandNotice`, `BrandLimitBanner`, `BrandSlider`, `BrandGauge`, `BrandStepper` | portés ; l'interrupteur d'iOS redessiné (`BrandSwitch`) | ✅ |
| `BrandSheet`, `BrandTextField`, `BrandTextBox`, `KeyboardDismissBar`, `BrandSearchField`, `BrandCountryField`, `BrandDateField`, `BrandRangeCalendar` | portés ; la feuille se présente par `BrandSheetHost`, et se referme au glissé (poignée ou contenu), au voile, au retour | ✅ |
| `BrandMark`, `BrandMarkBackdrop`, `BrandBackdrop`, `BrandStrokes`, `BrandChatBubble`, `BrandWaveform`, `RecordButton`, `BrandScreenHeader`, `BrandSwipeDrawer`, `BrandRefreshFlash`, `BrandComingSoon`, `BrandStatusBarScrim`, `BrandFilterChip`, `BrandAvatar`, `ScrollOffsetReader` | portés ; le tiroir glisse sans voler le défilement vertical, TalkBack y trouve ses actions | ✅ |
| `DeviceScreen`, `brandScrollWithoutBounce`, `brandHorizontalFade` | portés — le rayon des coins vient d'Android, qui le donne | ✅ |
| L'app en français sur un téléphone réglé dans une autre langue | `FrenchLocale` : la langue française, la région du téléphone | ✅ |

**À vérifier sur un vrai téléphone, à côté de l'iPhone :** TalkBack sur les
champs de saisie (l'intitulé est sur un nœud voisin de la zone de saisie, et
non sur elle : il peut s'annoncer en deux temps) ; le voile (40 %), la durée
(400 ms) et le seuil de fermeture de la feuille ; l'interrupteur aux mesures
d'iOS 26 plutôt que d'avant ; l'éclairci à 70 % des boutons nus sous le doigt.
Et une règle à trancher : les jours hors plage du calendrier et un champ
« Pays » sans liste sont désactivés, comme sur iOS, quand la règle de la maison
voudrait qu'ils pâlissent et s'expliquent.

### Cœur et bac à sable (A3)

Les 44 fichiers de `MemoBookCore` et les 9 de `MemoBookNetworking`, chacun sous
son nom. 380 tests sur la JVM, portés cas pour cas des suites iOS.

| iOS | Android | État |
|---|---|---|
| Modèles de `MemoBookCore` et leur décodage (états inconnus tolérés) | `kotlinx.serialization` ; un état inconnu devient `Unknown(raw)` (`RawValueSerializer`), les `decodeIfPresent ?? défaut` d'iOS des sérialiseurs dédiés | ✅ |
| Textes : `ChatCopy`, `BookCopy`, `OrderCopy`, CGU, confidentialité, FAQ, aide | recopiés par script, comparés chaîne à chaîne avec le Swift | ✅ |
| `MemoBookAPIClient` : les routes, `APIError` et ses messages en français | `MemoBookApiClient` (OkHttp, coroutines annulables), `ApiError` ; la bascule vers l'adresse de secours ; `platform: "android"` à l'enregistrement de l'appareil | ✅ |
| `TokenStore`, `Connectivity`, `NetworkLog` | interfaces pures ; `KeystoreTokenStore` (AES-GCM, clé dans l'AndroidKeyStore), `AndroidConnectivity`, `AndroidLogSink` — **compilés par la CI seulement** | ✅ |
| `ContentCache`, `CachedSource`, `SessionRestore` | les mêmes, dans `cacheDir` ; l'empreinte des voyages est celle d'iOS | ✅ |
| `PreviewAPI`, `SandboxPersona`, `SandboxCredit`, les jeux d'essai | `PreviewSupport.kt`, `SandboxPersona.kt`, un `…Fixtures.kt` par écran ; `HomeFeed.fixture` s'écrit pareil | ✅ |
| Interrupteurs `-previewSignedIn`, `-openOrder`, `-composeBook`, `-lastQuestions`, `-resetOnboarding` | extras de lancement du même nom (`LaunchSwitches`), lus en Debug seulement | ✅ |
| `AppDependencies`, `RootView` | `AppDependencies` assemblé à la première activité, les fabriques en fonctions d'extension par écran ; `RootView` et ses deux piles en Navigation 3, routes et intentions dans `Navigation.kt` | ✅ |

`ApiError.developerDiagnostics` est posé par l'app en Debug.
`BookCustomisationPreviewManifest.kt` est une recopie de la table Swift : la
régénérer avec elle (deux tests le vérifient).

### Comptes et entrée (A4)

✅ porté et testé sur la JVM, vu dans l'émulateur sur le jeu d'essai ·
🔶 porté, mais attend une clé ou un lot serveur · ⏳ à faire.
**Rien n'est encore vérifié sur un vrai téléphone, ni contre le serveur.**

| iOS | État |
|---|---|
| `SessionRestore`, `LaunchView` animé | ✅ |
| `WelcomeView` et les carnets d'exemple | ✅ |
| `AuthView` (inscription, connexion), `SocialCompletionView` | ✅ |
| Google par Credential Manager — bouton masqué tant que `memobook.googleWebClientId` est vide (A0, B1) | 🔶 |
| Pas d'Apple sur Android (22/10/2026) : un compte ouvert par Apple sur l'iPhone entre par « Mot de passe oublié » | ✅ |
| `PasswordRecoverySheet`, `PasswordResetView` et le lien de l'e-mail (`memobook://` et App Link `/password/reset`) | ✅ |
| `LastQuestionsView` | ✅ |
| Déconnexion, `DeleteAccountSheet` | ✅ |

### Le récit (A5)

| iOS | État |
|---|---|
| `HomeView` : cartes, tiroir d'actions, micro, boîte hors ligne, alerte de fin de voyage (seulement pour un abonnement Google Play) | ✅ |
| `NewNotebookSheet`, `JoinTripSheet` (Polarsteps reste « à venir ») | ✅ |
| `TripCreationView` : six étapes, création hors ligne, code d'accès, invitation par la feuille de partage | ✅ |
| `TripHomeView` : en-tête, étapes, validation, suppression d'étape | ✅ |
| `ChatView` : texte, vocal, photos, suggestions, appels à l'action, lecture à voix haute, photo plein écran, contexte du voyage, fil hors ligne | ✅ |
| `RecordingSheet` : forme d'onde, pause, crédit du jour (30 s, 5 s, zéro) — **forme d'onde seule**, sans transcription en direct (voir les risques) | ✅ |
| `RecordingOutbox`, `PendingRecordingStore`, `PendingTripStore`, vidés aussi app fermée par WorkManager | ✅ |
| `PhotoFlow` : sélecteur de photos du système (sans permission), appareil photo | ✅ |

### Le carnet (A6)

| iOS | État |
|---|---|
| `TripSettingsView` et ses feuilles (dates, rythme, notifications, thème, co-voyageurs, suppression) | ✅ |
| `DailyCreditSheet`, `PageTargetChangeSheet`, `PageTargetReachSheet` | ✅ |
| `BookCustomisationView` : ratio, pages, décorations, typos, extras, aperçus de personnalisation (images du bucket public, par Coil) | ✅ |
| `CoversView`, `CoverCarouselView`, `CoverTextsView`, `CoverStatsSheet` — un seul modèle pour les quatre écrans | ✅ |
| `BookPreviewFlowView` : composition, lecteur PDF (`PdfRenderer`), plein écran | ✅ |
| `ShareBookSheet` (PDF, lien, WhatsApp), `FoundersNoteSheet` | ✅ |
| `GalleryView` | ✅ |

### L'argent (A7)

| iOS | État |
|---|---|
| `PaywallView` (premier passage, retour), `BookPreviewSheet` par-dessus | ✅ |
| Achat de l'abonnement par Google Play Billing, restauration, achats non livrés — la remise au serveur (`POST /v1/subscriptions/google-play`) attend le lot B4 : le produit ne s'active pas dans la Play Console avant | 🔶 |
| `SubscriptionSheet` : actuel, continuer, raison, fin — et « Gérer » vers le store qui l'a vendu (Google Play, ou le renvoi vers l'iPhone pour l'App Store), lu sur `subscription.store` et `subscription.manageUrl` du serveur (B4), la lecture d'avant en repli | ✅ |
| `OrderView` : sept étapes, feuille Stripe, reprise d'un paiement abandonné, `OrderWhatsAppSheet` | ✅ |
| Google Pay dans la feuille Stripe — piloté par le serveur (`googlePayEnabled` du ticket, `GOOGLE_PAY_ENABLED`, B5) ; éteint tant que l'accès production Google Pay manque | 🔶 |
| Moyens de paiement enregistrés (CustomerSheet de Stripe) | ✅ |

### Profil, aide, notifications (A8)

| iOS | État |
|---|---|
| `ProfileView` : nom, photo, adresse, genre, notifications du compte, mot de passe, connecteurs (à venir), suivi de commande, statistiques, export | ✅ |
| `SupportView` : FAQ, votes, formulaire | ✅ |
| `LegalDocumentView` : conditions et confidentialité | ✅ |
| Textes légaux et FAQ en version Google Play (CGU chap. 5, confidentialité 2.4 et 3, trois réponses), relus par Clara ; les versions iOS ne changent pas | 🔶 |
| Notifications : permission `POST_NOTIFICATIONS` au même moment qu'iOS, `ChatNotificationsNudge`, ouverture du bon écran, accusé d'ouverture | ✅ |
| Le jeton FCM et la notification d'un message reçu (`FirebasePush.kt`, `MemoBookMessagingService`, lot B3) : `FirebaseApp` initialisé à la main depuis `memobook.firebase.*` de `gradle.properties`, sans `google-services.json` ; message de données seulement, canal « MemoBook », toucher vers `MainActivity` avec `link` et `deliveryId`. Vides tant que le projet Firebase (A0) n'existe pas : aucun jeton ne part | 🔶 |

### Recette et publication (A9)

| Sujet | État |
|---|---|
| La recette iOS rejouée : deux comptes, petit et grand téléphone, police à 200 %, TalkBack | ⏳ |
| Fiche Play en français, classification, sécurité des données : textes et réponses prêts dans [`fiche-play-store.md`](fiche-play-store.md), à saisir par Hugo | 🔶 |
| URL de suppression : `/account/delete` (PR #143) | 🔶 |
| Envoi signé sur la piste interne : `.github/workflows/play-internal.yml`, attend les cinq secrets de Hugo | 🔶 |
| Piste interne → production (pas de test fermé obligatoire pour un compte organisation) | ⏳ |

### Textes propres à Android, à relire par Clara

Tous les textes sont recopiés du Swift, à ces exceptions près, qui nomment la
plateforme :

- « Paramètres du téléphone » / « Ouvrir les Paramètres » à la place des
  « Réglages » d'iOS (micro, photos, notifications).
- La feuille de suppression du compte, pour un abonnement Google Play :
  « Ton abonnement, lui, se résilie dans le Play Store : supprimer ton compte
  ne l’arrête pas, pense à le couper dans Play Store › Paiements et
  abonnements › Abonnements. »
- La feuille d'abonnement, pour un abonnement pris sur iPhone : « Ton
  abonnement a été pris sur un iPhone : il se résilie chez Apple, dans les
  réglages de ton iPhone. MemoBook ne peut pas le couper depuis ce
  téléphone. » (et sa jumelle « il se réactive… ne peut pas le relancer »).
- Le prélèvement raté d'un abonnement Google Play : « Google Play réessaie /
  cesse de réessayer / ne le retentera pas », « dans ton compte Google Play ».
- Le paywall : « compte Google », « Play Store › Paiements et abonnements ›
  Abonnements » ; une erreur de vérification : « Le Play Store… ».

### Ce qui ne se porte pas

- `MemoList/` et `MemoDetail/` : plus aucune route n'y mène sur iOS — et avec
  eux `StatusBadge` et `EmptyStateView`, qu'ils sont seuls à employer.
- `BrandNavigation` : il rend sur iOS le glissé de retour qu'une barre masquée
  emporte ; Android a son geste de retour.
- Ce qui est « à venir » sur iOS l'est aussi sur Android, au même endroit :
  l'import Polarsteps, le Tricount, les six connecteurs, l'ouverture d'un carnet
  de la galerie.

## Les décisions

Validées par Clara et Hugo le 22/10/2026 :

- **L'enregistrement** : forme d'onde seule, sans transcription en direct.
- **Les mots d'Android** : « téléphone », « Paramètres du téléphone », « Play
  Store » partout où iOS dit iPhone, Réglages ou App Store (l'app et MEMO, B5).
- **La suppression du compte** : la page `/account/delete` (B6) supprime sous
  30 jours.
- **Pas d'Apple sur Android** : ni bouton ni lot B2 ; un compte Apple de
  l'iPhone entre par « Mot de passe oublié ».

## Les risques

- **Un micro, deux écoutes.** Sur iOS, la transcription en direct lit le son de
  l'enregistreur. Le `SpeechRecognizer` d'Android ouvre le micro lui-même, et
  seul Android 13+ lui laisse lire un flux fourni par l'app. Piste : enregistrer
  par `AudioRecord` et un encodeur AAC, nourrir la reconnaissance sur Android
  13+, n'afficher que la forme d'onde avant. La transcription affichée n'est
  qu'un retour visuel ; celle du serveur ne change pas. **Porté en forme
  d'onde seule** (l'option recommandée de `android-reprise.md`) ; l'interface
  du transcripteur est en place pour l'option Android 13+ si Clara la choisit
  (`SpeechTranscriber.kt` dit comment). Clara et Hugo ont validé la forme
  d'onde seule le 22/10/2026.
- **Un compte Apple de l'iPhone sur Android.** Android n'a pas d'entrée Apple :
  la personne choisit « Mot de passe oublié » avec l'adresse de son compte (le
  relais `privaterelay.appleid.com` si elle l'a masquée : il transfère
  l'e-mail), et le serveur l'envoie même à un compte sans mot de passe
  (`services/passwordReset.ts`). À vérifier en A4 avec un compte Apple masqué.
- **Payer deux fois.** Voir plus haut : Android masque « S'abonner » à tout
  compte illimité, quel que soit le store.
- **Material contre le papier.** Les composants Material tirent les écrans hors
  de la marque. Les écrans n'emploient que des `Brand…`.
- **Deux apps qui divergent.** Chaque lot iOS fusionné après aujourd'hui creuse
  l'écart. Les PR portent les étiquettes `ios`, `android`, `backend`, et disent
  ce que l'autre plateforme doit reprendre ; cette liste en garde la trace.
