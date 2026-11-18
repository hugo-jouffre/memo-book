/**
 * Fabrique à l'avance les vignettes que l'app affiche.
 *
 *   npm run photos:vignettes -- --dry-run         compte, ne touche à rien
 *   npm run photos:vignettes                      vignette tout ce qui reste
 *   npm run photos:vignettes -- --memo <id>       un seul voyage
 *   npm run photos:vignettes -- --limit 200       s'arrête après 200 photos
 *
 * **Pourquoi ce script existe.** Depuis le 17/11/2026, une photo qui arrive
 * reçoit tout de suite une vignette de 900 px (T260,
 * `services/photoThumbnails.ts`) : l'écran des couvertures propose toutes les
 * photos du voyage, et les servait en pleine résolution — 4,45 Mo par photo en
 * moyenne, jusqu'à 423 Mo pour parcourir un rail.
 *
 * Mais les photos **déjà en stock** n'en ont pas, et rien ne leur en fabrique
 * : contrairement à la copie du carnet, la vignette ne se fait pas à la
 * demande — l'écran aurait eu à en produire quatre-vingt-huit pendant qu'on
 * l'attend. C'est donc ce script, une fois, qui rattrape.
 *
 * Il se reprend là où il s'est arrêté : il ne regarde que les photos sans
 * vignette.
 *
 * ⚠️ La base est **partagée avec la production**. Le script n'écrit qu'un
 * champ, `thumbStorageKey`, et n'efface jamais rien : l'originale reste
 * intacte, et une photo illisible est comptée puis laissée telle quelle.
 */

import { PrismaClient } from "@prisma/client";
import { loadEnv } from "../src/env.js";
import { createMediaStorage } from "../src/services/storage.js";
import { downscaleForScreen, THUMB_MAX_BYTES } from "../src/services/photoDownscale.js";

/** Assez pour ne pas tenir mille photos en mémoire, assez pour avancer. */
const BATCH = 10;

function flag(nom: string): string | undefined {
  const index = process.argv.indexOf(nom);
  return index === -1 ? undefined : process.argv[index + 1];
}

async function main(): Promise<void> {
  const dryRun = process.argv.includes("--dry-run");
  const memoId = flag("--memo");
  const limitFlag = flag("--limit");
  const limit = limitFlag === undefined ? Infinity : Number(limitFlag);
  if (Number.isNaN(limit)) {
    console.error("--limit attend un nombre.");
    process.exitCode = 1;
    return;
  }

  const env = loadEnv();
  const prisma = new PrismaClient();
  const storage = createMediaStorage(env);

  // Seules les photos : un vocal n'a pas de vignette. `mimeType` le dit, et
  // c'est plus sûr que de se fier au préfixe de la clé.
  const where = {
    thumbStorageKey: null,
    mimeType: { startsWith: "image/" },
    bytes: { gt: THUMB_MAX_BYTES },
    ...(memoId ? { entries: { some: { memoId } } } : {}),
  };

  let seen = 0;
  let faites = 0;
  let illisibles = 0;
  let octetsAvant = 0;
  let octetsApres = 0;

  try {
    const total = await prisma.mediaAsset.count({ where });
    console.log(`${total} photo(s) à vignetter${memoId ? ` sur le voyage ${memoId}` : ""}.`);
    if (dryRun || total === 0) return;

    while (seen < limit) {
      // Pas de curseur : une photo vignettée sort du filtre, donc la première
      // page est toujours celle qui reste à faire. Une photo illisible y
      // resterait — `illisibles` le dit, et une deuxième passe la reverrait.
      const batch = await prisma.mediaAsset.findMany({
        where,
        orderBy: { createdAt: "asc" },
        take: Math.min(BATCH, limit - seen),
        skip: illisibles,
        select: { id: true, storageKey: true, bytes: true },
      });
      if (batch.length === 0) break;

      for (const asset of batch) {
        seen += 1;

        let vignette = null;
        try {
          vignette = await downscaleForScreen(await storage.get(asset.storageKey));
        } catch {
          // Fichier absent du stockage : rien à vignetter, on passe.
        }

        if (!vignette) {
          illisibles += 1;
          continue;
        }

        const stored = await storage.put(
          "photo",
          vignette.filename,
          vignette.buffer,
          vignette.mimeType,
        );
        await prisma.mediaAsset.update({
          where: { id: asset.id },
          data: { thumbStorageKey: stored.storageKey },
        });

        faites += 1;
        octetsAvant += asset.bytes;
        octetsApres += stored.bytes;
      }

      console.log(`  ${seen}/${Math.min(total, limit)}…`);
    }
  } finally {
    await prisma.$disconnect();
  }

  const mo = (octets: number): string => `${(octets / 1_000_000).toFixed(1)} Mo`;
  console.log(
    `${faites} vignette(s) : ${mo(octetsAvant)} → ${mo(octetsApres)} à l'écran ; ` +
      `${illisibles} laissée(s) telle(s) quelle(s).`,
  );
}

await main();
