import { randomBytes } from "node:crypto";
import type { FastifyInstance } from "fastify";
import { z } from "zod";
import type { AppContext } from "../context.js";
import { HttpError } from "../lib/httpError.js";
import { accountIdOf } from "../plugins/auth.js";
import { pendingRedactionCount } from "../jobs/structure.js";
import { currentBookFingerprint } from "../services/bookFingerprint.js";
import { visibleToAccount } from "../services/memoOwnership.js";
import { serializeBookPreview } from "./appSerializers.js";

/**
 * L'aperçu du carnet : le PDF composé, et de quoi le partager.
 *
 * Distinct de `GET /v1/renders/:id`, qui sert le **pipeline** — un rendu, son
 * état, son fichier. Celle-ci sert l'**écran** : elle réunit le dernier rendu,
 * le titre que le récit s'est donné, l'extrait de la carte de partage et
 * l'état des couvertures, que trois appels auraient fait apparaître l'un après
 * l'autre.
 *
 * L'app l'interroge en boucle pendant la composition (toutes les deux
 * secondes) : la réponse est donc volontairement petite et ne fait qu'une
 * requête.
 */

const params = z.object({ id: z.string().uuid() });

/** Ce que `serializeBookPreview` attend du carnet, et rien de plus. */
const previewInclude = {
  // Le dernier rendu, quel que soit son état : c'est lui qui dit si ça compose,
  // si c'est prêt, ou si ça a raté. Ne prendre que les `ready` aurait fait
  // passer un échec pour une composition en cours, éternellement.
  renders: {
    orderBy: { createdAt: "desc" as const },
    take: 1,
    select: {
      id: true,
      status: true,
      pdfUrl: true,
      error: true,
      createdAt: true,
      updatedAt: true,
      composingStartedAt: true,
    },
  },
  // De quoi tirer les deux phrases de la carte de partage. Les plus anciennes :
  // l'extrait doit ouvrir le récit, pas le finir.
  //
  // Les trois états du texte d'un souvenir, et non un seul : c'est la version
  // **corrigée à la main** qui fait foi, à défaut la version rédigée, à défaut
  // la transcription brute. Le même ordre de préférence que partout ailleurs
  // dans le pipeline.
  entries: {
    orderBy: { createdAt: "asc" as const },
    take: 5,
    select: { editedText: true, redactedText: true, transcript: true },
  },
};

async function readPreview(context: AppContext, accountId: string, memoId: string) {
  // Le dernier rendu **prêt**, distinct du dernier rendu tout court (ci-dessous,
  // dans `previewInclude`) : une régénération en fond (étape validée) enfile un
  // nouveau rendu `pending` sans `pdfUrl` — l'aperçu ne doit pas perdre le PDF
  // déjà affiché le temps qu'elle aboutisse. Indexé par
  // `@@index([memoId, createdAt])`, donc bon marché même interrogé toutes les
  // deux secondes ; menée en parallèle du reste, les deux requêtes sont
  // indépendantes.
  //
  // L'empreinte du carnet et les souvenirs en rédaction (T224) : de quoi dire
  // si le PDF est à jour, et ce que la composition attend. Quatre petites
  // requêtes agrégées, pas une relecture des textes.
  const [memo, lastReady, currentFingerprint, pendingMemoryCount] = await Promise.all([
    context.prisma.memo.findFirst({
      where: { id: memoId, ...visibleToAccount(accountId) },
      include: previewInclude,
    }),
    context.prisma.render.findFirst({
      where: { memoId, status: "ready" },
      orderBy: { createdAt: "desc" },
      select: { id: true, pdfUrl: true, inputFingerprint: true },
    }),
    currentBookFingerprint(context.prisma, memoId),
    pendingRedactionCount(context.prisma, memoId),
  ]);

  if (!memo) throw new HttpError(404, "Ce carnet n’existe pas.");
  return serializeBookPreview(
    memo,
    { lastReady, currentFingerprint, pendingMemoryCount },
    context.env.SHARE_PUBLIC_BASE_URL,
  );
}

/**
 * Le jeton du lien public.
 *
 * Seize caractères base64url, soit 96 bits d'entropie : le lien n'est protégé
 * par rien d'autre que son imprévisibilité, et il doit résister à quelqu'un qui
 * essaierait de les deviner en masse. Ce n'est **pas** un `accessCode` : celui-là
 * se recopie à la main et fait entrer dans le voyage, celui-ci ne fait que
 * donner à lire.
 */
function newShareSlug(): string {
  return randomBytes(12).toString("base64url");
}

export function registerBookPreviewRoutes(app: FastifyInstance, context: AppContext) {
  app.get("/v1/memos/:id/preview", async (request) => {
    const { id } = params.parse(request.params);
    return readPreview(context, accountIdOf(request), id);
  });

  /**
   * Crée le lien de prévisualisation, ou rend celui qui existe déjà.
   *
   * **Idempotente** : repartager deux fois ne donne pas deux liens. C'est ce
   * qui permet à celui qu'on a envoyé hier de marcher encore aujourd'hui — un
   * lien parti dans une conversation WhatsApp ne se rattrape pas.
   */
  app.post("/v1/memos/:id/share-link", async (request, reply) => {
    const { id } = params.parse(request.params);
    const accountId = accountIdOf(request);

    const memo = await context.prisma.memo.findFirst({
      where: { id, ...visibleToAccount(accountId) },
      select: { id: true, shareSlug: true },
    });
    if (!memo) throw new HttpError(404, "Ce carnet n’existe pas.");

    const slug = memo.shareSlug ?? newShareSlug();

    if (!memo.shareSlug) {
      await context.prisma.memo.update({ where: { id }, data: { shareSlug: slug } });
    }

    // 201 seulement quand on vient de le créer : c'est la différence entre
    // « voilà ton lien » et « voilà ton lien, il est neuf », et elle se lit
    // dans les journaux.
    reply.code(memo.shareSlug ? 200 : 201);
    return { url: `${context.env.SHARE_PUBLIC_BASE_URL}/c/${slug}` };
  });
}
