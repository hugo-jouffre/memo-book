import type { FastifyInstance } from "fastify";
import { z } from "zod";
import type { AppContext } from "../context.js";
import { HttpError } from "../lib/httpError.js";
import { deviceIdOf } from "../plugins/auth.js";
import { loadOwnedMemo } from "./memos.js";
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
   * La commande est créée en `draft` : l'envoi effectif à l'imprimeur suppose
   * un paiement encaissé, qui n'existe pas encore (StoreKit / Stripe, voir la
   * roadmap). Cette route pose le contrat côté app et rend la commande
   * traçable ; le passage en `submitted` viendra du webhook de paiement.
   */
  app.post("/v1/memos/:id/orders", async (request, reply) => {
    const { id: memoId } = memoIdParams.parse(request.params);
    await loadOwnedMemo(context, request, memoId);

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

    const order = await context.prisma.printOrder.create({
      data: {
        memoId,
        renderId: render.id,
        copies: body.copies,
        shippingName: body.shipping.name,
        shippingLine1: body.shipping.line1,
        shippingLine2: body.shipping.line2 ?? null,
        shippingPostalCode: body.shipping.postalCode,
        shippingCity: body.shipping.city,
        shippingCountry: body.shipping.country,
      },
    });

    context.logger.info(
      { orderId: order.id, memoId, renderId: render.id, copies: order.copies },
      "Commande d'impression créée",
    );

    return reply.code(201).send(serializePrintOrder(order));
  });

  app.get("/v1/memos/:id/orders", async (request) => {
    const { id: memoId } = memoIdParams.parse(request.params);
    await loadOwnedMemo(context, request, memoId);

    const orders = await context.prisma.printOrder.findMany({
      where: { memoId },
      orderBy: { createdAt: "desc" },
    });

    return { orders: orders.map(serializePrintOrder) };
  });

  app.get("/v1/orders/:id", async (request) => {
    const { id } = orderIdParams.parse(request.params);

    const order = await context.prisma.printOrder.findFirst({
      where: { id, memo: { deviceId: deviceIdOf(request) } },
    });

    if (!order) throw HttpError.notFound("Commande introuvable.");
    return serializePrintOrder(order);
  });
}
