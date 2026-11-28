# Manière — Comme je parle

> Clé `spoken`. **Le défaut, et elle n'injecte rien** dans le prompt de
> rédaction : c'est la rédaction telle que `agent-transcription.md` la décrit.
> Ce fichier existe pour que le voyageur sache ce qu'il choisit, et pour que la
> prochaine session sache qu'il n'y a rien à charger ici.

## Ce que le voyageur lit dans l'app

**Comme je parle** — « Le carnet garde ta façon de raconter : tes mots, ton
humour, tes images. C'est la rédaction d'origine. »

## Ce qu'elle fait

Ce que le prompt fait déjà, et qu'il faut connaître pour écrire les deux autres
manières :

- **Ses mots qui portent un sens restent** — ses mots signature, ses images,
  son argot quand il fait sa voix (§ « à la gratte » gardé tel quel).
- **Ses hésitations partent** : les reprises, les phrases en suspens, les
  « attends, je recommence ». Sa voix est dans ce qui porte un sens, pas dans
  le bafouillage.
- **Les phrases sont courtes à moyennes**, proches du rythme de la parole, mais
  chacune se comprend à la première lecture sans l'intonation.
- **Son humour se rend, il ne s'ajoute pas** : une blague se prépare et se pose
  comme une chute, aucun bon mot n'est inventé.

## Pourquoi elle n'injecte rien

Un carnet qui n'a jamais touché au réglage doit être rédigé **exactement**
comme avant T292. Si cette manière écrivait sa propre consigne, même fidèle,
elle changerait le prompt de tous les carnets existants — et il faudrait
rejouer le banc pour prouver qu'elle ne change rien, alors qu'il suffit de ne
rien écrire pour en être sûr.

C'est aussi ce qui garde la ligne de base du banc intacte : le passage `avant`
d'une comparaison **est** cette manière.

⚠️ Corollaire : `redactionManner` vaut `null` tant que le voyageur n'a pas
choisi, et `null` se comporte comme `spoken`. Les deux ne se distinguent que
dans l'app, où l'un affiche une pastille « par défaut » et l'autre un choix
fait.
