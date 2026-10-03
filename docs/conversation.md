# La conversation avec MEMO

> Ce que fait le chat, ce qu'il fait d'un vocal, ce que MEMO dit et ne dit
> jamais, et ce qui reste à construire pour qu'il fonctionne réellement.
>
> Écrit le 22/09/2026 avec Hugo, à partir de l'état du code (`main @ c64a0c8`)
> et des décisions listées en fin de fichier. Le ticket Notion « Module
> Conversation avec MEMO » renvoie ici : **ce fichier fait foi**, Notion en est
> la copie que Hugo partage. La fiche d'écran (mesures, composants, états) reste
> dans `archive/ui-development-journal.md` § 14 ; ce document dit le **produit** et le
> **contrat**, pas le dessin.

## 1. Qui parle

**MEMO est le personnage.** Une seule voix, une seule bulle blanche, un seul
prénom. Le voyageur ne parle jamais à « un agent » : il parle à MEMO.

Derrière lui travaillent les agents de `agents/`, et le voyageur n'a pas à
savoir lequel :

| Agent | Ce qu'il fait pour MEMO | État |
|---|---|---|
| **Conversation** (`agent-conversation.md`) | Sa voix : écouter, reformuler, relancer, classer ce qu'on lui dit | En production (Claude Sonnet 5) — le fichier **est** le prompt système |
| **Transcription & Rédaction** (`agent-transcription.md`) | Son écrivain : transformer un vocal en texte fidèle et agréable à lire | En production (OpenAI `gpt-4o-transcribe`, puis Claude Opus 5) |
| **Photo** (`agent-photo.md`) | Choisir et ordonner les photos d'un souvenir | Non implémenté — phase 2 |
| **Mise en page** (`agent-layout.md`) | Composer le carnet sans réécrire un mot | En production, à l'aperçu |
| **Modération** (`agent-moderation.md`) | Dernier filtre avant impression | Non implémenté — fin de chaîne, jamais dans le chat |

Quand la rédaction est prête, c'est **MEMO** qui dit « voilà ce que j'ai
compris ». Quand la transcription échoue, c'est MEMO qui dit qu'il n'a pas
réussi à écouter.

**Ce que Hugo veut du texte** (21/09/2026) : « garder l'authenticité du vocal
mais ajouter du liant, pour que le texte soit toujours fidèle à celui qui parle
mais aussi sympa à lire ». C'est exactement le prompt de rédaction déjà en
production — § 1 Fidélité, § 3 La voix du voyageur, § 4 Fluidité. Le liant est
**narratif** : on enchaîne comme un récit, pas comme une liste. On n'ajoute pas
de chaleur à quelqu'un de sobre — « ne pas rendre lyrique quelqu'un de sobre »
reste la règle. Ce chantier ne touche pas à ce prompt.

## 2. Un fil par voyage

- **Un seul fil par voyage.** Les messages portent leur étape (`stepId`), ils
  ne sont pas rangés par étape. Ouvrir une carte d'étape se pose sur le dernier
  message de cette journée ; ce qu'on raconte ensuite s'y rattache.
- **Le fil vit sur le serveur.** On le retrouve d'un autre téléphone, et un
  co-voyageur le voit. Il n'est **jamais mis en cache** dans l'app : un fil
  périmé se lit comme un message perdu.
- **Le fil est commun aux co-voyageurs.** C'est le récit du voyage, pas une
  messagerie privée. Dès qu'ils sont deux, chaque bulle bleue porte le prénom de
  qui parle. Les **souvenirs**, eux, restent sans auteur : le carnet parle d'une
  seule voix (`agent-transcription.md` § 3).
- **MEMO parle le premier**, une seule bulle d'ouverture, qui se termine déjà
  par une question. La relance du jour (« Comment ça se passe à Trastevere ? »)
  ne vient **jamais** dans le fil : elle est faite pour la carte de l'accueil du
  voyage et pour la notification qui la portera un jour.
- **Un voyage qui a déjà des souvenirs** (racontés depuis l'accueil, avant que
  le chat existe) les retrouve dans son fil : une bulle par souvenir, suivie de
  sa fiche, dans l'ordre des dates. Les réponses passées de MEMO n'existent pas ;
  seule l'ouverture précède.

## 2 bis. Le contexte du voyage, avant la première étape

**Décidé par Paul le 28/09/2026.** À la première ouverture du fil, une seule
puce : **« Je te raconte le contexte de mon voyage »** 🧭. On pose le décor
avant de raconter la première journée ; c'est ce qui fait écrire « Clara » et
non « une amie » à la page 2, et ce qui évite à MEMO de demander « qui est
Léo ? » à la dixième étape.

**Ce qu'il faut pour que le contexte soit posé** — cinq lignes, dans cet ordre :

| Ligne | Complète quand |
|---|---|
| Pays de départ | un pays est dit |
| Voyageurs | un nombre, narrateur compris (« seul » = 1, « en couple » = 2) |
| Compagnons de route | **un prénom par compagnon** — « on est quatre » avec deux prénoms, ce n'est pas fini |
| Dates | les dates du voyage, telles que dites |
| Genre de voyage | road trip, city trip, trek, farniente… |

