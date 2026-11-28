import type { Account, Memo, MemoMember, MemoStep } from "@prisma/client";
import { finalTextOf } from "../jobs/redact.js";
import { resolveCallToAction } from "../services/callsToAction.js";
import {
  GREETING_MESSAGE,
  SUGGESTION_SETS,
  TRANSCRIPT_FOOTNOTE,
  transcriptTitle,
  greetingTitle,
  suggestionsFor,
  type Suggestion,
} from "../services/conversationCopy.js";
import { reactionFor } from "../services/chatReaction.js";
import { firstNameOf, type ChatMessageRow, type EntryWithMedia } from "../services/conversationThread.js";
import { avatarUrlOf } from "../services/avatars.js";
import { livedDaysOf } from "../services/livedDays.js";
import { displayablePhotoUrl } from "./tripPhotos.js";
import {
  LIMITED_AUDIENCE,
  freeCorrectionCharactersLeft,
  serializeDailyCredit,
  type DailyCredit,
} from "../services/dailyCredit.js";
import {
  contextVoiceOf,
  isGathering,
  parseTripContext,
  serializeTripContext,
  type TripContext,
} from "../services/tripContext.js";

/**
 * Ce que l'écran de conversation reçoit.
 *
 * Même règle qu'`appSerializers.ts` : la forme suit **les modèles Swift** de
 * `MemoBookCore/Chat.swift` au champ près — `ChatThread`, `ChatMessage`,
 * `ChatMessageBody` (discriminée par `kind`), `TranscriptCard`, `VoiceNote`,
 * `PhotoAttachment`, `ChatSuggestion`, `ChatContext`, `ChatBookPreview`,
 * `ChatGreeting`. Un champ renommé d'un côté casse le décodage de l'autre.
 *
 * Ce qui s'ajoute par rapport au jeu d'essai de l'app — `seq`, `authorName`,
 * `pauseMilliseconds`, `disposition`, `phase`, `isValidated`, `turn`,
 * `canClear`, `now`, `callToAction`, `dailyCredit` — est **optionnel au
 * décodage** côté Swift : un fil d'aperçu qui ne les porte pas décode encore,
 * et une app installée qui ne les connaît pas les ignore.
 */

export type ChatTurnStatus =
  | { status: "idle" }
  | { status: "replying"; messageId: string };

/**
 * **Les deux versions d'un souvenir**, quand il y a bien deux textes à
 * comparer : la transcription littérale et le texte rédigé. Nulles sinon — la
 * fiche ne propose alors aucune bascule.
 */
function twoVersionsOf(entry: { transcript: string | null; redactedText: string | null }) {
  const hasTwo =
    entry.transcript !== null && entry.redactedText !== null && entry.transcript !== entry.redactedText;
  return {
    rawText: hasTwo ? entry.transcript : null,
    writtenText: hasTwo ? entry.redactedText : null,
  };
}

/** Où en est la fiche d'un souvenir : ce que la bulle dessine en trois temps. */
export type TranscriptPhase = "listening" | "writing" | "ready" | "unwritten" | "failed";

/**
 * Où en est la fiche — `docs/conversation.md` § 5.
 *
 * **Deux échecs, pas un** (Hugo, 04/11/2026). Ils tenaient dans le même
 * `failed`, et la fiche disait « Je n'ai pas réussi à finir cette fiche »
 * au-dessus d'un texte complet : alarmant, et faux.
 *
 * - `failed` : la **transcription** a échoué. Il n'y a rien à lire, et c'est
 *   la seule panne qui mérite du rouge.
 * - `unwritten` : la transcription est là, c'est la **rédaction** qui a
 *   échoué. Le mot-pour-mot s'affiche et part dans le carnet
 *   (`finalTextOf`) — rien n'est perdu, il manque la mise en forme.
 *
 * Une app plus ancienne décode `unwritten` en `unknown` et l'affiche comme
 * une fiche prête : le texte est là, sans alerte. C'est le bon repli.
 */
export function transcriptPhaseOf(entry: EntryWithMedia): TranscriptPhase {
  if (entry.status === "failed") return "failed";
  if (entry.status === "pending" || entry.status === "processing") return "listening";
  if (entry.redactionStatus === "failed") return "unwritten";
  if (entry.redactionStatus === "pending" || entry.redactionStatus === "processing") return "writing";
  return "ready";
}

/** Le drapeau d'un code ISO 3166-1 alpha-2, ou rien : mieux vaut pas de drapeau qu'un carré blanc. */
export function flagOf(countryCode: string | null): string | null {
  if (!countryCode || !/^[A-Za-z]{2}$/.test(countryCode)) return null;
  return String.fromCodePoint(
    ...[...countryCode.toUpperCase()].map((letter) => 0x1f1e6 + letter.charCodeAt(0) - 65),
  );
}

/** L'adresse d'un média servi par l'API, avec la session — `GET /v1/entries/:id/media`. */
export function mediaUrlOf(publicBaseUrl: string, entryId: string): string {
  return `${publicBaseUrl}/v1/entries/${entryId}/media`;
}

/**
 * Une ou deux initiales, quand la photo manque — la même règle que l'app
 * (`TravellerProfile.initials`) : la première lettre des deux premiers mots du
 * nom complet.
 */
export function initialsOf(
  account: { firstName: string | null; lastName: string | null } | null,
): string | null {
  const words = [account?.firstName, account?.lastName]
    .join(" ")
    .split(/\s+/)
    .filter((word) => word.length > 0)
    .slice(0, 2);
  const initials = words.map((word) => word[0]!.toUpperCase()).join("");
  return initials.length > 0 ? initials : null;
}

