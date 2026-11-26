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
const tripParams = z.object({ id: z.string().uuid() });

/**
 * L'élection d'une photo principale — et `null` pour la défaire. T270 : les
 * deux étoiles de l'appui long, la verte pour l'étape, la lime pour le voyage.
 */
const coverPhotoBody = z.object({ entryId: z.string().uuid().nullable() });

export function registerStepRoutes(app: FastifyInstance, context: AppContext): void {
  /**
   * « Valider cette étape » : confirme l'étape et, la première fois, déclenche
   * en fond une nouvelle génération du carnet (`ensureRenderInProgress`) —
   * sauf mémo encore vide, où valider l'étape doit réussir quand même.
   *
   * **En fond veut dire après une accalmie** (T307, `settle: true`) : valider
   * une étape ne prouve pas que le voyageur a fini. Il enchaîne souvent un
   * second vocal ou des photos, et la composition partie dans la seconde
   * attendait alors trois minutes la rédaction du suivant pour échouer. Elle
   * laisse maintenant le carnet se taire, et compose une fois pour tout.
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
        await ensureRenderInProgress(context, memo.id, { settle: true });
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

  /**
   * **« Définir comme photo principale de l'étape »** — l'étoile verte (T270).
   *
   * Elle sert à la carte de l'étape, aux propositions de couverture et à la
   * mise en page. Le choix se range dans `memo_steps.coverEntryId` et non dans
   * `photoUrl` : celle-là est **recalculée** à chaque passage de
   * `refreshTripFacts`, et une élection écrite dedans se serait effacée toute
   * seule. C'est le calcul qui respecte le choix, et pas l'inverse.
   *
   * La photo doit être **de cette étape** : une étoile sur une photo rangée
   * ailleurs ne se verrait nulle part, le calcul ne la trouvant pas parmi les
   * photos de l'étape.
   *
   * `entryId: null` défait l'élection — l'étape reprend son élection
   * automatique.
   */
  app.put("/v1/trips/:id/steps/:stepId/cover-photo", async (request) => {
    const { id: memoId, stepId } = params.parse(request.params);
    const { entryId } = coverPhotoBody.parse(request.body ?? {});
    const accountId = accountIdOf(request);
    const memo = await loadVisibleMemo(context, request, memoId);

    const step = await context.prisma.memoStep.findFirst({
      where: { id: stepId, memoId: memo.id },
      select: { id: true },
    });
    if (!step) throw HttpError.notFound("Étape introuvable.");

    if (entryId !== null) {
      const photo = await context.prisma.entry.findFirst({
        where: { id: entryId, memoId: memo.id, kind: "photo" },
        select: { id: true, stepId: true },
      });
      if (!photo) throw HttpError.notFound("Photo introuvable.");
      if (photo.stepId !== step.id) {
        throw HttpError.badRequest("Cette photo n'est pas dans cette étape.");
      }
    }

    await context.prisma.memoStep.update({ where: { id: step.id }, data: { coverEntryId: entryId } });
    // La vignette de l'étape se recalcule aussitôt : c'est elle que l'accueil
    // du voyage lit, et l'écran se relit juste après.
    await refreshTripFactsQuietly(context, memo.id);

    return loadTripDetail(context, accountId, memo.id);
  });

  /**
   * **« Définir comme photo principale du voyage »** — l'étoile lime (T270).
   *
   * Elle sert à l'accueil de l'app, à l'accueil du voyage, au haut du chat,
   * aux couvertures et à la mise en page.
   *
   * ⚠️ Elle ne touche pas `memos.coverPhotoUrl`, la photo **téléversée** pour
   * la couverture depuis l'atelier : celle-là passe devant, et une étoile ne
   * doit pas effacer en silence une couverture qu'on a composée.
   */
  app.put("/v1/trips/:id/cover-photo", async (request) => {
    const { id: memoId } = tripParams.parse(request.params);
    const { entryId } = coverPhotoBody.parse(request.body ?? {});
    const accountId = accountIdOf(request);
    const memo = await loadVisibleMemo(context, request, memoId);

    if (entryId !== null) {
      const photo = await context.prisma.entry.findFirst({
        where: { id: entryId, memoId: memo.id, kind: "photo" },
        select: { id: true },
      });
      if (!photo) throw HttpError.notFound("Photo introuvable.");
    }

    await context.prisma.memo.update({ where: { id: memo.id }, data: { coverEntryId: entryId } });

    return loadTripDetail(context, accountId, memo.id);
  });
}
