import type { MemoStep, Prisma, PrismaClient, TripTransport } from "@prisma/client";
import type { AppContext } from "../context.js";
import { promptAfterStep } from "./conversationCopy.js";
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
  /**
   * **Ce récit prolonge le précédent** : les deux ne font qu'une étape — ce
   * que la rédaction a compris (`continuesPreviousStep`), sauf si le voyageur
   * les a séparés depuis la carte (`separatedByTraveller`), qui passe devant.
   */
  continuesPrevious: boolean;
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
 * Ce qui rattache une photo à une étape, lu dans le fil.
 *
 * - `stepOf` : l'étape que le voyageur a choisie — il a ouvert le fil depuis
 *   la carte d'une étape, et l'app a envoyé son `stepId` avec les photos.
 * - `illustrates` : le récit que les photos illustrent — celui dont MEMO
 *   venait de demander les photos (`payload.forEntryId` du message de photos).
 */
export interface StepPins {
  stepOf: Map<string, string>;
  illustrates: Map<string, string>;
}

/**
 * Découpe les souvenirs en étapes : **un récit, une étape** (Hugo,
 * 12/10/2026 — « c'est enregistré, ton carnet compte une étape de plus »
 * doit se voir sur l'accueil du voyage) — **sauf quand un récit en prolonge
 * un autre** (Hugo, 28/10/2026 : « 1 message n'est pas toujours égal à
 * 1 étape »).
 *
 * C'est la règle du fil : la N-ième fiche « Retranscription étape N » est
 * l'étape N, MEMO compose « la page de cette étape » à chaque récit validé,
 * et le dos de couverture compte ces étapes. Le découpage par lieu successif
 * d'avant (T227) rangeait deux récits du même lieu dans une seule carte :
 * le chat annonçait une étape de plus, l'accueil n'en montrait aucune.
 *
 * - Un **récit** — un vocal, un texte — ouvre sa propre étape, dans l'ordre
 *   où il a été vécu (`capturedAt`). Un `stepId` envoyé avec lui ne le range
 *   pas ailleurs : ce n'était, le plus souvent, que l'étape où le voyage en
 *   était.
 * - …**sauf s'il prolonge le précédent** (``FactEntry/continuesPrevious``) :
 *   il rejoint alors son étape au lieu d'en ouvrir une. C'est l'écrivain qui
 *   le dit, à la rédaction — lui seul lit les deux récits. « Et sinon, le
 *   soir, on est retournés au même bar » n'est pas une étape de plus.
 *   Le voyageur peut le défaire depuis la carte, et sa main l'emporte.
 *   ⚠️ Un récit qui prolonge **le premier de la liste** ne prolonge rien : il
 *   ouvre l'étape, faute de précédent.
 * - Une **photo** rejoint l'étape choisie par le voyageur s'il y en a une,
 *   sinon le récit qu'elle illustre, sinon le dernier récit vécu avant elle
 *   (le premier, si elle les précède tous). Sans aucun récit, les photos
 *   font une seule étape, sans nom — c'est elle qui porte la croix de
 *   l'accueil (T235).
 */
export function groupIntoSteps(
  entries: FactEntry[],
  pins: StepPins = { stepOf: new Map(), illustrates: new Map() },
): StepGroup[] {
  const stories: StepGroup[] = [];
  const storyOf = new Map<string, StepGroup>();
  const photos: FactEntry[] = [];

  for (const entry of entries) {
    if (entry.kind === "photo") {
      photos.push(entry);
      continue;
    }
    // Prolonger le précédent, c'est le rejoindre : son groupe grandit, et
    // aucune étape ne s'ouvre. Le lieu reste celui du récit qui a ouvert
    // l'étape — c'est lui qui la nomme.
    const previous = stories[stories.length - 1];
    if (entry.continuesPrevious && previous) {
      previous.entries.push(entry);
      storyOf.set(entry.id, previous);
      continue;
    }

    const group: StepGroup = { place: placeOf(entry), entries: [entry], stepId: null, pinned: false };
    stories.push(group);
    storyOf.set(entry.id, group);
  }

  // Une étape choisie qui n'a plus son récit (effacé) garde ses photos.
  const pinnedOnly = new Map<string, StepGroup>();
  const loose: FactEntry[] = [];

  for (const photo of photos) {
    const pin = pins.stepOf.get(photo.id);
    if (pin) {
      const story = stories.find((group) => group.entries[0]?.stepId === pin);
      if (story) {
        story.entries.push(photo);
      } else {
        const group = pinnedOnly.get(pin) ?? { place: null, entries: [], stepId: pin, pinned: true };
        group.entries.push(photo);
        pinnedOnly.set(pin, group);
      }
      continue;
    }

    const illustrated = pins.illustrates.get(photo.id);
    const target =
      (illustrated ? storyOf.get(illustrated) : undefined) ??
      stories.findLast((group) => group.entries[0]!.capturedAt.getTime() <= photo.capturedAt.getTime()) ??
      stories[0];
    if (target) target.entries.push(photo);
    else loose.push(photo);
  }

  const groups = [...stories, ...pinnedOnly.values()];
  if (loose.length > 0) groups.push({ place: null, entries: loose, stepId: null, pinned: false });
  return groups;
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
          prompt: true,
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
          continuesPreviousStep: true,
          separatedByTraveller: true,
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
        // La main l'emporte sur la machine, comme partout ici.
        continuesPrevious: row.continuesPreviousStep && !row.separatedByTraveller,
      }));

      const before = [...memo.steps].sort((a, b) => b.number - a.number)[0] ?? null;
      const steps = await writeSteps(tx, memoId, memo.steps, entries);
      await writeFigures(tx, memoId, memo, entries, now);
      await writePrompt(tx, memoId, memo.prompt, before, steps.at(-1) ?? null);
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