function levelsOf(payload: unknown): number[] {
  if (!payload || typeof payload !== "object") return [];
  const levels = (payload as { levels?: unknown }).levels;
  if (!Array.isArray(levels)) return [];
  return levels
    .filter((level): level is number => typeof level === "number" && Number.isFinite(level))
    .map((level) => Math.min(1, Math.max(0, level)));
}

function entryIdsOf(payload: unknown, fallback: string | null): string[] {
  const ids =
    payload && typeof payload === "object" ? (payload as { entryIds?: unknown }).entryIds : undefined;
  if (Array.isArray(ids)) {
    const strings = ids.filter((id): id is string => typeof id === "string");
    if (strings.length > 0) return strings;
  }
  return fallback ? [fallback] : [];
}

/** Un champ du payload d'une bulle, sans faire confiance à sa forme. */
function payloadField(payload: unknown, key: string): unknown {
  return payload && typeof payload === "object" ? (payload as Record<string, unknown>)[key] : undefined;
}

/** Le souvenir dont une bulle parle — voir `entryId` dans ``serializeChatMessage``. */
function entryIdAbout(message: Pick<ChatMessageRow, "entryId" | "payload">): string | null {
  for (const key of ["asksValidationFor", "asksPhotosFor"]) {
    const value = payloadField(message.payload, key);
    if (typeof value === "string") return value;
  }
  return message.entryId;
}

/**
 * Cette bulle est-elle pour ce lecteur ? Une bulle `audience: "limited"` — la
 * bulle « reviens demain » du crédit du jour — ne parle qu'à ceux qui
 * comptent leur crédit : un abonné n'a pas à lire « reviens demain » dans un
 * fil qu'il partage avec ses co-voyageurs (Hugo, 03/10/2026).
 */
export function isVisibleTo(message: Pick<ChatMessageRow, "author" | "payload">, viewerIsUnlimited: boolean): boolean {
  if (message.author !== "memo") return true;
  return !(viewerIsUnlimited && payloadField(message.payload, "audience") === LIMITED_AUDIENCE);
}

/**
 * **La bulle de MEMO que ce tour vient saluer d'un 👍** (T296), ou `null` —
 * `payload.reactionTo`, écrit par la route (`routes/chat.ts`).
 *
 * C'est la seule chose qu'une réaction laisse en base, et elle sert deux
 * fois : à ne pas dessiner le tour qui l'a portée, et à poser le 👍 sur la
 * bulle visée.
 */
export function reactionTargetOf(payload: unknown): string | null {
  const value = payloadField(payload, "reactionTo");
  return typeof value === "string" && value.length > 0 ? value : null;
}

/**
 * Les bulles de MEMO qui portent un 👍, lues sur le fil entier : une réaction
 * vise presque toujours une bulle d'avant la page qu'on relit.
 */
export function reactedMessageIdsOf(rows: readonly { reactionTo: string | null }[]): Set<string> {
  const ids = new Set<string>();
  for (const row of rows) if (row.reactionTo) ids.add(row.reactionTo);
  return ids;
}

export function suggestionIdsOf(payload: unknown): string[] {
  const ids =
    payload && typeof payload === "object"
      ? (payload as { suggestions?: unknown }).suggestions
      : undefined;
  return Array.isArray(ids) ? ids.filter((id): id is string => typeof id === "string") : [];
}

// ---------------------------------------------------------------------------
// Un message
// ---------------------------------------------------------------------------

export interface SerializeMessageOptions {
  /** Le compte qui lit : ses propres bulles n'ont pas de prénom, MEMO non plus. */
  viewerAccountId: string;
  /** Le fil est-il à plusieurs ? Seul, personne n'a besoin d'une légende. */
  showsAuthors: boolean;
  publicBaseUrl: string;
  /** Le numéro d'étape de chaque fiche, par identifiant de message — ``stepNumbersOf``. */
  stepNumbers?: ReadonlyMap<string, number>;
  /**
   * Celui qui lit raconte-t-il sans limite ? Il décide de ce qu'il voit : ni
   * la bulle « reviens demain » (`isVisibleTo`), ni une offre d'abonnement
   * (`resolveCallToAction`).
   */
  viewerIsUnlimited: boolean;
  /**
   * **Les photos élues** (T270) : celle du voyage, et celles des étapes. La
   * bulle les marque d'une étoile, et le menu propose de défaire le choix au
   * lieu de le refaire.
   *
   * Deux ensembles et non deux identifiants : une même photo peut être la
   * principale de son étape **et** celle du voyage, et les deux étoiles se
   * dessinent alors ensemble.
   */
  cover?: { tripEntryId: string | null; stepEntryIds: ReadonlySet<string> };

  /**
   * **La taille de chaque photo** (T305) — `loadPhotoSizes`. La bulle range
   * ses photos au format qu'elles ont, et il lui faut les dimensions avant
   * que les images arrivent, sans quoi sa hauteur changerait au chargement.
   *
   * Absente d'un reçu de `POST` : les photos qu'on vient d'envoyer sont
   * encore les fichiers du téléphone, qui connaît leur taille. La relecture
   * du fil apporte les autres.
   */
  photoSizes?: ReadonlyMap<string, { widthPx: number; heightPx: number }>;

  /**
   * **Les puces que cette bulle propose quand on la choisit** (T286).
   * Absentes d'un sondage, qui ne rend que ce qui a changé : l'app garde
   * alors celles qu'elle a déjà.
   */
  suggestions?: ReturnType<typeof serializeChatSuggestions>;

