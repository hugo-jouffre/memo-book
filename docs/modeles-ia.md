# Quel modèle pour quel agent

> Ce que chaque poste du pipeline demande à un modèle, ce que ça coûte, et ce
> qu'on retient. Tarifs relevés le **23/09/2026** sur les pages officielles des
> quatre fournisseurs ; ils bougent, et ce fichier avec eux.
>
> Les agents sont décrits dans `agents/` ; la conversation a sa fiche produit
> dans [`conversation.md`](conversation.md). Ici, on ne parle que du **choix du
> moteur**.
>
> Réécrit le 23/09/2026 : **il n'y a plus de compte OpenAI** (Hugo). Deux postes
> pointaient dessus, et l'argument « c'est déjà dans la maison » — qui pesait
> dans la version précédente — ne vaut plus rien.

## 1. Le point de départ : un second fournisseur n'est pas un choix

**L'API Claude ne prend pas d'audio en entrée.** Texte et images, pas de son :
transcrire demande donc un autre fournisseur, quoi qu'on décide par ailleurs.
Ce n'est pas une préférence, c'est une contrainte de la pile.

La vraie question n'est donc pas « faut-il un second fournisseur ? » mais
**« lequel, et pour quoi ? »**. Et comme il sera là de toute façon, autant lui
confier tout ce qui n'a pas besoin du meilleur modèle du monde.

Voilà l'état des lieux, une fois OpenAI parti :

| Poste | Où | Qui le fait | Statut |
|---|---|---|---|
| **Transcription** d'un vocal | `services/transcription.ts` | `gpt-4o-transcribe` | ⚠️ **sans compte** — premier maillon, à rebrancher |
| **Structuration** avant rendu | `services/structuring.ts` | `gpt-4o` | ⚠️ **sans compte** |
| **Rédaction** d'un souvenir | `services/redaction.ts` | Claude Opus 5 | en place |
| **Conversation** — MEMO | `services/conversationAnthropic.ts` | Claude Sonnet 5 | en place |
| **Mise en page** | `services/bookPdf.ts` + APITemplate | pas de modèle | en place |
| **Photo** | `agents/agent-photo.md` | — | phase 2 |
| **Modération** | `agents/agent-moderation.md` | — | jamais construit |

Le second fournisseur hérite donc de **quatre** postes : transcription,
structuration, modération le jour où elle existe, et — s'il est bon — le
**repli** de MEMO (§ 6). Plus la photo en phase 2. Ça change la question :
on ne choisit pas un transcripteur, on choisit un colocataire.

## 2. Le prix ne tranche rien, et c'est démontrable

Trois scénarios, pour un carnet complet — 30 souvenirs, 30 minutes d'audio,
60 tours de conversation, 2 rendus :

| Scénario | Total | Rédaction | MEMO | Transcription | Structuration |
|---|---|---|---|---|---|
| **A — Mistral en second** | **2,90 $** | 2,36 $ | 0,43 $ | 0,09 $ | 0,01 $ |
| **B — Google en second** | **2,93 $** | 2,36 $ | 0,43 $ | 0,09 $ | 0,04 $ |
| **C — retour chez OpenAI** | **2,94 $** | 2,36 $ | 0,43 $ | 0,13 $ | 0,01 $ |

**Quatre centimes d'écart sur un carnet qui se vend 89,90 €.** Le prix ne
décide pas ; il valide seulement qu'aucun candidat n'est disqualifié.

Deux choses que ce tableau rend visibles :

- **La rédaction est 81 % du coût modèle** — et 2,6 % du prix de vente. C'est
  là qu'il ne faut pas économiser : c'est ce que les gens achètent.
- **La structuration n'était pas « marginale »**, contrairement à ce que disait
  la version précédente de ce fichier. Elle relit toute la base de connaissances
  de mise en page et recrache le payload entier : **10,7 ¢ par rendu** avec
  `gpt-4o`, soit 21 ¢ pour deux rendus — 7 % du coût modèle pour la tâche la
  plus mécanique de la pile. Avec un petit modèle récent, elle tombe à 1 ¢.

