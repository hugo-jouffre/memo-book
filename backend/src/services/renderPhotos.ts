import type { AppContext } from "../context.js";
import { publicApiBaseUrl } from "./avatars.js";
import { isRenderableImage, sniffImageFormat, toRenderablePhoto } from "./photoFormat.js";
import { tripPhotoUrl } from "../routes/tripPhotos.js";

/**
 * **L'adresse à laquelle le moteur de PDF ira chercher une photo** — et le
 * format dans lequel il la trouvera.
 *
 * Deux pannes muettes vivaient là, et chacune suffisait à sortir un carnet
 * sans aucune photo (Hugo, 11/11/2026).
 *
 * 1. **Le format.** La photothèque d'un iPhone donne du HEIC, que Chromium ne
 *    peint pas — voir `services/photoFormat.ts`. Les photos envoyées avant que
 *    la conversion n'existe à l'arrivée sont encore en stock : on les convertit
 *    ici, une fois, au premier carnet qui les demande. L'original reste
 *    (`originalStorageKey`), comme pour un agrandissement.
 *
 * 2. **L'adresse.** Le payload portait l'URL que rendait `publisher.publish`.
 *    Sans `WEBFLOW_API_TOKEN` — c'est-à-dire sur toute machine de
 *    développement, et sur un déploiement où la variable manque —, le
 *    publicateur est **simulé** : il rendait une adresse
 *    `https://cdn.example.test/…`, que rien ne sert. Le PDF se composait, se
 *    déclarait prêt, et n'avait pas une seule photo. Désormais, faute de CDN,
 *    la photo se sert par l'API elle-même (`GET /v1/trip-photos/:file`, déjà
 *    publique et déjà utilisée par l'app), et un échec de publication retombe
 *    sur la même adresse au lieu de faire échouer la composition.
 */

/** Ce qu'on lit d'un média pour en faire une photo de carnet. */
export interface RenderablePhotoMedia {
  id: string;
  storageKey: string;
  mimeType: string;
  cdnUrl: string | null;
  cdnAssetId: string | null;
  /** La clé de l'original, quand cette photo a déjà été réécrite une fois. */
  originalStorageKey?: string | null;
}

type Deps = Pick<AppContext, "prisma" | "storage" | "publisher" | "env" | "logger">;

/**
 * Convertit la photo si le moteur de PDF ne sait pas la lire, puis rend
 * l'adresse publique où il la trouvera — ou `null` si cette photo ne peut pas
 * entrer au carnet. Un `null` n'arrête rien : le composeur rend sa place au
 * récit (`services/bookComposer.ts`).
 */
export async function renderablePhotoUrl(
  deps: Deps,
  media: RenderablePhotoMedia,
): Promise<string | null> {
  const ready = await ensureRenderableFormat(deps, media);
  if (!ready) return null;

  if (ready.cdnUrl) return ready.cdnUrl;

  const base = publicApiBaseUrl(deps.env);
  // **Une adresse en boucle locale ne vaut rien pour APITemplate**, qui
  // télécharge les photos depuis ses serveurs. Sur le worker, Railway ne pose
  // pas toujours `RAILWAY_PUBLIC_DOMAIN` : il faut alors `API_PUBLIC_BASE_URL`
  // (voir docs/deploiement.md). Mieux vaut le lire dans les logs que sur un
  // carnet imprimé.
  if (deps.env.NODE_ENV === "production" && base.includes("localhost")) {
    deps.logger.error(
      { base },
      "Les photos du carnet seraient servies sur une adresse locale : pose API_PUBLIC_BASE_URL sur ce service",
    );
  }

  const ourUrl = tripPhotoUrl(base, ready.storageKey);

  if (!deps.publisher.servesPublicUrls) {
    if (!ourUrl) {
      deps.logger.warn(
        { mediaId: media.id, storageKey: ready.storageKey },
        "Photo hors du préfixe servi par l'API : aucune adresse publique à donner au carnet",
      );
    }
    return ourUrl;
  }

  try {
    const filename = ready.storageKey.split("/").pop() ?? "photo.jpg";
    const published = await deps.publisher.publish(
      filename,
      await deps.storage.signedReadUrl(ready.storageKey),
    );
    await deps.prisma.mediaAsset.update({
      where: { id: media.id },
      data: { cdnUrl: published.cdnUrl, cdnAssetId: published.assetId },
    });
    return published.cdnUrl;
  } catch (cause) {
    // Le CDN a refusé : la photo se sert par l'API. Un carnet sans photos
    // vaut moins qu'un carnet servi par nous — et la ligne le dit.
    deps.logger.warn(
      { err: cause, mediaId: media.id },
      "Publication de la photo sur le CDN échouée : le carnet la lira sur l'API",
    );
    return ourUrl;
  }
}

