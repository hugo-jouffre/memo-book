import type { Memo, MemoStep } from "@prisma/client";
import type { AppContext } from "../context.js";
import { coverPhotoUrl } from "../routes/covers.js";
import {
  coverCarriesStats,
  coverCarriesText,
  coverFamilyOf,
  coverStatsOf,
  readStoredCover,
  type CoverFace,
  type CoverFamily,
} from "./coverCatalogue.js";

/**
 * **Les deux plats du carnet, tels que le voyageur les a choisis**, dans la
 * forme que le gabarit lit (T259, Hugo 05/11/2026 : « les plats du PDF ne sont
 * pas ceux choisis dans la personnalisation »).
 *
 * Le sélecteur de couvertures est dans l'app depuis le 08/10/2026 : sept
 * gabarits, une photo, un titre, une signature, un texte de quatrième, des
 * chiffres. Tout cela se rangeait dans `memos.coverFront` / `coverBack`, et
 * **personne ne venait jamais le lire au moment de composer** : le carnet
 * sortait avec la couverture générique du gabarit — une photo pleine page et
 * le titre du voyage —, quel que soit le plat validé à l'écran. C'est le
 * « reste à écrire » de T256.
 *
 * Ce qui est ici, et ce qui n'y est pas :
 *
 * - **ici**, l'aperçu PDF de l'app : les deux plats dessinés par le gabarit
 *   (`templates/travel-journal/index.html`), au dessin près de ceux que l'app
 *   montre (`CoverTemplates.swift`). C'est ce que le voyageur regarde avant de
 *   commander ;
 * - **pas ici**, la couverture **imprimée** d'un relié : elle n'est pas une
 *   page du carnet (largeur du dos, fond perdu, autre papier), l'atelier la
 *   compose à part (`MemoBook Generator/public/couverture-styles.js`), et
 *   `sans_couvertures` retire justement les plats de l'intérieur qui part chez
 *   l'imprimeur.
 *
 * **Les règles de ce qui s'imprime viennent du catalogue** (`coverCatalogue.ts`),
 * pas d'ici : un plat qui ne porte pas de texte est le même à l'écran et au
 * PDF, sinon le voyageur écrirait dans un champ grisé par l'app et imprimé par
 * le gabarit.
 */

/**
 * Un chiffre du dos, son libellé déjà coupé en lignes — « 13 », « jours / de
 * voyage ». `lines` et non `label` : dans ce gabarit, `label` est la légende
 * d'une photo, et c'est une chaîne (`mb_photo`).
 */
export interface BookCoverStat {
  value: string;
  lines: string[];
}

/** Un temps du récit de quatrième, et l'image qui l'accompagne. */
export interface BookCoverParagraph {
  text: string;
  photo?: string;
}

/** Un plat, prêt à dessiner. */
export interface BookCoverFace {
  /** Le gabarit à dessiner : c'est lui qui décide de tout le reste. */
  family: CoverFamily;
  title: string;
  /**
   * Le texte du plat : la **signature** au devant (qui, quand), le **texte de
   * quatrième** au dos. Vide quand ce plat n'en porte pas.
   */
  text: string;
  /**
   * Le texte de quatrième, coupé en paragraphes et **déjà apparié** à une
   * image du voyage : c'est le dos d'« Aquarelle », qui raconte en trois temps,
   * une vignette à gauche puis à droite. L'appariement se fait ici et non dans
   * le gabarit : le même payload doit donner le même carnet chez les deux
   * moteurs, et une expression d'index tournée autrement par Jinja2 et par
   * Nunjucks ne se verrait qu'à l'impression.
   */
  paragraphs: BookCoverParagraph[];
  /**
   * Qui a voyagé : la première ligne de la signature, quand elle en a deux.
   *
   * ⚠️ **Absente plutôt que nulle**, comme tout le payload : Jinja2 imprime un
   * `null` par le mot « None » dans le carnet, et la composition refuse donc
   * d'en laisser passer un (`bookPdf.ts`, `assertNoNullValues`).
   */
  authors?: string;
  /** Quand : la dernière ligne de la signature — la seule, s'il n'y en a qu'une. */
  when?: string;
  /** Le titre du devant, que deux dos reprennent. */
  frontTitle: string;
  /** La photo choisie pour ce plat. */
  photo?: string;
  /**
   * Les photos du voyage, la choisie d'abord : les timbres de « Travel book »,
   * les vignettes du dos d'« Aquarelle ».
   */
  gallery: string[];
  /** Les chiffres retenus pour le dos, dans l'ordre du catalogue. Vides ailleurs. */
  stats: BookCoverStat[];
  /**
   * De combien le titre et le texte doivent **rétrécir** pour tenir sur le
   * plat, de 1 (tel que le gabarit le dessine) à `TITLE_FLOOR` / `TEXT_FLOOR`.
   *
   * Le gabarit n'a aucun moyen de le calculer : CSS ne sait pas réduire un
   * texte jusqu'à ce qu'il tienne — c'est `minimumScaleFactor` de SwiftUI, que
   * l'app emploie sur chaque plat. Sans lui, un titre de quarante signes
   * sortirait du papier, et un débordement ne se voit qu'à l'impression. Les
   * **tailles de base** restent dans la feuille de style : le serveur ne dit
   * que de combien rétrécir.
   */
  titleScale: number;
  textScale: number;
}

