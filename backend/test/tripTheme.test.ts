import { beforeEach, describe, expect, it } from "vitest";
import { acceptableTripTheme } from "../src/services/conversationAnthropic.js";
import { TRIP_THEME_QUESTION } from "../src/services/conversationCopy.js";
import type { MemoResponder, TripThemeTurnInput } from "../src/services/conversation.js";
import { MEMORIES_BEFORE_GUESSING, settleTripTheme } from "../src/services/tripTheme.js";
import { createHarness, registerAccount, resetDatabase, type TestHarness } from "./helpers.js";

/**
 * **Le thème se devine tout seul** (Hugo, 10/11/2026) — et quand rien ne va,
 * MEMO demande, une fois.
 */

let harness: TestHarness;
let codes = 0;

beforeEach(async () => {
  harness ??= await createHarness();
  await resetDatabase(harness.prisma);
  // Le catalogue vient du seed, que `resetDatabase` emporte : on le repose,
  // réduit à ce qu'il faut pour juger — dont « autre », qui ne doit jamais
  // être proposé au modèle.
  await harness.prisma.tripTheme.createMany({
    data: [
      { slug: "city-trips", emoji: "🏙️", name: "City trips & découverte", position: 1 },
      { slug: "gastronomie", emoji: "🍷", name: "Gastronomie & art de vivre", position: 2 },
      { slug: "autre", emoji: "💬", name: "Autre", position: 99, isOther: true },
    ],
  });
});

/** Un répondeur qui rend ce qu'on lui dit, et garde ce qu'on lui a montré. */
function responderSaying(slug: string | null) {
  const seen: TripThemeTurnInput[] = [];
  const responder = {
    async suggestTheme(input: TripThemeTurnInput) {
      seen.push(input);
      return { slug, model: "fake-theme" };
    },
  } as unknown as MemoResponder;
  return { responder, seen };
}

/** Un répondeur en panne : le thème attendra le souvenir suivant. */
const failing = {
  async suggestTheme() {
    throw new Error("Anthropic indisponible");
  },
} as unknown as MemoResponder;

async function tripWith(memories: number, extra: Record<string, unknown> = {}) {
  const account = await registerAccount(harness.app, `t${(codes += 1)}@memobook.app`);
  const memo = await harness.prisma.memo.create({
    data: {
      ownerAccountId: account.accountId,
      title: "Rome entre frère et sœur",
      destinationCity: "Rome",
      accessCode: `THM${String(codes).padStart(3, "0")}`,
      stage: "ongoing",
      ...extra,
    },
  });
  for (let index = 0; index < memories; index += 1) {
    await harness.prisma.entry.create({
      data: {
        memoId: memo.id,
        kind: "text",
        status: "ready",
        transcript: `Souvenir ${index + 1}`,
        redactedText: `Le récit du jour ${index + 1}, place Navone.`,
        capturedAt: new Date(Date.now() + index * 1_000),
      },
    });
  }
  return memo;
}

async function themes() {
  return harness.prisma.tripTheme.findMany({ select: { slug: true } });
}

describe("ce qui passe comme thème", () => {
  const catalogue = [{ slug: "city-trips" }, { slug: "gastronomie" }];

  it("accepte un slug du catalogue, quelle qu'en soit la casse", () => {
    expect(acceptableTripTheme("city-trips", catalogue)).toBe("city-trips");
    expect(acceptableTripTheme("  City-Trips ", catalogue)).toBe("city-trips");
  });

  it("refuse tout le reste, et « autre » en premier", () => {
    expect(acceptableTripTheme("autre", catalogue)).toBeNull();
    expect(acceptableTripTheme("randonnée en montagne", catalogue)).toBeNull();
    expect(acceptableTripTheme("City trips & découverte", catalogue)).toBeNull();
    expect(acceptableTripTheme("", catalogue)).toBeNull();
    expect(acceptableTripTheme(null, catalogue)).toBeNull();
  });
});