### Le détail, par poste

| Poste | Aujourd'hui | Mistral | Google | OpenAI |
|---|---|---|---|---|
| Transcription (30 min) | 13,5 ¢ | **9,0 ¢** (Voxtral Mini Transcribe 2) | **9,0 ¢** (Gemini 3.5 Transcribe) | 13,5 ¢ (gpt-transcribe) |
| Structuration (1 rendu) | 10,7 ¢ | **0,6 ¢** (Small 4) | 2,1 ¢ (Flash-Lite) | **0,5 ¢** (GPT-6 Luna) |
| Modération | — | **gratuite** (Moderation 2) | non publiée | non publiée |
| Repli de MEMO (1 tour) | — | 0,54 ¢ (Medium 3.5) | 0,27 ¢ (3.8 Flash) | 0,72 ¢ (GPT-6 Sol) |

## 3. Ce qui tranche vraiment

Cinq critères, dans l'ordre où je les ferais peser.

### a. La qualité de la transcription en français — **le seul vrai risque**

C'est le **premier maillon** : une transcription qui rate un prénom ou un nom
de lieu fait un souvenir faux, que la rédaction propagera fidèlement et que le
carnet imprimera. Aucun autre poste n'a ce pouvoir de nuisance.

Et c'est précisément ce que les fiches produit ne disent pas. Tes vocaux sont
du français parlé, dehors, avec des noms de lieux italiens, des phrases qui
s'arrêtent en route et des « euh ». Un benchmark de laboratoire ne prédit rien
de ça.

**Personne ne peut trancher ce point sur le papier — il faut l'essayer.**

### b. L'hébergement — le seul critère qui soit un argument de vente

MemoBook garde des récits intimes et les imprime. Or :

- L'API Claude **première partie** n'offre que deux géographies, `global` et
  `us`, et le stockage au repos est aux États-Unis. Pas d'option européenne en
  direct — elle passerait par Bedrock ou Vertex en région UE.
- **Mistral** propose une inférence régionale européenne (+10 %).
- Google et OpenAI ont des régions européennes, avec la même mécanique de
  contrats que n'importe quel hyperscaler américain.

Rien d'illégal dans aucun cas. Mais « vos souvenirs ne quittent pas l'Europe »
est une phrase qu'on met sur une page de vente, et aujourd'hui elle est
intenable. Si elle t'intéresse, elle se décide **maintenant** : tu dois
rebrancher la transcription de toute façon, et l'un des candidats est justement
celui qui ouvre cette porte.

### c. Ce que le colocataire saura faire plus tard

Le second fournisseur ne fait pas que transcrire ; il hérite de ce qui vient.

- **La modération** (`agent-moderation.md`, jamais construite) est un dernier
  filtre avant impression : rapide, systématique, sans finesse. **Mistral la
  facture zéro.** C'est un poste entier qui devient gratuit.
- **La photo** (phase 2) est de la vision sur une pellicule entière. C'est là
  que **Google** est le plus fort et le moins cher — et c'est le seul argument
  sérieux en sa faveur.

### d. Le repli de MEMO

Aujourd'hui, quand Claude tombe, c'est le moteur de règles qui répond. Il ne
ment jamais, mais il est rustique : sur la scène 02 du banc, le voyageur dit
« à Trastevere, avec Clara » et il redemande « c'était où, exactement ? ».

Un second modèle ferait un bien meilleur filet — **Claude → le colocataire →
les règles** —, et le point de branchement existe déjà (`fallbackResponder()`).
Les deux candidats savent le faire ; ça ne les départage pas, mais ça ajoute une
raison de ne pas prendre le moins bon.

### e. Le nombre de contrats

Un fournisseur de plus, c'est une facture, un statut de service, une panne et
une clé de plus. Ce critère ne dit pas *lequel* choisir — il dit qu'on n'en
prend **qu'un**, et qu'on lui donne tout ce qu'il sait faire.

