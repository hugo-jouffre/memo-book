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

## Les trois écrans

1. **`MemoListView`** — les carnets, bouton `+` en position fixe en haut à droite.
2. **`MemoDetailView`** — l'écran central : le bouton d'enregistrement, la waveform, les
   souvenirs avec leur statut de transcription, et la carte de génération du carnet.
3. **`BookPreviewView`** — le PDF, dans QuickLook.

## Design tokens

> ### ⚠️ La palette est tranchée, le code ne l'a pas encore
>
> Les couleurs de l'app sont désormais figées sur les variables Figma, recopiées dans
> [`agents/design.md`](../agents/design.md) : Green `#28654B` porte l'action, Blue
> `#AFD2F0` les accents d'onboarding, Beige `#FCF2E9` le fond, Black `#2D231A` le texte.
> Carrot et Forest Green n'existent plus.
>
> **Mais `MemoBookDesign/Tokens.swift` pointe encore vers des couleurs système iOS**, avec
> un `TODO(design)` sur chaque token. L'app est donc cohérente et utilisable, mais
> visiblement **non brandée** — impossible de confondre ces valeurs avec le design final.
>
> **Prochaine étape** : remplacer les valeurs de ce seul fichier, plus l'asset d'accent si
> besoin. Aucune couleur n'est codée en dur ailleurs dans l'app — c'est ce qui rend la
> bascule triviale.

Les règles de mise en page, elles, sont posées — voir
[`docs/ui-development.md`](../docs/ui-development.md) pour la méthode complète :

- **toutes les dimensions s'expriment en rem** (1 rem = 16 pt), l'unité étant définie
  dans `MemoBookDesign` puisque SwiftUI ne la connaît pas ;
- **marge horizontale unique de 1 rem (16 pt)** sur tous les écrans — `MemoBookSpacing`
  est encore sur 20 pt, à corriger avec les couleurs ;
- espacements verticaux sur l'échelle de 8 pt ;
- cibles tactiles de 44 pt minimum ;
- **Sora** pour les titres, **General Sans** pour le reste — les deux fichiers de police
  restent à embarquer (`UIAppFonts`) ; en attendant tout passe par les styles système, ce
  qui donne Dynamic Type et accessibilité gratuitement ;
- serif pour les titres de **carnet**, jamais pour le chrome système — un carnet ne se lit
  pas comme une barre de navigation ;
- SF Symbols en trait fin, pas de rendu 3D.

## Ce qui n'est pas encore là

Pas d'authentification utilisateur (l'app s'enregistre comme un appareil anonyme), pas de
wizard d'onboarding, pas d'écran de chat, pas de paiement. Ces écrans dépendent d'arbitrages
Figma encore ouverts — notamment l'unification des deux versions de l'accueil.
