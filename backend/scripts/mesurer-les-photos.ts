/**
 * Mesure les photos d'avant la mesure, pour qu'elles puissent faire couverture.
 *
 *   npm run photos:mesurer -- --dry-run   compte, ne touche à rien
 *   npm run photos:mesurer                mesure et écrit
 *   npm run photos:mesurer -- --limit 200 s'arrête après 200 photos
 *
 * **Pourquoi ce script existe.** Depuis le 15/10/2026, la couverture d'un
 * voyage est la plus récente de ses photos **paysage**, et c'est
 * `entries.photoIsLandscape` qui le dit — écrit à l'arrivée de la photo
 * (`routes/chat.ts`). Les photos envoyées avant ce jour-là n'ont pas ce champ :
 * sans rattrapage, elles ne sont jamais couverture, et les voyages déjà
 * racontés gardent leur motif pour toujours.
 *
 * Il relit donc chaque photo depuis le stockage et la mesure. C'est un
 * aller-retour par photo : lent, mais il ne tourne qu'une fois, et il se
 * reprend là où il s'est arrêté — il ne regarde que les photos sans mesure.
 *
 * ⚠️ La base est **partagée avec la production**. Ce script n'écrit que trois
 * champs **déduits du fichier lui-même** : aucune donnée du voyageur n'est
 * touchée, et le relancer donne le même résultat. Une photo illisible
 * (HEIC, fichier perdu) est comptée et laissée telle quelle.
 */

import { PrismaClient } from "@prisma/client";
import { loadEnv } from "../src/env.js";
import { createMediaStorage } from "../src/services/storage.js";
import { measurePhoto } from "../src/services/photoOrientation.js";

/** Assez pour ne pas tenir mille photos en mémoire, assez pour avancer. */
const BATCH = 25;

async function main(): Promise<void> {
  const dryRun = process.argv.includes("--dry-run");
  const limitFlag = process.argv.indexOf("--limit");
  const limit = limitFlag === -1 ? Infinity : Number(process.argv[limitFlag + 1] ?? NaN);
  if (Number.isNaN(limit)) {
    console.error("--limit attend un nombre.");
    process.exitCode = 1;
    return;
  }

  const env = loadEnv();
  const prisma = new PrismaClient();
  const storage = createMediaStorage(env);

  let seen = 0;
  let measured = 0;
  let landscape = 0;
  let unreadable = 0;

  try {
    const total = await prisma.entry.count({
      where: { kind: "photo", photoIsLandscape: null, media: { isNot: null } },
    });
    console.log(`${total} photo(s) sans mesure.`);
    if (dryRun || total === 0) return;

    // On repart toujours du début : les photos mesurées sortent du filtre au
    // fur et à mesure, donc la page suivante est celle qui reste à faire. Une
    // photo illisible, elle, y resterait pour toujours — d'où le curseur, qui
    // la laisse derrière lui.
    let after: string | undefined;

    while (seen < limit) {
      const batch = await prisma.entry.findMany({
        where: {
          kind: "photo",
          photoIsLandscape: null,
          media: { isNot: null },
          ...(after ? { id: { gt: after } } : {}),
        },
        orderBy: { id: "asc" },
        take: Math.min(BATCH, limit - seen),
        select: { id: true, media: { select: { storageKey: true } } },
      });
      if (batch.length === 0) break;

      for (const entry of batch) {
        seen += 1;
        after = entry.id;
        const key = entry.media?.storageKey;
        if (!key) {
          unreadable += 1;
          continue;
        }

        let measurement = null;
        try {
          measurement = await measurePhoto(await storage.get(key));
        } catch {
          // Fichier absent du stockage : rien à mesurer, on passe.
        }

        if (!measurement) {
          unreadable += 1;
          continue;
        }

        await prisma.entry.update({
          where: { id: entry.id },
          data: {
            photoWidthPx: measurement.widthPx,
            photoHeightPx: measurement.heightPx,
            photoIsLandscape: measurement.isLandscape,
          },
        });
        measured += 1;
        if (measurement.isLandscape) landscape += 1;
      }

      console.log(`  ${seen}/${Math.min(total, limit)}…`);
    }
  } finally {
    await prisma.$disconnect();
  }

  console.log(
    `${measured} mesurée(s), dont ${landscape} paysage(s) ; ${unreadable} illisible(s), laissée(s) sans mesure.`,
  );
}

await main();
