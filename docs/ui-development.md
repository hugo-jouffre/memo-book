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
| Icône inline | 1.5 rem (24) | Figma : `keyboard_backspace` = 24 |
| Texte courant | 1 rem (16) | `Text Sizes/Text Regular` |
| Barre de progression | 0.25 rem (4) | Convention iOS (Figma dessine 7 → §7) |

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

### 7.2 Ce qui reste ouvert

Tant que Clara n'a pas arbitré, on applique R4 (les variables Figma gagnent) et on
n'harmonise rien de sa propre initiative.

| # | Sujet | État |
|---|---|---|
| T4 | **Modèle d'authentification.** Le *Sign Up* Figma montre email + mot de passe + confirmation + trois fournisseurs sociaux. Le README annonce « Sign in with Apple + email (magic link) ». Ce sont deux back-ends différents, et la règle App Store 4.8 impose Sign in with Apple dès qu'un login social tiers est proposé | 🔴 Bloquant pour le back-end du lot 1 |
| T6 | **Loader du Splash** dessiné à 7 de haut ; la convention iOS est 4. Barre custom assumée ou arrondi R2 ? | 🟢 Mineur |
| T7 | **Rôle de Lime.** `Scheme/Accent` vaut Lime `#E2F32B`, mais aucun des trois écrans ne l'emploie : c'est Green qui porte le CTA. Accent réservé à plus tard, ou accent qui n'a pas encore été appliqué ? | 🟠 À clarifier avant de poser les tokens |
| T8 | **Vouvoiement dans le Figma.** Les cartes 2 et 3 du *Welcome* vouvoient (« Parlez simplement », « Ajoutez vos photos ») alors que le reste de l'app tutoie. Par R9 c'est une coquille de maquette : à réécrire dans Figma, pas dans le code | 🟠 En attente de la copie corrigée |
| T9 | **États non maquettés.** Aucune maquette d'erreur, de chargement ni d'état vide sur le *Sign Up*, qui en a besoin (validation, email déjà pris, réseau) | 🟠 Bloquant pour finir l'écran |

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
- **Rôle** : couvrir le démarrage. Le M s'écrit d'un trait par-dessus le squelette de
  l'accueil, puis s'efface en fondu pendant que le contenu se pose.

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
squelette et signe masqués. **Reduce Motion** : pas de tracé, le signe est posé entier
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

| # | Sujet |
|---|---|
| T10 | **Mesures non confirmées.** Les couleurs viennent du nœud ; les espacements, rayons et tailles sont relevés sur l'image. À confirmer au premier `get_design_context` disponible |
| T11 | **Marge d'écran.** Le code est à 1.5 rem (24) et D2 tranche à 1 rem (16). Le changement touche *Welcome* et *Sign Up* : à faire en une fois, pas au fil des écrans |
| T12 | **Bleu de texte absent des variables.** La carte de découverte écrit son titre dans un bleu moyen qui n'est pas dans la palette — `Brand Colors/Blue` posé en texte sur son propre fond tombe à 1,3:1. Deux valeurs ont été **dérivées** en gardant la teinte du bleu de marque (209°) : `blueText` #4780B3 (5,1:1) et `blueTextSoft` #74A6D0 (3,1:1). À faire entrer dans les variables Figma sous le nom que choisira Clara |
| T13 | **Compteurs en anglais** dans la maquette (« 10 days »). Traduits (« 10 jours ») — R9 s'applique, mais à confirmer |
| T15 | **Pastille de comptage** : elle compte les voyages de la liste. La maquette montre « x8 » avec une seule carte visible — total ou nombre affiché ? |
| T16 | ~~Image du carnet d'exemple~~ **Réglé** : `assets/illustrations/Carnets Example Homepage.png`, embarquée sous `ShowcaseCarnets`. Elle est **livrée avec l'app** — c'est une image de marque, pas une donnée ; `Showcase.imageUrl` la remplacera le jour où une campagne veut la sienne. Source en 330 × 252, un peu juste pour du @3x : à réexporter en 2× si elle paraît molle |
| T17 | **`Green Lighter` sur le point « en ce moment »** : la couleur est bien celle du nœud, son emploi est une déduction. À confirmer |
| T18 | **Deux gris coexistent** — `Grays/Gray` sur les écrans du lot 1, `Grey Typo` sur l'accueil. Voulu, ou l'un doit-il remplacer l'autre partout ? |

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

