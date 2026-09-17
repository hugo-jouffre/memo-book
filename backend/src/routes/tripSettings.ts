import type { FastifyInstance } from "fastify";
import { z } from "zod";
import type { AppContext } from "../context.js";
import { HttpError } from "../lib/httpError.js";
import { accountIdOf } from "../plugins/auth.js";
import { readMemoryAllowance, setMemoryPlan } from "../services/memoryAllowance.js";
import { visibleToAccount } from "../services/memoOwnership.js";
import { endSubscriptionsWithoutRunningTrip } from "../services/subscriptions.js";
import { stageFromDates } from "../services/tripStage.js";
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

const memoryPlanBody = z.object({ plan: z.enum(["included", "extended"]) });

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
  /**
   * Les quatre alertes, d'un bloc — la seule exception à la règle du réglage
   * unique, et elle se justifie : elles vivent sur la même feuille, personne
   * d'autre ne les touche, et les envoyer une par une ferait quatre requêtes
   * pour quatre bascules qu'on enchaîne au doigt.
   */
  notifications: z
    .object({
      writingReminder: z.boolean(),
      newStory: z.boolean(),
      weeklyDigest: z.boolean(),
      tripEndReminder: z.boolean(),
    })
    .optional(),
  theme: z.string().trim().max(120).nullable().optional(),
  isPublicGallery: z.boolean().optional(),

  /**
   * Les personnalisations du carnet passent par **la même route**, et c'est le
   * corollaire de leur lecture : elles voyagent avec les réglages parce qu'il y
   * en a un jeu par voyage. Une seconde route aurait doublé le contrôle
   * d'appartenance pour écrire dans la même ligne.
   *
   * Les bornes ne sont pas décoratives : un ratio hors 0–100 ou un carnet de
   * 4 000 pages n'a pas de sens pour le gabarit, et c'est ici qu'on le refuse —
   * pas dans l'app, qui n'est qu'un client parmi d'autres.
   */
  photoTextRatio: z.number().int().min(0).max(100).optional(),
  targetPageCount: z.number().int().min(10).max(400).optional(),
  funFactsEnabled: z.boolean().optional(),
  rulesEnabled: z.boolean().optional(),
  decorationQuota: z.number().int().min(0).max(4).optional(),
  // Les quatre typographies : des noms de famille, que le gabarit résout.
  // « Titres » écrit `fontDisplay` et « sous-titres » `fontTitle` — c'est le
  // croisement des tokens du gabarit, voir `LAYOUT_KB.md`.
  fontDisplay: z.string().trim().min(1).max(60).optional(),
  fontTitle: z.string().trim().min(1).max(60).optional(),
  fontHand: z.string().trim().min(1).max(60).optional(),
  fontFacts: z.string().trim().min(1).max(60).optional(),
  quizEnabled: z.boolean().optional(),
  freeZonesEnabled: z.boolean().optional(),
  crosswordEnabled: z.boolean().optional(),
});

/** Ce que `serializeTripSettings` attend du carnet, et rien de plus. */
const settingsInclude = {
  members: {
    // **Les invitations en attente aussi**, désormais : la feuille « Inviter un
    // proche » les montre — c'est à elles que s'adresse l'action « Renvoyer » —
    // et les cacher faisait disparaître quelqu'un qu'on venait d'inviter.
    // Seuls les retirés restent hors de la liste.
    where: { status: { in: ["active" as const, "invited" as const] } },
    orderBy: { invitedAt: "asc" as const },
    include: { account: true },
  },
  // Le propriétaire n'a pas de ligne dans `memo_members` : il se lit ici, et le
  // sérialiseur le pose en tête de la liste.
  owner: true,
  renders: {
    where: { status: "ready" as const },
    orderBy: { createdAt: "desc" as const },
    take: 1,
  },
};

async function readSettings(context: AppContext, accountId: string, memoId: string) {
  const [memo, account, memory] = await Promise.all([
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
    // Les limites de souvenirs pendent du compte elles aussi. La lecture remet
    // la période à zéro si le mois est écoulé — voir `readMemoryAllowance`.
    readMemoryAllowance(context.prisma, accountId),
  ]);

  if (!memo) throw new HttpError(404, "Ce voyage n’existe pas.");

  return serializeTripSettings(memo, account?.walletBalanceCents ?? 0, memory);
}

