import type { Prisma, PrismaClient } from "@prisma/client";

/**
 * La propriété d'un carnet, pendant la transition de l'appareil vers le compte.
 *
 * Deux identifications coexistent : un carnet porte encore un `deviceId`, et
 * porte désormais aussi un `ownerAccountId`. Tout ce qui décide « ce carnet est
 * à cette personne » passe par ici, pour que la bascule finale — supprimer
 * `deviceId` — n'ait qu'un fichier à traverser.
 *
 * L'invariant que ce module tient, et que la base ne peut pas exprimer : **un
 * carnet possédé a exactement une ligne `memo_members` de rôle `owner`.**
 * Prisma ne sait pas décrire un index unique partiel, et un index écrit à la
 * main serait supprimé par la migration suivante comme une dérive.
 */

/**
 * Crée un carnet et, quand on sait à qui il est, sa ligne de propriétaire —
 * dans la même écriture. Un carnet possédé mais sans participant serait un
 * carnet dont on ne peut pas afficher l'équipage.
 *
 * `ownerAccountId` reste nul pour un appareil qui n'a pas encore de compte.
 * C'est l'état que `linkDeviceToAccount` résorbe à la connexion.
 */
export async function createOwnedMemo(
  prisma: PrismaClient,
  data: Omit<Prisma.MemoUncheckedCreateInput, "ownerAccountId" | "members">,
  ownerAccountId: string | null,
) {
  const now = new Date();

  return prisma.memo.create({
    data: {
      ...data,
      ownerAccountId,
      ...(ownerAccountId
        ? {
            members: {
              create: [
                { accountId: ownerAccountId, role: "owner", status: "active", acceptedAt: now },
              ],
            },
          }
        : {}),
    },
  });
}

/**
 * Le compte auquel un appareil s'est rattaché, s'il l'a fait. C'est ce qui
 * permet à une création de carnet passée par le token d'appareil de désigner
 * quand même un propriétaire.
 */
export async function accountOfDevice(
  prisma: PrismaClient,
  deviceId: string,
): Promise<string | null> {
  const device = await prisma.device.findUnique({
    where: { id: deviceId },
    select: { accountId: true },
  });
  return device?.accountId ?? null;
}

/**
 * Rattache un appareil à un compte, et lui transfère ses carnets.
 *
 * Appelé après une connexion réussie : quelqu'un qui a raconté trois étapes
 * avant de se créer un compte doit les retrouver, pas repartir de zéro.
 *
 * **Ne prend que les carnets sans propriétaire.** Un appareil prêté, ou revendu,
 * ne doit pas transférer les carnets de son porteur précédent au nouveau compte
 * qui s'y connecte.
 *
 * Idempotent : rejouer la même liaison ne crée pas de doublon de participant.
 */
export async function linkDeviceToAccount(
  prisma: PrismaClient,
  deviceId: string,
  accountId: string,
): Promise<{ claimed: number }> {
  return prisma.$transaction(async (tx) => {
    await tx.device.update({ where: { id: deviceId }, data: { accountId } });

    const orphans = await tx.memo.findMany({
      where: { deviceId, ownerAccountId: null },
      select: { id: true, createdAt: true },
    });

    if (orphans.length === 0) return { claimed: 0 };

    await tx.memo.updateMany({
      where: { id: { in: orphans.map((memo) => memo.id) } },
      data: { ownerAccountId: accountId },
    });

    await tx.memoMember.createMany({
      data: orphans.map((memo) => ({
        memoId: memo.id,
        accountId,
        role: "owner" as const,
        status: "active" as const,
        invitedAt: memo.createdAt,
        acceptedAt: memo.createdAt,
      })),
      // `unique(memoId, accountId)` fait le reste : une liaison rejouée ne
      // duplique rien.
      skipDuplicates: true,
    });

    return { claimed: orphans.length };
  });
}

/**
 * La condition « ce compte a le droit de voir ce carnet ». Propriétaire ou
 * invité actif — un invité retiré ne voit plus rien.
 *
 * Écrite une fois et réutilisée par toutes les routes de compte : deux copies
 * de cette clause finiraient par diverger, et diverger ici veut dire montrer
 * le carnet de quelqu'un d'autre.
 */
export function visibleToAccount(accountId: string): Prisma.MemoWhereInput {
  return {
    OR: [
      { ownerAccountId: accountId },
      { members: { some: { accountId, status: "active" } } },
    ],
  };
}