## 4. Ce que je recommande, et pourquoi

**Mistral en second fournisseur**, sous condition d'essai.

L'argument n'est pas le prix — on a vu qu'il n'y en a pas. Il tient en trois
points :

1. **Il ferme une question produit que personne d'autre ne ferme.** L'inférence
   européenne est disponible chez lui seul parmi les candidats « par défaut »,
   et elle porte sur le poste le plus sensible : l'audio brut de quelqu'un qui
   raconte sa vie. C'est le seul critère de cette liste qui se transforme en
   phrase sur une page de vente.
2. **Il rend un poste entier gratuit.** La modération n'existe pas encore ;
   avec lui, elle naîtra sans ligne de facture. Sur un produit qui imprime, ce
   filtre finira par être obligatoire.
3. **Il est français, sur une tâche française.** Ce n'est pas un argument
   patriotique : le français parlé, avec ses élisions et ses accents, est le
   cœur de cible d'un modèle de parole entraîné en France. C'est une hypothèse,
   pas une certitude — d'où l'essai du § 7.

**Ce qui plaide contre, honnêtement** : si l'agent Photo devient une pièce
centrale du produit, Google est meilleur et moins cher en vision. Tu te
retrouverais soit avec un troisième fournisseur, soit avec une vision Mistral
moins bonne. C'est le vrai arbitrage, et il dépend d'une chose que tu sais mieux
que moi : est-ce que MemoBook devient un produit de **photos** ou reste un
produit de **récit** ?

Tant que c'est du récit, Mistral. Si la photo passe devant, Google.

### Et les autres postes ne bougent pas

- **Rédaction : Claude Opus 5.** C'est le produit. Seule chose à regarder :
  **Opus 5.5**, ‑23 % (6,05 ¢ contre 7,88 ¢ par souvenir), même famille, même
  prompt, aucun portage. À valider sur dix souvenirs réels.
- **Conversation : Claude Sonnet 5.** 43 ¢ par carnet ne se discutent pas, et
  le prompt a été écrit pour lui. Si le volume l'exigeait un jour, on descend à
  **Haiku 4.5** (moitié prix, une ligne dans `.env`) **avant** de penser à
  changer de maison.

## 5. Un piège de configuration, créé par le départ d'OpenAI — corrigé

`env.live` — ce qui décide si le pipeline tourne pour de vrai — se calcule ainsi
(`src/env.ts`) :

```ts
const hasLiveKeys = env.OPENAI_API_KEY !== "" && env.APITEMPLATE_API_KEY !== "";
```

`createResponder` rendait `FakeResponder` dès que `!env.live`. Autrement dit :
**sans clé OpenAI, MEMO parlait en simulé même avec une clé Anthropic valide**,
et rien ne le disait à l'écran — les réponses restaient plausibles, c'est ça le
piège. Le jour où la transcription déménage, plus personne n'a de clé OpenAI :
le piège se serait refermé sur tout le monde en même temps.

Corrigé le **24/09/2026** (`src/services/conversation.ts`) : la conversation
dépend de **sa** clé, pas de celle d'un autre poste.

```ts
if (env.PIPELINE_MODE === "fake") return new FakeResponder();
if (env.ANTHROPIC_API_KEY === "") return env.live ? new HeuristicResponder() : new FakeResponder();
return new AnthropicResponder(…);
```

Seul `PIPELINE_MODE=fake` — « personne n'appelle personne » — coupe encore
Claude ; c'est ce que posent la CI et `test/helpers.ts`, donc le modèle n'entre
toujours pas en CI.

## 6. Ce qu'un fournisseur doit savoir faire pour entrer ici

À vérifier **avant** d'écrire la classe :

