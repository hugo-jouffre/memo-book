# Vocabulaire — comment on nomme les choses

> Un mot par chose, le même dans la maquette, la fiche, le code, la PR et la
> conversation. Ce fichier dit lequel. Il est né d'une demande de Hugo
> (16/09/2026) : les retours arrivent souvent en anglais — *page*, *screen*,
> *modal*, *flow*, *feature* —, les fiches sont en français, et le code en
> Swift ; sans table de correspondance, « la page du paywall » désigne trois
> choses différentes selon qui parle.
>
> Un mot nouveau s'ajoute **ici d'abord**, puis sert. Un mot qu'on hésite à
> employer, c'est qu'il manque ici.

---

## 1. Ce que l'utilisateur voit

| Mot | Ce que c'est | Exemples | Dans le code |
|---|---|---|---|
| **Écran** | Une vue qui prend toute la dalle et occupe une place dans la pile de navigation. Un écran a sa fiche (`ui-development.md` § 5) et son nœud Figma | l'accueil, l'accueil d'un voyage, les paramètres du voyage, les personnalisations du carnet, la conversation, le profil | `<Nom>View` dans `MemoBookFeature/<Dossier>/` — `HomeView`, `TripHomeView`, `TripSettingsView`, `BookCustomisationView`, `ProfileView` |
| **Feuille** (on dit aussi *modale*) | Ce qui se pose **sur** un écran sans le quitter : hauteur calée sur son contenu, geste du système, dessin de la marque. « Modale » est le mot de Figma et de Hugo, « feuille » celui du code et des fiches — c'est la même chose | « Supprimer ce voyage », « Estimation », les neuf feuilles de la personnalisation, les cinq de l'abonnement | `<Nom>Sheet`, rangées dans `<Domaine>Sheets.swift` quand elles sont plusieurs ; toujours une `BrandSheet`. Une feuille ne s'empile pas sur une autre — sauf l'aperçu du carnet sur l'offre, l'exception voulue (`ios/CLAUDE.md`) |
| **Étape** | Un des états successifs d'une même feuille ou d'un même tunnel : le contenu change, le cadre reste | les cinq temps de la feuille d'abonnement (l'offre, l'abonnement en cours, « continuer », la raison, « c'est fait ») ; les sept étapes du tunnel de commande ; les trois de « Mot de passe oublié » | un `enum Step` dans la feuille ou le modèle (`SubscriptionSheet.Step`, `PasswordRecoveryModel`) |
| **Écran du paywall** | Chacun des trois panneaux du paywall de retour, qu'on parcourt comme des stories | l'accroche, l'estimation, l'offre | `PaywallView.page` est l'**index** du segment de la barre — le mot *page* n'y désigne pas un écran de l'app |
| **Page** | Réservé au **carnet** — les pages du livre imprimé — et au web. Jamais un écran de l'app | « Nombre de pages cible », les deux pages du carnet au-dessus d'une feuille (`BookPagesPeek`) | `targetPageCount`, `BookPagesPeek`, `BookPageStage` |
| **Parcours** | Une suite d'écrans et de feuilles qu'on traverse dans l'ordre, avec une entrée et une sortie | l'entrée dans l'app (accueil, inscription, mot des fondateurs), la création d'un voyage, les couvertures, la résiliation, le paywall de retour | pas de suffixe : c'est le **dossier** qui le tient (`TripCreation/`, `Covers/`, `Paywall/`), et sa première vue porte le nom du domaine |
| **Tunnel** | Un parcours dont on ne saute aucune étape et qui se termine par un paiement | le tunnel de commande du carnet imprimé | `Order/`, `OrderView` et ses étapes ; `PrintOrderFlow` dans `MemoBookCore` en porte l'état |
| **Fonctionnalité** | Un domaine du produit : l'ensemble de ses écrans, feuilles, modèles, copie et jeu d'essai. En anglais, *feature* | l'accueil, le voyage, ses paramètres, la conversation, le profil, la cagnotte, le paywall, la commande, les couvertures, l'aperçu du carnet, la galerie, le support | un dossier de `MemoBookFeature/` : `Home/`, `Trip/`, `TripSettings/`, `Chat/`, `Profile/`, `Wallet/`, `Paywall/`, `Order/`, `Covers/`, `BookPreview/`, `Gallery/`, `Support/`, `Auth/`… |
| **Module** | Une cible du paquet Swift — **pas** une fonctionnalité | `MemoBookCore`, `MemoBookDesign`, `MemoBookNetworking`, `MemoBookRecording`, `MemoBookFeature` | `ios/Modules/Package.swift`. On ne dit jamais « le module chat » |
| **Lot** | Une unité de livraison du plan : un groupe d'écrans qui arrivent ensemble | Lot 1 · l'entrée dans l'app, Lot 3 · carnets et enregistrement, Lot 7 · le paywall de retour et les onze modales | `ui-development.md` § 4 ; une branche porte souvent un lot |
| **Relecture** | Les retours de Hugo ou de Clara après avoir pris l'app en main, traités d'un bloc dans une branche | la relecture du 14/09, celles des 15 et 16/09 | `ui-development.md` § 18, § 20, § 21 ; branche `retouches-du-<date>` |
| **Composant** | Une pièce du design system, réutilisée telle quelle par plusieurs écrans | le bouton, la feuille, le groupe de lignes, la pastille, le champ, le voile du pied de page | `Brand<Nom>` dans `MemoBookDesign` — `BrandButton`, `BrandSheet`, `BrandRowGroup`, `BrandTagPill`, `BrandTextField`, `BrandFooterScrim`. Une pièce propre à un écran reste dans son dossier, sans le préfixe (`CoverStack`, `HomeAddButton`), jusqu'au deuxième écran qui la veut |
| **Token** | Une valeur nommée du design system, en rem | une couleur, un espacement, un style de texte | `MemoBookColor.*`, `MemoBookSpacing.*`, `MemoBookFont.*` — aucun point brut dans un écran (R1) |
| **Asset** | Une image de marque, nommée par sa nature | la roue des réglages, le logo Tricount, la photo d'accueil | `Icon<Nom>` (et `<Nom>Duo` pour la bichrome), `Logo<Nom>`, `Illustration<Nom>`, `Photo<Nom>` ; ils entrent par `ios/Tools/import-brand-*.py`, jamais à la main |
| **Copie** | Les textes que l'utilisateur lit, recopiés de Figma au caractère près (R8), au tutoiement (R9) | « Accéder au chat », « Choisis ton mode de paiement » | `<Domaine>Copy` dans `MemoBookCore` — `BookCopy`, `ChatCopy`, `PaywallCopy`, `OrderCopy`, `SupportCopy` |