| # | Sujet |
|---|---|
| T19 | **Copie des trois états ajoutés.** « Hors ligne » et « vocaux conservés » viennent de Hugo ; « envoi en cours », « vocal arrivé » et les singuliers sont écrits ici. À relire par Clara |
| T20 | **Le beige de la boîte** n'a pas de variable dédiée : on emploie `Beige Darker`, prévu pour « les séparateurs et les aplats discrets ». À confirmer, ou à nommer |

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
| Marge d'écran | 1.5 | `screenMargin`, comme l'accueil (D2 dit 1 — voir T11) |
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

- Titre : « Profile »
- Groupe 1 : « E-mail » · « Téléphone » · « Adresse postale » ·
  « Newsletter mensuelle MemoBook »
- Groupe 2 : « Ma cagnotte » · « Mon abonnement » · « Suivi des commandes » ·
  « Confidentialité »
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
> ⚠️ **« Confidentialité » apparaît deux fois**, dans le groupe 2 et dans le
> groupe 4. Implémenté tel quel (R3) — T18.

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

**Ce qui est délibérément inerte** — « Ma cagnotte », les deux
« Confidentialité », « Conditions d’utilisation », « En savoir plus »,
« Exporter mes données » et « Supprimer mon compte » gardent leur chevron parce
que la maquette le montre, et ne mènent nulle part parce qu'aucun écran n'est
dessiné derrière. C'est le même parti pris que les intentions non routées de
l'accueil, et il se voit en **un seul endroit** (`ProfileView.notYetRouted`).

**À trancher**

| # | Sujet |
|---|---|
| T16 | **Mesures non confirmées.** Aucun appel MCP n'a abouti : tout est relevé sur les captures. À confirmer au premier `get_design_context` disponible — au minimum le rayon des groupes, la taille du titre (24 supposé), la présence ou non d'un filet autour des cartes blanches (implémenté avec, par cohérence avec `homeCard()`), et la teinte de l'icône « Exporter mes données » (implémentée en `warning`) |
| T17 | **Quatre coquilles de copie** : « Ajoutr », « a » pour « à », « permets » pour « permet », et le vouvoiement de la carte des connecteurs (R9). Plus « Profile » pour « Profil » |
| T18 | **« Confidentialité » en double**, groupes 2 et 4. Doublon, ou deux destinations différentes ? |
| T19 | **Couleur de la sélection.** `Tokens.swift` réserve le vert d'action à la sélection ; la maquette du mode de paiement sélectionne en **bleu**. Implémenté en bleu (R3) |
| T20 | **Format du montant.** La maquette écrit « 67,88€ » collé ; on passe par le formateur du système, qui écrit « 67,88 € » en français et respecte la région d'un lecteur étranger. Écart assumé |
| T21 | **Bouton « Ajouter une carte ».** La maquette écarte le libellé et le « + » aux deux extrémités du bouton ; `BrandButton` les groupe au centre. Faut-il un axe « contenu écarté » sur le composant, ou le dessin groupé convient-il ? |
| T22 | **États non maquettés** : compte sans adresse, sans carte, sans commande ; erreur de chargement. Écrits ici, à valider |
| T23 | **Suppression de compte** : obligatoire (App Store 5.1.1), aucune maquette, aucune confirmation dessinée. À maquetter avant la soumission |
| T24 | **Le crayon des lignes modifiables** n'est pas dans la maquette. Sans lui, rien ne dit qu'une ligne se corrige ; avec lui, trois crayons apparaissent sur le premier groupe. À arbitrer |
| T26 | **Rayon des coins de l'écran** déduit d'une table de formats (``DeviceScreen``), aucune API publique ne le donnant. À relire à chaque nouveau format d'iPhone |
| T27 | **Le libellé « Gérée par ton compte Apple »** n'est pas maquetté. Il explique pourquoi l'adresse ne s'ouvre pas ; sans lui on bute dessus sans comprendre |
| T28 | **`signInProvider` n'existe pas encore côté back-end.** L'écran le lit sur le profil, le jeu d'essai le fournit ; il faudra que `GET /v1/me/profile` le renvoie, sans quoi une adresse Apple restera modifiable |
| T27 | ~~**L'icône « clavier bas »**~~ — close le 08/09/2026 : `IconKeyboardDown` est livrée, le double chevron provisoire est retiré |

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

