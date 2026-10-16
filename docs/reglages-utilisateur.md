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
`MemoBook Generator/templates/travel-journal/LAYOUT_KB.md`. Un drapeau que le gabarit ne connaît
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
| **Dates du voyage** | 26 août – 15 sept 2026 | `date_range`, bandeaux de journée, calculs du voyage (`agent-transcription-carnet.md` § 2 — appliqués par aucun agent aujourd'hui) |
| **Rythme du récit** | Tous les 2 jours | La cadence des relances (`notifications.md` § 2 : c'est aussi la fréquence déclarée qui fixe le rythme des notifications), donc la granularité naturelle des étapes. Cinq valeurs depuis le lot 7 (`NarrationPace`) : tous les jours, tous les 2 jours, tous les 3 jours, une fois par semaine, personnalisé |
| **Notifications** (les quatre alertes) | Toutes actives | Rien pour les agents — ce sont des relances, pas du contenu. Réglées une par une depuis « Gérer mes notifications » (`memos.notify*`), sous l'interrupteur maître du voyage. Le serveur en lit deux : « Rappel d'écriture » (la relance d'un carnet arrêté) et « Rappel de fin de voyage » (la fin du voyage, le carnet pas commandé). Voir [`notifications.md`](notifications.md) |
| **Collaborateurs** | @clara_prn, @ana.prn | Plusieurs voix entrent dans le même carnet : la fiche de cohérence doit les unifier en une seule (§ 3 de la rédaction). Le **rôle** de chacun (« Ton pote d'enfance ») devait être déduit par la rédaction au bout de quelques récits et posé sur `memo_members.role` — elle ne le fait pas encore (constaté le 02/10/2026) |
| **Thème de l'aventure** | City trip & découvertes | Oriente le registre des encarts et le vocabulaire du carnet |
| **Style du carnet** | Pointillés, cadres, etc. | Le fichier de `agents/carnet-styles/` appliqué de bout en bout |
| **Partager sur la galerie** | Désactivé | Un carnet public passe une modération plus stricte (→ Agent Modération) |
| **Tricount** (la ligne « Ma cagnotte » est retirée le 06/10/2026) | Relier Tricount | Une dépense est une **métadonnée vérifiable** : elle situe une date et un lieu. Elle ne raconte rien — le souvenir doit venir du voyageur |
| **Crédit du jour** | 3 min 20 / 5 min · « Illimité » pour un abonné | Rien pour les agents : ce n'est pas un réglage de contenu, c'est ce que le voyage peut encore raconter aujourd'hui — et le levier de l'abonnement. Voir plus bas |

---

## Écran « Personnalisations »

| Réglage | Valeurs | Défaut | Qui l'applique | État |
|---|---|---|---|---|
| **Couvertures (1re & 4e)** | Aperçu et personnalisation | — | Mise en page | Partiel : `cover_photo` et `back_cover` existent, l'éditeur non |
| **Ratio photo / texte** | 0 · 25 · 50 · 75 · 100 % | 50 % | Mise en page — le nombre de photos de chaque étape (`photoRatio.ts`), mises en page par le composeur de l'atelier, le même dans l'atelier et l'app (`bookComposer.ts`) | Rendu, les cinq paliers. Détail et cas limites : **`docs/ratio-texte-photo.md`** |
| **Nombre de page cible** | Compact · Par défaut · Détaillé · Personnalisé (30 à 180) | Par défaut — 60 pages sans date de fin | Rédaction — la taille des étapes (`services/pageTarget.ts`, ligne de consigne de `redaction.ts`) · Mise en page — les planches de photos (`recalerSurLaCible`, `mise-en-page.js`), la même dans l'atelier et l'app | Rendu : la rédaction règle la densité, deux changements par voyage une fois le récit commencé ; la composition recale le carnet sur la cible à ± 5 pages par ses planches de photos, quand les photos le permettent (15/10/2026) |
| **Fun facts** | ON / OFF | ON | Rédaction les écrit, mise en page les place | Rendu (`fun_facts`) — OFF : aucun encart, dans l'atelier comme dans l'app |
| **Pointillés** | ON / OFF | ON | Gabarit (`.mb-note__rules`) | Rendu : `rules_enabled` dans le payload |
| **Décorations & stickers** | 0 · 1 · 2 · 3 · 4 par étape | 2 | Mise en page | Rendu : les stickers de la bibliothèque dessinée (44 dessins importés de Notion, `assets/stickers/`), liés au récit puis complétés par des dessins de voyage, **autant par étape que le réglage** (14/10/2026 ; le curseur de l'app le dit : « Quantité de décorations par étape »), et le tracé pointillé ; à 0, ni l'un ni l'autre. Le scotch des photos n'en dépend plus (12/10/2026) |
| **Typographies** | Trois **assortiments** — voir plus bas | Carnet de voyage | Gabarit — `--mb-font-display`, `--mb-font-title`, `--mb-font-hand` | **V1 : « Carnet de voyage » seul** (Hugo, 09/10/2026) — Éditorial et Manuscrit restent sur la feuille, pâlis, « À venir ». Les sous-titres tombent sur Gloria Hallelujah tant que Hansley n'est pas inlinée (licence à vérifier) |
| **Quiz intégrés à l'histoire** | ON / OFF | ON | Rédaction les écrit (app : `redaction.ts` ; atelier : l'analyse d'étape), le composeur les place (`placerQuiz`, `mise-en-page.js`) | Rendu (`quiz`) et rempli depuis le 15/10/2026 — OFF : aucun quiz, dans l'atelier comme dans l'app |
| **Zones libres** | ON / OFF | ON | Mise en page | **Sans effet depuis le 15/10/2026** : les pages réglées de fin de carnet sont retirées (« pour le moment », Hugo) — `pages_libres: 0` dans l'atelier et `bookSettings.ts`. Le réglage reste affiché dans l'app : à retirer de l'écran, ou à rebrancher le jour où les pages reviennent |
| **Mot fléché à la fin du livre** | ON / OFF | ON | La grille se génère à la commande ; les mots du voyage, règles en attente dans `agent-transcription-carnet.md` § 1 | À construire |

### Ce que chaque réglage veut dire, précisément

- **Fun facts.** À OFF, aucun encart, nulle part. À ON, **à peu près un encart
  toutes les trois pages** (13/10/2026), posé dans la page ou, faute de place,
  à la place d'une photo quand le gabarit de la page a un emplacement libre
  (14/10/2026), jamais par-dessus — tant que l'étape a des faits qui passent le seuil
  de pertinence. Un carnet sans matière en aura moins : on n'invente pas.
- **Pointillés.** La réglure du papier, sous le texte. À OFF, la page reste
  blanche sous le récit ; le rythme vertical, lui, ne change pas.
  **Verrouillés à OFF sur *Manuscrit* et *Éditorial*** (02/10/2026) : ces deux
  assortiments n'ont pas d'aperçu avec pointillés, ils les éteignent. Un carnet
  « Personnalisé » n'est pas verrouillé. Voir `docs/apercu-personnalisation.md`
  § La contrainte.
- **Nombre de pages cible** (Hugo, 15/10/2026). Les paliers se calculent sur
  la durée du voyage : « Par défaut » vise une page par jour, à la dizaine,
  entre 30 et 180 ; « Compact » ×2/3 et « Détaillé » ×4/3. **Sans date de fin :
  40 / 60 / 80 pages.** Le carnet final vise sa cible à **± 5 pages** (un
  Compact de 40 pages fait 35 à 45 pages). La cible règle la **densité de la
  rédaction** — la taille d'étape vers laquelle on tire, jamais au-delà de ce
  que le vocal raconte : on ne gonfle pas. Puis la **composition recale** le
  carnet (`recalerSurLaCible`, `mise-en-page.js` — le même code dans l'atelier
  et l'app, donc le même PDF) :
  - on compte **le carnet entier hors couvertures** : colophon, introduction,
    page libre d'avant, pages d'étape, pages libres de fin. Les pages fixes
    comptent mais ne bougent jamais ;
  - la mise en page n'invente pas de texte : elle n'ajoute ou ne retire que
    des **planches** (pages de photos de fin d'étape). Aucun récit n'est coupé,
    raccourci ni réduit, aucune page de récit n'apparaît ni ne disparaît ;
  - **le ratio photo / texte tient** : chaque étape garde exactement le nombre
    de photos que le ratio lui donne (celui que le chat a demandé). Trop court,
    ces photos s'étalent sur deux planches de plus (celles que les six pages
    avaient écartées reviennent ; à 50 % et au-delà, une page de récit à
    plusieurs photos en cède — elle garde toujours la sienne), jusqu'à deux
    doubles pages de photos par étape, et six pages par étape au plus ; trop long, elles se resserrent sur
    moins de planches (cinq par page) ou remontent sur les pages de récit qui
    ont encore une place ;
  - chaque étape garde un **nombre pair de pages** : deux planches à la fois,
    ou une seule pour rendre paire une étape impaire ;
  - **hors d'atteinte**, on ne force rien : pas assez de photos (le cas courant
    à 0 et 25 %, ou d'un récit court qui n'en demande que deux), ou trop de
    récit (la cible est sous ce que le texte seul occupe). Le carnet reste au
    plus près, et le journal le dit — `pages cible : … hors d'atteinte`, en
    avertissement dans les journaux de l'API, dans le journal de l'atelier.
  Changer de cible en cours de voyage :
  - **deux changements au plus**, comptés seulement une fois qu'une étape est
    écrite (avant, rien à homogénéiser). L'app le dit avant de changer —
    « Changer le nombre de pages cible » / « Annuler » —, puis « il ne te reste
    plus qu'un changement », puis, en orange, que la cible ne peut plus changer.
    Le serveur refuse au-delà (409 `page_target_limit_reached`) ;
  - **début ou milieu du voyage** : « C'est noté, on passe d'un récit compact à
    un récit détaillé. Les prochaines étapes seront donc plus étoffées. » Ce qui
    est déjà écrit n'est pas retouché ;
  - **fin du voyage** (les deux derniers tiers écoulés, ou voyage terminé) : le
    même message, plus l'offre d'étoffer — ou de condenser — les étapes déjà
    écrites. Une fois par changement : `POST /v1/trips/:id/page-target/rewrite`
    réécrit, une à une et dans l'ordre, les étapes que le voyageur n'a pas
    corrigées à la main (`jobs/rewriteTrip.ts`) ;
  - **sans date de fin**, l'app demande « À quel stade de ton voyage en
    es-tu ? » — plutôt au début, environ à la moitié, plutôt à la fin — et
    retombe sur l'un des cas ci-dessus.
- **Ratio photo / texte.** La part de surface qu'occupent les photos, mesurée
  sur l'ensemble des pages d'une étape, à ±5 points. À **0 %**, aucune photo dans
  le carnet — la couverture garde la sienne — et le récit prend la place qu'elles
  occupaient. À **25 %**, une photo par page de récit au plus. À **100 %**, aucun
  récit imprimé : le bandeau de l'étape et le fun fact si l'option est allumée,
  puis des planches ; le récit du voyageur sert de matière au fun fact. **C'est le nombre de pages
  et de photos qui s'adapte, jamais le texte** : un souvenir validé n'est ni
  coupé, ni raccourci, ni réduit de corps. Le chat annonce au voyageur le nombre
  exact de photos qu'il lui faut, calculé par la même fonction que celle qui
  compose le PDF. Changer le réglage après coup recalcule l'étape et peut
  redemander des photos.
- **Décorations & stickers.** La quantité n'est plus un jugement de l'agent :
  elle est réglée par le voyageur : les stickers (1 à 4 par étape, deux
  par page au plus)
  et le tracé pointillé. **Le scotch des photos n'en dépend plus** (Hugo,
  12/10/2026 : cadre, inclinaison et scotch toujours). À 0, ni sticker ni
  tracé.
- **Typographies.** Quatre axes indépendants. L'agent n'en substitue jamais
  aucune, même s'il juge une page trop dense. Seules les polices réellement
  embarquées dans `MemoBook Generator/templates/travel-journal/assets/fonts/` peuvent être
  proposées dans la liste.
- **Quiz.** Écrits par l'IA à partir des récits (Hugo, 15/10/2026) : une
  question, trois propositions, la réponse imprimée à l'envers. **Environ un
  quiz toutes les trois étapes**, jamais deux étapes de suite, un par étape au
  plus — tant que l'étape offre de quoi : une question sur ce que le voyageur
  a raconté, ou un fait vérifiable du lieu. Jamais inventé ; un carnet sans
  matière en aura moins. Un seul bloc interactif par page, et il remplace la
  zone flottante du bas : le composeur le pose sur la première page de
  l'étape qui n'a ni photo, ni encart, ni carte, et dont le récit ne donne pas
  la réponse — faute de page, il ne s'imprime pas (à 0 % de photos, le récit
  pleine page n'en rend aucun). La rédaction l'écrit même quand le réglage
  est coupé, comme le fun fact : à OFF, aucun quiz n'entre au carnet, et le
  rallumer les retrouve sans rien relancer.
- **Zones libres.** Une zone blanche à la fin de chaque étape, pour écrire ou
  dessiner à la main, et trois pages libres à la fin du carnet — réglées comme
  le papier du récit (Hugo, 12/10/2026), après la dernière étape et avant la
  quatrième. Les trois pages sont rendues ; la zone de fin d'étape reste à
  construire. C'est aussi
  la réponse à « je ne dessine pas » : la zone n'impose rien, elle laisse la
  place.
- **Mot fléché.** Généré au moment de la commande, à partir des récits, et placé
  en fin de carnet. Elle se nourrit de huit à douze mots du voyage et de leurs
  définitions — règle écrite (`agent-transcription-carnet.md` § 1), mais qu'aucun
  agent ne tient encore.

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
| **Éditorial** | Playfair | Playfair | Playfair | Playfair |
| **Manuscrit** | Hansley | Hansley | Gloria Hallelujah | Gloria Hallelujah |

Le défaut est **exactement** le jeu que la base pose déjà : un carnet réglé
avant que cette feuille existe s'y reconnaît sans qu'on touche à quoi que ce
soit. Un carnet composé police par police qui n'entre dans aucune des trois
cases s'affiche « Personnalisé » — on ne coche pas de force.

« Éditorial » est **Playfair seule** depuis le 01/10/2026, comme la V3 le
propose ; elle mariait Playfair et Alegreya. Un carnet réglé sur l'ancien jeu
garde ses polices et se lit « Personnalisé ».

⚠️ **Une famille n'est pas dans le gabarit.** `fonts.css` n'inline que
Playfair Display et Gloria Hallelujah ; Hansley est versionné sans être inliné.
Rien n'échoue — la page retombe sur une police système —, mais Hansley ne
s'imprimera vraiment qu'une fois cette face ajoutée à `build-font-css.ts`.

---

## Le crédit du jour

**Chaque voyage peut raconter 5 minutes par jour**, partagées entre ses
co-voyageurs qui ne sont pas abonnés (Hugo, 03/10/2026). Il remplace à la fois
les trois étapes offertes et les limites de souvenirs hebdomadaires : il n'y a
plus de palier d'entrée, ni d'extension à acheter.

| | Sans abonnement | Abonné (4,99 €/mois) |
|---|---|---|
| Récit | 5 minutes par jour et par voyage, à partager | Illimité — et il ne prend rien au pot commun |
| Ce qui consomme | un vocal : sa durée ; un texte : 75 ms par caractère (800 caractères = 1 min) | rien |
| Photos | libres | libres |

**Un seul crédit pour l'oral et l'écrit.** Deux compteurs (des secondes et des
caractères) auraient demandé deux jauges et une règle de plus à expliquer ; un
texte se convertit en temps, et la ligne dit une seule chose. Une puce envoyée
telle quelle et les commandes silencieuses ne consomment rien ; le contexte du
voyage et les précisions comptent comme le reste.

**Par voyage, pas par compte.** Le crédit est le pot commun du voyage : ses
co-voyageurs non abonnés le partagent. L'abonnement est personnel — il rend
l'illimité à l'abonné seul, et n'ouvre rien à ses co-voyageurs.

**Il se recharge à minuit**, à l'heure de celui qui raconte (`accounts.timeZone`,
tenu à jour par l'en-tête `X-Time-Zone`). Le jour ne recule jamais : changer de
fuseau ne rouvre pas une journée déjà consommée.

**Il se voit en permanence dans les paramètres du voyage**, à la ligne « Crédit
du jour » : le reste (« 3 min 20 / 5 min »), la jauge de ce qui reste — pleine au
matin, elle se vide en vert et rougit à zéro (recette du 03/10/2026) —, et
la feuille qui explique la règle et propose « Passer en illimité ». Ce n'est
plus un garde-fou discret qui ne se montre qu'au seuil : c'est ce que
l'abonnement lève, il doit se lire d'un regard. Un abonné y lit « Illimité ».
Pendant un enregistrement, la barre prévient à 30 s du bout, pulse à 5 s, et
coupe net à zéro — ce qui a été dit est envoyé, jamais jeté.

⚠️ **Le mot « jeton » — et le mot « token » — n'apparaissent nulle part dans
l'app.** On compte en minutes et en secondes ; « souvenir » n'est plus une unité
de compte.

⚠️ **Le serveur tranche, l'app prévient.** Les constantes vivent dans
`backend/src/services/dailyCredit.ts` (`DAILY_CREDIT_LIMIT_MS`,
`TEXT_MS_PER_CHARACTER`, les seuils de 30 s et 5 s) et voyagent jusqu'à l'app
avec le solde — qui n'en écrit aucune. Le détail des garde-fous est dans
[`paiements.md`](paiements.md#le-crédit-du-jour-sans-abonnement).

---

## Ce qui n'est pas réglable

Ces points sont arbitrés une fois pour toutes. Les ouvrir reviendrait à demander
au voyageur d'arbitrer un défaut qu'il n'a pas produit.

| Point | La règle | Pourquoi |
|---|---|---|
| **Voix du récit** | Celle que le voyageur emploie le plus, uniformisée sur tout le carnet | Ce n'est pas un goût mais un relevé. « Je » ou « on » se déduit de ses vocaux, et se fige dans la fiche de cohérence |
| **Niveau de lissage** | Fidèle au récit, intégralement corrigé, retravaillé pour se lire | Un vocal est très oral ; un carnet imprimé se lit. Ce peaufinage est le cœur du savoir-faire MemoBook, il s'affine avec le temps — il ne se désactive pas |
| **Bandeau de journée** | L'agent décide ce qu'il porte ; la météo n'y figure que si le voyageur l'a dite clairement dans son vocal | Le panel préfère le gîte et les hôtes, et une météo supposée serait une invention. Un réglage de plus pour un bandeau de quatre champs ne se justifie pas |
| **Rose, épine, graine** | Demandé dans le chat, pas imprimé comme bloc à remplir | La réponse devient de la matière de récit. Une question posée à froid sur le papier n'obtient rien |
| **Mention « généré par IA »** | Toujours imprimée dès qu'un élément vient de la machine | Engagement de transparence, demandé explicitement par les lecteurs |
| **Nom des couleurs écrit** | Toujours en toutes lettres | Accessibilité : une consigne portée par la seule couleur disparaît pour un lecteur daltonien, sur une photocopie, en noir et blanc |
| **Qualité du français** | Les règles du § 8 de la rédaction | Un carnet imprimé ne se corrige plus |
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
