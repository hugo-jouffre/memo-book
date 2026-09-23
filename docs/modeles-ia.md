# Quel modèle pour quel agent

> Ce que chaque poste du pipeline demande à un modèle, ce que ça coûte, et ce
> qu'on retient. Les tarifs ont été relevés le **23/09/2026** sur les pages
> officielles des quatre fournisseurs ; ils bougent, et ce fichier avec eux.
>
> Les agents eux-mêmes sont décrits dans `agents/` ; la conversation a sa fiche
> produit dans [`conversation.md`](conversation.md). Ici, on ne parle que du
> **choix du moteur**.
>
> ⚠️ **Il n'y a plus de compte OpenAI** (Hugo, 23/09/2026). L'argument « c'est
> déjà dans la maison » ne vaut donc plus pour eux, et deux postes du pipeline
> — la transcription et la structuration — pointent aujourd'hui sur un
> fournisseur qu'on ne paie plus. Le § 3 en tire les conséquences.

## 1. Ce qu'on fait faire à un modèle aujourd'hui

| Poste | Où | Qui le fait | Ce que ça coûte par carnet |
|---|---|---|---|
| **Transcription** d'un vocal | `services/transcription.ts` | OpenAI `gpt-4o-transcribe` — ⚠️ **sans compte** | ~0,13 $ (30 min d'audio) |
| **Rédaction** d'un souvenir | `services/redaction.ts` | Claude Opus 5 | ~2,36 $ (30 souvenirs) |
| **Conversation** — MEMO | `services/conversationAnthropic.ts` | Claude Sonnet 5 | ~0,43 $ (60 tours) |
| **Structuration** | `services/structuring.ts` | OpenAI `gpt-4o` — ⚠️ **sans compte** | marginal |
| **Mise en page** | `services/bookPdf.ts` + APITemplate | pas de modèle | — |
| **Photo** | `agents/agent-photo.md` | non implémenté (phase 2) | — |
| **Modération** | `agents/agent-moderation.md` | non implémenté | — |

**Soit ~2,93 $ de modèles pour un carnet qui se vend 89,90 €** (50 pages).
Trois pour cent du prix de vente.

C'est le chiffre qui doit gouverner toutes les décisions de ce fichier, et il
dit deux choses en sens inverse :

1. **Économiser sur la rédaction n'a aucun sens.** C'est 80 % du coût modèle,
   mais 2,6 % du prix de vente — et c'est ce que les gens achètent. Diviser
   cette ligne par deux rapporte 1,20 € par carnet et met en jeu la seule chose
   qui justifie le prix.
2. **Économiser sur la conversation en a encore moins.** 43 ¢ par carnet. Passer
   au modèle le moins cher du marché ferait gagner 41 ¢ — sur un produit à
   90 €.

La question « quel modèle » n'est donc **pas une question de coût** tant que le
volume reste celui d'un produit qui se vend à l'unité. Elle le deviendra le jour
où le chat sera gratuit et illimité pour des gens qui n'achètent pas de carnet :
c'est le seul scénario qui renverse le calcul, et il est nommé en § 5.

## 2. Ce que coûte un tour, et un souvenir

Aux tarifs du 23/09/2026, pour **nos** prompts — le système de la rédaction fait
12 530 jetons, celui de la conversation 3 900, tous deux mis en cache :

