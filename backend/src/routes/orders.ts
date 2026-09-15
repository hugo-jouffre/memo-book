import type { FastifyInstance } from "fastify";
import { z } from "zod";
import type { AppContext } from "../context.js";
import { HttpError } from "../lib/httpError.js";
import { billablePageCount, bookPriceCents } from "../lib/pricing.js";
import { accountIdOf } from "../plugins/auth.js";
import { PAYMENT_KIND, ensureStripeCustomer } from "../services/billing.js";
import { visibleToAccount } from "../services/memoOwnership.js";
import { writeLedgerEntry } from "../services/walletLedger.js";
import { loadVisibleMemo } from "./memos.js";
import { serializePrintOrder } from "./serializers.js";

const memoIdParams = z.object({ id: z.string().uuid() });
const orderIdParams = z.object({ id: z.string().uuid() });

const createOrderBody = z.object({
  /**
   * Le rendu à imprimer. Explicite, jamais « le dernier en date » : entre la
   * prévisualisation et la commande, l'utilisateur a pu ajouter une étape, et
   * il doit recevoir le carnet qu'il a vu.
   */
  renderId: z.string().uuid(),
  copies: z.number().int().min(1).max(20).default(1),
  /**
   * Payer avec la cagnotte plutôt qu'avec une carte.
   *
   * Aucun appel à Stripe dans ce cas : l'argent y est déjà. La commande passe
   * directement en `submitted`, et c'est une écriture de registre — pas un
   * webhook — qui en fait foi.
   *
   * ⚠️ La cagnotte ne finance **que du physique**. Il n'y a volontairement pas
   * d'équivalent pour l'abonnement : du crédit acheté par Stripe qui
   * déverrouillerait une fonctionnalité numérique contournerait l'achat
   * intégré d'Apple.
   */
  payWithWallet: z.boolean().default(false),
  shipping: z.object({
    name: z.string().min(1).max(200),
    line1: z.string().min(1).max(200),
    line2: z.string().max(200).optional(),
    postalCode: z.string().min(1).max(20),
    city: z.string().min(1).max(120),
    /** Code ISO 3166-1 alpha-2, comme les cartes du gabarit. */
    country: z.string().length(2).toUpperCase(),
  }),
});

