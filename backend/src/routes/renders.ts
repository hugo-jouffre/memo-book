import type { FastifyInstance } from "fastify";
import { z } from "zod";
import type { AppContext } from "../context.js";
import { JOB_NAMES, type StructureJob } from "../jobs/index.js";
import { HttpError } from "../lib/httpError.js";
import { deviceIdOf } from "../plugins/auth.js";
import { loadOwnedMemo } from "./memos.js";
import { serializeRender } from "./serializers.js";

const memoIdParams = z.object({ id: z.string().uuid() });
const renderIdParams = z.object({ id: z.string().uuid() });

export function registerRenderRoutes(app: FastifyInstance, context: AppContext): void {
  /** Déclenche la génération du carnet : structuration puis rendu PDF. */
  app.post("/v1/memos/:id/renders", async (request, reply) => {
    const { id: memoId } = memoIdParams.parse(request.params);
    await loadOwnedMemo(context, request, memoId);

    const entryCount = await context.prisma.entry.count({ where: { memoId } });
    if (entryCount === 0) {
      throw HttpError.badRequest(
        "Ce carnet ne contient encore aucun souvenir : enregistre au moins une entrée avant de le générer.",
        "empty_memo",
      );
    }

    // Une génération déjà en cours est renvoyée telle quelle : deux appels
    // rapprochés depuis l'app ne doivent pas produire deux PDF facturés.
    const inFlight = await context.prisma.render.findFirst({
      where: { memoId, status: { in: ["pending", "processing"] } },
      orderBy: { createdAt: "desc" },
    });

    if (inFlight) {
      return reply.code(200).send(serializeRender(inFlight));
    }

    const render = await context.prisma.render.create({ data: { memoId } });

    await context.queue.publish<StructureJob>(JOB_NAMES.structure, {
      renderId: render.id,
    });

    // 202 : accepté, le résultat arrivera de façon asynchrone.
    const current = await context.prisma.render.findUniqueOrThrow({
      where: { id: render.id },
    });
    return reply.code(202).send(serializeRender(current));
  });

  app.get("/v1/renders/:id", async (request) => {
    const { id } = renderIdParams.parse(request.params);

    const render = await context.prisma.render.findFirst({
      where: { id, memo: { deviceId: deviceIdOf(request) } },
    });

    if (!render) throw HttpError.notFound("Génération introuvable.");
    return serializeRender(render);
  });
}
