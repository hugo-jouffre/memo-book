import { STEP_SIZES } from "./payloadValidator.js";

/**
 * Combien de photos demander pour illustrer un souvenir validé — décidé avec
 * Hugo le 01/10/2026.
 *
 * La règle : on prend **le layout le plus riche en photos qui tient tout le
 * texte validé**, et on demande son maximum. Un chiffre exact, jamais une
 * fourchette — le voyageur sait quoi choisir dans sa pellicule.
 *
 * | Texte validé              | Mise en page                         | Photos |
 * |---------------------------|--------------------------------------|--------|
 * | sous S (< 200 caractères) | 1 page `layout_hero_top`             | 1      |
 * | S ou M (200 → 559)        | 1 page `layout_collage`              | 3      |
 * | L ou XL (560 → 1440)      | 2 pages `layout_collage` (bandeau + suite) | 6 |
 *
 * Les capacités viennent de `LAYOUT_CAPACITY` : `layout_hero_top` tient 380
 * caractères mais une seule photo, `layout_collage` 560 sur la page à bandeau
 * et 880 sur la page de suite, avec 2 à 3 photos par page. Au-delà de M, le
 * texte passe sur deux pages, et chacune porte sa bande de trois photos.
 *
 * ⚠️ La mise en page doit suivre : une étape L ou XL répartit ses six photos
 * sur ses deux pages, trois et trois. Le structureur heuristique pose encore
 * toutes les photos sur la première page (`structuring.ts`) — à reprendre avec
 * le chantier PDF.
 */
export interface PhotoBudget {
  /** Le nombre exact de photos à demander. */
  photos: number;
  /** Les pages que le souvenir occupera. */
  pages: 1 | 2;
  /** Le layout retenu pour chaque page, dans l'ordre. */
  layouts: string[];
}

/** Le plus qu'une étape demande : deux pages de trois photos. L'envoi est borné là. */
export const MAX_PHOTOS_PER_STEP = 6;

export function photoBudgetFor(characters: number): PhotoBudget {
  if (characters < STEP_SIZES.S.min) {
    return { photos: 1, pages: 1, layouts: ["layout_hero_top"] };
  }
  if (characters <= STEP_SIZES.M.max) {
    return { photos: 3, pages: 1, layouts: ["layout_collage"] };
  }
  return { photos: MAX_PHOTOS_PER_STEP, pages: 2, layouts: ["layout_collage", "layout_collage"] };
}
