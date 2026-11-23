import OpenAI from "openai";
import type { Env } from "../env.js";

/**
 * **Ce que vaut une photo à regarder** (T265, Hugo — « quand il y en a trop,
 * une sélection sur l'esthétique, la netteté et la pertinence »).
 *
 * La netteté se mesure dans les pixels, gratuitement
 * (`services/photoOrientation.ts`). La beauté demande un œil : cadrage,
 * lumière, sujet, ce qu'on a envie de voir imprimé en pleine page. C'est un
 * appel de vision, et il se paie.
 *
 * ## Une note par photo, une seule fois dans sa vie
 *
 * C'est tout le dessin de ce fichier, et c'est ce qui le rend abordable. La
 * note ne dépend que de **la photo** — ni du texte qu'elle accompagne, ni de
 * l'étape où elle tombe, ni du carnet. Elle s'écrit donc en base
 * (`entries.photoBeauty`) et ne se redemande jamais : un carnet qui se
 * recompose trente fois ne la paie qu'au premier passage.
 *
 * Chiffré le 23/11/2026 (`docs/modeles-ia.md` § 2) : **1,6 ¢ pour un carnet de
 * 109 photos**, une fois. La même note recalculée à chaque composition aurait
 * coûté jusqu'à 1,59 $ — plus de la moitié du coût modèle d'un carnet.
 *
 * ## Le modèle, et pourquoi pas celui des stickers
 *
 * Une image en `detail: "low"` coûte **les jetons de base du modèle, quelle
 * que soit sa taille** : 2 833 pour `gpt-4o-mini`, 85 pour `gpt-4o`, ~308 pour
 * `gpt-5.6-luna`. Réduire la photo n'y change rien — c'est le transport qu'on
 * allège, pas la facture. `OPENAI_PHOTO_BEAUTY_MODEL` est donc réglé sur un
 * modèle de vision récent, et surtout pas sur le `gpt-4o-mini` des stickers,
 * qui est le plus cher par image de toute la liste.
 *
 * ## Ce qu'il ne fait pas
 *
 * Il ne dit pas si une photo **va avec le texte** : ça dépend du couple, donc
 * ça se refait à chaque composition, donc ça ne se range pas ici. C'est le
 * second tiers de T265, et il se décide à part.
 */

/** Ce qu'on sait d'une photo au moment de la montrer au modèle. */
export interface BeautyCandidate {
  /** L'identifiant du souvenir, que le modèle nous rend pour s'y retrouver. */
  id: string;
  /** La photo, réduite — voir ``BEAUTY_SIDE``. */
  jpeg: Buffer;
}

/** La note rendue pour une photo, de 0 à 100. */
export interface BeautyScore {
  id: string;
  score: number;
}

/**
 * Le côté auquel on réduit avant d'envoyer. 512 px, comme les stickers.
 *
 * ⚠️ **Ce n'est pas pour le prix** : en `detail: "low"`, une image coûte le
 * même nombre de jetons quelle que soit sa taille. C'est pour le transport —
 * une photo d'iPhone pèse 3 à 6 Mo, et l'encoder en base64 pour l'envoyer
 * entière ferait payer des secondes, pas des centimes.
 */
export const BEAUTY_SIDE = 512;

/** Par lot, comme les stickers : la consigne s'amortit sur dix photos. */
export const BEAUTY_BATCH = 10;

const SYSTEM = [
  "Tu notes des photos de voyage pour un carnet imprimé.",
  "Pour chaque photo, donne une note de 0 à 100 : ce qu'on a envie de voir",
  "sur une page, en grand. Regarde le cadrage, la lumière, la netteté du",
  "sujet, et ce que la photo raconte.",
  "",
  "Note bas : une photo ratée, un mur, un sol, un doigt sur l'objectif, une",
  "capture d'écran, un document illisible.",
  "Note haut : un paysage qui tient debout, un visage vivant, une scène qu'on",
  "reconnaîtrait un an plus tard.",
  "",
  "Tu ne juges pas le goût des gens ni les personnes photographiées : tu dis",
  "si l'image est belle à imprimer.",
  "Rends un JSON : {\"photos\":[{\"photo_id\":\"…\",\"score\":0}]} — une entrée par",
  "photo reçue, et rien d'autre.",
].join("\n");

