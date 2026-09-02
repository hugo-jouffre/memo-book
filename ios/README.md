# Application iOS MemoBook

SwiftUI, iOS 17+, Swift 6 en concurrence stricte.

## Démarrer

**Xcode 26.6** — la version de référence du projet. Toute l'équipe reste dessus : une
toolchain plus ancienne ou plus récente change les règles de concurrence stricte, et le
code cesse de compiler chez l'un sans que l'autre s'en aperçoive. On en change ensemble,
en mettant cette ligne à jour.

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

> ### ⚠️ La palette n'est pas encore posée
>
> Les couleurs de l'app et des mises en page vont changer prochainement. En attendant,
> **aucun token de `MemoBookDesign/Tokens.swift` ne porte de couleur de marque** : ils
> pointent tous vers des couleurs système iOS, et chacun porte un `TODO(design)`.
>
> C'est délibéré. L'app est cohérente et utilisable, mais visiblement **non brandée** —
> impossible de confondre ces valeurs avec le design final, et on ne fige pas une palette
> qu'on sait déjà fausse.
>
> Les deux sources existantes se contredisent et sont toutes deux en sursis :
> `agents/design.md` fait de Carrot `#F86015` la seule couleur d'accent et exclut Forest
> Green de l'UI, là où `critique_design_memobook.md` (Drive) recommandait l'inverse. Rien
> n'a été tranché dans le code.
>
> **Le jour venu** : remplacer les valeurs de ce seul fichier, plus l'asset d'accent si
> besoin. Aucune couleur n'est codée en dur ailleurs dans l'app — c'est ce qui rend la
> bascule triviale.

Ce qui est en revanche déjà stable, parce que ça vient des conventions iOS et non d'un
choix de marque :

- marge horizontale unique de 20 pt, espacements verticaux sur une échelle de 8 pt ;
- cibles tactiles de 44 pt minimum ;
- serif pour les titres de **carnet**, jamais pour le chrome système — un carnet ne se lit
  pas comme une barre de navigation ;
- SF Symbols en trait fin, pas de rendu 3D.

Les typographies sont elles aussi provisoires : le README du dépôt les liste comme « à
documenter dès qu'elles sont figées en Phase 2/3 ». Tout passe pour l'instant par les
styles système, ce qui donne Dynamic Type et accessibilité gratuitement.

## Ce qui n'est pas encore là

Pas d'authentification utilisateur (l'app s'enregistre comme un appareil anonyme), pas de
wizard d'onboarding, pas d'écran de chat, pas de paiement. Ces écrans dépendent d'arbitrages
Figma encore ouverts — notamment l'unification des deux versions de l'accueil.
