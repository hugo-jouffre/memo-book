import type { FastifyInstance } from "fastify";
import { z } from "zod";
import type { AppContext } from "../context.js";
import { HttpError } from "../lib/httpError.js";
import { accountIdOf } from "../plugins/auth.js";
import { publicApiBaseUrl } from "../services/avatars.js";
import {
  BACK_COVER_STYLES,
  COVER_PHOTO_FILENAME,
  COVER_PHOTO_PREFIX,
  FRONT_COVER_STYLES,
  coverPhotoMimeType,
  coverStatsOf,
  coverStylesFor,
  currentCoverStyleId,
  readStoredCover,
  type CoverFace,
  type StoredCover,
} from "../services/coverCatalogue.js";
import { visibleToAccount } from "../services/memoOwnership.js";

/**
 * Les deux plats du carnet : ce qu'on a choisi pour chacun, et de quoi choisir.
 *
 * **La route que l'écran attendait depuis le 15/09** (T88). Jusqu'ici une
 * photo importée pour la couverture vivait dans les caches de l'appareil et se
 * perdait à la fermeture de l'écran, et le style, les textes et les chiffres
 * du dos ne partaient nulle part. Tout tient désormais dans `memos.coverFront`
 * et `coverBack` — la structure libre du schéma s'est fixée sur ce que l'app
 * envoie, voir `services/coverCatalogue.ts` — et les photos importées dans
 * `cover_photos`, stockées comme les photos de profil.
 *
 * **Un co-voyageur règle comme le propriétaire** (`visibleToAccount`) : c'est la
 * règle de tout le voyage.
 */

const params = z.object({ id: z.string().uuid() });

const face = z.enum(["front", "back"]);

/**
 * Un geste à la fois, comme les personnalisations : le style, la photo, les
 * textes ou les chiffres — c'est ce que `BookCoverEdit` envoie côté app.
 */
const updateBody = z.object({
  face,
  styleId: z.string().min(1).max(40).optional(),
  photoId: z.string().min(1).max(80).nullable().optional(),
  title: z.string().max(120).optional(),
  subtitle: z.string().max(600).optional(),
  statIds: z.array(z.string().min(1).max(40)).max(4).optional(),
});

/** Une photo de couverture ne pèse pas plus : l'app la réduit avant de l'envoyer. */
const MAX_COVER_PHOTO_BYTES = 12 * 1024 * 1024;

const memoSelect = {
  id: true,
  coverFront: true,
  coverBack: true,
  startDate: true,
  endDate: true,
  dayCount: true,
  distanceKilometres: true,
  destinationCountryCode: true,
  memoryCount: true,
  photoCount: true,
  steps: { select: { destinationCountryCode: true, transport: true } },
  coverPhotos: { orderBy: { createdAt: "asc" as const } },
} as const;

export function coverPhotoUrl(env: AppContext["env"], storageKey: string): string {
  const filename = storageKey.slice(COVER_PHOTO_PREFIX.length + 1);
  return `${publicApiBaseUrl(env)}/v1/cover-photos/${filename}`;
}

async function readCovers(context: AppContext, accountId: string, memoId: string) {
  const memo = await context.prisma.memo.findFirst({
    where: { id: memoId, ...visibleToAccount(accountId) },
    select: memoSelect,
  });
  if (!memo) throw new HttpError(404, "Ce voyage n’existe pas.");

  // Les photos du voyage — celles de la conversation — s'offrent aussi à la
  // couverture, par une adresse signée le temps de choisir : le seau est
  // privé, et une photo de souvenir n'a pas à devenir publique parce qu'on la
  // regarde ici.
  const entryPhotos = await context.prisma.entry.findMany({
    where: { memoId, kind: "photo", mediaId: { not: null } },
    orderBy: { createdAt: "asc" },
    select: { id: true, media: { select: { storageKey: true } } },
  });

  const photos: { id: string; url: string | null }[] = [];
  for (const entry of entryPhotos) {
    if (!entry.media) continue;
    photos.push({
      id: `entry-${entry.id}`,
      url: await context.storage.signedReadUrl(entry.media.storageKey).catch(() => null),
    });
  }
  for (const photo of memo.coverPhotos) {
    photos.push({ id: photo.id, url: coverPhotoUrl(context.env, photo.storageKey) });
  }

  return {
    front: readStoredCover("front", memo.coverFront),
    back: readStoredCover("back", memo.coverBack),
    frontStyles: FRONT_COVER_STYLES,
    backStyles: BACK_COVER_STYLES,
    photos,
    stats: coverStatsOf(memo, memo.steps, entryPhotos.length),
  };
}

