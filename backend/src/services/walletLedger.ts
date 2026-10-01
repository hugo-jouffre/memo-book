import { Prisma, type PrismaClient, type WalletEntry, type WalletEntryKind } from "@prisma/client";

/**
 * Le registre de la cagnotte — la seule porte par laquelle un solde bouge.
 *
 * Trois invariants, et ils tiennent tous les trois **dans la base**, pas dans
 * le code appelant :
 *
 * 1. **Une écriture et son solde sont posés ensemble.** `accounts.
 *    walletBalanceCents` n'est qu'un cache de la somme du registre. Les
 *    séparer, c'est accepter qu'un incident laisse un solde qui ment.
 * 2. **Deux écritures simultanées se rangent.** Le solde est lu puis réécrit :
 *    sans verrou, deux recharges parties en même temps liraient le même solde
 *    de départ et la seconde effacerait la première. D'où le `FOR UPDATE` sur
 *    la ligne du compte.
 * 3. **Un même événement Stripe n'écrit qu'une fois.** `stripeEventId` est
 *    unique : c'est la contrainte qui bloque un rejeu, pas une vérification
 *    applicative qui aurait sa propre fenêtre de course.
 */

/** Le nom de colonne tel qu'il existe vraiment en base — camelCase, donc cité. */
const BALANCE_COLUMN = Prisma.raw('"walletBalanceCents"');

export interface LedgerWrite {
  accountId: string;
  /** Signé : positif au crédit, négatif au débit. */
  amountCents: number;
  kind: WalletEntryKind;
  label?: string | null;
  /** L'événement Stripe à l'origine. Nul pour un geste commercial. */
  stripeEventId?: string | null;
  printOrderId?: string | null;
  /**
   * Ce qui empêche l'écriture d'être posée deux fois quand elle ne vient pas
   * d'un événement Stripe — voir `WalletEntry.idempotencyKey`. Un second appel
   * avec la même clé rend `duplicate`, sans rien écrire.
   */
  idempotencyKey?: string | null;
  /** L'intention d'où vient l'argent — ce qu'un remboursement retrouvera. */
  stripePaymentIntentId?: string | null;
  /**
   * Un débit **plafonné au solde** au lieu d'être refusé. Pour reprendre une
   * recharge remboursée : la carte a déjà rendu l'argent, et s'il a été
   * dépensé entre-temps, on reprend ce qui reste — le reste se voit dans
   * `clampedCents` et part au support.
   */
  clampToBalance?: boolean;
}

/** Ce qu'une écriture a produit, ou pourquoi elle n'a rien produit. */
export type LedgerResult =
  | { outcome: "written"; entry: WalletEntry; balanceCents: number; clampedCents: number }
  /** L'événement avait déjà été écrit. Ce n'est pas une erreur. */
  | { outcome: "duplicate" }
  /** Le solde ne couvrait pas le débit. Rien n'a bougé. */
  | { outcome: "insufficient"; balanceCents: number; missingCents: number };

/**
 * Écrit une ligne de registre et déplace le solde, en une transaction.
 *
 * Un débit qui dépasse le solde ne passe pas : la cagnotte ne va jamais dans le
 * rouge. C'est vérifié **après** le verrou, pas avant — sinon deux débits
 * concurrents pourraient passer le contrôle chacun de leur côté.
 */
export async function writeLedgerEntry(
  prisma: PrismaClient,
  write: LedgerWrite,
): Promise<LedgerResult> {
  try {
    return await prisma.$transaction(async (tx) => {
      // `FOR UPDATE` verrouille la ligne du compte jusqu'à la fin de la
      // transaction : toute autre écriture sur cette cagnotte attend ici.
      // Pas de `::uuid` sur l'identifiant : `String @id @default(uuid())` se
      // matérialise en `TEXT` côté Postgres, et comparer `text = uuid` échoue
      // avec « operator does not exist ». Le contenu est bien un UUID, la
      // colonne ne l'est pas.
      const locked = await tx.$queryRaw<{ balance: number }[]>`
        SELECT ${BALANCE_COLUMN} AS balance
        FROM accounts
        WHERE id = ${write.accountId}
        FOR UPDATE
      `;

      const current = locked[0]?.balance;
      if (current === undefined) {
        throw new Error(`Compte ${write.accountId} introuvable.`);
      }

      // Plafonné : on ne reprend jamais plus que ce qu'il y a.
      const amountCents =
        write.clampToBalance && write.amountCents < 0
          ? Math.max(write.amountCents, -current)
          : write.amountCents;
      const clampedCents = amountCents - write.amountCents;
      const next = current + amountCents;

      if (next < 0) {
        return {
          outcome: "insufficient" as const,
          balanceCents: current,
          missingCents: -next,
        };
      }

      const entry = await tx.walletEntry.create({
        data: {
          accountId: write.accountId,
          amountCents,
          balanceAfterCents: next,
          kind: write.kind,
          label: write.label ?? null,
          stripeEventId: write.stripeEventId ?? null,
          printOrderId: write.printOrderId ?? null,
          idempotencyKey: write.idempotencyKey ?? null,
          stripePaymentIntentId: write.stripePaymentIntentId ?? null,
        },
      });

      await tx.account.update({
        where: { id: write.accountId },
        data: { walletBalanceCents: next },
      });

      return { outcome: "written" as const, entry, balanceCents: next, clampedCents };
    });
  } catch (cause) {
    // P2002 sur `stripeEventId` : le même événement a déjà été écrit. C'est le
    // rejeu normal de Stripe, pas un incident — et c'est bien la base qui l'a
    // arbitré, sans fenêtre de course possible.
    if (
      cause instanceof Prisma.PrismaClientKnownRequestError &&
      cause.code === "P2002" &&
      (write.stripeEventId || write.idempotencyKey)
    ) {
      return { outcome: "duplicate" };
    }
    throw cause;
  }
}