  /**
   * **Les bulles de MEMO sur lesquelles le voyageur a posé un 👍** (T296) —
   * ``reactedMessageIdsOf``. Absent d'un reçu de `POST` : le 👍 vise une
   * bulle d'avant, qui n'est pas dans ce que la requête vient d'écrire.
   */
  reactedMessageIds?: ReadonlySet<string>;
}

/**
 * « Retranscription étape N » : une fiche par souvenir, une étape par
 * souvenir — la N-ième fiche du fil est l'étape N. Calculé sur le fil entier,
 * jamais sur une page de messages.
 *
 * **Une fiche reposée garde son numéro** (12/10/2026) : quand MEMO revient à
 * une étape laissée en plan, il repose sa fiche au bas du fil — c'est la même
 * étape, pas une de plus.
 */
export function stepNumbersOf(
  messages: readonly Pick<ChatMessageRow, "id" | "kind" | "seq" | "entryId">[],
): Map<string, number> {
  const cards = messages.filter((message) => message.kind === "transcript").sort((a, b) => a.seq - b.seq);
  const numbers = new Map<string, number>();
  const numberOfEntry = new Map<string, number>();
  let count = 0;
  for (const card of cards) {
    let number = card.entryId ? numberOfEntry.get(card.entryId) : undefined;
    if (number === undefined) {
      count += 1;
      number = count;
      if (card.entryId) numberOfEntry.set(card.entryId, number);
    }
    numbers.set(card.id, number);
  }
  return numbers;
}

function serializeBody(
  message: ChatMessageRow,
  publicBaseUrl: string,
  stepNumbers?: ReadonlyMap<string, number>,
  cover?: SerializeMessageOptions["cover"],
  photoSizes?: SerializeMessageOptions["photoSizes"],
) {
  switch (message.kind) {
    case "text":
      return { kind: "text" as const, text: message.text ?? "" };

    case "voice": {
      // Un vocal du contexte du voyage, ou une correction dictée, n'a pas de
      // souvenir à lui : son fichier pend au message (`contextVoiceOf`). Une
      // correction vise pourtant la fiche qu'elle corrige (`entryId`) — c'est
      // son propre fichier qu'on réécoute, pas celui de la fiche.
      const voice = contextVoiceOf(message.payload);
      const entry = voice ? null : message.entry;
      return {
        kind: "voice" as const,
        voice: {
          id: message.id,
          duration: entry?.media?.durationSeconds ?? voice?.durationSeconds ?? 0,
          levels: levelsOf(message.payload),
          remoteUrl: entry
            ? mediaUrlOf(publicBaseUrl, entry.id)
            : voice
              ? `${publicBaseUrl}/v1/chat-messages/${message.id}/media`
              : null,
        },
      };
    }

    case "photos":
      return {
        kind: "photos" as const,
        photos: entryIdsOf(message.payload, message.entryId).map((entryId) => ({
          id: entryId,
          remoteUrl: mediaUrlOf(publicBaseUrl, entryId),
          // Les deux étoiles (T270). Absentes d'un serveur qui ne les connaît
          // pas : une app d'avant ignore les clés qu'elle ne lit pas.
          isTripCover: cover?.tripEntryId === entryId,
          isStepCover: cover?.stepEntryIds.has(entryId) ?? false,
          // **Son format** (T305). Absent d'une photo que le serveur n'a pas
          // su mesurer, et d'un serveur d'avant : la bulle la range alors
          // carrée, comme elle l'a toujours fait.
          ...(photoSizes?.get(entryId) ?? {}),
        })),
      };

    case "transcript": {
      // La fiche se redessine depuis le souvenir à chaque lecture : elle ne
      // recopie rien, et ne peut donc pas être périmée.
      const entry = message.entry;
      if (!entry) return null;
      const phase = transcriptPhaseOf(entry);
      return {
        kind: "transcript" as const,
        transcript: {
          title: transcriptTitle(stepNumbers?.get(message.id) ?? null),
          // Le titre que la rédaction a donné au récit — celui de l'étape dans le carnet.
          heading: phase === "ready" || phase === "unwritten" ? entry.suggestedTitle : null,
          // **Quand on en a parlé**, et c'est tout ce que ça dit : la fiche
          // ne l'affiche plus comme la date de l'étape (T308).
          capturedAt: entry.capturedAt.toISOString(),
          // **Le lieu et les jours que l'étape a compris**, ou rien.
          //
          // La fiche affichait `placeLabel` — l'écho que l'app renvoie du lieu
          // que le carnet lui avait donné, donc le lieu de l'étape **d'avant**
          // quand on change de ville — et le jour de l'enregistrement, qui
          // n'est pas celui qu'on raconte. Elle affiche maintenant ce que le
          // carnet a compris, ou elle se tait : un lieu faux est pire qu'un
          // lieu absent, et c'est la plainte même de T280.
          //
          // Pris sur l'étape et non sur le souvenir : une étape racontée en
          // deux fois porte une seule date, et ses deux fiches la montrent.
          //
          // **Ce que la main a écrit passe devant** (T288) : « changer le nom
          // du lieu » et « changer les dates » corrigent *cette* fiche, et
          // c'est sur elle qu'on doit le voir — tout de suite, sans attendre
          // que le recalcul remonte la correction sur l'étape, et même si
          // l'autre fiche de l'étape dit autre chose.
          placeName: entry.pinnedPlaceName ?? entry.step?.placeName ?? null,
          ...livedDatesOf(entry),
          // **Qui a écrit ça** (T288) : la main, ou la machine. L'app ne
          // propose « revenir aux dates déduites » que là où une main est
          // passée — ailleurs, le lien ne ferait rien, et un geste qui ne fait
          // rien se lit comme une panne.
          livedDaysByHand: entry.pinnedLivedFromDay !== null,
          placeByHand: entry.pinnedPlaceName !== null,
          duration: entry.media?.durationSeconds ?? null,
          text: finalTextOf(entry),
          // **Les deux versions, pour pouvoir les comparer** (Hugo,
          // 28/10/2026). La fiche montrait le texte rédigé et lui seul : rien
          // ne disait si l'IA avait inventé ou perdu quelque chose. Elle
          // porte désormais les deux, et l'app passe de l'une à l'autre sans
          // rien redemander.
          //
          // **Servies toutes les deux, et pas déduites de `text`** : `text`
          // est ce qui part au carnet (`finalTextOf`), et c'est tantôt l'une
          // tantôt l'autre. Les déduire de lui faisait disparaître la bascule
          // au moment précis où l'on venait de choisir la littérale.
          //
          // Nulles quand il n'y a rien à comparer : un souvenir écrit au
          // clavier, dont le brut *est* le texte ; une rédaction qui n'a rien
          // rendu ; deux textes identiques.
          ...twoVersionsOf(entry),
          // Laquelle part au carnet — voir `finalTextOf`.
          prefersTranscript: entry.prefersTranscript,
          isSimulated: false,
          entryId: entry.id,
          footnote: phase === "ready" ? TRANSCRIPT_FOOTNOTE : null,
          phase,
          isValidated: entry.validatedAt !== null,
          // Ce qui reste des 200 caractères de correction offerts (QA D8).
          freeCorrectionCharactersLeft: freeCorrectionCharactersLeft(entry),
        },
      };
    }
  }
}