export function registerTripSettingsRoutes(app: FastifyInstance, context: AppContext) {
  app.get("/v1/trips/:id/settings", async (request) => {
    const { id } = params.parse(request.params);
    return readSettings(context, accountIdOf(request), id);
  });

  /**
   * Étendre — ou remettre — les limites de souvenirs.
   *
   * **Sur le voyage et non sur le compte**, alors que le palier appartient au
   * compte : c'est l'écran des réglages d'un voyage qui l'ouvre, et la réponse
   * est le jeu de réglages entier, que l'app remplace tel quel. Une route
   * `/v1/account/memory` aurait rendu quatre nombres que l'écran aurait dû
   * recoller à la main dans ce qu'il avait déjà.
   */
  app.post("/v1/trips/:id/memory-plan", async (request) => {
    const { id } = params.parse(request.params);
    const { plan } = memoryPlanBody.parse(request.body);
    const accountId = accountIdOf(request);

    await setMemoryPlan(context.prisma, accountId, plan);
    return readSettings(context, accountId, id);
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

    // Les dates qui bougent réécrivent la colonne `stage`, pour qu'elle ne
    // contredise pas ce que l'app lit — l'état se lit sur les dates
    // (`services/tripStage.ts`), la colonne n'est qu'un repli sans date.
    const datesChanged = body.startDate !== undefined || body.endDate !== undefined;
    const current = datesChanged
      ? await context.prisma.memo.findUniqueOrThrow({
          where: { id },
          select: { startDate: true, endDate: true },
        })
      : null;
    const nextStart = body.startDate !== undefined ? body.startDate : current?.startDate;
    const nextEnd = body.endDate !== undefined ? body.endDate : current?.endDate;

    await context.prisma.memo.update({
      where: { id },
      data: {
        ...(body.name !== undefined ? { title: body.name } : {}),
        ...(body.startDate !== undefined ? { startDate: body.startDate } : {}),
        ...(body.endDate !== undefined ? { endDate: body.endDate } : {}),
        ...(datesChanged ? { stage: stageFromDates(nextStart, nextEnd) } : {}),
        ...(body.narrationPace !== undefined ? { narrationPace: body.narrationPace } : {}),
        ...(body.notificationsEnabled !== undefined
          ? { notificationsEnabled: body.notificationsEnabled }
          : {}),
        ...(body.notifications
          ? {
              notifyWritingReminder: body.notifications.writingReminder,
              notifyNewStory: body.notifications.newStory,
              notifyWeeklyDigest: body.notifications.weeklyDigest,
              notifyTripEnd: body.notifications.tripEndReminder,
            }
          : {}),
        ...(body.theme !== undefined ? { theme: body.theme } : {}),
        ...(body.isPublicGallery !== undefined ? { isPublicGallery: body.isPublicGallery } : {}),
        ...(body.photoTextRatio !== undefined ? { photoTextRatio: body.photoTextRatio } : {}),
        ...(body.targetPageCount !== undefined ? { targetPageCount: body.targetPageCount } : {}),
        ...(body.funFactsEnabled !== undefined ? { funFactsEnabled: body.funFactsEnabled } : {}),
        ...(body.rulesEnabled !== undefined ? { rulesEnabled: body.rulesEnabled } : {}),
        ...(body.decorationQuota !== undefined ? { decorationQuota: body.decorationQuota } : {}),
        ...(body.fontDisplay !== undefined ? { fontDisplay: body.fontDisplay } : {}),
        ...(body.fontTitle !== undefined ? { fontTitle: body.fontTitle } : {}),
        ...(body.fontHand !== undefined ? { fontHand: body.fontHand } : {}),
        ...(body.fontFacts !== undefined ? { fontFacts: body.fontFacts } : {}),
        ...(body.quizEnabled !== undefined ? { quizEnabled: body.quizEnabled } : {}),
        ...(body.freeZonesEnabled !== undefined ? { freeZonesEnabled: body.freeZonesEnabled } : {}),
        ...(body.crosswordEnabled !== undefined
          ? { crosswordEnabled: body.crosswordEnabled }
          : {}),
      },
    });

    // Une date de fin qui recule dans le passé **ferme le voyage**, et un
    // compte sans voyage en cours n'a plus d'abonnement à payer. C'est la
    // promesse de l'offre — « Arrêt automatique de l'abonnement » —, et c'est
    // ici qu'elle se tient le plus tôt : au moment où la dernière date bouge.
    if (body.endDate !== undefined) {
      await endSubscriptionsWithoutRunningTrip(context, accountId);
    }

    // On relit tout plutôt que de rendre ce qu'on vient d'écrire : la réponse
    // est ce que l'app garde à l'écran, et une réponse partielle effacerait le
    // reste de la page. Même règle que `PATCH /v1/profile`.
    return readSettings(context, accountId, id);
  });

  /**
   * Retire un co-voyageur du voyage.
   *
   * **Ses souvenirs restent.** Ils appartiennent au récit, pas à la personne —
   * c'est déjà pour ça qu'`entries` n'a pas de colonne d'auteur. On ne retire
   * qu'un droit d'écrire, jamais du texte écrit.
   *
   * `status: "removed"` plutôt qu'une suppression de ligne : la contrainte
   * d'unicité `(memoId, invitedEmail)` doit continuer d'empêcher qu'on réinvite
   * deux fois la même adresse, et l'historique d'un voyage partagé se lit.
   */
  app.delete("/v1/trips/:id/members/:memberId", async (request) => {
    const { id, memberId } = memberParams.parse(request.params);
    const accountId = accountIdOf(request);

    await assertVisible(context, accountId, id);

    const member = await context.prisma.memoMember.findFirst({
      where: { id: memberId, memoId: id },
      select: { id: true },
    });
    if (!member) throw new HttpError(404, "Ce co-voyageur n’est pas sur ce voyage.");

    // Le propriétaire n'a pas de ligne dans `memo_members` : il ne peut donc
    // pas être visé ici, et c'est le garde-fou le plus sûr qui soit — il n'y a
    // rien à supprimer, pas même par erreur.
    await context.prisma.memoMember.update({
      where: { id: memberId },
      data: { status: "removed" },
    });

    return readSettings(context, accountId, id);
  });

  /**
   * Renvoie son lien d'invitation à quelqu'un qui n'est jamais entré.
   *
   * ⚠️ **Rien ne part encore.** `services/mailer.ts` ne sait écrire qu'un seul
   * message, celui du mot de passe oublié : la route vérifie l'appartenance,
   * repousse la
   * date d'invitation — ce qui fait repartir tout compteur d'expiration qu'on
   * posera dessus — et rend 204. C'est volontairement peu : mieux vaut une
   * route honnête qu'un bouton qui prétend avoir envoyé.
   */
  app.post("/v1/trips/:id/members/:memberId/invitation", async (request, reply) => {
    const { id, memberId } = memberParams.parse(request.params);
    const accountId = accountIdOf(request);

    await assertVisible(context, accountId, id);

    const member = await context.prisma.memoMember.findFirst({
      where: { id: memberId, memoId: id, status: "invited" },
      select: { id: true },
    });
    if (!member) {
      throw new HttpError(404, "Cette invitation n’existe pas, ou elle a déjà été acceptée.");
    }

    await context.prisma.memoMember.update({
      where: { id: memberId },
      data: { invitedAt: new Date() },
    });

    return reply.code(204).send();
  });
}

const memberParams = z.object({ id: z.string().uuid(), memberId: z.string().uuid() });

/**
 * Le voyage existe et ce compte y a sa place.
 *
 * Vérifié **avant** l'écriture, et pas seulement par le `where` de l'update :
 * un `updateMany` qui ne touche aucune ligne réussit silencieusement, et l'app
 * croirait son geste enregistré.
 */
async function assertVisible(context: AppContext, accountId: string, memoId: string) {
  const visible = await context.prisma.memo.findFirst({
    where: { id: memoId, ...visibleToAccount(accountId) },
    select: { id: true },
  });
  if (!visible) throw new HttpError(404, "Ce voyage n’existe pas.");
}
