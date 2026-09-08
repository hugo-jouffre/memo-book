import type { Prisma, PrismaClient } from "@prisma/client";
import type { AppContext } from "../context.js";

/**
 * Supprimer pour de bon : un carnet, ou un compte entier.
 *
 * Écrit ici une seule fois parce que les deux suppressions ont les mêmes
 * chausse-trappes, et qu'une seule d'entre elles corrigée est un dépôt qui fuit
 * à moitié :
 *
 *  1. `print_orders.renderId` est en `RESTRICT`. La cascade depuis `memos`
 *     n'ordonne pas la suppression des commandes avant celle des rendus : on
 *     les efface donc à la main, d'abord.
 *  2. `media_assets` n'est référencée *que* par `entries.mediaId`, et cette
 *     clé est en `SET NULL`. Rien ne nettoie la table : sans cette passe, les
 *     lignes — et les fichiers derrière — resteraient indéfiniment.
 *  3. Le stockage S3 ne participe pas à la transaction. Les objets sont donc
 *     effacés **après** la validation : au pire un fichier survit à sa ligne,
 *     jamais l'inverse.
 */

export interface DeletionReport {
  memos: number;
  entries: number;
  mediaObjects: number;
  /** Voyages qui ont changé de main plutôt que d'être supprimés. */
  transferredMemos?: number;
}

/** Les médias attachés aux souvenirs de ces carnets, lignes et fichiers. */
async function mediaOf(prisma: PrismaClient, memoIds: readonly string[]) {
  const entries = await prisma.entry.findMany({
    where: { memoId: { in: [...memoIds] } },
    select: { mediaId: true },
  });

  const mediaIds = entries
    .map((entry) => entry.mediaId)
    .filter((id): id is string => id !== null);

  const assets = await prisma.mediaAsset.findMany({
    where: { id: { in: mediaIds } },
    select: { storageKey: true, originalStorageKey: true },
  });

  return {
    entryCount: entries.length,
    mediaIds,
    // L'original d'une photo agrandie est un fichier de plus, et il est à elle.
    storageKeys: assets.flatMap((asset) =>
      asset.originalStorageKey
        ? [asset.storageKey, asset.originalStorageKey]
        : [asset.storageKey],
    ),
  };
}

/** Les commandes d'abord (voir § 1), les médias en dernier (voir § 2). */
async function deleteOrders(tx: Prisma.TransactionClient, memoIds: readonly string[]) {
  await tx.printOrder.deleteMany({ where: { memoId: { in: [...memoIds] } } });
}

async function deleteMedia(tx: Prisma.TransactionClient, mediaIds: readonly string[]) {
  if (mediaIds.length === 0) return;
  await tx.mediaAsset.deleteMany({ where: { id: { in: [...mediaIds] } } });
}

/**
 * Efface les fichiers, une fois les lignes parties. Sans faire échouer la
 * suppression : un fichier orphelin se rattrape par un ménage, un compte à
 * moitié supprimé ne se rattrape pas.
 */
async function removeObjects(
  context: AppContext,
  storageKeys: readonly string[],
  scope: Record<string, unknown>,
): Promise<void> {
  if (storageKeys.length === 0) return;

  try {
    await context.storage.remove(storageKeys);
  } catch (cause: unknown) {
    context.logger.error(
      { cause, ...scope, objects: storageKeys.length },
      "Suppression faite en base, mais des médias sont restés en stockage",
    );
  }
}

