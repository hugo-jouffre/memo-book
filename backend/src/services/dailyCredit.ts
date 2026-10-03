import type { IncomingHttpHeaders } from "node:http";
import type { ChatMessage, Prisma, PrismaClient } from "@prisma/client";
import { HttpError } from "../lib/httpError.js";
import { mp4AudioDurationMs } from "../lib/mp4Duration.js";
import type { CallToActionId } from "./callsToAction.js";
import { pauseBeforeSaying } from "./conversation.js";
import {
  DAILY_CREDIT_EXHAUSTED_MESSAGE,
  SUGGESTIONS,
  isSilentCommand,
  isSuggestionId,
} from "./conversationCopy.js";
import { lockThread } from "./conversationThread.js";
import {
  DEFAULT_TIME_ZONE,
  addDays,
  calendarDate,
  isValidTimeZone,
  localDate,
  type LocalDate,
} from "./localCalendar.js";
import { hasUnlimitedAccess } from "./subscriptions.js";

/**
 * **Le crédit du jour d'un voyage** (Hugo, 03/10/2026) — ce qui remplace les
 * trois étapes offertes et les limites de souvenirs.
 *
 * Tout le monde raconte gratuitement, dans la limite de **5 minutes par jour et
 * par voyage**, partagées entre ses co-voyageurs **non abonnés**. Un seul
 * crédit pour le vocal et l'écrit : un vocal consomme sa durée **mesurée**
 * (`lib/mp4Duration.ts`), un texte 75 ms par caractère (800 caractères = une
 * minute). Les photos ne consomment rien. Un abonné raconte sans limite, pour
 * lui seul : ses tours ne prennent rien au pot commun, et il n'en ouvre pas un
 * second à ses co-voyageurs.
 *
 * **Le serveur est la seule vérité.** Les constantes ci-dessous partent avec
 * chaque solde (`serializeDailyCredit`) : l'app prévient à 4:30, pulse à 4:55
 * et coupe à 5:00 avec ce qu'elle reçoit, jamais avec un chiffre à elle.
 *
 * Trois règles tiennent le décompte honnête :
 *
 * 1. **Il se fait dans la transaction qui écrit la bulle du voyageur**, sous
 *    `lockThread` (`memos … FOR UPDATE`). Le pot étant par voyage, ce verrou
 *    sérialise déjà tout ce qui le touche : deux vocaux envoyés au même instant
 *    par deux co-voyageurs se décomptent l'un après l'autre, et le second voit
 *    ce que le premier a pris. Un échec plus loin annule le décompte avec le
 *    reste. (Les limites de souvenirs lisaient puis écrivaient hors de toute
 *    transaction : deux envois simultanés passaient tous les deux.)
 * 2. **Le jour ne recule jamais.** Il se calcule au fuseau de celui qui
 *    raconte (`accounts.timeZone`, Paris à défaut) ; mais si le voyage a déjà
 *    une ligne plus récente — ouverte par un co-voyageur à Tokyo, ou avant un
 *    changement de fuseau du téléphone —, c'est elle qu'on consomme. Passer
 *    d'UTC+14 à UTC-11 ne rouvre donc pas une journée entamée.
 * 3. **On mesure, on ne croit pas** : la durée d'un vocal est lue dans le
 *    fichier, et c'est elle qu'on écrit partout (`media_assets`, la bulle).
 */

// ---------------------------------------------------------------------------
// Le barème
// ---------------------------------------------------------------------------

/** Ce qu'un voyage peut raconter par jour : 5 minutes. */
export const DAILY_CREDIT_LIMIT_MS = 300_000;

/**
 * Ce qu'un caractère écrit consomme : 800 caractères valent une minute, 4 000
 * les cinq. C'est à peu près ce qu'on dit en une minute de vocal — on ne
 * pousse ni vers l'un ni vers l'autre.
 */
export const TEXT_MS_PER_CHARACTER = 75;

/** Le reste à partir duquel la barre d'enregistrement prévient (à 4:30). */
export const WARNING_REMAINING_MS = 30_000;

/** Le reste à partir duquel l'avertissement pulse (à 4:55). */
export const URGENT_REMAINING_MS = 5_000;

/**
 * Ce qu'un **dernier** vocal peut dépasser du reste : 3 secondes. L'app coupe
 * le micro à zéro, mais elle compte avec l'horloge de l'enregistreur, et le
 * fichier finit toujours un peu après — le refuser pour une demi-seconde
 * jetterait un souvenir entier. Au-delà, c'est un vocal enregistré hors ligne
 * ou ailleurs : il attend demain dans la file de l'app — ou l'illimité, s'il
 * dépasse à lui seul une journée entière (`DAILY_CREDIT_TOO_LONG`).
 */