/** L'œil. */
export interface BeautyJudge {
  score(photos: readonly BeautyCandidate[]): Promise<BeautyScore[]>;
}

/**
 * Sans modèle, aucune note — et le carnet choisit sur la netteté, comme avant
 * le 23/11/2026. C'est le repli de `BlindStickerSpotter`, pour la même raison :
 * une composition ne doit jamais échouer parce qu'un juge esthétique manque.
 */
export class BlindBeautyJudge implements BeautyJudge {
  async score(): Promise<BeautyScore[]> {
    return [];
  }
}

export class LlmBeautyJudge implements BeautyJudge {
  constructor(
    private readonly client: OpenAI,
    private readonly model: string,
  ) {}

  async score(photos: readonly BeautyCandidate[]): Promise<BeautyScore[]> {
    if (photos.length === 0) return [];

    const content: OpenAI.Chat.ChatCompletionContentPart[] = [];
    for (const photo of photos) {
      content.push({ type: "text", text: `photo_id: ${photo.id}` });
      content.push({
        type: "image_url",
        image_url: { url: `data:image/jpeg;base64,${photo.jpeg.toString("base64")}`, detail: "low" },
      });
    }

    const reponse = await this.client.chat.completions.create({
      model: this.model,
      // ⚠️ **`max_completion_tokens`, et pas `max_tokens`** (24/11/2026). Les
      // modèles récents refusent le second d'un `400 Unsupported parameter`,
      // et `services/stickerVision.ts` l'emploie encore parce que
      // `gpt-4o-mini` l'accepte : le motif recopié de là était juste pour son
      // modèle et faux pour celui-ci. Trouvé en production, sur la première
      // composition réelle — le repli a tenu, le carnet est sorti classé sur
      // la netteté, et le journal a nommé la cause.
      max_completion_tokens: 60 * photos.length + 100,
      response_format: { type: "json_object" },
      messages: [
        { role: "system", content: SYSTEM },
        { role: "user", content },
      ],
    });

    return readScores(reponse.choices[0]?.message?.content, new Set(photos.map((photo) => photo.id)));
  }
}

/**
 * Relit ce que le modèle rend, défensivement.
 *
 * Une note hors bornes, un identifiant inventé, un JSON tordu : on écarte
 * l'entrée et on garde les autres. Une photo sans note se rangera sur sa
 * netteté — c'est exactement ce qui se passait avant ce fichier.
 */
export function readScores(raw: string | null | undefined, known: ReadonlySet<string>): BeautyScore[] {
  if (!raw) return [];
  let parsed: unknown;
  try {
    parsed = JSON.parse(raw);
  } catch {
    return [];
  }

  const photos = (parsed as { photos?: unknown } | null)?.photos;
  if (!Array.isArray(photos)) return [];

  const vus = new Set<string>();
  const scores: BeautyScore[] = [];
  for (const item of photos) {
    const id = (item as Record<string, unknown> | null)?.["photo_id"];
    const score = (item as Record<string, unknown> | null)?.["score"];
    if (typeof id !== "string" || !known.has(id) || vus.has(id)) continue;
    if (typeof score !== "number" || !Number.isFinite(score)) continue;
    vus.add(id);
    scores.push({ id, score: Math.round(Math.min(Math.max(score, 0), 100)) });
  }
  return scores;
}

/** Claude ne note pas les photos : c'est un œil, et il est chez OpenAI. */
export function createBeautyJudge(env: Env): BeautyJudge {
  if (env.PIPELINE_MODE === "fake" || env.OPENAI_API_KEY === "") return new BlindBeautyJudge();
  return new LlmBeautyJudge(new OpenAI({ apiKey: env.OPENAI_API_KEY }), env.OPENAI_PHOTO_BEAUTY_MODEL);
}
