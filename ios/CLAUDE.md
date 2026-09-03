# MemoBook iOS — conventions

App SwiftUI, iOS 17+, Swift 6 (concurrence stricte). Le code vit dans le paquet
`Modules/`, pas dans la cible Xcode. Le `.xcodeproj` **n'est pas versionné** :
il se régénère depuis `project.yml`.

## Commandes

```bash
make project   # après toute modif de project.yml, ou au premier clone
make build
make test      # modules + cible app
```

Lancer dans le simulateur : construire, puis `xcrun simctl install <device> <.app>`
et `xcrun simctl launch <device> com.memobook.app`. Pour retomber sur l'écran
d'accueil, `xcrun simctl uninstall` d'abord — il est gardé par un `@AppStorage`.

## Modules

| Module | Rôle |
|---|---|
| `MemoBookCore` | modèles, aucune dépendance |
| `MemoBookDesign` | tokens, composants, **et les ressources de marque** |
| `MemoBookNetworking` | client API |
| `MemoBookRecording` | capture audio |
| `MemoBookFeature` | écrans et leurs modèles |

## Design system

**`Tokens.swift` est la seule source de vérité.** Aucune couleur, taille de
police ou marge codée en dur ailleurs.

- `MemoBookSpacing.screenMargin` est **la** marge latérale de l'app. Tout ce qui
  touche le bord d'un écran s'aligne dessus. Un écran ne définit jamais sa
  propre marge.
- Les couleurs sont **fixes**, pas adaptatives : la marque est un papier crème,
  elle ne se retourne pas en sombre. Les écrans forcent `.colorScheme(.light)`.
- `BrandButton` est **le** bouton (styles primary / secondary / tertiary / link,
  tailles regular / small, `alternate` pour les fonds sombres). Ne pas en
  écrire d'autre.
- `BrandTextField` est **le** champ de saisie, `BrandSegmentedPicker` **le**
  sélecteur à segments, `BrandBackdrop` le motif de fond. Même règle.
- Le focus appartient à l'écran, pas au champ : un `@FocusState` sur une énum
  passé aux `BrandTextField`, pour que le clavier enchaîne les champs.

### Aux tailles de texte accessibles

Tout composant qui pose deux choses côte à côte doit savoir les empiler. Le
motif est toujours le même :

```swift
@Environment(\.dynamicTypeSize) private var typeSize
// puis : if typeSize.isAccessibilitySize { VStack … } else { HStack … }
```

C'est déjà le cas de `BrandSegmentedPicker`, `WelcomeStepCard` et des champs
prénom/nom. Chaque nouveau composant en colonnes doit le faire aussi.

### Polices

Sora et General Sans sont embarquées comme instances **statiques générées**, pas
comme les fichiers variables du dépôt :

```bash
python3 ios/Tools/make-brand-fonts.py
```

Ne jamais éditer les `.ttf` de `MemoBookDesign/Resources/Fonts` à la main.
Le script fige aussi les interlignes Figma dans les métriques, parce que
`lineSpacing` de SwiftUI ne sait qu'**ajouter** de l'air — un interligne plus
serré que la police ne peut pas se rattraper côté code.

### Images

SVG dans `MemoBookDesign/Resources/MemoBookAssets.xcassets`, avec
`preserves-vector-representation`. On y accède par `Image(brand: "NomAsset")`.
Retirer `preserveAspectRatio="none"` des exports Figma, sinon Xcode déforme.

## Réseau

**Aucun appel réseau ne bloque le démarrage.** L'enregistrement de l'appareil est
paresseux : `AppDependencies.ensureRegistered()` est appelé par le modèle qui en
a besoin, et son échec est l'erreur de cet écran-là (un `ErrorBanner` en ligne),
jamais un mur devant l'app.

## Figma

Le MCP Figma est **cher et rationné** (quota atteint en ~3 appels sur le plan
Starter). Donc :

- un seul `get_design_context` par écran, sur le nœud le plus haut qui suffit ;
- `get_variable_defs` pour les tokens : réponse minuscule, à privilégier quand
  seules les couleurs ou les typos manquent ;
- `get_metadata` pour vérifier une largeur ou une hiérarchie, jamais
  `get_design_context` ;
- ne **pas** relancer un appel après une modif de maquette si l'intention est
  décrite en français dans la demande — l'appliquer directement.

Le code renvoyé est du React/Tailwind de **référence**, à traduire, jamais à
transposer littéralement : les positions absolues et largeurs fixes des
maquettes doivent devenir des layouts fluides.

## Vérification

Un écran n'est fini que vérifié en simulateur sur trois axes :
petit écran (SE 3e gén., 375 × 667), grand (17 Pro Max), et Dynamic Type
accessible (`xcrun simctl ui <device> content_size accessibility-extra-extra-extra-large`).
C'est là que se voient les débordements, les textes rognés et les cibles
tactiles perdues.