export function registerCoverRoutes(app: FastifyInstance, context: AppContext): void {
  app.get("/v1/trips/:id/covers", async (request) => {
    const { id } = params.parse(request.params);
    return readCovers(context, accountIdOf(request), id);
  });

  app.patch("/v1/trips/:id/covers", async (request) => {
    const { id } = params.parse(request.params);
    const body = updateBody.parse(request.body);
    const accountId = accountIdOf(request);

    const memo = await context.prisma.memo.findFirst({
      where: { id, ...visibleToAccount(accountId) },
      select: { coverFront: true, coverBack: true, coverPhotos: { select: { id: true, storageKey: true } } },
    });
    if (!memo) throw new HttpError(404, "Ce voyage n’existe pas.");

    const which: CoverFace = body.face;
    const current = readStoredCover(which, which === "front" ? memo.coverFront : memo.coverBack);
    const next: StoredCover = { ...current };

    if (body.styleId !== undefined) {
      // Un style d'avant les gabarits (08/10/2026) — une app restée hors
      // ligne avec l'ancien catalogue — prend celui qui le remplace.
      const styleId = currentCoverStyleId(body.styleId);
      if (!coverStylesFor(which).some((style) => style.id === styleId)) {
        throw HttpError.badRequest("Ce style de couverture n’existe pas.", "unknown_cover_style");
      }
      next.styleId = styleId;
    }

    if (body.photoId !== undefined) {
      if (body.photoId !== null) {
        const uploaded = memo.coverPhotos.some((photo) => photo.id === body.photoId);
        const fromTrip =
          body.photoId.startsWith("entry-") &&
          (await context.prisma.entry.count({
            where: { id: body.photoId.slice("entry-".length), memoId: id, kind: "photo" },
          })) > 0;
        if (!uploaded && !fromTrip) {
          throw HttpError.badRequest("Cette photo n’est pas dans le voyage.", "unknown_cover_photo");
        }
      }
      next.photoId = body.photoId;
    }

    if (body.title !== undefined) next.title = body.title;
    if (body.subtitle !== undefined) next.subtitle = body.subtitle;
    if (body.statIds !== undefined) next.statIds = body.statIds;

    // La photo de la première de couverture est aussi **la photo du voyage**
    // sur l'accueil et l'aperçu — quand c'est une photo importée, servie à une
    // adresse durable. Une photo de la conversation garde ce qu'il y avait.
    const uploadedFront =
      which === "front" && next.photoId
        ? memo.coverPhotos.find((photo) => photo.id === next.photoId)
        : undefined;

    await context.prisma.memo.update({
      where: { id },
      data: {
        // Un objet nu, pas l'interface : c'est ce que la colonne JSON accepte.
        ...(which === "front" ? { coverFront: { ...next } } : { coverBack: { ...next } }),
        ...(uploadedFront ? { coverPhotoUrl: coverPhotoUrl(context.env, uploadedFront.storageKey) } : {}),
      },
    });

    return readCovers(context, accountId, id);
  });

  /**
   * Une photo importée pour la couverture : stockée comme une photo de profil,
   * servie par `GET /v1/cover-photos/:file`. Elle entre dans la liste des photos
   * du voyage, et c'est l'app qui la pose ensuite sur un plat par le `PATCH`.
   */
  app.post("/v1/trips/:id/covers/photos", async (request) => {
    const { id } = params.parse(request.params);
    const accountId = accountIdOf(request);

    const visible = await context.prisma.memo.findFirst({
      where: { id, ...visibleToAccount(accountId) },
      select: { id: true },
    });
    if (!visible) throw new HttpError(404, "Ce voyage n’existe pas.");

    const file = await request.file({ limits: { fileSize: MAX_COVER_PHOTO_BYTES } });
    if (!file) throw HttpError.badRequest("Aucun fichier reçu.");

    const buffer = await file.toBuffer();
    if (buffer.byteLength === 0) throw HttpError.badRequest("Le fichier reçu est vide.");

    const mimeType = file.mimetype;
    if (mimeType !== "image/jpeg" && mimeType !== "image/png") {
      throw HttpError.badRequest(
        `Type d'image non supporté : ${mimeType}. Attendu : image/jpeg ou image/png.`,
      );
    }

    const filename = mimeType === "image/png" ? "cover.png" : "cover.jpg";
    const stored = await context.storage.put(COVER_PHOTO_PREFIX, filename, buffer, mimeType);

    const photo = await context.prisma.coverPhoto.create({
      data: { memoId: id, storageKey: stored.storageKey, mimeType, bytes: stored.bytes },
    });

    return { photo: { id: photo.id, url: coverPhotoUrl(context.env, photo.storageKey) } };
  });

  app.delete("/v1/trips/:id/covers/photos/:photoId", async (request, reply) => {
    const { id } = params.parse(request.params);
    const { photoId } = z.object({ photoId: z.string().uuid() }).parse(request.params);
    const accountId = accountIdOf(request);

    const photo = await context.prisma.coverPhoto.findFirst({
      where: { id: photoId, memo: { id, ...visibleToAccount(accountId) } },
    });
    if (!photo) throw HttpError.notFound("Photo introuvable.");

    await context.prisma.coverPhoto.delete({ where: { id: photoId } });
    await context.storage.remove([photo.storageKey]).catch((cause: unknown) => {
      request.log.warn({ cause }, "Photo de couverture non retirée du stockage");
    });

    return reply.code(204).send();
  });
}

/**
 * Les photos de couverture importées, servies **sans session**, comme les
 * photos de profil : elles s'impriment sur un carnet qu'on partage, et le
 * gabarit les lit par leur adresse. Le nom est un UUID — rien à deviner —, et
 * la mise en cache est longue : une photo ne change jamais, on en importe une
 * autre.
 */
export function registerCoverPhotoRoutes(app: FastifyInstance, context: AppContext): void {
  app.get("/v1/cover-photos/:file", async (request, reply) => {
    const { file } = request.params as { file: string };
    if (!COVER_PHOTO_FILENAME.test(file)) throw HttpError.notFound("Photo introuvable.");

    let body: Buffer;
    try {
      body = await context.storage.get(`${COVER_PHOTO_PREFIX}/${file}`);
    } catch {
      throw HttpError.notFound("Photo introuvable.");
    }

    return reply
      .header("Cache-Control", "public, max-age=2592000, immutable")
      .type(coverPhotoMimeType(file))
      .send(body);
  });
}
