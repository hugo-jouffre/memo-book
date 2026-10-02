import { describe, expect, it } from "vitest";
import { reminderIntervalDays, rhythmOf } from "./notificationRhythm.js";

const quiet = { deliveredCount: 0, openedCount: 0, usedRecently: false };

describe("le rythme du voyageur", () => {
  it("part de la réponse à « À quelle fréquence ? » — le rythme du récit", () => {
    expect(rhythmOf({ ...quiet, declaredPace: "daily" }).tier).toBe("sustained");
    expect(rhythmOf({ ...quiet, declaredPace: "every_two_days" }).tier).toBe("sustained");
    expect(rhythmOf({ ...quiet, declaredPace: "weekly" }).tier).toBe("moderate");
    expect(rhythmOf({ ...quiet, declaredPace: null }).tier).toBe("light");
    // Une réponse que l'app ne propose pas vaut une question passée.
    expect(rhythmOf({ ...quiet, declaredPace: "rarely" }).tier).toBe("light");
  });

  it("monte avec l'usage et les notifications ouvertes, descend avec celles qu'on ignore", () => {
    const opensEverything = { deliveredCount: 4, openedCount: 4, usedRecently: true };
    expect(rhythmOf({ ...opensEverything, declaredPace: "weekly" }).tier).toBe("sustained");

    const ignoresEverything = { deliveredCount: 5, openedCount: 0, usedRecently: false };
    expect(rhythmOf({ ...ignoresEverything, declaredPace: "weekly" }).tier).toBe("light");
    expect(rhythmOf({ ...ignoresEverything, declaredPace: "every_two_days" }).tier).toBe("moderate");
  });

  it("ne lit pas de taux d'ouverture sur moins de trois notifications", () => {
    expect(rhythmOf({ deliveredCount: 2, openedCount: 0, usedRecently: false, declaredPace: "daily" }).openRate).toBeNull();
  });

  it("relance au rythme choisi, deux fois moins souvent quand rien n'est ouvert", () => {
    expect(reminderIntervalDays("daily", null)).toBe(1);
    expect(reminderIntervalDays("every_two_days", 0.8)).toBe(2);
    expect(reminderIntervalDays("weekly", 0.1)).toBe(14);
    expect(reminderIntervalDays(null, null)).toBe(3);
  });
});