export const VOICE_TOLERANCE_MS = 3_000;

/**
 * Le reste en dessous duquel le pot est **vide**. L'app coupe le micro à zéro
 * d'après son horloge, et le fichier mesuré peut finir quelques millisecondes
 * plus tôt : sans ce seuil, le voyage garderait 40 ms de crédit — jamais
 * épuisé, jamais de bulle « reviens demain », et un micro qui s'ouvrirait pour
 * se refermer aussitôt. Moins d'une seconde ne raconte rien : on arrondit à
 * zéro.
 *
 * Servi avec le solde (`serializeDailyCredit`) : l'app arrondit de même ses
 * décomptes locaux (vocal mis en file hors ligne, texte en attente de son
 * reçu), sans quoi elle garderait 400 ms qu'aucun solde servi ne montre
 * jamais — le décompte, ici, ne laisse pas de reste entre 0 et cette valeur.
 */
export const EXHAUSTION_SLACK_MS = 1_000;

/**
 * Une commande silencieuse (« J’ai retouché le texte à la main. ») ne
 * consomme rien **tant qu'elle reste une phrase d'accusé** : au-delà de ces
 * quelques caractères, c'est un texte qui se fait passer pour une commande, et
 * il paie comme un texte.
 */
export const SILENT_COMMAND_FREE_CHARACTERS = 120;

/** Le code du refus : le tour passera demain, quand le crédit se recharge. */
export const DAILY_CREDIT_EXHAUSTED = "daily_credit_exhausted";

/**
 * Le code du refus d'un tour **plus long qu'une journée entière** de crédit
 * (03/10/2026) : un vocal de plus de 5:03 (`DAILY_CREDIT_LIMIT_MS +
 * VOICE_TOLERANCE_MS`), un texte de plus de 4 000 caractères. Le même `429`
 * aurait fait attendre la file de l'app jusqu'à minuit, puis encore, chaque
 * nuit, sans fin : un pot neuf ne le laisse pas passer non plus. Ce code dit
 * à l'app de ne plus attendre demain — le tour attend l'illimité
 * (`APIError.dailyCreditTooLongCode`).
 */
export const DAILY_CREDIT_TOO_LONG = "daily_credit_too_long";

/** Le message du refus, quand le pot est vide. */
export const DAILY_CREDIT_REFUSAL_MESSAGE =
  "Le crédit du jour de ce voyage est épuisé. Reviens demain pour continuer, ou passe en illimité.";

/**
 * Le message du refus **quand il reste du crédit**, mais pas assez pour ce
 * tour (03/10/2026) : un vocal enregistré hors ligne plus long que le reste,
 * un texte qui ne tient pas. Dire « épuisé » à côté d'une jauge qui montre
 * encore deux minutes serait faux. « Il partira demain » ne vaut que pour un
 * client qui garde le tour (`holdsRefusedTurns`) ; les autres lisent
 * `shortRefusalForLostTurn`.
 */
export const DAILY_CREDIT_SHORT_MESSAGE =
  "Ce tour dépasse le crédit qui reste aujourd’hui pour ce voyage : il partira demain.";

/** Le même, pour une correction à la main : elle n'attend dans aucune file. */
export const CORRECTION_SHORT_MESSAGE =
  "Cette correction dépasse le crédit qui reste aujourd’hui pour ce voyage : réessaie demain, ou passe en illimité.";

/** Un vocal plus long qu'une journée entière de crédit (`DAILY_CREDIT_TOO_LONG`). */
export const VOICE_TOO_LONG_MESSAGE =
  "Ce vocal dépasse les 5 minutes d’une journée : il partira dès que tu passes en illimité.";

/**
 * Le même, pour un client qui **perd** le tour refusé (`holdsRefusedTurns`) :
 * rien ne partira, il faut le redire.
 */
export const VOICE_TOO_LONG_LOST_MESSAGE =
  "Ce vocal dépasse les 5 minutes d’une journée : redis-le en plus court, ou passe en illimité.";

/** Un texte de plus de 4 000 caractères — l'espace fine insécable, comme l'app. */
export const TEXT_TOO_LONG_MESSAGE =
  "Ce message dépasse les 4 000 caractères d’une journée : raccourcis-le, ou passe en illimité.";

/** Une correction qui ajoute à elle seule plus de 4 000 caractères. */
export const CORRECTION_TOO_LONG_MESSAGE =
  "Cette correction ajoute plus de 4 000 caractères, les 5 minutes d’une journée : raccourcis-la, ou passe en illimité.";