/**
 * S'assure que les octets stockés sont d'un format que le moteur de PDF peint.
 *
 * Le format se reconnaît sur les **seize premiers octets** — un `Range` de
 * seize octets, pas le fichier entier : une composition qui vérifie trente
 * photos ne doit pas en rapatrier quatre-vingt-dix mégaoctets.
 */
async function ensureRenderableFormat(
  deps: Deps,
  media: RenderablePhotoMedia,
): Promise<RenderablePhotoMedia | null> {
  let head: Buffer;
  try {
    head = await deps.storage.firstBytes(media.storageKey);
  } catch (cause) {
    deps.logger.warn({ err: cause, mediaId: media.id }, "Photo illisible dans le stockage");
    return null;
  }

  if (isRenderableImage(head)) return media;

  // **Un format inconnu n'est pas un format refusé.** On ne reconnaît que les
  // signatures qui nous occupent ; le reste part au carnet comme avant, et
  // c'est la ligne de journal qui le signale. Écarter ce qu'on ne sait pas
  // nommer, ce serait perdre des photos pour se rassurer.
  const format = sniffImageFormat(head);
  if (format === null) {
    deps.logger.warn(
      { mediaId: media.id, mimeType: media.mimeType },
      "Format de photo non reconnu : envoyée telle quelle au moteur de PDF",
    );
    return media;
  }

  const original = await deps.storage.get(media.storageKey);
  const converted = await toRenderablePhoto(original, media.storageKey, media.mimeType);

  if (!converted.converted) {
    deps.logger.warn(
      { mediaId: media.id, format },
      "Photo dans un format que le moteur de PDF ne peint pas, et non convertible : écartée du carnet",
    );
    return null;
  }

  const stored = await deps.storage.put(
    "photo",
    converted.filename,
    converted.buffer,
    converted.mimeType,
  );

  // La copie publique d'avant montrait les octets que personne ne sait lire :
  // elle n'a plus de raison d'exister, et une photo de souvenir ne traîne pas
  // sur un CDN pour rien (`services/deletion.ts`).
  if (media.cdnAssetId && deps.publisher.servesPublicUrls) {
    await deps.publisher.unpublish(media.cdnAssetId).catch((cause: unknown) => {
      deps.logger.warn({ err: cause, mediaId: media.id }, "Ancienne copie CDN non retirée");
    });
  }

  await deps.prisma.mediaAsset.update({
    where: { id: media.id },
    data: {
      storageKey: stored.storageKey,
      mimeType: stored.mimeType,
      bytes: stored.bytes,
      // L'original n'est jamais effacé : une conversion ratée doit pouvoir
      // être rejouée depuis les octets de départ.
      originalStorageKey: media.originalStorageKey ?? media.storageKey,
      cdnUrl: null,
      cdnAssetId: null,
    },
  });

  deps.logger.info(
    { mediaId: media.id, from: media.mimeType, bytes: stored.bytes },
    "Photo convertie en JPEG pour le carnet",
  );

  return { ...media, storageKey: stored.storageKey, mimeType: stored.mimeType, cdnUrl: null, cdnAssetId: null };
}
