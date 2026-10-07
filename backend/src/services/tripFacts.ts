import type { MemoStep, Prisma, PrismaClient, TripTransport } from "@prisma/client";
import type { AppContext } from "../context.js";
import { parseInsights, type EntryInsights, type TransportKind } from "./redaction.js";

/**
 * **Les étapes et les chiffres d'un vrai voyage** (T227, Hugo 06/10/2026 —
 * « crée les routes nécessaires pour que les étapes, le nombre de souvenirs et
 * les chiffres du dos de couverture soient écrits et enregistrés pour chaque
 * voyage »).
 *
 * Jusque-là, seul le jeu d'essai écrivait `memo_steps`, la destination et les
 * compteurs du voyage (`memoryCount`, `photoCount`, `dayCount`,
 * `distanceKilometres`) : un vrai voyage montrait un accueil sans étape, un
 * dos de couverture sans chiffre et « 0 souvenir ». Pas de nouvelle route :
 * les champs que l'app lit déjà **se remplissent**, recalculés ici à chaque
 * souvenir traité — rédaction finie (c'est elle qui relève le lieu, le pays,
 * les kilomètres, les transports : `Entry.insights`), photo reçue, souvenir
 * supprimé, dates du voyage changées, et juste avant chaque composition.
 *
 * **Tout se recalcule depuis les souvenirs**, jamais par incrément : une
 * suppression, une rédaction relancée ou deux souvenirs traités ensemble
 * donnent le même résultat qu'un calcul à froid. Sous verrou par voyage, pour
 * que deux recalculs simultanés ne numérotent pas les étapes chacun de son
 * côté.
 *
 * **Rien n'est écrit qui n'a pas changé** : l'empreinte du carnet
 * (`bookFingerprint.ts`) lit la date de modification des souvenirs et des
 * étapes, et un recalcul à vide relancerait une composition pour rien.
 */

const DAY_MS = 86_400_000;

/**
 * Les transports que la rédaction relève, ramenés aux sept que porte une
 * étape (`TripTransport`, et l'icône de l'app). Le métro roule sur des rails,
 * le taxi et la moto sur la route, la trottinette se range avec le vélo.
 */
const STEP_TRANSPORT: Record<TransportKind, TripTransport> = {
  plane: "plane",
  train: "train",
  bus: "bus",
  car: "car",
  boat: "boat",
  bike: "bike",
  walk: "walk",
  scooter: "bike",
  motorbike: "car",
  metro: "train",
  taxi: "car",
};

/** « Rome », « rome » et « Róme » sont le même lieu. */
function placeKey(place: string): string {
  return place
    .normalize("NFD")
    .replace(/\p{Diacritic}/gu, "")
    .trim()
    .toLowerCase();
}

interface FactEntry {
  id: string;
  kind: "audio" | "text" | "photo";
  capturedAt: Date;
  createdAt: Date;
  stepId: string | null;
  insights: EntryInsights;
  cdnUrl: string | null;
}

/** Un groupe de souvenirs qui deviendra une étape. */
interface StepGroup {
  place: string | null;
  entries: FactEntry[];
  /** L'étape existante qu'il reprend, s'il y en a une. */
  stepId: string | null;
  /** Une étape choisie par le voyageur (`stepId` envoyé avec le message). */
  pinned: boolean;
}

/** L'élément le plus fréquent — le premier vu, à égalité. */
function mostCommon<T>(values: T[], key: (value: T) => string): T | null {
  const counts = new Map<string, { value: T; count: number }>();
  for (const value of values) {
    const k = key(value);
    const known = counts.get(k);
    if (known) known.count += 1;
    else counts.set(k, { value, count: 1 });
  }
  let best: { value: T; count: number } | null = null;
  for (const candidate of counts.values()) {
    if (!best || candidate.count > best.count) best = candidate;
  }
  return best?.value ?? null;
}

/** Le lieu qu'un souvenir raconte : celui que la rédaction a relevé. */
function placeOf(entry: FactEntry): string | null {
  return entry.insights.currentPlace?.trim() || null;
}

