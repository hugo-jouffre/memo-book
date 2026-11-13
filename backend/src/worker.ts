import { createContext, type AppContext } from "./context.js";
import { loadEnv } from "./env.js";
import { registerJobs } from "./jobs/index.js";
import { photosDiagnostic } from "./services/renderDiagnostics.js";

/**
 * Process worker : consomme la file sans exposer d'API. À déployer séparément
 * en production pour que la transcription d'un vocal long ne bloque jamais une
 * requête HTTP.
 */
async function main(): Promise<void> {
  const env = loadEnv();
  const context = createContext(env);

  registerJobs(context);
  await waitForSchema(context);
  await context.queue.start();

  context.logger.info(
    { pipelineMode: env.live ? "live" : "fake" },
    "Worker MemoBook démarré",
  );

  // C'est **ce** service qui compose les carnets, et il n'a ni domaine ni
  // contrôle de santé : son diagnostic ne peut s'annoncer que là, une fois,
  // au démarrage. Un carnet sans photos se lit alors dans les logs avant de
  // se lire sur le carnet. Voir `services/renderDiagnostics.ts`.
  const photos = photosDiagnostic(env);
  if (photos.problems.length > 0) {
    context.logger.error(photos, "Les carnets composés par ce worker sortiront sans photos");
  } else {
    context.logger.info(photos, "Rendu des carnets : moteur et adresse des photos");
  }

  const shutdown = async (signal: string): Promise<void> => {
    context.logger.info({ signal }, "Arrêt du worker");
    await context.queue.stop();
    await context.prisma.$disconnect();
    process.exit(0);
  };

  process.on("SIGINT", () => void shutdown("SIGINT"));
  process.on("SIGTERM", () => void shutdown("SIGTERM"));
}

/**
 * Le worker ne prend aucun job tant que la base n'a pas le schéma de son code.
 *
 * L'API, elle, a un contrôle de santé : un déploiement parti sans sa migration
 * échoue, et l'ancienne version reste. Le worker n'en a pas — Railway le met en
 * ligne dès que le process tourne. Sans cette attente, il aurait pris les
 * transcriptions et les rédactions une à une pour les faire échouer sur une
 * colonne absente. Les jobs attendent dans la file, et repartent tout seuls dès
 * la migration appliquée. Voir `lib/schemaGuard.ts`.
 */
async function waitForSchema(context: AppContext): Promise<void> {
  for (;;) {
    const pending = await context.schema.pending().catch(() => null);
    if (pending !== null && pending.length === 0) return;

    if (pending === null) {
      context.logger.warn("Base injoignable : le worker attend pour vérifier son schéma.");
    } else {
      context.logger.error(
        { pendingMigrations: pending },
        "Schéma en retard sur le code : le worker attend `prisma migrate deploy` avant de prendre un job.",
      );
    }
    await new Promise((resume) => setTimeout(resume, 30_000));
  }
}

main().catch((error: unknown) => {
  console.error(error);
  process.exit(1);
});
