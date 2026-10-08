import { createHash } from "node:crypto";
import type { Prisma, PrismaClient } from "@prisma/client";

/**
 * **L'empreinte d'un carnet** : de quoi dire qu'un rendu prêt montre encore le
 * contenu d'aujourd'hui (T224, Hugo 06/10/2026).
 *
 * L'aperçu PDF lance une composition à **chaque ouverture** — l'imprimante de
 * l'accueil du voyage, « Prévisualisation PDF » des paramètres, le CTA des
 * écrans de personnalisation. Une composition coûte de l'IA et un rendu
 * APITemplate : le serveur ne la relance donc que si quelque chose a changé
 * depuis la dernière réussie. L'empreinte est posée sur le rendu à sa création
 * (`renders.inputFingerprint`) et comparée à celle du moment.
 *
 * **Ce qui y entre**, et c'est la liste de Hugo — « aucun souvenir,
 * personnalisation, couverture modifiés depuis » :
 *
 * - les souvenirs : leur nombre et leur dernière modification. Le nombre
 *   attrape une suppression, la date toute écriture — un texte corrigé, une
 *   rédaction finie, un souvenir rattaché à une étape ;
 * - les étapes, de même ;
 * - les photos importées pour la couverture, de même ;
 * - le carnet lui-même : titre, dates, destination, contexte du voyage,
 *   personnalisations, couvertures.
 *
 * **Ce qui n'y entre pas**, exprès : ce que le pipeline écrit lui-même
 * (`pageCount`, `isPrintable`) — un rendu qui modifierait sa propre empreinte
 * serait périmé dès sa naissance —, et les compteurs que `tripFacts.ts`
 * déduit des souvenirs (`memoryCount`, `photoCount`, `dayCount`,
 * `distanceKilometres`) : ils ne bougent qu'avec eux, et les compter deux fois
 * ne ferait que relancer une composition pour rien quand ils suivent avec une
 * seconde de retard. Ni les réglages qui ne touchent pas au livre
 * (notifications, rythme, lien de partage, galerie).
 *
 * **Trop prudente plutôt que pas assez** : un « Ça me convient » sur un
 * souvenir touche sa date de modification sans changer une lettre du carnet,
 * et relance donc une composition. C'est le prix d'une empreinte qui se calcule
 * en quatre petites requêtes — l'aperçu la relit toutes les deux secondes —
 * au lieu de relire chaque texte. L'inverse, un carnet périmé présenté comme à
 * jour, serait pire : on commanderait un livre qui n'est pas le sien.
 */

/**
 * La version de la mise en page. **À incrémenter quand le gabarit change de
 * façon visible** (`MemoBook Generator/templates/travel-journal/`) : tous les
 * rendus deviennent périmés, et chaque aperçu se recompose une fois à sa
 * prochaine ouverture. Laisser la version telle quelle garde les PDF déjà
 * composés.
 */
export const BOOK_LAYOUT_VERSION = 1;

/** Les colonnes du carnet qui changent le livre. */
export const FINGERPRINT_MEMO_SELECT = {
  title: true,
  subtitle: true,
  authors: true,
  bookTitle: true,
  theme: true,
  startDate: true,
  endDate: true,
  coverPhotoUrl: true,
  styleKey: true,
  destinationName: true,
  destinationCountryCode: true,
  destinationCity: true,
  tripContext: true,
  targetPageCount: true,
  photoTextRatio: true,
  funFactsEnabled: true,
  quizEnabled: true,
  rulesEnabled: true,
  freeZonesEnabled: true,
  crosswordEnabled: true,
  decorationQuota: true,
  fontDisplay: true,
  fontTitle: true,
  fontHand: true,
  fontFacts: true,
  coverFront: true,
  coverBack: true,
} as const satisfies Prisma.MemoSelect;

type FingerprintMemo = Prisma.MemoGetPayload<{ select: typeof FINGERPRINT_MEMO_SELECT }>;

type Db = Pick<PrismaClient, "memo" | "entry" | "memoStep" | "coverPhoto"> | Prisma.TransactionClient;

/** Un ensemble de lignes, réduit à ce qui trahit un changement. */
interface RowsSummary {
  count: number;
  lastChange: string | null;
}

/**
 * L'empreinte, à partir de ce qui a déjà été lu. Pure : le même contenu donne
 * toujours la même chaîne.
 */
export function fingerprintOf(input: {
  memo: FingerprintMemo;
  entries: RowsSummary;
  steps: RowsSummary;
  coverPhotos: RowsSummary;
}): string {
  // L'ordre des clés est celui de `FINGERPRINT_MEMO_SELECT`, figé : deux
  // lectures du même carnet sérialisent à l'identique.
  const memo = Object.fromEntries(
    Object.keys(FINGERPRINT_MEMO_SELECT).map((key) => {
      const value = input.memo[key as keyof FingerprintMemo];
      return [key, value instanceof Date ? value.toISOString() : (value ?? null)];
    }),
  );
  const canonical = JSON.stringify({
    layout: BOOK_LAYOUT_VERSION,
    memo,
    entries: input.entries,
    steps: input.steps,
    coverPhotos: input.coverPhotos,
  });
  return createHash("sha256").update(canonical).digest("hex");
}

/** L'empreinte du carnet **aujourd'hui**. `null` si le carnet n'existe pas. */
export async function currentBookFingerprint(db: Db, memoId: string): Promise<string | null> {
  const [memo, entries, steps, coverPhotos] = await Promise.all([
    db.memo.findUnique({ where: { id: memoId }, select: FINGERPRINT_MEMO_SELECT }),
    db.entry.aggregate({ where: { memoId }, _count: { _all: true }, _max: { updatedAt: true } }),
    db.memoStep.aggregate({ where: { memoId }, _count: { _all: true }, _max: { updatedAt: true } }),
    db.coverPhoto.aggregate({ where: { memoId }, _count: { _all: true }, _max: { createdAt: true } }),
  ]);
  if (!memo) return null;

  return fingerprintOf({
    memo,
    entries: { count: entries._count._all, lastChange: entries._max.updatedAt?.toISOString() ?? null },
    steps: { count: steps._count._all, lastChange: steps._max.updatedAt?.toISOString() ?? null },
    coverPhotos: {
      count: coverPhotos._count._all,
      lastChange: coverPhotos._max.createdAt?.toISOString() ?? null,
    },
  });
}
