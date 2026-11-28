import OpenAI from "openai";
import { stringify as stringifyYaml } from "yaml";
import type { Env } from "../env.js";
import { escapeHtml } from "../lib/html.js";
import { photosLesPlusNettes, type PhotoQuality } from "./photoPicking.js";
import { loadLayoutKnowledgeBase, loadPayloadSchema } from "../lib/templates.js";
import {
  ATTRIBUTION_CLASS,
  EDITORIAL_LIMITS,
  bodyLength,
  sansAttributions,
  STEP_SIZES,
  groupSteps,
  pageCapacity,
  pagesAvantEtapes,
  validatePayload,
  type ValidationIssue,
} from "./payloadValidator.js";
import { describeTripContext, introTextFor, introTitleFor, type TripContext } from "./tripContext.js";

/** Une entrée du carnet telle que la voit l'étape de structuration. */
export interface StructuringEntry {
  kind: "audio" | "text" | "photo";
  /**
   * Le texte **définitif** de l'étape : corrigé par l'utilisateur s'il l'a
   * fait, sinon rédigé par l'agent de rédaction. Vide pour une photo seule.
   *
   * Ce n'est plus une transcription brute : la mise en page le reprend au mot
   * près, elle ne le réécrit pas.
   */
  transcript: string | null;
  /** `true` quand l'utilisateur a corrigé le texte à la main dans l'app. */
  editedByUser: boolean;
  /** Titre proposé par la rédaction, à reprendre tel quel. */
  title: string | null;
  /** Encart déjà rédigé et déjà borné à 140 caractères. */
  funFact: string | null;
  funFactTitle: string | null;
  /**
   * Le quiz déjà rédigé, dans la forme du gabarit (`quizForBook`). Absent ou
   * `null` quand l'étape n'en a pas, ou que le réglage Quiz est coupé.
   */
  quiz?: BookQuiz | null;
  /** Icône météo déjà choisie par la rédaction. */
  weatherKey: string | null;
  /**
   * **Quand le souvenir a été enregistré.** Sert de repli pour dater la
   * journée quand l'étape ne dit pas ce qu'elle raconte (``livedDay``).
   */
  capturedAt: Date;
  /**
   * **Le jour que l'étape raconte** (T308), `AAAA-MM-JJ`, quand un de ses
   * récits l'a dit. C'est lui qui regroupe et qui date la journée du carnet.
   *
   * Pris sur l'**étape** et non sur le souvenir, et c'est ce qui compte : une
   * photo ne raconte aucun jour, et prise sur elle-même elle partirait dans
   * une autre journée que le récit qu'elle illustre. Les souvenirs d'une étape
   * restent ensemble, et deux séances qui racontent le même jour se
   * retrouvent sur la même page — « une étape se raconte en plusieurs fois ».
   *
   * Absent, et c'est le cas de tout ce qui précède le 26/11/2026 : la journée
   * se regroupe et se date sur `capturedAt`, comme avant. Le carnet imprimé
   * garde une date dans tous les cas — une page sans date n'a nulle part où
   * mettre son blanc, là où un écran peut simplement se taire.
   */
  livedDay?: string | null;
  /**
   * **Le lieu de l'étape qui porte ce souvenir** (T267, 18/11/2026), et le
   * seul qui nomme une journée depuis T308.
   *
   * Ce n'est pas une déduction : depuis T227, un souvenir est rangé dans une
   * étape, et cette étape a un lieu. L'en-tête d'une journée n'imprimait
   * pourtant que `placeLabel` — absent, elle n'affichait qu'une date.
   *
   * ⚠️ **Et `placeLabel` est parti** (T308) : ce champ-là n'était qu'un écho.
   * L'app renvoie avec le vocal le lieu que le carnet lui avait donné, donc
   * le lieu de l'étape **d'avant** le jour où l'on change de ville — et il
   * passait devant celui de l'étape. Un lieu faux imprimé sur soixante pages
   * est exactement la plainte de T280 ; l'étape, elle, se recalcule.
   *
   * Mesuré sur la production avant d'y toucher : **15 journées de carnet sur
   * 35 (43 %) sans lieu**, dont **7** que l'étape rattrape. Les journées
   * voisines, que le ticket proposait, n'en rattrapaient qu'**une**.
   */
  stepPlace?: string | null;
  /** URL publique de la photo, quand l'entrée en porte une. */
  photoUrl: string | null;
  /**
   * Ce qu'on a mesuré de la photo à son arrivée (T265) : sa netteté, et le
   * verdict qui en découle. Absents d'une photo d'avant le 18/11/2026, ou
   * d'un format que `jimp` n'a pas su décoder — `photosLesPlusNettes` range
   * alors la photo entre les nettes et les refusées, sans la condamner.
   */
  photoSharpness?: number | null;
  photoVerdict?: string | null;
  /**
   * **Le flou mesuré pour de vrai** (T310, 28/11/2026) : de 0 à 1, et c'est
   * lui qui départage deux photos sur leur netteté. Nul pour une photo
   * d'avant cette date, ou sans aucun bord à juger.
   */
  photoBlur?: number | null;
  /**
   * Ce que la photo vaut à regarder, de 0 à 100 — notée une fois par
   * `jobs/judgePhotos.ts` (T265, 23/11/2026). Nulle tant que le job ne l'a
   * pas vue ; la photo se range alors sur sa netteté, comme avant.
   */
  photoBeauty?: number | null;
  /**
   * **Qui raconte ce souvenir** (T317, 28/11/2026) : le prénom du compte qui a
   * envoyé le vocal (`jobs/structure.ts`, même règle et même prénom que
   * ``narratorOf`` et que la bulle du fil). Nul pour un souvenir dont aucune
   * bulle ne dit l'auteur.
   *
   * ⚠️ **Le carnet ne le dit que s'il a plusieurs voix.** Un voyage raconté
   * par une seule personne n'écrit aucun prénom : il n'y a rien à distinguer,
   * et le chemin d'avant T317 est alors suivi **à l'octet près**.
   */
  narrator?: string | null;
}

/** Le quiz tel que le gabarit le lit (`day.quiz`, `index.html`). */
export interface BookQuiz {
  question: string;
  choices: string[];
  answer: string;
}

/**
 * Le quiz d'une entrée, des colonnes de `Entry` à la forme du gabarit. Relu
 * de façon défensive : `quizAnswers` est du JSON libre, et un rang qui ne
 * tombe sur aucune proposition ne fait pas un quiz.
 */