/** L'appel à l'action posé sous la bulle « reviens demain » (`callsToAction.ts`). */
export const DAILY_CREDIT_CALL_TO_ACTION: CallToActionId = "daily_credit_subscribe";

/**
 * À qui s'adresse une bulle : `limited` = à ceux qui comptent leur crédit. Un
 * abonné ne la voit pas — il n'a pas à lire « reviens demain »
 * (`chatSerializers.ts`).
 */
export const LIMITED_AUDIENCE = "limited";

// ---------------------------------------------------------------------------
// Le solde
// ---------------------------------------------------------------------------

type Db = PrismaClient | Prisma.TransactionClient;

/** Celui qui raconte, ou qui lit : un compte et son fuseau. */
export interface CreditAccount {
  id: string;
  timeZone: string | null;
}

/** Le crédit d'un voyage aujourd'hui, **vu par quelqu'un**. */
export interface DailyCredit {
  /** Celui qui lit raconte sans limite : il est abonné. */
  isUnlimited: boolean;
  /** Ce que le voyage a consommé ce jour-là, co-voyageurs compris. */
  usedMs: number;
  /** Le jour du crédit — jamais avant celui de la dernière ligne du voyage. */
  day: LocalDate;
  /** Minuit qui suit `day`, au fuseau de celui qui lit. */
  resetsAt: Date;
}

/** Ce qu'il reste aujourd'hui. Jamais négatif. */
export function remainingMs(credit: Pick<DailyCredit, "usedMs">): number {
  return Math.max(0, DAILY_CREDIT_LIMIT_MS - credit.usedMs);
}

/**
 * Le crédit, au champ près de `DailyCredit` côté Swift
 * (`MemoBookCore/DailyCredit.swift`). Servi avec le fil, sa mise à jour, le
 * reçu d'un tour, les réglages du voyage, la carte du voyage en cours de
 * l'accueil, et le corps du refus.
 */
export function serializeDailyCredit(credit: DailyCredit) {
  return {
    isUnlimited: credit.isUnlimited,
    limitMs: DAILY_CREDIT_LIMIT_MS,
    usedMs: credit.usedMs,
    remainingMs: remainingMs(credit),
    textMsPerCharacter: TEXT_MS_PER_CHARACTER,
    warningRemainingMs: WARNING_REMAINING_MS,
    urgentRemainingMs: URGENT_REMAINING_MS,
    exhaustionSlackMs: EXHAUSTION_SLACK_MS,
    day: credit.day,
    resetsAt: credit.resetsAt.toISOString(),
  };
}

export type SerializedDailyCredit = ReturnType<typeof serializeDailyCredit>;

/** Le fuseau d'un compte, s'il est valable ; Paris sinon. */
export function timeZoneOf(account: Pick<CreditAccount, "timeZone">): string {
  return account.timeZone && isValidTimeZone(account.timeZone) ? account.timeZone : DEFAULT_TIME_ZONE;
}

const offsetFormatters = new Map<string, Intl.DateTimeFormat>();

/** L'écart entre l'heure locale d'un fuseau et UTC, à un instant, en millisecondes. */
function utcOffsetMs(instant: number, timeZone: string): number {
  let formatter = offsetFormatters.get(timeZone);
  if (!formatter) {
    formatter = new Intl.DateTimeFormat("en-US", {
      timeZone,
      hourCycle: "h23",
      year: "numeric",
      month: "2-digit",
      day: "2-digit",
      hour: "2-digit",
      minute: "2-digit",
      second: "2-digit",
    });
    offsetFormatters.set(timeZone, formatter);
  }
  const parts = Object.fromEntries(
    formatter.formatToParts(new Date(instant)).map((part) => [part.type, part.value]),
  );
  const asUtc = Date.UTC(
    Number(parts.year),
    Number(parts.month) - 1,
    Number(parts.day),
    Number(parts.hour),
    Number(parts.minute),
    Number(parts.second),
  );
  return asUtc - Math.floor(instant / 1000) * 1000;
}

/**
 * L'instant où le crédit se recharge : minuit au début du jour qui suit `day`,
 * dans ce fuseau. Recalé une fois, pour un changement d'heure qui tomberait
 * entre l'estimation et minuit.
 */
export function localMidnightAfter(day: LocalDate, timeZone: string): Date {
  const naive = Date.parse(`${addDays(day, 1)}T00:00:00Z`);
  const first = naive - utcOffsetMs(naive, timeZone);
  return new Date(naive - utcOffsetMs(first, timeZone));
}

/** Une date de calendrier, telle qu'une colonne `DATE` l'attend : minuit UTC. */
function dateColumn(day: LocalDate): Date {
  return new Date(`${day}T00:00:00Z`);
}

