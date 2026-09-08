import type { Prisma, PrismaClient } from "@prisma/client";

/**
 * Qui possède un carnet, et qui a le droit d'y toucher.
 *
 * **Un carnet a exactement un propriétaire, et il est obligatoire** :
 * `memos.ownerAccountId`. Il n'y a plus de propriété de repli par l'appareil,
 * ni de ligne `memo_members` de rôle `owner` — deux vérités de plus sur le même
 * fait, que rien n'empêchait de diverger.
 *
 * Toutes les routes passent par les deux clauses de ce fichier. Deux copies de
 * ces conditions finiraient par diverger, et diverger ici veut dire montrer le
 * carnet de quelqu'un d'autre.
 */

/** Crée un carnet pour un compte. Le propriétaire n'est jamais optionnel. */
export async function createMemoFor(
  prisma: PrismaClient,
  ownerAccountId: string,
  data: Omit<Prisma.MemoUncheckedCreateInput, "ownerAccountId">,
) {
  return prisma.memo.create({ data: { ...data, ownerAccountId } });
}

/**
 * « Ce compte est sur ce voyage » : il en est le propriétaire, ou il y est
 * co-voyageur actif. Un co-voyageur retiré ne voit plus rien.
 *
 * C'est la clause de **presque toutes** les routes, et pas seulement de la
 * lecture : un co-voyageur raconte, envoie ses vocaux, change les réglages du
 * voyage, génère le carnet et le commande, exactement comme le propriétaire.
 */
export function visibleToAccount(accountId: string): Prisma.MemoWhereInput {
  return {
    OR: [
      { ownerAccountId: accountId },
      { members: { some: { accountId, status: "active" } } },
    ],
  };
}

/**
 * « Ce compte possède ce carnet ». La **seule** chose que `visibleToAccount` ne
 * suffit pas à autoriser : **supprimer le voyage**.
 *
 * Tout le reste est partagé. Détruire le récit de tout le monde, non : il n'y a
 * qu'un propriétaire principal, et c'est précisément à ça qu'il sert.
 */
export function ownedByAccount(accountId: string): Prisma.MemoWhereInput {
  return { ownerAccountId: accountId };
}

/**
 * Rattache un appareil à un compte, après une connexion réussie.
 *
 *
 * Il n'y a plus de carnets à réclamer au passage : un carnet naît avec son
 * propriétaire, l'appareil n'en possède aucun. Ce lien ne sert donc qu'à savoir
 * sur quelles installations un compte est ouvert — et à les faire disparaître
 * avec lui.
 */
export async function linkDeviceToAccount(
  prisma: PrismaClient,
  deviceId: string,
  accountId: string,
): Promise<void> {
  await prisma.device.update({ where: { id: deviceId }, data: { accountId } });
}
