import { afterAll, beforeAll, beforeEach, describe, expect, it } from "vitest";
import { billablePageCount, bookPriceCents } from "../src/lib/pricing.js";
import {
  createHarness,
  registerAccount,
  resetDatabase,
  type TestHarness,
} from "./helpers.js";

/**
 * L'encaissement d'une commande, et surtout ce qui le rend sûr : **le rejeu**.
 *
 * Stripe rejoue ses webhooks jusqu'à obtenir un 2xx, et il en envoie plusieurs
 * pour un même paiement. Ce n'est pas un incident à traiter, c'est le mode de
 * fonctionnement normal — donc la propriété à tester en priorité. Un test qui
 * vérifierait seulement « le paiement fait passer en submitted » laisserait
 * passer un double débit.
 */

let harness: TestHarness;
let authorization: string;
let accountId: string;

beforeAll(async () => {
  harness = await createHarness();
});

afterAll(async () => {
  await harness.close();
});

beforeEach(async () => {
  await resetDatabase(harness.prisma);
  ({ authorization, accountId } = await registerAccount(harness.app));
});

/** Un carnet avec un rendu prêt : le strict nécessaire pour commander. */
async function readyMemo() {
  const created = await harness.app.inject({
    method: "POST",
    url: "/v1/memos",
    headers: { authorization },
    payload: { title: "Rome 2026", authors: "Clara", theme: "voyage" },
  });
  expect(created.statusCode).toBe(201);
  const memoId = created.json<{ id: string }>().id;

  // Le rendu est posé directement : cette suite teste l'argent, pas le
  // pipeline de composition, qui a déjà le sien.
  const render = await harness.prisma.render.create({
    data: {
      memoId,
      status: "ready",
      pdfUrl: "https://pdf.example.test/rome.pdf",
    },
  });

  const memo = await harness.prisma.memo.findUniqueOrThrow({ where: { id: memoId } });
  return { memoId, renderId: render.id, memo };
}

const SHIPPING = {
  name: "Clara Martin",
  line1: "12 rue des Lilas",
  postalCode: "44000",
  city: "Nantes",
  country: "FR",
};

async function placeOrder(memoId: string, renderId: string, copies = 1) {
  return harness.app.inject({
    method: "POST",
    url: `/v1/memos/${memoId}/orders`,
    headers: { authorization },
    payload: { renderId, copies, shipping: SHIPPING },
  });
}

/**
 * Un webhook tel que `FakePaymentGateway` le lit : le corps brut, sans
 * signature réelle. La vérification de signature est le travail du SDK Stripe,
 * pas le nôtre ; ce qu'on teste ici, c'est ce qu'on en fait.
 */
async function postWebhook(type: string, body: Record<string, unknown>) {
  return harness.app.inject({
    method: "POST",
    url: "/v1/webhooks/stripe",
    headers: { "content-type": "application/json", "stripe-signature": "t=0,v1=fake" },
    payload: JSON.stringify({ id: `evt_${type}_1`, type, data: { object: body } }),
  });
}

