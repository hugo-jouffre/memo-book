import { afterAll, beforeEach, describe, expect, it } from "vitest";
import { quote as computeQuote } from "../src/services/printPricing.js";
import { createHarness, registerAccount, resetDatabase, type TestHarness } from "./helpers.js";

/**
 * Les **rails d'argent** : l'intention de paiement et le webhook — et ce qui
 * reste de la cagnotte, retirée le 06/10/2026. Complémentaire de `orders.test.ts`, qui couvre le tunnel — ce
 * qu'il affiche, ce qu'il compte, ce qu'il refuse.
 *
 * Ce qui est testé en priorité ici, c'est **le rejeu**. Stripe rejoue ses
 * webhooks jusqu'à obtenir un 2xx, et il en envoie plusieurs pour un même
 * paiement : ce n'est pas un incident, c'est le mode de fonctionnement normal.
 * Un test qui vérifierait seulement « le paiement fait passer en submitted »
 * laisserait passer un double débit.
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

/** Un carnet composé, donc commandable. */
async function printableTrip() {
  const memo = await harness.prisma.memo.create({
    data: {
      ownerAccountId: accountId,
      title: "Rome 2026",
      bookTitle: "Rome et la Dolce Vita",
      accessCode: `PAY${Math.random().toString(36).slice(2, 8).toUpperCase()}`,
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
    currency: string;
  };
};

async function placeOrder(memoId: string, renderId: string, copies = 1) {
  return harness.app.inject({
    method: "POST",
    url: `/v1/memos/${memoId}/orders`,
    headers: { authorization },
    payload: { renderId, copies, shippingSpeed: "standard", shipping: SHIPPING },
  });
}

/**
 * Un webhook tel que `FakePaymentGateway` le lit : le corps brut, sans
 * signature réelle. Vérifier la signature est le travail du SDK Stripe ; ce
 * qu'on teste ici, c'est ce qu'on en fait.
 */
async function postWebhook(type: string, body: Record<string, unknown>, eventId = "evt_1") {
  return harness.app.inject({
    method: "POST",
    url: "/v1/webhooks/stripe",
    headers: { "content-type": "application/json", "stripe-signature": "t=0,v1=fake" },
    payload: JSON.stringify({ id: eventId, type, data: { object: body } }),
  });
}

/**
 * Crédite la cagnotte en passant par le webhook : une recharge ouverte avant
 * le retrait de la cagnotte et payée après.
 */
async function creditWallet(cents: number, eventId = "evt_credit") {
  const response = await postWebhook(
    "payment_intent.succeeded",
    { id: "pi_topup", amount: cents, metadata: { kind: "wallet_topup", accountId } },
    eventId,
  );
  expect(response.statusCode).toBe(200);
}

async function balance(): Promise<number> {
  const account = await harness.prisma.account.findUniqueOrThrow({ where: { id: accountId } });
  return account.walletBalanceCents;
}

/** Ce que le serveur facturera, calculé par la même fonction que lui. */
function expectedTotal(pages: number, copies: number): number {
  return computeQuote({
    bookTitle: "x",
    pageCount: pages,
    copies,
    speed: "standard",
  }).totalCents;
}

describe("payer une commande par carte", () => {
  it("ouvre une intention et laisse la commande en draft", async () => {
    const { memo, renderId } = await printableTrip();

    const response = await placeOrder(memo.id, renderId, 2);
    expect(response.statusCode).toBe(201);

    const body = response.json<OrderBody>();

    // Tant que Stripe n'a pas confirmé, rien n'est parti à l'impression.
    expect(body.status).toBe("draft");
    expect(body.payment.paidFromWallet).toBe(false);
    expect(body.payment.clientSecret).toMatch(/^pi_fake_/);
    expect(body.payment.amountCents).toBe(expectedTotal(60, 2));

    const stored = await harness.prisma.printOrder.findUniqueOrThrow({ where: { id: body.id } });
    expect(stored.stripePaymentIntentId).toBe(body.payment.clientSecret!.split("_secret")[0]);
  });

  it("passe en submitted quand le paiement réussit", async () => {
    const { memo, renderId } = await printableTrip();
    const placed = (await placeOrder(memo.id, renderId)).json<OrderBody>();
    const orderId = placed.id;

    const hook = await postWebhook("payment_intent.succeeded", {
      id: "pi_order",
      amount: placed.payment.amountCents,
      currency: "eur",
      metadata: { orderId },
    });
    expect(hook.statusCode).toBe(200);

    const order = await harness.prisma.printOrder.findUniqueOrThrow({ where: { id: orderId } });
    expect(order.status).toBe("submitted");
    expect(order.submittedAt).not.toBeNull();
  });

  it("rejoué, le même webhook ne repose pas la date de commande", async () => {
    const { memo, renderId } = await printableTrip();
    const placed = (await placeOrder(memo.id, renderId)).json<OrderBody>();
    const orderId = placed.id;
    const event = { id: "pi_order", amount: placed.payment.amountCents, metadata: { orderId } };

    await postWebhook("payment_intent.succeeded", event);
    const first = await harness.prisma.printOrder.findUniqueOrThrow({ where: { id: orderId } });

    // Trois rejeux : Stripe en envoie plus que ça sur une journée.
    await postWebhook("payment_intent.succeeded", event);
    await postWebhook("payment_intent.succeeded", event);
    await postWebhook("payment_intent.succeeded", event);

    const after = await harness.prisma.printOrder.findUniqueOrThrow({ where: { id: orderId } });
    expect(after.status).toBe("submitted");
    // La date est la preuve : réécrite, elle raconterait le dernier rejeu et
    // non le paiement.
    expect(after.submittedAt?.toISOString()).toBe(first.submittedAt?.toISOString());
  });

  it("retrouve la commande par l'intention quand l'événement n'a pas nos métadonnées", async () => {
    const { memo, renderId } = await printableTrip();
    const created = (await placeOrder(memo.id, renderId)).json<OrderBody>();
    const intentId = created.payment.clientSecret!.split("_secret")[0];

    // Un `charge.refunded` ne porte pas `metadata.orderId` : il ne donne que
    // l'intention. C'est le second chemin de résolution. Remboursée **en
    // entier** : c'est ce qui annule — voir `stripeLifecycle.test.ts`.
    const hook = await postWebhook("charge.refunded", {
      id: "ch_1",
      payment_intent: intentId,
      amount_refunded: created.payment.amountCents,
      refunded: true,
    });
    expect(hook.statusCode).toBe(200);

    const order = await harness.prisma.printOrder.findUniqueOrThrow({ where: { id: created.id } });
    expect(order.status).toBe("cancelled");
  });

  it("acquitte un événement qui ne concerne aucune commande", async () => {
    // 200 et non 500 : un 500 ferait rejouer en boucle un événement qui ne
    // nous concerne pas.
    const hook = await postWebhook("payment_intent.succeeded", {
      id: "pi_inconnu",
      amount: 500,
      metadata: {},
    });
    expect(hook.statusCode).toBe(200);
  });

  it("refuse un webhook sans signature", async () => {
    const hook = await harness.app.inject({
      method: "POST",
      url: "/v1/webhooks/stripe",
      headers: { "content-type": "application/json" },
      payload: JSON.stringify({ id: "evt_1", type: "payment_intent.succeeded" }),
    });
    expect(hook.statusCode).toBe(400);
  });
});

describe("la cagnotte retirée (06/10/2026)", () => {
  it("ne sert plus aucune route", async () => {
    for (const [method, url] of [
      ["GET", "/v1/wallet"],
      ["POST", "/v1/wallet/topup"],
      ["POST", "/v1/wallet/debug-entry"],
    ] as const) {
      const response = await harness.app.inject({ method, url, headers: { authorization }, payload: {} });
      expect(response.statusCode, `${method} ${url}`).toBe(404);
    }
  });

  it("ne déduit plus un ancien solde : tout se paie par Stripe", async () => {
    const { memo, renderId } = await printableTrip();
    await creditWallet(expectedTotal(60, 1) + 5_000);

    const body = (await placeOrder(memo.id, renderId)).json<OrderBody>();

    expect(body.status).toBe("draft");
    expect(body.payment.paidFromWallet).toBe(false);
    expect(body.payment.amountCents).toBe(expectedTotal(60, 1));
    // Le solde ancien ne bouge pas : il n'est plus un moyen de paiement.
    expect(await balance()).toBe(expectedTotal(60, 1) + 5_000);
    expect(await harness.prisma.walletEntry.count({ where: { accountId, kind: "order_payment" } })).toBe(0);

    const stored = await harness.prisma.printOrder.findUniqueOrThrow({ where: { id: body.id } });
    expect(stored.walletAppliedCents).toBe(0);
    expect(stored.amountCents).toBe(expectedTotal(60, 1));
  });

  it("inscrit encore au registre une recharge ouverte avant, une seule fois", async () => {
    // L'argent est arrivé chez Stripe : il doit se lire quelque part, et le
    // journal le signale au support pour remboursement.
    await creditWallet(2_000);
    await creditWallet(2_000);
    await creditWallet(2_000);

    expect(await balance()).toBe(2_000);
    expect(await harness.prisma.walletEntry.count({ where: { accountId } })).toBe(1);
  });
});
