# Android — reprise du chantier par Clara et Paul

Objectif : **une app Android qui marche, installée sur vos téléphones, le
6 novembre 2026.** Ce fichier dit quoi faire, dans quel ordre, et comment le
faire sans Hugo. Le détail technique est dans [`android.md`](android.md) (le
plan et la liste de parité) et [`android/CLAUDE.md`](../android/CLAUDE.md) (les
conventions) : Claude les lit tout seul, vous n'avez pas à les lire.

## Ce que veut dire « qui marche » le 6 novembre

Le plan complet (paiements, Google, Apple, notifications…) prend environ dix
semaines. En deux, on vise **le cœur du produit**, sur un compte existant :

| Dans le périmètre du 6/11 | Après le 6/11 |
|---|---|
| Se connecter par e-mail, créer un compte, se déconnecter | Connexion Google et Apple (lots B1, B2) |
| L'accueil : ses voyages, en créer un, en rejoindre un par code | Abonnement Google Play (B4) — un compte déjà abonné sur iPhone reste illimité sur Android |
| Raconter : vocal, texte, photo, la conversation avec MEMO | Commande du carnet imprimé, Stripe, Google Pay (B5) |
| Le crédit du jour (5 min) et les envois hors ligne | Notifications push (B3) |
| Lire le carnet en PDF, le partager | Profil complet, aide, export, fiche Play Store |

**Fini quand** : Paul enregistre un vocal sur Android, et ce vocal apparaît une
fois, et une seule, dans la conversation du même voyage sur iPhone.

## Comment on travaille sans Hugo

Vous n'installez rien. Tout passe par **Claude Code sur le web**
(claude.ai/code), branché sur le repo `hugo-jouffre/memo-book` :

