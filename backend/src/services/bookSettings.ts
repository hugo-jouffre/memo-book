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
 * | Ratio photo / texte | les cinq paliers, voir plus bas |
 * | Pointillés coupés | `rules_enabled: false` : pas de réglure sous le récit |
 * | Décorations à 0 | `decoration_quota: 0` : ni tracé pointillé, ni sticker (le scotch reste) |
 * | Zones libres | `pages_libres: 3` : trois pages réglées après la dernière étape ; 0 si coupé |
 *
 * ## Le ratio photo / texte
 *
 * `applyBookSettings` **recompose chaque étape** selon le plan que
 * `photoRatio.ts` calcule : le nombre de pages, le layout de chacune, la part
 * de photos et la hauteur de leur bande. L'Agent Mise en page propose, le
 * module de ratio tranche — c'est le seul moyen que le PDF porte exactement le
 * nombre de photos que le chat a demandé au voyageur.
 *
 * **Le texte ne bouge jamais.** La recomposition peut déplacer un paragraphe
 * d'une page à la suivante, mais le `body_html` de l'étape, bout à bout, reste
 * identique octet pour octet — c'est ce que vérifie `test/ratioPhotos.test.ts`
 * sur les quinze cas du barème croisés avec les cinq paliers.
 */
import { appliquerRatio, getPhotoRatio } from "./photoRatio.js";
import type { BookPayload } from "./structuring.js";

export interface BookSettings {
  photoTextRatio: number;
  rulesEnabled: boolean;
  decorationQuota: number;
  freeZonesEnabled: boolean;
  /** Les fun facts du voyageur. Absent : allumés, comme le défaut du carnet. */
  funFactsEnabled?: boolean;
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

  // La recomposition vit dans `photoRatio.ts` et non ici : l'atelier l'appelle
  // aussi, sur son propre `days[]` (`app.js`, `reglagesDuCarnet`). Deux
  // implémentations, c'étaient deux carnets différents pour un même réglage.
  regle["days"] = appliquerRatio(days, ratio, {
    funFacts: settings.funFactsEnabled !== false,
    decorations: Math.round(settings.decorationQuota) > 0,
  });
  return regle;
}
