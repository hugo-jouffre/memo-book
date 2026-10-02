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
  /** Ce que lit le relevé et le reçu : « Carnet « Rome » — 2 exemplaires ». */
  description?: string;
  /**
   * L'adresse du reçu de Stripe. **Elle seule fait partir un reçu** : Stripe
   * n'envoie rien à un client sans adresse, et l'écran de confirmation en
   * promet un.
   */
  receiptEmail?: string | null;
  /** Où part le carnet. Stripe s'en sert pour évaluer la fraude. */
  shipping?: IntentShipping | null;
}

export interface IntentShipping {
  name: string;
  line1: string;
  line2: string | null;
  postalCode: string;
  city: string;
  /** ISO 3166-1 alpha-2. */
  country: string;
}

/** Ce qu'une intention attend encore — de quoi la reprendre ou la clore. */
export interface IntentState {
  /** `requires_payment_method`, `requires_action`, `processing`, `succeeded`, `canceled`… */
  status: string;
  amountCents: number;
  /** De quoi remonter la feuille de paiement. Jamais journalisé. */
  clientSecret: string | null;
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
  /**
   * Le montant de l'objet : ce que l'intention demande, ce qu'elle a reçu
   * (`amount_received` sur un `payment_intent.succeeded`), ou **le cumul
   * remboursé** sur un `charge.refunded`.
   */
  amountCents: number | null;
  /** ISO 4217 minuscule. */
  currency: string | null;
  /** Sur un `charge.refunded` : la charge est-elle remboursée **en entier** ? */
  fullyRefunded: boolean;
  /** Mode test ou réel — à comparer à la clé du serveur. */
  livemode: boolean;
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
  /** Relit une intention : ce qu'elle attend encore, et de quoi la reprendre. */
  retrieveIntent(intentId: string): Promise<IntentState>;
  /**
   * Annule une intention qui n'a pas abouti. **`false` si Stripe refuse** —
   * elle a réussi, ou un paiement est en cours. C'est Stripe qui tranche la
   * course entre une annulation et un paiement, pas nous : une fois annulée,
   * l'intention ne peut plus être payée.
   */
  cancelIntent(intentId: string): Promise<boolean>;
  /**
   * Ce qui laisse la feuille de paiement **montrer, enregistrer et retirer**
   * les cartes du compte. La clé ne vaut que pour ce client, et peu de temps.
   *
   * **Une clé éphémère, et pas une session client** : avec la version du SDK
   * iOS du dépôt (stripe-ios 24), les sessions client sont réservées à un
   * accès bêta (`@_spi(CustomerSessionBetaAccess)`). La clé éphémère est le
   * chemin stable — à condition d'être créée dans **la version d'API du SDK**,
   * que l'app envoie (`STPAPIClient.apiVersion`, « 2020-08-27 »).
   */
  createEphemeralKey(customerId: string, apiVersion: string): Promise<string>;
  /**
   * Enregistrer une carte sans payer — la gestion des moyens de paiement du
   * profil. Rend le secret de l'intention.
   */
  createSetupIntent(customerId: string): Promise<string>;
  /**
   * Vérifie la signature et rend l'événement.
   *
   * Prend le corps **brut**, pas l'objet JSON : la signature porte sur les
   * octets reçus. Reparser puis re-sérialiser change un espace et invalide
   * tout — c'est le piège numéro un des webhooks Stripe.
   */
  verifyEvent(rawBody: Buffer, signature: string): PaymentEvent;
}

/**
 * Les types d'événements qu'on traite. Tout le reste est acquitté et ignoré.
 *
 * ⚠️ **Le point de terminaison du tableau de bord doit être abonné à cette
 * liste exacte** — `docs/paiements.md` § Configuration. Un type absent ici
 * n'arrive jamais ; un type absent là-bas n'est jamais envoyé.
 */
export const HANDLED_EVENTS = [
  "payment_intent.succeeded",
  "payment_intent.payment_failed",
  "payment_intent.canceled",
  "charge.refunded",
  "charge.dispute.created",
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
        ...(request.description ? { description: request.description } : {}),
        ...(request.receiptEmail ? { receipt_email: request.receiptEmail } : {}),
        ...(request.shipping
          ? {
              shipping: {
                name: request.shipping.name,
                address: {
                  line1: request.shipping.line1,
                  ...(request.shipping.line2 ? { line2: request.shipping.line2 } : {}),
                  postal_code: request.shipping.postalCode,
                  city: request.shipping.city,
                  country: request.shipping.country,
                },
              },
            }
          : {}),
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

  async retrieveIntent(intentId: string): Promise<IntentState> {
    const intent = await this.stripe.paymentIntents.retrieve(intentId);
    return {
      status: intent.status,
      amountCents: intent.amount,
      clientSecret: intent.client_secret,
    };
  }

  async cancelIntent(intentId: string): Promise<boolean> {
    try {
      await this.stripe.paymentIntents.cancel(intentId);
      return true;
    } catch (cause) {
      // Déjà annulée : c'est le résultat voulu.
      const intent = await this.stripe.paymentIntents.retrieve(intentId);
      if (intent.status === "canceled") return true;
      // Réussie ou en cours : Stripe refuse, et il a raison. L'argent est
      // pris, ou va l'être — la commande ne s'annule pas.
      if (intent.status === "succeeded" || intent.status === "processing") return false;
      throw cause;
    }
  }

  async createEphemeralKey(customerId: string, apiVersion: string): Promise<string> {
    const key = await this.stripe.ephemeralKeys.create({ customer: customerId }, { apiVersion });
    if (!key.secret) throw new Error("Stripe a créé une clé éphémère sans secret.");
    return key.secret;
  }

  async createSetupIntent(customerId: string): Promise<string> {
    const intent = await this.stripe.setupIntents.create({
      customer: customerId,
      automatic_payment_methods: { enabled: true },
      usage: "off_session",
    });
    if (!intent.client_secret) {
      throw new Error("Stripe a créé une intention d'enregistrement sans `client_secret`.");
    }
    return intent.client_secret;
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

    return toPaymentEvent(event.id, event.type, event.data.object, event.livemode);
  }
}

