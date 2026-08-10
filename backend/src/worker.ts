import { createContext } from "./context.js";
import { loadEnv } from "./env.js";
import { registerJobs } from "./jobs/index.js";

/**
 * Process worker : consomme la file sans exposer d'API. À déployer séparément
 * en production pour que la transcription d'un vocal long ne bloque jamais une
 * requête HTTP.
 */
async function main(): Promise<void> {
  const env = loadEnv();
  const context = createContext(env);

  registerJobs(context);
  await context.queue.start();

  context.logger.info(
    { pipelineMode: env.live ? "live" : "fake" },
    "Worker MemoBook démarré",
  );

  const shutdown = async (signal: string): Promise<void> => {
    context.logger.info({ signal }, "Arrêt du worker");
    await context.queue.stop();
    await context.prisma.$disconnect();
    process.exit(0);
  };

  process.on("SIGINT", () => void shutdown("SIGINT"));
  process.on("SIGTERM", () => void shutdown("SIGTERM"));
}

main().catch((error: unknown) => {
  console.error(error);
  process.exit(1);
});
