import { afterAll, beforeEach, describe, expect, it } from "vitest";
import { createHarness, registerAccount, resetDatabase, type TestHarness } from "./helpers.js";

/**
 * Ce qu'on écrit à l'équipe et ce qu'on pense des réponses de la FAQ (T226) :
 * rien ne doit plus se perdre — ni « Écris à notre équipe », ni « Partager mes
 * retours », ni « Est-ce utile ? ».
 */

let harness: TestHarness;

beforeEach(async () => {
  harness ??= await createHarness();
  await resetDatabase(harness.prisma);
});

afterAll(async () => {
  await harness?.close();
});

describe("un message à l'équipe", () => {
  it("s'enregistre avec sa source, sa question, son voyage et son diagnostic", async () => {
    const me = await registerAccount(harness.app);
    const memo = await harness.prisma.memo.create({
      data: { ownerAccountId: me.accountId, title: "Rome", accessCode: "SUP001" },
    });

    const response = await harness.app.inject({
      method: "POST",
      url: "/v1/support/messages",
      headers: { authorization: me.authorization },
      payload: {
        source: "support",
        topicId: "faq.aide.probleme",
        message: "  L’aperçu ne s’ouvre pas.  ",
        tripId: memo.id,
        appVersion: "0.1.0 (21)",
        diagnostics: { osVersion: "iOS 26.0", deviceModel: "iPhone17,1", locale: "fr_FR" },
      },
    });

    expect(response.statusCode).toBe(201);
    const { id } = response.json<{ id: string; createdAt: string }>();
    const stored = await harness.prisma.supportMessage.findUniqueOrThrow({ where: { id } });
    expect(stored).toMatchObject({
      accountId: me.accountId,
      source: "support",
      topicId: "faq.aide.probleme",
      message: "L’aperçu ne s’ouvre pas.",
      memoId: memo.id,
      appVersion: "0.1.0 (21)",
      handledAt: null,
    });
    expect(stored.diagnostics).toEqual({ osVersion: "iOS 26.0", deviceModel: "iPhone17,1", locale: "fr_FR" });
  });

  it("vient aussi du mot des fondateurs, et oublie un voyage qui n'est pas le sien", async () => {
    const me = await registerAccount(harness.app, "moi@memobook.app");
    const other = await registerAccount(harness.app, "autre@memobook.app");
    const theirs = await harness.prisma.memo.create({
      data: { ownerAccountId: other.accountId, title: "Ailleurs", accessCode: "SUP002" },
    });

    const response = await harness.app.inject({
      method: "POST",
      url: "/v1/support/messages",
      headers: { authorization: me.authorization },
      payload: { source: "founders_note", message: "Bravo !", tripId: theirs.id },
    });

    expect(response.statusCode).toBe(201);
    const stored = await harness.prisma.supportMessage.findFirstOrThrow();
    expect(stored).toMatchObject({ source: "founders_note", memoId: null, topicId: null });
  });

  it("refuse un message vide, et freine au-delà de vingt par jour", async () => {
    const me = await registerAccount(harness.app);
    const post = (message: string) =>
      harness.app.inject({
        method: "POST",
        url: "/v1/support/messages",
        headers: { authorization: me.authorization },
        payload: { source: "support", message },
      });

    expect((await post("   ")).statusCode).toBe(400);

    await harness.prisma.supportMessage.createMany({
      data: Array.from({ length: 20 }, () => ({ accountId: me.accountId, source: "support" as const, message: "…" })),
    });
    const refused = await post("Encore une question");
    expect(refused.statusCode).toBe(429);
    expect(refused.json<{ error: string }>().error).toBe("support_rate_limited");
  });
});

describe("« Est-ce utile ? »", () => {
  it("garde un vote par question, que revoter remplace", async () => {
    const me = await registerAccount(harness.app);
    const vote = (questionId: string, isHelpful: boolean) =>
      harness.app.inject({
        method: "PUT",
        url: `/v1/support/faq-votes/${questionId}`,
        headers: { authorization: me.authorization },
        payload: { isHelpful, appVersion: "0.1.0 (21)" },
      });

    expect((await vote("faq.carnet.pages", false)).statusCode).toBe(200);
    const changed = await vote("faq.carnet.pages", true);
    expect(changed.json()).toMatchObject({ questionId: "faq.carnet.pages", isHelpful: true });
    await vote("faq.prix.app", false);

    expect(await harness.prisma.faqVote.count()).toBe(2);
    const listed = await harness.app.inject({
      method: "GET",
      url: "/v1/support/faq-votes",
      headers: { authorization: me.authorization },
    });
    const votes = listed.json<{ votes: { questionId: string; isHelpful: boolean }[] }>().votes;
    expect(votes.map((entry) => [entry.questionId, entry.isHelpful]).sort()).toEqual([
      ["faq.carnet.pages", true],
      ["faq.prix.app", false],
    ]);

    // Un identifiant qui n'en est pas un.
    expect((await vote("pas une question", true)).statusCode).toBe(400);
  });
});

describe("la suppression du compte", () => {
  it("emporte ses messages et ses votes", async () => {
    const me = await registerAccount(harness.app);
    await harness.prisma.supportMessage.create({
      data: { accountId: me.accountId, source: "support", message: "Bonjour" },
    });
    await harness.prisma.faqVote.create({ data: { accountId: me.accountId, questionId: "faq.ia.ton", isHelpful: true } });

    const deleted = await harness.app.inject({
      method: "DELETE",
      url: "/v1/accounts/me",
      headers: { authorization: me.authorization },
    });

    expect(deleted.statusCode).toBeLessThan(300);
    expect(await harness.prisma.supportMessage.count()).toBe(0);
    expect(await harness.prisma.faqVote.count()).toBe(0);
  });
});
