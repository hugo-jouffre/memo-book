import sharp from "sharp";
import type { AppContext } from "../context.js";
import { BEAUTY_BATCH, BEAUTY_SIDE, type BeautyCandidate } from "./photoBeauty.js";
import { lisible } from "./photoStickers.js";
import { photosQueLaPageMontre } from "./structuring.js";

type Deps = Pick<AppContext, "storage" | "logger" | "relevanceJudge">;

/** Où trouver les octets d'une photo du payload, par son adresse. */
export interface PhotoSource {
  entryId: string;
  storageKey: string;
}

/**
 * Le texte d'une page, tel qu'on le montre au juge : son titre, son lieu, et
 * son récit débarrassé de ses balises.
 *
 * Borné à quelques milliers de caractères par le juge lui-même — une page de
 * carnet en fait mille au plus, et un payload tordu ne doit pas faire gonfler
 * l'appel.
 */
export function texteDeLaPage(day: Record<string, unknown>): string {
  const intro = (day["day_intro"] ?? {}) as Record<string, unknown>;
  const morceaux = [day["title"], intro["location"], day["city"], day["body_html"]]
    .map((valeur) => (typeof valeur === "string" ? valeur : ""))
    .map((texte) => texte.replace(/<[^>]*>/g, " "))
    .map((texte) => texte.replace(/\s+/g, " ").trim())
    .filter((texte) => texte.length > 0);
  // Les doublons sautent : le lieu est souvent déjà dans le titre, et le
  // répéter n'apprend rien au juge.
  return [...new Set(morceaux)].join("\n");
}

/**
 * **Les étapes qui ont un choix à faire**, et elles seules.
 *
 * Une page qui montre trois photos et n'en porte que trois les montrera
 * toutes : les classer ne changerait rien, et les faire juger serait payer
 * pour rien. C'est le garde-fou qui rend la pertinence abordable.
 */
export function etapesQuiDebordent(days: readonly Record<string, unknown>[]): Record<string, unknown>[] {
  return days.filter((day) => {
    const photos = day["photos"];
    return Array.isArray(photos) && photos.length > photosQueLaPageMontre(day);
  });
}

/**
 * **Note chaque photo des étapes qui débordent, contre le texte de leur
 * page** (T265, 23/11/2026). Rend les notes par adresse de photo.
 *
 * Contrairement à la beauté, rien n'est gardé en base : la note dépend du
 * couple photo-texte, et le texte change. Elle se refait donc à chaque
 * composition — d'où le soin à n'en demander que le strict nécessaire.
 *
 * **Ne lève jamais.** Sans notes, le carnet choisit sur la beauté et la
 * netteté, comme avant ce fichier.
 */
export async function noterLaPertinence(
  deps: Deps,
  days: readonly Record<string, unknown>[],
  sources: ReadonlyMap<string, PhotoSource>,
): Promise<Map<string, number>> {
  const notes = new Map<string, number>();
  const aJuger = etapesQuiDebordent(days);
  if (aJuger.length === 0 || sources.size === 0) return notes;

  try {
    for (const day of aJuger) {
      const texte = texteDeLaPage(day);
      if (!texte) continue;

      const urls = (day["photos"] as unknown[]).filter((url): url is string => typeof url === "string");
      const vues: BeautyCandidate[] = [];
      const parId = new Map<string, string>();
      for (const url of urls) {
        const source = sources.get(url);
        if (!source) continue;
        try {
          const jpeg = await sharp(await lisible(deps, source.storageKey))
            .rotate()
            .resize({ width: BEAUTY_SIDE, height: BEAUTY_SIDE, fit: "inside" })
            .jpeg({ quality: 70 })
            .toBuffer();
          vues.push({ id: source.entryId, jpeg });
          parId.set(source.entryId, url);
        } catch (cause) {
          deps.logger.debug({ err: cause, url }, "Photo illisible pour la pertinence.");
        }
      }

      for (let i = 0; i < vues.length; i += BEAUTY_BATCH) {
        const rendues = await deps.relevanceJudge.score(texte, vues.slice(i, i + BEAUTY_BATCH));
        for (const note of rendues) {
          const url = parId.get(note.id);
          if (url) notes.set(url, note.score);
        }
      }
    }
  } catch (cause) {
    deps.logger.warn({ err: cause }, "Pertinence abandonnée, le carnet garde la beauté et la netteté");
  }

  return notes;
}
