import type { FastifyInstance } from "fastify";
import { z } from "zod";
import type { AppContext } from "../context.js";
import { HttpError } from "../lib/httpError.js";
import { accountIdOf } from "../plugins/auth.js";
import { visibleToAccount } from "../services/memoOwnership.js";

/**
 * Ce qu'on écrit à l'équipe, et ce qu'on pense des réponses de la foire aux
 * questions (T226, Hugo 06/10/2026) : « les questions envoyées depuis le
 * support ainsi que le contenu de "partager mes retours" dans le mot des
 * fondateurs et les votes "cette réponse t'a aidé" dans la FAQ ne se perdent
 * pas mais soient bien stockés dans notre database ».
 *
 * Jusqu'ici, « Envoyer » attendait 600 ms et disait « envoyé » ; le vote ne
 * vivait que le temps de la session. Tout s'écrit désormais dans
 * `support_messages` et `faq_votes`, part dans l'export des données et
 * disparaît avec le compte.
 *
 * ⚠️ **Rien n'est envoyé à l'équipe** : pas d'e-mail, pas d'alerte. Les
 * messages se lisent en base (`handledAt` nul = à traiter).
 */

/** L'identifiant stable d'une question de `Faq.swift` : `faq.carnet.pages`. */
const questionId = z
  .string()
  .trim()
  .min(1)
  .max(120)
  .regex(/^[A-Za-z0-9._-]+$/, "Identifiant de question invalide.");

const appVersion = z.string().trim().max(40).nullish();

/**
 * Le « diagnostic technique joint automatiquement » que le formulaire
 * annonce. Libre, mais court : c'est un système et un modèle de téléphone,
 * pas un journal — et jamais le contenu des souvenirs.
 */
const diagnostics = z
  .record(z.string().max(60), z.union([z.string().max(200), z.number(), z.boolean(), z.null()]))
  .refine((value) => JSON.stringify(value).length <= 2_048, "Diagnostic trop long.")
  .nullish();

const messageBody = z.object({
  source: z.enum(["support", "founders_note"]),
  topicId: questionId.nullish(),
  message: z.string().trim().min(1, "Le message est vide.").max(5_000),
  tripId: z.string().uuid().nullish(),
  appVersion,
  diagnostics,
});

const voteParams = z.object({ questionId });
const voteBody = z.object({ isHelpful: z.boolean(), appVersion });

/**
 * Au-delà, un compte n'écrit plus pour aujourd'hui. Vingt messages en vingt-
 * quatre heures, c'est déjà une conversation : au-delà c'est un script, ou un
 * bouton qui part en boucle.
 */
const DAILY_MESSAGE_CAP = 20;

export function registerSupportRoutes(app: FastifyInstance, context: AppContext): void {
  /** « Écris à notre équipe » et « Partager mes retours ». */
  app.post("/v1/support/messages", async (request, reply) => {
    const accountId = accountIdOf(request);
    const body = messageBody.parse(request.body ?? {});

    const since = new Date(Date.now() - 24 * 60 * 60 * 1000);
    const recent = await context.prisma.supportMessage.count({
      where: { accountId, createdAt: { gte: since } },
    });
    if (recent >= DAILY_MESSAGE_CAP) {
      throw new HttpError(
        429,
        "Tu nous as déjà beaucoup écrit aujourd’hui : on te répond, et tu pourras nous réécrire demain.",
        "support_rate_limited",
      );
    }

    // Le voyage d'où l'on écrit, **s'il est le sien** : un identifiant qui ne
    // désigne rien de visible est oublié, il ne fait pas échouer un message.
    const memo = body.tripId
      ? await context.prisma.memo.findFirst({
          where: { id: body.tripId, ...visibleToAccount(accountId) },
          select: { id: true },
        })
      : null;

    const saved = await context.prisma.supportMessage.create({
      data: {
        accountId,
        source: body.source,
        topicId: body.topicId ?? null,
        message: body.message,
        memoId: memo?.id ?? null,
        appVersion: body.appVersion ?? null,
        ...(body.diagnostics ? { diagnostics: body.diagnostics } : {}),
      },
      select: { id: true, createdAt: true },
    });

    // Le texte n'entre pas dans le journal : c'est la donnée de la personne.
    context.logger.info(
      { supportMessageId: saved.id, accountId, source: body.source, topicId: body.topicId ?? null },
      "Message à l'équipe enregistré",
    );

    return reply.code(201).send({ id: saved.id, createdAt: saved.createdAt.toISOString() });
  });

  /** Ses votes, pour remplacer les pouces par « Merci ! » d'une session à l'autre. */
  app.get("/v1/support/faq-votes", async (request) => {
    const votes = await context.prisma.faqVote.findMany({
      where: { accountId: accountIdOf(request) },
      orderBy: { updatedAt: "desc" },
    });
    return {
      votes: votes.map((vote) => ({
        questionId: vote.questionId,
        isHelpful: vote.isHelpful,
        updatedAt: vote.updatedAt.toISOString(),
      })),
    };
  });

  /** « Est-ce utile ? » — un vote par compte et par question, qui se change. */
  app.put("/v1/support/faq-votes/:questionId", async (request) => {
    const accountId = accountIdOf(request);
    const { questionId: id } = voteParams.parse(request.params);
    const body = voteBody.parse(request.body ?? {});

    const vote = await context.prisma.faqVote.upsert({
      where: { accountId_questionId: { accountId, questionId: id } },
      create: { accountId, questionId: id, isHelpful: body.isHelpful, appVersion: body.appVersion ?? null },
      update: { isHelpful: body.isHelpful, appVersion: body.appVersion ?? null },
    });

    return { questionId: vote.questionId, isHelpful: vote.isHelpful, updatedAt: vote.updatedAt.toISOString() };
  });
}