/**
 * Les lignes en cours de ces voyages : pour chacun, la plus récente qui ne
 * soit pas antérieure à `today`. Une ligne plus ancienne est une journée
 * finie ; une plus récente est le jour du voyage, qui ne recule pas.
 */
async function currentRows(db: Db, memoIds: readonly string[], today: LocalDate) {
  if (memoIds.length === 0) return new Map<string, { day: LocalDate; usedMs: number }>();
  const rows = await db.tripDailyUsage.findMany({
    where: { memoId: { in: [...memoIds] }, day: { gte: dateColumn(today) } },
    orderBy: { day: "desc" },
    select: { memoId: true, day: true, usedMs: true },
  });
  const byMemo = new Map<string, { day: LocalDate; usedMs: number }>();
  for (const row of rows) {
    if (!byMemo.has(row.memoId)) byMemo.set(row.memoId, { day: calendarDate(row.day), usedMs: row.usedMs });
  }
  return byMemo;
}

/**
 * Le crédit du jour de plusieurs voyages, pour un lecteur — en une requête
 * (l'accueil en montre un par voyage en cours).
 */
export async function readDailyCredits(
  db: Db,
  input: { memoIds: readonly string[]; viewer: CreditAccount; isUnlimited: boolean; now?: Date },
): Promise<Map<string, DailyCredit>> {
  const now = input.now ?? new Date();
  const timeZone = timeZoneOf(input.viewer);
  const today = localDate(now, timeZone);
  const rows = await currentRows(db, input.memoIds, today);

  return new Map(
    input.memoIds.map((memoId) => {
      const row = rows.get(memoId);
      const day = row?.day ?? today;
      return [
        memoId,
        {
          isUnlimited: input.isUnlimited,
          usedMs: row?.usedMs ?? 0,
          day,
          resetsAt: localMidnightAfter(day, timeZone),
        },
      ];
    }),
  );
}

/**
 * Le crédit du jour d'un voyage, pour un lecteur. `isUnlimited` se lit s'il
 * n'est pas fourni (`hasUnlimitedAccess`).
 */
export async function readDailyCredit(
  db: Db,
  input: { memoId: string; viewer: CreditAccount; isUnlimited?: boolean; now?: Date },
): Promise<DailyCredit> {
  const now = input.now ?? new Date();
  const isUnlimited = input.isUnlimited ?? (await hasUnlimitedAccess(db, input.viewer.id, now));
  const credits = await readDailyCredits(db, {
    memoIds: [input.memoId],
    viewer: input.viewer,
    isUnlimited,
    now,
  });
  return credits.get(input.memoId)!;
}

// ---------------------------------------------------------------------------
// Ce qui consomme
// ---------------------------------------------------------------------------

/**
 * Ce qu'un tour demande au crédit. `correction` : ce sont les caractères
 * qu'une correction à la main ajoute (`PATCH /v1/entries/:id`) — ils paient
 * comme un texte, seul le message d'un refus change.
 */
export type DailyCharge =
  | { kind: "voice"; durationMs: number }
  | { kind: "text"; characters: number; correction?: boolean };

/**
 * Les caractères d'un texte, en **scalaires Unicode** (`[...text]`) — comme
 * l'app (`unicodeScalars.count`) : en UTF-16, un emoji en vaudrait deux, et
 * les deux côtés ne tomberaient pas sur le même nombre.
 */
export function countCharacters(text: string): number {
  return [...text].length;
}

/** Ce qu'un tour coûte, en millisecondes de crédit. */
export function chargeCostMs(charge: DailyCharge): number {
  return charge.kind === "voice" ? charge.durationMs : charge.characters * TEXT_MS_PER_CHARACTER;
}

/**
 * Ce tour passerait-il ? Un vocal passe tant qu'il reste quelque chose et
 * qu'il ne dépasse le reste que de la tolérance ; un texte, seulement s'il
 * tient entier dans le reste — on ne coupe pas une phrase en deux.
 */
export function exceedsDailyCredit(credit: DailyCredit, charge: DailyCharge): boolean {
  if (credit.isUnlimited) return false;
  const remaining = remainingMs(credit);
  const cost = chargeCostMs(charge);
  return charge.kind === "voice" ? remaining <= 0 || cost > remaining + VOICE_TOLERANCE_MS : cost > remaining;
}

/**
 * Ce tour dépasse-t-il **une journée entière** de crédit ? Alors aucun pot
 * neuf ne le laissera passer : son refus porte `DAILY_CREDIT_TOO_LONG`, pas
 * « demain ». Un vocal garde sa tolérance ; un texte de 4 000 caractères
 * tient encore, un de 4 001 non.
 */
