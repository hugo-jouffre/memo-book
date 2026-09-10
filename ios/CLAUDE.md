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

## Configurations et secrets

Ce qui change d'un environnement à l'autre vit dans `Config/*.xcconfig`, jamais
dans le code : l'URL de l'API et le client OAuth Google. `Base.xcconfig` porte
le commun, `Debug` le back-end local, `Release` la production.

Les valeurs traversent par l'**Info.plist** (`MemoBookAPIBaseURL`), seul chemin
par lequel un réglage de build devient lisible à l'exécution. Côté Swift,
`APIConfiguration.fromBundle()` la lit et `fromBuildConfiguration` décide de
l'absence : repli local en debug, arrêt net en release — un build livré ne doit
pas parler à `localhost` en silence, ce qu'il faisait avant.

⚠️ Dans un `.xcconfig`, `//` ouvre un commentaire **au milieu d'une URL aussi**.
On coupe la séquence avec `$()` : `https:/$()/api.memo-book.com`. Le piège ne se
voit qu'à l'exécution.

**L'app n'a aucun secret**, et c'est l'architecture qui le veut : tout ce qui
coûte de l'argent ou ouvre un compte vit derrière l'API. Le client Google iOS
n'en est pas un — il part dans chaque binaire. `Config/Secrets.example.xcconfig`
est versionné et documente le fichier local `Config/Secrets.xcconfig`, ignoré
par Git, inclus par `#include?` (donc son absence ne casse rien) : c'est là
qu'on pointe l'app sur l'IP de son Mac pour tester sur un iPhone physique.

La CI (`.github/workflows/ci-ios.yml`) régénère le projet depuis `project.yml`,
compile, lance les deux suites de tests, et refuse un `Secrets.xcconfig`
versionné.

## Modules

| Module | Rôle |
|---|---|
| `MemoBookCore` | modèles, aucune dépendance |
| `MemoBookDesign` | tokens, composants, **et les ressources de marque** |
| `MemoBookNetworking` | client API |
| `MemoBookRecording` | capture audio |
| `MemoBookFeature` | écrans et leurs modèles |

## Architecture

