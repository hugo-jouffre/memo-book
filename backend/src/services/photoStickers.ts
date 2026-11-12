import sharp from "sharp";
import type { AppContext } from "../context.js";
import { publicApiBaseUrl } from "./avatars.js";
import { cutSticker, StickerCutError } from "./stickerCut.js";
import { STICKER_BATCH, STICKER_VISION_SIDE, type StickerCandidatePhoto } from "./stickerVision.js";

/**
 * **Les stickers découpés dans les vraies photos du voyage** (Hugo,
 * 10/11/2026 — « stickers découpés depuis tes vraies photos de billets et
 * tampons »).
 *
 * Ce fichier tient la chaîne, et rien d'autre : il va chercher les photos,
 * montre les réductions à l'œil (`stickerVision.ts`), passe les ciseaux
 * (`stickerCut.ts`), range le PNG, et écrit la ligne. L'œil ne connaît pas la
 * base, les ciseaux ne connaissent pas le réseau, et le composeur ne connaît
 * que des URL.
 *
 * ### Une fois, et pas à chaque carnet
 *
 * Un carnet se recompose souvent — une étape validée, un réglage changé. Le
 * découpage, lui, ne se refait pas : la photo porte la date où on l'a
 * regardée (`entries.stickerCheckedAt`), et le sticker reste
 * (`photo_stickers`). Sans ces deux marques, chaque composition rappellerait
 * le modèle sur les mêmes paysages pour s'entendre répondre « rien à
 * découper ».
 *
 * ### Rien de tout ça n'a le droit de faire échouer un carnet
 *
 * C'est de la décoration. Une photo illisible, un modèle en panne, un
 * stockage qui refuse : on range l'échec dans le journal et la composition
 * continue — avec les stickers de la bibliothèque, comme avant.
 */

/** Le préfixe de stockage des stickers découpés. */
export const STICKER_PREFIX = "sticker";

/** Un nom de fichier de sticker : un UUID, rien à deviner. */
export const STICKER_FILENAME = /^[0-9a-f-]{36}\.png$/;

/**
 * Combien de stickers découpés au plus dans un carnet. Quatre : c'est déjà le
 * maximum de décorations par étape, et au-delà le carnet ressemblerait à un
 * album de brocante. C'est aussi ce qui borne la dépense.
 */
export const STICKERS_PER_TRIP = 4;

/**
 * Combien de photos au plus on montre au modèle à chaque composition. Un
 * voyage de deux semaines en compte deux cents ; les regarder toutes d'un coup
 * coûterait cher pour rien, et celles qu'on n'a pas vues cette fois seront
 * vues à la composition suivante — elles ne sont jamais perdues.
 */
export const STICKER_PHOTOS_EXAMINED = 20;

/** Ce que le composeur reçoit : un sticker, et où le trouver. */
export interface PhotoStickerForBook {
  /** L'identifiant du souvenir photo d'où il sort. */
  entryId: string;
  label: string;
  url: string;
  width: number;
  height: number;
}

/** L'adresse publique d'un sticker découpé. */
export function photoStickerUrl(publicBaseUrl: string, storageKey: string): string | null {
  const prefix = `${STICKER_PREFIX}/`;
  if (!storageKey.startsWith(prefix)) return null;
  const file = storageKey.slice(prefix.length);
  return STICKER_FILENAME.test(file) ? `${publicBaseUrl}/v1/trip-stickers/${file}` : null;
}

type Deps = Pick<AppContext, "prisma" | "storage" | "env" | "logger" | "stickerSpotter">;

/**
 * **Découpe ce qui peut l'être dans les photos qu'on n'a pas encore
 * regardées.** Rend le nombre de stickers nouvellement découpés.
 *
 * Ne lève jamais : tout échec est journalisé et la composition continue.
 */
