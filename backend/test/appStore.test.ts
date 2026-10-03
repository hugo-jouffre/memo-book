import { afterAll, beforeEach, describe, expect, it } from "vitest";
import {
  AppStoreVerificationError,
  readRootCertificates,
  type AppStoreNotification,
  type AppStoreTransaction,
  type AppStoreVerifier,
} from "../src/services/appStore.js";
import { storeKitState } from "../src/services/appStoreSubscriptions.js";
import { APP_STORE_PRODUCT_IDS } from "../src/services/subscriptionCatalog.js";
import { hasUnlimitedAccess } from "../src/services/subscriptions.js";
import { createHarness, registerAccount, resetDatabase, type TestHarness } from "./helpers.js";

/**
 * L'abonnement acheté par StoreKit : la route de l'app, le webhook d'Apple, et
 * ce que le reste du serveur en lit. Voir `services/appStoreSubscriptions.ts`.
 *
 * La signature d'Apple est simulée : le vérificateur de test rend ce qu'on lui
 * a confié, et refuse le reste. Ce que ces tests gardent, c'est **ce qu'on fait
 * d'une transaction une fois qu'Apple l'a signée** — la vérification elle-même
 * est celle de la bibliothèque d'Apple.
 */

const DAY = 86_400_000;
const signed = new Map<string, unknown>();

function sign(value: AppStoreTransaction | AppStoreNotification): string {
  const jws = `jws-${signed.size + 1}`;
  signed.set(jws, value);
  return jws;
}

const fakeAppStore: AppStoreVerifier = {
  async verifyTransaction(jws) {
    const value = signed.get(jws);
    if (!value) throw new AppStoreVerificationError("Signature App Store refusée (VERIFICATION_FAILURE).");
    return value as AppStoreTransaction;
  },
  async verifyNotification(jws) {
    const value = signed.get(jws);
    if (!value) throw new AppStoreVerificationError("Signature App Store refusée (VERIFICATION_FAILURE).");
    return value as AppStoreNotification;
  },
};

let harness: TestHarness;

beforeEach(async () => {
  harness ??= await createHarness({ appStore: fakeAppStore });
  await resetDatabase(harness.prisma);
  signed.clear();
});

afterAll(async () => {
  await harness?.close();
});

function transaction(overrides: Partial<AppStoreTransaction> = {}): AppStoreTransaction {
  const purchasedAt = overrides.purchasedAt ?? new Date();
  return {
    transactionId: "2000000000000001",
    originalTransactionId: "2000000000000001",
    productId: APP_STORE_PRODUCT_IDS.monthlySubscription,
    appAccountToken: null,
    purchasedAt,
    expiresAt: new Date(purchasedAt.getTime() + 30 * DAY),
    revokedAt: null,
    priceCents: 499,
    currency: "EUR",
    environment: "Sandbox",
    signedAt: purchasedAt,
    ...overrides,
  };
}

function notification(
  type: string,
  tx: AppStoreTransaction,
  extra: Partial<AppStoreNotification> = {},
): AppStoreNotification {
  return {
    notificationId: `notif-${signed.size + 1}`,
    type,
    subtype: null,
    signedAt: tx.signedAt,
    transaction: tx,
    renewal: { autoRenews: true, gracePeriodEndsAt: null },
    status: "active",
    ...extra,
  };
}

async function purchase(authorization: string, tx: AppStoreTransaction, memoId?: string) {
  return harness.app.inject({
    method: "POST",
    url: "/v1/subscriptions/app-store",
    headers: { authorization },
    payload: { signedTransaction: sign(tx), ...(memoId ? { memoId } : {}) },
  });
}

async function notify(value: AppStoreNotification) {
  return harness.app.inject({
    method: "POST",
    url: "/v1/webhooks/app-store",
    payload: { signedPayload: sign(value) },
  });
}

async function tripOf(accountId: string, endDate: Date | null = new Date(Date.now() + 10 * DAY)) {
  return harness.prisma.memo.create({
    data: { ownerAccountId: accountId, title: "Rome 2026", accessCode: "STORE1", stage: "ongoing", endDate },
  });
}

/** Ce compte raconte-t-il sans limite ? La règle du crédit du jour (`subscriptions.ts`). */
async function isUnlimited(accountId: string): Promise<boolean> {
  return hasUnlimitedAccess(harness.prisma, accountId);
}