/**
 * Supprime un compte et tout ce qui est à lui — **sauf ce qui est aussi à
 * quelqu'un d'autre**.
 *
 * Pas d'anonymisation, pas de corbeille : ses souvenirs solitaires, ses médias,
 * ses commandes, sa cagnotte, ses moyens de paiement, ses connecteurs, ses
 * appareils et ses avis partent avec lui.
 *
 * **Un voyage qui a au moins un co-voyageur ne se supprime pas : il change de
 * main.** Il devient celui du co-voyageur actif le plus ancien, qui perd alors
 * sa ligne `memo_members` — le propriétaire n'en a pas. C'est un récit écrit à
 * plusieurs : le départ de l'un ne l'efface pas pour les autres.
 *
 * Ce qui suit du même principe :
 *
 *  - Les souvenirs racontés par le partant **restent dans le voyage transféré**.
 *    Ils appartiennent au récit, pas à leur auteur — c'est d'ailleurs pour ça
 *    qu'`entries` n'a pas de colonne d'auteur.
 *  - Ses commandes sur ce voyage survivent sans acheteur (`orderedByAccountId`
 *    en `SET NULL`) : un colis parti ne s'efface pas.
 *  - Un voyage sans **aucun** co-voyageur actif, lui, part entièrement. Une
 *    invitation encore en attente ne compte pas : elle ne désigne personne qui
 *    puisse en hériter.
 *
 * Les voyages où le compte n'était que co-voyageur survivent aussi, forcément :
 * seule sa participation disparaît, en cascade.
 */
export async function deleteAccountAndData(
  context: AppContext,
  accountId: string,
): Promise<DeletionReport> {
  const { prisma } = context;

  const memos = await prisma.memo.findMany({
    where: { ownerAccountId: accountId },
    select: {
      id: true,
      // L'héritier : le co-voyageur actif le plus ancien. Le plus ancien parce
      // qu'il faut une règle, et que celle-là ne dépend d'aucun jugement — c'est
      // la personne qui est sur ce voyage depuis le plus longtemps.
      members: {
        where: { status: "active", accountId: { not: null } },
        orderBy: { invitedAt: "asc" },
        take: 1,
        select: { id: true, accountId: true },
      },
    },
  });

  const transfers = memos.flatMap((memo) => {
    const heir = memo.members[0];
    return heir?.accountId
      ? [{ memoId: memo.id, memberId: heir.id, accountId: heir.accountId }]
      : [];
  });

  const transferredIds = new Set(transfers.map((transfer) => transfer.memoId));
  const memoIds = memos.map((memo) => memo.id).filter((id) => !transferredIds.has(id));

  const { entryCount, mediaIds, storageKeys } = await mediaOf(prisma, memoIds);

  await prisma.$transaction(async (tx) => {
    for (const transfer of transfers) {
      await tx.memo.update({
        where: { id: transfer.memoId },
        data: { ownerAccountId: transfer.accountId },
      });
      // Le nouveau propriétaire n'est plus un co-voyageur : sa ligne partirait
      // de toute façon en cascade si on l'oubliait ici, mais elle ferait de lui
      // le compagnon de lui-même le temps d'une requête.
      await tx.memoMember.delete({ where: { id: transfer.memberId } });
    }

    await deleteOrders(tx, memoIds);

    // Le compte emporte le reste en cascade : les voyages qui lui restent,
    // leurs souvenirs, étapes, dépenses, rendus et invitations, puis ses
    // sessions, identités, appareils, cagnotte, cartes, abonnements,
    // connecteurs et avis.
    await tx.account.delete({ where: { id: accountId } });

    await deleteMedia(tx, mediaIds);
  });

  await removeObjects(context, storageKeys, { accountId });

  const report: DeletionReport = {
    memos: memoIds.length,
    entries: entryCount,
    mediaObjects: storageKeys.length,
    transferredMemos: transfers.length,
  };

  context.logger.info({ accountId, ...report }, "Compte supprimé");
  return report;
}

/** Supprime un carnet, ses souvenirs, ses médias et ses commandes. */
export async function deleteMemoAndData(
  context: AppContext,
  memoId: string,
): Promise<DeletionReport> {
  const { prisma } = context;
  const { entryCount, mediaIds, storageKeys } = await mediaOf(prisma, [memoId]);

  await prisma.$transaction(async (tx) => {
    await deleteOrders(tx, [memoId]);
    await tx.memo.delete({ where: { id: memoId } });
    await deleteMedia(tx, mediaIds);
  });

  await removeObjects(context, storageKeys, { memoId });

  return { memos: 1, entries: entryCount, mediaObjects: storageKeys.length };
}