Et, s'ils viennent, sans jamais les réclamer : l'itinéraire prévu, le lien avec
chaque compagnon (« ma femme », « un ami d'enfance »), l'occasion (lune de
miel, anniversaire), le moment où l'on raconte (avant, pendant, après).

**Comment ça se passe.**

1. La puce : MEMO invite à tout raconter d'un coup, comme à un ami, à l'oral
   ou au clavier. Pas de puce sous l'invitation — le composeur suffit.
2. Chaque tour du voyageur est **écouté** : le modèle extrait ce qui a été dit
   et le reformule en une phrase, sans question. **Le code** voit ce qui
   manque et pose **la** question de la première ligne vide. Une question par
   tour, jamais deux, jamais une déjà répondue.
3. Tant qu'il manque une ligne, la puce **« Je compléterai plus tard »** ⏭️
   referme le contexte sans insister ; il se complète au fil du récit.
4. Tout y est : MEMO le dit, et propose de raconter la première journée.

**Rien de ce qui se dit ici n'est un souvenir** (disposition `trip_context`) :
pas d'`Entry`, pas de fiche de retranscription. Ce qu'on y raconte compte en
revanche sur le **crédit du jour** comme tout récit, vocal ou texte — plus
d'exemption depuis le 03/10/2026 (§ 6 bis). Un vocal est transcrit par le job
`converse` lui-même et son fichier pend au message
(`GET /v1/chat-messages/:id/media`). Des photos restent des souvenirs.

**Où ça vit.** `memos.tripContext` (JSON, forme dans
`backend/src/services/tripContext.ts`). MEMO le relit à chaque tour (« Le
contexte du voyage » dans son prompt, les compagnons sont connus du repli) et
l'écrivain à chaque rédaction. Il survit à « Supprimer la conversation » :
l'ouverture propose alors les puces habituelles.

**Ce que l'app en montre.** Une pastille « Contexte du voyage 3/5 » sous
l'en-tête du fil, qui se remplit à chaque réponse ; un appui ouvre la fiche,
ligne à ligne. On n'y corrige rien : on le dit à MEMO.

**Sans modèle**, le repli range la réponse dans la ligne que MEMO venait de
demander ; une première description libre est gardée pour l'écrivain, et MEMO
demande ensuite ligne à ligne.

## 3. Le tour type

### Le déroulé d'un souvenir — décidé par Hugo le 01/10/2026

« Poser trop de questions fatigue l'utilisateur. » Un souvenir suit désormais
un déroulé fixe, écrit par le code, sans modèle :

1. **Le voyageur raconte** (vocal ou texte) → la fiche de retranscription
   tombe. MEMO ne dit **rien d'autre** : ni reformulation, ni question sur le
   lieu, les gens, un détail.
2. **Le texte est prêt** (rédigé — ou brut si la rédaction a échoué) → une
   seule bulle : « Voilà ton texte pour le carnet. Il te convient ? », avec le
   trio de validation (§ 6). C'est le job de rédaction qui la pose
   (`askValidation`), parce que lui seul sait quand le texte est là.
   **Si l'écrivain a laissé de côté un passage qu'il n'a pas compris** — un
   mot mal transcrit, que le contexte ne permet pas de rétablir —, la même
   bulle le dit, deux passages au plus : « … Je n'ai pas compris « je tarbé » :
   je l'ai laissé de côté. Redis-le-moi autrement si tu veux qu'il y soit. Il
   te convient ? » Ce n'est pas une question de plus ; la réponse est une
   précision, et le texte se réécrit avec elle (point 3).
3. **On attend la validation.** Une précision tapée entre-temps (« c'était
   avec Clara ») reçoit « C'est noté, je reprends le texte avec ça. », le
   texte se réécrit, et la question revient avec lui. Une correction à la main
   reçoit l'accusé habituel et propose encore « Ça me convient ».
4. **« Ça me convient »** → « C'est enregistré… », puis **le nombre exact de
   photos** qui remplit l'étape : « Illustre ce souvenir avec 3 photos : c'est
   ce qu'il faut pour remplir sa page. » Puces : importer des photos, ou
   raconter la suite.
5. **Les photos arrivent** → MEMO demande de les valider, et dit ce que ça
   fait : « Si tu les valides, je crée la page de cette étape dans ton carnet,
   et tu pourras la prévisualiser. » Puces : « Je valide mes photos », « Ajouter
   d'autres photos ». Moins de photos que demandé : accepté sans redemander, la
   mise en page s'adapte.
6. **« Je valide mes photos »** → les photos sont validées et le carnet se
   recompose en fond (`ensureRenderInProgress`, le même déclencheur que
   « Valider cette étape »). MEMO le dit ; puces : « Voir ma page » (ouvre
   l'aperçu, n'envoie rien — intention `open_preview`), raconter à l'oral, à
   l'écrit. **L'étape suivante ne vient qu'ici.**

**La fiche** s'intitule « Retranscription étape N » — la N-ième fiche du fil
est l'étape N — et le récit prêt porte au-dessus de lui le titre que la
rédaction lui a donné (`suggestedTitle`, celui de l'étape dans le carnet).

**Le nombre de photos** (`backend/src/services/photoBudget.ts`) : le layout le
plus riche en photos qui tient **tout** le texte validé, à son maximum. Un
chiffre, jamais une fourchette.

| Texte validé | Mise en page | Photos |
|---|---|---|
| sous S (< 200 caractères) | 1 page `layout_hero_top` | **1** |
| S ou M (200 → 559) | 1 page `layout_collage` | **3** |
| L ou XL (560 → 1440) | 2 pages `layout_collage` (bandeau + suite) | **6** |

Le modèle ne sert plus, sur ces tours, qu'à **classer** un texte libre
(souvenir, précision, commande). Le contexte du voyage (§ 2 bis) n'est pas
concerné : ce n'est pas un souvenir.

Ce qui suit décrit les autres tours — une question au voyageur, une réponse à
une question sur l'app.

### Les autres tours

Le voyageur raconte — un vocal, un texte, des photos. MEMO répond en **trois
phrases au plus** :

1. **Une reformulation**, une phrase, avec les mots du voyageur. Elle prouve
   qu'il a écouté ; elle ne juge pas, n'embellit pas.
2. **Une question précise** sur ce qui manque au souvenir, dans cet ordre de
   priorité : le lieu → avec qui → un détail concret (un plat, une phrase
   entendue, un chiffre) → un ressenti. **Une seule.** Jamais « raconte-m'en
   plus ». Jamais une question à laquelle le fil, la fiche de cohérence ou le
   souvenir en cours répondent déjà.
3. Éventuellement une phrase courte de plus — l'accusé d'une commande.

Les réponses aux questions de MEMO **nourrissent l'écrivain** : c'est tout leur
intérêt. Une précision donnée dans le chat (« c'était avec Clara, le mardi »)
arrive dans la rédaction du souvenir en cours, à sa place, sans être citée comme
une réponse à une question.

**Rose, épine, graine** (v1b). En fin de journée racontée, MEMO demande en
**une seule bulle** le meilleur moment, le pire, et ce qu'on retient. Une fois
par journée, jamais avant que le souvenir en cours soit validé, jamais avant
17 h heure du voyageur sauf si l'étape se termine. Les réponses sont des
précisions marquées `rose_epine_graine` ; la rédaction les traite comme le reste
du souvenir (`agent-transcription.md` § 1.6).

**Quand on ne demande rien.** Un refus (« plus tard », « pas envie ») : MEMO
garde et s'arrête — c'est la règle la plus dure du contrat de l'agent. Une
émotion difficile : on accuse d'abord, la question est facultative. Une question
du voyageur reçoit une réponse, pas une relance.

## 4. Ce qui devient un souvenir

Chaque tour du voyageur est **gardé dans le fil**, quoi qu'il arrive. Ce qui
change, c'est ce que MEMO en fait — sa **disposition** :

| Disposition | Quoi | Ce qui se passe |
|---|---|---|
| **souvenir** (`memory`) | Un vocal, une photo — toujours. Un texte qui raconte un moment, une journée, un lieu, un événement | Une `Entry` est créée, la rédaction l'écrit, le carnet la reçoit |
| **précision** (`context`) | Un texte qui répond à la dernière question de MEMO ou complète le souvenir en cours : une date, un prénom, un chiffre, un ressenti. Typiquement court | Rattachée au souvenir en cours ; la rédaction relit le souvenir avec elle. S'il n'y a **pas** de souvenir en cours non validé, c'est un souvenir |
| **commande** (`command`) | Une puce (« Ça me convient »), un refus, une question sur l'app ou le carnet | Rien n'entre dans le carnet ; MEMO répond sans modèle |

C'est **MEMO qui classe** un texte libre. Le filet : le texte est de toute
façon dans le fil, rien ne se perd, et un vocal est toujours un souvenir. Un
« oui c'était mardi avec Clara » ne fera jamais un souvenir de trente
caractères dans le carnet.

## 5. La fiche de retranscription

Après un vocal, MEMO pose une fiche « Retranscription étape N » — date,
lieu, durée — **tout de suite**, avant même d'avoir écouté. Elle passe par
trois temps :

| Temps | Ce qu'on voit | Ce qui se passe derrière |
|---|---|---|
| **J'écoute** | La fiche, sans texte, et « J'écoute ton vocal… » | Transcription en cours (5 à 15 s) |
| **Je rédige** | Le texte brut, en gris, et « Je rédige… » | Rédaction en cours (10 à 40 s). Le voyageur voit qu'il a été entendu |
| **Prête** | Le texte rédigé, noir, avec le pied « Texte proposé par MEMO — tu peux le corriger » | C'est ce qui ira dans le carnet |

Si la transcription échoue, la fiche le dit et MEMO propose de réenregistrer ou
de raconter au clavier. Si la rédaction échoue, la fiche garde le texte brut.

La fiche **connaît son souvenir** (`entryId`) : c'est elle qu'on valide, qu'on
corrige, qu'on relit.

## 6. Valider, corriger

Sous une fiche prête, trois puces :

| Puce | Ce que ça fait |
|---|---|
| **Ça me convient** 👌 | Le souvenir est **validé** (`validatedAt`). MEMO : « C'est enregistré. Ton carnet compte une étape de plus. », puis le nombre exact de photos à ajouter (§ 3) |
| **J'aimerais faire des modifications à la main** ✍️ | Le texte de la fiche est déjà dans le champ, qui prend toute la barre. Envoyer **corrige le souvenir** (`editedText`) : la fiche change, MEMO dit « Je te laisse la main. Ta version fait autorité sur la mienne, je n'y retouche plus. » Un texte corrigé est intouchable (ADR-007) |
| **J'aimerais faire des modifications à l'oral** 🎙 | **Phase 2.** Aujourd'hui MEMO dit « Je t'écoute » et le vocal suivant est un **nouveau** souvenir, pas une révision. Le dire, pour que personne ne le prenne pour un bug |

**Le carnet n'attend pas la validation.** Il se compose avec tous les
souvenirs ; l'aperçu signale ceux qui n'ont pas été relus. Un voyageur qui
oublie de valider n'a pas un carnet vide.

**Valider ne coûte rien et ne décompte rien** : ce qu'on raconte se paie au
moment où on le raconte, sur le crédit du jour (§ 6 bis).

## 6 bis. Le crédit du jour, l'abonnement, et les boutons sous les bulles

Décidé par Hugo le 03/10/2026. L'ancien modèle — trois étapes offertes, limites
de souvenirs hebdomadaires, abonnement à la semaine — est archivé sur la branche
`icebox/abonnement-hebdomadaire`.

### Le crédit du jour, par voyage

**Chaque voyage peut raconter 5 minutes par jour**, partagées entre ses
co-voyageurs qui ne sont pas abonnés. **Un seul crédit** pour l'oral et l'écrit :

| Ce qu'on envoie | Ce que ça consomme |
|---|---|
| Un vocal — chat, accueil, contexte du voyage compris | Sa durée, **mesurée par le serveur** dans le fichier (jamais celle que l'app déclare) |
| Un texte libre — récit, précision, contexte du voyage | 75 ms par caractère : **800 caractères = 1 minute**, 4 000 = 5 minutes |
| Un texte corrigé à la main | Ce qu'il gagne en longueur, seulement |
| Une puce envoyée telle quelle, une commande silencieuse, des photos | Rien |

Le jour est celui de **qui raconte**, à son fuseau, et ne recule jamais ; le
crédit **se recharge à minuit**. Un vocal peut dépasser le reste de 3 secondes
au plus ; au-delà, ou crédit épuisé, le tour est refusé (`429
daily_credit_exhausted`) et l'app le garde en file pour le lendemain. Un tour
qui coûte plus que la journée entière — un vocal de plus de 5 min 03, un texte
de plus de 4 000 caractères — ne passera jamais : il est refusé à part (`429
daily_credit_too_long`), et l'app le garde jusqu'à ce que le compte passe en
illimité au lieu de le renvoyer chaque nuit ; sa bulle propose aussi de le
supprimer, après confirmation. « Il partira demain » et « dès que
tu passes en illimité » ne se disent qu'à un client qui garde le tour : celui
qui envoie `X-Time-Zone`, pour le chat (`holdsRefusedTurns`). Un build installé
avant le crédit du jour efface le tour refusé ; la route ancienne
`POST /v1/memos/:id/entries` n'a pas de file : leur refus dit ce qui reste et
de redire plus court, sans promettre de renvoi (03/10/2026). Le
**serveur est souverain** (`backend/src/services/dailyCredit.ts`, décompte sous
le verrou du voyage, dans la transaction qui écrit la bulle) ; l'app lit
l'objet `dailyCredit` servi avec le fil, le reçu d'un tour, les réglages du
voyage et l'accueil, pour prévenir à 30 secondes et couper net à zéro. Un
plafond anti-abus par carnet et par jour (150 tours, pour tous) ferme toujours
la porte à un script, pas à un voyageur.

### L'abonnement

**4,99 € par mois.** Il rend le récit **illimité pour l'abonné seul** : ses
tours ne consomment pas le crédit du voyage, et il n'ouvre rien à ses
co-voyageurs. Résilié, l'illimité reste ouvert jusqu'à la fin de la période
payée. On le découvre dans le profil (« Découvrir l’abonnement ») ; un abonné y
voit « Mon abonnement ».

### La bulle « reviens demain »

Quand un tour fait tomber le crédit du voyage à zéro, **ou** quand un tour est
refusé faute de crédit, **le serveur** — pas le modèle — pose une bulle de MEMO
(`model: "scripted"`), une fois par voyage et par jour (`limitNotifiedAt`) :

> Quelle journée ! Ce voyage a déjà raconté ses 5 minutes du jour. Je garde tout
> précieusement : reviens demain pour la suite, le crédit se recharge à minuit.

Elle porte le bouton `daily_credit_subscribe` (« Raconter sans limite », sous
l'en-tête « Crédit du jour épuisé ») et
`payload { notice: "daily_credit_exhausted:<AAAA-MM-JJ>", audience: "limited" }` :
un lecteur abonné ne la voit pas — il n'a pas à lire « reviens demain ». Le reçu
du tour la contient quand elle y naît. La réponse de MEMO à ce tour vient donc
**après** elle : le job `converse` la relit, retire `subscribe` des boutons
permis (pas de seconde offre sous la première) et la passe au répondeur comme
la dernière chose que MEMO a dite — sauf à un auteur abonné, qui ne la voit pas
(03/10/2026). Hors ligne, l'app pose la même, au mot
près (`DailyCreditCopy.exhaustedMessage`), en attendant celle du serveur.

### Ce que MEMO en dit

**Seulement quand on le lui demande** : le prix, l'abonnement, ce qu'il reste,
la limite. Il dit les faits ci-dessus, sans vendre — ni superlatif, ni urgence,
ni culpabilité (« tu as beaucoup parlé » ne se dit pas). Il ne connaît pas le
reste chiffré du jour : il renvoie aux réglages du voyage. À un abonné, il ne
décrit pas les 5 minutes comme une règle qui le concerne. Le moteur de règles
répond la même chose (`ANSWERS.subscription`, `ANSWERS.subscriptionUnlimited`).
Le détail est dans `agents/agent-conversation.md` § 3 bis.

### Les boutons sous une bulle

Une bulle de MEMO porte **au plus un bouton** — une carte sous son texte, avec
« Ignorer » si on peut l'écarter. Le catalogue est **fermé** :
`backend/src/services/callsToAction.ts` (et `ChatCallToAction.Kind` dans l'app).
Il se range dans `chat_messages.payload.callToAction = { id }` et se **résout à
la lecture, pour chaque lecteur** (`resolveCallToAction`) : une offre
d'abonnement n'est jamais montrée à quelqu'un qui raconte déjà sans limite.

Deux origines :

- **Le code** pose `daily_credit_subscribe` (la bulle « reviens demain ») et
  `open_photo_settings` (l'accès aux photos limité, que seule l'app connaît).
- **L'IA** choisit, rarement, un bouton parmi ceux que **le code autorise ce
  tour-ci** (`callsToActionAllowed`, `conversation.ts`) — le modèle propose, le
  code dispose :

| Bouton | Autorisé quand |
|---|---|
| `subscribe` | Un texte libre qui parle de l'abonnement, du crédit du jour, de la limite du récit ou du temps qui reste pour raconter (`mentionsSubscription` — pas du prix d'un billet ou du carnet, d'un musée gratuit, de la limite de vitesse, du temps d'un trajet, du crédit du téléphone, du wifi illimité ni d'une autre app), **et** son auteur n'a pas l'accès illimité |
| `open_trip_settings` | Un texte libre |
| `open_preview` | Un texte libre, et un rendu du carnet est prêt |
| `import_photos` | Un texte libre |

Et **jamais deux fois de suite le même bouton** : le bouton de la dernière bulle
de MEMO qui en porte un — la bulle « reviens demain » de ce tour d'abord — sort
des boutons permis, avec tout bouton qui fait la même chose (`daily_credit_subscribe`
et `subscribe` sont la même offre). Le repli suit : `validateReply` jette ce
qui n'est pas permis (03/10/2026).

Jamais sous un vocal, des photos ou une puce. `validateReply` jette un bouton
non autorisé ; le job le range sur la **dernière** bulle du tour, et le remet
à `null` quand les bulles disparaissent (un souvenir) ou sont remplacées par
« C’est noté, je reprends le texte avec ça » (une précision). Un bouton ne
passe **jamais** par un nouveau `body.kind` ni par une puce : les apps déjà
installées casseraient sur l'un et enverraient l'autre comme un texte. Elles
ignorent la clé `callToAction` — **le texte de la bulle doit donc se suffire**
et dire où trouver ce que le bouton ouvre.

## 7. Supprimer la conversation

Depuis les réglages du voyage, **le propriétaire seul**. Supprimer veut dire
**garder la bulle d'ouverture** : on retrouve MEMO qui se présente, les puces
d'ouverture, et rien d'autre — on a effacé ce qu'on s'est dit, pas fait comme si
on ne s'était jamais parlé. Les souvenirs déjà dans le carnet n'y sont pour
rien et n'y reviennent pas.

Un co-voyageur voit le lien pâli ; l'appuyer explique pourquoi.

## 8. Le temps

- **Le message part tout de suite.** La bulle bleue est « envoyée » dès que le
  serveur l'a reçue, pas quand MEMO a répondu. MEMO « écrit… » pendant qu'il
  réfléchit.
- **La réponse arrive en sondant** : l'app relit le fil toutes les deux secondes
  tant qu'un tour est en vol ou qu'une fiche n'est pas prête, et s'arrête
  après trois minutes sans changement. Pas de connexion ouverte, pas de
  minuterie globale — le motif de la feuille Statistiques.
- **Les bulles de MEMO ont un rythme**, décidé par le serveur et joué par
  l'app : un silence avant chaque bulle, proportionnel à ce qu'il y a à lire.
  Une latence nulle ou constante est le premier signe qu'il n'y a personne en
  face.
- **MEMO n'est jamais muet.** Si le modèle ne répond pas en vingt secondes, ou
  répond n'importe quoi, un moteur de règles répond à sa place — le même que
  celui qui vit aujourd'hui dans l'app, porté côté serveur. La bulle retient
  qui l'a écrite, pour compter combien de fois ça arrive.
- **La relance du voyage** (« Comment ça se passe à Trastevere ? ») est
  réécrite par MEMO après chaque tour. Elle s'affiche sur la carte de l'accueil
  du voyage. La notification qui la portera est un chantier à part.

## 9. Hors ligne

Un texte, un vocal ou des photos envoyés sans réseau restent « en cours
d'envoi » dans le fil et partent au retour du réseau, dans l'ordre, sans
doublon — la file des vocaux de l'accueil, généralisée à tout ce qu'on envoie.
Ce qui attend est dans `Application Support`, jamais dans les caches.

Ce que ça donne à l'écran : la bulle est posée, un peu en retrait, et le
composeur se rouvre — attendre n'est pas échouer, il n'y a rien à faire. On
quitte le fil et on y revient : ce qui attend est encore là, au même endroit.
Le réseau revient : les bulles prennent leur pleine couleur une à une, et MEMO
répond à chacune, dans l'ordre. Le vocal enregistré depuis l'accueil suit
exactement le même chemin, vers **un** carnet — celui dont la conversation
s'ouvre.

**Le fil s'ouvre aussi sans réseau** (Hugo, 01/10/2026 : « créer un voyage
doit être possible hors ligne de bout en bout ; pareil pour les vocaux et les
textes »). Il n'est toujours pas mis en cache (§ 2) : ce qui s'ouvre est un fil
**local** — l'accueil de MEMO, ce qui attend d'être envoyé, et une boîte qui le
dit (« Tu sembles hors ligne. **Ce que tu racontes est gardé sur ton
téléphone**… »). On y raconte comme d'habitude, tout part dans la file. Le
premier message arrivé au retour du réseau fait relire le vrai fil.

Deux cas l'ouvrent : une panne de **transport**, et un voyage **créé hors
ligne** que le serveur n'a pas encore reçu — celui-là s'ouvre comme un carnet
neuf, sur la puce du contexte. Un refus du serveur (5xx, 4xx) ne s'efface pas
derrière un fil local : il se dit.

Le voyage créé hors ligne passe **avant** ce qu'on y raconte : il porte
l'identifiant que l'app a tiré, et `POST /v1/trips` le reprend tel quel (et se
rejoue sans doublon). Un vocal pour un carnet que le serveur ne connaît pas
attend donc son voyage au lieu d'être refusé — et perdu.

## 10. Ce que MEMO ne fait jamais

- Inventer — un lieu, une météo, un prénom complété, un fait.
- Poser deux questions.
- Dépasser trois phrases.
- Insister après un refus.
- Rédiger le carnet (c'est l'écrivain), le mettre en page (c'est la mise en
  page), choisir des photos (phase 2).
- Parler d'argent, du crédit du jour ou de l'abonnement sans qu'on le lui
  demande, ni culpabiliser quelqu'un d'avoir beaucoup raconté (§ 6 bis). Les
  mots « quota », « jeton », « token » n'existent pas dans l'app.
- Vouvoyer.

## 11. Phase 2 — explicitement pas maintenant

- La réponse **mot à mot** (streaming) : la bulle s'écrit sous les yeux.
- **Proposer des photos** au souvenir (Agent Photo).
- **L'interview avant le départ**, au-delà du contexte du voyage (§ 2 bis) :
  le rythme, ce qu'on attend du voyage, le ton voulu pour le carnet.
- **« À l'oral » comme révision** d'un souvenir existant.
- **La notification** de relance, cadencée par le rythme du récit.
- Une **seconde réponse** quand le modèle finit après le repli.

## 12. Le contrat, en bref

| Pièce | Où | Quoi |
|---|---|---|
| Le fil | `backend/prisma/schema.prisma` → `chat_messages` | Un message par tour, adossé au carnet et au souvenir. `seq` est la seule vérité sur l'ordre |
| Lire le fil | `GET /v1/trips/:id/chat` (+ `?since=`) | Le `ChatThread` de `MemoBookCore/Chat.swift`, au champ près ; la fiche recalculée depuis `entries` ; les souvenirs sans message reconstruits |
| Un tour | `POST /v1/trips/:id/chat` | JSON pour un texte ou une puce, multipart pour un vocal ou des photos ; `id` fourni par l'app (idempotent) ; 201 tout de suite |
| Valider | `POST /v1/entries/:id/validate` | `validatedAt` ; rend `{ entry }` |
| Corriger | `PATCH /v1/entries/:id` (existe) | `editedText` |
| Supprimer | `DELETE /v1/trips/:id/chat` | Propriétaire seul, 403 sinon |
| Répondre | job `memobook.converse` | `AnthropicResponder` (Sonnet 5, prompt = `agents/agent-conversation.md`, sortie JSON contrainte : bulles, classement, puces, relance, rose/épine/graine, `callToActionId`) → repli `HeuristicResponder` sans clé Anthropic → `FakeResponder` sous `PIPELINE_MODE=fake`, en CI et dans les tests |
| Le crédit du jour | `backend/src/services/dailyCredit.ts`, table `trip_daily_usage` | Décompté sous le verrou du voyage ; servi en `dailyCredit` ; refus `429 daily_credit_exhausted` (§ 6 bis) |
| Un bouton | `payload.callToAction = { id }` → `message.callToAction` | Catalogue `callsToAction.ts`, résolu pour chaque lecteur (§ 6 bis) |
| Écrire | jobs `transcribe` → `redact` (existent) | La rédaction relit les précisions du fil |

Le détail — champs, codes d'erreur, tests, phasage en quatre PR — est dans le
plan de la branche `atelier-conversation` et sera reporté dans
`archive/ui-development-journal.md` § 14.1 à mesure. Le choix du moteur lui-même — pourquoi
Sonnet 5 ici et Opus 5 pour la rédaction, ce que ça coûte, et ce qui ferait
changer d'avis — est dans [`modeles-ia.md`](modeles-ia.md) (23/09/2026).

## 13. Comment on saura que MEMO est bon

Avant de couper le moteur local, on rejoue les vocaux des testeurs (Hugo en a
plus de dix) dans le pipeline réel et on relit chaque réponse de MEMO avec
cette grille — une ligne, sept cases, pas de note :

| | Oui / Non |
|---|---|
| Aucun fait inventé | |
| Une seule question | |
| Trois phrases au plus | |
| Tutoiement, et les mots du produit (co-voyageur, souvenir, étape) | |
| La question n'est pas déjà répondue dans le fil ou le souvenir | |
| La reformulation garde au moins un mot du voyageur | |
| La relance se lit seule, sans contexte | |

Deux ou trois itérations du prompt, en notant ici ce qui a changé et pourquoi.
Les mêmes vocaux nourrissent les tests structurels — jamais le modèle en CI.

### Première calibration — 23/09/2026, Sonnet 5, dix scènes écrites

Trois passes. Ce que la grille a attrapé, et ce que ça a changé dans
`agents/agent-conversation.md` :

| Ce qu'on a lu | Pourquoi c'est une faute | Ce qui a changé |
|---|---|---|
| « C'est un écrivain qui rédige les souvenirs, pas moi » | MEMO est **le** personnage (§ 1) : le voyageur n'a pas à savoir qu'il y a d'autres passages derrière | La section qui décrivait les autres agents devient « ce qui travaille derrière toi — et qui ne se dit pas ». MEMO répond en son nom : « c'est moi qui écris ton carnet » |
| « C'était où, et avec qui ? » | Un seul point d'interrogation, deux demandes | La règle le dit avec l'exemple — et ajoute que la tentation est la plus forte quand on ne sait **rien** (des photos sans un mot) : demander le lieu, rien d'autre |
| « lequel a marqué Clara ? » en relance, à Clara | La relance s'affiche sur la carte du voyage, que **tous** les co-voyageurs lisent | La relance ne nomme personne : un lieu, un moment, une chose |
| Un vocal inaudible classé `command` | Le souvenir existe, c'est sa transcription qui manque | « Un vocal est toujours un souvenir, **y compris celui que tu n'as pas réussi à entendre** » |

Et deux corrections dans le **banc**, pas dans le prompt — un faux positif
répété apprend à ignorer la grille :

- « Tutoiement » ne se coche plus automatiquement dès qu'une autre personne est
  en scène : « la burrata coupée devant vous », avec Clara, est du français
  correct. La ligne passe alors en lecture à la main.
- L'écho des mots du voyageur ne s'exige plus sur un **refus** : il n'y a rien
  à reformuler, et l'exiger reviendrait à demander d'insister.

Au terme des trois passes, les dix scènes passent sans manquement de forme, et
les trois lignes qui se lisent — rien d'inventé, la question n'est pas déjà
répondue, c'est la plus utile — tiennent sur les dix.

⚠️ **Ce sont des scènes écrites, pas des voix.** Elles disent que le contrat
tient ; elles ne disent rien du français parlé, des hésitations et des noms
propres mal transcrits. La calibration n'est pas finie tant que les vocaux des
testeurs n'y sont pas passés.

### Deuxième calibration — 24/09/2026, Sonnet 5, neuf vocaux de testeurs

Premier passage de vraies voix (`11` à `19` dans le dossier de scènes) : neuf
vocaux WhatsApp de Hugo pendant un voyage en Grèce (Paros, Naxos, Ios,
Mykonos), transcrits avec `gpt-4o-transcribe` pour l'occasion — texte gardé
tel quel, hésitations et noms mal transcrits compris (ex. « Famine » entendu
pour Fanny, scène 19).

Les neuf passent sans manquement de forme après une correction — **dans le
banc, pas dans le prompt** : son détecteur de refus cherchait le mot « stop »
en isolé, et « on a fait un bon petit stop avant de prendre le ferry » (une
halte de route) l'a déclenché à tort. Retiré du banc ; les autres formules de
refus (« plus tard », « pas envie »…) sont plus explicites et n'ont pas ce
défaut. Même famille de faux positif que les deux corrections du 23/09.

Les trois lignes qui se lisent tiennent sur les neuf : rien d'inventé, aucune
question déjà répondue, le mélange tu (au voyageur) / vous (au couple) sonne
juste partout où il apparaît.

**Une observation, laissée ouverte** : la scène 19 (dernier jour du voyage,
aucun ressenti dit) visait à voir si MEMO pose la question ressenti en fin de
séjour. Il a plutôt demandé un détail factuel non couvert — cohérent avec
l'ordre du prompt (lieu → avec qui → détail → ressenti), mais ça montre que
le ressenti peut ne jamais arriver tant qu'il reste un détail factuel non
posé, ce qui est fréquent sur un vocal aussi dense. Pas changé pour l'instant
— une scène ne suffit pas à trancher, et rien n'empêche la question au tour
suivant.

### L'outil de relecture

```bash
cd backend && npm run conversation:eval            # Claude, sur toutes les scènes
cd backend && npm run conversation:eval -- --heuristic   # le moteur de règles, sans clé
```

Le script (`backend/scripts/conversation-eval.ts`) fait parler MEMO sur les
scènes de `backend/test/fixtures/conversation/` — dix situations du contrat :
un vocal riche, une précision courte, un refus, une journée difficile, une
question sur le produit, une transcription échouée, des photos, la
rose/épine/graine, une question déjà répondue, un carnet à plusieurs ; et,
depuis le 03/10/2026, deux questions sur le prix et sur ce qu'il reste du
crédit du jour (`--only credit-du-jour`). Il n'écrit rien en base, et **ce
n'est pas un test** : il n'appelle que le répondeur.

Quatre des sept lignes de la grille se vérifient à la machine, et le script les
coche tout seul : une seule question, trois bulles au plus, le tutoiement, la
relance qui se lit seule — plus les mots interdits, le Markdown, les puces hors
catalogue, le classement attendu, le bouton permis (et aucun après un refus),
et « la reformulation garde un mot du voyageur ». Les trois qui restent se lisent : **aucun fait inventé**, **la
question n'est pas déjà répondue**, **c'est la question la plus utile au
carnet**. Elles s'impriment sous chaque réponse, en cases vides.

Les vocaux des testeurs entrent là, une scène par vocal — le mode d'emploi est
dans `backend/test/fixtures/conversation/README.md`. Le moteur de règles sert
d'étalon : il échoue aujourd'hui sur six points de forme (il redemande le lieu
qu'on vient de lui donner, il ne reprend pas les mots du voyageur), et c'est
exactement ce que le modèle doit faire mieux.

## 14. Décisions

| Date | Décision | Par |
|---|---|---|
| 21/09/2026 | Le chat se branche sur la donnée réelle et sur une vraie IA côté serveur ; déclencheur : de vrais voyageurs arrivent | Hugo |
| 21/09/2026 | MEMO est le personnage ; les agents de `agents/` travaillent pour lui | Hugo |
| 21/09/2026 | v1 : reformuler + une question précise ; rose/épine/graine juste derrière ; photos et interview en phase 2 | reco Claude, sans objection |
| 21/09/2026 | « Pointe de romance » = liant narratif ; le prompt de rédaction ne bouge pas | Hugo |
| 21/09/2026 | MEMO classe chaque tour : souvenir / précision / commande | Hugo |
| 21/09/2026 | Fil commun aux co-voyageurs, avec les prénoms ; souvenirs sans auteur | Hugo |
| 21/09/2026 | « Ça me convient » = `validatedAt` ; le carnet compose tout, l'aperçu signale | Hugo |
| 21/09/2026 | ~~Une étape offerte = un souvenir validé~~ — remplacée le 03/10/2026 par le crédit du jour (§ 6 bis) | Hugo |
| 21/09/2026 | Accusé immédiat + sondage 2 s ; streaming en phase 2 | Hugo |
| 21/09/2026 | Sonnet 5 converse, Opus 5 rédige ; plafond par jour. (« Réponses incluses » dans les limites de souvenirs : remplacé le 03/10/2026 par le crédit du jour) | Hugo |
| 21/09/2026 | Fiche : le brut d'abord, puis le rédigé | Hugo |
| 21/09/2026 | Un voyage qui a déjà des souvenirs les retrouve dans son fil | Hugo |
| 22/09/2026 | ~~Étape réservée à la création du souvenir, confirmée à la validation~~ — remplacée le 03/10/2026 par le crédit du jour (§ 6 bis) | Hugo |
| 22/09/2026 | Supprimer la conversation : propriétaire seul, 403 pour un co-voyageur | reco Claude |
| 22/09/2026 | Repli heuristique côté serveur ; le moteur local de l'app ne sert plus qu'aux aperçus et aux tests | reco Claude |
| 22/09/2026 | Tout ce qu'on envoie passe par la file de l'accueil ; un vocal de l'accueil va à un seul carnet, le premier en cours | reco Claude |
| 22/09/2026 | `agents/agent-conversation.md` **est** le prompt système, comme `agent-transcription.md` pour la rédaction : on change ce que MEMO dit en éditant du Markdown | reco Claude |
| 22/09/2026 | Le modèle écrit des phrases ; le rythme, le catalogue de puces et la rose/épine/graine restent au code. Une réponse hors contrat est refusée, pas rattrapée | reco Claude |
| 28/09/2026 | Le contexte du voyage avant la première étape : une seule puce à l'ouverture, cinq lignes obligatoires, rien ne devient souvenir (§ 2 bis). Il compte sur le crédit du jour depuis le 03/10/2026 | Paul |
| 28/09/2026 | Le modèle extrait le contexte, le code tient la liste et pose la question — une par tour | reco Claude |
| 22/09/2026 | Effort de réflexion bas pour la conversation (quelqu'un attend), élevé pour la rédaction (personne ne la regarde écrire) | reco Claude |
| 02/10/2026 | Un passage que l'écrivain n'a pas compris ne s'imprime pas : il se cite dans la bulle « Il te convient ? », jamais dans une question de plus | reco Claude |
| 03/10/2026 | Crédit du jour par voyage (5 minutes, oral et écrit, photos gratuites, recharge à minuit) ; abonnement à 4,99 €/mois, illimité pour l'abonné seul ; plus d'étapes offertes, de limites de souvenirs ni d'abonnement à la semaine | Hugo |
| 03/10/2026 | La bulle « reviens demain » est posée par le serveur, une fois par voyage et par jour, avec le bouton `daily_credit_subscribe` ; un abonné ne la voit pas | Hugo |
| 03/10/2026 | MEMO dit les faits du crédit et de l'abonnement quand on les lui demande, jamais de lui-même, sans culpabiliser | Hugo |
| 03/10/2026 | Un bouton au plus sous une bulle, pris dans un catalogue fermé ; l'IA ne choisit que parmi ceux que le code autorise au tour, le code jette le reste | Hugo |
