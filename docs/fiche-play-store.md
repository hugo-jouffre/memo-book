# La fiche Play Store et le formulaire « Sécurité des données »

Préparé le 23/10/2026 pour la première version publique d'Android
(`com.memobook.app`, 0.1.0). **Hugo saisit, Clara relit les textes.** Tout est
en français : l'app l'est. Les longueurs sont celles que la Play Console
compte (caractères, espaces compris).

Le pendant iOS est [`soumission-app-store.md`](soumission-app-store.md) : les
étiquettes de confidentialité d'App Store Connect disent la même chose que le
formulaire ci-dessous, avec d'autres cases.

## Décisions du 23/10/2026 (Hugo)

1. **La politique de confidentialité décrit l'app.** Réécrite dans les deux
   apps (`PrivacyPolicy.swift`, `PrivacyPolicy.kt`, un seul texte pour les
   deux stores) : comptes, récits, IA, commandes, abonnement, notifications,
   assistance, avec chaque prestataire. Clara la relit ; **memobook.fr doit
   publier le même texte avant l'envoi de la fiche à l'examen**, puisque la
   Console demande l'URL du site.
2. **L'adresse de la politique de confidentialité** : la page du site
   memobook.fr, une fois le nouveau texte publié. URL exacte à reporter
   ci-dessous par Hugo.
3. **Public cible : 16 ans et plus.** Cocher **16-17 ans** et **18 ans et
   plus**, rien en dessous : l'app reste hors du programme Familles. Les CGU
   (chapitre 3) et la politique (chapitre 8) disent désormais 16 ans, sur les
   deux apps.
4. **Contact public : `contact@memo-book.com`**, sur la fiche et dans les
   textes légaux (`LegalContact`, les deux apps).
5. **La position GPS des photos : plus tard.** Ce qui est déclaré ci-dessous
   (« Photos », pas de « Position ») reste vrai tant que le serveur ne lit pas
   les métadonnées EXIF (aucune lecture dans `backend/src`). Retirer la
   position côté app (`ExifInterface` avant l'envoi) reste un lot à part.

6. **Google dans les textes Android** (PR #149) : Google Commerce Limited vend
   l'abonnement, Google Ireland Limited fournit la connexion, FCM et Sheets ;
   un remboursement se demande à Google dans les 48 heures, à MemoBook
   au-delà.

### Reste à vérifier avant de saisir

- **L'identifiant publicitaire.** Aucun SDK de publicité ni d'analytique dans
  l'app. Répondre **Non** à « Votre app utilise-t-elle un identifiant
  publicitaire ? », après avoir vérifié que le manifeste fusionné du Release
  ne déclare pas `com.google.android.gms.permission.AD_ID`
  (`android/app/build/intermediates/merged_manifests/release/`).

## La fiche

### Nom de l'app (≤ 30)

> MemoBook : carnet de voyage

27 caractères.

### Description courte (≤ 80)

> Raconte ton voyage à voix haute : MEMO en fait un carnet illustré à imprimer.

77 caractères.

### Description complète (≤ 4 000)

> MemoBook transforme ton voyage en carnet illustré.
>
> Pendant le voyage, raconte tes journées à voix haute, écris quelques lignes ou ajoute tes photos. MEMO, ton compagnon de récit, t’écoute, te pose des questions et met chaque souvenir en page. À la fin, ton carnet de voyage est prêt : à feuilleter dans l’app, à partager, et à recevoir chez toi, imprimé.
>
> RACONTER, SIMPLEMENT
> • Un message vocal suffit : parle comme tu raconterais ta journée à un ami.
> • Tu préfères écrire ? Tape ton récit, MEMO s’en occupe aussi.
> • Ajoute tes photos depuis ton téléphone : elles trouvent leur place dans les pages.
> • Pas de réseau ? Raconte quand même : tout part dès que la connexion revient.
>
> VOYAGER À PLUSIEURS
> • Invite tes co-voyageurs avec un code ou un lien.
> • Chacun raconte depuis son téléphone, Android ou iPhone : tout se retrouve dans le même carnet.
>
> TON CARNET, À TON IMAGE
> • Choisis la couverture, le format, les typographies et les décorations.
> • Feuillette l’aperçu avant de commander.
> • Partage ton carnet en PDF, par lien ou sur WhatsApp.
>
> PRIX
> • L’app est gratuite : chaque voyage dispose de 5 minutes de récit par jour, à partager entre ses co-voyageurs non abonnés. Les photos ne comptent pas.
> • L’abonnement MemoBook, à 4,99 € par mois via Google Play, rend ton récit illimité. Il se résilie à tout moment dans le Play Store, et MemoBook te le rappelle quand ton voyage se termine.
> • Le carnet imprimé est vendu séparément, au moment de la commande.
>
> L’app est en français. Un compte MemoBook est nécessaire : tu retrouves tes voyages sur tous tes téléphones.

Environ 1 570 caractères. Chaque phrase dit une chose que l'app fait
aujourd'hui ; ce qui est « à venir » (Polarsteps, Tricount, connecteurs) n'y
est pas, Google refuse une fiche qui promet ce que l'app ne fait pas.

### Catégorie, coordonnées

| Champ | Valeur |
|---|---|
| Type | Application |
| Catégorie | Voyages et infos locales |
| Tags | carnet de voyage, journal, souvenirs (au choix de la Console) |
| Adresse e-mail | `contact@memo-book.com` (publique sur la fiche) |
| Site web | https://memobook.fr |
| Politique de confidentialité | la page de memobook.fr, une fois le nouveau texte publié (décision 2) |

### Notes de version 0.1.0

> Première version de MemoBook sur Android : raconte ton voyage par la voix, le texte et les photos, et retrouve-le dans un carnet illustré.

## Les images

### Icône et bannière

| Image | Format | D'où |
|---|---|---|
| Icône | PNG 512 × 512, 32 bits | l'icône adaptative de l'app (M crème sur vert), exportée à plat, sans coins arrondis : Google les ajoute |
| Bannière (feature graphic) | PNG ou JPEG 1024 × 500, sans transparence | à dessiner par Clara : le M, « MemoBook », un carnet ouvert. Pas de texte important près des bords : Google la recadre |

### Captures de téléphone

Six captures, en portrait, **1080 × 1920 au moins** (le minimum pour être mis
en avant est de quatre à 1080 px), sans cadre de téléphone. Elles se prennent
dans l'émulateur, sur le jeu d'essai : aucune donnée réelle, des voyages déjà
remplis.

Préparer l'émulateur une fois (barre d'état propre, 12:00, batterie pleine) :

```bash
adb shell settings put global sysui_demo_allowed 1
adb shell am broadcast -a com.android.systemui.demo -e command enter
adb shell am broadcast -a com.android.systemui.demo -e command clock -e hhmm 1200
adb shell am broadcast -a com.android.systemui.demo -e command battery -e level 100 -e plugged false
adb shell am broadcast -a com.android.systemui.demo -e command notifications -e visible false
```

Puis, pour chaque capture : `adb exec-out screencap -p > N.png`.

| # | Écran | Comment l'ouvrir (dans `android/`) | Ce qu'elle dit |
|---|---|---|---|
| 1 | L'accueil, avec ses voyages | `make run ARGS="--ez previewSignedIn true"` | Tous tes voyages au même endroit |
| 2 | La conversation avec MEMO : un vocal, une réponse, des photos | accueil ▸ un voyage en cours ▸ la conversation | Raconte, MEMO met en page |
| 3 | L'enregistrement, forme d'onde | depuis la conversation, le micro | Un vocal suffit |
| 4 | L'aperçu du carnet | `make run ARGS="--ez previewSignedIn true --ez composeBook true"`, attendre la fin de la composition | Ton carnet, page à page |
| 5 | Les couvertures | voyage ▸ réglages ▸ personnalisation ▸ couverture | À ton image |
| 6 | L'invitation des co-voyageurs (code d'accès) | accueil ▸ nouveau carnet ▸ jusqu'au code | Racontez à plusieurs |

