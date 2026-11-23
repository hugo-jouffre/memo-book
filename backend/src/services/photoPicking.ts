/**
 * **Quelles photos le carnet montre, quand une étape en porte plus que sa mise
 * en page n'en dessine** (T265, Hugo — « quand il y en a trop, une sélection
 * sur l'esthétique, la netteté et la pertinence »).
 *
 * ## Ce que ça remplace
 *
 * Un `slice`. Chaque gabarit dessine un nombre fixe de photos — une pour un
 * héros, trois pour un collage, cinq pour une planche — et les suivantes
 * n'étaient tout simplement pas peintes. Le tri était celui de l'arrivée :
 * **les premières envoyées gagnaient**, la nette comme la floue, celle du sol
 * comme celle du marché. Personne ne le voyait, puisque le carnet ne montre
 * pas ce qu'il écarte.
 *
 * ## Ce que ça ne fait pas
 *
 * Ni esthétique, ni pertinence par rapport au texte : les deux demandent un
 * appel de vision, donc un coût à chaque composition, et c'est une décision à
 * prendre à part. Ici on ne se sert que de ce qu'on mesure déjà gratuitement
 * à l'arrivée d'une photo (`services/photoOrientation.ts`) : sa **netteté** et
 * son **verdict**.
 *
 * C'est donc un tiers de la demande, et le tiers qui ne coûte rien.
 *
 * ## Deux ordres, et il faut les deux
 *
 * On **choisit** par la qualité, on **montre** dans l'ordre du récit. Classer
 * les photos affichées par netteté décroissante casserait la suite des images
 * — un coucher de soleil arriverait avant le départ du matin. Les retenues
 * reprennent donc leur ordre d'origine une fois choisies, et les écartées
 * restent derrière elles, dans le leur : une étape dont la mise en page
 * changerait de gabarit retrouve des photos cohérentes.
 */

/** Ce qu'on sait d'une photo au moment de choisir. */
export interface PhotoQuality {
  /** La variance de détail mesurée à l'arrivée. Plus haut, plus net. */
  sharpness?: number | null;
  /** `reject` pour une photo jugée floue, `upscale` pour une trop petite. */
  verdict?: string | null;
  /**
   * Ce que la photo vaut à regarder, de 0 à 100 (`services/photoBeauty.ts`,
   * T265). `null` ou absent : pas encore notée.
   */
  beauty?: number | null;
}

/**
 * La note d'une photo qu'on n'a pas notée : **le milieu**.
 *
 * Même doctrine que ``rang`` pour une netteté absente — on ne la privilégie
 * pas, on ne la condamne pas. Mettre 0 ferait passer derrière toutes les
 * autres une photo dont le seul tort est d'être arrivée avant le juge ; mettre
 * 100 lui offrirait la page.
 */
const BEAUTE_INCONNUE = 50;

function beaute(photo: PhotoQuality): number {
  return typeof photo.beauty === "number" && Number.isFinite(photo.beauty)
    ? photo.beauty
    : BEAUTE_INCONNUE;
}

/**
 * Le rang d'une photo : plus bas, plus elle mérite sa place.
 *
 * Le verdict d'abord, la netteté ensuite. Une photo **refusée** passe après
 * toutes les autres, même très nette — c'est le seul jugement franc que la
 * mesure porte. Une photo **non mesurée** (un HEIC d'avant la conversion à
 * l'arrivée, une photo d'avant le 18/11/2026) se range entre les deux : on ne
 * la privilégie pas, mais on ne la condamne pas non plus pour une mesure qui
 * manque.
 */
function rang(photo: PhotoQuality): number {
  if (photo.verdict === "reject") return 2;
  if (typeof photo.sharpness !== "number" || !Number.isFinite(photo.sharpness)) return 1;
  return 0;
}

/**
 * Réordonne des photos pour que **les `combien` meilleures viennent en tête**,
 * chacune des deux moitiés gardant son ordre d'origine.
 *
 * `combien` vient du gabarit choisi : c'est le nombre que la page dessine. Au
 * delà, les photos restent dans le payload — une page de photos ajoutée à la
 * fin d'une étape impaire ira y puiser (`completerEtapesImpaires`).
 *
 * Rien à choisir, rien à faire : moins de photos que la page n'en dessine, et
 * la liste revient telle quelle.
 */
export function photosLesPlusNettes<T>(
  photos: readonly T[],
  combien: number,
  qualiteDe: (photo: T) => PhotoQuality,
): T[] {
  if (combien <= 0 || photos.length <= combien) return [...photos];

  // Index gardé pour deux raisons : départager deux photos de même rang et de
  // même netteté sans que le tri devienne instable, et rendre son ordre à
  // chaque moitié ensuite.
  const classees = photos
    .map((photo, index) => ({ photo, index, qualite: qualiteDe(photo) }))
    .sort((a, b) => {
      const parRang = rang(a.qualite) - rang(b.qualite);
      if (parRang !== 0) return parRang;
      // **La beauté avant la netteté** (T265, 23/11/2026) : une photo nette
      // d'un mur ne vaut pas une photo un peu molle d'un visage. Le verdict
      // reste au-dessus des deux — une photo trop floue pour l'impression ne
      // se rattrape pas en étant jolie.
      const parBeaute = beaute(b.qualite) - beaute(a.qualite);
      if (parBeaute !== 0) return parBeaute;
      const nettete = (b.qualite.sharpness ?? 0) - (a.qualite.sharpness ?? 0);
      if (nettete !== 0) return nettete;
      return a.index - b.index;
    });

  const parOrdre = (liste: typeof classees) =>
    [...liste].sort((a, b) => a.index - b.index).map((item) => item.photo);

  return [...parOrdre(classees.slice(0, combien)), ...parOrdre(classees.slice(combien))];
}