/**
 * **Les jours que la fiche affiche** : la main, l'étape, puis le récit.
 *
 * La main d'abord (T288) — c'est cette fiche-là qu'on a corrigée. Sinon
 * l'étape, qui parle pour toutes ses fiches : une étape racontée en deux fois
 * porte une seule date (T308). Sinon ce que ce récit avait compris, pour un
 * souvenir qu'aucun recalcul n'a encore rangé. Sinon rien, et la ligne de
 * calendrier disparaît.
 */
function livedDatesOf(entry: EntryWithMedia): { livedFrom: string | null; livedTo: string | null } {
  const days = entry.pinnedLivedFromDay
    ? livedDaysOf(entry)
    : {
        from: entry.step?.livedFromDay ?? entry.livedFromDay,
        to: entry.step?.livedToDay ?? entry.livedToDay,
      };
  return { livedFrom: days.from?.toISOString() ?? null, livedTo: days.to?.toISOString() ?? null };
}

/**
 * Une bulle, ou `null` pour une fiche dont le souvenir a disparu — le fil
 * reste lisible sans elle — et pour une bulle qui ne s'adresse pas à ce
 * lecteur (`isVisibleTo`).
 *
 * `sentAt` d'une bulle du voyageur est la date **du souvenir**, pas celle de
 * l'écriture : un vocal reconstruit depuis l'accueil garde le jour où il a été
 * raconté. Les bulles de MEMO et les textes datent de leur écriture.
 *
 * ⚠️ **`postedAt` est une autre chose, et c'est lui qui range le fil** (T309) :
 * le moment où le voyageur a **posé** la bulle. Ranger le fil sur `sentAt`
 * ferait remonter une photo de l'été dernier au milieu du voyage ; le ranger
 * sur l'arrivée au serveur pousse au bas du fil une photo partie trois jours
 * plus tard. Les deux cohabitent donc, et chacune dit ce qu'elle dit.
 */
export function serializeChatMessage(message: ChatMessageRow, options: SerializeMessageOptions) {
  if (!isVisibleTo(message, options.viewerIsUnlimited)) return null;
  // **Réagir, c'est valider sans écrire** (T296) : le tour qu'une réaction
  // envoie est une puce « Ça me convient » comme les autres — il valide le
  // souvenir, MEMO lui répond —, mais il ne se dessine pas. Sa trace est le
  // 👍 posé sur la bulle visée, et une bulle « Ça me convient » de plus
  // dirait précisément ce qu'on venait d'éviter d'écrire.
  if (reactionTargetOf(message.payload) !== null) return null;
  const body = serializeBody(
    message,
    options.publicBaseUrl,
    options.stepNumbers,
    options.cover,
    options.photoSizes,
  );
  if (!body) return null;

  const isOtherTraveller =
    message.author === "traveller" &&
    options.showsAuthors &&
    message.accountId !== null &&
    message.accountId !== options.viewerAccountId;

  const sentAt =
    message.author === "traveller" && message.entry && message.kind !== "text" && !contextVoiceOf(message.payload)
      ? message.entry.capturedAt
      : message.createdAt;

  // Le bouton sous une bulle de MEMO, résolu **à la lecture** et pour ce
  // lecteur : le payload ne garde que son identifiant (`callsToAction.ts`).
  // Absent plutôt que nul : la clé est neuve, et la plupart des bulles n'en
  // ont pas.
  const callToAction =
    message.author === "memo" && message.kind === "text"
      ? resolveCallToAction(payloadField(message.payload, "callToAction"), {
          isUnlimited: options.viewerIsUnlimited,
        })
      : null;

  // L'emoji que MEMO pose sur ce tour, ou le 👍 que le voyageur a posé sur
  // cette bulle de MEMO (T296).
  const reaction = reactionFor(message, options.reactedMessageIds?.has(message.id) ?? false);

  return {
    id: message.id,
    seq: message.seq,
    // L'ordre du fil (T309). Absent d'un serveur d'avant le 26/11/2026 :
    // l'app retombe alors sur `seq`, l'ordre d'arrivée.
    postedAt: message.postedAt.toISOString(),
    // Ce que cette bulle propose quand on la choisit (T286) — absent du
    // sondage, où l'app garde ce qu'elle a.
    ...(options.suggestions ? { suggestions: options.suggestions } : {}),
    author: message.author,
    authorName: isOtherTraveller ? firstNameOf(message.account) : null,
    // Le portrait de celui qui a parlé, **sur toutes les bulles du voyageur** —
    // les siennes comme celles des autres : c'est lui que la bulle d'un vocal
    // montre, pas un signe de la marque.
    authorInitials: message.author === "traveller" ? initialsOf(message.account) : null,
    authorAvatarUrl:
      message.author === "traveller" && message.account ? avatarUrlOf(message.account) : null,
    body,
    sentAt: sentAt.toISOString(),
    // **L'étape de son souvenir d'abord** (12/10/2026) : les étapes naissent
    // des souvenirs après coup (`services/tripFacts.ts`), et c'est ce lien
    // qui permet d'ouvrir le fil sur le récit d'une étape depuis sa carte.
    stepId: message.entry?.stepId ?? message.stepId,
    // Le souvenir dont parle la bulle : celui du voyageur, la fiche dont MEMO
    // attend la validation, le récit dont il demande les photos. L'app s'en
    // sert pour viser la bonne fiche quand MEMO revient à une étape d'avant.
    entryId: entryIdAbout(message),
    disposition: message.disposition,
    pauseMilliseconds: message.pauseMilliseconds,
    ...(callToAction ? { callToAction } : {}),
    // La pastille de MEMO (T296), calculée et jamais stockée. Absente plutôt
    // que nulle : la clé est neuve, et une puce n'en porte pas.
    ...(reaction ? { reaction } : {}),
  };
}