export function quizForBook(entry: {
  quizQuestion: string | null;
  quizAnswers: unknown;
  quizAnswerIndex: number | null;
}): BookQuiz | null {
  const question = entry.quizQuestion?.trim();
  const choices = Array.isArray(entry.quizAnswers)
    ? entry.quizAnswers.filter((choice): choice is string => typeof choice === "string" && choice.trim().length > 0)
    : [];
  const answer = entry.quizAnswerIndex === null ? undefined : choices[entry.quizAnswerIndex];
  if (!question || choices.length < 2 || answer === undefined) return null;
  return { question, choices, answer };
}

export interface StructuringInput {
  title: string;
  subtitle: string | null;
  authors: string | null;
  theme: string | null;
  coverPhotoUrl: string | null;
  entries: StructuringEntry[];
  /** Le contexte du voyage — seule matière de la page d'introduction. */
  tripContext: TripContext | null;
}

export type BookPayload = Record<string, unknown>;

export interface Structurer {
  structure(input: StructuringInput): Promise<BookPayload>;
}

const DATE_FORMATTER = new Intl.DateTimeFormat("fr-FR", {
  day: "numeric",
  month: "long",
  year: "numeric",
  timeZone: "UTC",
});

const SHORT_DATE_FORMATTER = new Intl.DateTimeFormat("fr-FR", {
  weekday: "long",
  day: "numeric",
  month: "long",
  timeZone: "UTC",
});

function dayKey(date: Date): string {
  return date.toISOString().slice(0, 10);
}

/**
 * **Le jour sous lequel ce souvenir se range** : celui que son étape raconte,
 * sinon celui de son enregistrement (T308).
 */
function groupingDay(entry: StructuringEntry): string {
  return entry.livedDay ?? dayKey(entry.capturedAt);
}

/**
 * Regroupe les entrées par journée, dans l'ordre chronologique.
 *
 * **La journée est celle qu'on a vécue**, quand l'étape le dit (T308) : un
 * vocal du dimanche qui raconte vendredi imprimait « dimanche » sur la page,
 * et deux séances sur la même journée en faisaient deux pages. Le repli reste
 * la date d'enregistrement, qui est ce que le carnet a toujours fait.
 *
 * L'ordre suit donc le jour vécu d'abord — sinon une journée rattrapée se
 * serait rangée après celles d'après.
 */
export function groupEntriesByDay(
  entries: StructuringEntry[],
): { key: string; date: Date; entries: StructuringEntry[] }[] {
  const buckets = new Map<string, { key: string; date: Date; entries: StructuringEntry[] }>();

  for (const entry of [...entries].sort((a, b) => {
    const day = groupingDay(a).localeCompare(groupingDay(b));
    return day !== 0 ? day : a.capturedAt.getTime() - b.capturedAt.getTime();
  })) {
    const key = groupingDay(entry);
    const bucket = buckets.get(key);
    if (bucket) {
      bucket.entries.push(entry);
    } else {
      // La date imprimée est celle de la clé : minuit UTC du jour vécu, ou
      // l'instant de l'enregistrement quand on ne sait pas. Les deux
      // formateurs lisent en UTC.
      buckets.set(key, {
        key,
        date: entry.livedDay ? new Date(`${entry.livedDay}T00:00:00Z`) : entry.capturedAt,
        entries: [entry],
      });
    }
  }

  return [...buckets.values()];
}

function formatDateRange(days: { date: Date }[]): string {
  const first = days[0];
  const last = days[days.length - 1];
  if (!first || !last) return "";
  if (days.length === 1) return DATE_FORMATTER.format(first.date);
  return `${DATE_FORMATTER.format(first.date)} – ${DATE_FORMATTER.format(last.date)}`;
}

/** Découpe un texte long en paragraphes qui tiennent dans la page. */
function toBodyHtml(
  text: string,
  maxCharsPerParagraph = EDITORIAL_LIMITS.bodyHtmlCharsPerParagraph,
): string {
  const sentences = text
    .replace(/\s+/g, " ")
    .trim()
    .split(/(?<=[.!?…])\s+/)
    .filter(Boolean);

  const paragraphs: string[] = [];
  let current = "";

  for (const sentence of sentences) {
    if (current.length === 0) {
      current = sentence;
    } else if (current.length + 1 + sentence.length <= maxCharsPerParagraph) {
      current = `${current} ${sentence}`;
    } else {
      paragraphs.push(current);
      current = sentence;
    }
  }
  if (current.length > 0) paragraphs.push(current);

  if (paragraphs.length === 0) return "<p>Journée sans récit enregistré.</p>";

  return paragraphs
    .map((paragraph) => `<p>${escapeHtml(paragraph.slice(0, maxCharsPerParagraph))}</p>`)
    .join("");
}

/**
 * Heuristique de choix de layout, reprise du catalogue de `LAYOUT_KB.md` et du
 * barème S/M/L/XL. Elle sert de secours déterministe : c'est le modèle qui
 * décide en mode `live`.
 *
 * Deux règles la gouvernent, dans cet ordre :
 *
 * 1. **sous le minimum de S, c'est l'image qui porte la page** — une page de
 *    photos si on en a de quoi la remplir, sinon la photo héro. Un récit court
 *    sur un layout de récit laisse une page aux trois quarts vide ;
 * 2. **au-dessus, le layout le plus visuel qui tienne le texte.** `layout_hero_top`
 *    plafonne à 380 caractères : au-delà, il faut un layout à récit pleine
 *    largeur.
 *
 * Elle ne rend que des drapeaux du catalogue : un drapeau inconnu n'échoue pas,
 * il est silencieusement ignoré et la journée retombe sur la mise en page par
 * défaut — exactement le genre de dérive que `LAYOUT_KB.md` interdit.
 */
export function pickLayout(photoCount: number, textLength: number): string {
  if (textLength < STEP_SIZES.S.min) {
    if (photoCount >= 3) return "layout_photo_page";
    if (photoCount >= 1) return "layout_hero_top";
    return "layout_story_facts";
  }

  if (photoCount >= 3) return "layout_collage";
  if (photoCount === 2) return "layout_split_left";
  if (photoCount === 1 && textLength <= LAYOUT_CAPACITY_HERO_TOP) return "layout_hero_top";
  return "layout_story_opener";
}

/** Plafond mesuré de `layout_hero_top` sur une page à bandeau. */
const LAYOUT_CAPACITY_HERO_TOP = 380;

/**
 * Coupe `text` au plus près de `max` caractères, sur une fin de phrase si
 * possible, sinon sur une espace. Couper au milieu d'un mot se verrait à
 * l'impression, et le texte est définitif : on ne le réécrit pas, on choisit
 * seulement où tourner la page.
 */