/**
 * **Ce qui ne se redessine pas** : la palme d'Assouline, la moto, la route et
 * le globe de Dessin, le motard de son dos, les courbes de Photo-dessin. Ce
 * sont des découpes des plats de Hugo (`ios/Tools/import-cover-ornaments.py`),
 * et non des formes : le gabarit les charge par leur adresse, comme les
 * stickers du carnet (`services/bookComposer.ts`).
 *
 * Elles sont **les mêmes pour tous les voyages** — c'est ce que T256 laisse en
 * question. Et elles sont servies depuis `main` : un ornement nouveau n'existe
 * à cette adresse qu'après la fusion. Entre-temps un plat sort sans sa
 * décoration, jamais en erreur.
 */
export const COVER_ORNAMENTS_URL =
  "https://raw.githubusercontent.com/hugo-jouffre/memo-book/main/assets/covers/ornements/";

const ORNAMENT_FILES = {
  palm: "CoverOrnamentPalm.png",
  motorbike: "CoverOrnamentMotorbike.png",
  road: "CoverOrnamentRoad.png",
  globe: "CoverOrnamentGlobe.png",
  rider: "CoverOrnamentRider.png",
  contours: "CoverOrnamentContours.png",
} as const;

export type CoverOrnaments = Record<keyof typeof ORNAMENT_FILES, string>;

export const COVER_ORNAMENTS: CoverOrnaments = Object.fromEntries(
  Object.entries(ORNAMENT_FILES).map(([key, file]) => [key, `${COVER_ORNAMENTS_URL}${file}`]),
) as CoverOrnaments;

export interface BookCovers {
  front: BookCoverFace;
  back: BookCoverFace;
  ornaments: CoverOrnaments;
}

/** Ce qu'on lit du carnet pour composer ses plats. */
export type CoverMemo = Pick<
  Memo,
  | "coverFront"
  | "coverBack"
  | "startDate"
  | "endDate"
  | "dayCount"
  | "distanceKilometres"
  | "destinationCountryCode"
  | "memoryCount"
  | "photoCount"
> & {
  coverPhotos: { id: string; storageKey: string }[];
  steps: Pick<MemoStep, "destinationCountryCode" | "transport">[];
};

/**
 * Les souvenirs dont une photo est posée sur un plat. **Elle doit partir même
 * quand le carnet ne garde aucune photo à l'intérieur** — ratio photo / texte
 * à 0 % : le voyageur l'a mise sur sa couverture, pas dans son récit. La
 * composition les prépare donc à part (`jobs/structure.ts`).
 */
export function coverPhotoEntryIds(memo: Pick<CoverMemo, "coverFront" | "coverBack">): string[] {
  const ids = [readStoredCover("front", memo.coverFront).photoId, readStoredCover("back", memo.coverBack).photoId];
  return ids
    .filter((id): id is string => id !== null && id.startsWith("entry-"))
    .map((id) => id.slice("entry-".length));
}

/**
 * Le nombre de signes qu'un plat porte **sans rétrécir** — un titre de
 * destination (« PHILIPPINES »), un texte de quatrième de deux paragraphes.
 * Au-delà, le texte se réduit jusqu'à son plancher.
 *
 * **Trop prudent plutôt que débordant** : les sept gabarits n'ont pas tous la
 * même place, et la référence est celle du plus serré. Un titre un peu petit
 * se lit ; un titre coupé par le massicot, non.
 */
const TITLE_CHARS = 16;
const TITLE_FLOOR = 0.4;
const TEXT_CHARS = 420;
const TEXT_FLOOR = 0.6;

/** De combien ce texte rétrécit pour tenir dans sa place. */
function fitScale(text: string, chars: number, floor: number): number {
  const length = text.trim().length;
  if (length <= chars) return 1;
  return Math.max(floor, Math.round((chars / length) * 100) / 100);
}

