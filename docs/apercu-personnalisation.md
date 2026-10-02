# Aperçu de personnalisation

> L'image qui surmonte l'écran « Personnalisations » et se réactualise à chaque
> réglage touché. Ce fichier dit **quelle image** afficher pour un état donné du
> carnet, et rien d'autre : ni où elle est hébergée, ni comment elle s'anime.
> L'hébergement et le manifeste que lit l'app : `assets/README.md`.

Les visuels vivent dans `assets/illustrations/aperçu personnalisation/` :
200 aperçus plus une image de repli. Chaque nom de fichier porte, en clair, la
valeur des cinq propriétés qui l'ont produit.

## Cinq propriétés décident de l'image, quatre n'y changent rien

| Propriété du modèle (`BookCustomisation`) | Valeurs | Segment du nom de fichier |
|---|---|---|
| `rulesEnabled` | `true` / `false` | `Pointillés=on` / `Pointillés=off` |
| `photoTextRatio` | 0, 25, 50, 75, 100 | `Ratio image=50%` |
| `funFactsEnabled` | `true` / `false` | `Fun fact=on` / `Fun fact=off` |
| `decorationQuota` | 0, 1, 2, 3, 4 | `Stickers=2` |
| Les quatre polices | 3 assortiments | `Typos=…` (table ci-dessous) |

**Sans effet sur l'aperçu** — ils ne doivent déclencher aucun rechargement :
`targetPageCount`, `quizEnabled`, `freeZonesEnabled`, `crosswordEnabled`.

Les plages correspondent exactement à ce que les curseurs exposent déjà
(`BookCustomisationPanels.swift` : ratio `0...100` par pas de 25, quota `0...4`).

### Les trois assortiments typographiques

Le segment `Typos=` ne nomme pas quatre polices mais l'assortiment
(`BookFontCombo`), sous une forme abrégée et **non normalisée** :

| `BookFontCombo` | Nom affiché | Segment exact du fichier |
|---|---|---|
| `travel-journal` *(défaut)* | Carnet de voyage | `Playfair Display - Hansley - Gloria Hallelujah` |
| `handwritten` | Manuscrit | `Hansley - Gloria Hellelujah` |
| `editorial` | Éditorial | `Playfair Display` |

⚠️ Trois pièges dans cette seule table :
- **`Hellelujah`**, et non `Hallelujah`, dans le segment de l'assortiment
  *Manuscrit* — une faute de frappe figée dans 50 noms de fichiers. La table de
  correspondance doit la reproduire telle quelle.
- **`Éditorial` ne cite pas Alegreya**, qui est pourtant sa police de texte. Le
  segment se réduit à `Playfair Display`. Correspondance vérifiée sur le rendu :
  le texte courant y est bien en serif.
- Un carnet dont les quatre polices ne forment **aucun** des trois assortiments
  (l'état « Personnalisé », atteignable rôle par rôle depuis un catalogue de
  cinq familles) n'a pas d'aperçu : il tombe sur le repli.

## L'état par défaut

Tant que le voyageur n'a touché à rien, `BookCustomisation.init` pose :

`Pointillés=on, Ratio image=50%, Fun fact=on, Stickers=2, Typos=Playfair Display - Hansley - Gloria Hallelujah`

Cet aperçu-là existe : c'est celui qui s'affiche à l'ouverture de l'écran.

## La contrainte entre typographie et pointillés

Aucun aperçu n'existe pour `Pointillés=on` hors de l'assortiment par défaut.
**Décision (01/10/2026, Hugo) : changer de typographie pour *Manuscrit* ou
*Éditorial* met les pointillés à `false` et verrouille leur interrupteur.**
L'aperçu affiché est alors toujours celui, existant, de la variante sans
pointillés.

