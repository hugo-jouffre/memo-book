/**
 * **Regarder un vrai voyage, sans y toucher** (Hugo, 16/11/2026).
 *
 * Une quinzaine de retours du batch du Japon décrivent des défauts du contenu
 * produit par l'IA — une journée vide, un lieu faux, des souvenirs dans le
 * désordre. Aucun bac à sable ne les reproduit : il faut le carnet réel, et il
 * vit dans la base de production.
 *
 * Ce script est **en lecture seule**. Il n'écrit rien, ne corrige rien, et
 * n'appelle aucun modèle. Il se lance avec l'adresse de la base en variable
 * d'environnement, pour que l'identifiant reste chez celui qui le lance :
 *
 * ```bash
 * DATABASE_URL='postgresql://…' npx tsx scripts/inspecter-un-voyage.ts JHKFDA
 * ```
 *
 * Ce qu'il montre, et pourquoi :
 *
 * - **les étapes**, avec leur lieu et leurs dates — « parfois le lieu en haut
 *   d'une étape est complètement faux, Shanghai alors qu'on est à Tokyo », et
 *   « parfois des en-têtes ont la date mais pas le lieu » ;
 * - **les trous de journée** — « le jour 6 est vide alors que le chat m'a dit
 *   que tout avait été renseigné » ;
 * - **les souvenirs dans l'ordre où la base les porte**, avec la date de
 *   capture et celle de création — « les transcriptions ne sont pas toujours
 *   dans l'ordre chronologique » ;
 * - **ce qui a échoué en silence** : rédaction en attente ou en erreur.
 *
 * ⚠️ Il affiche du **récit personnel**. À lancer sur son propre voyage, et à
 * ne pas recopier n'importe où.
 */
import { PrismaClient } from "@prisma/client";

const JOUR_MS = 24 * 60 * 60 * 1000;

/** Le jour calendaire d'une date, en UTC : « 2026-11-05 ». */
function jourDe(date: Date): string {
  return date.toISOString().slice(0, 10);
}

function court(texte: string | null | undefined, taille = 60): string {
  if (!texte) return "—";
  const propre = texte.replace(/\s+/g, " ").trim();
  return propre.length > taille ? `${propre.slice(0, taille - 1)}…` : propre;
}

async function main(): Promise<void> {
  const code = process.argv[2]?.trim().toUpperCase();
  if (!code) {
    console.error("Usage : DATABASE_URL='…' npx tsx scripts/inspecter-un-voyage.ts <CODE>");
    process.exitCode = 1;
    return;
  }

  const prisma = new PrismaClient();
  try {
    const memo = await prisma.memo.findUnique({
      where: { accessCode: code },
      include: {
        steps: { orderBy: { number: "asc" } },
        entries: { orderBy: { createdAt: "asc" } },
      },
    });

    if (!memo) {
      console.error(`Aucun voyage avec le code ${code} dans cette base.`);
      process.exitCode = 1;
      return;
    }

    console.log(`\n=== ${memo.title ?? "(sans titre)"} — ${code} ===`);
    console.log(`du ${memo.startDate ? jourDe(memo.startDate) : "?"} au ${memo.endDate ? jourDe(memo.endDate) : "?"}`);
    console.log(`${memo.steps.length} étape(s), ${memo.entries.length} souvenir(s)\n`);

    console.log("--- Les étapes ---");
    for (const step of memo.steps) {
      const lieu = step.placeName ?? "⚠️ SANS LIEU";
      const dates = step.startDate ? jourDe(step.startDate) : "sans date";
      console.log(`  ${String(step.number).padStart(2)} · ${lieu.padEnd(24)} ${dates}  ${step.validatedAt ? "✓" : ""}`);
    }

    console.log("\n--- Les souvenirs, dans l'ordre de la base ---");
    let precedent: Date | null = null;
    for (const entry of memo.entries) {
      const capture = entry.capturedAt ?? entry.createdAt;
      // ⚠️ Le signe d'un désordre : une capture antérieure à la précédente.
      const recul = precedent && capture < precedent ? " ⚠️ RECULE" : "";
      precedent = capture;
      const etat = entry.redactionStatus === "ready" ? "" : ` [rédaction ${entry.redactionStatus}]`;
      const erreur = entry.redactionError ? ` ⚠️ ${court(entry.redactionError, 40)}` : "";
      console.log(
        `  ${jourDe(capture)} ${entry.kind.padEnd(6)} ${court(entry.suggestedTitle, 34).padEnd(34)}` +
          ` ${court(entry.placeLabel, 16).padEnd(16)}${etat}${erreur}${recul}`,
      );
    }

    // Les journées du voyage qu'aucun souvenir ne touche.
    if (memo.startDate && memo.endDate) {
      const vus = new Set(memo.entries.map((e) => jourDe(e.capturedAt ?? e.createdAt)));
      const vides: string[] = [];
      for (let t = memo.startDate.getTime(); t <= memo.endDate.getTime(); t += JOUR_MS) {
        const jour = jourDe(new Date(t));
        if (!vus.has(jour)) vides.push(jour);
      }
      console.log(`\n--- Les journées sans aucun souvenir : ${vides.length} ---`);
      if (vides.length) console.log(`  ${vides.join("  ")}`);
    }

    const bancales = memo.entries.filter((e) => e.redactionStatus !== "ready");
    const sansLieu = memo.steps.filter((s) => !s.placeName);
    console.log("\n--- En résumé ---");
    console.log(`  rédactions pas prêtes : ${bancales.length}`);
    console.log(`  étapes sans lieu      : ${sansLieu.length}`);
  } finally {
    await prisma.$disconnect();
  }
}

await main();
