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
| **1 · Entrée dans l'app** | Splash Screen, Welcome Screen, Sign Up | ✅ Implémenté (§8) — reste les exports Figma |
| **2 · Compte** | Login, Mdp oublié, Mdp oublié - compte inexistant, Mdp oublié - config, Complète tes informations | ✅ Implémenté (§8) — suppression de compte à venir avec les Réglages |
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
| D6 | **T4 est tranché** par le détail fonctionnel Notion : **email + mot de passe**, plus Apple, Google et Facebook. Pas de magic link, pas d'écran de vérification d'email. Le back-end est écrit (`backend/src/routes/auth.ts`), Sign in with Apple est bien du lot (App Store 4.8) |
| D7 | **Rayon des champs, boutons et sélecteur : 0.875 rem (14).** Relevé au `get_design_context` sur *Sign Up*, *Login* et *Mdp oublié*, qui portent tous 14. Le §2.3 annonçait 1 rem d'après un relevé plus ancien : par R4, la valeur lue sur le nœud gagne. Les **cartes** restent à 1.25 rem (20) |
| D8 | **T6 est sans objet.** Le *Splash* ne porte plus le trait de 7 : la maquette courante instancie un `Loader` de 195 × 46 (`2804:12741`) et masque l'ancien. L'implémentation garde une barre indéterminée de 12.5 × 0.25 rem, à revoir quand le nouveau loader sera exporté |
| D9 | **États d'un CTA.** Actif : fond Green + ombre interne basse (`inset 0 −4 20 rgba(0,0,0,.25)`, relevée sur *Mdp oublié*). Inactif : fond Grey `#C8C8C8`, relevé sur *Sign Up* et *Login*, dont le formulaire est vide |

### 7.2 Ce qui reste ouvert

Tant que Clara n'a pas arbitré, on applique R4 (les variables Figma gagnent) et on
n'harmonise rien de sa propre initiative.

| # | Sujet | État |
|---|---|---|
| T10 | **Copie de la carte 2 du *Welcome*.** Figma dit « Vos photos misent en page » / « Vos photos concernées sont ajoutées rapidement depuis la galerie ou Instagram ». Le détail fonctionnel Notion dit « Photos et stickers instantanés ». Par R3 c'est Figma qui est implémenté. La faute « misent » est corrigée en « mises » sur arbitrage de Hugo : **à répercuter dans Figma**. Le titre lui-même reste à arbitrer entre les deux sources | 🟠 Correction faite, titre en attente |
| T11 | **Critères du mot de passe.** Le détail fonctionnel dit « respectant les critères de sécurité définis » sans les définir. Retenu, et écrit deux fois (`MemoBookCore/FormValidation.swift` et `backend/src/lib/password.ts`) : 8 caractères minimum, au moins une lettre et un chiffre | 🟠 À confirmer |
| T12 | **Teinte de la modale d'erreur du *Login*.** La maquette met « Réessayer » en bleu et « Annuler » en rouge — le bleu est l'accent système. L'app est teintée en Green : le bouton par défaut d'une alerte système sort donc vert, pas bleu | 🟢 Mineur |
| T13 | **Troisième fournisseur social.** Figma nomme les logos `image 697`, `image 698`, `image 701` : l'affectation Apple / Google / Facebook se lit à l'œil, elle n'est écrite nulle part. Le détail fonctionnel, lui, nomme bien les trois | 🟠 À vérifier à l'export |
| T14 | **Un compte est désormais obligatoire pour atteindre les carnets.** C'est ce que dit `routeFromSplash`, mais l'app savait jusqu'ici fonctionner en appareil anonyme. Le rattachement d'appareil est en place côté back-end, donc rien n'est perdu — mais plus personne ne peut enregistrer un vocal sans compte | 🟠 À confirmer produit |
| T7 | **Rôle de Lime.** `Scheme/Accent` vaut Lime `#E2F32B`, mais aucun des trois écrans ne l'emploie : c'est Green qui porte le CTA. Accent réservé à plus tard, ou accent qui n'a pas encore été appliqué ? | 🟠 À clarifier avant de poser les tokens |
| T8 | **Vouvoiement dans le Figma.** Les cartes 2 et 3 du *Welcome* vouvoient (« Parlez simplement », « Ajoutez vos photos ») alors que le reste de l'app tutoie. Par R9 c'est une coquille de maquette : à réécrire dans Figma, pas dans le code | 🟠 En attente de la copie corrigée |
| T9 | **États non maquettés.** Aucune maquette d'erreur ni de chargement sur *Sign Up*. Implémentés faute de mieux : erreur **en inline sous le champ** (le détail fonctionnel l'impose : « jamais en pop-up »), CTA en `ProgressView` pendant l'appel. Le CTA désactivé, lui, **est** maquetté — c'est le fond Grey `#C8C8C8` des deux écrans | 🟠 À valider par Clara |