| Modèle | Un tour de MEMO | Un souvenir rédigé | 60 tours + 30 souvenirs |
|---|---|---|---|
| **Claude Opus 5** *(rédige aujourd'hui)* | 1,80 ¢ | 7,88 ¢ | 3,44 $ |
| Claude Opus 5.5 | 1,36 ¢ | 6,05 ¢ | 2,63 $ |
| **Claude Sonnet 5** *(converse aujourd'hui)* | 0,72 ¢ | 3,15 ¢ | 1,38 $ |
| Claude Haiku 4.5 | 0,36 ¢ | 1,58 ¢ | 0,69 $ |
| GPT-6 Astra | 3,59 ¢ | 15,75 ¢ | 6,88 $ |
| GPT-6 Sol | 0,72 ¢ | 3,15 ¢ | 1,38 $ |
| GPT-6 Luna | 0,04 ¢ | 0,16 ¢ | 0,07 $ |
| Gemini 3.8 Flash | 0,27 ¢ | 1,18 ¢ | 0,52 $ |
| Gemini 3.5 Flash-Lite | 0,15 ¢ | 0,72 ¢ | 0,31 $ |
| Gemini 3.1 Pro | 0,80 ¢ | 3,65 ¢ | 1,57 $ |
| Mistral Medium 3.5 | 0,54 ¢ | 2,36 ¢ | 1,03 $ |
| Mistral Large 3 | 0,14 ¢ | 0,54 ¢ | 0,24 $ |
| Mistral Small 4 | 0,05 ¢ | 0,20 ¢ | 0,09 $ |

Hypothèses, pour pouvoir refaire le calcul : un tour de conversation lit 3 900
jetons de cache, 1 200 jetons frais (le fil, la fiche de cohérence, le souvenir
en cours) et en produit 400 ; un souvenir lit 12 530 jetons de cache, 2 000
frais, et en produit 2 500 réflexion comprise. Le jour où de vrais relevés
existent (`usage` est déjà dans chaque réponse), ils remplacent ces estimations.

## 3. Poste par poste

### La rédaction — **Claude Opus 5**, et surveiller Opus 5.5

C'est **le** poste qui fait le produit. `agents/agent-transcription.md` demande
un exercice difficile : corriger sans effacer, alléger sans lisser, ne rien
inventer, tenir une fiche de cohérence sur vingt étapes, et écrire un français
impeccable. C'est là que les modèles se séparent vraiment, et c'est la dernière
ligne où il faut chercher à économiser.

**On garde Opus 5.** Le seul changement qui vaut d'être regardé tout de suite est
**Opus 5.5** : même famille, même API, même prompt, aucun portage — et 6,05 ¢
contre 7,88 ¢ par souvenir (‑23 %), grâce à un cache cinq fois moins cher. À
valider sur une dizaine de souvenirs réels avant de basculer.

Les alternatives crédibles en qualité (GPT-6 Astra, Gemini 3.1 Pro) coûtent
deux fois plus cher ou demandent de réécrire le prompt pour un autre dialecte de
sortie structurée. Aucune raison d'y toucher aujourd'hui.

### La conversation — **Claude Sonnet 5**, et Haiku 4.5 en réserve

Contraintes : quelqu'un attend devant son écran (donc la latence compte), le
français doit être impeccable, et le contrat est exigeant — **une seule
question**, ne rien inventer, classer le tour en souvenir / précision /
commande, ne jamais insister après un refus. C'est de la tenue d'instruction,
pas de la génération libre, et c'est exactement ce que les classements publics
mesurent mal.

**On garde Sonnet 5**, parce que 43 ¢ par carnet ne se discutent pas et que le
prompt a été écrit et calibré pour lui.

Si le volume change la donne, le bon réflexe n'est **pas** de changer de
fournisseur mais de descendre d'un cran dans la même famille : **Haiku 4.5**
coûte la moitié, parle la même API, lit le même prompt, utilise le même cache —
le portage est d'une ligne dans `.env`. C'est le test à faire en premier.

Un second fournisseur reste intéressant pour une autre raison que le prix : voir
§ 4.

### La transcription — **il faut déménager**

Le code appelle `gpt-4o-transcribe`, et il n'y a plus de compte OpenAI : ce
poste est le **premier maillon** de tout le pipeline, et il est aujourd'hui sans
moteur. C'est le seul point de ce fichier qui soit urgent — pas pour des raisons
de prix, parce que sans lui rien ne marche.

Deux successeurs, tous deux moins chers que ce qu'on payait :

| Candidat | Prix | Ce qui le recommande |
|---|---|---|
| **Voxtral Mini Transcribe 2** (Mistral) | 0,003 $/min | Européen, modèle français, inférence régionale UE possible (+10 %). Ferme aussi la question du § 5 |
| **Gemini 3.5 Transcribe** (Google) | 0,003 $/min | Même prix, gros fournisseur, mais même problème d'hébergement qu'aujourd'hui |

**Reco : Voxtral**, et pas seulement parce qu'il est moins cher — si la
transcription et la rédaction devaient un jour rester en Europe, c'est par là
qu'on commence.

⚠️ Changer de transcripteur ne se décide pas sur une fiche produit : il faut
l'essayer sur de **vrais vocaux de testeurs** — accents, bruit de rue, noms de
lieux italiens, phrases qui s'arrêtent en route. Le banc du § 6 ne teste pas ça.
Prendre cinq vocaux, les passer dans les deux, lire les deux transcriptions
côte à côte.

### La structuration — **elle déménage avec la transcription**

`gpt-4o` fait la tâche la plus mécanique de la pile, et il est sur le compte
qui n'existe plus. Comme c'est du travail sans finesse — découper, ranger,
nommer —, n'importe quel petit modèle récent fait l'affaire : **Mistral Small 4**
(0,15 $/M) ou **Gemini 3.5 Flash-Lite** (0,30 $/M).

Prendre le **même fournisseur que la transcription** : un contrat de moins à
tenir, et c'est le poste où la qualité du moteur ne se voit pas.

### La modération — **Mistral Moderation 2, parce qu'elle est gratuite**

`agents/agent-moderation.md` n'est pas implémenté, et c'est un dernier filtre
avant impression : il ne demande pas de génie, il demande d'être rapide,
systématique et gratuit. **Mistral Moderation 2 est facturée zéro.** Quand ce
poste sera construit, c'est là qu'il faut commencer — et c'est aussi la porte
d'entrée la moins risquée pour un second fournisseur dans la maison.

### La photo — **à trancher le jour venu**

Phase 2. C'est de la vision sur un volume potentiellement gros (une pellicule
entière). Les modèles Flash de Google sont taillés pour ça et peu chers ; Claude
sait le faire aussi. Rien à décider avant que l'agent existe.

### ⚠️ Un piège de configuration, créé par le départ d'OpenAI

`env.live` — ce qui décide si le pipeline tourne pour de vrai — se calcule
ainsi (`src/env.ts`) :

```ts
const hasLiveKeys = env.OPENAI_API_KEY !== "" && env.APITEMPLATE_API_KEY !== "";
```

Et `createResponder` rend `FakeResponder` quand `!env.live`. Autrement dit :
**sans clé OpenAI, MEMO parle en simulé même avec une clé Anthropic valide**, et
rien ne le dit à l'écran — les réponses sont plausibles, c'est ça le piège.

Le correctif tient en quelques lignes : la conversation doit dépendre de **sa**
clé, pas de celle d'un autre poste. `PIPELINE_MODE=fake` doit continuer à vouloir
dire « personne n'appelle personne ».

## 4. Un second fournisseur, mais pour la bonne raison

Aujourd'hui, quand MEMO tombe, c'est le **moteur de règles** qui répond
(`HeuristicResponder`). Il est honnête, il ne ment jamais, et il est rustique :
sur la scène 02 du banc, le voyageur répond « à Trastevere, avec Clara » et il
redemande « c'était où, exactement ? ».

Un second fournisseur ferait un bien meilleur filet : **Claude → l'autre → les
règles**. Le point d'entrée existe déjà et il est unique
(`fallbackResponder()`), le coût est d'une classe de ~150 lignes, et ça protège
contre la seule panne qu'on ne sait pas encaisser — une indisponibilité longue
d'un fournisseur pendant que des gens racontent leur voyage.

C'est le seul argument qui justifie vraiment d'ouvrir un second contrat
aujourd'hui. Le prix, non.

## 5. Ce qui n'est pas une question de prix

**L'hébergement des données.** MemoBook garde des récits intimes — des gens, des
dates, des adresses, des engueulades — et les imprime. Deux faits relevés le
23/09/2026 :

- L'API Claude **première partie** ne propose que deux géographies d'inférence,
  `global` et `us`, et le stockage au repos est aux États-Unis. Il n'y a **pas**
  d'option « Europe » chez Anthropic en direct : elle passe par Bedrock ou
  Vertex en région européenne.
- **Mistral** propose une inférence régionale européenne, facturée +10 %.

Ça ne rend rien illégal — des transferts encadrés, ça existe. Mais ça décide de
ce qu'on a le droit d'**écrire sur la page de vente**. « Vos souvenirs ne
quittent pas l'Europe » est une promesse commerciale, pas une préférence
technique, et aujourd'hui on ne peut pas la tenir. Si Hugo veut la tenir, ça
change le choix du moteur de la rédaction et de la transcription — pas l'inverse.

Le départ d'OpenAI rapproche cette question : il faut de toute façon rebrancher
la transcription, et le candidat recommandé (Voxtral) est justement celui qui
ouvre la porte européenne. Autant décider maintenant, pendant qu'on y est.

**Le scénario qui renverse le calcul du § 1** : un chat gratuit et illimité,
ouvert à des gens qui ne commandent pas de carnet. Le coût passe alors de « 43 ¢
sur une vente à 90 € » à « 43 ¢ par curieux ». C'est le jour où Haiku 4.5, Gemini
Flash-Lite ou Mistral Small 4 deviennent des questions sérieuses — et où le
plafond quotidien (`CHAT_DAILY_TURN_CAP`) devient une vraie défense et pas une
ceinture anti-abus.

## 6. Comment re-trancher, sans rien croire sur parole

Les classements publics ne disent presque rien de ce qu'on demande ici : du
français exigeant, une tenue d'instruction stricte, un classement fiable. Ce qui
tranche, c'est le banc :

```bash
cd backend && npm run conversation:eval                  # le modèle en place
cd backend && npm run conversation:eval -- --heuristic   # l'étalon sans modèle
```

Dix scènes, la même grille, la même sortie. Comparer deux modèles, c'est écrire
une classe à côté de `AnthropicResponder` et relancer le banc sur les mêmes
scènes — pas lire un benchmark.

Ce qu'un fournisseur doit savoir faire pour entrer dans cette pile, et qu'il faut
vérifier **avant** d'écrire la classe :

| Besoin | Où c'est utilisé | Pourquoi ça bloque si ça manque |
|---|---|---|
| Sortie **JSON contrainte par schéma** | rédaction, conversation, structuration | Sans elle, on reparse du texte libre et on réintroduit les pannes qu'on a supprimées |
| **Cache de prompt système** | rédaction (12 530 jetons), conversation (3 900) | Sans lui, les prix du § 2 sont faux : le système se repaie à chaque appel |
| Un **refus** distinguable d'une réponse | les deux | Sans lui, un refus se lit comme une réponse vide et l'écran ment |
| Un **effort de réflexion réglable** | bas pour la conversation, haut pour la rédaction | C'est ce qui sépare « MEMO répond en 2 s » de « MEMO réfléchit dix secondes » |

Et les points de branchement, tous identiques : une interface, une classe, une
fabrique — `Transcriber`/`createTranscriber`, `Redactor`/`createRedactor`,
`MemoResponder`/`createResponder`. Rien d'autre ne bouge : ni les routes, ni les
jobs, ni l'app.

## 7. Décisions

| Date | Décision | Par |
|---|---|---|
| 23/09/2026 | Le coût modèle est ~3 % du prix d'un carnet : le choix du moteur se décide sur la **qualité** et l'**hébergement**, pas sur le prix, tant que le carnet se vend à l'unité | reco Claude |
| 23/09/2026 | La rédaction reste sur Opus 5 — c'est ce que les gens achètent. Regarder Opus 5.5 (‑23 %, aucun portage) sur des souvenirs réels | reco Claude |
| 23/09/2026 | La conversation reste sur Sonnet 5. Si le volume l'exige, descendre à Haiku 4.5 **avant** d'envisager un autre fournisseur : même API, même prompt, moitié prix | reco Claude |
| 23/09/2026 | Un second fournisseur se justifie comme **repli** (Claude → l'autre → les règles), pas comme économie | reco Claude |
| 23/09/2026 | La modération, quand elle sera construite, part sur Mistral Moderation 2 — gratuite, et c'est le bon usage d'un second fournisseur | reco Claude |
| 23/09/2026 | « Vos souvenirs ne quittent pas l'Europe » n'est pas tenable aujourd'hui : à décider comme argument commercial avant de changer de moteur | à trancher — Hugo |
| 23/09/2026 | **Plus de compte OpenAI.** L'argument « déjà dans la maison » ne vaut plus, et deux postes pointent sur un fournisseur qu'on ne paie plus | Hugo |
| 23/09/2026 | La transcription déménage sur **Voxtral Mini Transcribe 2** — moins cher, et c'est la porte européenne. À essayer sur cinq vocaux de testeurs avant de basculer | reco Claude |
| 23/09/2026 | La structuration suit la transcription chez le même fournisseur : un contrat de moins, et la qualité du moteur ne s'y voit pas | reco Claude |
| 23/09/2026 | `env.live` dépend de la clé OpenAI : sans elle, MEMO répond en simulé même avec une clé Anthropic. À découpler | reco Claude |

## Sources

Relevées le 23/09/2026 sur les pages officielles :

- [Tarifs Claude](https://platform.claude.com/docs/en/about-claude/pricing) et
  [résidence des données](https://platform.claude.com/docs/en/manage-claude/data-residency)
- [Tarifs OpenAI](https://developers.openai.com/api/docs/pricing)
- [Tarifs Gemini](https://ai.google.dev/gemini-api/docs/pricing)
- [Tarifs Mistral](https://mistral.ai/pricing/api/)