MVVM avec `@Observable`, `async/await` partout, aucun singleton. Le document
complet est dans Notion (« Document d'architecture SwiftUI + MVVM ») ; voici ce
qui engage le code.

**La dépendance ne remonte jamais.** `MemoBookCore` ne dépend de rien.
`Networking`, `Recording` et `Design` ne dépendent que de `Core`. `Feature`
dépend des quatre. Une vue ne construit jamais un client d'API et ne fabrique
jamais une `URLRequest`.

**Une vue ne fait que dessiner, et ne navigue pas.** Elle lit l'état de son
modèle, appelle ses actions, et annonce une intention (`HomeIntent`) que
`RootView` traduit en destination. Aucun tri, aucun calcul dans un `body` :
`HomeModel` range ses trois listes **une fois**, à la réception — trier dans une
vue, c'est trier à chaque image d'animation.

**Un modèle d'écran reçoit ses dépendances, il ne les cherche pas.** Trois
formes, dans cet ordre de préférence :

1. **Une fonction-source** — `HomeModel`, `TripHomeModel`, `ProfileModel`
   reçoivent une fonction qui rend leur contenu (et, pour le profil, une qui
   l'écrit). Ils ne connaissent même pas `MemoBookAPI`. L'app y branche la
   route, les aperçus n'en fournissent aucune et tombent sur le jeu d'essai :
   c'est ce qui montre les quatre états d'un écran sans serveur ni double.
2. **`any MemoBookAPI`** quand l'écran appelle trop de routes pour qu'une liste
   de fonctions reste lisible (`MemoDetailModel`, `AuthModel`).
3. **`AppDependencies`** quand il faut aussi `ensureRegistered()`
   (`MemoListModel`).

`AppDependencies` est le seul point d'assemblage, descendu par
`.environment(…)`. Pas de singleton.

**Il n'y a pas de couche `Repository`, et c'est voulu.** Le protocole
`MemoBookAPI` *est* le contrat qu'on double en test et en aperçu. Une seconde
interface au-dessus serait à réécrire à chaque champ ajouté pour le même
service.

Le mode hors-ligne est arrivé — c'était le cas qui devait la justifier — et il
ne l'a pas demandée : le cache **enveloppe la fonction-source** au lieu de
s'intercaler sous le protocole (`AppDependencies.homeModel()` recopie ce qui
arrive et relit ce qu'il a en cas de panne de transport), et la file des vocaux
est un objet à part, qui reçoit une fonction d'envoi. Ni l'écran ni le client
d'API n'ont bougé. Voir § Hors ligne.

**Les erreurs appartiennent à l'écran qui les provoque.** `APIError` et
`RecordingError` portent des messages déjà destinés à l'utilisateur — le
back-end renvoie ses libellés en français, on les réutilise plutôt que
d'afficher un code HTTP. Le modèle attrape et pose un `errorMessage`, la vue le
rend en `ErrorBanner` **en ligne**, jamais en plein écran. Voir aussi § Réseau.

**Un état inconnu ne casse pas le décodage.** `EntryStatus` a un cas
`unknown(String)` : un état ajouté côté serveur ne doit pas faire échouer tout
l'écran.

## Design system

**`Tokens.swift` est la seule source de vérité.** Aucune couleur, taille de
police ou marge codée en dur ailleurs.

- `MemoBookSpacing.screenMargin` est **la** marge latérale de l'app. Tout ce qui
  touche le bord d'un écran s'aligne dessus. Un écran ne définit jamais sa
  propre marge.
- Les couleurs sont **fixes**, pas adaptatives : la marque est un papier crème,
  elle ne se retourne pas en sombre. Les écrans forcent `.colorScheme(.light)`.
- `BrandButton` est **le** bouton (styles primary / secondary / tertiary / soft /
  raised / accent / blue / destructive / link, tailles regular / small,
  `alternate` pour les fonds sombres). Ne pas en écrire d'autre. `destructive`
  porte le rouge sémantique sans fond ni contour — c'est l'action qui défait,
  jamais un `link` ; `accent` est le seul aplat large que porte le lime.
- `BrandTextField` est **le** champ de saisie (trois mises en page :
  `labelPlacement: .floating` pour les formulaires d'entrée, `.above` pour les
  feuilles, `.hidden` pour le champ unique d'une feuille dont le sous-titre dit
  déjà quoi saisir), `BrandSegmentedPicker` **le** sélecteur à segments,
  `BrandBackdrop` le motif de fond. Même règle.
- `BrandRowGroup` est **le** motif « lignes empilées et groupées » des écrans de
  réglages : une ligne se *décrit* (`BrandRow`), elle ne se dessine pas.
  `BrandOptionGroup` est **le** choix unique en lignes encadrées, et `BrandSheet`
  **la** feuille modale — geste du système, dessin de la marque, hauteur calée
  sur le contenu, titre à gauche ou centré (`titleAlignment`), aplat papier ou
  bleu d'écoute (`surface`). Son en-tête accepte une pastille (`badge:`) et un
  chapeau en plusieurs paragraphes (`paragraphs:`).
- **Un enchaînement de feuilles ne s'empile pas.** Une confirmation en plusieurs
  temps se fait dans **une seule** `BrandSheet` dont le contenu change (voir
  `SubscriptionSheet`) : chaque feuille ouverte par-dessus une autre fait
  reculer celle du dessous, et trois reculs de suite se lisent comme un
  empilement de fenêtres au lieu d'un chemin.
- Le focus appartient à l'écran, pas au champ : un `@FocusState` sur une énum
  passé aux `BrandTextField`, pour que le clavier enchaîne les champs.
- `BrandChatBubble` est **la** bulle de conversation (fond, queue, marges,
  largeur maximale), `BrandWaveform` **la** forme d'onde — celle du micro en
  direct (`init(live:size:…)`, la grande feuille comme la barre du chat) comme
  celle d'un vocal terminé (`init(levels:progress:…)`) —, et `BrandSkeleton`
  **la** barre d'attente d'une valeur qui n'est pas encore arrivée. Elle ne
  remplace jamais un écran, seulement une valeur : la page se dessine tout de
  suite. `brandShadow(_:)` pose l'une des deux ombres nommées de la marque, et
  il n'y en aura pas de troisième.

### Une `ScrollView` dans une barre doit se voir imposer sa hauteur

Elle est gourmande sur ses deux axes. Posée dans une barre d'outils, elle se
fait attribuer une hauteur plus courte que son contenu ; avec
`scrollClipDisabled()`, celui-ci reste **dessiné** mais tombe hors de sa zone
tactile — on le voit, et taper dessus ne fait rien. Le rail de suggestions du
chat s'y est pris deux fois. Même piège pour un `overlay` décalé hors du cadre
de la vue qui le porte : dessiné, jamais tapable.

### La durée d'un enregistrement ne se lit pas à l'horloge

`AudioRecorder` sait se mettre en pause. Dès lors, « maintenant moins le début »
est faux, et **deux dates différentes cohabitent** : `openedAt` date l'ouverture
du vocal — c'est le `recordedAt` du fichier —, tandis que `accumulated` plus le
segment en cours donnent le temps **réellement capturé**, pauses déduites.
C'est cette seconde valeur que publie `elapsed`.

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

Le catalogue n'est **jamais rempli à la main** : deux scripts l'alimentent depuis
`assets/`, et ils sont idempotents.

```bash
python3 ios/Tools/import-brand-icons.py     # assets/icons/brand-icons
python3 ios/Tools/import-lucide-icons.py    # assets/icons/lucide-icons
```

Le second sert les **remplaçants** : les pictogrammes que le jeu de marque n'a
pas — les catégories de la galerie, le train du filtre « Transports ». Ils
viennent de Lucide et non de Figma, la seule exception à la règle « les assets
viennent de Figma », nommée dans `docs/ui-development.md` §13. Leur clé est
résolue par `MemoBookDesign/LucideIcon.swift`, qui retombe sur une boussole pour
une clé inconnue : ajouter une catégorie en base ne demande pas de livrer une
version.

## Un choix de design ne s'arrête pas au dessin

Une décision de design qui demande une donnée que la base n'a pas **n'est pas
finie tant que la base ne l'a pas**. Une pastille qui compte, une ligne qui
affiche un solde, un état qui distingue deux personnes : ce sont des colonnes,
une route et un sérialiseur, pas seulement une vue.

La chaîne va toujours dans le même sens, et **la même demande la parcourt en
entier**. On ne s'arrête pas au premier maillon en laissant le reste « pour plus
tard » : l'écran a l'air fini parce qu'un jeu d'essai le remplit, et c'est
précisément comme ça qu'on livre un écran qui ment.

1. `backend/prisma/schema.prisma` — la colonne, commentée par ce qu'elle sert.
2. `npm run db:migrate` dans `backend/` — la migration, versionnée.
3. `backend/src/routes/appSerializers.ts` — le champ, **au nom près** du modèle
   Swift : ce fichier est le contrat entre les deux côtés.
4. `MemoBookCore` — le champ dans `HomeFeed`, `TripDetail` ou
   `TravellerProfile`. Un champ non optionnel doit toujours être présent dans la
   réponse, sinon c'est **tout l'écran** qui cesse de décoder, pas seulement la
   ligne concernée.
5. `backend/prisma/seed.ts` — de quoi voir le nouvel état dans le simulateur, et
   sur **les deux comptes** qu'il pose (voir plus bas).
6. La vue, en dernier.

Quand la donnée se **dérive** de ce qui existe déjà — un compteur de voyages,
les dates du voyage en cours — les étapes 1 et 2 sautent : le sérialiseur
calcule, rien n'est stocké, et une seconde vérité de moins est à tenir d'accord.
Le dire dans le commentaire du champ, pour qu'on ne cherche pas la colonne.

Et si l'écran **écrit** cette donnée, la route qui l'écrit fait partie de la
même demande. Une ligne qui s'enregistre en perdant le focus et qui ne part
nulle part est pire qu'une ligne en lecture seule : elle a l'air d'avoir marché.

L'inverse compte autant — ne pas exposer dans l'app un réglage que la base ne
sait pas retenir. Voir `docs/reglages-utilisateur.md`.

## Comptes de test

`npm run db:seed` (dans `backend/`) pose **deux** comptes, mot de passe
`memobook2026` pour les deux :

| Adresse | Palier |
|---|---|
| `demo@memo-book.com` | gratuit — c'est là que mène « Testing mode » |
| `demo@memobook.app` | abonné |

Deux, parce que le produit a deux paliers et qu'ils ne montrent pas le même
écran : la pastille d'étapes offertes, le CTA lime de l'accueil et le bouton
d'abonnement n'existent que sur un compte à quota, et la carte de statistiques
ne s'ouvre que pour un abonné. Vérifier un écran sur un seul des deux, c'est
n'en avoir vu que la moitié.

Le bac à sable de l'accueil bascule d'un palier à l'autre **sans changer de
compte** — « Devenir un abonné » et « Première connexion » — pour comparer les
deux états sans se déconnecter. Voir `SandboxPersona`.

## Réseau

**Quand quelque chose ne marche pas, voir `docs/debogage.md`** : où sont les
logs du serveur, comment lire la trace réseau de l'app, et le tableau symptôme
→ cause → geste. On ne devine pas une panne, on lit une ligne de log.

En développement, l'app **nomme la panne et donne la commande** au lieu
d'afficher « Connexion impossible. Vérifie ton réseau » — voir
`APIError.developerDiagnosis` et `NetworkLog`, tous deux sous `#if DEBUG`.

**Une seule identification : la session de compte.** Tout ce qui appartient à
quelqu'un — carnets, souvenirs, rendus, commandes, profil, accueil — passe par
le jeton de session, jamais par celui de l'appareil. C'est le corollaire d'une
règle de la base : **un carnet a toujours un propriétaire, et ce propriétaire
est un compte** (`memos.ownerAccountId`, NOT NULL). Le jeton d'appareil ne sert
plus qu'à s'enregistrer et à se rattacher, et il voyage alors dans le corps de
la requête. Côté client, `Credential.session` est le défaut : un appel qui ne
dit rien parle au nom du compte.

Corollaire produit : **on ne peut plus raconter avant d'avoir un compte.** Créer
un carnet exige une session.

**Un co-voyageur fait tout ce que fait le propriétaire** — raconter, envoyer des
vocaux, changer les réglages du voyage, générer le carnet, le commander. La
seule chose qui ne se partage pas est de **supprimer** le voyage : détruire le
récit de tout le monde appartient au propriétaire principal. Côté serveur, c'est
`visibleToAccount` presque partout et `ownedByAccount` sur la seule route de
suppression.

Ce qui ne se partage pas non plus, c'est l'argent : **cagnotte et abonnement
pendent d'un compte, pas d'un voyage.** Chacun a les siens, et une commande
retient qui l'a passée (`print_orders.orderedByAccountId`) — c'est elle qui
dira quelle cagnotte débiter quand l'encaissement existera.

Le mot est **co-voyageur** dans tout ce qui se lit. Le contrat d'API et la base
gardent `companions` et `memo_members` : renommer un contrat n'est pas un choix
de vocabulaire, ça se fait en une passe ou pas du tout.

**Supprimer un compte supprime tout ce qui est à lui — sauf ce qui est aussi à
quelqu'un d'autre.** Un voyage qui a au moins un co-voyageur actif **change de
main** (il passe au plus ancien, qui perd sa ligne `memo_members`) au lieu
d'être effacé : un récit écrit à plusieurs ne disparaît pas parce que l'un s'en
va. Les souvenirs du partant y restent — ils appartiennent au récit, et c'est
pour ça qu'`entries` n'a pas de colonne d'auteur. Voir
`backend/src/services/deletion.ts`, qui porte aussi les trois pièges (commandes
en `RESTRICT` avant les rendus, `media_assets` que rien ne cascade, et le
stockage S3 qui ne participe pas à la transaction).

**Aucun appel réseau ne bloque le démarrage.** L'enregistrement de l'appareil est
paresseux : `AppDependencies.ensureRegistered()` est appelé par le modèle qui en
a besoin, et son échec est l'erreur de cet écran-là (un `ErrorBanner` en ligne),
jamais un mur devant l'app.

## Hors ligne

**L'app marche sans réseau, et le dit.** Trois pièces, chacune avec une seule
responsabilité :

| Pièce | Où | Ce qu'elle fait |
|---|---|---|
| `Connectivity` | `Networking` | une **valeur** — une fonction qui rend un flux « en ligne / hors ligne », `NWPathMonitor` derrière. Un test en fabrique une qu'il pilote |
| `PendingRecordingStore` | `Recording` | la file des vocaux **sur le disque**, un acteur |
| `RecordingOutbox` | `Feature` | décide d'envoyer ou de garder, et vide la file au retour du réseau |

`AppDependencies` monte la file au démarrage (`outbox.start()`), pas à
l'ouverture d'un écran : c'est ce qui permet de savoir qu'on est hors ligne
**avant** de dessiner l'accueil, et de repartir avec ce qu'un lancement
précédent avait laissé en attente. Un envoi commencé continue quand on quitte
l'accueil.

Trois règles portent tout le reste :

1. **Ce qui n'existe nulle part ailleurs va dans `Application Support`, jamais
   dans `Caches`.** Un vocal en attente est le récit de quelqu'un et rien ne le
   régénère ; iOS vide les caches sous pression disque. Le dernier accueil reçu,
   lui, est une copie de ce que le serveur sait — il est dans `Caches`, et il
   s'efface à la déconnexion (`AppDependencies.forgetAccountContent()`).
2. **« En ligne » ne veut pas dire « l'API répond ».** `NWPathMonitor` dit
   qu'une interface est montée : un portail captif se déclare satisfait. Un
   envoi qui échoue au **transport** retourne donc dans la file, même en ligne.
3. **Un refus du serveur n'est pas une panne.** Un 4xx sort le vocal de la file
   et s'affiche : garder un souvenir que le serveur refusera à chaque fois, ce
   serait promettre une arrivée qui n'aura jamais lieu. Une réponse illisible
   (décodage) compte au contraire comme **arrivée** — l'appel a abouti, le
   renvoyer mettrait le souvenir deux fois dans le carnet.

Ce que l'écran en montre — une boîte, quatre états, et les boutons de bac à
sable qui les rejouent — est dans `docs/ui-development.md` §9.3.

⚠️ **Un envoi ne survit pas encore à la mise en arrière-plan.** `URLSession` en
tâche de fond serait la réponse complète, et demande un envoi par fichier et une
délégation — donc une autre forme de client d'API. En attendant, ce qui n'a pas
eu le temps de partir reste dans la file et repart au retour dans l'app : rien
n'est perdu, c'est plus tard.

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