/** Nombre de pages déjà posées pour l'étape en cours de construction. */
function pagesDeLEtape(days: Record<string, unknown>[]): number {
  let pages = 0;
  for (let i = days.length - 1; i >= 0; i -= 1) {
    pages += 1;
    if (days[i]?.["day_intro"]) break;
  }
  return pages;
}

function splitAt(text: string, max: number): [string, string] {
  if (text.length <= max) return [text, ""];

  const fenetre = text.slice(0, max + 1);
  const finDePhrase = Math.max(
    fenetre.lastIndexOf(". "),
    fenetre.lastIndexOf("! "),
    fenetre.lastIndexOf("? "),
    fenetre.lastIndexOf("… "),
  );
  const coupe = finDePhrase > max / 2 ? finDePhrase + 1 : fenetre.lastIndexOf(" ");

  if (coupe <= 0) return [text.slice(0, max), text.slice(max).trim()];
  return [text.slice(0, coupe).trim(), text.slice(coupe).trim()];
}

/**
 * **Dire qui raconte** — T317 (28/11/2026).
 *
 * « Dire qui raconte, en tête de chaque paragraphe, quand le voyage se raconte
 * à plusieurs » (Hugo). Deux choses ont demandé d'interpréter la demande.
 *
 * **Un paragraphe n'est pas une unité d'auteur.** ``toBodyHtml`` découpe le
 * récit d'une journée au nombre de caractères : deux phrases de deux personnes
 * peuvent tomber dans le même paragraphe, et une phrase se couper en deux. La
 * vraie unité est le **souvenir**, dont on connaît l'auteur
 * (``StructuringEntry.narrator``). L'attribution se pose donc par souvenir.
 *
 * **Et elle se pose au changement** (choix de Hugo, 28/11/2026) : écrire
 * « Maÿlis » au-dessus de chaque paragraphe d'une journée qu'elle raconte
 * seule serait du bruit. Le prénom paraît quand la voix change, et en tête de
 * chaque page — un lecteur qui tourne la page a besoin qu'on le lui rappelle.
 *
 * ⚠️ **Un carnet à une seule voix ne change pas d'un octet** : ``segmentsDe``
 * rend alors un seul morceau sans narrateur, et le code suit le chemin d'avant
 * T317, les mêmes appels à ``splitAt`` et au même ``toBodyHtml``. C'est ce que
 * garantit le test « un carnet à une voix est inchangé ».
 */

/** Un morceau de récit, et qui le raconte. */
interface Segment {
  text: string;
  /** `null` : personne de nommé, donc rien à attribuer. */
  narrator: string | null;
  /** L'attribution se pose-t-elle devant ce morceau ? Décidé à la découpe. */
  attribue?: boolean;
}

/**
 * La classe du prénom dans `body_html` — définie par le validateur, qui est le
 * module qui connaît le contrat du HTML, et réexportée ici pour les appelants.
 * Le gabarit la pose sur une ligne de réglure pleine (`style.css`).
 */
export { ATTRIBUTION_CLASS };

/**
 * Ce qu'une attribution coûte à la capacité d'une page, en signes de récit.
 *
 * Le barème des capacités (`payloadValidator.LAYOUT_CAPACITY`) compte des
 * signes, et chaque `<p>` du carnet traîne déjà une ligne vide derrière lui
 * (`.mb-note p { margin-bottom: var(--mb-line) }`). Une attribution est un
 * `<p>` de plus : elle coûte donc **deux lignes**, la sienne et sa ligne vide.
 * À 45 à 55 signes par ligne sur une page A5, cela fait une centaine de
 * signes.
 *
 * ⚠️ **C'est une arithmétique, pas une mesure.** Elle penche exprès du côté de
 * la page un peu trop vide, qui est le bon côté de l'erreur : un récit qui
 * déborde de sa page est un carnet raté, un récit qui s'arrête deux lignes
 * trop tôt ne se voit pas. À confirmer sur un carnet rendu.
 */
const ATTRIBUTION_COST = 100;

/**
 * Sous ce reste de place, on ne commence pas une nouvelle voix : un prénom
 * suivi de trois mots au bas d'une page ne se lit pas. La voix attend la page
 * suivante, où elle est nommée en tête.
 *
 * ⚠️ **Ce n'est pas « on ne dit rien et on continue »**, et c'est une erreur
 * qu'il a fallu voir sur un carnet rendu pour la corriger : laisser le texte
 * de Paul sans prénom juste après celui de Maÿlis le fait lire **comme du
 * Maÿlis**. Un prénom manquant n'est pas une petite perte de confort, c'est
 * une fausse attribution — précisément ce que le ticket veut empêcher. Quand
 * on ne peut pas nommer, on ne place pas.
 *
 * Une ligne de récit, soit 45 à 55 signes sur une page A5, et non deux : une
 * voix qui commence au bas d'une page et continue au verso est la chose la
 * plus ordinaire d'un livre, et la page suivante la renomme en tête. Exiger
 * deux lignes laissait une page remplie à 43 % — vu sur un carnet rendu.
 */
const MIN_APRES_ATTRIBUTION = 60;

/** Ce qu'il reste de récit à placer, en signes. */
function longueurDe(segments: readonly Segment[]): number {
  return segments.reduce((total, segment) => total + segment.text.length, 0);
}

/** Le prénom, tel qu'il entre dans `body_html`. */
function attributionHtml(name: string): string {
  return `<p class="${ATTRIBUTION_CLASS}">${escapeHtml(name)}</p>`;
}

/**
 * Les narrateurs d'un carnet, sans doublon. Deux ou plus : le carnet se
 * raconte à plusieurs, et c'est la seule condition qui ouvre l'attribution.
 */
export function narrateursDe(entries: readonly StructuringEntry[]): string[] {
  const noms = entries
    .filter((entry) => entry.transcript?.trim())
    .map((entry) => entry.narrator?.trim())
    .filter((nom): nom is string => Boolean(nom));
  return [...new Set(noms)];
}

/**
 * Le récit d'une journée, en morceaux porteurs de leur auteur.
 *
 * À une seule voix, un seul morceau sans narrateur : exactement la chaîne que
 * le code joignait avant T317.
 */
function segmentsDe(entries: readonly StructuringEntry[], plusieursVoix: boolean): Segment[] {
  const textes = entries
    .map((entry) => ({ text: entry.transcript?.trim() ?? "", narrator: entry.narrator?.trim() || null }))
    .filter((segment) => segment.text.length > 0);

  if (!plusieursVoix) {
    const joint = textes.map((segment) => segment.text).join(" ");
    return joint.length > 0 ? [{ text: joint, narrator: null }] : [];
  }
  return textes;
}

