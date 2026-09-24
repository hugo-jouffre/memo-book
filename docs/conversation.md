# La conversation avec MEMO

> Ce que fait le chat, ce qu'il fait d'un vocal, ce que MEMO dit et ne dit
> jamais, et ce qui reste à construire pour qu'il fonctionne réellement.
>
> Écrit le 22/09/2026 avec Hugo, à partir de l'état du code (`main @ c64a0c8`)
> et des décisions listées en fin de fichier. Le ticket Notion « Module
> Conversation avec MEMO » renvoie ici : **ce fichier fait foi**, Notion en est
> la copie que Hugo partage. La fiche d'écran (mesures, composants, états) reste
> dans `ui-development.md` § 14 ; ce document dit le **produit** et le
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
  seule voix (`agent-transcription.md` § 2).
- **MEMO parle le premier**, une seule bulle d'ouverture, qui se termine déjà
  par une question. La relance du jour (« Comment ça se passe à Trastevere ? »)
  ne vient **jamais** dans le fil : elle est faite pour la carte de l'accueil du
  voyage et pour la notification qui la portera un jour.
- **Un voyage qui a déjà des souvenirs** (racontés depuis l'accueil, avant que
  le chat existe) les retrouve dans son fil : une bulle par souvenir, suivie de
  sa fiche, dans l'ordre des dates. Les réponses passées de MEMO n'existent pas ;
  seule l'ouverture précède.

## 3. Le tour type

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
précisions marquées `rose_epine_graine` ; la rédaction en fait l'encart prévu
(`agent-transcription.md` § 5).

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

Après un vocal, MEMO pose une fiche « Retranscription du contexte » — date,
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
| **Ça me convient** 👌 | Le souvenir est **validé** (`validatedAt`). MEMO : « C'est enregistré. Ton carnet compte une étape de plus. » |
| **J'aimerais faire des modifications à la main** ✍️ | Le texte de la fiche est déjà dans le champ, qui prend toute la barre. Envoyer **corrige le souvenir** (`editedText`) : la fiche change, MEMO dit « Je te laisse la main. Ta version fait autorité sur la mienne, je n'y retouche plus. » Un texte corrigé est intouchable (ADR-007) |
| **J'aimerais faire des modifications à l'oral** 🎙 | **Phase 2.** Aujourd'hui MEMO dit « Je t'écoute » et le vocal suivant est un **nouveau** souvenir, pas une révision. Le dire, pour que personne ne le prenne pour un bug |

**Le carnet n'attend pas la validation.** Il se compose avec tous les
souvenirs ; l'aperçu signale ceux qui n'ont pas été relus. Un voyageur qui
oublie de valider n'a pas un carnet vide.

**Les étapes offertes.** Un compte gratuit a trois étapes offertes. **Une étape
= un souvenir.** Elle est **réservée à la création** du souvenir et **confirmée
à la validation** : avec trois offertes, le quatrième souvenir est refusé même
si aucun n'a été validé (« Tes étapes offertes sont toutes racontées :
abonne-toi pour continuer ton carnet. »). Valider décrémente le compteur.
Une précision, une photo, une commande ne coûtent rien. Un abonné n'a pas de
compteur.

**Les limites de souvenirs** (le garde-fou de coût, hebdomadaire) ne changent
pas : un texte vaut 1, une minute entamée de vocal vaut 10, une photo rien —
et **les réponses de MEMO sont incluses**, le voyageur paie ce qu'il raconte,
jamais ce qu'on lui répond. Un plafond anti-abus par carnet et par jour (150
tours) ferme la porte à un script, pas à un voyageur.

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

Ce que le fil ne fait pas : s'ouvrir sans réseau. Il n'est jamais mis en cache
(§ 2), donc un fil qu'on n'a pas encore chargé ne se charge pas dans le
métro ; ce qu'on y a dit avant la coupure, en revanche, reste sous les yeux.

## 10. Ce que MEMO ne fait jamais

- Inventer — un lieu, une météo, un prénom complété, un fait.
- Poser deux questions.
- Dépasser trois phrases.
- Insister après un refus.
- Rédiger le carnet (c'est l'écrivain), le mettre en page (c'est la mise en
  page), choisir des photos (phase 2).
- Parler d'argent, de quota, de jetons. Le mot « token » n'existe pas dans
  l'app.
- Vouvoyer.

## 11. Phase 2 — explicitement pas maintenant

