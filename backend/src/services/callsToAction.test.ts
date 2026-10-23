import { describe, expect, it } from "vitest";
import { CALL_TO_ACTION_IDS, CALLS_TO_ACTION, resolveCallToAction } from "./callsToAction.js";

/**
 * Les boutons sous une bulle se lisent sur iPhone **et** sur Android (lot B5,
 * 22/10/2026). Ils sont résolus à la lecture, pour celui qui lit, sans savoir
 * de quel téléphone : leurs mots ne doivent donc nommer ni l'un ni l'autre.
 * C'est l'app qui sait où mènent « les réglages du téléphone ».
 */
describe("les appels à l'action, sur les deux téléphones", () => {
  it("ne nomment ni l'iPhone, ni Android, ni un store", () => {
    for (const id of CALL_TO_ACTION_IDS) {
      const { label, eyebrow } = CALLS_TO_ACTION[id];
      expect(`${label} ${eyebrow}`, id).not.toMatch(/iPhone|iOS|Android|App Store|Play Store|Réglages de|Paramètres/);
    }
  });

  it("donnent à l'accès aux photos un libellé qui vaut pour les deux", () => {
    expect(resolveCallToAction({ id: "open_photo_settings" }, { isUnlimited: false })).toEqual({
      id: "open_photo_settings",
      kind: "open_photo_settings",
      label: "Modifier l’autorisation",
      eyebrow: "Accès aux photos limité",
      dismissible: true,
    });
  });

  it("ne montrent pas l'offre à qui raconte déjà sans limite, quel que soit son téléphone", () => {
    expect(resolveCallToAction({ id: "subscribe" }, { isUnlimited: true })).toBeNull();
    expect(resolveCallToAction({ id: "subscribe" }, { isUnlimited: false })?.kind).toBe("subscribe");
  });
});
