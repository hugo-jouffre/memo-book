import type { EntryKind, Status, TripStage, TripTransport } from "@prisma/client";
import { parseInsights, type EntryInsights, type TransportKind } from "./redaction.js";

/**
 * Les statistiques du profil — la feuille « Statistiques », réservée aux
 * abonnés.
 *
 * **Rien n'est stocké : tout s'additionne à la lecture.** Chaque souvenir
 * rédigé porte son relevé (`Entry.insights`, écrit par l'agent de rédaction),
 * et cette passe les somme sur tous les voyages du compte. Un compteur tenu à
 * l'écriture aurait été plus rapide d'une milliseconde et faux à la première
 * suppression de souvenir ; ici, une correction ou une relance de la rédaction
 * se voit à la lecture suivante, sans rien à décompter.
 *
 * **Ce que le voyage déclare sert de plancher.** Un carnet dont aucun souvenir
 * n'a encore été rédigé montre déjà son pays et sa ville de destination, les
 * transports posés entre ses étapes et la distance de sa fiche : le relevé de
 * la rédaction **complète** ces déclarations, il ne les remplace pas. Une
 * carte de chiffres à zéro sur un voyage en cours se lirait comme une panne.
 */

export interface MemoForStatistics {
  id: string;
  stage: TripStage;
  startDate: Date | null;
  endDate: Date | null;
  dayCount: number | null;
  destinationCountryCode: string | null;
  destinationCity: string | null;
  distanceKilometres: number | null;
  steps: { destinationCountryCode: string | null; transport: TripTransport | null }[];
  entries: {
    kind: EntryKind;
    redactionStatus: Status;
    capturedAt: Date;
    insights: unknown;
  }[];
}

/** Les cinq chiffres qui se lisent au global comme sur le voyage en cours. */
export interface TravelFigures {
  countries: number;
  regions: number;
  cities: number;
  encounters: number;
  distanceKilometres: number;
}

export interface TransportUsage {
  kind: TransportKind;
  /** Le nombre de trajets, ou `null` quand aucun souvenir ne l'a compté. */
  count: number | null;
}

export interface CurrentTripStatistics {
  id: string;
  startDate: string | null;
  endDate: string | null;
  /** « Rome » — la dernière ville où un souvenir situe le voyageur. */
  currentPlace: string | null;
  /** Le nombre de jours du voyage, pour « 2 jours validés sur 21 ». */
  dayCount: number;
  /** Les journées qui ont au moins un souvenir rédigé. */
  validatedDays: number;
  figures: TravelFigures;
  /** Les vocaux enregistrés sur ce voyage. */
  recordings: number;
  transports: TransportUsage[];
}

export interface TravelStatistics {
  tripCount: number;
  overall: TravelFigures;
  currentTrip: CurrentTripStatistics | null;
  /**
   * Combien de souvenirs attendent encore leur relevé. Tant qu'il y en a,
   * l'app relit la feuille à intervalle court : c'est ce qui fait apparaître
   * un chiffre « en instantané » sans tenir de connexion ouverte.
   */
  pendingDetections: number;
  updatedAt: string;
}

/** Un ensemble insensible à la casse et aux espaces, qui garde la première graphie. */
class LabelSet {
  private readonly labels = new Map<string, string>();

  add(label: string | null | undefined): void {
    const trimmed = label?.trim();
    if (!trimmed) return;
    const key = trimmed.toLowerCase();
    if (!this.labels.has(key)) this.labels.set(key, trimmed);
  }

  addAll(labels: Iterable<string>): void {
    for (const label of labels) this.add(label);
  }

  get size(): number {
    return this.labels.size;
  }

  values(): string[] {
    return [...this.labels.values()];
  }
}

/** Ce qu'un voyage apporte, avant addition. */
interface MemoTally {
  countries: LabelSet;
  regions: LabelSet;
  cities: LabelSet;
  encounters: number;
  distanceKilometres: number;
  recordings: number;
  transports: Map<TransportKind, number | null>;
  currentPlace: string | null;
  validatedDays: number;
  pending: number;
}