/**
 * Ce qu'une page prend, et ce qu'elle laisse — en suivant les morceaux, pour
 * qu'une attribution ne se retrouve jamais devant le texte de quelqu'un
 * d'autre.
 *
 * Le premier morceau d'une page est toujours attribué : c'est ce qui nomme la
 * voix après un tournement de page. Les suivants ne le sont qu'au changement.
 */
function decouperEnPage(segments: Segment[], capacite: number): [Segment[], Segment[]] {
  // Une seule voix : le chemin d'avant T317, au caractère près.
  if (segments.length === 1 && segments[0]!.narrator === null) {
    const [page, suite] = splitAt(segments[0]!.text, capacite);
    return [
      page.length > 0 ? [{ text: page, narrator: null }] : [],
      suite.length > 0 ? [{ text: suite, narrator: null }] : [],
    ];
  }

  const page: Segment[] = [];
  let reste = capacite;
  let precedent: string | null | undefined;

  for (const [index, segment] of segments.entries()) {
    const changement = segment.narrator !== precedent;
    const nommable = segment.narrator !== null;
    const peutNommer = nommable && reste - ATTRIBUTION_COST >= MIN_APRES_ATTRIBUTION;

    // **La voix change et on ne peut pas la nommer : la page s'arrête ici.**
    // Le placer quand même le ferait lire comme la voix d'avant.
    if (changement && !peutNommer && page.length > 0) return [page, segments.slice(index)];

    // Sur une page encore vide, on place quoi qu'il arrive : rien ne précède
    // ce texte, donc rien ne peut se l'attribuer, et refuser ferait tourner la
    // boucle sans avancer.
    const attribue = changement && peutNommer;
    const place = reste - (attribue ? ATTRIBUTION_COST : 0);

    if (place <= 0) return [page, segments.slice(index)];

    if (segment.text.length <= place) {
      page.push({ ...segment, attribue });
      reste = place - segment.text.length;
      precedent = segment.narrator;
      continue;
    }

    const [debut, suite] = splitAt(segment.text, place);
    // Rien n'a tenu : la page s'arrête ici plutôt que de pousser un morceau
    // vide, qui ferait tourner la boucle sans avancer.
    if (debut.length === 0) return [page, segments.slice(index)];
    page.push({ ...segment, text: debut, attribue });
    return [page, [{ ...segment, text: suite }, ...segments.slice(index + 1)]];
  }

  return [page, []];
}

/**
 * Le récit d'une page en HTML, attributions comprises.
 *
 * Les paragraphes se remplissent **à l'intérieur** d'un morceau : un
 * paragraphe appartient à une voix, sans quoi l'attribution qui le précède
 * mentirait sur sa fin.
 */
function corpsDeLaPage(segments: Segment[]): string {
  if (segments.length === 1 && segments[0]!.narrator === null) {
    // Le chemin d'avant T317.
    return toBodyHtml(segments[0]!.text);
  }

  const morceaux = segments.map((segment) => {
    const prenom = segment.attribue && segment.narrator ? attributionHtml(segment.narrator) : "";
    return `${prenom}${toBodyHtml(segment.text)}`;
  });
  const html = morceaux.join("");
  return html.length > 0 ? html : "<p>Journée sans récit enregistré.</p>";
}

/**
 * Une étape commence toujours sur une page de gauche : quand le colophon et
 * l'introduction font un nombre pair de pages, une page libre les complète.
 */
export function premiereEtapeAGauche(payload: BookPayload): BookPayload {
  const sans = { ...payload };
  delete sans["pages_libres_avant"];
  return pagesAvantEtapes(sans) % 2 === 0 ? { ...sans, pages_libres_avant: 1 } : sans;
}

/**
 * **Un chapitre s'ouvre sur la carte de son pays** (T284, Hugo, 05/11/2026 —
 * « aucune carte n'est générée dans le PDF d'aperçu »).
 *
 * Tout était en place pour les dessiner : le layout (`layout_chapter_map`),
 * la géométrie (`services/mapSvg.ts`), les contours de Natural Earth, et
 * jusqu'au rapatriement des rues pour les cartes de ville. Il manquait la
 * seule chose que rien ne calculait : **le champ `map` sur une journée**.
 * Aucun des deux structureurs ne l'écrivait — ni le déterministe, ni le
 * prompt du metteur en page, qui n'en dit pas un mot. Les cartes de
 * l'atelier sont écrites à la main dans le payload ; celles de l'app
 * n'étaient écrites par personne.
 *
 * Ici, donc, et **sans modèle** : un pays, c'est une donnée que le carnet a
 * déjà (`memo_steps.destinationCountryCode`, relevé par la rédaction).
 *
 * ## Une carte par pays, pas une par chapitre
 *
 * `planifierCartes` sait enchaîner plusieurs cartes dans un même pays — on y
 * voit le trajet avancer d'une étape à l'autre. Mais ce trajet se dessine
 * avec des **points**, et nous n'en avons aucun : l'app ne connaît aucune
 * coordonnée (T280 a établi qu'elle n'en garde pas, et le lieu d'une photo
 * nous arrive géocodé en nom). Deux cartes d'un même pays sans points
 * seraient donc **identiques**, et le carnet répéterait le même dessin.
 *
 * On n'en pose donc qu'une : sur le premier chapitre qui entre dans un pays.
 *
 * ## Quand on ne sait pas
 *
 * `codes` donne le pays de chaque étape, dans l'ordre. S'il n'y en a pas
 * autant que de chapitres — le metteur en page a regroupé ou scindé —, on
 * n'essaie pas de deviner lequel va où : on pose la seule carte dont on soit
 * sûr, celle du pays du voyage, sur le premier chapitre. Et sans pays du
 * tout, aucune carte : un carnet sans carte vaut mieux qu'une carte fausse.
 */
