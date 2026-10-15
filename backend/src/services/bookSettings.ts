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
 * | Quiz coupé | aucun quiz (`structure.ts`, et le composeur n'en place aucun) |
 * | Ratio photo / texte | les cinq paliers, voir plus bas |
 * | Pointillés coupés | `rules_enabled: false` : pas de réglure sous le récit |
 * | Décorations à 0 | `decoration_quota: 0` : ni tracé pointillé, ni sticker (le scotch reste) |
 * | Zones libres | `pages_libres: 3` : trois pages réglées après la dernière étape ; 0 si coupé |
 *
 * ## Le ratio photo / texte, et la composition
 *
 * `applyBookSettings` **recompose chaque étape** avec le composeur de
 * l'atelier (`bookComposer.ts`) : le module de ratio (`photoRatio.ts`) dit
 * combien de photos l'étape garde à ce palier — le nombre exact que le chat a
 * demandé au voyageur —, le composeur met en page (Hugo, 13/10/2026). Les deux
 * PDF sortent ainsi du même code.
 *
 * **Le texte ne bouge jamais.** La recomposition peut déplacer un paragraphe
 * d'une page à la suivante, ou le couper sur une fin de phrase, mais aucun mot
 * n'est ajouté, retiré ni changé (`test/bookSettings.test.ts`).
 */
import { composerCarnet } from "./bookComposer.js";
import { getPhotoRatio } from "./photoRatio.js";
import type { BookPayload } from "./structuring.js";

export interface BookSettings {
  photoTextRatio: number;
  rulesEnabled: boolean;
  decorationQuota: number;
  freeZonesEnabled: boolean;
  /** Les fun facts du voyageur. Absent : allumés, comme le défaut du carnet. */
  funFactsEnabled?: boolean;
  /** « Quiz intégrés à l'histoire ». Absent : allumés, comme le défaut du carnet. */
  quizEnabled?: boolean;
}

/** Les pages libres, réglées, de fin de carnet quand « Zones libres » est allumé. */
export const FREE_PAGES_AT_END = 3;

/** Le carnet garde-t-il ses photos ? Non à 0 % : « aucune photo dans tout le carnet ». */
export function keepsPhotos(settings: Pick<BookSettings, "photoTextRatio">): boolean {
  return settings.photoTextRatio > 0;
}

/**
 * Le payload, réglé.
 *
 * Les photos sont normalement écartées **avant** la composition
 * (`structure.ts`) à 0 % ; ce qui en resterait part ici, puisque
 * `appliquerRatio` ne distribue aucune photo à ce palier.
 */
export function applyBookSettings(payload: BookPayload, settings: BookSettings): BookPayload {
  const ratio = getPhotoRatio(null, { photo_ratio: settings.photoTextRatio });
  const regle: BookPayload = {
    ...payload,
    rules_enabled: settings.rulesEnabled,
    decoration_quota: Math.max(0, Math.min(4, Math.round(settings.decorationQuota))),
    pages_libres: settings.freeZonesEnabled ? FREE_PAGES_AT_END : 0,
    photo_ratio: ratio,
  };

  const days = Array.isArray(payload["days"]) ? (payload["days"] as Record<string, unknown>[]) : [];
  if (days.length === 0) return regle;

  // La composition vit dans le composeur de l'atelier (`mise-en-page.js`) et
  // non ici : deux implémentations, c'étaient deux carnets différents pour un
  // même réglage.
  regle["days"] = composerCarnet(regle, {
    ratio,
    funFacts: settings.funFactsEnabled !== false,
    // Coupé, le composeur ne place aucun quiz — même un quiz resté dans le
    // payload de la structuration n'atteint pas le PDF.
    quiz: settings.quizEnabled !== false,
    decorations: Math.max(0, Math.min(4, Math.round(settings.decorationQuota))),
  });
  return regle;
}
