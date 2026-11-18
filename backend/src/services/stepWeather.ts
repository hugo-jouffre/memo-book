/**
 * **Le temps qu'il faisait à une étape** : son icône et sa température (T263,
 * Hugo — « chaque étape devrait porter sa date et sa température, avec une
 * petite icône météo »).
 *
 * Une étape réunit plusieurs souvenirs, et c'est la rédaction qui relève le
 * temps, souvenir par souvenir. L'étape n'a donc **rien à stocker pour son
 * icône** : elle la déduit des siens, exactement comme la mise en page du
 * carnet le fait déjà pour un jour (`services/structuring.ts`). Une seconde
 * vérité de moins à tenir d'accord.
 *
 * La température, elle, a deux origines, et leur ordre est le cœur du sujet :
 *
 * 1. **celle qu'on a dite** (`entries.temperatureC`) — un souvenir. Elle
 *    l'emporte toujours, même si elle est fausse : le carnet raconte ce qu'on
 *    a vécu, pas ce qu'un service a mesuré ;
 * 2. **celle qu'on a cherchée** (`memo_steps.temperatureC`), faute de l'avoir
 *    entendue (`services/weatherLookup.ts`).
 *
 * Aucune des deux : l'étape n'affiche pas de température, et c'est très bien.
 */

/** Les cinq temps que la rédaction sait relever, et que le gabarit sait dessiner. */
export const WEATHER_KEYS = ["sun", "sun-wind", "cloud", "rain", "snow"] as const;
export type WeatherKey = (typeof WEATHER_KEYS)[number];

export function isWeatherKey(value: unknown): value is WeatherKey {
  return typeof value === "string" && (WEATHER_KEYS as readonly string[]).includes(value);
}

/** Ce qu'on lit d'une étape pour en tirer son temps. */
export interface StepWeatherInput {
  temperatureC?: number | null;
  entries?: { weatherKey?: string | null; temperatureC?: number | null }[];
}

export interface StepWeather {
  /** `null` quand aucun souvenir de l'étape n'a dit le temps qu'il faisait. */
  weatherKey: WeatherKey | null;
  /** En degrés Celsius entiers, dite d'abord, cherchée ensuite. */
  temperatureC: number | null;
  /**
   * D'où vient la température. L'app ne l'affiche pas — mais on ne met pas sur
   * le même plan ce qu'un voyageur a vécu et ce qu'un service a mesuré, et
   * c'est le genre de distinction qu'on regrette de ne pas avoir gardée.
   */
  temperatureSource: "told" | "looked-up" | null;
}

/**
 * **Le premier souvenir qui l'a dit l'emporte**, et non le plus fréquent : les
 * souvenirs d'une étape sont dans l'ordre du récit, et c'est le premier qui
 * plante le décor. Même règle que la mise en page du carnet.
 */
export function stepWeatherOf(step: StepWeatherInput): StepWeather {
  const entries = step.entries ?? [];

  const told = entries.find((entry) => entry.weatherKey);
  const weatherKey = isWeatherKey(told?.weatherKey) ? told.weatherKey : null;

  const saidTemperature = entries.find(
    (entry) => typeof entry.temperatureC === "number" && Number.isFinite(entry.temperatureC),
  )?.temperatureC;

  if (typeof saidTemperature === "number") {
    return { weatherKey, temperatureC: Math.round(saidTemperature), temperatureSource: "told" };
  }

  if (typeof step.temperatureC === "number" && Number.isFinite(step.temperatureC)) {
    return {
      weatherKey,
      temperatureC: Math.round(step.temperatureC),
      temperatureSource: "looked-up",
    };
  }

  return { weatherKey, temperatureC: null, temperatureSource: null };
}

/**
 * Le lieu qu'on donne au service météo pour cette étape, ou `null` s'il n'y a
 * rien d'assez précis à lui donner.
 *
 * `destinationName` d'abord — « Cebu » —, et le code pays avec lui quand on
 * l'a : « Cebu, PH » lève l'ambiguïté des homonymes, et il y en a beaucoup.
 * `placeName` est un repli : c'est un libellé libre, parfois un quartier,
 * parfois une phrase.
 */
export function lookupPlaceOf(step: {
  destinationName?: string | null;
  destinationCountryCode?: string | null;
  placeName?: string | null;
}): string | null {
  const ville = step.destinationName?.trim() || step.placeName?.trim();
  if (!ville) return null;
  const pays = step.destinationCountryCode?.trim();
  return pays ? `${ville}, ${pays}` : ville;
}

/**
 * Le jour qu'on interroge : le début de l'étape, sinon sa fin.
 *
 * Une étape qui dure n'a qu'une température affichée, et c'est celle du jour
 * où elle commence — la moyenne de la semaine ne serait la température
 * d'aucun jour vécu.
 */
export function lookupDayOf(step: { startDate?: Date | null; endDate?: Date | null }): Date | null {
  return step.startDate ?? step.endDate ?? null;
}