| # | Sujet |
|---|---|
| T29 | ✅ **Tranché (D7)** — le E sans accent et les compteurs en français sont validés. Restent les mesures relevées sur une capture, faute de nœud Figma |
| T30 | **L'intention du filtre « Étapes »** : filtrer la liste sur une étape, ou sauter à celle-ci ? Implémenté en filtre, par symétrie avec les deux autres |
| T31 | ✅ **Tranché (D8)** — le premier groupe est celui des **collaborateurs**, qui ajoutent des étapes ; le second, les visages croisés en chemin, passe en v2 et est retiré |
| T32 | **Icônes manquantes** au jeu de marque : le drapeau, la valise et l'itinéraire des trois filtres restent sur des symboles système, comme le calendrier et le tracé de l'accueil |
| T33 | **La carte d'étape** est plus sombre que le crème sur la maquette ; elle emploie ici la carte blanche de l'app (`homeCard()`), pour rester cohérente avec l'accueil et le profil |

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

| # | Sujet |
|---|---|
| T34 | ✅ **Tranché (D9)** — coquille confirmée, corrigée dans le code, à reprendre dans Figma |
| T35 | ✅ **Tranché (D10)** — « Ton voyage » pour un seul, « Tes voyages » dès le deuxième |
| T36 | **La pastille « ×1 »** est lime sur une maquette et bleue à contour sur une autre. Implémentée en lime, comme le compteur existant |
| T37 | 🟠 **Asset attendu** — Hugo fournira l'illustration (passeport + carnet ouvert). Le livre du *Welcome* tient la place d'ici là |
| T38 | ✅ **Tranché (D11)** — dès que les dates le disent en cours, il est en cours, même sans souvenir : c'est là qu'il faut inciter à raconter la première étape |

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

