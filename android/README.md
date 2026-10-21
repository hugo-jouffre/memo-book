# Application Android MemoBook

Kotlin et Jetpack Compose, Android 8.0+ (API 26). La jumelle de l'app iOS :
mêmes écrans, même serveur, mêmes comptes. Où en est le portage :
[`docs/android.md`](../docs/android.md).

## Démarrer

Un JDK 17 ou plus et le SDK Android. Android Studio fournit les deux ; sans
lui :

```bash
brew install openjdk@21
brew install --cask android-commandlinetools
```

```bash
make build    # compile l'app
make test     # tests des modules, sur la JVM
make doctor   # vérifie JDK, SDK, appareil et back-end
```

Dans Android Studio : *Open* ▸ le dossier `android/`.

### Un émulateur sans Android Studio

Une image système (≈ 4 Go avec l'émulateur), un Pixel, et `make run` :

```bash
export SDKMANAGER_OPTS=-Djava.net.preferIPv4Stack=true
sdkmanager "emulator" "system-images;android-36;google_apis;arm64-v8a"
avdmanager create avd -n MemoBook_Pixel -k "system-images;android-36;google_apis;arm64-v8a" -d pixel_8
emulator -avd MemoBook_Pixel &
make run
```

Sans `preferIPv4Stack`, `sdkmanager` peut se traîner ou échouer sur
`dl.google.com` alors que le réseau répond — vu le 21/10/2026, où l'image n'a
téléchargé qu'une fois Java forcé sur IPv4. `emulator -no-window` le fait
tourner sans fenêtre ; `adb exec-out screencap -p > capture.png` en prend une
capture.

Pour regarder un écran au petit format et aux grandes polices sans créer un
second appareil :

```bash
adb shell wm size 720x1280 && adb shell wm density 320          # 360 × 640 dp
adb shell settings put system font_scale 2.0                    # texte à 200 %
adb shell wm size reset && adb shell wm density reset && adb shell settings put system font_scale 1.0
```

Dans l'émulateur, l'app parle à `http://10.0.2.2:3000` — le Mac — si un
back-end y écoute (`cd ../backend && npm run dev`), et bascule sur la
**production** sinon. Sur un téléphone branché, un build Debug parle
directement à la production ; pour viser le Mac, voir
`secrets.example.properties`.

## Structure

```
app/                Point d'entrée : Application, Activity, manifeste. Volontairement mince.
core/               Modèles et règles pures, JVM seule. Aucune dépendance.
design/             Tokens, composants Brand…, polices et images de marque.
networking/         Client d'API et adresse du serveur.
recording/          Capture audio.
payments/           Google Play Billing et Stripe.
feature/            Écrans Compose et leurs modèles.
gradle/             Catalogue des versions et wrapper.
```

Chaque module a son jumeau dans `ios/Modules/Sources`, et chaque fichier garde
le nom de son jumeau Swift. Les conventions sont dans [`CLAUDE.md`](CLAUDE.md).

## Design tokens

`design/src/main/kotlin/com/memobook/design/Tokens.kt` recopie
`MemoBookDesign/Tokens.swift` : les mêmes couleurs, les mêmes styles de texte,
les mêmes marges. Les polices sont les mêmes fichiers que sur iOS. L'app reste
claire quel que soit le thème du téléphone : MemoBook est un carnet de papier
crème.
