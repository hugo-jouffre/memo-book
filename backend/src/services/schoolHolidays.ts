import type { AppContext } from "../context.js";
import { localDate, type LocalDate } from "./localCalendar.js";
import { findShippingCountry } from "./shippingCountries.js";

/**
 * Les vacances scolaires : **quelle zone**, et **quelles dates**.
 *
 * ## La zone
 *
 * La feuille « Notifications » laisse ouverte la source de la donnée. Celle
 * qu'on prend : **le code postal de l'adresse du profil**. Ses deux premiers
 * chiffres donnent le département, le département donne l'académie, et
 * l'académie la zone. Rien de plus à demander au voyageur — mais rien non plus
 * pour qui n'a pas encore donné d'adresse (elle n'est demandée qu'à la
 * commande, ou depuis le profil). Celui-là ne reçoit pas de notification de
 * vacances scolaires, plutôt qu'une notification calée sur la zone d'un autre.
 * Demander la zone ailleurs (onboarding, feuille des notifications) reste à
 * trancher — `docs/notifications.md` § Points ouverts.
 *
 * ## Les dates
 *
 * Celles du ministère, recopiées de data.education.gouv.fr (jeu
 * `fr-en-calendrier-scolaire`, Licence Ouverte) par la tâche quotidienne
 * `syncSchoolHolidays`. Le ministère y publie déjà l'année suivante : la table
 * a toujours au moins un an d'avance, sans que personne n'y pense.
 */

export type SchoolZone = "A" | "B" | "C" | "Corse";

/**
 * Le département → la zone, d'après la carte des académies en vigueur depuis
 * 2016. Une table et non une règle : il n'y en a pas.
 */
const ZONE_BY_DEPARTMENT: Record<string, SchoolZone> = Object.fromEntries(
  (
    [
      // Zone A — Besançon, Bordeaux, Clermont-Ferrand, Dijon, Grenoble,
      // Limoges, Lyon, Poitiers.
      ["A", "25 39 70 90 24 33 40 47 64 03 15 43 63 21 58 71 89 07 26 38 73 74 19 23 87 01 42 69 16 17 79 86"],
      // Zone B — Aix-Marseille, Amiens, Lille, Nancy-Metz, Nantes, Nice,
      // Normandie, Orléans-Tours, Reims, Rennes, Strasbourg.
      ["B", "04 05 13 84 02 60 80 59 62 54 55 57 88 44 49 53 72 85 06 83 14 27 50 61 76 18 28 36 37 41 45 08 10 51 52 22 29 35 56 67 68"],
      // Zone C — Créteil, Montpellier, Paris, Toulouse, Versailles.
      ["C", "77 93 94 11 30 34 48 66 75 09 12 31 32 46 65 81 82 78 91 92 95"],
    ] as const
  ).flatMap(([zone, departments]) => departments.split(" ").map((department) => [department, zone])),
);

/**
 * La zone d'une adresse, ou `null` quand on ne peut pas la dire : pas de code
 * postal, une adresse hors de France, l'outre-mer (ses calendriers sont à
 * part et ne sont pas repris), ou un code qui ne ressemble à rien.
 */
export function schoolZoneOf(
  postalCode: string | null | undefined,
  country: string | null | undefined,
): SchoolZone | null {
  // Un pays renseigné et qui n'est pas la France ferme la porte. Un pays vide
  // ne la ferme pas : les adresses saisies avant le champ pays en ont un nul.
  if (country && findShippingCountry(country)?.code !== "FR") return null;

  const digits = postalCode?.replace(/\s+/g, "") ?? "";
  if (!/^\d{5}$/.test(digits)) return null;

  const department = digits.slice(0, 2);
  if (department === "20") return "Corse";
  return ZONE_BY_DEPARTMENT[department] ?? null;
}

/** Une période de vacances, telle que le planificateur la lit. */
export interface SchoolHolidayPeriod {
  zone: SchoolZone;
  label: string;
  schoolYear: string;
  /** Le premier jour de vacances. */
  startsOn: LocalDate;
  /** Le jour de la reprise. */
  endsOn: LocalDate;
}

/** Une ligne du jeu de données du ministère, aux champs près qu'on lit. */
interface CalendarRecord {
  description?: string;
  start_date?: string;
  end_date?: string;
  zones?: string;
  annee_scolaire?: string;
}

const ZONE_BY_LABEL: Record<string, SchoolZone> = {
  "Zone A": "A",
  "Zone B": "B",
  "Zone C": "C",
  Corse: "Corse",
};

