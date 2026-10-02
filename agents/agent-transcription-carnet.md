# Les textes du carnet entier — règles en attente d'un agent

> Ces règles faisaient partie de `agent-transcription.md` jusqu'au 02/10/2026.
> Elles en sont sorties parce que **la rédaction ne les applique pas** : elle
> écrit une étape à la fois, et ne produit ni quiz, ni question du jour, ni mot
> fléché, ni intro, ni quatrième de couverture, ni chiffres du voyage. Les
> garder dans son prompt lui faisait relire, à chaque étape, plusieurs pages de
> consignes sans objet — et diluait celles qui comptent.
>
> **Aucun agent ne charge ce fichier aujourd'hui.** Il reviendra dans le prompt
> de celui qui écrira ces textes, le jour où il existera.

---

## 1. Les blocs à remplir (`prompt`, `quiz`)

Quand une page garde du blanc, la mise en page y pose un champ à remplir à la
main (`prompt`) ou un petit jeu (`quiz`) — jamais du décor. **Le texte de ces
blocs ne s'invente pas en mise en page** : l'Agent Mise en page les place, il
ne les écrit pas.

`prompt` imprime un intitulé suivi de **trois lignes réglées**.

| Bloc | Ce que l'agent écrit | Champ | Réglage |
|---|---|---|---|
| **Question du jour** | Une demande courte, liée à ce que le voyageur vient de raconter | `prompt` | — |
| **Quiz** | Une question sur le voyage, deux à quatre propositions, et la réponse, imprimée à l'envers | `quiz` | « Quiz intégrés à l'histoire », ON par défaut. À OFF, aucun quiz |

Règles communes :

- La question porte sur **le voyage raconté**, jamais sur un sujet générique.
- Un intitulé, une ligne, pas de consigne à tiroirs.
- Un quiz ne **donne jamais sa réponse** dans le récit de la même page.
- **Une couleur se nomme toujours en toutes lettres** — « en bleu », « à
  l'orange ». Jamais une pastille, jamais la seule couleur d'un mot : un lecteur
  daltonien, une photocopie ou une impression en noir et blanc perdraient
  l'information.

**Les mots du voyage.** Le carnet peut se terminer par une grille de **mot
fléché**, générée au moment de la commande à partir des récits (réglage « Mot
fléché à la fin du livre », ON par défaut). Elle se nourrit de **huit à douze
mots** — lieux, plats, prénoms, objets récurrents — chacun avec une définition
d'une ligne, courte et sans article, comme le veut le genre.

---

## 2. Les calculs du voyage

Le carnet donne, au moins une fois, la mesure du voyage dans son ensemble. C'est
le chiffre qu'on cite à table en montrant le livre.

### Ce qu'on calcule

- **Durée** : nombre de jours, de nuits, de semaines.
- **Géographie** : pays, régions, villes, étapes, fuseaux horaires traversés, décalage horaire cumulé.
- **Distances** : total parcouru, et le détail par mode (avion, train, bus, bateau, voiture, vélo, marche).
- **Temps de trajet cumulé**, par mode.
- **Relief** : altitude maximale atteinte, dénivelé cumulé — uniquement en randonnée et si les données existent.
- **Le carnet lui-même** : nombre de souvenirs enregistrés, durée totale d'audio, nombre de photos retenues.
- **Comparaisons d'échelle** : « l'équivalent d'un Paris–Le Caire », « un dixième du tour de la Terre ».

### Comment on calcule

1. **Ne calculer qu'à partir du connu** : les étapes réellement citées, les dates réellement données.
2. **Distances** : à vol d'oiseau entre les points d'étape, sauf pour la route et la marche, où l'on prend l'itinéraire réel s'il est connu. **Dire lequel** quand ce n'est pas évident.
3. **Arrondir** : au kilomètre sous 100 km, à la dizaine sous 1 000 km, à la centaine au-delà.
4. **Marquer l'estimation** : « environ », « près de », « un peu plus de ». Un chiffre nu est un chiffre garanti.
5. **Expliciter le périmètre** quand il y a un doute : « hors trajets locaux », « vols compris ».
6. **Jamais d'argent estimé.** Un budget ne s'écrit que si le voyageur a donné les montants.
7. **Une seule unité par chiffre**, et pas d'addition de choux et de carottes.

**Les chiffres du carnet sont recalculés à la génération finale, jamais recopiés
d'une version antérieure.** Contrôle avant livraison : la somme des étapes = le
total annoncé ; le nombre de jours = l'écart entre la première et la dernière
date ; le nombre de pays = ceux réellement cités dans les `days[]`.

### Où ça s'affiche

Dans `intro_text`, dans `back_cover`, ou dans un `fun_facts` intitulé
« Chiffres clés ». **Ne pas produire `global_stats`** : le champ est accepté par
le schéma mais n'est rendu par aucun layout — le calcul disparaîtrait
silencieusement. Voir `MemoBook Generator/templates/travel-journal/LAYOUT_KB.md`.

---

## 3. Les textes adressés au lecteur

Dédicace, quatrième de couverture, intro : ce sont les seuls textes du carnet
qui **s'adressent** à quelqu'un. Ce que le protocole français (*Guide du
protocole et des usages*, Jacques Gandouin) en retient :

1. **L'appellation prime sur le nom.** Madame, Monsieur, jamais suivis du patronyme quand on s'adresse à quelqu'un.
2. **Les préséances déterminent l'ordre d'énumération** : dames d'abord, aînés d'abord, invités avant les hôtes — sauf si le voyageur nomme toujours dans un autre ordre. Vaut pour `authors` et les légendes.
3. **Une formule ne se termine jamais tronquée.** « Cordialement » sec et « Au plaisir » sont proscrits.
4. **La sobriété est la marque du bon usage.** Pas de superlatif en cascade, pas de familiarité avec le lecteur.

| Limite | |
|---|---|
| `intro_text` | 700 caractères par paragraphe, 3 paragraphes |
| `highlights[]` | 80 caractères |
| `tag` | trois mots maximum |
