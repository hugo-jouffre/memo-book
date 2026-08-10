import { buildApp } from "./app.js";
import { createContext } from "./context.js";
import { loadEnv } from "./env.js";

/**
 * Process API. En développement il porte aussi les workers, pour n'avoir qu'une
 * commande à lancer ; en production, `npm run worker` les sort dans un process
 * séparé (voir src/worker.ts).
 */
async function main(): Promise<void> {
  const env = loadEnv();
  const context = createContext(env);
  const app = await buildApp(context);

  await context.queue.start();
  await app.listen({ port: env.PORT, host: "0.0.0.0" });

  context.logger.info(
    { port: env.PORT, pipelineMode: env.live ? "live" : "fake" },
    "MemoBook API démarrée",
  );

  const shutdown = async (signal: string): Promise<void> => {
    context.logger.info({ signal }, "Arrêt en cours");
    await app.close();
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
