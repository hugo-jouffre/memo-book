import { Prisma, type Subscription, type SubscriptionStatus } from "@prisma/client";
import type { AppContext } from "../context.js";
import { HttpError } from "../lib/httpError.js";
import type { AppStoreRenewal, AppStoreStatus, AppStoreTransaction } from "./appStore.js";
import { visibleToAccount } from "./memoOwnership.js";
import { APP_STORE_PRODUCTS, CATALOG_CURRENCY, isAcceptedAppStoreProduct } from "./subscriptionCatalog.js";

/**
 * L'abonnement StoreKit, recopié dans `subscriptions` — **Apple a le dernier
 * mot, on ne fait que tenir la copie à jour**.
 *
 * Deux portes y mènent, et elles écrivent la même chose :
 *
 * - **l'app**, juste après l'achat (`POST /v1/subscriptions/app-store`) : c'est
 *   ce qui ouvre le micro dans la seconde, sans attendre Apple ;
 * - **Apple**, à chaque événement (`POST /v1/webhooks/app-store`) : le
 *   renouvellement du mois, le renouvellement coupé dans les réglages iOS, le
 *   prélèvement qui échoue, le remboursement. L'app n'est pas ouverte pour ça.
 *
 * Une ligne par `originalTransactionId`, rouverte quand on se réabonne au
 * voyage suivant ; une ligne de `subscription_transactions` par période payée
 * — un mois, ou une semaine pour un ancien abonné de la semaine.
 *
 * **Passer de la semaine au mois** garde l'`originalTransactionId` (les deux
 * produits sont dans le même groupe « MemoBook ») : c'est la même ligne, qui
 * prend le produit, le rythme et le prix de la dernière transaction.
 */

/** Ce que l'état Apple devient dans nos colonnes. */
export interface StoreKitState {
  status: SubscriptionStatus;
  /** La fin de l'accès : période payée, délai de grâce, ou révocation. */
  renewsAt: Date | null;
  autoRenews: boolean | null;
}

/**
 * Traduit l'état Apple dans les statuts que lisent déjà l'accès illimité
 * (`hasUnlimitedAccess`, `subscriptions.ts`) et le profil — **sans rien leur
 * changer** :
 *
 * | Chez Apple | Ici | Accès |
 * |---|---|---|
 * | actif, renouvellement armé | `active` | oui |
 * | actif, renouvellement coupé | `cancelled` | jusqu'à `renewsAt` |
 * | délai de grâce | `past_due` | oui, c'est Apple qui l'accorde |
 * | nouvelle tentative de prélèvement | `expired` | non, la période n'est pas payée |
 * | expiré | `expired` | non |
 * | remboursé, révoqué | `expired` | non, dès la révocation |
 *
 * `status` vient des notifications ; l'app, elle, n'envoie qu'une transaction.
 * À défaut, on le déduit de la date d'expiration — et on garde ce qu'on savait
 * du renouvellement plutôt que de le supposer armé.
 */
export function storeKitState(input: {
  transaction: AppStoreTransaction;
  renewal: AppStoreRenewal | null;
  status: AppStoreStatus | null;
  previousAutoRenews: boolean | null;
  now: Date;
}): StoreKitState {
  const { transaction, renewal, now } = input;
  const autoRenews = renewal?.autoRenews ?? input.previousAutoRenews;

  if (transaction.revokedAt) {
    return { status: "expired", renewsAt: transaction.revokedAt, autoRenews: false };
  }

  const status =
    input.status ?? (transaction.expiresAt && transaction.expiresAt > now ? "active" : "expired");

  switch (status) {
    case "active":
      return {
        status: autoRenews === false ? "cancelled" : "active",
        renewsAt: transaction.expiresAt,
        autoRenews,
      };
    case "grace_period":
      return {
        status: "past_due",
        renewsAt: renewal?.gracePeriodEndsAt ?? transaction.expiresAt,
        autoRenews,
      };
    case "billing_retry":
      return { status: "expired", renewsAt: transaction.expiresAt, autoRenews };
    case "revoked":
      return { status: "expired", renewsAt: now, autoRenews: false };
    case "expired":
      return { status: "expired", renewsAt: transaction.expiresAt, autoRenews: false };
  }
}

