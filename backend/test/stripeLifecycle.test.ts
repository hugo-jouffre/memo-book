import { afterAll, beforeEach, describe, expect, it } from "vitest";
import { assertApiPaymentsConfigured, loadEnv } from "../src/env.js";
import { releaseAbandonedOrders } from "../src/services/orderPayments.js";
import { FakePaymentGateway } from "../src/services/payments.js";
import { writeLedgerEntry } from "../src/services/walletLedger.js";
import { createHarness, registerAccount, resetDatabase, type TestHarness } from "./helpers.js";

/**
 * **Ce qui arrive à l'argent après la création d'une commande** (01/10/2026) :
 * reprise du paiement, abandon, ménage, remboursements, cartes du compte. Le
 * pendant de `payments.test.ts`, qui couvre le chemin heureux.
 *
 * Le fil rouge : **la part de cagnotte réservée revient toujours, et une seule
 * fois**, quel que soit le chemin qui ferme la commande.
 */

let harness: TestHarness;
let authorization: string;
let accountId: string;

beforeEach(async () => {
  harness ??= await createHarness();
  await resetDatabase(harness.prisma);
  ({ authorization, accountId } = await registerAccount(harness.app));
});

afterAll(async () => {
  await harness?.close();
});

const fake = () => harness.context.payments as FakePaymentGateway;

/** La version d'API que pin le SDK iOS (`STPAPIClient.apiVersion`). */
const STRIPE_IOS_API_VERSION = "2020-08-27";

const SHIPPING = {
  name: "Clara Martin",
  line1: "12 rue des Lilas",
  postalCode: "44000",
  city: "Nantes",
  country: "FR",
};

type OrderBody = {
  id: string;
  status: string;
  payment: {
    paidFromWallet: boolean;
    clientSecret?: string;
    amountCents: number;
    customerId?: string | null;
    ephemeralKeySecret?: string | null;
    applePayMerchantId?: string | null;
  } | null;
};

async function printableTrip() {
  const memo = await harness.prisma.memo.create({
    data: {
      ownerAccountId: accountId,
      title: "Rome 2026",
      bookTitle: "Rome et la Dolce Vita",
      accessCode: `LIF${Math.random().toString(36).slice(2, 8).toUpperCase()}`,
      stage: "past",
      pageCount: 58,
      targetPageCount: 60,
      isPrintable: true,
      renders: { create: [{ status: "ready", pdfUrl: "https://pdf.example.test/rome.pdf" }] },
    },
    include: { renders: true },
  });
  return { memo, renderId: memo.renders[0]!.id };
}

/** De l'argent sur la cagnotte, pour que la commande en réserve une part. */
async function fund(cents: number) {
  await writeLedgerEntry(harness.prisma, { accountId, amountCents: cents, kind: "topup", label: "Test" });
}

async function balance() {
  const account = await harness.prisma.account.findUniqueOrThrow({ where: { id: accountId } });
  return account.walletBalanceCents;
}

async function placeOrder(): Promise<OrderBody> {
  const { memo, renderId } = await printableTrip();
  const response = await harness.app.inject({
    method: "POST",
    url: `/v1/memos/${memo.id}/orders`,
    headers: { authorization },
    payload: {
      renderId,
      copies: 1,
      shippingSpeed: "standard",
      shipping: SHIPPING,
      stripeApiVersion: STRIPE_IOS_API_VERSION,
    },
  });
  expect(response.statusCode).toBe(201);
  return response.json<OrderBody>();
}

const intentOf = (order: OrderBody) => order.payment!.clientSecret!.split("_secret")[0]!;

async function postWebhook(type: string, body: Record<string, unknown>, eventId = "evt_1") {
  return harness.app.inject({
    method: "POST",
    url: "/v1/webhooks/stripe",
    headers: { "content-type": "application/json", "stripe-signature": "t=0,v1=fake" },
    payload: JSON.stringify({ id: eventId, type, data: { object: body } }),
  });
}

async function statusOf(orderId: string) {
  return (await harness.prisma.printOrder.findUniqueOrThrow({ where: { id: orderId } })).status;
}

