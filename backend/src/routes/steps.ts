import type { FastifyInstance } from "fastify";
import { z } from "zod";
import type { AppContext } from "../context.js";
import { HttpError } from "../lib/httpError.js";
import { accountIdOf } from "../plugins/auth.js";
import { ensureRenderInProgress } from "../services/renderTrigger.js";
import { validateMemoStep } from "../services/memoSteps.js";
import { refreshTripFactsQuietly } from "../services/tripFacts.js";
import { loadVisibleMemo } from "./memos.js";
import { loadTripDetail } from "./home.js";

const params = z.object({ id: z.string().uuid(), stepId: z.string().uuid() });

export function registerStepRoutes(app: FastifyInstance, context: AppContext): void {
  /**
   * « Valider cette étape » : confirme l'étape et, la première fois, déclenche
   * en fond une nouvelle génération du carnet (`ensureRenderInProgress`) —
   * sauf mémo encore vide, où valider l'étape doit réussir quand même.
   *
   * Répond le voyage entier, comme `GET /v1/trips/:id` : on modifie une chose,
   * on relit tout.
   */
  app.post("/v1/trips/:id/steps/:stepId/validate", async (request) => {
    const { id: memoId, stepId } = params.parse(request.params);
    const accountId = accountIdOf(request);

    // Un invité voit le voyage, quelqu'un qui n'y participe pas reçoit un 404.
    const memo = await loadVisibleMemo(context, request, memoId);

    const result = await validateMemoStep(context.prisma, memo.id, stepId);
    if (!result) throw HttpError.notFound("Étape introuvable.");

    if (result.justValidated) {
      const entryCount = await context.prisma.entry.count({ where: { memoId: memo.id } });
      if (entryCount > 0) {
        await ensureRenderInProgress(context, memo.id);
      }
    }

    return loadTripDetail(context, accountId, memo.id);
  });

  /**
   * **« Séparer ces récits »** : une étape qui réunit plusieurs récits
   * redevient une étape par récit (Hugo, 28/10/2026).
   *
   * La rédaction groupe ce qui se prolonge (`continuesPreviousStep`) ; elle se
   * trompe parfois, et c'est le voyageur qui a raison. Son geste est retenu
   * sur chaque récit de l'étape (`separatedByTraveller`), et il passe devant
   * la machine — la rédaction a beau se relancer, elle ne les réunira plus.
   *
   * Le découpage se refait derrière (`refreshTripFacts`) : les récits
   * séparés ouvrent leurs étapes, et les numéros suivent. Répond le voyage
   * entier, comme la validation : on modifie une chose, on relit tout.
   */
  app.post("/v1/trips/:id/steps/:stepId/separate", async (request) => {
    const { id: memoId, stepId } = params.parse(request.params);
    const accountId = accountIdOf(request);
    const memo = await loadVisibleMemo(context, request, memoId);

    const step = await context.prisma.memoStep.findFirst({
      where: { id: stepId, memoId: memo.id },
      select: { id: true },
    });
    if (!step) throw HttpError.notFound("Étape introuvable.");

    // Tous les récits de l'étape, photos exclues : ce sont eux qui ouvrent
    // les étapes. Le premier n'avait de toute façon rien à prolonger.
    await context.prisma.entry.updateMany({
      where: { memoId: memo.id, stepId, kind: { not: "photo" } },
      data: { separatedByTraveller: true },
    });

    await refreshTripFactsQuietly(context, memo.id);

    return loadTripDetail(context, accountId, memo.id);
  });
}
