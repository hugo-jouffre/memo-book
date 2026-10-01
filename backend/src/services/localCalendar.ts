/**
 * Les jours **du voyageur**, et non ceux du serveur.
 *
 * Toutes les règles des notifications parlent en jours : « J+3 », « le jour
 * de la fin du voyage », « J-7 avant les vacances ». Or un jour commence à
 * minuit **chez quelqu'un** : le serveur tourne en UTC, et le 15 à Tokyo
 * commence quand il est encore le 14 à Paris. On ramène donc chaque instant au
 * calendrier du fuseau du téléphone (`accounts.timeZone`), et on compare des
 * dates `AAAA-MM-JJ` — qui, elles, ne connaissent ni heure ni fuseau.
 */

/** Le fuseau qu'on suppose tant que le téléphone ne nous a rien dit. */
export const DEFAULT_TIME_ZONE = "Europe/Paris";

/** Une date de calendrier, `AAAA-MM-JJ`. */
export type LocalDate = string;

const DAY_MS = 24 * 60 * 60 * 1000;

/** Un fuseau qu'`Intl` connaît — on ne garde pas « Mars/Olympus ». */
export function isValidTimeZone(timeZone: string): boolean {
  try {
    new Intl.DateTimeFormat("en-US", { timeZone });
    return true;
  } catch {
    return false;
  }
}

function parts(instant: Date, timeZone: string): Record<string, string> {
  const formatter = new Intl.DateTimeFormat("en-CA", {
    timeZone,
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
    hour: "2-digit",
    hourCycle: "h23",
  });
  return Object.fromEntries(formatter.formatToParts(instant).map((part) => [part.type, part.value]));
}

/** Le jour qu'il est, chez quelqu'un, à cet instant. */
export function localDate(instant: Date, timeZone: string = DEFAULT_TIME_ZONE): LocalDate {
  const { year, month, day } = parts(instant, timeZone);
  return `${year}-${month}-${day}`;
}

/** L'heure qu'il est, chez quelqu'un, à cet instant — de 0 à 23. */
export function localHour(instant: Date, timeZone: string = DEFAULT_TIME_ZONE): number {
  return Number(parts(instant, timeZone).hour);
}

/**
 * Une colonne `DATE` (date de naissance, vacances scolaires) telle que Prisma
 * la rend : minuit UTC du jour. On lit ses chiffres UTC, sans fuseau — une
 * date de naissance ne change pas quand on traverse un océan.
 */
export function calendarDate(column: Date): LocalDate {
  return column.toISOString().slice(0, 10);
}

/** Le jour, `days` plus tard (ou plus tôt, en négatif). */
export function addDays(date: LocalDate, days: number): LocalDate {
  return new Date(Date.parse(`${date}T00:00:00Z`) + days * DAY_MS).toISOString().slice(0, 10);
}

/** Combien de jours de `from` à `to` : 1 du 14 au 15, -1 du 15 au 14. */
export function daysBetween(from: LocalDate, to: LocalDate): number {
  return Math.round((Date.parse(`${to}T00:00:00Z`) - Date.parse(`${from}T00:00:00Z`)) / DAY_MS);
}

/**
 * Le même jour de l'année, une autre année. Un 29 février tombe le 28 les
 * années qui n'en ont pas : un anniversaire ne saute pas trois ans sur quatre.
 */
export function sameDayInYear(date: LocalDate, year: number): LocalDate {
  const [, month, day] = date.split("-").map(Number) as [number, number, number];
  const lastDay = new Date(Date.UTC(year, month, 0)).getUTCDate();
  const clamped = Math.min(day, lastDay);
  return `${year}-${String(month).padStart(2, "0")}-${String(clamped).padStart(2, "0")}`;
}

/** L'année d'une date. */
export function yearOf(date: LocalDate): number {
  return Number(date.slice(0, 4));
}