export interface ApplyStoreKitInput {
  /** Le compte qui envoie la transaction ; absent quand c'est Apple qui notifie. */
  accountId?: string;
  transaction: AppStoreTransaction;
  renewal: AppStoreRenewal | null;
  status: AppStoreStatus | null;
  /** Le voyage que l'achat finance, quand l'app le dit. */
  memoId?: string;
  /**
   * Quand Apple a signé ce qu'on applique — la notification, s'il y en a une ;
   * la transaction sinon. C'est ce qui ordonne les événements.
   */
  signedAt?: Date;
}

/**
 * Inscrit une transaction App Store : met la ligne `subscriptions` à l'état
 * qu'Apple décrit, et la période payée au registre.
 *
 * **Sûr à rejouer**, parce qu'il le sera : l'app renvoie sa transaction à
 * chaque lancement tant qu'elle ne l'a pas finie, et Apple renvoie sa
 * notification jusqu'au 200. La période ne s'inscrit qu'une fois
 * (`transactionId` unique), et **un événement plus ancien que le dernier
 * appliqué ne touche pas à l'état** — Apple ne promet aucun ordre, et un
 * renouvellement arrivé en retard rouvrirait un abonnement déjà coupé.
 *
 * Rend `null` quand la transaction ne mène à aucun compte : une notification
 * pour un achat dont l'app n'a jamais parlé, et qui ne porte pas
 * d'`appAccountToken`. Il n'y a alors personne à qui ouvrir l'abonnement.
 */
export async function applyStoreKitTransaction(
  context: AppContext,
  input: ApplyStoreKitInput,
): Promise<Subscription | null> {
  if (!isAcceptedAppStoreProduct(input.transaction.productId)) {
    throw HttpError.badRequest(
      `Produit App Store inconnu : ${input.transaction.productId}.`,
      "unknown_product",
    );
  }

  try {
    return await writeStoreKitTransaction(context, input);
  } catch (cause) {
    // L'app et Apple parlent souvent **en même temps** du même achat — le
    // retour de l'achat et la notification `SUBSCRIBED` partent ensemble.
    // Les deux tentent de créer la ligne ; l'unicité en laisse passer une,
    // et la seconde relit et met à jour.
    if (cause instanceof Prisma.PrismaClientKnownRequestError && cause.code === "P2002") {
      return writeStoreKitTransaction(context, input);
    }
    throw cause;
  }
}