Et les mots des pièces d'un écran, pour décrire une maquette sans la montrer :

| Mot | Ce que c'est | Composant |
|---|---|---|
| **Appel à l'action** (on dit aussi *CTA*) | le bouton plein, pleine largeur, souvent en pied d'écran | `BrandButton(fillsWidth: true)` |
| **Ligne** · **groupe de lignes** | une entrée d'un écran de réglages — intitulé, valeur, chevron ou interrupteur — et le bloc qui en empile plusieurs | `BrandRow` · `BrandRowGroup` |
| **Option** · **groupe d'options** | une ligne encadrée d'un choix unique | `BrandOptionRow` · `BrandOptionGroup` |
| **Interrupteur** | ce qu'on bascule | `BrandToggleCard`, `Toggle` |
| **Curseur** | ce qu'on fait glisser | `BrandSlider` |
| **Pastille** | une petite étiquette — « DON », « Voir un aperçu », « -20 % » | `BrandTagPill` |
| **Chapeau** | le texte sous le titre d'une feuille ou d'un écran | `BrandSheet(subtitle:)`, `BrandScreenHeader(subtitle:)` |
| **Bandeau d'erreur** | le constat, un conseil, « Réessayer » et « Besoin d'aide ? », en ligne dans l'écran | `ErrorBanner` |
| **Voile** | le fondu sous un pied d'écran, pour que le contenu passe sous le CTA sans le gêner | `BrandFooterScrim` |
| **Barre du clavier** | la barre d'accessoires du clavier, avec son seul bouton | `brandKeyboardDismissBar()` |
| **Squelette** | la barre d'attente d'une valeur qui n'est pas encore là — jamais un écran entier | `BrandSkeleton` |
| **Tiroir** | les actions qu'un glissé vers la gauche découvre derrière une carte — supprimer, partager, prévisualiser un voyage ; retirer un co-voyageur | `BrandSwipeDrawer`, `BrandSwipeAction` |

