# MemoBook Android — conventions

App Kotlin et Jetpack Compose, Android 8.0+ (API 26), cible API 36, compilée
contre l'API 37. **La jumelle de l'app iOS** : les mêmes écrans, le même
serveur, les mêmes comptes, les mêmes noms. Le portage et sa liste de parité
sont dans [`docs/android.md`](../docs/android.md).

## La règle de parité

**L'app iOS est la référence** tant que le portage n'est pas fini. Un écran,
un modèle, une règle se portent depuis leur fichier Swift, et **gardent son
nom** : `HomeView.swift` ↔ `HomeView.kt`, `TripSettingsModel` ↔
`TripSettingsModel`, `NotificationLink` ↔ `NotificationLink`. Un `grep` sur un
nom trouve les deux jumeaux. Seuls les sigles changent de casse, à la manière
de Kotlin : `APIConfiguration` → `ApiConfiguration`, `MemoBookAPI` →
`MemoBookApi`.

**Tout ce que `ios/CLAUDE.md` dit du produit vaut ici, tel quel** : l'architecture
(une vue dessine et ne navigue pas, un modèle reçoit ses dépendances, pas de
couche `Repository`), le design system (une seule source de tokens, un seul
bouton, ce qu'on ne peut pas faire pâlit sans se désactiver), le réseau (une
seule identification : la session), le cache, le hors-ligne et ses trois
règles, et « un choix de design ne s'arrête pas au dessin ». Ce fichier ne dit
que **ce qui change** côté Android. En cas de doute, lire la section iOS : la
réponse y est, et elle s'applique.

Un test iOS qui décrit une règle se porte avec elle, cas pour cas
(`APIConfigurationTests.swift` → `ApiConfigurationTest.kt`).

## Commandes

```bash
make build     # compile le Debug
make test      # tests de tous les modules, sur la JVM
make lint
make release   # le Release minifié par R8, que la CI compile aussi
make snapshots # réenregistre les captures de référence du design system
make assets    # réimporte le catalogue d'images d'iOS
make run       # installe et lance sur l'émulateur ou le téléphone branché
make doctor    # JDK, SDK, appareil, back-end
```

### Interrupteurs de lancement

Les arguments de lancement du simulateur iOS (`-previewSignedIn`…) sont ici
des **extras de l'intention**, lus par `MainActivity` en Debug seulement :

```bash
make run ARGS="--ez designCatalogue true"   # l'écran-catalogue du design system
```

Les interrupteurs d'iOS arrivent avec le bac à sable (phase A3), sous le même
nom.

Gradle demande un JDK 17 ou plus ; le `Makefile` prend celui de Homebrew
(`brew install openjdk@21`) quand le Java du Mac est plus ancien, et le SDK
d'Android Studio ou, à défaut, celui de Homebrew
(`brew install --cask android-commandlinetools`). Android Studio ouvre le
dossier `android/` tel quel.

Les versions — AGP, Kotlin, Compose, bibliothèques — sont toutes dans
`gradle/libs.versions.toml`, et Gradle lui-même dans le wrapper. Les monter se
fait dans une PR à elle, jamais au passage d'un lot.

## Configurations et secrets

**L'adresse de production est écrite une seule fois**, dans `gradle.properties`
(`memobook.productionApiBaseUrl`) — comme `ios/Config/Base.xcconfig`. Le build
Release la prend pour adresse ; le build Debug vise le Mac et la garde en
secours. Les deux arrivent dans le code par `BuildConfig`, que seule la cible
`app` lit.

**Un téléphone ne parle jamais à `localhost`, ni à `10.0.2.2`.** L'émulateur
joint le Mac à `10.0.2.2` : c'est l'adresse du Debug, l'équivalent du
`localhost` du simulateur iOS. Sur un téléphone, cette adresse ne mène nulle
part, et un APK est le même sur les deux — on ne peut pas trancher à la
compilation comme le fait `Debug.xcconfig`. C'est donc
`ApiConfiguration.effective(configured, productionFallback, runsInEmulator)` —
une fonction pure, testée — qui tranche à l'exécution : une boucle locale
(`10.0.2.2` en est une) est remplacée par la production hors de l'émulateur.

