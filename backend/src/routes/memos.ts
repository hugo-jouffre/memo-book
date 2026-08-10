import type { FastifyInstance, FastifyRequest } from "fastify";
import { z } from "zod";
import type { AppContext } from "../context.js";
import { HttpError } from "../lib/httpError.js";
import { deviceIdOf } from "../plugins/auth.js";
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

/** Charge un carnet en vérifiant qu'il appartient bien à l'appelant. */
export async function loadOwnedMemo(
  context: AppContext,
  request: FastifyRequest,
  memoId: string,
) {
  const memo = await context.prisma.memo.findFirst({
    where: { id: memoId, deviceId: deviceIdOf(request) },
  });
  if (!memo) throw HttpError.notFound("Carnet introuvable.");
  return memo;
}

export function registerMemoRoutes(app: FastifyInstance, context: AppContext): void {
  app.get("/v1/memos", async (request) => {
    const memos = await context.prisma.memo.findMany({
      where: { deviceId: deviceIdOf(request) },
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

    const memo = await context.prisma.memo.create({
      data: { ...body, deviceId: deviceIdOf(request) },
    });

    return reply.code(201).send(serializeMemo(memo));
  });

  app.get("/v1/memos/:id", async (request) => {
    const { id } = idParams.parse(request.params);
    await loadOwnedMemo(context, request, id);

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

  app.delete("/v1/memos/:id", async (request, reply) => {
    const { id } = idParams.parse(request.params);
    await loadOwnedMemo(context, request, id);
    await context.prisma.memo.delete({ where: { id } });
    return reply.code(204).send();
  });
}
