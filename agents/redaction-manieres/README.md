# Les manières d'être rédigé (T292)

> Le voyageur choisit **comment** son carnet est écrit, dans la personnalisation
> du voyage. Un fichier par manière, chargé et inséré dans le prompt de
> rédaction (`buildRedactionPrompt`, § « Comment écrire cette étape »).
>
> Les **règles** de la rédaction ne sont pas ici : elles sont dans
> [`../agent-transcription.md`](../agent-transcription.md). L'historique et les
> mesures sont dans [`../../docs/redaction.md`](../../docs/redaction.md).

## Le contrat : une manière ne relâche aucune règle

C'est la seule chose à retenir avant d'en écrire une quatrième.

Une manière règle le **registre** — la longueur des phrases, ce qui survit de
l'oral, la place des images. Elle ne touche **jamais** :

- la fidélité : rien d'inventé, aucun contresens, la chronologie réelle ;
- la frontière récit / encart, et la culture générale qui reste à l'encart ;
- la fiche de cohérence : un objet garde le même nom d'un bout à l'autre ;
- le schéma de sortie, les contraintes de longueur du gabarit ;
- ce que le voyageur a corrigé à la main, qui n'est plus jamais réécrit.

Une manière qui aurait besoin d'assouplir l'une de ces lignes n'est pas une
manière : c'est une autre rédaction, et ça se décide dans
`agent-transcription.md`, le banc à la main.

## Les trois manières

| Clé | Nom affiché | Ce qu'elle change |
|---|---|---|
| `spoken` *(défaut)* | Comme je parle | **Rien** — c'est la rédaction telle qu'elle est |
| `literary` | Récit littéraire | Phrases plus amples, l'oral s'efface davantage |
| `factual` | Journal factuel | Court, chronologique, sans effets |

⚠️ **`spoken` n'injecte rien dans le prompt**, et c'est le cœur du dispositif :
un carnet qui n'a jamais touché à ce réglage doit être rédigé **exactement**
comme avant T292, à l'octet près. C'est aussi ce qui permet au banc de garder
sa ligne de base : `avant` *est* `spoken`. Seules `literary` et `factual`
demandent un passage de banc.

## Les indications du voyageur

En plus de la manière, un champ libre (`Memo.redactionNotes`) part dans le
prompt sous le titre « Ce que le voyageur demande en plus ». Il est **second** :
le prompt dit explicitement qu'une indication qui contredirait une règle de
`agent-transcription.md` ne s'applique pas. « Invente ce qui manque » n'est donc
pas un contournement.

## Ajouter une manière

1. Un fichier ici, sur le modèle des trois autres : ce qu'elle change, ce
   qu'elle ne change pas, trois exemples « dit → écrit ».
2. La clé dans `REDACTION_MANNERS` (`backend/src/services/redactionManners.ts`)
   et dans `RedactionManner` (`MemoBookCore`, `core/.../Models.kt`).
3. **Un passage de banc**, avant et après, avec son rapport dans
   `docs/redaction.md` § 4. Une manière qui fait perdre de la fidélité ne se
   livre pas — c'est la leçon de T291.
