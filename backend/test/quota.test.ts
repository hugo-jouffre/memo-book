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

/**
 * Le **sursis de la semaine payée** : une semaine commencée est une semaine
 * réglée, donc elle va à son terme même après une résiliation. Hugo,
 * 16/09/2026. Voir `PAID_THROUGH_SUBSCRIPTION` dans `services/quota.ts`.
 */
describe("la semaine déjà payée", () => {
  async function exhaustedAccountWith(status: "cancelled" | "expired", renewsAt: Date | null) {
    const account = await registerAccount(harness.app);
    const memo = await tripOf(account.accountId);
    await harness.prisma.account.update({
      where: { id: account.accountId },
      data: { remainingSteps: 0 },
    });
    await harness.prisma.subscription.create({
      data: { accountId: account.accountId, provider: "stripe", status, priceCents: 199, renewsAt },
    });
    return { account, memo };
  }

  it("laisse raconter après une résiliation, jusqu'à la fin de la période", async () => {
    const { account, memo } = await exhaustedAccountWith(
      "cancelled",
      new Date(Date.now() + 5 * 86_400_000),
    );

    const told = await tellSomething(account.authorization, memo.id);
    expect(told.statusCode).toBe(201);
  });

  it("vaut aussi pour un abonnement éteint par la fin du voyage", async () => {
    // `expired` et non `cancelled` : personne n'a résilié, c'est le voyage qui
    // s'est terminé. La semaine a coûté le même prix.
    const { account, memo } = await exhaustedAccountWith(
      "expired",
      new Date(Date.now() + 2 * 86_400_000),
    );

    const told = await tellSomething(account.authorization, memo.id);
    expect(told.statusCode).toBe(201);
  });

  it("ferme une fois la période écoulée", async () => {
    const { account, memo } = await exhaustedAccountWith(
      "cancelled",
      new Date(Date.now() - 86_400_000),
    );

    const told = await tellSomething(account.authorization, memo.id);
    expect(told.statusCode).toBe(403);
    expect(told.json<{ error: string }>().error).toBe("quota_exhausted");
  });

  it("ferme quand aucune période n'a été payée", async () => {
    const { account, memo } = await exhaustedAccountWith("cancelled", null);

    const told = await tellSomething(account.authorization, memo.id);
    expect(told.statusCode).toBe(403);
  });
});

/**
 * Les **limites de souvenirs** : le budget mensuel de quelqu'un qui raconte
 * déjà. Voir `services/memoryAllowance.ts`.
 */
describe("les limites de souvenirs", () => {
  it("décomptent un message écrit, et un vocal bien plus", async () => {
    const account = await registerAccount(harness.app);
    const memo = await tripOf(account.accountId);

    await tellSomething(account.authorization, memo.id);

    const after = await harness.prisma.account.findUniqueOrThrow({
      where: { id: account.accountId },
      select: { memoryUsed: true },
    });
    expect(after.memoryUsed).toBe(1);
  });

  it("refusent avec un code que l'app sait lire", async () => {
    const account = await registerAccount(harness.app);
    const memo = await tripOf(account.accountId);
    // Tout consommé : le palier compris ouvre 3 000 souvenirs.
    await harness.prisma.account.update({
      where: { id: account.accountId },
      data: { memoryUsed: 3_000 },
    });

    const told = await tellSomething(account.authorization, memo.id);
    expect(told.statusCode).toBe(403);
    expect(told.json<{ error: string }>().error).toBe("memory_limit_reached");
    expect(await harness.prisma.entry.count({ where: { memoId: memo.id } })).toBe(0);
  });

  it("rouvrent au palier étendu", async () => {
    const account = await registerAccount(harness.app);
    const memo = await tripOf(account.accountId);
    await harness.prisma.account.update({
      where: { id: account.accountId },
      data: { memoryUsed: 3_000, memoryPlan: "extended" },
    });

    const told = await tellSomething(account.authorization, memo.id);
    expect(told.statusCode).toBe(201);
  });

  it("repartent à zéro quand le mois est écoulé", async () => {
    const account = await registerAccount(harness.app);
    const memo = await tripOf(account.accountId);
    await harness.prisma.account.update({
      where: { id: account.accountId },
      data: {
        memoryUsed: 3_000,
        // Une période entière derrière nous : la lecture la remet à zéro.
        memoryPeriodStart: new Date(Date.now() - 31 * 86_400_000),
      },
    });

    const told = await tellSomething(account.authorization, memo.id);
    expect(told.statusCode).toBe(201);

    const after = await harness.prisma.account.findUniqueOrThrow({
      where: { id: account.accountId },
      select: { memoryUsed: true },
    });
    // La période a été remise à plat, puis le message a coûté son unité.
    expect(after.memoryUsed).toBe(1);
  });
});
