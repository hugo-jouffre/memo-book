import OpenAI from "openai";
import type { Env } from "../env.js";
import { acceptableCorners, type StickerCorners } from "./stickerCut.js";

/**
 * **Repérer ce qui se découpe dans une photo** (Hugo, 10/11/2026 — « stickers
 * découpés depuis tes vraies photos de billets et tampons »).
 *
 * Un œil, et des ciseaux : ce fichier est l'œil. Il regarde les photos d'un
 * voyage et dit, pour chacune, s'il y voit un **souvenir plat** et où sont ses
 * quatre coins. Les ciseaux sont dans `stickerCut.ts`, et ne savent rien de
 * tout ça.
 *
 * ### Le modèle choisit, il ne dessine pas
 *
 * C'est toute la différence avec la spec d'origine
 * (`docs/sticker-generation.yaml`), qui faisait **générer** le sticker par un
 * modèle d'images. Un modèle d'images repeint, et un billet en ressort avec de
 * fausses dates. Ici le modèle ne rend que des **coordonnées** : la matière
 * reste la photo du voyageur, au pixel près.
 *
 * ### Ce qu'on cherche, et ce qu'on laisse
 *
 * Un billet de train, un tampon de passeport, une étiquette de bagage, un
 * ticket de musée, une carte postale : plats, nets, cadrés, et porteurs d'une
 * date ou d'un nom de lieu. Ce sont les photos qui font les **pires** pages
 * pleines et les meilleurs stickers — le carnet y gagne deux fois.
 *
 * Un paysage, un visage, une assiette : non. Détourer un visage demande un
 * masque que ces ciseaux-là ne savent pas faire, et un paysage détouré ne veut
 * rien dire.
 */

/** Une photo soumise à l'œil : son souvenir, ses pixels, et ce qu'on en sait. */
export interface StickerCandidatePhoto {
  /** L'identifiant du souvenir photo (`entries.id`). */
  id: string;
  /** La photo, réduite — voir ``STICKER_VISION_SIDE``. */
  jpeg: Buffer;
  /** Le lieu, quand il est connu : « Rome », « Gare de Santa Lucia ». */
  placeLabel?: string | null;
}

/** Ce que l'œil a vu dans une photo. */
export interface StickerSpot {
  photoId: string;
  /** Ce que c'est, en français et en trois mots : « billet de train ». */
  label: string;
  /** De 0 à 100 : à quel point ça fera un bon sticker. */
  score: number;
  corners: StickerCorners;
}

export interface StickerSpotter {
  spot(photos: StickerCandidatePhoto[]): Promise<StickerSpot[]>;
}

/**
 * Le côté auquel on réduit une photo avant de la montrer au modèle. 512 px
 * suffisent à reconnaître un billet et à en placer les coins à 1 % près, et
 * c'est la définition où une image coûte le moins cher. La découpe, elle,
 * travaille sur l'originale : la réduction ne coûte aucune netteté au sticker.
 */
export const STICKER_VISION_SIDE = 512;

/**
 * Le score en dessous duquel on ne découpe pas. 60 : au-dessous, le modèle
 * décrit en général un objet qui *pourrait* faire un sticker — une assiette,
 * une façade — plutôt qu'un souvenir plat.
 */
export const STICKER_MIN_SCORE = 60;

/** Combien de photos on montre en un appel. Au-delà, le modèle en oublie. */
export const STICKER_BATCH = 10;

const SYSTEM = [
  "Tu regardes les photos d'un carnet de voyage et tu repères celles qui portent",
  "un **souvenir plat** : un objet de papier ou de tissu, photographié à plat, qui",
  "ferait un joli sticker collé dans le carnet.",
  "",
  "## Ce qu'on cherche",
  "",
  "Billet de train ou d'avion, ticket de musée ou de métro, tampon de passeport,",
  "étiquette de bagage, carte postale, sous-bock, plan de ville, menu, carte de",
  "visite, timbre. L'objet doit être **entier dans la photo**, net, et occuper une",
  "bonne part du cadre.",
  "",
  "## Ce qu'on ne prend pas",
  "",
  "- Un paysage, un monument, un plat, un animal : ce n'est pas plat, et le",
  "  détourage n'aurait pas de sens.",
  "- **Une personne, un visage, même de loin.** Jamais.",
  "- Une capture d'écran, une photo d'écran de téléphone, un document administratif",
  "  (passeport ouvert, carte d'identité, carte bancaire) : c'est privé, ça n'a rien",
  "  à faire imprimé dans un carnet.",
  "- Un objet flou, coupé par le bord, ou si petit qu'on ne lirait rien dessus.",
  "",
  "## Les quatre coins",
  "",
  "Pour chaque objet retenu, donne ses **quatre coins**, dans le sens des aiguilles",
  "d'une montre en partant du coin en haut à gauche de l'objet — et non du cadre.",
  "Les coordonnées sont des fractions de la photo : `x` de 0 (bord gauche) à 1",
  "(bord droit), `y` de 0 (haut) à 1 (bas).",
  "",
  "Un objet posé de travers a des coins de travers : **suis l'objet**, pas un",
  "rectangle droit autour de lui. Ce qui déborde du quadrilatère sera jeté, et",
  "c'est le but : la table, la main, la nappe ne doivent pas entrer.",
  "",
  "## Ta réponse",
  "",
  "Du JSON, et rien d'autre :",
  "",
  '{"stickers":[{"photo_id":"…","label":"billet de train","score":85,',
  '"corners":[{"x":0.12,"y":0.20},{"x":0.88,"y":0.17},{"x":0.90,"y":0.70},{"x":0.14,"y":0.74}]}]}',
  "",
  "- `label` : ce que c'est, en français, trois mots au plus, sans article.",
  "- `score` : de 0 à 100. Au-dessous de 60, ne la propose pas du tout.",
  "- Une photo sans souvenir plat n'apparaît **pas** dans la liste. La liste vide",
  "  est une bonne réponse, et c'est la plus fréquente.",
].join("\n");