/**
 * Extrait ce qui nous intéresse d'un objet Stripe, quel qu'il soit.
 *
 * Défensif par construction : Stripe ajoute des types d'événements sans
 * prévenir, et un champ absent doit donner `null` plutôt que faire échouer la
 * route — un webhook qui répond 500 est rejoué en boucle.
 */
function toPaymentEvent(
  id: string,
  type: string,
  object: unknown,
  livemode: boolean,
): PaymentEvent {
  const payload = (object ?? {}) as {
    id?: unknown;
    payment_intent?: unknown;
    amount?: unknown;
    amount_received?: unknown;
    amount_refunded?: unknown;
    refunded?: unknown;
    currency?: unknown;
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

  // Ce qui a vraiment bougé : le reçu d'une intention réussie, le cumul rendu
  // d'une charge remboursée, la demande sinon.
  const amount =
    type === "charge.refunded"
      ? payload.amount_refunded
      : type === "payment_intent.succeeded" && typeof payload.amount_received === "number"
        ? payload.amount_received
        : payload.amount;

  return {
    id,
    type,
    intentId,
    orderId: text(payload.metadata?.orderId),
    kind: text(payload.metadata?.kind),
    accountId: text(payload.metadata?.accountId),
    amountCents: typeof amount === "number" ? amount : null,
    currency: text(payload.currency),
    fullyRefunded: payload.refunded === true,
    livemode,
  };
}

/**
 * Encaissement simulé : aucune clé, aucun réseau, résultat déterministe.
 *
 * Le `clientSecret` fabriqué ne monte aucune feuille de paiement — c'est
 * voulu. Il permet de dérouler la création de commande de bout en bout dans
 * les tests sans qu'un oubli de configuration puisse faire croire, en
 * production, qu'un paiement a eu lieu.
 *
 * Les intentions vivent en mémoire, avec un statut que les tests règlent
 * (`settle`) : c'est ce qui permet de vérifier qu'une intention réussie ne
 * s'annule pas.
 */
export class FakePaymentGateway implements PaymentGateway {
  private readonly intents = new Map<string, IntentState>();

  /**
   * @param acceptsUnsignedEvents Faux par défaut. **Seule la suite de tests
   * l'allume** : en dehors d'elle, le simulé refuse tout webhook — sans quoi
   * un serveur parti sans clé aurait crédité n'importe quelle cagnotte sur un
   * simple JSON (audit du 01/10/2026).
   */
  constructor(private readonly acceptsUnsignedEvents = false) {}

  async createIntent(request: IntentRequest): Promise<IntentResult> {
    const digest = createHash("sha256")
      .update(request.idempotencyKey)
      .digest("hex")
      .slice(0, 24);
    const intentId = `pi_fake_${digest}`;
    const clientSecret = `pi_fake_${digest}_secret_fake`;
    if (!this.intents.has(intentId)) {
      this.intents.set(intentId, {
        status: "requires_payment_method",
        amountCents: request.amountCents,
        clientSecret,
      });
    }
    return { intentId, clientSecret };
  }

  async createCustomer(input: { accountId: string }): Promise<string> {
    const digest = createHash("sha256").update(input.accountId).digest("hex").slice(0, 24);
    return `cus_fake_${digest}`;
  }

  async retrieveIntent(intentId: string): Promise<IntentState> {
    const intent = this.intents.get(intentId);
    if (!intent) throw new Error(`Intention inconnue : ${intentId}.`);
    return intent;
  }

  async cancelIntent(intentId: string): Promise<boolean> {
    const intent = this.intents.get(intentId);
    if (!intent) return true;
    if (intent.status === "succeeded" || intent.status === "processing") return false;
    this.intents.set(intentId, { ...intent, status: "canceled" });
    return true;
  }

  async createEphemeralKey(customerId: string): Promise<string> {
    return `ek_test_fake_${customerId}`;
  }

  async createSetupIntent(customerId: string): Promise<string> {
    return `seti_fake_${customerId}_secret_fake`;
  }

  /** Les tests jouent ce que Stripe ferait : une intention payée, refusée… */
  settle(intentId: string, status: string): void {
    const intent = this.intents.get(intentId);
    if (intent) this.intents.set(intentId, { ...intent, status });
  }

  verifyEvent(rawBody: Buffer): PaymentEvent {
    if (!this.acceptsUnsignedEvents) {
      throw new Error(
        "Encaissement non configuré : STRIPE_SECRET_KEY est vide, aucun webhook n'est accepté.",
      );
    }

    const parsed = JSON.parse(rawBody.toString("utf8")) as {
      id?: string;
      type?: string;
      livemode?: boolean;
      data?: { object?: unknown };
    };

    return toPaymentEvent(
      parsed.id ?? "evt_fake",
      parsed.type ?? "payment_intent.succeeded",
      parsed.data?.object,
      parsed.livemode ?? false,
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
  // Sans clé, le simulé — qui ne croit un webhook non signé que dans la suite
  // de tests. En production, `loadEnv` a déjà refusé de démarrer.
  if (env.STRIPE_SECRET_KEY === "") return new FakePaymentGateway(env.NODE_ENV === "test");

  return new StripePaymentGateway(
    new Stripe(env.STRIPE_SECRET_KEY),
    env.STRIPE_WEBHOOK_SECRET,
  );
}
