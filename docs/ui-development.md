# UI & Wireframes — règles de développement des écrans

> **Ce fichier n'est pas le design system.** `agents/design.md` décrit *quoi* (palette,
> tokens, sémantique des couleurs). Ce fichier-ci décrit *comment* : la méthode, les
> unités, les garde-fous et la fiche à remplir pour chaque écran livré depuis Figma —
> front-end **et** back-end.
>
> À lire **en entier avant de toucher au premier pixel** d'un nouvel écran, à chaque
> session. Fichier Figma de référence :
> [MemoBook — Product](https://www.figma.com/design/kytPYFno7PvDciIKTxCujK/MemoBook---Product).

---

## 1. Règles non négociables

Ces onze règles priment sur tout le reste, y compris sur ce qui paraîtrait « plus
propre » en Swift. Le design Figma a plusieurs semaines de travail de fond derrière lui :
on l'implémente, on ne le réinterprète pas.

### R1 — Tout se mesure et s'écrit en **rem**

Aucune dimension d'écran n'est spécifiée en pixels ou en points bruts. Espacements,
tailles, rayons, hauteurs, largeurs, tailles de texte : **tout est exprimé en rem**, dans
la spec comme dans le code.

- **1 rem = 16** — c'est la valeur de la variable Figma `Text Sizes/Text Regular` (16) et
  de `Size/medium` (16). La base ne change jamais.
- Conversion depuis Figma : `rem = valeur_figma / 16`.
- Sur iOS, 1 rem se matérialise par **16 pt** (à l'échelle @1x, 1 px Figma = 1 pt). Le
  point n'apparaît **que** dans `MemoBookDesign` — jamais dans un écran.

> ⚠️ SwiftUI n'a pas de notion de `rem` : c'est une unité web. On ne peut donc pas
> « écrire du rem » littéralement dans une vue — on la **définit nous-mêmes** dans le
> design system, et plus aucune vue ne manipule autre chose. L'intention (une échelle
> relative à une racine unique, qui suit la taille de texte de l'utilisateur) est
> respectée à 100 % ; seule la syntaxe diffère. Voir §2 pour l'implémentation exacte.

### R2 — Se caler sur les **tailles classiques** du mobile

Une valeur Figma qui tombe à moins de 2 pt d'une taille standard est **arrondie sur la
taille standard**, pas recopiée telle quelle. Un champ à 47 devient 3 rem (48). Un écart
supérieur à 2 pt est conservé tel quel **et signalé** dans la fiche écran (§5) : c'est
peut-être une intention, peut-être une glissade de souris.

Toute valeur doit tomber sur l'échelle de §2.2. Une valeur hors échelle est une exception
qui se justifie par écrit dans la fiche.

### R3 — Figma est la source de vérité, et rien d'autre

On ne « améliore » pas, on ne recentre pas, on n'harmonise pas de sa propre initiative.
Si un écran paraît incohérent avec un autre, on **le signale** dans la section « À
trancher » de la fiche et on implémente ce que Figma dit, en attendant l'arbitrage de
Clara.

Interdits explicites : inventer un état vide, changer un libellé, remplacer une icône par
un SF Symbol « équivalent », arrondir un coin « pour faire iOS », ajouter une animation
non spécifiée.

### R4 — Les variables Figma priment sur `agents/design.md`

Les deux divergent aujourd'hui (voir §7). Tant que l'arbitrage n'est pas fait, la valeur
lue par `get_variable_defs` sur le nœud gagne, et l'écart est noté dans la fiche.

Corollaire : **aucune couleur, aucune taille, aucun rayon en dur dans une vue.** Tout
passe par un token de `MemoBookDesign`. Si le token n'existe pas, on l'ajoute au design
system d'abord, on écrit la vue ensuite.

### R5 — 390 × 844 est une **référence**, pas une largeur

Les maquettes sont dessinées sur iPhone 14 / 13 Pro (390 × 844). Aucune vue ne code 390
en dur : les largeurs sont fluides (`.frame(maxWidth: .infinity)` + marge d'écran), les
hauteurs suivent le contenu. Chaque écran est vérifié sur **iPhone SE (375 × 667)** et
**iPhone 17 Pro Max**, en plus de la taille de référence.

### R6 — On ne redessine jamais le chrome système

`Status Bar`, `Home Indicator`, `Bottom Bar` présents dans les frames Figma sont des
repères de maquette. Ils ne sont **pas** implémentés : ce sont les safe areas iOS. Le
contenu se positionne par rapport à la safe area, et les coordonnées Figma sont
recalculées en conséquence (une valeur `y` absolue de 80 sur la maquette = 33 sous la
status bar de 47).

### R7 — L'accessibilité fait partie de la fidélité

- Toute cible tactile ≥ **2.75 rem** (44 pt), même si le visuel est plus petit
  (`.contentShape` + `.frame(minWidth:minHeight:)`).
- Le texte suit **Dynamic Type**. Les tailles de police se déclarent avec
  `relativeTo:`, jamais en taille fixe.
- Chaque écran est relu en taille `AX3` : rien ne doit être tronqué ni superposé.
- Contraste ≥ 4.5:1 pour le texte courant, ≥ 3:1 pour les gros titres. Les couples
  hors-norme sont signalés, pas corrigés en douce.
- Chaque élément interactif porte un `accessibilityLabel` en français. Les éléments
  purement décoratifs sont masqués à VoiceOver.

### R8 — Les textes sont recopiés **au caractère près**

Copie française identique à Figma, apostrophes typographiques (`’`, pas `'`), pas de
correction orthographique silencieuse. Une faute se signale, elle ne se corrige pas sans
retour de Clara. Tous les libellés passent par des constantes localisables — pas de
chaîne en dur dispersée dans les vues.

### R9 — Les assets viennent de Figma, jamais d'ailleurs

Icônes et illustrations sont exportées depuis le nœud Figma (`download_assets`) en SVG →
`Assets.xcassets` en *Single Scale / Preserve Vector Data*. On ne substitue pas un SF
Symbol à une icône dessinée. `assets/icons/` du repo sert de banque secondaire ; le nœud
Figma reste prioritaire.

### R10 — Un écran n'est pas fini sans son contrat back-end

Pour chaque écran : lister les données affichées, l'endpoint qui les fournit, les erreurs
possibles. Les routes existantes sont dans `backend/src/routes/`. **On n'invente pas un
endpoint côté app** : soit il existe, soit on l'écrit côté back-end dans la même PR (avec
son test), soit l'écran est livré branché sur `PreviewAPI` et c'est écrit noir sur blanc
dans la fiche.

Chaque écran doit gérer les quatre états : **vide**, **chargement**, **erreur**,
**nominal**. Si Figma n'en dessine que le nominal, les trois autres sont signalés comme
manquants dans la fiche — pas improvisés.

### R11 — Une PR = un écran (ou un lot cohérent)

Branche par lot, PR obligatoire, CI verte. Messages de commit en français, à l'impératif,
sans préfixe `feat:`/`fix:` (voir l'historique du repo). La PR contient une **capture de
l'écran implémenté à côté de la maquette Figma**.

---

## 2. Le rem chez MemoBook

### 2.1 Définition

| | |
|---|---|
| Base | **1 rem = 16 pt** |
| Source | Variables Figma `Text Sizes/Text Regular` = 16, `Size/medium` = 16 |
| Conversion Figma → spec | `rem = px / 16` |
| Arrondi | au quart de rem le plus proche (0.25 rem = 4 pt), sauf exception justifiée |

### 2.2 Échelle de référence

| rem | pt | Usage type |
|---|---|---|
| 0.25 | 4 | Micro-espacement, épaisseur de barre |
| 0.5 | 8 | Espacement interne serré (titre ↔ sous-titre) |
| 0.75 | 12 | Espacement interne |
| **1** | **16** | Unité de base — marge d'écran mini, gouttière entre champs |
| 1.25 | 20 | Espacement de section court |
| 1.5 | 24 | Marge d'écran large, gouttière entre blocs, taille d'icône inline |
| 1.75 | 28 | Hauteur de pastille / tag |
| 2 | 32 | Espacement entre blocs, taille d'icône large |
| 2.5 | 40 | Grand espacement vertical |
| **2.75** | **44** | **Cible tactile minimale (HIG)** |
| **3** | **48** | **Hauteur de bouton primaire et de champ de saisie** |
| 3.5 | 56 | Hauteur de barre / ligne haute |
| 4 | 64 | Bloc, avatar large |
| 5 | 80 | Zone d'en-tête |

### 2.3 Tailles classiques attendues (garde-fous R2)

| Élément | Valeur MemoBook | Origine |
|---|---|---|
| Cible tactile minimale | 2.75 rem (44) | Apple HIG |
| Bouton primaire (hauteur) | 3 rem (48) | Figma : `Button` = 48 sur les 3 écrans ✅ |
| Champ de saisie (hauteur) | 3 rem (48) | Figma dessine 47 → arrondi R2 |
| Rayon des champs et cartes | 0.875 rem (14) | `MemoBookSpacing.cornerRadius` existant |
| Marge d'écran | **à trancher** (§7) | Figma : 1 rem sur *Sign Up*, 1.5 rem sur *Welcome* |
| Icône inline | 1.5 rem (24) | Figma : `keyboard_backspace` = 24.4 |
| Texte courant | 1 rem (16) | `Text Sizes/Text Regular` |
| Barre de progression | 0.25 rem (4) | Convention iOS (Figma dessine 7 → §7) |

### 2.4 Implémentation dans `MemoBookDesign`

Nouveau fichier `ios/Modules/Sources/MemoBookDesign/Rem.swift` :

```swift
import SwiftUI

/// L'unité de mesure de l'app. 1 rem = 16 pt, comme la racine typographique de
/// Figma (`Text Sizes/Text Regular` = 16).
///
/// C'est le SEUL endroit de l'app où un point apparaît. Toute vue mesure en rem.
public enum Rem {
    public static let base: CGFloat = 16

    /// Convertit une valeur en rem vers des points. Structure fixe uniquement
    /// (marges d'écran, gouttières) : ne suit pas Dynamic Type.
    public static func pt(_ value: CGFloat) -> CGFloat { value * base }
}

/// Raccourci de lecture : `rem(1.5)` plutôt que `24`.
public func rem(_ value: CGFloat) -> CGFloat { Rem.pt(value) }
```

**Deux régimes, à ne pas confondre :**

| | Quoi | Comment |
|---|---|---|
| **Structure fixe** | Marges d'écran, gouttières entre blocs, rayons | `rem(1.5)` |
| **Éléments qui suivent le texte** | Hauteur de bouton et de champ, taille d'icône accolée à du texte, cible tactile | `@ScaledMetric` |

```swift
struct PrimaryButton: View {
    // La hauteur grandit avec la taille de texte de l'utilisateur : un bouton de
    // 3 rem à taille standard, plus haut en accessibilité.
    @ScaledMetric(relativeTo: .body) private var unit: CGFloat = Rem.base

    var body: some View {
        Text(title)
            .frame(maxWidth: .infinity, minHeight: unit * 3)   // 3 rem
            .padding(.horizontal, rem(1))                      // structure fixe
    }
}
```

**Les tailles de police ne se multiplient jamais à la main.** Une taille Figma de 16 se
déclare `.font(.system(.body))` ou, quand la police de marque sera figée,
`.font(.custom("…", size: rem(1), relativeTo: .body))` — pour garder Dynamic Type. Écrire
`.font(.system(size: rem(1)))` fige la taille et casse l'accessibilité : c'est interdit.

**Interdit également :** `.padding(24)`, `.frame(height: 48)`, `.cornerRadius(14)` dans un
écran. Ces valeurs vivent dans `MemoBookSpacing` / `Rem`, jamais dans une vue.

> À faire à la prochaine session UI : réécrire `MemoBookSpacing` en rem
> (`xs = rem(0.5)`, `s = rem(1)`, `m = rem(1.5)`, `l = rem(2)`, `xl = rem(2.5)`), les
> valeurs en points actuelles y correspondant déjà exactement.

---

## 3. Le rituel, écran par écran

Quand Hugo fournit un ou plusieurs liens Figma, dérouler ces étapes **dans l'ordre**,
sans en sauter.

**Étape 1 — Lire la maquette, ne jamais la deviner.**
Depuis l'URL `.../design/<fileKey>/…?node-id=2553-27641`, extraire `fileKey` et
`nodeId` (`2553:27641`), puis, via le MCP Figma :

| Outil | Ce qu'il donne |
|---|---|
| `get_metadata` | L'arborescence : noms, positions, tailles. Le squelette |
| `get_design_context` | Le rendu de référence + le code source des propriétés. **Obligatoire avant d'implémenter** |
| `get_variable_defs` | Les tokens réellement appliqués sur le nœud (couleurs, tailles) |
| `get_screenshot` | Le visuel, pour la comparaison finale |
| `download_assets` | Les icônes et images du nœud |

**Étape 2 — Remplir la fiche écran** (§5) avant d'écrire une ligne de Swift. Convertir
toutes les mesures en rem, appliquer R2, lister les écarts.

**Étape 3 — Les tokens d'abord.** Chaque valeur nouvelle entre dans `MemoBookDesign`
(couleur, espacement, style de texte, composant partagé). Un composant vu sur deux écrans
(`Button`, `Toggle`, `Number`…) est factorisé dès la deuxième occurrence.

**Étape 4 — La vue.** SwiftUI + MVVM `@Observable`, dans `MemoBookFeature/<Écran>/`.
Deux previews minimum : taille de référence, et Dynamic Type `AX3`.

**Étape 5 — Le back-end.** Vérifier `backend/src/routes/` ; écrire la route manquante
avec son test dans la même PR, ou brancher sur `PreviewAPI` et le dire.

**Étape 6 — La comparaison.** Capture de l'app à côté de `get_screenshot`, superposées.
Dérouler la checklist §6. Tout écart non intentionnel est corrigé avant la PR.

**Étape 7 — La PR.** Branche dédiée, CI verte, capture avant/après dans la description,
section « À trancher » recopiée pour Clara.

---

## 4. Découpage du travail

| Lot | Écrans | Statut |
|---|---|---|
| **1 · Entrée dans l'app** | Splash Screen, Welcome Screen, Sign Up | 📐 Maquettes reçues, spec ci-dessous |
| 2 · Compte | Sign In, mot de passe oublié, suppression de compte | ⏳ En attente de maquettes |
| 3 · Carnets & enregistrement | Liste, détail, enregistrement | 🔄 Existe en version non brandée |
| 4 · Carnet & partage | Génération, aperçu PDF, partage | 🔄 Existe en version non brandée |
| 5 · Paywall & réglages | Achat, abonnement, profil | ⏳ En attente de maquettes |

---

## 5. Modèle de fiche écran

À copier pour chaque nouvel écran, à remplir **avant** d'implémenter, à garder dans ce
fichier.

```md
### <Nom de l'écran>

- **Nœud Figma** : `<node-id>` — <lien>
- **Vue** : `MemoBookFeature/<Dossier>/<Nom>View.swift`
- **Rôle** : une phrase.
- **Entrée / sortie** : d'où on vient, où on va.

**Structure (en rem)** — mesures Figma converties, écarts R2 signalés.

**Tokens utilisés** — couleurs, textes, espacements ; ce qui manque au design system.

**Composants** — partagés vs spécifiques à l'écran.

**Copie** — chaque libellé, au caractère près.

**États** — vide / chargement / erreur / nominal. Ce qui n'est pas maquetté est marqué.

**Contrat back-end** — endpoint, payload, erreurs, ou « aucun ».

**Assets** — fichiers à exporter du nœud.

**Accessibilité** — labels VoiceOver, comportement en AX3.

**À trancher** — les questions ouvertes, nommées.
```

---

## 6. Checklist de conformité (Definition of Done)

Aucune PR d'écran ne part sans que ces cases soient cochées.

**Fidélité**
- [ ] Capture de l'app superposée à la maquette : aucun écart non justifié
- [ ] Toutes les mesures viennent de tokens ; zéro valeur numérique nue dans la vue
- [ ] Couleurs = variables Figma du nœud ; aucun hex dans la vue
- [ ] Libellés au caractère près, apostrophes typographiques comprises
- [ ] Icônes exportées de Figma, pas substituées
- [ ] Rayons, ombres, bordures, opacités vérifiés un à un

**Unités**
- [ ] Toute dimension exprimée en rem, sur l'échelle §2.2
- [ ] Arrondis R2 appliqués et listés dans la fiche
- [ ] Structure fixe via `rem()`, éléments typographiques via `@ScaledMetric`
- [ ] Aucune taille de police fixe (toujours `relativeTo:`)

**Adaptation**
- [ ] Vérifié sur iPhone SE, 390 × 844, et Pro Max
- [ ] Dynamic Type AX3 : rien de tronqué ni de superposé
- [ ] Mode sombre traité, ou explicitement hors périmètre pour cet écran
- [ ] Safe areas respectées ; chrome système non redessiné
- [ ] Clavier : le contenu remonte, rien n'est masqué (écrans à champs)

**Accessibilité**
- [ ] Cibles tactiles ≥ 2.75 rem
- [ ] Labels VoiceOver en français, décoratif masqué
- [ ] Contrastes vérifiés

**Fonctionnel**
- [ ] Les quatre états sont gérés (ou l'absence de maquette est signalée)
- [ ] Contrat back-end vérifié dans `backend/src/routes/`
- [ ] Navigation entrante et sortante branchée
- [ ] `make build` et `make test` passent ; CI back-end verte
- [ ] Section « À trancher » remontée dans la PR

---

## 7. Points à trancher (transverses)

Ces questions dépassent un écran. Elles sont ouvertes tant que Clara n'a pas arbitré ;
en attendant, on applique la règle R4 (les variables Figma gagnent) et on n'harmonise
rien de sa propre initiative.

| # | Sujet | État |
|---|---|---|
| T1 | **Palette.** Les variables Figma et `agents/design.md` divergent : Black `#2d231a` vs `#2B231B`, un vert `#28654b` (« Green ») qui n'est ni Forest Green ni Kiwi, un `White #fffcf8` et un `Background Light #fcf2e9` absents du doc. Aucune trace de Carrot `#F86015` sur les trois premiers écrans. `Tokens.swift` est encore sur des couleurs système, volontairement | 🔴 Bloquant pour brander les écrans |
| T2 | **Marge d'écran.** *Sign Up* est à 1 rem (16), *Welcome* à 1.5 rem (24), le code actuel à 1.25 rem (20). Trois valeurs pour la même chose | 🔴 À figer avant le lot 1 |
| T3 | **Typographies.** Aucune variable de police dans Figma ; le repo les liste comme « à documenter ». Les écrans partiront sur les styles système tant que la police de marque n'est pas fournie | 🟠 Non bloquant, dette assumée |
| T4 | **Modèle d'authentification.** Le *Sign Up* Figma montre email + mot de passe + confirmation + trois fournisseurs sociaux. Le README annonce « Sign in with Apple + email (magic link) ». Ce sont deux back-ends différents, et la règle App Store 4.8 impose Sign in with Apple dès qu'un login social tiers est proposé | 🔴 Bloquant pour le back-end du lot 1 |
| T5 | **Cartes inclinées du *Welcome*.** Les trois blocs de bénéfices ont des cadres non alignés (x = 16.9 / 13.2 / 12.8, dimensions non entières) : rotation légère probable. Angle exact à récupérer via `get_design_context` avant implémentation — une rotation « à l'œil » se voit | 🟠 À vérifier à l'implémentation |
| T6 | **Loader du Splash** dessiné à 7 de haut ; la convention iOS est 4. Barre custom assumée ou arrondi R2 ? | 🟢 Mineur |

---

## 8. Lot 1 — Entrée dans l'app

Trois écrans, tous en 390 × 844. Mesures relevées via `get_metadata` et
`get_variable_defs` ; **les valeurs fines (couleurs par nœud, rotations, ombres, polices)
restent à confirmer par `get_design_context` au moment d'implémenter**.

### 8.1 Splash Screen

- **Nœud Figma** : `2553:27641` —
  [ouvrir](https://www.figma.com/design/kytPYFno7PvDciIKTxCujK/MemoBook---Product?node-id=2553-27641)
- **Vue** : `MemoBookFeature/Onboarding/SplashView.swift`
- **Rôle** : premier écran au lancement, pendant la restauration de session et le
  premier appel réseau. Enchaîne automatiquement sur *Welcome* (nouvel utilisateur) ou
  sur la liste des carnets (session valide).

**Structure (en rem)**

| Élément | Figma | rem | Note |
|---|---|---|---|
| Bloc contenu (logo + loader) | 390 × 145.68 | pleine largeur × 9.1 | Centré ; haut du bloc à 360.16 → ≈ centre optique, léger décalage bas de 0.7 rem |
| Logo | 149.35 × 106.68, x 120.33 | 9.33 × 6.67 | Centré horizontalement (85.5 de chaque côté ✅) |
| Espace logo → loader | 39 | 2.5 | Arrondi R2 (39 → 40) |
| Loader | 198 × 7, x 96 | 12.375 × 0.4375 | Largeur → **12.5 rem** (R2). Hauteur : voir T6 |

**Tokens** : fond `Scheme/Background Light` (à confirmer sur le nœud), teinte du loader à
récupérer.

**Composants** : `Loader` (instance Figma `2720:21912`) → composant partagé de
`MemoBookDesign`, il resservira. `Company Logo` (`2699:14313`) → asset.

**Copie** : aucune.

**États** : nominal uniquement. Prévoir un **plancher de 0.8 s** (sinon l'écran clignote
sur bon réseau) et un **plafond de 5 s** au-delà duquel on bascule sur *Welcome* en mode
hors-ligne plutôt que de rester bloqué. Non maquetté → à valider.

**Contrat back-end** : `POST /v1/devices` (existant, `backend/src/routes/devices.ts`) si
l'appareil n'est pas encore enregistré ; sinon aucun appel. Une fois T4 tranché, cet
écran portera aussi la validation du token de session.

**Assets** : logo MemoBook (SVG), animation du loader.

**Accessibilité** : `accessibilityLabel` « MemoBook, chargement en cours » sur le bloc ;
loader en `accessibilityHidden`.

**À trancher** : T1 (fond et teinte), T6 (hauteur du loader), durées ci-dessus.

---

### 8.2 Welcome Screen

- **Nœud Figma** : `2552:27407` —
  [ouvrir](https://www.figma.com/design/kytPYFno7PvDciIKTxCujK/MemoBook---Product?node-id=2552-27407)
- **Vue** : `MemoBookFeature/Onboarding/WelcomeView.swift`
- **Rôle** : présenter la promesse produit en trois bénéfices, puis envoyer vers *Sign Up*.
- **Entrée / sortie** : depuis *Splash* → CTA vers *Sign Up*.

**Structure (en rem)** — coordonnées relatives au conteneur, sous la status bar.

| Élément | Figma | rem | Note |
|---|---|---|---|
| Pastille « tagline » | 219 × 28, centrée, y 24 | 13.7 × 1.75, top 1.5 | Padding interne 9 → **0.5 rem** (R2) |
| Titre (3 lignes) | 332 × 105, x 29, y 74 | 20.75 × 6.6, top 4.6 | Marge latérale 1.8 rem — cadre de texte, pas marge d'écran |
| Sous-titre | 342 × 66.67, x 24, y 201 | 21.375 × 4.2, top 12.6 | Marge 1.5 rem |
| Carte bénéfice ×3 | ≈ 356–367 × 99, y 295.9 / 410.6 / 538 | ≈ 6.2 de haut | **Voir T5** : cadres non alignés, rotation probable |
| Espace entre cartes | 15.8 puis 28.3 | — | Incohérent : conséquence probable de T5, à recalculer après avoir lu la rotation |
| CTA | 342 × 48, x 24, y 652.8 | 21.375 × **3**, top 40.8 | Hauteur = 3 rem ✅ conforme §2.3 |

**Anatomie d'une carte bénéfice** : conteneur d'icône ≈ 2.3–3 × 2.5 rem (icône 1–1.6 rem
dedans) · bloc texte 15 rem de large, titre puis description à 1.3 rem d'écart · flèche
`keyboard_backspace` 1.5 rem à droite · pastille `Number` 1.66 rem **en débord au-dessus
du cadre** (y négatif) — le débord est intentionnel, ne pas le rentrer dans la carte.

**Tokens** : `Scheme/Text` `#2d231a`, `Brand Colors/White` `#fffcf8`,
`Scheme/Background Light` `#fcf2e9`, `Brand Colors/Green` `#28654b`,
`Brand Colors/Blue` `#afd2f0`, `Grays/Gray` `#8e8e93`, texte courant 16 (1 rem).

**Composants** : `Button` (partagé, aussi sur *Sign Up*) · `Number` (pastille, partagée) ·
`BenefitCard` (spécifique) · `Tagline` (pastille).

**Copie** (verbatim)

- Tagline : « Bienvenue voyageur & voyageuse »
- Titre : « Chaque instant mérite d’être mémorisé »
- Sous-titre : « Garde tes moments de voyage tels qu’ils se vivent. Tu les racontes,
  MemoBook les met en forme »
- Carte 1 : « Assistant vocal & écrit » / « Parlez simplement durant la journée, Memo
  retranscrit vos anecdotes »
- Carte 2 : « Photos & stickers instantanés » / « Ajoutez vos photos depuis la galerie,
  Instagram ou créez vos stickers personnalisés »
- Carte 3 : « Carnet imprimé d’exception » / « Mise en page automatique élégante et
  livraison chez vous de votre véritable carnet papier »
- CTA : libellé à lire dans l'instance `Button` (`2552:27426`)

> ⚠️ Les cartes tutoient (« Garde tes moments ») et vouvoient (« Parlez simplement »,
> « Ajoutez vos photos ») dans le même écran. On implémente tel quel et on le remonte à
> Clara : c'est une question de copie, pas de code.

**États** : nominal uniquement. Écran statique, aucun chargement.

**Contrat back-end** : aucun.

**Assets** : icône micro (vector `2552:27454`), `photo` (`2553:27481`), `book.fill`
(`2553:27484`), `keyboard_backspace` ×3, pastilles `Number` 1/2/3.

**Accessibilité** : chaque carte est **un seul élément** VoiceOver (titre + description
regroupés) ; la pastille numérotée devient partie du label (« Étape 1 sur 3 »). AX3 :
les cartes doivent grandir en hauteur, jamais tronquer — la rotation de T5 ne doit pas
faire déborder le texte.

**À trancher** : T1, T2 (l'écran utilise 1.5 rem), T5, ton tutoiement/vouvoiement,
libellé exact du CTA, présence ou non d'un « passer » / d'un indicateur de progression.

---

### 8.3 Sign Up

- **Nœud Figma** : `2553:27489` —
  [ouvrir](https://www.figma.com/design/kytPYFno7PvDciIKTxCujK/MemoBook---Product?node-id=2553-27489)
- **Vue** : `MemoBookFeature/Onboarding/SignUpView.swift`
- **Rôle** : création de compte par email + mot de passe, ou via un fournisseur tiers.
- **Entrée / sortie** : depuis *Welcome* → liste des carnets. Le `Toggle` en tête bascule
  vers *Sign In* (écran non encore maquetté).

**Structure (en rem)** — conteneur `Frame 294` à x 16, y 80.4, largeur 358.

| Élément | Figma | rem | Note |
|---|---|---|---|
| Marge d'écran | 16 | **1** | Diffère de *Welcome* → T2 |
| Toggle Connexion / Inscription | 314 × 51, x 22 | 19.6 × 3.1875 | Hauteur → **3.25 rem** (52) par R2 ; centré, 1.375 rem de retrait de chaque côté |
| Espace toggle → titre | 32 | 2 | ✅ sur l'échelle (`Size/xlarge` = 32) |
| Titre | 358 × 35 | pleine largeur × 2.2 | |
| Espace titre → sous-titre | 8 | 0.5 | ✅ |
| Sous-titre | 358 × 21 | × 1.3 | |
| Espace sous-titre → champs | 32 | 2 | ✅ |
| Champ | 358 × 47 | × **3** | 47 → 48 par R2. Retrait de texte 24 → 1.5 rem |
| Gouttière verticale entre champs | 16 | 1 | ✅ |
| Ligne Prénom / Nom | 171 + 16 + 171 | 10.7 + 1 + 10.7 | Deux colonnes égales, gouttière 1 rem |
| Espace champs → CTA | 32 | 2 | ✅ |
| CTA | 358 × 48 | × **3** | ✅ conforme §2.3 |
| Espace CTA → « Ou continue avec » | 32 | 2 | ✅ |
| Logos sociaux | ≈ 35 × 37, écart 25 | ≈ 2.2 × 2.3, écart **1.5** | 25 → 24 par R2. Bloc centré |

> ⚠️ Le passage des champs de 47 à 48 rallonge le bloc de 5 pt au total. C'est voulu et
> conforme à R2 : la mise en page est fluide, les espacements ne bougent pas.
>
> ⚠️ La status bar est posée à x = −1 sur 391 de large dans la maquette : glissade de
> souris, à ignorer (R6 — on ne l'implémente pas de toute façon).

**Tokens** : `Scheme/Text` `#2d231a`, `Brand Colors/White` `#fffcf8`,
`Scheme/Background Light` `#fcf2e9`, `Brand Colors/Grey` `#c8c8c8` (bordures probables),
`Grays/Gray` `#8E8E93` (placeholders), `Size/medium` 16, `Size/xlarge` 32.

**Composants** : `Toggle` (segmenté, partagé avec *Sign In*) · `TextField` MemoBook
(hauteur 3 rem, retrait 1.5 rem, rayon à confirmer) · `Button` · `SocialButton` ×3.

**Copie** (verbatim) : « Crée ton compte » · « pour commencer à raconter ton histoire » ·
« Prénom » · « Nom » · « Email » · « Mot de passe » · « Confirme ton mot de passe » ·
« Ou continue avec ». Libellés du `Toggle` et du CTA à lire dans les instances.

**États**
- **Nominal** : formulaire vide, CTA désactivé tant que les champs requis sont vides.
- **Validation** : email mal formé, mots de passe différents, mot de passe trop court.
  **Aucun état d'erreur n'est maquetté** → à demander à Clara avant de l'inventer.
- **Chargement** : CTA en attente pendant l'appel réseau. Non maquetté.
- **Erreur serveur** : email déjà pris, réseau indisponible. Non maquetté.

**Contrat back-end** — ⚠️ **rien de tout cela n'existe aujourd'hui.**
`backend/src/routes/` ne contient que `devices`, `memos`, `entries`, `renders`, `orders`,
`health` : l'app s'enregistre comme appareil anonyme. Cet écran demande, une fois **T4**
tranché :

| Besoin | Route à créer | Remarques |
|---|---|---|
| Création de compte | `POST /v1/auth/signup` | prénom, nom, email, mot de passe. Hash Argon2id, jamais en clair |
| Connexion | `POST /v1/auth/login` | pour l'écran *Sign In* du lot 2 |
| Login tiers | `POST /v1/auth/oauth/:provider` | Apple / Google / le troisième, à identifier |
| Rattachement | migration | relier l'appareil anonyme existant au compte créé, sans perdre les carnets déjà enregistrés |
| Modèle | `prisma/schema.prisma` | table `User`, relation avec `Device` |

Trois contraintes à ne pas oublier : **Sign in with Apple obligatoire** dès qu'un login
social tiers est proposé (App Store 4.8) · **suppression de compte obligatoire**
(guideline 5.1.1) · mot de passe **jamais** stocké ni journalisé en clair, et pas de
message d'erreur qui révèle si un email existe déjà.

**Assets** : trois logos de fournisseurs (`image 701`, `image 697`, `image 698` — à
identifier au moment de l'export ; probablement Apple, Google et un troisième).

**Accessibilité** : `textContentType` correct sur chaque champ (`.givenName`,
`.familyName`, `.emailAddress`, `.newPassword`) pour le trousseau et la suggestion de mot
de passe fort · `submitLabel` et enchaînement au clavier · le contenu remonte à
l'ouverture du clavier (R7) · contraste des placeholders `#8E8E93` sur `#fcf2e9` à
vérifier (probablement sous 4.5:1).

**À trancher** : T1, T2, **T4 (bloquant)**, états d'erreur non maquetté, identité du
troisième fournisseur social, présence de CGU / politique de confidentialité à cocher —
absente de la maquette mais généralement exigée à la création de compte.

---

## 9. Ce qu'on ne fait jamais

- Coder une valeur numérique dans une vue au lieu d'un token
- Écrire une taille de police fixe (casse Dynamic Type)
- Substituer une icône, un rayon, une couleur « équivalente »
- Inventer un état, un libellé, une animation absents de la maquette
- Inventer un endpoint côté app en espérant qu'il existe
- Corriger une faute de français sans retour de Clara
- Harmoniser deux écrans qui divergent, au lieu de le signaler
- Fermer une PR d'écran sans la capture comparée à Figma
