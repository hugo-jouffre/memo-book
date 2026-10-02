# La rédaction — l'écrivain du carnet

> La fiche de l'agent qui fait d'un vocal une page de carnet : ce qu'il fait, où
> le changer, comment on sait qu'il écrit bien, et **le journal de ce qu'on a
> changé et pourquoi**. C'est le pendant de [`conversation.md`](conversation.md)
> pour MEMO.
>
> Les **règles** qu'il suit ne sont pas ici : elles sont dans
> [`agents/agent-transcription.md`](../agents/agent-transcription.md), qui est
> son prompt, chargé tel quel. On n'y écrit jamais d'historique — le modèle le
> relirait à chaque vocal. L'historique vit ici.

## 1. Ce qu'il fait

| Étape | Où | Qui |
|---|---|---|
| Le vocal devient du texte brut | job `transcribe` | `gpt-4o-transcribe`, avec les noms que le carnet connaît déjà (`transcriptionHintFor`) |
| **Le texte brut devient une page** | job `redact` | **Claude Opus 5**, piloté par `agents/agent-transcription.md` |
| MEMO propose le texte : « Il te convient ? » | `askValidation` | Le code — et la bulle cite les passages que l'écrivain n'a pas compris |
| Le voyageur corrige au clavier | app iOS | Sa version fait autorité, plus jamais réécrite |

**Ce qu'il reçoit** : la transcription et les précisions du chat, qui raconte
et avec qui, les dates du voyage et de l'étape, la fiche de cohérence du carnet,
les trois dernières étapes écrites, tous les titres et encarts déjà employés.

**Ce qu'il rend** : sa lecture du vocal (`understanding` — le cœur de l'étape,
le ton, ce que veut dire chaque passage oral), le titre, le récit, la météo,
l'encart éventuel, la fiche de cohérence mise à jour, le relevé pour les
statistiques, et ses doutes.

## 2. Où changer quoi

| Je veux changer… | Où |
|---|---|
| La façon d'écrire | `agents/agent-transcription.md` — puis rejouer le banc (§ 3) |
| Ce qu'il sait du voyage | `buildRedactionPrompt` dans `backend/src/services/redaction.ts`, et `backend/src/jobs/redact.ts` qui va le chercher |
| Ce qu'il rend | `REDACTION_SCHEMA` dans `redaction.ts` |
| La bulle qui cite ses doutes | `validationQuestionFor` dans `backend/src/services/conversationCopy.ts` |
| Les noms soufflés au transcripteur | `transcriptionHintFor` dans `backend/src/services/transcription.ts` |
| Le modèle | `ANTHROPIC_REDACTION_MODEL` dans `backend/.env` — voir [`modeles-ia.md`](modeles-ia.md) |

Les règles des textes du **carnet entier** — quiz, mot fléché, intro, chiffres
du voyage — sont dans `agents/agent-transcription-carnet.md`. **Aucun agent ne
les applique aujourd'hui** : ni la rédaction, ni la mise en page n'écrivent ces
textes.

## 3. Comment on sait qu'il écrit bien — le banc

Le banc rédige un voyage entier de vrais vocaux, étape après étape, avec la
fiche de cohérence qui passe de l'une à l'autre, exactement comme le job
`redact`. Chaque étape porte ses **pièges** : ce qu'un bon écrivain doit
comprendre (`backend/test/fixtures/redaction/`).

```bash
cd backend
npm run redaction:eval -- --label avant                  # avant de toucher aux règles
npm run redaction:eval -- --label apres                  # après
npm run redaction:eval -- --compare avant apres          # côte à côte, gratuit
npm run redaction:eval -- --compare avant apres --judge  # + un relecteur qui note
npm run redaction:eval -- --label essai --until 13       # seulement les trois premières étapes
```

Les rapports vont dans `backend/.redaction-eval/` (hors dépôt).

**Ce que ça coûte** (02/10/2026, Opus 5) : environ **1 à 2 $** pour un passage
complet des neuf vocaux, autant pour le relecteur. Pour régler un détail,
`--until` sur trois étapes suffit ; le relecteur se garde pour la fin.

**Les exemples du prompt ne reprennent jamais une phrase du banc** : un exemple
copié du banc apprendrait la réponse au lieu de la règle, et le banc ne
mesurerait plus rien. On illustre avec des voyages inventés (Lisbonne, l'Algarve,
Clara, Tom).

## 4. Journal

### 02/10/2026 — Comprendre avant d'écrire

**Le constat** (Hugo, carnet Grèce, étape du 28 août). Le vocal dit
« l'activité préférée sur l'île » — leur activité préférée du séjour ; le carnet
imprime « L'activité préférée de l'île nous attendait ». La blague sur Fanny,
« super forte en équitation sur ce super beau âne », tombe à plat entre deux
corvées. Le texte manque de fluidité : il recopie l'ordre du vocal au lieu de
raconter la journée.

