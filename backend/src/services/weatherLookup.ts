import type { AppContext } from "../context.js";
import type { Env } from "../env.js";
import { lookupDayOf, lookupPlaceOf } from "./stepWeather.js";

/**
 * **La température d'un lieu à une date**, quand le voyageur ne l'a pas dite
 * (T263, Hugo : « si la température n'est pas dite il faut que tu la trouves
 * toi-même »).
 *
 * ## Pourquoi Visual Crossing
 *
 * Une question de licence, pas de goût. Le palier gratuit d'Open-Meteo est
 * réservé à l'usage **non commercial**, et son premier palier payant exclut
 * justement l'API historique. Celui de Visual Crossing autorise le commercial,
 * avec 30 000 relevés par mois — nous en demandons **un par étape, une fois**,
 * puisqu'une température passée ne change plus. Un voyage de vingt étapes,
 * c'est vingt relevés.
 *
 * Et il **géocode le nom du lieu lui-même** (`/timeline/Tokyo,Japan/2026-08-02`).
 * C'est décisif : aucune coordonnée n'existe en base — une étape a un nom, pas
 * un point. Sans ça, il aurait fallu brancher un géocodeur en plus.
 *
 * ## Trois règles
 *
 * 1. **Jamais bloquant.** Service muet, lent, hors quota, lieu introuvable :
 *    on rend `null`, l'étape n'affiche pas de température, et l'app ne sait
 *    même pas qu'on a essayé. Même parti pris que les rues d'OpenStreetMap
 *    (`services/osmCity.ts`) — une carte sobre plutôt qu'un carnet qui
 *    n'arrive jamais.
 * 2. **Une fois par étape.** L'appelant retient la réponse *et* le fait
 *    d'avoir cherché (`memo_steps.temperatureLookedUpAt`) : sans ça, une
 *    étape dont le lieu est introuvable rappellerait le service à chaque
 *    lecture du voyage.
 * 3. **Sans clé, rien.** Pas de `VISUAL_CROSSING_API_KEY`, pas d'appel. Les
 *    températures dites dans les vocaux continuent de s'afficher.
 *
 * ⚠️ **Ce n'est pas la météo du carnet.** L'icône qui s'imprime vient de ce
 * que le voyageur a raconté (`entries.weatherKey`, T264) et ne se cherche
 * nulle part. Ici on ne complète qu'un chiffre, et seulement s'il manque.
 */

export interface WeatherLookupDeps {
  env: Pick<Env, "VISUAL_CROSSING_URL" | "VISUAL_CROSSING_API_KEY">;
  fetcher?: typeof fetch;
  warn?: (message: string, error?: unknown) => void;
}

/** Au-delà, on renonce : personne n'attend une température. */
const TIMEOUT_MS = 8_000;

/**
 * Les bornes du plausible, en degrés Celsius. Au-delà, on préfère ne rien
 * afficher qu'un chiffre absurde : un service qui change d'unité sans le dire
 * est plus probable qu'un −90 vécu par un voyageur.
 */
const MIN_C = -60;
const MAX_C = 60;

/** `2026-08-02`, le format que l'API attend. */
export function isoDay(date: Date): string {
  return date.toISOString().slice(0, 10);
}

/**
 * La température moyenne de ce lieu ce jour-là, arrondie, ou `null`.
 *
 * `place` est un nom en clair — « Tokyo, Japon », « Cebu ». C'est le service
 * qui le place sur la carte, et il le dit dans `resolvedAddress` ; on ne
 * vérifie pas qu'il a vu juste, parce qu'on n'a rien pour comparer.
 */