export function ouvrirLesChapitresSurUneCarte(
  payload: BookPayload,
  codes: readonly (string | null | undefined)[],
  paysDuVoyage: string | null | undefined,
): BookPayload {
  const days = Array.isArray(payload["days"]) ? (payload["days"] as Record<string, unknown>[]) : [];
  if (days.length === 0) return payload;

  const chapitres = groupSteps(days);
  const propres = codes.map((code) => code?.trim().toUpperCase() || null);
  // Un code par chapitre, ou rien : on ne redistribue pas au jugé.
  const parChapitre =
    propres.length === chapitres.length
      ? propres
      : chapitres.map((_, index) => (index === 0 ? paysDuVoyage?.trim().toUpperCase() || null : null));

  const posees = new Set<string>();
  const avecCarte = new Map<number, string>();
  for (const [index, chapitre] of chapitres.entries()) {
    const code = parChapitre[index];
    // Le premier chapitre du pays, et lui seul.
    if (!code || posees.has(code)) continue;
    posees.add(code);
    avecCarte.set(chapitre.start, code);
  }
  if (avecCarte.size === 0) return payload;

  return {
    ...payload,
    days: days.map((day, index) => {
      const code = avecCarte.get(index);
      // Une carte déjà posée — l'atelier en écrit à la main — n'est pas
      // remplacée : elle en sait plus que nous, elle a ses points.
      if (!code || day["map"] || day["map_svg"]) return day;
      return { ...day, map: { regions: [code] } };
    }),
  };
}

/** Combien de photos chaque layout montre : au-delà, elles ne sont pas dessinées. */
/**
 * Combien de photos la page d'une étape **montre**, d'après son gabarit.
 *
 * Exporté pour la pertinence (T265) : c'est ce nombre qui dit si une étape a
 * un choix à faire. Une étape dont toutes les photos tiennent n'en a aucun —
 * et la faire juger par un modèle serait payer pour un classement sans effet.
 */
export function photosQueLaPageMontre(day: Record<string, unknown>): number {
  const layout = Object.keys(day).find((cle) => cle.startsWith("layout_") && day[cle] === true) ?? "";
  return PHOTOS_MONTREES[layout] ?? 1;
}

const PHOTOS_MONTREES: Readonly<Record<string, number>> = {
  layout_hero_top: 1,
  layout_split_left: 2,
  layout_collage: 3,
  layout_photo_page: 5,
  layout_story_opener: 1,
  layout_story_facts: 1,
};

/**
 * Une étape compte un nombre de pages pair, et ses pages de photos seules
 * viennent après son récit (LAYOUT_KB § « Structure d'une étape »). Le repli
 * déterministe pose toutes les photos sur la première page : à une étape au
 * nombre de pages impair, on ajoute une page de photos à la fin avec celles
 * que la première page ne montre pas. Sans photo de reste, l'étape reste
 * impaire — le validateur le signale.
 */
export function completerEtapesImpaires(days: Record<string, unknown>[]): Record<string, unknown>[] {
  const sortie: Record<string, unknown>[] = [];
  for (const etape of groupSteps(days)) {
    sortie.push(...etape.days);
    if (etape.days.length % 2 === 0) continue;
    const premiere = etape.days[0] as Record<string, unknown>;
    const photos = Array.isArray(premiere["photos"]) ? (premiere["photos"] as unknown[]) : [];
    const layout = Object.keys(premiere).find((cle) => cle.startsWith("layout_") && premiere[cle] === true) ?? "";
    const reste = photos.slice(PHOTOS_MONTREES[layout] ?? 1, (PHOTOS_MONTREES[layout] ?? 1) + 5);
    if (!reste.length) continue;
    premiere["photos"] = photos.slice(0, PHOTOS_MONTREES[layout] ?? 1);
    sortie.push({ title: "", body_html: "", photos: reste, layout_photo_page: true });
  }
  return sortie;
}

/**
 * Structuration déterministe : une journée par date, un layout par heuristique,
 * aucun appel réseau. C'est ce que le smoke test et la CI utilisent, et c'est
 * aussi le filet de sécurité si l'appel modèle échoue.
 */
export class HeuristicStructurer implements Structurer {
  async structure(input: StructuringInput): Promise<BookPayload> {
    const groups = groupEntriesByDay(input.entries);
    // **Le carnet se raconte-t-il à plusieurs ?** (T317) Décidé une fois, sur
    // tout le carnet et non sur la journée : un voyage à deux voix dont une
    // journée n'a qu'un narrateur dit quand même qui la raconte, sans quoi le
    // lecteur attribuerait cette journée à la dernière voix nommée.
    const plusieursVoix = narrateursDe(input.entries).length > 1;

    const days: Record<string, unknown>[] = [];
    let numero = 0;

    groups.forEach((group) => {
      const photos = group.entries
        .map((entry) => entry.photoUrl)
        .filter((url): url is string => Boolean(url));

      // **Le récit de la journée, en morceaux porteurs de leur auteur** (T317).
      // À une seule voix, c'est un seul morceau : la chaîne jointe d'avant.
      const segments = segmentsDe(group.entries, plusieursVoix);

      // **Le lieu de l'étape, et lui seul** (T308). Pas l'écho que l'app
      // renvoie avec le vocal, qui nomme l'étape d'avant le jour où l'on
      // change de ville ; pas la ville du voyage non plus, qui imprimerait
      // « Tokyo » sur une journée passée à Kyoto — c'est très exactement la
      // plainte de T280. Sans lieu, l'en-tête n'en affiche pas, et MEMO le
      // demandera (reste de T267).
      const place = group.entries.find((entry) => entry.stepPlace)?.stepPlace ?? null;

      // Titre, météo et encart viennent de la rédaction quand elle est passée.
      // Le repli déterministe ne réinvente que ce qui manque.
      const redactedTitle = group.entries.find((entry) => entry.title)?.title ?? null;
      const weatherKey = group.entries.find((entry) => entry.weatherKey)?.weatherKey ?? null;
      const withFunFact = group.entries.find((entry) => entry.funFact);
      // Un quiz par étape au plus : le premier de la journée. Le composeur
      // choisit ensuite sa page, et la cadence du carnet (`bookComposer.ts`).
      const withQuiz = group.entries.find((entry) => entry.quiz);

      // Le récit se déverse page après page. Une étape occupe au plus deux
      // pages — la première porte le bandeau, la seconde enchaîne sans lui.
      // Au-delà, c'est une nouvelle étape, pas une page de plus : c'est ce que
      // dit le barème, et ce que le validateur vérifiera.
      let reste = segments;
      let premierePage = true;

      while (longueurDe(reste) > 0 || premierePage) {
        const ouvreEtape = premierePage || days.length === 0 || pagesDeLEtape(days) >= STEP_SIZES.XL.pages;

        if (ouvreEtape) numero += 1;

        const day: Record<string, unknown> = {
          // Une page de suite n'a ni bandeau ni titre — le titre reste présent
          // mais vide, parce que le schéma l'exige et que le gabarit ne rend
          // que les titres non vides.
          title: "",
          [pickLayout(ouvreEtape ? photos.length : 0, longueurDe(reste))]: true,
        };

        if (ouvreEtape) {
          day["title"] = redactedTitle ?? `Jour ${numero}${place ? ` – ${place}` : ""}`;
          day["date"] = DATE_FORMATTER.format(group.date);
          day["day_intro"] = {
            day_number: String(numero).padStart(2, "0"),
            location: place ?? "",
            date: SHORT_DATE_FORMATTER.format(group.date),
            ...(weatherKey ? { weather_key: weatherKey } : {}),
          };
          if (place) day["city"] = place;
          if (photos.length > 0) day["photos"] = photos;
          if (withFunFact?.funFact) {
            day["fun_facts"] = [withFunFact.funFact];
            if (withFunFact.funFactTitle) day["fun_facts_title"] = withFunFact.funFactTitle;
          }
        }

        // La capacité se lit sur la page telle qu'elle vient d'être montée :
        // le bandeau, la carte info et les photos la font varier du simple au
        // quadruple.
        const [page, suite] = decouperEnPage(reste, pageCapacity(day));
        day["body_html"] = corpsDeLaPage(page);
        // Posé après la coupe : un quiz élargit la page par défaut
        // (`pageCapacity`), mais c'est le composeur qui lui trouve sa page.
        if (premierePage && withQuiz?.quiz) day["quiz"] = withQuiz.quiz;

        days.push(day);
        reste = suite;
        premierePage = false;
      }
    });

    const payload: BookPayload = {
      book_title: input.title,
      authors: input.authors ?? "",
      date_range: formatDateRange(groups),
      brand_name: "MemoBook",
      days: completerEtapesImpaires(choisirLesMontrees(days, input.entries)),
    };

    if (input.subtitle) payload["book_subtitle"] = input.subtitle;
    if (input.coverPhotoUrl) payload["cover_photo"] = input.coverPhotoUrl;

    // La seule prose que ce structureur compose lui-même : une intro assemblée
    // directement depuis les champs du contexte, sans appel modèle.
    if (input.tripContext) {
      payload["intro_title"] = introTitleFor(input.tripContext);
      payload["intro_text"] = introTextFor(input.tripContext);
    }

    return payload;
  }
}