/**
 * Ce que le fil dit des photos : l'étape choisie depuis sa carte, et le récit
 * que MEMO venait d'illustrer — voir ``StepPins``. Seules les photos sont
 * rattachées ainsi : un récit fait toujours sa propre étape.
 */
async function pinnedSteps(tx: Tx, memoId: string, steps: ExistingStep[]): Promise<StepPins> {
  const known = new Set(steps.map((step) => step.id));
  const messages = await tx.chatMessage.findMany({
    where: { memoId, author: "traveller", kind: "photos" },
    select: { stepId: true, entryId: true, payload: true },
  });

  const pins: StepPins = { stepOf: new Map(), illustrates: new Map() };
  for (const message of messages) {
    // Un message de photos en porte plusieurs (`payload.entryIds`).
    const payload = message.payload as { entryIds?: unknown; forEntryId?: unknown } | null;
    const ids = new Set<string>();
    if (message.entryId) ids.add(message.entryId);
    if (payload && Array.isArray(payload.entryIds)) {
      for (const id of payload.entryIds) if (typeof id === "string") ids.add(id);
    }
    const forEntryId = typeof payload?.forEntryId === "string" ? payload.forEntryId : null;
    for (const id of ids) {
      if (message.stepId && known.has(message.stepId)) pins.stepOf.set(id, message.stepId);
      if (forEntryId) pins.illustrates.set(id, forEntryId);
    }
  }
  return pins;
}

/** Une étape telle qu'elle est écrite : de quoi suivre la dernière. */
interface WrittenStep {
  id: string;
  placeName: string | null;
}

async function writeSteps(
  tx: Tx,
  memoId: string,
  existing: ExistingStep[],
  entries: FactEntry[],
): Promise<WrittenStep[]> {
  const byId = new Map(existing.map((step) => [step.id, step]));
  const groups = groupIntoSteps(entries, await pinnedSteps(tx, memoId, existing));

  // --- Chaque groupe reprend une étape existante, si possible ---------------
  //
  // Celle de son récit d'abord, puis celle où la plupart de ses photos sont
  // déjà rangées, puis une étape libre du même lieu. Garder l'identifiant
  // garde ce qui y est attaché : la validation (« Valider cette étape »), la
  // photo, les messages du fil. Les récits passent dans l'ordre du voyage :
  // deux récits qu'une ancienne étape réunissait, c'est le premier qui la
  // garde, l'autre en ouvre une.
  const claimed = new Set(groups.filter((group) => group.pinned).map((group) => group.stepId!));
  const kept: StepGroup[] = groups.filter((group) => group.pinned);

  for (const group of groups) {
    if (group.pinned) continue;
    const free = (id: string | null | undefined): id is string => Boolean(id) && byId.has(id!) && !claimed.has(id!);

    const own = group.entries[0]?.kind === "photo" ? null : group.entries[0]?.stepId;
    const vote = mostCommon(
      group.entries.flatMap((entry) => (free(entry.stepId) ? [entry.stepId] : [])),
      (id) => id,
    );

    if (free(own)) {
      group.stepId = own;
    } else if (vote) {
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

  const written: WrittenStep[] = [];
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
    written.push({ id: group.stepId!, placeName: fields.placeName });
  }
  return written;
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

/**
 * **La relance de l'accueil du voyage suit la dernière étape racontée**
 * (Hugo, 12/10/2026 — « le chat doit mieux alimenter le texte d'accroche »).
 *
 * Elle n'était écrite qu'au tour de MEMO, et la plupart des tours sont
 * maintenant écrits par le code, avant que la rédaction ait lu le lieu : la
 * relance restait sur l'étape d'avant, ou vide. Elle se réécrit donc ici dès
 * qu'une étape **nouvelle** devient la dernière — ou que la dernière change de
 * lieu — et que ce lieu est connu. Le reste du temps, elle garde ce que MEMO a
 * écrit entre deux étapes.
 */
async function writePrompt(
  tx: Tx,
  memoId: string,
  current: string | null,
  before: Pick<MemoStep, "id" | "placeName"> | null,
  latest: WrittenStep | null,
) {
  if (!latest) return;
  const moved = before?.id !== latest.id || before.placeName !== latest.placeName;
  // Sans lieu, la nouvelle étape n'apprend rien de plus que la relance que
  // MEMO vient d'écrire en lisant le récit : elle ne remplace qu'une relance
  // absente.
  if (current && (!moved || !latest.placeName)) return;
  const prompt = promptAfterStep(latest.placeName);
  if (prompt !== current) await tx.memo.update({ where: { id: memoId }, data: { prompt } });
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