type ProfileBody = {
  subscription: {
    price: number;
    interval: "month" | "week";
    weeklyPrice: number;
    isActive: boolean;
    isUnlimited: boolean;
    paidThrough: string | null;
    managedByAppStore: boolean;
  };
  offeredSteps?: unknown;
  remainingSteps?: unknown;
};

describe("l'achat depuis l'app", () => {
  it("ouvre l'abonnement, l'inscrit au registre, et le rattache au voyage", async () => {
    const account = await registerAccount(harness.app);
    const memo = await tripOf(account.accountId);
    expect(await isUnlimited(account.accountId)).toBe(false);

    const tx = transaction({ appAccountToken: account.accountId });
    const response = await purchase(account.authorization, tx, memo.id);

    expect(response.statusCode).toBe(200);
    expect(response.json<ProfileBody>().subscription).toMatchObject({
      price: 4.99,
      interval: "month",
      weeklyPrice: 4.99,
      isActive: true,
      isUnlimited: true,
      paidThrough: tx.expiresAt?.toISOString(),
      managedByAppStore: true,
    });

    const row = await harness.prisma.subscription.findFirstOrThrow({
      where: { accountId: account.accountId },
      include: { transactions: true },
    });
    expect(row).toMatchObject({
      provider: "storekit",
      status: "active",
      providerSubscriptionId: tx.originalTransactionId,
      memoId: memo.id,
      priceCents: 499,
      interval: "month",
      productId: APP_STORE_PRODUCT_IDS.monthlySubscription,
      environment: "Sandbox",
    });
    expect(row.transactions).toHaveLength(1);
    expect(row.transactions[0]).toMatchObject({ memoId: memo.id, priceCents: 499 });

    // L'illimité s'ouvre dans la seconde, sans attendre la notification d'Apple.
    expect(await isUnlimited(account.accountId)).toBe(true);
  });

  it("accepte encore l'ancien abonnement hebdomadaire, à son rythme et à son prix", async () => {
    // Plus vendu dans l'app, mais un abonné de la semaine qui restaure son
    // achat reste illimité jusqu'au bout de ce qu'il a payé (03/10/2026).
    const account = await registerAccount(harness.app);
    const tx = transaction({
      appAccountToken: account.accountId,
      productId: APP_STORE_PRODUCT_IDS.legacyWeeklySubscription,
      expiresAt: new Date(Date.now() + 7 * DAY),
      priceCents: 199,
    });

    const response = await purchase(account.authorization, tx);

    expect(response.statusCode).toBe(200);
    expect(response.json<ProfileBody>().subscription).toMatchObject({
      price: 1.99,
      interval: "week",
      weeklyPrice: 1.99,
      isUnlimited: true,
    });
    const row = await harness.prisma.subscription.findFirstOrThrow({ where: { accountId: account.accountId } });
    expect(row).toMatchObject({ interval: "week", priceCents: 199, productId: tx.productId });
  });

  it("passe de la semaine au mois sur la même ligne, qui prend le produit, le rythme et le prix", async () => {
    const account = await registerAccount(harness.app);
    const weekly = transaction({
      appAccountToken: account.accountId,
      productId: APP_STORE_PRODUCT_IDS.legacyWeeklySubscription,
      purchasedAt: new Date(Date.now() - 2 * DAY),
      expiresAt: new Date(Date.now() + 5 * DAY),
      priceCents: 199,
    });
    await purchase(account.authorization, weekly);

    // Même groupe d'abonnements chez Apple : l'`originalTransactionId` reste.
    const monthly = transaction({
      transactionId: "2000000000000002",
      originalTransactionId: weekly.originalTransactionId,
      appAccountToken: account.accountId,
      purchasedAt: new Date(),
      signedAt: new Date(),
    });
    expect((await notify(notification("DID_CHANGE_RENEWAL_PREF", monthly))).statusCode).toBe(200);

    expect(await harness.prisma.subscription.count()).toBe(1);
    const row = await harness.prisma.subscription.findFirstOrThrow({
      where: { accountId: account.accountId },
      include: { transactions: true },
    });
    expect(row).toMatchObject({
      productId: APP_STORE_PRODUCT_IDS.monthlySubscription,
      interval: "month",
      priceCents: 499,
      renewsAt: monthly.expiresAt,
    });
    expect(row.transactions).toHaveLength(2);
  });

  it("se rejoue sans inscrire deux fois la même période", async () => {
    // L'app renvoie sa transaction à chaque lancement tant qu'elle ne l'a pas finie.
    const account = await registerAccount(harness.app);
    const tx = transaction({ appAccountToken: account.accountId });

    expect((await purchase(account.authorization, tx)).statusCode).toBe(200);
    expect((await purchase(account.authorization, tx)).statusCode).toBe(200);

    expect(await harness.prisma.subscription.count()).toBe(1);
    expect(await harness.prisma.subscriptionTransaction.count()).toBe(1);
  });

  it("refuse un achat fait depuis un autre compte MemoBook", async () => {
    const account = await registerAccount(harness.app);
    const other = await registerAccount(harness.app, "autre@memobook.app");

    const response = await purchase(account.authorization, transaction({ appAccountToken: other.accountId }));

    expect(response.statusCode).toBe(403);
    expect(response.json<{ error: string }>().error).toBe("transaction_account_mismatch");
    expect(await harness.prisma.subscription.count()).toBe(0);
  });

  it("restaure sur un nouveau compte un achat fait depuis un compte supprimé", async () => {
    // Le compte supprimé emporte sa ligne ; Apple, lui, continue de prélever.
    const gone = await registerAccount(harness.app, "parti@memobook.app");
    await purchase(gone.authorization, transaction({ appAccountToken: gone.accountId }));
    await harness.prisma.account.delete({ where: { id: gone.accountId } });

    const account = await registerAccount(harness.app);
    const response = await purchase(account.authorization, transaction({ appAccountToken: gone.accountId }));

    expect(response.statusCode).toBe(200);
    expect(await isUnlimited(account.accountId)).toBe(true);
  });

  it("refuse un abonnement Apple déjà rattaché à un autre compte", async () => {
    // Même identifiant Apple, deux comptes MemoBook : un paiement n'ouvre qu'un abonnement.
    const first = await registerAccount(harness.app);
    const second = await registerAccount(harness.app, "second@memobook.app");
    await purchase(first.authorization, transaction());

    const response = await purchase(second.authorization, transaction({ transactionId: "2000000000000002" }));

    expect(response.statusCode).toBe(409);
    expect(response.json<{ error: string }>().error).toBe("subscription_owned_elsewhere");
  });

  it("refuse une transaction qu'Apple n'a pas signée", async () => {
    const account = await registerAccount(harness.app);

    const response = await harness.app.inject({
      method: "POST",
      url: "/v1/subscriptions/app-store",
      headers: { authorization: account.authorization },
      payload: { signedTransaction: "eyJmYWtlIjp0cnVlfQ" },
    });

    expect(response.statusCode).toBe(400);
    expect(response.json<{ error: string }>().error).toBe("invalid_transaction");
    expect(await harness.prisma.subscription.count()).toBe(0);
  });

  it("refuse un autre produit que l'abonnement", async () => {
    const account = await registerAccount(harness.app);

    const response = await purchase(
      account.authorization,
      transaction({ productId: "com.memobook.app.autre.chose" }),
    );

    expect(response.statusCode).toBe(400);
    expect(response.json<{ error: string }>().error).toBe("unknown_product");
  });
});

