import { Prisma, type PrismaClient } from "@prisma/client";
import { MAX_MOMENTS, parseMoments } from "./redaction.js";
import { pauseBeforeTranscript } from "./conversation.js";

type Db = PrismaClient | Prisma.TransactionClient;

/**
 * **Découper un récit en plusieurs étapes** (Hugo, 28/10/2026 — « comprendre
 * si un message contient au contraire plusieurs étapes »).
 *
 * Quelqu'un qui rattrape trois jours d'un coup raconte trois moments dans un
 * seul vocal. L'écrivain les entend et les propose (`entries.splitSuggestion`,
 * chaque part citant mot pour mot sa tranche de la transcription) ; MEMO pose
 * la question dans le fil ; **rien n'est découpé avant la réponse**. On
 * raconte une fois : deux cartes qui apparaissent sans prévenir se lisent
 * comme un bug.
 *
 * Ce que le découpage fait, une fois dit oui :
 *
 * - le souvenir d'origine **garde sa première part** — et avec elle son
 *   audio, ses photos, sa place dans le fil et sa bulle. C'est toujours lui,
 *   raccourci ;
 * - chaque part suivante devient un **souvenir à elle**, du texte : l'audio
 *   ne se coupe pas en deux, et il n'y a qu'un fichier. Sa transcription est
 *   la tranche citée, mot pour mot ;
 * - toutes repassent par la rédaction, qui leur écrit leur texte ;
 * - chacune reçoit sa fiche dans le fil, à la suite — c'est là que le
 *   voyageur les relira et les validera, une par une.
 *
 * Les dates se décalent d'une seconde par part, et c'est tout : elles disent
 * l'ordre du récit, et `capturedAt` ordonne les étapes
 * (`groupIntoSteps`). Une minute aurait prétendu savoir quand chaque moment a
 * été vécu — on ne le sait pas.
 */
export interface SplitOutcome {
  /** Les souvenirs après découpage, le premier étant celui d'origine. */
  entryIds: string[];
}

/**
 * Découpe le souvenir selon la proposition qu'il porte. Rend `null` quand il
 * n'y a rien à découper — pas de proposition, ou une proposition qui ne tient
 * plus contre la transcription actuelle (le texte a changé entre-temps).
 *
 * ⚠️ **À appeler dans une transaction verrouillée** (`lockThread`) : elle
 * écrit dans le fil, et deux réponses simultanées ne doivent pas découper
 * deux fois.
 */
export async function splitEntryIntoMoments(db: Db, entryId: string): Promise<SplitOutcome | null> {
  const entry = await db.entry.findUnique({
    where: { id: entryId },
    include: { media: { select: { durationSeconds: true } } },
  });
  if (!entry) return null;

  // Relus **contre la transcription d'aujourd'hui** : une relance de la
  // rédaction a pu la changer depuis que la proposition a été écrite.
  const moments = parseMoments(entry.splitSuggestion, entry.transcript);
  if (moments.length < 2 || moments.length > MAX_MOMENTS) {
    // La proposition ne tient plus : on l'efface plutôt que de la reposer.
    if (entry.splitSuggestion !== null) {
      await db.entry.update({ where: { id: entryId }, data: { splitSuggestion: Prisma.DbNull } });
    }
    return null;
  }

  const [first, ...rest] = moments;

  // Le souvenir d'origine garde la première part. Son texte rédigé tombe : il
  // racontait tout, il ne raconte plus que le début.
  await db.entry.update({
    where: { id: entryId },
    data: {
      transcript: first!.transcript,
      suggestedTitle: first!.title,
      redactedText: null,
      redactionStatus: "pending",
      redactionError: null,
      splitSuggestion: Prisma.DbNull,
    },
  });

  const entryIds = [entryId];

  for (const [index, moment] of rest.entries()) {
    const created = await db.entry.create({
      data: {
        memoId: entry.memoId,
        // Du texte : l'audio ne se coupe pas en deux, et il reste au premier.
        kind: "text",
        status: "ready",
        transcript: moment.transcript,
        suggestedTitle: moment.title,
        redactionStatus: "pending",
        // **Découpée à la demande : rien ne la recollera** (30/10/2026, à la
        // fusion de #160 et #161). Chaque part repasse par la rédaction, qui
        // juge aussi si un récit prolonge le précédent
        // (`continuesPreviousStep`) — et deux parts d'un même récit, elle les
        // dirait prolongées sans hésiter. Elle réunirait donc en une étape ce
        // que le voyageur vient de demander de séparer. `separatedByTraveller`
        // passe devant la machine, comme sur la carte d'étape : la main
        // l'emporte.
        separatedByTraveller: true,
        // Une seconde par part : l'ordre du récit, rien de plus.
        capturedAt: new Date(entry.capturedAt.getTime() + (index + 1) * 1_000),
        placeLabel: entry.placeLabel,
      },
    });
    entryIds.push(created.id);

    // Sa fiche dans le fil, à la suite : c'est là qu'on la relit et qu'on la
    // valide. Pas de bulle du voyageur — il n'a rien dit de plus, il a dit
    // tout ça d'un coup, et sa bulle d'origine est déjà au-dessus.
    await db.chatMessage.create({
      data: {
        memoId: entry.memoId,
        author: "memo",
        kind: "transcript",
        entryId: created.id,
        pauseMilliseconds: pauseBeforeTranscript(entry.media?.durationSeconds ?? null),
        model: "scripted",
      },
    });
  }

  return { entryIds };
}