| # | Sujet |
|---|---|
| T66 | ✅ **Tranché (D12)** — les neuf fautes et les deux formes d'apostrophe sont corrigées dans le code. À reprendre dans Figma |
| T67 | **Le rayon de la pastille.** La maquette dessine 6 ; `BrandTagPill` est une capsule pour tous ses tons. Un quatrième rayon rouvrirait le problème que ce composant a été écrit pour fermer — implémenté en capsule |
| T68 | ✅ **Tranché (D13)** — le lime **peut** porter un fond de bouton, à une condition qui n'est pas négociable : le libellé et le filet sont alors verts, jamais l'encre. `Tokens.swift` porte désormais la règle, et `BrandButton.accent` comme `BrandTagPill.accentOutlined` l'appliquent |
| T69 | **Les cartes d'options divergent d'un écran à l'autre.** Rayon 8 / padding 14 / gouttière 12 ici, contre 16 / 8 / 8 sur la feuille du moyen de paiement (§10.1), pour le même motif. `BrandOptionGroup` est réemployé tel quel ; à harmoniser dans Figma |
| T70 | ✅ **Tranché (D14)** — on garde le rond de fermeture existant, partout. `BrandSheet` n'est pas touché, et les cinq nouvelles feuilles emploient le même que les six du lot Profil. L'écart avec la maquette (× simple contre × cerclé) est à reprendre dans Figma |
| T71 | **Le voyage n'est pas rattachable à un abonnement** côté base. Sans lui, trois phrases sur cinq feuilles perdent leur donnée et se replient sur une formulation vague. À trancher avec le modèle de données avant de brancher StoreKit |
| T72 | **La raison de départ n'a pas de compteur.** Les quatre réponses sont modélisées côté app et jetées à l'envoi. Où doivent-elles atterrir ? |
| T73 | **Aucune raison n'est pré-cochée**, alors que la maquette montre « C'est un peu cher » sélectionnée. Lu comme la démonstration d'un état, pas comme une réponse par défaut : en pré-cocher une fausserait le compteur |
| T74 | **« Voir un aperçu de ton carnet → », « En savoir plus » et « Voir ma cagnotte » ne mènent nulle part** — aucun écran n'est dessiné derrière. Même parti pris que les intentions non routées du profil |
| T75 | ✅ **Tranché (D15)** — résiliation immédiate, dès maintenant. ⚠️ **StoreKit s'y opposera** : voir §13.2 |
| T76 | **« Abonné » ou « Abonnée » ?** La feuille écrit « Abonnée » (la maquette montre un compte féminin) ; la pastille du profil, elle, s'en tient à la forme non marquée parce que l'app ne sait pas à qui elle s'adresse. Les deux se contredisent à l'écran. Forme non marquée, doublet (« Abonné·e »), ou donnée de genre au compte ? |
| T77 | **Le profil ne connaît pas le quota.** `GET /v1/profile` ne rend pas `offeredSteps` / `remainingSteps`, que seul l'accueil reçoit : le profil ne sait donc pas distinguer un compte neuf d'un compte épuisé, et leur montre la même invitation. Faut-il que le profil porte le quota, ou lui suffit-il de savoir qu'il n'y a pas d'abonnement ? |

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

