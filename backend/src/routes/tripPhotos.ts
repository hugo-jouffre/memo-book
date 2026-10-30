import type { Prisma } from "@prisma/client";
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

/**
 * **La photo qui illustre un voyage quand aucune n'a été choisie** : la plus
 * récente de ses photos **paysage**, et faute de paysage, la plus récente de
 * ses photos tout court (Hugo, 15 et 18/10/2026 — « il faut que les photos
 * envoyées dans le chat alimentent la photo qui illustre le voyage »).
 *
 * ⚠️ **Une seule règle, lue par toutes les routes** (Hugo, 28/10/2026 — « les
 * photos du chat sont parfois automatiquement ajoutées dans la photo
 * d'accueil, mais ce n'est pas toujours le cas »). Elle ne vivait que dans
 * `home.ts` : l'accueil et l'écran du voyage élisaient une photo, la
 * conversation n'en élisait aucune et montrait sa montagne. Le « parfois »
 * était là — pas dans l'élection, mais dans les routes qui ne la faisaient
 * pas. Toute route qui sérialise un voyage ou son fil charge donc ceci, et
 * passe son `publicBaseUrl` au sérialiseur.
 *
 * **Les trois tris, et pas seulement le premier** : six photos envoyées dans
 * un même message partagent leur `capturedAt` à la milliseconde, et
 * `ORDER BY capturedAt DESC LIMIT 1` laissait Postgres trancher — la
 * couverture changeait d'une requête à l'autre. `createdAt` puis `id` rendent
 * le choix stable.
 *
 * `photoIsLandscape` plutôt qu'une comparaison de deux colonnes, que Prisma ne
 * sait pas faire ; il est écrit à l'arrivée de la photo, avec ses dimensions
 * (`services/photoOrientation.ts`).
 */
export const coverPhotoOrder: Prisma.EntryOrderByWithRelationInput[] = [
  // Les paysages d'abord (`true` avant `false` et `null`), puis la plus récente.
  { photoIsLandscape: { sort: "desc", nulls: "last" } },
  { capturedAt: "desc" },
  { createdAt: "desc" },
  { id: "desc" },
];

/**
 * À inclure dans la requête d'un voyage pour que `serializeTrip` et
 * `serializeChatThread` aient la photo élue sous la main — voir
 * ``coverPhotoOrder``. Une seule photo remonte : celle qui gagne.
 */
export const coverPhotoInclude = {
  entries: {
    where: { kind: "photo" as const, media: { isNot: null } },
    orderBy: coverPhotoOrder,
    take: 1,
    select: { media: { select: { storageKey: true, cdnUrl: true } } },
  },
} as const;

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