const MILLISECONDS_PER_DAY = 86_400_000;

function dayKey(date: Date): string {
  return date.toISOString().slice(0, 10);
}

/**
 * Le nombre de jours d'un voyage : celui de sa fiche, sinon l'écart entre ses
 * deux dates, bornes comprises — un voyage du 10 au 12 dure trois jours.
 */
export function tripDayCount(memo: {
  dayCount: number | null;
  startDate: Date | null;
  endDate: Date | null;
}): number {
  if (memo.dayCount && memo.dayCount > 0) return memo.dayCount;
  if (!memo.startDate || !memo.endDate) return 0;
  const span = memo.endDate.getTime() - memo.startDate.getTime();
  return Math.max(0, Math.floor(span / MILLISECONDS_PER_DAY) + 1);
}

/**
 * Deux comptes de trajets s'additionnent ; un compte inconnu (`null`) ne
 * l'emporte jamais sur un compte connu, et deux inconnus restent inconnus —
 * « la semaine en scooter » deux fois reste « scooter », sans chiffre.
 */
function addTransport(
  tally: Map<TransportKind, number | null>,
  kind: TransportKind,
  count: number | null,
): void {
  const known = tally.get(kind);
  if (known === undefined) {
    tally.set(kind, count);
  } else if (count !== null) {
    tally.set(kind, (known ?? 0) + count);
  }
}

function tallyMemo(memo: MemoForStatistics): MemoTally {
  const tally: MemoTally = {
    countries: new LabelSet(),
    regions: new LabelSet(),
    cities: new LabelSet(),
    encounters: 0,
    distanceKilometres: 0,
    recordings: 0,
    transports: new Map(),
    currentPlace: null,
    validatedDays: 0,
    pending: 0,
  };

  // Le plancher : ce que le voyage déclare de lui-même.
  tally.countries.add(memo.destinationCountryCode?.toUpperCase());
  for (const step of memo.steps) tally.countries.add(step.destinationCountryCode?.toUpperCase());
  tally.cities.add(memo.destinationCity);

  const validatedDayKeys = new Set<string>();
  let latestPlaceAt = -Infinity;
  let detectedDistance = 0;
  let hasDetectedTransport = false;

  for (const entry of memo.entries) {
    if (entry.kind === "audio") tally.recordings += 1;
    if (entry.kind === "photo") continue;

    if (entry.redactionStatus === "pending" || entry.redactionStatus === "processing") {
      tally.pending += 1;
    }
    if (entry.redactionStatus === "ready") validatedDayKeys.add(dayKey(entry.capturedAt));

    if (entry.insights === null || entry.insights === undefined) continue;
    const insights: EntryInsights = parseInsights(entry.insights);

    tally.countries.addAll(insights.countries.map((country) => country.code));
    tally.regions.addAll(insights.regions);
    tally.cities.addAll(insights.cities);
    tally.encounters += insights.peopleMet;
    detectedDistance += insights.distanceKilometres ?? 0;

    for (const transport of insights.transports) {
      hasDetectedTransport = true;
      addTransport(tally.transports, transport.kind, transport.count);
    }

    // Le souvenir le plus récent qui situe le voyageur l'emporte : c'est là
    // qu'il est « actuellement ».
    const at = entry.capturedAt.getTime();
    if (insights.currentPlace && at > latestPlaceAt) {
      latestPlaceAt = at;
      tally.currentPlace = insights.currentPlace;
    }
  }

  // Les kilomètres relevés priment sur ceux de la fiche ; la fiche ne sert
  // que tant que rien n'a été relevé. Les deux ne s'additionnent pas — ce
  // serait compter deux fois le même trajet.
  tally.distanceKilometres =
    detectedDistance > 0 ? detectedDistance : (memo.distanceKilometres ?? 0);

  // Même règle pour les transports : ce que les souvenirs racontent, sinon ce
  // que les étapes déclarent.
  if (!hasDetectedTransport) {
    for (const step of memo.steps) {
      if (step.transport) addTransport(tally.transports, step.transport, 1);
    }
  }

  tally.currentPlace ??= memo.destinationCity;
  tally.validatedDays = validatedDayKeys.size;

  return tally;
}

