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
