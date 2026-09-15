import { buildApp } from "./app.js";
import { createContext, type AppContext } from "./context.js";
import { loadEnv } from "./env.js";
import { startQueueWhenPossible } from "./jobs/queue.js";

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
 *
 * **Le port s'ouvre avant tout le reste.** Ce qui vient après — la file de
 * travaux — se branche quand il peut, et son absence se lit dans `/health` au
 * lieu d'éteindre le serveur. Une API qui ne peut pas transcrire sait quand
 * même rendre un accueil.
 */
async function main(): Promise<void> {
  const env = loadEnv();
  const isDevelopment = env.NODE_ENV === "development";
  const context = createContext(env);
  const app = await buildApp(context);

  await listen(app, env.PORT, isDevelopment);

  context.logger.info(
    { port: env.PORT, pipelineMode: env.live ? "live" : "fake" },
    "MemoBook API démarrée",
  );

  const queueStart = startQueueWhenPossible(context.queue, context.logger);

  keepAliveInDevelopment(context, isDevelopment);

  const shutdown = async (signal: string): Promise<void> => {
    context.logger.info({ signal }, "Arrêt en cours");
    queueStart.cancel();
    await app.close();
    await context.queue.stop();
    await context.prisma.$disconnect();
    process.exit(0);
  };

  process.on("SIGINT", () => void shutdown("SIGINT"));
  process.on("SIGTERM", () => void shutdown("SIGTERM"));
}

/**
 * Le dernier filet : en développement, une erreur qu'aucun `try` n'a attrapée
 * est **journalisée, et le serveur reste debout**.
 *
 * Node termine le process sur une promesse rejetée sans écouteur, et c'est la
 * bonne règle en production — l'état d'après est inconnu, et l'orchestrateur
 * redémarre. En développement, personne ne redémarre : `tsx watch` attend une
 * modification de fichier, et le port reste fermé sans que rien ne le dise. Un
 * serveur bancal qu'on voit vaut mieux qu'un serveur mort qu'on ne voit pas.
 */
function keepAliveInDevelopment(context: AppContext, isDevelopment: boolean): void {
  if (!isDevelopment) return;

  process.on("unhandledRejection", (reason) => {
    context.logger.error({ err: reason }, "Promesse rejetée sans écouteur — serveur maintenu.");
  });
  process.on("uncaughtException", (error) => {
    context.logger.error({ err: error }, "Exception non attrapée — serveur maintenu.");
  });
}

main().catch((error: unknown) => {
  console.error(error);
  // Ce qui reste ici ne se retente pas : une variable d'environnement
  // manquante, une route mal déclarée, un port tenu par un autre programme.
  // Les pannes qui passent — base, file, réseau — n'y arrivent plus.
  process.exit(1);
});
