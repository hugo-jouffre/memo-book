import type { PrintOrder } from "@prisma/client";
import type { FastifyInstance } from "fastify";
import { z } from "zod";
import type { AppContext } from "../context.js";
import { HttpError } from "../lib/httpError.js";
import { accountIdOf } from "../plugins/auth.js";
import {
  PAYMENT_KIND,
  ensureStripeCustomer,
  paymentTicket,
  stripeApiVersionSchema,
} from "../services/billing.js";
import { visibleToAccount } from "../services/memoOwnership.js";
import { releaseUnpaidOrder } from "../services/orderPayments.js";
import { quote as computeQuote, shippingCents, SHIPPING_DAYS, unitPriceCents } from "../services/printPricing.js";
import {
  SHIPPING_COUNTRIES,
  SHIPPING_COUNTRY_CODES,
  toShippingCountryCode,
} from "../services/shippingCountries.js";
import { frozenWallet, serializeTrip } from "./appSerializers.js";
import { loadVisibleMemo } from "./memos.js";
import { serializeOrderQuote, serializePrintOrder } from "./serializers.js";

const memoIdParams = z.object({ id: z.string().uuid() });
const orderIdParams = z.object({ id: z.string().uuid() });

/** Ce que l'imprimeur accepte. Vingt exemplaires est déjà généreux pour un carnet de voyage. */
const MAX_COPIES = 20;

const shippingSchema = z.object({
  name: z.string().trim().min(1).max(200),
  line1: z.string().trim().min(1).max(200),
  line2: z.string().trim().max(200).optional().nullable(),
  postalCode: z.string().trim().min(1).max(20),
  city: z.string().trim().min(1).max(120),
  /**
   * Code ISO 3166-1 alpha-2, **et un pays où l'imprimeur livre**. Valider la
   * seule longueur laissait passer « ZZ », donc une commande impossible à
   * honorer qu'on n'aurait découverte qu'à l'expédition.
   */
  country: z
    .string()
    .trim()
    .toUpperCase()
    .refine((code) => SHIPPING_COUNTRY_CODES.includes(code as (typeof SHIPPING_COUNTRY_CODES)[number]), {
      message: "Nous ne livrons pas encore dans ce pays.",
    }),
});

const copyOptionsSchema = z.object({
  position: z.number().int().min(1).max(MAX_COPIES),
  decorationsEnabled: z.boolean(),
  quizEnabled: z.boolean(),
  freeZonesEnabled: z.boolean(),
  crosswordEnabled: z.boolean(),
});

const quoteBody = z.object({
  copies: z.number().int().min(1).max(MAX_COPIES).default(1),
  shippingSpeed: z.enum(["standard", "express"]).default("standard"),
});

const createOrderBody = z.object({
  /**
   * Le rendu à imprimer — celui que l'aperçu a montré : entre la
   * prévisualisation et la commande, l'utilisateur a pu ajouter une étape, et
   * il doit recevoir le carnet qu'il a vu.
   *
   * **Facultatif depuis le 06/10/2026** (T224) : absent, c'est le dernier rendu
   * prêt du voyage. Et s'il n'y en a aucun, le refus porte son propre code,
   * `no_render`, que l'app traduit par « Aucun rendu de ton carnet n'a encore
   * été généré… » — au lieu d'un « Payer » qui ne faisait rien.
   */
  renderId: z.string().uuid().optional(),
  copies: z.number().int().min(1).max(MAX_COPIES).default(1),
  shippingSpeed: z.enum(["standard", "express"]).default("standard"),
  shipping: shippingSchema,
  /**
   * Les options, exemplaire par exemplaire. Facultatif : sans rien, chaque
   * exemplaire reprend le style du carnet, ce que l'écran annonce déjà —
   * « Par défaut, nous appliquons la même version que ton 1er carnet ».
   */
  copyOptions: z.array(copyOptionsSchema).max(MAX_COPIES).optional(),
  /**
   * **Ignoré** (01/10/2026), et accepté pour ne pas casser les versions de
   * l'app qui l'envoient encore. C'était l'identifiant d'une carte que l'app
   * fabriquait elle-même, que le serveur ne connaissait pas — d'où le « Ce
   * moyen de paiement est introuvable » (T225). Le moyen de paiement se choisit
   * dans la feuille Stripe, qui tient les cartes du compte.
   */
  paymentCardId: z.string().nullish(),
  /** La version d'API du SDK Stripe de l'app — voir `paymentTicket`. */
  stripeApiVersion: stripeApiVersionSchema.optional(),
});

