# Application iOS MemoBook

SwiftUI, iOS 17+, Swift 6 en concurrence stricte.

## Démarrer

```bash
brew install xcodegen     # une seule fois
make project              # génère MemoBook.xcodeproj depuis project.yml
open MemoBook.xcodeproj
```

Le `.xcodeproj` **n'est pas versionné** : `project.yml` en est la source. Ça évite les
conflits Git sur le pbxproj et rend la structure du projet lisible en revue de code.

L'app parle par défaut à `http://localhost:3000` — lance `cd ../backend && npm run dev` avant.

```bash
make test                 # tests des modules, sur simulateur
make build                # compile l'app
```

## Structure

```
App/                      Point d'entrée : @main, Info.plist, assets. Volontairement mince.
Modules/                  Le vrai code, en paquet SwiftPM local « MemoBookKit »
├── MemoBookCore          Modèles et décodage. Aucune dépendance.
├── MemoBookDesign        Design tokens et composants partagés.
├── MemoBookNetworking    Client d'API, stockage du token, multipart.
├── MemoBookRecording     Capture audio (AVFoundation) et permissions.
└── MemoBookFeature       Écrans SwiftUI et modèles de vue.
Tests/                    Tests de la cible app (l'essentiel est dans Modules/Tests).
```

Les modèles de vue dépendent du protocole `MemoBookAPI`, pas du client HTTP : `PreviewAPI`
(dans `MemoBookFeature`) en fournit une implémentation en mémoire, ce qui permet de
travailler les écrans et de les tester sans back-end lancé.

## Les écrans

**Entrer dans l'app** — `MemoBookFeature/Onboarding/`, huit écrans qui forment un seul
parcours. `OnboardingModel` en est le pilote : c'est lui qui, au lancement, décide entre
les carnets (session valide), le *Welcome* (premier lancement) et la connexion.

1. **`SplashView`** — le logo pendant la restauration de session. Plancher 0,8 s pour ne
   pas clignoter, plafond 5 s pour ne coincer personne devant un réseau mort.
2. **`WelcomeView`** — la promesse produit en trois cartes, puis l'inscription.
3. **`CredentialsView`** — *Sign Up* et *Login* : **un seul écran à deux onglets**, comme
   le demande le détail fonctionnel. Basculer ne navigue pas et n'efface pas la saisie.
4. **`ForgotPasswordView`**, **`ForgotPasswordNoAccountView`**, **`ResetPasswordView`** —
   les trois écrans de mot de passe. Le dernier n'est atteignable que par le deep link
   `memobook://reset-password?token=…`.
5. **`CompleteProfileView`** — après une connexion tierce sur un compte inconnu. Un compte
   n'est jamais créé en silence.

**Le cœur produit**

6. **`MemoListView`** — les carnets, bouton `+` en position fixe en haut à droite.
7. **`MemoDetailView`** — l'écran central : le bouton d'enregistrement, la waveform, les
   souvenirs avec leur statut de transcription, et la carte de génération du carnet.
8. **`BookPreviewView`** — le PDF, dans QuickLook.

Les règles d'implémentation depuis Figma, et la fiche de chaque écran, sont dans
[`docs/ui-development.md`](../docs/ui-development.md). À lire en entier avant de toucher
au premier pixel.

## Design tokens

La palette est posée. `MemoBookDesign/Tokens.swift` recopie les variables du fichier
Figma, telles que les **écrans** les résolvent — pas telles que la page *Design System*
les affiche, qui est encore sur le mode par défaut du template acheté.

- **Green** `#28654B` porte l'action · **Blue** `#AFD2F0` est l'accent illustratif de
  l'onboarding · **Beige** `#FCF2E9` est le fond · **White** `#FFFCF8` les surfaces ·
  **Black** `#2D231A` le texte. Carrot, Forest Green et Kiwi n'existent plus.
