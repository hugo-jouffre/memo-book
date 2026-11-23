import type { TripTransport } from "@prisma/client";
import { frenchCount } from "../lib/frenchFormat.js";

/**
 * **Le résumé et les catégories d'un carnet de la galerie, déduits de ses
 * faits** (T236).
 *
 * Jusqu'ici, les deux n'étaient écrits que par le seed
 * (`prisma/seed.ts`) : `memos.gallerySummary` par la main, les rattachements à
 * `memo_gallery_categories` en création imbriquée. Un carnet réellement partagé
 * — l'interrupteur « Partager sur la galerie de la communauté » des réglages du
 * voyage — n'avait donc ni phrase sous son titre, ni catégorie. Et comme
 * `GalleryTrip.belongs(to:)` rend `false` sur une liste vide, il ne disparaissait
 * pas seulement des filtres : il **n'apparaissait sous aucune pastille**. La
 * barre ne triait pas mal, elle effaçait le vrai contenu et ne laissait que les
 * neuf démos.
 *
 * **Rien n'est stocké, tout se recalcule à la lecture.** C'est la règle
 * d'`ios/CLAUDE.md` § « Un choix de design ne s'arrête pas au dessin » : quand
 * la donnée se dérive de ce qui existe déjà, la colonne et la migration sautent,
 * et une seconde vérité de moins est à tenir d'accord. Les chiffres viennent de
 * `services/tripFacts.ts`, qui les réécrit à chaque souvenir traité.
 *
 * **La colonne garde le dernier mot** : `gallerySummary` renseigné passe devant
 * ce qui est déduit ici, et les rattachements en base s'ajoutent aux slugs
 * déduits. Le jour où un agent écrit la phrase, ou où le voyageur choisit ses
 * catégories en partageant, ce fichier s'efface tout seul derrière eux.
 *
 * ⚠️ **On déduit un fait, jamais une étiquette.** Une durée, un nombre de pays,
 * des kilomètres : le carnet les connaît. « Plage & îles » ou « Montagne », non —
 * rien dans le carnet ne les prouve, et les deviner rangerait une quinzaine
 * balnéaire sous « Randonnée » parce qu'une journée s'est faite à pied. Ces
 * quatre catégories-là (`montagne`, `plage-et-iles`, `city-trip`, `en-famille`)
 * restent donc réservées au seed jusqu'à ce que quelque chose les écrive.
 */

/** Ce qu'il faut savoir d'un carnet pour en déduire sa phrase et ses rangs. */
export interface GalleryFacts {
  /** Le nombre de jours du voyage, tel que `refreshTripFacts` le calcule. */
  dayCount: number | null;
  /** Les kilomètres relevés par la rédaction, cumulés sur les étapes. */
  distanceKilometres: number | null;
  /** Les pays du carnet et de ses étapes, sans doublon — voir `galleryDestinations`. */
  countryCount: number;
  /** Le moyen de transport de chaque étape, tel quel : `null` quand l'étape n'en déclare pas. */
  stepTransports: (TripTransport | null)[];
}

/**
 * Les transports qui disent **quel genre de voyage** c'était, et la catégorie
 * qu'ils désignent.
 *
 * L'avion, le train et le bus n'y sont pas : ils disent comment on est arrivé,
 * pas ce qu'on est allé faire. Un tour du monde et un city trip prennent le même
 * avion.
 */
const CATEGORY_BY_TRANSPORT: Partial<Record<TripTransport, string>> = {
  walk: "randonnee",
  bike: "velo",
  boat: "voile",
  car: "road-trip",
};

/**
 * La durée, dans l'unité qui se lit : « 9 jours », « 3 semaines », « 2 mois ».
 *
 * On change d'unité quand le chiffre devient encombrant, pas à une frontière de
 * calendrier : « 18 jours » se lit encore, « 67 jours » non.
 */
