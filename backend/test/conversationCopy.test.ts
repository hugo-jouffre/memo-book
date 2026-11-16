import { describe, expect, it } from "vitest";
import { CALLS_TO_ACTION } from "../src/services/callsToAction.js";
import { photosBeyondAsked, photosKept, photosMissing } from "../src/services/conversationCopy.js";

/**
 * **Le raccourci vers le réglage** (Hugo, 25/10/2026 — « un bouton-raccourci
 * vers le réglage dans la bulle »).
 *
 * MEMO annonçait que le carnet s'écarterait des réglages du voyageur, et il
 * fallait sortir du fil, revenir au voyage, ouvrir ses réglages pour y faire
 * quelque chose. Une phrase qui annonce un écart doit donner la main sur ce
 * qui l'a causé.
 *
 * ⚠️ **Un bouton, et surtout pas une puce.** Une puce portant une intention
 * nouvelle arriverait aux apps déjà installées en intention inconnue — et une
 * intention inconnue s'envoie comme un texte : « Mes réglages » s'écrirait
 * dans le récit du voyage. C'est la règle de `docs/conversation.md`
 * § « Les boutons sous une bulle », et elle vient d'éviter une régression sur
 * le build déjà posé chez les testeurs.
 *
 * Ce qui se garde ici est **le lien entre le bouton et la phrase** : si
 * quelqu'un retire « tes réglages » d'une de ces bulles, ces cas rougissent,
 * et la question se repose — le raccourci a-t-il encore un sens là ?
 */
describe("le raccourci vers les réglages", () => {
  const parleDesReglages = (phrase: string) => /réglages/i.test(phrase);

  it("accompagne les bulles qui annoncent un écart avec les réglages", () => {
    expect(parleDesReglages(photosMissing(1, 3))).toBe(true);
    expect(parleDesReglages(photosBeyondAsked(5, 3))).toBe(true);
  });

  /**
   * Et pas les autres : la bulle qui dit simplement que les photos sont
   * gardées ne parle d'aucun réglage, et ne porte donc pas le bouton
   * (`converse.ts` ne le pose que sur les deux premières).
   */
  it("ne se pose pas sous une bulle qui n'en parle pas", () => {
    expect(parleDesReglages(photosKept(3))).toBe(false);
  });

  /**
   * Le bouton existait déjà au catalogue — il servait au modèle, qui le
   * choisit rarement et seulement sous un texte libre. Rien de nouveau n'est
   * exposé aux apps : elles le connaissent toutes depuis longtemps, et une
   * app qui l'ignorerait ne montrerait rien du tout.
   */
  it("réutilise un bouton que les apps connaissent déjà", () => {
    expect(CALLS_TO_ACTION).toHaveProperty("open_trip_settings");
    expect(CALLS_TO_ACTION.open_trip_settings.kind).toBe("open_trip_settings");
  });
});