describe("les notifications d'Apple", () => {
  async function subscribedAccount() {
    const account = await registerAccount(harness.app);
    const tx = transaction({ appAccountToken: account.accountId, purchasedAt: new Date(Date.now() - DAY) });
    await purchase(account.authorization, tx);
    return { account, tx };
  }

  it("prolongent l'abonnement à chaque renouvellement", async () => {
    const { account, tx } = await subscribedAccount();
    const renewal = transaction({
      ...tx,
      transactionId: "2000000000000002",
      purchasedAt: tx.expiresAt!,
      expiresAt: new Date(tx.expiresAt!.getTime() + 30 * DAY),
      signedAt: new Date(),
    });

    expect((await notify(notification("DID_RENEW", renewal))).statusCode).toBe(200);

    const row = await harness.prisma.subscription.findFirstOrThrow({
      where: { accountId: account.accountId },
      include: { transactions: true },
    });
    expect(row.status).toBe("active");
    expect(row.renewsAt).toEqual(renewal.expiresAt);
    expect(row.transactions).toHaveLength(2);
  });

  it("gardent le mois payé quand le renouvellement est coupé dans iOS", async () => {
    const { account, tx } = await subscribedAccount();

    await notify(
      notification("DID_CHANGE_RENEWAL_STATUS", { ...tx, signedAt: new Date() }, {
        subtype: "AUTO_RENEW_DISABLED",
        renewal: { autoRenews: false, gracePeriodEndsAt: null },
      }),
    );

    const row = await harness.prisma.subscription.findFirstOrThrow({ where: { accountId: account.accountId } });
    expect(row).toMatchObject({ status: "cancelled", autoRenews: false, renewsAt: tx.expiresAt });
    expect(row.cancelledAt).not.toBeNull();

    // Un mois commencé est un mois réglé : l'illimité reste ouvert jusqu'au bout.
    expect(await isUnlimited(account.accountId)).toBe(true);
    const profile = await harness.app.inject({
      method: "GET",
      url: "/v1/profile",
      headers: { authorization: account.authorization },
    });
    expect(profile.json<ProfileBody>().subscription).toMatchObject({
      isActive: false,
      isUnlimited: true,
      price: 4.99,
      interval: "month",
    });
  });

  it("ferment l'illimité à l'expiration", async () => {
    const { account, tx } = await subscribedAccount();
    const ended = { ...tx, expiresAt: new Date(Date.now() - 1000), signedAt: new Date() };

    await notify(notification("EXPIRED", ended, { subtype: "VOLUNTARY", status: "expired" }));

    const row = await harness.prisma.subscription.findFirstOrThrow({ where: { accountId: account.accountId } });
    expect(row.status).toBe("expired");
    expect(await isUnlimited(account.accountId)).toBe(false);
  });

  it("écrivent encore la ligne d'un ancien abonné de la semaine", async () => {
    // Ignorer ses renouvellements et ses expirations le laisserait illimité à vie.
    const account = await registerAccount(harness.app);
    const weekly = transaction({
      appAccountToken: account.accountId,
      productId: APP_STORE_PRODUCT_IDS.legacyWeeklySubscription,
      purchasedAt: new Date(Date.now() - 8 * DAY),
      expiresAt: new Date(Date.now() - DAY),
      priceCents: 199,
      signedAt: new Date(Date.now() - 8 * DAY),
    });
    await notify(notification("SUBSCRIBED", weekly));
    await notify(notification("EXPIRED", { ...weekly, signedAt: new Date() }, { status: "expired" }));

    const row = await harness.prisma.subscription.findFirstOrThrow({ where: { accountId: account.accountId } });
    expect(row).toMatchObject({ status: "expired", interval: "week" });
    expect(await isUnlimited(account.accountId)).toBe(false);
  });

  it("retirent l'accès et la semaine du registre au remboursement", async () => {
    const { account, tx } = await subscribedAccount();
    const revokedAt = new Date();

    await notify(notification("REFUND", { ...tx, revokedAt, signedAt: revokedAt }, { status: "revoked" }));

    const row = await harness.prisma.subscription.findFirstOrThrow({
      where: { accountId: account.accountId },
      include: { transactions: true },
    });
    expect(row.status).toBe("expired");
    expect(row.transactions[0]?.revokedAt).toEqual(revokedAt);
    expect(await isUnlimited(account.accountId)).toBe(false);
  });

  it("ignorent un événement plus ancien que le dernier appliqué", async () => {
    // Apple ne promet aucun ordre : l'achat initial arrivé après la coupure
    // du renouvellement ne doit pas rouvrir l'abonnement.
    const { account, tx } = await subscribedAccount();
    await notify(
      notification("DID_CHANGE_RENEWAL_STATUS", { ...tx, signedAt: new Date() }, {
        renewal: { autoRenews: false, gracePeriodEndsAt: null },
      }),
    );

    await notify(notification("SUBSCRIBED", tx, { subtype: "INITIAL_BUY" }));

    const row = await harness.prisma.subscription.findFirstOrThrow({ where: { accountId: account.accountId } });
    expect(row.status).toBe("cancelled");
  });

  it("ne laissent pas un vieux renouvellement rejoué par l'app raccourcir le mois payé", async () => {
    // `Transaction.unfinished` : l'app renvoie, sans statut, une période déjà
    // passée — signée après le dernier événement d'Apple.
    const { account, tx } = await subscribedAccount();
    const renewal = transaction({
      ...tx,
      transactionId: "2000000000000002",
      purchasedAt: tx.expiresAt!,
      expiresAt: new Date(tx.expiresAt!.getTime() + 30 * DAY),
      signedAt: new Date(),
    });
    await notify(notification("DID_RENEW", renewal));

    const old = transaction({
      ...tx,
      transactionId: "2000000000000003",
      purchasedAt: new Date(Date.now() - 40 * DAY),
      expiresAt: new Date(Date.now() - 10 * DAY),
      signedAt: new Date(Date.now() + 1000),
    });
    expect((await purchase(account.authorization, old)).statusCode).toBe(200);

    const row = await harness.prisma.subscription.findFirstOrThrow({ where: { accountId: account.accountId } });
    expect(row.status).toBe("active");
    expect(row.renewsAt).toEqual(renewal.expiresAt);
    expect(await isUnlimited(account.accountId)).toBe(true);
  });

  it("ferment l'illimité d'un abonnement resté « actif » sans nouvelles bien après sa date", async () => {
    // L'`EXPIRED` d'Apple s'est perdu : la ligne dit encore « active ».
    const account = await registerAccount(harness.app);
    await harness.prisma.subscription.create({
      data: {
        accountId: account.accountId,
        provider: "storekit",
        status: "active",
        priceCents: 499,
        renewsAt: new Date(Date.now() - 7 * DAY),
      },
    });

    expect(await isUnlimited(account.accountId)).toBe(false);
  });

  it("retrouvent le compte par l'appAccountToken, sans que l'app ait parlé", async () => {
    // L'app a été tuée juste après le paiement : Apple est le seul à le dire.
    const account = await registerAccount(harness.app);

    await notify(notification("SUBSCRIBED", transaction({ appAccountToken: account.accountId })));

    const row = await harness.prisma.subscription.findFirst({ where: { accountId: account.accountId } });
    expect(row?.status).toBe("active");
  });

  it("acquittent un achat qu'aucun compte ne porte, sans rien écrire", async () => {
    const response = await notify(notification("SUBSCRIBED", transaction()));

    expect(response.statusCode).toBe(200);
    expect(await harness.prisma.subscription.count()).toBe(0);
  });

  it("refusent une notification qu'Apple n'a pas signée", async () => {
    const response = await harness.app.inject({
      method: "POST",
      url: "/v1/webhooks/app-store",
      payload: { signedPayload: "eyJmYWtlIjp0cnVlfQ" },
    });

    expect(response.statusCode).toBe(400);
  });

  it("acquittent la notification de test d'App Store Connect", async () => {
    const response = await notify({ ...notification("TEST", transaction()), transaction: null });

    expect(response.statusCode).toBe(200);
  });
});