- La réponse **mot à mot** (streaming) : la bulle s'écrit sous les yeux.
- **Proposer des photos** au souvenir (Agent Photo).
- **L'interview avant le départ** : pour un voyage à venir, MEMO pose les
  questions de contexte (rythme, avec qui, ce qu'on attend) qui donnent le ton
  du carnet — le cahier des charges le voulait.
- **« À l'oral » comme révision** d'un souvenir existant.
- **La notification** de relance, cadencée par le rythme du récit.
- Une **seconde réponse** quand le modèle finit après le repli.

## 12. Le contrat, en bref

| Pièce | Où | Quoi |
|---|---|---|
| Le fil | `backend/prisma/schema.prisma` → `chat_messages` | Un message par tour, adossé au carnet et au souvenir. `seq` est la seule vérité sur l'ordre |
| Lire le fil | `GET /v1/trips/:id/chat` (+ `?since=`) | Le `ChatThread` de `MemoBookCore/Chat.swift`, au champ près ; la fiche recalculée depuis `entries` ; les souvenirs sans message reconstruits |
| Un tour | `POST /v1/trips/:id/chat` | JSON pour un texte ou une puce, multipart pour un vocal ou des photos ; `id` fourni par l'app (idempotent) ; 201 tout de suite |
| Valider | `POST /v1/entries/:id/validate` | `validatedAt`, décrémente l'étape offerte |
| Corriger | `PATCH /v1/entries/:id` (existe) | `editedText` |
| Supprimer | `DELETE /v1/trips/:id/chat` | Propriétaire seul, 403 sinon |
| Répondre | job `memobook.converse` | `AnthropicResponder` (Sonnet 5, prompt = `agents/agent-conversation.md`, sortie JSON contrainte) → repli `HeuristicResponder` sans clé Anthropic → `FakeResponder` sous `PIPELINE_MODE=fake`, en CI et dans les tests |
| Écrire | jobs `transcribe` → `redact` (existent) | La rédaction relit les précisions du fil |

Le détail — champs, codes d'erreur, tests, phasage en quatre PR — est dans le
plan de la branche `atelier-conversation` et sera reporté dans
`ui-development.md` § 14.1 à mesure. Le choix du moteur lui-même — pourquoi
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

### L'outil de relecture

```bash
cd backend && npm run conversation:eval            # Claude, sur toutes les scènes
cd backend && npm run conversation:eval -- --heuristic   # le moteur de règles, sans clé
```

Le script (`backend/scripts/conversation-eval.ts`) fait parler MEMO sur les
scènes de `backend/test/fixtures/conversation/` — dix situations du contrat :
un vocal riche, une précision courte, un refus, une journée difficile, une
question sur le produit, une transcription échouée, des photos, la
rose/épine/graine, une question déjà répondue, un carnet à plusieurs. Il
n'écrit rien en base, et **ce n'est pas un test** : il n'appelle que le
répondeur.

Quatre des sept lignes de la grille se vérifient à la machine, et le script les
coche tout seul : une seule question, trois bulles au plus, le tutoiement, la
relance qui se lit seule — plus les mots interdits, le Markdown, les puces hors
catalogue, le classement attendu, et « la reformulation garde un mot du
voyageur ». Les trois qui restent se lisent : **aucun fait inventé**, **la
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
| 21/09/2026 | Une étape offerte = un souvenir validé | Hugo |
| 21/09/2026 | Accusé immédiat + sondage 2 s ; streaming en phase 2 | Hugo |
| 21/09/2026 | Sonnet 5 converse, Opus 5 rédige ; réponses incluses ; plafond par jour | Hugo |
| 21/09/2026 | Fiche : le brut d'abord, puis le rédigé | Hugo |
| 21/09/2026 | Un voyage qui a déjà des souvenirs les retrouve dans son fil | Hugo |
| 22/09/2026 | Étape réservée à la création du souvenir, confirmée à la validation — sinon un compte gratuit raconte sans fin | Hugo |
| 22/09/2026 | Supprimer la conversation : propriétaire seul, 403 pour un co-voyageur | reco Claude |
| 22/09/2026 | Repli heuristique côté serveur ; le moteur local de l'app ne sert plus qu'aux aperçus et aux tests | reco Claude |
| 22/09/2026 | Tout ce qu'on envoie passe par la file de l'accueil ; un vocal de l'accueil va à un seul carnet, le premier en cours | reco Claude |
| 22/09/2026 | `agents/agent-conversation.md` **est** le prompt système, comme `agent-transcription.md` pour la rédaction : on change ce que MEMO dit en éditant du Markdown | reco Claude |
| 22/09/2026 | Le modèle écrit des phrases ; le rythme, le catalogue de puces et la rose/épine/graine restent au code. Une réponse hors contrat est refusée, pas rattrapée | reco Claude |
| 22/09/2026 | Effort de réflexion bas pour la conversation (quelqu'un attend), élevé pour la rédaction (personne ne la regarde écrire) | reco Claude |
