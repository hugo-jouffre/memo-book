import type { FastifyInstance } from "fastify";
import { z } from "zod";
import type { AppContext } from "../context.js";
import { HttpError } from "../lib/httpError.js";
import { accountIdOf } from "../plugins/auth.js";
import { ensureRenderInProgress } from "../services/renderTrigger.js";
import { visibleToAccount } from "../services/memoOwnership.js";
import { loadVisibleMemo } from "./memos.js";
import { serializeRender } from "./serializers.js";

const memoIdParams = z.object({ id: z.string().uuid() });
const renderIdParams = z.object({ id: z.string().uuid() });

export function registerRenderRoutes(app: FastifyInstance, context: AppContext): void {
  /** Déclenche la génération du carnet : structuration puis rendu PDF. */
  app.post("/v1/memos/:id/renders", async (request, reply) => {
    const { id: memoId } = memoIdParams.parse(request.params);
    await loadVisibleMemo(context, request, memoId);

    const entryCount = await context.prisma.entry.count({ where: { memoId } });
    if (entryCount === 0) {
      throw HttpError.badRequest(
        "Ce carnet ne contient encore aucun souvenir : enregistre au moins une entrée avant de le générer.",
        "empty_memo",
      );
    }

    // Une génération déjà en cours est renvoyée telle quelle : deux appels
    // rapprochés depuis l'app ne doivent pas produire deux PDF facturés.
    const { render, created } = await ensureRenderInProgress(context, memoId);

    // 202 : accepté, le résultat arrivera de façon asynchrone. 200 quand une
    // génération était déjà en cours — ce n'est pas une nouvelle acceptation.
    return reply.code(created ? 202 : 200).send(serializeRender(render));
  });

  app.get("/v1/renders/:id", async (request) => {
    const { id } = renderIdParams.parse(request.params);

    const render = await context.prisma.render.findFirst({
      where: { id, memo: visibleToAccount(accountIdOf(request)) },
    });

    if (!render) throw HttpError.notFound("Génération introuvable.");
    return serializeRender(render);
  });
}
