import { Prisma } from "@prisma/client";
import type { PrismaClient } from "@prisma/client";
import { makeAccessCode } from "../lib/accessCode.js";

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

/**
 * Crée un carnet pour un compte. Le propriétaire n'est jamais optionnel, et le
 * **code d'accès** non plus : il est tiré ici, pour qu'aucun appelant ne puisse
 * fabriquer un carnet qu'on ne saurait pas partager.
 *
 * La boucle n'est pas de la superstition. L'unicité du code est tenue par un
 * index, donc par la base, et c'est elle qui a le dernier mot. Deux tirages qui
 * se télescopent sur un milliard de codes n'arriveront jamais — mais le jour où
 * ça arrive, on retire au sort plutôt que de rendre une erreur à quelqu'un qui
 * n'y peut rien.
 */
export async function createMemoFor(
  prisma: PrismaClient,
  ownerAccountId: string,
  data: Omit<Prisma.MemoUncheckedCreateInput, "ownerAccountId" | "accessCode">,
) {
  for (let attempt = 0; ; attempt += 1) {
    try {
      return await prisma.memo.create({
        data: { ...data, ownerAccountId, accessCode: makeAccessCode() },
      });
    } catch (error) {
      const isCollision =
        error instanceof Prisma.PrismaClientKnownRequestError && error.code === "P2002";
      // Seul le code d'accès se retire au sort. Un identifiant déjà pris —
      // celui que l'app a choisi pour un voyage créé hors ligne — ne changera
      // pas au prochain essai : c'est à l'appelant de reconnaître le voyage.
      if (!isCollision || isTakenId(error) || attempt >= 4) throw error;
    }
  }
}

/** L'erreur dit que l'identifiant du carnet est déjà pris, et non son code d'accès. */
export function isTakenId(error: unknown): boolean {
  if (!(error instanceof Prisma.PrismaClientKnownRequestError) || error.code !== "P2002") return false;
  // Prisma nomme la contrainte par ses colonnes (`["id"]`), ou par son nom
  // (`memos_pkey`) selon le moteur.
  const target: unknown = error.meta?.["target"];
  const fields = Array.isArray(target) ? target : [target];
  return fields.some((field) => field === "id" || field === "memos_pkey");
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
