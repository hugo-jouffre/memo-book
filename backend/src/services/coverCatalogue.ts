import type { Memo, MemoStep } from "@prisma/client";

/**
 * Le catalogue des couvertures : les styles proposés pour chaque plat, et les
 * chiffres du voyage qui peuvent s'imprimer au dos.
 *
 * **Il vit ici et non dans l'app** (T88, 29/09/2026) : c'est le gabarit qui
 * saura les dessiner, et un style ajouté doit exister avant que l'app le
 * propose. L'app ne connaît que les identifiants qu'elle a reçus — c'est ce
 * qui permet à `PATCH /v1/trips/:id/covers` de refuser un style inventé.
 *
 * Les identifiants sont ceux du jeu d'essai de l'app (`CoverFixtures.swift`),
 * pour qu'un carnet réglé sur le bac à sable se relise tel quel.
 */

export type CoverFace = "front" | "back";
export type CoverTreatment = "photo" | "framed" | "plain" | "kraft";
export type CoverTint = "paper" | "sand" | "forest" | "slate" | "ink";

/**
 * Les sept gabarits de `assets/covers` (Hugo, 08/10/2026), par paires : la
 * 1ère et la 4e d'une même famille portent le même nom de fichier à la fin
 * (« front cover_style dessin », « back cover_style dessin »). C'est la
 * famille qui fait la pastille « Assortie à ta 1ère de couverture » dans
 * l'app, et le gabarit que l'app redessine (`CoverFamily`, `CoverTemplates`).
 */
export type CoverFamily =
  | "default"
  | "watercolor"
  | "assouline"
  | "drawing"
  | "photo-drawing"
  | "travel-book"
  | "elegant";

export interface CoverStyle {
  id: string;
  name: string;
  /**
   * La composition et l'aplat **des apps installées** avant les gabarits :
   * elles ne lisent pas `family` et dessinent leur plat d'après ces deux-là.
   * Choisis pour en être le plus proche.
   */
  treatment: CoverTreatment;
  tint: CoverTint;
  family: CoverFamily;
}

export const FRONT_COVER_STYLES: readonly CoverStyle[] = [
  { id: "front-default", name: "Par défaut", treatment: "photo", tint: "ink", family: "default" },
  { id: "front-watercolor", name: "Aquarelle", treatment: "framed", tint: "sand", family: "watercolor" },
  { id: "front-assouline", name: "Assouline", treatment: "plain", tint: "slate", family: "assouline" },
  { id: "front-drawing", name: "Dessin", treatment: "kraft", tint: "paper", family: "drawing" },
  { id: "front-photo-drawing", name: "Photo-dessin", treatment: "photo", tint: "ink", family: "photo-drawing" },
  { id: "front-travel-book", name: "Travel book", treatment: "framed", tint: "paper", family: "travel-book" },
  { id: "front-elegant", name: "Élégant", treatment: "framed", tint: "paper", family: "elegant" },
];

export const BACK_COVER_STYLES: readonly CoverStyle[] = [
  { id: "back-default", name: "Par défaut", treatment: "plain", tint: "paper", family: "default" },
  { id: "back-watercolor", name: "Aquarelle", treatment: "framed", tint: "sand", family: "watercolor" },
  { id: "back-assouline", name: "Assouline", treatment: "plain", tint: "slate", family: "assouline" },
  { id: "back-drawing", name: "Dessin", treatment: "kraft", tint: "paper", family: "drawing" },
  { id: "back-photo-drawing", name: "Photo-dessin", treatment: "plain", tint: "paper", family: "photo-drawing" },
  { id: "back-travel-book", name: "Travel book", treatment: "framed", tint: "paper", family: "travel-book" },
  { id: "back-elegant", name: "Élégant", treatment: "framed", tint: "paper", family: "elegant" },
];

/**
 * Les six styles provisoires d'avant les gabarits, et celui qui les remplace
 * au plus près. Un carnet réglé avant le 08/10/2026 garde ainsi une
 * couverture qui lui ressemble, au lieu de retomber sur le défaut.
 */
const LEGACY_COVER_STYLES: Readonly<Record<string, string>> = {
  "front-photo": "front-default",
  "front-framed": "front-elegant",
  "front-plain": "front-assouline",
  "front-sand": "front-watercolor",
  "front-kraft": "front-drawing",
  "front-forest": "front-travel-book",
  "back-photo": "back-travel-book",
  "back-framed": "back-default",
  "back-plain": "back-assouline",
  "back-sand": "back-watercolor",
  "back-kraft": "back-drawing",
  "back-forest": "back-travel-book",
};

/** L'identifiant d'aujourd'hui d'un style, qu'on le reçoive neuf ou d'avant les gabarits. */
export function currentCoverStyleId(id: string): string {
  return LEGACY_COVER_STYLES[id] ?? id;
}

export function coverStylesFor(face: CoverFace): readonly CoverStyle[] {
  return face === "front" ? FRONT_COVER_STYLES : BACK_COVER_STYLES;
}

