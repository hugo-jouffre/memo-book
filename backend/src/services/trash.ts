import type { AppContext } from "../context.js";
import { deleteMemoAndData } from "./deletion.js";
import type { DeletionReport } from "./deletion.js";

/**
 * **La corbeille des voyages** (Hugo, 10/11/2026) — « j'ai toujours peur qu'un
 * voyage soit supprimé par inadvertance ».
 *
 * Supprimer un voyage ne l'efface plus : ça pose `memos.deletedAt`. Le voyage
 * disparaît aussitôt de partout — `visibleToAccount` exige `deletedAt: null`,
 * et c'est la clause de presque toutes les routes —, mais il n'est pas perdu :
 * son propriétaire le retrouve dans une section discrète au bas de l'accueil,
 * et le restaure d'un geste.
 *
 * **Trente jours plus tard, il s'efface pour de bon.** Une corbeille qui ne se
 * vide jamais n'est pas une corbeille, c'est une archive : elle garderait des
 * données personnelles sans raison, et le RGPD veut une durée. La purge
 * (`purgeDeletedMemos`) appelle alors la suppression d'avant — souvenirs,
 * fichiers, commandes et traces chez les prestataires compris.
 *
 * ### Ce que la corbeille ne fait pas
 *
 * - **Elle ne protège pas la suppression du compte.** Supprimer son compte
 *   efface tout, corbeille comprise : c'est un geste qu'on demande deux fois,
 *   et qui doit tenir sa promesse (RGPD, et guideline 5.1.1 d'Apple).
 * - **Elle n'est pas partagée.** Un co-voyageur ne peut pas jeter un voyage —
 *   c'est déjà la règle — et ne voit donc pas la corbeille. Pendant qu'un
 *   voyage y dort, il n'y a plus accès : pour lui, le voyage a disparu. S'il
 *   revient, il revient pour tout le monde.
 * - **Elle ne garde pas la place.** Les fichiers restent sur S3 trente jours
 *   de plus, et c'est le prix du filet.
 */

/** Ce qu'un voyage jeté passe dans la corbeille avant de s'effacer : 30 jours. */
export const TRASH_RETENTION_DAYS = 30;

/** La même durée en millisecondes, pour les calculs de date. */
export const TRASH_RETENTION_MS = TRASH_RETENTION_DAYS * 24 * 60 * 60 * 1000;

/**
 * La date avant laquelle un voyage jeté a fait son temps. Passée en paramètre
 * plutôt que lue de l'horloge, pour que les tests n'attendent pas trente
 * jours.
 */
export function expiryLimit(now: Date = new Date()): Date {
  return new Date(now.getTime() - TRASH_RETENTION_MS);
}

/**
 * Le jour où un voyage jeté s'effacera — ce que l'app affiche sous sa ligne
 * dans la corbeille (« il s'effacera le 10 décembre »).
 */
export function purgeDateOf(deletedAt: Date): Date {
  return new Date(deletedAt.getTime() + TRASH_RETENTION_MS);
}

/**
 * **Jette un voyage.** Rien n'est effacé : la date se pose, et le voyage
 * quitte toutes les vues du même coup.
 *
 * Idempotent : un voyage déjà dans la corbeille garde la date de sa première
 * suppression, sans quoi un double appui repousserait sa purge de trente
 * jours. `updateMany` plutôt que `update` pour que la clause le dise, et pour
 * ne pas lever sur un voyage qui n'est plus là.
 */
export async function softDeleteMemo(
  context: AppContext,
  memoId: string,
  now: Date = new Date(),
): Promise<boolean> {
  const { count } = await context.prisma.memo.updateMany({
    where: { id: memoId, deletedAt: null },
    data: { deletedAt: now },
  });
  return count > 0;
}

/**
 * **Sort un voyage de la corbeille.** Il revient exactement comme il était :
 * ses souvenirs, ses photos, ses co-voyageurs, son carnet. Rien n'a bougé
 * pendant qu'il dormait — c'est tout l'intérêt de n'avoir posé qu'une date.
 *
 * Rend `false` si le voyage n'est pas dans la corbeille : déjà restauré par un
 * second appui, ou purgé entre-temps. L'app relit l'accueil et le dit.
 */
export async function restoreMemo(context: AppContext, memoId: string): Promise<boolean> {
  const { count } = await context.prisma.memo.updateMany({
    where: { id: memoId, deletedAt: { not: null } },
    data: { deletedAt: null },
  });
  return count > 0;
}

/**
 * **La purge** : les voyages jetés il y a plus de trente jours s'effacent pour
 * de bon.
 *
 * Un par un, et non en lot : `deleteMemoAndData` touche S3 et les prestataires
 * en plus de la base, et une transaction géante qui tient tous les fichiers de
 * dix carnets échouerait en bloc. Un voyage qui résiste n'emporte donc pas les
 * autres — il sera repris au prochain passage, puisque sa date ne bouge pas.
 */
export async function purgeDeletedMemos(
  context: AppContext,
  now: Date = new Date(),
): Promise<DeletionReport> {
  const expired = await context.prisma.memo.findMany({
    where: { deletedAt: { not: null, lte: expiryLimit(now) } },
    select: { id: true },
    orderBy: { deletedAt: "asc" },
  });

  const total: DeletionReport = { memos: 0, entries: 0, mediaObjects: 0, providerTraces: 0 };
  for (const { id } of expired) {
    try {
      const report = await deleteMemoAndData(context, id);
      total.memos += report.memos;
      total.entries += report.entries;
      total.mediaObjects += report.mediaObjects;
      total.providerTraces += report.providerTraces;
    } catch (cause) {
      // Le voyage garde sa date : le prochain passage le reprendra. On ne
      // laisse pas une panne S3 bloquer la corbeille des autres.
      context.logger.error({ err: cause, memoId: id }, "Purge d'un voyage impossible.");
    }
  }
  return total;
}
