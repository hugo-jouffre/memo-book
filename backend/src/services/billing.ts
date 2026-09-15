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