Facultatif : la commande du carnet imprimé
(`make run ARGS="--ez previewSignedIn true --ez openOrder true"`). Pas de
paywall en capture : le prix est dans la description, et Google le lit mal
sur une image.

`adb shell am force-stop com.memobook.app` avant chaque `make run` : un extra
n'est lu qu'au lancement à froid.

## Le formulaire « Sécurité des données »

Déduit du code du 23/10/2026 : `android/core` (`Profile.kt`, `SupportMessage.kt`),
`android/networking` (`MemoBookApiClient.kt`), `android/feature` (`PhotoFlow`,
`notifications/FirebasePush.kt`), les dépendances de `android/*/build.gradle.kts`
et le serveur (`backend/src`). « Collectée » = envoyée hors du téléphone, au
serveur de MemoBook ou à un SDK de l'app.

### Les questions générales

| Question | Réponse | Pourquoi |
|---|---|---|
| L'app collecte-t-elle ou partage-t-elle des données parmi les types requis ? | **Oui** | |
| Toutes les données collectées sont-elles chiffrées en transit ? | **Oui** | HTTPS partout ; le HTTP en clair n'est permis qu'au Debug (`network_security_config.xml`) |
| Méthodes de création de compte | **Nom d'utilisateur et mot de passe** (e-mail) et **OAuth** (Google) | `AuthView`, Credential Manager |
| Les utilisateurs peuvent-ils demander la suppression de leurs données ? | **Oui** | Profil ▸ Supprimer mon compte, et la page web |
| URL de suppression du compte | `https://api-production-9f35a.up.railway.app/account/delete` | lot B6, suppression sous 30 jours |
| Suppression partielle (sans supprimer le compte) | **Oui** | supprimer un voyage ou une étape |
| Les données sont-elles partagées avec des tiers ? | **Non**, pour chaque type | les prestataires (Railway, S3, Anthropic, OpenAI, Resend, Stripe, Google FCM) traitent pour le compte de MemoBook : Google ne compte pas un prestataire comme un « partage ». Ils doivent figurer dans la politique de confidentialité (décision 1) |
| L'app suit-elle des engagements du programme Familles ? | Non | voir le public cible |

