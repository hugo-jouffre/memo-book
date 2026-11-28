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
  /**
   * ⚠️ `upscale` pour une photo trop petite. **Pas** « floue » : ce verdict
   * découle de ``sharpness`` ci-dessus, qui mesure le contraste (T310,
   * 28/11/2026).
   */
  verdict?: string | null;
  /**
   * **Le flou, mesuré pour de vrai** (T310, `services/photoAnalysis.blurOf`) :
   * de 0 (nette) à 1 (bouillie). `null` ou absent : pas de jugement — une
   * photo d'avant le 28/11/2026, ou une image sans aucun bord.
   *
   * C'est **lui** qui départage deux photos sur leur netteté, et non
   * ``sharpness``. Classer n'a pas besoin de seuil : entre deux photos du même
   * souvenir, la moins floue passe devant, quels que soient les chiffres.
   */
  blur?: number | null;
  /**
   * Ce que la photo vaut à regarder, de 0 à 100 (`services/photoBeauty.ts`,
   * T265). `null` ou absent : pas encore notée.
   */
  beauty?: number | null;
  /**
   * À quel point elle illustre **le texte de sa page**, de 0 à 100
   * (`services/photoRelevance.ts`, T265). Absente sur une étape qui ne
   * déborde pas : il n'y avait aucun choix à faire, donc rien à juger.
   */
  relevance?: number | null;
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

/**
 * Le flou d'une photo qu'on n'a pas mesurée : **le milieu**.
 *
 * Même doctrine que ``BEAUTE_INCONNUE``. Les photos nettes mesurées tombent
 * entre 0,24 et 0,34, les floues au-delà de 0,6 : 0,5 range donc une photo non
 * mesurée derrière les nettes et devant les floues, sans la condamner.
 */
const FLOU_INCONNU = 0.5;

function note(valeur: number | null | undefined): number | null {
  return typeof valeur === "number" && Number.isFinite(valeur) ? valeur : null;
}

/**
 * **Ce que vaut une photo pour cette page-ci** : la moyenne de ce qu'on sait
 * d'elle.
 *
 * Deux notes, et on ne les hiérarchise pas. Une belle photo qui ne raconte
 * pas la page n'a pas sa place ; une photo juste mais ratée non plus. Les
 * classer l'une avant l'autre reviendrait à décréter laquelle des deux fautes
 * est la pire, et rien ne le dit — la moyenne laisse chacune peser autant.
 *
 * Quand une seule est connue, elle décide seule : c'est le cas courant, la
 * pertinence n'étant calculée que sur les étapes qui débordent
 * (`services/photoRelevancePass.ts`). Aucune des deux : le milieu, comme pour
 * une netteté absente — on ne privilégie ni ne condamne une photo pour une
 * note qui manque.
 */
function flou(photo: PhotoQuality): number {
  return note(photo.blur) ?? FLOU_INCONNU;
}

function beaute(photo: PhotoQuality): number {
  const connues = [note(photo.beauty), note(photo.relevance)].filter(
    (valeur): valeur is number => valeur !== null,
  );
  if (connues.length === 0) return BEAUTE_INCONNUE;
  return connues.reduce((somme, valeur) => somme + valeur, 0) / connues.length;
}

/**
 * Le rang d'une photo : plus bas, plus elle mérite sa place.
 *
 * Une photo **non mesurée** (un HEIC d'avant la conversion à l'arrivée, une
 * photo d'avant le 18/11/2026) passe derrière celles qu'on a mesurées : on ne
 * la privilégie pas, mais rien d'autre ne permet de la situer.
 *
 * 🔴 **Le verdict `reject` ne rétrograde plus rien** (T310, 28/11/2026). Il
 * le faisait, et il rétrogradait les mauvaises photos : mesuré, il ne découle
 * pas du flou mais du **contraste** (``photoAnalysis``, tableau du 28/11).
 * Une photo illisible de flou le passait haut la main, et un ciel uni
 * parfaitement net sortait `reject` — donc **entre deux photos du même
 * souvenir, la floue passait devant le ciel**. C'était un bug vivant depuis
 * le 18/11.
 *
 * Une rétrogradation franche « trop floue pour être imprimée » reviendra ici
 * quand ``blur`` aura un seuil calibré sur un vrai lot de photos. D'ici là le
 * flou **classe** sans condamner, plus bas dans le tri : c'est tout ce dont
 * une sélection a besoin.
 */
function rang(photo: PhotoQuality): number {
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
      // **La netteté, et c'est `blur` qui la dit** (T310) : la moins floue
      // devant. Sous la beauté, comme la netteté l'était — une photo nette
      // d'un mur ne vaut toujours pas une photo un peu molle d'un visage.
      const parFlou = flou(a.qualite) - flou(b.qualite);
      if (parFlou !== 0) return parFlou;
      // Le contraste en dernier recours. Il ne dit pas la netteté, mais entre
      // deux photos du même endroit il vaut encore mieux que l'ordre d'arrivée.
      const nettete = (b.qualite.sharpness ?? 0) - (a.qualite.sharpness ?? 0);
      if (nettete !== 0) return nettete;
      return a.index - b.index;
    });

  const parOrdre = (liste: typeof classees) =>
    [...liste].sort((a, b) => a.index - b.index).map((item) => item.photo);

  return [...parOrdre(classees.slice(0, combien)), ...parOrdre(classees.slice(combien))];
}
