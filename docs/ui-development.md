# UI & Wireframes — règles de développement des écrans

> **Ce fichier n'est pas le design system.** `agents/design.md` décrit *quoi* (palette,
> tokens, sémantique des couleurs). Ce fichier-ci décrit *comment* : la méthode, les
> unités, les garde-fous et la fiche à remplir pour chaque écran livré depuis Figma —
> front-end **et** back-end.
>
> À lire **en entier avant de toucher au premier pixel** d'un nouvel écran, à chaque
> session. Fichier Figma de référence :
> [MemoBook — Product](https://www.figma.com/design/kytPYFno7PvDciIKTxCujK/MemoBook---Product).
>
> Les mots qu'on emploie ici et dans le code — écran, feuille, étape, parcours,
> tunnel, fonctionnalité, lot, fiche, T-numéro — sont fixés dans
> [`vocabulaire.md`](vocabulaire.md). Un mot nouveau s'y ajoute avant de servir.

---

## 1. Règles non négociables

Ces douze règles priment sur tout le reste, y compris sur ce qui paraîtrait « plus
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
- **Une seule exception : les traits.** Bordures et séparateurs restent en points
  (`Stroke/Border Width` = 1 pt). Un filet ne grossit pas avec le texte — c'est la
  convention iOS, et une bordure mise à l'échelle devient un cadre.

> ⚠️ SwiftUI n'a pas de notion de `rem` : c'est une unité web. On ne peut donc pas
> « écrire du rem » littéralement dans une vue — on la **définit nous-mêmes** dans le
> design system, et plus aucune vue ne manipule autre chose. L'intention (une échelle
> relative à une racine unique, qui suit la taille de texte de l'utilisateur) est
> respectée à 100 % ; seule la syntaxe diffère. Voir §2 pour l'implémentation exacte.

### R2 — Se caler sur les **tailles classiques** du mobile

Une valeur Figma qui tombe à 2 pt ou moins d'une taille standard est **arrondie sur la
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

`agents/design.md` est un **miroir** des variables Figma, pas une source parallèle. En cas
d'écart, la valeur lue par `get_variable_defs` **sur le nœud** gagne, et le miroir est mis
à jour dans la foulée.

Attention aux **modes** : la page *Design System* de Figma affiche encore le mode par
défaut du template (Roboto, `Radius/*` à 0, `Scheme/Text` #212121). Ce sont les valeurs
résolues **sur les écrans de l'app** qui font foi.

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

### R9 — **On tutoie l'utilisateur. Toujours.**

Dans l'app, MemoBook dit **tu** : « Crée ton compte », « Découvre MemoBook », « Garde tes
moments de voyage ». Sans exception — écrans, messages d'erreur, notifications, mails
transactionnels, textes générés par les agents IA.

Le vouvoiement est réservé à ce qui **n'est pas l'app** : decks investisseurs, documents
partenaires, et encore, rarement.

Concrètement, quand une maquette vouvoie (c'est le cas de deux cartes du *Welcome*),
c'est une coquille de la maquette, pas une règle : on **signale** la phrase à Clara pour
qu'elle la réécrive dans Figma. On ne la réécrit pas soi-même dans le code — R8 tient —
mais on ne la recopie pas non plus sans la remonter.

### R10 — Les assets viennent de Figma, jamais d'ailleurs

Icônes et illustrations sont exportées depuis le nœud Figma (`download_assets`) en SVG →
`Assets.xcassets` en *Single Scale / Preserve Vector Data*. On ne substitue pas un SF
Symbol à une icône dessinée. `assets/icons/` du repo sert de banque secondaire ; le nœud
Figma reste prioritaire.

### R11 — Un écran n'est pas fini sans son contrat back-end

Pour chaque écran : lister les données affichées, l'endpoint qui les fournit, les erreurs
possibles. Les routes existantes sont dans `backend/src/routes/`. **On n'invente pas un
endpoint côté app** : soit il existe, soit on l'écrit côté back-end dans la même PR (avec
son test), soit l'écran est livré branché sur `PreviewAPI` et c'est écrit noir sur blanc
dans la fiche.

Chaque écran doit gérer les quatre états : **vide**, **chargement**, **erreur**,
**nominal**. Si Figma n'en dessine que le nominal, les trois autres sont signalés comme
manquants dans la fiche — pas improvisés.

### R12 — Une PR = un écran (ou un lot cohérent)

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
| **1** | **16** | Unité de base — **marge d'écran**, gouttière entre champs |
| 1.25 | 20 | Espacement de section court |
| 1.5 | 24 | Gouttière entre blocs, taille d'icône inline |
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
| **Marge d'écran (unique)** | **1 rem (16)** | Voir l'encadré ci-dessous |
| Rayon d'une carte | 1.25 rem (20) | Figma : cartes et tagline du *Welcome* |
| Rayon d'un bouton | 1 rem (16) | Figma : `Button` |
| Rayon d'un fond d'icône | 0.75 rem (12) | Figma dessine 13 → arrondi R2 |
| Épaisseur de trait | 1 pt (jamais en rem) | `Stroke/Border Width` |
| Icône inline (symbole système) | 1.5 rem (24) | Figma : `keyboard_backspace` = 24 |
| **Icône de contenu du jeu de marque** | **2 rem (32)** | `contentIcon` — les glyphes du jeu n'occupent que 55 à 70 % de leur boîte de 24 ; à 24 pt ils faisaient 9 à 12 pt d'encre. Hugo, 14/09/2026 — voir T101 |
| Texte courant | 1 rem (16) | `Text Sizes/Text Regular` |
| Barre de progression | 0.375 rem (6) | `progressBarHeight` — ce que dessinent la cagnotte et les cartes de l'accueil (T77, 17/09/2026) |

> **La marge d'écran est de 1 rem (16 pt), sur tous les écrans, sans exception.**
>
> Les maquettes divergeaient (1 rem sur *Sign Up*, 1.5 rem sur *Welcome*) et le code
> était sur 1.25 rem (20). Valeur retenue : **1 rem**. C'est la marge standard du mobile
> — celle d'iOS comme de Material —, c'est exactement l'unité de base de l'échelle, et
> c'est la plus généreuse en largeur de contenu, ce dont les cartes du *Welcome* ont
> besoin : sur un iPhone SE (375 de large), 1.5 rem laisserait 327 pt de contenu contre
> 343 en 1 rem, et le bloc de texte d'une carte tombe déjà à 217 pt sur cette taille
> d'écran.
>
> Conséquence sur *Welcome* : les blocs passent de 342 à 358 de large. Les maquettes
> restent la référence pour **tout le reste** — cette valeur-là, et elle seule, est
> uniformisée.

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

### 2.5 Typographie

Deux familles, désormais figées : **Sora** (titres, chiffres) et **General Sans** (tout
le reste). Détail des styles et des graisses dans
[`agents/design.md`](../agents/design.md#typographies).

| Style | rem | Police | Emploi |
|---|---|---|---|
| Titre d'écran | 2 | Sora Bold | Le titre principal, un par écran |
| Titre de bloc | 1 | General Sans Semibold | Titre de carte, de section |
| Corps | 1 | General Sans Regular | Texte courant |
| Description | 0.75 | General Sans Regular | Texte secondaire dans une carte |
| Bouton | 1 | General Sans Medium | Libellés d'action |
| Tagline | 0.875 | General Sans Medium | Pastilles |

Les deux polices doivent être embarquées dans l'app (`Info.plist` →
`UIAppFonts`) avant le premier écran brandé. Chaque style se déclare avec
`relativeTo:` pour garder Dynamic Type :

```swift
.font(.custom("Sora-Bold", size: rem(2), relativeTo: .largeTitle))
```

Interligne et approche viennent de Figma (`.lineSpacing`, `.tracking`) : ils font partie
du dessin, pas de la décoration.

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
| **1 · Entrée dans l'app** | Splash Screen, Welcome Screen, Sign Up | 📐 Spec figée (§8) — *Sign Up* attend T4 pour son back-end |
| 2 · Compte | Sign In, mot de passe oublié, suppression de compte | ⏳ En attente de maquettes |
| 3 · Carnets & enregistrement | **Accueil**, **accueil d'un voyage**, **chat**, **exemples de carnets**, liste, détail, enregistrement | 🟢 *Accueil* + écran de lancement (§9), *accueil d'un voyage* (§11), la **conversation avec MEMO** (§14, moteur de réponses local — §14.1) et *exemples de carnets* (§15, branché sur `GET /v1/gallery`) livrés — le reste existe en version non brandée |
| 4 · Carnet & partage | Génération, aperçu PDF, partage | 🔄 Existe en version non brandée |
| 5 · Paywall & réglages | Achat, abonnement, **profil** | 🟢 *Profil* et ses six feuilles livrés (§10), les **cinq feuilles de l'abonnement** et la résiliation en trois temps (§13), le **palier freemium** partagé accueil ↔ profil (§13.2) et les **trois écrans du paywall** (§13.3), sur jeu d'essai — seule la déconnexion agit vraiment. Restent les trois feuilles du paywall |

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
- [ ] **Tout tutoie** — écrans, erreurs, notifications (R9)
- [ ] Rotations, débords et chevauchements reproduits au degré et au point près
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

## 7. Décisions transverses et points ouverts

### 7.1 Ce qui est tranché

| # | Décision |
|---|---|
| D1 | **Palette.** [`agents/design.md`](../agents/design.md) recopie désormais les variables Figma réelles. Carrot, Carrot Darker, Forest Green et Kiwi **n'existent plus** ; Blue `#AFD2F0` et Lime `#E2F32B` entrent. Green `#28654B` porte le CTA, Lime est `Scheme/Accent`. Reste à faire : poser ces valeurs dans `Tokens.swift` (l'avertissement « palette pas encore posée » de `ios/README.md` peut alors tomber) et traiter les fichiers listés en fin de `design.md` |
| D2 | **Marge d'écran : 1 rem (16 pt) partout**, y compris sur *Welcome* qui était dessiné à 1.5 rem. Justification en §2.3 |
| D3 | **Typographies : Sora** (titres, chiffres) et **General Sans** (tout le reste). Styles détaillés en §2.5. Les variables `Heading/*` et `Text/*` de Figma annoncent encore Roboto : c'est le template de départ, à nettoyer dans Figma |
| D4 | **Cartes du *Welcome*.** L'inclinaison est **conservée telle quelle** : −1°, +1°, −1°. Les dimensions, elles, sont **uniformisées** (§8.2) |
| D5 | **Tutoiement systématique** dans l'app — c'est la règle R9 |
| D6 | **Tous les points T16 → T38 sont arbitrés** — Hugo, 06/09/2026. Ceux qui ne figurent pas ci-dessous sont validés **tels qu'implémentés** : la fiche de chaque écran les décrit, et ils n'ont plus à être rouverts |
| D7 | **« Etape n°1 » garde son E sans accent**, et les compteurs restent en français avec leurs unités (« 10 jours », « 37 km ») plutôt qu'en anglais comme la maquette. Clôt T29 et l'écart signalé en §11 |
| D8 | **Le second groupe de personnes d'un voyage attend la v2.** Le premier, lui, est celui des **collaborateurs** : ceux qui peuvent ajouter des étapes, et qu'on invitera. Le second réunira les visages croisés en chemin — il est retiré du modèle et de l'écran en attendant, plutôt que dessiné à moitié. Clôt T31 |
| D9 | **« les carnets de la communauté »** — la coquille de la maquette est corrigée dans le code, et à reprendre dans Figma. Clôt T34 |
| D10 | **Le titre de la section suit le nombre** : « Ton voyage » pour un seul, « Tes voyages » dès le deuxième. Clôt T35 |
| D11 | **Un voyage sans souvenir dont les dates disent « en cours » est en cours.** C'est même l'intérêt : c'est là qu'il faut inciter à raconter la première étape. Le `stage` reste calculé par le serveur. Clôt T38 |
| D16 | **Le lime ne dit que l'abonnement.** Hugo, 14/09/2026 : tout ce qui touche à l'abonnement est lime — le bouton qui y invite, la pastille « Abonné », le solde d'étapes offertes, l'écriture « ABONNEMENT » de la cagnotte — et la couleur d'accent du reste de l'app est le bleu `Brand Colors/Blue` #AFD2F0. `Tokens.swift` porte la règle (`accent`, `outline`) ; le compteur d'une section, le rond de confirmation du support et le rond de la cagnotte vide passent au bleu. Clôt T7 et T36 |
| D17 | **Trois bleus, et pas un de plus.** `Brand Colors/Blue` #AFD2F0 (l'aplat, la majorité des emplois), `Semantic/Information` #4A8FE0 (les retours système) et **`blueText` #4088C6**, le bleu du texte, que Hugo définit le 14/09/2026. Les deux valeurs dérivées de T12 (#4780B3, #74A6D0) disparaissent : pas de variante « douce », la hiérarchie se fait au corps et à la graisse. ⚠️ 3,7:1 sur le blanc de la marque, sous les 4,5:1 d'un texte courant — il tient sur un libellé court ou demi-gras, un paragraphe reste à l'encre. Nom de la variable Figma à poser par Clara. Clôt T12 |
| D18 | **`Grays/Gray` ne porte plus de texte.** Il ne sert qu'aux aplats de couleur ; tout texte secondaire est en `Grey Typo` (`inkMuted`). Hugo, 14/09/2026. Le token `inkSecondary` devient `gray`, et les 26 textes qui l'employaient — écrans d'entrée, création d'un voyage, champs de saisie — passent au gris de la marque. Clôt T18 |
| D19 | **La marge d'écran est 1 rem (16), partout, pour de vrai.** D2 l'avait tranchée et le code était resté à 24 ; Hugo la confirme le 14/09/2026 et `screenMargin` l'applique à tous les écrans d'un coup. Le paywall, qui s'était donné sa marge de 16, la reprend. Clôt T11 et T62 |
| D20 | **Lot 1 et accueil, en bloc** — Hugo, 14/09/2026. Le modèle d'authentification est réglé (T4). Le loader du Splash n'est pas prévu pour le moment, et l'écran de lancement de §9.1 a de toute façon remplacé le Splash (T6). Les compteurs sont en français, R9 s'applique (T13). La pastille de comptage compte les voyages de la liste, dont toutes les cartes sont visibles — le « ×8 » de la maquette était une erreur (T15). `Green Lighter` sur le point « en ce moment » est confirmé (T17). La copie des états de la boîte d'information est relue (T19) et `Beige Darker` confirmé pour son fond (T20) |
| D21 | **Profil, en bloc** — Hugo, 14/09/2026. Les quatre coquilles sont corrigées dans Figma, et donc dans le code (T17). « Confidentialité » ne vit que dans le bloc des conditions d'utilisation (T18). La sélection reste bleue (T19), le montant passe par le formateur du système (T20). Le dessin groupé de « Ajouter une carte » convient, son « + » passe devant (T21). Un compte sans adresse ou sans carte lit « Ajouter une adresse » / « Ajouter une carte » en General Sans Regular 13 vert, et l'état sans commande reprend la carte de la maquette `3162:34917` (T22). La suppression du compte a ses deux modales, `3203:21809` et `3206:21854` (T23). Le crayon est sur le nom et le téléphone, petit, sans cerne, au bord droit de la colonne (T24). Le rayon d'écran (T26) et « Gérée par ton compte Apple » (T27) sont validés |
| D22 | **Accueil d'un voyage** — Hugo, 14/09/2026. Le filtre « Étapes » est retiré pour le moment (T30). Les icônes que le jeu de marque n'a pas restent des symboles système : à terme, toutes les icônes seront dans la DA (T32). Les points à trancher sur la carte attendent la v2 (T33) |
| D23 | **Ce qui a été redessiné dans Figma** — Hugo, 14/09/2026. Le *Welcome* est redessiné et ne vouvoie plus : il reste à le redévelopper (T8, → T106). Les états d'erreur du *Sign Up* sont dessinés — validation, adresse déjà prise, serveur — et l'état de chargement avant l'inscription est le Splash (T9, → T107) |

| D24 | **Le genre se déduit du prénom, et se corrige dans le profil** — Hugo, 17/09/2026 (T76). Femme, homme, ou « je ne préfère pas répondre », juste sous l'adresse postale. Il ne sert qu'à accorder « Abonné(e) » ; le serveur devine, la personne l'emporte |
| D25 | **« 1ère », partout.** L'ordinal s'abrège comme la maquette l'écrit, et non « 1re » — Hugo, 17/09/2026 (T91). « 4e » reste |
| D26 | **Les coquilles de la maquette se corrigent des deux côtés.** Quand Hugo dit qu'une faute est corrigée dans Figma, le code suit sans attendre un nouvel export (T49, T67, T92, T113) — R8 vaut pour la copie voulue, pas pour la faute |
| D27 | **Les étapes Contexte et Ratio quittent le parcours de création**, code gardé — Hugo, 17/09/2026. Le brouillon part avec leurs valeurs par défaut ; les réglages du voyage les portent toujours |
| D28 | **La pastille « Mis à jour » s'éteint** — Hugo, 17/09/2026. Le balayage et le clignotement des chiffres suffisent ; elle reviendra peut-être pour l'aperçu PDF |
| D29 | **Un seul cadrage du M** derrière tous les écrans, celui du design system — Hugo, 17/09/2026 (T63) |
| D30 | **Chaque ticket dit son écran** — troisième colonne « Écran / parcours » dans toutes les tables de tickets, à partir du 17/09/2026 |

### 7.2 Ce qui reste ouvert

Tant que Clara n'a pas arbitré, on applique R4 (les variables Figma gagnent) et on
n'harmonise rien de sa propre initiative.

| # | Sujet | État |
|---|---|---|

---

## 8. Lot 1 — Entrée dans l'app

Trois écrans, tous en 390 × 844. *Welcome* a été relevé au `get_design_context` : ses
valeurs sont fines et fiables. *Splash* et *Sign Up* n'ont pour l'instant que le
`get_metadata` et les variables — **leurs couleurs par nœud, ombres et rayons restent à
confirmer par `get_design_context` au moment d'implémenter**.

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

**À trancher** : T6 (hauteur du loader), durées ci-dessus. Le fond suit D1
(`Scheme/Background Light` = Beige `#FCF2E9`), la teinte du loader reste à lire sur le
nœud.

---

### 8.2 Welcome Screen

- **Nœud Figma** : `2552:27407` —
  [ouvrir](https://www.figma.com/design/kytPYFno7PvDciIKTxCujK/MemoBook---Product?node-id=2552-27407)
- **Vue** : `MemoBookFeature/Onboarding/WelcomeView.swift`
- **Rôle** : présenter la promesse produit en trois bénéfices, puis envoyer vers *Sign Up*.
- **Entrée / sortie** : depuis *Splash* → CTA vers *Sign Up*.

**Structure (en rem)** — l'écran est une **colonne** (`VStack`) centrée, marge
horizontale 1 rem (D2), padding vertical 1.5 rem, **espacement uniforme de 1.5 rem**
entre tous les blocs (Figma : 22, arrondi R2).

| Bloc | Figma | rem | Note |
|---|---|---|---|
| Pastille « tagline » | hug, px 8 / py 2, r 20 | px 0.5 / py 0.125, r 1.25 | Fond White, bordure 1 pt Green, texte Green |
| Titre | 332 de large, centré | 20.75 | Largeur conservée : c'est elle qui fixe les retours à la ligne |
| Sous-titre | pleine largeur | 22.375 | Aligné à gauche, gris |
| Carte bénéfice ×3 | voir ci-dessous | 22.25 × 5.75 mini | Inclinaison conservée, taille uniformisée |
| CTA | 342 × 48 → pleine largeur | 22.375 × **3** | Hauteur 3 rem ✅ ; py 0.75 + contenu 1.5 |

**Les trois cartes bénéfices**

L'inclinaison est **intentionnelle et se garde au degré près** (D4) :

| Carte | Rotation |
|---|---|
| 1 · Assistant vocal & écrit | **−1°** |
| 2 · Photos & stickers instantanés | **+1°** |
| 3 · Carnet imprimé d'exception | **−1°** |

Les **dimensions**, elles, sont uniformisées : Figma donne trois largeurs différentes
(354.6, 365.2, 362.8) parce que les cadres épousent leur texte. Les hauteurs, elles,
étaient déjà identiques (92.76). Spécification commune aux trois :

| Propriété | Valeur | Note |
|---|---|---|
| Largeur | **22.25 rem** (largeur de contenu − 0.125 rem) | Les 2 pt retirés absorbent le débord de la rotation : un cadre de 22.25 rem incliné de 1° occupe 357.6 pt et reste dans la marge |
| Hauteur | **5.75 rem** minimum, grandit avec le contenu | Ne jamais figer : le texte doit pouvoir s'étendre en Dynamic Type |
| Padding | 1 rem horizontal (Figma 15 → R2), 1.25 rem vertical | |
| Rayon | 1.25 rem | |
| Fond / bordure | White / 1 pt Blue | Le trait reste en points (R1) |
| Espacement interne | 0.75 rem entre icône, texte et flèche | |
| Fond d'icône | **2.75 × 2.5 rem**, rayon 0.75 rem, Blue à 30 % | Uniformisé : Figma donne 46.9 / 44.4 / 36.3 de large |
| Icône | hauteur **1.25 rem**, ratio d'origine préservé | Jamais déformée |
| Bloc texte | occupe la largeur restante (14.5 rem à 390) | Titre 1 rem Semibold, description 0.75 rem Regular, 0.25 rem d'écart |
| Flèche | 1.5 rem, à droite | `keyboard_backspace` retournée (miroir vertical + 180°) |
| Pastille `Number` | 1.625 rem, fond Blue, chiffre Sora SemiBold 1 rem blanc | À 1.5 rem du bord droit, **débordant du cadre de la moitié de sa hauteur** (0.8125 rem au-dessus) — le débord est le dessin, ne pas le rentrer |

**Tokens** : `Scheme/Background Light` #FCF2E9 (fond d'écran) · `Brand Colors/White`
#FFFCF8 (cartes, tagline) · `Scheme/Text` #2D231A (titre) · `Brand Colors/Black` #2D231A
(texte des cartes) · `Grays/Gray` #8E8E93 (sous-titre) · `Brand Colors/Green` #28654B
(CTA, bordure et texte de la tagline) · `Brand Colors/Blue` #AFD2F0 (bordures de cartes,
pastilles, et à 30 % pour les fonds d'icônes) · `Text Sizes/Text Regular` 16.

**Typographie** : titre Sora Bold 2 rem / interligne 35 / approche −0.408 · tagline
General Sans Medium 0.875 rem / interligne 22 / approche −0.408 · sous-titre et titres de
carte 1 rem (Regular / Semibold) interligne 1.3, approche +0.16 · descriptions General
Sans Regular 0.75 rem, approche +0.12 · CTA General Sans Medium 1 rem.

**Composants** : `Button` (partagé, aussi sur *Sign Up* — fond Green, rayon 1 rem,
icône `arrow_right_alt` 1.5 rem **à gauche** du libellé, ensemble centré) · `Number`
(pastille, partagée) · `BenefitCard` (spécifique) · `Tagline` (pastille).

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
- CTA : « Découvre MemoBook »

> ⚠️ **Deux phrases vouvoient** (« Parlez simplement », « Ajoutez vos photos ») alors que
> l'app tutoie partout ailleurs — R9. Ce sont des coquilles de maquette (T8) : à réécrire
> dans Figma par Clara. On implémente la copie de Figma en l'état et on n'attend pas la
> correction pour livrer l'écran.

**États** : nominal uniquement. Écran statique, aucun chargement.

**Contrat back-end** : aucun.

**Assets** : icône micro (vector `2552:27454`), `photo` (`2553:27481`), `book.fill`
(`2553:27484`), `keyboard_backspace` ×3, pastilles `Number` 1/2/3.

**Accessibilité** : chaque carte est **un seul élément** VoiceOver (titre + description
regroupés) ; la pastille numérotée devient partie du label (« Étape 1 sur 3 »). La
rotation est décorative : elle ne doit pas être annoncée, et le texte reste lu à
l'horizontale. AX3 : les cartes grandissent en hauteur, jamais de troncature — vérifier
que le débord de la pastille ne recouvre pas le titre quand la carte s'allonge.

**À trancher** : T8 (les deux phrases qui vouvoient), présence ou non d'un « passer » ou
d'un indicateur de progression. La marge (D2), la palette (D1), les polices (D3) et
l'inclinaison (D4) sont tranchées.

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
| Marge d'écran | 16 | **1** | ✅ C'est cet écran qui a fixé la valeur commune (D2) |
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

**Tokens** : `Scheme/Text` #2D231A · `Brand Colors/White` #FFFCF8 (champs) ·
`Scheme/Background Light` #FCF2E9 (fond) · `Brand Colors/Grey` #C8C8C8 (bordures
probables) · `Grays/Gray` #8E8E93 (placeholders) · `Size/medium` 16 · `Size/xlarge` 32.
Le CTA suit le `Button` du *Welcome* : fond `Brand Colors/Green` #28654B, rayon 1 rem.

**Composants** : `Toggle` (segmenté, partagé avec *Sign In*) · `TextField` MemoBook
(hauteur 3 rem, retrait 1.5 rem, rayon à confirmer) · `Button` · `SocialButton` ×3.

**Copie** (verbatim) : « Crée ton compte » · « pour commencer à raconter ton histoire » ·
« Prénom » · « Nom » · « Email » · « Mot de passe » · « Confirme ton mot de passe » ·
« Ou continue avec ». Libellés du `Toggle` et du CTA à lire dans les instances.
L'écran tutoie de bout en bout ✅ (R9) — les messages d'erreur à écrire devront suivre :
« Vérifie ton adresse email », pas « Veuillez vérifier votre adresse email ».

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

**À trancher** : **T4 (bloquant)**, T9 (états non maquettés), identité du troisième
fournisseur social, présence de CGU / politique de confidentialité à cocher — absente de
la maquette mais généralement exigée à la création de compte.

---

---

## 9. Lot 3 — Accueil

> **Scotch** (ex-T14) : l'élément qui dépasse en haut de la carte du voyage en cours est
> un **bout de scotch**, pas un onglet de pile. Il est donc dessiné **par-dessus** la
> carte, translucide — on voit le bord au travers, c'est ce qui trahit un adhésif — et de
> travers. Décidé par Hugo le 04/09/2026.

> **Quand le M s'écrit** (décidé le 04/09/2026). Le tracé n'est pas une marque
> d'ouverture, c'est **l'attente de l'accueil** : il ne s'écrit qu'en allant vers
> l'accueil, et pendant que celui-ci se charge. Quelqu'un qui n'a pas encore de
> compte arrive donc directement sur l'écran d'entrée, sans animation devant, et
> l'écran d'accueil du tout premier démarrage n'en a pas non plus. Un seul chemin
> le déclenche, `RootView.enterApp(as:)`, qu'on vienne d'une session restaurée ou
> d'un formulaire tout juste envoyé.

### 9.1 Écran de lancement (le M qui s'écrit)

- **Source** : `Animated Cutout.svg` (Brand & Com ▸ Logo MemoBook ▸ 🎨 Branding) + la
  maquette d'accueil fournie par Hugo. **Pas de nœud Figma** : cet écran n'est pas dans
  le fichier *Product*, il remplace le *Splash Screen* de §8.1.
- **Vues** : `MemoBookFeature/Onboarding/LaunchView.swift`,
  `MemoBookDesign/BrandMark.swift`.
- **Rôle** : couvrir le démarrage. Le M s'écrit d'un trait sur le crème, puis s'efface
  en fondu pendant que le contenu de l'accueil monte du bas. **Plus de squelette**
  sous le tracé depuis le 18/09/2026 (Hugo) : le signe, puis la cascade, rien d'autre.
  Et le tracé commence **dès qu'un jeton est au trousseau** — la vérification de la
  session se joue dessous, pas avant.

**Structure**

| Élément | Valeur | Note |
|---|---|---|
| Fond | `Scheme/Background Light` | |
| Signe | 2 × la largeur de l'écran | Décalé de +0.15 en largeur, +0.09 en hauteur, en fractions d'écran |
| Trait | 164.949 / 1850 de la largeur du signe | Le rapport du SVG, conservé à toutes les tailles |
| Couleur | `Brand Colors/Blue` à 90 % | `opacity="0.9"` du SVG |
| Squelette | barre 196 × 26, rond 40 | Aux coordonnées exactes de l'en-tête de l'accueil (`HomeMetrics`) |

**Animation** — le tracé dure **0,95 s** sur la courbe du fichier de marque,
`cubic-bezier(0.884, 0.01, 0.302, 0.99)`. Le signe arrive à 97 % et se détend jusqu'à 100
% (`.smooth`, 1,2 s). La sortie est un fondu + montée à 1,06 sur 0,6 s, pendant que
l'accueil entre en fondu et que ses blocs montent de 14 pt en cascade (0,55 s, 0,07 s de
décalage par bloc).

**Le tracé n'est pas une image.** Le `d` du SVG est recopié courbe par courbe dans
`BrandMark`, un `Shape` : c'est la seule façon de le faire s'écrire avec `.trim(to:)`.
Une image vectorielle sait s'afficher, pas se tracer. Le `transform` du SVG
(`rotate(-5.54°)` puis `translate`) est appliqué tel quel, et le cadrage tient compte du
débord de la moitié de l'épaisseur du trait.

**États** : nominal uniquement. Aucune attente réseau — l'écran ne dure que le temps de
son animation, il ne peut donc pas rester bloqué.

**Contrat back-end** : aucun.

**Accessibilité** : `accessibilityLabel` « MemoBook, chargement en cours » sur le bloc,
signe masqué. **Reduce Motion** : pas de tracé, le signe est posé entier
pendant 0,4 s.

**À trancher** — l'`UILaunchScreen` d'iOS affiche encore le logotype vert (`LaunchLogo`)
avant cet écran : on voit donc **deux marques à la suite**, le mot MemoBook puis le M. La
maquette ne montre que le M. Vider `UIImageName` pour ne garder que le crème rendrait
l'enchaînement continu — décision de marque, pas de code.

---

### 9.2 Accueil