export function exceedsWholeDailyCredit(charge: DailyCharge): boolean {
  const cost = chargeCostMs(charge);
  return charge.kind === "voice" ? cost > DAILY_CREDIT_LIMIT_MS + VOICE_TOLERANCE_MS : cost > DAILY_CREDIT_LIMIT_MS;
}

/**
 * Un texte du chat est-il **gratuit** ?
 *
 * - une puce, si son identifiant est connu **et** que le texte est exactement
 *   son libellé du catalogue : « Ça me convient » ne coûte rien, mais un récit
 *   envoyé sous l'identifiant d'une puce reste un récit, et il paie ;
 * - une commande silencieuse, tant qu'elle reste une phrase d'accusé
 *   (`SILENT_COMMAND_FREE_CHARACTERS`).
 *
 * Tout le reste est un texte, contexte du voyage et précisions compris.
 */
export function isFreeChatText(text: string, suggestionId: string | null): boolean {
  if (suggestionId === null) return false;
  if (isSilentCommand(suggestionId)) return countCharacters(text) <= SILENT_COMMAND_FREE_CHARACTERS;
  return isSuggestionId(suggestionId) && SUGGESTIONS[suggestionId].label === text;
}

/**
 * La durée d'un vocal, **lue dans le fichier**. Un fichier qui ne se lit pas
 * est refusé : sans durée, ni le crédit ni la bulle ne sauraient quoi dire.
 */
export function measureVoiceMs(buffer: Buffer): number {
  const duration = mp4AudioDurationMs(buffer);
  if (duration === null) {
    throw new HttpError(
      400,
      "On n’arrive pas à lire ce vocal : le fichier est peut-être incomplet. Réessaie de l’enregistrer.",
      "unreadable_audio",
    );
  }
  return duration;
}

/**
 * Le client qui raconte **garde-t-il un tour refusé** pour le renvoyer seul ?
 * (03/10/2026)
 *
 * L'app de ce lot garde un tour refusé faute de crédit dans sa file et le
 * renvoie à minuit, ou à l'abonnement (`RecordingOutbox`) ; elle envoie
 * `X-Time-Zone` sur chaque appel. Les builds installés avant elle, non : leur
 * file range tout 4xx en refus définitif, **efface le vocal**, puis affiche
 * « Ton vocal n’a pas pu être envoyé. » suivi de notre message. Leur dire « il
 * partira demain » ferait attendre un souvenir déjà perdu. L'en-tête est le
 * seul signe qu'on ait de la différence : sans lui, le refus ne promet aucun
 * renvoi (`dailyCreditRefusal`).
 *
 * La présence suffit, pas la validité du fuseau : c'est le build qu'on
 * reconnaît, pas l'heure qu'il est chez lui.
 */
export function holdsRefusedTurns(request: { headers: IncomingHttpHeaders }): boolean {
  const header = request.headers["x-time-zone"];
  return typeof header === "string" && header.trim().length > 0;
}

/**
 * Une durée de crédit comme l'app l'écrit (`DailyCreditCopy.duration`) :
 * « 45 s », « 3 min », « 1 min 05 », « 2 min 30 ». Arrondie à la seconde
 * inférieure — on ne promet pas une seconde qu'on n'a pas.
 */
export function formatCreditDuration(milliseconds: number): string {
  const seconds = Math.floor(Math.max(0, milliseconds) / 1000);
  if (seconds === 0) return "moins d’une seconde";
  const minutes = Math.floor(seconds / 60);
  const rest = seconds % 60;
  if (minutes === 0) return `${rest} s`;
  if (rest === 0) return `${minutes} min`;
  return `${minutes} min ${String(rest).padStart(2, "0")}`;
}

/**
 * Le refus d'un tour plus long que le reste, pour un client qui **perd** le
 * tour (`holdsRefusedTurns`) : ce qu'il reste, et ce qu'on peut faire —
 * jamais « il partira demain ». Il se lit aussi derrière « Ton vocal n’a pas
 * pu être envoyé. », que les builds installés écrivent devant.
 */
export function shortRefusalForLostTurn(credit: DailyCredit, charge: DailyCharge): string {
  const left = formatCreditDuration(remainingMs(credit));
  return charge.kind === "voice"
    ? `Il reste ${left} aujourd’hui sur ce voyage, pas assez pour ce vocal : redis-le en plus court, ou passe en illimité.`
    : `Il reste ${left} aujourd’hui sur ce voyage, pas assez pour ce message : raccourcis-le, ou passe en illimité.`;
}

