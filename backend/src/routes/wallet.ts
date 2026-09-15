import { randomUUID } from "node:crypto";
import type { FastifyInstance } from "fastify";
import { z } from "zod";
import type { AppContext } from "../context.js";
import { HttpError } from "../lib/httpError.js";
import { accountIdOf } from "../plugins/auth.js";
import { PAYMENT_KIND, ensureStripeCustomer } from "../services/billing.js";
import { visibleToAccount } from "../services/memoOwnership.js";
import { serializeWallet } from "./appSerializers.js";

/**
 * La cagnotte : ce qu'il y a dessus, d'où ça vient, et ce que le carnet
 * coûtera.
 *
 * **Elle appartient au compte, pas au voyage.** Deux co-voyageurs ont chacun la
 * leur, et c'est la même somme qu'on lit dans le profil et dans les paramètres
 * d'un voyage — d'où une seule route, et un `tripId` facultatif qui ne dit pas
 * *quelle* cagnotte mais **quel carnet on finance**.
 *
 * Le solde ne se recalcule pas ici : `accounts.walletBalanceCents` est le cache
 * tenu à jour dans la même transaction que chaque écriture, et
 * `wallet_entries.balanceAfterCents` permet de vérifier qu'il n'a pas dérivé.
 * Sommer le registre à chaque affichage coûterait une agrégation sur tout
 * l'historique pour une valeur déjà connue.
 */

const query = z.object({ tripId: z.string().uuid().optional() });

/**
 * Ce qu'on pose à la main depuis le bac à sable : un montant **signé** en euros,
 * sa nature, et le motif lisible que l'historique affichera.
 */
const debugEntryBody = z.object({
  amount: z.number().finite().min(-10_000).max(10_000),
  kind: z.enum(["gift", "topup", "refund", "adjustment"]),
  label: z.string().trim().min(1).max(120).optional(),
});

/**
 * Combien d'écritures l'historique rend.
 *
 * Cinquante : l'écran les affiche toutes d'un bloc, sans pagination — la
 * maquette n'en dessine pas — et cinquante contributions représentent déjà un
 * carnet très entouré. Au-delà, il faudra paginer, et ce sera un vrai sujet
 * d'écran avant d'être un sujet de route.
 */
const HISTORY_LIMIT = 50;

/**
 * Les bornes d'une recharge, en centimes.
 *
 * Le plancher écarte les recharges qui coûteraient plus cher en frais Stripe
 * (0,25 € fixe) qu'elles ne rapportent. Le plafond est un garde-fou : une
 * cagnotte n'est pas un compte en banque, et une recharge à quatre chiffres est
 * plus probablement une erreur de saisie qu'une intention.
 */
const TOPUP_MIN_CENTS = 500;
const TOPUP_MAX_CENTS = 50_000;

const topupBody = z.object({
  amountCents: z.number().int().min(TOPUP_MIN_CENTS).max(TOPUP_MAX_CENTS),
});