export function serializeChatSuggestions(ids: readonly string[]): Suggestion[] {
  return suggestionsFor(ids);
}

// ---------------------------------------------------------------------------
// Le fil
// ---------------------------------------------------------------------------

export type MemoForChat = Memo & {
  owner: Account;
  members: (MemoMember & { account: Account | null })[];
  steps: MemoStep[];
  /**
   * La photo élue du voyage, quand la requête l'a chargée — une seule,
   * `coverPhotoInclude` (`tripPhotos.ts`). Absente d'une requête qui ne la
   * demande pas : l'en-tête retombe alors sur sa montagne.
   */
  entries?: { media: { storageKey: string; cdnUrl: string | null } | null }[];
  /** **La photo élue** du voyage, telle que `coverPhotoInclude` la charge. */
  coverEntry?: { id: string; media: { storageKey: string; cdnUrl: string | null } | null } | null;
};

/**
 * **Le petit livre qui dépasse du bord** — T297.
 *
 * « Un petit livre dépasse du bord, en haut à droite, et sautille quand
 * l'aperçu se met à jour — la porte d'entrée du PDF » (Hugo, 28/11/2026). Il
 * **évolue** : d'abord nu, avec le nombre d'étapes qui le séparent de sa
 * couverture ; puis la couverture s'affiche, et le livre s'épaissit.
 *
 * ⚠️ **La couverture existe bien avant qu'on la montre.** La photo élue du
 * voyage est choisie dès la première photo reçue : si le livre la portait
 * tout de suite, il n'aurait plus rien à devenir, et le voyageur n'aurait
 * aucune raison d'illustrer ses étapes. Le serveur la retient donc jusqu'à
 * ``COVER_AFTER_STEPS``, et c'est **lui** qui décide — l'app ne refait pas le
 * calcul, elle lit `coverUrl` et `stepsBeforeCover`.
 *
 * **Une étape « avec photos » est une étape qui a une photo élue**
 * (`steps.coverEntryId`), ce que `refreshTripFacts` pose dès qu'une photo s'y
 * range. Rien à charger de plus : les étapes sont déjà là pour les étoiles.
 */
export const COVER_AFTER_STEPS = 4;

export function bookDoorOf(memo: MemoForChat, publicBaseUrl: string) {
  const withPhotos = memo.steps.filter((step) => step.coverEntryId !== null).length;
  if (withPhotos < COVER_AFTER_STEPS) {
    return { coverUrl: null, stepsBeforeCover: COVER_AFTER_STEPS - withPhotos };
  }
  return {
    // La même photo que l'en-tête du fil : celle choisie à la main, sinon
    // celle que le voyage a élue.
    coverUrl: memo.coverPhotoUrl ?? displayablePhotoUrl(publicBaseUrl, memo.entries?.[0]?.media) ?? null,
    stepsBeforeCover: null,
  };
}

/**
 * **Les deux étoiles d'un carnet** (T270) : la photo principale du voyage, et
 * celles des étapes. Lues une fois par réponse, puis posées sur chaque photo —
 * voir ``SerializeMessageOptions.cover``.
 */
function coverOf(memo: MemoForChat): SerializeMessageOptions["cover"] {
  return {
    tripEntryId: memo.coverEntryId,
    stepEntryIds: new Set(memo.steps.flatMap((step) => (step.coverEntryId ? [step.coverEntryId] : []))),
  };
}

export interface SerializeThreadOptions {
  memo: MemoForChat;
  messages: ChatMessageRow[];
  viewer: Pick<Account, "id" | "firstName" | "lastName" | "avatarStorageKey" | "avatarUrl">;
  activeStep: MemoStep | null;
  /**
   * `count(entries kind ≠ photo)`, compté à la lecture : `memos.memoryCount`
   * (`services/tripFacts.ts`) n'avance qu'à la fin de la rédaction, et le fil
   * veut le souvenir qu'on vient d'envoyer.
   */
  memoryCount: number;
  hasReadyRender: boolean;
  turn: ChatTurnStatus;
  publicBaseUrl: string;
  now: Date;
  /** Le crédit du jour du voyage, vu par celui qui lit. */
  dailyCredit: DailyCredit;

