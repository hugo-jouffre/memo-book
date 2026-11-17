#!/usr/bin/env tsx
/**
 * Les épaves de la rédaction : annoncées « en attente » ou « en cours », sans
 * aucun job derrière elles. Ce script les compte, et les remet en file quand
 * on le lui demande.
 *
 *   railway run --service worker -- npm run redaction:epaves
 *   railway run --service worker -- npm run redaction:epaves -- --relancer --max 5
 *   railway run --service worker -- npm run redaction:epaves -- --relancer --entree <id>
 *   railway run --service worker -- npm run redaction:epaves -- --echecs
 *
 * D'où elles viennent : pg-boss fait expirer un job que personne n'a dépilé,
 * puis l'archive ; l'entrée, elle, reste à `pending` pour toujours. Le
 * 04/11/2026 il y en avait trente et une, la plus ancienne du 29 octobre — et
 * avec elles, **aucun carnet ne pouvait se composer** : `jobs/structure.ts`
 * attend les rédactions en cours trois minutes avant de renoncer. La route de
 * relance les ignorait ; elle les reprend depuis (`routes/entries.ts`).
 *
 * **`--echecs` ajoute les rédactions `failed`** (Hugo, 16/11/2026). Une épave
 * est une entrée que personne n'a dépilée ; un échec est une entrée dont le
 * job a tourné et s'est fait refuser. Les deux se réparent de la même façon,
 * mais seules les premières étaient ramassées — et le jour où le compte
 * Anthropic s'est vidé, les huit rédactions du carnet de Hugo sont passées à
 * `failed`, hors de portée du script.
 *
 * ⚠️ **Toutes ne méritent pas une relance** : un « souvenir trop long pour une
 * seule étape » échouera de nouveau. Le script affiche donc l'erreur de chaque
 * échec avant de relancer — on relit, puis on décide, `--max` à la main.
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
const avecEchecs = process.argv.includes("--echecs");

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
      select: { id: true, memoId: true, redactionStatus: true, updatedAt: true, redactionError: true },
    })
  : await context.prisma.entry.findMany({
      where: {
        kind: { not: "photo" },
        // Un échec n'a pas d'âge à attendre : son job a déjà tourné.
        OR: [
          { redactionStatus: { in: ["pending", "processing"] }, updatedAt: { lt: strandedBefore() } },
          ...(avecEchecs ? [{ redactionStatus: "failed" as const }] : []),
        ],
      },
      select: { id: true, memoId: true, redactionStatus: true, updatedAt: true, redactionError: true },
      orderBy: { updatedAt: "asc" },
    });

if (entree && epaves.length === 0) {
  console.error(`Aucune entrée ${entree} à rédiger (inexistante, ou c'est une photo).`);
  await context.prisma.$disconnect();
  process.exit(1);
}

const carnets = new Set(epaves.map((epave) => epave.memoId)).size;
console.log(`${epaves.length} épave(s), sur ${carnets} carnet(s).`);
// Une épave ne dit rien de plus que sa date : dix suffisent à en prendre la
// mesure. Un échec, lui, porte son erreur — et c'est elle qu'on vient lire
// avant de payer la relance. On les affiche donc tous, et en entier : tronquée
// trop court, « Your credit balance is too low to access the Anth » ne dit
// plus de quoi il s'agit.
let attentesMasquees = 0;
let attentesAffichees = 0;
for (const epave of epaves) {
  if (epave.redactionStatus !== "failed") {
    if (attentesAffichees >= 10) {
      attentesMasquees += 1;
      continue;
    }
    attentesAffichees += 1;
  }
  const pourquoi = epave.redactionError ? `\n      ${epave.redactionError.replace(/\s+/g, " ").slice(0, 240)}` : "";
  console.log(`  ${epave.updatedAt.toISOString()}  ${epave.redactionStatus.padEnd(10)} ${epave.id}${pourquoi}`);
}
if (attentesMasquees > 0) {
  console.log(`  … et ${attentesMasquees} épave(s) de plus, sans erreur à lire.`);
}

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
