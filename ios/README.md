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

`MemoBookDesign/Tokens.swift` porte la palette de marque, recopiée de
[`agents/design.md`](../agents/design.md), qui recopie lui-même les variables Figma. Aucune
couleur, aucune dimension n'est codée en dur ailleurs dans l'app.

La méthode complète est dans [`docs/ui-development.md`](../docs/ui-development.md) ; les
règles qui touchent au code :

- **toutes les dimensions s'expriment en rem** (1 rem = 16 pt). L'unité est définie dans
  `Rem.swift` puisque SwiftUI ne la connaît pas, et c'est le seul fichier de l'app où un
  point apparaît. Structure fixe : `rem(1.5)`. Contrôle qui suit le texte :
  `@ScaledMetric(relativeTo: .body) var unit = Rem.base`, puis `unit * 3` ;
- **marge horizontale unique de 1 rem** sur tous les écrans (`MemoBookSpacing.screenMargin`) ;
- hauteur de bouton et de champ à 3 rem, cible tactile à 2.75 rem minimum ;
- une seule exception au rem : les **traits** restent en points (`Rem.hairline`) — un filet
  ne grossit pas avec le texte ;
- **Sora** pour les titres, **General Sans** pour le reste (voir *Polices* ci-dessous) ;
- serif pour les titres de **carnet**, jamais pour le chrome système — un carnet ne se lit
  pas comme une barre de navigation ;
- SF Symbols en trait fin, pas de rendu 3D.

> **Ce qui reste à brander** : seul `MemoDetailView` pose explicitement le fond de marque.
> L'accueil est encore sur le fond système d'une `List` — à reprendre quand ses maquettes
> arriveront, pas au coup par coup.

## Polices

Les fichiers **ne sont pas encore dans le dépôt**. Tant qu'ils manquent, `Font.custom`
retombe silencieusement sur la police système : la mise en page reste juste, seul le dessin
des lettres diffère.

Pour les activer :

1. vérifier la licence d'embarquement dans une app — Sora est sous OFL (Google Fonts),
   General Sans vient de Fontshare et a sa propre licence, **à lire avant de publier** ;
2. déposer les fichiers dans `App/Resources/Fonts/` ;
3. décommenter le bloc `UIAppFonts` de `project.yml`, puis `make project` ;
4. vérifier les noms PostScript réels (Livre des polices sur macOS) et les aligner sur
   `MemoBookFont.Family` — un nom faux ne casse rien, il retombe simplement sur le système.

## Ce qui n'est pas encore là

Pas d'authentification utilisateur (l'app s'enregistre comme un appareil anonyme), pas de
wizard d'onboarding, pas d'écran de chat, pas de paiement. Ces écrans dépendent d'arbitrages
Figma encore ouverts — notamment l'unification des deux versions de l'accueil.