**Et l'émulateur marche toujours, back-end lancé ou non** : il vise le Mac
d'abord, la production en secours (`fallbackBaseUrl`), exactement comme le
simulateur. ⚠️ La production est aussi la base de développement
(`docs/debogage.md`, § 4).

Pour viser le Mac depuis un téléphone, `secrets.properties` (local, ignoré par
Git) pose son IP — modèle documenté : `secrets.example.properties`. Le HTTP en
clair n'est permis qu'au Debug (`src/debug/res/xml/network_security_config.xml`,
le `NSAllowsLocalNetworking` d'iOS).

**L'app n'a aucun secret**, comme sur iOS. Le client OAuth Android de Google
n'en est pas un. La clé de signature, elle, n'entre **jamais** dans le dépôt :
ni `*.jks`, ni `*.keystore`, ni `keystore.properties`, ni `google-services.json`
— la CI refuse une PR qui en versionne un.

## Modules

| Module | Jumeau iOS | Rôle |
|---|---|---|
| `:core` | `MemoBookCore` | modèles et règles pures. **JVM seule**, aucune dépendance : ses tests tournent sans Android |
| `:design` | `MemoBookDesign` | tokens, composants `Brand…`, polices et images de marque |
| `:networking` | `MemoBookNetworking` | client d'API, adresse, connectivité |
| `:recording` | `MemoBookRecording` | capture audio |
| `:payments` | `MemoBookPayments` | Google Play Billing et Stripe, isolés |
| `:feature` | `MemoBookFeature` | écrans, modèles, `AppDependencies`, `RootView` |
| `:app` | `ios/App` | volontairement mince : lit `BuildConfig`, assemble `AppDependencies` |

**La dépendance ne remonte jamais** : `core` ne dépend de rien ;
`networking`, `recording`, `payments` et `design` de `core` seulement ;
`feature` de tous. `settings.gradle.kts` les déclare dans cet ordre.

## Architecture

Les mots de `docs/vocabulaire.md` valent ici, avec leurs suffixes.

- **Une vue** est une fonction `@Composable` nommée `…View` ou `…Sheet`. Elle
  lit l'état de son modèle, appelle ses actions, annonce une intention. Elle
  ne trie pas, ne calcule pas, ne construit jamais un client d'API.
- **Un modèle d'écran** est un `ViewModel` qui expose son état en
  `StateFlow`. Il reçoit ses dépendances — une fonction-source d'abord, sinon
  `MemoBookApi`, sinon `AppDependencies` —, il ne les cherche pas.
- **`AppDependencies`** est le seul point d'assemblage : construit une fois par
  `MemoBookApplication`, descendu aux écrans. Pas de singleton, pas de Hilt.
- **`RootView`** traduit les intentions en destinations, comme sur iOS.
- Coroutines partout où iOS a `async/await`.

## Design system

**`Tokens.kt` est la recopie de `Tokens.swift`**, et la seule source côté
Android. Un token change ? Les deux fichiers changent dans la même PR.

- Les couleurs sont **fixes** : l'app ne suit pas le thème sombre du
  téléphone, et ses barres système restent claires sur le crème.
- **Pas de Material.** `:design` ne dépend que de Compose Foundation : la
  marque dessine chacune de ses surfaces, et chaque composant `Brand…` porté
  depuis iOS est **le** composant de son rôle. Un écran n'utilise jamais un
  composant Material, même « en attendant ».
- Les dp valent les pt d'iOS, et Figma fait foi (1 rem = 16). Seule exception
  voulue : la cible tactile minimale est de **48 dp** (44 pt sur iOS), la règle
  d'Android.
- Les tailles de texte sont en `sp` : elles suivent la taille de police du
  téléphone comme le Dynamic Type. Le motif « empiler ce qui est côte à côte
  aux grandes tailles » se porte avec le premier composant qui en a besoin.
- **Polices** : les mêmes fichiers que sur iOS, dans `design/src/main/res/font`,
  écrits par `python3 ios/Tools/make-brand-fonts.py` — jamais à la main.
  L'interligne Figma est dans les polices ; ne pas poser de `lineHeight`.
- **Images** : `make assets` recopie **le catalogue d'iOS**
  (`MemoBookAssets.xcassets`) dans `design/src/main/res-brand` — les SVG en
  VectorDrawables par le convertisseur d'Android Studio, les PNG et JPG à leur
  densité. Les scripts de `ios/Tools` ont déjà nommé et nettoyé chaque image :
  partir de leur sortie donne les mêmes images sous les mêmes noms
  (`IconPrinterDuo` → `R.drawable.icon_printer_duo`, `BrandImages["IconPrinterDuo"]`
  pour un nom qui arrive en texte). Ajouter une image : le script iOS, puis
  `make assets`. `res-brand/` n'appartient qu'au script ; ce qui est dessiné à
  la main vit dans `res/drawable` — le M (`brand_mark.xml`) et les symboles
  système d'iOS redessinés (`system_*.xml`), SF Symbols n'existant pas ici.
  ⚠️ aapt2 tronque sans rien dire un tracé de plus de 32 767 caractères, et
  l'écran qui l'affiche plante : l'import le signale, et `BrandImagesLoadTest`
  charge chaque image comme `painterResource` la charge.
- **`Modifier.border` dessine par-dessus le contenu**, pas dessous comme
  `strokeBorder` sur iOS : ce qui doit couper un contour (l'intitulé monté d'un
  champ) a besoin d'un contour dessiné derrière.

### Porter un composant

`BrandButton.kt` est le modèle. Le composant garde le nom et les paramètres de
son jumeau Swift ; ses types imbriqués vivent dans un `object` du même nom
(`BrandButton.Style`). Un `Binding` devient une valeur et son rappel, nommé
d'après elle (`isOn` / `onIsOnChange`) ; un `@ViewBuilder`, un emplacement
`@Composable`. Ce que SwiftUI donne et que Compose Foundation n'a pas est écrit
une fois : `Platform.kt` (`BrandText`, `scaled()` pour `@ScaledMetric`,
`isAccessibilityTextSize()`, `isReduceMotionEnabled()`, `brandShadow`,
`ActivitySpinner`) et `SwiftMotion.kt` (les ressorts `.smooth`, `.snappy`,
`.spring`, et l'appui `.plain`). Un composant qui ne peut pas être identique le
dit en une ligne, à l'endroit où il diffère.

`BrandNavigation` ne se porte pas : il rend sur iOS le glissé de retour qu'une
barre masquée emporte, et Android a son geste de retour. `StatusBadge` et
`EmptyStateView` non plus : seuls les écrans abandonnés d'iOS s'en servent.

### Captures de référence

Chaque `@Preview` de `:design` est aussi un test de capture (Roborazzi, rendu
par Robolectric en Pixel 7) : `make snapshots` écrit les images dans
`design/src/test/screenshots`, la CI les compare. Changer un composant, c'est
regarder ses nouvelles images **avant** de les commiter, et les poser à côté de
la preview Xcode du jumeau. Les previews privées comptent.

La comparaison tolère **1 % des pixels** (`MemoBookPreviewTester`) : les images
sont enregistrées sur un Mac, comparées sous Linux, et Robolectric n'y lisse pas
le texte tout à fait pareil (jusqu'à 0,5 % au premier passage de la CI). Deux dp
de marge en plus sur une pastille la font bien échouer.

## Vérification

Un écran n'est fini que vérifié sur trois axes : petit téléphone
(360 × 640 dp), grand (Pixel Pro), et taille de police à 200 % avec TalkBack.
Et **à côté de l'iPhone**, sur le même compte : c'est la parité qu'on vérifie,
pas seulement l'écran.