describe("la fin du voyage", () => {
  it("n'arrête aucun abonnement, pas même hors d'Apple", async () => {
    // L'illimité court jusqu'à ce qu'on le résilie (Hugo, 03/10/2026) : fermer
    // le voyage n'éteint plus rien.
    const account = await registerAccount(harness.app);
    const memo = await tripOf(account.accountId);
    await purchase(account.authorization, transaction({ appAccountToken: account.accountId }));
    await harness.prisma.subscription.create({
      data: { accountId: account.accountId, provider: "stripe", status: "active", priceCents: 499 },
    });

    const closed = await harness.app.inject({
      method: "PATCH",
      url: `/v1/trips/${memo.id}/settings`,
      headers: { authorization: account.authorization },
      payload: { endDate: new Date(Date.now() - 2 * DAY).toISOString() },
    });
    expect(closed.statusCode).toBe(200);

    const rows = await harness.prisma.subscription.findMany({ where: { accountId: account.accountId } });
    expect(rows.map((row) => row.status)).toEqual(["active", "active"]);
  });

  it("propose de couper le renouvellement sur l'accueil", async () => {
    const account = await registerAccount(harness.app);
    await tripOf(account.accountId, new Date(Date.now() - DAY));
    await purchase(account.authorization, transaction({ appAccountToken: account.accountId }));

    const home = await harness.app.inject({
      method: "GET",
      url: "/v1/home",
      headers: { authorization: account.authorization },
    });

    expect(home.json<{ traveller: { subscriptionOutlivesTrip: boolean } }>().traveller.subscriptionOutlivesTrip).toBe(true);
  });

  it("ne le propose pas tant qu'un voyage court", async () => {
    const account = await registerAccount(harness.app);
    await tripOf(account.accountId);
    await purchase(account.authorization, transaction({ appAccountToken: account.accountId }));

    const home = await harness.app.inject({
      method: "GET",
      url: "/v1/home",
      headers: { authorization: account.authorization },
    });

    expect(home.json<{ traveller: { subscriptionOutlivesTrip: boolean } }>().traveller.subscriptionOutlivesTrip).toBe(false);
  });

  it("garde la raison de la résiliation, mais laisse Apple fermer l'abonnement", async () => {
    const account = await registerAccount(harness.app);
    await purchase(account.authorization, transaction({ appAccountToken: account.accountId }));

    const response = await harness.app.inject({
      method: "POST",
      url: "/v1/profile/subscription/cancel",
      headers: { authorization: account.authorization },
      payload: { reason: "tooExpensive" },
    });

    expect(response.statusCode).toBe(200);
    const row = await harness.prisma.subscription.findFirstOrThrow({ where: { accountId: account.accountId } });
    expect(row).toMatchObject({ status: "active", cancellationReason: "tooExpensive" });
  });
});

