# Les tours qu'on rejoue pour relire MEMO

> `npm run conversation:eval` fait parler MEMO sur chacun de ces tours et
> imprime ses réponses avec la grille de `docs/conversation.md` § 13.

Chaque fichier `.json` est une **scène** : un carnet, un fil, un message reçu.
Le script les joue dans l'ordre alphabétique et n'écrit rien en base — il
n'appelle que le répondeur.

## Le format

```jsonc
{
  "name": "Un vocal riche",              // ce qui s'imprime en tête
  "why": "Ce qu'on vérifie ici.",        // rappelé sous la réponse
  "memo": { "title": "…", "theme": null, "destinationCity": "Rome",
            "people": ["Clara"], "places": ["Testaccio"], "prompt": null },
  "traveller": { "firstName": "Hugo", "memberCount": 1 },
  "history": [{ "author": "traveller", "text": "…" }],  // du plus ancien au plus récent
  "message": { "kind": "voice", "text": "la transcription brute", "durationSeconds": 48 },
  "currentEntry": { "text": "…", "validatedAt": null },  // ou absent
  "allows": { "roseEpineGraine": false },
  "expect": { "disposition": "memory" }   // facultatif : vérifié automatiquement
}
```

Tout ce qui manque prend une valeur par défaut raisonnable — voir
`scripts/conversation-eval.ts`, qui est la seule lecture de ce format.

## Les vraies voix

Les scènes livrées ici sont **écrites**, pas enregistrées : elles couvrent les
situations du contrat (un refus, une émotion difficile, une question, une
précision courte, un vocal riche, une transcription qui a échoué, des photos,
la rose/épine/graine). Elles servent à voir tout de suite si une modification du
prompt casse un cas connu.

Ce qui tranche vraiment, ce sont les **vocaux des testeurs** (Hugo en a plus de
dix). Pour en ajouter un :

1. faire passer l'audio par la transcription réelle (ou reprendre la
   transcription déjà en base) ;
2. copier le texte tel quel dans `message.text` — **sans le nettoyer** : les
   hésitations et les phrases qui s'arrêtent en route sont précisément ce qu'on
   veut que MEMO sache écouter ;
3. remplir le fil autour, s'il y en avait un, et nommer la scène d'après ce
   qu'elle éprouve, pas d'après le voyageur.

Aucun nom de famille, aucune adresse, aucun numéro : ces fichiers sont
versionnés.

## Ce que ces scènes ne sont pas

Des tests. Elles ne tournent pas en CI et ne font échouer aucun build : le
modèle n'entre jamais en CI (`docs/conversation.md` § 13). Ce qui se vérifie
sans modèle — le contrat, le catalogue, le rythme — est dans
`src/services/conversationAnthropic.test.ts` et
`src/services/conversation.test.ts`.