describe("une commande pas encore payée", () => {
  it("se reprend sans nouvelle commande ni second débit de cagnotte", async () => {
    // « Payer » après une feuille refermée créait une nouvelle commande, et
    // débitait la cagnotte une seconde fois.
    await fund(3_000);
    const order = await placeOrder();
    expect(await balance()).toBe(0);

    const resumed = await harness.app.inject({
      method: "POST",
      url: `/v1/orders/${order.id}/payment`,
      headers: { authorization },
    });

    expect(resumed.statusCode).toBe(200);
    expect(resumed.json<OrderBody>().payment?.clientSecret).toBe(order.payment?.clientSecret);
    expect(await harness.prisma.printOrder.count()).toBe(1);
    expect(await balance()).toBe(0);
  });

  it("rend sa réservation quand l'app l'abandonne, une seule fois", async () => {
    await fund(3_000);
    const order = await placeOrder();

    const cancel = () =>
      harness.app.inject({ method: "POST", url: `/v1/orders/${order.id}/cancel`, headers: { authorization } });

    expect((await cancel()).statusCode).toBe(200);
    expect((await cancel()).statusCode).toBe(200);

    expect(await statusOf(order.id)).toBe("cancelled");
    expect(await balance()).toBe(3_000);
    expect((await fake().retrieveIntent(intentOf(order))).status).toBe("canceled");
  });

  it("rend sa réservation quand Stripe annule l'intention", async () => {
    await fund(3_000);
    const order = await placeOrder();

    const hook = await postWebhook("payment_intent.canceled", {
      id: intentOf(order),
      metadata: { orderId: order.id },
    });

    expect(hook.statusCode).toBe(200);
    expect(await statusOf(order.id)).toBe("cancelled");
    expect(await balance()).toBe(3_000);
  });

  it("rend sa réservation si le paiement ne peut pas s'ouvrir", async () => {
    await fund(3_000);
    const gateway = fake();
    const original = gateway.createIntent.bind(gateway);
    gateway.createIntent = async () => {
      throw new Error("Stripe injoignable");
    };

    try {
      const { memo, renderId } = await printableTrip();
      const response = await harness.app.inject({
        method: "POST",
        url: `/v1/memos/${memo.id}/orders`,
        headers: { authorization },
        payload: { renderId, copies: 1, shippingSpeed: "standard", shipping: SHIPPING },
      });
      expect(response.statusCode).toBe(500);
    } finally {
      gateway.createIntent = original;
    }

    const [order] = await harness.prisma.printOrder.findMany();
    expect(order?.status).toBe("cancelled");
    expect(await balance()).toBe(3_000);
  });

  it("ne s'abandonne plus une fois payée", async () => {
    await fund(3_000);
    const order = await placeOrder();
    fake().settle(intentOf(order), "succeeded");

    const cancel = await harness.app.inject({
      method: "POST",
      url: `/v1/orders/${order.id}/cancel`,
      headers: { authorization },
    });

    expect(cancel.statusCode).toBe(409);
    expect(await statusOf(order.id)).toBe("draft");
    expect(await balance()).toBe(0);
  });

  it("se ferme au bout de 24 h, et pas avant", async () => {
    await fund(6_000);
    const old = await placeOrder();
    await harness.prisma.printOrder.update({
      where: { id: old.id },
      data: { createdAt: new Date(Date.now() - 25 * 3_600_000) },
    });
    const recent = await placeOrder();

    expect(await releaseAbandonedOrders(harness.context)).toBe(1);
    expect(await statusOf(old.id)).toBe("cancelled");
    expect(await statusOf(recent.id)).toBe("draft");
  });

  it("expirée, ne se reprend plus", async () => {
    const order = await placeOrder();
    fake().settle(intentOf(order), "canceled");

    const resumed = await harness.app.inject({
      method: "POST",
      url: `/v1/orders/${order.id}/payment`,
      headers: { authorization },
    });

    expect(resumed.statusCode).toBe(409);
    expect(resumed.json<{ error: string }>().error).toBe("order_expired");
    expect(await statusOf(order.id)).toBe("cancelled");
  });
});

describe("le paiement reçu", () => {
  it("laisse en brouillon un montant inattendu", async () => {
    const order = await placeOrder();

    await postWebhook("payment_intent.succeeded", {
      id: intentOf(order),
      amount: 1,
      currency: "eur",
      metadata: { orderId: order.id },
    });

    expect(await statusOf(order.id)).toBe("draft");
  });
});

describe("les remboursements", () => {
  async function paidOrder() {
    await fund(3_000);
    const order = await placeOrder();
    await postWebhook(
      "payment_intent.succeeded",
      { id: intentOf(order), amount: order.payment!.amountCents, metadata: { orderId: order.id } },
      "evt_paid",
    );
    expect(await statusOf(order.id)).toBe("submitted");
    return order;
  }

  it("inscrit un remboursement partiel sans annuler la commande", async () => {
    const order = await paidOrder();

    await postWebhook(
      "charge.refunded",
      { id: "ch_1", payment_intent: intentOf(order), amount_refunded: 500, refunded: false },
      "evt_refund",
    );

    const stored = await harness.prisma.printOrder.findUniqueOrThrow({ where: { id: order.id } });
    expect(stored.status).toBe("submitted");
    expect(stored.refundedCents).toBe(500);
    expect(await balance()).toBe(0);
  });

  it("annule et rend la cagnotte sur un remboursement total, une seule fois", async () => {
    const order = await paidOrder();
    const full = {
      id: "ch_1",
      payment_intent: intentOf(order),
      amount_refunded: order.payment!.amountCents,
      refunded: true,
    };

    await postWebhook("charge.refunded", full, "evt_refund_1");
    await postWebhook("charge.refunded", full, "evt_refund_2");

    expect(await statusOf(order.id)).toBe("cancelled");
    expect(await balance()).toBe(3_000);
  });

  it("ne touche pas au statut d'une commande déjà expédiée", async () => {
    const order = await paidOrder();
    await harness.prisma.printOrder.update({ where: { id: order.id }, data: { status: "shipped" } });

    await postWebhook(
      "charge.refunded",
      { id: "ch_1", payment_intent: intentOf(order), amount_refunded: order.payment!.amountCents, refunded: true },
      "evt_refund",
    );

    expect(await statusOf(order.id)).toBe("shipped");
    expect(await balance()).toBe(0);
  });

  it("reprend une recharge remboursée, plafonnée à ce qui reste", async () => {
    const topup = { id: "pi_topup_1", amount: 2_000, metadata: { kind: "wallet_topup", accountId } };
    await postWebhook("payment_intent.succeeded", topup, "evt_topup");
    expect(await balance()).toBe(2_000);

    // 15 € déjà dépensés dans un carnet.
    await writeLedgerEntry(harness.prisma, { accountId, amountCents: -1_500, kind: "order_payment" });

    await postWebhook(
      "charge.refunded",
      { id: "ch_t", payment_intent: "pi_topup_1", amount_refunded: 2_000, refunded: true },
      "evt_topup_refund",
    );

    expect(await balance()).toBe(0);
  });

  it("ne crédite qu'une fois une recharge vue par deux événements", async () => {
    const topup = { id: "pi_topup_2", amount: 2_000, metadata: { kind: "wallet_topup", accountId } };
    await postWebhook("payment_intent.succeeded", topup, "evt_a");
    await postWebhook("payment_intent.succeeded", topup, "evt_b");

    expect(await balance()).toBe(2_000);
  });
});