- **Nœud Figma** : `3116:30733` —
  [ouvrir](https://www.figma.com/design/kytPYFno7PvDciIKTxCujK/MemoBook---Product?node-id=3116-30733).
  Seul `get_variable_defs` a pu être appelé (quota Starter épuisé à l'appel
  suivant) : les **couleurs** viennent donc du nœud, les **mesures** restent
  relevées sur l'image et à confirmer.
- **Vues** : `MemoBookFeature/Home/` — `HomeView`, `TripCards`, `TripCover`,
  `HomeSections`, `HomeModel`, `TripFormatting`, `HomeFixtures`.
- **Rôle** : où en sont tes voyages, et le micro toujours à portée de pouce.
- **Entrée / sortie** : depuis le lancement (session valide) → détail d'un voyage,
  profil, impression, exemples de carnet.

**Structure (en rem)**

| Élément | rem | Note |
|---|---|---|
| Marge d'écran | 1.5 | `screenMargin`, valeur actuelle du code (D2 dit 1 — voir « À trancher ») |
| Espacement entre sections | 2 | |
| Espacement entre cartes | 1 | |
| Rayon de carte | 1.25 | `largeCornerRadius` |
| Rayon d'une couverture | 0.875 | `cornerRadius` |
| Retrait de la couverture dans la carte | 0.5 | |
| Marges du bloc de texte | 1 | |
| Couverture, voyage en cours | 16:9 | |
| Couverture, voyage passé | 5:2 | Bande plus basse : hiérarchie entre en cours et terminé |
| Avatar de profil | 2.5 | Cible tactile portée à 2.75 |
| Pastille de compagnon | 2.125, figée | Décoration masquée à VoiceOver, comme la pastille de `WelcomeStepCard` |

**Tokens ajoutés** — `MemoBookColor.accent` (`Scheme/Accent`, Lime #E2F32B, pastille de
comptage) · `MemoBookColor.hairline` (`Scheme/Borders`, #2B231B à 10 %, filets et
squelette) · `MemoBookColor.inkMuted` (`Brand Colors/Grey Typo`, #2B231B à 50 %, **tout
le texte secondaire de cet écran**) · `MemoBookColor.actionLight`
(`Brand Colors/Green Lighter`, #3D9A6F, le point « en ce moment ») ·
`MemoBookFont.greeting` (**General Sans Regular** 24) · `.heading` (Sora SemiBold 20) ·
`.label` (General Sans Medium 14) · `.overline` (General Sans Semibold 12).

Les deux couleurs viennent du nœud et sont désormais recopiées dans
[`agents/design.md`](../agents/design.md) (R4).

**Composants** — `BrandButton` gagne deux axes plutôt qu'un deuxième bouton :
le style `soft` (aplat crème sans contour, pour les actions posées dans une carte) et
`isRound` (variante ronde). Spécifiques à l'écran : `FeaturedTripCard`,
`CompactTripCard`, `PastTripCard`, `ShowcaseCard`, `HomeSectionHeading`, `CountBadge`,
`StageBadge`, `DestinationLabel`, `TripStatsRow`, `TripCover`, `CompanionStack`.

**Copie** (verbatim, hors données)

- Salutation : « Bienvenue {prénom} 👋 » — espace insécable avant la main
- Sections : « Tes voyages en cours » · « Tes voyages précédents »
- Pastille d'état : « EN COURS »
- CTA : « Commencer à enregistrer »
- Découverte : « Voir des exemples de carnet » / « Découvre à quoi ressemble un carnet
  MemoBook terminé »
- État vide : « Ton premier carnet commence ici » / « Raconte ta journée à la voix :
  MemoBook s'occupe du reste. »

**États** — les quatre sont traités. *Chargement* : l'écran de lancement (§9.1).
*Vide* : `HomeEmptyState`, non maquetté, écrit ici. *Erreur* : `ErrorBanner` en ligne
au-dessus des sections, avec « Réessayer ». *Nominal* : la maquette.

**Contrat back-end** — **aucun appel**. L'écran lit un `HomeFeed` fourni par une closure
passée à `HomeModel` ; c'est aujourd'hui `HomeFeed.fixture`. Les modèles
(`Trip`, `Destination`, `TripStats`, `Companion`, `Traveller`, `Showcase`, `HomeFeed`)
sont dans `MemoBookCore` et déjà `Codable`, taillés pour la réponse à venir. La route
reste à écrire : un `GET /v1/home` qui rend ce `HomeFeed` d'un coup, ou la composition
de `GET /v1/trips` + le profil. Le drapeau se **dérive** du code ISO, il ne se stocke
pas.

**Assets** — l'écran emploie le **jeu d'icônes de marque**
(`assets/icons/brand-icons`, importé par `ios/Tools/import-brand-icons.py`, documenté
dans son README) : `IconUser` (profil), `IconPrinter` (impression), `IconPictureFrame`
(compteur de photos), `IconMic` (CTA). Deux pictogrammes n'existent pas dans le jeu et
restent sur un symbole système : **calendrier** (durée) et **tracé d'itinéraire**
(distance). Ils sont isolés dans `TripStatItem.Kind.icon`, un seul endroit à changer.

Les couvertures sans photo tombent sur un aplat de marque (`TripCoverPlaceholder`), pas
sur un rectangle gris. **Manque** : l'image du carnet d'exemple pour la carte bleue —
elle est dans le nœud Figma, que le quota n'a pas permis d'exporter.

> Les illustrations du *Welcome* ont été renommées `WelcomeMic` / `WelcomePhoto` /
> `WelcomeBook`. Elles ne font pas partie du jeu d'icônes : proportions libres, aplat
> bleu dans le SVG, pas de teinte. Le renommage libère les noms canoniques `IconMic`
> et `IconBook` pour le jeu.

**Accessibilité** — chaque carte est un seul élément VoiceOver, avec le trait
`isButton` · en-têtes marqués `isHeader` · décorations (onglet de page, pastilles de
compagnons, filigrane) masquées · en taille accessible, l'en-tête, la ligne
pays/état, les compteurs, la légende d'un carnet et la carte de découverte passent tous
en colonne · le CTA suit le Dynamic Type mais **s'arrête à AX1** : une barre ancrée en
bas prenait la moitié de l'écran au-delà. Vérifié sur SE 3 (375 × 667), iPhone 17
(402 × 874), 17 Pro Max (440 × 956) et en AX3.

**Localisation** — l'app déclare `CFBundleDevelopmentRegion: fr` et
`CFBundleLocalizations: [fr]`. Sans ça, `Locale.current` suivait la langue de l'appareil
et l'accueil affichait « 26 Aug–15 Sep 2026 » au milieu d'une interface française. Dates
et distances passent par `FormatStyle` : la **région** de l'utilisateur reste respectée
(un lecteur aux États-Unis lit des miles).

**L'arrivée du contenu** — chaque élément monte de 40 pt en fondu, l'un après l'autre,
0,06 s d'écart (`HomeRise`). Le rang n'est pas écrit en dur : il se calcule à partir du
contenu, si bien qu'ajouter un voyage décale tout ce qui suit. Le retard est plafonné au
dixième élément — au-delà, attendre n'ajoute rien et retarde ce qu'on voulait voir. Le
drapeau `homeContentHasAppeared` descend par l'environnement (`@Entry`), pour qu'un rang
suffise sur le lieu d'appel et qu'aucun élément ne puisse être oublié hors de la cascade.
Sans effet si Reduce Motion est actif.

L'écran ne dessine **rien** tant que le contenu n'est pas chargé : sans ce garde-fou, le
premier rendu affichait « Bienvenue 👋 » sans prénom avant de le remplacer, et la cascade
rendait le fondu croisé des deux textes bien visible. L'écran de lancement couvre cette
attente.

> ⚠️ **Deux pièges rendaient cette cascade invisible**, et ils se cumulaient.
>
> 1. `animation(_:value:)` n'anime qu'un **changement**. Le jeu d'essai revient sans
>    jamais suspendre : le contenu était monté et le drapeau levé dans la même passe de
>    rendu, donc chaque bloc naissait déjà en place. Il faut laisser passer une frame
>    (`Task.sleep` de 16 ms) entre le chargement et le drapeau.
> 2. `RootView` fondait **tout** le contenu par-dessus. Un fondu global recouvre la
>    cascade : les blocs montent bien, mais on ne voit que le fondu. Le contenu entre
>    donc en `.transition(.identity)`, et c'est l'écran de lancement qui s'efface
>    par-dessus (0,45 s) pendant que l'accueil se pose.

**Ce que porte le fond** — le M du lancement ne disparaît pas : ``BrandMarkBackdrop``
est la **même vue** pour les deux écrans, si bien qu'au passage le signe ne bouge pas
d'un pixel — seule son opacité descend de 50 % à 20 %. Il est posé **derrière** la zone
de défilement, donc il ne défile pas : c'est un décor, pas un élément de la page.

**Le voile du CTA** — 200 pt de haut, pleine largeur, `Background Light` opaque au ras du
bas et transparent en haut. Il vaut une note d'implémentation : posé en fond du bouton ou
en overlay de la `ScrollView`, il s'arrête au-dessus de l'indicateur d'accueil — la bande
où le texte restait justement lisible. Il faut l'ancrer au bas d'un cadre qui prend
**tout l'écran** (`frame(maxHeight: .infinity, alignment: .bottom)` puis
`ignoresSafeArea()`), sans quoi l'alignement `.bottom` de la pile le repince sur la safe
area et `ignoresSafeArea` l'étire vers le haut.

**À trancher**

| # | Sujet | Écran / parcours |
|---|---|---|
| T10 | **Mesures non confirmées.** Les couleurs viennent du nœud ; les espacements, rayons et tailles sont relevés sur l'image. À confirmer au premier `get_design_context` disponible | Accueil |

### 9.3 La boîte d'information de l'accueil

- **Nœud Figma** : aucun. La boîte vient d'une capture annotée par Hugo (09/09/2026) ;
  le dessin est celui de la capture, la copie est verbatim. **À faire entrer dans la
  maquette**, et à faire relire par Clara pour les trois états qu'elle n'écrivait pas.
- **Vues** : `MemoBookDesign/BrandNotice` (le bloc), `MemoBookFeature/Home/HomeNotice`
  (ce qu'il dit), `HomeView.noticeBox` (où il est).
- **Rôle** : dire où on en est de la connexion et des vocaux, sans rien demander.

**Ce n'est ni une erreur ni une alerte**, et c'est pourquoi ça ne ressemble à aucune des
deux : pas de rouge, pas de pictogramme, pas de bouton. `ErrorBanner` dit « ça a raté,
voilà pour réessayer » ; la boîte dit « voilà où on en est, tu peux continuer ». Elle
disparaît d'elle-même quand la situation change.

**Une seule boîte, quatre états, toujours au même endroit** — sous la salutation, avant
les voyages. Une bande d'état qui change de place se cherche ; deux bandes empilées ne
se lisent plus. L'ordre de priorité est celui de l'utilité, pas de la gravité :

| # | État | Message (le gras est celui de la boîte) |
|---|---|---|
| 1 | Envoi en cours | « **Ton vocal est en cours d'envoi.** Encore un instant. » |
| 2 | En attente de réseau | « **Tes vocaux enregistrés hors ligne sont bien conservés.** Ils seront envoyés dès ta reconnexion. » |
| 3 | Vocal arrivé (4 s) | « **Ton vocal est bien arrivé.** Il sera retranscrit dans quelques instants. » |
| 4 | Hors ligne | « Tu sembles hors ligne. **Tu peux consulter tes récits et enregistrer des étapes**, qui seront retranscrites plus tard. » |

Quelqu'un qui a trois vocaux en attente sait déjà qu'il est hors ligne : ce qu'il veut
savoir, c'est qu'ils ne sont pas perdus. D'où l'attente **avant** l'absence de réseau.
Chaque état a son singulier et son pluriel — « Tes 1 vocaux » est le genre de phrase qui
fait douter de tout le reste de l'app.

**Tokens** — fond `Brand Colors/Beige Darker` (`MemoBookColor.separator`, le seul aplat
discret de la palette), texte `Scheme/Text` sur 7,6:1, rayon `largeCornerRadius`, marge
intérieure `s`. Le gras est **une autre police** (General Sans Semibold) et non un
épaississement : les instances embarquées sont des familles distinctes, un `.bold()`
donnerait un faux gras. D'où le balisage `**…**`, résolu à la construction de la vue et
jamais dans un `body`.

**Ce que la boîte engage côté code** — une phrase affichée est une promesse tenue, sinon
l'écran ment :

- « tu peux consulter tes récits » ⟶ `HomeFeedCache`, le dernier accueil reçu relu depuis
  le disque quand l'appel échoue **au transport** (un 500 reste une erreur : le cacher
  derrière un contenu périmé masquerait une panne du serveur) ;
- « enregistrer des étapes » ⟶ le micro et la feuille d'enregistrement ne dépendent de
  rien du réseau ;
- « ils seront envoyés dès ta reconnexion » ⟶ `RecordingOutbox` + `PendingRecordingStore`,
  file sur disque dans `Application Support` (pas dans `Caches` : iOS les purge, et un
  vocal en attente n'existe nulle part ailleurs), vidée automatiquement au retour de
  `NWPathMonitor`.

**États limites** — un refus **définitif** du serveur (4xx) sort le vocal de la file et
s'affiche en `ErrorBanner` : garder un souvenir que le serveur refusera à chaque fois,
c'est promettre une arrivée qui n'aura jamais lieu. Une réponse illisible (décodage)
compte au contraire comme **arrivée** — l'appel a abouti, et le renvoyer mettrait le
souvenir deux fois dans le carnet. Hors ligne **avec** du contenu à l'écran, le bandeau
d'erreur de chargement se tait : la boîte dit déjà pourquoi rien ne bouge.

**Accessibilité** — la boîte est un seul élément, et chaque changement d'état est
**annoncé** (`AccessibilityNotification.Announcement`) : une coupure de réseau ne se voit
pas quand on ne regarde pas l'écran. Le texte se replie sur plusieurs lignes et suit le
Dynamic Type sans plafond.

**Bac à sable** — « Passer hors ligne » coupe **vraiment** le réseau de l'app (le vocal
suivant part sur le disque, le retour en ligne le fait vraiment repartir), « + vocal en
attente » met un vocal en file sans passer par le micro, « Envoi en cours » et « Vocal
envoyé » posent l'état passager qu'on n'aurait sinon le temps de voir qu'avec un très
mauvais réseau.

**À trancher**

| # | Sujet | Écran / parcours |
|---|---|---|

## 10. Ce qu'on ne fait jamais

- Coder une valeur numérique dans une vue au lieu d'un token
- Écrire une taille de police fixe (casse Dynamic Type)
- Substituer une icône, un rayon, une couleur « équivalente »
- Vouvoyer l'utilisateur, où que ce soit dans l'app
- Inventer un état, un libellé, une animation absents de la maquette
- Inventer un endpoint côté app en espérant qu'il existe
- Corriger une faute de français sans retour de Clara
- Harmoniser deux écrans qui divergent, au lieu de le signaler
- Fermer une PR d'écran sans la capture comparée à Figma

---

## 10. Lot 5 — Profil

### 10.1 Profil

- **Nœud Figma** : `2370:4991` —
  [ouvrir](https://www.figma.com/design/kytPYFno7PvDciIKTxCujK/MemoBook---Product?node-id=2370-4991).
  ⚠️ **Aucun appel MCP n'a pu aboutir** : le quota Starter était déjà épuisé au
  premier `get_variable_defs`. Couleurs, espacements et tailles sont donc
  **relevés sur les captures** fournies par Hugo, et tous passent par des tokens
  existants — voir « À trancher », T16.
- **Vues** : `MemoBookFeature/Profile/` — `ProfileView`, `ProfileModel`,
  `ProfileFormatting`, `ProfileFixtures`, `PostalAddressSheet`,
  `PaymentSheets`, `SubscriptionSheet`, `ConnectorsSheet`,
  `OrderTrackingSheet`. ⚠️ `SubscriptionSheet` a depuis été **entièrement
  réécrite** sur un nœud plus récent — voir §13.
- **Rôle** : qui tu es pour MemoBook, ce que tu lui as confié, et par où on sort.
- **Entrée / sortie** : depuis l'**avatar bleu en haut à droite de l'accueil**
  (`HomeIntent.openProfile`, poussé par `RootView` sur `HomeRoute.profile`) →
  retour à l'accueil, ou sortie de session vers l'écran d'entrée.

**Structure (en rem)**

| Élément | rem | Note |
|---|---|---|
| Marge d'écran | 1 | `screenMargin` — D2, appliquée à toute l'app le 14/09/2026 (T11) |
| Espacement entre groupes | 1.5 | |
| Avatar | 5, **figé** | Comme celui de l'accueil : une photo n'est pas du texte, la faire grandir en AX3 lui faisait prendre la moitié de l'écran |
| Hauteur d'une ligne | 2.75 minimum | Cible tactile ; grandit avec le Dynamic Type |
| Marges d'une ligne | 1 horizontal, 0.75 vertical | |
| Rayon d'un groupe | 1.25 | `largeCornerRadius` |
| Rayon d'un champ et d'un bouton | 1 | `controlCornerRadius` (nouveau token) |
| Hauteur d'un champ | 3.5 | `fieldHeight` — **identique à l'écran d'entrée** |
| Hauteur d'un CTA | 3.125 | `controlHeight` — **identique à l'écran d'entrée** |
| Rayon du haut d'une feuille | 1.75 | `sheetCornerRadius` (nouveau token) |

**Tokens ajoutés** — `MemoBookFont.h2` (Sora SemiBold 24 : titre d'écran
secondaire et nom propre ; **pas encore une variable Figma**, relevé entre
`App/h1` 32 et `Heading 6` 20) · `MemoBookSpacing.controlCornerRadius` (16, le
rayon que `BrandButton` et `BrandTextField` codaient déjà en dur chacun de son
côté) · `MemoBookSpacing.sheetCornerRadius` (28).

**Composants** — trois entrent dans le design system, parce que le motif
resservira :

| Composant | Ce qu'il fait |
|---|---|
| `BrandRowGroup` + `BrandRow` | **Les lignes empilées et groupées** demandées par Hugo. Une ligne se **décrit** (intitulé, valeur, chevron ou interrupteur), elle ne se dessine pas : c'est ce qui garantit qu'aucun écran n'invente sa propre hauteur de ligne ni son propre chevron. Un `@resultBuilder` permet les `if` |
| `BrandOptionGroup` + `BrandOptionRow` | Le choix unique en lignes encadrées (moyen de paiement aujourd'hui, style de carnet et typographies demain) |
| `BrandSheet` | La feuille modale : poignée, grand titre Sora, rond de fermeture, et **cran de hauteur calé sur le contenu** |
| `BrandTextField` gagne `labelPlacement` | `.floating` (l'écran d'entrée) et `.above` (les feuilles, où l'intitulé reste lisible pendant la saisie et le texte indicatif montre un exemple de valeur). **Un seul champ**, deux mises en page — CLAUDE.md interdit d'en écrire un second |
| `DeviceScreen` | Le rayon des coins de l'écran, déduit du format de la dalle. Aucune API publique ne le donne, et la clé privée qui le porte n'a rien à faire dans un binaire envoyé à l'App Store |
| `View.brandSheetPresenter(isPresented:)` + `BrandSheetPresentation` | Le recul de l'app derrière une feuille, et le compteur qui le déclenche |
| `View.brandKeyboardDismissBar()` | La barre d'accessoires du clavier, partagée par le profil et l'écran d'entrée |

Spécifiques à l'écran : `ProfileAvatar`, `ConnectorsCallout`, `ProfileExitAction`,
`ApplePayRow`, `ConnectorCard`, `ConnectorLogo`, `OrderCard`.

**La feuille modale est posée au bas de l'écran**, comme toute feuille iOS. Le
système porte son fond (`presentationBackground`) et sa forme
(`presentationCornerRadius`) ; à nous la poignée, le grand titre Sora, le rond de
fermeture, le crème et la hauteur calée sur le contenu.

> ⚠️ **La safe area compte déjà dans la marge basse.** Le défilement réserve
> l'indicateur d'accueil sous le contenu — 34 pt sur un iPhone récent — et la
> marge d'écran s'y ajoutait : 58 pt de vide en bas de **chaque** feuille, soit
> deux fois ce qu'il fallait. On ne pose donc que ce qui *manque* pour atteindre
> la marge d'écran, et rien du tout là où l'indicateur la donne déjà. Un appareil
> à bouton d'accueil, qui n'a pas de safe area, reçoit les 24 pt entiers.

> ⚠️ **Elle a flotté, détachée des bords, et c'était une erreur sur trois plans à
> la fois.** Le système dessine une ombre autour du conteneur d'une feuille :
> détachée, la carte en héritait d'un **liseré gris**. Le conteneur ne portant
> plus la forme, plus rien ne **rognait le contenu**, qui passait par-dessus les
> coins arrondis dès qu'on faisait défiler. Et le bas décroché laissait voir une
> **bande d'écran sous la feuille**. Les trois défauts n'en faisaient qu'un :
> avoir pris au système ce qu'il faisait bien. À ne pas retenter.

**L'app recule derrière — toujours, et pour toutes les feuilles.** L'écran du
dessous rapetisse (0,92), prend les coins du téléphone, et du noir apparaît tout
autour. Trois pièges, tous rencontrés :

1. *Le système ne le fait pas pour nous.* Il ne recule que la vue racine d'une
   fenêtre ; une feuille présentée depuis un écran poussé dans une pile ne
   déclenche rien.
2. *Il faut l'appliquer tout en haut*, sur
   [`RootView`](../ios/Modules/Sources/MemoBookFeature/RootView.swift) : c'est le
   seul niveau qui occupe vraiment l'écran, safe areas comprises.
3. *Le découpage des coins ne peut pas être un `clipShape`.* Le cadre d'une vue
   s'arrête au bord de la safe area, donc `clipShape` rognait le fond de l'app au
   ras de la barre d'état et laissait **deux bandes noires**, y compris quand
   aucune feuille n'était ouverte. C'est un `mask` dont la forme
   `ignoresSafeArea` : une couche de rendu, qui déborde comme le fond.
4. *Le masque vient **avant** la réduction.* Posé après, il arrondissait les
   coins de l'écran — que la carte réduite ne touche plus — et celle-ci gardait
   des angles droits.
6. *Le noir doit s'effacer avec le recul.* Posé en dur, il restait derrière la
   carte pendant qu'elle regrandissait : refermer une feuille laissait une
   **bande noire en haut et en bas** le temps du retour à l'échelle — les deux
   bandes du piège 3, revenues par une autre porte. Il est donc en opacité, il a
   le **crème de l'app** sous lui — jamais la fenêtre, qui est noire —, et le
   recul se relâche plus vite (0,2 s) qu'il ne s'installe (0,35 s) : la carte a
   retrouvé sa taille avant que la feuille ait fini de descendre.
7. *Le relâchement se lit sur la liaison, pas sur la feuille.* Branché sur
   l'apparition et la disparition de la feuille — qui **encadrent** l'animation
   au lieu de l'accompagner — le recul ne se relâchait qu'une fois la feuille
   entièrement descendue, et l'app se remettait à l'échelle d'un coup sec après
   coup. D'où ``SwiftUI/View/brandSheet(item:content:)``, **à employer partout à
   la place de `sheet(item:)`** : la liaison bascule à l'instant où la fermeture
   commence, et l'app regrandit pendant que la feuille descend.
6. *Une feuille ne monte jamais jusqu'en haut.* Son cran est plafonné pour
   laisser voir 2.75 rem de la carte de l'app au-dessus d'elle
   (``BrandSheetMetrics/appReveal``). Sans ce plafond, la feuille des six
   connecteurs venait affleurer le bord de la carte et il ne restait plus rien à
   voir de l'écran qu'on venait de quitter. La bande se compte **depuis la
   carte** et non depuis le bord de la dalle, dont la barre d'état fait 20 pt sur
   un SE et 59 sur un modèle à Dynamic Island : c'est ce qui donne le même écran
   d'un iPhone à l'autre.

Et pour que ce soit vrai de **toutes** les feuilles sans qu'aucun écran ait à y
penser, ce n'est pas l'écran qui l'annonce mais la feuille : chaque
``BrandSheet`` s'inscrit en apparaissant dans un compteur partagé
(``BrandSheetPresentation``), que `RootView` observe. Une feuille ouverte
par-dessus une autre les fait reculer toutes les deux.

**Le reste de la feuille** — le **geste** est celui d'iOS, le **dessin** est le nôtre.
On s'appuie sur la présentation modale du système : elle seule donne le glissé
élastique, le repli de l'écran du dessous, le retour arrière de VoiceOver et le
redimensionnement au clavier. Tout ce qui se voit est repris de la maquette :
poignée dessinée à la main (`presentationDragIndicator(.hidden)`), titre `h2`
Sora, rond de fermeture, crème de la marque (`presentationBackground`), rayon 28
(`presentationCornerRadius`). La hauteur est **mesurée** : iOS ne sait pas caler
un cran sur la hauteur naturelle du contenu, donc on la lit dans un
`GeometryReader` posé en fond et on en fait un `.height()` sur mesure. Un contenu
plus haut que l'écran (les six connecteurs) est ramené par le système à la
hauteur maximale et se met à défiler.

**Les lignes qui se corrigent sur place** — nom, e-mail et téléphone s'éditent
**sans quitter l'écran** : on touche la ligne, le clavier s'ouvre, la valeur est
enregistrée dès que le champ perd le focus — clavier refermé, défilement
(`scrollDismissesKeyboard(.immediately)`), passage à un autre champ, ou sortie de
l'écran. Rien à valider, comme dans les Réglages d'iOS.

**La ligne ne change pas d'apparence en se corrigeant** : ni cadre, ni aplat, ni
déplacement. Seul le curseur apparaît. Une ligne qui se transforme en champ de
saisie fait sursauter la page entière pour une information qu'on a déjà — le
clavier vient de s'ouvrir.

La valeur du modèle n'est touchée qu'**à la sortie du champ** et non à chaque
frappe : le jour où il y aura un serveur, c'est un appel réseau par correction et
non un par caractère.

Un **crayon** (`IconPen`) accompagne le nom et chaque ligne modifiable, à la
place qu'occupe le chevron ailleurs : les deux disent « cette ligne se touche »,
l'un mène ailleurs, l'autre ouvre le clavier ici. Il ne figure pas sur la
maquette — T24.

**La barre du clavier** — un chevron, pas un « OK ». « OK » laisse croire qu'on
valide quelque chose alors qu'on ne fait que ranger le clavier, et sur un écran
où l'enregistrement se fait tout seul à la sortie du champ, ce faux bouton de
validation est un contresens. Il flotte au-dessus des touches plutôt que d'y être
collé : au ras du clavier, on l'atteint en visant entre deux rangées et on tape un
caractère une fois sur trois. Même barre sur le profil et sur l'écran d'entrée.

**Le retour arrière** — l'en-tête est dessiné dans la page, pas dans une barre de
navigation : la maquette met la flèche et le titre sur une même ligne, et sur
iOS 26 un élément personnalisé de barre est enfermé d'office dans une pastille de
verre qui avale le titre (essayé, capture à l'appui). Mais masquer la barre
emporte avec elle le **glissé de retour depuis le bord**, que le système attache
à son bouton. Il est donc rendu à la main, en `simultaneousGesture` pour ne pas
casser le défilement — même montage que le balayage entre inscription et
connexion de l'écran d'entrée.

**Copie** (verbatim, hors données)

- Titre : « Profil » (« Profile » jusqu'au 14/09/2026 — T17)
- Groupe 1 : « E-mail » · « Téléphone » · « Adresse postale » ·
  « Newsletter mensuelle MemoBook »
- Groupe 2 : « Ma cagnotte » · « Mon abonnement » · « Suivi des commandes »
  (« Confidentialité » y figurait aussi ; retirée le 14/09/2026 — T18)
- Groupe 3 : « Carte bancaire enregistrée »
- Groupe 4 : « Confidentialité » · « Conditions d’utilisation »
- Carte bleue : « Ajouter des connecteurs » / « Connecter MemoBook a des
  applications externes vous permets d’étoffer vos aventures de manière
  intelligente. »
- Pied : « Exporter mes données » · « Me déconnecter » · « Supprimer mon compte »
- *Adresse postale* : « Ajoute l’adresse où tu souhaites recevoir ton carnet. » ·
  « Adresse » · « Code postal » · « Ville » · « Pays » · « Valider »
- *Mode de paiement* : « Ajoutes-en un ou choisis parmi tes cartes déjà
  enregistrées. » · « ApplePay » « disponible » · « Ajouter une carte »
- *Ajoutr une carte* : « Numéro de carte » · « Date d’expiration » · « CVV » ·
  « Nom sur la carte » · « Ajouter une carte »
- *Mon Abonnement* : ⚠️ **remplacée** — cette feuille a été entièrement
  redessinée et se lit désormais en §13. Sa copie d'origine (« Poursuis
  l’enregistrement de tes souvenirs de voyage sans aucune interruption. »,
  « / semaine (sans engagement) », « 100% de la somme versée est déduite du prix
  final de ton carnet imprimé ! », « Activer mon abonnement (1,99 €) », « Plus
  tard (consulter les souvenirs existants) ») n'est plus dans le code
- *Suivi des commandes* : « Livraison » · « Dans 5 à 7 jours » ·
  « 2 exemplaires - 50 pages »

> ⚠️ **Quatre coquilles de maquette, recopiées telles quelles (R8) et à
> reprendre dans Figma par Clara** — voir T17 :
> 1. Titre de la feuille d'ajout de carte : « **Ajoutr** une carte ».
> 2. Carte des connecteurs : « Connecter MemoBook **a** des applications » (« à »).
> 3. Même phrase : « vous **permets** » (« permet »), et surtout elle **vouvoie**
>    alors que R9 impose le tutoiement partout. Les six promesses de connecteurs,
>    elles, tutoient correctement.
> 4. Titre de l'écran : « **Profile** », orthographe anglaise au milieu d'une
>    interface française.
>
> ✅ **« Confidentialité » apparaissait deux fois**, dans le groupe 2 et dans le
> groupe 4 : c'était une erreur de maquette, la ligne du groupe 2 est retirée
> (T18, 14/09/2026). Les quatre coquilles ci-dessus sont corrigées dans Figma et
> dans le code (T17).

**États** — les quatre sont traités. *Chargement* : l'écran ne dessine rien tant
que le profil n'est pas là, même garde-fou que l'accueil. *Vide* : compte sans
adresse, sans carte, sans commande — non maquetté, écrit ici
(`TravellerProfile.emptyFixture`, « Aucune carte enregistrée », état vide du suivi
des commandes). *Erreur* : `ErrorBanner` en ligne avec « Réessayer ».
*Nominal* : la maquette.

**Contrat back-end** — **aucun appel**, sauf la déconnexion. L'écran lit un
`TravellerProfile` fourni par une closure passée à `ProfileModel` ; c'est
aujourd'hui `TravellerProfile.fixture`. Les modèles (`TravellerProfile`,
`PostalAddress`, `PaymentCard`, `Connector`, `Subscription`, `OrderTracking`)
sont dans `MemoBookCore` et déjà `Codable`, taillés pour la réponse à venir.

| Besoin | Route à créer |
|---|---|
| Lire le profil | `GET /v1/me/profile` — ou composition de `currentAccount()` et des ressources ci-dessous |
| Adresse, newsletter | `PATCH /v1/me/profile` |
| Cartes | `GET`/`POST`/`DELETE /v1/me/payment-methods` — **côté prestataire**, l'app n'envoie jamais un numéro complet à notre back-end |
| Connecteurs | `GET /v1/me/connectors` + OAuth par fournisseur |
| Abonnement | achat in-app (StoreKit), pas une route à nous |
| Commandes | `printOrders(memoId:)` existe, mais par carnet : il faudra un `GET /v1/me/orders` |
| Export des données | `POST /v1/me/export` (RGPD) |
| Suppression de compte | `DELETE /v1/me` — **obligatoire App Store 5.1.1** |

`signOut()` existe déjà et est branché : c'est la seule action de cet écran qui
agit vraiment. Les interrupteurs et le choix de carte agissent sur le modèle, en
mémoire, le temps de la session — un seul endroit à brancher.

**Assets**

- Employés : `IconArrowDuo` (retour), `IconCross` (fermeture, suppression de
  compte), `IconExport`, `IconExit`, `IconPlus`, `IconQuestion`.
- Les **six logos de connecteurs** (`ConnectorStrava`, `ConnectorAllTrails`,
  `ConnectorGarmin`, `ConnectorPolarSteps`, `ConnectorAirbnb`,
  `ConnectorBooking`) viennent de `assets/logos/connectors`, en 120 px déclarés
  en **3×** — la définition exacte d'une pastille de 2.5 rem. Ce sont des marques
  tierces : elles gardent leurs couleurs, **jamais** de
  `renderingMode(.template)`, et ne se remplacent pas par une icône du jeu
  MemoBook. Un filet très clair les entoure, sans quoi les logos blancs se
  dissoudraient dans la carte.
- `IconKeyboardDown` ferme le clavier. Elle vient de `assets/icons/brand-icons`
  (livrée le 08/09/2026) et **remplace** le double chevron provisoire
  `IconChevronDown`, qui a été retiré du catalogue — T27 est close.
- **Manquants**, faute de quota MCP pour les exporter du nœud :
  1. le **logo Mastercard** du champ « Numéro de carte » ;
  2. le **logotype Apple Pay** — remplacé par le symbole système `applelogo`
     suivi de « Pay », qui en est la composition officielle ;
  3. la **photo de couverture** de la commande en cours.
- Le **chevron** des lignes est `IconChevron`, arrivé le 08/09/2026 dans le jeu
  de marque à la place du `chevron.right` système. Il n'y en a qu'un dessin, posé
  dans `BrandRow` : gris sur une ligne, vert sur le bouton d'abonnement.
  ⚠️ Comme toutes les icônes du jeu, le trait n'occupe que le tiers de sa boîte
  de 24 — c'est la boîte qu'on dimensionne, et elle se pose donc un peu plus en
  retrait du bord que ne le faisait le symbole système.

**Accessibilité** — chaque ligne est **un seul élément** VoiceOver
(« E-mail, maylis.garde@icloud.com ») avec le trait `isButton` quand elle mène
quelque part · les lignes à interrupteur sont de **vrais `Toggle`**, dont
l'étiquette est le libellé : le geste de balayage, l'annonce « activé /
désactivé » et le rôle viennent du système · une carte de connecteur est un
`Toggle` entier, promesse comprise · le rond de fermeture d'une feuille porte
« Fermer » · les décorations (chevrons, poignée, ronds de sélection, avatar,
logos) sont masquées · en taille accessible, la valeur d'une ligne passe **sous**
son intitulé, les colonnes code postal / ville et date / CVV passent en colonne
unique, et le logo d'un connecteur passe au-dessus de sa promesse · l'avatar est
figé, seules ses initiales suivent le texte (et se réduisent plutôt que de
déborder). Vérifié sur **iPhone SE 3 (375 × 667)**, **iPhone 17 (402 × 874)**,
**17 Pro Max** et en **AX3** : rien de tronqué, rien de superposé.

**L'adresse email** — elle se corrige sur place comme le nom et le téléphone,
avec deux règles de plus. Une adresse qui ne tient pas debout est **gardée** et
signalée sous la ligne (« Vérifie ton adresse email. ») plutôt qu'effacée sous
les doigts de celui qui vient de la taper. Et une adresse venue d'**Apple ou de
Google** ne s'ouvre pas du tout : elle appartient au compte tiers, et la changer
ici ne ferait que la désaccorder de celle qui ouvre la session. La ligne le dit —
« Gérée par ton compte Apple » — au lieu de laisser quelqu'un buter dessus.

La règle de validation vit dans `MemoBookCore` (`EmailAddress`) parce que **deux
écrans la posent** : l'entrée dans l'app et le profil. Deux copies auraient fini
par diverger, et un formulaire aurait accepté ce que l'autre refuse.

**Le nom** — au repos c'est un `Text` qui se coupe en points de suspension à la
largeur disponible ; le champ de saisie n'apparaît que pendant l'édition. Un
champ qui reste posé refuse de se comprimer et poussait le crayon hors de
l'écran dès que le nom était long.

**La cascade de l'accueil** — elle attend **deux** conditions : le contenu
chargé, et le tracé du M effacé. Depuis que l'accueil se monte *derrière* le
voile plutôt qu'après lui, la seconde manquait et la cascade se jouait en entier
avant qu'on puisse la voir.

**Ce qui est délibérément inerte** — « Confidentialité »,
« Conditions d’utilisation », « En savoir plus »,
« Exporter mes données » et « Supprimer mon compte » gardent leur chevron parce
que la maquette le montre, et ne mènent nulle part parce qu'aucun écran n'est
dessiné derrière. C'est le même parti pris que les intentions non routées de
l'accueil, et il se voit en **un seul endroit** (`ProfileView.notYetRouted`).

**À trancher**

| # | Sujet | Écran / parcours |
|---|---|---|
| T16 | **Mesures non confirmées.** Aucun appel MCP n'a abouti : tout est relevé sur les captures. À confirmer au premier `get_design_context` disponible — au minimum le rayon des groupes, la taille du titre (24 supposé), la présence ou non d'un filet autour des cartes blanches (implémenté avec, par cohérence avec `homeCard()`), et la teinte de l'icône « Exporter mes données » (implémentée en `warning`) | Profil |
| T28 | **`signInProvider` n'existe pas encore côté back-end.** L'écran le lit sur le profil, le jeu d'essai le fournit ; il faudra que `GET /v1/me/profile` le renvoie, sans quoi une adresse Apple restera modifiable | Profil |

---

## 11. Lot 3 — Accueil d'un voyage

### 11.1 Accueil d'un voyage

- **Maquette** : capture fournie par Hugo. ⚠️ **Pas de nœud Figma** : les
  mesures sont relevées sur l'image, comme celles du profil, et tout passe par
  des tokens existants — voir T29.
- **Vues** : `MemoBookFeature/Trip/` — `TripHomeView`, `TripHomeModel`,
  `TripHeader`, `TripStepsSection`, `TripFixtures`.
- **Rôle** : où en est *ce* voyage, et la relance de MemoBook juste au-dessus du
  micro.
- **Entrée / sortie** : depuis **n'importe quelle carte de voyage de l'accueil**
  (`HomeIntent.openTrip`, poussé par `RootView` sur `HomeRoute.trip`) → retour à
  l'accueil.

**Structure** — deux couches, et une seule qui défile.

| Élément | Valeur | Note |
|---|---|---|
| Photo de couverture | rapport 390/440, en **plancher** | Un rapport et non une hauteur : la couverture garde ses proportions du SE au Pro Max. Un **plancher** et non une hauteur figée — voir l'encadré ci-dessous |
| Commandes | 3 ronds de 2.75 rem | Retour, impression, réglages. Posés sous la barre d'état, dont la hauteur vient de `DeviceScreen` |
| Panneau crème | rayon 2.5 rem (`overlayCornerRadius`) | Il **mord de son propre rayon** sur la photo — 2.5 rem, pas 1.5. Voir l'encadré ci-dessous |
| Pastilles de filtre | hauteur 2.75 rem, capsule | `BrandFilterChip`, dans une bande qui défile |
| Vignette d'étape | 4.75 rem | Avec le drapeau du pays dans le coin |

> ⚠️ **Le panneau mord d'exactement son rayon.** À 1.5 rem de chevauchement
> contre un rayon de 2.5, l'arc de chaque coin dépassait de 16 pt sous le bas de
> la photo : sa moitié haute découpait l'image, sa moitié basse découpait le
> crème du fond — invisible —, et la frontière entre les deux laissait une
> **encoche sombre à angle droit** dans le coin. Un coin n'a l'air d'un coin que
> si toute sa courbe tombe sur la photo. C'est revenu une fois ; la valeur est
> maintenant tirée du rayon lui-même, plus d'un cran de l'échelle.

> ⚠️ **La hauteur de la couverture est un plancher, pas une hauteur.** Figée,
> elle rognait tout en taille de texte accessible : les compteurs, qui s'empilent
> alors les uns sous les autres, débordaient par le haut et venaient se poser sur
> la flèche de retour. L'en-tête est donc une **pile** dont le contenu décide de
> la hauteur, la photo passant en fond — rien ne peut en sortir.

**Tokens ajoutés** — `MemoBookSpacing.overlayCornerRadius` (40) ·
`DeviceScreen.width` (hauteur minimale d'une bannière pleine largeur, sans
`GeometryReader`).

**Composants**

| Composant | Ce qu'il fait |
|---|---|
| `BrandFilterChip` | **La** pastille de filtre. Elle ne porte pas l'action : elle sert d'étiquette à un `Menu`, qui apporte la liste, les coches et VoiceOver. Deux états seulement — au repos un contour, active le vert de la marque : un filtre posé doit se voir de loin, sinon on cherche pourquoi la liste est courte |
| `View.brandHiddenNavigationBar()` | Masque la barre **et rend le glissé de retour** qu'elle emporte. Extrait du profil, qui le portait seul, à sa deuxième occurrence |
| `TripStatsRow` (étendu) | Le même composant qu'à l'accueil, avec deux emplois : réparti sur une carte, ou serré et teinté de blanc sur une photo. Les règles qui comptent — pluriels, unités, empilement en AX — restent partagées |
| `CompanionStack` (étendu) | Gagne un nombre de pastilles visibles et un **total**, pour afficher « +24 » sans que le serveur envoie vingt-quatre visages. Puis un slot `onAdd` : le « + » d'invitation vit **dans** la pile, pas à côté — posé en frère dans la rangée, il se retrouvait espacé de 0.5 rem quand les visages se recouvrent d'un cinquième, et flottait à côté du groupe au lieu d'en faire partie. Sa cible tactile reste à 2.75 rem, les cinq points de marge repris en négatif pour que le recouvrement soit celui des visages |

**Le texte blanc sur une photo qu'on ne choisit pas** — c'est le seul endroit de
l'app où le contraste ne se calcule pas d'avance : une couverture claire rendrait
le titre illisible. Deux voiles dégradés le garantissent, un en haut pour les
commandes, un en bas pour le titre, et le milieu de la photo reste net. Ils sont
donc du **dessin**, pas de la décoration.

**Les filtres** — Pays, Étapes et Transports se **combinent** : choisir un pays
*et* un transport ne garde que ce qui satisfait les deux. C'est ce qu'on attend
d'une barre de filtres, et ça évite d'avoir à expliquer une règle de priorité.
Chacun est un `Menu` portant un `Picker`. ⚠️ **L'intention de « Étapes » est
supposée** : filtrer la liste sur une étape. C'est la lecture littérale d'un
filtre, mais elle mérite confirmation — T30.

Deux corrections après relecture en simulateur (Hugo, 09/09/2026) :

- **« Transports » n'avait pas de pictogramme.** Le symbole système qui tenait
  la place (`arrow.triangle.turn.up.right.diagonal`) ne se dessinait tout
  simplement pas, et la pastille gardait un trou à gauche de son libellé. C'est
  un **train** de Lucide qui le remplace — aucune icône de transport dans le jeu
  de marque, voir §13 et `MemoBookDesign/LucideIcon.swift`.
- **La bande se comporte comme celle de la galerie** : `contentMargins` au lieu
  d'un `padding` sous `scrollClipDisabled`, et un fondu à ses deux bords. Une
  pastille verte qui sortait par la gauche se retrouvait tranchée à la verticale
  contre le bord de l'écran ; elle s'y efface maintenant.

**Copie** (verbatim, hors données) — « Continuer à enregistrer » · « Pays » ·
« Étapes » · « Transports » · « Etape n°1 » · « avec … »

> ⚠️ **« Etape n°1 » sans accent** sur le E : c'est la copie de la maquette,
> recopiée telle quelle (R8). À reprendre dans Figma — T29.
>
> ⚠️ Les compteurs de la maquette sont en **anglais** et sans unité (« 10 days »,
> « 37km », « 24 »). L'écran emploie le formateur de l'accueil — « 10 jours »,
> « 37 km », « 24 photos » — qui connaît les pluriels et les unités du lecteur.
> Écart assumé, comme celui du montant en euros (T20).

**États** — les quatre sont traités. *Chargement* : l'écran ne dessine rien tant
que le voyage n'est pas là. *Vide* : deux vides très différents, un voyage sans
étape (« Le voyage commence ici ») et un filtre qui ne laisse rien passer
(« Aucune étape ne correspond », avec « Tout afficher ») — **aucun n'est
maquetté**. *Erreur* : `ErrorBanner` en ligne. *Nominal* : la maquette.

**Contrat back-end** — **aucun appel**. L'écran lit un `TripDetail` fourni par
une closure passée à `TripHomeModel` ; c'est aujourd'hui `TripDetail.fixture(id:)`,
qui **reprend le voyage de l'accueil** plutôt que d'en réinventer un — ouvrir une
carte doit mener à ce qu'elle montrait. Les modèles (`TripDetail`, `TripStep`,
`TripTransport`) sont dans `MemoBookCore` et déjà `Codable`.

| Besoin | Route à créer |
|---|---|
| Le voyage ouvert | `GET /v1/trips/:id` — voyage, relance, étapes, collaborateurs |
| Les étapes | comprises dans la réponse ci-dessus, ou `GET /v1/trips/:id/steps` si elles se paginent |
| La relance | calculée côté serveur à partir des récits déjà envoyés |
| Inviter un collaborateur | `POST /v1/trips/:id/companions` |
| Les visages croisés en chemin | **v2** — voir D8 |
| Impression, réglages du voyage | écrans non dessinés — voir `docs/reglages-utilisateur.md` |

**Accessibilité** — les compteurs, le titre et le groupe de collaborateurs sont
des éléments VoiceOver uniques · les trois ronds de commande portent leur nom
(« Retour », « Imprimer ce carnet », « Paramètres du voyage ») · la photo, les
voiles, les pastilles et les drapeaux sont masqués · en taille accessible, les
compteurs s'empilent, les deux groupes de personnes passent l'un sous l'autre, et
la vignette d'une étape passe au-dessus de son texte · le libellé du CTA s'arrête
à AX1, où « enregistrer » devient plus large que le bouton entier. Vérifié sur
iPhone 17 et en **AX3**.

**Ce qui est délibérément inerte** — impression, réglages du voyage, invitation,
micro et ouverture d'une étape. Même parti pris que l'accueil et le profil, et il
se voit en un seul endroit (`TripHomeView.notYetRouted`).

**À trancher**

| # | Sujet | Écran / parcours |
|---|---|---|
| T33 | ⏸️ **En stand-by (D22)** — Hugo, 14/09/2026 : les points à trancher concernant la carte attendent la **v2** de l'app, la carte en fait partie | Accueil d'un voyage |

---

## 12. Lot 3 — Les états de l'accueil

Quatre maquettes fournies par Hugo, plus les états qu'elles impliquent. Elles
**changent la copie et la structure** de §9 : ce qui suit fait foi.

**Ce qui change de nom** — « Tes voyages en cours » devient **« Ton voyage »**
(au singulier, point vert conservé) et « Tes voyages précédents » devient
**« Voyages précédents »**.

**La section « Voyage à venir »** apparaît quand il y a un voyage prévu, ou
quand il n'y en a **aucun en cours** — l'invitation à en préparer un n'a de sens
que dans ce second cas. Vide, elle porte un cadre en pointillés : « Commence à
planifier ton prochain voyage » / « Clique ici pour voir le carnets de la
communauté ».

**La section « Voyages précédents » est toujours là**, même vide : c'est une
promesse, et son cadre en pointillés le dit — « Tes voyages passés s'afficheront
ici ».

**L'appel à l'action change avec l'état** : « Commencer à enregistrer » avec le
micro tant qu'un voyage est en cours, « Créer un nouveau voyage » sinon. Un micro
devant quelqu'un qui n'a aucun carnet ouvert ne mène nulle part.

**L'avancement du carnet** — « 5 souvenirs et 2/80 pages » et sa jauge, sur la
carte du moment comme sur les cartes compactes. Deux compteurs et une cible dans
le modèle (`TripProgress`), pas un pourcentage : « 2/80 pages » se lit, « 2,5 % »
ne dit rien. La fraction n'en est que la traduction pour la barre, bornée des
deux côtés — un carnet qui dépasse sa cible ne fait pas déborder sa jauge.

**Les pastilles**, mises à jour et réunies dans **un seul composant**
(`BrandTagPill`). Elles étaient trois dessins écrits chacun de son côté, qui
divergeaient déjà sur le rayon et la graisse. Trois tons, et trois seulement :

| Ton | Dessin | Emploi |
|---|---|---|
| `accent` | aplat lime | un décompte, un cadeau — « ×3 », « 3 étapes offertes » |
| `outlined` | contour vert | un état — « EN COURS » |
| `info` | contour bleu | une précision — « À VENIR » |

**Le solde d'étapes offertes** se pose sur l'avatar, en débordant par le haut :
c'est ce chevauchement qui la rattache à lui plutôt que de la faire flotter dans
le coin. Deux messages pour un seul compteur — tant que rien n'est consommé on
annonce un cadeau (« 3 étapes offertes »), ensuite un solde (« 2 étapes
restantes »). C'est le même chiffre, mais pas la même nouvelle.

**Le bac à sable** — un panneau en pointillés, tout en bas de l'accueil, pour
voir chaque état sans back-end : tout effacer, ajouter un voyage en cours / à
venir / passé (rejouable, destinations tirées au sort), basculer les étapes
offertes, montrer l'erreur, revenir au jeu d'essai. **Absent de l'app livrée** :
le fichier entier est sous `#if DEBUG`, et les méthodes qu'il appelle aussi. Elles
vivent dans `HomeModel.swift` et non à côté du panneau parce que les listes sont
en `private(set)` — le bac à sable peut ranger le contenu, une vue ne le peut pas.

> ⚠️ **Un bug attrapé au passage.** `pastTrips` filtrait sur « tout ce qui n'est
> pas en cours ». Depuis qu'un voyage peut être **à venir**, cette négation le
> rangeait parmi les carnets terminés — un voyage qui n'a pas commencé affiché
> comme fini. Le filtre est maintenant explicite (`== .past`), et un test le
> tient.

**Copie** (verbatim) — « Ton voyage » · « Voyage à venir » · « Voyages
précédents » · « Commence à planifier ton prochain voyage » · « Clique ici pour
voir le carnets de la communauté » · « Tes voyages passés s'afficheront ici » ·
« Créer un nouveau voyage » · « Besoin d'aide ? » · « 3 étapes offertes » /
« 2 étapes restantes »

**À trancher**

| # | Sujet | Écran / parcours |
|---|---|---|

---

## 13. Lot 5 — Les cinq feuilles de l'abonnement

### 13.1 Abonnement : mode d'emploi, état, et résiliation en trois temps

- **Nœud Figma** : `3268:26957` —
  [ouvrir](https://www.figma.com/design/kytPYFno7PvDciIKTxCujK/MemoBook---Product?node-id=3268-26957).
  Cinq frames : `Modale – Profile Non Abonné` (`3290:19693`),
  `Modale – Profile Abonné` (`3290:19751`), `Modale – Résiliation 1`
  (`3290:19777`), `Modale – Résiliation 2` (`3290:19793`),
  `Modale – Résiliation 3` (`3290:19823`).
  ✅ Contrairement au lot Profil (T16), **tous les appels MCP ont abouti** :
  `get_metadata`, `get_design_context` sur les cinq frames, `get_variable_defs`
  et `download_assets`. Les mesures ci-dessous sont lues sur le nœud, pas
  relevées sur une capture.
- **Vue** : `MemoBookFeature/Profile/SubscriptionSheet.swift` — elle remplace
  entièrement l'ancienne feuille « Mon Abonnement » du lot Profil (§10.1).
- **Rôle** : ce que l'abonnement coûte, ce qu'il rend, et les trois portes qu'il
  faut pousser pour en sortir.
- **Entrée / sortie** : ligne « Mon abonnement » du profil → retour au profil.

**Le chemin**

```
                   ┌─ pas abonné ─→ .pitch     « Comment ça fonctionne ? »
« Mon abonnement » ┤
                   └─ abonné ─────→ .current   « Mon Abonnement »
                                       │ Résilier mon abonnement
                                       ▼
                                    .keepGoing « Ton voyage continue »
                                       │ Résilier
                                       ▼
                                    .reason    « Pourquoi nous quittes-tu ? »
                                       │ Confirmer ma résiliation
                                       ▼
                                    .done      « C'est validé »
```

À chaque étape, le **bouton vert garde** l'abonnement et le **bouton rouge
avance** vers la sortie. La maquette le répète trois fois ; c'est la seule chose
qu'on n'a pas eu à décider.

> **Les cinq feuilles n'en font qu'une.** Une seule `brandSheet` est présentée,
> et c'est son contenu qui change. Empiler cinq feuilles aurait fait reculer
> l'app cinq fois — chaque `BrandSheet` recule celle du dessous (§10.1) — et une
> confirmation en trois temps se serait lue comme un empilement de fenêtres au
> lieu d'un chemin. Le cran de hauteur, lui, est remesuré à chaque étape et
> s'anime.

**Structure (en rem)** — mesures Figma converties, arrondis R2 signalés.

| Élément | Figma | rem | Note |
|---|---|---|---|
| Marge de la feuille | 24 | 1.5 | `screenMargin` |
| Écart entre blocs | 24 | 1.5 | `m` |
| Écart entre les 3 temps du rail | 21 | 1.25 | **R2** → `sectionGap` (nouveau token) |
| Écart rail ↔ texte | 18 | 1 | **R2** → `s` |
| Largeur du rail | 18,71 | 1.25 | **R2** → suit le Dynamic Type |
| Icône du rail | 16 | 1 | |
| Écart titre ↔ détail | 8 | 0.5 | `xs` |
| Écart entre les deux lignes d'un encadré | 4 | 0.25 | `xs / 2` |
| Carte « Comment résilier ? » | px 12 / py 16 | 0.75 / 1 | `snug` (nouveau token) / `s` |
| Encadré « Résiliation automatique » | px 16 / py 24 | 1 / 1.5 | `s` / `m` |
| Rayon des deux cartes | 16 | 1 | `controlCornerRadius` |
| Aplat des deux cartes | `Blue` à 50 % | | `outline.opacity(0.5)` — 0.35 ailleurs, 0.5 ici (R3) |
| Écart entre deux boutons | 16 | 1 | `s` |
| Hauteur d'un bouton | 48 | 3 | **R2** → `controlHeight` (50), la hauteur commune des CTA |
| Cartes d'options | radius 8, padding 14, gap 12 | | `BrandOptionGroup` — voir T69 |

**Tokens ajoutés** — `MemoBookSpacing.sectionGap` (20, le cran de 1.25 rem qui
manquait à l'échelle §2.2) · `MemoBookSpacing.snug` (12, le cran de 0.75 rem) ·
`MemoBookFont.cardTitle` (Sora SemiBold 16) · `MemoBookFont.calloutTitle`
(General Sans Semibold 20). Les deux polices **ne sont pas encore des variables
Figma** — même statut que `h2` (T16).

**Composants** — trois entrent dans le design system, parce que le motif
resservira :

| Composant | Ce qui change |
|---|---|
| `BrandButton` | Deux styles de plus : **`destructive`** (rouge sémantique, ni fond ni contour, mais les marges d'un bouton pleine largeur) vu **trois fois** dans ce lot, et **`accent`** (aplat lime cerclé de vert) pour « S'inscrire à nouveau » |
| `BrandTagPill` | Un ton de plus : **`accentOutlined`** (lime plein cerclé de vert, texte vert), vu deux fois — la pastille « ABONNÉE » et « VOIR UN APERÇU DE TON CARNET → » |
| `BrandSheet` | L'en-tête accepte une **pastille** (`badge:`) entre le titre et le chapeau, et un chapeau en **plusieurs paragraphes** (`paragraphs:`) — trois des cinq feuilles en ont |

Spécifiques à l'écran : `SubscriptionTimeline`, `HowToCancelCard`,
`SubscriptionCallout`, et `SubscriptionCopy` qui porte toute la copie.

**Le rail qui s'éteint** — le fil vertical des trois temps est **un fond, pas
une colonne d'icônes** : posé en `background(alignment: .topLeading)` derrière la
pile entière, il en prend la hauteur exacte sans que personne ait à la mesurer,
et les icônes tombent d'elles-mêmes en face de leur titre. Figma le dessine en
deux couches (un dégradé lime qui s'efface à partir de 69,5 %, recouvert d'une
capsule verte sur 81,3 % de la hauteur) ; on le rend en **un seul dégradé** —
vert plein jusqu'à 81,3 %, puis le lime repris à l'opacité qu'il avait déjà à cet
endroit (61,3 %) et qui finit de s'effacer sur le crème. Même image, une couche
de moins, et aucune hauteur en dur.

**Assets** — R10 respecté, et **un seul fichier nouveau** :

| Maquette | Ce qu'on emploie |
|---|---|
| « + » du rail | `IconPlus` — même tracé, à l'échelle 1,5 exactement |
| Bulle du rail | **`IconBubble`** — nouveau. Exporté du nœud, remis à l'échelle du gabarit 24 du jeu de marque, et **le miroir vertical de la maquette est cuit dans le fichier** plutôt que posé en transformation dans la vue |
| Cadenas du rail | `IconLockerOutlined` — même tracé (vérifié en rendu côte à côte) |
| Flèche « En savoir plus » / « Résilier » | **`IconArrowForward`** — nouveau, mais c'est l'export Figma tel quel : la flèche de marque pointe à gauche (`IconArrow`, employé pour « Retour »), la maquette la retourne. Baguer un asset plutôt que transformer une `Image` dans la vue, que SwiftUI ne sait pas faire proprement |
| ⊗ de « Confirmer ma résiliation » | `IconCross` — même tracé |
| × de fermeture | Voir T43 |

**Copie** (verbatim, R8) — toute dans `SubscriptionCopy`.

- *Comment ça fonctionne ?* : « Création du voyage » / « Configure ton voyage et
  attend le jour du du départ pour commencer » · « Raconte tes 3 première
  étapes » / « Une étape c'est une journée, une semaine, un lot d'ajouts à ton
  voyage (vocaux + photos) » · « Tu atteins la limite gratuite » / « Préparer ton
  carnet demande de l'energie, l'abonnement fait donc vivre notre
  application » · « Envoie illimité d'étape et mise en page illimité de tes
  souvenirs pour 1,99€/semaine » · « Résiliation automatique à la fin du
  voyage » · « Voir un aperçu de ton carnet → » · « Comment résilier ? » ·
  « L'abonnement est sans engagement. Tu l'annules quand tu veux sans perdre tes
  créations. » · « Surtout, il s'arrête tout seul à la fin de ton voyage ! » ·
  « En savoir plus »
- *Mon Abonnement* : « Abonnée » · « Tu as déjà souscrit à ton abonnement
  MemoBook, tu peux mettre en page tes récits de manière illimité. » ·
  « Résiliation automatique à la fin de ton voyage à Rome. » · « Parce que l'on
  sait que tu n'as pas besoin de notre application en dehors de tes voyages, ton
  abonnement sera résilié automatiquement dans 3 semaines. » · « Voir ma
  cagnotte » · « Résilier mon abonnement »
- *Ton voyage continue* : « Il te reste encore quelques jours dans ton voyage
  “Rome entre amis”. » · « Si tu coupes maintenant tu ne pourras plus dicter tes
  derniers souvenirs. » · « Pour rappel, ton abonnement sera résilier
  automatiquement à ton retour. » · « Attendre la résiliation automatique » ·
  « Résilier »
- *Pourquoi nous quittes-tu ?* : « Aide nous à faire évoluer l'application. » ·
  « Choisis la raison principale. » · « Je ne l'utilise plus » · « C'est un peu
  cher » · « J'ai fini mes récits » · « C'était pour tester » · « Rester abonné
  encore quelques jours » · « Confirmer ma résiliation »
- *C'est validé* : « L'abonnement s'arrête aujourd'hui. » · « Tu ne pourras plus
  dicter tes souvenirs, mais tu gardes accès à ton carnet de bord pour le relire
  quand tu veux. » · « Revenir à l'accueil » · « S'inscrire à nouveau »

> ✅ **Neuf fautes de maquette, corrigées dans le code (D12)** — c'est l'un des
> rares endroits où l'on s'écarte volontairement de R8, sur arbitrage de Hugo.
> À reprendre **dans Figma** par Clara, sans quoi l'écart reparaîtra à la
> prochaine relecture :
> 1. « attend le jour **du du** départ » → « attends le jour du départ » (mot
>    doublé, et impératif à la 2ᵉ personne).
> 2. « tes 3 **première** étapes » → « premières ».
> 3. « demande de **l'energie** » → « l'énergie ».
> 4. « **Envoie** illimité d'**étape** et mise en page **illimité** » → « Envoi
>    illimité d'étapes et mise en page illimitée » (le nom, pas le verbe ; le
>    pluriel ; l'accord).
> 5. « de manière **illimité** » → « illimitée ».
> 6. « Si tu coupes maintenant tu ne pourras plus » → virgule de subordonnée.
> 7. « sera **résilier** automatiquement » → « résilié ».
> 8. « **Aide nous** à faire évoluer » → « Aide-nous » (impératif + pronom).
> 9. L'**apostrophe** est uniformisée en typographique (’) : Figma emploie la
>    droite (') dans les trois feuilles de résiliation et les quatre raisons, et
>    la typographique ailleurs.

**Le prix est écrit une seule fois** et vient de l'abonnement, pas d'une chaîne :
`SubscriptionCopy.offerHeadline(price:)`. La maquette le colle au symbole
(« 1,99€ ») ; on passe par le formateur du système comme à la ligne « Ma
cagnotte » — même écart assumé qu'en T20.

**Le voyage est une donnée, pas un décor.** « à Rome », « “Rome entre amis” » et
« dans 3 semaines » viennent de `Subscription` (`tripDestination`, `tripTitle`,
`endsOn`). Le délai passe par `Date.relativeDelay`, qui écrit « dans 3 semaines »
ou « dans 3 jours » selon ce qui reste — et change de langue avec l'appareil.

**États** — les quatre sont traités. *Nominal* : la maquette. *Chargement* : la
feuille ne s'ouvre que depuis un profil déjà chargé. *Erreur* : aucune, rien ne
part au réseau. *Vide* : **non maquetté, écrit ici** — sans destination, sans
titre de voyage ou sans date de fin, chaque phrase se replie sur une formulation
qui ne promet pas de chiffre (« à la fin de ton voyage »). C'est l'état que
produit aujourd'hui le vrai back-end — T44.

**Contrat back-end** — **aucun appel**, comme le reste du profil. La résiliation
agit sur `ProfileModel`, en mémoire, le temps de la session.

| Besoin | État |
|---|---|
| Lire l'abonnement | `GET /v1/profile` existe, mais `serializeProfile` aplatit l'abonnement à `{ weeklyPrice, isActive }` — ni `renewsAt`, ni `cancelledAt`, ni le voyage |
| Souscrire | Achat in-app StoreKit — rien n'existe |
| Résilier | Aucune route. `schema.prisma` sait pourtant dire `status: cancelled` et `cancelledAt` |
| Rattacher un abonnement à un voyage | **Le modèle Prisma ne le prévoit pas** : `Subscription` n'a pas de lien vers `Memo`. C'est ce qui manque pour que « à la fin de ton voyage à Rome » ait quelque chose à écrire |
| Compter les raisons de départ | Aucune table. `SubscriptionCancellationReason` part dans le vide côté app |

**Accessibilité** — chaque temps du rail est **un seul élément** VoiceOver
(titre + détail), les icônes du rail et le rail lui-même sont masqués · les deux
encadrés bleus sont un seul élément chacun · les cartes de raison sont des
`BrandOptionRow`, qui portent déjà `isSelected` · le rond de fermeture porte
« Fermer » · le rail et ses icônes grandissent avec le texte, ensemble : un rail
figé derrière des lignes deux fois plus hautes ne relierait plus rien.

> **Une pastille longue peut désormais se replier.** `BrandTagPill` imposait sa
> largeur (`fixedSize()`) pour ne pas se faire écraser dans une rangée ; « VOIR
> UN APERÇU DE TON CARNET → » doublait de largeur en AX3 et sortait de l'écran.
> Passé les tailles accessibles, la pastille se replie sur plusieurs lignes.

**Vérifié** — iPhone 17 (402 × 874) aux cinq étapes, et en **AX3** sur les deux
feuilles les plus hautes : rien de tronqué, rien de superposé, la feuille passe
en défilement. ⚠️ **iPhone SE 3 (375 × 667) non vérifié** — ce simulateur n'a pas
de session ouverte et le jeton vit dans le trousseau, qui ne se recopie pas d'un
simulateur à l'autre. À reprendre à la prochaine session sur un SE connecté.

**À trancher**

| # | Sujet | Écran / parcours |
|---|---|---|
| T69 | **Les cartes d'options divergent d'un écran à l'autre.** Rayon 8 / padding 14 / gouttière 12 ici, contre 16 / 8 / 8 sur la feuille du moyen de paiement (§10.1), pour le même motif. `BrandOptionGroup` est réemployé tel quel ; à harmoniser dans Figma | Abonnement : mode d'emploi, état, et résiliation en trois temps |
| T71 | **Le voyage n'est pas rattachable à un abonnement** côté base. Sans lui, trois phrases sur cinq feuilles perdent leur donnée et se replient sur une formulation vague. À trancher avec le modèle de données avant de brancher StoreKit | Abonnement : mode d'emploi, état, et résiliation en trois temps |
| T72 | **La raison de départ n'a pas de compteur.** Les quatre réponses sont modélisées côté app et jetées à l'envoi. Où doivent-elles atterrir ? | Abonnement : mode d'emploi, état, et résiliation en trois temps |

---

## 14. Lot 3 — La conversation avec MEMO

### 14.1 Chat

- **Nœud Figma** : `3292:20278` (section « Chat »), quatre frames de 390 × 844 —
  `3292:19915` squelette, `3292:19896` conversation neuve, `3292:19870`
  conversation avec le rail de suggestions, `3292:19851` « modif à l'oral ».
- **Vues** : `MemoBookFeature/Chat/` — `ChatView`, `ChatModel`, `ChatHeader`,
  `ChatBubbles`, `ChatComposer`, `ChatSkeleton`, `ChatFormatting`,
  `ChatFixtures`.
- **Modèles et moteur** : `MemoBookCore/` — `Chat`, `ChatCopy`, `ChatAnalysis`,
  `MemoResponder`, `LocalMemoResponder`.
- **Rôle** : le voyageur raconte, MEMO écoute et relance, le carnet se remplit
  pendant ce temps-là.
- **Entrée / sortie** : depuis l'accueil d'un voyage — le CTA « Continuer à
  enregistrer » (`TripIntent.tellMore`) ou **n'importe quelle carte d'étape**
  (`TripIntent.openStep`), poussés par `RootView` sur `HomeRoute.chat`. Retour au
  voyage.

**Deux entrées, une seule conversation.** Raconter la suite et ouvrir une étape
mènent au même écran, posé à deux endroits différents du voyage : `stepId` change
le titre de l'en-tête et le lieu que MEMO connaît, rien d'autre. Un second écran
de saisie aurait dit la même chose.

**Structure** — trois couches, une seule qui défile.

| Élément | Valeur | Note |
|---|---|---|
| En-tête | `safeAreaInset(.top)`, matériau `.ultraThin` | Le fil passe **dessous** et se laisse deviner : c'est ce qui dit qu'il continue au-delà du bord |
| Avatar de l'en-tête | 2.5 rem (`avatarSide`), **fixe** | Une photo n'est pas du texte ; un avatar qui grandit pousse le titre hors de sa ligne |
| Commandes de l'en-tête | 3 × 2.75 rem, icône 1.5 rem | Sans disque, contrairement à celles de l'accueil d'un voyage : ici le fond est le crème, pas une photo |
| Bannière d'aperçu | rayon 1.25 rem, bordure 1 pt verte, fond bleu | `largeCornerRadius` ; Figma dessine 20 |
| Bulle | rayon 0.75 rem (`bubbleCornerRadius`) + queue | Figma dessine 11 → R2 ramène à 12. Plus serré qu'une carte : une bulle est une réplique |
| Queue de bulle | 7 pt de large, 3 pt de descente, **comptée dans le cadre** | Un tracé qui déborde de son rectangle se fait rogner en `clipShape` et fausse les marges |
| Largeur d'une bulle | `écran − gouttières − 2 cibles − respiration` | Déduite de ce qui l'entoure, jamais une fraction ronde : sinon les deux commandes sortent de l'écran sur un SE |
| Forme d'onde | hauteur 1.5 rem, barres de 3 pt | Figma dessine 22,6 → cran au-dessus |
| Rail de suggestions | hauteur = 1 ligne + 1 rem, jamais moins que 2.75 rem | **Hauteur explicite obligatoire** — voir l'encadré |
| Barre d'envoi | `safeAreaInset(.bottom)`, même matériau | Trois capsules à égalité de largeur au repos |

> ⚠️ **Une `ScrollView` doit se voir imposer sa hauteur dans une barre.** Elle
> est gourmande sur ses deux axes : posée dans la barre du bas, le rail de
> suggestions se faisait attribuer une hauteur plus courte que ses puces. Avec
> `scrollClipDisabled()`, elles restaient **dessinées** mais tombaient hors de sa
> zone tactile — on les voyait, et taper dessus ne faisait rien. Même piège pour
> la pastille « Retourner en bas », d'abord posée en `overlay` décalé au-dessus
> du cadre de la barre : dessinée, jamais tapable. Elle occupe désormais sa
> propre bande.

**Tokens ajoutés** — `MemoBookColor.bubbleTraveller` / `.bubbleMemo` (alias
sémantiques des styles Figma `Chat Bubble` et `Neutral/100`) ·
`MemoBookSpacing.avatarSide` (40, monté depuis `HomeMetrics` à sa deuxième
occurrence) · `MemoBookSpacing.bubbleCornerRadius` (12) · `MemoBookFont.bubble`
(General Sans Regular 17) et `.bubbleAction` (Medium 17) · `MemoBookShadow`
(`.soft` = `medium shadow`, `.raised` = `Elevation-200`) et
`View.brandShadow(_:)`.

**Composants entrés au design system**

| Composant | Ce qu'il fait |
|---|---|
| `BrandBubbleShape` | La forme d'une bulle : rectangle arrondi + queue, la queue comptée **dans** le cadre |
| `BrandChatBubble` | **La** bulle : fond, queue, marges, largeur maximale. Quatre contenus la portent — texte de MEMO, texte du voyageur, vocal, fiche |
| `BrandWaveform` | La forme d'onde, dans ses deux emplois : le micro en direct, et un vocal terminé avec sa position de lecture. **Promue** depuis `RecordingIndicator`, qui était privée à `MemoDetailView` |
| `BrandSkeleton` + `brandSkeletonShimmer()` | Les blocs gris du chargement, et **un seul** lustre qui les traverse en phase — autant d'animations indépendantes se désynchronisent en quelques secondes |
| `BrandButton.Style.raised` | Le pavé blanc **sans contour** qui tient par son ombre : le bouton « clavier » de la barre d'envoi |
| `AudioNotePlayer` (Recording) | La lecture d'un vocal. Un seul à la fois, sans délégué — `AVAudioPlayerDelegate` n'est pas `Sendable` |
| `SpeechReader` (Recording) | La lecture à voix haute d'un message, voix française forcée |
| `VoiceNoteFile` (Recording) | Où vit un vocal le temps qu'on le réécoute. ⚠️ `AudioRecorder.stop()` **efface** son fichier temporaire et ne rend que des octets |

**Le moteur de réponse** — `MemoResponder`, et `LocalMemoResponder` par défaut.

**Aucune bulle blanche ne s'écrit à la main** : chacune est produite par
l'analyse du message bleu qui la précède. Trois propriétés font la différence
entre un assistant et un décor :

1. **Une priorité stricte, pas une addition de scores.** Refus → question →
   vocal → émotion négative → message trop court → lieu → date → personne →
   chiffre → message long → émotion positive → rotation neutre. Un refus ne
   reçoit jamais une question, et une question ne reçoit jamais une relance.
2. **Aucun état mutable, aucun aléatoire, aucune horloge.** La mémoire du moteur
   est l'historique du fil : il écarte toute phrase déjà dite et descend d'un
   cran plutôt que de se répéter. Le même tour rend toujours la même réponse —
   c'est ce qui le rend testable.
3. **Le rythme est une donnée.** `MemoBeat.pauseMilliseconds` se calcule sur la
   matière : `900 + 22 ms/caractère` après un texte, `1200 + 45 ms/seconde`
   d'audio, plancher de 450 ms appliqué par le modèle. Une latence nulle — ou
   constante — est le premier signe qu'il n'y a personne en face.

L'analyse (`ChatAnalysis`) cherche des **marqueurs**, pas un dictionnaire : une
préposition devant un mot capitalisé, une unité derrière un nombre, un point
d'interrogation final. Deux règles valent d'être connues, parce que les tests les
ont attrapées :

- un nom de lieu générique ne compte que derrière un **déterminant** — « le
  marché » est un endroit, « on a marché » est un verbe ;
- « de » ne désigne un lieu que **derrière un nom de lieu générique** — « le
  marché de Testaccio » oui, « l'appartement de Camille » non.

**Copie** (verbatim) — la bulle d'ouverture entière · « Aperçu en direct » ·
« Votre Carnet prend forme » · « 5 Souvenirs - 10 pages composées » ·
« Retranscription du contexte » · « Voir plus » · « Ça me convient » ·
« J'aimerais faire des modifications à la main » / « … à l'oral » ·
« Retourner en bas » · « Record ». Tout le reste — les relances de MEMO, ses
réponses, les autres puces — est **écrit pour ce lot** et vit dans `ChatCopy`.

**États** — les quatre sont traités. *Chargement* : le squelette de la maquette.
*Vide* : l'accueil de la maquette (signe de la marque, titre, paragraphe), centré,
avec les trois puces d'ouverture. *Erreur* : `ErrorBanner` en ligne — plus un
bandeau dédié au **micro refusé**, qui mène aux Réglages ; `MemoDetailModel`
calculait déjà cet état sans qu'aucune vue le lise. *Nominal* : la maquette.

**Contrat back-end** — **aucun appel**. L'écran lit un `ChatThread` fourni par une
closure, et fait répondre un `MemoResponder` local. Les deux se remplacent d'une
ligne chacun dans `AppDependencies.chatModel(tripId:stepId:)`.

| Besoin | Route à créer |
|---|---|
| Le fil, repris d'un autre appareil | `GET /v1/trips/:id/chat` — messages, suggestions, contexte. Demande un modèle Prisma `ChatMessage`, adossé à `Memo` et à `Entry` : c'est le seul vrai travail de schéma |
| Un tour de parole | `POST /v1/trips/:id/chat` — JSON pour un texte, multipart pour un vocal, **comme `POST /v1/memos/:id/entries` le fait déjà**. La route crée l'`Entry`, enfile le job `transcribe`, appelle le répondeur serveur, et met à jour `Memo.prompt` avec la relance émise |
| La transcription | **Elle existe déjà** (`transcribeEntry`, OpenAI, français forcé) mais c'est un job : la route répondra `text: null`, et l'app appelle `awaitTranscript(of:)` — prévu pour ça dès maintenant |
| L'agent de conversation | Côté serveur, sur le motif `Transcriber` / `Redactor` : `HeuristicResponder` (le portage de ces mêmes règles) et `AnthropicResponder` (prompt système = `agents/agent-conversation.md`) |
| Le nombre de pages composées | `serializeRender` retient volontairement le payload de mise en page. **Le compteur est aujourd'hui déduit** (deux pages par souvenir) — c'est un ordre de grandeur, pas une mesure |

**Assets** — onze icônes **Lucide** (licence ISC), faute d'équivalent dans le jeu
de marque : haut-parleur, presse-papiers, appareil photo, clavier, calendrier,
étincelle, lecture, pause, arrêt, flèche bas, flèche haut. Vendues dans
`assets/icons/lucide/`, importées par `ios/Tools/import-lucide-icons.py`, et
préfixées **`IconLucide…`** exprès : à la lecture d'une vue, on voit ce qui est de
la marque et ce qui est provisoire. Écart assumé à R10 — voir T53.

**Accessibilité** — chaque bulle est un élément VoiceOver unique · les commandes
sans libellé visible en portent un, en français et en tutoiement · la forme
d'onde, les queues, le motif de fond et les emojis de puce sont masqués · un
vocal s'annonce « Vocal de 37 secondes » et se joue par action VoiceOver · le
point d'attente s'annonce « MEMO réfléchit » · les animations passent toutes par
`accessibilityReduceMotion`, lustre du squelette compris.

**Vérifié** — iPhone 17 (402 × 874), en taille standard et en **AX3**, sur les
sept états : squelette, accueil vide, ouverture, texte, vocal, fiche de
retranscription, micro armé et enregistrement en cours. En AX3, les commandes
d'un message passent **sous** la bulle, le menu burger disparaît, le champ se
limite à trois lignes, et le rail garde une seule ligne par puce et défile.
⚠️ **iPhone SE 3 (375 × 667) non vérifié** — même raison qu'au lot précédent : ce
simulateur n'a pas de session ouverte et le jeton vit dans le trousseau.

**Ce qui est délibérément inerte** — le menu burger, l'appareil photo et
« Importer des photos », les réglages du voyage, le globe, et l'aperçu du carnet.
Aucune bulle de photo n'est dessinée dans la maquette, et R3 interdit d'en
inventer une : les commandes gardent leur bouton et ne mènent nulle part, en un
seul endroit (`ChatView.notYetRouted`).

**À trancher**

| # | Sujet | Écran / parcours |
|---|---|---|

### 14.2 La barre d'envoi, état par état

- **Nœud Figma** : `3293:20279` — variante `Sending Bar`, treize valeurs de
  `property1`.
- **Vue** : `MemoBookFeature/Chat/ChatComposer.swift` — `ChatSendingBar`.

**Treize variantes Figma, quatre dispositions dans le code.** Les treize se
ramènent à quatre mises en page croisées avec deux axes — le micro est-il
disponible, et enregistre-t-on ? — plus l'état de brouillon. Écrire treize
branches aurait donné treize dessins à tenir cohérents.

| Nœud Figma | Ce que le code en fait |
|---|---|
| `start` | ``.tools``, micro disponible |
| `start sans micro` | ``.tools``, `microphoneIsDenied` |
| `Default` | ``.speaking`` — « Record » s'étire |
| `Default snas micro` | ``.speaking`` **replié sur** ``.writing`` : sans micro, « Record » ne propose rien |
| `Start Typing` / `Finish Typing` | ``.writing``, l'avion gris ou bleu selon `canSendDraft` |
| `… sans micro` | les mêmes, cerne du micro en gris et icône barrée |
| `Start Recording` | `recorder.isRecording` — pause, frise, chrono, micro allumé, envoyer |
| `Finish Recording` | `recorder.isPaused` — corbeille, frise éteinte, chrono figé, envoyer |
| `Modifying transcription` | ``.writing`` avec `isEditingTranscript` : le texte de la fiche est **déjà dans le champ**, qui monte à dix lignes et prend toute la barre — voir § 24 |
| `skeleton` | `ChatSkeleton`, qui dessine déjà la barre en blocs gris |

**Tokens ajoutés** — `MemoBookColor.send` (#5D6CF5, `chat/toolbar/input-btn-active`) ·
`MemoBookColor.disabledOutline` (#C8C8C8, `Brand Colors/Grey`) ·
`MemoBookFont.composer` (General Sans Regular 21).

**La croix, ajoutée à la maquette.** Ses états de saisie n'ont aucune commande à
gauche ; sur demande de Hugo, le burger devient une **croix** dès qu'un outil est
ouvert, et la tape ramène la barre à ses trois boutons. Elle jette un
enregistrement en cours : c'est le seul geste de la barre qui puisse perdre
quelque chose, et c'est ce qu'on attend d'une croix. En taille de texte
accessible, le burger disparaît faute de place et la croix reste — d'elle on ne
peut pas se passer.

**Le micro refusé garde sa place.** Il perd son cerne vert, porte un micro barré,
et mène aux Réglages. Un bouton qui disparaît laisse croire à un bug ; celui-là a
quelque chose à dire. `RecordingPermission.current` est relu **à chaque
ouverture** de l'écran : l'accès peut avoir été retiré pendant que l'app était en
arrière-plan.

**La frise glisse.** ``BrandWaveform`` a désormais deux rendus, et il en faut
deux :

| Emploi | Rendu | Pourquoi |
|---|---|---|
| Un vocal terminé | `Canvas`, niveaux rééchantillonnés | des centaines d'échantillons, une seule vue à mesurer |
| La capture en cours | une `Capsule` par **position** | c'est cette identité de position qui fait que seule la hauteur s'anime, et que la frise **glisse** au lieu de sauter d'un cran |

Elle se remplit depuis la gauche, puis chaque nouvel échantillon pousse les
autres — dix-neuf barres dans la barre d'envoi, un relevé toutes les 90 ms, donc
un peu moins de deux secondes de voix à l'écran. C'est le geste de la grande
feuille d'enregistrement de la branche `proprietaire-unique-et-secrets`, reprise
ici pour que les deux se comportent pareil (T61).

**La pause était déjà dans l'enregistreur**, posée par la grande feuille :
`AudioRecorder` porte `pause()` / `resume()` / `isPaused`, et la barre du chat
s'y branche telle quelle. `AVAudioRecorder` sait reprendre là où il s'est
arrêté, mais **la durée ne peut plus se lire comme « maintenant moins le
début »** : `openedAt` date l'ouverture du vocal, `accumulated` porte le temps
réellement capturé, et `startedAt` ne date plus que la reprise.

**Tout bouge au ressort.** `.spring(response: 0.34, dampingFraction: 0.62)`,
sous-amorti exprès : la barre dépasse d'un cheveu puis revient. Les dispositions
ne se remplacent pas, elles s'échangent — ce qui part rétrécit, ce qui arrive
grandit. Le chrono passe par `.contentTransition(.numericText())`, l'avion en
papier grossit en devenant bleu. Tout s'annule sous « Réduire les animations ».

### 14.3 Ajouter une photo

**Le geste suit iOS, pas MemoBook.** Une tape sur l'appareil photo demande
d'abord l'accès à la photothèque — c'est là qu'iOS propose « Autoriser l'accès
complet » ou « Limiter l'accès… », et cette décision ne nous appartient pas —,
puis pose la question en français : **Prendre une photo · Choisir dans la
galerie · Annuler**. L'appareil photo a sa propre autorisation, demandée au
moment où on le choisit.

`NSCameraUsageDescription` entre dans `project.yml` ; `NSPhotoLibraryUsageDescription`
y était déjà. « Prendre une photo » n'apparaît pas là où il n'y a pas d'appareil
photo — un simulateur —, parce que le proposer ouvrirait un écran noir.

Un refus n'est pas une impasse silencieuse : iOS ne redemande jamais, donc
l'écran affiche un `ErrorBanner` qui mène aux Réglages.

Les images sont écrites dans les **caches** avant d'entrer dans le fil, comme les
vocaux : une bulle qui garderait ses octets ferait grossir la conversation à
chaque photo, et les perdrait au premier retour d'arrière-plan.

### 14.4 Une conversation par voyage, ouverte sur une étape

**Un seul fil, et des messages qui portent leur étape.** C'était l'inverse :
un fil par étape. Un carnet se relit d'un bout à l'autre, et couper le récit en
autant de fils qu'il y a d'étapes obligeait à changer de fil pour relire la
veille. `ChatMessage.stepId` remplace ce découpage, et l'en-tête affiche
désormais le **voyage**.

Ouvrir une carte d'étape se pose donc sur le **dernier** message de cette
journée-là — `ChatThread.lastMessage(about:)` : on ne rouvre pas une journée pour
relire son début, on la rouvre pour voir où on en était. Ce qu'on raconte ensuite
se rattache à l'étape ouverte, ou à défaut à celle où le voyage en est.

> ⚠️ **Trois tentatives pour se poser.** Le fil s'ouvre ancré en bas dans une
> `LazyVStack` : les rangées du haut n'existent pas encore, et un `scrollTo` vers
> l'une d'elles ne fait alors **rien du tout** — sans erreur, sans rien. Chaque
> tentative en matérialise une partie et la suivante va plus loin. C'est laid, et
> c'est le prix d'un défilement paresseux qu'on veut ouvrir ailleurs qu'à son
> ancre.

**Le jeu d'essai arrive rempli** — une journée par étape terminée : un vocal, la
fiche que MEMO en a tirée, sa relance, la validation. Sans cet historique, ouvrir
une étape tombait sur une conversation vide, et « montre-moi où j'en étais »
n'avait rien à montrer.

### 14.5 Copier un message

Une tape sur le presse-papiers **remplace l'icône par une coche verte** pendant
une seconde, avec un petit sursaut de ressort. Elle remplace, elle ne s'ajoute
pas : c'est la même commande qui répond, et rien ne bouge autour. Une seconde,
parce que c'est le temps de la voir sans qu'elle devienne un état — au-delà, on
se demande si elle attend un second geste. VoiceOver, lui, l'annonce en
`accessibilityValue` : il n'a pas de coche à regarder.

### 13.2 Le palier freemium, et ce que la résiliation change ailleurs

- **Vues** : `MemoBookFeature/FreemiumStatus.swift` (dans `MemoBookCore`),
  `MemoBookFeature/SubscriptionSession.swift`, plus les reprises de
  `ProfileView` et `HomeView`.
- **Rôle** : résilier depuis la feuille d'abonnement doit se voir **partout
  ailleurs dans l'app**, tout de suite.

**Un seul vocabulaire pour deux écrans.** L'accueil et le profil montrent le même
parcours vu de deux endroits, et chacun le déduisait de son propre modèle : deux
calculs, donc deux occasions de diverger. ``FreemiumStatus`` porte les trois
états et **les libellés qui vont avec** ; aucune vue n'écrit plus « étapes
restantes » ni « Abonne-toi » de son côté.

| État | Pastille de l'accueil | Pastille du profil | Gros bouton lime |
|---|---|---|---|
| `subscriber` | *aucune* | « ABONNÉ » | non |
| `freeSteps` (rien consommé) | « 3 étapes offertes » | « 3 ÉTAPES GRATUITES RESTANTES » | oui |
| `freeSteps` (entamé) | « 2 étapes restantes » | idem | oui |
| `limitReached` | « Abonne-toi » | « ABONNE-TOI » | oui |

Un abonné n'a **pas** de pastille sur l'accueil : là-bas c'est un décompte, et
quelqu'un qui n'a plus rien à décompter n'a pas besoin qu'on le lui rappelle à
chaque ouverture. Son statut se lit dans le profil, où il a une raison d'être.

**Résilier ne rend pas de crédit.** Le serveur croit encore l'accueil abonné et
lui a laissé son ancien quota ; le lui rendre ferait repartir un décompte
(« 2 étapes restantes ») au lieu de proposer l'offre. Un ancien abonné passe donc
directement à `limitReached`. Un test le tient
(`FreemiumStatusTests.cancellingNeverRestoresACredit`).

**Comment l'information circule.** Les deux écrans ont chacun leur modèle,
alimenté par un appel distinct, et **rien n'est persisté** : l'accueil ne peut
pas apprendre du serveur qu'on vient de résilier. ``SubscriptionSession`` porte
donc l'information à l'envers de l'environnement, du profil vers l'accueil —
exactement comme ``BrandSheetPresentation`` porte le recul des feuilles. `nil`
tant que rien n'a été touché de la session : c'est alors la parole du serveur qui
vaut.

> ⚠️ **Le profil se reconstruit à chaque fois qu'on y revient.** Son modèle est
> un `@State` : sans la session, il repartirait du jeu d'essai — abonnement
> rétabli, résiliation oubliée dès qu'on quitte l'écran. C'est le piège qui s'est
> vu en simulateur et pas en test : la pastille du profil basculait bien, puis
> revenait toute seule. La session a donc le dernier mot **des deux côtés**, pas
> seulement sur l'accueil.

**Ce que StoreKit dira (T48).** La résiliation est immédiate aujourd'hui, et
c'est ce que la maquette écrit (« L'abonnement s'arrête aujourd'hui »). Le jour
où l'achat existe, **trois choses s'y opposeront** :

1. **L'app ne peut pas résilier.** Il n'existe aucune API pour annuler un
   abonnement auto-renouvelable à la place de la personne : on ne peut que
   l'emmener à la page d'Apple (`AppStore.showManageSubscriptions(in:)`), où
   elle annule elle-même. La feuille « Pourquoi nous quittes-tu ? » devra donc
   se poser **avant** ce renvoi, pas après.
2. **L'accès court jusqu'à l'échéance.** Après annulation, Apple continue de
   rendre l'abonnement comme actif jusqu'à `expirationDate` — c'est sa règle,
   pas la nôtre. Couper l'accès le jour même ferait perdre des jours déjà payés,
   sans remboursement : c'est un motif de rejet en revue autant qu'un mauvais
   traitement.
3. **StoreKit ne prévient pas.** L'app n'est notifiée de rien à l'annulation ;
   elle ne le découvre qu'en relisant ses transactions au lancement suivant.

Deux issues, à trancher avec Clara le moment venu : ou la copie change (« ton
abonnement s'arrêtera le … »), ou l'app coupe volontairement l'accès plus tôt
qu'Apple — ce qui n'est pas recommandé. **En attendant, l'immédiat est ce qui est
implémenté**, sur le modèle en mémoire, et c'est cohérent avec la feuille
précédente qui propose justement d'*attendre* la résiliation automatique.

**Contrat back-end** — inchangé, et c'est le nœud : ni souscription, ni
résiliation, ni lien voyage ↔ abonnement (T44). ``SubscriptionSession`` est le
pansement qui tient jusque-là, et **disparaît** le jour où `GET /v1/profile` et
`GET /v1/home` s'accordent d'eux-mêmes.

**Vérifié** — iPhone 17, parcours complet : profil abonné (pastille « ABONNÉ »,
pas de bouton lime, ligne « Mon abonnement » présente) → résiliation en trois
temps → profil résilié (pastille « ABONNE-TOI », bouton lime revenu, ligne
disparue) → retour à l'accueil, pastille « Abonne-toi » et plus aucun décompte.
Huit tests unitaires tiennent les règles sans écran
(`MemoBookCoreTests/FreemiumStatusTests.swift`).

### 13.3 Le paywall — trois écrans qui se suivent comme des stories

- **Nœud Figma** : `3297:20771` (section « Paywall ») —
  [ouvrir](https://www.figma.com/design/kytPYFno7PvDciIKTxCujK/MemoBook---Product?node-id=3297-20771).
  Trois écrans (`3297:20609`, `3297:20637`, `3297:20440`) et trois feuilles
  (`Paiement`, `Prévisualisation`, `Estimation`).
- **Vues** : `MemoBookFeature/Paywall/` — `PaywallView`, `PaywallPages`.
- **Entrée** : « En savoir plus », au bas de la feuille « Comment ça
  fonctionne ». Le paywall se présente en `fullScreenCover` **par-dessus la
  feuille, qui se referme d'abord** : c'est un écran entier, pas une feuille de
  plus, et on ne veut pas la retrouver dessous en sortant.

**Le temps passe tout seul, mais on peut le doubler.** La barre du haut se
remplit en 6 s et tourne la page ; un tapotis à droite avance, à gauche revient,
et à gauche depuis le premier écran on sort. **Le dernier écran ne s'en va
pas** : c'est celui qui porte l'offre, il attend qu'on décide.

> **Toute la minuterie tient dans le `task(id: page)`.** L'attente est
> structurée : changer de page annule la tâche en cours et SwiftUI en relance
> une. Une `Task` détachée gardée dans un `@State` pour l'annuler à la main a été
> essayée d'abord — elle enchaînait **deux écrans d'un coup**, parce que le
> minuteur qu'on annulait n'était déjà plus celui qui courait. Vu en simulateur,
> invisible en relecture.

**Les traits bleus sont des `Shape`, pas des images.** Figma décrit sur ces
nœuds une animation `path-trim` : le trait ne paraît pas, il **s'écrit**. Un SVG
posé dans un `Image` ne sait pas faire ça ; une `Shape`, si — `trim(from:to:)`
suffit. Les courbes sont donc reprises telles quelles de l'export dans
`MemoBookDesign/BrandStrokes.swift` (`BrandSquiggleDown`, `BrandSquiggleUp`,
`BrandUnderline`), rapportées au cadre reçu pour suivre la largeur de l'écran.
Les durées viennent des images-clés du nœud : **0,117 s d'attente puis 0,79 s de
tracé qui ralentit**.

**Rien ne bouge en Reduce Motion** : barres remplies d'avance, traits déjà
tracés, aucune page qui tourne toute seule. Une page qui se dérobe est
exactement ce que ce réglage demande d'éteindre.

**Tokens ajoutés** — `MemoBookFont.h1Light` (Sora **Regular** 32 : les titres du
paywall s'écrivent en deux temps, la moitié courante en Regular et la chute en
SemiBold) · `MemoBookFont.eyebrow` (Sora Regular 16) · `MemoBookFont.h3` (Sora
Regular 14, `App/h3`) · `BrandButton.Style.blue` (aplat `Brand Colors/Blue`,
libellé à l'encre — l'action qui fait simplement avancer).

> ⚠️ **Sora Regular n'était pas embarquée.** Le module ne livrait que le
> SemiBold ; l'instance 400 a été générée par
> `python3 ios/Tools/make-brand-fonts.py`, dont la table `INSTANCES` la
> mentionne désormais. Ne pas éditer les `.ttf` à la main — voir `ios/CLAUDE.md`.

**Assets** — `IconMoneyBag` est le seul fichier nouveau ; `IconPictureFrame`,
`IconPrinter` et `IconLockerChecked` existaient déjà et portent le bon tracé.

**Ce qui n'est pas fait**

| Manque | Détail |
|---|---|
| Les **trois feuilles** du nœud | `Modale - Paiement` (`3297:20490`), `Modale - Paywall Previsualisation` (`3297:20517`), `Modale - Paywall Estimation` (`3297:20574`). Les deux pastilles qui y mènent — « Voir un aperçu → » et « Voir une estimation → » — sont dessinées et **inertes**, même parti pris que les intentions non routées du profil |
| Le **cercle tracé autour du « 3 »** de l'écran 1 | Décor positionné à la main sur la maquette ; non reproduit |
| Le **cadrage du M** | `BrandMarkBackdrop` garde le cadrage du design system ; la maquette du paywall le tourne d'un quart de tour — T53 |

## 15. Lot 3 — Les carnets de la communauté

### 15.1 Exemples de carnets

- **Maquette** : capture fournie par Hugo. ⚠️ **Pas de nœud Figma** : les mesures
  sont relevées sur l'image, comme celles du profil et de l'accueil d'un voyage.
- **Vues** : `MemoBookFeature/Gallery/` — `GalleryView`, `GalleryModel`,
  `GalleryCards`, `GalleryFixtures`.
- **Rôle** : montrer à quoi ressemble un carnet MemoBook terminé, à quelqu'un
  qui n'en a pas encore.
- **Entrée / sortie** : depuis **la carte bleue de découverte** en bas de
  l'accueil (`HomeIntent.openGallery`, poussé par `RootView` sur
  `HomeRoute.gallery`) → retour à l'accueil. Le bouton du bas ressort par une
  intention : le voyage en cours, ou la feuille « Nouveau carnet ».

**La carte de découverte change de destination.** Elle portait une URL
(`Showcase.destinationUrl`) et ne menait nulle part ; elle ouvre désormais cet
écran. Sa copie vient de la base et dit maintenant « Voir des exemples de
carnet » / « Découvre à quoi ressemble un carnet MemoBook terminé » —
`prisma/seed.ts`, pas le code. Le champ `destinationUrl` reste au contrat pour
une campagne qui pointerait ailleurs.

**Structure**

| Élément | Valeur | Note |
|---|---|---|
| En-tête | flèche 1.5 rem dans une cible de 2.75 rem + `h2` | Le même que le profil : l'écran dessine son en-tête, il n'emploie pas la barre système |
| Barre de filtres | `IconFilter` 1.25 rem + pastilles 2.75 rem | Fixée en haut (`safeAreaInset`) : c'est elle qui commande la grille, elle ne part pas avec |
| Pastille | `BrandFilterChip`, variante `.toggle` | Sans chevron : elle **est** le choix, rien ne se déroule |
| Voile du haut | 1.5 rem, sous la barre | Les vignettes s'y **dissolvent** au lieu d'être coupées sur un trait |
| Vignette | rayon **1.5 rem** (`galleryCornerRadius`) | Nouveau token — voir « À trancher » |
| Gouttière | 0.75 rem, verticale et horizontale | |
| Colonnes | 2, **1 en taille accessible** | |
| CTA | 3.125 rem, pleine largeur, fixe | Même voile de 12.5 rem que l'accueil |

**La bande de filtres défile d'un seul tenant, et s'efface à ses bords.**
`IconFilter` est **dans** la bande, pas à côté : posé dehors, il restait planté
à la marge pendant que les pastilles lui passaient dessus. Et la bande prend
toute la largeur de l'écran — c'est `contentMargins(for: .scrollContent)` qui
aligne son contenu sur la colonne, **pas** un `padding` sous un
`scrollClipDisabled` : celui-là laissait une pastille sortie du cadre continuer
d'être dessinée par-dessus tout ce qui traînait là. Ce qui sort par un bord y
fond (``brandHorizontalFade``), au lieu d'être tranché à la verticale — une
pastille pleine coupée net contre le bord de l'écran se lit comme un défaut de
rendu. Les deux règles valent aussi pour les filtres d'un voyage (§11).

**La mosaïque.** Les vignettes n'ont pas toutes la même hauteur : quatre formats
(0.78, 0.86, 1.0, 1.12 en largeur/hauteur) tirés d'une empreinte stable de
l'identifiant du voyage — la même que celle des aplats de couverture, pour
qu'une carte garde sa forme d'un lancement à l'autre. Chaque carnet va dans la
**colonne la plus courte** : en alternant simplement, deux vignettes hautes de
suite creusaient cent points de vide dans l'autre colonne. Le rangement se fait
dans `GalleryModel`, une fois par filtre, jamais dans un `body`.

**L'image est en `scaledToFill`, jamais rognée de travers**, et un voile
(transparent au tiers, noir à 68 % en bas) rend le titre lisible sur n'importe
quelle photo. Tant qu'aucune photo ne remonte du serveur, c'est l'aplat de marque
de `TripCoverPlaceholder` qui tient la place.

**Le drapeau, ou le globe.** Un seul pays → son drapeau, dérivé du code ISO. Deux
ou plus → **`IconGlobeDuo`**. Choisir un drapeau parmi dix désignerait le premier
pays comme *le* pays du voyage, ce qu'un tour du monde n'a pas ; un pays sans
code exploitable prend le globe aussi, plutôt qu'un carré blanc.

**Le CTA suit ce que la personne a déjà.** « Continuer mon voyage » +
`IconArrowRight` quand elle a un voyage en cours ou à venir, « Créer mon
voyage » + `IconPlus` sinon. C'est **le serveur** qui répond à cette question
(`Gallery.resumableTripId`), avec la même règle que `HomeModel.resumableTrip` :
deux écrans qui répondraient différemment seraient un bug qu'on ne verrait qu'en
passant de l'un à l'autre.

**Aux tailles accessibles**, la vignette se retourne : l'image en haut à son
format, le titre **en dessous** sur le papier, en encre pleine. Posé sur l'image,
un titre en AX3 débordait par le bas, recouvrait le drapeau et mordait sur la
carte voisine. Une seule colonne, aussi : à 165 points de large, « De Nantes à
Saint-Malo à vélo » fait dix lignes d'un mot.

**Contrat back-end** — `GET /v1/gallery`, session obligatoire.

| Donnée | Origine |
|---|---|
| Les carnets | `memos` où `isPublicGallery` est vrai — **le seul critère** |
| Titre | `memos.title` |
| Sous-titre | `memos.gallerySummary` — **nouvelle colonne**, qu'un agent déduira du contenu du voyage. `null` : la carte n'affiche que son titre |
| Pays | **dérivé** de `memos.destination*` + `memo_steps.destination*`, sans doublon. Rien n'est stocké |
| Catégories | `gallery_categories` (actives, triées par `position`) et `memo_gallery_categories` |
| Bouton du bas | `resumableTripId` — le voyage en cours du lecteur, sinon son prochain départ |

**Les catégories sont une table, pas une énumération** : en ajouter une, la
renommer, changer son pictogramme ou la retirer de la barre est une écriture en
base, pas une livraison d'app. Un carnet peut tenir dans **plusieurs** (un tour
du monde à pied est aussi une randonnée) ; la barre, elle, n'en coche qu'une à la
fois. `npm run db:seed` en pose neuf et neuf carnets publics, sur un compte à
part (`communaute@memo-book.com`) pour qu'ils n'encombrent pas l'accueil des
comptes de test.

**Assets** — ⚠️ **Exception assumée à R10.** Les pictogrammes de catégorie
viennent de [Lucide](https://lucide.dev) (licence ISC) et non de Figma : le jeu
de marque compte trente-cinq icônes, aucune ne représente un *type de voyage*.
Voir `assets/icons/lucide-icons/README.md` et
`ios/Tools/import-lucide-icons.py`. La clé est celle de la base
(`iconKey` = nom du fichier), résolue par `MemoBookDesign/LucideIcon.swift`,
qui retombe sur une boussole pour une clé inconnue — une catégorie ajoutée en
base s'affiche donc avant la prochaine version de l'app. `IconFilter` et
`IconFilterDuo`, eux, viennent bien du jeu de marque et sont importés au passage.

**États** — les quatre sont gérés. *Chargement* : la grille se dessine tout de
suite à sa forme définitive, avec six vignettes vides. *Erreur* : `ErrorBanner`
en ligne au-dessus de la grille. *Vide* : deux textes différents selon qu'aucun
carnet public n'existe encore ou que la catégorie cochée n'en range aucun — **ni
l'un ni l'autre n'est maquetté**.

**Accessibilité** — la flèche de retour a sa cible de 2.75 rem et son libellé
« Retour » ; les pastilles portent `.isButton` et `.isSelected` ; une vignette est
lue d'un bloc, et **nomme le pays** plutôt que de laisser VoiceOver annoncer un
emoji de drapeau. L'icône de filtre est décorative et masquée.

**Copie** (verbatim) — « Exemples de carnets » · « Tout » · « Continuer mon
voyage » · « Créer mon voyage » · « Les premiers carnets arrivent » · « Reviens
bientôt : la communauté partage ses carnets terminés ici. » · « Aucun carnet dans
cette catégorie » · « Choisis « Tout » pour revoir tous les carnets. » · « Tout
afficher »

**À trancher (suite)**

| # | Sujet | Écran / parcours |
|---|---|---|
| T43 | **Aucune photo de couverture** ne remonte encore : toutes les vignettes portent l'aplat dégradé. Les formats de la mosaïque sont donc à revoir sur de vraies images | Exemples de carnets |

---

## 16. Lot 4 — Le carnet : réglages, aperçu, partage et cagnotte

Cinq écrans et deux feuilles, livrés ensemble parce qu'ils forment **un seul
parcours** : on règle son voyage, on regarde le carnet qu'il produit, on le
partage, et on le fait financer. Nœud Figma :
[`🤖 Claude Import`](https://www.figma.com/design/kytPYFno7PvDciIKTxCujK/MemoBook---Product?node-id=3268-26957).

Trois des douze frames de la page **ne sont pas implémentées**, et c'est
délibéré : `Modale - Partager son MB - 2`, `- 5` et `Partager son MB sur WA`
dessinent la **feuille de partage du système** et l'écran de WhatsApp. On
présente `UIActivityViewController` ; en redessiner une ne donnerait qu'une
liste plus courte, qui ignorerait les apps installées, les AirDrop à portée et
les raccourcis de l'utilisateur.

### 16.1 Paramètres du voyage

`3335:9819` → `TripSettings/TripSettingsView.swift`

**On y arrive par la roue crantée**, posée au même endroit sur l'accueil d'un
voyage et sur la conversation : les réglages appartiennent au voyage, pas à
l'écran qui les ouvre.

L'écran est un empilement de `BrandRowGroup`, et n'a donc presque rien de
propre. Trois blocs ne sont pas des lignes de réglage et sont écrits à la main —
le Tricount, « La carte » et « Prévisulation PDF » — parce qu'ils portent une
explication ou une vignette, pas une valeur.

| Mesure | Figma | Retenu |
|---|---|---|
| Marge d'écran | 16 | `screenMargin` (1 rem depuis le 14/09/2026) — règle du § 2.3 |
| Groupe de lignes | rayon 20 | `largeCornerRadius` |
| Filet entre deux lignes | 1 pt | `hairline`, posé **entre** les lignes |
| Vignette de l'aperçu | 45 × 64 | 3.5 rem de large, rapport A5 |

**Chargement** — l'écran se dessine entier tout de suite ; seules les valeurs
portent une `BrandSkeleton`. Les deux groupes qui contiennent un interrupteur
sont `.disabled` tant que les réglages ne sont pas lus : basculer avant
enverrait un état qu'on n'a pas.

**Back-end** — `GET /v1/trips/:id/settings` et `PATCH` (écrits dans cette PR).
Un réglage part seul, à la bascule, sans bouton pour valider. ⚠️ L'app est
encore branchée sur le **jeu d'essai** : `AppDependencies.tripSettingsModel`
documente la bascule, qui est de quatre lignes.

### 16.2 On compose ton Carnet

`3335:10193` → `BookPreview/BookCompositionPage.swift`

L'attente de la composition, occupée par **une page de carnet qui se monte**.
Treize morceaux — un signet, deux bandeaux, six pictogrammes, huit lignes de
texte, une carte, une photo, un tampon — arrivent chacun d'un bord et se posent
à leur place, dans l'ordre où l'on monte vraiment une page : la structure, puis
le texte, puis ce qu'on colle.

Les positions sont des **fractions de la page**, jamais des points : la
chorégraphie tient dans une seule liste (`BookCompositionPiece.all`), et régler
le rythme de l'écran c'est changer des nombres, pas du code.

**2,6 s, et c'est aussi le plancher de l'attente.** Même si le serveur répond en
300 ms, l'écran les tient : une page qui se monte et disparaît avant d'être
finie donne l'impression d'un bogue. Les deux attentes — la cascade et le
serveur — sont menées en parallèle, et c'est la plus longue qui décide.

Sous « Réduire les animations », les morceaux ne voyagent plus : ils se révèlent
sur place. La promesse tient sans mouvement.

### 16.3 Aperçu PDF, et son plein écran

`3335:10090`, `3335:10159`, `3335:10306` → `BookPreview/BookPreviewFlowView.swift`,
`BookFullScreenView.swift`

**L'app ne redessine pas le carnet : elle affiche le PDF.** Les pages sont
rendues par PDFKit depuis le document composé (`BookPageRenderer`), mises en
cache par (page, largeur), et la page voisine est préparée pendant qu'on lit la
courante — tourner ne coûte alors rien. C'est la seule façon d'être sûr que
l'aperçu montre ce qui sortira de l'imprimante.

Le plein écran n'est **pas un écran de plus** mais un mode : la flèche de retour
doit ramener au voyage, pas à la version réduite. C'est le rond `normal_screen`
qui revient en arrière. C'est aussi le seul endroit de l'app où quelque chose
déborde la marge d'écran, et c'est ce débordement qui fait le plein écran.

La première et la dernière page portent l'invitation à choisir ses couvertures
(`Prévisualisation PDF - 2`) — mais **seulement quand il y a une page dessous** :
posée sur un aplat vide, elle promettait une couverture qu'on ne voyait pas.

### 16.4 Le mot des fondateurs

`3335:10957` → `BookPreview/FoundersNoteSheet.swift`

**Elle s'ouvre toute seule**, une fois par compte, douze secondes après le
premier aperçu — la maquette dit « 10 à 15 », et il faut laisser le temps de
tourner deux ou trois pages avant d'interrompre. Jamais par-dessus le partage
ni le plein écran : elle s'invite, elle n'interrompt pas.
`OnboardingStorage.hasSeenFoundersNote` la retient.

Trois choses la distinguent de toutes les autres feuilles, et aucune n'est
décorative : la photo dépasse en haut et **flotte** (2 pt, 3 s, arrêtée sous
« Réduire les animations »), une ligne est écrite **à la main** en vert, et la
signature est un **dessin** — un nom tapé sous un mot manuscrit annulerait tout
ce qui précède.

La manuscrite est **Gloria Hallelujah**, déjà la police du carnet
(`memos.fontHand`). Elle était livrée en woff2, que CoreText ne lit pas :
`ios/Tools/make-brand-fonts.py` la convertit désormais en TTF. C'est le même
dessin, pas une seconde police.

### 16.5 Partager ton MemoBook

`3335:10879` → `BookPreview/ShareBookSheet.swift`

Deux façons de partager, et elles ne disent pas la même chose : le **PDF** est
le carnet tel qu'il est aujourd'hui (hors connexion, imprimable, figé), le
**lien** est le carnet tel qu'il sera (il suit la conversation, ce qui est
exactement ce qu'il faut pour donner envie d'aider à le financer).

La carte du haut n'est pas décorative : c'est **l'aperçu de ce que le
destinataire verra**. Le lien portera des métadonnées Open Graph, et c'est cette
vignette-là qui apparaîtra dans WhatsApp.

Les deux options ouvrent la feuille du système avec le message déjà écrit
(`BookCopy.Share.invitation`), et le lien de cagnotte accompagne **les deux** :
c'est le message qui demande un coup de main, pas la pièce jointe.

### 16.6 Ma cagnotte

`3335:11159` (pleine) et `3335:11379` (vide) → `Wallet/WalletView.swift`

**Un seul écran pour les deux maquettes.** Elles ne diffèrent que par un bloc —
l'historique d'un côté, la carte d'invitation de l'autre — et tout le reste est
identique, carte de solde comprise.

Le solde est **vert dès qu'il y a quelque chose dessus, gris à zéro** : c'est
l'écart que dessinent les deux maquettes, et il porte tout — une cagnotte vide
ne doit pas avoir l'air d'une réussite. Il s'anime chiffre par chiffre quand une
contribution arrive.

Deux natures d'écriture, distinguées sans lire : **bleu** pour un don (une
initiale, une pastille « DON »), **lime** pour l'abonnement (un engrenage, une
pastille « ABONNEMENT »).

**Bac à sable** (`WalletDebugPanel`, sous `#if DEBUG`) — demandé explicitement,
et nécessaire : sans encaissement, il n'existe aucun chemin depuis l'app vers un
solde non nul, et c'est l'écran qui a le plus de choses à montrer. « + 10 € »
ajoute une contribution **par-dessus ce qui est là**, ce qui est le seul moyen de
vérifier l'animation du solde et l'arrivée d'une ligne en tête d'historique.

**Back-end** — `GET /v1/wallet` (écrite dans cette PR). Rien de neuf en base :
`wallet_entries` (M4) porte déjà le montant, la nature, le motif et la date, et
`accounts.walletBalanceCents` le cache du solde. Le registre en ajout seul avait
vu juste. ⚠️ L'app est encore branchée sur le jeu d'essai.

**Copie** (verbatim) — « Ma Cagnotte » · « Finance ton carnet de Rome » ·
« Montant disponible » · « A ce rythme, ton carnet fera probablement 50 pages » ·
« coût estimé » · « Ajouter » · « Partager » · « Historique des contributions » ·
« Aucune contribution pour le moment » · « Inviter des proches » · « offerts par
tes proches » · « grace à ton abonnement » · « Si je n'utilise pas toute ma
cagnotte ? » · « Prévisualiser mon carnet »

### 16.8 Personnalisations du carnet

`3348:11485` → `TripSettings/BookCustomisationView.swift`

Ouvert par la ligne « Style du carnet » des paramètres. L'écran le plus long de
l'app, rangé en **cinq paquets** plutôt qu'en une liste : les couvertures, la
forme de la page, les décors, les typographies, et les extras. On ne règle pas
une typographie en même temps qu'un nombre de pages.

Les **extras** sont les seuls à porter un interrupteur, et c'est ce que dessine
la maquette : ils *ajoutent* quelque chose au carnet — un quiz, des pages
blanches, une grille de mots fléchés — là où les autres lignes choisissent entre
des valeurs. Un interrupteur répond à « est-ce que j'en veux », une ligne à
« lequel ».

Toutes les valeurs existent déjà en base depuis M4 (`memos.photoTextRatio`,
`targetPageCount`, `funFactsEnabled`, `rulesEnabled`, `decorationQuota`,
`font*`, `quizEnabled`, `freeZonesEnabled`, `crosswordEnabled`) et sont
désormais servies **avec les réglages** — un jeu par voyage, lu avec lui.

⚠️ **Seuls les trois extras s'enregistrent.** Dix des onze autres lignes
montrent leur valeur et ne mènent nulle part : leurs écrans de choix ne sont pas
dessinés, et on ne les invente pas (R3). La onzième — **les couvertures**, en
tête de l'écran — ouvre depuis le lot 6 le parcours du § 17.1.

### 16.9 La feuille « Prévisualisation »

`3348:11671` → `BookPreview/BookPreviewSheet.swift`

Ce qu'ouvrent les deux pastilles « Voir un aperçu » du parcours d'abonnement.
Une **feuille** et non un écran poussé : quelqu'un à qui l'on propose un
abonnement veut voir ce qu'il achète, puis *revenir à l'offre*.

Elle réutilise les pièces de l'aperçu — ``BookPageStage``, ``BookSheetView``,
``BookPageStepper``, et la cascade de composition — plutôt que d'en redessiner
de plus petites : deux aperçus à tenir d'accord, et celui de la feuille
vieillirait le premier.

Une seule forme, d'où qu'elle vienne : une feuille **posée par-dessus** ce qui
l'a ouverte. Depuis le **paywall**, le minuteur des stories s'arrête pendant ce
temps-là (voir `PageTimer`). Depuis la **feuille d'abonnement**, elle se pose
sur « Comment ça fonctionne », qui recule d'un cran — le petit zoom de toute
feuille de l'app — et revient tel quel quand on la referme. C'est **l'exception
voulue** à la règle des feuilles enchaînées (Hugo, 16/09/2026 ; § 21, T133) :
l'aperçu a d'abord été une *étape* de la feuille d'abonnement, et le refermer
ramenait alors au profil au lieu de l'offre.

### 16.7 À trancher

| # | Sujet | Écran / parcours |
|---|---|---|
| T76 | **Deux lignes des réglages n'ouvrent rien** : « Connecte ton Tricount » et « La carte ». Les sept autres ont leur feuille ou leur écran depuis le lot 7. Pas de carte pour le moment (Hugo, 17/09/2026) ; Tricount attend son intégration | Lot 4 — Le carnet : réglages, aperçu, partage et cagnotte |
| T80 | **Les zones de tapotis du paywall passent sous le contenu.** Posées au-dessus, elles avalaient tout contrôle hors de la bande basse épargnée — c'est ce qui est arrivé à la pastille « Voir un aperçu ». Le texte des pages porte donc `paywallProse()`, qui le rend non touchable. Chaque nouveau bloc de texte du paywall devra le porter aussi, sinon la story ne défilera plus dessous. Les quatre cartes de l'écran 3 le portent également — pastille « Voir une estimation » comprise, qui est inerte : le jour où elle mènera quelque part, elle devra en sortir | Lot 4 — Le carnet : réglages, aperçu, partage et cagnotte |

---

## 17. Lot 6 — Les couvertures, et le support

Quatorze frames livrées ensemble, et deux parcours qui n'ont rien à voir l'un
avec l'autre : **les deux plats du carnet**, et **l'aide**. Nœud Figma :
[`🤖 Claude Import`](https://www.figma.com/design/kytPYFno7PvDciIKTxCujK/MemoBook---Product?node-id=3268-26957).

Une seule des quatorze n'est pas implémentée : `Modale - Statistiques v1`, la
première version du choix des chiffres. La v2 la remplace — arbitrage de Hugo,
14/09/2026. C'est la seule qui reprenne la composition du bandeau imprimé (le
chiffre en gros au-dessus de son libellé) ; choisir ce qui va sur un plat en
lisant une liste de réglages, c'est choisir à l'aveugle.

### 17.1 Couvertures — le choix

`3365:12242` → `Covers/CoversView.swift`

**Deux chemins y mènent**, et le second est le plus important : la ligne
« Couvertures (1re & 4e) » en tête des personnalisations, et la pastille
« Défini maintenant ta 1ère et 4ème de couverture » → « Configurer », posée sur
la première et la dernière page de l'aperçu PDF. C'est en feuilletant son carnet
qu'on s'aperçoit qu'il n'a pas de couverture. Clôt la partie « couvertures » de
T82, et le `configureCovers` resté inerte du § 16.3.

⚠️ **« Personnaliser mon carnet » garde sa route vers les paramètres du
voyage** — arbitrage de Hugo, 14/09/2026 : ce CTA ouvre tout le réglage du
carnet, pas seulement ses plats.

L'écran ne fait presque rien : le plat en grand, et trois lignes qui mènent aux
trois écrans qui le changent. C'est son rôle — **voir avant de régler**.

| Mesure | Figma | Retenu |
|---|---|---|
| Plat | 300 × 469,5 | 300 de large, plafonné à la largeur utile, **rapport A5** |
| Ligne d'action | rayon 12, marge 12 | `cornerRadius` (14) par R2, `snug` |
| Onglets | rayon 100, segment 34 | `BrandSegmentedPicker` en taille `compact` |
| Filet | `#E6DAD0` | `hairline` — trois points d'écart sur un canal (§ 16.8) |

### 17.2 Couvertures — style et photo

`3365:12314`, `3365:12407`, `3365:12269`, `3365:13002`, `3365:13091`
→ `Covers/CoverCarouselView.swift`

**Un seul écran pour les cinq frames.** Elles ne diffèrent que par ce qu'on fait
défiler — des plats dessinés d'un côté, des photos et une case d'import de
l'autre — et par le sous-titre. Deux écrans auraient eu à rester d'accord sur le
rythme du défilement, et le second aurait vieilli le premier.

**Ce qui est au centre est ce qui est choisi.** La maquette agrandit le plat du
milieu et le coiffe d'une coche : il n'y a donc pas de sélection au tapotis
séparée du défilement. Toucher un plat voisin l'amène au centre, ce qui revient
au même geste.

⚠️ **L'agrandissement est un `scaleEffect`, pas une largeur** — et ça vaut d'être
dit, parce que l'inverse paraît plus naturel et ne marche pas. Faire dépendre la
largeur de la case du plat sélectionné rend la mise en page circulaire : le plat
choisi grandit, ce qui décale la file, ce qui change le plat au centre. Le
carrousel se calait alors une case à côté, sans jamais cocher personne. Même
raison pour `contentMargins` plutôt que `padding` : une marge posée **dans** le
contenu compte comme du contenu, et `viewAligned` s'y cale.

**Le choix ne part qu'à « Valider ».** C'est la seule différence avec les lignes
de réglage de l'app, où un réglage part seul à la bascule : ici le choix est
visuel, et faire défiler sept plats ne doit pas écrire sept fois au serveur.

### 17.3 Couvertures — les textes

`3365:13180`, `3365:13208` → `Covers/CoverTextsView.swift`

Le plat reste la pièce principale, et les crayons se posent dessus : on modifie
ce qu'on regarde. Un titre de couverture ne se juge pas dans un champ.

⚠️ **La maquette ne dessine pas l'état « en train d'écrire ».** Elle pose les
crayons et s'arrête là. Plutôt que d'inventer une feuille (R3), le crayon ouvre
le champ **sous le plat** et lui donne le focus ; le plat se met à jour à mesure
qu'on tape. Signalé (T89).

Le titre est une **valeur** (`BrandTextField`), le sous-titre un **texte**
(`BrandTextBox`, nouveau — voir §17.6).

### 17.4 Choix des statistiques

`3365:13716` → `Covers/CoverStatsSheet.swift`

Ouverte par le crayon du bandeau « Mon voyage en quelques chiffres » de la
quatrième de couverture. Trois ou quatre chiffres, jamais moins, jamais plus :
la contrainte vient du gabarit — sous trois, le bandeau imprimé a des colonnes
vides ; au-delà de quatre, les chiffres ne se lisent plus à la taille imprimée.

Une carte qu'on ne peut plus cocher **reste lisible** et devient inactive :
la masquer ferait disparaître la moitié de la grille à la quatrième coche.
L'ordre de sélection est celui qui s'imprime, de gauche à droite.

### 17.5 Support et retours

`3365:12123`, `3365:13695`, `3365:13779`, `3365:13796`
→ `Support/SupportView.swift`, `Support/SupportSheet.swift`

**On y arrive de partout où l'app écrit « Besoin d'aide ? »** — le bas de
l'accueil, le bas du profil, la barre du paywall, la dernière ligne des
paramètres d'un voyage et celle de la cagnotte. C'est la raison d'être de
l'écran : cinq liens qui ne menaient nulle part mènent au même endroit. Clôt la
partie « aide » de T76 et l'avertissement du § 13.3.

Depuis le paywall, le lien **referme l'offre** avant d'ouvrir le support : celui-ci
est un écran poussé, il ne peut pas apparaître sous une couverture plein écran —
et quelqu'un qui va chercher de l'aide devant un prix ne revient pas à la story
qu'il regardait.

**Le contenu vient de la page Notion**
[« FAQ in-app MemoBook »](https://app.notion.com/p/FAQ-3d7401e7bdc1803cac95c800f34a71db),
version 1.0, recopiée dans `MemoBookCore/Faq.swift` : dix paquets,
quarante-cinq questions. La maquette, elle, ne dessine que le motif — deux
sections de quatre lignes de remplissage (« Typographie des titres », en Inter,
qui n'est pas une police de la marque). C'est donc le **motif** qui est
implémenté, répété pour les neuf paquets de sujets courants, et le dixième
— « Aide et contact » — qui devient la section « Nous contacter ».

Cinq règles de la page Notion tiennent dans le code, et `FaqTests` les garde :

| Règle | Où |
|---|---|
| Identifiant `faq.categorie.slug` immuable | `FaqEntry.id`, testé unique et bien formé |
| Prix, délais et seuils en variables `{{…}}` | `FaqVariables`, résolues à l'affichage |
| Tutoiement, et le vocabulaire Carnet / souvenirs / voyageurs | testé sur les 45 réponses |
| « Est-ce utile ? » mesuré **par identifiant** | `SupportModel.vote(_:on:)` |
| Un écran peut pointer une question précise | `Faq.entry(id:)` |

⚠️ **Trois points de la page Notion ne sont pas tenus**, et c'est dit plutôt
qu'oublié : le contenu n'est pas encore servi depuis une source distante (il
arrive par une fonction, donc le branchement fera quatre lignes), il n'y a pas
de champ mots-clés faute d'écran de recherche dessiné, et l'app est en français
seul.

**Les trois feuilles n'en font qu'une.** « J'ai encore une question » mène au
formulaire, et le formulaire à la confirmation : ce sont trois **temps** d'une
même `BrandSheet`, parce que le design system interdit d'en empiler deux. La
feuille garde donc son identité, sa hauteur s'anime au lieu de sauter, et
VoiceOver n'a qu'un retour arrière.

### 17.6 Ce qui entre dans le design system

- **`BrandTextBox`** — le champ de plusieurs lignes, à côté de `BrandTextField`.
  La frontière est nette : un `BrandTextField` reçoit une **valeur** (un e-mail,
  un code), un `BrandTextBox` un **texte**. Deux écrans l'emploient — le message
  au support et le texte de quatrième —, et c'est ce qui l'a fait entrer.
- **`BrandSegmentedPicker` gagne une taille `compact`** — 34 pt de segment,
  libellé en `tagline`, filet discret. C'est le rail que dessinent les
  couvertures, posé *dans* un écran plutôt qu'au-dessus de lui.
- **Trois pictogrammes** exportés du nœud : `IconLayers`, `IconThumbUp`,
  `IconThumbDown`, entrés par `assets/icons/brand-icons` et le script d'import.

### 17.7 Contrat back-end

⚠️ **Les deux parcours sont sur le jeu d'essai, et les couvertures plus
complètement que le reste.**

| Écran | Ce qui manque |
|---|---|
| Couvertures | `GET`/`PATCH /v1/trips/:id/covers` n'existent pas, et la base n'a qu'un booléen (`memos.hasConfiguredCovers`). Il manque le style, la photo retenue, les deux textes et les chiffres choisis — cinq colonnes, une route, un sérialiseur |
| Support | Aucune route. Le contenu est statique, l'envoi d'un message simulé, le vote « Est-ce utile ? » perdu à la fermeture |

Conséquence à dire à Clara et Paul : **choisir une couverture ne survit pas à la
fermeture de l'écran**, et un message écrit au support n'arrive nulle part.

### 17.8 À trancher

| # | Sujet | Écran / parcours |
|---|---|---|
| T87 | **Le plat est au rapport A5 (1,414)**, là où la maquette dessine 233 × 339 (1,455) — neuf points d'écart sur la hauteur. C'est le format du papier qui tranche, pas l'artboard, et c'est déjà le choix du § 16.1 pour la vignette des réglages | Lot 6 — Les couvertures, et le support |
| T88 | **Une photo importée ne part nulle part.** Elle est enregistrée dans les caches de l'appareil, comme les photos du chat, et se perd à la fermeture de l'écran. C'est la route des couvertures qui manque (T-back-end ci-dessus), pas l'écran | Lot 6 — Les couvertures, et le support |
| T89 | **L'état « en train d'écrire » n'est pas dessiné** sur l'écran des textes. Le champ s'ouvre sous le plat, faute de maquette. À dessiner, ou à valider tel quel | Lot 6 — Les couvertures, et le support |


---

## 18. Relecture du 14/09/2026 — ce que les fiches n'avaient pas remonté

Dix retours de Hugo, hors des tickets ouverts, en relisant l'app dans le
simulateur. Chacun a son numéro, pour qu'on puisse le rouvrir : sept sont
réglés dans ce lot, trois attendent quelque chose.

> ⚠️ **Le quota du MCP Figma était épuisé** dès le troisième appel de cette
> session (plan Starter). Tout ce qui est écrit ci-dessous sur les maquettes
> vient de la **métadonnée** de la page *App* — la structure et le texte des
> calques, lus une fois — et jamais d'un rendu. Ce qui n'y était pas lisible
> (les instances de composants, les titres nommés « title ») est signalé.

Les dix lignes sont parties le 17/09/2026 : tout est réglé, ou validé tel quel.

---

## 19. Lot 7 — L'entrée dans l'app, le paywall de retour, et les onze modales

> Nœuds : page **« 🤖 Claude Import »** (`3268:26957`) du fichier Figma —
> *Accueil - 1ère Connexion* (`3420:10409`), *Paywall Recurrent 1 & 2*
> (`3443:9675`, `3443:9626`), section **Trip settings** (`3443:10523`) et
> section **Book personnalisation** (`3443:10525`).

Trois blocs, un seul lot : ils se tiennent par la donnée. Les modales de
réglages ne valaient rien tant que `GET /v1/trips/:id/settings` n'était pas
branché côté app — et c'est ce branchement qui a, au passage, rendu vrai tout
l'écran des paramètres, qui tournait sur un jeu d'essai depuis sa livraison.

### 19.1 Accueil — 1ère connexion

- **Nœud** : `3420:10409`
- **Vue** : `MemoBookFeature/Welcome/WelcomeView.swift`, copie dans
  `WelcomeCopy.swift`, boutons dans `WelcomeSocialButtons.swift`
- **Rôle** : la porte de l'app. Ce que MemoBook fait, en trois mots, et les deux
  entrées qui ne demandent rien à taper.
- **Entrée / sortie** : c'est l'écran de **quiconque n'a pas de session** — il
  n'est plus gardé par un `@AppStorage`, et il revient donc à chaque
  déconnexion. Apple et Google entrent directement ; « S'inscrire avec un
  e-mail » pousse `AuthView`, qui en revient par « Retour ».

**Structure (en rem)** — photo 23.75 (380), carte à coins hauts de 2.25 (36,
soit `largeCornerRadius` + `s`), marge de carte 1.5, gouttière de blocs 2,
boutons de fournisseur 3.25 (52) à rayon 1, note communauté à rayon 0.75.

**Les deux boutons de fournisseur portent le même habillage**, écrit une seule
fois (`providerChrome`) : même aplat `surface`, même filet `Beige Darker`, même
rayon de contrôle. Celui d'Apple reste **son** bouton — son libellé, sa
typographie, sa pomme —, mais en style `.white` plutôt que `.whiteOutline` : le
filet d'`.whiteOutline` est à l'encre, il suit *son* rayon et coupait les angles
en travers de l'arrondi. Sans contour, découpé à notre forme, le beige se pose
dessus comme sur l'autre. Et `colorMultiply(surface)` rattrape le blanc pur
d'Apple sans toucher au noir de la pomme ni du texte — multiplier par 0 ne donne
que 0. Mesuré : les deux aplats rendent (255, 252, 248).

**Les trois icônes des étapes sont bichromes** (`IconMicDuo`,
`IconPictureFrameDuo`, `IconPrinterFilledDuo`), sans `renderingMode(.template)`
— qui les aplatirait en une couleur, c'est-à-dire effacerait exactement le bleu
pour lequel on les a choisies. L'imprimante est la version **pleine** :
`IconPrinterDuo` n'est qu'un contour, et elle paraissait vide entre deux voisines
pleines.

**Les logos Apple et Google** sont ceux de la marque, dessinés à la main et
cernés du même bleu (`assets/logos/*.svg`, importés par
`ios/Tools/import-brand-logos.py`). ⚠️ Figma les exporte en **bitmap incrusté** —
la planche entière en base64 dans un `<pattern>`, dont le nœud ne montre qu'une
découpe. Xcode ne sait pas rendre ça, et l'embarquer voudrait dire recopier
160 ko de planche par icône de 24 pt : le script décode, découpe, et écrit un
PNG à la résolution native (131 × 139 et 139 × 150). Voir T123.

**Ce qui a changé ailleurs** — `AuthView` perd ses deux boutons de fournisseur
et son entrée de chantier, gagne une flèche « Retour », et devient un écran
poussé (`SignedOutRoute.email`). `WelcomeStepCard` et `SocialSignInSection`
sont supprimés. `OnboardingStorage.hasSeenWelcome` disparaît : il ne gardait
plus rien.

**Contrat back-end** — aucun appel. Les deux entrées passent par
`POST /v1/auth/social`, déjà en place.

**À trancher** — T113, T115, T124. La pomme du bouton Apple est tranchée (T123).

### 19.2 Paywall de retour — deux écrans au lieu de trois

- **Nœuds** : `3443:9675` et `3443:9626`
- **Vues** : `PaywallVariant` dans `Paywall/PaywallView.swift`, écran d'ouverture
  dans `Paywall/PaywallPages.swift` (`PaywallReturning`)

**Le mécanisme est celui du paywall de découverte**, sans une ligne de
différence : même minuteur de 6 s, mêmes zones de tapotis, même barre de
stories — qui compte deux segments au lieu de trois —, même dernier écran qui
ne s'en va pas tout seul. Seuls changent le nombre d'écrans et deux titres.

**Qui le voit** : un compte qui a **déjà** été abonné et ne l'est plus —
`subscription.hasEndedBefore`. Ce n'est pas l'état d'un mécontent, c'est l'état
ordinaire entre deux voyages, parce que l'abonnement s'arrête tout seul.

**L'arrêt automatique**, côté serveur et sans StoreKit :
`services/subscriptions.ts`. Un compte sans voyage **encore en cours** (date de
fin passée, ou pas de voyage du tout) voit ses abonnements passer à `expired`.
Deux déclencheurs : le `PATCH` des réglages quand une date de fin bouge, et une
tâche quotidienne à 3 h 10 UTC (`JOB_NAMES.endSubscriptions`), parce qu'un
voyage se termine par le calendrier et que personne n'ouvre l'app ce jour-là.
Un voyage **sans date de fin** compte comme en cours : partir sans savoir quand
on rentre ne doit pas couper l'abonnement.

⚠️ **Rien n'est annulé chez Apple**, et ça ne peut pas l'être : StoreKit n'est
pas branché, et même branché, Apple ne laisse aucune app résilier à la place de
son client. Ce qui s'éteint ici est la ligne `subscriptions` — ce que l'app lit
pour savoir s'il faut remontrer l'offre. Voir T116.

### 19.3 Les cinq modales des paramètres du voyage

`TripSettings/TripSettingsSheets.swift`. Toutes sont des ``BrandSheet`` : geste
du système, dessin de la marque, hauteur calée sur le contenu, recul de l'écran
du dessous.

| Modale | Nœud | Ce qu'elle règle | Enregistrement |
|---|---|---|---|
| **Dates** | `3443:9881` | `startDate`, `endDate` | au choix d'une date |
| **Rythme du récit** | `3443:9841` | `narrationPace` | au choix, puis se ferme |
| **Notifications** | `3443:9895` | les quatre alertes | à chaque bascule |
| **Thème de l'aventure** | `3443:9937` | `theme` | au « Valider » — c'est un champ de saisie |
| **Inviter un proche** | `3443:9805` | la liste, le code d'accès | au geste |

**Le sélecteur de date est celui du système**, et il **monte du bas, par-dessus
la feuille** (`BrandDateField`). Il se dépliait auparavant *dans* la ligne,
comme à la création d'un voyage : une feuille de réglages fait déjà sa hauteur,
et un calendrier de 320 pt qui s'y ajoute repousse le reste hors de l'écran. Il se
referme **dès qu'une date est choisie** — `.graphical` et non `.wheel`, parce
que c'est le seul des deux où choisir est un geste unique.

**Le carrousel de thèmes est celui de la création du voyage**, à la lettre :
c'est la note « Logique » du nœud. Un second jeu de thèmes ferait dériver
`memos.theme`, que l'agent de rédaction lit tel quel.

**Retirer un co-voyageur, renvoyer son lien** : glissé vers la gauche **et**
appui long (menu contextuel), plus les actions du rotor VoiceOver. Le
propriétaire ne se retire pas — il n'a pas de ligne dans `memo_members`, donc
il n'y a rien à supprimer, pas même par erreur. On ne renvoie un lien qu'à une
invitation jamais acceptée.

### 19.4 Les six modales de la personnalisation du carnet

`TripSettings/BookCustomisationSheets.swift`.

| Modale | Nœud | Ce qu'elle règle | Pages du carnet |
|---|---|---|---|
| **Ratio média** | `3443:10212` | `photoTextRatio`, pas de 25 | non |
| **Nombre de page** | `3443:10177` | `targetPageCount` | non |
| **Fun Facts** | `3443:10105` | `funFactsEnabled` | oui |
| **Pointillés** | `3443:10126` | `rulesEnabled` | oui |
| **Titres du carnet** | `3443:10073` | `fontDisplay` | oui |
| **Sous-titres du carnet** | — (sur le modèle des titres, § 21, T136) | `fontTitle` | oui |
| **Textes du carnet** | — (idem) | `fontHand` | oui |
| **Fun facts du carnet** | — (idem) | `fontFacts` | oui |
| **Décorations & stickers** | `3443:10147` | `decorationQuota`, 0 à 4 | oui |

**Les paliers de pages sont calculés, pas écrits.** La maquette annonce
30 / 60 / 90 en précisant « Estimations pour un voyage de 2 mois » : ce sont des
projections. `BookPageTarget.pageCount(forTripDays:)` les recalcule sur la durée
du voyage qu'on regarde — une page par jour au palier courant, arrondie à la
dizaine, bornée entre 30 et 180 —, ce qui rend bien 30 / 60 / 90 sur deux mois.
C'est la note « Logique » du nœud `3443:10070`.

**« Typographie des titres » écrit `fontDisplay`, pas `fontTitle`**, et le
croisement est volontaire : c'est le token `--mb-font-display` du gabarit. Voir
la table de `templates/travel-journal/LAYOUT_KB.md`.

**Les deux pages du carnet** (`BookPagesPeek`) sont les **vraies** : rendues du
PDF du dernier carnet composé, servi avec les réglages (`bookPdfUrl`). Pas de
carnet, pas de pages. Voir T117 pour ce que la maquette voulait et ce qu'iOS
permet.

### 19.5 Ce qui entre dans le design system

| Composant | Ce qu'il porte |
|---|---|
| `BrandSlider` | Le curseur à crans nommés : rail, poignée crème à point bleu, valeurs sous le rail, celle du moment en gras. Ajustable pour VoiceOver |
| `BrandToggleCard` | La carte à interrupteur — montée depuis `BookCustomisationView`, désormais partagée par les extras, les quatre alertes et deux feuilles |
| `BrandDateField` | Une date, et le sélecteur du système qui monte du bas |
| `BrandAvatar` | Le portrait de quelqu'un, ou ses initiales |
| `BrandSheet(topInset:)` | La réserve haute d'une feuille, pour un objet posé en tête |

`BrandOptionRow` change sur un point : son sous-titre passe de 1 rem à 0.75. Il
était au corps du titre, ce qui faisait lire deux titres par option — relevé
sur les `option-card` de ce lot, qui sont le même composant Figma que celles du
moyen de paiement.

### 19.6 Le vocal de l'accueil ne se déclare pas arrivé avant de l'être

- **Pièces** : `Recording/RecordingHandoff.swift`, `RecordingOutbox.handoffDelivery`,
  `ChatModel.receive(_:)` / `markHandoff(_:)`

Le trajet lui-même — enregistrer sur l'accueil, arriver dans la conversation le
message déjà posé — a été livré au lot précédent (T102). Ce lot-ci corrige deux
choses qu'il laissait derrière lui, et elles tiennent toutes les deux à la même
idée : **une bulle ne doit pas prétendre.**

**L'état d'envoi appartient à la file, pas à l'écran.** La bulle passait par le
chemin ordinaire d'un message, qui se marque « envoyé » dès que MEMO a répondu.
Or ce vocal est parti **avant** que la conversation n'existe, et il peut très
bien attendre le réseau sur le disque : on lisait donc « envoyé » sur un
souvenir encore dans la file, à chaque fois qu'on racontait dans le métro.
`RecordingHandoff` porte désormais un identifiant, la file dit où en est **cet**
envoi-là (`handoffDelivery`), et la conversation ne fait que l'écrire.
`.queued` n'est ni un échec ni une arrivée : la bulle reste sur « envoi en
cours », et la reprise de la file la termine.

**La forme d'onde est celle du vocal entier.** La feuille rendait `levels`, la
frise qui défile sous le micro — quarante barres, soit les trois dernières
secondes. Un vocal de deux minutes arrivait donc dans le fil avec la silhouette
de sa fin. `RecordingModel` garde les deux : la frise pour l'écran, le relevé
complet (`capturedLevels`) pour la bulle.

### 19.7 Contrat back-end

| Route | État |
|---|---|
| `GET /v1/trips/:id/settings` | Existait ; **branchée côté app** (elle tournait sur un jeu d'essai) |
| `PATCH /v1/trips/:id/settings` | Étendue : les quatre alertes, et les neuf personnalisations du carnet |
| `DELETE /v1/trips/:id/members/:memberId` | **Nouvelle** — `status: removed`, jamais une suppression de ligne |
| `POST /v1/trips/:id/members/:memberId/invitation` | **Nouvelle** — repousse `invitedAt`, rend 204. ⚠️ **N'envoie rien** : les e-mails transactionnels ne sont pas branchés |
| `GET /v1/profile` | `subscription.hasEndedBefore` |

Migration `20260915120000_alertes_du_voyage_et_role_du_co_voyageur` : quatre
booléens d'alerte sur `memos`, et `memo_members.role`.

### 19.8 À trancher

| # | Point |
|---|---|
| T115 | **La photo de l'écran d'entrée est floue** : le fichier fait 587 × 360 px, soit moins d'un pixel d'image par point d'écran. Il faut un export plus grand de la même photo (au moins 1170 × 720, le double sur un grand iPhone). Reformulé le 17/09/2026 — c'est un export à refaire dans Figma, rien à trancher |
| T116 | **L'arrêt automatique de l'abonnement ne parle pas à Apple.** Le jour où StoreKit sera branché, c'est le webhook App Store qui devra fermer la ligne `subscriptions`, et cette tâche deviendra le filet plutôt que la règle |
| T118 | **Alegreya s'écrit encore en General Sans** dans la feuille des assortiments : Playfair, Hansley et Gloria Hallelujah ont leur nom dessiné en vectoriel depuis le 18/09/2026 (`assets/logos/<Nom>.svg` → `Wordmark<Nom>`), elle attend le sien. Montserrat n'y est plus (« Moderne » retiré) | Typographies du carnet |
| T121 | **L'icône « Renvoyer » emprunte `IconTeleverser`**, faute d'un envoi dans le jeu de marque. Le logo WhatsApp, lui, est arrivé le 17/09/2026 (`assets/logos/whatsapp.svg`, en vert foncé) |
| T124 | **Les autocollants Apple et Google sont des images, pas des dessins vectoriels.** Ce sont les deux logos cerclés de bleu des boutons de l'écran d'entrée (`assets/logos/Apple Icon.svg`, `Google Icon.svg`) : Figma les a exportés en bitmap collé dans un SVG. Nets à 24 pt, ils pixelliseraient plus grand. Reformulé le 17/09/2026 — un export **vectoriel** de ces deux autocollants règle la question |

---

## 20. Retouches du 15/09/2026 — la relecture de Hugo, écran par écran

Dix-neuf retours de Hugo sur l'app en main, un seul lot (branche
`retouches-du-15-septembre`). Aucun nouvel écran : des corrections, deux
feuilles de plus sur le paywall, et **un composant** qui remplace quatre
dessins du même voile.

> Le MCP Figma n'a servi que deux fois : la métadonnée puis la capture du nœud
> `3469:14105` (la feuille « Estimation »). Tout le reste est décrit en français
> dans la demande, et appliqué directement (`ios/CLAUDE.md`, § Figma).

### 20.1 Le 500 des paramètres du voyage

« Erreur interne du serveur » en bas des paramètres, sur le compte
`hugo.jouffre.freelance@gmail.com` — et rien de cliquable au-dessus. **Le
voyage n'y est pour rien** : ses deux carnets (« Japon », « Test Hugo 1 ») sont
bien formés en base. La cause est dans les journaux de l'API déployée
(Railway, service `api`) :

```
PrismaClientValidationError — Unknown argument `role`
  include: { members: { where: { status: "active", role: "guest" } } }
```

L'API en production est le commit `eba4dc6` (PR #27, déployé le 15/09 à
10 h 06 UTC) : son `tripSettings.ts` filtrait déjà les co-voyageurs sur `role`,
mais son `schema.prisma` ne connaissait pas encore la colonne — elle est
arrivée avec la PR #28, fusionnée à 12 h 51 UTC, **qui n'a déclenché aucun
déploiement**. Le code de `main` est cohérent depuis ; il suffit de le
déployer. Les lignes inertes étaient la conséquence : les groupes de lignes se
désactivaient tant que `settings` était nul, donc aussi après un échec.

Ce que le lot change autour de ça, pour que la prochaine panne ne soit pas un
mur :

| Où | Avant | Après |
|---|---|---|
| Le serveur (`app.ts`) | « Erreur interne du serveur. » | « Notre serveur a rencontré un problème inattendu. Ce n'est pas de ton fait : réessaie dans un instant, et si ça continue, écris-nous depuis « Besoin d'aide ? ». » |
| L'app (`APIError.recoveryAdvice`) | rien | un conseil par famille d'erreur — 5xx, 404, 401, transport, décodage — et la vieille phrase d'un serveur pas encore redéployé est réécrite |
| `ErrorBanner` | une ligne, « Réessayer » | le constat, le conseil dessous, et « Réessayer » + « Besoin d'aide ? » — sur les paramètres du voyage et les personnalisations |
| Les groupes de lignes | `.disabled(settings == nil)` | `.disabled(model.isLoading)` : ils attendent la lecture, pas son échec |

### 20.2 Ce qui a changé, écran par écran

| Écran | Retour de Hugo | Ce qui a été fait |
|---|---|---|
| Accueil | « Commencer à enregistrer » fait disparaître l'app sur son iPhone, pas sur celui de Clara | `SpeechTranscriber` posait sa prise avec `inputFormat(forBus:)`, périmé dès qu'un casque Bluetooth change la fréquence de la session : `installTap` lève alors une exception Objective-C, que Swift ne rattrape pas. La prise lit désormais `outputFormat(forBus:)` et **renonce** si la fréquence du nœud et celle de la session divergent. C'est le seul écran de l'app qui transcrit en direct — le chat n'a que l'`AudioRecorder`, et il ne plantait pas. Voir T129 |
| Accueil | un « + » pour créer un voyage, à droite de « Ton voyage » (ou de « Voyage à venir » sans voyage en cours) | `HomeSectionHeading(onAdd:)` et `HomeAddButton` : le rond du « + » des co-voyageurs, cerné de bleu sur le crème. Il ouvre la feuille « Nouveau carnet » — créer, rejoindre, importer |
| Accueil d'un voyage | la roue des réglages plus petite que l'imprimante, et à droite d'elle | `Settings.svg` et `Settings 2.svg` **recadrés** (`viewBox="4.5 4.5 15 15"`) : le glyphe occupait 42 % de sa boîte, l'imprimante 68 % ; ils font désormais la même taille optique partout — chat compris. Et l'ordre de la conversation : réglages, puis imprimante. Recadrage repris le lendemain à `3.5 3.5 17 17` (§ 21) : à 15 unités, la roue paraissait cette fois plus grosse |
| Accueil d'un voyage | le CTA vert dit « Accéder au chat », flèche de la marque en fin de libellé | `IconArrowRight`, `iconPlacement: .trailing` ; le cadenas reste devant quand le quota est épuisé |
| Paramètres du voyage | un lien rouge « Supprimer ce voyage » tout en bas, avec une feuille de confirmation comme celle du compte, puis retour à l'accueil | `DeleteTripSheet` (ce qui part, « Garder ce voyage », « Supprimer définitivement ce voyage »), `TripSettingsModel.delete()` sur `DELETE /v1/memos/:id`, `TripSettingsIntent.tripDeleted` → `RootView` vide la pile, et l'accueil **se relit en réapparaissant** (`onAppear`). Le serveur réserve la route au propriétaire ; un co-voyageur lit son refus dans la feuille (T128) |
| Paramètres du voyage | le logo Tricount déposé dans `assets/logos` | `import-brand-logos.py` accepte désormais un PNG (`LogoTricount`) ; le « tt » de secours disparaît. Clôt T73 |
| Paramètres du voyage | « Commander le carnet » ouvre le tunnel de commande | `TripSettingsIntent.orderBook` → `HomeRoute.order`. La ligne n'attend plus `isPrintable`, que l'écran ne pouvait pas lire derrière un 500 : c'est le tunnel qui dit s'il n'y a rien à imprimer (T130) |
| Personnalisations du carnet | aucune modale ne s'ouvre, sauf « Typographie des titres » | même cause, même correction que les paramètres : `.disabled(model.isLoading)`. La ligne des titres était la seule hors d'un groupe désactivé, ce qui confirmait le diagnostic |
| Personnalisations du carnet | les trois interrupteurs du bas doivent écrire en base | ils l'étaient déjà — `BookCustomisationModel.setQuiz/setFreeZones/setCrossword` → `PATCH /v1/trips/:id/settings` (`quizEnabled`, `freeZonesEnabled`, `crosswordEnabled`) — et ne le pouvaient pas derrière le 500. Rien à changer côté chaîne ; vérifié de bout en bout sur le code de `main` |
| Couvertures — photo | « Choisir la photo » porte une vilaine icône de partage | `IconImport` (la flèche qui entre dans le plateau) à la place d'`IconTeleverser`, bleu, plein et hors grille (T101) |
| Couvertures — carrousels | le rond coché est tranché en haut | la file réserve une gouttière **de chaque côté** (`2 × m`) : elle centre le plat, donc la moitié seulement de l'air allait au-dessus — 12 pt, quand l'agrandissement en mange 17 et la pastille 13 |
| Couvertures — textes | des crayons ne font rien, pas de clavier | le crayon posait `focus = .title` alors que le champ n'existe **que** lorsqu'il a le focus : SwiftUI ne peut pas focaliser une vue absente, remettait `nil`, et rien n'apparaissait. Un état `editing` ouvre le champ d'abord ; le champ prend le focus en apparaissant |
| Partout | le voile sous les CTA est tantôt trop appuyé, tantôt s'arrête trop tôt | `BrandFooterScrim` — un fondu de 56 pt puis un aplat à 90 %, jusqu'au bord de la dalle — remplace les quatre voiles de l'accueil, de la galerie, de la commande et de la création d'un voyage ; l'offre du paywall le reçoit aussi |
| Paywall | les barres se remplissent à plusieurs sur « Continuer » ; retour doit repartir de zéro | la barre ne porte plus d'animation de six secondes : `PaywallFill` retient une **date de départ**, `TimelineView` calcule la part à chaque image, et le segment n'anime que les sauts — à 1 pour la barre qu'on quitte, à 0 pour celle où l'on revient. Voir la fiche § 13.3 |
| Paywall — offre | trop haut, « Besoin d'aide ? » se voit derrière ; gradient sous le CTA et la mention | `PaywallOffer` défile ; la mention et le bouton sont un pied sur `BrandFooterScrim` |
| Paywall — offre | la dernière icône a de vilains bords | `IconMoneyBag` était la bichrome — cerne bleu de 2 pt, bande crème —, rendue en gabarit : le cerne devenait de l'encre. `Money Bag.svg` entre dans `assets/icons/brand-icons` en **monochrome** (un seul tracé pair-impair, la bande crème devient un vide), et le script d'import régénère l'asset |
| Paywall — offre | « Voir une estimation » doit ouvrir la feuille du calcul (`3469:14105`) | `PaywallEstimationSheet` : durée et dates, prix du carnet et pages, cumul des abonnements cerclé, filet, montant final, cartouche « -20 % ». Sur les chiffres de la maquette (T127) |
| Paywall — offre | « Envoyer des vocaux en illimité » devient « Choisis ton mode de paiement », et ouvre la feuille de paiement avant de revenir à l'accueil | `PaywallPaymentSheet` sur un `ProfileModel` — cartes du compte, Apple Pay, « Ajouter une carte », « Payer 1,99 € » —, fabriqué par `RootView` (`profileModelFactory`) parce que le paywall se présente depuis trois écrans sans dépendances. « Payer » pose l'abonnement et referme le paywall. ⚠️ Rien n'est encaissé (T126) |
| Support et retours | moins d'air au-dessus de la photo, intro plus grande | 1 rem entre le titre et la photo au lieu de 2 ; l'intro passe au corps de texte (16) |
| Accueil — 1ère connexion | la nouvelle photo (`assets/photos/Welcome Background.png`), plein écran, jamais de blanc derrière la carte | `PhotoWelcomeHero.jpg` refait depuis le PNG (1080 × 1920, en 2x) ; la photo couvre la dalle entière, sous la carte comprise — tirer la carte vers le bas découvre la photo, plus le crème. Le voile d'encre à 40 % part avec l'ancienne image (T125) |

### 20.3 Ce qui entre dans le design system

| Pièce | Ce qu'elle porte |
|---|---|
| `BrandFooterScrim` / `.brandFooterScrim()` | **Le** voile d'un pied d'écran : fondu de `fadeHeight` (56) au-dessus, aplat crème à 90 % dessous, jusqu'au bord de la dalle. Cinq écrans le partagent |
| `ErrorBanner(message:advice:retry:help:)` | le constat, un conseil, et deux gestes. Sans conseil ni aide, le dessin d'origine |
| `APIError.recoveryAdvice`, `isServerSide` | le conseil par famille d'erreur, dans le module réseau |
| `LogoTricount` | le logo d'un tiers, en PNG tel quel — `import-brand-logos.py` sait désormais copier un bitmap |
| `IconMoneyBag` | monochrome, depuis `assets/icons/brand-icons/Money Bag.svg` |
| `IconSettings`, `IconSettingsDuo` | recadrés à la taille optique du reste du jeu |

### 20.4 À trancher

| # | Point |
|---|---|
| T125 | **La photo d'accueil n'a plus de voile.** L'ancienne portait un aplat d'encre à 40 % pour un texte blanc qui n'existe plus ; la nouvelle image est montrée telle quelle, sous le seul dégradé de la barre d'état. Si Clara veut l'assombrir sous la carte, c'est une ligne |
| T126 | **« Payer » n'encaisse rien.** La feuille de paiement du paywall pose l'abonnement comme le bouton le faisait avant elle (`ProfileModel.activateSubscription`, `SubscriptionSession.record`). StoreKit reste à brancher, ici comme sur la feuille d'abonnement du profil. Et la feuille d'ajout de carte se présente **par-dessus**, comme dans le profil et la commande — trois occurrences du même écart à la règle des feuilles enchaînées, à régler ensemble |
| T127 | **La feuille « Estimation » calcule sur les chiffres de la maquette** — trois semaines à partir d'aujourd'hui, 50 pages, 60 € — et seul le prix hebdomadaire vient de l'offre. `GET /v1/wallet` connaît déjà l'estimation d'un carnet ; la lire depuis le paywall demande de savoir quel voyage on finance (`previewMemoId`) et un appel de plus |
| T128 | **Le lien « Supprimer ce voyage » s'affiche aussi aux co-voyageurs**, à qui le serveur refuse la suppression : `TripSettings` ne dit pas si le compte qui regarde est le propriétaire. Une ligne `isOwner` sur le voyageur courant — ou `companions` marqué « moi » — permettrait de ne le montrer qu'à lui |
| T130 | **« Commander le carnet » ouvre toujours le tunnel**, même sans carnet composé : c'est `GET /v1/memos/:id/order-context` qui répond alors, et son message. À vérifier sur un voyage sans rendu |

### 20.5 « Testing mode » et l'erreur `localhost`, pour la dernière fois

Un build Debug posé par ⌘R sur un iPhone embarquait `http://localhost:3000` —
sur le téléphone, c'est le téléphone —, et « Testing mode » répondait « Rien
n'écoute sur localhost:3000 ». La parade documentée (`Secrets.xcconfig` avec
l'IP du Mac) reposait sur une action à ne pas oublier ; elle a été oubliée deux
fois. Le build ne peut plus l'embarquer :

| Garde-fou | Où | Ce qu'il fait |
|---|---|---|
| Le SDK décide de l'adresse | `Config/Debug.xcconfig` | `[sdk=iphonesimulator*]` → `localhost`, `[sdk=iphoneos*]` → la production, écrite une seule fois dans `Base.xcconfig` |
| La production voyage toujours | `project.yml` → `MemoBookProductionAPIBaseURL` | une seconde clé de l'Info.plist, dans tous les builds |
| L'app refuse une boucle locale hors simulateur | `APIConfiguration.effective(configured:productionFallback:runsInSimulator:)`, `APIConfigurationTests` | remet la production à la place ; sans production ni simulateur, l'app s'arrête net au lieu de parler dans le vide |
| Le message dit la vraie cause | `APIError.developerDiagnosis` | sur un appareil, « Ce build parle à localhost depuis un iPhone » au lieu de « lance `npm run dev` » |
| Le simulateur marche sans back-end | `APIConfiguration.fallbackBaseURL`, `MemoBookAPIClient.rebasedOnFallback` | `localhost` d'abord, la production au premier appel refusé, pour la session ; un délai dépassé ne bascule pas. Trois tests dans `APIClientTests` |

Vérifié par `xcodebuild -showBuildSettings` sur les deux SDK, par un build
Debug pour appareil (`generic/platform=iOS`) dont l'Info.plist porte la
production, et par les six tests de `APIConfigurationTests`. Pour viser le Mac
depuis un iPhone, `Secrets.xcconfig` pose l'IP avec la condition
`[sdk=iphoneos*]` — la dernière affectation l'emporte, conditionnée ou non ;
sans condition, le simulateur perd `localhost` aussi. Voir `docs/deploiement.md`.


---

## 21. Retouches du 16/09/2026 — la seconde relecture, et les mots

Neuf retours de Hugo sur la branche de la veille, traités dans la même PR
(#31). Pas de nouvel écran : trois comportements corrigés, une feuille qui sert
quatre fois, et **un lexique** — `docs/vocabulaire.md` — pour que les mots des
maquettes, des fiches, du code et des conversations soient les mêmes.

### 21.1 Ce qui a changé, écran par écran

| Écran | Retour de Hugo | Ce qui a été fait |
|---|---|---|
| Feuille d'abonnement | « Voir un aperçu » quittait « Comment ça fonctionne » ; refermer l'aperçu doit y ramener, avec le petit zoom | L'aperçu redevient une **feuille posée sur** la feuille d'abonnement (`SubscriptionSheet.showsPreview`), et non une étape : l'offre recule d'un cran et revient telle quelle. C'est l'exception voulue à « un enchaînement de feuilles ne s'empile pas » — § 16.9, `ios/CLAUDE.md`, T133 |
| Paywall | la flèche doit reculer d'un écran, pas fermer sur le profil | `turn(-1)` ; elle ne ferme que depuis le premier écran, et son libellé VoiceOver le dit — « Retour », puis « Fermer ». Répond pour moitié à T132 (voir T135) |
| Conversation | les trois petites lignes à gauche des trois boutons ne servent à rien | Le burger part, et `ChatCopy.Voice.menu` avec lui : il ne restait que par fidélité à la maquette et ne menait nulle part. La croix seule, dès qu'un outil est ouvert — comme déjà en taille de texte accessible (T134) |
| Accueil d'un voyage, conversation | la roue des réglages trop grosse face à l'imprimante | `Settings.svg` et `Settings 2.svg` recadrés à `viewBox="3.5 3.5 17 17"` (15 la veille) : un rond plein de la largeur d'une imprimante à traits fins pèse plus qu'elle. Le script d'import a régénéré `IconSettings` et `IconSettingsDuo` |
| Personnalisations du carnet | aucune modale ne marche ; les quatre typographies doivent se comporter pareil, données branchées | Sur le code de `main`, les six feuilles marchent : c'est la production qui sert encore un serveur d'avant (T131 → T137). Les typographies : **une** feuille pour les quatre rôles (`BookFontsSheet(role:)`, `BookFontRole`), chacune écrit sa colonne — `fontDisplay`, `fontTitle`, `fontHand`, `fontFacts` —, le client encode les trois éditions nouvelles, le bac à sable les rejoue, le `PATCH /v1/trips/:id/settings` les accepte et `screens.test.ts` les couvre. Chaque liste : le défaut du rôle, puis les trois familles de la maquette (T136). Les lignes affichent le libellé de la maquette (« Playfair ») là où la base dit « Playfair Display » |
| Personnalisations du carnet | « le serveur a l'air éteint » | Il ne l'était pas : il servait encore `eba4dc6`, dont `GET …/settings` répond 500 (§ 20.1). Le déploiement de `main` depuis cette session a été **refusé par son garde-fou** (« Production Deploy ») ; Hugo l'a lancé lui-même dans la foulée, et la route répond 200 — T137 |
| Partout — le clavier | ce qu'on tape ne doit jamais passer sous le clavier ; l'icône centrée dans la bulle ou sur la ligne, quel que soit l'iOS | `KeyboardDismissBar` ne se soulève plus : ses 8 pt la sortaient du centre de la bulle d'iOS 26, et de la ligne avant. Les textes des couvertures : le champ qui s'ouvre sous le plat, tout en bas, est amené au-dessus du clavier une fois celui-ci monté (`ScrollViewReader`, T138). Les autres formulaires laissent le système faire — leurs champs existent avant d'avoir le focus, et une `ScrollView` les remonte d'elle-même |
| Paramètres du voyage | « Tu es sûr de vouloir supprimer ce voyage » sans le nom du voyage | Sur l'iPhone de Hugo, le nom manquait parce que les réglages n'arrivaient pas (le 500). La phrase ne s'ouvre plus sur des guillemets vides : sans nom, « Ce voyage sera effacé… » (`BookCopy.Settings.Delete.body(trip: String?)`) |

### 21.2 Ce qui entre dans le code partagé

| Pièce | Ce qu'elle porte |
|---|---|
| `BookFontRole`, `BookFontOption` (`MemoBookCore`) | les quatre rôles — titres, sous-titres, textes, fun facts —, la colonne que chacun écrit, son édition, ses familles, et le libellé de la maquette face au nom que le gabarit résout |
| `BookCustomisationEdit.fontTitle / fontHand / fontFacts` | trois éditions de plus, portées par `MemoBookAPIClient`, `PreviewAPI` et `routes/tripSettings.ts` |
| `BookCopy.Fonts.sheetTitle(for:)`, `sheetSubtitle(for:)` | le titre et le chapeau des trois feuilles que la maquette ne dessine pas, au tutoiement (R9) |
| `docs/vocabulaire.md` | le lexique — lié depuis le README, `ios/CLAUDE.md` et l'en-tête de ce fichier |

### 21.3 À trancher

| # | Point |
|---|---|
| T133 | **L'aperçu se pose sur la feuille d'abonnement** : première exception assumée à « un enchaînement de feuilles ne s'empile pas ». Les trois empilements de T126 (la feuille d'ajout de carte) restent à régler ; si Clara les accepte aussi, la règle devient « une feuille ne s'empile que pour aller voir et revenir » |
| T134 | **Le burger de la conversation a quitté l'app, pas la maquette.** Le nœud du chat le dessine encore à gauche des trois boutons ; à retirer dans Figma, ou à lui donner un menu |
| T136 | **Trois feuilles de typographie sans maquette.** « Sous-titres du carnet », « Textes du carnet », « Fun facts du carnet » sont écrites sur le modèle de « Titres du carnet » (`3443:10073`), au tutoiement ; leurs familles — Hansley ou Gloria Hallelujah d'abord, puis Playfair, Alegreya, Montserrat — et leurs phrases sont à valider ou à dessiner. « La recommandations de nos équipes » reste tel quel sur la feuille des titres (R8) ; les défauts des autres disent « Le choix de nos équipes ». Remplace T78 |
| T138 | **Le champ des textes de couverture remonte après 350 ms**, le temps que le clavier monte — une durée choisie, pas mesurée. Sur un iPhone lent, le premier caractère peut encore se taper sous le clavier ; la parade propre est d'écouter sa hauteur (`keyboardLayoutGuide`), ce qui touche au design system |

## 22. Retouches du 16/09/2026 (soir) — treize retours, et deux chantiers

Treize retours de Hugo sur `main`, traités dans une même PR. Deux d'entre eux
ne sont pas des retouches mais des **fonctionnalités** — les limites de
souvenirs et le cache local —, et ils amènent chacun leur lot de base, de
route, de modèle et d'écran.

⚠️ **Six écrans ou blocs de cette section n'ont pas de maquette** : la ligne et
la feuille des limites de souvenirs, la feuille des assortiments de
typographies, le champ de recherche du support, les messages d'information des
couvertures, la carte « Bientôt disponible » et le lien « Commander sans
attendre ». Ils sont écrits sur les motifs existants et **restent à dessiner
dans Figma** — voir « À trancher ».

### 22.1 Ce qui a changé, écran par écran

| Écran | Retour de Hugo | Ce qui a été fait |
|---|---|---|
| Abonnement — résiliation | une semaine payée doit aller à son terme ; le dire sur l'avant-dernière modale ; une alerte système quand ça s'arrête pour de bon ; si le dernier jour est aujourd'hui, rien ne change | `Subscription.paidThrough` (= `subscriptions.renewsAt`) et trois règles testées — `isWithinPaidWeek`, `grantsAccess`, `graceEnd`. La feuille « Pourquoi nous quittes-tu ? » annonce « jusqu'au 22 septembre inclus », la dernière dit « ne se renouvellera pas » au lieu de « s'arrête aujourd'hui ». **Le dernier jour garde la phrase d'avant**, à la journée près. Côté serveur, `assertCanRecord` accepte un abonnement `cancelled`/`expired` dont la période court encore. L'alerte native s'ouvre sur l'accueil (`Traveller.subscriptionEndedOn`, borné à 15 jours côté serveur, `@AppStorage` côté app pour ne le dire qu'une fois) |
| Réglages du voyage | des limites de souvenirs, hautes, visibles **ici seulement**, avec un palier étendu à 3,99 €/semaine ; jamais le mot « token » | Une ligne « Limites de souvenirs » sous la cagnotte, muette tant qu'il reste de la marge, et une feuille en trois temps — solde, comparaison, confirmation. **2 000 souvenirs/semaine** compris, 8 000 étendus. Un message écrit vaut 1, une **minute entamée** de vocal vaut 10 (`services/memoryAllowance.ts`, seul endroit où le barème vit). La durée part désormais avec le vocal (`uploadAudio(durationSeconds:)`), et voyage déjà dans la file hors ligne |
| Couvertures | griser ce qu'un style ne porte pas — texte au dos, photo sur un aplat —, avec un message en couleur d'information | `CoverTreatment.carriesPhoto` / `carriesText(on:)`, et `BookCovers.acceptsPhoto/acceptsText`. Le segment du rail et la ligne d'action **pâlissent sans se désactiver** : ils restent tapables, et l'appui pose un `BrandNotice(tone: .information)` qui nomme la cause *et* donne la sortie. Le plat lui-même cesse d'écrire le texte de quatrième sur une photo pleine page — sinon le dessin contredirait l'explication |
| Accueil — entrée | la carte de connexion laisse voir la photo et sa coupe nette quand on la tire vers le haut | Le crème de la carte déborde d'**une hauteur d'écran** sous la dalle (`WelcomeView.cardUnderrun`). `ignoresSafeArea` ne suffisait pas : il prolonge jusqu'au bord, pas au-delà, et l'élastique de la `ScrollView` va plus loin. Un fond n'impose pas sa taille, donc la mise en page ne bouge pas |
| Partout — le prix | 1,99 €/semaine partout, y compris le « 3 × » de l'estimation, au lieu de 0 € | `services/subscriptionCatalog.ts` : le tarif est servi à qui **n'a pas** encore d'abonnement (le serveur rendait 0, faute de ligne à lire). Côté app, `Subscription.displayedWeeklyPrice` ne rend jamais zéro. Le seed disait 2,99 €, corrigé. Un prix Stripe `memobook_subscription_weekly` existe désormais dans le sandbox |
| Aperçu PDF | pouvoir commander même quand le carnet n'est pas composé, **hors debug** | Un lien beige sous le bouton grisé, en légende soulignée, uniquement quand `!isComposed`. Dans la version livrée : un TestFlight est un build Release, et une porte sous `#if DEBUG` ne s'ouvre nulle part où l'on en a besoin |
| Support et retours | un champ de recherche sous l'introduction, résultats vivants | `BrandSearchField` (nouveau) + `FaqQuery`, qui cherche dans la **question, la réponse et le titre du paquet**, sans casse ni accents, tous les mots devant répondre. Le filtre vit dans `SupportModel`, pas dans un `body`. La ligne « Écris à notre équipe » reste **toujours** visible : c'est la sortie d'une recherche qui ne trouve rien |
| Partout — l'ouverture | garder un maximum de données en local, et animer la mise à jour quand le serveur dit autre chose | `ContentCache` (l'ancien `HomeFeedCache`, devenu générique) garde cinq choses : accueil, profil, voyage, réglages du voyage, galerie. Les cinq modèles s'ouvrent dessus et **continuent** l'appel derrière ; `contentFreshness(of:replacing:)` dit si ça a bougé, et `BrandRefreshFlash` joue un balayage et une pastille « Mis à jour ». Rien n'est animé à la première arrivée ni sur une réponse identique |
| Paiement | Apple Pay sélectionné doit se voir comme les autres | `BrandApplePayRow` retenue passe au **bleu de la marque sur un aplat bleu à 35 %**, exactement comme une `BrandOptionRow` cochée. Elle portait le vert d'action et aucun fond |
| Paywall → support | la flèche doit revenir à l'étape du paywall, pas au profil | Le support se pose **sur** le paywall (`fullScreenCover`), qui reste monté avec sa page ; sa flèche `dismiss()` y ramène sans une ligne de plus. Le minuteur des stories s'arrête pendant ce temps, comme devant l'aperçu. `PaywallView.onHelp` disparaît, et `RootView` descend le `SupportModel` de la session (`\.supportModel`) |
| Nouveau carnet | « Importe depuis Polarsteps » n'est pas dans la V1 | `NewNotebookOptionCard.availability = .comingSoon` : aplat beige, contour et titre au beige, contenu à 75 %, flèche retirée, et une pastille « Bientôt disponible » **à l'encre pleine** posée à cheval sur le coin. La carte n'est pas `disabled` — ça l'aurait grisée et aurait emporté la pastille — elle perd son geste (`allowsHitTesting`) et son rôle VoiceOver |
| Personnalisations | une seule ligne de typographie, groupée avec les décors, ouvrant quatre **combos** ; le choix des combos est de ton ressort | Les quatre lignes deviennent « Typographies », rangée avec Fun facts / Pointillés / Décorations. `BookFontCombo` porte quatre assortiments — **Carnet de voyage** (le défaut d'aujourd'hui : Playfair, Hansley, Hallelujah, Playfair), **Éditorial**, **Moderne**, **Manuscrit** — et la feuille écrit en face de chaque police **ce qu'elle habille**. `BookCustomisationEdit.fontCombo` envoie les quatre colonnes en un seul `PATCH` : quatre requêtes auraient laissé trois états intermédiaires que personne n'a choisis |
| Personnalisations | le chapeau est trop petit, et il vouvoie | Le chapeau passe au **corps de texte** (16, à l'encre pleine) et le détail d'une `BrandToggleCard` de 12 à 14. Et **tout le vouvoiement du carnet, du voyage et de la cagnotte est corrigé** : douze phrases, R9 l'emportant sur R8 — voir § 22.2 |
| E-mail de réinitialisation | reçu en spam, et le bouton ne marchait pas | **Déjà corrigé** par la PR #32 (`lien-de-reinitialisation`), ouverte et non fusionnée : le lien devient une URL `https://` servie par l'API, et `RootView` repasse le secret à `AuthView`. Rien n'a été refait ici. Le **spam**, lui, est un sujet de délivrabilité (SPF/DKIM/DMARC du domaine d'envoi), pas de code — voir « À trancher » |

### 22.2 Le vouvoiement de la maquette n'est plus recopié

R8 dit « la copie de Figma au caractère près », R9 dit « on tutoie
l'utilisateur, toujours ». Les deux s'opposaient sur une douzaine de phrases du
carnet, du voyage et de la cagnotte, qui vouvoyaient au milieu d'une app qui
tutoie — et chacune portait un commentaire « signalé » depuis des semaines.

**R9 l'emporte** (Hugo, 16/09/2026), comme il l'emportait déjà sur les cinq
feuilles de l'abonnement. Chaque phrase corrigée le dit dans son commentaire, et
la liste vit ici pour que Clara les reprenne **à la source** :

| Où | Avant | Après |
|---|---|---|
| Personnalisations, chapeau | « Ajuster les différents options … votre carnet vous ressemble » | « Ajuste les différentes options … ton carnet te ressemble » |
| Couvertures, style assorti | « Assortie à votre 1e de couverture » | « Assortie à ta 1re de couverture » |
| Cagnotte, vide | « Partagez votre cagnotte avec vos proches » | « Partage ta cagnotte avec tes proches » |
| Rythme du récit | « Ajustez … vos émotions et votre personnalité » | « Ajuste … tes émotions et ta personnalité » |
| Notifications | « Activez ou désactivez les alertes … » | « Active ou désactive les alertes … » |
| Thème | « … l'agencement graphique de vos souvenirs » | « … de tes souvenirs » |
| Co-voyageurs | « Invitez vos proches à participer … » | « Invite tes proches à participer … » |
| Ratio média | « Déterminez l'importance visuelle … » | « Détermine l'importance visuelle … » |
| Nombre de page | « Gérez le niveau de détails de votre carnet … » | « Gère le niveau de détail de ton carnet … » |
| Fun facts | « … pour agrémenter vos récits » | « … pour agrémenter tes récits » |
| Pointillés | « … dans votre carnet » | « … dans ton carnet » |
| Décorations | « Déterminez la quantité … dans vos pages » | « Détermine la quantité … dans tes pages » |

Trois coquilles restent recopiées telles quelles, parce qu'elles ne touchent pas
à la personne à qui l'app parle : « grace » sans circonflexe, « Prévisulation »,
« Défini » pour « Définis ».

### 22.3 Ce qui entre dans le code partagé

| Pièce | Ce qu'elle porte |
|---|---|
| `BrandSearchField` (`Design`) | **le** champ de recherche : capsule, loupe, croix qui efface sans rendre le clavier. Distinct de `BrandTextField`, qui saisit une valeur dans un formulaire — celui-ci filtre ce qui est en dessous |
| `BrandGauge` (`Design`) | **la** jauge : une barre qui se lit, jamais qu'on règle. Vert d'action, rouge sémantique à zéro, **pas d'orange** — trois couleurs demanderaient une légende |
| `BrandRefreshFlash` (`Design`) | le balayage et la pastille « Mis à jour ». Rien ne bouge en Reduce Motion, sauf la pastille, en fondu |
| `BrandNotice(tone:)` (`Design`) | un second ton, `.information` : filet, pictogramme et aplat dilué en `MemoBookColor.information`. Pour ce qu'on **explique** à quelqu'un qui vient de taper quelque part |
| `BrandSegmentedPicker(isAvailable:onUnavailable:)` | un segment fermé **pâlit et reste tapable**. Un `disabled` avale le geste et n'explique rien |
| `BookFontCombo`, `BookFontOption.catalogue` (`Core`) | les assortiments (quatre alors, trois depuis le 18/09), les cinq familles, et la résolution « Playfair » ↔ « Playfair Display » |
| `MemoryAllowance`, `MemoryPlan`, `MemoryCopy` (`Core`) | les limites de souvenirs et tout ce qu'elles font écrire. **Le mot « token » n'y figure pas** |
| `Subscription.paidThrough` + `grantsAccess/graceEnd` (`Core`) | le sursis de la semaine payée, testé dans `SubscriptionGraceTests` |
| `FaqQuery`, `FaqCategory.filtered(by:)` (`Core`) | la recherche du support, sans casse ni accents, tous les mots devant répondre |
| `ContentCache`, `CachedValue`, `ContentFreshness` (`Feature`) | le cache local et sa règle d'animation, en une seule pièce pour les cinq écrans |
| `\.supportModel` (`Feature`) | le support de la session, à portée du paywall |

### 22.4 Contrat back-end

| Route | Ce qui change |
|---|---|
| `GET /v1/profile` | `subscription.weeklyPrice` rend le **tarif du catalogue** quand rien n'a été souscrit (il rendait 0) ; `subscription.cancelledAt` et `subscription.paidThrough` s'ajoutent |
| `GET /v1/home` | `traveller.subscriptionEndedOn` — la fin de la semaine payée du dernier abonnement, **si elle date de moins de quinze jours**. Déduit, pas stocké |
| `GET /v1/trips/:id/settings` | `memory` : palier, consommé, plafond, date de renouvellement, prix **hebdomadaire** de l'extension, et les **deux coûts** (un message, une minute de vocal) |
| `POST /v1/trips/:id/memory-plan` | nouvelle. Pose le palier et rend les réglages entiers. ⚠️ **N'encaisse rien** — voir « À trancher » |
| `POST /v1/memos/:id/entries` | accepte `durationSeconds` en multipart, le range sur `media_assets`, et **décompte** les limites de souvenirs. Refus `403 memory_limit_reached` |
| Migration | `20260916230000_limites_de_souvenirs` — `accounts.memoryPlan`, `memoryUsed`, `memoryPeriodStart`, et l'énumération `MemoryPlan`. ⚠️ À appliquer **aussi** au schéma `memobook_test`, sinon la suite entière échoue |

### 22.5 À trancher

| # | Point |
|---|---|
| T139 | **L'abonnement et l'extension ne s'encaissent toujours pas.** Un prix Stripe `memobook_subscription_weekly` (1,99 €/semaine) existe dans le sandbox et donne au back-end une référence, mais Apple impose l'achat intégré pour un service numérique : c'est **StoreKit** qui portera les deux transactions, et `POST /v1/trips/:id/memory-plan` deviendra alors ce que son reçu appelle. Le prix `memobook_memory_upgrade_monthly` (3,99 €/mois) **reste à créer** — la commande a été refusée par le garde-fou de la session |
| T140 | **Le barème des souvenirs est un ordre de grandeur, pas une mesure.** 1 pour un message, 10 pour une minute de vocal : à réétalonner sur les factures OpenAI et Anthropic d'un mois plein. Les deux constantes sont dans `services/memoryAllowance.ts`, et les deux coûts voyagent jusqu'à l'app — l'écran n'en écrit aucun |
| T141 | **Le plafond du palier étendu est écrit dans l'app** (`MemoryAllowanceSheet.extendedAllowance = 8 000`), faute de route de catalogue : la réponse ne porte que le palier *courant*. À remplacer le jour où `GET /v1/catalog` existe |
| T142 | **Trois assortiments, une famille absente du gabarit.** `fonts.css` n'inline que Playfair Display et Gloria Hallelujah ; Hansley est versionné sans être inliné, Alegreya n'est pas là (Montserrat n'est plus promise : « Moderne » est retiré le 18/09/2026). Rien n'échoue — la page retombe sur une police système —, et c'était déjà vrai des quatre lignes que les combos remplacent. À inliner avant de promettre « Éditorial » |
| T143 | **Six blocs sans maquette** : la ligne et la feuille des limites de souvenirs, la feuille des assortiments, le champ de recherche du support, les messages d'information des couvertures, la carte « Bientôt disponible », le lien « Commander sans attendre ». Écrits sur les motifs existants, au tutoiement, à dessiner dans Figma |
| T144 | **Quel style de couverture porte quoi, c'est l'app qui le décide.** `CoverTreatment.carriesPhoto` et `carriesText(on:)` sont des règles écrites ici : la photo pleine page au dos n'a pas de texte, l'aplat et le kraft n'ont pas de photo. À valider avec Clara, et à faire redescendre du serveur le jour où le catalogue des styles y vivra |
| T145 | **L'e-mail de réinitialisation arrive en spam.** Le lien est réparé (PR #32) ; la délivrabilité ne l'est pas. Elle demande SPF, DKIM et DMARC sur le domaine d'envoi côté Resend, plus un expéditeur au domaine de la marque — c'est une configuration DNS, pas du code. À faire avant la beta élargie |
| T146 | **L'écran d'entrée n'a pas été vérifié sur un petit écran.** Le débordement du crème sous la dalle est la correction du bord net ; aucun simulateur SE (375 × 667) n'est installé sur cette machine, et c'est précisément le format où le défaut se voit. À revoir au premier build TestFlight |

### 22.6 Après coup — la cadence, et une erreur de prix trouvée en chemin

**3,99 € c'est par semaine, pas par mois** (Hugo, 17/09/2026), et l'extension
**reste sous le produit « Abonnement MemoBook »** : ce n'est pas une seconde
offre, c'est une option de l'abonnement.

La cadence ne s'arrête pas au prix. Un plafond mensuel derrière un prélèvement
hebdomadaire aurait annoncé quatre fois le montant affiché — « 12 000 souvenirs
par mois pour 3,99 €/semaine », soit ~17 €/mois. **Tout passe donc à la
semaine** : le prix, la période (`PERIOD_DAYS = 7`), et les plafonds.

| | Avant | Après |
|---|---|---|
| Palier compris | 3 000 / mois | **2 000 / semaine** |
| Palier étendu | 12 000 / mois | **8 000 / semaine** |
| Prix de l'extension | 3,99 €/mois | **3,99 €/semaine** |

2 000 souvenirs par semaine, c'est 200 minutes de vocal — près de 30 minutes par
jour. Un voyageur qui raconte 20 minutes quotidiennes en consomme 1 400 : la
limite ne mord pas, ce qui est exactement ce qu'on lui demande.

**Et une erreur de prix trouvée en passant** : le pied de page de l'écran
d'offre du paywall écrivait « Renouvellement automatique pour 1,99 €/**mois** »,
alors que l'abonnement est hebdomadaire — la feuille d'abonnement l'écrit,
l'estimation compte trois semaines. Il annonçait donc le quart du prix réel.
Corrigé (`PaywallCopy.offerFootnote`). C'est la même famille que le 0 € de
§ 22.1, et elle n'était pas dans les treize retours.

⚠️ **L'intervalle d'un prix Stripe ne se modifie pas.** Le prix mensuel créé par
erreur est **désactivé**, pas supprimé — un prix ne se supprime jamais —, et un
prix hebdomadaire le remplace sous la clé `memobook_memory_upgrade_weekly`.

---

## 25. « Supprimer la conversation » — dans les réglages du voyage

Hugo, 17/09/2026 : un lien « Supprimer la conversation » **juste au-dessus de
« Supprimer ce voyage »**, et supprimer veut dire **garder la bulle
d'introduction de MEMO** (« Bonjour 👋 Je suis MEMO… »).

**Le lien** — à l'encre avec la bulle (`IconBubble`), sur le dessin de « Me
déconnecter » : deux croix rouges l'une sur l'autre auraient dit deux fois la
même chose, et effacer un fil se rattrape plus qu'effacer un voyage. Les deux
portes partagent maintenant un seul dessin (`TripSettingsView.exitLink`).

**La feuille** — `ClearConversationSheet`, sur le modèle de `DeleteTripSheet` :
le bouton plein garde, le rouge efface, et le paragraphe dit ce qui part **et
ce qui reste** — le mot d'accueil revient, les souvenirs déjà dans le carnet
n'y sont pour rien. On reste sur les réglages après : c'est le fil, en dessous
dans la pile, qui se vide.

**Ce qu'on retrouve en revenant** — la bulle d'ouverture de MEMO, la relance du
voyage s'il en a une, et les puces d'ouverture. **Pas** l'écran d'accueil du
chat (le M et « Nouveau voyage à Rome ! ») : celui-là est l'écran de quelqu'un
qui n'a jamais rien dit, et on a effacé ce qu'on s'est dit, pas fait comme si
on ne s'était jamais parlé.

**Comment ça tient, sans serveur.** Il n'y a pas de conversation côté serveur
— ni `GET /v1/trips/:id/chat`, ni `DELETE` — et le fil vient du jeu d'essai
(§ 14). `ConversationArchive` retient donc les voyages dont la conversation a
été supprimée, dans les réglages de l'app, un pour la session
(`AppDependencies.conversations`) :

| Qui | Quoi |
|---|---|
| `TripSettingsModel.clearConversation()` | y écrit, par la fonction que `AppDependencies` lui passe — le jour où la route existe, c'est cette fonction qui l'appelle |
| `ChatModel` | y lit : un voyage supprimé rend son fil vide (`ChatThread.cleared()`) puis pose l'ouverture de MEMO (`ensureOpening()`) |
| `ChatView` | recharge sur `archive.version` : l'écran du chat reste sous celui des réglages dans la pile, il ne se refabrique pas au retour |

Le bac à sable des réglages gagne « Rétablir la conversation » : après une
suppression, c'est le seul moyen de revoir le jeu d'essai sans réinstaller.

`ConversationArchiveTests` (cible app) garde les trois promesses : un fil
supprimé rouvre sur l'ouverture de MEMO, un fil intact garde ses bulles, et la
suppression survit à un relancement.

### 25.1 À trancher

| # | Sujet | Écran / parcours |
|---|---|---|
| T158 | **La suppression n'existe que sur l'appareil.** Un autre téléphone du même compte verra la conversation du jeu d'essai. C'est la conséquence de l'absence de route, pas un choix : `DELETE /v1/trips/:id/chat` remplacera l'archive le jour où le fil sera servi | « Supprimer la conversation » — dans les réglages du voyage |
| T159 | **Aucune maquette** pour le lien ni pour la feuille : écrits sur les motifs existants (« Me déconnecter », `DeleteTripSheet`). À dessiner dans Figma | « Supprimer la conversation » — dans les réglages du voyage |
| T160 | **Un co-voyageur peut supprimer la conversation**, alors qu'il ne peut pas supprimer le voyage. Aujourd'hui le fil est propre à l'appareil, la question ne se pose pas ; elle se posera avec la route — qui décide de l'effacer pour tout le monde ? | « Supprimer la conversation » — dans les réglages du voyage |
## 26. La relance du voyage n'est pas une bulle

Hugo, 17/09/2026 : **la bulle d'ouverture de MEMO est seule.** Elle se termine
déjà sur une question — « pourrais-tu me faire un contexte global de ton
voyage ? » — et la personne doit y répondre. « Comment ça se passe à
Testaccio ? » ne doit jamais venir par-dessus, ni en seconde bulle
d'ouverture, ni en dernière bulle du fil.

Deux endroits la posaient, les deux sont retirés :

| Où | Avant | Après |
|---|---|---|
| `LocalMemoResponder.opening(for:)` | la bulle d'ouverture, puis `context.prompt` en seconde bulle | la bulle d'ouverture, seule |
| `ChatThread.fixture` | la relance du jour en dernière bulle, sous des puces « question ouverte » | rien après « C'est enregistré », et les puces d'après-validation (raconter à l'oral, importer des photos, plus tard) |

`ChatContext.prompt` reste : le répondeur doit savoir de quelle journée on
parle, et c'est la relance que portera la **notification** — celle qui
rappellera à qui n'a pas raconté sa journée. La carte de l'accueil du voyage
(« Comment ça se passe à Hanoï ? » + « Accéder au chat ») continue de
l'afficher : c'est là qu'elle relance, pas dans le fil.

`ChatResponderTests.testTheOpeningIsTheSingleOpeningBubble` le garde, avec un
contexte qui porte une relance.

### 26.1 À trancher
## 23. Lot 8 — Les documents légaux

### 23.1 Conditions d'utilisation, et Politique de confidentialité

- **Nœud Figma** : aucun — la référence est le gabarit « Template Pages
  Légales » fourni par Hugo (17/09/2026), une image, pas un nœud. Il dessine le
  **motif** (des cartes qui se déplient, la première ouverte en bleu, un pied
  « Besoin d'aide ? Découvrir notre FAQ ») avec des titres de remplissage
  (« Chapitre 1 — Principes », du lorem ipsum).
- **Vue** : `MemoBookFeature/Legal/LegalDocumentView.swift` — **une seule vue
  pour les deux documents**, qui reçoit un `LegalDocument` (titre + chapitres).
- **Rôle** : lire un document légal du site, chapitre par chapitre.
- **Entrée / sortie** : les deux lignes du groupe légal du profil
  (`ProfileIntent.openTermsOfUse` / `.openPrivacyPolicy` →
  `HomeRoute.legal(.termsOfUse | .privacyPolicy)`). Sortie par la flèche, ou
  par « Découvrir notre FAQ » vers le support (`LegalIntent.openHelp`).

**Structure (en rem)** — marge d'écran 1 ; en-tête `BrandScreenHeader` ; les
cartes à 1 d'écart, marge intérieure 1, rayon 1.25 (celui des cartes de
l'accueil) ; titre en `cardTitle` (Sora 16), chevron du jeu de marque à 22 pt
comme sur une `BrandRow`, tourné de 90° (bas) ou −90° (haut) ; corps en
`taglineRegular` (14), en sourdine repliée, à l'encre dépliée ; **trois
lignes** visibles repliée. Le pied à 0.5 sous la dernière carte.

**Tokens utilisés** — `surface` + `hairline` pour une carte repliée, `outline`
(le bleu d'aplat) pour une carte dépliée ; `ink`, `inkMuted` ; `action` pour
les liens du texte (l'adresse de contact, le site de la CNIL) ; `tagline`
(General Sans Semibold 14) pour les étiquettes `**…**` et les intertitres.
Rien de nouveau.

**Composants** — **`BrandDisclosureCard`** entre dans le design system : le
motif « carte qui se déplie » n'existait pas (`BrandToggleCard` règle,
`BrandRow` mène ailleurs, ici on lit). Le contenu replié et le contenu déplié
sont deux vues fournies par l'écran ; la carte ne sait pas ce qu'elle porte et
c'est l'écran qui tronque. L'état appartient à l'écran (un `Set` d'identifiants
— plusieurs chapitres peuvent être ouverts à la fois ; le premier l'est à
l'arrivée).

**« Si le contenu est trop long, on peut appuyer » — et pas autrement.** La
carte a un interrupteur `isExpandable` : faux, elle perd son chevron et ne
répond plus au toucher (sans `disabled`, qui éteindrait le titre). L'écran le
règle en **mesurant** : `LegalText` dessine le même texte caché sans limite
sous le texte limité et compare les deux hauteurs (`onGeometryChange`) — la
seule façon en SwiftUI de savoir si `lineLimit` a coupé. Mesuré et non deviné,
parce qu'un chapitre qui tient sur un 17 Pro Max déborde à AX3. Un chapitre
dont l'aperçu tient **mais qui a une structure** (intertitres, puces, lignes)
reste dépliable : trois lignes d'adresse jointes par des espaces ne sont pas le
chapitre. Aujourd'hui, un seul chapitre est concerné : « Cookies » de la
politique de confidentialité.

Le corps d'un chapitre (`LegalChapterBody`) et le paragraphe avec ses liens et
ses étiquettes (`LegalText`) sont spécifiques à l'écran. `LegalText` lit deux
balises Markdown et seulement celles-là : le lien, et `**…**` — traduit en
General Sans Semibold par portions, comme `BrandNotice`, parce que le gras est
une autre police et non un épaississement.

**Copie** — le texte des deux documents vient du site memobook.fr, recopié au
caractère près dans `MemoBookCore/TermsOfUse.swift` (9 chapitres) et
`MemoBookCore/PrivacyPolicy.swift` (11 chapitres) ; la forme dans
`LegalDocument.swift`, les libellés de l'interface dans `LegalCopy`.
Apostrophes typographiques, espaces insécables dans le SIRET et le numéro de
TVA. Le titre d'une carte suit le motif du gabarit — « Chapitre 4 — Description
du service » — avec le titre du site. La ligne du profil dit
« Confidentialité », l'écran « Politique de confidentialité » (le titre de la
page du site). L'aperçu d'une carte repliée est **tout le texte courant du
chapitre** d'un seul tenant, sans les intertitres : le premier paragraphe du
chapitre 4 des CGU tient en deux lignes et finit sur deux-points, une carte qui
ne montrerait que ça aurait l'air vide.

**États** — nominal seulement : le contenu est embarqué, il n'y a ni vide, ni
chargement, ni erreur.

**Contrat back-end** — aucun. Même parti pris que la FAQ : le texte arrive par
une constante, le brancher sur une route fera quatre lignes le jour où les
documents seront servis.

**Assets** — aucun nouveau : `IconChevron` tourné.

**Accessibilité** — chaque carte dépliable est un bouton portant son titre, la
valeur « Dépliée / Repliée » et l'indice « Déplier / Replier » ; une carte qui
ne se déplie pas perd le trait de bouton ; le chevron et les puces sont masqués
à VoiceOver ; les intertitres portent le trait d'en-tête ; l'adresse est un
lien `mailto:`, la CNIL un lien `https:`. Vérifié à AX3 : le chevron reste en
face de la première ligne du titre, rien ne se rogne, la carte grandit.

`LegalDocumentTests` garde le contenu **des deux documents** (tests
paramétrés) : numérotation 1 à n, identifiants `<document>.slug` uniques, un
aperçu par chapitre, l'adresse toujours liée, apostrophe typographique partout,
demi-gras refermés.

### 23.2 À trancher

| # | Sujet | Écran / parcours |
|---|---|---|
| T147 | **Les documents légaux vouvoient**, seule exception à R9. C'est un contrat, pas une phrase de l'interface : le texte du site est celui qui engage, et il est recopié tel quel. Si Clara et Hugo veulent tutoyer, c'est le site qui change d'abord, et l'app suit | Lot 8 — Les documents légaux |
| T148 | **« Découvrir notre FAQ » est à l'encre**, là où le gabarit le dessine en vert. C'est `BrandButton` en style `link`, petite taille : le design system n'a pas de lien vert, et un lien d'une autre couleur serait un second bouton. À dessiner dans Figma, ou à valider tel quel | Lot 8 — Les documents légaux |
| T151 | **« En continuant, tu acceptes nos Conditions d'utilisation »** sur l'écran d'entrée n'ouvre pas la page : elle est derrière la session (`HomeRoute`), et l'écran d'entrée a sa propre pile. À relier si on veut lire les CGU avant de créer un compte | Lot 8 — Les documents légaux |
| T152 | **Le chapitre 3 de la politique de confidentialité annonce une liste qui ne suit pas** — « transmises aux prestataires techniques suivants … : » puis rien. Le site la porte dans un tableau qui n'a pas été fourni. Recopié tel quel (R8) ; **à compléter** avec la liste des prestataires (Webflow, Google Analytics, Hotjar, Meta, WhatsApp ?) | Lot 8 — Les documents légaux |
| T153 | **Le chapitre 9 (« Mineurs ») se termine par un point-virgule** au lieu d'un point. Recopié tel quel (R8), à corriger sur le site | Lot 8 — Les documents légaux |
| T154 | **La politique de cookies n'existe pas dans l'app**, et les deux documents y renvoient (« disponible sur ce site »). Un troisième `LegalDocument` suffira le jour où le texte est fourni | Lot 8 — Les documents légaux |

---

## 27. Réponses du 17/09/2026 — les tickets tranchés, les retours de Clara, l'UX de Hugo

Hugo a répondu ticket par ticket au fichier, Clara a relu l'app de bout en
bout, et Hugo a ajouté dix changements d'UX. **Tout ce qui est réglé a quitté
le fichier** : les lignes de tickets tranchées ou livrées sont parties, et
celles qui restent sont ouvertes pour de vrai. À partir de ce lot, chaque
ticket dit **sur quel écran ou quel parcours** il se joue, dans une troisième
colonne — les tables existantes l'ont reçue aussi.

> ⚠️ **Le quota du MCP Figma était épuisé** au premier appel (plan Starter).
> Ce qui demandait une maquette qu'on n'a pas encore lue — les recommandations
> de message du chat, l'icône « export data », le carrousel des thèmes — est
> écrit en ticket, pas inventé.

### 27.1 Ce que les réponses de Hugo ont changé

| Ticket | Réponse | Ce qui a été fait | Écran / parcours |
|---|---|---|---|
| T49 | corrige dans l'app | « pourrais-tu », « tout le long » (`ChatCopy.opening`) | Conversation |
| T51 | « enregistrer » | `ChatCopy.record` = « Enregistrer » | Conversation |
| T54 | Gloria Hallelujah pour les titres des fiches | `MemoBookFont.handwriting` sur le titre de la fiche de retranscription — la police était déjà dans le bundle | Conversation |
| T59 | bleu #4088C6, un rond, l'icône en blanc | `MemoBookColor.send` = `blueText` ; `ChatSendingBar.sendGlyph` : rond plein de 2 rem, avion blanc, cible 2.75 rem — les deux boutons d'envoi | Conversation |
| T62 | marges de 16 partout | vérifié : tous les écrans posent `screenMargin` ; les seuls 20 restants sont l'alignement d'un message d'erreur sous son champ | Partout |
| T63 | uniformise | un seul cadrage du M, celui du design system ; le quart de tour de la maquette du paywall est abandonné | Paywall |
| T66, T84, T91 | tutoiement, « 1ère » partout | le tutoiement était déjà là depuis le 16/09 ; « 1re » devient **« 1ère »** partout — onglets, ligne « Couvertures (1ère & 4e) », pastille, « ma 1ère étape » | Couvertures, personnalisations, cagnotte |
| T67 | coquilles corrigées dans Figma | « grâce à ton abonnement », « Prévisualisation PDF », « Définis maintenant » | Cagnotte, réglages du voyage, aperçu PDF |
| T68 | `PDF.svg` et `View.svg` | `IconPDF` sur « Partager le fichier pdf », `IconView` sur « Partager le lien de prévisualisation » | Partager ton MemoBook |
| T70 | les deux boutons à 48 | `BrandButton.Size.medium` : le libellé de 16 du `small`, la hauteur de 48 (`MemoBookSpacing.mediumControlHeight`) | Ma cagnotte |
| T74 | les trois liens mènent quelque part | « Voir un aperçu » et « En savoir plus » y menaient déjà ; **« Voir ma cagnotte » ouvre la cagnotte** (`SubscriptionSheet.onSeeWallet`, la feuille se referme d'abord) | Mon abonnement |
| T76 | genre déduit du prénom, modifiable sous l'adresse postale | colonne `accounts.gender` (nulle tant qu'on n'a rien dit), `services/genderInference.ts` devine sur le prénom, `PATCH /v1/profile { gender }`, ligne « Genre » sous « Adresse postale », `GenderSheet` (femme, homme, je ne préfère pas répondre). « Abonnée » / « Abonné » s'accorde sur la feuille et sur la pastille | Profil, Mon abonnement |
| T77 (§ 16) | pas compris | c'était une note pour le document : le § 2.3 disait 4 pt pour une barre de progression que l'app dessine à 6. Le § 2.3 est corrigé, le ticket est clos | Cagnotte, accueil |
| T90 | un crayon sur le texte de dos, en haut à droite | `CoverPlate` pose `subtitleBadge` sur le texte de quatrième ; `CoverTextsView` le donne dès que le plat porte un texte | Couvertures — les textes |
| T92 | coquilles corrigées dans Figma | « tu ne trouves », « Écris à notre équipe », « les plus brefs délais par mail ou par WhatsApp » | Support et retours |
| T113 | tutoiement dans Figma | « En continuant, tu acceptes nos Conditions d'utilisation. » | Accueil — 1ère connexion |
| T118 | pas de polices embarquées | ticket réécrit : Hugo fournira peut-être un vectoriel du nom de chaque typographie | Typographies du carnet |
| T121 | le logo WhatsApp, en vert foncé | `assets/logos/whatsapp.svg` → `LogoWhatsApp` (`import-brand-logos.py`), teinté par `BrandButton` sur « Partager via WhatsApp ». La partie « Renvoyer » du ticket reste | Création — co-voyageurs, invitation |
| T122 | données communes, moins d'options à la création | `TripCreationStepContent.paces` = trois `NarrationPace` (tous les jours, tous les 2 jours, une fois par semaine) ; c'est la **clé** qui part en base, comme depuis les réglages | Création — notifications |
| T115, T124 | pas compris | réécrits dans leur table : la photo d'entrée est à réexporter plus grande ; les deux autocollants Apple et Google sont des bitmaps à réexporter en vectoriel | Accueil — 1ère connexion |
| T41, T42, T44, T53, T55, T56, T58, T60, T64, T69, T71, T72, T73, T75, T81, T82, T83, T93, T94, T95, T106, T117, T119, T120 | validés tels quels, ou réglés entre-temps | lignes retirées | — |

### 27.2 Ce que Clara a relevé, écran par écran

| Écran | Retour de Clara | Ce qui a été fait |
|---|---|---|
| Accueil | un voyage fini le 15 est encore « en cours » le 16 | `memos.stage` était figé à l'écriture. `services/tripStage.ts` **déduit l'état des dates à chaque lecture**, le dernier jour compris en entier ; la colonne n'est plus qu'un repli pour un voyage sans date, et le `PATCH` des dates la réécrit. Testé (`tripStage.test.ts`) |
| Accueil d'un voyage | le « + » des collaborateurs n'est pas cliquable | `TripIntent.inviteCompanions` : les réglages du voyage s'ouvrent **sur la feuille des co-voyageurs** (`TripSettingsView(opening: .companions)`, `HomeRoute.tripSettings(id:opening:)`) |
| Conversation | l'onde n'est pas centrée, le micro trop petit et mal placé | l'onde et le chrono passent sur **une ligne**, centrée sur le bouton et la signature ; le micro prend la taille d'une icône de barre et se pose en bas à gauche du disque |
| Conversation | l'icône d'aperçu doit être l'imprimante du voyage | `IconPrinter` en en-tête, comme sur l'accueil du voyage |
| Exemples de carnets | l'icône « filtre » n'est pas cliquable et perturbe | retirée ; « Tout » ouvre la ligne |
| Paywall | la barre d'avant se remplit encore un peu ; la 3e va plus vite ; tapotis « retour » inerte sur la 3e | les sauts des segments sont **instantanés** (plus d'animation) ; la 3e barre se remplit en six secondes comme les autres et reste pleine ; la moitié gauche de l'écran d'offre recule d'un écran — la zone vit **dans** la `ScrollView`, derrière les cartes, qui laissent passer le doigt sauf sur la pastille (T132, T135 clos) |
| Personnalisations | le titre « Décorations & stickers » passe à deux lignes dès deux stickers | `BrandRow` donne la priorité à l'intitulé : c'est la valeur qui s'abrège, jamais l'intitulé qui se coupe — pour toutes les lignes |
| Couvertures | la pastille « assortie » ne suit pas le devant | `CoverStyle.isMatched` (un drapeau du catalogue) disparaît ; `BookCovers.isMatched(_:on:)` compare composition et aplat au style **choisi** sur l'autre plat. Testé |
| Couvertures — 4e | « 2,3k » sur deux lignes | un chiffre tient sur une ligne et rapetisse s'il le faut (plat et feuille des chiffres) |
| Couvertures — textes | pas d'icône « clavier bas » sur le titre | `brandKeyboardDismissBar()` sur le champ du titre ; le texte l'avait déjà par `BrandTextBox` |
| Aperçu PDF | pas d'accès aux couvertures | un lien « Configurer mes couvertures » sous « Personnaliser mon carnet », toujours là — l'invitation sur la page ne s'affichait que tant qu'elles n'étaient pas choisies |
| Support et retours | retirer « Sujets courants » ; sous-titres en Sora Semibold 12 gris capitales | le chapeau part ; les titres de paquets prennent `sectionOverline` (Sora Semibold 12, `inkMuted`, capitales), le même dessin que « Nous contacter » |
| Profil | le chevron « Voyage en cours » doit mener au voyage | `ProfileIntent.openTrip(id:)` → l'accueil du voyage |
| Accueil — 1ère connexion | la carte doit bloquer en bas | `brandScrollWithoutBounce()` : l'`UIScrollView` de SwiftUI perd son élastique, la carte s'arrête une fois entière |
| Personnalisations — typographies | un paquet de typos plutôt qu'une par catégorie | déjà fait le 16/09 (`BookFontCombo`) |
| Personnalisations — chapeau | tutoiement | déjà fait le 16/09 |
| Config — contexte, co-voyageurs, 3 étapes offertes, boutons inertes sans étape, icônes trop petites, vocal qui arrive dans le chat, flèche des paramètres, icône de partage de l'aperçu, CTA des fondateurs, page après un social login | relevés avant le 14/09 | déjà faits (T96–T105) |
| Config — contexte de voyage | tous les thèmes, glissé horizontal, l'émoji du centre plus gros à 100 %, les autres à 60 %, noms longs coupés | l'étape est **retirée du parcours** ce même jour (Hugo, ci-dessous) ; le carrousel attend le nœud Figma — voir T163 |

### 27.3 Ce que Hugo a changé dans l'UX

| Écran | Demande | Ce qui a été fait |
|---|---|---|
| Accueil | glisser vers la droite ouvre le profil | un `DragGesture` sur l'accueil, franchement horizontal, parti de n'importe où ; le tiroir des cartes va dans l'autre sens |
| Accueil | glisser un voyage vers la gauche : supprimer (croix), partager (flèche), prévisualiser (imprimante) | `BrandSwipeDrawer` — **le** tiroir d'actions, extrait de la liste des co-voyageurs qui l'emploie aussi. Supprimer ouvre `DeleteTripSheet` (celle des réglages) et `HomeModel.deleteTrip` → `DELETE /v1/memos/:id`, puis recharge ; partager ouvre l'aperçu **sur sa feuille de partage** (`HomeRoute.bookPreview(memoId:sharing:)`) ; prévisualiser ouvre l'aperçu |
| Création d'un voyage | retirer les étapes Ratio et Thème, garder le code | `TripCreationStep.active` = nom, dates, notifications, co-voyageurs ; `next` / `previous` / `position` suivent cette liste, la frise compte quatre barres, le brouillon part avec les valeurs par défaut des deux étapes retirées |
| Création d'un voyage | feuilleter les étapes au doigt, dans les deux sens | glissé vers la gauche = « Valider » (seulement si l'étape le permet), vers la droite = la flèche |
| Accueil d'un voyage | l'imprimante du chat = celle du voyage ; « Accéder au chat » avec une bulle | `IconPrinter` en en-tête du chat ; `IconBubble` en fin de libellé du CTA |
| Support et retours | les trois dernières lignes ouvrent le formulaire, avec une explication plus courte | `SupportSheetRoute.contact(about:)` : les deux questions de « Nous contacter » ouvrent le formulaire sous leur propre titre, avec une phrase (`SupportCopy.Contact.brief(for:)`) ; « Écris à notre équipe » garde la sienne |
| Profil | le logo Apple ou Google, petit, après « E-mail », à la place de la phrase | `BrandRow.TitleIcon` (`LogoApple` / `LogoGoogle`, cerclés de bleu, 20 pt) ; VoiceOver garde la phrase |
| Accueil | « Commencer à enregistrer » plante sur son iPhone | **la permission d'abord, la feuille ensuite** : le premier appui demande l'accès au micro (et à la reconnaissance vocale) sans toucher au micro ; le second ouvre la feuille ; l'accès déjà accordé, le premier appui l'ouvre. Refusé, une boîte mène aux Réglages. T129 clos |
| Partout | retirer la pastille « Mis à jour » | `brandRefreshFlash` ne pose plus la pastille (le balayage reste, et VoiceOver reçoit l'annonce) ; `showsBadge:` la garde sous la main pour l'aperçu PDF |

### 27.4 Ce qui entre dans le code partagé

| Pièce | Ce qu'elle porte |
|---|---|
| `BrandSwipeDrawer`, `BrandSwipeAction` (`Design`) | **le** tiroir d'actions d'une carte : glissé vers la gauche, menu contextuel à l'appui long, rotor VoiceOver. L'accueil et la liste des co-voyageurs le partagent |
| `BrandButton.Size.medium`, `MemoBookSpacing.mediumControlHeight` | le libellé de 16 et les 48 pt de la maquette pour un bouton d'appoint qui compte |
| `BrandRow.TitleIcon` | un petit logo après l'intitulé d'une ligne, avec ce que VoiceOver en dit |
| `brandScrollWithoutBounce()` (`Design`) | retire l'élastique de la `ScrollView` qui porte la vue |
| `MemoBookColor.send` = `blueText` | le bouton d'envoi est du bleu de la palette, plus du bleu-violet du kit |
| `MemoBookFont.handwriting` | deux emplois désormais : le mot des fondateurs et le titre des fiches du chat |
| `Gender` (`Core`), `TravellerProfile.gender`, `ProfileEdit.gender` | femme, homme, je ne préfère pas répondre ; `agreed(_:)` accorde « Abonné(e) » |
| `BookCovers.isMatched(_:on:)`, `CoverStyle.matches(_:)` | la pastille « assortie » se calcule, elle ne se stocke plus |
| `TripCreationStep.active`, `next`, `previous`, `position` | le parcours de création, distinct de la liste des étapes que le code connaît |
| `LogoWhatsApp` | depuis `assets/logos/whatsapp.svg`, monochrome, à teinter |
| `services/tripStage.ts`, `services/genderInference.ts` (back-end) | l'état d'un voyage lu sur ses dates ; le genre deviné sur le prénom |

### 27.5 Contrat back-end

| Route / colonne | Ce qui change |
|---|---|
| T147 | **Les documents légaux vouvoient**, seule exception à R9. C'est un contrat, pas une phrase de l'interface : le texte du site est celui qui engage, et il est recopié tel quel. Si Clara et Hugo veulent tutoyer, c'est le site qui change d'abord, et l'app suit |
| T148 | **« Découvrir notre FAQ » est à l'encre**, là où le gabarit le dessine en vert. C'est `BrandButton` en style `link`, petite taille : le design system n'a pas de lien vert, et un lien d'une autre couleur serait un second bouton. À dessiner dans Figma, ou à valider tel quel |
| T151 | **« En continuant, vous acceptez nos Conditions d'utilisation »** sur l'écran d'entrée n'ouvre pas la page : elle est derrière la session (`HomeRoute`), et l'écran d'entrée a sa propre pile. À relier si on veut lire les CGU avant de créer un compte |
| T152 | **Le chapitre 3 de la politique de confidentialité annonce une liste qui ne suit pas** — « transmises aux prestataires techniques suivants … : » puis rien. Le site la porte dans un tableau qui n'a pas été fourni. Recopié tel quel (R8) ; **à compléter** avec la liste des prestataires (Webflow, Google Analytics, Hotjar, Meta, WhatsApp ?) |
| T153 | **Le chapitre 9 (« Mineurs ») se termine par un point-virgule** au lieu d'un point. Recopié tel quel (R8), à corriger sur le site |
| T154 | **La politique de cookies n'existe pas dans l'app**, et les deux documents y renvoient (« disponible sur ce site »). Un troisième `LegalDocument` suffira le jour où le texte est fourni |

## 24. Lot 5 — La feuille « Statistiques »

### 24.1 Statistiques

- **Maquette** : la capture fournie par Hugo le 17/09/2026 (une carte cerclée
  de vert, deux volets : « STATISTIQUES » et « VOYAGE EN COURS »). Pas de nœud
  Figma relevé — les tokens sont ceux de la carte de chiffres du profil (§10.1),
  dont cette feuille est la version dépliée.
- **Vues** : `MemoBookFeature/Profile/` — `StatisticsSheet`, `StatisticsModel`,
  `StatisticsFormatting` ; modèle `MemoBookCore/TravelStatistics.swift` ;
  jeu d'essai dans `ProfileFixtures`.
- **Rôle** : les chiffres du voyageur — tous ses voyages, puis celui en cours —
  **relevés par l'agent de rédaction** à chaque souvenir, et mis à jour sous les
  yeux pendant que le voyage se raconte.
- **Entrée / sortie** : la ligne « Statistiques » de la carte de chiffres du
  profil. **Réservée aux abonnés** : sans abonnement la ligne dit « Réservé aux
  abonnés », porte la pastille `LOCKED`, perd son chevron et ne répond pas au
  toucher (c'était déjà le cas ; la feuille ne fait que se brancher derrière).
  Retour au profil au glissé ou par le rond.

**Structure (en rem)**

| Élément | rem | Note |
|---|---|---|
| Carte | rayon 1.25, filet vert 1.5 pt | `largeCornerRadius`, `MemoBookColor.action` — la même coque que la carte de chiffres du profil |
| Marge intérieure d'un volet | 1 | `MemoBookSpacing.s` |
| Espacement surtitre → lignes | 0.75 | `snug` |
| Espacement entre deux lignes | 0.5 | `xs` |
| Anneau | 4.75, trait 0.4375 | `@ScaledMetric`, **plafonné à xxLarge** — voir Accessibilité |
| Surtitre d'un volet | `sectionOverline` (Sora 12, capitales, vert) | |
| Détail du volet (« 5 voyages », les dates) | `label` (14, vert) | |
| Intitulé d'une ligne | `body`, `inkMuted` | |
| Valeur d'une ligne | `body`, `ink` | roule vers sa nouvelle valeur (`contentTransition(.numericText())`) |
| Chiffre d'un anneau | `figure` (Sora 24) | |
| Ligne « en cours de lecture » | `caption`, `inkMuted` + `ProgressView` petit | n'existe que pendant |

**Les deux volets se replient**, chacun par sa ligne de tête (toute la ligne se
touche, pas seulement le chevron), et repartent ouverts à chaque ouverture de
la feuille. Le chevron est `IconChevron` tourné comme dans
`BrandDisclosureCard`. La feuille suit la hauteur de son contenu, volets
repliés ou non.

**Ce que chaque ligne écrit** — tout est accordé par `counted(_:_:_:)`, et zéro
prend le singulier :

| Ligne | Exemple | Règle |
|---|---|---|
| Étapes | « 6 pays, 8 régions, 13 villes » | une part à zéro s'omet ; tout à zéro : « Pas encore relevé » |
| Rencontres | « 406 personnes » | zéro : « Pas encore relevé » |
| Km parcourus | « 2 280 km » | formateur du système, unité espacée (§ 6 de l'agent) |
| Enregistrements | « 300 vocaux » | les vocaux seulement, pas les messages |
| Transports | « 1 avion, 2 trains, scooter » | le nombre ne s'écrit que s'il a été relevé ; « à pied » ne se compte jamais ; plus fréquents d'abord |
| Anneau 1 | « 9 % du voyage » | jours ayant au moins un souvenir rédigé / jours du voyage |
| Anneau 2 | « 2 pays » | pays du voyage / pays du compte |
| Phrase | « Tu es actuellement à Rome. » | la dernière ville où un souvenir situe le voyageur, sinon la destination |
| Sous-phrase | « 9 % écrit (2 jours validés sur 21) » | |

**Les chiffres bougent sous les yeux, et c'est le point.** Le serveur dit
combien de souvenirs attendent encore leur relevé (`pendingDetections`) ; tant
qu'il y en a, `StatisticsModel.watch()` relit la route toutes les **3 s**, et
s'arrête dès que la file est vide — ou après **40 relectures sans changement**
(un job perdu ne doit pas faire frapper le serveur toute la soirée). La veille
est une `.task(id:)` sur le compteur de livraisons de la file des vocaux : un
vocal qui part relance la lecture tout de suite. Un changement de chiffres joue
`brandRefreshFlash` ; une relecture identique ne joue rien (comparée sur les
chiffres, jamais sur l'horodatage). Aucune connexion ouverte : c'est un choix,
argumenté dans `StatisticsModel`.

**La feuille s'ouvre sur ce qu'on avait** : case `statistics` de `ContentCache`,
même contrat que le profil. Barres d'attente (`BrandSkeleton`) à la place des
valeurs tant que rien n'est arrivé ; `ErrorBanner` en ligne sous la carte avec
« Réessayer ».

**Contrat back-end** — `GET /v1/profile/statistics`, servi à tout compte (c'est
l'app qui tient la ligne sous clé). Forme : `TravelStatistics` au champ près —
`tripCount`, `overall {countries, regions, cities, encounters,
distanceKilometres}`, `currentTrip {id, startDate, endDate, currentPlace,
dayCount, validatedDays, figures, recordings, transports[{kind, count|null}]}`,
`pendingDetections`, `updatedAt`. **Rien n'est stocké** : chaque souvenir rédigé
porte le relevé de l'agent (`entries.insights`, migration
`20260917100000_releves_de_la_redaction`), et `services/travelStatistics.ts`
additionne à la lecture — ce que le voyage déclare (destination, étapes,
distance de la fiche) sert de plancher, ce que la rédaction relève prime. Le
contrat du relevé est dans `agents/agent-transcription.md` § 6 (« Le relevé de
l'étape »), chargé tel quel comme prompt système ; `FakeRedactor` en produit un
minimal (la ville du `placeLabel`) pour que la feuille vive en développement.

**Accessibilité** — chaque volet est un bouton portant son titre, son détail et
« déplié / replié », avec le trait d'en-tête ; chaque ligne est un seul
élément ; chaque anneau annonce son intitulé et sa valeur. Vérifié à AX3 : les
anneaux passent **au-dessus** du texte, côte à côte, et **cessent de grandir à
xxLarge** — à AX3 ils feraient 240 pt chacun et emmenaient toute la feuille
hors de l'écran ; l'intitulé d'une ligne passe au-dessus de sa valeur ; le
détail d'un volet passe sous son surtitre et s'enroule. `reduceMotion` fige
l'arc au lieu de le dessiner.

`TravelStatisticsTests` (Core) garde la part écrite, l'accord des transports, la
comparaison hors horodatage et le décodage tolérant (transport inconnu sauté,
serveur ancien qui rend `{}`). `travelStatistics.test.ts` et `screens.test.ts`
gardent l'addition côté serveur.

### 24.2 À trancher

| # | Sujet |
|---|---|
| T155 | **La maquette vouvoie** (« Vous êtes actuellement à Rome. ») ; la feuille tutoie (R9), comme le reste du profil depuis §22.2 |
| T156 | **« 2.280km » devient « 2 280 km »**, et « 9% » devient « 9 % » : formateur du système et espace de l'unité, même parti pris que les euros de la cagnotte. À valider ou à redessiner |
| T157 | **Le second anneau n'a pas de définition dans la maquette** (« 2 pays »). Il montre la part des pays du compte que ce voyage couvre ; si Clara y voyait autre chose, seule `countryFraction(of:)` change |
| T158 | **« Pas encore relevé »** est inventé pour une ligne à zéro — la maquette ne montre que des chiffres pleins. Un tiret se lisait comme une panne |
| T159 | **Les souvenirs rédigés avant la migration n'ont pas de relevé** : ils comptent pour les jours validés, pas pour les lieux ni les rencontres. Une relance de la rédaction (`POST /v1/entries/:id/redaction`) les relit ; à décider si on la lance en masse |
| T160 | **Le jeu d'essai n'enfile pas sa rédaction** : ses souvenirs restent « en cours de lecture » (4 sur le compte de test), et la veille s'arrête d'elle-même au bout de deux minutes. Le seed pourrait enfiler les jobs `redact` |
| T161 | **Pas de simulateur SE sur le Mac de vérification** : contrôlé sur iPhone 17 (medium et AX3). Sur un écran court, la feuille défile — c'est `BrandSheet` qui plafonne |
| `accounts.gender` (`Gender?`, migration `20260917200000_genre_du_profil`) | nulle tant que la personne n'a rien dit ; `undisclosed` est un choix |
| `GET /v1/profile` → `gender` | ce que la personne a dit, sinon ce que son prénom laisse deviner (`effectiveGender`) |
| `PATCH /v1/profile { gender }` | `"female" \| "male" \| "undisclosed"`, jamais `null` |
| `GET /v1/home`, `GET /v1/profile`, `GET /v1/gallery` → `stage`, `currentTrip`, `resumableTripId` | **déduits des dates** à la lecture (`effectiveStage`) ; un voyage fini hier est « terminé » aujourd'hui sans qu'on le rouvre |
| `PATCH /v1/trips/:id/settings` (dates) | réécrit `memos.stage` pour que la colonne ne contredise pas les dates |

⚠️ La migration est à déployer **sur les deux schémas** (`public` et
`memobook_test`), et l'API sur Railway **ne se redéploie pas toute seule** à la
fusion : sans elle, le profil ne rend pas `gender` (l'app accorde alors au
masculin) et le voyage fini reste « en cours ».

### 27.6 À trancher, et ce qui attend quelque chose

| # | Sujet | Écran / parcours |
|---|---|---|
| T164 | **Les « Valider » des feuilles de personnalisation** semblent inutiles à Clara ; seule « Nombre de pages » n'en a pas, et c'est bien — mais la feuille ne devrait peut-être pas se refermer dès qu'on choisit. **À trancher avec Hugo et Paul** : sans bouton, la feuille se referme au choix (comme « Genre » du profil) ; avec, elle reste ouverte | Personnalisations du carnet |
| T167 | **« Voir une estimation » sur la 3e story** (Clara) : la pastille ouvre bien la feuille « Estimation » depuis le 15/09, sur les chiffres de la maquette (T127). Clara a peut-être vu la version d'avant ; à revérifier sur ce build. T80 reste ouvert jusqu'à ce que la pastille soit configurée pour de bon | Paywall |
| T168 | **Le tiroir des cartes de l'accueil n'a pas de maquette** — croix, flèche, imprimante cerclées, sur le modèle de la liste des co-voyageurs. À dessiner dans Figma, ou à valider tel quel | Accueil |
| T169 | **La feuille « Genre » n'a pas de maquette** — trois options sur le motif des feuilles de choix du profil, et la ligne « Genre » sous « Adresse postale ». À dessiner dans Figma, ou à valider telle quelle | Profil |
| T170 | **Le genre deviné est une liste de prénoms**, pas une science : environ six cents prénoms français, les mixtes (Camille, Dominique, Sacha…) restent sans réponse. Un prénom absent accorde au masculin par défaut (« Abonné ») — c'est la forme non marquée, pas une erreur, mais c'est à savoir | Profil |
| T171 | **Le glissé vers la droite de l'accueil** ouvre le profil de n'importe où sur l'écran. Il n'entre pas en conflit avec le tiroir des cartes (vers la gauche) ni avec le retour de la pile (l'accueil est le premier écran) ; s'il gêne le défilement des bandes horizontales de l'accueil, il faudra le limiter au bord | Accueil |
| T172 | **Trois migrations et l'API sont à déployer** — `genre_du_profil`, `photo_de_profil` et `rythme_du_recit_en_cles`, voir § 27.5, § 27.8 et § 27.11. Tant que l'API sert le code d'avant, l'accueil montre encore « en cours » un voyage fini, et le profil ne connaît ni le genre ni la photo. Aucune variable à ajouter sur Railway : le domaine du service suffit aux adresses d'avatar et au lien de l'e-mail | Back-end |

### 27.7 Le lendemain — les assets déposés, et neuf détails

Hugo a déposé ce qui manquait (18/09/2026) et ajusté neuf points ; tout est
dans le même lot.

| Écran | Demande | Ce qui a été fait |
|---|---|---|
| Typographies du carnet | les noms des polices dessinés dans leur police, sans embarquer les familles | `assets/logos/Playfair.svg`, `Hansley.svg`, `Gloria Hallelujah.svg` → `WordmarkPlayfair`, `WordmarkHansley`, `WordmarkGloriaHallelujah` (`import-brand-logos.py`) ; `BookFontOption.wordmark`, et la carte d'un assortiment les pose en gabarit **à la hauteur d'une ligne de texte** (`@ScaledMetric` 14). Alegreya et Montserrat restent en General Sans (T118) |
| Accueil — carte de découverte | la nouvelle image, sans dégradé, et un léger bleu sur sa gauche pour que le texte puisse mordre dessus | `ShowcaseCarnets` remplacée ; **le dégradé est dessiné par l'app**, depuis les deux couches de la carte (crème puis bleu à 22 %), sur les 45 premiers pour cent de l'image — pas une couleur inventée. ⚠️ L'export fait **111 × 85 px**, trois fois moins que l'ancien (330 × 252) pour 124 pt d'affichage : net sur aucun écran — voir T173 |
| Accueil — voyage à venir | T37, l'illustration passeport + carnet ouvert | elle était déjà là : `assets/illustrations/Empty Trip Illustration.png` est `EmptyTripIllustration`, posée par `UpcomingTripInvite`. Ticket retiré |
| Profil — photo | toucher le rond ouvre « Prendre une photo / Choisir dans la galerie », et la chaîne base de données | **chaîne entière** : `accounts.avatarStorageKey` (migration `20260918100000_photo_de_profil`), `POST /v1/profile/avatar` (multipart, JPEG ou PNG, 5 Mo), l'objet dans le stockage sous `avatars/`, l'ancien retiré, et `GET /v1/avatars/:file` qui le sert **sans session** — `AsyncImage` n'envoie pas d'en-tête. L'adresse se calcule à la lecture (`services/avatars.ts`, `API_PUBLIC_BASE_URL`). Côté app : `PhotoFlow` (l'ancien `ChatPhotoFlow`, sorti du chat), le rond du profil devient un bouton avec un petit crayon, l'image est réduite à 512 px avant de partir, `ProfileModel.setAvatar`. Testé côté serveur, vu en simulateur |
| Profil | l'icône `Export data.svg` | `IconExportData` sur « Exporter mes données » (T162 clos) |
| Conversation — propositions | le bon type de bulle, un émoji devant chaque proposition (nœud `3520:35958`) | les puces sont des **capsules** blanches, et **chaque** proposition porte son émoji (`ChatCopy.Suggest.*Symbol`) — T161 clos. Le nœud `3520:35930` est la bulle bleue du voyageur, déjà en place |
| Conversation — bannière « Ton Carnet prend forme » | posée sur le fil ; part vers le haut après 4 s avec un rebond ; revient dès 20 pt de remontée ; repart après 200 pt de remontée ou 20 pt de descente | la bannière quitte la pile des messages et devient un **calque sous l'en-tête** (`overlay`, hauteur de l'en-tête mesurée) ; `ChatView.trackScroll` cumule le défilement dans chaque sens sur un `GeometryReader` (iOS 17, pas d'`onScrollGeometryChange`) ; ressort `bounce: 0.35`, fondu en Reduce Motion. Et **« Votre Carnet » devient « Ton Carnet »** (R9) |
| Contexte de voyage | le carrousel est très bien tel quel | T163 clos |
| Ma cagnotte | plus de valeur figée | T166 clos |
| Accueil — tiroir des cartes | les trois icônes arrivent en quinconce avec le glissé | `BrandSwipeDrawer` décale chaque icône d'une part de ce qu'il reste à découvrir, croissante de la première à la dernière (0,35 / 0,70 / 1,05), et les fait monter en opacité — un rapport, pas une animation : rien à couper quand on relâche |
| Partout — boîtes d'information | le beige trop foncé, plus doux, avec un léger effet de verre | `MemoBookColor.noticeBeige` (#E6D5C4, entre `Beige` et `Beige Darker`) à 70 % **sur un verre dépoli** (`ultraThinMaterial`), liseré blanc à 45 %. `Beige Darker` ne change pas ailleurs (séparateurs, scotch) — à trancher si le token lui-même doit s'éclaircir, voir T174 |
| Paramètres du voyage — thème | seul « Autre » ouvre un champ ; les autres n'ont que « Valider » | `TripThemeSheet` : le champ n'existe que derrière « Autre » (ou un thème libre déjà enregistré, que la rangée ne connaît pas) ; un thème de la rangée se valide tel quel |

### 27.8 Contrat back-end (suite)

| Route / colonne | Ce qui change |
|---|---|
| `accounts.avatarStorageKey` (migration `20260918100000_photo_de_profil`) | la clé de la photo envoyée ; `avatarUrl` reste pour celle d'un fournisseur |
| `POST /v1/profile/avatar` | multipart, champ `file` en `image/jpeg` ou `image/png`, 5 Mo ; renvoie le profil relu |
| `GET /v1/avatars/:file` | **sans session**, `Cache-Control` long, 404 hors `avatars/<uuid>.(jpg\|png)` |
| `avatarUrl` (profil, accueil, co-voyageurs, propriétaire) | `avatarUrlOf` : la photo envoyée d'abord, sinon celle du fournisseur |
| `API_PUBLIC_BASE_URL` (env) | la racine des adresses d'avatar. Vide, c'est **`RAILWAY_PUBLIC_DOMAIN`** — que Railway pose tout seul sur le service — qui sert ; puis `APP_LINK_BASE_URL` s'il est en `https://`, sinon `localhost:3000`. **Rien à poser sur Railway.** Le lien de l'e-mail « mot de passe oublié » suit la même règle : `APP_LINK_BASE_URL` n'y avait jamais été posé, et l'e-mail partait en `memobook://` |
| Suppression de compte | la photo part avec le compte (`services/deletion.ts`) |

### 27.9 À trancher (suite)

| # | Sujet | Écran / parcours |
|---|---|---|
| T173 | **La nouvelle image de la carte de découverte est trop petite** : 111 × 85 px pour un cadre de 124 pt — l'ancienne faisait 330 × 252. Elle s'affiche floue sur tous les écrans. Il faut le même export en **au moins 372 × 285 px** (3×), déposé au même chemin ; le script ne change pas | Accueil |
| T174 | **`Beige Darker` lui-même doit-il s'éclaircir ?** Les boîtes d'information ont leur propre beige doux depuis le 18/09 ; les séparateurs, le scotch des cartes et le filet des boutons Apple/Google gardent `#CFBBAA`. Si c'est le token qui doit changer, c'est une ligne dans `Tokens.swift` — et la variable Figma avec | Partout |
| T175 | **La bannière du chat ne sait pas qu'un message vient d'arriver** : un nouveau message en bas fait bouger le haut du contenu comme un défilement vers le bas, et la referme. C'est acceptable — on lit ce qui arrive —, mais c'est un effet de bord, pas un choix | Conversation |

### 27.10 Le 18/09 au soir — huit détails, et une accolade

Hugo a fusionné les deux dernières PR et résolu les conflits à la main ; deux
fichiers en sont sortis blessés — `MemoBookAPIClient.swift` sans l'accolade qui
ferme `travelStatistics()` (d'où « Expected '}' in actor » et ses quatre-vingts
échos), `routes/profile.ts` sans l'`import {` de `services/avatars.js`. Les deux
sont réparés en premier ; le reste est ce qu'il a demandé.

| Écran | Demande | Ce qui a été fait |
|---|---|---|
| Nouveau carnet | « Importe depuis Polarsteps » plus effacée et grisée, pas beige | `NewNotebookOptionCard.comingSoon` : même fond crème que les deux autres, contour et titre au gris des contrôles inactifs (`disabledOutline`), contenu à 45 % — le logo s'efface avec, sans être teinté —, pastille intacte par-dessus |
| Typographies du carnet | retirer « Moderne », garder trois assortiments | `BookFontCombo.all = [travelJournal, editorial, handwritten]`. Un carnet réglé sur Montserrat garde ses quatre polices en base et se lit « Personnalisé » |
| Profil — Genre | la feuille se referme avant qu'on voie le choix ; et « Homme » / « Femme » revient à « Je ne préfère pas répondre » au bout de quelques secondes | Deux choses. **La feuille** coche sa propre valeur (`@State chosen`), attend 350 ms, puis se referme. **Le retour en arrière** venait de l'API : celle qui tourne sur Railway est celle d'avant le genre, elle répond au `PATCH` sans le champ, l'app le décode « ne préfère pas répondre » et remplace le profil par cette réponse. `ProfileModel.save` garde désormais le genre envoyé — le serveur n'a rien à corriger dessus. Disparaît de toute façon au déploiement (T172) |
| Lancement | plus lent depuis le cache ; retirer le squelette, garder le M puis le contenu qui monte | Trois causes, trois coupes. **Le M ne s'écrivait qu'après** `GET /v1/auth/me` : `RootView.restore` lance le tracé dès qu'un jeton est au trousseau, et vérifie dessous (`drawingFinished` retient le voile si le compte n'est pas encore là ; un 401 ou une panne lève le voile sur l'écran d'entrée). **L'accueil attendait le serveur** : `HomeView.isLoaded` se lève dès que `feed` ou `errorMessage` existe — le cache, en millisecondes —, le serveur suit et le flash dit s'il a changé quelque chose. **Le squelette** (`HomeSkeleton`, `HomeMetrics.greetingPlaceholder*`) est retiré. Vu en simulateur : M à ~1,6 s après le lancement du processus, accueil posé à ~2,7 s, dont ~1,1 s de `UILaunchScreen` |
| Paramètres du voyage — Nom de l'aventure | se corrige sur place, clavier direct, comme le téléphone du profil | `BrandRow(text:)` sur la ligne, `TripSettingsModel.setName` (vide refusé, espaces coupés), coche verte quatre secondes via `justSaved == .name`. L'intention `renameTrip`, que `RootView` ignorait, disparaît. `BrandRow` relit le modèle en sortant du champ, pour qu'un nom refusé reprenne sa valeur |
| Ma cagnotte | retirer « Inviter des proches » ; « Aucune contribution… » dans un cadre en pointillés, distinct de la FAQ dessous | `WalletEmptyCard` sans bouton, sur `brandDashedCard()` — le même cadre que l'accueil sans voyage. `WalletIntent.inviteFriends` et `BookCopy.Wallet.invite` disparaissent |
| Paramètres du voyage — Rythme du récit | la valeur choisie à la création n'était pas cochée dans la feuille | La création écrivait jusqu'au 17/09 le **libellé** de l'écran (« Tous les jours ») là où la feuille écrit la **clé** (`daily`) : dix voyages en base portaient un libellé, décodé `.unknown` et jamais coché. Trois verrous : `services/narrationPace.ts` ramène tout ce qui entre à la clé (les deux routes) ; la migration `20260918150000_rythme_du_recit_en_cles` a réécrit les dix rangées (appliquée sur `public` et `memobook_test`) ; `NarrationPace(storedValue:)` relit aussi les anciens libellés, au cas où l'app parle à l'API d'avant. Tests des deux côtés |

### 27.11 Contrat back-end (suite)

| Route / colonne | Ce qui change |
|---|---|
| `memos.narrationPace` (migration `20260918150000_rythme_du_recit_en_cles`) | les libellés d'écran deviennent des clés : `daily`, `every_two_days`, `every_three_days`, `weekly`, `custom`, `by_place` |
| `POST /v1/trips`, `PATCH /v1/trips/:id`, `PATCH /v1/trips/:id/settings` | `narrationPace` est normalisé à l'entrée — un libellé connu devient sa clé, un mot inconnu est gardé tel quel |