export async function settlePhotoStickers(deps: Deps, memoId: string): Promise<number> {
  const { prisma, logger } = deps;

  try {
    const dejaDecoupes = await prisma.photoSticker.count({ where: { memoId } });
    const place = STICKERS_PER_TRIP - dejaDecoupes;
    if (place <= 0) return 0;

    const photos = await prisma.entry.findMany({
      where: { memoId, kind: "photo", stickerCheckedAt: null, media: { isNot: null } },
      orderBy: { capturedAt: "asc" },
      take: STICKER_PHOTOS_EXAMINED,
      select: { id: true, placeLabel: true, media: { select: { storageKey: true } } },
    });
    if (photos.length === 0) return 0;

    // Les réductions : c'est ce qu'on montre au modèle. Une photo illisible ne
    // part pas — mais elle est quand même marquée vue, sinon on la relirait à
    // chaque carnet pour échouer pareil.
    const vues: StickerCandidatePhoto[] = [];
    for (const photo of photos) {
      const cle = photo.media?.storageKey;
      if (!cle) continue;
      try {
        const original = await deps.storage.get(cle);
        const jpeg = await sharp(original)
          .rotate()
          .resize({ width: STICKER_VISION_SIDE, height: STICKER_VISION_SIDE, fit: "inside" })
          .jpeg({ quality: 70 })
          .toBuffer();
        vues.push({ id: photo.id, jpeg, placeLabel: photo.placeLabel });
      } catch (cause) {
        logger.debug({ err: cause, entryId: photo.id }, "Photo illisible pour un sticker.");
      }
    }

    const reperes = [];
    for (let i = 0; i < vues.length; i += STICKER_BATCH) {
      reperes.push(...(await deps.stickerSpotter.spot(vues.slice(i, i + STICKER_BATCH))));
    }

    // **Toutes** les photos de cette passe sont marquées vues, repérées ou
    // non : c'est la marque qui dit « on a regardé », pas « on a trouvé ».
    const vuesMaintenant = new Date();
    await prisma.entry.updateMany({
      where: { id: { in: photos.map((photo) => photo.id) } },
      data: { stickerCheckedAt: vuesMaintenant },
    });

    // Le meilleur d'abord : si le voyage n'a plus la place que pour deux
    // stickers, autant que ce soient les deux plus beaux.
    const retenus = reperes.sort((a, b) => b.score - a.score).slice(0, place);
    const parEntree = new Map(photos.map((photo) => [photo.id, photo]));

    let decoupes = 0;
    for (const repere of retenus) {
      const cle = parEntree.get(repere.photoId)?.media?.storageKey;
      if (!cle) continue;
      try {
        const original = await deps.storage.get(cle);
        const sticker = await cutSticker(original, repere.corners);
        // `put` tire lui-même l'UUID du fichier : `sticker/<uuid>.png`.
        const { storageKey } = await deps.storage.put(
          STICKER_PREFIX,
          "sticker.png",
          sticker.png,
          "image/png",
        );
        await prisma.photoSticker.create({
          data: {
            memoId,
            entryId: repere.photoId,
            storageKey,
            label: repere.label,
            score: repere.score,
            widthPx: sticker.width,
            heightPx: sticker.height,
          },
        });
        decoupes += 1;
        logger.info({ memoId, entryId: repere.photoId, label: repere.label }, "Sticker découpé.");
      } catch (cause) {
        // Un découpage raté ne se réessaie pas : la photo est marquée vue, et
        // les mêmes coins donneraient le même échec.
        const attendu = cause instanceof StickerCutError;
        logger[attendu ? "debug" : "warn"](
          { err: cause, memoId, entryId: repere.photoId },
          "Découpage du sticker impossible.",
        );
      }
    }
    return decoupes;
  } catch (cause) {
    logger.warn({ err: cause, memoId }, "Les stickers découpés n'ont pas pu être préparés.");
    return 0;
  }
}

/** Les stickers découpés d'un voyage, prêts pour le composeur. */
export async function photoStickersOf(deps: Deps, memoId: string): Promise<PhotoStickerForBook[]> {
  const base = publicApiBaseUrl(deps.env);
  const lignes = await deps.prisma.photoSticker.findMany({
    where: { memoId },
    orderBy: [{ score: "desc" }, { createdAt: "asc" }],
    take: STICKERS_PER_TRIP,
  });

  const stickers: PhotoStickerForBook[] = [];
  for (const ligne of lignes) {
    const url = photoStickerUrl(base, ligne.storageKey);
    if (!url) continue;
    stickers.push({
      entryId: ligne.entryId,
      label: ligne.label,
      url,
      width: ligne.widthPx,
      height: ligne.heightPx,
    });
  }
  return stickers;
}