export function registerWalletRoutes(app: FastifyInstance, context: AppContext) {
  app.get("/v1/wallet", async (request) => {
    const { tripId } = query.parse(request.query);
    const accountId = accountIdOf(request);

    const [account, entries, trip] = await Promise.all([
      context.prisma.account.findUnique({
        where: { id: accountId },
        select: { walletBalanceCents: true },
      }),
      context.prisma.walletEntry.findMany({
        where: { accountId },
        orderBy: { createdAt: "desc" },
        take: HISTORY_LIMIT,
        select: { id: true, amountCents: true, kind: true, label: true, createdAt: true },
      }),
      // Le voyage n'est lu que pour l'estimation. Un identifiant qui ne
      // correspond à rien de visible ne fait pas échouer la route : la cagnotte
      // existe indépendamment du carnet, et l'écran s'affiche sans estimation
      // plutôt que pas du tout.
      tripId
        ? context.prisma.memo.findFirst({
            where: { id: tripId, ...visibleToAccount(accountId) },
            select: {
              title: true,
              destinationCity: true,
              targetPageCount: true,
              pageCount: true,
            },
          })
        : Promise.resolve(null),
    ]);

    return serializeWallet(account?.walletBalanceCents ?? 0, entries, trip);
  });

  /**
   * Pose une écriture de cagnotte **à la main**, pour le développement.
   *
   * Pourquoi cette route existe : sans encaissement branché, il n'y a aucun
   * chemin depuis l'app vers un solde non nul. L'écran de la cagnotte pleine,
   * les deux natures de pastille, et surtout **les déductions du tunnel de
   * commande** ne se voient donc jamais. Le bac à sable de l'écran mutait un
   * objet en mémoire : le solde montait à l'écran mais le serveur n'en savait
   * rien, et le récapitulatif de commande — qui, lui, demande au serveur —
   * continuait d'annoncer un total sans déduction.
   *
   * Elle écrit une **vraie** écriture, dans la même transaction que le cache du
   * solde, exactement comme le fera le webhook de paiement. C'est donc aussi ce
   * qui vérifie que `balanceAfterCents` ne dérive pas.
   *
   * ⚠️ **Fermée en production**, comme les interrupteurs de l'app sont fermés
   * en release : c'est une route qui crée de l'argent.
   */
  app.post("/v1/wallet/debug-entry", async (request, reply) => {
    if (context.env.NODE_ENV === "production") {
      throw HttpError.notFound("Route inconnue.");
    }

    const accountId = accountIdOf(request);
    const body = debugEntryBody.parse(request.body ?? {});
    const amountCents = Math.round(body.amount * 100);

    if (amountCents === 0) {
      throw HttpError.badRequest("Une écriture de zéro ne dit rien.", "empty_entry");
    }

    const wallet = await context.prisma.$transaction(async (tx) => {
      const account = await tx.account.findUniqueOrThrow({
        where: { id: accountId },
        select: { walletBalanceCents: true },
      });

      // La cagnotte ne descend pas sous zéro : un débit plus grand que le solde
      // serait un découvert, ce que le registre ne sait pas représenter.
      const balanceAfter = account.walletBalanceCents + amountCents;
      if (balanceAfter < 0) {
        throw HttpError.badRequest("La cagnotte n'a pas de découvert.", "insufficient_funds");
      }

      await tx.walletEntry.create({
        data: {
          accountId,
          amountCents,
          balanceAfterCents: balanceAfter,
          kind: body.kind,
          label: body.label ?? null,
        },
      });

      // Le cache, **dans la même transaction** que l'écriture : c'est la règle
      // qui empêche les deux de diverger.
      await tx.account.update({
        where: { id: accountId },
        data: { walletBalanceCents: balanceAfter },
      });

      return balanceAfter;
    });

    context.logger.warn(
      { accountId, amountCents, kind: body.kind, balanceAfterCents: wallet },
      "Écriture de cagnotte posée à la main (bac à sable)",
    );

    return reply.code(201).send({ balance: Number((wallet / 100).toFixed(2)) });
  });

  /**
   * Recharger sa cagnotte.
   *
   * Ouvre une intention de paiement, et **rien d'autre** : le solde ne bouge
   * pas ici. C'est le webhook qui écrit au registre, une fois l'argent
   * réellement encaissé — le schéma le dit, « il n'y a pas d'état en attente :
   * une écriture n'existe qu'une fois l'argent réellement mouvementé ».
   *
   * La clé d'idempotence est tirée à chaque appel, contrairement à celle d'une
   * commande : recharger deux fois 20 € est une intention parfaitement
   * légitime, et deux appels doivent donner deux paiements.
   */
  app.post("/v1/wallet/topup", async (request, reply) => {
    const { amountCents } = topupBody.parse(request.body ?? {});
    const accountId = accountIdOf(request);

    if (context.env.STRIPE_SECRET_KEY === "" && context.env.NODE_ENV === "production") {
      throw HttpError.badRequest(
        "L'encaissement n'est pas configuré sur ce serveur.",
        "payments_unavailable",
      );
    }

    const customerId = await ensureStripeCustomer(context, accountId);

    const intent = await context.payments.createIntent({
      idempotencyKey: `topup:${randomUUID()}`,
      amountCents,
      currency: "eur",
      customerId,
      metadata: { kind: PAYMENT_KIND.walletTopup, accountId },
    });

    context.logger.info(
      { accountId, amountCents, intentId: intent.intentId },
      "Recharge de cagnotte ouverte",
    );

    return reply.code(201).send({
      clientSecret: intent.clientSecret,
      amountCents,
      currency: "eur",
      publishableKey: context.env.STRIPE_PUBLISHABLE_KEY,
    });
  });
}
