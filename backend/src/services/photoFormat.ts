/**
 * **Le format dans lequel une photo doit arriver au carnet** (Hugo,
 * 11/11/2026 — « les photos n'apparaissent pas dans les PDF »).
 *
 * Le PDF est composé par un Chromium — le nôtre en local, celui d'APITemplate
 * en production. Or **Chromium ne décode pas le HEIC** : vérifié ici, une
 * `<img>` qui pointe sur un HEIC reste à `naturalWidth: 0`, `complete: true`,
 * et **aucun évènement `error` n'est émis**. La page se compose donc sans la
 * photo, le rendu se déclare prêt, et rien dans les journaux ne le dit.
 *
 * Et le HEIC arrive bel et bien : la photothèque d'un iPhone le stocke en
 * « haute efficacité », et l'app envoyait les octets du fichier tels quels,
 * sous un nom en `.jpg` et un `content-type: image/jpeg`. Le mensonge ne se
 * voyait nulle part — iOS, lui, décode le HEIC : la photo s'affichait dans la
 * conversation et dans l'app, et disparaissait au carnet.
 *
 * **On ne croit donc pas le type déclaré : on regarde les octets.** Tout ce
 * que Chromium ne sait pas peindre est converti en JPEG ici, à l'arrivée de la
 * photo (`routes/chat.ts`, `routes/entries.ts`, `routes/covers.ts`) et, pour
 * celles déjà en stock, avant la composition (`jobs/structure.ts`).
 *
 * Deux effets de bord gagnés au passage :
 * - `services/photoOrientation.ts` sait mesurer un JPEG, pas un HEIC : une
 *   photo convertie redevient candidate à la couverture du voyage ;
 * - `services/photoAnalysis.ts` (scotch, point de focus) lit le même fichier.
 */

/** Ce qu'un Chromium de rendu peint sans rien installer. */
const RENDERABLE = new Set(["image/jpeg", "image/png", "image/webp", "image/gif", "image/avif"]);

/** Qualité d'encodage : au-dessus, le fichier double sans gain visible en A5. */
export const JPEG_QUALITY = 90;

/**
 * Le format **réel** d'un fichier image, d'après ses premiers octets, ou
 * `null` si on ne le reconnaît pas.
 *
 * Les signatures, et pas l'extension ni le `content-type` : les deux viennent
 * du client, et c'est précisément ce qui nous a menés ici.
 */
export function sniffImageFormat(buffer: Buffer): string | null {
  if (buffer.length < 12) return null;

  // JPEG : FF D8 FF
  if (buffer[0] === 0xff && buffer[1] === 0xd8 && buffer[2] === 0xff) return "image/jpeg";

  // PNG : 89 50 4E 47 0D 0A 1A 0A
  if (buffer.subarray(0, 8).equals(Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]))) {
    return "image/png";
  }

  // GIF87a / GIF89a
  if (buffer.subarray(0, 3).toString("latin1") === "GIF") return "image/gif";

  // RIFF….WEBP
  if (
    buffer.subarray(0, 4).toString("latin1") === "RIFF" &&
    buffer.subarray(8, 12).toString("latin1") === "WEBP"
  ) {
    return "image/webp";
  }

  // ISO-BMFF : « ....ftyp<marque> ». HEIC, HEIF et AVIF partagent le conteneur
  // et ne se distinguent que par leur marque.
  if (buffer.subarray(4, 8).toString("latin1") === "ftyp") {
    const brand = buffer.subarray(8, 12).toString("latin1");
    if (brand === "avif" || brand === "avis") return "image/avif";
    // `mif1` / `msf1` sont les marques génériques des HEIF produits par iOS.
    if (["heic", "heix", "hevc", "hevx", "heim", "heis", "hevm", "hevs", "mif1", "msf1"].includes(brand)) {
      return brand === "msf1" || brand === "hevc" || brand === "hevx" ? "image/heic-sequence" : "image/heic";
    }
    return null;
  }

  return null;
}

/** Vrai quand le Chromium de rendu saura peindre ces octets. */
export function isRenderableImage(buffer: Buffer): boolean {
  const format = sniffImageFormat(buffer);
  return format !== null && RENDERABLE.has(format);
}

