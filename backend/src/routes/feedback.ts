import type { FeedbackCampaign, FeedbackQuestion } from "@prisma/client";
import type { FastifyInstance } from "fastify";
import { z } from "zod";
import type { AppContext } from "../context.js";
import { matchesAudience, parseAudience } from "../services/feedbackAudience.js";
import { HttpError } from "../lib/httpError.js";
import { accountIdOf } from "../plugins/auth.js";

/**
 * **La modale d'avis, poussée sans livrer de version** (T273, Hugo,
 * 05/11/2026 — « vérifier qu'on peut envoyer des popups aux utilisateurs sans
 * leur faire retélécharger l'app »).
 *
 * Les tables existaient depuis le 07/09/2026 (`feedback_campaigns`,
 * `feedback_questions`, `feedback_responses`, `feedback_answers`) ; rien ne
 * les servait. Ces deux routes les branchent : l'app ne connaît que les
 * **formes** de question et sait les dessiner, le reste — le texte, l'ordre,
 * le nombre, le moment — est une insertion en base.
 *
 * ⚠️ **Jamais de note sur l'App Store ici.** Hugo l'a écarté pour le moment :
 * on demande un avis, on ne demande pas une étoile.
 */

const campaignParams = z.object({ id: z.string().uuid() });

/**
 * Ce que l'app renvoie : une réponse par question, ou rien du tout quand la
 * modale a été fermée.
 *
 * `dismissed` et des réponses ne vont pas ensemble — mais une app qui
 * enverrait les deux n'est pas un cas à traiter : le serveur retient le geste
 * (`dismissedAt`) **et** ce qui a été écrit, et personne n'a rien perdu.
 */
const responseBody = z.object({
  dismissed: z.boolean().default(false),
  appVersion: z.string().max(32).optional(),
  answers: z
    .array(
      z.object({
        questionId: z.string().uuid(),
        /** `text` — ce qui a été écrit. */
        text: z.string().max(4_000).optional(),
        /** `slider` et `rating` — la valeur retenue. */
        number: z.number().finite().optional(),
        /** `choice` — la clé de l'option, pas son libellé. */
        choiceKey: z.string().max(64).optional(),
      }),
    )
    .max(20)
    .default([]),
});

type CampaignWithQuestions = FeedbackCampaign & { questions: FeedbackQuestion[] };

/**
 * La campagne à montrer à ce compte, ou `null`.
 *
 * Trois conditions, et elles se lisent dans cet ordre : la campagne est
 * **ouverte** (drapeau levé, fenêtre en cours), elle a au moins une question,
 * et cette personne ne l'a pas déjà vue plus de `maxDisplays` fois. Une
 * campagne déjà **envoyée ou fermée** ne revient jamais, quel que soit le
 * compteur : répondre, c'est en avoir fini avec elle.
 *
 * `audience` se lit depuis le 23/11/2026 (`services/feedbackAudience.ts`) :
 * quatre critères, qui se cumulent. Un critère **inconnu** ferme encore la
 * campagne, et c'est la même prudence qu'avant — mieux vaut une modale qui ne
 * paraît pas qu'une modale servie à côté de sa cible, sans que personne ne le
 * voie.
 */
async function campaignFor(
  context: AppContext,
  accountId: string,
  now: Date,
): Promise<CampaignWithQuestions | null> {
  const open = await context.prisma.feedbackCampaign.findMany({
    where: {
      isActive: true,
      OR: [{ startsAt: null }, { startsAt: { lte: now } }],
      AND: [{ OR: [{ endsAt: null }, { endsAt: { gte: now } }] }],
    },
    include: { questions: { orderBy: { position: "asc" } } },
    orderBy: { createdAt: "asc" },
  });

  for (const campaign of open) {
    if (campaign.questions.length === 0) continue;

    const audience = parseAudience(campaign.audience);
    if (audience === null) {
      // Une audience illisible — un critère qu'on ne connaît pas, une faute
      // de frappe — ne vaut pas une audience vide : la campagne attend la
      // version qui la comprend, et le journal dit laquelle.
      context.logger.warn(
        { campaign: campaign.key },
        "Campagne d'avis écartée : audience illisible",
      );
      continue;
    }
    if (!(await matchesAudience(context, audience, accountId, now))) continue;

    const seen = await context.prisma.feedbackResponse.findUnique({
      where: { campaignId_accountId: { campaignId: campaign.id, accountId } },
      select: { displayCount: true, submittedAt: true, dismissedAt: true },
    });
    if (seen?.submittedAt || seen?.dismissedAt) continue;
    if (seen && seen.displayCount >= campaign.maxDisplays) continue;

    return campaign;
  }

  return null;
}

