import type { FastifyInstance } from "fastify";
import { Prisma } from "@prisma/client";
import { z } from "zod";
import type { AppContext } from "../context.js";
import { HttpError } from "../lib/httpError.js";
import { finalTextOf } from "../jobs/redact.js";
import { serializePublicBook } from "./appSerializers.js";

/**
 * **Lire un carnet de la galerie de la communauté** — `GET /v1/gallery/:id`
 * (T236).
 *
 * La galerie existait à moitié depuis des semaines : `GET /v1/gallery` servait
 * les cartes, et les cartes ne menaient nulle part — ni écran, ni route pour
 * lire un carnet public. Celle-ci est l'autre moitié.
 *
 * ⚠️ **Elle est publique, alors que `GET /v1/gallery` juste à côté exige une
 * session.** Ce n'est pas un oubli : un carnet de la galerie se lit **sans
 * compte** — c'est à ça que sert une vitrine, montrer à quoi ressemble un
 * MemoBook terminé à quelqu'un qui n'en a pas encore. D'où son enregistrement
 * **hors** du groupe de routes identifiées de `app.ts`, à côté de la page d'un
 * carnet partagé (`sharePage.ts`), qui est publique pour la même raison. Ne pas
 * la déplacer dans le groupe sans le vouloir.
 *
 * **Un seul critère d'entrée, le même que la galerie** : `memos.isPublicGallery`,
 * l'interrupteur « Partager sur la galerie de la communauté » des réglages du
 * voyage. Plus `deletedAt: null` — un carnet jeté sort de la vitrine.
 *
 * **Et un carnet qui n'est pas dans la galerie répond 404, pas 403** : un 403
 * confirmerait qu'un carnet existe à cet identifiant, ce qui est déjà une
 * information sur quelqu'un. Les deux cas se répondent donc pareil.
 */

const params = z.object({ id: z.string().uuid() });

/**
 * **Ce qu'un carnet public montre, et rien d'autre** (arrêté par Hugo le
 * 23/11/2026 : « le récit entier, sans rien d'identifiant »).
 *
 * C'est ici que la décision se prend, dans la requête elle-même : ce qui n'est
 * pas sélectionné ne peut pas fuir par un sérialiseur distrait.
 *
 * **Ce qu'on sert** : le titre du carnet, ses dates, sa couverture, ses pays,
 * ses chiffres (pages, souvenirs), et chaque étape avec son lieu, sa photo et
 * **le récit entier** des souvenirs qui s'y rattachent — le texte tel que le
 * carnet l'imprime (`finalTextOf`, qui respecte le choix « garder ma
 * transcription »).
 *
 * **Ce qu'on ne sert pas, et pourquoi** :
 *
 * - `ownerAccountId` et tout ce qui pend du compte — l'e-mail, le prénom,
 *   l'avatar du propriétaire. Un carnet public ne dit pas **qui** l'a écrit.
 * - `members` / les co-voyageurs. Partager son carnet n'est pas partager le nom
 *   des gens avec qui on a voyagé : ils n'ont rien coché, eux.
 * - `chat_messages`, la conversation avec MEMO. C'est l'atelier, pas le carnet —
 *   on y hésite, on y répond à des questions, et rien n'y est destiné à être lu.
 * - `accessCode` et `shareSlug`. Le premier fait **entrer** dans le voyage ; le
 *   second ouvre une page publique qu'il n'appartient pas à cette route de
 *   distribuer.
 * - les commandes, les rendus, l'abonnement — de l'argent, et rien à montrer.
 * - `entries.insights` et la fiche de cohérence : des notes de machine sur
 *   quelqu'un, que même le voyageur ne lit pas.
 * - les photos qui ne sont pas publiées au CDN. La galerie se regarde sans
 *   compte et notre seau est privé — voir `publiclyServableImageUrl`.
 */
const publicBookSelect = {
  id: true,
  title: true,
  bookTitle: true,
  startDate: true,
  endDate: true,
  coverPhotoUrl: true,
  destinationName: true,
  destinationCountryCode: true,
  gallerySummary: true,
  dayCount: true,
  distanceKilometres: true,
  pageCount: true,
  memoryCount: true,
  steps: {
    orderBy: { number: "asc" as const },
    select: {
      id: true,
      number: true,
      placeName: true,
      destinationName: true,
      destinationCountryCode: true,
      startDate: true,
      endDate: true,
      photoUrl: true,
      transport: true,
      entries: {
        // Le récit dans l'ordre où il a été vécu. Les photos d'un souvenir
        // remontent avec lui : c'est `media.cdnUrl` qui décide si on peut les
        // montrer, pas leur présence.
        orderBy: [{ capturedAt: "asc" }, { createdAt: "asc" }],
        select: {
          id: true,
          kind: true,
          editedText: true,
          redactedText: true,
          transcript: true,
          prefersTranscript: true,
          media: { select: { cdnUrl: true } },
        },
      },
    },
  },
} satisfies Prisma.MemoSelect;

export function registerPublicBookRoutes(app: FastifyInstance, context: AppContext): void {
  app.get<{ Params: { id: string } }>("/v1/gallery/:id", async (request, reply) => {
    const { id } = params.parse(request.params);

    const memo = await context.prisma.memo.findFirst({
      where: { id, isPublicGallery: true, deletedAt: null },
      select: publicBookSelect,
    });

    // Introuvable **et** « pas dans la galerie » répondent la même chose : voir
    // l'en-tête de ce fichier.
    if (!memo) throw HttpError.notFound("Ce carnet n'est pas dans la galerie.");

    // Quelques minutes, comme la page d'un carnet partagé : un carnet public
    // bouge à l'échelle de la semaine, et il se lit sans compte — donc sans
    // raison de relire la base à chaque curieux.
    void reply.header("Cache-Control", "public, max-age=300");

    return { book: serializePublicBook(memo, finalTextOf) };
  });
}