/**
 * Le voyage « en cours » est le plus récemment commencé de ceux qui le sont :
 * la même règle que l'accueil et que la carte de chiffres du profil.
 */
function pickCurrent(memos: MemoForStatistics[]): MemoForStatistics | undefined {
  return memos
    .filter((memo) => memo.stage === "ongoing")
    .sort((a, b) => (b.startDate?.getTime() ?? 0) - (a.startDate?.getTime() ?? 0))[0];
}

function roundKilometres(value: number): number {
  return Math.round(value);
}

function serializeTransports(tally: Map<TransportKind, number | null>): TransportUsage[] {
  // Les plus fréquents d'abord ; les non comptés ferment la marche, comme
  // « scooter » à la fin de la ligne de la maquette.
  return [...tally.entries()]
    .map(([kind, count]) => ({ kind, count }))
    .sort((a, b) => (b.count ?? -1) - (a.count ?? -1));
}

/**
 * Additionne les voyages d'un compte. Pure : c'est ce qui la rend testable
 * sans base, et ce qui garantit que la route ne fait qu'une requête.
 */
export function aggregateTravelStatistics(
  memos: MemoForStatistics[],
  now: Date = new Date(),
): TravelStatistics {
  const tallies = new Map(memos.map((memo) => [memo.id, tallyMemo(memo)]));

  const countries = new LabelSet();
  const regions = new LabelSet();
  const cities = new LabelSet();
  let encounters = 0;
  let distance = 0;
  let pending = 0;

  for (const tally of tallies.values()) {
    countries.addAll(tally.countries.values());
    regions.addAll(tally.regions.values());
    cities.addAll(tally.cities.values());
    encounters += tally.encounters;
    distance += tally.distanceKilometres;
    pending += tally.pending;
  }

  const current = pickCurrent(memos);
  const currentTally = current ? tallies.get(current.id) : undefined;

  return {
    tripCount: memos.length,
    overall: {
      countries: countries.size,
      regions: regions.size,
      cities: cities.size,
      encounters,
      distanceKilometres: roundKilometres(distance),
    },
    currentTrip:
      current && currentTally
        ? {
            id: current.id,
            startDate: current.startDate?.toISOString() ?? null,
            endDate: current.endDate?.toISOString() ?? null,
            currentPlace: currentTally.currentPlace,
            dayCount: tripDayCount(current),
            validatedDays: currentTally.validatedDays,
            figures: {
              countries: currentTally.countries.size,
              regions: currentTally.regions.size,
              cities: currentTally.cities.size,
              encounters: currentTally.encounters,
              distanceKilometres: roundKilometres(currentTally.distanceKilometres),
            },
            recordings: currentTally.recordings,
            transports: serializeTransports(currentTally.transports),
          }
        : null,
    pendingDetections: pending,
    updatedAt: now.toISOString(),
  };
}

/**
 * Ce que la route lit, et rien de plus : les colonnes que l'addition regarde.
 * Les textes des souvenirs — transcription, rédaction, correction — n'en font
 * pas partie, et c'est ce qui garde la requête légère sur un compte qui a
 * raconté trois cents vocaux.
 */
export const memoStatisticsSelect = {
  id: true,
  stage: true,
  startDate: true,
  endDate: true,
  dayCount: true,
  destinationCountryCode: true,
  destinationCity: true,
  distanceKilometres: true,
  steps: { select: { destinationCountryCode: true, transport: true } },
  entries: {
    select: { kind: true, redactionStatus: true, capturedAt: true, insights: true },
  },
} as const;
