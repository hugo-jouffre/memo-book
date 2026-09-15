import type { FastifyInstance } from "fastify";
import { z } from "zod";
import type { AppContext } from "../context.js";
import { HttpError } from "../lib/httpError.js";
import { accountIdOf } from "../plugins/auth.js";
import { PAYMENT_KIND, ensureStripeCustomer } from "../services/billing.js";
import { visibleToAccount } from "../services/memoOwnership.js";
import { quote as computeQuote, shippingCents, SHIPPING_DAYS, unitPriceCents } from "../services/printPricing.js";
import {
  SHIPPING_COUNTRIES,
  SHIPPING_COUNTRY_CODES,
  toShippingCountryCode,
} from "../services/shippingCountries.js";
import { writeLedgerEntry } from "../services/walletLedger.js";
import { serializeTrip, serializeWallet } from "./appSerializers.js";
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
   * Le rendu à imprimer. Explicite, jamais « le dernier en date » : entre la
   * prévisualisation et la commande, l'utilisateur a pu ajouter une étape, et
   * il doit recevoir le carnet qu'il a vu.
   */
  renderId: z.string().uuid(),
  copies: z.number().int().min(1).max(MAX_COPIES).default(1),
  shippingSpeed: z.enum(["standard", "express"]).default("standard"),
  shipping: shippingSchema,
  /**
   * Les options, exemplaire par exemplaire. Facultatif : sans rien, chaque
   * exemplaire reprend le style du carnet, ce que l'écran annonce déjà —
   * « Par défaut, nous appliquons la même version que ton 1er carnet ».
   */
  copyOptions: z.array(copyOptionsSchema).max(MAX_COPIES).optional(),
  /** La carte présentée. Nulle pour Apple Pay, qui n'en enregistre aucune. */
  paymentCardId: z.string().uuid().nullish(),
});

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
 * cagnotte — les deux doivent annoncer le même chiffre.
 */
function billablePages(memo: { targetPageCount: number; pageCount: number }): number {
  return Math.max(memo.targetPageCount, memo.pageCount, 1);
}

/**
 * De quoi tarifer pour **celui qui commande** : son solde, et ses crédits par
 * provenance pour la répartition d'affichage des deux déductions.
 *
 * Chacun a sa cagnotte — celle du propriétaire n'a pas à régler l'exemplaire
 * d'un co-voyageur.
 */