---

## 8. Lots 1 et 2 — Entrée dans l'app et compte

Huit écrans, tous en 390 × 844, tous implémentés. Ils forment un seul parcours et ont été
développés ensemble : le détail fonctionnel de l'onboarding
([Notion](https://app.notion.com/p/3bf401e7bdc18028a62fd686961c2686)) les décrit d'un
bloc, et *Sign Up* et *Login* sont littéralement le même écran.

*Welcome*, *Sign Up*, *Login*, *Mdp oublié* et *Mdp oublié - compte inexistant* ont été
relevés au `get_design_context` : leurs valeurs sont fines et fiables. *Splash*,
*Mdp oublié - config* et *Complète tes informations* n'ont que le `get_metadata` et le
gabarit de leurs voisins — la limite d'appels du plan Figma a été atteinte en cours de
session. **Leurs couleurs par nœud, ombres et rayons restent à confirmer par
`get_design_context`.**

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

**Implémenté** : `MemoBookFeature/Onboarding/SplashView.swift`. Plancher 0.8 s, plafond
5 s, `LoaderBar` indéterminée. Le fond décoratif `M 01` (`2788:11553`), ajouté à la
maquette après le premier relevé, est en place via `BackgroundRoute`.

**À trancher** : D8 solde T6 — la maquette instancie désormais un `Loader` de 195 × 46
(`2804:12741`) et masque le trait de 7. L'implémentation garde une barre de
12.5 × 0.25 rem en attendant l'export du nouveau composant. Le fond suit D1
(`Scheme/Background Light` = Beige `#FCF2E9`).

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
- Carte 2 : « Vos photos mises en page » / « Vos photos concernées sont ajoutées
  rapidement depuis la galerie ou Instagram »
- Carte 3 : « Carnet imprimé d’exception » / « Mise en page automatique élégante et
  livraison chez vous de votre véritable carnet papier »
- CTA : « Découvre MemoBook »

> ⚠️ **La carte 2 a changé depuis le premier relevé** (20/08). Elle disait « Photos &
> stickers instantanés » / « Ajoutez vos photos depuis la galerie, Instagram ou créez vos
> stickers personnalisés » — c'est encore ce que dit le détail fonctionnel Notion. La
> maquette courante (`2552:27407`) dit ce qui est écrit ci-dessus : c'est elle qui fait
> foi (R3), et l'écart est remonté (T10).
>
> ⚠️ **La maquette écrit « misent »**, pour « mises ». Hugo a arbitré la correction : le
> code porte « mises ». **Reste à la répercuter dans Figma**, sinon le prochain relevé
> réintroduira la faute — R8 vaut dans les deux sens, la maquette et le code ne doivent pas
> diverger. Le sous-titre a aussi changé : « les met en page » et non plus « les met en
> forme ».

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

**Implémenté** : `MemoBookFeature/Onboarding/WelcomeView.swift` et `BenefitCard.swift`.
Le fond décoratif `M 01` a été ajouté à la maquette après le premier relevé : il est en
place. L'écran est dans un `ScrollView` (`.basedOnSize`) pour tenir en AX3 sur iPhone SE
sans rien tronquer.

**À trancher** : T8 (les phrases qui vouvoient), T10 (la copie de la carte 2 et sa faute),
présence ou non d'un « passer ». La marge (D2), la palette (D1), les polices (D3) et
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

**Contrat back-end** — ✅ **écrit** (`backend/src/routes/auth.ts`), T4 étant tranché par
le détail fonctionnel (D6).

| Besoin | Route | Remarques |
|---|---|---|
| Création de compte | `POST /v1/auth/signup` | prénom, nom, email, mot de passe. Argon2id, jamais en clair. 409 `conflict` si l'email est pris |
| Connexion | `POST /v1/auth/login` | 401 générique : ni l'email ni le mot de passe ne sont désignés |
| Login tiers | `POST /v1/auth/social/:provider` | renvoie une session, ou `profile_required` + le profil à confirmer |
| Profil tiers | `POST /v1/auth/social/complete` | nommé comme dans le détail fonctionnel |
| Session | `GET /v1/auth/me`, `POST /v1/auth/logout` | `me` est ce que le *Splash* interroge |
| Rattachement | `services/accounts.ts` | l'appareil anonyme cède ses carnets à l'appareil principal du compte |
| Modèle | `prisma/schema.prisma` | `User`, `Session`, `SocialIdentity`, `PasswordReset`, plus `Device.userId` |

> ⚠️ Le nom de la route de login tiers diverge de la ligne « `POST /v1/auth/oauth/:provider` »
> écrite ici lors du cadrage : `social/` a été retenu pour que l'échange et la complétion
> forment une seule famille, `complete` étant nommé ainsi dans le détail fonctionnel.

Trois contraintes tenues : **Sign in with Apple obligatoire** dès qu'un login social
tiers est proposé (App Store 4.8) — les trois boutons vont ensemble · mot de passe
**jamais** stocké ni journalisé en clair · aucun message qui révèle si un email existe,
**sauf** sur `forgot-password`, où le détail fonctionnel le demande explicitement (c'est
ce qui fait exister l'écran *Mdp oublié - compte inexistant*).

La **suppression de compte** (guideline 5.1.1) reste à écrire : elle appartient au lot
Réglages, pas à celui-ci. À ne pas oublier avant la soumission App Store.

**Implémenté** : `MemoBookFeature/Onboarding/CredentialsView.swift` +
`CredentialsModel.swift`, partagés avec *Login* (§8.4). Les trois boutons sociaux
répondent qu'ils ne sont pas disponibles tant que les SDK ne sont pas intégrés
(`SocialSignInBroker`) — un bouton qui ne marche pas doit le dire.

**Assets** : trois logos de fournisseurs (`image 701`, `image 697`, `image 698` — à
identifier au moment de l'export ; probablement Apple, Google et un troisième).

**Accessibilité** : `textContentType` correct sur chaque champ (`.givenName`,
`.familyName`, `.emailAddress`, `.newPassword`) pour le trousseau et la suggestion de mot
de passe fort · `submitLabel` et enchaînement au clavier · le contenu remonte à
l'ouverture du clavier (R7) · contraste des placeholders `#8E8E93` sur `#fcf2e9` à
vérifier (probablement sous 4.5:1).

**À trancher** : T9 (états non maquettés), T11 (critères du mot de passe), T13 (identité
des trois logos sociaux), et la présence de CGU / politique de confidentialité à cocher —
absente de la maquette, mais généralement exigée à la création de compte. T4 est soldé
par D6.

---

---

### 8.4 Login

- **Nœud Figma** : `2720:21779` (nominal) et `2553:27577` (avec la modale d'erreur) —
  [ouvrir](https://www.figma.com/design/kytPYFno7PvDciIKTxCujK/MemoBook---Product?node-id=2720-21779)
- **Vue** : `MemoBookFeature/Onboarding/CredentialsView.swift`, onglet `.signIn`
- **Rôle** : authentifier quelqu'un qui a déjà un compte.
- **Entrée / sortie** : depuis *Splash* (onboarding déjà vu), depuis l'onglet de *Sign
  Up*, ou au retour de *Mot de passe oublié* → carnets, *Sign Up*, ou *Mot de passe
  oublié*.

**Le même écran que *Sign Up*.** Le détail fonctionnel le dit : « idéalement en changement
d'état d'un même composant plutôt qu'en navigation complète ». C'est ce qui est
implémenté — une seule vue, un seul modèle, l'onglet est un état.

**Structure (en rem)** — identique à *Sign Up* (§8.3) pour le conteneur, le sélecteur, le
CTA et le bloc social. Ce qui change :

| Élément | Figma | rem | Note |
|---|---|---|---|
| Titre | « Ravi de te revoir ! » | 2 | Sora SemiBold, comme *Sign Up* |
| Champs | Email, Mot de passe | × 3 chacun | Deux au lieu de cinq |
| Lien « Mot de passe oublié ? » | 12, Green, centré | 0.75 | General Sans **Bold** sur le nœud ; implémenté en Medium, faute de graisse Bold dans les styles relevés — à confirmer |
| CTA | fond Grey `#C8C8C8` | × 3 | État désactivé : le formulaire est vide (D9) |

**Copie** (verbatim) : « S’inscrire » · « Se connecter » · « Ravi de te revoir ! » ·
« connecte toi » · « Email » · « Mot de passe » · « Mot de passe oublié ? » ·
« Continuer » · « Ou continue avec ».

> ⚠️ « connecte toi » s'écrit sans trait d'union sur la maquette. Recopié tel quel (R8),
> signalé : « connecte-toi ».

**États**
- **Nominal** : formulaire vide, CTA désactivé.
- **Validation** : email vide ou mal formé, mot de passe vide → inline sous le champ.
- **Chargement** : CTA en `ProgressView`.
- **Erreur d'authentification** : **modale**, et c'est la seule du flow. Texte « Une
  erreur s'est produite lors de votre tentative de connexion », bouton « Réessayer » qui
  ferme et remet le focus sur le mot de passe **sans effacer l'email**, bouton « Annuler »
  qui ferme. Le message reste générique : dire lequel des deux champs est faux, c'est
  confirmer qu'une adresse a un compte.

**Contrat back-end** : `POST /v1/auth/login` → `200 { userId, sessionToken,
hasSeenOnboarding }` · `401 invalid_credentials`.

**Accessibilité** : `textContentType` `.emailAddress` et `.password` pour le trousseau ·
enchaînement au clavier `.next` puis `.go` · le lien « Mot de passe oublié ? » porte une
cible de 2.75 rem alors que son texte fait 0.75 rem.

**À trancher** : T12 (la modale de la maquette met « Réessayer » en bleu ; l'app est
teintée en Green, donc le bouton par défaut d'une alerte système sort vert) · le
vouvoiement du texte de la modale (« votre tentative ») contre R9 — recopié, signalé ·
la graisse du lien.

---

### 8.5 Mot de passe oublié

- **Nœud Figma** : `2707:9275` —
  [ouvrir](https://www.figma.com/design/kytPYFno7PvDciIKTxCujK/MemoBook---Product?node-id=2707-9275)
- **Vue** : `MemoBookFeature/Onboarding/ForgotPasswordView.swift`
- **Rôle** : confirmer l'adresse, puis déclencher l'envoi du lien.
- **Entrée / sortie** : depuis le lien de *Login* → *Connection* si un compte existe,
  *Mdp oublié - compte inexistant* sinon.

**Structure (en rem)**

| Élément | Figma | rem | Note |
|---|---|---|---|
| Espacement entre blocs | 28 | 1.75 | Écart R2 conservé et signalé : 28 n'est pas sur l'échelle §2.2 |
| Pastille cadenas | 66, icône 44 (tracé 30 × 38.8) | 4.125 / 2.75 | |
| Colonne de contenu | 358, gap 32 | 22.375, gap 2 | |
| Titre | 348 de large | 21.75 | Sora SemiBold 2 rem |
| Texte explicatif | pleine largeur | — | General Sans Regular 1 rem, **Black** et non gris |
| Champ email + crayon | 47, r 14, px 24 | × 3, r 0.875 | Le crayon fait 44 → cible tactile déjà conforme |
| CTA | 358 × 48, Green + ombre interne | × 3 | État **actif** (D9) |

**Copie** (verbatim) : « Mot de passe oublié » · « Un email pour reconfigurer ton mot de
passe va t’être envoyé à l’adresse suivante : » · « Continuer ». L'écran tutoie ✅.

**Comportement** — le détail fonctionnel est explicite : **l'app n'attend pas la
confirmation d'envoi.** Elle repart sur *Connection* dès que le serveur confirme qu'un
compte existe, et l'envoi part en parallèle côté serveur. Faire porter à quelqu'un la
latence d'un SMTP pour afficher un écran n'aurait aucun intérêt.

**Contrat back-end** : `POST /v1/auth/forgot-password` → `200 { message: "email_sent" }` ·
`404 account_not_found`. Le lien envoyé est un deep link
`memobook://reset-password?token=…`, valable 45 minutes (`PASSWORD_RESET_TTL_MINUTES`) et
à usage unique.

> ⚠️ **Aucun fournisseur d'email n'est choisi.** `backend/src/services/mailer.ts` écrit le
> message dans les logs : le flow est complet et testable, mais personne ne reçoit rien.
> C'est la dernière dépendance de cet écran.

**États** : nominal (adresse pré-remplie, en lecture seule) · édition (le crayon ouvre le
champ) · validation inline · chargement sur le CTA · erreur réseau en bandeau. Seul le
nominal est maquetté.

**Accessibilité** : le crayon porte « Modifier l’adresse email » · l'adresse est tronquée
en son milieu plutôt qu'à la fin, pour garder le domaine lisible.

**À trancher** : le champ est-il modifiable d'emblée quand aucune adresse n'arrive de
*Connection* ? Implémenté ainsi (sinon l'écran serait sans issue). Non maquetté.

---

### 8.6 Mdp oublié - compte inexistant

- **Nœud Figma** : `2820:18513` —
  [ouvrir](https://www.figma.com/design/kytPYFno7PvDciIKTxCujK/MemoBook---Product?node-id=2820-18513)
- **Vue** : `MemoBookFeature/Onboarding/ForgotPasswordView.swift`,
  `ForgotPasswordNoAccountView`
- **Rôle** : dire qu'aucun compte n'existe pour cette adresse, et proposer d'en créer un.
- **Entrée / sortie** : depuis *Mot de passe oublié* → *Sign Up*, **et rien d'autre**.

**Structure** : la même que §8.5, moins le champ et moins le CTA.

**Copie** (verbatim) : « Mot de passe oublié » · « Il n’existe aucun compte associé à
l’adresse <email> » · « Tu peux en créer un  » · « en cliquant ici » (souligné, Green).

> ⚠️ « Tu peux en créer un » est suivi de **deux espaces** sur le nœud, avant le lien.
> Un seul est implémenté : deux espaces consécutifs ne sont pas une intention de mise en
> page, c'est le rendu d'un `HStack` avec une gouttière. Signalé.

**Cet écran n'a pas de CTA.** Le lien est la seule sortie, et il n'y a **pas de chemin de
retour** vers *Mot de passe oublié* ni vers *Connection* : c'est le dessin de la maquette,
et le détail fonctionnel le confirme mot pour mot.

**Contrat back-end** : aucun. L'information vient du 404 de l'écran précédent.

**À trancher** : l'absence de retour. Quelqu'un qui s'est trompé d'un caractère dans son
adresse n'a d'autre choix que de créer un compte ou de tuer l'app. À valider par Clara —
implémenté conforme à la maquette, comme le veut R3.

---

### 8.7 Mdp oublié - config

- **Nœud Figma** : `2707:9539` —
  [ouvrir](https://www.figma.com/design/kytPYFno7PvDciIKTxCujK/MemoBook---Product?node-id=2707-9539)
- **Vue** : `MemoBookFeature/Onboarding/ForgotPasswordView.swift`, `ResetPasswordView`
- **Rôle** : poser le nouveau mot de passe.
- **Entrée / sortie** : **uniquement** par le deep link reçu par email → *Connection*.

**Structure (en rem)** — même gabarit que §8.5.

| Élément | Figma | rem | Note |
|---|---|---|---|
| Pastille cadenas | 66, à y 75 | 4.125 | |
| Titre | 348 × 105 | 21.75, 3 lignes | « Configure ton nouveau mot de passe » |
| Champs | 47 chacun, gouttière 24 | × 3, gouttière 1 | Gouttière 24 → 1 rem par R2 (écart de 8 : **signalé**, la maquette dessine 71 − 47 = 24) |
| CTA | 358 × 48 | × 3 | |

**Copie** (verbatim) : « Configure ton nouveau mot de passe » · « Mot de passe » ·
« Confirme ton nouveau mot de passe » · « Continuer ».

**Contrat back-end** : `POST /v1/auth/reset-password` → `200 { message:
"password_updated" }` · `400 invalid_or_expired_token`. Le succès **ferme toutes les
sessions ouvertes** du compte et invalide les autres demandes en cours : si quelqu'un
d'autre était connecté, il ne l'est plus.

**États** : validation inline sur les deux champs · **lien mort** (périmé, déjà utilisé,
invalide) → message clair **avec une sortie vers l'écran de connexion**. On ne laisse
jamais quelqu'un devant un formulaire qui ne servira à rien. Non maquetté.

**Sécurité** : le jeton vaut 45 minutes et une seule utilisation. L'écran n'est
atteignable par aucune navigation interne — `OnboardingModel.open(deepLink:)` est le seul
chemin, et il refuse tout ce qui n'est pas `memobook://reset-password?token=…` non vide.

**À trancher** : le « message de confirmation discret » évoqué par le détail fonctionnel
au retour sur *Connection* n'est pas maquetté et n'est pas implémenté.

---

### 8.8 Complète tes informations

- **Nœud Figma** : `2707:9456` (« Social login - compléments ») —
  [ouvrir](https://www.figma.com/design/kytPYFno7PvDciIKTxCujK/MemoBook---Product?node-id=2707-9456)
- **Vue** : `MemoBookFeature/Onboarding/CompleteProfileView.swift`
- **Rôle** : confirmer ou corriger ce qu'un fournisseur tiers a transmis, avant de créer
  le compte.
- **Entrée / sortie** : depuis *Sign Up* ou *Login*, après une connexion tierce sur une
  identité inconnue → carnets.

**Structure (en rem)** — conteneur à x 16, y 80.4, largeur 358, comme *Sign Up*.

| Élément | Figma | rem | Note |
|---|---|---|---|
| Titre | 348 × 70 | 21.75, 2 lignes | |
| Sous-titre | 288 × 42 | 18 | |
| Espace titre → champs | 32 | 2 | ✅ |
| Ligne Prénom / Nom | 171 + 16 + 171 | 10.7 + 1 + 10.7 | Deux colonnes égales |
| Gouttière verticale | 63 − 47 = 16 | 1 | ✅ |
| Champ Email | 358 × 47 | × 3 | |
| Espace champs → CTA | 286 − 254 = 32 | 2 | ✅ |

**Copie** (verbatim) : « Complète tes informations » · « nous avons récupéré les
informations suivantes, vérifie leur validité » · « Prénom » · « Nom » · « Email » ·
« Continuer ». Les champs sont montrés **pré-remplis** sur la maquette (« cla »,
« thioll », « cla.thioll@gmail.com ») : ce sont des données d'exemple, pas des libellés.

**Le cas Apple.** Apple peut renvoyer un relais `xxxx@privaterelay.appleid.com` plutôt
qu'une adresse personnelle. Il est **accepté tel quel** — Apple fait suivre le courrier
tant que l'accès n'est pas révoqué, et on ne réclame pas une « vraie » adresse à quelqu'un
qui a justement choisi de la masquer. Une mention discrète le dit sous le champ ; elle
n'est **pas maquettée** et est à valider.

**Contrat back-end** : `POST /v1/auth/social/complete` → `201 { userId, sessionToken,
hasSeenOnboarding }` · `409 conflict` si l'adresse est déjà prise par un autre compte,
auquel cas on reste sur l'écran, message sous le champ Email.

**États** : nominal (pré-rempli) · champs vides si le fournisseur n'a rien transmis ·
validation inline · chargement sur le CTA · 409 sous le champ. Seul le nominal est
maquetté.

**À trancher** : la mention sur le relais Apple · que faire si le fournisseur n'a transmis
**aucun** email — le champ est vide et bloquant, ce qui est le comportement implémenté,
mais l'écran ne l'explique pas.

---

### 8.9 Ce que le lot 1+2 laisse ouvert

Trois dépendances externes, listées ici parce qu'elles ne sont pas du code à écrire :

| Dépendance | État | Conséquence aujourd'hui |
|---|---|---|
| **Exports Figma** | ❌ | Les icônes, le logo et les logos sociaux laissent une réserve neutre. Liste et procédure : [`figma-assets.md`](figma-assets.md) |
| **Polices Sora et General Sans** | ❌ | `Font.custom` retombe sur la police système. Les tailles, graisses et approches sont déjà justes |
| **SDK Apple / Google / Facebook** | ❌ | Les trois boutons répondent qu'ils ne sont pas disponibles. Il leur faut les client IDs des trois fournisseurs |
| **Fournisseur d'email** | ❌ | Le lien de réinitialisation part dans les logs du serveur |

Et une vérification qui n'a pas pu être faite : **la comparaison capture / maquette**
(§6, étape 6). Elle demande un Mac avec Xcode ; la session de développement n'en avait
pas. `make build`, `make test` et les captures comparées restent à passer avant la PR.

## 9. Ce qu'on ne fait jamais

- Coder une valeur numérique dans une vue au lieu d'un token
- Écrire une taille de police fixe (casse Dynamic Type)
- Substituer une icône, un rayon, une couleur « équivalente »
- Vouvoyer l'utilisateur, où que ce soit dans l'app
- Inventer un état, un libellé, une animation absents de la maquette
- Inventer un endpoint côté app en espérant qu'il existe
- Corriger une faute de français sans retour de Clara
- Harmoniser deux écrans qui divergent, au lieu de le signaler
- Fermer une PR d'écran sans la capture comparée à Figma