describe("commander et payer", () => {
  it("ouvre une intention de paiement et laisse la commande en draft", async () => {
    const { memoId, renderId, memo } = await readyMemo();

    const response = await placeOrder(memoId, renderId, 2);
    expect(response.statusCode).toBe(201);

    const body = response.json<{
      id: string;
      status: string;
      payment: { clientSecret: string; amountCents: number; currency: string };
    }>();

    // Tant que Stripe n'a pas confirmé, rien n'est parti à l'impression.
    expect(body.status).toBe("draft");
    expect(body.payment.clientSecret).toMatch(/^pi_fake_/);
    expect(body.payment.currency).toBe("eur");

    // Le montant débité est **exactement** celui qu'affiche la cagnotte.
    const expected = bookPriceCents(billablePageCount(memo), 2);
    expect(body.payment.amountCents).toBe(expected);

    const stored = await harness.prisma.printOrder.findUniqueOrThrow({
      where: { id: body.id },
    });
    expect(stored.amountCents).toBe(expected);
    expect(stored.stripePaymentIntentId).toBe(body.payment.clientSecret.split("_secret")[0]);
  });

  it("le prix facturé suit le prix estimé, au centime près", async () => {
    const { memoId, renderId } = await readyMemo();

    const wallet = await harness.app.inject({
      method: "GET",
      url: `/v1/wallet?tripId=${memoId}`,
      headers: { authorization },
    });
    const estimate = wallet.json<{ estimate: { cost: number } }>().estimate;

    const order = await placeOrder(memoId, renderId, 1);
    const charged = order.json<{ payment: { amountCents: number } }>().payment.amountCents;

    expect(charged).toBe(Math.round(estimate.cost * 100));
  });

  it("fait passer la commande en submitted quand le paiement réussit", async () => {
    const { memoId, renderId } = await readyMemo();
    const orderId = (await placeOrder(memoId, renderId)).json<{ id: string }>().id;

    const hook = await postWebhook("payment_intent.succeeded", {
      id: "pi_test_1",
      amount: 10788,
      metadata: { orderId },
    });
    expect(hook.statusCode).toBe(200);

    const order = await harness.prisma.printOrder.findUniqueOrThrow({
      where: { id: orderId },
    });
    expect(order.status).toBe("submitted");
    expect(order.submittedAt).not.toBeNull();
  });

  it("rejoué, le même webhook ne repose pas la date de commande", async () => {
    const { memoId, renderId } = await readyMemo();
    const orderId = (await placeOrder(memoId, renderId)).json<{ id: string }>().id;

    const event = { id: "pi_test_1", amount: 10788, metadata: { orderId } };

    await postWebhook("payment_intent.succeeded", event);
    const first = await harness.prisma.printOrder.findUniqueOrThrow({
      where: { id: orderId },
    });

    // Trois rejeux de suite : Stripe en envoie plus que ça sur une journée.
    await postWebhook("payment_intent.succeeded", event);
    await postWebhook("payment_intent.succeeded", event);
    await postWebhook("payment_intent.succeeded", event);

    const after = await harness.prisma.printOrder.findUniqueOrThrow({
      where: { id: orderId },
    });

    expect(after.status).toBe("submitted");
    // La date est la preuve : réécrite, elle raconterait la date du dernier
    // rejeu et non celle du paiement.
    expect(after.submittedAt?.toISOString()).toBe(first.submittedAt?.toISOString());
  });

  it("retrouve la commande par l'intention quand l'événement n'a pas nos métadonnées", async () => {
    const { memoId, renderId } = await readyMemo();
    const created = (await placeOrder(memoId, renderId)).json<{
      id: string;
      payment: { clientSecret: string };
    }>();
    const intentId = created.payment.clientSecret.split("_secret")[0];

    // Un `charge.refunded` ne porte pas `metadata.orderId` : il ne donne que
    // l'intention. C'est le second chemin de résolution.
    const hook = await postWebhook("charge.refunded", {
      id: "ch_test_1",
      payment_intent: intentId,
      amount_refunded: 10788,
    });
    expect(hook.statusCode).toBe(200);

    const order = await harness.prisma.printOrder.findUniqueOrThrow({
      where: { id: created.id },
    });
    expect(order.status).toBe("cancelled");
  });

  it("acquitte sans rien casser un événement qui ne concerne aucune commande", async () => {
    const hook = await postWebhook("payment_intent.succeeded", {
      id: "pi_inconnu",
      amount: 500,
      metadata: {},
    });

    // 200 et non 500 : un 500 ferait rejouer en boucle un événement qui ne
    // nous concerne pas.
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

describe("recharger la cagnotte", () => {
  /** Le corps d'un `payment_intent.succeeded` de recharge. */
  function topupEvent(cents: number) {
    return {
      id: "pi_topup_1",
      amount: cents,
      metadata: { kind: "wallet_topup", accountId },
    };
  }

  async function balance(): Promise<number> {
    const account = await harness.prisma.account.findUniqueOrThrow({
      where: { id: accountId },
    });
    return account.walletBalanceCents;
  }

  it("ouvre une intention sans rien créditer", async () => {
    const response = await harness.app.inject({
      method: "POST",
      url: "/v1/wallet/topup",
      headers: { authorization },
      payload: { amountCents: 2000 },
    });

    expect(response.statusCode).toBe(201);
    expect(response.json<{ clientSecret: string }>().clientSecret).toMatch(/^pi_fake_/);

    // Le schéma est formel : « une écriture n'existe qu'une fois l'argent
    // réellement mouvementé ». Tant que le webhook n'est pas passé, rien.
    expect(await balance()).toBe(0);
  });

  it("crédite au webhook, et tient le solde et l'écriture ensemble", async () => {
    await postWebhook("payment_intent.succeeded", topupEvent(2000));

    expect(await balance()).toBe(2000);

    const entries = await harness.prisma.walletEntry.findMany({ where: { accountId } });
    expect(entries).toHaveLength(1);
    expect(entries[0]?.kind).toBe("topup");
    expect(entries[0]?.amountCents).toBe(2000);
    // Le solde recopié sur l'écriture : c'est ce qui permet de détecter une
    // dérive sans rejouer tout l'historique.
    expect(entries[0]?.balanceAfterCents).toBe(2000);
  });

  it("rejoué, le même événement ne crédite pas deux fois", async () => {
    const event = topupEvent(2000);

    await postWebhook("payment_intent.succeeded", event);
    await postWebhook("payment_intent.succeeded", event);
    await postWebhook("payment_intent.succeeded", event);

    expect(await balance()).toBe(2000);
    expect(await harness.prisma.walletEntry.count({ where: { accountId } })).toBe(1);
  });

  it("refuse une recharge sous le plancher", async () => {
    const response = await harness.app.inject({
      method: "POST",
      url: "/v1/wallet/topup",
      headers: { authorization },
      payload: { amountCents: 100 },
    });

    expect(response.statusCode).toBe(400);
  });
});

describe("payer un carnet avec la cagnotte", () => {
  async function credit(cents: number) {
    await postWebhook("payment_intent.succeeded", {
      id: "pi_credit",
      amount: cents,
      metadata: { kind: "wallet_topup", accountId },
    });
  }

  it("débite la cagnotte et passe la commande en submitted, sans Stripe", async () => {
    const { memoId, renderId, memo } = await readyMemo();
    const price = bookPriceCents(billablePageCount(memo), 1);
    await credit(price + 1000);

    const response = await harness.app.inject({
      method: "POST",
      url: `/v1/memos/${memoId}/orders`,
      headers: { authorization },
      payload: { renderId, copies: 1, payWithWallet: true, shipping: SHIPPING },
    });

    expect(response.statusCode).toBe(201);
    const body = response.json<{
      id: string;
      status: string;
      payment: { paidFromWallet: boolean; clientSecret?: string };
    }>();

    // Aucun aller-retour de paiement : l'argent était déjà là.
    expect(body.status).toBe("submitted");
    expect(body.payment.paidFromWallet).toBe(true);
    expect(body.payment.clientSecret).toBeUndefined();

    const account = await harness.prisma.account.findUniqueOrThrow({
      where: { id: accountId },
    });
    expect(account.walletBalanceCents).toBe(1000);

    const debit = await harness.prisma.walletEntry.findFirstOrThrow({
      where: { accountId, kind: "order_payment" },
    });
    expect(debit.amountCents).toBe(-price);
    expect(debit.printOrderId).toBe(body.id);
  });

  it("refuse quand le solde ne suffit pas, et ne bouge rien", async () => {
    const { memoId, renderId } = await readyMemo();
    await credit(1000);

    const response = await harness.app.inject({
      method: "POST",
      url: `/v1/memos/${memoId}/orders`,
      headers: { authorization },
      payload: { renderId, copies: 1, payWithWallet: true, shipping: SHIPPING },
    });

    expect(response.statusCode).toBe(400);
    expect(response.json<{ error: string }>().error).toBe("wallet_insufficient");

    const account = await harness.prisma.account.findUniqueOrThrow({
      where: { id: accountId },
    });
    expect(account.walletBalanceCents).toBe(1000);
    expect(
      await harness.prisma.walletEntry.count({ where: { accountId, kind: "order_payment" } }),
    ).toBe(0);
  });

  it("ne descend jamais sous zéro, même sur deux débits concurrents", async () => {
    const { memoId, renderId, memo } = await readyMemo();
    const price = bookPriceCents(billablePageCount(memo), 1);
    // De quoi payer **une** commande, pas deux.
    await credit(price);

    const order = () =>
      harness.app.inject({
        method: "POST",
        url: `/v1/memos/${memoId}/orders`,
        headers: { authorization },
        payload: { renderId, copies: 1, payWithWallet: true, shipping: SHIPPING },
      });

    const [a, b] = await Promise.all([order(), order()]);
    const codes = [a.statusCode, b.statusCode].sort();

    // L'une passe, l'autre est refusée : c'est le verrou de ligne qui les a
    // rangées. Sans lui, les deux liraient le même solde et passeraient.
    expect(codes).toEqual([201, 400]);

    const account = await harness.prisma.account.findUniqueOrThrow({
      where: { id: accountId },
    });
    expect(account.walletBalanceCents).toBe(0);
  });
});
