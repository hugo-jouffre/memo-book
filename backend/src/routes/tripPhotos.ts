import type { FastifyInstance } from "fastify";
import type { AppContext } from "../context.js";
import { HttpError } from "../lib/httpError.js";

/**
 * **Les photos envoyées dans la conversation, en HTTP simple** (Hugo,
 * 12/10/2026 — « le chat doit mieux alimenter la photo du voyage et les
 * étapes »).
 *
 * Dans le fil, une photo se télécharge avec la session
 * (`GET /v1/entries/:id/media`). Mais la photo du voyage et la vignette d'une
 * étape se dessinent par `AsyncImage`, qui n'en envoie pas : jusqu'ici, elles
 * attendaient que la composition du carnet ait publié la photo sur le CDN
 * (`cdnUrl`), et l'accueil du voyage restait sans image. Elles se servent donc
 * ici, comme les photos de profil et de couverture : le nom est un UUID —
 * rien à deviner —, seules les photos y passent, jamais un vocal, et la mise
 * en cache est longue — une photo ne change jamais sous sa clé.
 */

/** Le préfixe de stockage des photos de la conversation (`chat.ts`). */
export const TRIP_PHOTO_PREFIX = "photo";

const TRIP_PHOTO_FILENAME = /^[0-9a-f-]{36}\.(jpg|jpeg|png|heic|heif|webp)$/i;

const MIME_TYPES: Readonly<Record<string, string>> = {
  jpg: "image/jpeg",
  jpeg: "image/jpeg",
  png: "image/png",
  heic: "image/heic",
  heif: "image/heif",
  webp: "image/webp",
};

/** L'adresse publique d'une photo de la conversation, ou `null` pour un autre média. */
export function tripPhotoUrl(publicBaseUrl: string, storageKey: string): string | null {
  const prefix = `${TRIP_PHOTO_PREFIX}/`;
  if (!storageKey.startsWith(prefix)) return null;
  const file = storageKey.slice(prefix.length);
  return TRIP_PHOTO_FILENAME.test(file) ? `${publicBaseUrl}/v1/trip-photos/${file}` : null;
}

/** La photo à montrer pour un média : celle du CDN si elle est publiée, sinon la nôtre. */
export function displayablePhotoUrl(
  publicBaseUrl: string,
  media: { storageKey: string; cdnUrl: string | null } | null | undefined,
): string | null {
  if (!media) return null;
  return media.cdnUrl ?? tripPhotoUrl(publicBaseUrl, media.storageKey);
}

export function registerTripPhotoRoutes(app: FastifyInstance, context: AppContext): void {
  app.get("/v1/trip-photos/:file", async (request, reply) => {
    const { file } = request.params as { file: string };
    if (!TRIP_PHOTO_FILENAME.test(file)) throw HttpError.notFound("Photo introuvable.");

    let body: Buffer;
    try {
      body = await context.storage.get(`${TRIP_PHOTO_PREFIX}/${file}`);
    } catch {
      throw HttpError.notFound("Photo introuvable.");
    }

    const extension = file.split(".").pop()!.toLowerCase();
    return reply
      .header("Cache-Control", "public, max-age=2592000, immutable")
      .type(MIME_TYPES[extension] ?? "application/octet-stream")
      .send(body);
  });
}
