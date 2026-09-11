import type { FastifyInstance } from "fastify";
import { z } from "zod";
import type { AppContext } from "../context.js";
import { HttpError } from "../lib/httpError.js";
import { accountIdOf } from "../plugins/auth.js";
import { visibleToAccount } from "../services/memoOwnership.js";
import { serializeTripSettings } from "./appSerializers.js";

/**
 * Les réglages d'un voyage : ce qui se règle sur le carnet sans quitter le
 * voyage.
 *
 * Tout arrive en une réponse — nom, dates, rythme, co-voyageurs, solde de
 * cagnotte, style, aperçu — parce que l'écran les affiche ensemble. Sept
 * appels feraient apparaître ses lignes une à une, ce qui est exactement ce
 * que `BrandSkeleton` cherche à éviter côté app.
 *
 * **Un réglage part seul.** Le `PATCH` n'accepte qu'une poignée de champs
 * optionnels, et l'app n'en envoie qu'un à la fois : la ligne s'enregistre en
 * perdant le focus, sans bouton pour valider. Envoyer l'objet entier
 * écraserait ce qu'un co-voyageur aurait changé entre-temps.
 *
 * **Un co-voyageur règle comme le propriétaire** : `visibleToAccount` et non
 * `ownedByAccount`. C'est la règle de tout le voyage — seule la suppression
 * reste au propriétaire (voir `ios/CLAUDE.md`).
 */

const params = z.object({ id: z.string().uuid() });

/**
 * Un champ absent n'est pas touché ; un champ à `null` est effacé. « Pas de
 * date de fin » et « une date de fin vide » ne sont pas la même chose — même
 * sémantique que `PATCH /v1/profile`.
 */
const updateBody = z.object({
  name: z.string().trim().min(1).max(120).optional(),
  startDate: z.coerce.date().nullable().optional(),
  endDate: z.coerce.date().nullable().optional(),
  narrationPace: z.string().trim().max(40).nullable().optional(),
  notificationsEnabled: z.boolean().optional(),
  theme: z.string().trim().max(120).nullable().optional(),
  isPublicGallery: z.boolean().optional(),
});

/** Ce que `serializeTripSettings` attend du carnet, et rien de plus. */
const settingsInclude = {
  members: {
    // Le propriétaire n'est pas un co-voyageur de sa propre ligne : l'écran
    // liste ceux qui l'accompagnent, pas lui-même.
    where: { status: "active" as const, role: "guest" as const },
    orderBy: { invitedAt: "asc" as const },
  },
  renders: {
    where: { status: "ready" as const },
    orderBy: { createdAt: "desc" as const },
    take: 1,
  },
};

async function readSettings(context: AppContext, accountId: string, memoId: string) {
  const [memo, account] = await Promise.all([
    context.prisma.memo.findFirst({
      where: { id: memoId, ...visibleToAccount(accountId) },
      include: settingsInclude,
    }),
    // Le solde vient du **compte** et non du voyage : la cagnotte n'appartient
    // pas au carnet. C'est la même somme que celle du profil, et c'est voulu.
    context.prisma.account.findUnique({
      where: { id: accountId },
      select: { walletBalanceCents: true },
    }),
  ]);

  if (!memo) throw new HttpError(404, "Ce voyage n’existe pas.");

  return serializeTripSettings(memo, account?.walletBalanceCents ?? 0);
}

export function registerTripSettingsRoutes(app: FastifyInstance, context: AppContext) {
  app.get("/v1/trips/:id/settings", async (request) => {
    const { id } = params.parse(request.params);
    return readSettings(context, accountIdOf(request), id);
  });

  app.patch("/v1/trips/:id/settings", async (request) => {
    const { id } = params.parse(request.params);
    const body = updateBody.parse(request.body);
    const accountId = accountIdOf(request);

    // L'appartenance se vérifie **avant** l'écriture, et pas seulement par le
    // `where` de l'update : un `updateMany` qui ne touche aucune ligne réussit
    // silencieusement, et l'app croirait son réglage enregistré.
    const visible = await context.prisma.memo.findFirst({
      where: { id, ...visibleToAccount(accountId) },
      select: { id: true },
    });
    if (!visible) throw new HttpError(404, "Ce voyage n’existe pas.");

    await context.prisma.memo.update({
      where: { id },
      data: {
        ...(body.name !== undefined ? { title: body.name } : {}),
        ...(body.startDate !== undefined ? { startDate: body.startDate } : {}),
        ...(body.endDate !== undefined ? { endDate: body.endDate } : {}),
        ...(body.narrationPace !== undefined ? { narrationPace: body.narrationPace } : {}),
        ...(body.notificationsEnabled !== undefined
          ? { notificationsEnabled: body.notificationsEnabled }
          : {}),
        ...(body.theme !== undefined ? { theme: body.theme } : {}),
        ...(body.isPublicGallery !== undefined ? { isPublicGallery: body.isPublicGallery } : {}),
      },
    });

    // On relit tout plutôt que de rendre ce qu'on vient d'écrire : la réponse
    // est ce que l'app garde à l'écran, et une réponse partielle effacerait le
    // reste de la page. Même règle que `PATCH /v1/profile`.
    return readSettings(context, accountId, id);
  });
}
