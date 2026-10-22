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

| # | Tâche | État | Pour qui | Fini quand |
|---|---|---|---|---|
| A3 | Modèles, client des 72 routes, erreurs en français | 🔄 | Claude | les tests portés d'iOS passent en CI |
| T0a | APK de test téléchargeable à chaque PR | 🔄 | Claude | un APK se télécharge depuis la PR |
| T0b | Envoi signé sur la piste interne de Google Play | ⏳ | Claude, après les secrets de Hugo | Clara et Paul installent depuis le Play Store |
| A3b | Bac à sable : `PreviewApi`, personas, interrupteurs de debug, `AppDependencies` | ⏳ | Claude | l'app s'ouvre sur l'accueil du bac à sable, sans réseau |
| A4 | Lancement, bienvenue, inscription et connexion e-mail, mot de passe oublié, déconnexion, suppression | ⏳ | Claude ; Paul teste | les deux comptes de test entrent sur Android |
| A5a | Accueil, nouveau carnet, rejoindre, création de voyage | ⏳ | Claude ; Paul teste | un voyage créé sur Android apparaît sur iPhone |
| A5b | Conversation avec MEMO : texte, photos, appels à l'action | ⏳ | Claude ; Paul teste | le même fil, dans le même ordre, sur les deux |
| A5c | Enregistrement, crédit du jour, file des envois hors ligne | ⏳ | Claude ; **Clara tranche la transcription en direct** | un vocal hors ligne arrive une fois sur iPhone |
| A6a | Lecteur du carnet PDF et partage | ⏳ | Claude ; Paul teste | le même PDF sur les deux |
| R1 | Recette du 6/11 : deux comptes, petit et grand téléphone, police à 200 % | ⏳ | Paul | liste des bugs bloquants vide |

Ordre imposé : A3 → A3b → A4 → A5a → A5b → A5c → A6a. T0b peut partir en même
temps que A3b, dès que les secrets existent.

### Les prompts à coller

Chaque prompt suppose que la PR précédente est fusionnée.

**T0b — Piste interne**
> Lis android/CLAUDE.md et docs/android-reprise.md. Ajoute un workflow manuel qui signe un AAB Release avec les secrets `ANDROID_UPLOAD_*` et l'envoie sur la piste interne de Google Play avec `PLAY_SERVICE_ACCOUNT_JSON` ; s'il manque un secret, il échoue en le nommant. Aucune clé dans le repo. Ouvre une PR.

**A3b — Bac à sable**
> Lis android/CLAUDE.md et docs/android.md. Porte la phase A3, partie bac à sable : `PreviewSupport.swift` (`PreviewApi`), `SandboxPersona.swift`, `ContentCache.swift`, et le câblage de `AppDependencies.swift` (client réel, `TokenStore` Keystore, connectivité). Les interrupteurs de debug d'iOS deviennent des extras de lancement du même nom, lus par `MainActivity` en Debug. Porte les tests. Coche la liste de parité de docs/android.md et ouvre une PR.

**A4 — Comptes et entrée (e-mail seulement)**
> Lis android/CLAUDE.md et docs/android.md. Porte la phase A4 sans Google ni Apple (lots B1 et B2 après le 6/11) : `SessionRestore`, `LaunchView` animé, `WelcomeView` et ses carnets d'exemple, `AuthView` en e-mail, `PasswordRecoverySheet`, `PasswordResetView`, `LastQuestionsView`, déconnexion et `DeleteAccountSheet`. Les boutons Google et Apple n'apparaissent pas encore. Uniquement les composants `Brand…`. Porte les modèles d'écran et leurs tests, coche la liste de parité, ouvre une PR.

**A5a — Accueil et voyages**
> Lis android/CLAUDE.md et docs/android.md. Porte de la phase A5 : `HomeView` et `HomeModel` (cartes, tiroir d'actions, boîte hors ligne, alerte de fin de voyage), `NewNotebookSheet`, `JoinTripSheet`, `TripCreationView` (six étapes, création hors ligne, code d'accès), `TripHomeView`, avec `PendingTripStore`. Le micro de l'accueil ouvre la conversation (A5b). Porte les tests, coche la liste de parité, ouvre une PR.

**A5b — La conversation**
> Lis android/CLAUDE.md et docs/android.md. Porte `ChatView` et son modèle : texte, photos (Photo Picker système, sans permission de stockage), suggestions, appels à l'action, lecture à voix haute (`TextToSpeech` fr-FR), photo plein écran, contexte du voyage, fil hors ligne, et `PhotoFlow`. Le bouton micro ouvre `RecordingSheet` (A5c). Porte les tests, coche la liste de parité, ouvre une PR.

**A5c — L'enregistrement et la file des envois**
> Lis android/CLAUDE.md et docs/android.md, dont le risque « Un micro, deux écoutes ». Clara a tranché : [COLLER LA DÉCISION DE CLARA]. Porte `RecordingSheet` (forme d'onde, pause, crédit du jour à 30 s, 5 s et zéro), l'enregistreur `.m4a` AAC 44,1 kHz mono du module `:recording`, et `RecordingOutbox` et `PendingRecordingStore` vidés par WorkManager, avec les identifiants créés par l'app pour qu'un vocal n'arrive qu'une fois. Porte les tests, coche la liste de parité, ouvre une PR.

**A6a — Le carnet**
> Lis android/CLAUDE.md et docs/android.md. Porte de la phase A6 : le lecteur PDF de `BookPreviewFlowView` (`PdfRenderer`, plein écran) et `ShareBookSheet` (PDF, lien, WhatsApp). La composition et la personnalisation viennent après le 6/11 : leurs entrées pâlissent avec la mention « bientôt ». Porte les tests, coche la liste de parité, ouvre une PR.

## Une décision à prendre (Clara, avant A5c)

**La transcription en direct pendant l'enregistrement.** Sur iPhone, le texte
s'écrit pendant qu'on parle. Sur Android, le micro ne peut pas servir à la fois
à l'enregistrement et à la reconnaissance vocale avant Android 13. Trois choix :

1. **Forme d'onde seule sur tous les Android** (recommandé pour le 6/11) : le
   plus simple et le plus sûr ; le texte du serveur arrive comme aujourd'hui.
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