const resumePaymentBody = z.object({ stripeApiVersion: stripeApiVersionSchema.optional() });

/**
 * Le suivi par WhatsApp, accepté ou refusé depuis l'écran de confirmation.
 *
 * Le numéro est **exigé avec l'accord** : `notifyByWhatsApp` sans destinataire
 * serait une promesse que personne ne peut tenir. Refuser, en revanche, n'en
 * demande aucun.
 */
const whatsappBody = z.discriminatedUnion("enabled", [
  z.object({
    enabled: z.literal(true),
    phone: z.string().trim().min(6).max(40),
  }),
  z.object({ enabled: z.literal(false) }),
]);

/**
 * Le nombre de pages qui fait foi pour le prix : celui que le voyageur vise,
 * ou celui déjà composé s'il est plus grand. Même règle que l'estimation de la
 * notification de fin de voyage — les deux doivent annoncer le même chiffre.
 */
function billablePages(memo: { targetPageCount: number; pageCount: number }): number {
  return Math.max(memo.targetPageCount, memo.pageCount, 1);
}

/**
 * Le refus d'une commande sans carnet composé (T224). Un code à lui, distinct
 * de `render_not_ready` (un rendu désigné qui n'est pas prêt) : c'est le seul
 * que l'app traduit par « aucun rendu de ton carnet n'a encore été généré ».
 */
function noRender(): HttpError {
  return new HttpError(
    409,
    "Aucun rendu de ton carnet n’a encore été généré. Ouvre l’aperçu pour le composer, puis reviens commander.",
    "no_render",
  );
}

/**
 * Ouvre l'intention Stripe d'une commande — à sa création, ou quand on la
 * finalise après un abandon (T232). Le même appel pour les deux : mêmes
 * métadonnées (c'est par elles que le webhook retrouve la commande), même
 * description, même reçu, même adresse figée.
 */
async function openOrderIntent(
  context: AppContext,
  input: { order: PrintOrder; accountId: string; title: string; amountCents: number; idempotencyKey: string },
) {
  const { order, accountId, title } = input;
  const customerId = await ensureStripeCustomer(context, accountId);
  const buyer = await context.prisma.account.findUnique({
    where: { id: accountId },
    select: { email: true },
  });

  const intent = await context.payments.createIntent({
    idempotencyKey: input.idempotencyKey,
    amountCents: input.amountCents,
    currency: "eur",
    customerId,
    metadata: {
      kind: PAYMENT_KIND.bookOrder,
      orderId: order.id,
      memoId: order.memoId,
      renderId: order.renderId,
      accountId,
    },
    description:
      order.copies > 1 ? `Carnet « ${title} » — ${order.copies} exemplaires` : `Carnet « ${title} »`,
    receiptEmail: buyer?.email ?? null,
    shipping: {
      name: order.shippingName,
      line1: order.shippingLine1,
      line2: order.shippingLine2,
      postalCode: order.shippingPostalCode,
      city: order.shippingCity,
      country: order.shippingCountry,
    },
  });

  return { customerId, intent };
}

/**
 * Le prix entier d'une commande, **sans déduction** : ses articles et sa
 * livraison, figés à la commande. Pour une commande d'avant le 06/10/2026
 * dont la cagnotte payait une part — rendue quand elle s'est fermée —, c'est
 * ce qu'il reste à payer par Stripe en la finalisant.
 */
function fullPriceCents(order: PrintOrder): number | null {
  if (order.itemsCents !== null && order.shippingCents !== null) return order.itemsCents + order.shippingCents;
  if (order.amountCents === null) return null;
  return order.amountCents + (order.walletAppliedCents ?? 0);
}

/** Une commande payée un jour : soumise, en impression, expédiée — ou remboursée depuis. */
function wasPaid(order: Pick<PrintOrder, "status" | "submittedAt">): boolean {
  return order.status !== "draft" && (order.status !== "cancelled" || order.submittedAt !== null);
}

