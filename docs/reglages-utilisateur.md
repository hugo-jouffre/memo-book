# Réglages du voyageur

> Ce que l'utilisateur peut régler, ce qu'il ne peut pas, et qui applique quoi.
>
> **Les maquettes Figma font foi** pour les libellés et les valeurs par défaut :
> écrans *Paramètres du voyage* et *Personnalisations*. Ce fichier dit ce que
> chaque réglage change dans la chaîne — rédaction, mise en page, gabarit — et
> ce qui reste à construire pour qu'il fonctionne réellement.

## Deux écrans, deux portées

| Écran | Portée | Quand ça se règle |
|---|---|---|
| **Paramètres du voyage** | Le voyage : son nom, ses dates, qui y participe, à quel rythme on raconte | Pendant le voyage, à tout moment |
| **Personnalisations** | Le carnet : ce que la page montre et comment elle est composée | Jusqu'à la génération du carnet |

**Règle de survie.** Aucun réglage n'est exposé dans l'app avant d'exister dans
`templates/travel-journal/LAYOUT_KB.md`. Un drapeau que le gabarit ne connaît
pas est ignoré en silence : l'utilisateur croirait avoir réglé quelque chose.

---

## Écran « Paramètres du voyage »

Tous ne concernent pas les agents. Ceux qui les concernent :

| Réglage | Valeur de maquette | Ce que ça change dans la chaîne |
|---|---|---|
| **Nom de l'aventure** | « Rome 2026 » | `book_title` en couverture |
| **Dates du voyage** | 26 août – 15 sept 2026 | `date_range`, bandeaux de journée, calculs du § 6 de la rédaction |
| **Rythme du récit** | Tous les 2 jours | La cadence des relances, donc la granularité naturelle des étapes |
| **Collaborateurs** | @clara_prn, @ana.prn | Plusieurs voix entrent dans le même carnet : la fiche de cohérence doit les unifier en une seule (§ 2 de la rédaction) |
| **Thème de l'aventure** | City trip & découvertes | Oriente le registre des encarts et le vocabulaire du carnet |
| **Style du carnet** | Pointillés, cadres, etc. | Le fichier de `agents/carnet-styles/` appliqué de bout en bout |
| **Partager sur la galerie** | Désactivé | Un carnet public passe une modération plus stricte (→ Agent Modération) |
| **Ma cagnotte** · **Tricount** | 67,88 € | Une dépense est une **métadonnée vérifiable** : elle situe une date et un lieu. Elle ne raconte rien — le souvenir doit venir du voyageur |

---

## Écran « Personnalisations »

| Réglage | Valeurs | Défaut | Qui l'applique | État |
|---|---|---|---|---|
| **Couvertures (1re & 4e)** | Aperçu et personnalisation | — | Mise en page | Partiel : `cover_photo` et `back_cover` existent, l'éditeur non |
| **Ratio photo / texte** | Échelle à arrêter | 50/50 | Mise en page — choix des layouts et fréquence des `layout_photo_page` | Rendu, via le catalogue de layouts |
| **Nombre de page cible** | Échelle à arrêter | 60 pages | Rédaction — niveau de détail des textes · Mise en page — regroupement des étapes | Rendu côté agents, sans garde-fou automatique |
| **Fun facts** | ON / OFF | ON | Rédaction les écrit, mise en page les place | Rendu (`fun_facts`) |
| **Pointillés** | ON / OFF | ON | Gabarit (`.mb-note__rules`) | À construire : un booléen dans le payload |
| **Décorations & stickers** | 0 · 1 · 2 · 3 · 4 par paragraphe ou par image | 2 | Mise en page | Partiel : seul le scotch est rendu, les stickers ne le sont pas |
| **Typographie des titres** | Liste fermée | Playfair | Gabarit — `--mb-font-display` | À construire |
| **Typographie des sous-titres** | Liste fermée | Hansley | Gabarit — `--mb-font-title` | À construire. `Hansley.otf` est versionné, mais pas encore inliné : le titre retombe sur Gloria Hallelujah |
| **Typographie des textes** | Liste fermée | Gloria Hallelujah | Gabarit — `--mb-font-hand` | À construire |
| **Typographie des fun facts** | Liste fermée | Playfair | Gabarit — pas de token dédié aujourd'hui | À construire : ajouter `--mb-font-facts` |
| **Quiz intégrés à l'histoire** | ON / OFF | ON | Rédaction les écrit, mise en page les place | Rendu (`quiz`) |
| **Zones libres** | ON / OFF | ON | Mise en page | À construire : une zone blanche en fin d'étape, trois pages blanches en fin de carnet |
| **Mot fléché à la fin du livre** | ON / OFF | ON | Rédaction fournit les mots, la grille se génère à la commande | À construire |

