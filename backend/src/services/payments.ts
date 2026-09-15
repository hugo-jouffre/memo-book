import { createHash } from "node:crypto";
import Stripe from "stripe";
import type { Env } from "../env.js";

/**
 * L'encaissement — carnets imprimés et recharges de cagnotte.
 *
 * **Jamais l'abonnement.** Celui-là est un service numérique : Apple impose
 * StoreKit, et le faire passer par Stripe depuis l'app ferait rejeter le
 * binaire. `Subscription.provider` porte les deux fournisseurs pour cette
 * raison, et rien ici ne touche à l'abonnement.
 *
 * Même forme que le reste du dépôt — une interface, une implémentation réelle,
 * une simulée, une fabrique pilotée par l'environnement : la suite de tests
 * tourne sans clé et sans réseau, comme pour la transcription et le rendu.
 */

/** Ce qu'on demande à encaisser. */
export interface IntentRequest {
  /**
   * Ce qui rend l'appel rejouable sans risque.
   *
   * Pour une commande, c'est son identifiant : un double appui sur
   * « Commander » ne doit pas créer deux intentions, donc pas deux débits.
   * Pour une recharge de cagnotte, c'est un identifiant tiré à chaque
   * tentative — recharger deux fois 20 € est une intention légitime, pas un
   * doublon.
   */
  idempotencyKey: string;
  amountCents: number;
  /** ISO 4217 minuscule. Le compte est en euros. */
  currency: string;
  /** Le client Stripe du compte, quand il en a déjà un. */
  customerId: string | null;
  /** Recopié dans le tableau de bord Stripe : c'est ce qui rend un litige lisible. */
  metadata: Record<string, string>;
}

export interface IntentResult {
  intentId: string;
  /** Ce que l'app passe à la feuille de paiement. Jamais journalisé. */
  clientSecret: string;
}

/** Ce qu'un webhook nous apprend, une fois la signature vérifiée. */
export interface PaymentEvent {
  /** L'identifiant de l'événement. Unique, et c'est lui qui bloque un rejeu. */
  id: string;
  type: string;
  /** L'intention concernée, quand l'événement en porte une. */
  intentId: string | null;
  /** `metadata.orderId` posé à la création de l'intention. */
  orderId: string | null;
  /** `metadata.kind` : ce que ce paiement finance. */
  kind: string | null;
  /** `metadata.accountId` : à qui créditer une recharge de cagnotte. */
  accountId: string | null;
  amountCents: number | null;
}

export interface PaymentGateway {
  createIntent(request: IntentRequest): Promise<IntentResult>;
  /**
   * Crée le client Stripe d'un compte.
   *
   * Il porte les moyens de paiement enregistrés et, un jour, l'historique des
   * recharges. Créé à la première dépense et non à l'ouverture du compte : un
   * compte qui n'achète jamais rien n'a pas à exister chez Stripe.
   */
  createCustomer(input: { accountId: string; email: string | null }): Promise<string>;
  /**
   * Vérifie la signature et rend l'événement.
   *
   * Prend le corps **brut**, pas l'objet JSON : la signature porte sur les
   * octets reçus. Reparser puis re-sérialiser change un espace et invalide
   * tout — c'est le piège numéro un des webhooks Stripe.
   */
  verifyEvent(rawBody: Buffer, signature: string): PaymentEvent;
}

/** Les types d'événements qu'on traite. Tout le reste est acquitté et ignoré. */
export const HANDLED_EVENTS = [
  "payment_intent.succeeded",
  "payment_intent.payment_failed",
  "charge.refunded",
] as const;

export class StripePaymentGateway implements PaymentGateway {
  constructor(
    private readonly stripe: Stripe,
    private readonly webhookSecret: string,
  ) {}

  async createIntent(request: IntentRequest): Promise<IntentResult> {
    const intent = await this.stripe.paymentIntents.create(
      {
        amount: request.amountCents,
        currency: request.currency,
        ...(request.customerId ? { customer: request.customerId } : {}),
        // Laisse le tableau de bord décider des moyens acceptés : activer
        // Apple Pay deviendra une case à cocher, pas une livraison de serveur.
        automatic_payment_methods: { enabled: true },
        metadata: request.metadata,
      },
      // Rejouée avec la même clé, Stripe rend **la même** intention au lieu
      // d'en créer une seconde. C'est ce qui rend la route sûre à réessayer.
      { idempotencyKey: request.idempotencyKey },
    );

    if (!intent.client_secret) {
      throw new Error("Stripe a créé une intention sans `client_secret`.");
    }

    return { intentId: intent.id, clientSecret: intent.client_secret };
  }