async function walletOf(context: AppContext, accountId: string) {
  const [account, credits] = await Promise.all([
    context.prisma.account.findUnique({
      where: { id: accountId },
      select: { walletBalanceCents: true },
    }),
    context.prisma.walletEntry.groupBy({
      by: ["kind"],
      where: { accountId, amountCents: { gt: 0 } },
      _sum: { amountCents: true },
    }),
  ]);

  const sumOf = (kind: string) =>
    credits.find((row) => row.kind === kind)?._sum.amountCents ?? 0;

  return {
    balanceCents: account?.walletBalanceCents ?? 0,
    giftCreditCents: sumOf("gift"),
    topupCreditCents: sumOf("topup"),
  };
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

    const [memo, account, wallet, walletEntries] = await Promise.all([
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
      walletOf(context, accountId),
      // L'historique **fait partie du contrat** : ``Wallet`` le porte, et un
      // champ non optionnel absent de la réponse fait échouer le décodage de
      // tout l'écran, pas seulement de la ligne concernée. Servir un objet
      // partiel « parce que le tunnel n'affiche pas l'historique » a coûté
      // exactement ça — l'étape 1 restait en squelette sur une erreur de
      // décodage. Voir `CLAUDE.md`, § Un choix de design ne s'arrête pas au
      // dessin.
      context.prisma.walletEntry.findMany({
        where: { accountId },
        orderBy: { createdAt: "desc" as const },
        take: 50,
        select: { id: true, amountCents: true, kind: true, label: true, createdAt: true },
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
      trip: serializeTrip(memo),
      // Le **même** sérialiseur que `GET /v1/wallet` : un seul endroit décide
      // de la forme d'une cagnotte, et elle ne peut donc pas diverger d'un
      // écran à l'autre.
      wallet: serializeWallet(wallet.balanceCents, walletEntries, memo),
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
    const wallet = await walletOf(context, accountIdOf(request));

    return serializeOrderQuote(
      computeQuote({
        bookTitle: memo.bookTitle?.trim() || memo.title,
        pageCount: billablePages(memo),
        copies: body.copies,
        speed: body.shippingSpeed,
        walletBalanceCents: wallet.balanceCents,
        giftCreditCents: wallet.giftCreditCents,
        topupCreditCents: wallet.topupCreditCents,
      })
    );
  });

  /**
   * Commande d'un carnet imprimé, à partir d'un rendu déjà prévisualisé.
   *
   * **Ouverte aux co-voyageurs autant qu'au propriétaire** : chacun commande
   * son exemplaire du carnet qu'ils ont écrit ensemble. La commande retient
   * donc qui l'a passée — c'est ce qui dira quelle cagnotte débiter, chacun
   * ayant la sienne.
   *
   * La commande est créée en `draft` : l'envoi effectif à l'imprimeur suppose
   * un paiement encaissé, qui n'existe pas encore (StoreKit / Stripe, voir la
   * roadmap). Cette route pose le contrat côté app et rend la commande
   * traçable ; le passage en `submitted` viendra du webhook de paiement.
   *
   * ⚠️ **Aucune écriture de cagnotte n'est posée ici.** `wallet_entries` est un
   * registre de mouvements *réellement encaissés* — il n'a pas d'état « en
   * attente ». `walletAppliedCents` garde ce que la commande déduira le jour où
   * elle sera payée ; la ligne, elle, s'écrira avec le webhook.
   */
  app.post("/v1/memos/:id/orders", async (request, reply) => {
    const { id: memoId } = memoIdParams.parse(request.params);
    const memo = await loadVisibleMemo(context, request, memoId);
    const accountId = accountIdOf(request);

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

    // La carte doit être **au compte qui commande**. Sans cette vérification,
    // un identifiant deviné rattacherait la commande à la carte d'un autre.
    if (body.paymentCardId) {
      const card = await context.prisma.paymentCard.findFirst({
        where: { id: body.paymentCardId, accountId },
        select: { id: true },
      });
      if (!card) throw HttpError.notFound("Ce moyen de paiement est introuvable.");
    }

    // Le prix se **recalcule ici**, à partir de l'état du serveur. Ce que l'app
    // a affiché ne l'engage pas : un total qui arriverait du client serait un
    // total qu'on peut réécrire.
    const wallet = await walletOf(context, accountId);
    const priced = computeQuote({
      bookTitle: memo.bookTitle?.trim() || memo.title,
      pageCount: billablePages(memo),
      copies: body.copies,
      speed: body.shippingSpeed,
      walletBalanceCents: wallet.balanceCents,
      giftCreditCents: wallet.giftCreditCents,
      topupCreditCents: wallet.topupCreditCents,
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
        paymentCardId: body.paymentCardId ?? null,
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
    // Deux mouvements possibles, et ils ne s'excluent pas : la cagnotte couvre
    // ce qu'elle peut, la carte paie le reste. `priced` a déjà fait le partage.

    if (priced.walletAppliedCents > 0) {
      const debit = await writeLedgerEntry(context.prisma, {
        accountId,
        amountCents: -priced.walletAppliedCents,
        kind: "order_payment",
        label: `Carnet « ${memo.bookTitle?.trim() || memo.title} »`,
        printOrderId: order.id,
      });

      if (debit.outcome === "insufficient") {
        // Le solde a bougé entre le devis et le débit — une seconde commande
        // partie en parallèle. La commande vient d'être créée, personne ne l'a
        // vue, et elle porte un `walletAppliedCents` que le registre dément :
        // la laisser serait garder une ligne qui ment. On la retire.
        await context.prisma.printOrder.delete({ where: { id: order.id } });
        throw HttpError.badRequest(
          `Il manque ${(debit.missingCents / 100).toFixed(2)} € sur ta cagnotte.`,
          "wallet_insufficient",
        );
      }
    }

    // La cagnotte a tout couvert : aucun aller-retour de paiement, le débit
    // **est** l'encaissement.
    if (priced.totalCents === 0) {
      const paid = await context.prisma.printOrder.update({
        where: { id: order.id },
        data: { status: "submitted", submittedAt: new Date() },
        include: { copyOptions: true },
      });

      context.logger.info(
        { orderId: order.id, memoId, walletCents: priced.walletAppliedCents, paidFrom: "wallet" },
        "Commande payée par la cagnotte",
      );

      return reply.code(201).send({
        ...serializePrintOrder(paid),
        payment: { paidFromWallet: true, amountCents: 0, currency: "eur" },
      });
    }

    // Reste à payer : Stripe prend la main. L'intention est créée **après** la
    // commande — sa clé d'idempotence est l'identifiant de celle-ci, donc elle
    // doit exister. Un échec ici laisse une commande en `draft`, ce qui est le
    // bon état à laisser derrière soi : l'app la reprend.
    const customerId = await ensureStripeCustomer(context, accountId);

    const intent = await context.payments.createIntent({
      idempotencyKey: `order:${order.id}`,
      amountCents: priced.totalCents,
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

    return reply.code(201).send({
      ...serializePrintOrder(order),
      // Ce que la feuille de paiement consomme. `clientSecret` n'ouvre que
      // cette intention-là, mais il n'entre jamais dans un journal.
      payment: {
        paidFromWallet: false,
        clientSecret: intent.clientSecret,
        amountCents: priced.totalCents,
        currency: "eur",
        publishableKey: context.env.STRIPE_PUBLISHABLE_KEY,
      },
    });
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