### Les types de données

Aucun traitement n'est « éphémère ». Les finalités sont celles de la Console :
fonctionnement de l'app, gestion du compte, communications du développeur,
personnalisation. Aucune donnée ne sert à la publicité, ni à l'analyse
d'audience, ni à la prévention de la fraude.

| Catégorie | Type | Collecté | Obligatoire ? | Finalités | Dans l'app |
|---|---|---|---|---|---|
| Informations personnelles | Nom | Oui | **Obligatoire** | Fonctionnement, gestion du compte | prénom et nom à l'inscription, nom du carnet |
| | Adresse e-mail | Oui | **Obligatoire** | Gestion du compte, fonctionnement, communications du développeur | identifiant ; e-mails de mot de passe, d'export, de rappel d'abonnement |
| | ID utilisateur | Oui | **Obligatoire** | Gestion du compte, fonctionnement | l'identifiant du compte, celui du compte Google |
| | Adresse | Oui | Facultatif | Fonctionnement | adresse postale du profil et de la commande, pour la livraison |
| | Numéro de téléphone | Oui | Facultatif | Fonctionnement, communications du développeur | les « Dernières questions » (WhatsApp), le suivi de commande |
| | Autres informations | Oui | Facultatif | Personnalisation | date de naissance (rappel d'anniversaire), genre (accords « Abonnée/Abonné ») |
| Informations financières | Informations de paiement | Oui | Facultatif | Fonctionnement | la carte saisie dans la feuille Stripe pour un carnet imprimé, et les cartes enregistrées (CustomerSheet) ; MemoBook ne la voit pas, Stripe la garde |
| | Historique des achats | Oui | Facultatif | Fonctionnement, gestion du compte | l'abonnement (jeton Google Play, statut, dates) et les commandes de carnets |
| Photos et vidéos | Photos | Oui | Facultatif | Fonctionnement | photos du récit, photo de profil |
| Fichiers audio | Enregistrements vocaux ou sonores | Oui | Facultatif | Fonctionnement | les vocaux, transcrits par le serveur |
| Messages | Autres messages dans l'app | Oui | Facultatif | Fonctionnement | la conversation avec MEMO, les messages au support |
| Activité dans l'app | Interactions avec l'app | Oui | **Obligatoire** | Fonctionnement | le compteur du crédit du jour (secondes et caractères par voyage et par jour) |
| | Autres contenus générés par l'utilisateur | Oui | Facultatif | Fonctionnement | voyages, souvenirs, fiches, réglages et personnalisation du carnet |
| Infos et performances de l'app | Diagnostics | Oui | Facultatif | Fonctionnement | modèle du téléphone, version d'Android et de l'app, joints à un message au support |
| Identifiants de l'appareil ou autres | Identifiants de l'appareil ou autres | Oui | **Obligatoire** | Fonctionnement | le jeton d'appareil (`POST /v1/devices`) et le jeton Firebase Cloud Messaging des notifications |

**Ce qui n'est pas collecté** : position (approximative ou précise ; la
destination d'un voyage est un texte tapé, voir aussi la décision 5),
contacts, agenda, santé et forme, historique de navigation, historique des
recherches, applications installées, fichiers et documents, vidéos, musique,
journaux de plantage (aucun SDK de rapport de plantage), identifiant
publicitaire.

## Le reste de la Console

| Section | Réponse |
|---|---|
| Accès à l'app | Connexion requise : le compte gratuit **`demo@memo-book.com`**, avec le mot de passe des comptes de test (`TEST_PASSWORD`, `backend/prisma/seed.ts`), à ne pas écrire ici. Mêmes notes qu'App Review, la fin adaptée : l'abonnement se teste avec un testeur de licence, et « Résilier » ouvre la page des abonnements du Play Store |
| Annonces | Non, l'app ne contient pas d'annonces |
| Classification du contenu (IARC) | Catégorie « Toutes les autres apps ». Aucune violence, sexualité, langage grossier, substance, jeu d'argent. **Interactions entre utilisateurs : oui** (les co-voyageurs d'un même voyage voient ce que chacun raconte). Pas de partage de position. Achats numériques : oui (l'abonnement) |
| Public cible | **16-17 ans** et **18 ans et plus** (décision 3) ; l'app n'est pas conçue pour les enfants |
| App d'actualités, app gouvernementale, fonctionnalités financières, santé | Non |
| Déclaration sur les autorisations | `RECORD_AUDIO` (les vocaux), `POST_NOTIFICATIONS` : aucune n'est sensible au sens de Google. Pas d'accès à la photothèque : le sélecteur de photos du système n'en demande pas |

## Ce qui reste à vérifier sur un vrai téléphone

- Le parcours décrit à l'équipe d'examen, de bout en bout, depuis la piste
  interne : connexion, un vocal, une photo, l'aperçu, « Résilier » qui ouvre
  le Play Store.
- Une photo prise par l'appareil photo depuis l'app : ses métadonnées de
  position arrivent-elles sur le serveur (décision 5) ?
- Les captures elles-mêmes, une fois prises dans l'émulateur : les regarder à
  côté de l'iPhone avant de les envoyer.
