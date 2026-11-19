import { Prisma, type PrismaClient } from "@prisma/client";
import { MAX_MOMENTS, PART_OF_DAY_HOURS, parseMoments, type RedactedMoment } from "./redaction.js";
import { pauseBeforeTranscript } from "./conversation.js";
import { localTimeOn } from "./dailyCredit.js";
import { DEFAULT_TIME_ZONE, localDate } from "./localCalendar.js";

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
 * **Et chaque part est datée de ce qu'elle raconte** (Hugo, 05/11/2026 — « les
 * souvenirs ne sont pas toujours dans l'ordre chronologique et gardent
 * l'ordre du vocal, qui peut être très désordonné »).
 *
 * C'était vrai : les parts se décalaient d'une seconde chacune, et cette
 * seconde ne disait que l'ordre du récit. Quelqu'un qui rattrape trois jours
 * ne les raconte pas forcément dans l'ordre — « hier on a fait ça… ah, et
 * avant-hier… » — et le carnet imprimait l'ordre du vocal.
 *
 * Ce n'était pas le modèle qui se trompait : on ne lui demandait rien. Il
 * trouvait les moments, jamais **quand** ils avaient eu lieu. Il le dit
 * maintenant, quand le récit le dit (`RedactedMoment.day` et `.partOfDay`),
 * et c'est `momentInstants` qui en fait des dates. `capturedAt` ordonne
 * ensuite les étapes comme toujours (`groupIntoSteps`).
 *
 * Ce qu'on ne sait pas, on continue de ne pas le prétendre : une part que le
 * récit ne situe pas garde la seconde de décalage, c'est-à-dire sa place dans
 * le récit — ce qui reste le meilleur indice quand le voyageur n'a rien dit.
 * Sans la moindre date ni le moindre moment de journée, le découpage date
 * exactement comme avant.
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
export async function splitEntryIntoMoments(
  db: Db,
  entryId: string,
  timeZone: string = DEFAULT_TIME_ZONE,
): Promise<SplitOutcome | null> {
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
  const instants = momentInstants(moments, entry.capturedAt, timeZone);

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
      // Lui aussi se redate : le premier moment du récit n'est pas forcément
      // le premier vécu. Sans rien de dit, `momentInstants` lui rend sa date.
      capturedAt: instants[0]!,
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
        // Quand ce moment a été vécu, si le récit l'a dit — sinon sa place
        // dans le récit, à une seconde près. Voir `momentInstants`.
        capturedAt: instants[index + 1]!,
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

/**
 * **La date de chaque part**, dans l'ordre du récit.
 *
 * Trois règles, et la troisième est la plus importante :
 *
 * 1. une part qui porte un **jour** se pose à midi de ce jour-là, dans le
 *    fuseau du voyage — la même heure que les souvenirs racontés après coup
 *    (`capturedAtFor`), parce que c'est la seule qui retombe sur la bonne
 *    journée depuis n'importe quel fuseau ;
 * 2. une part qui porte un **moment de journée** se pose à son heure
 *    (`PART_OF_DAY_HOURS`), le jour qu'elle dit ou, à défaut, celui de la
 *    part précédente — « le matin… puis le soir » parle bien du même jour ;
 * 3. une part qui ne dit **rien** suit la précédente d'une seconde. C'est
 *    l'ancien comportement, et il reste juste : faute de mieux, l'ordre du
 *    récit vaut mieux que le hasard.
 *
 * Le décalage d'une seconde par rang s'applique **à toutes**, y compris aux
 * parts datées : deux moments qui disent le même matin se suivraient sinon
 * dans un ordre que rien ne décide, et `capturedAt` est ce qui range le
 * carnet.
 */
export function momentInstants(
  moments: readonly RedactedMoment[],
  capturedAt: Date,
  timeZone: string = DEFAULT_TIME_ZONE,
): Date[] {
  let anchor = capturedAt;
  return moments.map((moment, index) => {
    if (moment.day || moment.partOfDay) {
      const day = moment.day ?? localDate(anchor, timeZone);
      const hour = moment.partOfDay ? PART_OF_DAY_HOURS[moment.partOfDay] : 12;
      anchor = localTimeOn(day, hour, timeZone);
    }
    return new Date(anchor.getTime() + index * 1_000);
  });
}
