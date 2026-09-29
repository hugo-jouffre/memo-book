/**
 * Pousse le relevé du jour dans la feuille de bord, à la main — ou l'affiche.
 *
 *   npm run stats:show          relève et affiche, n'envoie rien
 *   npm run stats:push          relève et envoie (STATS_SHEET_WEBHOOK_URL)
 *
 * Le même relevé que le job quotidien (`jobs/exportStats.ts`). Utile le jour
 * où l'on branche la feuille, pour vérifier que les onglets se remplissent
 * sans attendre 4 h 20.
 *
 * ⚠️ La base est **partagée avec la production** : ce script ne fait que lire.
 */

import { PrismaClient } from "@prisma/client";
import { loadEnv } from "../src/env.js";
import { collectStats, isSheetConfigured, postToSheet } from "../src/services/statsExport.js";

async function main(): Promise<void> {
  const dryRun = process.argv.includes("--dry-run");
  const env = loadEnv();
  const prisma = new PrismaClient();

  try {
    const snapshot = await collectStats(prisma);
    console.log(JSON.stringify(snapshot, null, 2));

    if (dryRun) return;
    if (!isSheetConfigured(env)) {
      console.error("STATS_SHEET_WEBHOOK_URL est vide : rien n'est envoyé.");
      process.exitCode = 1;
      return;
    }
    await postToSheet(env, { type: "snapshot", snapshot });
    console.log("Relevé envoyé à la feuille de bord.");
  } finally {
    await prisma.$disconnect();
  }
}

main().catch((error: unknown) => {
  console.error(error);
  process.exitCode = 1;
});