describe("les cartes du compte", () => {
  it("passent par le client Stripe du compte, dans la feuille", async () => {
    const order = await placeOrder();

    expect(order.payment?.customerId).toMatch(/^cus_fake_/);
    expect(order.payment?.ephemeralKeySecret).toMatch(/^ek_test_fake_/);
  });

  it("ne proposent pas Apple Pay tant que l'identifiant marchand n'est pas posé", async () => {
    // Sans certificat Apple Pay chez Stripe, le bouton échouerait après Face ID.
    const order = await placeOrder();

    expect(order.payment?.applePayMerchantId ?? null).toBeNull();
  });

  it("restent hors de la feuille d'une app qui ne dit pas sa version de SDK", async () => {
    // Une clé éphémère n'est lisible que dans la version d'API du SDK : sans
    // elle, pas de clé, et la feuille s'ouvre quand même.
    const { memo, renderId } = await printableTrip();
    const response = await harness.app.inject({
      method: "POST",
      url: `/v1/memos/${memo.id}/orders`,
      headers: { authorization },
      payload: { renderId, copies: 1, shippingSpeed: "standard", shipping: SHIPPING },
    });

    expect(response.json<OrderBody>().payment?.ephemeralKeySecret).toBeNull();
    expect(response.json<OrderBody>().payment?.clientSecret).toMatch(/^pi_fake_/);
  });

  it("se gèrent par Stripe depuis le profil", async () => {
    const session = await harness.app.inject({
      method: "POST",
      url: "/v1/payments/ephemeral-key",
      headers: { authorization },
      payload: { stripeApiVersion: STRIPE_IOS_API_VERSION },
    });
    const setup = await harness.app.inject({
      method: "POST",
      url: "/v1/payments/setup-intent",
      headers: { authorization },
    });

    expect(session.statusCode).toBe(200);
    expect(session.json<{ ephemeralKeySecret: string }>().ephemeralKeySecret).toMatch(/^ek_test_fake_/);
    expect(setup.json<{ clientSecret: string }>().clientSecret).toMatch(/^seti_fake_/);
  });

  it("ignorent l'identifiant de carte qu'envoyait l'app", async () => {
    // Il venait d'une carte fabriquée par l'app : le serveur répondait 404
    // (T225). Une version qui l'envoie encore doit pouvoir commander.
    const { memo, renderId } = await printableTrip();
    const response = await harness.app.inject({
      method: "POST",
      url: `/v1/memos/${memo.id}/orders`,
      headers: { authorization },
      payload: {
        renderId,
        copies: 1,
        shippingSpeed: "standard",
        shipping: SHIPPING,
        paymentCardId: "4F2C1E9A-7B3D-4C55-9E21-0A6B8D3F1C77",
      },
    });

    expect(response.statusCode).toBe(201);
  });
});

describe("la configuration", () => {
  it("refuse tout webhook non signé hors de la suite de tests", () => {
    expect(() => new FakePaymentGateway(false).verifyEvent(Buffer.from("{}"))).toThrow(
      /STRIPE_SECRET_KEY/,
    );
  });

  it("refuse de démarrer en production sans clé secrète", () => {
    expect(() => loadEnv({ NODE_ENV: "production", DATABASE_URL: "postgresql://x" })).toThrow(
      /STRIPE_SECRET_KEY/,
    );
  });

  it("refuse une API de production sans clé publique ni secret de webhook", () => {
    const env = loadEnv({ NODE_ENV: "production", DATABASE_URL: "postgresql://x", STRIPE_SECRET_KEY: "sk_test_x" });
    expect(() => assertApiPaymentsConfigured(env)).toThrow(/STRIPE_PUBLISHABLE_KEY, STRIPE_WEBHOOK_SECRET/);
  });
});