/**
 * Le nombre de jours du voyage, comme le dos de couverture le dit : du départ
 * jusqu'au retour — **jusqu'à aujourd'hui** s'il est en cours —, bornes
 * comprises. Sans date de départ (un voyage d'avant T238), les jours qui ont
 * au moins un souvenir. `null` pour un voyage qui n'a pas commencé.
 */
export function dayCountOf(
  memo: { startDate: Date | null; endDate: Date | null },
  capturedAt: Date[],
  now: Date,
): number | null {
  const utcDay = (date: Date) => Date.UTC(date.getUTCFullYear(), date.getUTCMonth(), date.getUTCDate());

  if (memo.startDate) {
    if (utcDay(memo.startDate) > utcDay(now)) return null;
    const end = memo.endDate && memo.endDate.getTime() < now.getTime() ? memo.endDate : now;
    return Math.max(1, Math.round((utcDay(end) - utcDay(memo.startDate)) / DAY_MS) + 1);
  }

  const days = new Set(capturedAt.map((date) => utcDay(date)));
  return days.size > 0 ? days.size : null;
}

/**
 * Découpe les souvenirs en étapes : **une par lieu successif**.
 *
 * - Dans l'ordre où ils ont été vécus (`capturedAt`). Un souvenir dont le lieu
 *   change ouvre une nouvelle étape ; revenir à Rome après Florence en ouvre
 *   une troisième — c'est un itinéraire, pas un index des villes.
 * - Un souvenir sans lieu (une photo, un vocal pas encore rédigé, un récit qui
 *   ne dit pas où il se passe) rejoint l'étape en cours ; avant le premier
 *   lieu, il rejoint la première étape. Aucun lieu du tout : une seule étape,
 *   sans nom — c'est elle qui porte la croix de l'accueil (T235).
 * - **Un souvenir raconté depuis une étape** (« Raconter » sur la carte d'une
 *   étape : l'app envoie son `stepId` avec le message) y reste, quel que soit
 *   le lieu que la rédaction y lit. C'est le geste du voyageur ; il gagne.
 */
export function groupIntoSteps(entries: FactEntry[], pinnedStepOf: Map<string, string>): StepGroup[] {
  const pinned = new Map<string, StepGroup>();
  const auto: StepGroup[] = [];
  const leading: FactEntry[] = [];

  for (const entry of entries) {
    const pin = pinnedStepOf.get(entry.id);
    if (pin) {
      const group = pinned.get(pin) ?? { place: null, entries: [], stepId: pin, pinned: true };
      group.entries.push(entry);
      pinned.set(pin, group);
      continue;
    }

    const place = placeOf(entry);
    const current = auto.at(-1);
    if (!place) {
      if (current) current.entries.push(entry);
      else leading.push(entry);
      continue;
    }
    if (current && current.place !== null && placeKey(current.place) === placeKey(place)) {
      current.entries.push(entry);
      continue;
    }
    auto.push({ place, entries: [entry], stepId: null, pinned: false });
  }

  if (leading.length > 0) {
    const first = auto[0];
    if (first) first.entries.unshift(...leading);
    else auto.push({ place: null, entries: leading, stepId: null, pinned: false });
  }

  return [...pinned.values(), ...auto];
}

/**
 * Recalcule les étapes et les chiffres d'un voyage depuis ses souvenirs.
 * Sûr à rappeler : un second appel sans changement n'écrit rien.
 */