/**
 * Ce qu'on garde du calendrier : les vacances, pas les ponts.
 *
 * « Pont de l'Ascension » n'est pas une période de vacances — quatre jours au
 * plus — et la feuille parle de « chaque période de vacances scolaires ».
 * « Début des Vacances d'Été » est en revanche une vraie période, publiée
 * sous ce nom tant que sa fin n'est pas arrêtée.
 */
function isHolidayPeriod(description: string): boolean {
  return /vacances/i.test(description);
}

/**
 * Les dates du ministère sont des instants UTC calés sur **minuit à Paris** :
 * `2026-10-16T22:00:00+00:00` est le samedi 17 octobre. Le jour se lit donc
 * dans le fuseau de Paris, pas dans celui du serveur.
 */
function parisDay(instant: string): LocalDate {
  return localDate(new Date(instant), "Europe/Paris");
}

/**
 * Ramène les lignes du ministère aux périodes qu'on garde : une par zone,
 * libellé et année scolaire. Le jeu publie une ligne par **population**
 * (« Élèves », « Enseignants ») : on garde la première date de début et la
 * dernière date de reprise, celle des élèves.
 */
export function parseCalendar(records: CalendarRecord[]): SchoolHolidayPeriod[] {
  const periods = new Map<string, SchoolHolidayPeriod>();

  for (const record of records) {
    const zone = ZONE_BY_LABEL[record.zones ?? ""];
    const label = record.description?.trim();
    if (!zone || !label || !isHolidayPeriod(label)) continue;
    if (!record.start_date || !record.end_date || !record.annee_scolaire) continue;

    const startsOn = parisDay(record.start_date);
    const endsOn = parisDay(record.end_date);
    const key = `${zone}|${label}|${record.annee_scolaire}`;
    const existing = periods.get(key);

    periods.set(key, {
      zone,
      label,
      schoolYear: record.annee_scolaire,
      startsOn: existing && existing.startsOn < startsOn ? existing.startsOn : startsOn,
      endsOn: existing && existing.endsOn > endsOn ? existing.endsOn : endsOn,
    });
  }

  return [...periods.values()].sort((a, b) => a.startsOn.localeCompare(b.startsOn));
}

/** L'adresse du jeu de données, filtré sur la métropole et la Corse. */
export function calendarUrl(since: LocalDate): string {
  const where = `zones in ("Zone A","Zone B","Zone C","Corse") and end_date >= "${since}"`;
  const query = new URLSearchParams({
    select: "description,start_date,end_date,zones,annee_scolaire",
    where,
    order_by: "start_date",
    limit: "100",
  });
  return `https://data.education.gouv.fr/api/explore/v2.1/catalog/datasets/fr-en-calendrier-scolaire/records?${query}`;
}

export type CalendarFetcher = (url: string) => Promise<CalendarRecord[]>;

/** La lecture réelle, par `fetch`. Remplacée dans les tests. */
export const fetchCalendar: CalendarFetcher = async (url) => {
  const response = await fetch(url, { signal: AbortSignal.timeout(20_000) });
  if (!response.ok) {
    throw new Error(`data.education.gouv.fr a répondu ${response.status}.`);
  }
  const body = (await response.json()) as { results?: CalendarRecord[] };
  return body.results ?? [];
};

/**
 * Recopie le calendrier dans `school_holidays`. Rend le nombre de périodes
 * écrites.
 *
 * Seulement les périodes **qui ne sont pas finies** : le passé ne sert plus à
 * rien et il est déjà en base. Une période déjà connue est mise à jour — le
 * ministère corrige parfois une date. Une réponse vide ne vide rien : un site
 * en panne ne doit pas effacer l'année.
 */
export async function syncSchoolHolidays(
  context: Pick<AppContext, "prisma">,
  fetcher: CalendarFetcher = fetchCalendar,
  now: Date = new Date(),
): Promise<number> {
  const since = localDate(now, "Europe/Paris");
  const periods = parseCalendar(await fetcher(calendarUrl(since)));

  for (const period of periods) {
    const dates = {
      startsOn: new Date(`${period.startsOn}T00:00:00Z`),
      endsOn: new Date(`${period.endsOn}T00:00:00Z`),
    };
    await context.prisma.schoolHoliday.upsert({
      where: {
        zone_label_schoolYear: {
          zone: period.zone,
          label: period.label,
          schoolYear: period.schoolYear,
        },
      },
      create: { zone: period.zone, label: period.label, schoolYear: period.schoolYear, ...dates },
      update: dates,
    });
  }

  return periods.length;
}
