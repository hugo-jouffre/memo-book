import OpenAI from "openai";
import type { Env } from "../env.js";
import { readScores, type BeautyCandidate, type BeautyScore } from "./photoBeauty.js";

/**
 * **Est-ce que cette photo illustre ce texte ?** (T265, le dernier tiers,
 * 23/11/2026.)
 *
 * La beauté se note une fois pour toutes : elle ne dépend que de la photo
 * (`services/photoBeauty.ts`). La pertinence, elle, dépend du **couple** —
 * la même photo de port vaut 90 sous un récit d'embarquement et 20 sous une
 * soirée en ville. Elle ne se garde donc pas en base : elle se recalcule à
 * chaque composition, et c'est ce qui la rend chère.
 *
 * ## D'où le garde-fou, qui est dans la passe et non ici
 *
 * `services/photoRelevancePass.ts` ne fait juger **que les étapes qui
 * débordent** — celles qui portent plus de photos que leur gabarit n'en
 * dessine. Une étape dont tout tient n'a aucun choix à faire : la noter
 * serait payer pour un classement sans effet. Sur un vrai carnet, ça ramène
 * « 109 photos × 31 compositions » à une poignée d'étapes.
 *
 * Le chiffrage est dans `docs/modeles-ia.md` § 2 : sans ce garde-fou, la
 * pertinence coûtait jusqu'à 1,59 $ par carnet, plus de la moitié de son coût
 * modèle.
 */

/** La note rendue pour une photo, de 0 à 100 — la même forme que la beauté. */
export type RelevanceScore = BeautyScore;

const SYSTEM = [
  "On te donne le texte d'une page de carnet de voyage, puis des photos.",
  "Pour chaque photo, dis de 0 à 100 à quel point elle illustre CE texte-là.",
  "",
  "Note haut : on y voit ce que le texte raconte — le lieu, la scène, les gens,",
  "l'objet dont il parle.",
  "Note bas : une photo qui pourrait venir de n'importe quelle page, ou qui",
  "contredit le texte.",
  "",
  "Tu ne juges pas si la photo est belle : seulement si elle va avec le texte.",
  "Rends un JSON : {\"photos\":[{\"photo_id\":\"…\",\"score\":0}]} — une entrée par",
  "photo reçue, et rien d'autre.",
].join("\n");

/** L'œil qui rapproche une photo d'un texte. */
export interface RelevanceJudge {
  score(texte: string, photos: readonly BeautyCandidate[]): Promise<RelevanceScore[]>;
}

/**
 * Sans modèle, aucune pertinence — et le carnet choisit sur la beauté et la
 * netteté. Même repli que `BlindBeautyJudge`, pour la même raison : une
 * composition ne doit jamais échouer sur un avis esthétique.
 */
export class BlindRelevanceJudge implements RelevanceJudge {
  async score(): Promise<RelevanceScore[]> {
    return [];
  }
}

export class LlmRelevanceJudge implements RelevanceJudge {
  constructor(
    private readonly client: OpenAI,
    private readonly model: string,
  ) {}

  async score(texte: string, photos: readonly BeautyCandidate[]): Promise<RelevanceScore[]> {
    if (photos.length === 0 || texte.trim().length === 0) return [];

    const content: OpenAI.Chat.ChatCompletionContentPart[] = [
      { type: "text", text: `Le texte de la page :\n${texte.trim().slice(0, 4_000)}` },
    ];
    for (const photo of photos) {
      content.push({ type: "text", text: `photo_id: ${photo.id}` });
      content.push({
        type: "image_url",
        image_url: { url: `data:image/jpeg;base64,${photo.jpeg.toString("base64")}`, detail: "low" },
      });
    }

    const reponse = await this.client.chat.completions.create({
      model: this.model,
      max_tokens: 60 * photos.length + 100,
      response_format: { type: "json_object" },
      messages: [
        { role: "system", content: SYSTEM },
        { role: "user", content },
      ],
    });

    return readScores(reponse.choices[0]?.message?.content, new Set(photos.map((photo) => photo.id)));
  }
}

/** Le même modèle que la beauté : c'est le même œil, sur une autre question. */
export function createRelevanceJudge(env: Env): RelevanceJudge {
  if (env.PIPELINE_MODE === "fake" || env.OPENAI_API_KEY === "") return new BlindRelevanceJudge();
  return new LlmRelevanceJudge(new OpenAI({ apiKey: env.OPENAI_API_KEY }), env.OPENAI_PHOTO_BEAUTY_MODEL);
}