describe("le profil, sans abonnement", () => {
  it("propose l'offre du catalogue : 4,99 € par mois, et plus d'étapes offertes", async () => {
    const account = await registerAccount(harness.app);
    const response = await harness.app.inject({
      method: "GET",
      url: "/v1/profile",
      headers: { authorization: account.authorization },
    });

    const body = response.json<ProfileBody>();
    expect(body.subscription).toMatchObject({
      price: 4.99,
      interval: "month",
      weeklyPrice: 4.99,
      isActive: false,
      isUnlimited: false,
    });
    expect(body).not.toHaveProperty("offeredSteps");
    expect(body).not.toHaveProperty("remainingSteps");
  });

  it("ne reprend pas l'ancien tarif d'un abonné de la semaine qui ne l'est plus", async () => {
    const account = await registerAccount(harness.app);
    await harness.prisma.subscription.create({
      data: {
        accountId: account.accountId,
        provider: "storekit",
        status: "expired",
        priceCents: 199,
        interval: "week",
        renewsAt: new Date(Date.now() - 30 * DAY),
      },
    });

    const response = await harness.app.inject({
      method: "GET",
      url: "/v1/profile",
      headers: { authorization: account.authorization },
    });
    expect(response.json<ProfileBody>().subscription).toMatchObject({
      price: 4.99,
      interval: "month",
      isUnlimited: false,
    });
  });
});

