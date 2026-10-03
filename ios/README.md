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

Dans le simulateur, l'app parle à `http://localhost:3000` si un back-end y écoute (`cd ../backend && npm run dev`),
et bascule sur la **production** au premier appel sinon — « Testing mode » marche dans les deux cas.
Sur un iPhone branché, un build Debug parle directement à la production : `localhost` y serait le téléphone
(voir `Config/Debug.xcconfig`, et `docs/deploiement.md` pour viser le Mac à la place).

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

Ils vivent dans `Modules/Sources/MemoBookFeature`, un dossier par écran ou par parcours
(`Home`, `Trip`, `Chat`, `TripSettings`, `Paywall`, `Profile`, `Order`…). Leurs noms, et
ce qu'ils désignent dans le code, sont dans [`docs/vocabulaire.md`](../docs/vocabulaire.md) ;
les règles qu'ils suivent et les tickets encore ouverts, dans
[`docs/ui-development.md`](../docs/ui-development.md).

## Design tokens

La palette et la typographie de la marque (Sora, crème, vert `#28654B`…) sont posées dans
`MemoBookDesign/Tokens.swift`, recopiées des variables Figma du fichier « MemoBook —
Product ». C'est la seule source dans le code : aucune couleur ni police n'est codée en dur
ailleurs. Les mesures sont en **rem** (1 rem = 16 pt) et Figma fait foi (règles R1 à R4 de
`docs/ui-development.md`). Les composants partagés, préfixés `Brand`, sont dans le même
module.

Les couleurs sont volontairement fixes : MemoBook est un carnet de papier crème, les
écrans forcent `.colorScheme(.light)`.