export async function refreshTripFacts(prisma: PrismaClient, memoId: string, now = new Date()): Promise<void> {
  await prisma.$transaction(
    async (tx) => {
      // Un verrou consultatif par voyage, et non `FOR UPDATE` sur la ligne du
      // voyage : celui-là, la conversation le prend (`lockThread`), et un
      // recalcul n'a pas à faire attendre un message.
      await tx.$executeRaw`SELECT pg_advisory_xact_lock(hashtext(${`trip-facts:${memoId}`}))`;

      const memo = await tx.memo.findUnique({
        where: { id: memoId },
        select: {
          startDate: true,
          endDate: true,
          destinationName: true,
          destinationCountryCode: true,
          destinationCity: true,
          destinationInferred: true,
          memoryCount: true,
          photoCount: true,
          dayCount: true,
          distanceKilometres: true,
          steps: true,
        },
      });
      if (!memo) return;

      const rows = await tx.entry.findMany({
        where: { memoId },
        orderBy: [{ capturedAt: "asc" }, { createdAt: "asc" }],
        select: {
          id: true,
          kind: true,
          capturedAt: true,
          createdAt: true,
          stepId: true,
          insights: true,
          media: { select: { cdnUrl: true } },
        },
      });
      const entries: FactEntry[] = rows.map((row) => ({
        id: row.id,
        kind: row.kind,
        capturedAt: row.capturedAt,
        createdAt: row.createdAt,
        stepId: row.stepId,
        insights: parseInsights(row.insights),
        cdnUrl: row.media?.cdnUrl ?? null,
      }));

      await writeSteps(tx, memoId, memo.steps, entries);
      await writeFigures(tx, memoId, memo, entries, now);
    },
    { timeout: 20_000 },
  );
}

/**
 * La même chose, sans jamais faire échouer l'appelant : un souvenir enregistré
 * ou une rédaction finie ne doivent pas répondre 500 parce que les chiffres de
 * l'accueil n'ont pas pu suivre. Le recalcul suivant rattrape.
 */
export async function refreshTripFactsQuietly(context: Pick<AppContext, "prisma" | "logger">, memoId: string) {
  try {
    await refreshTripFacts(context.prisma, memoId);
  } catch (cause) {
    context.logger.warn({ err: cause, memoId }, "Étapes et chiffres du voyage non recalculés");
  }
}

type Tx = Prisma.TransactionClient;
type ExistingStep = MemoStep;

/** Les souvenirs que le voyageur a racontés depuis une étape précise. */
async function pinnedSteps(tx: Tx, memoId: string, steps: ExistingStep[]): Promise<Map<string, string>> {
  const known = new Set(steps.map((step) => step.id));
  const messages = await tx.chatMessage.findMany({
    where: { memoId, author: "traveller", stepId: { not: null } },
    select: { stepId: true, entryId: true, payload: true },
  });

  const pinned = new Map<string, string>();
  for (const message of messages) {
    if (!message.stepId || !known.has(message.stepId)) continue;
    const ids = new Set<string>();
    if (message.entryId) ids.add(message.entryId);
    // Un message de photos en porte plusieurs (`payload.entryIds`).
    const payload = message.payload as { entryIds?: unknown } | null;
    if (payload && Array.isArray(payload.entryIds)) {
      for (const id of payload.entryIds) if (typeof id === "string") ids.add(id);
    }
    for (const id of ids) pinned.set(id, message.stepId);
  }
  return pinned;
}

