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
  /**
   * **À appeler à chaque ouverture de l'aperçu PDF** (T224, Hugo 06/10/2026)
   * — l'imprimante de l'accueil du voyage, « Prévisualisation PDF » des
   * paramètres, le CTA des écrans de personnalisation.
   *
   * Sûre à rappeler : elle ne lance une composition (IA + APITemplate) que si
   * elle sert — voir `ensureRenderInProgress`. 202 et le nouveau rendu quand
   * une composition part ; 200 et le rendu existant quand une composition
   * tourne déjà, ou que le dernier PDF est à jour.
   */
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

    const { render, created } = await ensureRenderInProgress(context, memoId);

    // 202 : accepté, le résultat arrivera de façon asynchrone. 200 quand on
    // rend une composition en cours ou un PDF à jour — rien de nouveau.
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
