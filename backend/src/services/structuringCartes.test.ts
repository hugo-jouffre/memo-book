import { describe, expect, it } from "vitest";
import { ouvrirLesChapitresSurUneCarte } from "./structuring.js";

/**
 * **T284** (Hugo, 05/11/2026) : « aucune carte n'est générée dans le PDF
 * d'aperçu ».
 *
 * Tout était en place — le layout, la géométrie, les contours de Natural
 * Earth. Il manquait le champ `map` sur une journée, qu'aucun des deux
 * structureurs n'écrivait.
 */
describe("ouvrir un chapitre sur la carte de son pays", () => {
  /** Une journée ; `intro` en fait le début d'un chapitre. */
  const jour = (id: string, intro = false) => ({
    id,
    ...(intro ? { day_intro: { day_number: id } } : {}),
  });

  const cartesDe = (payload: Record<string, unknown>) =>
    (payload["days"] as Record<string, unknown>[]).map((day) => (day["map"] as { regions: string[] })?.regions[0] ?? null);

  it("pose une carte sur le premier chapitre de chaque pays", () => {
    const payload = {
      days: [jour("a"), jour("a2"), jour("b", true), jour("c", true)],
    };

    const sortie = ouvrirLesChapitresSurUneCarte(payload, ["CN", "JP", "JP"], "JP");

    // Chine au premier chapitre, Japon au deuxième — et rien au troisième,
    // qui est déjà au Japon.
    expect(cartesDe(sortie)).toEqual(["CN", null, "JP", null]);
  });

  it("n'en pose pas deux pour le même pays : sans points, elles seraient identiques", () => {
    const payload = { days: [jour("a"), jour("b", true), jour("c", true)] };

    const sortie = ouvrirLesChapitresSurUneCarte(payload, ["JP", "JP", "JP"], "JP");

    expect(cartesDe(sortie)).toEqual(["JP", null, null]);
  });

  it("ne devine pas quand les étapes et les chapitres ne se correspondent plus", () => {
    // Le metteur en page a regroupé : deux chapitres pour trois étapes. On ne
    // redistribue pas au jugé — une seule carte, celle du pays du voyage.
    const payload = { days: [jour("a"), jour("b", true)] };

    const sortie = ouvrirLesChapitresSurUneCarte(payload, ["CN", "JP", "JP"], "JP");

    expect(cartesDe(sortie)).toEqual(["JP", null]);
  });

  it("ne pose rien sans pays : un carnet sans carte vaut mieux qu'une carte fausse", () => {
    const payload = { days: [jour("a"), jour("b", true)] };

    expect(cartesDe(ouvrirLesChapitresSurUneCarte(payload, [null, null], null))).toEqual([null, null]);
  });

  it("ne remplace pas une carte déjà écrite : elle en sait plus, elle a ses points", () => {
    const main = { regions: ["PH"], points: [{ label: "Manille", lat: 14.6, lon: 121 }] };
    const payload = { days: [{ ...jour("a"), map: main }, jour("b", true)] };

    const sortie = ouvrirLesChapitresSurUneCarte(payload, ["PH", "PH"], "PH");

    expect((sortie["days"] as Record<string, unknown>[])[0]?.["map"]).toEqual(main);
  });

  it("laisse un carnet sans journée tranquille", () => {
    expect(ouvrirLesChapitresSurUneCarte({ days: [] }, ["JP"], "JP")).toEqual({ days: [] });
  });
});
