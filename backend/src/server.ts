import { buildApp } from "./app.js";
import { createContext } from "./context.js";
import { loadEnv } from "./env.js";

/**
 * Ouvre le port, en laissant au process précédent le temps de lâcher le sien.
 *
 * `tsx watch` redémarre en envoyant un `SIGTERM` **sans attendre la sortie** :
 * le nouveau process appelle donc `listen` pendant que l'ancien est encore en
 * train de fermer ses connexions. Une fois sur quelques-unes, il tombait sur un
 * `EADDRINUSE`, remontait jusqu'à `main().catch` et **tuait le serveur de
 * développement** — silencieusement, puisque la sortie part dans un fichier de
 * log. On ne s'en apercevait qu'à l'écran d'entrée de l'app, sur un
 * « Connexion impossible » qui accusait le réseau.
 *
 * On réessaie donc, mais **en développement seulement** : en production, un
 * port déjà pris veut dire qu'un autre programme l'occupe, et l'attente
 * masquerait une vraie erreur de déploiement.
 */
async function listen(
  app: Awaited<ReturnType<typeof buildApp>>,
  port: number,
  isDevelopment: boolean,
): Promise<void> {
  const deadline = Date.now() + (isDevelopment ? 5_000 : 0);

  for (;;) {
    try {
      await app.listen({ port, host: "0.0.0.0" });
      return;
    } catch (error) {
      const isPortTaken =
        error instanceof Error && "code" in error && error.code === "EADDRINUSE";

      if (!isPortTaken || Date.now() >= deadline) throw error;

      app.log.warn({ port }, "Port encore occupé par le process précédent, nouvel essai");
      await new Promise((resume) => setTimeout(resume, 250));
    }
  }
}

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
  await listen(app, env.PORT, env.NODE_ENV === "development");

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