/**
 * Le refus, avec le solde dans le corps : l'app y lit `resetsAt` pour sa file.
 *
 * Trois cas, trois phrases (03/10/2026) — toujours un `429` avec le solde :
 *
 * - le tour dépasse une journée entière (`exceedsWholeDailyCredit`) : code
 *   `daily_credit_too_long`, il n'attend pas demain mais l'illimité ;
 * - il reste du crédit, mais pas assez : `daily_credit_exhausted`, « il
 *   partira demain » — sans dire « épuisé » ;
 * - le pot est vide : `daily_credit_exhausted`, « épuisé ».
 *
 * `holdsTurn` dit si le client garde le tour refusé (`holdsRefusedTurns`).
 * Sans lui, « il partira demain » et « dès que tu passes en illimité » sont
 * faux : le tour est déjà perdu, la phrase dit de le redire. Le code ne
 * change pas, et « épuisé, reviens demain » ne promet rien : il reste.
 */
export function dailyCreditRefusal(credit: DailyCredit, charge: DailyCharge, holdsTurn: boolean): HttpError {
  const correction = charge.kind === "text" && charge.correction === true;
  const tooLong = exceedsWholeDailyCredit(charge);
  const message = tooLong
    ? charge.kind === "voice"
      ? holdsTurn
        ? VOICE_TOO_LONG_MESSAGE
        : VOICE_TOO_LONG_LOST_MESSAGE
      : correction
        ? CORRECTION_TOO_LONG_MESSAGE
        : TEXT_TOO_LONG_MESSAGE
    : remainingMs(credit) > 0
      ? correction
        ? CORRECTION_SHORT_MESSAGE
        : holdsTurn
          ? DAILY_CREDIT_SHORT_MESSAGE
          : shortRefusalForLostTurn(credit, charge)
      : DAILY_CREDIT_REFUSAL_MESSAGE;

  return new HttpError(429, message, tooLong ? DAILY_CREDIT_TOO_LONG : DAILY_CREDIT_EXHAUSTED, {
    dailyCredit: serializeDailyCredit(credit),
  });
}

/**
 * Levée **dans** la transaction du tour quand le crédit ne suffit pas : elle
 * l'annule entière (rien n'est écrit), et la route prend le chemin du refus
 * (`refuseForDailyCredit`). Elle garde le tour refusé : c'est lui qui choisit
 * le code et la phrase du refus.
 */
export class DailyCreditExhaustedError extends Error {
  constructor(
    readonly credit: DailyCredit,
    readonly charge: DailyCharge,
  ) {
    super(DAILY_CREDIT_REFUSAL_MESSAGE);
    this.name = "DailyCreditExhaustedError";
  }
}

export interface DailyChargeResult {
  /** Le crédit **après** ce tour, vu par celui qui raconte. */
  credit: DailyCredit;
  /** La bulle « reviens demain », quand ce tour vient de vider le pot. */
  notice: ChatMessage | null;
}

/**
 * Décompte un tour du crédit du jour de son voyage.
 *
 * ⚠️ **À appeler dans la transaction qui écrit le tour, après `lockThread`** :
 * c'est le verrou du voyage qui rend la lecture puis l'écriture sûres. Lève
 * `DailyCreditExhaustedError` quand le tour ne passe pas — la transaction
 * s'annule, et rien n'a été compté.
 *
 * Un abonné ne consomme rien, mais ce qu'il dit s'ajoute aux colonnes de
 * détail (`voiceMs`, `textCharacters`) : c'est ce qui dira si l'abonnement
 * couvre ce qu'il coûte. Un vocal toléré au-delà du reste est compté jusqu'à
 * la limite, pas au-delà.
 *
 * Quand le tour fait tomber le reste à zéro, MEMO pose sa bulle « reviens
 * demain » dans la même transaction — le reçu la contient.
 */