export interface NormalizedPhoto {
  buffer: Buffer;
  /** Le type **réel** du résultat — celui qu'on écrit dans le stockage. */
  mimeType: string;
  /** Le nom de fichier à donner au stockage, extension comprise. */
  filename: string;
  /** Vrai quand les octets ont été réencodés. */
  converted: boolean;
}

/** L'extension qui va avec un type, pour que la clé de stockage ne mente pas. */
function extensionOf(mimeType: string): string {
  switch (mimeType) {
    case "image/png":
      return "png";
    case "image/webp":
      return "webp";
    case "image/gif":
      return "gif";
    case "image/avif":
      return "avif";
    default:
      return "jpg";
  }
}

/** Le nom reçu, privé de son extension — on la remplace par la vraie. */
function stem(filename: string): string {
  const base = filename.split("/").pop() ?? "photo";
  const dot = base.lastIndexOf(".");
  const withoutExtension = dot > 0 ? base.slice(0, dot) : base;
  return withoutExtension || "photo";
}

/**
 * **Rend une photo peignable par le moteur de PDF.**
 *
 * Un format que Chromium peint revient tel quel — on ne réencode jamais un
 * JPEG, ce serait perdre de la matière pour rien. Un HEIC est décodé puis
 * réencodé en JPEG.
 *
 * Une conversion **impossible** (fichier tronqué, format inconnu) ne jette
 * pas : on rend les octets d'origine, `converted: false`, et c'est à
 * l'appelant de le journaliser. Mieux vaut un souvenir enregistré dont la
 * photo manquera qu'un envoi refusé — le récit, lui, est irremplaçable.
 */
export async function toRenderablePhoto(
  buffer: Buffer,
  filename: string,
  declaredMimeType: string,
): Promise<NormalizedPhoto> {
  const format = sniffImageFormat(buffer);

  if (format !== null && RENDERABLE.has(format)) {
    return { buffer, mimeType: format, filename: `${stem(filename)}.${extensionOf(format)}`, converted: false };
  }

  if (format === "image/heic" || format === "image/heic-sequence") {
    const jpeg = await heicToJpeg(buffer);
    if (jpeg) {
      return { buffer: jpeg, mimeType: "image/jpeg", filename: `${stem(filename)}.jpg`, converted: true };
    }
  }

  // Format inconnu : on garde ce qu'on a reçu, en gardant le type déclaré.
  return { buffer, mimeType: declaredMimeType, filename, converted: false };
}

/**
 * HEIC → JPEG, ou `null` si le décodage échoue.
 *
 * `heic-decode` (libheif en WebAssembly) et non `sharp` : les binaires
 * précompilés de `sharp` lisent l'AVIF mais **pas** le HEIC d'un iPhone, faute
 * du décodeur HEVC (`libde265`) — vérifié le 11/11/2026, sharp 0.35. Et non
 * `jimp`, qui ne connaît pas du tout le conteneur. Les deux imports sont
 * paresseux : la plupart des requêtes n'ont pas de photo à convertir, et le
 * WASM pèse.
 */
async function heicToJpeg(buffer: Buffer): Promise<Buffer | null> {
  try {
    const { default: decode } = await import("heic-decode");
    const { Jimp } = await import("jimp");

    // libheif applique lui-même les transformations du conteneur (`irot`,
    // `imir`) : le bitmap arrive dans le sens où la photo se regarde, et il
    // n'y a rien à tourner par-dessus.
    const { width, height, data } = await decode({ buffer: new Uint8Array(buffer) });

    // `Jimp.fromBitmap` est typé `any` dans jimp 1.6 : on dit ici ce qu'on en
    // attend plutôt que de laisser l'`any` se propager.
    const image = Jimp.fromBitmap({ width, height, data: Buffer.from(data) }) as unknown as {
      getBuffer(mime: "image/jpeg", options: { quality: number }): Promise<Buffer>;
    };
    return Buffer.from(await image.getBuffer("image/jpeg", { quality: JPEG_QUALITY }));
  } catch {
    return null;
  }
}