function formatIssues(issues: ValidationIssue[]): string {
  return issues
    .map((issue) => `- ${issue.path || "(racine)"}: ${issue.message}`)
    .join("\n");
}

/**
 * Structuration par modèle. Le prompt système est construit à partir des
 * fichiers du dépôt (`gpt_image_schema.yaml`, `LAYOUT_KB.md`) : quand le
 * template évolue, le prompt suit sans changement de code.
 */
export class LlmStructurer implements Structurer {
  constructor(
    private readonly client: OpenAI,
    private readonly model: string,
    /** Reprend la main si le modèle ne produit rien d'exploitable. */
    private readonly fallback: Structurer = new HeuristicStructurer(),
  ) {}

  private buildSystemPrompt(): string {
    return [
      "Tu es le metteur en page de MemoBook. Tu reçois des textes **déjà rédigés et",
      "déjà validés par le voyageur**, et tu les arranges en pages de carnet.",
      "",
      "## Ta seule mission : arranger, jamais réécrire",
      "",
      "Le texte de chaque étape t'arrive fini. Une autre passe l'a écrit en suivant",
      "les règles de rédaction de la maison, et le voyageur l'a relu et corrigé au",
      "clavier. Le réécrire effacerait son travail.",
      "",
      "- Reprends `title`, le récit, `fun_facts`, `weather_key` et `quiz` **au mot près**.",
      "- Tu peux **découper** un texte en `<p>` et **répartir** une étape trop dense",
      "  sur plusieurs entrées consécutives de `days[]`. Découper n'est pas réécrire :",
      "  aucun mot n'est ajouté, retiré ni remplacé.",
      "- Une étape marquée « corrigée par le voyageur » est intouchable, même si elle",
      "  te semble maladroite. Si elle dépasse les limites de longueur, scinde-la en",
      "  plusieurs entrées plutôt que de la raccourcir.",
      "- N'invente aucun texte : ni titre, ni encart, ni transition, ni légende.",
      "",
      "## Une exception : la page d'introduction",
      "",
      "`intro_title` et `intro_text` sont la seule prose que tu composes toi-même —",
      "et seulement à partir du « Contexte du voyage » donné plus bas (pays de",
      "départ, voyageurs, compagnons, dates, genre de voyage), jamais à partir du",
      "récit des étapes. Deux à quatre phrases, dans un seul `<p>`. Si aucun contexte",
      "n'est donné, n'écris ni l'un ni l'autre.",
      "",
      "Tu réponds UNIQUEMENT par un objet JSON conforme au schéma ci-dessous.",
      "",
      "## Schéma du payload",
      "```yaml",
      stringifyYaml(loadPayloadSchema()),
      "```",
      "",
      "## Règles éditoriales (à respecter strictement)",
      loadLayoutKnowledgeBase(),
    ].join("\n");
  }

  private buildUserPrompt(input: StructuringInput): string {
    const groups = groupEntriesByDay(input.entries);

    const lines: string[] = [
      `Titre du carnet : ${input.title}`,
      input.subtitle ? `Sous-titre : ${input.subtitle}` : "",
      input.authors ? `Auteurs : ${input.authors}` : "",
      input.theme ? `Thème : ${input.theme}` : "",
      input.coverPhotoUrl ? `Photo de couverture : ${input.coverPhotoUrl}` : "",
    ].filter(Boolean);

    if (input.tripContext) {
      lines.push("", "Contexte du voyage (pour la seule page d'introduction) :");
      lines.push(...describeTripContext(input.tripContext));
    }

    lines.push("", `Matière brute — ${groups.length} journée(s) :`);

    for (const [index, group] of groups.entries()) {
      lines.push("", `### Journée ${index + 1} — ${DATE_FORMATTER.format(group.date)}`);
      for (const entry of group.entries) {
        // Le lieu de l'étape (T308) : le même que celui du repli
        // déterministe, sinon le modèle écrirait une journée sans lieu là où
        // le repli en a un — ou, pire, le lieu de l'étape d'avant.
        const lieu = entry.stepPlace ?? null;
        if (lieu) lines.push(`Lieu : ${lieu}`);
        if (entry.title) lines.push(`Titre (à reprendre tel quel) : ${entry.title}`);
        if (entry.weatherKey) lines.push(`weather_key (déjà choisi) : ${entry.weatherKey}`);
        if (entry.funFact) {
          lines.push(
            `Encart « ${entry.funFactTitle ?? "Fun fact"} » (à reprendre tel quel) : ${entry.funFact}`,
          );
        }
        if (entry.quiz) {
          lines.push(`Quiz (à reprendre tel quel, \`quiz\` de la première page de l'étape) : ${JSON.stringify(entry.quiz)}`);
        }
        if (entry.transcript) {
          lines.push(
            entry.editedByUser
              ? `Récit — CORRIGÉ PAR LE VOYAGEUR, intouchable : ${entry.transcript}`
              : `Récit — texte validé : ${entry.transcript}`,
          );
        }
        if (entry.photoUrl) lines.push(`Photo : ${entry.photoUrl}`);
      }
    }

    lines.push(
      "",
      "Rappel : ces textes sont définitifs. Tu les découpes en paragraphes et tu",
      "choisis les layouts ; tu ne les réécris pas, tu ne les résumes pas, tu ne les",
      "complètes pas. N'invente aucun lieu, aucune date et aucune photo : n'utilise",
      "que les URLs listées ci-dessus. N'ajoute pas de `fun_facts` : ceux qui devaient",
      "exister sont déjà donnés ci-dessus. N'ajoute pas non plus de `weather_key` : seule",
      "une étape dont la météo est donnée ci-dessus en porte une. Même chose pour `quiz` :",
      "seuls ceux donnés ci-dessus existent, et tu n'en écris aucun.",
    );

    return lines.join("\n");
  }

