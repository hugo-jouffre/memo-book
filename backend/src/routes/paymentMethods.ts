import type { FastifyInstance } from "fastify";
import { z } from "zod";
import type { AppContext } from "../context.js";
import { HttpError } from "../lib/httpError.js";
import { accountIdOf } from "../plugins/auth.js";
import { ensureStripeCustomer, stripeApiVersionSchema } from "../services/billing.js";

const ephemeralKeyBody = z.object({ stripeApiVersion: stripeApiVersionSchema });

/**
 * Les moyens de paiement du compte — **tenus par Stripe, montrés par Stripe**.
 *
 * L'app avait son propre formulaire de carte (numéro, échéance, cryptogramme)
 * qui ne gardait que les quatre derniers chiffres en mémoire et ne parlait à
 * personne (audit du 01/10/2026). Il est remplacé par la feuille « Moyens de
 * paiement » de Stripe (`CustomerSheet`), que ces deux routes alimentent : un
 * numéro de carte ne passe jamais ni par l'app, ni par ce serveur.
 */
export function registerPaymentMethodRoutes(app: FastifyInstance, context: AppContext): void {
  /**
   * La clé qui laisse la feuille lister, ajouter et retirer les cartes du
   * compte — dans la version d'API du SDK de l'app (voir `paymentTicket`). Le
   * client Stripe est créé s'il n'existe pas encore : ouvrir cette feuille,
   * c'est vouloir en enregistrer une.
   */
  app.post("/v1/payments/ephemeral-key", async (request) => {
    const { stripeApiVersion } = ephemeralKeyBody.parse(request.body ?? {});
    const customerId = await customerOf(context, accountIdOf(request));
    return {
      customerId,
      ephemeralKeySecret: await context.payments.createEphemeralKey(customerId, stripeApiVersion),
      publishableKey: context.env.STRIPE_PUBLISHABLE_KEY,
    };
  });

  /**
   * Une intention d'enregistrement : ce que la feuille confirme quand on ajoute
   * une carte hors paiement. Une par ajout — la feuille la demande au moment
   * où l'on valide.
   */
  app.post("/v1/payments/setup-intent", async (request) => {
    const customerId = await customerOf(context, accountIdOf(request));
    return { clientSecret: await context.payments.createSetupIntent(customerId) };
  });
}

async function customerOf(context: AppContext, accountId: string): Promise<string> {
  const customerId = await ensureStripeCustomer(context, accountId);
  if (!customerId) throw HttpError.notFound("Compte introuvable.");
  return customerId;
}