  /** **La taille de chaque photo** (T305) — voir ``SerializeMessageOptions.photoSizes``. */
  photoSizes?: ReadonlyMap<string, { widthPx: number; heightPx: number }>;
}

/**
 * Ce que ``currentSuggestionIds`` lit d'un message — **audité champ par champ
 * le 19/11/2026**. Elle prenait le fil entier (`ChatMessageRow[]`) sans dire
 * ce qu'elle en tirait, et c'est elle qui décide des puces affichées sous la
 * conversation : se tromper ici met de mauvais boutons sous la main du
 * voyageur.
 *
 * Elle lit quatre choses, et rien d'autre : l'auteur, la sorte de bulle, la
 * présence et la relecture du souvenir d'une fiche, et les puces posées sous
 * une bulle de MEMO. Ni le texte, ni le média, ni le compte de celui qui a
 * parlé. Elle dépend en revanche de **l'ordre** : le fil lui arrive trié par
 * `seq` croissant.
 *
 * C'est ce qui permet de relire le fil entier sans rien rattacher — voir
 * `loadOutline` dans `routes/chat.ts`.
 */
export interface SuggestionsRow {
  author: ChatMessageRow["author"];
  kind: ChatMessageRow["kind"];
  /**
   * Le souvenir de cette bulle, **s'il existe encore**. La clé est posée
   * `SetNull` : supprimer un souvenir laisse `entryId` nul, et `entryId` non
   * nul vaut donc « le souvenir est là » (deux fiches sans souvenir en
   * production le 19/11/2026 — la fiche disparaît de la réponse, et les puces
   * l'enjambent).
   */
  entryId: string | null;
  /** Ce souvenir a-t-il été relu ? Faux quand il n'y en a pas. */
  isEntryValidated: boolean;
  /**
   * Les puces posées sous cette bulle — `payload.suggestions`, et rien d'autre
   * du payload.
   *
   * Renseigné pour les bulles **où une puce peut vivre** : une bulle texte de
   * MEMO. Vide partout ailleurs, parce que ``currentSuggestionIds`` ne le lit
   * nulle part ailleurs — elle rend la main dès une bulle du voyageur et
   * enjambe les autres sortes de bulles. (Vérifié aussi sur la production :
   * aucune autre bulle ne porte `payload.suggestions`.)
   */
  suggestionIds: readonly string[];
  /**
   * **Le 👍 de ce tour** (T296) — la bulle de MEMO qu'il salue, ou `null`.
   * C'est la seconde chose que le fil entier porte : une réaction vise une
   * bulle d'avant la page qu'on relit (``reactedMessageIdsOf``).
   */
  reactionTo: string | null;
}

/**
 * Ce que la réponse du fil demande au fil **entier** : de quoi numéroter les
 * fiches (``stepNumbersOf``) et de quoi choisir les puces
 * (``currentSuggestionIds``). Rien de plus — c'est la liste qui rend le
 * sondage léger.
 */
export type ThreadOutlineRow = Pick<ChatMessageRow, "id" | "seq"> & SuggestionsRow;

/**
 * La même lecture, d'une bulle déjà rattachée : à l'ouverture, le fil rendu
 * *est* le fil entier, et il n'y a rien à relire. Les deux chemins passent par
 * le même type, et un test tient qu'ils donnent les mêmes puces
 * (`test/chat.test.ts`, « sonde sans rien rattacher »).
 */
export function suggestionsRowOf(message: ChatMessageRow): SuggestionsRow {
  return {
    author: message.author,
    kind: message.kind,
    entryId: message.entryId,
    isEntryValidated: message.entry !== null && message.entry.validatedAt !== null,
    suggestionIds: suggestionIdsOf(message.payload),
    reactionTo: reactionTargetOf(message.payload),
  };
}

/**
 * **Les puces de chaque bulle, pour quand on la choisit** (T286, Hugo — « un
 * clic simple sur un message le cerne d'un liseré, et les propositions
 * s'adaptent à ce message-là »).
 *
 * Les puces répondaient au fil **entier** : sa dernière bulle décidait pour
 * tout le monde. Elles répondent en réalité à un message précis, et c'est
 * celui-là qu'on choisit.
 *
 * La règle ne change pas d'un iota : ce sont celles que ``currentSuggestionIds``
 * aurait rendues **si le fil s'arrêtait là**. Un fil de deux cents bulles tient
 * en deux cents lectures d'un prefixe, et la liste se calcule une fois par
 * réponse, jamais par bulle.
 *
 * ⚠️ Avec le `turn` **au repos** : « MEMO réfléchit » vide les puces du bas de
 * l'écran, mais choisir une bulle d'hier pendant qu'il répond doit quand même
 * montrer les siennes.
 */
export function suggestionIdsByMessage(
  rows: readonly (ThreadOutlineRow | (SuggestionsRow & { id: string }))[],
  tripContext: TripContext | null,
): Map<string, string[]> {
  const byMessage = new Map<string, string[]>();
  for (let index = 0; index < rows.length; index += 1) {
    const prefix = rows.slice(0, index + 1);
    byMessage.set(rows[index]!.id, currentSuggestionIds(prefix, { status: "idle" }, tripContext));
  }
  return byMessage;
}

