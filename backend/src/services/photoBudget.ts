import {
  RATIO_DEFAUT,
  normaliserRatio,
  photosRequired,
  type PhotoPlan,
  type PhotoRatio,
} from "./photoRatio.js";

/**
 * Combien de photos demander pour illustrer un souvenir validé.
 *
 * ## Ce qui décide du chiffre
 *
 * Deux choses, et une seule était là au départ :
 *
 * 1. **la longueur du texte validé** — c'est lui qui dit combien de pages
 *    l'étape occupe, et le texte ne bouge jamais pour faire entrer une photo ;
 * 2. **le ratio texte / photo réglé par le voyageur** (0, 25, 50, 75, 100 %) —
 *    c'est lui qui dit quelle part de ces pages les photos occupent.
 *
 * Le calcul lui-même est dans `photoRatio.ts`, et c'est **le même que celui de
 * l'atelier** (`MemoBook Generator/public/ratio-photos.js`, généré depuis la
 * même source). Un écart entre le nombre annoncé ici et le nombre posé dans le
 * PDF est un bug : c'est ce que garde `test/ratioPhotosAtelier.test.ts`.
 *
 * Avant le réglage de ratio, ce fichier portait une table de trois lignes
 * (« sous S → 1 photo, S ou M → 3, L ou XL → 6 ») qui prenait toujours le
 * layout le plus riche en photos. C'était, de fait, un ratio figé autour de
 * 50-75 %. La table a disparu : elle est devenue le palier 50 % de `GABARITS`.
 *
 * ## À 0 %, on ne demande rien
 *
 * Le carnet n'a aucune photo : le chat ne doit pas en réclamer. `photos` vaut
 * alors 0, et c'est à l'appelant de ne pas poser la question (`converse.ts`).
 */
export interface PhotoBudget {
  /** Le nombre exact de photos à demander. 0 à un ratio de 0 %. */
  photos: number;
  /** Les pages que le souvenir occupera. */
  pages: number;
  /** Le layout retenu pour chaque page, dans l'ordre. */
  layouts: string[];
  /** Le ratio appliqué, après normalisation sur les cinq paliers. */
  ratio: PhotoRatio;
  /** Le plan complet, pour la composition et l'inspecteur. */
  plan: PhotoPlan;
}

/**
 * Le plus qu'une étape demande. Six était le maximum structurel de l'ancienne
 * table (deux pages de trois photos) ; le plafond vient maintenant du plus
 * visuel des paliers — cinq photos par planche, et une étape peut en compter
 * plusieurs. La borne reste là pour les envois (`routes/chat.ts`), qui ne
 * doivent pas accepter n'importe quelle pile de fichiers.
 */
export const MAX_PHOTOS_PER_STEP = 20;

/** Les réglages du carnet qui entrent dans le calcul. */
export interface PhotoBudgetSettings {
  photoTextRatio?: number | null;
  funFactsEnabled?: boolean | null;
  decorationQuota?: number | null;
}

/**
 * Le texte validé, découpé en paragraphes de `body_html`.
 *
 * Le calcul raisonne en paragraphes : chacun est suivi d'une ligne vide dans le
 * gabarit, et c'est cette ligne qui fait qu'un texte de 560 signes tient en
 * deux paragraphes et déborde en trois. Un texte sans ligne vide compte pour un
 * seul paragraphe, ce qui est exactement ce que la rédaction produit alors.
 */
function enBodyHtml(texte: string): string {
  const paragraphes = texte
    .split(/\n\s*\n|\r\n\s*\r\n/)
    .map((p) => p.trim().replace(/\s+/g, " "))
    .filter((p) => p.length > 0);
  return paragraphes.map((p) => `<p>${p}</p>`).join("");
}

export function photoBudgetFor(texte: string, reglages: PhotoBudgetSettings = {}): PhotoBudget {
  const ratio = normaliserRatio(reglages.photoTextRatio ?? RATIO_DEFAUT);
  const bodyHtml = enBodyHtml(texte);

  // Pas de récit : il n'y a rien à équilibrer, et le minimum du palier n'a pas
  // de sens — c'est un rapport de surfaces, et l'une des deux est vide. Une
  // photo suffit (aucune à 0 %, où le carnet n'en porte pas). Le cas se
  // présente avec « Photos de test » sur un carnet encore vide.
  if (bodyHtml.length === 0) {
    const plan = photosRequired({ body_html: "" }, 0, "a5", {});
    return { photos: ratio === 0 ? 0 : 1, pages: 1, layouts: plan.layouts, ratio, plan };
  }

  const plan = photosRequired({ body_html: bodyHtml }, ratio, "a5", {
    funFacts: reglages.funFactsEnabled !== false,
    decorations: (reglages.decorationQuota ?? 2) > 0,
  });
  return { photos: plan.photos, pages: plan.pages, layouts: plan.layouts, ratio, plan };
}
