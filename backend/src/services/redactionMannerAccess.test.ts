import { describe, expect, it } from "vitest";

import { mannerAccess } from "./redactionMannerAccess.js";

describe("qui peut changer sa manière d'être rédigé (T292)", () => {
  it("ouvre le réglage à un abonné illimité, quel que soit le carnet", () => {
    expect(mannerAccess({ isUnlimited: true, stepCount: 40 })).toEqual({
      allowed: true,
      reason: "unlimited",
    });
  });

  it("l'ouvre aussi sur un carnet d'une seule étape, sans abonnement", () => {
    // La reprise ne coûte qu'un appel : un paywall y serait posé sur rien.
    expect(mannerAccess({ isUnlimited: false, stepCount: 1 })).toEqual({
      allowed: true,
      reason: "single_step",
    });
  });

  it("l'ouvre sur un carnet vide", () => {
    expect(mannerAccess({ isUnlimited: false, stepCount: 0 }).allowed).toBe(true);
  });

  it("le ferme dès la deuxième étape, sans abonnement", () => {
    expect(mannerAccess({ isUnlimited: false, stepCount: 2 })).toEqual({
      allowed: false,
      reason: "needs_unlimited",
    });
  });
});