  async createCustomer(input: { accountId: string; email: string | null }): Promise<string> {
    const customer = await this.stripe.customers.create(
      {
        ...(input.email ? { email: input.email } : {}),
        metadata: { accountId: input.accountId },
      },
      // Un compte n'a qu'un client Stripe. Deux appels concurrents — deux
      // onglets, deux appareils — ne doivent pas en créer deux.
      { idempotencyKey: `customer:${input.accountId}` },
    );
    return customer.id;
  }

  verifyEvent(rawBody: Buffer, signature: string): PaymentEvent {
    if (this.webhookSecret === "") {
      throw new Error(
        "STRIPE_WEBHOOK_SECRET est vide : impossible de vérifier la signature. " +
          "En local, le secret est celui qu'affiche `stripe listen`.",
      );
    }

    // Lève si la signature ne colle pas. On laisse remonter : un webhook non
    // signé doit répondre 400, pas être traité.
    const event = this.stripe.webhooks.constructEvent(
      rawBody,
      signature,
      this.webhookSecret,
    );

    return toPaymentEvent(event.id, event.type, event.data.object);
  }
}

/**
 * Extrait ce qui nous intéresse d'un objet Stripe, quel qu'il soit.
 *
 * Défensif par construction : Stripe ajoute des types d'événements sans
 * prévenir, et un champ absent doit donner `null` plutôt que faire échouer la
 * route — un webhook qui répond 500 est rejoué en boucle.
 */
function toPaymentEvent(id: string, type: string, object: unknown): PaymentEvent {
  const payload = (object ?? {}) as {
    id?: unknown;
    payment_intent?: unknown;
    amount?: unknown;
    amount_refunded?: unknown;
    metadata?: { orderId?: unknown; kind?: unknown; accountId?: unknown };
  };

  const text = (value: unknown): string | null =>
    typeof value === "string" && value !== "" ? value : null;

  // Sur un `charge.*`, l'intention est dans `payment_intent` ; sur un
  // `payment_intent.*`, c'est l'objet lui-même.
  const intentId =
    typeof payload.payment_intent === "string"
      ? payload.payment_intent
      : typeof payload.id === "string" && payload.id.startsWith("pi_")
        ? payload.id
        : null;

  const amount = type === "charge.refunded" ? payload.amount_refunded : payload.amount;

  return {
    id,
    type,
    intentId,
    orderId: text(payload.metadata?.orderId),
    kind: text(payload.metadata?.kind),
    accountId: text(payload.metadata?.accountId),
    amountCents: typeof amount === "number" ? amount : null,
  };
}

/**
 * Encaissement simulé : aucune clé, aucun réseau, résultat déterministe.
 *
 * Le `clientSecret` fabriqué ne monte aucune feuille de paiement — c'est
 * voulu. Il permet de dérouler la création de commande de bout en bout dans
 * les tests sans qu'un oubli de configuration puisse faire croire, en
 * production, qu'un paiement a eu lieu.
 */
export class FakePaymentGateway implements PaymentGateway {
  async createIntent(request: IntentRequest): Promise<IntentResult> {
    const digest = createHash("sha256")
      .update(request.idempotencyKey)
      .digest("hex")
      .slice(0, 24);
    return {
      intentId: `pi_fake_${digest}`,
      clientSecret: `pi_fake_${digest}_secret_fake`,
    };
  }

  async createCustomer(input: { accountId: string }): Promise<string> {
    const digest = createHash("sha256").update(input.accountId).digest("hex").slice(0, 24);
    return `cus_fake_${digest}`;
  }

  verifyEvent(rawBody: Buffer): PaymentEvent {
    const parsed = JSON.parse(rawBody.toString("utf8")) as {
      id?: string;
      type?: string;
      data?: { object?: unknown };
    };

    return toPaymentEvent(
      parsed.id ?? "evt_fake",
      parsed.type ?? "payment_intent.succeeded",
      parsed.data?.object,
    );
  }
}

/**
 * Le vrai Stripe dès qu'une clé secrète est posée, le simulé sinon.
 *
 * Volontairement **indépendant de `PIPELINE_MODE`** : celui-ci décide de la
 * transcription et de la mise en page, qui coûtent des jetons. L'argent est un
 * axe à lui, et on ne veut pas qu'un `PIPELINE_MODE=live` posé pour travailler
 * la maquette mette en route l'encaissement par effet de bord.
 */
export function createPaymentGateway(env: Env): PaymentGateway {
  if (env.STRIPE_SECRET_KEY === "") return new FakePaymentGateway();

  return new StripePaymentGateway(
    new Stripe(env.STRIPE_SECRET_KEY),
    env.STRIPE_WEBHOOK_SECRET,
  );
}