| # | Sujet |
|---|---|
| T49 | **Deux coquilles dans la bulle d'ouverture** : « pourrais tu » sans trait d'union, et « tous le long » pour « tout le long ». Recopiées telles quelles (R8) |
| T50 | ✅ **Tranché (D9)** — l'accueil tutoie : « Comment souhaites-tu commencer aujourd'hui ? ». R9 ne souffre pas d'exception, et la phrase se contredisait elle-même. À reprendre dans Figma |
| T51 | **« Record » est en anglais** au milieu d'une app française. Recopié tel quel |
| T52 | ✅ **Tranché (D10)** — la ville est **entrée dans le modèle** : `Destination.city` côté app, `memos.destinationCity` en base (migration `20260910120000_ville_du_voyage`), sérialisée par `serializeTrip`, et posée sur chaque voyage du jeu d'essai. L'accueil écrit donc « Nouveau voyage à Rome ! » comme la maquette. Nulle pour un voyage sans ville — un tour du monde —, où la phrase se replie |
| T53 | **Seize icônes Lucide** remplacent des dessins que le jeu de marque n'a pas. Lesquelles Clara veut-elle dessiner, et lesquelles restent empruntées ? |
| T54 | **La police manuscrite manque.** « Retranscription du contexte » est en Gloria Hallelujah dans la maquette ; elle n'est pas dans le bundle et doit passer par `make-brand-fonts.py`. Rendu en surtitre General Sans vert en attendant |
| T55 | **La pastille « Aperçu en direct » est en 10 pt** dans la maquette. L'app n'est jamais descendue sous 12 et emploie `overline` ici |
| T56 | **Le blanc des bulles.** La maquette dit `Neutral/100` (#FFFFFF), l'app pose son blanc crème `surface` (#FFFCF8). Écart invisible sur le fond crème, et deux blancs presque identiques coûtent plus cher que lui |
| T57 | ✅ **Accepté en l'état (D11)** — on garde le repli tant que la transcription n'est pas branchée. **Le trio de validation suit une fiche qui porte du vrai texte.** Tant que la transcription n'est pas branchée, une fiche sans récit propose « Je te le réécris ici / Je réenregistre / Plus tard ». En debug, une petite banque déterministe remplit la fiche et la marque `isSimulated` ; en release, elle reste vide — une fiche qui prétend restituer un vocal que personne n'a écouté est un fait inventé |
| T58 | **Une puce s'affiche en bulle bleue dans le fil**, comme la maquette le montre (frame 4). Est-ce voulu pour « J'aimerais faire des modifications à la main », qui se lit alors comme une phrase adressée à MEMO ? |
| T59 | **Le bleu du bouton d'envoi** (`chat/toolbar/input-btn-active`, #5D6CF5) n'est pas dans la palette de marque : c'est un bleu-violet emprunté au kit de messagerie. Gardé parce qu'un envoi est un geste de système, pas une action de marque — le vert sert déjà à « c'est ici qu'on appuie » partout ailleurs. À faire entrer dans les variables, ou à remplacer |
| T60 | **La bulle de photos n'est pas dessinée.** La maquette propose l'ajout de photos (une puce, un bouton) sans montrer ce que ça produit dans le fil. Écrite ici — une grande vignette seule, une grille de deux colonnes sinon, `+n` au-delà de quatre — pour que le bouton mène quelque part. À faire dessiner |
| T61 | ✅ **Réglé** — la grande feuille d'enregistrement est dans `main` (e507931) : « Commencer à enregistrer » la rouvre depuis l'accueil, et la conversation se rejoint par une étape du voyage. `BrandWaveform` porte les deux frises — celle de la feuille (`size: .sheet`) et celle de la barre du chat (`size: .bar`) — et le même rendu d'un vocal terminé |

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
| `Modifying transcription` | ``.writing`` avec un long brouillon : le champ s'étire tout seul, il n'y avait pas de cinquième disposition à écrire |
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

| # | Sujet |
|---|---|
| T65 | ✅ **Réglé** — le hors-ligne du bac à sable coupe vraiment le réseau depuis la fusion de `proprietaire-unique-et-secrets` : le vocal part sur le disque (`PendingRecordingStore`) et la file (`RecordingOutbox`) le renvoie au retour. Le drapeau provisoire `SandboxNetwork`, qui ne faisait qu'échouer le chargement, a été retiré |
| T62 | **La marge du paywall est 16**, là où le reste de l'app marge à `screenMargin` (24). Deuxième écran à s'en écarter après ceux de D2 — à raccrocher à T11 |
| T63 | **Le M de fond** : cadrage du design system contre quart de tour de la maquette du paywall. Uniformiser le cadrage, ou ouvrir un axe de rotation sur `BrandMarkBackdrop` ? |
| T64 | **Durée d'un écran de story : 6 s**, choisie ici — la maquette ne la donne pas (seul le tracé du trait est animé dans Figma). À valider à l'usage |
| T39 | ✅ **Tranché** — l'icône de filtre est **décorative**, et rien d'autre. Hugo, 09/09/2026. Elle ouvre la ligne et défile avec elle ; elle ne se laisse pas toucher et reste masquée à VoiceOver |
| T40 | ✅ **Tranché** — le rayon 1.5 rem (24) reste tel quel. Hugo, 09/09/2026 : « c'est ok pour l'instant ». Cinquième valeur de rayon de l'app, à reprendre le jour où Clara passe sur l'échelle |
| T41 | **Les vignettes ne s'ouvrent pas** — confirmé par Hugo, c'est normal pour l'instant. Il n'y a donc ni bouton, ni flèche, ni retour au doigt : rien ne promet un geste qui ne se passerait pas |
| T42 | **Les pictogrammes de catégorie sont ceux de Lucide**, tracés, là où le jeu de marque est plein. L'écart se voit dans la barre. À reprendre le jour où Clara dessine la série |
| T43 | **Aucune photo de couverture** ne remonte encore : toutes les vignettes portent l'aplat dégradé. Les formats de la mosaïque sont donc à revoir sur de vraies images |
| T44 | **Un glissé vertical parti de la bande de filtres fait défiler la page.** C'est le verrou directionnel d'iOS — un glissé franchement horizontal ne bouge que les pastilles, un glissé vertical prend la page, exactement comme les rayons de l'App Store. Le rendre horizontal seul veut dire refuser le défilement depuis cette bande de 2.75 rem, ce qui demande de passer par UIKit. À trancher : est-ce gênant, ou est-ce l'attendu ? |

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
| Marge d'écran | 16 | `screenMargin` (1.5 rem) — règle du § 2.3 |
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

⚠️ **Seuls les trois extras s'enregistrent.** Les onze autres lignes montrent
leur valeur et ne mènent nulle part : leurs écrans de choix ne sont pas
dessinés, et on ne les invente pas (R3).

### 16.9 La feuille « Prévisualisation »

`3348:11671` → `BookPreview/BookPreviewSheet.swift`

Ce qu'ouvrent les deux pastilles « Voir un aperçu » du parcours d'abonnement.
Une **feuille** et non un écran poussé : quelqu'un à qui l'on propose un
abonnement veut voir ce qu'il achète, puis *revenir à l'offre*.

Elle réutilise les pièces de l'aperçu — ``BookPageStage``, ``BookSheetView``,
``BookPageStepper``, et la cascade de composition — plutôt que d'en redessiner
de plus petites : deux aperçus à tenir d'accord, et celui de la feuille
vieillirait le premier.

Deux formes, selon d'où elle vient. Depuis le **paywall**, c'est une feuille
posée par-dessus, et le minuteur des stories s'arrête pendant ce temps-là (voir
`PageTimer`). Depuis la **feuille d'abonnement**, c'est une **étape** de cette
feuille-là — la règle du design system interdit d'empiler deux feuilles — avec
un bouton « Revenir à l'offre ».

