# Aperçu de personnalisation

> L'image qui surmonte l'écran « Personnalisations » et se réactualise à chaque
> réglage touché. Ce fichier dit **quelle image** afficher pour un état donné du
> carnet, et ce que l'écran en fait (§ À l'écran). L'hébergement et la chaîne
> qui publie les images : `assets/README.md`.

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
- **`Éditorial` se réduit à `Playfair Display`**, et c'est exact : depuis le
  01/10/2026, l'assortiment met Playfair sur les quatre rôles. Un carnet réglé
  sur l'ancien *Éditorial*, qui mariait Alegreya au récit, garde ses polices :
  il est « Personnalisé », et tombe sur le repli.
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

**Les carnets d'avant le verrou sont remis dans le rang à l'ouverture**
(décision du 02/10/2026, Hugo). La contrainte agit au *changement* de
typographie ; or les assortiments existent depuis le 16/09/2026, et
`rulesEnabled` vaut `true` par défaut : un carnet passé sur *Manuscrit* ou
*Éditorial* sans toucher aux pointillés les a encore allumés. Une ancienne
version de l'app, sans verrou, peut aussi les rallumer. L'écran des
personnalisations les éteint donc à son ouverture, et mémorise qu'ils étaient
allumés — sauf si ce téléphone garde déjà la valeur d'avant le verrou : c'est
elle que le retour au défaut rendra. C'est la seule écriture au serveur qu'il
fasse sans geste du voyageur ; si elle échoue, il ne la retente pas avant la
prochaine ouverture, et l'interrupteur reste libre de les éteindre : le verrou
interdit de les rallumer, pas de les éteindre.

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
exactement dans l'état où il était. Un second changement de typographie, verrou
posé (*Manuscrit* → *Éditorial*), ne touche pas à la mémoire.

**La mémoire vit sur l'appareil** (décision du 02/10/2026, Hugo) : une clé par
voyage dans `UserDefaults`, qui survit à la fermeture de l'écran et de l'app, et
s'efface dès que le serveur rend un carnet déverrouillé. Ce qu'elle ne couvre
pas, et c'est accepté : un autre téléphone, ou un co-voyageur, ne la connaît
pas — le retour au défaut y **rallume** les pointillés, la valeur par défaut.

**Le verrou se voit, et se dit** (copie validée le 02/10/2026, Hugo) :

- dans **Extras**, l'interrupteur des pointillés éteints pâlit et reste
  tapable ; l'appui pose une note d'information : « Les pointillés ne s’impriment qu’avec la
  typographie Carnet de voyage. Choisis-la dans Typos pour les retrouver. » ;
- dans **Typos**, au geste qui vient d'éteindre des pointillés allumés, une note
  sous les assortiments : « Manuscrit s’imprime sans pointillés : on les a
  retirés. Ils reviendront si tu repasses sur Carnet de voyage. » (ou
  *Éditorial*). L'écran défile jusqu'à elle — sous les trois assortiments, elle
  tombe sous le bas de l'écran de la plupart des iPhone —, et elle disparaît au
  geste suivant.

VoiceOver annonce l'une et l'autre au moment où elles paraissent.

**Dans le code.** `BookFontCombo.allowsRules` dit quels assortiments permettent
les pointillés — le défaut seul. `BookRulesLock` (`MemoBookCore`) en tire la
règle, en fonctions pures ; `BookCustomisationModel` l'applique, et envoie
l'assortiment **et** les pointillés dans une seule édition
(`.fontCombo(_:rulesEnabled:)`) : le serveur ne passe jamais par un
*Manuscrit* aux pointillés allumés. Le jour où les rendus manquants arrivent,
`allowsRules` rend `true` partout, et c'est tout.

## La règle

1. Lire les cinq propriétés sur le carnet.
2. Résoudre l'assortiment typographique ; aucun ne correspond → **repli**.
3. Assortiment autre que celui par défaut → `Pointillés=off`. C'est **l'écran**
   qui l'a posé en appliquant la contrainte (ci-dessus) : la sélection lit
   `rulesEnabled` tel quel et ne force rien. Un carnet que la contrainte n'a pas
   encore touché — *Manuscrit* avec pointillés, que l'écran n'a pas pu remettre
   dans le rang — n'a pas d'image et tombe sur le repli à l'étape 5, plutôt que
   sur un aperçu sans les pointillés qu'il imprimera. Le jour où la contrainte
   saute, la sélection n'a donc pas à bouger.
4. Composer le nom de fichier, dans cet ordre strict, séparateur `, ` :
   `Pointillés={on|off}, Ratio image={n}%, Fun fact={on|off}, Stickers={n}, Typos={assortiment}.png`
5. Ce fichier existe → l'afficher. Sinon → **repli**.

