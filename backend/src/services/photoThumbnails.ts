import type { AppContext } from "../context.js";
import { downscaleForScreen } from "./photoDownscale.js";

/**
 * **La vignette que l'app affiche** (T260, 17/11/2026).
 *
 * L'écran des couvertures propose **toutes** les photos du voyage comme image
 * de plat, et les servait en pleine résolution. Mesuré en production avant d'y
 * toucher — c'est ce que le ticket demandait :
 *
 * | | mesure |
 * |---|---|
 * | poids moyen d'une photo | **4,45 Mo** (107 photos, 477 Mo) |
 * | taille moyenne | **17,9 Mpx**, soit 68 Mo de bitmap décodé |
 * | pire voyage | 88 photos, **423 Mo** à télécharger pour parcourir le rail |
 * | décodage d'une photo entière | **35 ms** sur un Mac, 0,6 ms pour une vignette |
 * | dessin des sept plats | **3,4 ms** depuis un bitmap déjà décodé |
 *
 * Le temps part donc dans le **réseau**, de deux ordres de grandeur devant le
 * reste ; le décodage vient ensuite, et surtout par la mémoire qu'il prend ;
 * le dessin des plats, lui, ne coûte rien — l'hypothèse du ticket qu'on peut
 * écarter.
 *
 * D'où ce fichier : la photo part en 900 px de grand côté, quelques dizaines
 * de kilo-octets. L'originale ne bouge pas — c'est une **copie**, retenue sur
 * `media_assets.thumbStorageKey`.
 *
 * ⚠️ **Fabriquée à l'arrivée de la photo**, et non à la demande de l'écran.
 * 47 ms sur des octets déjà en mémoire, noyés dans un envoi ; les fabriquer à
 * l'ouverture de l'écran aurait voulu dire quatre secondes pour un voyage de
 * 88 photos, sur une requête que quelqu'un attend. C'est l'inverse du choix de
 * `renderStorageKey` (`services/renderPhotos.ts`), et pour cette raison-là :
 * une composition est un travail de fond, l'ouverture d'un écran non.
 *
 * ⚠️ **Et ce n'est pas la copie du carnet.** Celle-là fait 2400 px et part à
 * l'imprimeur. Servir la vignette au PDF sortirait un carnet flou.
 */

/** Ce qu'on lit d'un média pour savoir quoi servir à l'écran. */
export interface ThumbnailableMedia {
  storageKey: string;
  thumbStorageKey?: string | null;
}

type Deps = Pick<AppContext, "storage" | "logger">;

/**
 * **La clé à servir à l'app** : celle de la vignette, ou celle de la photo
 * elle-même quand il n'y en a pas.
 *
 * Pas de vignette, ce n'est pas une panne : une photo arrivée avant le
 * 17/11/2026 que le rattrapage n'a pas encore vue, ou une photo déjà si légère
 * qu'une vignette ne gagnerait rien. L'écran l'affiche comme avant.
 */
export function screenPhotoKey(media: ThumbnailableMedia): string {
  return media.thumbStorageKey ?? media.storageKey;
}

/**
 * Fabrique la vignette depuis des octets **déjà en mémoire**, la range, et rend
 * sa clé — ou `null` s'il n'y a rien à gagner.
 *
 * Rien ici ne fait échouer un envoi : une photo sans vignette s'affiche en
 * pleine résolution, comme avant ce ticket. C'est pour ça que l'appel n'est pas
 * dans la transaction qui écrit le souvenir — le récit est irremplaçable, la
 * vignette se refabrique.
 */
export async function storeScreenThumbnail(deps: Deps, original: Buffer): Promise<string | null> {
  let thumbnail: Awaited<ReturnType<typeof downscaleForScreen>>;
  try {
    thumbnail = await downscaleForScreen(original);
  } catch (cause) {
    deps.logger.warn({ err: cause }, "Vignette non fabriquée : l'app lira la photo entière");
    return null;
  }
  if (!thumbnail) return null;

  try {
    const stored = await deps.storage.put(
      "photo",
      thumbnail.filename,
      thumbnail.buffer,
      thumbnail.mimeType,
    );
    return stored.storageKey;
  } catch (cause) {
    deps.logger.warn({ err: cause }, "Vignette non rangée : l'app lira la photo entière");
    return null;
  }
}

/**
 * Fabrique la vignette d'une photo **déjà en stock**, et l'écrit sur son média.
 * Rend la clé posée, ou `null` si rien n'a été fait.
 *
 * C'est le chemin du rattrapage (`scripts/retro-vignettes.ts`) : il lit les
 * octets depuis le stockage, ce qui coûte un aller-retour par photo — à
 * l'arrivée d'une photo, ``storeScreenThumbnail`` travaille sur ce qui est
 * déjà là.
 */
export async function backfillScreenThumbnail(
  deps: Deps & Pick<AppContext, "prisma">,
  media: { id: string; storageKey: string; thumbStorageKey?: string | null },
): Promise<string | null> {
  if (media.thumbStorageKey) return null;

  let original: Buffer;
  try {
    original = await deps.storage.get(media.storageKey);
  } catch (cause) {
    deps.logger.warn(
      { err: cause, mediaId: media.id },
      "Photo illisible au moment d'en faire une vignette",
    );
    return null;
  }

  const key = await storeScreenThumbnail(deps, original);
  if (!key) return null;

  await deps.prisma.mediaAsset.update({
    where: { id: media.id },
    data: { thumbStorageKey: key },
  });
  return key;
}