export async function lookUpTemperature(
  deps: WeatherLookupDeps,
  place: string,
  day: Date,
): Promise<number | null> {
  const key = deps.env.VISUAL_CROSSING_API_KEY;
  if (!key) return null;

  const lieu = place.trim();
  if (!lieu) return null;

  const url = new URL(
    `${deps.env.VISUAL_CROSSING_URL}/${encodeURIComponent(lieu)}/${isoDay(day)}`,
  );
  url.searchParams.set("key", key);
  url.searchParams.set("unitGroup", "metric");
  // Seulement la journée, seulement la moyenne : la réponse complète porte
  // heure par heure et pèse cent fois plus pour un chiffre.
  url.searchParams.set("include", "days");
  url.searchParams.set("elements", "temp");
  url.searchParams.set("contentType", "json");

  const fetcher = deps.fetcher ?? fetch;
  const signal = AbortSignal.timeout(TIMEOUT_MS);

  let reponse: Response;
  try {
    reponse = await fetcher(url, { signal });
  } catch (cause) {
    deps.warn?.("Température non relevée : le service n'a pas répondu", cause);
    return null;
  }

  if (!reponse.ok) {
    // 400 = lieu introuvable, 429 = quota. Ni l'un ni l'autre n'est une
    // panne de notre côté, et l'appelant retiendra qu'on a cherché.
    deps.warn?.(`Température non relevée : le service a répondu ${reponse.status}`);
    return null;
  }

  let corps: unknown;
  try {
    corps = await reponse.json();
  } catch (cause) {
    deps.warn?.("Température non relevée : réponse illisible", cause);
    return null;
  }

  const jours = (corps as { days?: unknown })?.days;
  if (!Array.isArray(jours) || jours.length === 0) return null;
  const temp = (jours[0] as { temp?: unknown })?.temp;
  if (typeof temp !== "number" || !Number.isFinite(temp)) return null;

  const arrondie = Math.round(temp);
  if (arrondie < MIN_C || arrondie > MAX_C) {
    deps.warn?.(`Température écartée, hors du plausible : ${arrondie} °C`);
    return null;
  }
  return arrondie;
}

// ---------------------------------------------------------------------------
// Ce qui va chercher, et ce qui retient
// ---------------------------------------------------------------------------

/**
 * **Complète les températures manquantes d'un voyage**, une étape à la fois.
 *
 * Appelée après le recalcul des étapes, depuis un **travail de fond** et
 * jamais depuis une requête : un appel réseau de huit secondes n'a rien à
 * faire sur le chemin de quelqu'un qui attend. Et jamais **dans** la
 * transaction de `refreshTripFacts`, dont le délai est de vingt secondes —
 * trois étapes suffiraient à la faire expirer.
 *
 * Ne touche qu'aux étapes qui ont un lieu, une date, aucune température
 * cherchée et aucune température dite. `temperatureLookedUpAt` est posé **même
 * quand on ne trouve rien** : c'est ce qui empêche de redemander à chaque
 * passage un lieu que le service ne sait pas placer.
 *
 * Séquentielle, à dessein : un voyage a quelques dizaines d'étapes au plus, le
 * quota est partagé, et rien ici n'est pressé.
 */
export async function fillMissingStepTemperatures(
  context: Pick<AppContext, "prisma" | "env" | "logger">,
  memoId: string,
): Promise<number> {
  if (!context.env.VISUAL_CROSSING_API_KEY) return 0;

  const steps = await context.prisma.memoStep.findMany({
    where: {
      memoId,
      temperatureLookedUpAt: null,
      // Une étape dont un souvenir dit déjà la température n'a rien à
      // chercher : la dite l'emporte, et l'appel serait payé pour rien.
      entries: { none: { temperatureC: { not: null } } },
    },
    select: {
      id: true,
      placeName: true,
      destinationName: true,
      destinationCountryCode: true,
      startDate: true,
      endDate: true,
    },
  });

  let trouvees = 0;
  for (const step of steps) {
    const place = lookupPlaceOf(step);
    const day = lookupDayOf(step);
    // Sans lieu ou sans date, il n'y a rien à demander — et rien à retenir
    // non plus : l'étape peut encore en recevoir un.
    if (!place || !day) continue;

    const temperature = await lookUpTemperature(
      {
        env: context.env,
        warn: (message, error) => context.logger.warn({ err: error, memoId, stepId: step.id }, message),
      },
      place,
      day,
    );

    await context.prisma.memoStep.update({
      where: { id: step.id },
      data: { temperatureC: temperature, temperatureLookedUpAt: new Date() },
    });
    if (temperature !== null) trouvees += 1;
  }

  return trouvees;
}

/**
 * La même chose, sans jamais faire échouer l'appelant : une rédaction finie ne
 * doit pas échouer parce qu'un service météo est en panne. Le passage suivant
 * rattrape les étapes qu'on n'a pas pu remplir.
 */
export async function fillMissingStepTemperaturesQuietly(
  context: Pick<AppContext, "prisma" | "env" | "logger">,
  memoId: string,
): Promise<void> {
  try {
    await fillMissingStepTemperatures(context, memoId);
  } catch (cause) {
    context.logger.warn({ err: cause, memoId }, "Températures des étapes non relevées");
  }
}
