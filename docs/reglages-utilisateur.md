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

⚠️ **« Exister » n'est pas « être rendu ».** Les onze modales du lot 7 rendent
*réglables* des valeurs que la table ci-dessous marque encore « à construire » —
pointillés, typographies — les quatre, chacune sa feuille depuis le 16/09/2026 —,
zones libres, mot fléché. Elles sont bien dans le gabarit et bien enregistrées en base ; c'est leur **effet sur la page** qui
manque. L'app tient donc sa moitié du contrat, et la colonne « État » de la
table du gabarit reste la seule à dire ce qui se voit vraiment dans le carnet.

---

## Écran « Paramètres du voyage »

Tous ne concernent pas les agents. Ceux qui les concernent :

| Réglage | Valeur de maquette | Ce que ça change dans la chaîne |
|---|---|---|
| **Nom de l'aventure** | « Rome 2026 » | `book_title` en couverture |
| **Dates du voyage** | 26 août – 15 sept 2026 | `date_range`, bandeaux de journée, calculs du § 6 de la rédaction |
| **Rythme du récit** | Tous les 2 jours | La cadence des relances, donc la granularité naturelle des étapes. Cinq valeurs depuis le lot 7 (`NarrationPace`) : tous les jours, tous les 2 jours, tous les 3 jours, une fois par semaine, personnalisé |
| **Notifications** (les quatre alertes) | Toutes actives | Rien pour les agents — ce sont des relances, pas du contenu. Réglées une par une depuis « Gérer mes notifications » (`memos.notify*`), sous l'interrupteur maître du voyage |
| **Collaborateurs** | @clara_prn, @ana.prn | Plusieurs voix entrent dans le même carnet : la fiche de cohérence doit les unifier en une seule (§ 2 de la rédaction). Le **rôle** de chacun (« Ton pote d'enfance ») est déduit par la rédaction au bout de quelques récits et posé sur `memo_members.role` — personne ne le saisit |
| **Thème de l'aventure** | City trip & découvertes | Oriente le registre des encarts et le vocabulaire du carnet |
| **Style du carnet** | Pointillés, cadres, etc. | Le fichier de `agents/carnet-styles/` appliqué de bout en bout |
| **Partager sur la galerie** | Désactivé | Un carnet public passe une modération plus stricte (→ Agent Modération) |
| **Ma cagnotte** · **Tricount** | 67,88 € | Une dépense est une **métadonnée vérifiable** : elle situe une date et un lieu. Elle ne raconte rien — le souvenir doit venir du voyageur |
| **Limites de souvenirs** | 312 / 2 000 | Rien pour les agents, et c'est le but : c'est un **garde-fou de coût**, pas un réglage de contenu. Voir plus bas |

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
| **Typographies** | Quatre **assortiments** — voir plus bas | Carnet de voyage | Gabarit — `--mb-font-display`, `--mb-font-title`, `--mb-font-hand`, et `--mb-font-facts` à créer | À construire. Les quatre colonnes existent en base ; le gabarit ne les lit pas encore |
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

## Les trois assortiments de typographies

**On ne choisit plus police par police** (Hugo, 16/09/2026). L'écran posait
quatre lignes — titres, sous-titres, textes, fun facts — et laissait marier
librement trois familles sur chacune : des dizaines de combinaisons, dont la
plupart sont laides, sur un objet qu'on imprime et qui ne se rattrape pas.

Trois assortiments, donc, chacun cohérent de bout en bout — il y en avait
quatre, « Moderne » (titres Montserrat) est retiré le 18/09/2026 (Hugo) ; un
carnet réglé dessus garde ses polices et se lit « Personnalisé ». La feuille écrit en
face de chaque police **ce qu'elle habille** : c'est la seule information qui
permet de choisir sans connaître la typographie.

| Assortiment | Titres | Sous-titres | Textes | Fun facts & autres |
|---|---|---|---|---|
| **Carnet de voyage** (défaut) | Playfair | Hansley | Gloria Hallelujah | Playfair |
| **Éditorial** | Playfair | Playfair | Alegreya | Alegreya |
| **Manuscrit** | Hansley | Hansley | Gloria Hallelujah | Gloria Hallelujah |

Le défaut est **exactement** le jeu que la base pose déjà : un carnet réglé
avant que cette feuille existe s'y reconnaît sans qu'on touche à quoi que ce
soit. Un carnet composé police par police qui n'entre dans aucune des trois
cases s'affiche « Personnalisé » — on ne coche pas de force.

⚠️ **Une famille n'est pas dans le gabarit.** `fonts.css` n'inline que
Playfair Display et Gloria Hallelujah ; Hansley est versionné sans être inliné,
Alegreya n'est pas là du tout. Rien n'échoue — la page retombe sur une police
système —, mais « Éditorial » ne s'imprimera vraiment qu'une fois cette face
ajoutée à `build-font-css.ts`.

---

## Les limites de souvenirs

**Ce n'est pas le quota d'étapes offertes.** Celui-là est le palier d'entrée :
trois étapes, une fois, puis l'abonnement. Les limites de souvenirs sont le
budget **hebdomadaire** de quelqu'un qui raconte déjà — elles se rechargent, et
se relèvent contre 3,99 €/semaine.

| | Compris | Étendu |
|---|---|---|
| Par semaine | 2 000 souvenirs | 8 000 souvenirs |
| Prix | inclus dans l'abonnement | 3,99 €/semaine |

**La semaine, parce que tout le produit est à la semaine** (Hugo, 17/09/2026) :
l'abonnement se facture ainsi, un voyage se compte ainsi, et l'extension est une
**option du même produit** — pas une seconde offre. Elle vit d'ailleurs sous le
même produit Stripe.

Le barème, et lui seul, décide de ce que chaque geste consomme :

| Geste | Coût |
|---|---|
| Un message écrit | 1 souvenir |
| Une **minute entamée** de vocal | 10 souvenirs |
| Une photo | rien |

**Un vocal coûte plus cher parce qu'il coûte plus cher** : transcription,
rédaction, relecture. Une photo ne passe par aucune des trois. La minute est
*entamée* et non écoulée — c'est la règle la plus facile à expliquer, et la
seule qui ne récompense pas le découpage d'un vocal en morceaux de 59 secondes.

**Elles ne se voient que dans les paramètres du voyage**, et la ligne reste
muette tant qu'il reste de la marge : la jauge n'apparaît qu'à 80 %. Cette
limite est un garde-fou contre l'usage qui coûterait plus cher que
l'abonnement, pas un levier commercial — quelqu'un qui raconte normalement ne
doit jamais la voir bouger.

Le compte est vite fait : 2 000 souvenirs par semaine, c'est **200 minutes de
vocal**, soit près de 30 minutes par jour. Un voyageur bavard qui raconte
20 minutes quotidiennes en consomme 1 400. La limite ne mord pas.

⚠️ **Le mot « jeton » — et le mot « token » — n'apparaissent nulle part dans
l'app.** L'unité s'appelle un souvenir, et l'app compte en souvenirs.

⚠️ Le barème est un **ordre de grandeur, pas une mesure** : il est à réétalonner
sur les factures OpenAI et Anthropic d'un mois plein. Les deux constantes vivent
dans `backend/src/services/memoryAllowance.ts`, et voyagent jusqu'à l'app — qui
n'en écrit aucune.

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
   `.woff2` —, **ajouter Alegreya et Montserrat**, que deux des quatre
   assortiments emploient, et créer le token `--mb-font-facts`.
3. **Les zones libres** : bloc de fin d'étape, et pages blanches de fin de carnet.
4. **Le mot fléché** : grille générée à la commande à partir des mots du voyage.
5. **La carte postale automatique** : repoussée, mais toujours demandée par deux
   foyers du panel sur trois.

**Attention aux textes déjà relus.** Changer un réglage qui touche l'écriture
relance la rédaction. Or le texte corrigé au clavier par le voyageur fait
autorité et ne se réécrit jamais : il faut exclure les étapes déjà validées, ou
prévenir explicitement avant de régénérer.