- Le miroir de référence reste [`agents/design.md`](../agents/design.md) ; en cas d'écart,
  la valeur lue sur le nœud Figma gagne.
- **Aucune couleur en dur dans une vue.** Si un token manque, il s'ajoute à
  `MemoBookDesign` d'abord, la vue s'écrit ensuite.

### L'unité : le rem

Tout se mesure en **rem** — 1 rem = 16 pt, la racine typographique de Figma. `Rem.swift`
est le seul endroit de l'app où un point apparaît :

- **structure fixe** (marges, gouttières, rayons) → `rem(1.5)` ;
- **ce qui suit le texte** (hauteur de bouton et de champ, icône accolée à du texte, cible
  tactile) → `@ScaledMetric` sur `MemoBookMetric.unit`.

La marge horizontale est de **1 rem sur tous les écrans, sans exception**.

### Ce qui manque encore

> ⚠️ **Les visuels et les polices ne sont pas encore dans le dépôt.**
>
> `FigmaAsset` tient la liste des exports attendus avec leur nœud d'origine ; tant qu'un
> fichier manque, `FigmaImage` affiche une **réserve neutre à la bonne taille**. Jamais un
> SF Symbol de remplacement : un placeholder qui ressemble à l'icône finale, personne ne
> le remplace jamais.
>
> Sora et General Sans ne sont pas embarquées : `Font.custom` retombe sur la police
> système. Les tailles, graisses et approches sont déjà justes.
>
> La procédure des deux : [`docs/figma-assets.md`](../docs/figma-assets.md).

### Mode sombre

Hors périmètre pour l'instant. `Scheme/Background Dark` existe dans Figma, mais aucun
écran ne le décline : les tokens portent des valeurs fixes, et l'app garde son apparence
claire quel que soit le réglage du téléphone. Le jour où Clara dessine les écrans en
sombre, la bascule s'écrit dans `Tokens.swift` et nulle part ailleurs.

### Les conventions qui ne bougent pas

- cibles tactiles de **2.75 rem** (44 pt) minimum, même quand le visuel est plus petit ;
- **Dynamic Type partout** : chaque style de texte se déclare avec `relativeTo:`, jamais
  en taille fixe ;
- serif pour les titres de **carnet**, jamais pour le chrome système — un carnet ne se lit
  pas comme une barre de navigation ;
- les traits (bordures, séparateurs) restent en points : un filet ne grossit pas avec le
  texte.

## Comptes et sessions

L'app porte désormais deux jetons, tous deux au trousseau :

- le **jeton d'appareil**, obtenu au premier lancement (`POST /v1/devices`) ;
- le **jeton de session**, obtenu à l'inscription ou à la connexion.

Dès qu'une session existe, c'est elle qui parle à l'API : `MemoBookAPIClient` la
privilégie sur le jeton d'appareil. À l'inscription, le jeton d'appareil part avec la
requête — c'est ce qui fait suivre dans le compte les carnets déjà enregistrés en
anonyme.

Le flag `has_seen_onboarding` vit dans `UserDefaults` (ce n'est pas un secret) et remonte
au serveur à la première connexion, qui le renvoie ensuite : une désinstallation puis
réinstallation ne repropose pas le *Welcome* à quelqu'un qui a déjà un compte.

## Ce qui n'est pas encore là

Pas d'écran de chat, pas de paiement, pas de réglages — donc **pas encore de suppression
de compte**, obligatoire pour la revue App Store (guideline 5.1.1) : à écrire avec le lot
Réglages.

Les trois boutons de connexion tierce répondent qu'ils ne sont pas disponibles :
`SocialSignInBroker` attend l'intégration d'`AuthenticationServices` et des SDK Google et
Facebook, qui demandent les identifiants de client des trois fournisseurs. Sign in with
Apple est **obligatoire** dès qu'un login social tiers est proposé (App Store 4.8) : les
trois arrivent ensemble, ou aucun.