/**
 * Les puces à proposer : celles de la dernière bulle de MEMO ; sous une fiche
 * qui clôt le fil (un souvenir reconstruit), le trio de validation tant
 * qu'elle n'est pas relue, puis de quoi continuer ; rien pendant un tour en vol.
 */
export function currentSuggestionIds(
  messages: readonly SuggestionsRow[],
  turn: ChatTurnStatus,
  tripContext: TripContext | null,
): string[] {
  if (turn.status === "replying") return [];
  // Rien encore dit par le voyageur : l'ouverture, décidée **à la lecture**
  // et non figée dans la bulle — un voyage ouvert avant le contexte du voyage
  // doit proposer lui aussi de le raconter, et un contexte déjà posé (après
  // « Supprimer la conversation ») ne se redemande pas.
  if (!messages.some((message) => message.author === "traveller")) {
    return tripContext && tripContext.status !== "gathering"
      ? [...SUGGESTION_SETS.openingWithContext]
      : [...SUGGESTION_SETS.opening];
  }
  // Pendant le contexte, les puces sont celles que MEMO a posées sous sa
  // dernière bulle — aucune sous l'invitation. Remonter plus haut ferait
  // ressortir « Plus tard », qui ne referme pas le contexte.
  if (isGathering(tripContext)) {
    const last = [...messages].reverse().find((message) => message.author === "memo" && message.kind === "text");
    return last ? [...last.suggestionIds] : [];
  }

  for (let index = messages.length - 1; index >= 0; index -= 1) {
    const message = messages[index]!;
    if (message.author === "traveller") return [...SUGGESTION_SETS.neutral];
    if (message.kind === "transcript") {
      // Un souvenir supprimé : sa fiche n'est plus dans la réponse, les puces
      // l'enjambent comme le sérialiseur.
      if (message.entryId === null) continue;
      return message.isEntryValidated ? [...SUGGESTION_SETS.afterAccept] : [...SUGGESTION_SETS.trio];
    }
    if (message.kind !== "text") continue;
    if (message.suggestionIds.length > 0) return [...message.suggestionIds];
  }
  return [...SUGGESTION_SETS.neutral];
}

export function serializeChatThread(options: SerializeThreadOptions) {
  const { memo, viewer, activeStep } = options;
  const memberCount = 1 + memo.members.filter((member) => member.status === "active").length;
  // Un seul relevé du fil entier, partagé par les puces de chaque bulle (T286)
  // et par les 👍 (T296) : les deux se lisent sur tout le fil, jamais sur une
  // page de messages.
  const outline = options.messages.map((row) => ({ id: row.id, ...suggestionsRowOf(row) }));
  const messageOptions: SerializeMessageOptions = {
    viewerAccountId: viewer.id,
    showsAuthors: memberCount > 1,
    publicBaseUrl: options.publicBaseUrl,
    stepNumbers: stepNumbersOf(options.messages),
    viewerIsUnlimited: options.dailyCredit.isUnlimited,
    cover: coverOf(options.memo),
    photoSizes: options.photoSizes,
    reactedMessageIds: reactedMessageIdsOf(outline),
  };

  const tripContext = parseTripContext(memo.tripContext);

  // Une fois pour tout le fil, et non une fois par bulle : la carte se lit
  // ensuite par identifiant (T286).
  const suggestionsByMessage = suggestionIdsByMessage(outline, tripContext);

  const messages = options.messages
    .map((message) =>
      serializeChatMessage(message, {
        ...messageOptions,
        // Ce que cette bulle-là propose quand on la choisit (T286).
        suggestions: serializeChatSuggestions(suggestionsByMessage.get(message.id) ?? []),
      }),
    )
    .filter((message) => message !== null);
  const flag = flagOf(memo.destinationCountryCode);
  const placeName = activeStep?.placeName ?? memo.destinationCity ?? null;
  const pageCount = memo.pageCount > 0 ? memo.pageCount : options.memoryCount * 2;

  return {
    id: memo.id,
    title: memo.title,
    // La photo choisie à la main, sinon celle que le voyage a élue — la même
    // règle que l'accueil et l'écran du voyage (`coverPhotoInclude`). Nulle
    // tant qu'aucune photo n'est arrivée : l'en-tête dessine sa montagne.
    avatarUrl:
      memo.coverPhotoUrl ?? displayablePhotoUrl(options.publicBaseUrl, memo.entries?.[0]?.media),
    destination: memo.destinationName
      ? {
          name: memo.destinationName,
          countryCode: memo.destinationCountryCode,
          city: memo.destinationCity ?? null,
        }
      : null,
    greeting: {
      title: greetingTitle(memo.destinationCity ?? memo.destinationName, flag),
      message: GREETING_MESSAGE,
    },
    // Un voyage sans souvenir n'a pas de carnet à annoncer : la bannière reste absente.
    preview:
      options.memoryCount > 0
        ? {
            memoryCount: options.memoryCount,
            pageCount,
            isOpenable: options.hasReadyRender,
            // Le petit livre et son âge (T297).
            ...bookDoorOf(memo, options.publicBaseUrl),
          }
        : null,
    context: {
      tripId: memo.id,
      tripTitle: memo.title,
      travellerFirstName: firstNameOf(viewer),
      // Le portrait de celui qui lit, pour ses bulles qui ne sont pas encore
      // parties : elles n'ont pas de réponse du serveur où le lire.
      travellerInitials: initialsOf(viewer),
      travellerAvatarUrl: avatarUrlOf(viewer),
      placeName,
      stepNumber: activeStep?.number ?? null,
      // **Plus d'étape « active » à épingler** (12/10/2026). Les builds
      // installés envoyaient cet identifiant avec chaque message, et tout ce
      // qu'on racontait ensuite se rangeait dans la dernière étape : « ton
      // carnet compte une étape de plus », et aucune carte de plus sur
      // l'accueil. L'app n'envoie plus une étape que si on a ouvert le fil
      // depuis sa carte.
      stepId: null,
      prompt: memo.prompt,
      memberCount,
      // **Les étapes du voyage, pour « Déplacer dans une autre étape »**
      // (T270) : l'appui long sur une bulle de photos ouvre la liste, il lui
      // faut donc les étapes sous la main. Le strict nécessaire — de quoi
      // nommer une ligne et l'envoyer — et non les étapes du voyage entières,
      // que l'écran du voyage sert déjà.
      //
      // Servi avec le fil seulement, jamais avec un sondage : la liste change
      // quand le carnet gagne une étape, pas toutes les deux secondes. Le fil
      // se relit à chaque ouverture, et c'est là qu'on appuie longuement.
      steps: memo.steps.map((step) => ({
        id: step.id,
        number: step.number,
        placeName: step.placeName,
      })),
    },
    messages,
    suggestions: serializeChatSuggestions(
      currentSuggestionIds(options.messages.map(suggestionsRowOf), options.turn, tripContext),
    ),
    tripContext: serializeTripContext(tripContext),
    turn: options.turn,
    canClear: memo.ownerAccountId === viewer.id,
    // Ce que la barre d'enregistrement compte pendant qu'on parle : le reste,
    // les seuils et le barème, sans appel de plus.
    dailyCredit: serializeDailyCredit(options.dailyCredit),
    now: options.now.toISOString(),
  };
}