export async function chargeDailyCredit(
  tx: Prisma.TransactionClient,
  input: {
    memoId: string;
    account: CreditAccount;
    isUnlimited: boolean;
    charge: DailyCharge;
    now?: Date;
  },
): Promise<DailyChargeResult> {
  const now = input.now ?? new Date();
  const timeZone = timeZoneOf(input.account);
  const today = localDate(now, timeZone);
  const current = (await currentRows(tx, [input.memoId], today)).get(input.memoId);
  const day = current?.day ?? today;
  const usedMs = current?.usedMs ?? 0;
  const before: DailyCredit = {
    isUnlimited: input.isUnlimited,
    usedMs,
    day,
    resetsAt: localMidnightAfter(day, timeZone),
  };

  if (exceedsDailyCredit(before, input.charge)) throw new DailyCreditExhaustedError(before, input.charge);

  const charged = Math.min(DAILY_CREDIT_LIMIT_MS, usedMs + chargeCostMs(input.charge));
  // Un reste de quelques millisecondes est un pot vide — `EXHAUSTION_SLACK_MS`.
  const nextUsedMs = input.isUnlimited
    ? usedMs
    : DAILY_CREDIT_LIMIT_MS - charged < EXHAUSTION_SLACK_MS
      ? DAILY_CREDIT_LIMIT_MS
      : charged;
  const voiceMs = input.charge.kind === "voice" ? input.charge.durationMs : 0;
  const textCharacters = input.charge.kind === "text" ? input.charge.characters : 0;

  await tx.tripDailyUsage.upsert({
    where: { memoId_day: { memoId: input.memoId, day: dateColumn(day) } },
    create: { memoId: input.memoId, day: dateColumn(day), usedMs: nextUsedMs, voiceMs, textCharacters },
    update: {
      usedMs: nextUsedMs,
      voiceMs: { increment: voiceMs },
      textCharacters: { increment: textCharacters },
    },
  });

  const exhaustedNow = !input.isUnlimited && usedMs < DAILY_CREDIT_LIMIT_MS && nextUsedMs >= DAILY_CREDIT_LIMIT_MS;
  const notice = exhaustedNow ? await postExhaustedNotice(tx, { memoId: input.memoId, day, now }) : null;

  return { credit: { ...before, usedMs: nextUsedMs }, notice };
}

/**
 * La bulle « reviens demain » de MEMO — **une fois par voyage et par jour**
 * (`limitNotifiedAt`). Rend `null` quand elle est déjà dans le fil.
 *
 * Elle porte le bouton `daily_credit_subscribe` (résolu à la lecture, et
 * jamais pour un abonné), la clé `notice` du jour, et `audience: "limited"` :
 * un co-voyageur abonné ne la voit pas. À appeler sous `lockThread`.
 */
export async function postExhaustedNotice(
  tx: Prisma.TransactionClient,
  input: { memoId: string; day: LocalDate; now?: Date },
): Promise<ChatMessage | null> {
  const now = input.now ?? new Date();
  const where = { memoId_day: { memoId: input.memoId, day: dateColumn(input.day) } };

  const { count } = await tx.tripDailyUsage.updateMany({
    where: { memoId: input.memoId, day: dateColumn(input.day), limitNotifiedAt: null },
    data: { limitNotifiedAt: now },
  });
  if (count === 0) {
    // Pas de ligne du tout : un premier vocal du jour déjà trop long. Sinon,
    // la bulle a déjà été posée aujourd'hui.
    const existing = await tx.tripDailyUsage.findUnique({ where, select: { memoId: true } });
    if (existing) return null;
    await tx.tripDailyUsage.create({
      data: { memoId: input.memoId, day: dateColumn(input.day), limitNotifiedAt: now },
    });
  }

  return tx.chatMessage.create({
    data: {
      memoId: input.memoId,
      author: "memo",
      kind: "text",
      text: DAILY_CREDIT_EXHAUSTED_MESSAGE,
      pauseMilliseconds: pauseBeforeSaying(DAILY_CREDIT_EXHAUSTED_MESSAGE),
      model: "scripted",
      payload: {
        callToAction: { id: DAILY_CREDIT_CALL_TO_ACTION },
        notice: `${DAILY_CREDIT_EXHAUSTED}:${input.day}`,
        audience: LIMITED_AUDIENCE,
      },
    },
  });
}

/**
 * Le chemin du refus : la bulle « reviens demain » dans sa propre petite
 * transaction (le tour, lui, n'a rien écrit), puis le `429` avec le solde.
 *
 * **La bulle seulement si le pot est vraiment vide.** Un vocal enregistré
 * hors ligne qui dépasse un reste de deux minutes est refusé aussi — il attend
 * demain dans la file de l'app —, mais écrire alors « ce voyage a déjà raconté
 * ses 5 minutes du jour » serait faux, et poser la bulle du jour trop tôt
 * l'empêcherait de paraître au vrai moment. De même pour un tour plus long
 * qu'une journée entière : la bulle ne vient que si le pot est vide, et le
 * refus dit ce qui se passe (`dailyCreditRefusal`).
 */
export async function refuseForDailyCredit(
  prisma: PrismaClient,
  memoId: string,
  credit: DailyCredit,
  charge: DailyCharge,
  options: { holdsTurn: boolean; now?: Date },
): Promise<never> {
  if (remainingMs(credit) <= 0) {
    await prisma.$transaction(async (tx) => {
      await lockThread(tx, memoId);
      await postExhaustedNotice(tx, { memoId, day: credit.day, now: options.now ?? new Date() });
    });
  }
  throw dailyCreditRefusal(credit, charge, options.holdsTurn);
}