function serializeCampaign(campaign: CampaignWithQuestions) {
  return {
    id: campaign.id,
    key: campaign.key,
    title: campaign.title,
    subtitle: campaign.subtitle,
    submitLabel: campaign.submitLabel,
    questions: campaign.questions.map((question) => ({
      id: question.id,
      kind: question.kind,
      prompt: question.prompt,
      placeholder: question.placeholder,
      isRequired: question.isRequired,
      // Tel quel : chaque forme a ses réglages, et l'app ne lit que ceux de
      // la forme qu'elle dessine (`options`, `min`/`max`, `max`).
      config: question.config,
    })),
  };
}

export function registerFeedbackRoutes(app: FastifyInstance, context: AppContext): void {
  /**
   * **La modale à montrer, s'il y en a une.** L'app appelle en ouvrant
   * l'accueil ; `null` est la réponse la plus fréquente, et c'est bien.
   *
   * La lire **compte comme un affichage** (`displayCount`) : c'est ce
   * compteur que `maxDisplays` borne, et il doit monter là où la modale
   * paraît, pas là où elle est remplie — une modale fermée d'un geste ne
   * passerait jamais par la seconde route.
   */
  app.get("/v1/feedback-campaign", async (request) => {
    const accountId = accountIdOf(request);
    const campaign = await campaignFor(context, accountId, new Date());
    if (!campaign) return { campaign: null };

    await context.prisma.feedbackResponse.upsert({
      where: { campaignId_accountId: { campaignId: campaign.id, accountId } },
      create: { campaignId: campaign.id, accountId },
      update: { displayCount: { increment: 1 } },
    });

    return { campaign: serializeCampaign(campaign) };
  });

  /**
   * **Ce que la personne en a fait** : elle a répondu, ou elle a fermé. Les
   * deux comptent — savoir qu'on écarte une question est un résultat.
   *
   * Idempotent par (campagne, compte) : la ligne existe déjà depuis
   * l'affichage, on la complète. Renvoyer deux fois ne crée pas deux avis.
   */
  app.post("/v1/feedback-campaigns/:id/response", async (request, reply) => {
    const { id } = campaignParams.parse(request.params);
    const body = responseBody.parse(request.body ?? {});
    const accountId = accountIdOf(request);
    const now = new Date();

    const campaign = await context.prisma.feedbackCampaign.findUnique({
      where: { id },
      select: { id: true, questions: { select: { id: true } } },
    });
    if (!campaign) throw HttpError.notFound("Campagne introuvable.");

    // Une réponse qui vise une question d'une autre campagne est écartée sans
    // faire échouer l'envoi : le reste de l'avis vaut toujours.
    const known = new Set(campaign.questions.map((question) => question.id));
    const answers = body.answers.filter((answer) => known.has(answer.questionId));

    await context.prisma.$transaction(async (tx) => {
      const response = await tx.feedbackResponse.upsert({
        where: { campaignId_accountId: { campaignId: campaign.id, accountId } },
        create: {
          campaignId: campaign.id,
          accountId,
          ...(body.appVersion ? { appVersion: body.appVersion } : {}),
          ...(body.dismissed ? { dismissedAt: now } : { submittedAt: now }),
        },
        update: {
          ...(body.appVersion ? { appVersion: body.appVersion } : {}),
          ...(body.dismissed ? { dismissedAt: now } : { submittedAt: now }),
        },
      });

      for (const answer of answers) {
        const data = {
          textValue: answer.text ?? null,
          numberValue: answer.number ?? null,
          choiceKey: answer.choiceKey ?? null,
        };
        await tx.feedbackAnswer.upsert({
          where: { responseId_questionId: { responseId: response.id, questionId: answer.questionId } },
          create: { responseId: response.id, questionId: answer.questionId, ...data },
          update: data,
        });
      }
    });

    return reply.code(204).send();
  });
}