| Besoin | Où | Pourquoi ça bloque si ça manque |
|---|---|---|
| Sortie **JSON contrainte par schéma** | rédaction, conversation, structuration | Sans elle, on reparse du texte libre et on réintroduit les pannes qu'on a supprimées |
| **Cache de prompt système** | rédaction (12 530 jetons), conversation (3 900) | Sans lui, les prix du § 2 sont faux : le système se repaie à chaque appel |
| Un **refus** distinguable d'une réponse | les deux | Sans lui, un refus se lit comme une réponse vide et l'écran ment |
| Un **effort de réflexion réglable** | bas pour MEMO, haut pour la rédaction | C'est ce qui sépare « MEMO répond en 2 s » de « MEMO réfléchit dix secondes » |

Les points de branchement sont identiques partout : une interface, une classe,
une fabrique — `Transcriber`/`createTranscriber`, `Redactor`/`createRedactor`,
`MemoResponder`/`createResponder`. Ni les routes, ni les jobs, ni l'app ne
bougent.

## 7. Comment trancher pour de bon

Le seul point qui reste ouvert est le seul qui compte : **Voxtral tient-il sur
tes vocaux ?**

1. Prendre **cinq vocaux de testeurs**, les plus ingrats : dehors, à plusieurs,
   avec des noms propres.
2. Les passer dans Voxtral Mini Transcribe 2 **et** Gemini 3.5 Transcribe.
3. Lire les deux transcriptions côte à côte, et compter ce qui compte : les
   prénoms, les noms de lieux, les chiffres. Le reste, la rédaction le rattrape.
4. Si Voxtral tient → Mistral en second, et la question européenne se pose
   sérieusement. S'il déçoit → Google, et on oublie l'argument UE.

Pour MEMO, le banc existe déjà et ne dépend d'aucun de ces choix :

```bash
cd backend && npm run conversation:eval                  # le modèle en place
cd backend && npm run conversation:eval -- --heuristic   # l'étalon sans modèle
```

## 8. Décisions

| Date | Décision | Par |
|---|---|---|
| 23/09/2026 | Plus de compte OpenAI. Deux postes — transcription, structuration — sont sans moteur | Hugo |
| 23/09/2026 | L'API Claude ne prend pas d'audio : un second fournisseur est une **contrainte**, pas une option. On n'en prend qu'un, et il hérite de tout ce qu'il sait faire | reco Claude |
| 23/09/2026 | Le coût modèle est ~3 % du prix d'un carnet, et les trois scénarios tiennent en 4 ¢ : le choix se décide sur la **qualité de transcription** et l'**hébergement**, pas sur le prix | reco Claude |
| 23/09/2026 | **Mistral en second fournisseur** — inférence européenne, modération gratuite, français natif — **sous réserve** de l'essai du § 7 | reco Claude |
| 23/09/2026 | Google passe devant si l'agent Photo devient central : c'est le seul poste où il est franchement meilleur | reco Claude |
| 23/09/2026 | La rédaction reste sur Opus 5 ; regarder Opus 5.5 (‑23 %, aucun portage) | reco Claude |
| 23/09/2026 | La conversation reste sur Sonnet 5 ; descendre à Haiku 4.5 avant d'envisager un autre fournisseur | reco Claude |
| 24/09/2026 | `env.live` ne décide plus qui parle : MEMO répond dès qu'il a **sa** clé, même sans clé OpenAI. Seul `PIPELINE_MODE=fake` le coupe | fait |
| 23/09/2026 | « Vos souvenirs ne quittent pas l'Europe » : argument commercial à trancher **avant** de rebrancher la transcription | à trancher — Hugo |

## Sources

Relevées le 23/09/2026 :

- [Tarifs Claude](https://platform.claude.com/docs/en/about-claude/pricing),
  [résidence des données](https://platform.claude.com/docs/en/manage-claude/data-residency)
  et [capacités des modèles](https://platform.claude.com/docs/en/models/overview)
  (texte et image en entrée, pas d'audio)
- [Tarifs OpenAI](https://developers.openai.com/api/docs/pricing)
- [Tarifs Gemini](https://ai.google.dev/gemini-api/docs/pricing)
- [Tarifs Mistral](https://mistral.ai/pricing/api/)