  async structure(input: StructuringInput): Promise<BookPayload> {
    const messages: OpenAI.Chat.ChatCompletionMessageParam[] = [
      { role: "system", content: this.buildSystemPrompt() },
      { role: "user", content: this.buildUserPrompt(input) },
    ];

    // Deux tentatives : la seconde reçoit les erreurs de validation de la
    // première. En pratique, c'est ce qui rattrape les dépassements de longueur
    // et les layouts multiples.
    for (let attempt = 1; attempt <= 2; attempt += 1) {
      const completion = await this.client.chat.completions.create({
        model: this.model,
        messages,
        response_format: { type: "json_object" },
        temperature: 0.7,
      });

      const content = completion.choices[0]?.message?.content;
      if (!content) break;

      let candidate: unknown;
      try {
        candidate = JSON.parse(content);
      } catch {
        messages.push(
          { role: "assistant", content },
          { role: "user", content: "Ta réponse n'était pas du JSON valide. Recommence." },
        );
        continue;
      }

      // Le modèle renvoie parfois le schéma complet de l'agent plutôt que le
      // seul payload : on accepte les deux formes.
      const payload =
        candidate && typeof candidate === "object" && "apitemplate_payload" in candidate
          ? (candidate as Record<string, unknown>)["apitemplate_payload"]
          : candidate;

      const result = validatePayload(payload);
      if (result.valid) {
        return withBestPhotosFirst(
          // **Qui raconte** (T317) : posé après le modèle, et non par lui.
          avecLesVoix(
            withToldQuizzesOnly(withToldWeatherOnly(payload as BookPayload, input.entries), input.entries),
            input.entries,
          ),
          input.entries,
        );
      }

      if (attempt === 2) break;

      messages.push(
        { role: "assistant", content },
        {
          role: "user",
          content: `Ton JSON ne respecte pas le schéma :\n${formatIssues(result.errors)}\n\nCorrige-le et renvoie le JSON complet.`,
        },
      );
    }

    return this.fallback.structure(input);
  }
}

/**
 * **Reposer les prénoms sur un carnet arrangé par le modèle** — T317.
 *
 * En production, ce n'est pas le repli déterministe qui monte les pages : un
 * modèle reçoit les textes déjà rédigés et les arrange (``LlmStructurer``).
 * Son prompt lui interdit d'inventer le moindre mot, et il **ne sait rien**
 * des attributions : on ne lui en demande pas, et on ne lui en montre pas.
 *
 * C'est ce qui rend cette passe sûre. Elle ne vérifie pas le travail du
 * modèle, elle le refait : elle retire toute attribution présente, retrouve à
 * quel souvenir appartient chaque paragraphe en cherchant son texte dans les
 * souvenirs du carnet, puis repose les prénoms aux changements de voix. Le
 * modèle n'a qu'une chose à tenir, celle qu'il tient déjà et dont tout le
 * reste du montage dépend : **ne pas réécrire les mots**.
 *
 * Elle est donc idempotente, et sans effet sur un carnet à une seule voix.
 *
 * ⚠️ **Un paragraphe qui mêle deux souvenirs n'est pas attribué.** Le modèle a
 * le droit de réunir deux souvenirs dans un même paragraphe ; aucun prénom
 * n'est alors vrai pour tout le paragraphe, et on se taît plutôt que d'en
 * choisir un. Même silence pour un paragraphe dont le texte ne se retrouve
 * dans aucun souvenir — s'il a été réécrit, on ne sait plus qui l'a dit.
 *
 * ⚠️ **Et jamais au prix d'un débordement.** Le modèle a rempli la page sans
 * savoir que des lignes s'ajouteraient : chaque prénom posé est retiré de ce
 * qu'il reste de place (``ATTRIBUTION_COST``), et les prénoms qui ne tiennent
 * plus ne sont pas posés. C'est aussi ce qui autorise le validateur à ignorer
 * les attributions (``sansAttributions``) : leur place est toujours payée
 * avant qu'elles soient écrites, ici comme dans le repli.
 */
export function avecLesVoix<T extends BookPayload>(
  payload: T,
  entries: readonly StructuringEntry[],
): T {
  const days = payload["days"];
  if (!Array.isArray(days)) return payload;

  const plusieursVoix = narrateursDe(entries).length > 1;
  const sources = entries
    .filter((entry) => entry.transcript?.trim() && entry.narrator?.trim())
    .map((entry) => ({ narrator: entry.narrator!.trim(), texte: normaliseTexte(entry.transcript!) }));

  const refaits = (days as unknown[]).map((day) => {
    if (!day || typeof day !== "object") return day;
    const page = day as Record<string, unknown>;

    // Un carnet à une voix n'écrit aucun prénom — y compris si le modèle en
    // avait inventé un, ce que rien ne lui demande.
    const nettoyes = CHAMPS_DE_RECIT.map((champ) =>
      typeof page[champ] === "string" ? sansAttributions(page[champ]) : null,
    );
    if (!plusieursVoix) {
      return remplaceLesRecits(page, nettoyes);
    }

    const sansPrenoms = remplaceLesRecits(page, nettoyes);
    let reste = pageCapacity(sansPrenoms) - bodyLength(sansPrenoms);
    let precedent: string | null = null;

    const ecrits = nettoyes.map((html) => {
      if (html === null) return null;
      return html.replace(PARAGRAPHE, (entier: string, dedans: string) => {
        const voix = voixDuParagraphe(dedans, sources);
        if (voix === null || voix === precedent) return entier;
        if (reste - ATTRIBUTION_COST < 0) return entier;
        reste -= ATTRIBUTION_COST;
        precedent = voix;
        return `${attributionHtml(voix)}${entier}`;
      });
    });

    return remplaceLesRecits(page, ecrits);
  });

  return { ...payload, days: refaits };
}

