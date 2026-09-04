# Icônes de marque MemoBook

Le jeu d'icônes de l'interface. **35 icônes, deux variantes chacune**, toutes
dessinées sur une grille de 24 × 24.

> Ce dossier est la **source**. Ce que l'app embarque vit dans
> `ios/Modules/Sources/MemoBookDesign/Resources/MemoBookAssets.xcassets`, importé
> depuis ici — voir « Importer dans l'app » plus bas.

## Les deux variantes

| Fichier | Couleurs | Emploi |
|---|---|---|
| `Nom.svg` | un seul tracé, `#2D231A` (*Brand Colors/Black*) | **Le cas courant.** Icône d'interface, dans un bouton, une ligne, une barre |
| `Nom 2.svg` | tracé sombre + aplat `#AFD2F0` (*Brand Colors/Blue*) | Icône **mise en avant** : une seule par écran, là où le regard doit se poser |

La monochrome est celle qui se **teinte** : un seul tracé plein, elle supporte
`renderingMode(.template)` et prend la couleur du contexte — blanc sur un CTA
vert, encre sur une carte blanche. La bichrome, elle, porte ses couleurs :
la teinter la réduirait à une silhouette pleine et lui ferait perdre son aplat.

## Nommage dans l'app

| Source | Asset | Accès |
|---|---|---|
| `Printer.svg` | `IconPrinter` | `Image(brand: "IconPrinter")` |
| `Printer 2.svg` | `IconPrinterDuo` | `Image(brand: "IconPrinterDuo")` |
| `Picture Frame.svg` | `IconPictureFrame` | espaces et tirets retirés, chaque mot capitalisé |

## Le jeu complet

**Navigation** — `Arrow` `Cross` `Exit` `Menu Burger` `House` `View`
**Carnet** — `Book` `Book Simple` `PDF` `Pen` `Picture Frame` `Printer`
**Capture** — `Mic` `Ringtone` `Import` `Export` `Plus` `Plus Outlined`
**Commande** — `Cart` `Cart Pending` `Deliver`
**Compte** — `User` `Settings` `Locker` `Locker Outlined` `Locker checked`
**Divers** — `Globe` `Link` `Magnifier` `Mountain` `Question` `Star` `Trash`
`Desktop PC Checked` `Desktop PC Checked-1`

### Ce qui manque

Deux pictogrammes employés sur l'accueil n'ont pas d'équivalent ici, et restent
sur un symbole système en attendant : un **calendrier** (durée d'un voyage) et
un **tracé d'itinéraire** (distance parcourue). Ils sont regroupés dans
`TripStatItem.Kind.icon` — un seul endroit à changer le jour où ils arrivent.

## Ne pas confondre avec les illustrations du *Welcome*

`WelcomeMic`, `WelcomePhoto` et `WelcomeBook` **ne font pas partie de ce jeu**.
Ce sont trois illustrations dessinées pour les cartes de l'écran d'accueil, avec
leurs proportions propres (23 × 30, 33 × 26, 25 × 24) et leur aplat bleu déjà
dans le SVG. D'où leur préfixe : elles ne suivent pas la grille de 24 et ne se
teintent pas.

## Importer dans l'app

Après avoir ajouté ou remplacé un SVG ici :

```bash
python3 ios/Tools/import-brand-icons.py
```

Le script recopie chaque SVG dans un `.imageset` du catalogue, avec
`preserves-vector-representation` — l'icône reste vectorielle et ne pixellise
pas quand le Dynamic Type l'agrandit.

⚠️ Retirer `preserveAspectRatio="none"` des exports Figma avant l'import, sinon
Xcode déforme l'icône.
