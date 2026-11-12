import type { FastifyInstance } from "fastify";
import type { AppContext } from "../context.js";
import { HttpError } from "../lib/httpError.js";
import { STICKER_FILENAME, STICKER_PREFIX } from "../services/photoStickers.js";

/**
 * **Les stickers découpés, en HTTP simple** — le jumeau de
 * `routes/tripPhotos.ts`, pour la même raison.
 *
 * Le moteur de PDF télécharge lui-même ce qu'il pose sur la page : il lui faut
 * une adresse publique. Les stickers de la bibliothèque en ont une (GitHub,
 * `STICKERS_URL`) ; ceux qu'on découpe dans les photos du voyageur n'ont que
 * le stockage. Ils se servent donc ici, comme les photos de la conversation :
 * le nom est un UUID — rien à deviner —, seuls les PNG de `sticker/` y
 * passent, et la mise en cache est longue, un sticker ne changeant jamais sous
 * sa clé.
 *
 * ⚠️ **C'est une adresse publique, et le sticker est un bout de photo.** C'est
 * déjà le cas des photos de la conversation, pour le même besoin ; l'œil qui
 * découpe refuse d'ailleurs les visages et les papiers d'identité
 * (`services/stickerVision.ts`).
 */
export function registerTripStickerRoutes(app: FastifyInstance, context: AppContext): void {
  app.get("/v1/trip-stickers/:file", async (request, reply) => {
    const { file } = request.params as { file: string };
    if (!STICKER_FILENAME.test(file)) throw HttpError.notFound("Sticker introuvable.");

    let body: Buffer;
    try {
      body = await context.storage.get(`${STICKER_PREFIX}/${file}`);
    } catch {
      throw HttpError.notFound("Sticker introuvable.");
    }

    return reply
      .header("Cache-Control", "public, max-age=2592000, immutable")
      .type("image/png")
      .send(body);
  });
}