**Les causes trouvées**

1. **Les règles poussaient au mot à mot.** La fidélité portait sur les mots du
   voyageur (« au moins trois marqueurs de sa voix — ses mots »), pas sur ce
   qu'il voulait dire. Rien ne demandait de comprendre le cœur d'une journée, ni
   de reconnaître une blague.
2. **Une consigne impossible.** En cas de doute : « demander une clarification à
   l'Agent Conversation ». Ce fil n'existait pas ; coincé, l'écrivain recopiait.
   Un mot mal transcrit (« starbés ») s'imprimait, et la fiche de cohérence le
   consacrait comme « mot du voyageur, dit avec affection ».
3. **Un tiers du prompt ne le concernait pas** : quiz, mot fléché, chiffres du
   carnet, protocole des dédicaces — des textes qu'il n'écrit pas.
4. **Deux plafonds contradictoires** : 420 caractères par paragraphe dans le
   code, 379 à la validation du carnet. Les paragraphes trop longs étaient coupés
   en plein milieu à l'impression.
5. **Du contexte manquant.** Il ne savait pas qui racontait (la fiche notait Max
   comme « compagnon du narrateur »), recevait la date d'envoi du vocal comme si
   c'était le jour raconté, et ne voyait jamais les encarts déjà écrits.
6. **Rien pour mesurer.** Chaque retouche du prompt était un pari.

**Ce qui a changé** — détail dans les commits de la branche
`redaction-comprend-l-intention` :

- Les règles réécrites autour de l'intention : fidèle au sens, pas aux mots ;
  une lecture du vocal avant d'écrire ; les erreurs de transcription corrigées
  quand le contexte les rend certaines, sinon tues et signalées ; les noms
  propres gardés ; aucun bon mot ajouté.
- Le contexte complet (§ 1), les doutes cités par MEMO, l'indice de noms pour le
  transcripteur, un encart trop long qui saute au lieu de casser le carnet.
- Le banc (§ 3).

**Mesuré sur le banc** — neuf vocaux de Maxime, Opus 5, relu à la main :

| | Avant | Après |
|---|---|---|
| Paragraphes au-delà du plafond | 3 | 0 |
| « Fabien », « Famine » (Fanny), « jeans toniques », « Cora » (Chora) | imprimés tels quels | corrigés |
| La journée du mercredi 2 septembre (deux jours dans un vocal) | disparue | racontée |
| La blague de Fanny et l'âne | aplatie en fait | gardée comme blague |
| « L'activité préférée sur l'île » | « l'activité préférée de l'île nous attendait » | « notre activité préférée de l'île » |

Trois versions intermédiaires ont été écartées en route : la première recopiait
encore les incohérences et mélangeait « je » et « Maxime » ; la deuxième, trop
méfiante, faisait disparaître les noms propres inconnus (Kane, Toto Scooter, le
Prime) et ajoutait des bons mots (« une sieste stratégique »).

**Ce qui reste ouvert**

- Le relecteur n'a noté que trois étapes : les crédits Anthropic se sont épuisés
  pendant la relecture. Ses notes complètes restent à faire.
- La toute dernière règle — « un détail qu'on choisit de taire n'est pas un
  doute » — n'a pas été rejouée.
- Le coût par vocal de la nouvelle version n'est pas remesuré : la lecture du
  vocal ajoute de la sortie.
- Le réglage « Fun facts » à OFF n'est lu ni par la rédaction ni par la mise en
  page.

## 5. Décisions

| Date | Décision | Par |
|---|---|---|
| 02/10/2026 | La fidélité porte sur le **sens** : un contresens est une faute aussi grave qu'une invention | Hugo, reco Claude |
| 02/10/2026 | L'écrivain établit sa lecture du vocal (`understanding`) **avant** d'écrire, dans la même réponse | reco Claude |
| 02/10/2026 | Un passage incompris ne s'imprime pas : il se cite dans la bulle « Il te convient ? », jamais dans une question de plus | reco Claude |
| 02/10/2026 | Un nom propre nouveau se garde ; seul un prénom qui ressemble à celui d'un compagnon est suspect | reco Claude |
| 02/10/2026 | Les règles des textes du carnet entier sortent du prompt, dans `agent-transcription-carnet.md` | reco Claude |
| 02/10/2026 | Un paragraphe : 379 caractères, comme la validation du carnet | reco Claude |
| 02/10/2026 | Toute modification des règles se mesure sur le banc, avant et après ; l'historique s'écrit ici, jamais dans le prompt | Hugo, reco Claude |
