import type { FastifyInstance, FastifyRequest } from "fastify";
import { z } from "zod";
import type { AppContext } from "../context.js";
import { HttpError } from "../lib/httpError.js";
import { accountIdOf } from "../plugins/auth.js";
import { restoreMemo, softDeleteMemo } from "../services/trash.js";
import {
  createMemoFor,
  deletedForAccount,
  ownedByAccount,
  visibleToAccount,
} from "../services/memoOwnership.js";
import { serializeEntry, serializeMemo, serializeRender } from "./serializers.js";

const createBody = z.object({
  title: z.string().min(1, "le titre est requis").max(200),
  subtitle: z.string().max(300).optional(),
  authors: z.string().max(200).optional(),
  theme: z.string().max(200).optional(),
  startDate: z.coerce.date().optional(),
  endDate: z.coerce.date().optional(),
  coverPhotoUrl: z.string().url().optional(),
});

const idParams = z.object({ id: z.string().uuid() });

/**
 * Charge un carnet où l'appelant est : le sien, ou un voyage dont il est
 * co-voyageur. C'est ce que demandent presque toutes les routes — lire,
 * raconter, régler, générer, commander.
 *
 * Un voyage auquel on ne participe pas répond 404 et non 403 : un 403
 * confirmerait son existence.
 */
export async function loadVisibleMemo(
  context: AppContext,
  request: FastifyRequest,
  memoId: string,
) {
  const memo = await context.prisma.memo.findFirst({
    where: { id: memoId, ...visibleToAccount(accountIdOf(request)) },
  });
  if (!memo) throw HttpError.notFound("Carnet introuvable.");
  return memo;
}

/**
 * Charge un carnet dont l'appelant est **le propriétaire**. Réservé au seul
 * geste qui ne se partage pas : supprimer le voyage, et donc le récit de tous
 * ceux qui y ont raconté.
 */
export async function loadOwnedMemo(
  context: AppContext,
  request: FastifyRequest,
  memoId: string,
) {
  const memo = await context.prisma.memo.findFirst({
    where: { id: memoId, ...ownedByAccount(accountIdOf(request)) },
  });
  if (!memo) throw HttpError.notFound("Carnet introuvable.");
  return memo;
}

export function registerMemoRoutes(app: FastifyInstance, context: AppContext): void {
  app.get("/v1/memos", async (request) => {
    const memos = await context.prisma.memo.findMany({
      where: visibleToAccount(accountIdOf(request)),
      orderBy: { createdAt: "desc" },
      include: {
        _count: { select: { entries: true } },
        renders: { orderBy: { createdAt: "desc" }, take: 1 },
      },
    });

    return {
      memos: memos.map((memo) => ({
        ...serializeMemo(memo),
        entryCount: memo._count.entries,
        latestRender: memo.renders[0] ? serializeRender(memo.renders[0]) : null,
      })),
    };
  });

  app.post("/v1/memos", async (request, reply) => {
    const body = createBody.parse(request.body ?? {});

    if (body.startDate && body.endDate && body.endDate < body.startDate) {
      throw HttpError.badRequest("La date de fin précède la date de début.");
    }

    // Le compte qui crée le carnet en est le propriétaire, tout de suite et
    // sans condition : il n'existe pas de carnet sans propriétaire principal.
    const memo = await createMemoFor(context.prisma, accountIdOf(request), body);

    return reply.code(201).send(serializeMemo(memo));
  });

  app.get("/v1/memos/:id", async (request) => {
    const { id } = idParams.parse(request.params);
    await loadVisibleMemo(context, request, id);

    const memo = await context.prisma.memo.findUniqueOrThrow({
      where: { id },
      include: {
        entries: { orderBy: { capturedAt: "asc" }, include: { media: true } },
        renders: { orderBy: { createdAt: "desc" }, take: 5 },
      },
    });

    return {
      ...serializeMemo(memo),
      entries: memo.entries.map(serializeEntry),
      renders: memo.renders.map(serializeRender),
    };
  });

  /**
   * Jette un carnet — **son propriétaire seul**, jamais un co-voyageur.
   *
   * **Rien n'est effacé** (Hugo, 10/11/2026) : le carnet part à la corbeille,
   * d'où son propriétaire peut le reprendre pendant trente jours. Il quitte
   * pourtant toutes les vues aussitôt, y compris celles de ses co-voyageurs —
   * `visibleToAccount` exige `deletedAt: null`. Passé les trente jours, la
   * purge appelle la vraie suppression : souvenirs, médias, commandes et
   * traces chez les prestataires (`services/deletion.ts`).
   *
   * `404` sur un carnet **déjà** dans la corbeille : il n'y est plus pour être
   * jeté, et `ownedByAccount` exige `deletedAt: null` comme partout ailleurs.
   * `softDeleteMemo` reste malgré tout idempotent — deux appels concurrents
   * gardent la date du premier, sans quoi une course repousserait la purge de
   * trente jours.
   */
  app.delete("/v1/memos/:id", async (request, reply) => {
    const { id } = idParams.parse(request.params);
    await loadOwnedMemo(context, request, id);
    await softDeleteMemo(context, id);
    return reply.code(204).send();
  });

  /**
   * Sort un carnet de la corbeille. **Son propriétaire seul** : il n'y a que
   * lui qui a pu l'y mettre.
   *
   * Le carnet revient exactement comme il était — rien n'a bougé pendant qu'il
   * dormait. `404` s'il n'y est plus : restauré par un autre appui, ou purgé.
   */
  app.post("/v1/memos/:id/restore", async (request, reply) => {
    const { id } = idParams.parse(request.params);
    const accountId = accountIdOf(request);
    const memo = await context.prisma.memo.findFirst({
      where: { id, ...deletedForAccount(accountId) },
      select: { id: true },
    });
    if (!memo) return reply.code(404).send({ error: "memo_not_found" });

    await restoreMemo(context, id);
    return reply.code(204).send();
  });
}