/**
 * Ce qu'on accepte de la réponse du modèle.
 *
 * Trois gardes, et ils comptent : l'identifiant doit être une des photos qu'on
 * a montrées (un modèle en invente), le score doit valoir le découpage, et les
 * coins doivent tenir dans la photo et entourer quelque chose
 * (``acceptableCorners``). Une entrée qui tombe est **écartée seule** : une
 * réponse à moitié bonne vaut mieux que rien.
 */
export function acceptableSpots(raw: unknown, known: Set<string>): StickerSpot[] {
  const liste = (raw as Record<string, unknown> | null)?.["stickers"];
  if (!Array.isArray(liste)) return [];

  const vus = new Set<string>();
  const spots: StickerSpot[] = [];
  for (const brut of liste) {
    const item = brut as Record<string, unknown> | null;
    const photoId = item?.["photo_id"];
    const label = item?.["label"];
    const score = item?.["score"];
    if (typeof photoId !== "string" || !known.has(photoId)) continue;
    // Deux stickers dans la même photo : on garde le premier, le modèle les
    // rend par ordre de pertinence. La base n'en accepterait qu'un de toute
    // façon (`photo_stickers.entryId` est unique).
    if (vus.has(photoId)) continue;
    if (typeof label !== "string" || label.trim().length === 0) continue;
    if (typeof score !== "number" || !Number.isFinite(score) || score < STICKER_MIN_SCORE) continue;
    const corners = acceptableCorners(item?.["corners"]);
    if (!corners) continue;

    vus.add(photoId);
    spots.push({
      photoId,
      label: label.trim().slice(0, 60),
      score: Math.round(Math.min(score, 100)),
      corners,
    });
  }
  return spots;
}

/** Sans modèle, aucun sticker : le carnet garde ceux de la bibliothèque. */
export class BlindStickerSpotter implements StickerSpotter {
  async spot(): Promise<StickerSpot[]> {
    return [];
  }
}

/** L'œil, par un modèle de vision. */
export class LlmStickerSpotter implements StickerSpotter {
  constructor(
    private readonly client: OpenAI,
    private readonly model: string,
  ) {}

  async spot(photos: StickerCandidatePhoto[]): Promise<StickerSpot[]> {
    if (photos.length === 0) return [];

    const content: OpenAI.Chat.ChatCompletionContentPart[] = [];
    for (const photo of photos) {
      content.push({
        type: "text",
        text: `photo_id: ${photo.id}${photo.placeLabel ? ` — ${photo.placeLabel}` : ""}`,
      });
      content.push({
        type: "image_url",
        // `low` : la photo fait déjà 512 px, et le détail fin ne change pas la
        // place des coins. C'est ce qui rend l'appel négligeable.
        image_url: { url: `data:image/jpeg;base64,${photo.jpeg.toString("base64")}`, detail: "low" },
      });
    }

    const completion = await this.client.chat.completions.create({
      model: this.model,
      messages: [
        { role: "system", content: SYSTEM },
        { role: "user", content },
      ],
      response_format: { type: "json_object" },
      // Un repérage n'a pas à être créatif : les mêmes photos doivent donner
      // les mêmes coins d'une composition à l'autre.
      temperature: 0,
      max_tokens: 900,
    });

    const texte = completion.choices[0]?.message?.content;
    if (!texte) return [];
    let candidate: unknown;
    try {
      candidate = JSON.parse(texte);
    } catch {
      return [];
    }
    return acceptableSpots(candidate, new Set(photos.map((photo) => photo.id)));
  }
}

export function createStickerSpotter(env: Env): StickerSpotter {
  if (!env.live) return new BlindStickerSpotter();
  return new LlmStickerSpotter(new OpenAI({ apiKey: env.OPENAI_API_KEY }), env.OPENAI_STICKER_MODEL);
}