/**
 * Exécute la transaction d'un tour et prend le chemin du refus si le crédit
 * manque — le geste commun de toutes les routes qui consomment. `holdsTurn` :
 * le client garde-t-il le tour refusé (`holdsRefusedTurns`) — c'est ce qui
 * choisit la phrase du refus.
 */
export async function withDailyCredit<T>(
  prisma: PrismaClient,
  memoId: string,
  options: { holdsTurn: boolean },
  run: () => Promise<T>,
): Promise<T> {
  try {
    return await run();
  } catch (cause) {
    if (cause instanceof DailyCreditExhaustedError) {
      return refuseForDailyCredit(prisma, memoId, cause.credit, cause.charge, options);
    }
    throw cause;
  }
}

// ---------------------------------------------------------------------------
// Le filet du transcripteur
// ---------------------------------------------------------------------------

/**
 * L'écart en dessous duquel une transcription trop longue ne dit rien : une
 * hallucination du transcripteur sur un vocal d'une seconde, quelqu'un qui
 * parle vite. Au-delà, c'est un fichier dont la durée ne dit pas ce qu'il
 * contient.
 */
export const TRANSCRIPT_OVERRUN_FLOOR_MS = 15_000;

/**
 * Ce qu'une transcription a dit **de plus** que le vocal mesuré, en
 * millisecondes de crédit — 0 tant que c'est vraisemblable (03/10/2026).
 *
 * `lib/mp4Duration.ts` recoupe les en-têtes, mais un fichier peut encore
 * tasser plusieurs trames par paquet à très bas débit, ou accélérer la voix
 * avant de l'encoder : la durée mesurée est alors vraie pour le conteneur,
 * fausse pour le récit. Le texte, lui, ne ment pas : au-delà de **deux fois**
 * la durée mesurée (on dit environ un caractère toutes les 75 ms), l'écart
 * (`caractères × 75 − durée mesurée`) est ce qui n'a jamais été décompté.
 */
export function transcriptOverrunMs(input: { characters: number; measuredMs: number }): number {
  const spokenMs = input.characters * TEXT_MS_PER_CHARACTER;
  if (spokenMs <= 2 * input.measuredMs) return 0;
  const overrun = spokenMs - input.measuredMs;
  return overrun >= TRANSCRIPT_OVERRUN_FLOOR_MS ? overrun : 0;
}

/**
 * Décompte l'écart d'une transcription trop longue (`transcriptOverrunMs`),
 * **sans rien refuser** : le vocal est déjà dans le fil, et son souvenir
 * aussi. Compté jusqu'à la limite, sous le verrou du voyage, sur la ligne du
 * jour qui ne recule pas — comme `chargeDailyCredit`. La bulle « reviens
 * demain » n'est pas posée ici : le tour suivant la posera en étant refusé.
 *
 * Un abonné ne consomme rien : rend `null`.
 */
export async function chargeTranscriptOverrun(
  prisma: PrismaClient,
  input: { memoId: string; account: CreditAccount; isUnlimited: boolean; overrunMs: number; now?: Date },
): Promise<DailyCredit | null> {
  if (input.isUnlimited || input.overrunMs <= 0) return null;
  const now = input.now ?? new Date();
  const timeZone = timeZoneOf(input.account);

  return prisma.$transaction(async (tx) => {
    await lockThread(tx, input.memoId);
    const today = localDate(now, timeZone);
    const current = (await currentRows(tx, [input.memoId], today)).get(input.memoId);
    const day = current?.day ?? today;
    const charged = Math.min(DAILY_CREDIT_LIMIT_MS, (current?.usedMs ?? 0) + input.overrunMs);
    const usedMs = DAILY_CREDIT_LIMIT_MS - charged < EXHAUSTION_SLACK_MS ? DAILY_CREDIT_LIMIT_MS : charged;

    await tx.tripDailyUsage.upsert({
      where: { memoId_day: { memoId: input.memoId, day: dateColumn(day) } },
      create: { memoId: input.memoId, day: dateColumn(day), usedMs },
      update: { usedMs },
    });
    return { isUnlimited: false, usedMs, day, resetsAt: localMidnightAfter(day, timeZone) };
  });
}

/** Le compte qui raconte, et s'il raconte sans limite — lus avant la transaction. */
export async function loadSpeaker(
  prisma: PrismaClient,
  accountId: string,
  now: Date = new Date(),
): Promise<{ account: CreditAccount; isUnlimited: boolean }> {
  const [account, isUnlimited] = await Promise.all([
    prisma.account.findUniqueOrThrow({ where: { id: accountId }, select: { id: true, timeZone: true } }),
    hasUnlimitedAccess(prisma, accountId, now),
  ]);
  return { account, isUnlimited };
}
