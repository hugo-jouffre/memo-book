import { createContext } from "../src/context.js";
import { loadEnv } from "../src/env.js";

const context = createContext(loadEnv());
for (let i = 1; i <= 80; i += 1) {
  const rows = await context.prisma.entry.findMany({
    where: { kind: { not: "photo" }, memo: { accessCode: "UNBV73" }, redactionStatus: { not: "ready" } },
    select: { id: true, redactionStatus: true, redactionError: true, transcript: true },
  });
  const enCours = rows.filter((r) => r.redactionStatus === "pending" || r.redactionStatus === "processing");
  const echecs = rows.filter((r) => r.redactionStatus === "failed");
  console.log(`[${i}] en cours : ${enCours.length}  échecs : ${echecs.length}`);
  if (enCours.length === 0) {
    console.log("\nTERMINÉ");
    for (const e of echecs) {
      console.log(`  ÉCHEC ${e.id} (${(e.transcript ?? "").trim().length} car.) — ${(e.redactionError ?? "").replace(/\s+/g, " ").slice(0, 200)}`);
    }
    const ok = await context.prisma.entry.count({
      where: { kind: { not: "photo" }, memo: { accessCode: "UNBV73" }, redactionStatus: "ready" },
    });
    console.log(`  rédigés sur ce carnet : ${ok}`);
    break;
  }
  await new Promise((r) => setTimeout(r, 20_000));
}
await context.prisma.$disconnect();
