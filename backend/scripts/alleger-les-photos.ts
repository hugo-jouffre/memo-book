/**
 * Fabrique à l'avance les copies allégées que le moteur de PDF ira chercher.
 *
 *   npm run photos:alleger -- --dry-run          compte, ne touche à rien
 *   npm run photos:alleger                       allège tout ce qui reste
 *   npm run photos:alleger -- --memo <id>        un seul voyage
 *   npm run photos:alleger -- --limit 200        s'arrête après 200 photos
 *
 * **Pourquoi ce script existe.** Depuis le 14/11/2026, une photo de plus de
 * 900 Ko part au carnet en copie 2400 px (`services/photoDownscale.ts`), parce
 * qu'APITemplate télécharge chaque photo avant de composer et abandonne en
 * HTTP 504 quand il y en a trois cents mégaoctets. La copie se fabrique toute
 * seule, à la première composition qui demande la photo — mais celle-là paie
 * alors soixante-dix téléchargements et autant d'encodages **dans sa propre
 * fenêtre**, et c'est précisément ce qu'on cherche à éviter.
 *
 * Ce script prend donc de l'avance sur les carnets déjà écrits. Il se reprend
 * là où il s'est arrêté : il ne regarde que les photos sans copie.
 *
 * ⚠️ La base est **partagée avec la production**. Le script n'écrit qu'un
 * champ, `renderStorageKey`, et n'efface jamais rien : l'original reste
 * intact, et une photo illisible est comptée puis laissée telle quelle.
 */

import { PrismaClient } from "@prisma/client";
import { loadEnv } from "../src/env.js";
import { createMediaStorage } from "../src/services/storage.js";
import { downscaleForRender, RENDER_MAX_BYTES } from "../src/services/photoDownscale.js";

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

  const where = {
    renderStorageKey: null,
    bytes: { gt: RENDER_MAX_BYTES },
    ...(memoId ? { entries: { some: { memoId } } } : {}),
  };

  let seen = 0;
  let allegees = 0;
  let illisibles = 0;
  let octetsAvant = 0;
  let octetsApres = 0;

  try {
    const total = await prisma.mediaAsset.count({ where });
    console.log(`${total} photo(s) à alléger${memoId ? ` sur le voyage ${memoId}` : ""}.`);
    if (dryRun || total === 0) return;

    while (seen < limit) {
      // Pas de curseur : une photo allégée sort du filtre, donc la première
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

        let copie = null;
        try {
          copie = await downscaleForRender(await storage.get(asset.storageKey));
        } catch {
          // Fichier absent du stockage : rien à alléger, on passe.
        }

        if (!copie) {
          illisibles += 1;
          continue;
        }

        const stored = await storage.put("photo", copie.filename, copie.buffer, copie.mimeType);
        await prisma.mediaAsset.update({
          where: { id: asset.id },
          data: { renderStorageKey: stored.storageKey },
        });

        allegees += 1;
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
    `${allegees} allégée(s) : ${mo(octetsAvant)} → ${mo(octetsApres)} ; ` +
      `${illisibles} laissée(s) telle(s) quelle(s).`,
  );
}

await main();