/** La suite du fil depuis `since` — ce que l'app sonde tant qu'un tour est en vol. */
export function serializeChatUpdate(options: {
  memo: MemoForChat;
  /**
   * Le fil entier, en version légère : la numérotation des fiches et les puces
   * se calculent sur **tout** le fil, jamais sur une page de messages. Rien
   * n'y est rattaché — voir ``ThreadOutlineRow``.
   */
  allMessages: readonly ThreadOutlineRow[];
  /** Les messages à rendre, eux, sont hydratés. */
  changed: ChatMessageRow[];
  viewer: Pick<Account, "id">;
  memoryCount: number;
  hasReadyRender: boolean;
  turn: ChatTurnStatus;
  publicBaseUrl: string;
  now: Date;
  dailyCredit: DailyCredit;
  /** **La taille de chaque photo** (T305) — voir ``SerializeMessageOptions.photoSizes``. */
  photoSizes?: ReadonlyMap<string, { widthPx: number; heightPx: number }>;
}) {
  const memberCount = 1 + options.memo.members.filter((member) => member.status === "active").length;
  const messageOptions: SerializeMessageOptions = {
    viewerAccountId: options.viewer.id,
    showsAuthors: memberCount > 1,
    publicBaseUrl: options.publicBaseUrl,
    stepNumbers: stepNumbersOf(options.allMessages),
    viewerIsUnlimited: options.dailyCredit.isUnlimited,
    cover: coverOf(options.memo),
    photoSizes: options.photoSizes,
    reactedMessageIds: reactedMessageIdsOf(options.allMessages),
  };
  const pageCount =
    options.memo.pageCount > 0 ? options.memo.pageCount : options.memoryCount * 2;
  const tripContext = parseTripContext(options.memo.tripContext);

  return {
    messages: options.changed
      .map((message) => serializeChatMessage(message, messageOptions))
      .filter((message) => message !== null),
    suggestions: serializeChatSuggestions(
      currentSuggestionIds(options.allMessages, options.turn, tripContext),
    ),
    // Toujours rendu, pas seulement quand il change : il est petit, et la
    // pastille se remplit sous les yeux à chaque réponse.
    tripContext: serializeTripContext(tripContext),
    preview:
      options.memoryCount > 0
        ? {
            memoryCount: options.memoryCount,
            pageCount,
            isOpenable: options.hasReadyRender,
            ...bookDoorOf(options.memo, options.publicBaseUrl),
          }
        : null,
    turn: options.turn,
    // Rendu à chaque sondage : un co-voyageur raconte peut-être en même temps,
    // et c'est le même pot.
    dailyCredit: serializeDailyCredit(options.dailyCredit),
    now: options.now.toISOString(),
  };
}

/**
 * Ce qu'un `POST` rend : les bulles qu'il vient d'écrire — la bulle « reviens
 * demain » comprise quand ce tour a vidé le pot —, l'état du tour, et le
 * crédit du jour **après** ce tour.
 */
export function serializeChatReceipt(options: {
  written: ChatMessageRow[];
  viewerAccountId: string;
  showsAuthors: boolean;
  publicBaseUrl: string;
  /** Les fiches du fil entier (`id`, `kind`, `seq`), pour numéroter celles du reçu. */
  cards: Pick<ChatMessageRow, "id" | "kind" | "seq" | "entryId">[];
  turn: ChatTurnStatus;
  now: Date;
  dailyCredit: DailyCredit;
}) {
  const messageOptions: SerializeMessageOptions = {
    viewerAccountId: options.viewerAccountId,
    showsAuthors: options.showsAuthors,
    publicBaseUrl: options.publicBaseUrl,
    stepNumbers: stepNumbersOf(options.cards),
    viewerIsUnlimited: options.dailyCredit.isUnlimited,
  };
  return {
    messages: options.written
      .map((message) => serializeChatMessage(message, messageOptions))
      .filter((message) => message !== null),
    turn: options.turn,
    dailyCredit: serializeDailyCredit(options.dailyCredit),
    now: options.now.toISOString(),
  };
}