### Ce que chaque réglage veut dire, précisément

- **Fun facts.** À OFF, aucun encart, nulle part. À ON, **un encart toutes les
  trois à quatre pages**, et seulement si le fait passe le seuil de pertinence :
  le réglage autorise, il n'oblige pas. Une page sans encart reste normale.
- **Pointillés.** La réglure du papier, sous le texte. À OFF, la page reste
  blanche sous le récit ; le rythme vertical, lui, ne change pas.
- **Décorations & stickers.** La quantité n'est plus un jugement de l'agent :
  elle est réglée par le voyageur. **Le scotch des photos compte dans le
  quota.** À 0, aucun décor — et la page se remplit autrement, ou pas du tout.
- **Typographies.** Quatre axes indépendants. L'agent n'en substitue jamais
  aucune, même s'il juge une page trop dense. Seules les polices réellement
  embarquées dans `templates/travel-journal/assets/fonts/` peuvent être
  proposées dans la liste.
- **Quiz.** Un seul bloc interactif par page, et il remplace la zone flottante
  du bas. À OFF, l'agent n'en produit aucun.
- **Zones libres.** Une zone blanche à la fin de chaque étape, pour écrire ou
  dessiner à la main, et trois pages blanches à la fin du carnet. C'est aussi
  la réponse à « je ne dessine pas » : la zone n'impose rien, elle laisse la
  place.
- **Mot fléché.** Généré au moment de la commande, à partir des récits, et placé
  en fin de carnet. La rédaction n'écrit pas la grille : elle tient dans la fiche
  de cohérence les huit à douze mots du voyage et leurs définitions.

---

## Ce qui n'est pas réglable

Ces points sont arbitrés une fois pour toutes. Les ouvrir reviendrait à demander
au voyageur d'arbitrer un défaut qu'il n'a pas produit.

| Point | La règle | Pourquoi |
|---|---|---|
| **Voix du récit** | Celle que le voyageur emploie le plus, uniformisée sur tout le carnet | Ce n'est pas un goût mais un relevé. « Je » ou « on » se déduit de ses vocaux, et se fige dans la fiche de cohérence |
| **Niveau de lissage** | Fidèle au récit, intégralement corrigé, retravaillé pour se lire | Un vocal est très oral ; un carnet imprimé se lit. Ce peaufinage est le cœur du savoir-faire MemoBook, il s'affine avec le temps — il ne se désactive pas |
| **Bandeau de journée** | L'agent décide ce qu'il porte ; la météo reste rare | Le panel préfère le gîte et les hôtes. Un réglage de plus pour un bandeau de quatre champs ne se justifie pas |
| **Rose, épine, graine** | Demandé dans le chat, pas imprimé comme bloc à remplir | La réponse devient de la matière de récit. Une question posée à froid sur le papier n'obtient rien |
| **Mention « généré par IA »** | Toujours imprimée dès qu'un élément vient de la machine | Engagement de transparence, demandé explicitement par les lecteurs |
| **Nom des couleurs écrit** | Toujours en toutes lettres | Accessibilité : une consigne portée par la seule couleur disparaît pour un lecteur daltonien, sur une photocopie, en noir et blanc |
| **Qualité du français** | Les règles du § 7 de la rédaction | Un carnet imprimé ne se corrige plus |
| **Absence de doublon** | Jamais deux fois le même encart, ni deux du même registre | Ce n'est pas un style, c'est un défaut visible en feuilletant |
| **Fidélité au récit** | Rien d'inventé, jamais | C'est ce qui distingue le carnet d'un texte générique |

---

## Ce qu'il reste à construire

1. **Un objet de réglages dans le payload**, décrit dans `LAYOUT_KB.md` et validé
   par `gpt_image_schema.yaml`, puis lu par le gabarit : pointillés, quatre
   polices, quota de décor.
2. **Les polices** : inliner Hansley — le fichier est versionné, mais
   `build-font-css.ts` ne connaît que les deux familles Google et ne lit que des
   `.woff2` — puis faire de même pour toute face ajoutée à la liste, et créer le
   token `--mb-font-facts`.
3. **Les zones libres** : bloc de fin d'étape, et pages blanches de fin de carnet.
4. **Le mot fléché** : grille générée à la commande à partir des mots du voyage.
5. **La carte postale automatique** : repoussée, mais toujours demandée par deux
   foyers du panel sur trois.

**Attention aux textes déjà relus.** Changer un réglage qui touche l'écriture
relance la rédaction. Or le texte corrigé au clavier par le voyageur fait
autorité et ne se réécrit jamais : il faut exclure les étapes déjà validées, ou
prévenir explicitement avant de régénérer.