export function registerOrderRoutes(app: FastifyInstance, context: AppContext): void {
  /**
   * Commande d'un carnet imprimé, à partir d'un rendu déjà prévisualisé.
   *
   * **Ouverte aux co-voyageurs autant qu'au propriétaire** : chacun commande
   * son exemplaire du carnet qu'ils ont écrit ensemble. La commande retient
   * donc qui l'a passée — c'est ce qui dira quelle cagnotte débiter, chacun
   * ayant la sienne.
   *
   * La commande est créée en `draft`, **et elle y reste** jusqu'à ce que le
   * webhook Stripe confirme l'encaissement. Cette route ne fait que deux
   * choses : figer ce qui est commandé, et ouvrir une intention de paiement.
   * C'est `POST /v1/webhooks/stripe` qui fait passer en `submitted`, et lui
   * seul — l'app peut être tuée entre le paiement et son retour à l'écran, le
   * webhook non.
   */
  app.post("/v1/memos/:id/orders", async (request, reply) => {
    const { id: memoId } = memoIdParams.parse(request.params);
    const memo = await loadVisibleMemo(context, request, memoId);

    const body = createOrderBody.parse(request.body ?? {});

    const render = await context.prisma.render.findFirst({
      where: { id: body.renderId, memoId },
    });

    if (!render) {
      throw HttpError.notFound("Ce rendu n'appartient pas à ce carnet.");
    }

    if (render.status !== "ready" || !render.pdfUrl) {
      throw HttpError.badRequest(
        "Ce carnet n'est pas encore généré. Prévisualise-le avant de le commander.",
        "render_not_ready",
      );
    }

    // Le montant est figé sur la commande au même titre que le rendu : ajouter
    // une étape demain ne change pas ce qui a été payé. Et il sort de la même
    // fonction que l'estimation affichée sur la carte de cagnotte — c'est ce
    // qui garantit que l'utilisateur est débité du chiffre qu'il a lu.
    const pageCount = billablePageCount(memo);
    const accountId = accountIdOf(request);
    const amountCents = bookPriceCents(pageCount, body.copies);

    const order = await context.prisma.printOrder.create({
      data: {
        memoId,
        renderId: render.id,
        orderedByAccountId: accountId,
        copies: body.copies,
        pageCount,
        coverImageUrl: memo.coverPhotoUrl,
        amountCents,
        shippingName: body.shipping.name,
        shippingLine1: body.shipping.line1,
        shippingLine2: body.shipping.line2 ?? null,
        shippingPostalCode: body.shipping.postalCode,
        shippingCity: body.shipping.city,
        shippingCountry: body.shipping.country,
      },
    });

    // --- Payée par la cagnotte : rien ne sort chez Stripe ------------------
    if (body.payWithWallet) {
      const debit = await writeLedgerEntry(context.prisma, {
        accountId,
        amountCents: -amountCents,
        kind: "order_payment",
        label: `Carnet « ${memo.title} »`,
        printOrderId: order.id,
      });

      if (debit.outcome === "insufficient") {
        // La commande reste en `draft` : elle est reprenable à la carte, et
        // l'app sait exactement ce qui manque pour la payer autrement.
        throw HttpError.badRequest(
          `Il manque ${(debit.missingCents / 100).toFixed(2)} € sur ta cagnotte.`,
          "wallet_insufficient",
        );
      }

      // Pas de webhook à attendre : le débit **est** l'encaissement.
      const paid = await context.prisma.printOrder.update({
        where: { id: order.id },
        data: { status: "submitted", submittedAt: new Date() },
      });

      context.logger.info(
        { orderId: order.id, memoId, amountCents, paidFrom: "wallet" },
        "Commande payée par la cagnotte",
      );

      return reply.code(201).send({
        ...serializePrintOrder(paid),
        payment: { paidFromWallet: true, amountCents, currency: "eur" },
      });
    }

    // --- Payée par carte : Stripe prend la main -----------------------------
    //
    // L'intention est créée **après** la commande, pas avant : sa clé
    // d'idempotence est l'identifiant de la commande, et il faut donc que la
    // commande existe. Un échec ici laisse une commande en `draft` sans
    // paiement — c'est le bon état à laisser derrière soi, l'app la reprend.
    const customerId = await ensureStripeCustomer(context, accountId);

    const intent = await context.payments.createIntent({
      idempotencyKey: `order:${order.id}`,
      amountCents,
      currency: "eur",
      customerId,
      metadata: {
        kind: PAYMENT_KIND.bookOrder,
        orderId: order.id,
        memoId,
        renderId: render.id,
        accountId,
      },
    });

    await context.prisma.printOrder.update({
      where: { id: order.id },
      data: { stripePaymentIntentId: intent.intentId },
    });

    context.logger.info(
      {
        orderId: order.id,
        memoId,
        renderId: render.id,
        copies: order.copies,
        pageCount,
        amountCents,
        intentId: intent.intentId,
        orderedBy: order.orderedByAccountId,
      },
      "Commande d'impression créée",
    );

    return reply.code(201).send({
      ...serializePrintOrder(order),
      // Ce que la feuille de paiement de l'app consomme. `clientSecret` n'est
      // pas un secret de serveur — il n'ouvre que cette intention-là — mais il
      // ne doit jamais entrer dans un journal.
      payment: {
        paidFromWallet: false,
        clientSecret: intent.clientSecret,
        amountCents,
        currency: "eur",
        publishableKey: context.env.STRIPE_PUBLISHABLE_KEY,
      },
    });
  });

  app.get("/v1/memos/:id/orders", async (request) => {
    const { id: memoId } = memoIdParams.parse(request.params);
    await loadVisibleMemo(context, request, memoId);

    const orders = await context.prisma.printOrder.findMany({
      where: { memoId },
      orderBy: { createdAt: "desc" },
    });

    return { orders: orders.map(serializePrintOrder) };
  });

  app.get("/v1/orders/:id", async (request) => {
    const { id } = orderIdParams.parse(request.params);

    const order = await context.prisma.printOrder.findFirst({
      where: { id, memo: visibleToAccount(accountIdOf(request)) },
    });

    if (!order) throw HttpError.notFound("Commande introuvable.");
    return serializePrintOrder(order);
  });
}
