import { afterAll, beforeEach, describe, expect, it } from "vitest";
import { seedTripThemes, TRIP_THEMES } from "../prisma/tripThemes.js";
import { createHarness, registerAccount, resetDatabase, type TestHarness } from "./helpers.js";

interface ThemesBody {
  themes: { id: string; slug: string; emoji: string; name: string; isOther: boolean }[];
}

/**
 * Les thèmes de « Contexte de ton voyage » viennent de la base, pas de l'app :
 * ce qui est vérifié ici, c'est ce dont `TripThemePicker` dépend pour se
 * remplir — l'ordre, « Autre » en dernier, et les clés que Swift décode.
 */
let harness: TestHarness;

beforeEach(async () => {
  harness ??= await createHarness();
  await resetDatabase(harness.prisma);
});

afterAll(async () => {
  await harness?.close();
});

describe("les thèmes de voyage", () => {
  it("sert les thèmes actifs dans l'ordre, « Autre » en dernier", async () => {
    await seedTripThemes(harness.prisma);
    // Éteint, il ne doit plus se voir ; et un « Autre » posé n'importe où dans
    // la table doit quand même finir dernier — c'est la route qui le garantit,
    // pas la discipline de celui qui remplit la table.
    await harness.prisma.tripTheme.update({ where: { slug: "evenementiels" }, data: { isActive: false } });
    await harness.prisma.tripTheme.update({ where: { slug: "autre" }, data: { position: -1 } });

    const account = await registerAccount(harness.app);
    const response = await harness.app.inject({
      method: "GET",
      url: "/v1/trip-themes",
      headers: { authorization: account.authorization },
    });

    expect(response.statusCode).toBe(200);
    const { themes } = response.json<ThemesBody>();

    expect(themes.map((theme) => theme.slug)).toEqual(
      TRIP_THEMES.map((theme) => theme.slug).filter((slug) => slug !== "evenementiels"),
    );
    expect(themes.at(-1)).toMatchObject({ slug: "autre", name: "Autre", isOther: true });
    expect(themes[0]).toMatchObject({ emoji: "🏔️", name: "Nature & aventure", isOther: false });
  });

  it("exige une session : la liste n'est pas publique", async () => {
    const response = await harness.app.inject({ method: "GET", url: "/v1/trip-themes" });
    expect(response.statusCode).toBe(401);
  });

  it("se repose sans doublon, et rallume ce qui avait été éteint", async () => {
    await seedTripThemes(harness.prisma);
    await harness.prisma.tripTheme.update({ where: { slug: "a-deux" }, data: { isActive: false } });
    await seedTripThemes(harness.prisma);

    const count = await harness.prisma.tripTheme.count();
    expect(count).toBe(TRIP_THEMES.length);
    const revived = await harness.prisma.tripTheme.findUniqueOrThrow({ where: { slug: "a-deux" } });
    expect(revived.isActive).toBe(true);
  });
});
