import type { MemoStep, PrismaClient } from "@prisma/client";

/**
 * « Valider cette étape » : le voyageur confirme l'étape.
 *
 * Idempotent : valider deux fois ne redéclenche rien — c'est `justValidated`
 * qui le dit à l'appelant, pour qu'il n'enfile une nouvelle génération du
 * carnet qu'au premier passage. Même geste qu'`Entry`'s `validateEntry`
 * (« Ça me convient »), à l'échelle de l'étape.
 */
export async function validateMemoStep(
  prisma: PrismaClient,
  memoId: string,
  stepId: string,
): Promise<{ step: MemoStep; justValidated: boolean } | null> {
  return prisma.$transaction(async (tx) => {
    const existing = await tx.memoStep.findFirst({ where: { id: stepId, memoId } });
    if (!existing) return null;

    const { count } = await tx.memoStep.updateMany({
      where: { id: stepId, memoId, validatedAt: null },
      data: { validatedAt: new Date() },
    });

    const step = await tx.memoStep.findUniqueOrThrow({ where: { id: stepId } });
    return { step, justValidated: count > 0 };
  });
}