/** Le style par défaut d'un plat qu'on n'a jamais réglé : la paire « par défaut ». */
export function defaultCoverStyleId(face: CoverFace): string {
  return face === "front" ? "front-default" : "back-default";
}

/**
 * Ce que le serveur garde d'un plat, dans `memos.coverFront` / `coverBack`.
 *
 * La structure « libre » que le schéma annonçait s'est fixée ici : c'est
 * exactement ce que l'app envoie et relit (`BookCover`, dans `MemoBookCore`).
 */
export interface StoredCover {
  styleId: string;
  photoId: string | null;
  title: string;
  subtitle: string;
  statIds: string[];
}

/** Relit un plat stocké, et retombe sur le défaut pour ce qui manque. */
export function readStoredCover(face: CoverFace, value: unknown): StoredCover {
  const raw = value && typeof value === "object" ? (value as Record<string, unknown>) : {};
  const styles = coverStylesFor(face);
  const stored = typeof raw["styleId"] === "string" ? currentCoverStyleId(raw["styleId"]) : null;
  const styleId = stored && styles.some((style) => style.id === stored) ? stored : defaultCoverStyleId(face);
  return {
    styleId,
    photoId: typeof raw["photoId"] === "string" ? raw["photoId"] : null,
    title: typeof raw["title"] === "string" ? raw["title"] : "",
    subtitle: typeof raw["subtitle"] === "string" ? raw["subtitle"] : "",
    statIds: Array.isArray(raw["statIds"])
      ? raw["statIds"].filter((id): id is string => typeof id === "string")
      : [],
  };
}

export interface CoverStat {
  id: string;
  /** « 13 », « 2,3k » — c'est le serveur qui abrège, et lui seul. */
  value: string;
  /** Sur deux lignes, comme au dos du carnet. */
  label: string;
}

const DAY_MS = 24 * 60 * 60 * 1000;

/** « 2,3k » au-delà de mille, à la française. */
function abbreviate(value: number): string {
  if (value >= 1000) {
    const thousands = Math.round(value / 100) / 10;
    return `${thousands.toLocaleString("fr-FR", { maximumFractionDigits: 1 })}k`;
  }
  return String(Math.round(value));
}

/**
 * Les chiffres que ce voyage sait produire, dans l'ordre où le dos les
 * propose. Un chiffre qu'on ne sait pas calculer n'apparaît pas : mieux vaut
 * trois chiffres vrais qu'un zéro imprimé.
 */
export function coverStatsOf(
  memo: Pick<Memo, "startDate" | "endDate" | "dayCount" | "distanceKilometres" | "destinationCountryCode" | "memoryCount" | "photoCount">,
  steps: Pick<MemoStep, "destinationCountryCode" | "transport">[],
  photoEntries: number,
): CoverStat[] {
  const stats: CoverStat[] = [];

  const days =
    memo.dayCount ??
    (memo.startDate && memo.endDate
      ? Math.max(1, Math.round((memo.endDate.getTime() - memo.startDate.getTime()) / DAY_MS) + 1)
      : null);
  if (days) stats.push({ id: "stat-days", value: String(days), label: "jours\nde voyage" });

  if (memo.distanceKilometres && memo.distanceKilometres > 0) {
    stats.push({ id: "stat-km", value: abbreviate(memo.distanceKilometres), label: "km\nparcourus" });
  }

  const countries = new Set<string>();
  if (memo.destinationCountryCode) countries.add(memo.destinationCountryCode);
  for (const step of steps) if (step.destinationCountryCode) countries.add(step.destinationCountryCode);
  if (countries.size > 0) {
    stats.push({
      id: "stat-countries",
      value: String(countries.size),
      label: countries.size === 1 ? "pays\nvisité" : "pays\nvisités",
    });
  }

  if (steps.length > 0) {
    stats.push({ id: "stat-steps", value: String(steps.length), label: "étapes\nde voyage" });
  }

  const photos = Math.max(memo.photoCount ?? 0, photoEntries);
  if (photos > 0) stats.push({ id: "stat-photos", value: String(photos), label: "photos\nprises" });

  if (memo.memoryCount > 0) {
    stats.push({ id: "stat-memories", value: String(memo.memoryCount), label: "souvenirs\nracontés" });
  }

  const transports = new Set(steps.map((step) => step.transport?.trim().toLowerCase()).filter(Boolean));
  if (transports.size > 0) {
    stats.push({ id: "stat-transport", value: String(transports.size), label: "transports\nutilisés" });
  }

  return stats;
}

/** Les photos importées pour les couvertures : le préfixe de stockage, et le nom servi. */
export const COVER_PHOTO_PREFIX = "covers";
export const COVER_PHOTO_FILENAME = /^[0-9a-f-]{36}\.(jpg|jpeg|png)$/;

export function coverPhotoMimeType(filename: string): string {
  return filename.endsWith(".png") ? "image/png" : "image/jpeg";
}
