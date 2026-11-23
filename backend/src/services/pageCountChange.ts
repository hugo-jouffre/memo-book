import { formatEuros } from "./notificationCopy.js";
import { getPrintPrice } from "./printPricing.js";

/**
 * **Quand le carnet change de taille, et que ça change son prix** (T265,
 * dernier reste — « un avertissement si le nombre de pages change »).
 *
 * ## Pourquoi pas à chaque changement de pages
 *
 * L'aperçu se recompose à **chaque** changement du carnet : un souvenir de
 * plus, une photo, un réglage. Un carnet de la production en est à trente et
 * une compositions. Une bulle par changement de pagination noierait le fil, et
 * une bulle qu'on apprend à ignorer ne prévient plus de rien — c'est la leçon
 * de la bulle des doutes, retirée le 16/11/2026 parce qu'elle « sonnait comme
 * un refus » à chaque souvenir.
 *
 * Or le nombre de pages, le voyageur le **voit déjà** : l'accueil l'affiche
 * (« 2/80 pages »), l'aperçu le montre page après page. Ce qu'il ne voit pas
 * venir, c'est le **prix** : il est par palier (`printPricing.ts`), et passer
 * de 85 à 86 pages coûte cinq euros de plus sans que rien ne le laisse
 * deviner.
 *
 * **On avertit donc quand le prix change, et on dit les pages comme cause.**
 * Un carnet qui grossit sans changer de palier ne dit rien : il n'y a rien à
 * décider.
 *
 * ## Ce qui se facture
 *
 * `billablePages` facture **ce qui est composé** dès qu'il y a quelque chose,
 * et retombe sur la cible seulement tant que rien ne l'est : un carnet de
 * 40 pages visant 90 se paie 40, pas 90. Le calcul ci-dessous reprend cette
 * règle au mot près — l'inverse annoncerait des hausses qui n'arrivent pas, et
 * tairait celles qui arrivent.
 */
export interface PageCountChange {
  /** Les pages facturées avant, et après. */
  avant: number;
  apres: number;
  /** Le prix du carnet, en centimes, avant et après. */
  prixAvant: number;
  prixApres: number;
}

/** Les pages qui comptent pour le prix — la même règle que `billablePages`. */
function facturees(composees: number, cible: number): number {
  return Math.max(composees > 0 ? composees : cible, 1);
}

/**
 * Le changement à annoncer, ou `null` quand il n'y a rien à dire.
 *
 * `null` dans quatre cas, et chacun compte : aucune pagination connue avant
 * (le premier carnet n'annonce pas une hausse), le même nombre de pages, un
 * nombre différent **au même prix**, et un carnet dont le prix ne se calcule
 * pas — au-delà du maximum relié, `getPrintPrice` refuse, et un avertissement
 * n'est pas l'endroit où l'apprendre.
 */
export function changementDePages(
  avantComposees: number | null,
  apresComposees: number | null,
  cible: number,
): PageCountChange | null {
  if (avantComposees === null || apresComposees === null) return null;
  if (avantComposees <= 0) return null;

  const avant = facturees(avantComposees, cible);
  const apres = facturees(apresComposees, cible);
  if (avant === apres) return null;

  try {
    const prixAvant = getPrintPrice(avant).priceCents;
    const prixApres = getPrintPrice(apres).priceCents;
    if (prixAvant === prixApres) return null;
    return { avant, apres, prixAvant, prixApres };
  } catch {
    return null;
  }
}

/**
 * Ce que MEMO en dit. Deux phrases : ce qui a changé, et ce que ça coûte.
 *
 * Le ton est celui d'un constat, pas d'un reproche — le carnet a grossi parce
 * que le voyage a été raconté, et c'est une bonne nouvelle. On ne propose donc
 * rien à faire : le réglage des pages cible est dans la personnalisation, et
 * qui veut y aller sait où il est.
 */
export function pageCountChangeText(change: PageCountChange): string {
  const sens = change.apres > change.avant ? "fait maintenant" : "ne fait plus que";
  return (
    `Ton carnet ${sens} ${change.apres} pages, contre ${change.avant}. ` +
    `Son prix passe donc de ${formatEuros(change.prixAvant)} à ${formatEuros(change.prixApres)}.`
  );
}
