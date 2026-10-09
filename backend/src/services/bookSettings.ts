/**
 * Les réglages de personnalisation du carnet, appliqués au PDF de l'app.
 *
 * L'atelier (`MemoBook Generator/public/app.js`, `reglagesDuCarnet`) applique
 * les mêmes, au même endroit du payload : un réglage qui ne changerait que
 * l'un des deux PDF ferait croire au voyageur qu'il a réglé quelque chose
 * (`docs/reglages-utilisateur.md`, « Règle de survie »).
 *
 * | Réglage | Effet |
 * |---|---|
 * | Fun facts coupé | aucun encart (`structure.ts`, avant la composition) |
 * | Ratio photo / texte à 0 % | aucune photo dans le carnet — la couverture garde la sienne |
 * | Pointillés coupés | `rules_enabled: false` : pas de réglure sous le récit |
 * | Décorations à 0 | `decoration_quota: 0` : ni tracé pointillé, ni scotch, ni sticker |
 *
 * Les paliers 25, 50 et 75 % du ratio ne sont pas encore définis : ils
 * composent comme 50 %.
 */
import type { BookPayload } from "./structuring.js";

export interface BookSettings {
  photoTextRatio: number;
  rulesEnabled: boolean;
  decorationQuota: number;
}

/** Le carnet garde-t-il ses photos ? Non à 0 % : « aucune photo dans tout le carnet ». */
export function keepsPhotos(settings: Pick<BookSettings, "photoTextRatio">): boolean {
  return settings.photoTextRatio > 0;
}

const PHOTO_LAYOUTS = [
  "layout_hero_top",
  "layout_split_left",
  "layout_collage",
  "layout_trio_portrait",
  "layout_trio_landscape",
];

/**
 * Le payload, réglé. Les photos sont normalement écartées **avant** la
 * composition (`structure.ts`) ; ce qui en resterait — une page de photos, une
 * photo posée par le modèle — part ici, et la page retombe sur le layout de
 * récit sans photo : un drapeau de photos sur une page qui n'en a plus
 * laisserait un trou à leur place.
 */
export function applyBookSettings(payload: BookPayload, settings: BookSettings): BookPayload {
  const regle: BookPayload = {
    ...payload,
    rules_enabled: settings.rulesEnabled,
    decoration_quota: Math.max(0, Math.min(4, Math.round(settings.decorationQuota))),
  };
  if (keepsPhotos(settings)) return regle;

  const days = Array.isArray(payload["days"]) ? (payload["days"] as Record<string, unknown>[]) : [];
  regle["days"] = days
    .filter((day) => day["layout_photo_page"] !== true)
    .map((day) => {
      const sansPhotos: Record<string, unknown> = { ...day, photos: [] };
      if (PHOTO_LAYOUTS.some((flag) => day[flag] === true)) {
        for (const flag of PHOTO_LAYOUTS) delete sansPhotos[flag];
        sansPhotos["layout_story_facts"] = true;
      }
      return sansPhotos;
    });
  return regle;
}
