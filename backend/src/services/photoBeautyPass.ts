import sharp from "sharp";
import type { AppContext } from "../context.js";
import { BEAUTY_BATCH, BEAUTY_SIDE, type BeautyCandidate } from "./photoBeauty.js";
import { lisible } from "./photoStickers.js";

type Deps = Pick<AppContext, "prisma" | "storage" | "logger" | "beautyJudge">;

/**
 * Combien de photos on note au plus par passe.
 *
 * Un carnet de cent photos en note cent la première fois, puis zéro : la note
 * est gardée (`entries.photoBeauty`). Le plafond n'est donc pas là pour le
 * prix mais pour le **temps** — une composition ne doit pas attendre dix
 * allers-retours au modèle. Au-delà, les suivantes se noteront à la
 * composition d'après, et les non notées se rangent sur leur netteté en
 * attendant.
 */
export const BEAUTY_PER_PASS = 60;

/**
 * **Note ce qu'on n'a pas encore regardé**, et rend le nombre de photos
 * notées (T265, 23/11/2026).
 *
 * Même forme que ``settlePhotoStickers``, au même endroit du job de
 * structuration, et pour la même raison : c'est un travail de fond, personne
 * n'attend devant son téléphone, et le résultat se garde.
 *
 * **Une photo n'est notée qu'une fois dans sa vie.** La note ne dépend que de
 * la photo — pas du texte, pas de l'étape, pas du carnet —, donc la colonne
 * est remplie une bonne fois et les trente recompositions suivantes ne
 * coûtent rien. C'est ce qui fait tenir le prix : 1,6 ¢ pour un carnet de
 * 109 photos, une fois (`docs/modeles-ia.md` § 2).
 *
 * **Ne lève jamais.** Une note manquante ne vaut pas une composition perdue :
 * sans elle, le carnet choisit ses photos sur la netteté, comme avant le
 * 23/11/2026.
 */
export async function settlePhotoBeauty(deps: Deps, memoId: string): Promise<number> {
  const { prisma, logger } = deps;

  try {
    const photos = await prisma.entry.findMany({
      where: { memoId, kind: "photo", photoBeauty: null, media: { isNot: null } },
      orderBy: { capturedAt: "asc" },
      take: BEAUTY_PER_PASS,
      select: { id: true, media: { select: { storageKey: true } } },
    });
    if (photos.length === 0) return 0;

    const vues: BeautyCandidate[] = [];
    for (const photo of photos) {
      const cle = photo.media?.storageKey;
      if (!cle) continue;
      try {
        const jpeg = await sharp(await lisible(deps, cle))
          .rotate()
          .resize({ width: BEAUTY_SIDE, height: BEAUTY_SIDE, fit: "inside" })
          .jpeg({ quality: 70 })
          .toBuffer();
        vues.push({ id: photo.id, jpeg });
      } catch (cause) {
        logger.debug({ err: cause, entryId: photo.id }, "Photo illisible pour la note.");
      }
    }
    if (vues.length === 0) return 0;

    const notes = [];
    for (let i = 0; i < vues.length; i += BEAUTY_BATCH) {
      notes.push(...(await deps.beautyJudge.score(vues.slice(i, i + BEAUTY_BATCH))));
    }

    // Une par une : chaque note est la sienne, et un `updateMany` par valeur
    // ferait autant de requêtes pour moins de clarté.
    for (const note of notes) {
      await prisma.entry.update({ where: { id: note.id }, data: { photoBeauty: note.score } });
    }

    if (notes.length > 0) {
      logger.info({ memoId, notees: notes.length, vues: vues.length }, "Photos notées");
    }
    return notes.length;
  } catch (cause) {
    logger.warn({ err: cause, memoId }, "Notation des photos abandonnée, le carnet garde la netteté");
    return 0;
  }
}
