import type { Env } from "../env.js";
import { cleDeVue, requeteOverpass, ruesDOverpass, vuesDesVilles, type Cadre, type Rues } from "./mapSvg.js";
import { createPublicAssetStore, type PublicAssetStore } from "./storage.js";

/**
 * Les rues et les cours d'eau des cartes de ville, tirés d'OpenStreetMap.
 *
 * Trois règles :
 *
 * 1. **Avant le rendu.** Le moteur PDF ne fait aucun appel réseau : les rues
 *    se demandent ici, puis `expandMaps` les dessine dans le SVG.
 * 2. **Une fois par zone.** Overpass est un service partagé, et sa réponse
 *    pour une zone ne bouge pas d'un carnet à l'autre. Elle se garde dans le
 *    bucket public, sous `osm/v1/<sud>_<ouest>_<nord>_<est>.json` — la zone
 *    arrondie au centième de degré (`vueDeVille`), réduite à ce que la carte
 *    dessine (`ruesDOverpass`) : quelques dizaines de Ko au lieu de quelques
 *    Mo.
 * 3. **Jamais bloquant.** Overpass en panne, trop lent ou saturé : la carte
 *    de ville retombe sur sa version sobre (contour, points, trajet), et le
 *    carnet part quand même.
 */

/** À incrémenter si `ruesDOverpass` change ce qu'elle garde : l'ancien cache est alors ignoré. */
const PREFIXE_CACHE = "osm/v1";
/**
 * Au-delà, on renonce aux rues : un carnet n'attend pas une carte. L'instance
 * publique met souvent une demi-minute à servir une requête minuscule (file
 * d'attente) : une minute laisse passer ces jours-là.
 */
const DELAI_MS = 60_000;

export interface CityStreetSourceOptions {
  store: PublicAssetStore;
  /** L'API Overpass (`OVERPASS_URL`). */
  url: string;
  timeoutMs?: number;
  fetcher?: typeof fetch;
  warn?: (message: string, error?: unknown) => void;
}

export class CityStreetSource {
  private readonly store: PublicAssetStore;
  private readonly url: string;
  private readonly timeoutMs: number;
  private readonly fetcher: typeof fetch;
  private readonly warn: (message: string, error?: unknown) => void;

  constructor(options: CityStreetSourceOptions) {
    this.store = options.store;
    this.url = options.url;
    this.timeoutMs = options.timeoutMs ?? DELAI_MS;
    this.fetcher = options.fetcher ?? fetch;
    this.warn = options.warn ?? ((message, error) => console.warn(`[osm] ${message}`, error ?? ""));
  }

  /** Les rues de chaque carte de ville du carnet, par clé de vue. Une ville sans réponse n'y est pas. */
  async forPayload(payload: Record<string, unknown>): Promise<Map<string, Rues>> {
    const rues = new Map<string, Rues>();
    let vues: Cadre[] = [];
    try {
      vues = vuesDesVilles(payload);
    } catch (error) {
      this.warn("cartes de ville illisibles : cartes sobres", error);
    }
    for (const vue of vues) {
      const trouvees = await this.forView(vue);
      if (trouvees) rues.set(cleDeVue(vue), trouvees);
    }
    return rues;
  }

  async forView(vue: Cadre): Promise<Rues | null> {
    const cle = `${PREFIXE_CACHE}/${cleDeVue(vue)}.json`;
    try {
      const enCache = await this.store.read(cle);
      if (enCache) return JSON.parse(enCache.toString("utf8")) as Rues;
    } catch (error) {
      // Un cache illisible ne coûte qu'un appel à Overpass.
      this.warn(`cache ${cle} illisible`, error);
    }

    let rues: Rues;
    try {
      const reponse = await this.fetcher(this.url, {
        method: "POST",
        headers: {
          "content-type": "application/x-www-form-urlencoded",
          // La règle d'usage des instances publiques : dire qui appelle.
          "user-agent": "MemoBook/1.0 (https://memo-book.com ; cartes de chapitre)",
        },
        body: new URLSearchParams({ data: requeteOverpass(vue) }),
        signal: AbortSignal.timeout(this.timeoutMs),
      });
      if (!reponse.ok) throw new Error(`HTTP ${reponse.status}`);
      const json = (await reponse.json()) as { remark?: string };
      // Un délai dépassé côté Overpass répond 200, avec une remarque et des
      // éléments partiels : une carte à moitié dessinée, et mise en cache
      // pour toujours. On la refuse.
      if (json.remark && /error/i.test(json.remark)) throw new Error(json.remark);
      rues = ruesDOverpass(json, vue);
    } catch (error) {
      this.warn(`Overpass indisponible pour ${cleDeVue(vue)} : carte de ville sobre`, error);
      return null;
    }

    try {
      await this.store.write(cle, Buffer.from(JSON.stringify(rues), "utf8"), "application/json");
    } catch (error) {
      this.warn(`cache ${cle} non écrit`, error);
    }
    return rues;
  }
}

/** `null` en test : la suite ne parle jamais à Overpass. */
export function createCityStreetSource(env: Env): CityStreetSource | null {
  if (env.NODE_ENV === "test") return null;
  return new CityStreetSource({ store: createPublicAssetStore(env), url: env.OVERPASS_URL });
}