/** Les deux champs qui portent le récit d'une page. */
const CHAMPS_DE_RECIT = ["body_html", "body_html_apres"] as const;

const PARAGRAPHE = /<p(?:\s[^>]*)?>([\s\S]*?)<\/p>/g;

function remplaceLesRecits(
  page: Record<string, unknown>,
  valeurs: readonly (string | null)[],
): Record<string, unknown> {
  const sortie = { ...page };
  CHAMPS_DE_RECIT.forEach((champ, index) => {
    const valeur = valeurs[index];
    if (valeur !== null && valeur !== undefined) sortie[champ] = valeur;
  });
  return sortie;
}

/** Comparer des textes sans se laisser arrêter par les espaces ni la casse. */
function normaliseTexte(texte: string): string {
  return texte.replace(/\s+/g, " ").trim().toLowerCase();
}

/**
 * À quel souvenir appartient ce paragraphe, et donc à qui.
 *
 * `null` dès que la réponse n'est pas franche : aucun souvenir ne contient ce
 * texte, ou plusieurs voix le contiennent. Dans les deux cas on ne nomme
 * personne.
 */
function voixDuParagraphe(
  dedans: string,
  sources: readonly { narrator: string; texte: string }[],
): string | null {
  const texte = normaliseTexte(dedans.replace(/<[^>]+>/g, " "));
  if (texte.length === 0) return null;

  const voix = new Set(
    sources.filter((source) => source.texte.includes(texte)).map((source) => source.narrator),
  );
  return voix.size === 1 ? [...voix][0]! : null;
}

/**
 * **Les meilleures photos d'abord, dans chaque page** (T265, 18/11/2026).
 *
 * Chaque gabarit dessine un nombre fixe de photos et laisse les suivantes de
 * côté (`PHOTOS_MONTREES`) : jusqu'ici, c'étaient **les premières arrivées**
 * qui gagnaient, la floue comme la nette. On les réordonne pour que celles
 * que la page montre soient les plus nettes — sans toucher à leur ordre
 * d'apparition, qui reste celui du récit (`services/photoPicking.ts`).
 *
 * Posé en passe finale, comme `withToldWeatherOnly` : les deux structureurs y
 * passent, celui du modèle comme le déterministe, et aucun n'a à y penser.
 */
export function choisirLesMontrees(
  days: Record<string, unknown>[],
  entries: readonly StructuringEntry[],
  pertinence: ReadonlyMap<string, number> = new Map(),
): Record<string, unknown>[] {
  const qualite = new Map<string, PhotoQuality>();
  for (const entry of entries) {
    if (!entry.photoUrl) continue;
    qualite.set(entry.photoUrl, {
      sharpness: entry.photoSharpness,
      verdict: entry.photoVerdict,
      blur: entry.photoBlur,
      beauty: entry.photoBeauty,
    });
  }
  if (qualite.size === 0) return days;

  for (const day of days) {
    const photos = day["photos"];
    if (!Array.isArray(photos) || photos.length < 2) continue;
    day["photos"] = photosLesPlusNettes(photos, photosQueLaPageMontre(day), (photo) =>
      typeof photo === "string"
        ? { ...(qualite.get(photo) ?? {}), relevance: pertinence.get(photo) ?? null }
        : {},
    );
  }
  return days;
}

/** La même chose sur un payload déjà assemblé — le chemin du modèle. */
export function withBestPhotosFirst(
  payload: BookPayload,
  entries: readonly StructuringEntry[],
  pertinence: ReadonlyMap<string, number> = new Map(),
): BookPayload {
  const days = (payload as unknown as { days?: unknown }).days;
  if (Array.isArray(days)) {
    choisirLesMontrees(days as Record<string, unknown>[], entries, pertinence);
  }
  return payload;
}

/**
 * La météo ne s'imprime que si le voyageur l'a dite clairement dans son vocal :
 * c'est la rédaction qui la relève, étape par étape (`weatherKey`). Le metteur
 * en page n'a que des textes rédigés sous les yeux ; une `weather_key` qu'il
 * ajouterait serait supposée — du lieu, de la saison, d'un coucher de soleil.
 * On retire donc toute valeur que la rédaction n'a relevée nulle part.
 */
export function withToldWeatherOnly(payload: BookPayload, entries: StructuringEntry[]): BookPayload {
  const told = new Set(entries.map((entry) => entry.weatherKey).filter(Boolean));
  const days = payload["days"];
  if (!Array.isArray(days)) return payload;
  for (const day of days) {
    const intro = (day as Record<string, unknown> | null)?.["day_intro"];
    if (!intro || typeof intro !== "object") continue;
    const fields = intro as Record<string, unknown>;
    if ("weather_key" in fields && !told.has(fields["weather_key"] as string)) delete fields["weather_key"];
  }
  return payload;
}

/**
 * Même garde pour les quiz : seul un quiz que la rédaction a écrit, et que le
 * réglage laisse passer, s'imprime. Celui que le metteur en page aurait
 * inventé — ou recopié de travers — saute ; un quiz reconnu à sa question est
 * remis tel que la rédaction l'a écrit.
 */
export function withToldQuizzesOnly(payload: BookPayload, entries: StructuringEntry[]): BookPayload {
  const told = new Map(entries.flatMap((entry) => (entry.quiz ? [[entry.quiz.question, entry.quiz] as const] : [])));
  const days = payload["days"];
  if (!Array.isArray(days)) return payload;
  for (const day of days) {
    if (!day || typeof day !== "object" || !("quiz" in day)) continue;
    const fields = day as Record<string, unknown>;
    const question = (fields["quiz"] as { question?: unknown } | null)?.question;
    const quiz = typeof question === "string" ? told.get(question.trim()) : undefined;
    if (quiz) fields["quiz"] = quiz;
    else delete fields["quiz"];
  }
  return payload;
}

export function createStructurer(env: Env): Structurer {
  if (!env.live) return new HeuristicStructurer();
  return new LlmStructurer(
    new OpenAI({ apiKey: env.OPENAI_API_KEY }),
    env.OPENAI_STRUCTURING_MODEL,
  );
}