async function writeSteps(tx: Tx, memoId: string, existing: ExistingStep[], entries: FactEntry[]) {
  const byId = new Map(existing.map((step) => [step.id, step]));
  const groups = groupIntoSteps(entries, await pinnedSteps(tx, memoId, existing));

  // --- Chaque groupe reprend une étape existante, si possible ---------------
  //
  // Celle où la plupart de ses souvenirs sont déjà rangés, puis une étape libre
  // du même lieu. Garder l'identifiant garde ce qui y est attaché : la
  // validation (« Valider cette étape »), la photo, les messages du fil.
  const claimed = new Set(groups.filter((group) => group.pinned).map((group) => group.stepId!));
  const pinnedById = new Map(groups.filter((group) => group.pinned).map((group) => [group.stepId!, group]));
  const kept: StepGroup[] = groups.filter((group) => group.pinned);

  for (const group of groups) {
    if (group.pinned) continue;
    const vote = mostCommon(
      group.entries.flatMap((entry) => (entry.stepId && byId.has(entry.stepId) ? [entry.stepId] : [])),
      (id) => id,
    );

    const pinnedTarget = vote ? pinnedById.get(vote) : undefined;
    if (pinnedTarget) {
      // Le même lieu que celui où le voyageur a raconté : une seule étape.
      pinnedTarget.entries.push(...group.entries);
      pinnedTarget.place ??= group.place;
      continue;
    }

    if (vote && !claimed.has(vote)) {
      group.stepId = vote;
    } else if (group.place) {
      const key = placeKey(group.place);
      const samePlace = existing.find(
        (step) => !claimed.has(step.id) && step.placeName && placeKey(step.placeName) === key,
      );
      if (samePlace) group.stepId = samePlace.id;
    }
    if (group.stepId) claimed.add(group.stepId);
    kept.push(group);
  }

  // Dans l'ordre du voyage : la première date de chaque étape.
  const firstAt = (group: StepGroup) =>
    Math.min(...group.entries.map((entry) => entry.capturedAt.getTime()));
  kept.sort((a, b) => firstAt(a) - firstAt(b));

  // --- Les étapes qui ne portent plus rien disparaissent --------------------
  //
  // T235 : la croix efface les souvenirs d'une étape un à un ; le dernier parti,
  // l'étape n'a plus rien à montrer. Ses messages du fil restent (`SetNull`).
  const orphans = existing.filter((step) => !claimed.has(step.id)).map((step) => step.id);
  if (orphans.length > 0) await tx.memoStep.deleteMany({ where: { id: { in: orphans } } });

  // --- Les numéros, sans heurter l'unicité (voyage, numéro) -----------------
  //
  // Une étape qui change de rang passe d'abord par un numéro négatif : ainsi
  // aucune écriture ne prend un numéro qu'une autre tient encore.
  const moving = kept.flatMap((group, index) => {
    const step = group.stepId ? byId.get(group.stepId) : undefined;
    return step && step.number !== index + 1 ? [{ id: step.id, number: index + 1 }] : [];
  });
  for (const { id, number } of moving) {
    await tx.memoStep.update({ where: { id }, data: { number: -number } });
  }

  for (const [index, group] of kept.entries()) {
    const number = index + 1;
    const step = group.stepId ? byId.get(group.stepId) : undefined;
    const fields = stepFields(group, step);

    if (!step) {
      const created = await tx.memoStep.create({ data: { memoId, number, ...fields } });
      group.stepId = created.id;
    } else {
      const changed: Prisma.MemoStepUpdateInput = {};
      if (step.number !== number) changed.number = number;
      if (step.placeName !== fields.placeName) changed.placeName = fields.placeName;
      if (step.destinationName !== fields.destinationName) changed.destinationName = fields.destinationName;
      if (step.destinationCountryCode !== fields.destinationCountryCode) {
        changed.destinationCountryCode = fields.destinationCountryCode;
      }
      if (step.startDate?.getTime() !== fields.startDate.getTime()) changed.startDate = fields.startDate;
      if (step.endDate?.getTime() !== fields.endDate.getTime()) changed.endDate = fields.endDate;
      if (step.transport !== fields.transport) changed.transport = fields.transport;
      if (step.photoUrl !== fields.photoUrl) changed.photoUrl = fields.photoUrl;
      if (Object.keys(changed).length > 0) await tx.memoStep.update({ where: { id: step.id }, data: changed });
    }

    // Les souvenirs qui changent d'étape, et eux seuls.
    const moved = group.entries.filter((entry) => entry.stepId !== group.stepId).map((entry) => entry.id);
    if (moved.length > 0) {
      await tx.entry.updateMany({ where: { id: { in: moved } }, data: { stepId: group.stepId } });
    }
  }
}

