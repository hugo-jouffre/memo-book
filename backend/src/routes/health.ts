import type { FastifyInstance } from "fastify";
import type { AppContext } from "../context.js";

/**
 * Readiness réelle : on interroge la base et la file, on ne se contente pas de
 * répondre 200 parce que le process est vivant.
 */
export function registerHealthRoutes(app: FastifyInstance, context: AppContext): void {
  app.get("/health", async (_request, reply) => {
    const [database, queue] = await Promise.all([
      context.prisma
        .$queryRaw`SELECT 1`.then(() => true)
        .catch(() => false),
      context.queue.healthy().catch(() => false),
    ]);

    const healthy = database && queue;

    return reply.code(healthy ? 200 : 503).send({
      status: healthy ? "ok" : "degraded",
      checks: {
        database: database ? "ok" : "down",
        queue: queue ? "ok" : "down",
      },
      // Indique si le pipeline appelle vraiment OpenAI/APITemplate ou tourne
      // sur les implémentations simulées — première question qu'on se pose en
      // débuggant un carnet vide.
      pipelineMode: context.env.live ? "live" : "fake",
    });
  });
}