describe("deviner le thème", () => {
  it("l'écrit sans déranger personne, et ne demande rien", async () => {
    const memo = await tripWith(MEMORIES_BEFORE_GUESSING);
    const { responder, seen } = responderSaying("city-trips");

    const outcome = await settleTripTheme(harness.context, responder, memo.id);

    expect(outcome).toMatchObject({ kind: "guessed", slug: "city-trips" });
    const after = await harness.prisma.memo.findUniqueOrThrow({ where: { id: memo.id } });
    // **Le nom, pas le slug** : c'est ce que la feuille des réglages compare
    // et ce que la rédaction écrit tel quel dans son prompt.
    expect(after.theme).toBe("City trips & découverte");
    expect(after.themeAskedAt).toBeNull();
    expect(await harness.prisma.chatMessage.count({ where: { memoId: memo.id } })).toBe(0);

    // Ce qu'on a montré au modèle : le voyage, et ce qui en est écrit.
    expect(seen[0]?.memo).toMatchObject({ title: "Rome entre frère et sœur", destinationCity: "Rome" });
    expect(seen[0]?.memories).toHaveLength(MEMORIES_BEFORE_GUESSING);
    // « Autre » n'est jamais proposé au modèle.
    expect(seen[0]?.themes.map((theme) => theme.slug)).not.toContain("autre");
  });

  it("attend d'avoir assez de souvenirs écrits", async () => {
    const memo = await tripWith(MEMORIES_BEFORE_GUESSING - 1);
    const { responder, seen } = responderSaying("city-trips");

    expect(await settleTripTheme(harness.context, responder, memo.id)).toMatchObject({
      kind: "skipped",
      why: "too-early",
    });
    expect(seen).toHaveLength(0);
  });

  it("ne touche jamais à un thème déjà choisi", async () => {
    const memo = await tripWith(MEMORIES_BEFORE_GUESSING, { theme: "Gastronomie & art de vivre" });
    const { responder, seen } = responderSaying("city-trips");

    expect(await settleTripTheme(harness.context, responder, memo.id)).toMatchObject({
      kind: "skipped",
      why: "already-set",
    });
    expect(seen).toHaveLength(0);
    const after = await harness.prisma.memo.findUniqueOrThrow({ where: { id: memo.id } });
    expect(after.theme).toBe("Gastronomie & art de vivre");
  });
});

describe("quand aucun thème ne va", () => {
  it("MEMO demande, une seule fois", async () => {
    const memo = await tripWith(MEMORIES_BEFORE_GUESSING);
    const { responder } = responderSaying(null);

    expect(await settleTripTheme(harness.context, responder, memo.id)).toMatchObject({ kind: "asked" });

    const bulles = await harness.prisma.chatMessage.findMany({ where: { memoId: memo.id } });
    expect(bulles).toHaveLength(1);
    expect(bulles[0]?.text).toBe(TRIP_THEME_QUESTION);
    expect(bulles[0]?.author).toBe("memo");
    const after = await harness.prisma.memo.findUniqueOrThrow({ where: { id: memo.id } });
    expect(after.themeAskedAt).toBeInstanceOf(Date);

    // Le souvenir suivant ne repose pas la question.
    expect(await settleTripTheme(harness.context, responder, memo.id)).toMatchObject({
      kind: "skipped",
      why: "already-asked",
    });
    expect(await harness.prisma.chatMessage.count({ where: { memoId: memo.id } })).toBe(1);
  });

  it("la question ne porte aucun bouton : c'est une conversation", async () => {
    const memo = await tripWith(MEMORIES_BEFORE_GUESSING);
    await settleTripTheme(harness.context, responderSaying(null).responder, memo.id);

    const bulle = await harness.prisma.chatMessage.findFirstOrThrow({ where: { memoId: memo.id } });
    expect(bulle.payload).toEqual({});
  });
});

describe("quand le modèle est en panne", () => {
  /**
   * Rien n'est écrit, **pas même la date** : le souvenir suivant réessaiera.
   * Une panne d'une minute ne doit pas coûter le thème d'un voyage.
   */
  it("laisse le voyage intact, et retentera", async () => {
    const memo = await tripWith(MEMORIES_BEFORE_GUESSING);

    expect(await settleTripTheme(harness.context, failing, memo.id)).toMatchObject({
      kind: "skipped",
      why: "too-early",
    });

    const after = await harness.prisma.memo.findUniqueOrThrow({ where: { id: memo.id } });
    expect(after.theme).toBeNull();
    expect(after.themeAskedAt).toBeNull();
    expect(await harness.prisma.chatMessage.count({ where: { memoId: memo.id } })).toBe(0);
  });
});

describe("le catalogue", () => {
  it("existe, et « autre » en fait partie — mais jamais pour deviner", async () => {
    const all = await themes();
    expect(all.length).toBeGreaterThan(1);
    expect(all.map((theme) => theme.slug)).toContain("autre");
  });
});
