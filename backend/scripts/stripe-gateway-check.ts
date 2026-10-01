import { randomUUID } from "node:crypto";
import Stripe from "stripe";
import { loadEnv } from "../src/env.js";
import { StripePaymentGateway } from "../src/services/payments.js";

/**
 * Ce que le simulé ne peut pas prouver : **Stripe accepte-t-il nos appels ?**
 *
 * Les tests passent par `FakePaymentGateway`, qui ne valide aucun paramètre. Ce
 * script joue chaque méthode du vrai gateway contre le compte de la clé posée
 * (en mode test seulement) : client, clé éphémère dans la version d'API du
 * SDK iOS, intention d'enregistrement, intention de
 * paiement avec reçu et adresse, relecture, annulation, annulation refusée
 * d'une intention payée.
 *
 * `npm run stripe:gateway-check` — ne touche ni la base ni le serveur.
 */
async function main(): Promise<void> {
  const env = loadEnv();
  if (!env.STRIPE_SECRET_KEY.startsWith("sk_test_")) {
    throw new Error("Ce contrôle ne tourne qu'avec une clé de test (sk_test_…).");
  }

  const stripe = new Stripe(env.STRIPE_SECRET_KEY);
  const gateway = new StripePaymentGateway(stripe, env.STRIPE_WEBHOOK_SECRET);
  const step = (label: string) => console.log(`✓ ${label}`);

  const customerId = await gateway.createCustomer({
    accountId: `gateway-check-${randomUUID()}`,
    email: "gateway-check@memobook.test",
  });
  step(`client ${customerId}`);

  // La version d'API que pin stripe-ios 24 (`STPAPIClient.apiVersion`).
  const key = await gateway.createEphemeralKey(customerId, "2020-08-27");
  if (!key.startsWith("ek_")) throw new Error("Clé éphémère inattendue.");
  step("clé éphémère du client (feuille de paiement + CustomerSheet)");

  const setup = await gateway.createSetupIntent(customerId);
  if (!setup.startsWith("seti_")) throw new Error("Intention d'enregistrement inattendue.");
  step("intention d'enregistrement");

  const intent = await gateway.createIntent({
    idempotencyKey: `gateway-check:${randomUUID()}`,
    amountCents: 4_990,
    currency: "eur",
    customerId,
    metadata: { kind: "book_order", orderId: "gateway-check" },
    description: "Carnet « Contrôle du gateway »",
    receiptEmail: "gateway-check@memobook.test",
    shipping: {
      name: "Clara Martin",
      line1: "12 rue des Lilas",
      line2: null,
      postalCode: "44000",
      city: "Nantes",
      country: "FR",
    },
  });
  step(`intention ${intent.intentId}`);

  const state = await gateway.retrieveIntent(intent.intentId);
  if (state.amountCents !== 4_990 || !state.clientSecret) throw new Error("Relecture inattendue.");
  step(`relecture : ${state.status}`);

  if (!(await gateway.cancelIntent(intent.intentId))) throw new Error("Annulation refusée.");
  if (!(await gateway.cancelIntent(intent.intentId))) throw new Error("Seconde annulation refusée.");
  step("annulation, puis seconde annulation sans erreur");

  // Une intention payée ne s'annule pas : c'est ce qui tranche la course entre
  // le ménage et un paiement.
  const paid = await stripe.paymentIntents.create({
    amount: 1_000,
    currency: "eur",
    customer: customerId,
    payment_method: "pm_card_visa",
    confirm: true,
    automatic_payment_methods: { enabled: true, allow_redirects: "never" },
  });
  if (paid.status !== "succeeded") throw new Error(`Paiement de test : ${paid.status}`);
  if (await gateway.cancelIntent(paid.id)) throw new Error("Une intention payée a été annulée.");
  step("une intention payée refuse l'annulation");
}

main().catch((error: unknown) => {
  console.error(error instanceof Error ? error.message : error);
  process.exit(1);
});
