import { afterAll, beforeEach, describe, expect, it } from "vitest";
import {
  AppStoreVerificationError,
  readRootCertificates,
  type AppStoreNotification,
  type AppStoreTransaction,
  type AppStoreVerifier,
} from "../src/services/appStore.js";
import { storeKitState } from "../src/services/appStoreSubscriptions.js";
import { assertCanRecord } from "../src/services/quota.js";
import { APP_STORE_PRODUCT_IDS } from "../src/services/subscriptionCatalog.js";
import { sweepEndedSubscriptions } from "../src/services/subscriptions.js";
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
    productId: APP_STORE_PRODUCT_IDS.weeklySubscription,
    appAccountToken: null,
    purchasedAt,
    expiresAt: new Date(purchasedAt.getTime() + 7 * DAY),
    revokedAt: null,
    priceCents: 199,
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

/** Un compte qui a raconté ses trois étapes offertes : seul l'abonnement le laisse continuer. */
async function exhaustedAccount() {
  const account = await registerAccount(harness.app);
  await harness.prisma.account.update({
    where: { id: account.accountId },
    data: { remainingSteps: 0 },
  });
  return account;
}

type ProfileBody = {
  subscription: { isActive: boolean; paidThrough: string | null; managedByAppStore: boolean };
};

describe("l'achat depuis l'app", () => {
  it("ouvre l'abonnement, l'inscrit au registre, et le rattache au voyage", async () => {
    const account = await exhaustedAccount();
    const memo = await tripOf(account.accountId);
    await expect(assertCanRecord(harness.prisma, account.accountId)).rejects.toThrow();

    const tx = transaction({ appAccountToken: account.accountId });
    const response = await purchase(account.authorization, tx, memo.id);

    expect(response.statusCode).toBe(200);
    expect(response.json<ProfileBody>().subscription).toMatchObject({
      isActive: true,
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
      priceCents: 199,
      environment: "Sandbox",
    });
    expect(row.transactions).toHaveLength(1);
    expect(row.transactions[0]).toMatchObject({ memoId: memo.id, priceCents: 199 });

    // Le micro s'ouvre dans la seconde, sans attendre la notification d'Apple.
    await expect(assertCanRecord(harness.prisma, account.accountId)).resolves.toBeUndefined();
  });

  it("se rejoue sans inscrire deux fois la même semaine", async () => {
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
    const account = await exhaustedAccount();
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
      expiresAt: new Date(tx.expiresAt!.getTime() + 7 * DAY),
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

  it("gardent la semaine payée quand le renouvellement est coupé dans iOS", async () => {
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

    // Une semaine commencée est une semaine réglée : le micro reste ouvert.
    await expect(assertCanRecord(harness.prisma, account.accountId)).resolves.toBeUndefined();
  });

  it("ferment le micro à l'expiration", async () => {
    const { account, tx } = await subscribedAccount();
    const ended = { ...tx, expiresAt: new Date(Date.now() - 1000), signedAt: new Date() };

    await notify(notification("EXPIRED", ended, { subtype: "VOLUNTARY", status: "expired" }));

    const row = await harness.prisma.subscription.findFirstOrThrow({ where: { accountId: account.accountId } });
    expect(row.status).toBe("expired");
    await expect(assertCanRecord(harness.prisma, account.accountId)).rejects.toThrow();
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
    await expect(assertCanRecord(harness.prisma, account.accountId)).rejects.toThrow();
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

describe("la fin du voyage, avec un abonnement Apple", () => {
  it("n'éteint pas un abonnement qu'Apple continue de prélever", async () => {
    // Le contraire faisait payer quelqu'un dont le micro était fermé.
    const account = await registerAccount(harness.app);
    await tripOf(account.accountId, new Date(Date.now() - DAY));
    await purchase(account.authorization, transaction({ appAccountToken: account.accountId }));

    expect(await sweepEndedSubscriptions(harness.context)).toBe(0);

    const row = await harness.prisma.subscription.findFirstOrThrow({ where: { accountId: account.accountId } });
    expect(row.status).toBe("active");
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