⚠️ `rulesEnabled` n'est pas un réglage d'aperçu : c'est celui des lignes
pointillées **du carnet imprimé** (`BookCopy` : « Lignes en pointillé sous le
texte dans ton carnet »). Cette règle fait donc qu'un choix de police retire une
option de mise en page du produit final. C'est tenable tant que les 100 rendus
manquants n'existent pas ; le jour où ils sont produits, la contrainte doit
sauter — et elle seule, le reste de la règle ne bouge pas.

**Le verrouillage se défait.** Au retour vers l'assortiment par défaut, les
pointillés reprennent la valeur qu'ils avaient avant le verrouillage (décision du
01/10/2026, Hugo) — et non `false`, que personne n'aurait choisi. L'écran mémorise
donc la valeur d'avant le premier changement de typographie, et la rend telle
quelle ; un aller-retour entre deux assortiments doit laisser le carnet
exactement dans l'état où il était.

## La règle

1. Lire les cinq propriétés sur le carnet.
2. Résoudre l'assortiment typographique ; aucun ne correspond → **repli**.
3. Assortiment autre que celui par défaut → forcer `Pointillés=off` (ci-dessus).
4. Composer le nom de fichier, dans cet ordre strict, séparateur `, ` :
   `Pointillés={on|off}, Ratio image={n}%, Fun fact={on|off}, Stickers={n}, Typos={assortiment}.png`
5. Ce fichier existe → l'afficher. Sinon → **repli**.

Le repli est `apercu non existant.png`, dans le même dossier — **sans cédille**,
renommé le 01/10/2026 pour cette raison : il était le seul des 201 fichiers écrit
en Unicode NFD (`c` + U+0327) là où tous les autres sont en NFC, et le nom
« évident » renvoyait un 404. Le dossier est désormais homogène ; garder ce nom
en ASCII le maintient hors de portée du problème.

## Les aperçus « composition trop chargée »

Douze aperçus ne montrent pas une page mais un avertissement incrusté — la page
grisée sous le texte « Cette composition est trop chargée. Modifie un paramètre
de mise en page pour que ton carnet reste harmonieux ». Ce sont des aperçus
ordinaires du point de vue de la règle : ils portent le nom de leur combinaison
et s'affichent comme les autres. Ils ne sont **pas** le repli.

Ils couvrent exactement les compositions à `Stickers=4` combinées à beaucoup de
photo :

| Ratio image | Fun fact | Concernés |
|---|---|---|
| 100 % | `on` ou `off` | toutes les combinaisons existantes |
| 75 % | `on` seulement | toutes les combinaisons existantes |

Soit, par assortiment : 4 pour la typographie par défaut (les deux états des
pointillés), 2 pour *Manuscrit*, 2 pour *Éditorial* à 100 % ; plus un chacun à
75 % avec fun fact.

**Cet avertissement ne déclenche rien** (décision du 02/10/2026, Hugo). Il ne
bloque pas la commande, ne renvoie vers aucun réglage, n'allume aucun état
particulier dans l'écran : le message vit dans l'image et nulle part ailleurs.
Pour le code, ces douze fichiers sont des aperçus comme les autres — rien dans
la règle de sélection ni dans l'écran ne doit chercher à les reconnaître.

## Couverture : complète

Le dépôt contient 200 aperçus et une image de repli. Les cinq propriétés
produisent 300 états, dont 200 ont un aperçu. Les 100 absents sont exactement
ceux que la contrainte typographie → pointillés rend inatteignables
(`Pointillés=on` avec *Manuscrit* ou *Éditorial*).

**Une fois la contrainte posée, les 200 états atteignables ont tous leur
aperçu** — vérifié sur le dossier. Le repli ne sert donc plus que pour l'état
« Personnalisé » : quatre polices qui ne forment aucun des trois assortiments.

Le lot du 02/10/2026 a réglé ce qui manquait : les douze fichiers autrefois
suffixés `-1` étaient mal nommés — ils portent les pointillés éteints, et non
allumés — et ont été renommés en `Pointillés=off`. Ils comblent précisément les
douze combinaisons qui tombaient sur le repli. Plus aucun fichier du dossier ne
porte de suffixe numérique.
