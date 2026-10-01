import type { AppContext } from "../context.js";

/**
 * Ce qu'un paiement finance, recopié dans `metadata.kind` de chaque intention.
 *
 * **C'est le webhook qui en a besoin** : il reçoit un événement et doit savoir
 * s'il tient une commande à expédier ou une cagnotte à créditer. Le déduire de
 * la présence d'un `orderId` marcherait aujourd'hui et casserait au premier
 * troisième usage.
 *
 * ⚠️ **Aucune valeur d'abonnement ici, et il ne faut pas en ajouter.**
 * L'abonnement passe par StoreKit : Apple impose l'achat intégré pour un
 * service numérique, et l'encaisser par Stripe ferait rejeter le binaire.
 */
export const PAYMENT_KIND = {
  /** Un carnet imprimé — un bien physique, donc hors achat intégré. */
  bookOrder: "book_order",
  /** Une recharge de cagnotte, qui ne financera que du physique. */
  walletTopup: "wallet_topup",
} as const;

/**
 * Le client Stripe du compte, créé s'il n'existe pas encore.
 *
 * **À la première dépense, pas à l'ouverture du compte** : un compte qui
 * n'achète jamais rien n'a pas à exister chez Stripe. L'identifiant est ensuite
 * stocké sur `accounts.stripeCustomerId`, qui est unique.
 *
 * Deux appels concurrents ne créent pas deux clients : la création côté Stripe
 * porte une clé d'idempotence tirée de l'identifiant de compte, et l'écriture
 * locale repasse par une lecture. Au pire, on écrit deux fois le même
 * identifiant.
 */
export async function ensureStripeCustomer(
  context: AppContext,
  accountId: string,
): Promise<string | null> {
  const account = await context.prisma.account.findUnique({
    where: { id: accountId },
    select: { stripeCustomerId: true, email: true },
  });

  if (!account) return null;
  if (account.stripeCustomerId) return account.stripeCustomerId;

  const customerId = await context.payments.createCustomer({
    accountId,
    email: account.email,
  });

  await context.prisma.account.update({
    where: { id: accountId },
    data: { stripeCustomerId: customerId },
  });

  return customerId;
}

/**
 * Ce que la feuille de paiement de l'app reçoit : l'intention à régler, la clé
 * publique, et **le client Stripe du compte avec sa session** — c'est elle qui
 * fait apparaître les cartes déjà enregistrées, proposer « Enregistrer pour la
 * prochaine fois », et retirer une carte, sans que l'app touche jamais un
 * numéro (01/10/2026 : l'app avait son propre formulaire de carte, qui ne
 * servait à rien et n'aurait jamais dû exister).
 *
 * Une session qui échoue ne fait pas échouer le paiement : la feuille s'ouvre
 * alors sans cartes enregistrées, et on peut toujours payer.
 */
export async function paymentTicket(
  context: AppContext,
  input: { customerId: string | null; clientSecret: string; amountCents: number },
) {
  let customerSessionClientSecret: string | null = null;
  if (input.customerId) {
    try {
      customerSessionClientSecret = await context.payments.createCustomerSession(input.customerId);
    } catch (cause) {
      context.logger.warn({ err: cause }, "Session client Stripe indisponible : feuille sans cartes enregistrées");
    }
  }

  return {
    paidFromWallet: false,
    clientSecret: input.clientSecret,
    amountCents: input.amountCents,
    currency: "eur",
    publishableKey: context.env.STRIPE_PUBLISHABLE_KEY,
    customerId: customerSessionClientSecret ? input.customerId : null,
    customerSessionClientSecret,
  };
}