/** Ce qu'une étape dit d'elle-même, tiré de ses souvenirs. */
function stepFields(group: StepGroup, step: ExistingStep | undefined) {
  const times = group.entries.map((entry) => entry.capturedAt.getTime());
  const country = mostCommon(
    group.entries.flatMap((entry) => entry.insights.countries.slice(0, 1)),
    (candidate) => candidate.code,
  );
  // Comment on est arrivé : le premier transport que ses souvenirs nomment.
  const transport = group.entries.flatMap((entry) => entry.insights.transports)[0];
  const photo = group.entries.find((entry) => entry.kind === "photo" && entry.cdnUrl);

  const majorityPlace = mostCommon(
    group.entries.flatMap((entry) => {
      const place = placeOf(entry);
      return place ? [place] : [];
    }),
    placeKey,
  );

  return {
    // Une étape choisie par le voyageur garde son nom ; les autres prennent
    // celui de leur lieu. Ce que la rédaction ne sait pas, on ne l'efface pas.
    placeName: (group.pinned ? (step?.placeName ?? majorityPlace) : (group.place ?? step?.placeName)) ?? null,
    destinationName: country?.name ?? step?.destinationName ?? null,
    destinationCountryCode: country?.code ?? step?.destinationCountryCode ?? null,
    startDate: new Date(Math.min(...times)),
    endDate: new Date(Math.max(...times)),
    transport: transport ? STEP_TRANSPORT[transport.kind] : (step?.transport ?? null),
    photoUrl: photo?.cdnUrl ?? step?.photoUrl ?? null,
  };
}

type MemoFigures = {
  startDate: Date | null;
  endDate: Date | null;
  destinationName: string | null;
  destinationCountryCode: string | null;
  destinationCity: string | null;
  destinationInferred: boolean;
  memoryCount: number;
  photoCount: number | null;
  dayCount: number | null;
  distanceKilometres: number | null;
};

async function writeFigures(tx: Tx, memoId: string, memo: MemoFigures, entries: FactEntry[], now: Date) {
  const memories = entries.filter((entry) => entry.kind !== "photo");
  const photoCount = entries.length - memories.length;

  // Les kilomètres que la rédaction a pu estimer, souvenir par souvenir. Aucun :
  // `null`, et le dos de couverture n'affiche pas « 0 km parcourus ».
  const distances = entries.flatMap((entry) =>
    entry.insights.distanceKilometres && entry.insights.distanceKilometres > 0
      ? [entry.insights.distanceKilometres]
      : [],
  );
  const distanceKilometres =
    distances.length > 0 ? Math.round(distances.reduce((sum, km) => sum + km, 0) * 10) / 10 : null;

  const data: Prisma.MemoUpdateInput = {};
  if (memo.memoryCount !== memories.length) data.memoryCount = memories.length;
  if (memo.photoCount !== photoCount) data.photoCount = photoCount;
  if (memo.distanceKilometres !== distanceKilometres) data.distanceKilometres = distanceKilometres;

  const dayCount = dayCountOf(memo, entries.map((entry) => entry.capturedAt), now);
  if (memo.dayCount !== dayCount) data.dayCount = dayCount;

  // **La destination**, quand personne ne l'a posée : le pays le plus cité par
  // les souvenirs, et sa ville la plus citée. Elle suit les souvenirs tant
  // qu'elle est déduite (`destinationInferred`).
  const mayInfer =
    memo.destinationInferred || (!memo.destinationName && !memo.destinationCountryCode && !memo.destinationCity);
  if (mayInfer) {
    const country = mostCommon(
      entries.flatMap((entry) => entry.insights.countries),
      (candidate) => candidate.code,
    );
    const city = country
      ? mostCommon(
          entries
            .filter((entry) => entry.insights.countries.some((candidate) => candidate.code === country.code))
            .flatMap((entry) => {
              const place = entry.insights.currentPlace ?? entry.insights.cities[0];
              return place ? [place] : [];
            }),
          placeKey,
        )
      : null;

    const next = {
      destinationName: country?.name ?? null,
      destinationCountryCode: country?.code ?? null,
      destinationCity: city,
      destinationInferred: country !== null,
    };
    if (
      next.destinationName !== memo.destinationName ||
      next.destinationCountryCode !== memo.destinationCountryCode ||
      next.destinationCity !== memo.destinationCity ||
      next.destinationInferred !== memo.destinationInferred
    ) {
      Object.assign(data, next);
    }
  }

  if (Object.keys(data).length > 0) await tx.memo.update({ where: { id: memoId }, data });
}