function duration(dayCount: number): string {
  if (dayCount < 21) return frenchCount(dayCount, "jour", "jours");
  if (dayCount < 60) return frenchCount(Math.round(dayCount / 7), "semaine", "semaines");
  return frenchCount(Math.round(dayCount / 30), "mois", "mois");
}

/**
 * La phrase sous le titre d'une carte, déduite des chiffres du voyage.
 *
 * Trois faits au plus, du plus parlant au moins : la durée, les pays dès qu'il y
 * en a plusieurs, les kilomètres quand la rédaction en a relevé. « 12 jours ·
 * 3 pays · 1 400 km ». `null` quand le carnet ne sait encore rien de lui-même —
 * la carte n'affiche alors que son titre, et n'invente pas.
 *
 * Volontairement plus sèche que les phrases du seed (« 12 jours de refuge en
 * refuge ») : celles-là ont été écrites par quelqu'un qui connaissait le voyage.
 * Une déduction n'a pas le droit de ce ton — elle compte, elle ne raconte pas.
 */
export function derivedGallerySummary(facts: GalleryFacts): string | null {
  const parts: string[] = [];

  if (facts.dayCount !== null && facts.dayCount > 0) parts.push(duration(facts.dayCount));
  if (facts.countryCount > 1) parts.push(frenchCount(facts.countryCount, "pays", "pays"));
  if (facts.distanceKilometres !== null && facts.distanceKilometres >= 1) {
    parts.push(`${Math.round(facts.distanceKilometres).toLocaleString("fr-FR")} km`);
  }

  return parts.length > 0 ? parts.join(" · ") : null;
}

/**
 * Les catégories que les faits du voyage **prouvent**, par leur slug.
 *
 * Deux règles, et pas une de plus :
 *
 * 1. **`tour-du-monde`** demande plusieurs pays *et* une longue absence. Les deux
 *    ensemble, parce que ni l'un ni l'autre ne suffit : « La traversée des
 *    Alpes » passe trois pays en douze jours et n'est pas un tour du monde,
 *    tandis que deux mois dans un seul pays n'en est pas un non plus.
 * 2. **Le transport dominant** range le carnet, à condition de dominer vraiment :
 *    il doit être le plus fréquent *et* porter au moins la moitié des étapes qui
 *    déclarent un transport. Sans ce plancher, une seule étape à pied suffirait à
 *    classer en « Randonnée » un voyage qui n'en est pas un.
 *
 * Les étapes sans transport ne comptent ni pour ni contre : une étape que la
 * rédaction n'a pas su lire ne doit pas diluer celles qu'elle a lues.
 */
export function derivedGalleryCategorySlugs(facts: GalleryFacts): string[] {
  const slugs: string[] = [];

  // Trois pays et quarante-cinq jours : le couple qui sépare un vrai tour du
  // monde d'une traversée de massif. Calibré sur les neuf carnets du seed, les
  // seuls exemples qu'on ait de la main de quelqu'un qui savait.
  if (facts.countryCount >= 3 && (facts.dayCount ?? 0) >= 45) slugs.push("tour-du-monde");

  const declared = facts.stepTransports.filter((transport): transport is TripTransport =>
    Boolean(transport),
  );

  if (declared.length > 0) {
    const tally = new Map<TripTransport, number>();
    for (const transport of declared) tally.set(transport, (tally.get(transport) ?? 0) + 1);

    let dominant: TripTransport | null = null;
    let best = 0;
    for (const [transport, count] of tally) {
      if (count > best) {
        dominant = transport;
        best = count;
      }
    }

    const slug = dominant ? CATEGORY_BY_TRANSPORT[dominant] : undefined;
    // `best * 2 >= declared.length` : la moitié, sans passer par une division
    // qui arrondirait une étape sur trois du mauvais côté.
    if (slug && best * 2 >= declared.length && !slugs.includes(slug)) slugs.push(slug);
  }

  return slugs;
}
