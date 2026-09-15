import { afterAll, beforeEach, describe, expect, it } from "vitest";
import { quote as computeQuote } from "../src/services/printPricing.js";
import { createHarness, registerAccount, resetDatabase, type TestHarness } from "./helpers.js";

/**
 * Les **rails d'argent** : l'intention de paiement, le webhook, le registre de
 * la cagnotte. Complémentaire de `orders.test.ts`, qui couvre le tunnel — ce
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

/** Crédite la cagnotte en passant par le webhook, comme la vraie vie. */
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
    walletBalanceCents: 0,
    giftCreditCents: 0,
    topupCreditCents: 0,
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
    const orderId = (await placeOrder(memo.id, renderId)).json<OrderBody>().id;

    const hook = await postWebhook("payment_intent.succeeded", {
      id: "pi_order",
      amount: 10_000,
      metadata: { orderId },
    });
    expect(hook.statusCode).toBe(200);

    const order = await harness.prisma.printOrder.findUniqueOrThrow({ where: { id: orderId } });
    expect(order.status).toBe("submitted");
    expect(order.submittedAt).not.toBeNull();
  });

  it("rejoué, le même webhook ne repose pas la date de commande", async () => {
    const { memo, renderId } = await printableTrip();
    const orderId = (await placeOrder(memo.id, renderId)).json<OrderBody>().id;
    const event = { id: "pi_order", amount: 10_000, metadata: { orderId } };

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
    // l'intention. C'est le second chemin de résolution.
    const hook = await postWebhook("charge.refunded", {
      id: "ch_1",
      payment_intent: intentId,
      amount_refunded: 10_000,
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

describe("recharger la cagnotte", () => {
  it("ouvre une intention sans rien créditer", async () => {
    const response = await harness.app.inject({
      method: "POST",
      url: "/v1/wallet/topup",
      headers: { authorization },
      payload: { amountCents: 2_000 },
    });

    expect(response.statusCode).toBe(201);
    expect(response.json<{ clientSecret: string }>().clientSecret).toMatch(/^pi_fake_/);

    // Le schéma est formel : « une écriture n'existe qu'une fois l'argent
    // réellement mouvementé ». Tant que le webhook n'est pas passé, rien.
    expect(await balance()).toBe(0);
  });

  it("crédite au webhook, et tient le solde et l'écriture ensemble", async () => {
    await creditWallet(2_000);

    expect(await balance()).toBe(2_000);

    const entries = await harness.prisma.walletEntry.findMany({ where: { accountId } });
    expect(entries).toHaveLength(1);
    expect(entries[0]?.kind).toBe("topup");
    // Le solde recopié sur l'écriture : c'est ce qui permet de détecter une
    // dérive sans rejouer tout l'historique.
    expect(entries[0]?.balanceAfterCents).toBe(2_000);
  });

  it("rejoué, le même événement ne crédite pas deux fois", async () => {
    await creditWallet(2_000);
    await creditWallet(2_000);
    await creditWallet(2_000);

    expect(await balance()).toBe(2_000);
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

describe("la cagnotte déduite d'une commande", () => {
  it("couvre tout : la commande part sans passer par Stripe", async () => {
    const { memo, renderId } = await printableTrip();
    await creditWallet(expectedTotal(60, 1) + 5_000);

    const body = (await placeOrder(memo.id, renderId)).json<OrderBody>();

    // Aucun aller-retour de paiement : l'argent était déjà là.
    expect(body.status).toBe("submitted");
    expect(body.payment.paidFromWallet).toBe(true);
    expect(body.payment.clientSecret).toBeUndefined();

    const debit = await harness.prisma.walletEntry.findFirstOrThrow({
      where: { accountId, kind: "order_payment" },
    });
    expect(debit.amountCents).toBe(-expectedTotal(60, 1));
    expect(debit.printOrderId).toBe(body.id);
  });

  it("couvre une partie : elle est débitée, la carte paie le reste", async () => {
    const { memo, renderId } = await printableTrip();
    await creditWallet(3_000);

    const body = (await placeOrder(memo.id, renderId)).json<OrderBody>();

    expect(body.status).toBe("draft");
    expect(body.payment.paidFromWallet).toBe(false);
    // L'intention ne porte que le reste à payer, pas le total du carnet.
    expect(body.payment.amountCents).toBe(expectedTotal(60, 1) - 3_000);

    // La cagnotte est vidée, et le registre le dit.
    expect(await balance()).toBe(0);
    const debit = await harness.prisma.walletEntry.findFirstOrThrow({
      where: { accountId, kind: "order_payment" },
    });
    expect(debit.amountCents).toBe(-3_000);
  });

  it("ne descend jamais sous zéro, même sur deux commandes concurrentes", async () => {
    const { memo, renderId } = await printableTrip();
    // De quoi couvrir **une** commande entière, pas deux.
    await creditWallet(expectedTotal(60, 1));

    const responses = await Promise.all([
      placeOrder(memo.id, renderId),
      placeOrder(memo.id, renderId),
    ]);

    // **Deux dénouements, tous deux corrects**, et lequel survient n'est pas
    // décidable — c'est l'entrelacement du devis et du débit qui tranche :
    //
    //   · la perdante a fait son devis *avant* que la gagnante ne débite. Elle
    //     croit la cagnotte pleine, son débit trouve le solde à zéro, et
    //     `routes/orders.ts` supprime la commande plutôt que de garder une
    //     ligne portant un `walletAppliedCents` que le registre dément → 400 ;
    //   · la perdante a fait son devis *après*. Elle voit zéro, ne débite rien,
    //     et part à la carte pour le total → 201 « draft ».
    //
    // Fixer l'un des deux rend le test vert une fois sur deux : c'est ce qui
    // l'a fait échouer dans les deux sens sur la CI. On vérifie donc ce qui est
    // vrai dans les deux cas.
    const outcomes = responses
      .map((response) => {
        const body = response.json<OrderBody & { error?: string }>();
        return response.statusCode === 201
          ? `201 ${body.status}`
          : `${response.statusCode} ${body.error}`;
      })
      .sort();

    expect([
      ["201 draft", "201 submitted"],
      ["201 submitted", "400 wallet_insufficient"],
    ]).toContainEqual(outcomes);

    // Ce que le verrou garantit vraiment, et dans les deux cas : une seule
    // commande est payée par la cagnotte, une seule écriture la débite, et le
    // solde s'arrête à zéro. Sans lui, les deux liraient le même solde et la
    // cagnotte passerait en négatif.
    expect(outcomes.filter((outcome) => outcome === "201 submitted")).toHaveLength(1);
    expect(await balance()).toBe(0);
    expect(
      await harness.prisma.walletEntry.count({ where: { accountId, kind: "order_payment" } }),
    ).toBe(1);
  });
});
