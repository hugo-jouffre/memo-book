import { afterAll, beforeEach, describe, expect, it } from "vitest";
import { createHarness, registerAccount, resetDatabase, type TestHarness } from "./helpers.js";

/**
 * Le verrou des étapes offertes, côté serveur : quand le quota est à zéro et
 * qu'aucun abonnement ne vit, **aucun souvenir n'entre** — quel que soit ce que
 * l'app affiche. Voir `services/quota.ts`.
 */
let harness: TestHarness;

beforeEach(async () => {
  harness ??= await createHarness();
  await resetDatabase(harness.prisma);
});

afterAll(async () => {
  await harness?.close();
});

async function tellSomething(authorization: string, memoId: string) {
  return harness.app.inject({
    method: "POST",
    url: `/v1/memos/${memoId}/entries`,
    headers: { authorization },
    payload: { kind: "text", transcript: "On est montés au Colisée à l'aube." },
  });
}

async function tripOf(accountId: string) {
  return harness.prisma.memo.create({
    data: {
      ownerAccountId: accountId,
      title: "Rome 2026",
      accessCode: "QUOTA1",
      stage: "ongoing",
    },
  });
}

describe("les étapes offertes", () => {
  it("laissent raconter tant qu'il en reste", async () => {
    const account = await registerAccount(harness.app);
    const memo = await tripOf(account.accountId);

    const told = await tellSomething(account.authorization, memo.id);
    expect(told.statusCode).toBe(201);
  });

  it("ferment le carnet à zéro, sans abonnement", async () => {
    const account = await registerAccount(harness.app);
    const memo = await tripOf(account.accountId);
    await harness.prisma.account.update({
      where: { id: account.accountId },
      data: { remainingSteps: 0 },
    });

    const told = await tellSomething(account.authorization, memo.id);
    expect(told.statusCode).toBe(403);
    expect(told.json<{ error: string }>().error).toBe("quota_exhausted");

    // Rien n'est entré : le refus vient avant l'écriture.
    expect(await harness.prisma.entry.count({ where: { memoId: memo.id } })).toBe(0);
  });

  it("rouvrent le carnet dès qu'un abonnement vit", async () => {
    const account = await registerAccount(harness.app);
    const memo = await tripOf(account.accountId);
    await harness.prisma.account.update({
      where: { id: account.accountId },
      data: { remainingSteps: 0 },
    });
    await harness.prisma.subscription.create({
      data: {
        accountId: account.accountId,
        provider: "stripe",
        status: "active",
        priceCents: 199,
      },
    });

    const told = await tellSomething(account.authorization, memo.id);
    expect(told.statusCode).toBe(201);
  });

  it("ne limitent pas un compte sans quota", async () => {
    // Les comptes d'avant le quota, et les anciens abonnés à qui personne ne
    // l'a posé : `null` veut dire « pas de limite », pas « zéro ».
    const account = await registerAccount(harness.app);
    const memo = await tripOf(account.accountId);
    await harness.prisma.account.update({
      where: { id: account.accountId },
      data: { offeredSteps: null, remainingSteps: null },
    });

    const told = await tellSomething(account.authorization, memo.id);
    expect(told.statusCode).toBe(201);
  });
});
