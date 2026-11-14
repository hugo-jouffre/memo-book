import type { AppContext } from "../context.js";
import { publicApiBaseUrl } from "./avatars.js";
import { isRenderableImage, sniffImageFormat, toRenderablePhoto } from "./photoFormat.js";
import { downscaleForRender, RENDER_MAX_BYTES } from "./photoDownscale.js";
import { isSimulatedCdnUrl } from "./webflow.js";
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
 *
 *    **Et on ne croit plus une adresse écrite en base sur parole** (Hugo,
 *    14/11/2026). Arrêter d'en fabriquer ne défaisait pas celles déjà posées :
 *    68 photos de production portaient encore l'adresse simulée, dont 59 des
 *    71 d'un même voyage. On l'efface en passant, et le carnet se sert chez
 *    nous.
 *
 * 3. **Le poids** (Hugo, 14/11/2026 — « ça a galéré à créer le PDF »). Le jour
 *    où les adresses sont devenues bonnes, APITemplate s'est mis à télécharger
 *    pour de vrai : 306 Mo pour un carnet de 71 photos d'iPhone, et trois
 *    HTTP 504 de suite. Il part donc une **copie allégée**
 *    (`services/photoDownscale.ts`), fabriquée une fois et retenue sur
 *    `renderStorageKey`. L'original ne bouge pas.
 */

/** Ce qu'on lit d'un média pour en faire une photo de carnet. */
export interface RenderablePhotoMedia {
  id: string;
  storageKey: string;
  mimeType: string;
  /** Le poids des octets stockés : de quoi savoir s'il faut les alléger. */
  bytes: number;
  cdnUrl: string | null;
  cdnAssetId: string | null;
  /** La clé de l'original, quand cette photo a déjà été réécrite une fois. */
  originalStorageKey?: string | null;
  /** La clé de la copie allégée, quand une composition l'a déjà fabriquée. */
  renderStorageKey?: string | null;
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
  const ready = await forgetSimulatedCdnUrl(deps, await ensureRenderableFormat(deps, media));
  if (!ready) return null;

  if (ready.cdnUrl) return ready.cdnUrl;

  // La copie allégée **avant** l'adresse : c'est elle qu'on publie, et c'est
  // elle qu'on sert. Donner l'original à l'un et la copie à l'autre ferait
  // deux carnets différents selon la configuration du jour.
  const served = await ensureRenderCopy(deps, ready);

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

  const ourUrl = tripPhotoUrl(base, served);

  if (!deps.publisher.servesPublicUrls) {
    if (!ourUrl) {
      deps.logger.warn(
        { mediaId: media.id, storageKey: served },
        "Photo hors du préfixe servi par l'API : aucune adresse publique à donner au carnet",
      );
    }
    return ourUrl;
  }

  try {
    const filename = served.split("/").pop() ?? "photo.jpg";
    const published = await deps.publisher.publish(
      filename,
      await deps.storage.signedReadUrl(served),
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
 * **Oublie une adresse de CDN qui ne mène nulle part**, et la retire de la
 * base au passage.
 *
 * On pourrait se contenter de l'ignorer ici. L'effacer vaut mieux : la même
 * adresse est donnée à l'app pour les vignettes d'étapes et la photo du voyage
 * (`routes/tripPhotos.ts`), et une ligne nettoyée répare les deux d'un coup —
 * sans attendre la composition suivante.
 */
async function forgetSimulatedCdnUrl(
  deps: Deps,
  media: RenderablePhotoMedia | null,
): Promise<RenderablePhotoMedia | null> {
  if (!media || !isSimulatedCdnUrl(media.cdnUrl)) return media;

  await deps.prisma.mediaAsset.update({
    where: { id: media.id },
    data: { cdnUrl: null, cdnAssetId: null },
  });
  deps.logger.warn(
    { mediaId: media.id },
    "Adresse de CDN simulée effacée : la photo se sert par l'API",
  );

  return { ...media, cdnUrl: null, cdnAssetId: null };
}

/**
 * **La clé à servir au moteur de PDF** : celle de la copie allégée, ou celle
 * de la photo elle-même quand l'alléger n'apporterait rien.
 *
 * La copie se fabrique **une fois** et se retient sur `renderStorageKey` : une
 * composition qui recommence ne repaie ni le téléchargement ni l'encodage. Et
 * une photo déjà légère ne se télécharge même pas — `bytes` le dit, la base le
 * sait.
 *
 * Rien ici ne fait échouer une composition : stockage muet, octets illisibles,
 * copie plus grosse que l'original — on sert l'original, et la ligne de
 * journal dit ce qui s'est passé.
 */
async function ensureRenderCopy(deps: Deps, media: RenderablePhotoMedia): Promise<string> {
  if (media.renderStorageKey) return media.renderStorageKey;
  if (media.bytes <= RENDER_MAX_BYTES) return media.storageKey;

  let original: Buffer;
  try {
    original = await deps.storage.get(media.storageKey);
  } catch (cause) {
    deps.logger.warn(
      { err: cause, mediaId: media.id },
      "Photo illisible au moment de l'alléger : le carnet lira l'originale",
    );
    return media.storageKey;
  }

  const light = await downscaleForRender(original);
  if (!light) return media.storageKey;

  const stored = await deps.storage.put("photo", light.filename, light.buffer, light.mimeType);
  await deps.prisma.mediaAsset.update({
    where: { id: media.id },
    data: { renderStorageKey: stored.storageKey },
  });

  deps.logger.info(
    {
      mediaId: media.id,
      avant: media.bytes,
      apres: stored.bytes,
      largeur: light.widthPx,
      hauteur: light.heightPx,
    },
    "Copie allégée de la photo fabriquée pour le carnet",
  );

  return stored.storageKey;
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
      // La copie allégée montrait les octets d'avant la conversion : elle ne
      // vaut plus rien, et la prochaine composition en refera une.
      renderStorageKey: null,
    },
  });

  deps.logger.info(
    { mediaId: media.id, from: media.mimeType, bytes: stored.bytes },
    "Photo convertie en JPEG pour le carnet",
  );

  return {
    ...media,
    storageKey: stored.storageKey,
    mimeType: stored.mimeType,
    bytes: stored.bytes,
    cdnUrl: null,
    cdnAssetId: null,
    renderStorageKey: null,
  };
}