describe("l'état Apple, dans nos statuts", () => {
  const now = new Date("2026-10-01T12:00:00Z");
  const tx = transaction({ purchasedAt: new Date("2026-09-28T12:00:00Z") });

  it("garde l'accès pendant le délai de grâce, jusqu'à sa fin", () => {
    const gracePeriodEndsAt = new Date("2026-10-08T12:00:00Z");
    expect(
      storeKitState({
        transaction: tx,
        renewal: { autoRenews: true, gracePeriodEndsAt },
        status: "grace_period",
        previousAutoRenews: true,
        now,
      }),
    ).toEqual({ status: "past_due", renewsAt: gracePeriodEndsAt, autoRenews: true });
  });

  it("ferme l'accès pendant une nouvelle tentative de prélèvement", () => {
    expect(
      storeKitState({ transaction: tx, renewal: null, status: "billing_retry", previousAutoRenews: true, now })
        .status,
    ).toBe("expired");
  });

  it("garde ce qu'on savait du renouvellement quand l'app n'envoie qu'une transaction", () => {
    expect(
      storeKitState({ transaction: tx, renewal: null, status: null, previousAutoRenews: false, now }).status,
    ).toBe("cancelled");
  });
});

describe("le certificat racine d'Apple", () => {
  it("est là où le vérificateur le cherche", () => {
    // Sans lui, chaque achat serait refusé — voir le `COPY backend/certs` du Dockerfile.
    expect(readRootCertificates().length).toBeGreaterThan(0);
  });
});