export function registerOrderRoutes(app: FastifyInstance, context: AppContext): void {
  /**
   * Tout ce que le tunnel de commande a besoin de savoir pour s'ouvrir.
   *
   * **Une réponse pour les sept étapes**, et non une par étape : le parcours
   * est une seule destination, et le découper ferait apparaître une attente à
   * chaque « Continuer ». Ce qui bouge en cours de route — le récapitulatif —
   * a sa propre route, parce que lui seul dépend de choix pas encore faits.
   */
  app.get("/v1/memos/:id/order-context", async (request) => {
    const { id: memoId } = memoIdParams.parse(request.params);
    const accountId = accountIdOf(request);

    const [memo, account] = await Promise.all([
      context.prisma.memo.findFirst({
        where: { id: memoId, ...visibleToAccount(accountId) },
        include: {
          members: {
            where: { status: { not: "removed" as const } },
            include: { account: true },
            orderBy: { invitedAt: "asc" as const },
          },
          renders: {
            where: { status: "ready" },
            orderBy: { createdAt: "desc" as const },
            take: 1,
          },
        },
      }),
      context.prisma.account.findUnique({
        where: { id: accountId },
        select: {
          firstName: true,
          lastName: true,
          phoneNumber: true,
          addressLine1: true,
          addressLine2: true,
          addressPostalCode: true,
          addressCity: true,
          addressCountry: true,
          cards: {
            orderBy: [{ isDefault: "desc" as const }, { createdAt: "asc" as const }],
          },
        },
      }),
    ]);

    if (!memo) throw HttpError.notFound("Carnet introuvable.");

    const pages = billablePages(memo);
    const render = memo.renders[0];

    // L'adresse du profil sert d'amorce. Ce n'est pas l'adresse de la
    // commande — celle-ci se fige à la commande —, c'est ce qu'on propose pour
    // ne pas faire ressaisir ce qu'on sait déjà.
    const fullName = [account?.firstName, account?.lastName]
      .filter((part): part is string => Boolean(part?.trim()))
      .join(" ");

    const hasAddress = Boolean(account?.addressLine1?.trim());

    const defaultCard = account?.cards.find((card) => card.isDefault) ?? account?.cards[0];

    return {
      memoId: memo.id,
      /**
       * Le rendu prêt le plus récent. `null` quand le carnet n'a jamais été
       * composé : l'écran ouvre alors sur l'aperçu au lieu de la commande.
       */
      renderId: render?.id ?? null,
      // Le titre du **récit** (« Rome et la Dolce Vita »), pas le nom du voyage.
      bookTitle: memo.bookTitle?.trim() || memo.title,
      pageCount: pages,
      trip: serializeTrip(memo, { viewerAccountId: accountId }),
      // **Gelé** (06/10/2026, la cagnotte est retirée) : un solde à zéro et un
      // historique vide. Les builds installés décodent ``Wallet`` comme
      // obligatoire — un champ absent ferait échouer tout l'écran, l'étape 1
      // restait en squelette pour moins que ça. À retirer quand plus aucun
      // build ne le lit.
      wallet: frozenWallet(memo),
      // Les deux prix que les étapes 3 et 4 affichent sans rien recalculer.
      unitPrice: Number((unitPriceCents(pages) / 100).toFixed(2)),
      expressPrice: Number((shippingCents("express") / 100).toFixed(2)),
      standardDays: SHIPPING_DAYS.standard,
      expressDays: SHIPPING_DAYS.express,
      shipping: hasAddress
        ? {
            name: fullName,
            line1: account?.addressLine1 ?? "",
            line2: account?.addressLine2 ?? null,
            postalCode: account?.addressPostalCode ?? "",
            city: account?.addressCity ?? "",
            country: toShippingCountryCode(account?.addressCountry),
          }
        : { name: fullName, line1: "", line2: null, postalCode: "", city: "", country: "FR" },
      // La liste vient du serveur : elle suit l'imprimeur, pas nos livraisons.
      countries: SHIPPING_COUNTRIES,
      cards: (account?.cards ?? []).map((card) => ({
        id: card.id,
        label: card.label?.trim() || card.brand || "Carte",
        last4: card.last4,
        isDefault: card.isDefault,
      })),
      selectedCardId: defaultCard?.id ?? null,
      // Le numéro qu'on proposera pour le suivi WhatsApp. `null` tant que le
      // compte n'en a pas : l'écran le demande alors au lieu de le supposer.
      phoneNumber: account?.phoneNumber?.trim() || null,
      // Le style du carnet, que chaque exemplaire reprend par défaut.
      //
      // `position: 1` n'est pas décoratif : côté app c'est un
      // ``PrintedCopyOptions``, qui porte toujours un rang — celui du premier
      // carnet, puisque c'est de lui que les autres se copient. L'omettre
      // faisait échouer le décodage de **tout** le contexte.
      options: {
        position: 1,
        decorationsEnabled: memo.decorationQuota > 0,
        quizEnabled: memo.quizEnabled,
        freeZonesEnabled: memo.freeZonesEnabled,
        crosswordEnabled: memo.crosswordEnabled,
      },
    };
  });

  /**
   * Le récapitulatif de l'étape 5.
   *
   * **C'est le serveur qui compte.** L'app envoie ce qui a été choisi et
   * dessine ce qu'on lui rend ; elle n'additionne aucun montant, sans quoi les
   * deux côtés finiraient par annoncer des totaux différents.
   */
  app.post("/v1/memos/:id/orders/quote", async (request) => {
    const { id: memoId } = memoIdParams.parse(request.params);
    const memo = await loadVisibleMemo(context, request, memoId);
    const body = quoteBody.parse(request.body ?? {});

    return serializeOrderQuote(
      computeQuote({
        bookTitle: memo.bookTitle?.trim() || memo.title,
        pageCount: billablePages(memo),
        copies: body.copies,
        speed: body.shippingSpeed,
      })
    );
  });

  /**
   * Commande d'un carnet imprimé, à partir d'un rendu déjà prévisualisé.
   *
   * **Ouverte aux co-voyageurs autant qu'au propriétaire** : chacun commande
   * son exemplaire du carnet qu'ils ont écrit ensemble. La commande retient
   * donc qui l'a passée — c'est à lui qu'elle appartient, et à lui seul
   * qu'elle se montre dans le suivi.
   *
   * La commande est créée en `draft`, et n'en sort que payée, par le webhook
   * de Stripe. **Tout se paie par Stripe** depuis le 06/10/2026 : la cagnotte,
   * qui réglait une part ici même, est retirée du produit.
   */
  app.post("/v1/memos/:id/orders", async (request, reply) => {
    const { id: memoId } = memoIdParams.parse(request.params);
    const memo = await loadVisibleMemo(context, request, memoId);
    const accountId = accountIdOf(request);

    const body = createOrderBody.parse(request.body ?? {});

    // Le rendu désigné, ou à défaut le dernier prêt du voyage — et sans aucun
    // des deux, le refus que l'app sait traduire (T224).
    const render = body.renderId
      ? await context.prisma.render.findFirst({ where: { id: body.renderId, memoId } })
      : await context.prisma.render.findFirst({
          where: { memoId, status: "ready", pdfUrl: { not: null } },
          orderBy: { createdAt: "desc" },
        });

    if (!render) {
      if (!body.renderId) throw noRender();
      throw HttpError.notFound("Ce rendu n'appartient pas à ce carnet.");
    }

    if (render.status !== "ready" || !render.pdfUrl) {
      throw HttpError.badRequest(
        "Ce carnet n'est pas encore généré. Prévisualise-le avant de le commander.",
        "render_not_ready",
      );
    }

    // Le prix se **recalcule ici**, à partir de l'état du serveur. Ce que l'app
    // a affiché ne l'engage pas : un total qui arriverait du client serait un
    // total qu'on peut réécrire.
    const priced = computeQuote({
      bookTitle: memo.bookTitle?.trim() || memo.title,
      pageCount: billablePages(memo),
      copies: body.copies,
      speed: body.shippingSpeed,
    });

    // Les options manquantes reprennent le style du carnet, exemplaire par
    // exemplaire — ce que l'écran annonce quand on n'ouvre pas le 2e carnet.
    const fallback = {
      decorationsEnabled: memo.decorationQuota > 0,
      quizEnabled: memo.quizEnabled,
      freeZonesEnabled: memo.freeZonesEnabled,
      crosswordEnabled: memo.crosswordEnabled,
    };
    const chosen = new Map((body.copyOptions ?? []).map((copy) => [copy.position, copy]));
    const copyOptions = Array.from({ length: body.copies }, (_, index) => {
      const position = index + 1;
      const picked = chosen.get(position);
      return {
        position,
        decorationsEnabled: picked?.decorationsEnabled ?? fallback.decorationsEnabled,
        quizEnabled: picked?.quizEnabled ?? fallback.quizEnabled,
        freeZonesEnabled: picked?.freeZonesEnabled ?? fallback.freeZonesEnabled,
        crosswordEnabled: picked?.crosswordEnabled ?? fallback.crosswordEnabled,
      };
    });

    const order = await context.prisma.printOrder.create({
      data: {
        memoId,
        renderId: render.id,
        orderedByAccountId: accountId,
        copies: body.copies,
        shippingSpeed: body.shippingSpeed,
        shippingName: body.shipping.name,
        shippingLine1: body.shipping.line1,
        shippingLine2: body.shipping.line2 ?? null,
        shippingPostalCode: body.shipping.postalCode,
        shippingCity: body.shipping.city,
        shippingCountry: body.shipping.country,
        // Figé avec la commande : c'est le livre qui part à l'impression, pas
        // celui d'aujourd'hui.
        pageCount: priced.pageCount,
        coverImageUrl: memo.coverPhotoUrl,
        estimatedMinDays: priced.estimatedDays.min,
        estimatedMaxDays: priced.estimatedDays.max,
        itemsCents: priced.itemsCents,
        shippingCents: priced.shippingCents,
        walletAppliedCents: priced.walletAppliedCents,
        amountCents: priced.totalCents,
        copyOptions: { create: copyOptions },
      },
      include: { copyOptions: true },
    });

    context.logger.info(
      {
        orderId: order.id,
        memoId,
        renderId: render.id,
        copies: order.copies,
        shippingSpeed: order.shippingSpeed,
        amountCents: order.amountCents,
        orderedBy: order.orderedByAccountId,
      },
      "Commande d'impression créée",
    );

    // --- L'encaissement ------------------------------------------------
    //
    // Stripe, et rien d'autre. L'intention est créée **après** la commande —
    // sa clé d'idempotence est l'identifiant de celle-ci, donc elle doit
    // exister. Un échec ici ferme la commande : un brouillon sans intention ne
    // pourrait plus être payé que par la reprise (`POST /v1/orders/:id/payment`).
    let opened;
    try {
      opened = await openOrderIntent(context, {
        order,
        accountId,
        title: memo.bookTitle?.trim() || memo.title,
        amountCents: priced.totalCents,
        idempotencyKey: `order:${order.id}`,
      });

      await context.prisma.printOrder.update({
        where: { id: order.id },
        data: { stripePaymentIntentId: opened.intent.intentId },
      });
    } catch (cause) {
      await releaseUnpaidOrder(context, order.id, "Le paiement n'a pas pu s'ouvrir.");
      throw cause;
    }

    return reply.code(201).send({
      ...serializePrintOrder(order),
      // Ce que la feuille de paiement consomme. `clientSecret` n'ouvre que
      // cette intention-là, mais il n'entre jamais dans un journal.
      payment: await paymentTicket(context, {
        customerId: opened.customerId,
        clientSecret: opened.intent.clientSecret,
        amountCents: priced.totalCents,
        stripeApiVersion: body.stripeApiVersion,
      }),
    });
  });

  /**
   * **Reprendre le paiement d'une commande déjà passée** (01/10/2026) — et,
   * depuis le 07/10/2026, **la finaliser après un abandon** (T232) : c'est le
   * CTA « Finaliser ma commande » du suivi des commandes.
   *
   * « Payer », après une feuille refermée ou une carte refusée, créait une
   * **nouvelle** commande. L'app reprend désormais celle qu'elle a :
   *
   * - à régler sur son intention (`requires_payment_method`,
   *   `requires_action`…) → la feuille, **sur la même intention** ;
   * - réglée ou en cours (`succeeded`, `processing`) → `payment: null`, et
   *   l'app relit la commande jusqu'à ce que le webhook l'ait passée ;
   * - **fermée sans avoir été payée** — par le ménage des 24 h, une intention
   *   annulée, ou l'app — → elle est **rouverte** : de nouveau `draft`, avec
   *   une intention neuve, au prix figé à la commande. Elle répondait 409
   *   `order_expired` ; il fallait tout repasser ;
   * - payée puis remboursée → 409 `order_refunded` : celle-là ne se rouvre
   *   pas, il faut en repasser une.
   */
  app.post("/v1/orders/:id/payment", async (request) => {
    const { id } = orderIdParams.parse(request.params);
    const { stripeApiVersion } = resumePaymentBody.parse(request.body ?? {});
    const accountId = accountIdOf(request);

    const order = await context.prisma.printOrder.findFirst({
      where: { id, orderedByAccountId: accountId },
      include: { copyOptions: true, memo: { select: { title: true, bookTitle: true } } },
    });
    if (!order) throw HttpError.notFound("Commande introuvable.");

    const settled = () => ({ ...serializePrintOrder(order), payment: null });

    if (wasPaid(order)) {
      if (order.status === "cancelled") {
        throw new HttpError(
          409,
          "Cette commande a été remboursée : repasse-la depuis l’aperçu du carnet.",
          "order_refunded",
        );
      }
      return settled();
    }

    // Une commande d'avant la tarification n'a pas de prix à demander.
    const amountCents = fullPriceCents(order);
    if (amountCents === null) return settled();

    if (order.status === "draft" && order.stripePaymentIntentId) {
      const intent = await context.payments.retrieveIntent(order.stripePaymentIntentId);

      if (intent.status === "succeeded" || intent.status === "processing") return settled();

      if (intent.status !== "canceled" && intent.clientSecret) {
        const customerId = await ensureStripeCustomer(context, accountId);
        return {
          ...serializePrintOrder(order),
          payment: await paymentTicket(context, {
            customerId,
            clientSecret: intent.clientSecret,
            amountCents: order.amountCents ?? amountCents,
            stripeApiVersion,
          }),
        };
      }
    }

    // --- Rouvrir (T232) ------------------------------------------------
    //
    // Fermer d'abord, par le chemin de toujours : l'intention s'annule (Stripe
    // tranche si elle vient d'être payée) et une ancienne part de cagnotte
    // revient. Puis rouvrir sur une intention neuve.
    //
    // **La clé d'idempotence nomme l'intention qu'on remplace**, lue avant
    // tout (08/10/2026). Elle portait l'instant de la dernière écriture, relu
    // après la fermeture : deux appuis simultanés sur « Finaliser » ne
    // relisaient pas toujours le même instant — le second arrivait après
    // l'écriture du premier — et ouvraient deux intentions, la commande ne
    // gardant que la seconde (vu en CI, `stripeLifecycle.test.ts`). L'intention
    // remplacée, elle, est la même pour les deux appuis ; la fermeture la
    // garde sur la commande, et la réouverture suivante en remplacera une
    // autre — donc une clé neuve.
    const reopenKey = `order:${order.id}:reopen-after:${order.stripePaymentIntentId ?? "none"}`;
    if (order.status === "draft") {
      const outcome = await releaseUnpaidOrder(context, order.id, "Paiement rouvert.");
      if (outcome === "paid") return settled();
    }
    const closed = await context.prisma.printOrder.findUniqueOrThrow({ where: { id: order.id } });
    if (wasPaid(closed)) return { ...serializePrintOrder({ ...closed, copyOptions: order.copyOptions }), payment: null };

    const { customerId, intent } = await openOrderIntent(context, {
      order: closed,
      accountId,
      title: order.memo.bookTitle?.trim() || order.memo.title,
      amountCents,
      idempotencyKey: reopenKey,
    });

    await context.prisma.printOrder.updateMany({
      where: { id: order.id, status: { in: ["cancelled", "draft"] }, submittedAt: null },
      data: {
        status: "draft",
        error: null,
        stripePaymentIntentId: intent.intentId,
        amountCents,
        // La part de cagnotte d'une commande d'avant a été rendue en la
        // fermant : tout se paie par Stripe désormais.
        walletAppliedCents: 0,
      },
    });

    const reopened = await context.prisma.printOrder.findUniqueOrThrow({
      where: { id: order.id },
      include: { copyOptions: true },
    });

    context.logger.info({ orderId: order.id, amountCents, intentId: intent.intentId }, "Commande rouverte pour être finalisée");

    return {
      ...serializePrintOrder(reopened),
      payment: await paymentTicket(context, {
        customerId,
        clientSecret: intent.clientSecret,
        amountCents,
        stripeApiVersion,
      }),
    };
  });

  /**
   * Abandonner une commande pas encore payée — l'app le fait quand on change
   * d'adresse, d'exemplaires ou de rapidité après une première tentative :
   * l'ancienne commande ne correspond plus, elle rend sa réservation et la
   * nouvelle repart d'un devis frais.
   *
   * Idempotente : une commande déjà fermée se rend telle quelle. Une commande
   * payée entre-temps ne s'annule pas — 409, et l'app relit.
   */
  app.post("/v1/orders/:id/cancel", async (request) => {
    const { id } = orderIdParams.parse(request.params);
    const accountId = accountIdOf(request);

    const order = await context.prisma.printOrder.findFirst({
      where: { id, orderedByAccountId: accountId },
      select: { id: true },
    });
    if (!order) throw HttpError.notFound("Commande introuvable.");

    const outcome = await releaseUnpaidOrder(context, order.id, "Commande abandonnée.");
    if (outcome === "paid") {
      throw new HttpError(409, "Cette commande vient d'être payée.", "order_paid");
    }

    const fresh = await context.prisma.printOrder.findUniqueOrThrow({
      where: { id: order.id },
      include: { copyOptions: true },
    });
    return serializePrintOrder(fresh);
  });

  /**
   * Accepter — ou refuser — d'être prévenu par WhatsApp de l'acheminement.
   *
   * Le numéro **remonte aussi sur le compte** quand celui-ci n'en a pas : c'est
   * la seule fois où on le demande aujourd'hui, et le redemander à la commande
   * suivante serait une question déjà posée. Le jour où l'accueil du compte le
   * collecte, cette route n'aura plus qu'à le lire.
   *
   * ⚠️ Rien n'est envoyé : aucun WhatsApp Business n'est branché. La commande
   * retient qui prévenir, l'envoi viendra avec le suivi de l'imprimeur.
   */
  app.post("/v1/orders/:id/whatsapp", async (request) => {
    const { id } = orderIdParams.parse(request.params);
    const accountId = accountIdOf(request);
    const body = whatsappBody.parse(request.body ?? {});

    // **La commande de celui qui demande**, et pas seulement une commande
    // visible : c'est son numéro de téléphone qu'on y attache.
    const order = await context.prisma.printOrder.findFirst({
      where: { id, orderedByAccountId: accountId },
      select: { id: true },
    });
    if (!order) throw HttpError.notFound("Commande introuvable.");

    const phone = body.enabled ? body.phone : null;

    const updated = await context.prisma.$transaction(async (tx) => {
      if (phone) {
        const account = await tx.account.findUnique({
          where: { id: accountId },
          select: { phoneNumber: true },
        });
        // On ne réécrit pas un numéro déjà connu : il appartient au profil, et
        // c'est là qu'il se corrige.
        if (!account?.phoneNumber?.trim()) {
          await tx.account.update({ where: { id: accountId }, data: { phoneNumber: phone } });
        }
      }

      return tx.printOrder.update({
        where: { id },
        data: { notifyByWhatsApp: body.enabled, whatsappPhone: phone },
        include: { copyOptions: true },
      });
    });

    return serializePrintOrder(updated);
  });

  app.get("/v1/memos/:id/orders", async (request) => {
    const { id: memoId } = memoIdParams.parse(request.params);
    await loadVisibleMemo(context, request, memoId);

    const orders = await context.prisma.printOrder.findMany({
      where: { memoId },
      orderBy: { createdAt: "desc" },
      include: { copyOptions: true },
    });

    return { orders: orders.map(serializePrintOrder) };
  });

  app.get("/v1/orders/:id", async (request) => {
    const { id } = orderIdParams.parse(request.params);

    const order = await context.prisma.printOrder.findFirst({
      where: { id, memo: visibleToAccount(accountIdOf(request)) },
      include: { copyOptions: true },
    });

    if (!order) throw HttpError.notFound("Commande introuvable.");
    return serializePrintOrder(order);
  });
}
