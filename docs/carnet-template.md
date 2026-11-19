# Le carnet template — ce qu'il faudrait pour le vendre

> T271, Hugo, 05/11/2026 : « Commander un carnet template (façon Nature &
> Découvertes ou UnikJournal) depuis la page d'inscription, l'accueil, et le
> bas de l'accueil d'un voyage — au cas où les utilisateurs en ont marre de
> remplir dans l'app. Commande dans l'app, rapide : choix de la 1re et de la
> 4e de couverture, et du pack de stickers associé. »

Cette fiche dit **ce qui existe**, **ce qui manque**, et **ce qui est une
décision plutôt qu'un écran**. Écrite le 19/11/2026, avant toute ligne de code :
le ticket demande de vendre un objet qui n'existe pas encore, et un bouton
« Commander » qui prend un paiement pour un carnet qu'on ne sait pas expédier
serait la pire façon de commencer.

## 1. Ce que c'est, et en quoi c'est un autre produit

Le carnet que MemoBook vend aujourd'hui est **composé** : il naît d'un voyage
raconté, ses pages sont mises en page à partir des souvenirs, et son prix
dépend du nombre de pages. Le carnet template est l'inverse : un **objet vierge,
fabriqué d'avance**, qu'on achète pour écrire soi-même. Il n'a ni voyage, ni
rendu, ni nombre de pages variable.

C'est ce renversement qui fait tout le travail ci-dessous.

## 2. Ce qui existe déjà, et qui resservira

| Pièce | Où | Ce qu'elle donne |
|---|---|---|
| Le tunnel de commande | `MemoBookFeature/Order/`, `MemoBookCore/PrintOrderFlow.swift` | Sept étapes — démarrage, livraison, exemplaires, rapidité, récapitulatif, paiement, confirmation —, leur dessin, leurs états et leurs tests |
| L'adresse de livraison | `print_orders.shipping*`, `BrandCountryField` | Le formulaire, les pays servis par le serveur, la reprise depuis le profil |
| Le paiement | `docs/paiements.md`, Stripe, Apple Pay | L'encaissement, les webhooks, les remboursements, le rejeu inoffensif |
| Les e-mails | `docs/emails.md` | Confirmation de commande, expédition |
| Le choix d'une couverture | `routes/covers.ts`, l'atelier de personnalisation | Le dessin d'un choix de 1re et de 4e, mais **pour un carnet composé** |

## 3. Ce qui manque — et ce n'est pas du code

**Aucune de ces quatre lignes ne se code tant qu'elle n'est pas décidée.**

1. **Le produit lui-même.** Il n'existe pas. T272 le dit : il faut trouver un
   imprimeur, faire designer les couvertures, en imprimer cent et les vendre.
   Tant qu'il n'y a pas de carnet en stock, « Commander » ment.
2. **Le prix.** La grille actuelle (`services/printPricing.ts`) est **par
   palier de pages** : elle n'a rien à dire d'un carnet vierge. Il faut un prix
   à l'unité, et savoir ce qu'il couvre (livraison comprise ou non, comme pour
   le carnet composé).
3. **Le catalogue.** « Choix de la 1re et de la 4e de couverture » suppose une
   liste de couvertures qui existent en vrai — pas les propositions tirées des
   photos d'un voyage. Idem pour les **packs de stickers** : aujourd'hui, un
   sticker est une découpe faite dans **une photo du voyageur**
   (`routes/tripStickers.ts`), pas un article de catalogue.
4. **L'expédition.** Une commande payée reste en `submitted` jusqu'à ce qu'un
   humain la traite (`docs/paiements.md` § Ce qui n'existe pas encore). Pour le
   carnet composé, c'est tenable le temps des premières commandes ; pour un
   article qu'on vend à des gens qui n'ont pas encore de carnet, ça se voit
   tout de suite.

## 4. L'obstacle de structure, à connaître avant de dessiner

`print_orders` **exige** un carnet et un rendu :

```prisma
memoId   String
renderId String
render   Render @relation(..., onDelete: Restrict)
```

Un carnet template n'a ni l'un ni l'autre. Deux chemins, et ils n'ont pas le
même coût :

- **Un type de commande à part** — `product` sur `print_orders`, `memoId` et
  `renderId` rendus optionnels, et tout ce qui les lit (le paiement, les
  e-mails, la page de suivi, la suppression de compte) revu pour accepter
  l'absence. C'est la voie propre, et elle touche du code qui encaisse de
  l'argent.
- **Une table à elle** — `product_orders`, qui partage l'adresse, le paiement
  et les e-mails sans rien devoir à un voyage. Plus de surface, mais aucune
  route d'argent existante n'est modifiée.

⚠️ Ce qu'il ne faut **pas** faire : fabriquer un faux carnet et un faux rendu
pour faire entrer le template dans le tunnel. La base dirait que quelqu'un a
commandé un voyage qu'il n'a jamais raconté, et tout ce qui compte les carnets
— les chiffres de l'accueil, les statistiques, la suppression de compte —
mentirait avec elle.

## 5. Ce qui n'est pas dans ce dépôt

Les **pages d'atterrissage**, la **home** et la page **tarifs** sont sur
Webflow. Rien de ce qui les concerne ne s'écrit ici ; ce dépôt ne peut servir
que les images et les textes, s'il le faut.

## 6. Le découpage proposé

1. **Décider** (Hugo) : le produit, son prix, qui l'imprime, combien de
   couvertures et quels packs de stickers. Sans ça, rien.
2. **Le catalogue**, côté serveur : les couvertures et les packs comme
   **articles**, avec leurs images et leur disponibilité. C'est la première
   chose qui se code, et elle ne dépend que de la décision 1.
3. **La commande** : le chemin de données choisi au § 4, puis le tunnel —
   quatre étapes suffiraient (choix, livraison, paiement, confirmation), les
   exemplaires et la rapidité se reprenant tels quels.
4. **Les entrées** : l'inscription, l'accueil, le bas de l'accueil d'un voyage.
   Elles arrivent **en dernier** : ce sont elles qui promettent, et elles ne
   doivent promettre qu'une fois le reste debout.

## 7. Ce que ça veut dire pour le ticket

T271 n'est pas bloqué par de la technique : il est bloqué par **quatre
décisions produit**, dont trois tiennent à un objet physique qui n'existe pas
encore. Le jour où elles tombent, le § 6 se code dans l'ordre — et les pièces
du § 2 font que la commande elle-même n'est pas le plus long.
