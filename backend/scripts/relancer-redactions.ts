#!/usr/bin/env tsx
/**
 * Les épaves de la rédaction : annoncées « en attente » ou « en cours », sans
 * aucun job derrière elles. Ce script les compte, et les remet en file quand
 * on le lui demande.
 *
 *   railway run --service worker -- npm run redaction:epaves
 *   railway run --service worker -- npm run redaction:epaves -- --relancer --max 5
 *   railway run --service worker -- npm run redaction:epaves -- --relancer --entree <id>
 *
 * D'où elles viennent : pg-boss fait expirer un job que personne n'a dépilé,
 * puis l'archive ; l'entrée, elle, reste à `pending` pour toujours. Le
 * 04/11/2026 il y en avait trente et une, la plus ancienne du 29 octobre — et
 * avec elles, **aucun carnet ne pouvait se composer** : `jobs/structure.ts`
 * attend les rédactions en cours trois minutes avant de renoncer. La route de
 * relance les ignorait ; elle les reprend depuis (`routes/entries.ts`).
 *
 * ⚠️ **Chaque relance est une rédaction payée**, et la rédaction pèse 81 % du
 * coût modèle (`docs/modeles-ia.md` § 2). Sans `--relancer` le script ne fait
 * que lire ; `--max` borne la dépense le temps de vérifier qu'une première
 * repasse.
 */
import { createContext } from "../src/context.js";
import { loadEnv } from "../src/env.js";
import { JOB_NAMES } from "../src/jobs/index.js";
import { strandedBefore, type RedactJob } from "../src/jobs/redact.js";

const relancer = process.argv.includes("--relancer");
const maxIndex = process.argv.indexOf("--max");
const max = maxIndex === -1 ? Number.POSITIVE_INFINITY : Number(process.argv[maxIndex + 1]);
const entreeIndex = process.argv.indexOf("--entree");
const entree = entreeIndex === -1 ? null : process.argv[entreeIndex + 1];

if (Number.isNaN(max) || max <= 0) {
  console.error("--max attend un nombre de relances supérieur à zéro.");
  process.exit(1);
}

const context = createContext(loadEnv());

// Exactement ce qui bloque une composition : `pendingRedactionCount` de
// `jobs/structure.ts` compte toute entrée non-photo en attente, sans regarder
// le reste. On ne filtre donc ni sur la transcription ni sur une correction
// manuelle — `jobs/redact.ts` les passe à `ready` dès la première ligne, sans
// appeler l'IA ni toucher au texte. Les écarter laisserait des carnets
// bloqués par des entrées qu'on débloque pourtant gratuitement.
//
// `--entree` vise une fiche nommée, quel que soit son état et son âge : c'est
// le geste d'après un échec, quand on veut savoir si la rédaction repasse
// avant d'engager les autres.
const epaves = entree
  ? await context.prisma.entry.findMany({
      where: { id: entree, kind: { not: "photo" } },
      select: { id: true, memoId: true, redactionStatus: true, updatedAt: true },
    })
  : await context.prisma.entry.findMany({
      where: {
        redactionStatus: { in: ["pending", "processing"] },
        updatedAt: { lt: strandedBefore() },
        kind: { not: "photo" },
      },
      select: { id: true, memoId: true, redactionStatus: true, updatedAt: true },
      orderBy: { updatedAt: "asc" },
    });

if (entree && epaves.length === 0) {
  console.error(`Aucune entrée ${entree} à rédiger (inexistante, ou c'est une photo).`);
  await context.prisma.$disconnect();
  process.exit(1);
}

const carnets = new Set(epaves.map((epave) => epave.memoId)).size;
console.log(`${epaves.length} épave(s), sur ${carnets} carnet(s).`);
for (const epave of epaves.slice(0, 10)) {
  console.log(`  ${epave.updatedAt.toISOString()}  ${epave.redactionStatus.padEnd(10)} ${epave.id}`);
}
if (epaves.length > 10) console.log(`  … et ${epaves.length - 10} autres.`);

if (!relancer || epaves.length === 0) {
  if (epaves.length > 0) console.log("\nLecture seule. Ajoute --relancer pour les remettre en file.");
  await context.prisma.$disconnect();
  process.exit(0);
}

const aRelancer = epaves.slice(0, max === Number.POSITIVE_INFINITY ? epaves.length : max);
console.log(`\nRelance de ${aRelancer.length} rédaction(s) — autant d'appels payés.`);

await context.queue.start();
for (const epave of aRelancer) {
  // `updatedAt` se rafraîchit ici : une entrée relancée cesse d'être une épave
  // pour un quart d'heure, le temps que son job vive.
  await context.prisma.entry.update({
    where: { id: epave.id },
    data: { redactionStatus: "pending", redactionError: null },
  });
  await context.queue.publish<RedactJob>(JOB_NAMES.redact, { entryId: epave.id });
  console.log(`  remise en file : ${epave.id}`);
}

console.log(`\n${aRelancer.length} rédaction(s) en file. Suis-les dans les logs du worker.`);
await context.queue.stop();
await context.prisma.$disconnect();
