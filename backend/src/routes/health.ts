import type { FastifyInstance } from "fastify";
import type { AppContext } from "../context.js";

/**
 * Readiness réelle : on interroge la base et la file, on ne se contente pas de
 * répondre 200 parce que le process est vivant.
 *
 * Et on vérifie que la base **a le schéma de ce code** : c'est ce contrôle que
 * Railway attend avant de basculer le trafic sur un déploiement. Un code parti
 * sans sa migration échoue donc ici, au lieu de rendre 500 à l'app — voir
 * `lib/schemaGuard.ts`.
 */
export function registerHealthRoutes(app: FastifyInstance, context: AppContext): void {
  app.get("/health", async (request, reply) => {
    const [database, queue, pendingMigrations] = await Promise.all([
      context.prisma
        .$queryRaw`SELECT 1`.then(() => true)
        .catch(() => false),
      context.queue.healthy().catch(() => false),
      // `null` : la base ne répond pas, et `database` le dit déjà.
      context.schema.pending().catch(() => null),
    ]);

    const schema = pendingMigrations === null ? null : pendingMigrations.length === 0;
    const healthy = database && queue && schema === true;

    if (pendingMigrations?.length) {
      request.log.error(
        { pendingMigrations },
        "Schéma en retard sur le code : `prisma migrate deploy` n'a pas tourné avant ce déploiement.",
      );
    }

    return reply.code(healthy ? 200 : 503).send({
      status: healthy ? "ok" : "degraded",
      checks: {
        database: database ? "ok" : "down",
        queue: queue ? "ok" : "down",
        schema: schema === null ? "unknown" : schema ? "ok" : "behind",
      },
      ...(pendingMigrations?.length ? { pendingMigrations } : {}),
      // Indique si le pipeline appelle vraiment OpenAI/APITemplate ou tourne
      // sur les implémentations simulées — première question qu'on se pose en
      // débuggant un carnet vide.
      pipelineMode: context.env.live ? "live" : "fake",
    });
  });
}
