/**
 * Dates, heures, tailles et nombres écrits comme on les lit en France — pour
 * ce que le serveur écrit **à quelqu'un** : un e-mail, une page, un récit.
 *
 * Toujours à l'heure de Paris. Le serveur ne connaît pas le fuseau de celui
 * qui lit, et c'est celui de la quasi-totalité des voyageurs au moment où ils
 * ouvrent un e-mail ; les fichiers destinés à une machine, eux, gardent l'ISO
 * en UTC.
 */

const TIME_ZONE = "Europe/Paris";

const LONG_DATE = new Intl.DateTimeFormat("fr-FR", {
  day: "numeric",
  month: "long",
  year: "numeric",
  timeZone: TIME_ZONE,
});

const LONG_DATE_WITH_WEEKDAY = new Intl.DateTimeFormat("fr-FR", {
  weekday: "long",
  day: "numeric",
  month: "long",
  year: "numeric",
  timeZone: TIME_ZONE,
});

const TIME = new Intl.DateTimeFormat("fr-FR", {
  hour: "2-digit",
  minute: "2-digit",
  hourCycle: "h23",
  timeZone: TIME_ZONE,
});

const STAMP = new Intl.DateTimeFormat("fr-FR", {
  year: "numeric",
  month: "2-digit",
  day: "2-digit",
  hour: "2-digit",
  minute: "2-digit",
  hourCycle: "h23",
  timeZone: TIME_ZONE,
});

/** « 1 octobre » s'écrit « 1er octobre ». `Intl` ne le sait pas. */
function withFirst(text: string): string {
  return text.replace(/(^|\s)1(\s)/, "$11er$2");
}

/** « 8 octobre 2026 », ou « mercredi 8 octobre 2026 ». */
export function frenchDate(date: Date, options: { weekday?: boolean } = {}): string {
  return withFirst((options.weekday ? LONG_DATE_WITH_WEEKDAY : LONG_DATE).format(date));
}

/** « 14 h 30 ». */
export function frenchTime(date: Date): string {
  return TIME.format(date).replace(":", " h ");
}

/**
 * `2026-08-27_14-30` — un horodatage qui se trie, pour nommer un fichier.
 * Sans deux-points, que Windows refuse dans un nom de fichier.
 */
export function fileStamp(date: Date): string {
  const parts = Object.fromEntries(STAMP.formatToParts(date).map((part) => [part.type, part.value]));
  return `${parts.year}-${parts.month}-${parts.day}_${parts.hour}-${parts.minute}`;
}

/** `2026-10-01`, le jour à Paris. */
export function fileDay(date: Date): string {
  return fileStamp(date).slice(0, 10);
}

/** « 1 voyage », « 3 voyages » — et « 0 voyage » : le français met le zéro au singulier. */
export function frenchCount(count: number, singular: string, plural: string): string {
  return `${count.toLocaleString("fr-FR")} ${count > 1 ? plural : singular}`;
}

/** « 850 Ko », « 412 Mo », « 1,2 Go » — en puissances de dix, comme iOS et macOS. */
export function frenchSize(bytes: number): string {
  if (bytes < 1_000_000) return `${Math.max(1, Math.round(bytes / 1_000))} Ko`;
  if (bytes < 1_000_000_000) return `${Math.round(bytes / 1_000_000)} Mo`;
  return `${(bytes / 1_000_000_000).toLocaleString("fr-FR", { maximumFractionDigits: 1 })} Go`;
}