/** Les trois temps du récit, chacun avec une image, en tournant sur la galerie. */
function pairWithPhotos(paragraphs: string[], gallery: readonly string[]): BookCoverParagraph[] {
  return paragraphs.map((text, index) => {
    const photo = gallery.length > 0 ? gallery[index % gallery.length] : undefined;
    return { text, ...(photo ? { photo } : {}) };
  });
}

/** La signature du devant, ligne par ligne, sans les lignes vides. */
function signatureLines(text: string): string[] {
  return text
    .split("\n")
    .map((line) => line.trim())
    .filter((line) => line.length > 0);
}

/** Le texte de quatrième, coupé sur les lignes vides comme dans l'app. */
function paragraphsOf(text: string): string[] {
  return text
    .split("\n\n")
    .map((paragraph) => paragraph.trim())
    .filter((paragraph) => paragraph.length > 0);
}

/**
 * L'adresse d'une photo de plat. Deux provenances, et c'est l'app qui les
 * mélange dans une seule liste de choix (`GET /v1/trips/:id/covers`) :
 *
 * - `entry-<id>` — une photo du voyage. Son adresse est celle que la
 *   composition vient de préparer pour le carnet : déjà convertie si elle
 *   arrivait en HEIC, déjà allégée (`services/renderPhotos.ts`). La
 *   redemander ici en fabriquerait une seconde, lourde, pour la même image ;
 * - un UUID — une photo importée **pour la couverture**, servie sans session
 *   par `GET /v1/cover-photos/:file`, faite pour être lue par le gabarit.
 */
function coverPhotoAddress(
  env: AppContext["env"],
  memo: CoverMemo,
  photoUrlByEntryId: ReadonlyMap<string, string>,
  photoId: string | null,
): string | undefined {
  if (!photoId) return undefined;
  if (photoId.startsWith("entry-")) return photoUrlByEntryId.get(photoId.slice("entry-".length));
  const imported = memo.coverPhotos.find((photo) => photo.id === photoId);
  return imported ? coverPhotoUrl(env, imported.storageKey) : undefined;
}

/**
 * Les deux plats du carnet. `photoUrlByEntryId` est la table des photos que la
 * composition a déjà préparées, par souvenir — celle que `jobs/structure.ts`
 * tient pour poser ses stickers.
 */
export function bookCoversOf(
  env: AppContext["env"],
  memo: CoverMemo,
  photoUrlByEntryId: ReadonlyMap<string, string>,
  /**
   * Le nombre de photos du voyage — **toutes**, pas seulement celles que la
   * composition a su préparer : c'est le chiffre « photos prises » que l'app
   * propose au dos, et il doit être le même des deux côtés.
   */
  photoEntries: number,
): BookCovers {
  const stored = { front: readStoredCover("front", memo.coverFront), back: readStoredCover("back", memo.coverBack) };
  const families: Record<CoverFace, CoverFamily> = {
    front: coverFamilyOf("front", stored.front.styleId),
    back: coverFamilyOf("back", stored.back.styleId),
  };

  const available = coverStatsOf(memo, memo.steps, photoEntries);
  const chosen = stored.back.statIds
    .map((id) => available.find((stat) => stat.id === id))
    .filter((stat): stat is (typeof available)[number] => stat !== undefined)
    .map((stat) => ({ value: stat.value, lines: stat.label.split("\n") }));

  const signature = signatureLines(stored.front.subtitle);

  const faceOf = (face: CoverFace): BookCoverFace => {
    const family = families[face];
    const cover = stored[face];
    const text = coverCarriesText(face, family) ? cover.subtitle : "";
    const photo = coverPhotoAddress(env, memo, photoUrlByEntryId, cover.photoId);
    // La choisie d'abord, comme dans l'app : c'est elle qui ouvre le collage
    // de timbres et la première vignette du dos.
    const others = [...photoUrlByEntryId.values()].filter((url) => url !== photo);
    const gallery = photo ? [photo, ...others] : others;

    const authors = signature.length > 1 ? signature[0] : undefined;
    const when = signature.at(-1);

    return {
      family,
      title: cover.title,
      text,
      paragraphs: face === "back" ? pairWithPhotos(paragraphsOf(text), gallery) : [],
      ...(authors ? { authors } : {}),
      ...(when ? { when } : {}),
      frontTitle: stored.front.title,
      ...(photo ? { photo } : {}),
      gallery,
      stats: coverCarriesStats(face, family) ? chosen : [],
      titleScale: fitScale(cover.title, TITLE_CHARS, TITLE_FLOOR),
      textScale: fitScale(text, TEXT_CHARS, TEXT_FLOOR),
    };
  };

  return { front: faceOf("front"), back: faceOf("back"), ornaments: COVER_ORNAMENTS };
}