Le repli est `apercu non existant.png`, dans le même dossier — **sans cédille**,
renommé le 01/10/2026 pour cette raison : il était le seul des 201 fichiers écrit
en Unicode NFD (`c` + U+0327) là où tous les autres sont en NFC, et le nom
« évident » renvoyait un 404. Le dossier est désormais homogène ; garder ce nom
en ASCII le maintient hors de portée du problème.

### Dans le code

`BookCustomisationPreview.fileName(for:)` (`MemoBookCore`) applique les étapes
1, 2, 4 et 5 : une fonction pure, qui rend un nom de fichier et ne charge rien.

« Ce fichier existe » ne se demande pas au disque : la liste des aperçus est
une **donnée**, `BookCustomisationPreview.availableFileNames`, écrite par un
script depuis le dossier. Le même script y joint, pour chaque nom, l'image
**publiée** que l'app télécharge (`imageURL(for:)`), lue dans le manifeste de
la chaîne de publication (`assets/illustrations/apercus-personnalisation.manifest.json`) :
la correspondance est **embarquée** dans l'app (décision du 02/10/2026, Hugo),
un seul appel réseau, celui de l'image. Après tout ajout, retrait ou
renommage :

```bash
cd backend && npm run previews:publish && cd ..
python3 ios/Tools/make-customisation-preview-manifest.py
```

puis une version de l'app : un aperçu ajouté n'y paraît qu'avec elle. Ce n'est
pas une contrainte de plus pour les 100 rendus attendus — lever le verrou
(`allowsRules`) en demande une de toute façon.

Le script refuse un nom en NFD, un nom qui ne suit pas la forme des cinq
segments, et l'absence du repli ; la valeur de `Typos=`, elle, n'est vérifiée
que par les tests, qui tiennent la table des assortiments.
`BookCustomisationPreviewTests` compare le manifeste au dossier **octet par
octet** — Swift tient « é » et « e + accent » pour la même chaîne, une URL
non ; c'est aussi pourquoi `fileName(for:)` rend l'élément du manifeste et non
le nom qu'il a composé. Les tests vérifient encore la couverture ci-dessous :
tout fichier est composable, tout état atteignable a son image, et les 100
états que la contrainte écarte n'en ont pas. Ce dernier test cassera le jour où
les rendus manquants arriveront : c'est le signal pour lever la contrainte.

⚠️ La CI iOS ne surveille encore que `ios/` : un rendu téléversé ou renommé
seul — c'est ainsi que le repli est arrivé — ne lance pas ces tests. Après
tout changement du dossier, `make test-modules` dans `ios/`.

## À l'écran

L'aperçu remplace, en tête de l'écran, les deux pages qui y flottaient
(`BookCustomisationPreviewView`). Décisions du 02/10/2026 (Hugo) :

- **Toujours l'aperçu**, même quand un carnet a déjà été composé : c'est lui qui
  suit les réglages, les vraies pages ne changeraient qu'à la composition
  suivante. Elles restent dans l'aperçu du carnet.
- **La place est réservée** : le bloc garde la taille des deux pages d'avant
  (358 × 280), image ou pas. Rien ne saute sous lui.
- **Le papier nu, puis un fondu.** Tant que la première image n'est pas là, les
  deux pages blanches d'avant ; à l'échec, elles restent, sans message, et
  l'image est redemandée au réglage suivant ou à la prochaine ouverture.
  **L'image d'avant reste affichée** tant que la suivante n'est pas prête.

À l'ouverture, l'aperçu par défaut arrive **sans attente**. Ensuite, un réglage
doit tenir 300 ms avant que l'image le suive : un curseur qu'on fait glisser
change de valeur à chaque cran, et l'image ne suit que le cran où il s'arrête.
L'adresse de l'image ne dépend que des cinq propriétés : le nombre de pages, le
quiz, les zones libres et le mot fléché ne la changent pas, et rien ne se
recharge. Les réglages partent au serveur **un par un, en file**
(`BookCustomisationModel`) : la réponse à un geste sur le quiz ne peut plus
défaire un réglage d'aperçu envoyé juste avant, ce qui faisait bouger l'image.
Le repli s'affiche comme n'importe quel aperçu.

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
Et, si sa remise dans le rang échoue, pour un carnet d'avant la contrainte,
jusqu'à la prochaine ouverture de l'écran (voir plus haut).

Le lot du 02/10/2026 a réglé ce qui manquait : les douze fichiers autrefois
suffixés `-1` étaient mal nommés — ils portent les pointillés éteints, et non
allumés — et ont été renommés en `Pointillés=off`. Ils comblent précisément les
douze combinaisons qui tombaient sur le repli. Plus aucun fichier du dossier ne
porte de suffixe numérique.