1. Ouvrir une session sur le repo, branche `main`.
2. Coller le prompt de la tâche (ci-dessous), tel quel.
3. Claude code, teste, et ouvre une PR. La CI Android la compile et la teste.
4. Le build de test : chaque PR produit un APK (`memobook-debug-apk`) dans
   l'onglet *Actions* de GitHub, à installer sur un téléphone Android
   (autoriser l'installation depuis le navigateur ou Fichiers).
5. Paul teste à côté de l'iPhone, sur le même compte, et commente la PR. Clara
   tranche ce qui est produit, puis fusionne quand la CI est verte et que Paul
   a validé.

Une tâche = une session = une PR. Si une session déraille, on la ferme et on en
rouvre une avec le même prompt, plus ce qui n'allait pas.

## Avant le départ de Hugo (lui seul peut le faire)

Sans ces accès, rien ne s'installe sur un téléphone. **À faire en premier.**

- [ ] Donner à Clara et Paul l'accès en écriture au repo GitHub, et un accès Claude Code.
- [ ] Inviter Clara (admin) et Paul (testeur) sur la Play Console ; créer l'app `com.memobook.app`.
- [ ] Créer la clé d'upload Android et la poser en secret GitHub
      (`ANDROID_UPLOAD_KEYSTORE`, `ANDROID_UPLOAD_KEYSTORE_PASSWORD`,
      `ANDROID_UPLOAD_KEY_ALIAS`, `ANDROID_UPLOAD_KEY_PASSWORD`) — jamais dans le repo.
- [ ] Créer le compte de service de la Play Developer API et le poser en secret
      GitHub (`PLAY_SERVICE_ACCOUNT_JSON`), pour que la CI publie seule sur la piste interne.
- [ ] Noter où vivent ces clés, à côté de celles d'iOS (pas dans ce fichier).

## Les tâches, dans l'ordre

✅ fait · 🔄 PR ouverte · ⏳ à faire. Cochez en fusionnant la PR.

**Le 22/10/2026, tous les écrans d'iOS ont été portés** (PR « Android : tous
les écrans », après la PR #142 du cœur) : ce qui reste n'est plus du portage,
c'est **la vérification sur téléphone**, les clés de Hugo et les lots serveur.

| # | Tâche | État | Pour qui | Fini quand |
|---|---|---|---|---|
| A3 | Modèles, client des routes, erreurs en français | 🔄 #142 | Claude | les 380 tests portés d'iOS passent en CI |
| T0a | APK de test téléchargeable à chaque PR | 🔄 #142 | Claude | un APK se télécharge depuis la PR |
| A3b → A8 | Le bac à sable et **tous les écrans** : entrée, accueil, voyage, conversation, enregistrement et file hors ligne, réglages, carnet, couvertures, paywall, commande, profil, aide | 🔄 | Claude | 833 tests verts, l'app traversée dans l'émulateur sur le jeu d'essai |
| T0b | Envoi signé sur la piste interne (`play-internal.yml`) | 🔄 | Claude ; **les secrets de Hugo** | Clara et Paul installent depuis le Play Store |
| B1, B6 | `assetlinks.json`, pages qui ouvrent l'app, page de suppression | 🔄 #143 | Claude ; Hugo pose `ANDROID_APP_CERT_SHA256` | un lien `/j/…` ouvre l'app sans demander |
| R1 | Recette sur téléphone, à côté de l'iPhone : deux comptes, petit et grand téléphone, police à 200 %, TalkBack | ⏳ | Paul | liste des bugs bloquants vide |
| R2 | Les fins de parcours : un vocal hors ligne arrive une fois sur iPhone ; un voyage créé sur Android y apparaît ; le même PDF des deux côtés | ⏳ | Paul | les trois sont vrais |
| B3 | Notifications FCM (projet Firebase d'abord) | ⏳ | Claude, après Hugo | chacun des neuf types ouvre son écran |
| B4 | Abonnement Google Play côté serveur (compte de service Play d'abord) | ⏳ | Claude, après Hugo | un achat de test rend illimité le même compte sur iPhone |
| B2 | Apple par le web (Services ID d'abord) | ⏳ | Claude, après Hugo | un compte Apple d'iPhone entre sur Android |
| B5 | Plateforme dans les réponses de MEMO, Google Pay | ⏳ | Claude | MEMO dit « Paramètres du téléphone » sur Android |
| A8b | CGU, confidentialité et FAQ réécrites pour Google Play | ⏳ | Claude ; Clara relit | la fiche Play peut citer ses textes |
| A9 | Fiche Play, classification, sécurité des données | ⏳ | Clara | l'app passe l'examen de Google |

### Les prompts à coller

Chaque prompt suppose que la PR précédente est fusionnée.

**R1 — Un bug trouvé à la recette**
> Lis android/CLAUDE.md. Sur Android, [ÉCRAN] fait [CE QUI SE PASSE] alors que l'iPhone fait [CE QU'IL FAIT] (captures jointes). Corrige-le dans le code Android en suivant le fichier Swift jumeau, ajoute un test si c'est une règle, et ouvre une PR.

**B3 — Notifications FCM**
> Lis android/CLAUDE.md, docs/android.md (lot B3) et docs/notifications.md. Le projet Firebase existe et `google-services.json` est posé en secret GitHub `GOOGLE_SERVICES_JSON` (jamais dans le repo). Côté serveur : `push_tokens.provider` (migration additive, dans sa propre PR, appliquée aussi à `memobook_test`), `/v1/push-tokens` qui accepte un jeton FCM sans le passer en minuscules, un expéditeur FCM HTTP v1 derrière `PushSender`. Côté app : remplace `FirebasePushTokenSource` (`notifications/PushNotifications.kt`, `TODO(B3)`) et le service de réception. Ouvre les PR.

**B4 — Abonnement Google Play**
> Lis android/CLAUDE.md, docs/android.md (lot B4, et l'avertissement sur `POST /v1/profile/subscription/cancel`) et docs/paiements.md. Le compte de service de la Play Developer API est posé sur Railway. Écris `POST /v1/subscriptions/google-play` (`purchaseToken`, `productId`, `memoId`), que l'app appelle déjà : vérifie le jeton, rattache l'achat au compte (`obfuscatedAccountId`), **acquitte-le**, rends le profil. Ajoute le fournisseur `google_play` (migration additive à part), le webhook des notifications temps réel, et une résiliation qui ne coupe plus localement un abonnement Play. Ouvre les PR.

**A8b — Textes légaux pour Google Play**
> Lis android/CLAUDE.md et docs/android.md. Les CGU (chapitre 5), la politique de confidentialité (2.4 et 3) et trois réponses de la FAQ parlent de l'App Store et de l'iPhone. Propose, dans `:core` (Android) et `MemoBookCore` (iOS), des textes qui valent pour les deux stores, sans changer le fond ; liste chaque phrase changée dans la PR pour Clara.

## Une décision à prendre (Clara)

**La transcription en direct pendant l'enregistrement.** Sur iPhone, le texte
s'écrit pendant qu'on parle. Sur Android, le micro ne peut pas servir à la fois
à l'enregistrement et à la reconnaissance vocale avant Android 13. Trois choix :

1. **Forme d'onde seule sur tous les Android** (recommandé pour le 6/11, **et
   c'est ce qui est porté**) : le plus simple et le plus sûr ; le texte du
   serveur arrive comme aujourd'hui.
2. Transcription en direct sur Android 13+, forme d'onde seule en dessous.
3. Transcription partout, avec deux micros en concurrence : déconseillé, le
   vocal risque d'être coupé sur certains téléphones.

## Si quelque chose bloque

- **La CI est rouge** : coller le lien de la CI à Claude dans la même session,
  avec « corrige la CI ».
- **Un écran diffère de l'iPhone** : capture des deux côtés dans la PR ; Claude
  corrige dans la même PR.
- **Une question produit** : Clara tranche, et la réponse va dans la PR.
- **Une clé ou un accès manque** : seul Hugo peut agir ; noter dans la PR et
  passer à la tâche suivante.
