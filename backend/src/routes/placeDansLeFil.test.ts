import { describe, expect, it } from "vitest";
import { POSTED_AT_FLOOR_MS, postedAtFrom } from "./chat.js";

/**
 * **L'instant que l'app annonce range la bulle dans le fil** (T309) — et une
 * date fautive la poserait au début du carnet, ou après tout le reste. Ce qui
 * est relu ici est donc la garde, pas la politesse.
 */

const NOW = new Date("2026-11-26T18:00:00.000Z");

describe("l'instant où le voyageur a posé sa bulle", () => {
  it("est pris tel quel quand il est passé et récent", () => {
    expect(postedAtFrom("2026-11-23T09:30:00.000Z", NOW)).toEqual(new Date("2026-11-23T09:30:00.000Z"));
  });

  /** Une app sans la clé, et tout ce qui précède le 26/11/2026. */
  it("retombe sur l'arrivée quand l'app n'en envoie pas", () => {
    expect(postedAtFrom(undefined, NOW)).toEqual(NOW);
    expect(postedAtFrom(null, NOW)).toEqual(NOW);
    expect(postedAtFrom("", NOW)).toEqual(NOW);
  });

  it("refuse ce qui n'est pas une date", () => {
    expect(postedAtFrom("hier", NOW)).toEqual(NOW);
  });

  /**
   * Une horloge en avance rangerait la bulle **après** tout ce qui suivra,
   * pour toujours : on ne pose rien dans l'avenir.
   */
  it("ramène un instant futur à l'arrivée", () => {
    expect(postedAtFrom("2027-01-01T00:00:00.000Z", NOW)).toEqual(NOW);
  });

  /**
   * Et une horloge déréglée — ou un client malveillant — ne pose pas une
   * bulle en tête du carnet d'un voyage d'il y a trois ans.
   */
  it("refuse un instant plus vieux qu'un an", () => {
    const limite = new Date(NOW.getTime() - POSTED_AT_FLOOR_MS + 1_000);
    expect(postedAtFrom(limite.toISOString(), NOW)).toEqual(limite);
    expect(postedAtFrom(new Date(NOW.getTime() - POSTED_AT_FLOOR_MS - 1_000).toISOString(), NOW)).toEqual(NOW);
  });
});