async function writeStoreKitTransaction(
  context: AppContext,
  input: ApplyStoreKitInput,
): Promise<Subscription | null> {
  const { prisma } = context;
  const { transaction } = input;
  const signedAt = input.signedAt ?? transaction.signedAt;

  const existing = await prisma.subscription.findUnique({
    where: { providerSubscriptionId: transaction.originalTransactionId },
  });

  if (input.accountId !== undefined) {
    // L'achat a été fait **depuis un autre compte MemoBook** sur le même
    // téléphone : l'`appAccountToken` est celui du compte qui a payé. Ouvrir
    // l'abonnement à celui-ci en ferait deux pour un seul paiement.
    // Un compte **supprimé** depuis ne compte pas : Apple continue de prélever
    // l'identifiant Apple, et le nouveau compte doit pouvoir le restaurer.
    if (
      transaction.appAccountToken !== null &&
      transaction.appAccountToken !== input.accountId &&
      (await prisma.account.findUnique({
        where: { id: transaction.appAccountToken },
        select: { id: true },
      })) !== null
    ) {
      throw new HttpError(
        403,
        "Cet achat a été fait depuis un autre compte MemoBook.",
        "transaction_account_mismatch",
      );
    }
    if (existing && existing.accountId !== input.accountId) {
      throw new HttpError(
        409,
        "Cet abonnement Apple est déjà rattaché à un autre compte MemoBook.",
        "subscription_owned_elsewhere",
      );
    }
  }

  const accountId = existing?.accountId ?? input.accountId ?? transaction.appAccountToken;
  // (Quand c'est l'app qui envoie, `input.accountId` passe avant le jeton d'un
  // compte supprimé.)
  if (!accountId) return null;

  const account = await prisma.account.findUnique({ where: { id: accountId }, select: { id: true } });
  if (!account) return null;

  const memoId = input.memoId ? await visibleMemoId(context, accountId, input.memoId) : null;
  const state = storeKitState({
    transaction,
    renewal: input.renewal,
    status: input.status,
    previousAutoRenews: existing?.autoRenews ?? null,
    now: new Date(),
  });

  // Une transaction **sans statut** (l'app rejoue `Transaction.unfinished` :
  // un vieux renouvellement) ne raccourcit jamais la période connue. Seule
  // une révocation, ou un statut d'Apple, peut la faire reculer.
  const shortensKnownPeriod =
    input.status === null &&
    transaction.revokedAt === null &&
    existing?.renewsAt != null &&
    (state.renewsAt === null || state.renewsAt < existing.renewsAt);

  const isStale =
    shortensKnownPeriod ||
    (existing?.providerUpdatedAt !== null &&
      existing?.providerUpdatedAt !== undefined &&
      signedAt < existing.providerUpdatedAt);

  // Le rythme et le prix **du produit de cette transaction** : un abonné qui
  // passe de la semaine au mois garde sa ligne, qui doit dire « month » et
  // 4,99 € dès la première transaction mensuelle. Le prix d'Apple prime ; le
  // catalogue ne sert qu'aux transactions qui ne le portent pas.
  const product = APP_STORE_PRODUCTS[transaction.productId]!;

  return prisma.$transaction(async (tx) => {
    const fields = {
      status: state.status,
      renewsAt: state.renewsAt,
      autoRenews: state.autoRenews,
      cancelledAt: cancelledAtFor(state.status, existing?.cancelledAt ?? null, signedAt),
      environment: transaction.environment,
      providerUpdatedAt: signedAt,
      productId: transaction.productId,
      interval: product.interval,
      priceCents: transaction.priceCents ?? product.priceCents,
      ...(transaction.currency === null ? {} : { currency: transaction.currency }),
      ...(memoId === null ? {} : { memoId }),
    };

    const subscription = isStale && existing
      ? existing
      : existing
        ? await tx.subscription.update({ where: { id: existing.id }, data: fields })
        : await tx.subscription.create({
            data: {
              ...fields,
              accountId,
              provider: "storekit",
              currency: transaction.currency ?? CATALOG_CURRENCY,
              providerSubscriptionId: transaction.originalTransactionId,
              startedAt: transaction.purchasedAt,
            },
          });

    // La période payée, même quand l'événement arrive en retard : l'état ne
    // bouge pas, mais l'argent, lui, a bien été encaissé.
    await tx.subscriptionTransaction.upsert({
      where: { transactionId: transaction.transactionId },
      create: {
        subscriptionId: subscription.id,
        memoId: subscription.memoId,
        transactionId: transaction.transactionId,
        originalTransactionId: transaction.originalTransactionId,
        productId: transaction.productId,
        purchasedAt: transaction.purchasedAt,
        expiresAt: transaction.expiresAt,
        priceCents: transaction.priceCents,
        currency: transaction.currency,
        environment: transaction.environment,
        revokedAt: transaction.revokedAt,
      },
      // Seule la révocation change après coup : Apple rembourse une période
      // déjà inscrite.
      update: { revokedAt: transaction.revokedAt },
    });

    return subscription;
  });
}

/**
 * Le jour de la résiliation. Posé une fois, au premier événement qui ferme ;
 * effacé quand l'abonnement repart — un réabonnement n'est pas une
 * résiliation.
 */
function cancelledAtFor(status: SubscriptionStatus, previous: Date | null, signedAt: Date): Date | null {
  if (status === "active" || status === "trialing" || status === "past_due") return null;
  return previous ?? signedAt;
}

/**
 * Le voyage annoncé par l'app, s'il est bien à ce compte. Un identifiant faux
 * ne fait pas échouer l'achat — l'argent est déjà parti —, il est ignoré.
 */
async function visibleMemoId(
  context: AppContext,
  accountId: string,
  memoId: string,
): Promise<string | null> {
  const memo = await context.prisma.memo.findFirst({
    where: { AND: [{ id: memoId }, visibleToAccount(accountId)] },
    select: { id: true },
  });
  return memo?.id ?? null;
}