### 16.7 À trancher

| # | Sujet |
|---|---|
| T66 | **`Wallet.emptyMessage` vouvoie** — « Partagez votre cagnotte avec vos proches pour recevoir vos premières contributions ! ». R9 ne souffre aucune exception : la phrase est recopiée telle quelle (R8) et remontée. À réécrire dans Figma en « Partage ta cagnotte avec tes proches pour recevoir tes premières contributions ! » |
| T67 | **Trois coquilles recopiées** (R8 interdit de corriger en silence) : « grace » sans accent circonflexe sur la pastille de synthèse, « Prévisulation PDF » pour « Prévisualisation » dans les réglages, et « Défini maintenant » pour « Définis » sur la couverture à configurer |
| T68 | **Les deux boutons de la feuille de partage portent la même icône** — un cube Relume, visiblement un reste de composant : « Partager le fichier pdf » et « Partager le lien de prévisualisation » ne veulent pas dire la même chose et se ressemblent trait pour trait. Implémenté tel quel (R3, R10). Le jeu de marque a `IconPDF` et `IconLink`, qui diraient exactement ce qu'il faut |
| T69 | **Le libellé d'un bouton `small` passe à 16**, la valeur du composant Figma `Button`. Le 18 de `MemoBookFont.button` reste, mais il redevient ce qu'il est : une exception due au bouton d'Apple, qui n'a de sens que sur un appel à l'action pleine largeur. À 18, « Partager ma cagnotte » perdait le mot « cagnotte » |
| T70 | **Les deux boutons de la carte de solde sont en taille `small`** (44 pt) là où la maquette les dessine à 48. Quatre points au-dessus du seuil de R2, et assumé : c'est la **typographie** qui décide — à 18 pt, « Partager » et son icône demandent 152 pt dans une moitié de carte qui en offre 133 sur un iPhone SE. Soit la maquette descend son libellé de taille pleine à 16, soit ces deux boutons montent à 48 |
| T71 | **Le montant s'écrit toujours à deux décimales**, là où la maquette alterne « +30€ » et « +10,00€ » dans la même liste. Deux formats de montant côte à côte se lisent comme une erreur de saisie |
| T72 | **La pastille « DON » est à 11 pt** et non aux 9 de la maquette : l'app n'est jamais descendue sous 11, et ce mot-là porte la seule information qui distingue deux lignes de l'historique |
| T73 | **Le logo Tricount est écrit en toutes lettres** (« tt » dans le bleu de la marque) faute d'asset : c'est le logo d'un service tiers, il n'a pas à entrer dans le catalogue de MemoBook. À récupérer auprès de Tricount, ou à remplacer par un pictogramme neutre |
| T74 | **« La carte » montre l'illustration `IllustrationMaps`** et non le tracé du voyage : `backend/src/services/mapSvg.ts` le produit pour le carnet, pas pour l'écran. La ligne ne mène d'ailleurs nulle part |
| T75 | **Le coût d'impression est une constante** (1,798 € la page, soit les 89,90 € des 50 pages de la maquette). Les frais fixes de fabrication et de port sont dedans, donc un carnet de dix pages ne coûte pas un cinquième d'un carnet de cinquante. À trancher avec l'imprimeur **avant** d'encaisser quoi que ce soit |
| T76 | **Dix lignes de réglages n'ouvrent rien** — dates, rythme, notifications, co-voyageurs, thème, style, Tricount, carte, commande, aide. Les feuilles ne sont pas dessinées ; les lignes sont inertes plutôt que branchées sur un écran inventé (R3) |
| T78 | ✅ **Réglé** — le profil lisait « Abonne-toi » à quelqu'un à qui l'accueil annonçait « 2 étapes restantes ». Il ne regardait que l'abonnement, jamais le quota, alors que `GET /v1/profile` rend `offeredSteps` et `remainingSteps` depuis toujours. Les deux écrans partagent désormais le même calcul, et les deux pastilles s'accordent au singulier |
| T79 | ✅ **Réglé** — les trois barres du paywall se remplissaient ensemble. Deux causes : la remise à zéro et le remplissage tombaient dans la même passe (SwiftUI n'y voyait qu'une écriture, de 1 vers 1), et le `withAnimation` autour de `page` emportait les barres avec le contenu. La remise à zéro est explicitement sans animation, et la transition vit sur le contenu |
| T80 | **Les zones de tapotis du paywall passent sous le contenu.** Posées au-dessus, elles avalaient tout contrôle hors de la bande basse épargnée — c'est ce qui est arrivé à la pastille « Voir un aperçu ». Le texte des pages porte donc `paywallProse()`, qui le rend non touchable. Chaque nouveau bloc de texte du paywall devra le porter aussi, sinon la story ne défilera plus dessous |
| T81 | **La barre de la story finit de se remplir derrière la feuille d'aperçu.** Le minuteur, lui, est bien à l'arrêt — la page ne tourne pas, et on la retrouve entière en refermant. C'est l'animation SwiftUI déjà lancée qui va au bout : l'arrêter demanderait de lire l'avancement en cours, ce que SwiftUI n'expose pas |
| T82 | **Les onze lignes de personnalisation ne mènent nulle part** — ratio, nombre de pages, fun facts, pointillés, décorations, quatre typographies, couvertures. Leurs écrans de choix ne sont pas dessinés. Seuls les trois extras s'enregistrent |
| T83 | **Les deux plats de la ligne « Couvertures » sont dessinés en SwiftUI**, là où la maquette pose un rendu 3D de deux livres. Un rendu importé serait une image figée qui mentirait dès que le voyageur change sa couverture ; ces deux plats-là afficheront sa photo le jour où elle existe |
| T84 | **« Ajuster les différents options… vous ressemble »** — l'intro des personnalisations vouvoie *et* porte deux fautes (infinitif au lieu de l'impératif, accord manquant). Recopiée telle quelle (R8) et remontée, comme T66 |
| T77 | **La barre de progression est à 6 pt**, ce que dessinent la cagnotte comme les cartes de l'accueil. Le § 2.3 annonce encore 0.25 rem (4) au motif que Figma dessinait 7 : c'est **le document** qui est en retard, pas la valeur |