---

## 2. Ce que le code manipule

| Mot | Ce que c'est | Suffixe ou nom |
|---|---|---|
| **Vue** | ce qui dessine ; ne navigue pas, ne calcule pas | `<Nom>View` |
| **Modèle** (d'écran) | l'état de l'écran et ses actions ; reçoit ses dépendances sous forme de fonctions | `<Nom>Model`, `@MainActor @Observable` |
| **Intention** | ce qu'un écran demande à l'app d'ouvrir, sans savoir comment | `<Nom>Intent` — `HomeIntent`, `TripSettingsIntent.orderBook` ; c'est `RootView` qui les traduit |
| **Route** | une destination de la pile de navigation | `HomeRoute`, `SignedOutRoute` |
| **Édition** | un seul réglage envoyé au serveur, tel qu'on l'a touché | `<Nom>Edit` — `TripSettingsEdit`, `BookCustomisationEdit` ; un `PATCH` à un champ |
| **Jeu d'essai** | les valeurs de la maquette, qui font vivre un écran sans serveur | `.fixture`, `<Domaine>Fixtures.swift` |
| **Bac à sable** | l'app entière branchée sur le jeu d'essai, en mémoire | `PreviewAPI`, `-previewSignedIn`, `SandboxPersona` (DEBUG seulement) |
| **Aperçu** | ⚠️ deux sens. Pour l'utilisateur, **l'aperçu du carnet** (`BookPreview/`, « Voir un aperçu »). Pour le développeur, les **previews Xcode** (`#Preview`). Dans une fiche, « aperçu » seul désigne toujours celui du carnet ; l'autre s'écrit « preview Xcode » | `BookPreviewSheet` · `#Preview` |
| **Sections**, **en-tête**, **pages** d'un écran | les morceaux d'un écran trop long pour un fichier, gardés à côté de lui | `HomeSections.swift`, `TripHeader.swift`, `PaywallPages.swift` |
| **Client** | ce qui parle au serveur ; la seule chose qui fabrique une `URLRequest` | `MemoBookAPIClient`, protocole `MemoBookAPI` |

Côté serveur (`backend/src/`) :

| Mot | Ce que c'est | Où |
|---|---|---|
| **Route** | un point d'entrée HTTP, un fichier par ressource, sa validation `zod` avec | `routes/` — `tripSettings.ts`, `memos.ts`, `wallet.ts` |
| **Service** | une règle métier qu'une route ou un job appelle | `services/` — `quota.ts`, `deletion.ts`, `billing.ts` |
| **Job** | une étape du pipeline, exécutée par le worker | `jobs/` — `transcribe`, `structure`, `redact`, `render` |
| **Sérialiseur** | ce qu'une route rend, et rien de plus | `routes/appSerializers.ts`, `serializers.ts` |
| **Gabarit** | le modèle du carnet imprimé, source de vérité de ce qu'un réglage peut faire | `templates/travel-journal/`, `LAYOUT_KB.md` |

### Voyage, carnet, `memo` — le même objet, trois noms

Pour l'utilisateur, un **voyage** a un **carnet**. En base, les deux sont **une
ligne** de `memos` — le carnet *est* le voyage, avec ses réglages dessus. L'API
dit `/v1/memos/:id` dans ses routes historiques et `/v1/trips/:id` dans celles
écrites depuis le lot 3 ; c'est le **même identifiant**. Dans l'app, `tripId`
et `memoId` désignent donc la même chose, et on garde `memoId` là où la route
appelée dit `memos`.

Les autres noms de la base, et leur mot dans l'app :

| Base et API | App |
|---|---|
| `account` | le compte |
| `memo` | le voyage, et son carnet |
| `entry` | un souvenir — un vocal, une photo, et ce qu'on en a tiré |
| `member`, `guest` | un co-voyageur (invité tant qu'il n'a pas rejoint) |
| `wallet` | la cagnotte |
| `subscription` | l'abonnement |
| `order` | la commande du carnet imprimé |
| `render` | le rendu — le PDF composé |
| `showcase`, `gallery` | la galerie, l'écran « Exemples de carnets » |

---

## 3. Ce qu'on écrit à côté du code

| Mot | Ce que c'est |
|---|---|
| **Fiche écran** | La description d'un écran avant de le coder : nœud, structure en rem, tokens, copie, états, contrat back-end, accessibilité, « à trancher ». Modèle en `ui-development.md` § 5, une par écran, dans ce fichier |
| **À trancher** · **T-numéro** | Une question ouverte pour Clara ou Hugo — un écart à la maquette, un choix pris faute de mieux. Numérotée `T<n>` **en continu sur tout le fichier** (le dernier employé se lit dans la dernière section) ; une fois réglée, la ligne reste et s'ouvre sur ✅ **Réglé** |
| **Règle R1 à R12** | Les règles non négociables de `ui-development.md` § 1 : rem, tailles classiques, Figma source de vérité, copie verbatim (R8), tutoiement (R9)… On les cite par leur numéro |
| **Nœud** | Un élément de la maquette Figma, désigné par son identifiant `1234:5678` — deux-points dans le texte, tiret dans une URL |
| **Branche** | Un lot ou une relecture, en français, en minuscules et tirets : `nouveaux-ecrans-et-modales`, `retouches-du-15-septembre` |
| **Commit** | Un titre en français, au présent, qui dit ce que le produit fait de plus ou de mieux — « Fait basculer le simulateur sur la production quand rien n'écoute sur le Mac » —, et un corps qui dit **pourquoi** |
| **PR** | Le lot ou la relecture ; sa description reprend ce qui a changé écran par écran, et recopie les « à trancher » pour Clara |

---

## 4. Français ↔ anglais

Pour lire une demande écrite en anglais, et y répondre avec les mots d'ici.

| En anglais | Ici |
|---|---|
| screen | **écran** |
| page | **page** s'il s'agit du carnet ou du web ; **écran** s'il s'agit de l'app |
| modal, sheet, bottom sheet, dialog | **feuille** (ou *modale*, même chose) |
| step | **étape** |
| flow, journey | **parcours** |
| funnel, checkout | **tunnel** |
| feature | **fonctionnalité** — un dossier de `MemoBookFeature/` ; jamais « module » |
| module, package target | **module** |
| batch, milestone | **lot** |
| review, feedback pass | **relecture** |
| component | **composant** |
| token, design token | **token** |
| asset, icon | **asset**, **icône** |
| copy, label, string | **copie** ; un **libellé** pour le texte d'un bouton ou d'une ligne |
| subtitle, caption | **chapeau** sous un titre ; **légende** sous une image |
| CTA, primary button | **appel à l'action** |
| row, list item | **ligne** |
| toggle, switch | **interrupteur** |
| slider | **curseur** |
| pill, chip, badge, tag | **pastille** |
| scrim, gradient overlay | **voile** |
| skeleton, shimmer | **squelette** |
| preview | **aperçu** (du carnet) ; **preview Xcode** pour `#Preview` |
| fixture, mock data | **jeu d'essai** |
| sandbox | **bac à sable** |
| trip | **voyage** |
| book, notebook, journal | **carnet** |
| memory, entry, recording | **souvenir** ; **vocal** pour l'enregistrement lui-même |
| companion, guest, member | **co-voyageur** |
| wallet, pot | **cagnotte** |
| order | **commande** |
| render, PDF | **rendu** |
| template | **gabarit** |
| back-end, API, server | **serveur** pour l'utilisateur ; **back-end** ou **API** entre nous |
