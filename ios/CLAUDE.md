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
et `xcrun simctl launch <device> com.memobook.app`.

### Revoir l'écran d'accueil

Un ⌘R réinstalle **par-dessus** sans toucher au conteneur : l'écran d'accueil,
gardé par un `@AppStorage`, ne revient donc pas tout seul. Pour repartir du
premier démarrage, cocher `-resetOnboarding` dans *Product ▸ Scheme ▸ Edit
Scheme ▸ Run ▸ Arguments*, ou :

```bash
xcrun simctl launch <device> com.memobook.app -resetOnboarding
```

Voir `OnboardingStorage`. Sans effet en release.

### Vérifier un écran sans back-end

Réinstaller l'app efface son conteneur, donc le trousseau, donc la session : il
faut alors un back-end debout et une connexion à refaire pour regarder un coin
arrondi. D'où cet interrupteur, qui ouvre l'app directement sur l'accueil avec
le jeu d'essai :

```bash
xcrun simctl launch <device> com.memobook.app -previewSignedIn
```

Il n'ouvre **aucun accès** : le compte est local, aucun jeton n'est écrit, et
tout appel réseau échoue comme il le doit. Sans effet en release.

⚠️ Ne **jamais** poser un réglage de test avec
`xcrun simctl spawn <device> defaults write com.memobook.app …` : ça écrit dans
un domaine au niveau de l'appareil que l'app lit aussi, mais que son propre
`UserDefaults` ne peut pas effacer. On croit alors à un bug de l'app. Passer par
l'interface, ou par `-resetOnboarding`.

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
- `BrandButton` est **le** bouton (styles primary / secondary / tertiary / soft /
  accent / destructive / link, tailles regular / small, `alternate` pour les
  fonds sombres). Ne pas en écrire d'autre. `destructive` porte le rouge
  sémantique sans fond ni contour — c'est l'action qui défait, jamais un
  `link` ; `accent` est le seul aplat large que porte le lime.
- `BrandTextField` est **le** champ de saisie (deux mises en page :
  `labelPlacement: .floating` pour les formulaires d'entrée, `.above` pour les
  feuilles), `BrandSegmentedPicker` **le** sélecteur à segments, `BrandBackdrop`
  le motif de fond. Même règle.
- `BrandRowGroup` est **le** motif « lignes empilées et groupées » des écrans de
  réglages : une ligne se *décrit* (`BrandRow`), elle ne se dessine pas.
  `BrandOptionGroup` est **le** choix unique en lignes encadrées, et `BrandSheet`
  **la** feuille modale — geste du système, dessin de la marque, hauteur calée
  sur le contenu. Son en-tête accepte une pastille (`badge:`) et un chapeau en
  plusieurs paragraphes (`paragraphs:`).
- **Un enchaînement de feuilles ne s'empile pas.** Une confirmation en plusieurs
  temps se fait dans **une seule** `BrandSheet` dont le contenu change (voir
  `SubscriptionSheet`) : chaque feuille ouverte par-dessus une autre fait
  reculer celle du dessous, et trois reculs de suite se lisent comme un
  empilement de fenêtres au lieu d'un chemin.
- Le focus appartient à l'écran, pas au champ : un `@FocusState` sur une énum
  passé aux `BrandTextField`, pour que le clavier enchaîne les champs.
- `BrandChatBubble` est **la** bulle de conversation (fond, queue, marges,
  largeur maximale), `BrandWaveform` **la** forme d'onde — celle du micro en
  direct comme celle d'un vocal terminé —, et `BrandSkeleton` +
  `brandSkeletonShimmer()` **le** chargement en blocs gris. `brandShadow(_:)`
  pose l'une des deux ombres nommées de la marque, et il n'y en aura pas de
  troisième.

### Une `ScrollView` dans une barre doit se voir imposer sa hauteur

Elle est gourmande sur ses deux axes. Posée dans une barre d'outils, elle se
fait attribuer une hauteur plus courte que son contenu ; avec
`scrollClipDisabled()`, celui-ci reste **dessiné** mais tombe hors de sa zone
tactile — on le voit, et taper dessus ne fait rien. Le rail de suggestions du
chat s'y est pris deux fois. Même piège pour un `overlay` décalé hors du cadre
de la vue qui le porte : dessiné, jamais tapable.

### La durée d'un enregistrement ne se lit pas à l'horloge

`AudioRecorder` sait se mettre en pause. Dès lors, « maintenant moins le début »
est faux : `recordedBeforePause` porte le temps réellement capturé, et
`startedAt` ne date plus que la reprise. Toute lecture de durée passe par
`capturedDuration`.

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
